# tempus-build

Oneshot Docker build of [Tempus](https://github.com/eddyizm/tempus) (degoogled flavor, release build) with a custom launcher icon, signed with your own key.

- Builds the latest stable upstream release (or a pinned tag)
- Optional GitHub Actions automation: new upstream release, then a signed `vX.Y.Z-tanka` release for Obtainium. See [GUIDE.md](GUIDE.md)
- Converts `logo.svg` into adaptive-icon VectorDrawables (foreground, background, monochrome, splash)
- Installs as `com.eddyizm.degoogled.tempus.tanka`, side by side with the F-Droid build
- Signs with `zipalign` + `apksigner`; the keystore and passwords are passed as BuildKit secrets and never stored in image layers

## Requirements

- Docker with BuildKit (Docker 23+)
- A keystore (PKCS12 or JKS)

## Usage

```
KEYSTORE=~/keys/tempus.p12 KS_PASS_FILE=~/keys/tempus.pass ./build.sh
```

Output in `./out/`:

| File | Description |
|---|---|
| `tempus-degoogled-<version>-universal.apk` | All ABIs, install this if unsure |
| `tempus-degoogled-<version>-<abi>.apk` | Per-ABI builds |
| `SHA256SUMS` | Checksums |
| `signing-cert.txt` | Certificate DN and SHA-256 (public info, for verification) |
| `icon-preview.png` | Launcher icon as rendered (circle mask) |

### Environment variables

| Variable | Required | Description |
|---|---|---|
| `KEYSTORE` | yes | Path to keystore |
| `KS_PASS_FILE` / `KS_PASS` | yes | Keystore password (file or env) |
| `KEY_PASS_FILE` / `KEY_PASS` | no | Key password, only if it differs from the keystore password |
| `KEY_ALIAS` | no | Only needed if the keystore holds several keys |
| `TEMPUS_TAG` | no | Upstream tag, e.g. `v4.32.0` (default: latest stable via `scripts/latest-tag.sh`) |

### Build args

Pass extra arguments to `build.sh`; they go straight to `docker build`.

| Arg | Default | Description |
|---|---|---|
| `ICON_BG` | `#000000` | Icon background colour |
| `ICON_RADIUS` | `30` | Logo size in dp from center (safe zone max is 33) |
| `APP_ID_SUFFIX` | `.tanka` | applicationId suffix |
| `GRADLE_XMX` | `4g` | Gradle JVM heap |
| `CMDLINE_TOOLS_VERSION` | `13114758` | Android cmdline-tools build number |

Example:

```
TEMPUS_TAG=v4.32.0 KEYSTORE=~/keys/tempus.p12 KS_PASS_FILE=~/keys/tempus.pass \
  ./build.sh --build-arg ICON_RADIUS=28
```

## Keystore

Inspect an existing keystore (type and aliases):

```
keytool -list -v -keystore tempus.p12
```

Create a new one. Keep `-dname` minimal, because the certificate subject is public in every APK:

```
keytool -genkeypair -keystore tempus.p12 -storetype PKCS12 \
  -keyalg RSA -keysize 4096 -validity 10000 -alias tanka -dname "CN=tanka"
```

Back it up. Losing it means you can no longer update the installed app without uninstalling it. See [GUIDE.md](GUIDE.md) for safe creation and KeePassXC storage.

## Logo

Replace `logo.svg`. Requirements:

- Solid fills only (no gradients, embedded images or text; the script fails loudly on these)
- Hidden layers (`display:none`, common in Inkscape) are ignored
- Logo only, the background colour comes from `ICON_BG`

Preview without Docker (needs [uv](https://docs.astral.sh/uv/) and `rsvg-convert`):

```
./scripts/svg2icons.py logo.svg /tmp/icons
rsvg-convert -w 512 /tmp/icons/preview.svg -o /tmp/icons/preview.png
```

## How it works

| Stage | Purpose |
|---|---|
| `source` | Clones the upstream tag passed in as `TEMPUS_TAG` |
| `icon` | `scripts/svg2icons.py` (picosvg) turns the SVG into VectorDrawables |
| `sdk` | Temurin 21 + Android cmdline-tools |
| `build` | Installs the SDK versions the release needs, patches the applicationId suffix, copies icons into `app/src/degoogled/res/`, runs `assembleDegoogledRelease`, verifies the package name |
| `sign` | `scripts/sign.sh`: zipalign (16 KB pages) + apksigner + verify |
| `export` | Only the signed APKs, checksums, certificate info and the preview |

The build stops with an error if upstream changes the `applicationId` line in `app/build.gradle`, instead of quietly building the wrong package.

## Notes

- In-app logos (toolbar, login, nav drawer) are not replaced, only the launcher icon and splash screen.
- The monochrome (themed) icon uses every shape of the logo in white.
- Locally, the Gradle cache persists in a BuildKit cache mount, so rebuilds are fast. Run `docker builder prune` to clear it. On GitHub Actions every build starts cold.

## Automation

`.github/workflows/build.yml` checks upstream every 6 hours and publishes signed releases. Setup, secrets, key handling and Obtainium config: [GUIDE.md](GUIDE.md).
