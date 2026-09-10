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
