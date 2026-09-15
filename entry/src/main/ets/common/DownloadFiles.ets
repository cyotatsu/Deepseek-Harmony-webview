import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0001;
const TAG = 'DeepSeekDownloadFiles';

/**
 * 下载中转文件相关的纯逻辑。
 *
 * 抽到 common/ 下便于单独测试，也避免 Index.ets 继续膨胀。
 * 这里的输入（服务端 Content-Disposition 给出的文件名）属于**不可信数据**，
 * 因此净化逻辑必须与业务代码分开、可被独立验证。
 */

/** 下载中转目录名（位于应用 cacheDir 之下） */
export const DOWNLOAD_TEMP_DIR: string = 'web';

/** 文件名长度上限，避免超过底层文件系统限制 */
const MAX_FILE_NAME_LENGTH: number = 120;

/**
 * 净化服务端建议的下载文件名。
 *
 * 为什么必须净化：
 *   · 文件名可能携带 '/' 或 '..'，直接拼进路径会**穿越出中转目录**（安全风险）；
 *   · 可能含控制字符或平台非法字符（<>:"|?*），落盘时直接失败；
 *   · 可能以 '.' 或空格结尾，Windows 系文件系统不允许。
 *
 * 处理方式：统一分隔符后只取最后一段（这一步天然消除 '../' 与绝对路径），
 * 再剔除非法字符、修剪首尾，最后限制总长度（保留扩展名）。
 */
export function sanitizeFileName(raw: string, fallback: string = 'download'): string {
  if (!raw || raw.length === 0) {
    return fallback;
  }
  const normalized: string = raw.replace(/\\/g, '/');
  let name: string = normalized;
  const slash: number = normalized.lastIndexOf('/');
  if (slash >= 0) {
    name = normalized.substring(slash + 1);
  }
  // 剔除非法字符与控制字符
  name = name.replace(/[<>:"|?*\u0000-\u001F]/g, '_');
  // 去掉首尾空白，以及结尾的点/空格
  name = name.trim().replace(/[. ]+$/, '');
  if (name.length === 0 || name === '.' || name === '..') {
    return fallback;
  }
  if (name.length > MAX_FILE_NAME_LENGTH) {
    const dot: number = name.lastIndexOf('.');
    const ext: string = dot > 0 ? name.substring(dot) : '';
    const keep: number = MAX_FILE_NAME_LENGTH - ext.length;
    name = name.substring(0, keep > 0 ? keep : MAX_FILE_NAME_LENGTH) + ext;
  }
  return name;
}

/**
 * 构造沙箱中转文件路径。
 *
 * 用 guid 作为前缀而不是直接用文件名：同名文件并发下载时不会互相覆盖
 * （原实现只把 guid 用在映射表的 key 上，落盘路径仍是纯文件名）。
 */
export function buildDownloadTempPath(cacheDir: string, guid: string, fileName: string): string {
  return `${cacheDir}/${DOWNLOAD_TEMP_DIR}/${guid}_${fileName}`;
}

/** 从中转路径还原用户可见的文件名（去掉 guid_ 前缀，保持与落盘内容一致） */
export function fileNameFromTempPath(tempPath: string, guid: string): string {
  const base: string = tempPath.substring(tempPath.lastIndexOf('/') + 1);
  const prefix: string = `${guid}_`;
  return base.startsWith(prefix) ? base.substring(prefix.length) : base;
}

/**
 * 确保中转目录存在。
 *
 * WebDownloadItem.start() 不会自建父目录，原实现直接把文件写到
 * `cacheDir/web/` 却从未创建该目录，属于对系统行为的隐性依赖。
 */
export function ensureDownloadTempDir(cacheDir: string): string {
  const dir: string = `${cacheDir}/${DOWNLOAD_TEMP_DIR}`;
  try {
    if (!fs.accessSync(dir)) {
      fs.mkdirSync(dir, true);
    }
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'Failed to create download temp dir');
  }
  return dir;
}

/**
 * 删除单个中转文件（失败不抛异常）。
 *
 * 已复制到公共目录后必须调用，否则每下载一次就在沙箱里永久留一份副本。
 */
export function removeDownloadTempFile(tempPath: string): void {
  if (!tempPath || tempPath.length === 0) {
    return;
  }
  try {
    fs.unlinkSync(tempPath);
  } catch (err) {
    // 文件可能已被系统清理，忽略
  }
}

/**
 * 清理上次运行遗留的下载中转文件。
 *
 * 下载完成后我们会主动删除中转文件，但进程被杀、保存对话框未走完等情况下仍会残留。
 * cacheDir 语义上随时可被系统回收，因此启动时整目录清空是安全的。
 */
export function cleanupDownloadTempFiles(cacheDir: string): void {
  const dir: string = `${cacheDir}/${DOWNLOAD_TEMP_DIR}`;
  let removed: number = 0;
  try {
    if (!fs.accessSync(dir)) {
      return;
    }
    const names: string[] = fs.listFileSync(dir);
    for (const name of names) {
      try {
        fs.unlinkSync(`${dir}/${name}`);
        removed++;
      } catch (err) {
        // 单个文件删除失败（仍被占用等）不影响其余清理
      }
    }
    fs.rmdirSync(dir);
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'Download temp cleanup failed');
  }
  if (removed > 0) {
    hilog.info(DOMAIN, TAG, 'Cleaned %{public}d leftover download temp file(s)', removed);
  }
}
