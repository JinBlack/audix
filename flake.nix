{
  description = "Audix — Flutter audiobook player, built end-to-end into an arm64-v8a Android APK with Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { nixpkgs, flake-utils, ... }:
    # The Android toolchain restricts us to Linux hosts.
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          # Android SDK components are unfree and require accepting Google's licence.
          config = {
            allowUnfree = true;
            android_sdk.accept_license = true;
          };
        };
        lib = pkgs.lib;

        pname = "audix";
        version = "1.2.0";

        # ---- Toolchain -------------------------------------------------------
        # The nixpkgs Flutter wrapper already prefetches the Android *engine*
        # artifacts on x86_64-linux, so the engine itself need not be vendored.
        flutter = pkgs.flutter;
        jdk = pkgs.jdk17; # android/app/build.gradle.kts targets Java 17
        gradle = pkgs.gradle_8; # 8.14.4, matches the project's wrapper (8.14)

        # Android SDK: platforms 34-36 (compileSdk 36), build-tools, plus the
        # NDK and CMake that drift/sqlite3_flutter_libs compile native code with.
        androidComposition = pkgs.androidenv.composeAndroidPackages {
          platformVersions = [
            "34"
            "35"
            "36"
          ];
          buildToolsVersions = [
            "35.0.0"
            "36.0.0"
          ];
          includeNDK = true;
          ndkVersions = [ "28.2.13676358" ]; # == flutter.ndkVersion (3.44.2)
          cmakeVersions = [ "3.22.1" ];
          includeEmulator = false;
          includeSystemImages = false;
          includeSources = false;
        };
        androidSdk = androidComposition.androidsdk;
        sdkRoot = "${androidSdk}/libexec/android-sdk";

        buildToolsVersion = "36.0.0";
        targetPlatform = "android-arm64"; # aarch64 / arm64-v8a

        # ---- Sources ---------------------------------------------------------
        # Full project source (git-tracked files only; build/ etc. are ignored).
        src = lib.cleanSource ./.;
        # Minimal source for pub resolution — keeps the pub cache hash stable.
        pubspecSrc = lib.fileset.toSource {
          root = ./.;
          fileset = lib.fileset.unions [
            ./pubspec.yaml
            ./pubspec.lock
          ];
        };

        # ---- Helpers ---------------------------------------------------------
        # Flutter is patched to honour NIX_FLUTTER_PUB_DART; point it at a dart
        # wrapped with the CA bundle so `pub get` can fetch over HTTPS.
        dartWithCerts = pkgs.runCommand "dart-with-certs" { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
          mkdir -p "$out/bin"
          makeWrapper ${flutter.dart}/bin/dart "$out/bin/dart" \
            --add-flags "--root-certs-file=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
        '';

        # Prebuilt arm64 libsqlite3.so. With `source: system` (set in
        # pubspec.yaml) the sqlite3 build hook expects this at runtime instead of
        # downloading it from GitHub; we bundle it via jniLibs (the EOL
        # sqlite3_flutter_libs no longer ships it).
        libsqlite3Android = pkgs.fetchurl {
          name = "libsqlite3.arm64.android.so";
          url = "https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-3.3.3/libsqlite3.arm64.android.so";
          hash = "sha256-nEt1wvd5jZqmMGgRs7QS0aDlS9QfIwR4DapHSLJ6lx4=";
        };

        # drift's web worker + sqlite3 wasm — fetched at build time (versions
        # match drift / sqlite3 in pubspec.lock) so they aren't vendored in git.
        driftWorkerJs = pkgs.fetchurl {
          name = "drift_worker.js";
          url = "https://github.com/simolus3/drift/releases/download/drift-2.34.0/drift_worker.js";
          hash = "sha256-uLn4jN+gWC7trPO1X2Ezt9m+p8jnTU3AGaOA2pl2p6g=";
        };
        sqlite3Wasm = pkgs.fetchurl {
          name = "sqlite3.wasm";
          url = "https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-3.3.3/sqlite3.wasm";
          hash = "sha256-z6tIxru3GFUuwZvE8TZeGRhTEbcuRznMGe9zM3WDBNM=";
        };

        # Rebuild a flat Maven repo from Gradle's downloaded artifacts
        # (caches/modules-2/files-2.1). Unlike vendoring the cache directory,
        # this is deterministic — files-2.1 holds only the upstream artifacts,
        # not Gradle's timestamped binary metadata indices. Some artifacts use a
        # non-standard filename (e.g. sqlite-release.aar); Gradle Module Metadata
        # (.module) records the real repo URL, so we also place each artifact at
        # its declared url.
        reconstructMavenRepo = pkgs.writeShellApplication {
          name = "reconstruct-maven-repo";
          runtimeInputs = [
            pkgs.jq
            pkgs.coreutils
            pkgs.findutils
          ];
          text = ''
            src="$1"; out="$2"; mkdir -p "$out"
            find "$src" -type f | while read -r f; do
              rel="''${f#"$src"/}"
              g="$(echo "$rel" | cut -d/ -f1)"; a="$(echo "$rel" | cut -d/ -f2)"
              v="$(echo "$rel" | cut -d/ -f3)"; fn="$(echo "$rel" | cut -d/ -f5)"
              d="$out/''${g//.//}/$a/$v"; mkdir -p "$d"; cp -n "$f" "$d/$fn"
            done
            find "$out" -name '*.module' | while read -r m; do
              d="$(dirname "$m")"
              jq -r '.variants[]?.files[]? | "\(.name) \(.url)"' "$m" 2>/dev/null \
                | sort -u | while read -r name url; do
                [ -z "''${url:-}" ] && continue
                [ "$name" = "$url" ] && continue
                if [ -f "$d/$name" ] && [ ! -f "$d/$url" ]; then cp "$d/$name" "$d/$url"; fi
              done
            done
          '';
        };

        # Gradle init script that points every build at the vendored Maven repo,
        # offline. The flutter_tools/gradle composite build sets
        # FAIL_ON_PROJECT_REPOS, so the root build gets project repositories
        # while included builds get dependencyResolutionManagement repositories.
        offlineInit = pkgs.writeText "nix-offline-init.gradle" ''
          def repoUrl = "file://${gradleRepo}"
          beforeSettings { settings ->
              settings.pluginManagement { repositories { maven { url repoUrl } } }
              if (settings.gradle.parent == null) {
                  settings.gradle.allprojects {
                      buildscript { repositories { maven { url repoUrl } } }
                      repositories { maven { url repoUrl } }
                  }
              } else {
                  settings.dependencyResolutionManagement { repositories { maven { url repoUrl } } }
              }
          }
        '';

        # Replace the Gradle wrapper (which would download a distribution) with
        # the nix-provided Gradle. Online for the deps FOD; offline + the vendored
        # Maven repo for the final build.
        gradlewOnline = pkgs.writeShellScript "gradlew" ''exec ${gradle}/bin/gradle "$@"'';
        gradlewOffline = pkgs.writeShellScript "gradlew" ''exec ${gradle}/bin/gradle --offline --init-script ${offlineInit} "$@"'';

        androidEnv = ''
          export ANDROID_HOME="${sdkRoot}"
          export ANDROID_SDK_ROOT="${sdkRoot}"
          export JAVA_HOME="${jdk.home}"
          # aapt2 from Maven is not patched for Nix; force Gradle to use the SDK's.
          export GRADLE_OPTS="-Dorg.gradle.project.android.aapt2FromMavenOverride=${sdkRoot}/build-tools/${buildToolsVersion}/aapt2"
        '';

        # Prefer the large in-sandbox /dev/shm tmpfs for heavy scratch (the
        # daemon's /tmp can be small); fall back to $TMPDIR.
        mkScratch = ''
          SCRATCH=/dev/shm/${pname}-$$
          mkdir -p "$SCRATCH" 2>/dev/null || SCRATCH="$TMPDIR/scratch"
          mkdir -p "$SCRATCH"
        '';

        # ---- FOD 1: pub (Dart) dependencies ---------------------------------
        pubCache = pkgs.stdenvNoCC.mkDerivation {
          name = "${pname}-pub-cache-${version}";
          src = pubspecSrc;
          nativeBuildInputs = [ flutter ];
          dontConfigure = true;
          buildPhase = ''
            runHook preBuild
            export HOME="$TMPDIR/home"; mkdir -p "$HOME"
            export PUB_CACHE="$out"
            export NIX_FLUTTER_PUB_DART="${dartWithCerts}/bin/dart"
            flutter config --no-analytics >/dev/null 2>&1 || true
            flutter pub get --enforce-lockfile
            runHook postBuild
          '';
          installPhase = ''
            runHook preInstall
            # Drop volatile entries so the output is deterministic. The
            # hosted/<host>/.cache version-listing JSONs carry per-request
            # signatures/timestamps and are not needed for offline pub get.
            rm -rf "$out/_temp" "$out/active_roots" "$out/log" "$out/git" "$out/README.md"
            find "$out" -type d -name .cache -prune -exec rm -rf {} +
            runHook postInstall
          '';
          dontFixup = true;
          outputHashMode = "recursive";
          outputHashAlgo = "sha256";
          outputHash = "sha256-9c4bHGuhFmuvzjec9RHqy9Is2z5PmUeVSywa3QU5nwU=";
        };

        # ---- FOD 2: Gradle / Maven dependencies -----------------------------
        # Runs the real (networked) build once so Gradle resolves & downloads
        # every artifact, then vendors them as a flat Maven repo rebuilt from
        # files-2.1. This is deterministic (only upstream artifacts, no Gradle
        # binary metadata), so the fixed-output hash is stable across rebuilds.
        gradleRepo = pkgs.stdenvNoCC.mkDerivation {
          name = "${pname}-gradle-repo-${version}";
          inherit src;
          nativeBuildInputs = [
            flutter
            jdk
            gradle
            androidSdk
            reconstructMavenRepo
            pkgs.git
            pkgs.which
          ];
          dontConfigure = true;
          buildPhase = ''
            runHook preBuild
            ${mkScratch}
            export HOME="$SCRATCH/home"; mkdir -p "$HOME"
            ${androidEnv}
            export PUB_CACHE="$SCRATCH/pub-cache"
            cp -r ${pubCache} "$PUB_CACHE"; chmod -R u+w "$PUB_CACHE"
            export GRADLE_USER_HOME="$SCRATCH/gradle"; mkdir -p "$GRADLE_USER_HOME"
            install -m755 ${gradlewOnline} android/gradlew
            flutter config --no-analytics >/dev/null 2>&1 || true
            flutter pub get --offline --enforce-lockfile
            flutter build apk --target-platform ${targetPlatform} --release
            # Vendor the resolved artifacts as a deterministic Maven repo.
            reconstruct-maven-repo \
              "$GRADLE_USER_HOME/caches/modules-2/files-2.1" "$out"
            runHook postBuild
          '';
          dontInstall = true;
          dontFixup = true;
          outputHashMode = "recursive";
          outputHashAlgo = "sha256";
          outputHash = "sha256-yvIdMepQdKa5HhfRS3Xtx+RLiSd+hUdnPXilVHZJpUw=";
        };

        # ---- Final: the APK (pure, offline) ---------------------------------
        apk = pkgs.stdenv.mkDerivation {
          inherit pname version src;
          nativeBuildInputs = [
            flutter
            jdk
            gradle
            androidSdk
            pkgs.git
            pkgs.which
          ];
          dontConfigure = true;
          buildPhase = ''
            runHook preBuild
            ${mkScratch}
            export HOME="$SCRATCH/home"; mkdir -p "$HOME"
            ${androidEnv}
            export PUB_CACHE="$SCRATCH/pub-cache"
            cp -r ${pubCache} "$PUB_CACHE"; chmod -R u+w "$PUB_CACHE"
            # Fresh Gradle home; deps come from the vendored Maven repo via the
            # offline init script baked into the gradlew shim.
            export GRADLE_USER_HOME="$SCRATCH/gradle"; mkdir -p "$GRADLE_USER_HOME"
            install -m755 ${gradlewOffline} android/gradlew
            # Bundle libsqlite3.so (sqlite3 uses source:system -> dlopen at runtime).
            install -D ${libsqlite3Android} android/app/src/main/jniLibs/arm64-v8a/libsqlite3.so
            flutter config --no-analytics >/dev/null 2>&1 || true
            flutter pub get --offline --enforce-lockfile
            # --no-pub: skip flutter's implicit (online) pub get; we resolved it
            # offline above. Without it the sandboxed build hits pub.dev.
            flutter build apk --target-platform ${targetPlatform} --release --no-pub
            runHook postBuild
          '';
          installPhase = ''
            runHook preInstall
            mkdir -p "$out"
            cp build/app/outputs/flutter-apk/app-release.apk \
               "$out/${pname}-${version}-arm64-v8a.apk"
            runHook postInstall
          '';
          dontFixup = true;
          passthru = {
            inherit
              pubCache
              gradleRepo
              androidSdk
              flutter
              ;
          };
          meta = with lib; {
            description = "Audix audiobook player — release APK (arm64-v8a)";
            homepage = "https://github.com/JinBlack/audix";
            platforms = [ "x86_64-linux" "aarch64-linux" ];
            license = licenses.unfree; # app has no declared licence
          };
        };

        # ---- Web build (pure, offline) --------------------------------------
        # Flutter's web engine artifacts are prefetched by the nixpkgs wrapper,
        # so this builds offline from the pub cache. Output is the static site.
        web = pkgs.stdenv.mkDerivation {
          pname = "audix-web";
          inherit version src;
          nativeBuildInputs = [ flutter ];
          dontConfigure = true;
          buildPhase = ''
            runHook preBuild
            ${mkScratch}
            export HOME="$SCRATCH/home"; mkdir -p "$HOME"
            export PUB_CACHE="$SCRATCH/pub-cache"
            cp -r ${pubCache} "$PUB_CACHE"; chmod -R u+w "$PUB_CACHE"
            # drift's wasm + worker aren't vendored in git; drop them in.
            install -m644 ${driftWorkerJs} web/drift_worker.js
            install -m644 ${sqlite3Wasm} web/sqlite3.wasm
            flutter config --no-analytics >/dev/null 2>&1 || true
            flutter pub get --offline --enforce-lockfile
            flutter build web --release --no-pub
            runHook postBuild
          '';
          installPhase = ''
            runHook preInstall
            mkdir -p "$out"
            cp -r build/web/. "$out/"
            runHook postInstall
          '';
          dontFixup = true;
          meta.description = "Audix audiobook player — Flutter web build";
        };

        # `nix run` serves the web build locally (cross-origin isolated so
        # drift's wasm worker can use SharedArrayBuffer).
        serveScript = pkgs.writeText "serve.py" ''
          import http.server, socketserver, sys
          port = int(sys.argv[1]); directory = sys.argv[2]
          class H(http.server.SimpleHTTPRequestHandler):
              def __init__(self, *a, **k):
                  super().__init__(*a, directory=directory, **k)
              def end_headers(self):
                  self.send_header("Cross-Origin-Opener-Policy", "same-origin")
                  self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
                  super().end_headers()
          with socketserver.TCPServer(("127.0.0.1", port), H) as s:
              print(f"Audix on http://127.0.0.1:{port}  (Ctrl-C to stop)", flush=True)
              s.serve_forever()
        '';
        serveWeb = pkgs.writeShellApplication {
          name = "audix";
          runtimeInputs = [ pkgs.python3 ];
          text = ''exec python3 ${serveScript} "''${1:-8080}" "${web}"'';
        };
      in
      {
        packages = {
          default = apk;
          audix = apk;
          web = web;
          pub-cache = pubCache;
          gradle-repo = gradleRepo;
          android-sdk = androidSdk;
        };
        apps.default = {
          type = "app";
          program = "${serveWeb}/bin/audix";
        };
        formatter = pkgs.nixfmt-rfc-style;
      }
    );
}
