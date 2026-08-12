# WebF Android verification

This harness builds a plugin and starts a temporary Songloft server on the host.
Docker builds an x86_64 release APK, runs the Android Emulator, installs the
APK, opens the real WebF plugin page, and runs automated verification.

## Downloader plugin test

```bash
./scripts/webf-android-verify/run.sh
```

Builds the downloader plugin, opens its settings page, and verifies switch
alignment from a screenshot. This is the original / primary test.

## MIoT plugin test

```bash
./scripts/webf-android-verify/run-miot-test.sh
```

Builds and uploads the miot plugin (`jsplugins-src/songloft-plugin-miot`),
opens the miot WebF page, navigates to settings, and captures screenshots.
Requires a pre-built APK (run `run.sh` at least once first to build it).

Outputs are written to `scripts/webf-android-verify/out/miot-test/`:

| File | Description |
|------|-------------|
| `miot-main.png` | 主页面截图（歌单选择器、播放栏、控件） |
| `miot-settings.png` | 设置页面截图（分类菜单） |
| `miot-settings-scrolled.png` | 设置页面滚动后截图 |
| `miot-ui.xml` | 主页面 UI 树 dump |
| `miot-settings-ui.xml` | 设置页面 UI 树 dump |
| `miot-logcat.txt` | 完整 logcat 日志 |

验证覆盖点：
- WebF 页面加载成功（无 startupError）
- SlSelect / SlButton / SlIcon 组件渲染
- Player icon font codepoints 映射正确
- PlayerProgress 时间标签显示
- 设置页面高度（100dvh → 100vh fix）生效

## Host requirements

Linux with Go, npm, Docker, and `/dev/kvm`. The temporary server listens on
port `58192` (downloader) or `58394` (miot) by default. The Android device
reaches it through `adb reverse`; override with `SERVER_PORT` when needed.

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
