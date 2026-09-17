# DeepSeek for HarmonyOS

<p align="center">
  <img src="assets/app_icon.png" width="160" alt="DeepSeek for HarmonyOS">
</p>

基于 HarmonyOS WebView 封装的 DeepSeek 鸿蒙客户端，支持手机、平板和 2in1。

---

## ⚠️ 使用须知

> **本项目仅供鸿蒙（HarmonyOS / ArkTS）应用开发交流与学习使用。**
>
> **请通过官方途径使用 DeepSeek** —— 官方网站 <https://chat.deepseek.com>，或各应用商店中的官方 App。
> 本项目**不是**官方客户端，不提供任何官方保证。
>
> 本应用只是把 DeepSeek 网页装进 WebView 容器：账号与对话内容均由官方站点处理，
> 适用官方的隐私政策。使用本项目产生的任何后果由使用者自行承担。

> **复刻说明**：本项目 fork 自 [SakuraNeko/Deepseek-Harmony](https://github.com/SakuraNeko/Deepseek-Harmony)，
> 在原项目基础上继续完善。原作者 **Sakura Neko**（MIT 许可，详见 [LICENSE](./LICENSE)）。
> 本项目与 DeepSeek 官方无任何关联；DeepSeek 名称及相关标识归其权利人所有。

## 功能

| 功能 | 说明 |
|------|------|
| 🌐 WebView | 内嵌 chat.deepseek.com，完整对话体验 |
| 🖥️ 多形态窗口 | 全屏 / 悬浮窗 / 自由多窗下网页布局自动跟随窗口宽度 |
| 🌍 系统语言 | 跟随系统语言注入 WebView，支持动态切换（zh / en / ru / zh_HK） |
| 🔗 Deep Link | 冷/温/热启动接收分享链接并导航 |
| 🌙 深色模式 | 跟随系统自动切换 |
| 📤 文件上传 | 拍照 / 相册 / 文档选择器 |
| 💾 文件下载 | 转存至公共下载目录（文件名净化 + 沙箱不留残件） |
| 📲 系统分享 | 拦截分享链接，唤起系统分享面板 |
| 🎙️ 语音输入 | 麦克风走官方两步链路：系统权限 + 应用内确认 |
| 🔗 外部链接 | 站外链接与 `window.open` / `target="_blank"` 均转交系统浏览器 |
| ↩️ 返回手势 | 网页弹层交给网页关闭；对话界面「再按一次返回桌面」 |
| ♿ 无障碍 | 图标按钮均有朗读文案，触摸目标不小于 44vp |
| 🔒 安全 | TLS 证书错误一律拒绝，不提供「继续访问」 |
| 🔄 稳定性 | 渲染崩溃自动刷新 + 15s 超时错误页 |

> 各功能的实现细节（返回手势判定、软键盘与编辑卡片处理、窗口形态适配等）见 git 提交记录，README 不再展开。

## 项目结构

```
entry/src/main/ets/
├── common/                          纯逻辑与常量（不依赖组件，可独立测试）
│   ├── AppConfig.ets                入口 URL / 域名 / 反馈地址 / scheme 前缀 / UA 标识
│   ├── UrlRules.ets                 同域判断 / 聊天主站判定 / 对话界面判定 / 下载链接判定
│   ├── WebViewport.ets              视口修正 / 窗口尺寸通知 / 运行时诊断脚本
│   ├── WebInputGuard.ets            点图片不聚焦输入框的防护脚本
│   ├── BackPolicy.ets               返回手势判定（纯函数）
│   ├── DownloadFiles.ets            下载文件名净化 / 沙箱中转路径 / 残留清理
│   ├── AppPermissions.ets           系统权限查询与申请（麦克风）
│   ├── AllowedFileExtensions.ets    上传后缀白名单
│   ├── LanguageUtil.ets             BCP 47 语言标识规范化
│   ├── PhotoTempFiles.ets           拍照临时文件的生成与启动清理
│   └── UiPrefs.ets                  悬浮条位置等界面偏好持久化
├── components/                      展示型组件
│   ├── FloatingBar.ets              悬浮操作条（拖拽、边界、位置持久化）
│   ├── SettingsSheet.ets            设置面板内容
│   ├── UploadSheet.ets              上传方式选择模态框
│   ├── PageProgress.ets             顶部加载进度条
│   ├── ErrorView.ets                网络异常 / 加载失败页
│   └── RefreshConfirmDialog.ets     刷新确认弹窗
├── entryability/EntryAbility.ets    窗口沉浸 + Deep Link + 系统语言初始化
└── pages/Index.ets                  WebView 主页面
```

## 版本

`dev.cyotatsu.deepseek.oh` — v1.1.4.4 (1001044)

`versionCode` 编码规则：`主版本×1000000 + 次版本×10000 + 修订×10 + 构建`。
发版只需改 `AppScope/app.json5` 的 `versionName` 与 `versionCode`
（User-Agent 里的版本号是运行时从 `bundleManager` 读取的，不需要另改）。

## License

本项目以 **MIT License** 发布，详见 [LICENSE](./LICENSE)。

原项目版权：Copyright (c) 2026 Sakura Neko

原项目的版权声明与许可条款已完整保留。在此基础上新增的修改同样以 MIT 许可发布。
