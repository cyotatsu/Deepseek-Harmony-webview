import { describe, it, expect } from '@ohos/hypium';
import { buildUserAgent, isMobileUa, buildViewportFixScript, buildResizeNotifyScript,
  buildProbeScript, buildOverlayProbeScript, isOverlayOpenResult,
  VIEWPORT_STYLE_ID, EDITABLE_SELECTOR, MOBILE_UA_TOKEN,
  COMPOSER_CAP_VAR, COMPOSER_FALLBACK_VH, COMPOSER_MAX_PX, COMPOSER_MIN_PX,
  COMPOSER_MAX_RATIO, COMPOSER_UNSTRETCH_CSS,
  computeComposerCapPx } from '../main/ets/common/WebViewport';

/**
 * common/WebViewport 的本地（宿主）单元测试。
 *
 * 只覆盖**纯字符串逻辑**：UA 拼装与三段注入脚本的拼装。
 * 这些字符串最终会被送进网页执行，拼错一个字符就整段失效，且失败时
 * 在应用侧几乎不可见（runJavaScript 只是抛个异常），因此值得单独钉住。
 *
 * 真正「viewport 是否生效」必须靠实机 probe 日志判定，不在本地测试范围内。
 */
export default function webViewportTest() {
  describe('isMobileUa', () => {
    it('detects_mobile_token_case_insensitively', 0, () => {
      expect(isMobileUa('Mozilla/5.0 (Linux; Android 12; Mobile) AppleWebKit/537.36')).assertTrue();
      expect(isMobileUa('Mozilla/5.0 (phone; OpenHarmony) Mobile Safari/537.36')).assertTrue();
      // 大小写不敏感
      expect(isMobileUa('MOBILE')).assertTrue();
      expect(isMobileUa('mobile')).assertTrue();
    });

    it('rejects_ua_without_mobile_token', 0, () => {
      // 平板 / 2in1 的典型形态：带设备身份但不含 Mobile
      expect(isMobileUa('Mozilla/5.0 (Tablet; OpenHarmony 5.0) AppleWebKit/537.36')).assertFalse();
      expect(isMobileUa('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36')).assertFalse();
      expect(isMobileUa('')).assertFalse();
    });
  });

  describe('buildUserAgent', () => {
    const base: string = 'Mozilla/5.0 (Tablet; OpenHarmony 5.0) AppleWebKit/537.36';
    // 版本号只是拼装样例，**不跟随** AppScope/app.json5 的 versionName ——
    // 真实版本号是运行时从 bundleManager 读的，这里写死应用版本只会让每次发版
    // 都要顺手改测试（写成本样例就不会再过期）
    const sampleVersion: string = '9.9.9.9';

    it('keeps_base_ua_and_appends_product_token', 0, () => {
      const ua: string = buildUserAgent(base, 'DeepSeek-HarmonyOS', sampleVersion, false);
      expect(ua).assertContain('Tablet');
      expect(ua).assertContain('DeepSeek-HarmonyOS/' + sampleVersion);
      // 默认不得无端塞入 Mobile —— 否则站点会改发移动端页面，
      // 让平板/2in1 全屏这种本来正常的场景也跟着退化
      expect(isMobileUa(ua)).assertFalse();
    });

    it('appends_mobile_only_when_explicitly_requested', 0, () => {
      const ua: string = buildUserAgent(base, 'DeepSeek-HarmonyOS', '1.0', true);
      expect(isMobileUa(ua)).assertTrue();
      expect(ua).assertContain(MOBILE_UA_TOKEN);
    });

    // 兜底开关打开时，若内核 UA 本就含 Mobile 不能重复追加
    it('never_duplicates_mobile_token', 0, () => {
      const mobileBase: string = 'Mozilla/5.0 (Linux; Mobile) AppleWebKit/537.36';
      const ua: string = buildUserAgent(mobileBase, 'P', '1.0', true);
      expect(ua.indexOf('Mobile')).assertEqual(ua.lastIndexOf('Mobile'));
    });

    it('handles_empty_base_and_version', 0, () => {
      expect(buildUserAgent('', 'P', '', false)).assertEqual('P');
      expect(buildUserAgent('Base', '', '', false)).assertEqual('Base');
      // 全空时不能产出前导/尾随空格
      expect(buildUserAgent('', '', '', false)).assertEqual('');
    });
  });

  describe('buildViewportFixScript', () => {
    const script: string = buildViewportFixScript();

    it('declares_a_device_width_viewport_fallback', 0, () => {
      expect(script).assertContain('meta[name="viewport"]');
      expect(script).assertContain('width=device-width');
      expect(script).assertContain('initial-scale=1');
    });

    // 只在页面自身没有 width 声明时才覆盖（那是 -1/未知宽度时的兜底路径）
    it('only_overrides_when_width_is_missing', 0, () => {
      expect(script).assertContain("indexOf('width') < 0");
    });

    // 关键：布局视口宽度必须显式取「应用窗口宽度」，不能用 device-width。
    // Chromium 里 device-width = 屏幕宽度，自由多窗下会让整页按屏幕排版再缩小。
    it('uses_explicit_window_width_when_provided', 0, () => {
      const s: string = buildViewportFixScript(720);
      expect(s).assertContain('var target = 720');
      expect(s).assertContain("indexOf('width=')");
    });

    // 尚未测到窗口宽度时退回 device-width，而不是写一个错的数值
    it('falls_back_to_device_width_when_width_unknown', 0, () => {
      const s: string = buildViewportFixScript(0);
      expect(s).assertContain('var target = 0');
      expect(s).assertContain('width=device-width');
    });

    it('injects_composer_height_cap_once', 0, () => {
      expect(script).assertContain(VIEWPORT_STYLE_ID);
      expect(script).assertContain('overflow-y');
      // 用 id 去重，避免每次 onPageEnd 反复插入 style
      expect(script).assertContain('getElementById');
    });

    // 上限走 CSS 变量，且带 vh 兜底 —— 脚本没跑时也不会完全放开
    it('caps_composer_via_css_variable_with_vh_fallback', 0, () => {
      expect(script).assertContain(COMPOSER_CAP_VAR);
      expect(script).assertContain(`var(${COMPOSER_CAP_VAR},${COMPOSER_FALLBACK_VH}vh)`);
    });

    // 消除「文字与工具栏之间的大片空白」：让输入框的直接父容器退出拉伸。
    // 实机 DOM 实测该父容器被拉到 336px 而输入框只有 99px。
    it('unsticks_the_stretched_composer_wrapper', 0, () => {
      expect(script).assertContain(COMPOSER_UNSTRETCH_CSS);
      expect(script).assertContain('div:has(> textarea)');
    });

    // 硬保证的实现方式：按实时可视高度算像素上限，而不是写死一个 vh
    it('computes_cap_from_live_visible_height', 0, () => {
      expect(script).assertContain('clientHeight');
      expect(script).assertContain('visualViewport');
      expect(script).assertContain(`${COMPOSER_MAX_PX}`);
      expect(script).assertContain(`${COMPOSER_MIN_PX}`);
      expect(script).assertContain(`${COMPOSER_MAX_RATIO}`);
    });

    // 键盘弹出/收起都要重算：两个 resize 源都监听；且必须幂等
    it('recomputes_on_resize_and_is_idempotent', 0, () => {
      expect(script).assertContain("addEventListener('resize'");
      expect(script).assertContain('__dsComposerCap');
    });

    // 注入结果必须可区分，否则「样式没生效」在应用侧完全无声
    it('reports_inject_result', 0, () => {
      expect(script).assertContain("'ok:'");
      expect(script).assertContain("'no-head'");
      expect(script).assertContain("'error'");
    });

    it('is_self_executing_and_guarded', 0, () => {
      expect(script).assertContain('(function');
      expect(script).assertContain('catch');
    });
  });

  describe('buildResizeNotifyScript', () => {
    it('dispatches_a_resize_event', 0, () => {
      const script: string = buildResizeNotifyScript();
      expect(script).assertContain("new Event('resize')");
      expect(script).assertContain('dispatchEvent');
      expect(script).assertContain('catch');
    });
  });

  describe('buildProbeScript', () => {
    const script: string = buildProbeScript();

    // 这几个字段是实机判定方案是否奏效的依据，缺一不可
    it('reports_the_fields_needed_to_judge_viewport', 0, () => {
      expect(script).assertContain('clientW');
      expect(script).assertContain('innerW');
      expect(script).assertContain('mobileToken');
      expect(script).assertContain('viewportMeta');
      expect(script).assertContain('visualViewport');
    });

    // 输入框的诊断信息：用于判断高度上限是否命中、以及真实选择器是什么
    it('reports_composer_diagnostics', 0, () => {
      expect(script).assertContain(EDITABLE_SELECTOR);
      expect(script).assertContain('parentCls');
      // 注入是否真的落进文档、上限生效成了多少
      expect(script).assertContain('capStyle');
      expect(script).assertContain('maxH');
      expect(script).assertContain('scrollH');
    });

    // 祖先链与工具栏是否在 DOM —— 用于定位「上限把工具栏挤出视野」这类问题
    it('reports_ancestors_and_toolbar_presence', 0, () => {
      expect(script).assertContain('ancestors');
      expect(script).assertContain('chipTextInDom');
    });

    it('returns_json_string_and_survives_errors', 0, () => {
      expect(script).assertContain('JSON.stringify');
      expect(script).assertContain('catch');
    });
  });

  // 直接对应需求：「键盘弹出时输入框必须短于可显示区域」。
  // 公式由纯函数承载，因此这条保证是可单测的，而不是只能靠实机碰运气。
  describe('computeComposerCapPx', () => {
    it('scales_with_visible_height', 0, () => {
      // 平板横屏 + 键盘弹出：实测可视高度约 356 CSS px
      expect(computeComposerCapPx(356)).assertEqual(Math.round(356 * COMPOSER_MAX_RATIO));
    });

    it('is_always_shorter_than_the_visible_height', 0, () => {
      const heights: Array<number> = [171, 200, 250, 356, 400, 500, 727, 1200, 2000];
      for (const h of heights) {
        expect(computeComposerCapPx(h) < h).assertTrue();
      }
    });

    it('is_clamped_to_the_absolute_max', 0, () => {
      expect(computeComposerCapPx(4000)).assertEqual(COMPOSER_MAX_PX);
    });

    it('keeps_a_floor_on_tiny_viewports', 0, () => {
      expect(computeComposerCapPx(100)).assertEqual(COMPOSER_MIN_PX);
      expect(computeComposerCapPx(0)).assertEqual(COMPOSER_MIN_PX);
      expect(computeComposerCapPx(-5)).assertEqual(COMPOSER_MIN_PX);
    });
  });

  // 返回手势要靠这段脚本区分「网页弹层开着」与「只是在聊天」——
  // 实测两者 in canGoBack 上完全一样（都是 true），只有 DOM 能区分，
  // 所以这段脚本的探测条件一旦写歪，返回手势就会整体走错分支。
  describe('overlay probe', () => {
    const script: string = buildOverlayProbeScript();

    it('matches_the_aria_modal_markers_observed_on_device', 0, () => {
      // 实机实测：DeepSeek 的「系统设置」弹窗打开时 role=dialog 与 aria-modal 各 1 个
      expect(script).assertContain('[role="dialog"]');
      expect(script).assertContain('[aria-modal="true"]');
    });

    it('ignores_hidden_or_sizeless_dialogs', 0, () => {
      expect(script).assertContain("display === 'none'");
      expect(script).assertContain("visibility === 'hidden'");
      expect(script).assertContain('getBoundingClientRect');
      expect(script).assertContain('width < 80');
    });

    it('returns_a_number_and_is_guarded', 0, () => {
      expect(script).assertContain('return 1;');
      expect(script).assertContain('return 0;');
      expect(script).assertContain('catch');
    });

    // runJavaScript 的返回值是字符串化的，不同返回类型可能带引号，两种都要认；
    // 其余任何形态一律当「未打开」，避免误把返回让给网页
    it('parses_the_run_javascript_result_conservatively', 0, () => {
      expect(isOverlayOpenResult('1')).assertTrue();
      expect(isOverlayOpenResult('"1"')).assertTrue();
      expect(isOverlayOpenResult("'1'")).assertTrue();
      expect(isOverlayOpenResult(' true ')).assertTrue();
      expect(isOverlayOpenResult('0')).assertFalse();
      expect(isOverlayOpenResult('"0"')).assertFalse();
      expect(isOverlayOpenResult('false')).assertFalse();
      expect(isOverlayOpenResult('')).assertFalse();
      expect(isOverlayOpenResult('undefined')).assertFalse();
      expect(isOverlayOpenResult('probe-error')).assertFalse();
    });
  });
}
