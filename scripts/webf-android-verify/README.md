# WebF Android verification

This harness builds the current downloader plugin and starts a temporary
Songloft server on the host. Docker builds an x86_64 release APK, runs the
Android Emulator, installs the APK, opens the real WebF plugin page, and
verifies the downloader settings switches from an Android screenshot.

## Run

```bash
./scripts/webf-android-verify/run.sh
```

The host must be Linux with Go, pnpm, Docker, and `/dev/kvm`. The temporary
server listens on port `58192` by default. The Android device reaches it through
`adb reverse`; override the host port with `SERVER_PORT` when needed.

The default emulator is the official Google API 30 x86_64 container image.
Override it when a locally-built newer image is available:

```bash
EMULATOR_IMAGE=us-docker.pkg.dev/android-emulator-268719/images/30-google-x64:30.1.2 \
  ./scripts/webf-android-verify/run.sh
```

Set `KEEP_RUNNING=1` to keep the server and emulator up after a run. Results are
written to `scripts/webf-android-verify/out/`.

The default emulator image is headless and uses ADB. Screenshots are captured
with `adb exec-out screencap -p` by the runner.
