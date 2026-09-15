/**
 * 应用级常量。
 *
 * 这些值原先硬编码在 EntryAbility.ets 与 Index.ets 中（域名出现 3 次），
 * 集中一处后改域名只需改这里。
 */

/** DeepSeek 网页版入口，Web 组件首次加载的地址 */
export const DEEPSEEK_URL: string = 'https://chat.deepseek.com/';

/** DeepSeek 网页版域名，用于同域判断与分享链接识别 */
export const DEEPSEEK_HOST: string = 'chat.deepseek.com';

/** 问题反馈地址（设置面板中点击后交给系统浏览器打开） */
export const FEEDBACK_URL: string = 'https://github.com/cyotatsu/Deepseek-Harmony-webview/pulls';

/**
 * 注入脚本回传「分享」用的自定义 scheme 前缀。
 *
 * 网页侧没有可用的原生通道，只能通过一次 location.href 「导航」把分享链接
 * 带出来，再由 Web 组件的 onLoadIntercept 拦截。前缀集中在此，避免注入脚本
 * （字符串拼装）与拦截逻辑（字符串比较）各写一份而写歪。
 */
export const SHARE_SCHEME_PREFIX: string = 'share://?url=';

/**
 * 注入到 User-Agent 的产品标识前缀，版本号在运行时从 bundleManager 读取。
 * 原实现把版本号写死为 1.0，与 AppScope/app.json5 的 versionName 早已脱节。
 */
export const UA_PRODUCT_PREFIX: string = 'DeepSeek-HarmonyOS';
