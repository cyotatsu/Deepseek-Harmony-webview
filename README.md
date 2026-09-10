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
| 💾 文件下载 | WebView 下载转存至公共下载目录 |
| 📲 系统分享 | 拦截分享链接，唤起系统分享面板 |
| 🔄 稳定性 | 渲染崩溃自动刷新 + 15s 超时错误页 |

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

`dev.cyotatsu.deepseek.oh` — v1.1.4.2 (1001042)

## License

本项目以 **MIT License** 发布，详见 [LICENSE](./LICENSE)。

原项目版权：Copyright (c) 2026 Sakura Neko

原项目的版权声明与许可条款已完整保留。在此基础上新增的修改同样以 MIT 许可发布。
