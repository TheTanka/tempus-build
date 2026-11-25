# tempus-build

Automatic, signed builds of [Tempus](https://github.com/eddyizm/tempus), the open-source Subsonic music client for Android, with a custom launcher icon.

A GitHub Actions workflow checks upstream every 6 hours. When eddyizm publishes a new stable release, it builds the **degoogled** flavor (no Google services, the same variant as on F-Droid) as a **release** build, signs it, and publishes it here as `vX.Y.Z-tanka`.

<p align="center"><img src="https://github.com/TheTanka/tempus-build/releases/latest/download/icon-preview.png" width="128" alt="Launcher icon"></p>

## What is different from upstream

| | Upstream degoogled (F-Droid) | This repo |
|---|---|---|
| App code | Tempus | Unchanged, built from the upstream release tag |
| Package name | `com.eddyizm.degoogled.tempus` | `com.eddyizm.degoogled.tempus.tanka` |
| App version | e.g. `4.32.0` | e.g. `4.32.0-tanka`, rebuilds `4.32.0-tanka.2`, … (same `versionCode` as upstream) |
| Logo | Tempus logo | Custom logo (`logo.svg`) on black: launcher icon (incl. Android 13+ themed icon), splash screen, in-app logo (toolbar, side drawer, login), home-screen widget |
| Signing key | F-Droid / upstream | My own key |

Because the package name differs, it installs **next to** an existing Tempus install instead of replacing it. The two installs do not share settings or data.

## Install

### With Obtainium (automatic updates)

1. In [Obtainium](https://github.com/ImranR98/Obtainium), choose Add App and use this URL: `https://github.com/TheTanka/tempus-build`
2. Set **Filter APKs by regular expression** to `universal`.
3. Install. New upstream releases arrive here within about 6 hours plus build time.

The app version equals the release tag without the `v` (e.g. `4.32.0-tanka.2`), so rebuilds of the same upstream version arrive as normal updates. Leave **Trim version string** empty; if Obtainium shows a version-detection warning, set it to `[0-9].*`.

### Manually

Download an APK from [Releases](https://github.com/TheTanka/tempus-build/releases):

| File | For |
|---|---|
| `tempus-degoogled-<version>-universal.apk` | Any device (all CPU architectures in one APK) |

If upstream ever enables per-architecture builds, they appear as `tempus-degoogled-<version>-<abi>.apk` (e.g. `arm64-v8a`) next to the universal one.

### Verify

Each release lists the signing certificate's SHA-256 in its notes, and `SHA256SUMS` covers all APKs. To check a download:

```
sha256sum -c SHA256SUMS --ignore-missing
apksigner verify --print-certs tempus-degoogled-*-universal.apk
```

The certificate must be the same for every release. Android refuses updates signed with a different key anyway.

## Source and license

Tempus is licensed under the [GPL-3.0](https://github.com/eddyizm/tempus/blob/main/LICENSE). The complete source of every APK here is the upstream release tag it names, plus the changes made by this repo's build:

- `applicationIdSuffix` and `versionNameSuffix` added to the degoogled flavor in `app/build.gradle`
- Icon drawables in `app/src/degoogled/res/drawable/` replaced by the output of `scripts/svg2icons.py`

Bugs in the app itself belong [upstream](https://github.com/eddyizm/tempus/issues). Issues here only for build or icon problems.

## Build it yourself

### Your own automated builds

Fork or copy this repo, swap `logo.svg`, and follow [GUIDE.md](GUIDE.md). It covers:

- creating a signing key without exposing personal data
- storing and backing up the key in KeePassXC
- GitHub secrets, the first run, and Obtainium setup

To use your own suffix instead of `tanka`, change `APP_ID_SUFFIX` in the `Dockerfile` and `TAG_SUFFIX` in `.github/workflows/build.yml`.

### Local build

Requires Docker with BuildKit (Docker 23+) and a keystore.

```
KEYSTORE=~/keys/tempus.p12 KS_PASS_FILE=~/keys/tempus.pass ./build.sh
```

Output goes to `./out/`: the signed APKs, `SHA256SUMS`, `signing-cert.txt`, `icon-preview.png` (launcher) and `icon-preview-inapp.png` (in-app badge and widget tile on light and dark backgrounds).

| Environment variable | Required | Description |
|---|---|---|
| `KEYSTORE` | yes | Path to keystore (PKCS12 or JKS) |
| `KS_PASS_FILE` / `KS_PASS` | yes | Keystore password (file or env) |
| `KEY_PASS_FILE` / `KEY_PASS` | no | Key password, only if it differs from the keystore password |
| `KEY_ALIAS` | no | Only needed if the keystore holds several keys |
| `TEMPUS_TAG` | no | Upstream tag, e.g. `v4.32.0` (default: latest stable) |
| `VERSION_NAME_SUFFIX` | no | Appended to the app version (default: `-tanka`) |

Extra arguments to `build.sh` are passed on to `docker build`:

| Build arg | Default | Description |
|---|---|---|
| `ICON_BG` | `#000000` | Icon background colour |
| `ICON_RADIUS` | `24` | Logo size in dp from center (safe zone max is 33) |
| `APP_ID_SUFFIX` | `.tanka` | applicationId suffix |
| `GRADLE_XMX` | `4g` | Gradle JVM heap |
| `CMDLINE_TOOLS_VERSION` | `13114758` | Android cmdline-tools build number |

Example:

```
TEMPUS_TAG=v4.32.0 KEYSTORE=~/keys/tempus.p12 KS_PASS_FILE=~/keys/tempus.pass \
  ./build.sh --build-arg ICON_RADIUS=28
```

### Logo requirements

- Solid fills only. Gradients, embedded images or text make the build fail on purpose.
- Hidden layers (`display:none`, common in Inkscape) are ignored.
- Logo only; the background colour comes from `ICON_BG`.

Preview without Docker (needs [uv](https://docs.astral.sh/uv/) and `rsvg-convert`):

```
./scripts/svg2icons.py logo.svg /tmp/icons
rsvg-convert -w 512 /tmp/icons/preview.svg -o /tmp/icons/preview.png
rsvg-convert -w 1280 /tmp/icons/preview-inapp.svg -o /tmp/icons/preview-inapp.png
```

## How it works

| Part | Purpose |
|---|---|
| `.github/workflows/build.yml` | Every 6 h: compare the newest upstream stable tag with this repo's releases; if new, build, sign and publish. Manual runs can force a rebuild (`-tanka.2`, …). |
| `scripts/latest-tag.sh` | Newest stable upstream tag via `git ls-remote` (no API rate limits) |
| `Dockerfile` stage `source` | Clones the upstream tag |
| `Dockerfile` stage `icon` | `scripts/svg2icons.py` (picosvg) turns the SVG into VectorDrawables: launcher layers, splash, a round badge for the toolbar/drawer/login, and a rounded tile for the widget |
| `Dockerfile` stages `sdk` / `build` | Temurin 21 + Android SDK, patches the applicationId suffix, copies the icons, runs `assembleDegoogledRelease`, verifies the package name |
| `Dockerfile` stage `sign` | `scripts/sign.sh`: zipalign (16 KB pages), apksigner, verify. Keystore and passwords come in as BuildKit secrets and never end up in image layers. |

The build stops with an error if upstream changes the `applicationId` line in `app/build.gradle`, instead of quietly building the wrong package.

## Notes

- The in-app logo is a black round badge (and a rounded tile in the widget), so the white logo stays visible on the light theme and the daytime widget.
- The themed (monochrome) icon uses every shape of the logo in white.
- Locally, the Gradle cache persists in a BuildKit cache mount, so rebuilds are fast (`docker builder prune` clears it). On GitHub Actions every build starts cold.