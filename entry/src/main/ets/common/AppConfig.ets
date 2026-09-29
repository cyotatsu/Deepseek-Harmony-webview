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

/**
 * 自定义 scheme（浏览器/其它应用唤起本应用的通路）。
 *
 * 为什么需要它：http/https 分享链接要被本应用优先接住，必须通过 App Linking 的
 * 域名校验（系统到 https://chat.deepseek.com/.well-known/ 拉校验文件核对应用身份），
 * 而该域名属 DeepSeek，本项目无法托管校验文件 —— 实测隐式投递 https 链接直接进浏览器
 * 且不弹选择框）。自定义 scheme 不要求域名归属，
 * 因此「提示用本应用打开」这条路只有它走得通。
 *
 * 支持的两种写法（都会在 EntryAbility.handleDeepLink 里归一化成 https 分享链接）：
 *   · deepseek://share/<id>
 *   · deepseek://chat.deepseek.com/share/<id>
 */
export const CUSTOM_SCHEME: string = 'deepseek';

/**
 * 悬浮条设置的 AppStorage 键。
 *
 * 设置面板（SettingsSheet）与悬浮条（FloatingBar）之间不做直接引用：
 * 面板只写这些键，悬浮条用 @StorageLink 读取，二者互不知道对方存在。
 */
/** 按钮直径倍率（1.0 = 默认 48vp） */
export const KEY_FAB_SIZE_SCALE: string = 'fab.sizeScale';
/** 左右贴边时是否半隐藏（只露一小半） */
export const KEY_FAB_HIDE_ON_SNAP: string = 'fab.hideOnSnap';
/** 是否启用空闲自动吸附 */
export const KEY_FAB_AUTO_SNAP: string = 'fab.autoSnap';
/** 请求悬浮条重置到默认位置（写 true 后由悬浮条复位并清零） */
export const KEY_FAB_RESET_POS: string = 'fab.resetPosition';
