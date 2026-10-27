/**
 * 网页文字缩放（手动调节字号）的纯逻辑。
 *
 * 为什么单独成文件：缩放值来自用户拖动滑块，必须夹取到安全区间并按步进取整，
 * 否则会出现「100.0000001%」「80% 以下文字糊成一团」之类的怪值。
 * 这几个判定与 ArkUI 无关，抽出来就能在宿主机上直接单测（见 test/FontZoom.test.ets）。
 */

/** 最小缩放（%）：再小正文就难以辨认 */
export const TEXT_ZOOM_MIN: number = 80;
/**
 * 最大缩放（%）。
 *
 * 不给到 200%：实测 200% 时一屏只剩约 7 行正文，手机端每行仅 7~8 个汉字，
 * 表格 / 代码块这类定宽内容也会被挤坏 —— 再往上调是「越调越难用」。
 * 160% 已足够覆盖"字太小看不清"的场景，且版面基本还排得住。
 */
export const TEXT_ZOOM_MAX: number = 160;
/** 步进（%）：5 一档，既能精细调节，又不至于滑不到目标值 */
export const TEXT_ZOOM_STEP: number = 5;
/** 默认缩放（%），与内核 textZoomRatio 的默认值一致 */
export const TEXT_ZOOM_DEFAULT: number = 100;

/**
 * 把任意数值夹取到 [MIN, MAX] 并取整。
 *
 * 1. 非数字（含 NaN）一律回到默认值 —— 存储被写坏时不至于把字号设成 0；
 * 2. 越界先夹取，避免把超出区间的值透传给内核；
 * 3. 最后四舍五入，内核只接受整数百分比。
 */
export function clampTextZoom(value: number): number {
  if (Number.isNaN(value)) {
    return TEXT_ZOOM_DEFAULT;
  }
  if (value < TEXT_ZOOM_MIN) {
    return TEXT_ZOOM_MIN;
  }
  if (value > TEXT_ZOOM_MAX) {
    return TEXT_ZOOM_MAX;
  }
  return Math.round(value);
}

/**
 * 规范化滑块输入：先按步进取整，再夹取。
 *
 * 滑块本身已带 step，但程序化赋值（恢复默认、读存储）不经过滑块，
 * 因此这条路径必须自己也保证「落在步进网格上」。
 */
export function normalizeTextZoom(value: number): number {
  if (Number.isNaN(value)) {
    return TEXT_ZOOM_DEFAULT;
  }
  const stepped: number = Math.round(value / TEXT_ZOOM_STEP) * TEXT_ZOOM_STEP;
  return clampTextZoom(stepped);
}

/** 展示用文本，例如 "115%" */
export function formatTextZoom(value: number): string {
  return clampTextZoom(value).toString() + '%';
}
