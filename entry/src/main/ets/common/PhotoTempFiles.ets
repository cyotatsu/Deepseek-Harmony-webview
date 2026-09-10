import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0001;
const TAG = 'DeepSeekPhotoTemp';

/**
 * 拍照预创建文件的专用前缀。
 *
 * 原先文件名是光秃秃的 `<时间戳>.jpg`，无法与 filesDir 中的其它文件区分，
 * 也就无法安全地按名字清理。加上前缀后即可精确匹配，只删本应用自己产生的文件。
 */
export const PHOTO_TEMP_PREFIX: string = 'ds_photo_';

/** 生成一次拍照所需的临时文件路径（调用方负责预创建该空文件） */
export function buildPhotoTempPath(filesDir: string): string {
  return `${filesDir}/${PHOTO_TEMP_PREFIX}${new Date().getTime()}.jpg`;
}

/**
 * 清理上次运行遗留的拍照临时文件。
 *
 * 背景：handleTakePhoto 会在 filesDir 预创建一个空文件供系统相机写入。
 * 用户取消时会删除；但上传成功后**不会**删（此时 WebView 可能仍在读取该文件，
 * 删早了会导致上传失败）。结果是每拍照上传一次，filesDir 里就永久多出一份副本，
 * 长期使用会持续占用空间。
 *
 * 放在应用启动时清理最安全 —— 此刻不可能有上传正在进行，因此无需改动上传时序，
 * 也能让该目录自愈。
 */
export function cleanupPhotoTempFiles(filesDir: string): void {
  let removed: number = 0;
  try {
    const names: string[] = fs.listFileSync(filesDir);
    for (const name of names) {
      if (!name.startsWith(PHOTO_TEMP_PREFIX)) {
        continue;
      }
      try {
        fs.unlinkSync(`${filesDir}/${name}`);
        removed++;
      } catch (err) {
        // 单个文件删除失败（例如仍被占用）不影响其余清理
      }
    }
    if (removed > 0) {
      hilog.info(DOMAIN, TAG, 'Cleaned %{public}d leftover photo temp file(s)', removed);
    }
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'Photo temp cleanup failed');
  }
}
