# DeepSeek for HarmonyOS

<p align="center">
  <img src="assets/app_icon.png" width="160" alt="DeepSeek for HarmonyOS">
</p>

基于 HarmonyOS WebView 封装的 DeepSeek 鸿蒙客户端，支持手机、平板和 2in1。

---

## ⚠️ 使用须知

> **本项目仅供鸿蒙（HarmonyOS / ArkTS）应用开发交流与学习使用。**
>
> **请通过官方途径使用 DeepSeek** —— 官方网站 <https://chat.deepseek.com>，
> 或各应用商店中的官方 App。本项目**不是**官方客户端，不提供任何官方保证。
>
> 本应用只是把 DeepSeek 网页装进 WebView 容器：您的账号、对话内容等均由
> DeepSeek 官方站点处理，其数据处理适用官方的隐私政策。使用本项目产生的任何
> 后果由使用者自行承担。

---

> **复刻说明**
> 本项目 fork 自 [SakuraNeko/Deepseek-Harmony](https://github.com/SakuraNeko/Deepseek-Harmony)，
> 在原项目基础上继续完善。原作者：**Sakura Neko**（MIT 许可，详见 [LICENSE](./LICENSE)）。
>
> 本项目为**非官方客户端**，与 DeepSeek 官方无任何关联；DeepSeek 名称及相关标识归其权利人所有。

## 功能

| 功能 | 说明 |
|------|------|
| 🌐 WebView | 内嵌 chat.deepseek.com，完整对话体验 |
| 🌍 系统语言 | 跟随系统语言注入 WebView，支持动态切换 |
| 🔗 Deep Link | 冷/温/热启动接收分享链接并导航 |
| 🌙 深色模式 | 跟随系统自动切换 |
| 📤 文件上传 | 拍照 / 相册 / 文档选择器 |
| 💾 文件下载 | 转存至公共下载目录（文件名净化 + 沙箱不留残件） |
| 📲 系统分享 | 拦截分享链接，唤起系统分享面板 |
| 🎙️ 语音输入 | 网页请求麦克风时走官方两步链路：系统权限 + 应用内确认 |
| 🔗 外部链接 | 站外链接与 `window.open` / `target="_blank"` 均转交系统浏览器 |
| ↩️ 返回手势 | 对话界面「再按一次返回桌面」，二三级界面保持网页后退 |
| ♿ 无障碍 | 图标按钮均提供朗读文案，触摸目标不小于 44vp |
| 🔒 安全 | TLS 证书错误一律拒绝，不提供「继续访问」 |
| 🔄 稳定性 | 渲染崩溃自动刷新 + 15s 超时错误页 |

## 项目结构

```
entry/src/main/ets/
├── common/                          纯逻辑与常量（不依赖组件，可独立测试）
│   ├── AppConfig.ets                入口 URL / 域名 / 反馈地址 / scheme 前缀 / UA 标识
│   ├── LanguageUtil.ets             BCP 47 语言标识规范化
│   ├── UrlRules.ets                 同域判断 / 聊天主站判定 / 下载链接判定
│   ├── AllowedFileExtensions.ets    上传后缀白名单
│   ├── DownloadFiles.ets            下载文件名净化 / 沙箱中转路径 / 残留清理
│   ├── AppPermissions.ets           系统权限查询与申请（麦克风）
│   ├── WebViewport.ets              视口修正 / 窗口尺寸通知 / 运行时诊断脚本
│   ├── WebInputGuard.ets            点图片不聚焦输入框的防护脚本
│   ├── PhotoTempFiles.ets           拍照临时文件的生成与启动清理
│   └── UiPrefs.ets                  悬浮条位置等界面偏好持久化
├── components/                      展示型组件
│   ├── PageProgress.ets             顶部加载进度条
│   ├── ErrorView.ets                网络异常 / 加载失败页
│   ├── RefreshConfirmDialog.ets     刷新确认弹窗
│   ├── FloatingBar.ets              右下角悬浮操作条（拖拽、边界、位置持久化）
│   ├── SettingsSheet.ets            设置面板内容
│   └── UploadSheet.ets              上传方式选择模态框
├── entryability/EntryAbility.ets    窗口沉浸 + Deep Link + 系统语言初始化
└── pages/Index.ets                  WebView 主页面
```

## Deep Link

支持从其他 App / 短信 / 扫码打开 `https://chat.deepseek.com/share/...` 分享链接。

> **浏览器中点击同域链接不会唤醒应用**，原因：`chat.deepseek.com` 非自有域名，无法托管 AGC 域名校验文件。

## 构建

| 要求 | 版本 |
|------|------|
| DevEco Studio | 6.0+（实测 26.0.0.821） |
| HarmonyOS SDK | API 23+ |
| 权限 | INTERNET、GET_NETWORK_INFO、MICROPHONE（user_grant，用于语音输入） |

### ⚠️ 工程路径不能包含空格

**这是最容易踩的坑。** DevEco Studio 的工程路径只允许字母、数字、`.`、`_`、`-`。
路径里带空格（例如把工程放在 `D:\DevEco Studio\projects\` 这类目录下）会表现为：

- hvigor 命令行构建**完全正常**，能产出签名 HAP；
- 但 IDE 侧的工程模型解析失败（日志里可见 `module src path is not valid`、`module model size: 0`）；
- 结果：**运行配置的 Module 下拉是空的**，点 Run 报 `No module found`，
  并且 `.idea/modules.xml`、`entry.iml`、`.deveco/module/entry.cache.json` 永远不会生成。

清 IDE 缓存、重装 DevEco 都无效 —— 只有把工程移到无空格路径才能解决。
推荐形如 `D:\DevEcoProjects\Deepseek-Harmony-webview`。

### 关于签名配置

`build-profile.json5` 的 `signingConfigs.default.material` 记录的是**签名证书的本机绝对路径**
（`C:\Users\<你>\.ohos\config\...`），因此：

- 直接 clone 后无法构建，必须先在 DevEco 里重新配置签名：
  **File → Project Structure → Signing Configs → 勾选 Automatically generate signature**；
- 其中的口令是 DevEco 加密后的密文，即便如此也不建议提交到公开仓库。

## 命令行构建与测试

工程**没有** `hvigorw` 包装脚本，命令行需直接使用 DevEco 自带的 node + hvigor，
并且必须显式提供两个环境（IDE 里是自动注入的，命令行不会给）：

```powershell
$devEco = 'D:\anzhuanglujing\DevEco Studio'   # 换成你自己的安装目录
$env:DEVECO_SDK_HOME = "$devEco\sdk"          # 不设置会报 00303217 Configuration Error
$env:Path = "$devEco\jbr\bin;$env:Path"       # 不设置会在打包阶段报 spawn java ENOENT

$node    = "$devEco\tools\node\node.exe"
$hvigorw = "$devEco\tools\hvigor\bin\hvigorw.js"

# 构建 HAP → entry/build/default/outputs/default/entry-default-signed.hap
& $node $hvigorw --mode module -p product=default assembleHap `
  --analyze=normal --parallel --incremental --no-daemon

# 本地单元测试（跑在宿主机上，不需要设备）
& $node $hvigorw --mode module -p module=entry@default -p product=default test --no-daemon

# 设备侧测试：构建测试 HAP → 安装 → 用 aa test 驱动
$hdc = "$devEco\sdk\default\openharmony\toolchains\hdc.exe"
& $node $hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon
& $hdc install -r entry/build/default/outputs/ohosTest/entry-ohosTest-signed.hap
& $hdc shell aa test -b dev.cyotatsu.deepseek.oh -m entry_test `
    -s unittest OpenHarmonyTestRunner -s timeout 120000
```

> 设备侧测试**不要**加 `-s class testsuite`。该参数按 `describe` 名称过滤，
> 而不是按导出的函数名 —— 传 `testsuite` 会得到 `Tests run: 0`，
> 看着像"跑过了"其实一个用例都没执行。不加它才会跑全部套件。

| 测试位置 | 覆盖范围 | 用例数 | 运行环境 |
|----------|----------|--------|----------|
| `entry/src/test/` | 纯逻辑：`toBCP47`、下载文件名净化与中转路径、viewport 脚本与 UA 拼装、输入框上限公式、点图防护脚本、网页弹层探测脚本、返回手势判定 | 69 | 宿主机 |
| `entry/src/ohosTest/` | 依赖系统 API：`UrlRules`（含 `isChatHost` 的 fail-closed 边界、`isChatRootPage` 的对话界面判定） | 19 | 设备 |

本地测试结果：`entry/.test/default/intermediates/test/coverage_data/test_result.txt`，
HTML 报告：`entry/.test/default/outputs/test/reports/index.html`；
设备侧结果直接打印在 `aa test` 的 `OHOS_REPORT_RESULT` 行。

> 两组用例均已在真机（MatePad 11.5，`5HEUN26228G12607`）跑通：本地 **69/69**、设备侧 **19/19**。

### 无人工的 UI 验证（uitest）

设备连着时，可以用系统自带的 uitest 直接验证界面渲染，不需要人盯着屏幕：

```powershell
& $hdc shell aa start -a EntryAbility -b dev.cyotatsu.deepseek.oh
& $hdc shell uitest dumpLayout -p /data/local/tmp/layout.json   # 导出 ArkUI 节点树
& $hdc file recv /data/local/tmp/layout.json .\layout.json
& $hdc shell uitest uiInput click <x> <y>                       # 模拟点击，坐标单位 px
```

判断依据：我们自绘控件的文案是 ArkUI `Text` 节点，**一定会出现在 dump 里**；
而网页内容跑在 `Web` 组件内部，**不会**出现在 dump 里。所以 dump 中出现
「清理应用缓存」「问题反馈」这类文案，就等于证明该组件确实被渲染了 ——
反过来说，如果自绘控件的文案一个都找不到，那多半是组件根本没渲染出来。

> 注意 `dumpLayout` 不导出 `accessibilityText`，只导出 `accessibilityId`。
> 想用 dump 验证无障碍文案是行不通的，得实际开读屏。

> 之所以分成两处：`src/test/` 里**不能**调用系统 API（`url.URL.parseURL` 在宿主机环境会抛异常，
> 断言会全部失真）。纯逻辑放本地、依赖系统 API 的放设备侧。

## 窗口形态与网页布局适配

本应用会跑在多种窗口形态下，窗口宽度差异很大且可以连续变化。网页能不能跟着切换
桌面端 / 移动端布局，取决于**布局视口（layout viewport）是否跟随窗口宽度**。

### 根因

SDK 中 `WebAttribute.metaViewport` 的 API Note 原文：

> If a User-Agent does not contain the Mobile field, the viewport property in the meta tag is
> disabled by default. In this case, you can explicitly set the **metaViewport** property to
> true to overwrite the disabled state.
>
> If the device is 2-in-1, the viewport property is not supported.

也就是说：**内核按「UA 里有没有 Mobile」决定要不要解析网页的 `<meta name="viewport">`**。
手机默认 UA 含 Mobile，所以一直正常；平板/2in1 的默认 UA 不含 Mobile，网页里的
`width=device-width` 就不被解析，布局视口退回约 980px 的默认宽度 —— 于是窗口拖窄了，
网页仍按桌面大屏排版，表现为挤压 / 留白 / 错位。

**这是第一层，但不是全部。** 只加 `.metaViewport(true)` 只解决了「网页的 viewport 声明
被不被解析」，并不改变 `device-width` 的语义 —— 实测发现还有第二层：

#### 第二层（决定性）：`device-width` 是**屏幕**宽度，不是窗口宽度

Chromium 里 `width=device-width` 取的是**整块屏幕**的宽度，而非 WebView（应用窗口）的宽度。
全屏时窗口宽度恰好等于屏幕宽度，两者重合，所以**全屏下永远看不出问题**；
一旦进入悬浮窗 / 自由多窗，窗口远窄于屏幕，网页就按整屏宽度排版，再被整体缩小塞进小窗。

实机实测（平板 2456×1600，自由多窗）：

| 量 | 值 | 说明 |
|----|----|------|
| 窗口宽度 | 1430 px | 应用窗口实际占的物理像素 |
| `dpr` | 1.8625 | WebView 的 `devicePixelRatio` |
| 窗口宽度的 CSS px | 1430 ÷ 1.8625 = **768** | 也正好等于 ArkUI 侧 `pageW` 的 768 vp |
| 屏幕宽度 | 2456 px | |
| 屏幕宽度的 CSS px | 2456 ÷ 1.8625 = **1319** | 这才是 `device-width` 的取值 |
| 修复前探针 `clientW` | **1319** | 布局视口 = 屏幕宽，比窗口宽 1.72 倍 |
| 修复后探针 `clientW` | **768** | 布局视口 = 窗口宽 |

1319 CSS px 的页面被塞进 768 CSS px 的窗口里显示，缩放比约 58% —— 这正是「**自由多窗下
UI 显得很小**」的由来，不是系统的正常缩放，而是布局视口取错了基准。

由此还得到一个可用的换算不变式：**本设备上 WebView 里 1 CSS px 恰好等于 ArkUI 的 1 vp**
（`pageW` 768 vp → `clientW` 768 CSS px），所以 ArkUI 侧的窗口宽度可以直接当作 CSS px 用。

### 采用的策略

| 手段 | 作用 |
|------|------|
| `.metaViewport(true)` | 第一层：显式覆盖「UA 无 Mobile 就禁用 viewport」的默认行为，让网页的 `<meta name="viewport">` 重新被解析 |
| **注入 `width=<窗口宽度>`** | 第二层（决定性）：把网页 viewport 里的 `width=device-width` 改写成**应用窗口的宽度（vp）**，布局视口才真正等于窗口宽度。只替换 `width=` 这一段，保留站点自己的 `maximum-scale` / `user-scalable` / `viewport-fit` |
| 补发 `resize` 事件（防抖 260ms） | 唤醒「只在加载时读一次 `window.innerWidth`」的 SPA；窗口尺寸稳定后再发，避免拖拽时高频重排 |
| 注入 CSS 高度上限 | `textarea / [contenteditable]` 按实时可视高度取上限并内部滚动，长文本不再把输入框无限向上顶（详见「输入框高度上限」一节） |
| 运行时探针日志 | 打印 UA、`clientW`、`innerWidth`、`dpr`、viewport meta、输入框高度，用于实机判定 |

注入点在页面加载完成（`onPageEnd`）与每次窗口尺寸变化（`onAreaChange` → 防抖 → 重新注入）
时都会执行。页面若没有 viewport 声明则补一个；`document.head` 还没就绪时返回 `no-head`，
下一次时机再补，日志里的 `Viewport fix:` 会给出 `ok:<最终 content>` / `no-head` / `error` 三态。

### 为什么不动态切换 User-Agent

「宽窗用桌面 UA、窄窗用移动 UA」看似直观，但有三个硬伤：

1. `setCustomUserAgent` **只对后续加载生效**，跨断点必须重载页面；
2. 自由多窗拖拽时宽度连续变化，会反复跨断点 → 频繁重载、闪烁；
3. 重载会丢掉 SPA 里**正在输入的内容**和会话状态。

而「`.metaViewport(true)` + 注入 `width=<窗口宽度>`」是让网页按**实时窗口宽度**重排，
**全程零重载**，因此是更稳妥的方案。

`APPEND_MOBILE_UA_TOKEN`（`common/WebViewport.ets`）保留了兜底开关，默认关闭：
只有在实测发现「已经显式注入 `width=<窗口宽度>`，`clientW` 却仍不等于窗口宽度」时
（即内核对显式宽度也不认）才需要打开，代价是站点会改发移动端页面，
平板/2in1 全屏这种本来正常的场景会跟着退化。

### 为什么不使用 layoutMode(FIT_CONTENT)

SDK 注释明确写了它的两条限制：**「Width adaptation is not supported. Only height adaptation
is supported.」**（不支持宽度自适应），以及「Frequent changes to the page width and height
will trigger a re-layout」（尺寸频繁变化会触发重布局）—— 既解决不了宽度问题，又恰好命中
自由多窗拖拽的场景。

### 各窗口形态的预期

| 形态 | 修复前 | 本方案 |
|------|--------|--------|
| 手机全屏 | 正常（UA 含 Mobile，viewport 生效；窗口=屏幕） | 无变化（`width=<窗口宽>` 与 `device-width` 等值） |
| 手机悬浮窗 | 窗口窄于屏幕 → 同样会缩小 | 按窗口宽排版，恢复正常尺寸 |
| 平板全屏 | 看起来正常（窗口=屏幕，掩盖了第二层问题） | 无变化 |
| 平板悬浮窗 | **异常**：UI 整体缩小 | 已修复，按窗口宽排版 |
| 平板自由多窗 | **异常**，且宽度连续变化 | 已修复；宽度变化时防抖重注入，不重载页面 |
| 2in1 / PC 模式 | 系统**不支持** viewport，走桌面式布局 | 注入的 viewport meta 会被内核忽略（无害）；桌面式布局本就跟随窗口宽度，另靠 resize 通知唤醒只读一次的 SPA |

> **已实机验证**（MatePad 11.5 / HarmonyOS 7.0.0，自由多窗，窗口 768×539 CSS px）：
> 注入 `width=768` 后探针 `clientW` 由 **1319** 变为 **768**，页面恢复 100% 尺寸并铺满窗口，
> 站点据此切到窄屏（无侧边栏）布局，每次启动都稳定复现。
> 点击输入框仍能正常唤起软键盘（`DISABLE_AUTO_KEYBOARD_ON_ACTIVE` 只拦「激活状态切换」
> 触发的键盘，不影响聚焦输入框这一路）；键盘弹出时窗口收缩、网页同步重排，
> 实测输入框约 **53 CSS px** 而可视区约 **389 CSS px**，
> 深度思考 / 智能搜索工具栏完整可见、输入区与发送按钮之间无空白横条。

### 为什么全屏下内容看起来「变小了」——正常，不是缺陷

把窗口最大化后，布局视口从窗口宽度（例如 768）变成整屏宽度（例如 1319 CSS px），
站点据此切到它的**宽屏布局**：对话区与输入区是一个固定 `max-width`（实测约 768 CSS px，
即站点的 `48rem`）并**居中**的列，于是屏幕上约 42% 的宽度成了两侧留白。
看起来像「内容变小了」，但**页面本身并没有被缩小**。

同一台设备、同一坐标系的实测：

| 量 | 自由多窗 | 全屏 |
|----|----------|------|
| 注入的布局视口宽度 | 768 | 1319（= 2456 ÷ dpr 1.8625） |
| 问候语字形的物理高度 | 45 px | **45 px（完全相同）** |
| `visualViewport.scale` | 1 | 1 |

两态的**字形物理尺寸完全一致**，说明页面始终按 1:1 渲染；差别只在排版宽度（站点自己的
响应式断点）以及由此产生的居中留白。另外站点本身用 `minimum-scale=1.0` / `maximum-scale=1`
把缩放钉死了，所以页面**不可能**被缩放：万一注入的宽度与窗口宽度不符，表现也只会是
横向留白或横向滚动，而不会变成「整体缩小」。反过来说，可以用「居中列两侧留白是否相等」
来反证注入宽度是对的（实测两侧相等）。

> 如果记得「以前全屏下字更大」，那是修复前的状态：网页的 viewport 声明没被内核解析，
> 内核退回默认约 980 CSS px 的布局视口并**整体拉伸铺满窗口** ——
> 全屏下相当于放大 1319/980 ≈ 1.35 倍，自由多窗下反而缩小到 768/980 ≈ 0.78 倍
> （这正是当初「自由多窗 UI 较小」的成因）。所以现在的变化不是「变小」，
> 而是从「被拉伸」回到了 1:1 的忠实渲染。
>
> 若确实希望全屏下内容更「大」，可选的官方手段只有两个，且都属于**有意偏离忠实渲染**：
> `WebAttribute.textZoomRatio()`（只放大文字，不动布局）与 `WebAttribute.initialScale()`
> （整体缩放，但站点把 `minimum-scale`/`maximum-scale` 钉在 1 上，需要在注入的 meta 里
> 一并覆盖才能生效，代价是会放开站点的缩放锁、允许双指缩放）。
> 两者默认都不启用。

### 实机验证方法

启动应用后过滤日志即可拿到探针数据：

```powershell
& $hdc shell hilog -x | Select-String 'Viewport probe'
```

判定标准 —— **看注入后的布局视口宽度是否等于窗口宽度**：

| 观察 | 结论 |
|------|------|
| `Viewport fix: "ok:...width=<N>"` 里的 `N` ≈ 当前窗口宽度（vp） | 注入成功 |
| `Viewport fix: "no-head"` | 注入时机早于 `document.head`，会在下一次时机重试；若一直只有 `no-head` 说明页面结构特殊 |
| `Viewport fix: "error"` + 探针 `viewportMeta=null` | 页面没有 viewport 声明，走的是兜底补写分支 |
| 探针 `clientW` ≈ 日志里的 `width=` | **布局视口 = 窗口宽度，方案奏效** |
| 探针 `clientW` 明显大于窗口宽度（例如窗口 768 而 `clientW`=1319） | 宽度注入未生效，页面仍按**屏幕**宽度排版并整体缩小 |

最后一行就是「自由多窗下 UI 变小」的判据，可以直接用来回归。
注意 `dpr` 会随**系统显示设置 / 窗口形态**变化（本项目在不同时间实测到 2.2 与 1.8625
两种值），所以**不要用固定的「屏幕宽 ÷ dpr」去心算窗口宽度**，
直接比对探针 `clientW` 与日志里的 `width=` 即可。当前配置下的实测基准：
全屏（窗口 2456 px）日志为 `width=1319`（= 2456 ÷ 1.8625，说明该形态下窗口密度同样是
1.8625，即 1 vp = 1 CSS px）；自由多窗（窗口约 1430 px）为 `width=768`
（1430 ÷ 1.8625 ≈ 768）。两种形态下 `clientW` 都应等于该 `width=`。

窗口尺寸变化时同样会打 `Viewport fix:`（`onAreaChange` → 防抖 260ms → 重新注入），
拖拽窗口后若这条日志里的 `width=` 跟着变，说明自适应链路是通的。

日志里还会带 `composer`（输入框的标签、高度、class、父节点 class），
如果高度上限没命中，可据此写出更精确的 CSS 选择器。

## 软键盘与输入焦点

### 现象

点击聊天里的图片会莫名弹出软键盘。

### 两条成因路径

**路径一：内核基于「残留焦点」自动弹键盘。** 两个默认值叠加造成：

- `BlurOnKeyboardHideMode` 默认 `SILENT` —— **键盘收起时输入框仍持有焦点**；
- `WebSoftKeyboardBehaviorMode` 默认 `DEFAULT` —— Web 组件获得/失去焦点、或激活状态
  在 inactive/active 之间切换时，系统会**自动隐藏或显示**软键盘。

于是：键盘收起后输入框仍是焦点元素 → 点图片使 Web 组件的焦点/激活状态变化 →
系统按自动策略又为那个仍然聚焦的输入框把键盘弹回来。

**路径二：网页自己把焦点移回输入框。** 例如把「点击输入区任意位置都聚焦输入框」的
处理器挂在了包含图片预览的容器上，点图片冒泡上去就把输入框聚焦了。内核无法区分
这次聚焦是不是用户本意。

### 采用的手段

| 手段 | 对应路径 | API 版本 |
|------|----------|----------|
| `.blurOnKeyboardHideMode(BlurOnKeyboardHideMode.BLUR)` | 路径一：键盘收起时让输入框失焦、焦点回到 body，从机制上消除残留焦点 | 14 |
| `controller.setSoftKeyboardBehaviorMode(DISABLE_AUTO_KEYBOARD_ON_ACTIVE)` | 路径一：关掉内核的自动软键盘策略，键盘只在明确点到可输入元素时出现 | 22 |
| 注入焦点防护脚本（`common/WebInputGuard.ets`） | 路径二：只在「用户刚点了图片」时抑制随后落到输入框上的焦点 | — |
| 注入 CSS 高度上限（`textarea / [contenteditable]` 最高 32vh 并内部滚动） | 长文本时输入框不再无限向上扩张 | — |

> `setSoftKeyboardBehaviorMode` 必须在控制器挂载后调用，否则抛 `17100001`
>（未与 Web 组件关联），因此放在 `onControllerAttached` 里。

### 输入框高度上限：由实时可视高度算出，保证短于可显示区域

**目标**：键盘弹出时，输入框必须短于当前可显示区域。

只写一个固定 `vh` 值做不到硬保证 —— 它默认 `vh` 的基准正确；键盘若以浮层方式覆盖，
`vh` 仍按整窗高度算，算出的上限可能反而大于可视区。因此改为**由脚本按实时可视高度算像素上限**：

```js
可视高度 = min(documentElement.clientHeight, visualViewport.height)
上限     = clamp(48px, 可视高度 × 0.28, 160px)   // 写入 CSS 变量 --ds-composer-max
```

样式规则取用该变量，并保留 `32vh` 兜底（脚本没跑时也不会完全放开）：

```css
textarea,[contenteditable="true"]{max-height:var(--ds-composer-max,32vh) !important;overflow-y:auto !important;}
```

脚本同时监听 `window.resize` 与 `visualViewport.resize`（键盘为浮层时可能只触发后者），
因此键盘弹出/收起都会重算，**始终跟随当前可视区**；幂等安装，不会重复叠加监听器。

**由此得到的保证**：只要可视高度 ≥ 171 CSS px（= 下限 48px ÷ 0.28），
输入框上限就 ≤ 可视高度的 28%，必然短于可显示区域。该公式由纯函数
`computeComposerCapPx()` 承载，并有单测直接断言「对一组可视高度，算出的上限都严格小于该高度」。

#### 实机验证（平板横屏 2456×1600，键盘弹出）

> 下表是**当次显示设置**下的测量，`dpr` 为 2.2；`dpr` 会随系统显示设置变化
> （另一次实测为 1.8625），但结论（输入框占比命中 28% 上限）与 `dpr` 无关。

| 量 | 实测值 |
|----|--------|
| 可显示区域（键盘之上的应用窗口） | `[0,86][2456,860]` → 774 px = **352 CSS px** |
| 输入框高度 | `[377,225][2081,444]` → 219 px = **100 CSS px** |
| 占比 | **28.4%**（正好命中 28% 上限）|

#### 大片空白与工具栏消失：根因与修法

加上高度上限后出现两个现象：**文字与工具栏之间有大片空白**、**工具栏（深度思考 / 智能搜索 /
发送按钮）从可视区消失**。运行时 DOM 快照（探针的 `ancestors` / `parentKids`）给出了根因：

```
TEXTAREA                        h=99     ← 已被上限压住
DIV（直接父）                    h=336    ← 多出的 237px 就是那片空白
  ├ DIV.ds-scroll-area__gutters h=336    ← 兄弟元素，撑高了父容器
  ├ TEXTAREA                    h=99
  └ DIV.b13855df                h=336    ← 兄弟元素，撑高了父容器
DIV（flex）                      h=394
DIV（overflow:hidden，卡片）      h=400    ← 比可视区(353)还高，把底部工具栏裁掉
chipTextInDom: true                      ← 工具栏一直在 DOM 里，只是被裁掉了
```

关键点：**父容器的 336px 来自它的子元素**，所以只给父容器写 `height:auto` 是没用的
（实测 `:has()` 规则匹配成功，但祖先高度一格未变）。页面把「输入框未封顶时算出的高度」
同时写在了直接父**和那两个兄弟元素**上，必须一并限制：

```css
div:has(> textarea){height:auto !important;min-height:0 !important;flex:0 0 auto !important;}
div:has(> textarea) > *{max-height:var(--ds-composer-max,32vh) !important;}
```

修完实测（同一场景：键盘弹出、可视高度 353 CSS px、输入框内容 1680 字）：

| 量 | 修前 | 修后 |
|----|------|------|
| 直接父容器 | 336 px | **99 px** |
| composer 卡片 | 400 px（**超出**可视区 353） | **163 px** |
| 工具栏在 UI 树中 | 0 | **2 条建议 + 2 个按钮** |

用 `:has()` 而不是页面的哈希类名：哈希随站点构建而变，`div:has(> textarea)` 只依赖结构；
`:has()` 自 Chromium 105 起支持，本设备为 144。

> 能定位到这一步靠的是探针里的 `ancestors`（祖先链高度/溢出）与 `parentKids`
> （输入框各兄弟节点的高度）——「父容器高度来自子元素」这一点，只有看到兄弟节点高度才能确定。
> 另外 `chipTextInDom` 把「工具栏被裁掉」与「被页面移除」区分开，避免了往错误方向排查。

### 防护脚本的防误伤设计

这个脚本会主动 `blur()` 输入框，所以边界必须收紧：

1. **只认图片类目标**（`IMG` / `PICTURE` / `FIGURE` 及其向上 4 层祖先）。点发送按钮
   （通常是 `svg` / `button`）、点加号、点输入框本身都不受影响 —— 「发送后网页把焦点
   移回输入框」这种正常行为因此不会被破坏；
2. **每次点击最多抑制一次**：先清标记再 `blur()`，即便网页在 blur 后又把焦点抢回来，
   也不会形成「blur → 网页抢焦点 → 再 blur」的死循环；
3. **标记 600ms 自动过期**，避免一次点击的影响泄漏到后续操作；
4. 监听器挂在**捕获阶段**，因为页面的处理器可能在冒泡阶段抢焦点。

若实机发现它误伤了某个正常交互，把 `common/WebInputGuard.ets` 里的
`ENABLE_IMAGE_TAP_FOCUS_GUARD` 改为 `false` 即可单独关掉它，内核侧那两个开关仍然生效。

### 实机验证

```powershell
& $hdc shell hilog -x | Select-String 'Focus guard|Viewport probe'
```

- `Focus guard: installed` → 防护脚本注入成功；
- probe 里的 `active` 字段给出**当前持有焦点的元素**，用于区分上面两条路径：
  若 `active.editable` 长期为 `true`，说明是残留焦点引发的（路径一）；
- 手动步骤：点开输入框 → 收起键盘 → 点一张图片，观察键盘是否还会弹出。

## 返回手势（侧滑返回 / 返回键）

侧滑返回与返回键走的是同一个 `onBackPress`。它不再「一律等于网页后退」，而是按当前
所在界面分流：

| 当前界面 | 返回行为 |
|----------|----------|
| **网页自己的弹层**（设置弹窗、分享面板…） | **交给网页后退**：它打开时 push 的那条历史正是为「返回关弹层」准备的 |
| **对话界面**（聊天主站根级页面：首页 `/`、会话页 `/a/chat/s/<id>`），且没有网页弹层 | **不执行网页后退**。第一次弹「再按一次返回桌面」，`2s` 内再按一次才真正返回桌面 |
| **二三级界面**（站内其他页面：`/sign_in`、`/share/…`、`/download-app` 等） | **保持原样**：网页还有历史就照旧后退 |
| 网页已退无可退（没有任何历史） | 也给一次「再按一次」确认，避免一次误触直接退出 |
| 应用自己的弹层开着（上传方式选择 / 设置面板） | 优先关掉自己的弹层 |

判定顺序就是上表顺序：**自己的弹层 → 网页弹层 → 对话界面 → 二三级界面 → 退无可退**。

### 为什么「网页弹层」要单独判一层

这是本次修的关键。只有 `canGoBack` 一个信号时，实现会写成「对话界面一律不后退」，
于是**打开设置弹窗后返回关不掉弹窗**，反而弹出「再按一次返回桌面」—— 而弹窗是网页自己
的界面，用户期望返回先关它。但也不能简单地改成「有历史就后退」，因为实测两者在
历史长度上**完全一样**：

| 状态 | `histLen` | `canGoBack` | 期望的返回行为 |
|------|-----------|-------------|----------------|
| 切换到某个历史会话 | 1 → **2** | false → **true** | 对话界面 → 再按一次返回桌面 |
| 打开「系统设置」弹窗 | 1 → **2** | false → **true** | 关掉弹窗 |

`canGoBack` 区分不了这两者，**只有 DOM 能区分**：实测弹窗打开时
`role="dialog"` 与 `aria-modal="true"` 的可见元素由 0 变 1。因此
`common/WebViewport.buildOverlayProbeScript()` 按这两个标记探测弹层，
再把结果并进返回决策（`webOverlayOpen`）。

### 为什么返回决策是异步的

`onBackPress` 必须**同步**返回，而查网页弹层只能走 `runJavaScript`（异步）。
因此 `onBackPress` **固定消费事件**，把决策放到 `dispatchBackDecision()` 里在几十毫秒内完成。
两个后果都处理了：

- 「退出到桌面」不能再用 `return false`，改为主动 `terminateSelf()`；
- 加了 **500ms 兜底超时**：DOM 查询万一不回来就按「没有弹层」继续决策 ——
  返回键是主导航手段，不能因为一次异步失败而失灵。另外决策未完成前的重复按下会被忽略，
  避免一次连击被算成两次动作。

### 为什么对话界面要屏蔽网页后退

改造前侧滑返回一律是 `controller.backward()`，在对话界面上会得到两个反直觉的结果：
刚登录完还能后退回登录页；在会话里侧滑会被带到上一个会话，而不是像其他应用那样退出。
用户对「返回」的预期是「退出当前应用层级」，而网页自己的历史对用户是不可见的 ——
让他去猜「这一下会退到哪个网页」没有意义。

### 实现分工

| 位置 | 职责 | 测试层级 |
|------|------|----------|
| `common/UrlRules.ets` → `isChatRootPage()` | URL → 「是不是对话界面」 | **设备侧**（依赖 `@kit.ArkTS` 的 URL 解析） |
| `common/WebViewport.ets` → `buildOverlayProbeScript()` / `isOverlayOpenResult()` | DOM → 「网页弹层是否开着」 | **宿主机**（纯字符串拼装与返回值解析） |
| `common/BackPolicy.ets` → `decideBackAction()` | 上面两者 + 有无历史 + 是否有自己的弹层 → 四种动作之一 | **宿主机**（不依赖任何系统 API） |
| `pages/Index.ets` | `onBackPress()` 消费事件 → 异步查弹层 → 按决策执行；`lastExitPromptAt` 记录提示时间，`terminateSelf()` 退出 | 实机 |

四个动作：`dismiss-modal`（关自己的弹层）、`web-back`（网页后退）、
`prompt-exit`（弹提示并记时间）、`exit-now`（`terminateSelf()` 回桌面）。

> URL 解析与判定逻辑特意**分成两个模块**：`url.URL.parseURL` 在宿主机测试环境不可用
> （每次调用都抛异常），一旦把两者写在一起，`decideBackAction` 的断言会整体失真 ——
> 这正是本次开发中实际踩到的坑，分开之后判定逻辑才真正可在宿主机上快速回归。

### 设计取舍

- **失败方向一致地保守**：URL 解析失败、拿不到地址、弹层探测失败 —— 一律按
  「没有弹层 / 不是对话界面」处理，回落到改动前的「网页后退」行为。宁可少生效，
  也不要把用户困在一个退不出去的页面上。
- **前缀匹配必须带分隔符**：`/a/chatx`、`/a/chats` 不会被误判成 `/a/chat` 之下（有单测钉住）。
- **弹层只认 `role="dialog"` / `aria-modal`**：实测 DeepSeek 的设置弹窗带这两个标记，
  而账号行弹出的**菜单**两个都没有（它也不 push 历史）。菜单不在此规则内 ——
  那种状态下返回手势走「对话界面」分支（先提示再退出），比改动前「直接退出应用」更安全。
- 提示时长与确认窗口取自同一个常量 `EXIT_CONFIRM_WINDOW_MS`，提示消失即窗口结束。

### 实机验证

侧滑手势本身无法用 `uitest` 注入，但**返回键**可以，而两者都走 `onBackPress`：

```powershell
& $hdc shell "uitest uiInput keyEvent 2"      # 返回键
& $hdc shell "uitest uiInput keyEvent 2; sleep 1; uitest uiInput keyEvent 2"   # 连按两次
& $hdc shell hilog -x | Select-String 'Back action'
```

日志里会打出每次决策（含 `overlay` / `canGoBack` / `onChatRoot`），可直接核对分支
（下面是真机实测输出）：

| 操作 | 日志 | 结果 |
|------|------|------|
| 打开「系统设置」弹窗后按一次 | `web-back (overlay=true canGoBack=true onChatRoot=true)` | **弹窗关闭，应用留在原界面**（截图已确认） |
| 对话界面（无弹层）按一次 | `prompt-exit (overlay=false canGoBack=false onChatRoot=true)` | 弹「再按一次返回桌面」，**应用不退出** |
| 同上，`1s` 后再按一次 | `exit-now (overlay=false canGoBack=false onChatRoot=true)` + `Exit to desktop` | 回到桌面（截图确认已到桌面） |
| 同上，间隔 `2.4s` 再按 | `prompt-exit` | 窗口已过，**重新提示**而不是直接退出 |
| 深链到站内二三级界面（`/share/test123`）后按一次 | `web-back (overlay=false canGoBack=true onChatRoot=false)` | **网页后退，与改动前一致** |
| 深链到无历史的站内页面（`/sign_in`）按一次 | `prompt-exit (canGoBack=false)` | 退无可退 → 仍先确认 |

> 注意 `hdc shell hilog` 会**先把缓冲区里的历史日志整段吐出来**，再开始跟随新日志 ——
> 上面的判定必须按**时间戳**对齐刚做的操作，否则会把上一轮运行留下的
> `Back action` 行当成新事件（本次开发中就一度被它误导）。

## 已知限制

| 限制 | 说明 |
|------|------|
| 浏览器深链不唤醒 | `chat.deepseek.com` 非自有域名，无法托管 AGC 域名校验文件，故浏览器里点同域链接不会唤起本应用（从其他 App / 扫码仍可） |
| base 资源为简体中文 | 资源目录为 `base`(简中) / `en` / `en_US` / `ru` / `zh_HK`。德语、法语、日语等**未覆盖**的系统语言会回退到 `base`，即显示简体中文。若需完整国际化，应把 `base` 改为英文、简体中文迁到 `zh_CN` |
| 不创建新窗口 | 单 Web 组件架构，`window.open` 不另开窗口：站内地址在当前 Web 内导航，站外地址转系统浏览器 |

## 开发与优化

本复刻版本的**优化与开发由 DeepSeek Harness 完成**。最近一轮修复与改进：

**功能缺陷**

- 页面加载超时（15s）后即使网页最终加载成功，错误页也不会消失 —— `onPageEnd` 未复位错误态
- 网络可达但主框架加载失败（DNS 解析失败、连接被重置、服务端不可用）时错误被静默吞掉，用户只能干等 15s
- 刷新失败降级时直接回首页，会丢掉正在进行的会话
- 下载文件名直接取自 `Content-Disposition`，未净化，存在路径穿越与非法字符风险
- 下载中转目录从未创建、中转文件从不删除，沙箱持续堆积副本
- `windowStage.loadContent` 回调未判空，`err` 为 undefined 时会抛异常并跳过窗口初始化
- 上传框打开后直接销毁页面时，`onShowFileSelector` 存下的回调闭包一直持有 Web 侧事件结果
- 错误页成因未区分：只修「超时后成功加载仍显示错误页」会让 HTTP 4xx/5xx 的错误页
  被 `onPageEnd` 一并清掉、变成一闪而过（已用 `errorFromTimeout` 区分暂时性 / 确定性失败）

**官方规范对齐**

- 新增 `onPermissionRequest`：语音输入走完整两步链路（系统权限申请 + 应用内确认弹窗）
- 新增 `onSslErrorEventReceive`：证书错误一律取消，不做静默放行
- 新增 `onWindowNew`：站内地址当前页导航、站外转系统浏览器，并显式释放渲染流程
- User-Agent 版本号改为运行时从 `bundleManager` 读取（原先写死 `1.0`，与 versionName 脱节）
- 图标按钮补齐无障碍朗读文案，触摸目标提升到 44vp，字形字符改用系统符号
- 新增 `en` 语言目录，覆盖 `en-GB` / `en-AU` 等英语变体

**多形态窗口适配与软键盘**（细节见「窗口形态与网页布局适配」「软键盘与输入焦点」两节）

- 定位到「自由多窗 / 悬浮窗下 UI 整体变小」的真正成因是**第二层**：
  `.metaViewport(true)` 只让网页的 viewport 声明重新被解析，而 Chromium 的 `device-width`
  取的是**屏幕**宽度而非窗口宽度 —— 窄窗下页面按整屏宽排版再整体缩小
  （实测布局视口 1319 CSS px、窗口仅 768 CSS px，显示比例约 58%）。
  修法是在 `onPageEnd` 与窗口尺寸变化时，把网页 viewport 的 `width=` 段改写成**窗口宽度（vp）**
- 新增 `common/WebViewport.ets`：UA 拼装、viewport 修正脚本、resize 通知脚本、
  运行时诊断脚本，以及输入框上限的纯函数 `computeComposerCapPx`
- 新增 `common/WebInputGuard.ets`：点图片不再让输入框获得焦点
  （捕获阶段拦截 + 600ms TTL + 幂等安装）
- 输入框上限改由脚本按**实时可视高度**算出像素值写入 CSS 变量，并同时约束
  「直接父容器及其子元素」—— 修掉长文本把输入框顶到无限高，以及由此产生的
  「输入区与发送按钮之间大片空白、底部工具栏被裁掉」
- 键盘对齐两条官方手段：`setSoftKeyboardBehaviorMode(DISABLE_AUTO_KEYBOARD_ON_ACTIVE)`
  （只拦「激活状态切换」触发的键盘，不影响聚焦输入框这一路）与 `blurOnKeyboardHideMode(BLUR)`

**返回手势**（细节见「返回手势（侧滑返回 / 返回键）」一节）

- 侧滑返回原先一律等于网页后退：在对话界面上会「刚登录完又退回登录页」、
  「在会话里被带到上一个会话」。现改为按界面分流 —— 网页自己的弹层交给网页关、
  对话界面提示「再按一次返回桌面」、二三级界面保持网页后退
- **网页弹层必须用 DOM 判、不能用 `canGoBack` 判**：实测「切换历史会话」与
  「打开设置弹窗」都让 `histLen` 1→2、`canGoBack` 变 true，两者期望的返回行为却相反；
  只有 `role="dialog"` / `aria-modal` 能区分（实测 0→1）。新增
  `WebViewport.buildOverlayProbeScript()` 探测，`BackPolicy` 据此把返回让给网页
- 因为查 DOM 只能异步，而 `onBackPress` 必须同步返回：改为**固定消费事件 + 异步决策**，
  并补 500ms 兜底超时（异步失败时按「无弹层」继续决策，返回键不会失灵），
  「退出到桌面」随之从 `return false` 改为 `terminateSelf()`
- 新增 `common/BackPolicy.ets`（返回决策，**不依赖系统 API**，宿主机单测）与
  `UrlRules.isChatRootPage()`（对话界面判定，依赖 `@kit.ArkTS` 的 URL 解析，设备侧单测）。
  两者刻意分开：`url.URL.parseURL` 在宿主机不可用，混在一起会让判定逻辑的断言整体失真
- probe 新增 `histLen` 与 `overlay` 诊断字段，`Back action` 日志会打出
  `overlay / canGoBack / onChatRoot` 三个判定输入，便于按日志回归

**工程整理**

- 新增 `common/DownloadFiles.ets`（下载文件名净化与清理）与 `common/AppPermissions.ets`（权限申请）
- `UrlRules` 新增 `isChatHost`，消掉两处重复的 host 判定
- 分享 scheme 前缀、UA 标识收进 `AppConfig`
- 新增本地单元测试 `entry/src/test/DownloadFiles.test.ets`（10 例），`hvigorw test` 共 18 例全绿
- 移除 3 个确认无引用的死资源：`text_body`、`drag_indicator_bg`，以及只剩死资源的 `float.json`
- 拆出 `components/SettingsSheet.ets`、`components/UploadSheet.ets`、`components/FloatingBar.ets`
  三个组件（`Index.ets` 1775 → 1332 行）。`FloatingBar` 把拖拽状态、边界限制与位置持久化
  一并下沉，拖动时不再连带重算包含 Web 组件的整个页面

  > `FloatingBar` 的根节点是撑满全屏的 Stack（提示气泡与操作条原本是页面 Stack 的两个
  > 平级绝对定位子节点，收进组件后需要同尺寸的参照系）。**它必须带
  > `hitTestBehavior(HitTestMode.None)`** —— 否则这个全屏容器会吞掉落在空白处的触摸，
  > 表现为「整个网页点不动、划不动」。改动此处后务必回归「点击网页元素是否仍有效」。

## 版本

`dev.cyotatsu.deepseek.oh` — v1.1.4.3 (1001043)

`versionCode` 的编码规则（沿用历史值）：`主版本×1000000 + 次版本×10000 + 修订×10 + 构建`，
例如 `1.1.4.2 → 1001042`、`1.1.4.3 → 1001043`。**发版时只需在
`AppScope/app.json5` 里同时改 `versionName` 与 `versionCode`**（User-Agent 里的版本号
是运行时从 `bundleManager` 读的，不需要另改）。

## License

本项目以 **MIT License** 发布，详见 [LICENSE](./LICENSE)。

原项目版权：Copyright (c) 2026 Sakura Neko

原项目的版权声明与许可条款已完整保留。在此基础上新增的修改同样以 MIT 许可发布。
