import { describe, it, expect } from '@ohos/hypium';
import { isDeepSeekDomain, isDownloadUrl } from '../../../main/ets/common/UrlRules';

/**
 * UrlRules 的设备侧单元测试。
 *
 * 为什么放在 ohosTest 而不是 src/test：这两个函数依赖 @kit.ArkTS 的
 * url.URL.parseURL，该 API 在本地（宿主）测试环境不可用 —— 每个调用都会抛异常，
 * 从而落进各自的 catch 分支（isDeepSeekDomain 返回 true、isDownloadUrl 返回 false），
 * 导致断言全部失真。放到设备上运行才能拿到真实结果。
 */
export default function urlRulesTest() {
  describe('isDeepSeekDomain', () => {
    it('accepts_deepseek_host', 0, () => {
      expect(isDeepSeekDomain('https://chat.deepseek.com/')).assertTrue();
      expect(isDeepSeekDomain('https://chat.deepseek.com/share/abc123')).assertTrue();
    });

    it('accepts_subdomains', 0, () => {
      expect(isDeepSeekDomain('https://www.deepseek.com/')).assertTrue();
    });

    it('rejects_other_hosts', 0, () => {
      expect(isDeepSeekDomain('https://example.com/')).assertFalse();
      expect(isDeepSeekDomain('https://github.com/')).assertFalse();
    });

    // 边界：不能因为域名里含 deepseek 就放行
    it('rejects_lookalike_hosts', 0, () => {
      expect(isDeepSeekDomain('https://notdeepseek.com/')).assertFalse();
      expect(isDeepSeekDomain('https://chat.deepseek.com.evil.com/')).assertFalse();
    });

    // 这条记录的是「解析失败时 fail-open」的既有设计：
    // 无法解析的地址会被当作站内地址放行，宁可放行也不误拦。
    // 若将来改为 fail-closed，这条断言需要同步修改。
    it('unparseable_url_fails_open', 0, () => {
      expect(isDeepSeekDomain('::not a url::')).assertTrue();
    });
  });

  describe('isDownloadUrl', () => {
    it('accepts_known_extensions', 0, () => {
      expect(isDownloadUrl('https://chat.deepseek.com/a/b.pdf')).assertTrue();
      expect(isDownloadUrl('https://chat.deepseek.com/a/b.png')).assertTrue();
      expect(isDownloadUrl('https://chat.deepseek.com/a/b.zip')).assertTrue();
      expect(isDownloadUrl('https://chat.deepseek.com/a/b.md')).assertTrue();
    });

    it('extension_match_is_case_insensitive', 0, () => {
      expect(isDownloadUrl('https://chat.deepseek.com/a/b.PDF')).assertTrue();
    });

    it('rejects_unknown_extensions', 0, () => {
      expect(isDownloadUrl('https://chat.deepseek.com/a/b.unknownext')).assertFalse();
    });

    it('rejects_extensionless_urls', 0, () => {
      expect(isDownloadUrl('https://chat.deepseek.com/')).assertFalse();
      expect(isDownloadUrl('https://chat.deepseek.com/share/abc')).assertFalse();
    });
  });
}
