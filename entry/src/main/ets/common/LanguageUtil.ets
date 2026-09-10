/**
 * 语言标识处理。
 *
 * 纯函数、不依赖组件状态，放在此处便于单独测试，也避免 Index.ets 继续膨胀。
 */

/**
 * 把系统语言标识规范化为 BCP 47，供 WebView navigator.language 使用。
 *
 * 规则（优先级：地区 > script > 仅语言）：
 *   "zh-Hans-CN" → "zh-CN"    有地区时用「语言-地区」，兼容性最好
 *   "zh-Hant-HK" → "zh-HK"
 *   "zh-Hant"    → "zh-Hant"  无地区时保留 script，否则繁体会被当成简体
 *   "zh-Hans"    → "zh"       Hans 是简体的默认写法，裸 "zh" 已隐含简体，
 *                             故不返回 "zh-Hans" 以保持网页侧现网行为不变
 *   "en-US" → "en-US"   "en" → "en"   "ru" → "ru"
 *
 * 历史问题：原实现对 zh-Hans / zh-Hant 一律只取首段，两者都退化成 "zh"，
 * 导致繁体（zh_HK / zh-Hant）用户被网页按简体处理。
 */
export function toBCP47(raw: string): string {
  if (!raw || raw.length === 0) {
    return 'en';
  }
  const parts: string[] = raw.split('-');
  const lang: string = parts[0].toLowerCase();
  if (lang.length === 0) {
    return 'en';
  }
  let script: string = '';
  let region: string = '';
  for (let i = 1; i < parts.length; i++) {
    const seg: string = parts[i];
    if (seg.length === 0) {
      continue;
    }
    if (script === '' && seg.length === 4) {
      // 4 字母 = script 子标签（Hans/Hant/Latn…），规范化为首字母大写
      script = seg.charAt(0).toUpperCase() + seg.substring(1).toLowerCase();
    } else if (region === '' && (seg.length === 2 || seg.length === 3)) {
      // 2 字母或 3 位数字 = 地区子标签
      region = seg.toUpperCase();
    }
  }
  if (region !== '') {
    return `${lang}-${region}`;
  }
  if (script !== '' && script !== 'Hans') {
    return `${lang}-${script}`;
  }
  return lang;
}
