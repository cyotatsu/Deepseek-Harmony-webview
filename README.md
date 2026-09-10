# DeepSeek for HarmonyOS

<p align="center">
  <img src="assets/app_icon.png" width="160" alt="DeepSeek for HarmonyOS">
</p>

基于 HarmonyOS WebView 封装的 DeepSeek 客户端，支持手机、平板和 2in1。

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

## 更新与优化内容

### 修复

| 问题 | 说明 |
|------|------|
| **平板自由多窗下窗口无法拖动** | 原实现无条件隐藏系统标题栏（`setWindowDecorVisible(false)`）。SDK 说明指出：标题栏隐藏后，主窗口进入全屏时**只有鼠标光标悬停热区**才会浮出标题栏 —— 触屏没有悬停，于是自由多窗下既没有应用标识、也没有拖动入口。应用市场、设置等系统应用从不隐藏该标题栏，所以能正常显示与拖动。现改为**按窗口模式决定显隐**：自由多窗下保留系统标题栏（含图标、应用名与窗口控制按钮，并可拖动），其余形态维持隐藏以保持沉浸 |
| **冷启动分享链接 100% 失效** | `onPageShow` 早于 Web 的 `onControllerAttached` 约 35ms，此刻 `loadUrl` 必抛「必须关联 Web 组件」，而调用方随后无条件清空 `deepLinkUrl`，链接就此丢失。现改为把冷启动 DeepLink 直接作为 Web 的**初始 `src`**，从根上避开竞态 |
| **拍照上传后临时文件不清理** | 预创建的文件只在用户取消时删除，上传成功后永久留在 `filesDir`，而文件名是无前缀的 `<时间戳>.jpg`，事后无法安全识别。现改为加 `ds_photo_` 前缀，并在应用启动时回收（此刻不可能有上传在进行） |
| **图标显示异常** | 原实现用 Nerd Font 私有区字符（`U+F0xxx`）作图标，HarmonyOS 系统字体不含这些字形，真机上会显示为空白或豆腐块。已改用系统符号资源 `sys.symbol.*` |
| **繁体中文被当作简体** | 语言标识规范化会丢弃 script 子标签，导致 `zh-Hant` 与 `zh-Hans` 都退化成 `zh`。已修复，繁体（zh-HK / zh-Hant）不再被按简体处理 |
| **下载提示误导** | 原先点下载立刻弹「下载完成」，但此时文件仅在应用沙箱内；用户取消保存对话框后仍会看到该提示。现已改为保存成功后才提示，并移除失效的 `newFileNames` 赋值 |
| **2in1 状态栏调用无效** | `setWindowSystemBarProperties` 在 2in1 上不生效，原实现无条件调用；现按设备形态跳过，并修正了在平板上误报 `2in1:` 前缀的日志 |

### 优化

| 项目 | 说明 |
|------|------|
| **配色改用资源限定词** | 建立 `resources/base\|dark/element/color.json` 共 18 个语义化颜色，`build()` 中 19 处深浅色三元表达式全部消除。**切换深浅色不再触发整页重绘** |
| **逻辑外提** | ArkTS 纯逻辑（BCP 47 规范化、URL 判定、常量）从页面外提到 `common/`，这些函数因此可被单元测试覆盖 |
| **组件抽取** | 顶部进度条与错误页抽为独立 `@Component`，状态变化时只重绘受影响的部分 |
| **单元测试** | 本地（宿主）8 条 + 设备侧 10 条，覆盖语言规范化与 URL 判定 |
| **图标与闪屏** | 应用图标与启动闪屏统一更新 |

## 功能

| 功能 | 说明 |
|------|------|
| 🌐 WebView | 内嵌 chat.deepseek.com，完整对话体验 |
| 🌍 系统语言 | 跟随系统语言注入 WebView，支持动态切换 |
| 🔗 Deep Link | 冷/温/热启动接收分享链接并导航 |
| 🌙 深色模式 | 跟随系统自动切换 |
| 📤 文件上传 | 拍照 / 相册 / 文档选择器 |
| 💾 文件下载 | WebView 下载转存至公共下载目录 |
| 📲 系统分享 | 拦截分享链接，唤起系统分享面板 |
| 🔄 稳定性 | 渲染崩溃自动刷新 + 15s 超时错误页 |

## 窗口形态适配

应用在手机上全屏运行，在平板 / 2in1 上还可能是**悬浮窗**或**自由多窗**。注意「窗口模式」与「是否全屏」是**两条正交的轴**，必须分别判断：

| 判断维度 | API |
|---------|-----|
| 窗口模式 | `Window.isInFreeWindowMode()`（自由多窗 / 悬浮窗），变化用 `on('freeWindowModeChange')` 订阅 |
| 是否全屏 | `WindowStatusType` —— `FULL_SCREEN` 与 `MAXIMIZE` 都表示「占据整个屏幕」 |

系统标题栏的显隐据此决定：

| 窗口模式 | 顶部表现 |
|---------|---------|
| **悬浮窗**（含平板正常使用时的全屏） | 隐藏系统标题栏，内容区接管整个窗口，保持沉浸 |
| **自由多窗** | **保留系统标题栏** —— 它是触摸设备上移动窗口的唯一入口，也让应用与系统应用表现一致 |

> **两条平台边界，未做（非实现问题）：**
>
> - 自由多窗 · 全屏下**隐藏**标题栏：SDK 明确 `MAXIMIZE` 状态下「dock、状态栏和标题栏无需悬停即显示」，应用无法隐藏
> - 通过**触摸下拉**浮出标题栏：官方浮出机制基于「鼠标光标悬停标题栏热区」，触屏没有悬停
>
> 这两条若强行实现，只能自绘系统窗口部件，不符合官方窗口界面规范，故放弃。

## 项目结构

```
entry/src/main/ets/
├── common/                          纯逻辑与常量（不依赖组件，可独立测试）
│   ├── AppConfig.ets                DEEPSEEK_URL / DEEPSEEK_HOST
│   ├── LanguageUtil.ets             BCP 47 语言标识规范化
│   ├── UrlRules.ets                 同域判断 / 下载链接判定
│   └── AllowedFileExtensions.ets    上传后缀白名单
├── components/                      展示型组件
│   ├── PageProgress.ets             顶部加载进度条
│   └── ErrorView.ets                网络异常 / 加载失败页
├── entryability/EntryAbility.ets    窗口沉浸 + Deep Link + 系统语言初始化
└── pages/Index.ets                  WebView 主页面
```

## 测试

```powershell
# 本地（宿主）单元测试：common/LanguageUtil 的 BCP 47 规范化
hvigorw test --no-daemon
# 结果：entry/.test/default/intermediates/test/coverage_data/test_result.txt

# 设备侧单元测试：common/UrlRules 的同域与下载链接判定
# 这两个函数依赖 @kit.ArkTS 的 url.URL.parseURL，该 API 在宿主测试环境不可用，
# 调用会一律抛异常落入 catch 分支，因此必须放到设备上运行。
hvigorw assembleHap --mode module -p module=entry@ohosTest -p product=default
hdc install entry/build/default/outputs/default/entry-default-signed.hap
hdc install entry/build/default/outputs/ohosTest/entry-ohosTest-signed.hap
hdc shell aa test -b dev.cyotatsu.deepseek.oh -m entry_test `
    -s unittest OpenHarmonyTestRunner -s timeout 60000
```

## Deep Link

支持从其他 App / 短信 / 扫码打开 `https://chat.deepseek.com/share/...` 分享链接。

> **浏览器中点击同域链接不会唤醒应用**，原因：`chat.deepseek.com` 非自有域名，无法托管 AGC 域名校验文件。

## 构建

| 要求 | 版本 |
|------|------|
| DevEco Studio | 6.0+ |
| HarmonyOS SDK | API 23+ |
| 权限 | ohos.permission.INTERNET, ohos.permission.GET_NETWORK_INFO |

## 开发与优化

本复刻版本的**优化与开发由 DeepSeek Harness 完成**。

## 版本

`dev.cyotatsu.deepseek.oh` — v1.1.4.1 (1001041)

## License

本项目以 **MIT License** 发布，详见 [LICENSE](./LICENSE)。

原项目版权：Copyright (c) 2026 Sakura Neko

原项目的版权声明与许可条款已完整保留。在此基础上新增的修改同样以 MIT 许可发布。
