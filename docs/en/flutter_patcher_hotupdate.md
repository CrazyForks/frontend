# flutter_patcher Self-Hosted Android Hot Update (frontend libapp.so)

This doc describes songloft-player's **frontend self-hosted Android hot update** built on [`flutter_patcher`](https://github.com/xuelinger2333/flutter_patcher): it replaces the whole `libapp.so` on cold start, patches are **auto-published as assets on every GitHub Release**, and the client checks on startup, downloads on manual confirm, and takes effect on cold restart; versions that can't be hot-patched send the user to Settings to download the APK.

> Bilingual: any change here must be mirrored in `docs/cn/flutter_patcher_hotupdate.md`.
> The Bundle build merges this frontend patch and the backend `libgojni.so` patch into one update experience (one dialog, one cold restart) — see [backend_hotupdate.md](backend_hotupdate.md); this doc focuses on the **frontend mechanism and the standard-build release**.

## Scope & boundaries

| Dimension | Conclusion |
|------|------|
| Platform | **Android only**. On iOS/desktop/web the plugin and our wrapper are safe no-ops |
| Hot-patchable | Any Dart under `lib/`, pure-Dart deps, bundled-registered Flutter assets |
| Not hot-patchable | Native Kotlin/Java/C++, `AndroidManifest`, `res/`, native plugin add/change, Flutter Engine upgrades — must ship a new APK |
| When it applies | On the **next cold start** after download, never in-process; the plugin has crash rollback + bad-patch blacklist |
| Channel | **dev updates dev, stable updates stable, no crossing** (decided by compile-time `AppConfig.frontendVersion`) |
| Integrity | Currently **MD5 only** (`FlutterPatcher.init(strictSignature: false)`); Ed25519 can be added later |

## Core model: baseline-free + auto-publish + compatibility key

- **Baseline-free**: the client fetches the **latest of its channel** — dev → rolling tag `dev`; stable → GitHub `/releases/latest` (dev is a prerelease, so latest returns the newest stable). Resolved by `lib/core/updater/channel_release_resolver.dart`; any non-latest → latest.
- **Auto-publish**: `build-and-release.yml`'s `build-android` job runs `dart run flutter_patcher:pack` on every release, producing `patch-<abi>.zip` + `manifest-<abi>.json` uploaded with the release (`arm64-v8a` / `armeabi-v7a` only; `x86_64` produces no patch). **The manual `patch-release.yml` is gone.**
- **Comparison**: dev by **git commit hash**; stable by **version number** (semver, `lib/core/updater/version_compare.dart`). Already-applied (`flutter_patcher.currentVersion == patchLabel`) is skipped.
- **Compatibility key instead of a versionCode baseline**: `libapp.so` inherently binds to the host APK's **versionCode** (engine binding). This project's pubspec `+N` is **constant** (CI does not bump it per build), so all dev/stable builds share one versionCode and cross-version hot update works naturally — versionCode is an **automatic compatibility proxy, not a hand-picked baseline**. The client additionally compares `AppConfig.flutterBinding` (= CI `FLUTTER_VERSION`) with the manifest's `flutterBinding`: different → not hot-patchable (guards against same versionCode but a changed Flutter engine crashing) → the "incompatible / full-APK" branch. Only a deliberate versionCode bump (usually alongside engine/native changes) forces the full APK.

## Client flow (startup check + manual)

Entry: the home page calls `PatchUpdateDialog.maybeShow` once per session in `initState` (`lib/core/updater/`) — the frontend patch (this doc) and backend patch (Bundle build) are **merged into one dialog**.

1. **A hot-patchable patch** (and not "ignored") → a **dismissible** dialog listing pending components + a **GitHub proxy selector** (reusing `GithubProxySelectionMixin`) + buttons **[Ignore this version] [Later] [Download & update]**; download shows progress → on success a "restart to apply" dialog ([Restart now] = `EmbeddedBackendService.restartProcess()`, a **real process cold restart** so `libapp.so` takes effect on cold start).
2. **No patch but a newer full version on the same channel** (`FrontendVersionApi`, not ignored) → "New version required" dialog → **[Ignore] [Later] [Go to download]**; go-to-download navigates to `/settings` (which has the client-update APK download).
3. Neither → silent.

- Proxy: both the manifest fetch and the patch download go through the selected proxy (`PatchUpdateService.applyProxy`, prefix concat); the choice persists to `githubProxyProvider`, shared with the plugin store / full-package upgrade.
- Ignore: remembered separately in `AppPreferences.ignoredPatchVersion / ignoredClientVersion`.

## Hosting & URL convention

Patches are uploaded as assets with the corresponding Release; the repo is decided by `AppConfig.frontendUpdateRepo` (standard = `songloft-org/songloft-player`; Bundle = parent repo `songloft-org/songloft`), and the client switches by channel automatically, no code change.

- manifest: `https://github.com/<repo>/releases/download/<tag>/manifest-<abi>.json`
  - stable: `<tag>` = `v<version>` (resolved via `/releases/latest`); dev: `<tag>` = `dev`
  - content is `PatchCheckResult` shaped: `{"hasUpdate":true,"patch":{"version"(= the `<semver>-<gitCommit>` label),"semanticVersion","gitCommit","flutterBinding","targetVersionCode","patchUrl","md5"}}`
- patch package: `patch-<abi>.zip` in the same Release (md5 over the zip)
- **Backward compatibility**: when a legacy manifest lacks `semanticVersion` / `gitCommit` / `flutterBinding`, the client falls back to the old "`hasUpdate` + versionCode binding + already-applied guard" behavior.

## Publishing (`build-and-release.yml`'s `build-android`, automatic)

Every release (tag `dev` or `v<x.y.z>`) automatically runs: `flutter build apk --release --split-per-abi` → for `arm64-v8a` / `armeabi-v7a` each `dart run flutter_patcher:pack --apk <abi apk> --version <semver>-<commit> --target-version-code <vc> --abi <abi>` → produces `patch-<abi>.zip` + `manifest-<abi>.json` → uploaded with the release. **No manual workflow, no cherry-pick, no `patch_label` input.**

## Release discipline

- **Dart-only change** → ships with the next release automatically; old builds hot-update, effective on cold restart (no separate patch tag);
- **Native / plugin-native / engine change** → if the Flutter engine changes, the `flutterBinding` key mismatches and old builds auto-fall to the full-APK branch; a deliberate versionCode bump goes full APK the same way, and users are guided to download the APK.

## Verification

1. `flutter analyze` passes; `flutter build apk --release --split-per-abi` succeeds.
2. Install an old dev / stable APK of some ABI on a real device.
3. Ship an update (change one visible Dart thing) → open the app → "Update available" dialog lists the frontend component → pick proxy → download → restart → see the change = success.
4. Incompatible path: a new build with an upgraded Flutter engine → `flutterBinding` mismatch → opening the app shows "New version required" → navigates to `/settings`.
5. After "Ignore this version" the same version stops prompting; a higher version resumes prompting.

## Notes

- **Google Play and some channels** may restrict dynamic delivery of executable `.so`; this project targets self-controlled / sideload distribution.
- flutter_patcher is beta; validate internally before staged rollout.
- Requirements (already met): AGP 8.11.1+ / Kotlin 2.2.20+ / Java 17 / minSdk 24 / compileSdk 36 / NDK 27+.
