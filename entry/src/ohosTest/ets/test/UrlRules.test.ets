import { describe, it, expect } from '@ohos/hypium';
import { isChatHost, isDeepSeekDomain, isDownloadUrl, isChatRootPage }
  from '../../../main/ets/common/UrlRules';

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

  describe('isChatHost', () => {
    // 与 isDeepSeekDomain 的区别一：精确匹配，子域名不算聊天主站
    it('accepts_only_the_chat_host', 0, () => {
      expect(isChatHost('https://chat.deepseek.com/')).assertTrue();
      expect(isChatHost('https://chat.deepseek.com/share/abc123')).assertTrue();
    });

    it('rejects_subdomains_and_other_hosts', 0, () => {
      expect(isChatHost('https://www.deepseek.com/')).assertFalse();
      expect(isChatHost('https://example.com/')).assertFalse();
      expect(isChatHost('https://chat.deepseek.com.evil.com/')).assertFalse();
    });

    // 区别二、也是这条函数的重点：必须 **fail-closed**。
    // 它被用作功能开关（上传白名单、2in1 返回按钮），一旦 fail-open，
    // 未知页面会被当成聊天主站，出现「随手点一下弹上传框」这种越权行为。
    // isDeepSeekDomain 的语义相反（fail-open），两者不能混用 ——
    // 这组断言就是把这条边界钉死，防止以后被"统一"掉。
    it('unparseable_url_fails_closed', 0, () => {
      expect(isChatHost('::not a url::')).assertFalse();
      expect(isChatHost('')).assertFalse();
    });
  });

  // 返回手势策略依赖这条判定：对话界面屏蔽网页后退，二三级界面保持不变。
  // 失败方向必须是「不算对话界面」，即回落到改动前的网页后退行为。
  describe('isChatRootPage', () => {
    it('accepts_home_and_chat_paths', 0, () => {
      expect(isChatRootPage('https://chat.deepseek.com/')).assertTrue();
      expect(isChatRootPage('https://chat.deepseek.com/a/chat')).assertTrue();
      expect(isChatRootPage('https://chat.deepseek.com/a/chat/')).assertTrue();
      expect(isChatRootPage('https://chat.deepseek.com/a/chat/s/0f2c1a7e-1234-4bcd-9abc-1234567890ab'))
        .assertTrue();
    });

    // 会话页常带 query / hash（分享回链、消息锚点），pathname 判定必须不受影响
    it('ignores_query_and_hash', 0, () => {
      expect(isChatRootPage('https://chat.deepseek.com/a/chat/s/abc?from=share&id=1')).assertTrue();
      expect(isChatRootPage('https://chat.deepseek.com/a/chat/s/abc#msg-3')).assertTrue();
      expect(isChatRootPage('https://chat.deepseek.com/a/chat/?lang=zh')).assertTrue();
    });

    it('rejects_other_paths', 0, () => {
      expect(isChatRootPage('https://chat.deepseek.com/sign_in')).assertFalse();
      expect(isChatRootPage('https://chat.deepseek.com/share/abcd1234')).assertFalse();
      expect(isChatRootPage('https://chat.deepseek.com/download-app')).assertFalse();
    });

    // 前缀匹配必须带分隔符：/a/chatx 不是 /a/chat 之下
    it('does_not_match_sibling_paths_with_shared_prefix', 0, () => {
      expect(isChatRootPage('https://chat.deepseek.com/a/chatx')).assertFalse();
      expect(isChatRootPage('https://chat.deepseek.com/a/chats')).assertFalse();
    });

    it('rejects_other_hosts', 0, () => {
      expect(isChatRootPage('https://www.deepseek.com/a/chat')).assertFalse();
      expect(isChatRootPage('https://example.com/a/chat')).assertFalse();
      expect(isChatRootPage('https://chat.deepseek.com.evil.com/a/chat')).assertFalse();
    });

    it('unparseable_url_fails_closed', 0, () => {
      expect(isChatRootPage('::not a url::')).assertFalse();
      expect(isChatRootPage('')).assertFalse();
    });
  });
}
