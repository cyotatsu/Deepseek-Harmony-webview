import { describe, it, expect } from '@ohos/hypium';
import { buildFocusGuardScript, EDITABLE_SELECTOR, ENABLE_IMAGE_TAP_FOCUS_GUARD }
  from '../main/ets/common/WebInputGuard';

/**
 * common/WebInputGuard 的本地（宿主）单元测试。
 *
 * 防护脚本是纯字符串拼装，拼错一处就整段失效，而 runJavaScript 失败在应用侧
 * 几乎不可见（只有一个 warn），因此把关键结构钉在测试里。
 *
 * 真正「点图片还会不会弹键盘」必须实机验证，不在本地测试范围内。
 */
export default function webInputGuardTest() {
  describe('focus guard script', () => {
    const script: string = buildFocusGuardScript();

    // 每次 onPageEnd 都会注入，必须自带幂等标记，否则重复注册监听器
    it('is_idempotent', 0, () => {
      expect(script).assertContain('__dsFocusGuard');
      expect(script).assertContain("'already'");
    });

    it('listens_on_capture_phase_for_pointer_and_focus', 0, () => {
      expect(script).assertContain("addEventListener('pointerdown'");
      expect(script).assertContain("addEventListener('focusin'");
      // 必须用捕获阶段：页面自身的处理器可能在冒泡阶段抢焦点
      expect(script).assertContain('true)');
    });

    it('only_targets_image_elements', 0, () => {
      expect(script).assertContain('IMG');
      expect(script).assertContain('PICTURE');
      expect(script).assertContain('FIGURE');
    });

    it('only_suppresses_focus_on_editable_elements', 0, () => {
      expect(script).assertContain(EDITABLE_SELECTOR);
      expect(script).assertContain('blur()');
    });

    // 关键防误伤：先清标记再 blur → 每次点击最多抑制一次，杜绝「抢焦点↔blur」死循环
    it('clears_the_flag_before_blurring_to_avoid_focus_loop', 0, () => {
      const flagClear: number = script.indexOf('tappedImage = false;', script.indexOf('focusin'));
      const blurCall: number = script.indexOf('t.blur()');
      expect(flagClear > 0).assertTrue();
      expect(blurCall > 0).assertTrue();
      expect(flagClear < blurCall).assertTrue();
    });

    // 标记必须有超时失效，否则一次点击的影响会泄漏到后续操作
    it('expires_the_tap_flag', 0, () => {
      expect(script).assertContain('setTimeout');
      expect(script).assertContain('clearTimeout');
    });

    it('is_guarded_against_dom_exceptions', 0, () => {
      expect(script).assertContain('(function');
      expect(script).assertContain('catch');
      expect(script).assertContain('return');
    });

    it('reports_install_status', 0, () => {
      expect(script).assertContain("'installed'");
    });
  });

  describe('module flags', () => {
    it('selector_covers_all_editable_kinds', 0, () => {
      expect(EDITABLE_SELECTOR).assertContain('textarea');
      expect(EDITABLE_SELECTOR).assertContain('input');
      expect(EDITABLE_SELECTOR).assertContain('contenteditable');
    });

    // 默认必须是开启的：这就是本次要修的问题
    it('guard_is_enabled_by_default', 0, () => {
      expect(ENABLE_IMAGE_TAP_FOCUS_GUARD).assertTrue();
    });
  });
}
