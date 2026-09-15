import { url } from '@kit.ArkTS';
import { DEEPSEEK_HOST } from './AppConfig';

/**
 * URL 判定规则。
 *
 * 纯函数、不依赖组件状态，放在此处便于单独测试，也避免 Index.ets 继续膨胀。
 */

/** 常见可下载文件的扩展名 */
const DOWNLOAD_EXTENSIONS: Array<string> = [
  '.zip', '.rar', '.7z', '.tar', '.gz', '.bz2', '.xz',
  '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx',
  '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.svg', '.webp',
  '.mp3', '.mp4', '.avi', '.mov', '.mkv', '.flv', '.wmv',
  '.exe', '.msi', '.apk', '.dmg', '.deb', '.rpm',
  '.csv', '.json', '.xml', '.sql', '.db',
  '.iso', '.img', '.bin',
  '.txt', '.md', '.log'
];

/**
 * 判断 URL 是否属于 DeepSeek 域名（chat.deepseek.com 及其子域名）。
 *
 * 解析失败时保守返回 true，即允许继续在 WebView 内加载 —— 这样宁可放行也不误拦，
 * 与在 onLoadIntercept 中的调用语义一致。
 */
export function isDeepSeekDomain(requestUrl: string): boolean {
  try {
    const parsed: url.URL = url.URL.parseURL(requestUrl);
    const hostname: string = parsed.hostname;
    return hostname === DEEPSEEK_HOST || hostname.endsWith('.deepseek.com');
  } catch (err) {
    return true;
  }
}

/**
 * 判断给定 URL 是否正是 DeepSeek 聊天主站（精确匹配 host，不含子域名）。
 *
 * 与 {@link isDeepSeekDomain} 的区别在于**用途不同**，因此失败策略也相反：
 *   · isDeepSeekDomain 回答「这个地址要不要留在应用内打开」，所以放宽 ——
 *     允许子域名、解析失败时放行，宁可放行也不误拦；
 *   · isChatHost 回答「当前页面是不是聊天主站」，用于功能开关（上传白名单、返回按钮），
 *     所以收紧 —— 精确匹配、解析失败时返回 false，避免把未知页面当成主站。
 */
export function isChatHost(rawUrl: string): boolean {
  try {
    return url.URL.parseURL(rawUrl).hostname === DEEPSEEK_HOST;
  } catch (err) {
    return false;
  }
}

/**
 * 聊天主站中属于「根级界面」的路径前缀。
 *
 * chat.deepseek.com 的对话界面都挂在 `/a/chat` 之下（`/a/chat`、
 * `/a/chat/s/<会话 id>`、带 query/hash 的分享回链等），首页是 `/`。
 * 其余路径（`/sign_in`、`/share/…`、`/download-app` 等）都算二三级界面。
 */
const CHAT_ROOT_PATH_PREFIXES: Array<string> = ['/a/chat'];

/** 规范化 pathname，避免 `/a/chat/` 与 `/a/chat` 被判成两个不同界面 */
function normalizePath(pathname: string): string {
  let p: string = pathname;
  while (p.length > 1 && p.endsWith('/')) {
    p = p.substring(0, p.length - 1);
  }
  return p;
}

/**
 * 判断 URL 是否处于聊天主站的「根级界面」（即用户所说的**对话界面**）：
 * 首页 `/`，或 `/a/chat` 之下的会话页。
 *
 * 用途是**返回手势策略**（见 common/BackPolicy.ets）：对话界面屏蔽网页后退、
 * 改为「再按一次返回桌面」。因此这里的失败策略同样是收紧 —— 解析失败、非聊天主站
 * 一律返回 false，让返回手势回落到改动前的「网页后退」行为，
 * 宁可少生效，也不要把用户困在一个退不出去的页面上。
 */
export function isChatRootPage(rawUrl: string): boolean {
  try {
    const parsed: url.URL = url.URL.parseURL(rawUrl);
    if (parsed.hostname !== DEEPSEEK_HOST) {
      return false;
    }
    const path: string = normalizePath(parsed.pathname || '/');
    if (path === '' || path === '/') {
      return true;
    }
    // 前缀匹配必须带上分隔符，否则 /a/chatx 会被误判成 /a/chat 之下
    return CHAT_ROOT_PATH_PREFIXES.some((prefix: string) =>
      path === prefix || path.startsWith(prefix + '/'));
  } catch (err) {
    return false;
  }
}

/**
 * 判断 URL 是否为下载链接（按常见文件扩展名）。
 *
 * 解析失败时返回 false，即不当作下载处理。
 */
export function isDownloadUrl(requestUrl: string): boolean {
  try {
    const parsed: url.URL = url.URL.parseURL(requestUrl);
    const pathname: string = (parsed.pathname || '').toLowerCase();
    return DOWNLOAD_EXTENSIONS.some((ext: string) => pathname.endsWith(ext));
  } catch (err) {
    return false;
  }
}
