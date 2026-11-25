# tempus-build

Automatic, signed builds of [Tempus](https://github.com/eddyizm/tempus), the open-source Subsonic music client for Android, with a custom launcher icon.

A GitHub Actions workflow checks upstream every 6 hours. When eddyizm publishes a new stable release, it builds the **degoogled** flavor (no Google services, the same variant as on F-Droid) as a **release** build, signs it, and publishes it here as `vX.Y.Z-tanka`.

<p align="center"><img src="https://github.com/TheTanka/tempus-build/releases/latest/download/icon-preview.png" width="128" alt="Launcher icon"></p>

## What is different from upstream

|                              | Upstream degoogled (F-Droid)   | This repo                                                        |
| ---------------------------- | ------------------------------ | ---------------------------------------------------------------- |
| App code                     | Tempus                         | Unchanged, built from the upstream release tag                   |
| Package name                 | `com.eddyizm.degoogled.tempus` | `com.eddyizm.degoogled.tempus.tanka`                             |
| Launcher icon, splash screen | Tempus logo                    | Custom logo (`logo.svg`) on black, incl. Android 13+ themed icon |
| Signing key                  | F-Droid / upstream             | My own key                                                       |

Because the package name differs, it installs **next to** an existing Tempus install instead of replacing it. The two installs do not share settings or data.

## Install

### With Obtainium (automatic updates)

1. In [Obtainium](https://github.com/ImranR98/Obtainium), choose Add App and use this URL: `https://github.com/TheTanka/tempus-build`
2. Set **Filter APKs by regular expression** to `universal`. Use `arm64-v8a` instead for a smaller download on most modern phones.
3. Install. New upstream releases arrive here within about 6 hours plus build time.

If Obtainium shows a version-detection warning, set **Trim version string** to `\d+\.\d+\.\d+`.

### Manually

Download an APK from [Releases](https://github.com/TheTanka/tempus-build/releases):

| File                                                | For                                       |
| --------------------------------------------------- | ----------------------------------------- |
| `tempus-degoogled-<version>-universal.apk`          | Any device, install this if unsure        |
| `tempus-degoogled-<version>-arm64-v8a.apk`          | Most phones from roughly the last 8 years |
| `tempus-degoogled-<version>-armeabi-v7a.apk`        | Older 32-bit phones                       |
| `tempus-degoogled-<version>-x86_64.apk` / `x86.apk` | Emulators, some tablets                   |

### Verify

Each release lists the signing certificate's SHA-256 in its notes, and `SHA256SUMS` covers all APKs. To check a download:

```
sha256sum -c SHA256SUMS --ignore-missing
apksigner verify --print-certs tempus-degoogled-*-universal.apk
```

The certificate must be the same for every release. Android refuses updates signed with a different key anyway.

## Source and license

Tempus is licensed under the [GPL-3.0](https://github.com/eddyizm/tempus/blob/main/LICENSE). The complete source of every APK here is the upstream release tag it names, plus the changes made by this repo's build:

- `applicationIdSuffix` added to the degoogled flavor in `app/build.gradle`
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

Output goes to `./out/`: the signed APKs, `SHA256SUMS`, `signing-cert.txt` and `icon-preview.png`.

| Environment variable         | Required | Description                                                 |
| ---------------------------- | -------- | ----------------------------------------------------------- |
| `KEYSTORE`                   | yes      | Path to keystore (PKCS12 or JKS)                            |
| `KS_PASS_FILE` / `KS_PASS`   | yes      | Keystore password (file or env)                             |
| `KEY_PASS_FILE` / `KEY_PASS` | no       | Key password, only if it differs from the keystore password |
| `KEY_ALIAS`                  | no       | Only needed if the keystore holds several keys              |
| `TEMPUS_TAG`                 | no       | Upstream tag, e.g. `v4.32.0` (default: latest stable)       |

Extra arguments to `build.sh` are passed on to `docker build`:

| Build arg               | Default    | Description                                       |
| ----------------------- | ---------- | ------------------------------------------------- |
| `ICON_BG`               | `#000000`  | Icon background colour                            |
| `ICON_RADIUS`           | `30`       | Logo size in dp from center (safe zone max is 33) |
| `APP_ID_SUFFIX`         | `.tanka`   | applicationId suffix                              |
| `GRADLE_XMX`            | `4g`       | Gradle JVM heap                                   |
| `CMDLINE_TOOLS_VERSION` | `13114758` | Android cmdline-tools build number                |

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
```

## How it works

| Part                                | Purpose                                                                                                                                                        |
| ----------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `.github/workflows/build.yml`       | Every 6 h: compare the newest upstream stable tag with this repo's releases; if new, build, sign and publish. Manual runs can force a rebuild (`-tanka.2`, …). |
| `scripts/latest-tag.sh`             | Newest stable upstream tag via `git ls-remote` (no API rate limits)                                                                                            |
| `Dockerfile` stage `source`         | Clones the upstream tag                                                                                                                                        |
| `Dockerfile` stage `icon`           | `scripts/svg2icons.py` (picosvg) turns the SVG into VectorDrawables: foreground, background, monochrome, splash                                                |
| `Dockerfile` stages `sdk` / `build` | Temurin 21 + Android SDK, patches the applicationId suffix, copies the icons, runs `assembleDegoogledRelease`, verifies the package name                       |
| `Dockerfile` stage `sign`           | `scripts/sign.sh`: zipalign (16 KB pages), apksigner, verify. Keystore and passwords come in as BuildKit secrets and never end up in image layers.             |

The build stops with an error if upstream changes the `applicationId` line in `app/build.gradle`, instead of quietly building the wrong package.

## Notes

- In-app logos (toolbar, login, nav drawer) still show the original Tempus logo; only the launcher icon and splash screen are replaced.
- The themed (monochrome) icon uses every shape of the logo in white.
- Locally, the Gradle cache persists in a BuildKit cache mount, so rebuilds are fast (`docker builder prune` clears it). On GitHub Actions every build starts cold.
