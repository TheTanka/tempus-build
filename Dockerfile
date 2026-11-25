# check=skip=SecretsUsedInArgOrEnv
# (KEY_ALIAS is only a key name, not a secret; passwords and keystore use --secret)
#
# Oneshot build of Tempus (degoogled flavor, release) with a custom icon,
# signed with your own key. Use ./build.sh, or see it for the raw command.

ARG JDK_IMAGE=eclipse-temurin:21-jdk-noble
ARG UV_IMAGE=ghcr.io/astral-sh/uv:python3.13-bookworm-slim

# ---------------------------------------------------------------- source
FROM alpine:3 AS source
RUN apk add --no-cache git
# Upstream tag to build, e.g. v4.32.0. build.sh resolves the latest one
# (scripts/latest-tag.sh) and passes it in, so the cache breaks per release.
ARG TEMPUS_TAG
RUN set -eu; \
    if [ -z "${TEMPUS_TAG:-}" ]; then \
        echo "TEMPUS_TAG build-arg is required (build.sh sets it)" >&2; exit 1; \
    fi; \
    echo "Building Tempus $TEMPUS_TAG"; \
    git clone --depth 1 --branch "$TEMPUS_TAG" https://github.com/eddyizm/tempus.git /src; \
    echo "$TEMPUS_TAG" > /src/.tempus-tag

# ---------------------------------------------------------------- icon
FROM ${UV_IMAGE} AS icon
RUN apt-get update \
 && apt-get install -y --no-install-recommends librsvg2-bin \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /work
COPY scripts/svg2icons.py ./
COPY logo.svg ./
ARG ICON_BG=#000000
ARG ICON_RADIUS=24
RUN --mount=type=cache,target=/root/.cache/uv \
    uv run --script svg2icons.py logo.svg out --bg "${ICON_BG}" --radius "${ICON_RADIUS}" \
 && rsvg-convert -w 512 -h 512 out/preview.svg -o out/icon-preview.png \
 && rsvg-convert -w 1280 out/preview-inapp.svg -o out/icon-preview-inapp.png

# ---------------------------------------------------------------- sdk
FROM ${JDK_IMAGE} AS sdk
ARG CMDLINE_TOOLS_VERSION=13114758
ENV ANDROID_HOME=/opt/android-sdk
ENV PATH=${ANDROID_HOME}/cmdline-tools/latest/bin:${PATH}
RUN apt-get update \
 && apt-get install -y --no-install-recommends unzip curl git \
 && rm -rf /var/lib/apt/lists/*
RUN set -eu; \
    curl -fsSL -o /tmp/clt.zip \
        "https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_VERSION}_latest.zip"; \
    mkdir -p "$ANDROID_HOME/cmdline-tools"; \
    unzip -q /tmp/clt.zip -d "$ANDROID_HOME/cmdline-tools"; \
    mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"; \
    rm /tmp/clt.zip; \
    yes | sdkmanager --licenses > /dev/null

# ---------------------------------------------------------------- build
FROM sdk AS build
WORKDIR /src
COPY --from=source /src/ /src/

# Platform and build-tools are NOT installed here: the Android Gradle plugin
# downloads exactly what compileSdk/buildToolsVersion need (licenses are
# accepted in the sdk stage). sdkmanager package names change between Android
# versions (e.g. android-37 vs android-37.0), AGP always knows the right one.
# Only remember the build-tools version for zipalign/apksigner later.
RUN set -eu; \
    bt="$(sed -n "s/^ *buildToolsVersion *=* *['\"]\([0-9.]*\)['\"].*/\1/p" app/build.gradle | head -n1)"; \
    if [ -z "$bt" ]; then \
        echo "Could not read buildToolsVersion from app/build.gradle" >&2; exit 1; \
    fi; \
    echo "buildTools=$bt"; \
    echo "$bt" > /opt/build-tools-version

# Own applicationId so it installs next to the F-Droid build and updates never clash.
ARG APP_ID_SUFFIX=.tanka
RUN set -eu; \
    anchor='applicationId = "com.eddyizm.degoogled.tempus"'; \
    if ! grep -qF "$anchor" app/build.gradle; then \
        echo "Upstream changed the degoogled applicationId line, patch needs updating" >&2; exit 1; \
    fi; \
    sed -i "s|^\( *\)$anchor|&\n\1applicationIdSuffix = \"${APP_ID_SUFFIX}\"|" app/build.gradle; \
    grep -n -A1 -F "$anchor" app/build.gradle

# Custom icon: launcher (foreground, background, monochrome), splash,
# in-app badge (toolbar, drawer, login) and widget tile.
COPY --from=icon /work/out/res/ app/src/degoogled/res/

# Retries cover transient repository hiccups (plugin portal, Maven Central,
# Google Maven), which Gradle reports as "plugin/artifact not found".
ARG GRADLE_XMX=4g
RUN --mount=type=cache,target=/root/.gradle \
    set -eu; \
    for attempt in 1 2 3; do \
        if ./gradlew --no-daemon --console=plain \
            -Dorg.gradle.jvmargs="-Xmx${GRADLE_XMX}" \
            assembleDegoogledRelease; then \
            exit 0; \
        fi; \
        echo "Gradle attempt $attempt of 3 failed" >&2; \
        if [ "$attempt" -lt 3 ]; then sleep $((attempt * 30)); fi; \
    done; \
    exit 1

# Fail early if the package name is not what we expect.
RUN set -eu; \
    bt="$ANDROID_HOME/build-tools/$(cat /opt/build-tools-version)"; \
    if [ ! -x "$bt/apksigner" ] || [ ! -x "$bt/zipalign" ] || [ ! -x "$bt/aapt2" ]; then \
        echo "build-tools missing in $bt (Gradle did not install them)" >&2; \
        ls "$ANDROID_HOME/build-tools" >&2 || true; \
        exit 1; \
    fi; \
    out=app/build/outputs/apk/degoogled/release; \
    echo "Gradle output:"; ls -l "$out"; \
    apk="$(find "$out" -maxdepth 1 -name '*.apk' | sort | head -n1)"; \
    if [ -z "$apk" ]; then echo "No APK in $out" >&2; exit 1; fi; \
    expected="com.eddyizm.degoogled.tempus${APP_ID_SUFFIX}"; \
    "$bt/aapt2" dump badging "$apk" | grep -q "package: name='$expected'" \
        || { echo "Package name mismatch, expected $expected" >&2; exit 1; }; \
    echo "Package OK: $expected"

# ---------------------------------------------------------------- sign
FROM build AS sign
COPY scripts/sign.sh /usr/local/bin/sign.sh
ARG KEY_ALIAS=
RUN --mount=type=secret,id=keystore,required=true \
    --mount=type=secret,id=ks_pass,required=true \
    --mount=type=secret,id=key_pass \
    KEY_ALIAS="${KEY_ALIAS}" sh /usr/local/bin/sign.sh /out

# ---------------------------------------------------------------- export
FROM scratch AS export
COPY --from=sign /out/ /
COPY --from=icon /work/out/icon-preview.png /work/out/icon-preview-inapp.png /