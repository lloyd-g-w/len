{
  description = "Len — handwriting notes app (Flutter) + sync server (Dart)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAll = f: nixpkgs.lib.genAttrs systems (system:
        f (import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true; # Android SDK
            android_sdk.accept_license = true;
          };
        }));

      # Versions required by Flutter 3.47 / AGP 9.1 (see android/ Gradle files).
      androidVersions = {
        platforms = [ "35" "36" ]; # 35: required by the `jni` plugin
        buildTools = "36.0.0";
        ndk = "28.2.13676358";
        cmake = "3.22.1"; # required by the `jni` plugin
      };
    in {
      devShells = forAll (pkgs:
        let
          # PDFium (PDF import via `pdfrx`) needs no system package: the
          # `pdfium_dart` build hook downloads a prebuilt library at build time.
          linuxDesktop = with pkgs; [ cmake ninja pkg-config clang gtk3 sqlite ] ++ linuxAudio;

          # Audio (features/audio): `audioplayers_linux` builds against
          # GStreamer and plays through its plugins (qtdemux in -good, AAC via
          # -libav, Opus/WebM in -base/-good); `record_linux` records by
          # running `parecord` (PulseAudio/PipeWire) and `ffmpeg`.
          gstPlugins = with pkgs.gst_all_1; [ gst-plugins-base gst-plugins-good gst-libav ];
          linuxAudio = with pkgs; [ gst_all_1.gstreamer libunwind elfutils pulseaudio ffmpeg-headless ] ++ gstPlugins;

          androidSdk = (pkgs.androidenv.composeAndroidPackages {
            platformVersions = androidVersions.platforms;
            buildToolsVersions = [ androidVersions.buildTools ];
            includeCmake = true;
            cmakeVersions = [ androidVersions.cmake ];
            includeNDK = true;
            ndkVersions = [ androidVersions.ndk ];
            includeEmulator = false;
            includeSystemImages = false;
          }).androidsdk;
          sdkRoot = "${androidSdk}/libexec/android-sdk";
        in {
          # Linux desktop development: `nix develop`
          default = pkgs.mkShell {
            packages = [ pkgs.flutter ] ++ linuxDesktop;
            # nixpkgs' Flutter engine has its own RUNPATH, which hides the
            # bundled libsqlite3.so; provide SQLite explicitly.
            LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [ pkgs.sqlite ];
            GST_PLUGIN_SYSTEM_PATH_1_0 = pkgs.lib.makeSearchPath "lib/gstreamer-1.0" gstPlugins;
          };

          # Android development: `nix develop .#android`
          android = pkgs.mkShell {
            packages = [ pkgs.flutter pkgs.jdk17 androidSdk ];
            ANDROID_HOME = sdkRoot;
            ANDROID_SDK_ROOT = sdkRoot;
            JAVA_HOME = pkgs.jdk17.home;
            # Gradle downloads a generic aapt2 that cannot run on NixOS; use the SDK's.
            GRADLE_OPTS = "-Dorg.gradle.project.android.aapt2FromMavenOverride=${sdkRoot}/build-tools/${androidVersions.buildTools}/aapt2";
          };
        });
    };
}
