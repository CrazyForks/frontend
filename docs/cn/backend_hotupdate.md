# Bundle 版 Android 热更新(前端 libapp.so + 后端 libgojni.so)

本文描述 Bundle 本地模式下 songloft-player 的 **Android 自托管热更新**:**无基线**——任何非最新 dev 更新到最新 dev、任何非最新 stable 更新到最新 stable。**每次发版自动**把最新补丁挂到 Release,客户端启动检查、一次下载、只重启一次:一次真进程冷启同时让前端 `libapp.so`(flutter_patcher)与后端 `libgojni.so`(gomobile)生效。

> 中英双语并存,改一版需同步 `docs/en/backend_hotupdate.md`。

## 核心模型:无基线 + 自动发布 + 工具链兼容键

- **无基线**:客户端查**本渠道最新**——dev→滚动 tag `dev`;stable→GitHub `/releases/latest`(dev 是 prerelease,latest 天然返回最新正式版)。由 `lib/core/updater/channel_release_resolver.dart` 解析,复用 `FrontendVersionApi` 思路。
- **自动发布**:`release.yml` 的 `build-bundled-android` job 每次发版自动产出并上传:前端 `patch-<abi>.zip`+`manifest-<abi>.json`、后端 `libgojni-<abi>.so`+`backend-manifest-<abi>.json`(arm64-v8a / armeabi-v7a / x86_64,gomobile bind 含 android/amd64 目标)。**无手动 workflow、无 versionCode 绑定**。
- **兼容键取代 versionCode**(自动、非手改):
  - **前端 libapp.so**:flutter_patcher 天然按 **versionCode** 绑定(libapp.so ↔ 引擎)。`--split-per-abi` 下 gradle 会把各 ABI APK 的 versionCode 改写为「ABI偏移×1000+pubspec基础值」(如 arm64-v8a=2001),CI 用 aapt 从分 ABI APK 读**真实值**写入 manifest/补丁;本项目 pubspec 的 `+N` **恒定**(CI 不随构建 bump),同 ABI 的新旧构建 versionCode 相同,自然绑定即可跨版本热更——versionCode 是**自动的兼容代理**,不是手挑的基线。客户端额外比对 `AppConfig.flutterBinding`(= CI `FLUTTER_VERSION`)与 manifest 的 `flutterBinding`:不同 → 不热更(防同 versionCode 但换了 Flutter 引擎导致崩溃),交「整包不兼容」分支下 APK。仅当有意 bump pubspec `+N`(通常伴随引擎/原生变更)时前端才走整包。
  - **后端 libgojni.so**:兼容边界是 gomobile 导出面(`mobile/export_surface.txt` + `release.yml` 导出面守卫,自动)。**去掉 versionCode**,靠「导出面冻结 + 崩溃回滚黑名单」保证任意老包热更到最新。
- **比较规则**:dev 比 **git commit hash**;stable 比**版本号**(semver,`lib/core/updater/version_compare.dart`)。已应用同补丁(`flutter_patcher.currentVersion == patchLabel` / 后端 confirmed)跳过。

## 原生契约哈希闸(Dart↔原生 / Go 导出面运行时校验)

热更只换 native .so,**Kotlin/Java 永不热更**(只随整包 APK 走)。versionCode 与 `flutterBinding` 两闸抓不到 **Dart↔原生 MethodChannel 契约漂移**:若某次发版给某 `com.songloft/*` channel 加了方法(Kotlin 加 + Dart 调),既不动引擎也不动 versionCode → 现有闸全放行 → 老包热更到新 `libapp.so`,但设备旧 Kotlin 没这方法 → 运行时 `MissingPluginException`。dev 渠道尤甚:只有一个滚动 release,git commit 每次都不同,无法据此区分「正常新版本」与「契约不兼容版本」。标准版无后端桥但同样热更 `libapp.so`,风险面更大(自定义 channel + 大量原生插件)。

**唯一能忠实反映「本地 APK 原生层支持什么」的信号只能运行时从不被热更的 Kotlin 读取**(Dart/Go 侧常量都会被补丁覆盖)。为此引入原生契约哈希闸:

- **两个哈希**,由原生 channel `com.songloft/contract` 的 `getHash` 一次返回 `{"dart","go"}`:
  - `dart` = Dart↔原生契约 = {所有 `com.songloft/*` channel 名 + 方法名集合 + `GeneratedPluginRegistrant` 插件集 + `.flutter-plugins-dependencies` 里 android 原生插件 name+version}。门控**前端 libapp.so**(标准版 + bundle 都用)。
  - `go` = `sha256(mobile/export_surface.txt)`。门控**后端 libgojni.so**(仅 bundle),补上「老 APK Kotlin vs 新 libgojni 运行时错配」——这是 CI 导出面冻结守卫看不到的维度。
- **值的来源**:CI 用 `scripts/compute_native_contract.sh`(确定性)在 `flutter build apk` 前算出,同时写进 APK asset `android/app/src/main/assets/native_contract.json`(Kotlin 读它返回)与热更 manifest(`patch.contractHash` / `backend.contractHash`),**同源同值**。
- **比对**:`checkPatch` 里 `contractHashBlocks(manifestHash, deviceHash)`——两端非空且不同 → 返回 null(落整包)。**任一为空**(老宿主无此 channel / 本地开发无 asset / 老式 manifest 无字段)→ 视为未知、**不拦截**(降级),同 `flutterBinding` 闸。
- **iOS 不参与**:热更 Android-only,`NativeContractService` 的 `_isAndroid` 守卫使 iOS 永不触发。
- **残余风险(诚实)**:Kotlin 方法集为启发式解析(`call.method == "x"` / `when` 分支 `"x" ->`),动态拼接的方法名可能漏掉;插件「同版本号但内部原生实现变化」也不捕获。宁滥勿缺(误触发只是多走整包=安全侧),换来零手维护清单。

## 能力边界(诚实)

| 场景 | 前端 libapp.so | 后端 libgojni.so |
|------|----------------|------------------|
| dev → 最新 dev | ✓(dev 共用 versionCode/引擎) | ✓ |
| stable → 最新 stable(引擎未变) | ✓(引擎键相同,跨 versionCode) | ✓(无 versionCode) |
| stable 且 Flutter 引擎升级 | ✗ → 走整包 APK(本就是新引擎新包) | ✓(与 gomobile 导出面无关) |
| 改了 `com.songloft/*` channel 方法集 / 增删原生插件 | ✗ 整包(dart 契约哈希不匹配) | —— |
| 改了 mobile.go 导出面 | ✗ 整包(前端不受影响则仍可热更) | ✗ 整包(导出面守卫 + go 契约哈希双拦) |

- 仅 Android;仅 Bundle 版(`hasEmbeddedBackend`)+ local 模式后端在运行时才检查后端补丁。iOS 静态 xcframework + Apple 政策 → 不支持。

## 可行性根基(原生机制)

- `libgojni.so` 由 gomobile 的 `go.Seq` 静态块 `System.loadLibrary("gojni")` 在首次触碰任意 `mobile.*` 类时懒加载。
- `SongloftApplication.onCreate()`(早于任何 `mobile.*`)`System.load("<filesDir>/backend_patch/active/libgojni.so")` 预加载补丁版;bionic 按 soname 去重,后续 `loadLibrary("gojni")` 复用补丁版。**gomobile 产物无 DT_SONAME**(正常),bionic(minSdk 24 ≥ API 23)回退用**文件 basename** 作 soname;客户端落地文件名固定为 `libgojni.so`,故去重仍生效。release.yml 只校验「soname 为空或恰为 libgojni.so」(非空且不同才失败)。
- W^X:targetSdk 29+ 从私有目录 `System.load()` 下载的 .so **允许**(限制的是 execve 与含 text-reloc 的 .so)。
- 必须冷重启进程生效(Go runtime 单进程只初始化一次);`SystemNavigator.pop()` 只关 Activity,不够 → 用 `ProcessRestarter`(AlarmManager + killProcess)真重启。

## 客户端流程(统一入口)

首页 `initState` 每会话调一次 `PatchUpdateDialog.maybeShow`(`lib/core/updater/`):
1. 并行检查前端(`PatchUpdateService.checkPatch`)+ 后端(`BackendPatchService.checkPatch`,仅 `hasEmbeddedBackend && Android && local && 后端运行`)本渠道最新补丁,各自过滤「忽略此版本」。
2. 任一有更新 → 弹**一个**对话框列出待更新组件 + GitHub 代理选择器(复用 `GithubProxySelectionMixin`),按钮 **[忽略此版本] [稍后] [下载并更新]**。
3. 「下载并更新」一起下载(前端 `flutter_patcher.applyPatch` stage libapp.so、后端 `downloadAndStage` 下 .so + md5 + 交原生 `stageBackendPatch`)。
4. 完成 → 「立即重启」**一次** `EmbeddedBackendService.restartProcess()`(真进程冷启),提示「应用将重启,可能中断当前播放」。「稍后」保留 staged,下次冷启一并生效。
5. 前端补丁引擎不兼容(新 stable 换了 Flutter)→ checkPatch 返回 null → 落入「整包不兼容」分支跳设置页下 APK。

## 崩溃回滚 + 黑名单(原生 `BackendPatchManager`)

状态存纯文件 `filesDir/backend_patch/state.json`(需在 Dart 引擎前可读)。`preloadIfStaged`:无 active / 在黑名单 → 不预加载(回滚随包版);`confirmed` → 直接 `System.load`;`staged/pending` → `bootAttempts++`,超阈值(>1)判定启动即崩 → 拉黑(gitCommit+md5)+ 清 active + 回滚;`System.load` 抛异常 → 立即拉黑回滚,绝不让进程崩。confirm 时机:新进程后端健康后(`startup_gate` 冷启 / `backend_lifecycle` resume)`BackendPatchService.confirmIfHealthy()` 校验 `/api/v1/version` git_commit 一致 → `confirmBackendPatch()`。

## Manifest 约定(父仓库 Release 资产,按 ABI)

- 前端 `manifest-<abi>.json`:`{hasUpdate, patch:{version(patchLabel), semanticVersion, gitCommit, flutterBinding, patchUrl, md5}}`
- 后端 `backend-manifest-<abi>.json`:`{hasUpdate, backend:{abi, version, gitCommit, buildTime, soUrl, md5, size}}`(无 targetVersionCode)
- 都随 `release.yml` 的 release(tag=dev / v<x.y.z>)自动上传;客户端按渠道解析最新。

## 发布纪律

- 每次发版自动带补丁,无需额外操作;**导出面守卫**(`go doc ./mobile` 比对 `mobile/export_surface.txt`)在 `release.yml` 里,导出面漂移即 fail(须整包)。
- 改 Flutter 版本 → 前端老包自动走整包(引擎键不匹配);改 mobile.go 导出面 / 加原生插件 → 整包。
- **原生契约哈希全自动**:`scripts/compute_native_contract.sh` 每次构建重算 asset + manifest,无需手维护版本号或清单。改 `com.songloft/*` channel 方法集 / 增删原生插件 → dart 哈希自动变,老包读到不匹配自动走整包;导出面变 → go 哈希自动变。**无需 bump 任何常量**。

## 验证

1. **dev 任意→最新**:老 dev 包 → 弹一个对话框列前端+后端 → 一次下载 → 单次重启 → `/api/v1/version` git_commit 变最新 + 前端改动生效 → confirm。
2. **stable 任意→最新(引擎未变)**:老 stable 包 → 后端按版本号更新到最新 stable;前端引擎键相同 → 也更新。
3. **stable 引擎已变**:前端引擎键不匹配 → 前端走整包;后端仍可热更。
4. **崩溃回滚**:坏 .so → System.load/Init 崩 → bootAttempts 超阈值拉黑回滚,不再下发。
5. **无 versionCode 依赖**:后端全程不比 versionCode;CI `readelf` + 导出面守卫为唯一后端门禁。

## 注意

- Google Play 等渠道可能限制动态下发 `.so`,本项目走自控/侧载分发。
- **标准版(非 bundle)也是无基线**:player 仓库 `build-and-release.yml` 的 `build-android` 每次发版自动产出前端 `patch-<abi>.zip`+`manifest`(无后端);手动 `patch-release.yml` 已删除。客户端逻辑对老式 manifest 仍向后兼容(无新字段时退回 hasUpdate + versionCode 绑定旧行为)。
