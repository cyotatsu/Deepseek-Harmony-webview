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
