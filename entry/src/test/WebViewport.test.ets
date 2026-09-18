import { describe, it, expect } from '@ohos/hypium';
import { buildUserAgent, isMobileUa, buildViewportFixScript, buildResizeNotifyScript,
  buildProbeScript, buildOverlayProbeScript, buildOverlayDismissScript, parseOverlayKind,
  isDismissClicked, buildComposerAutoHideScript, buildKeyboardStateScript, buildRetryFocusScript,
  COMPOSER_HIDDEN_CLASS, EDITOR_CARD_CLASS, EDITOR_MAX_VAR, EDITOR_MAX_RATIO, EDITOR_MAX_PX,
  OVERLAY_NONE, OVERLAY_DIALOG, OVERLAY_MENU, OVERLAY_CLOSABLE,
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

  // 返回手势要靠这两段脚本区分「网页弹窗」「网页菜单」「多选模式」——
  // 实测三者都不能只看 canGoBack：弹窗会把历史顶出一条、菜单与多选模式则完全不进历史，
  // 所以探测条件与关闭方式一旦写歪，返回手势就会整体走错分支。
  describe('overlay probe', () => {
    const script: string = buildOverlayProbeScript();

    it('matches_the_markers_observed_on_device', 0, () => {
      // 系统设置弹窗：role=dialog / aria-modal（实测可见元素 0→1）
      expect(script).assertContain('[role="dialog"]');
      expect(script).assertContain('[aria-modal="true"]');
      // 会话「…」菜单：role=menu（实测 0→1）
      expect(script).assertContain('[role="menu"]');
    });

    // 多选模式没有 role 标记：平板上是 aria-label="关闭" 的图标按钮，
    // 手机上「选择对话 / 分享选择」顶部则是**文字**「取消」（实测没有 aria-label）
    it('detects_closable_ui_by_aria_label_and_by_exact_text', 0, () => {
      expect(script).assertContain('[aria-label]');
      expect(script).assertContain('getAttribute');
      expect(script).assertContain('关闭');
      // 标签必须是全等匹配（^…$）：否则「取消订阅」这类文案会被当成关闭入口
      expect(script).assertContain('^(');
      // 文字按钮这一路：只认叶子节点 + 按钮尺寸，避免误判成页面里的普通文案
      expect(script).assertContain('innerText');
      expect(script).assertContain('children.length > 0');
      expect(script).assertContain('320');
    });

    it('ignores_hidden_or_sizeless_elements', 0, () => {
      expect(script).assertContain("display === 'none'");
      expect(script).assertContain("visibility === 'hidden'");
      expect(script).assertContain('getBoundingClientRect');
    });

    it('reports_the_kind_and_is_guarded', 0, () => {
      expect(script).assertContain(OVERLAY_DIALOG);
      expect(script).assertContain(OVERLAY_MENU);
      expect(script).assertContain(OVERLAY_CLOSABLE);
      expect(script).assertContain('catch');
    });

    // runJavaScript 的返回值是字符串化的（字符串会被再包一层引号），
    // 认不出来的一律当作「没有瞬时界面」，避免误把返回让给网页
    it('parses_the_kind_conservatively', 0, () => {
      expect(parseOverlayKind('dialog')).assertEqual(OVERLAY_DIALOG);
      expect(parseOverlayKind('"dialog"')).assertEqual(OVERLAY_DIALOG);
      expect(parseOverlayKind("'menu'")).assertEqual(OVERLAY_MENU);
      expect(parseOverlayKind(' closable ')).assertEqual(OVERLAY_CLOSABLE);
      expect(parseOverlayKind('')).assertEqual(OVERLAY_NONE);
      expect(parseOverlayKind('0')).assertEqual(OVERLAY_NONE);
      expect(parseOverlayKind('true')).assertEqual(OVERLAY_NONE);
      expect(parseOverlayKind('undefined')).assertEqual(OVERLAY_NONE);
      expect(parseOverlayKind('probe-error')).assertEqual(OVERLAY_NONE);
    });

    // 探测会连「是谁触发的」一起带出来（`kind|TAG|role|cls|WxH`），
    // 供日志定位；解析时要只取第一段，且完整串要能原样取出给日志
    it('keeps_the_hit_element_identity_for_logging', 0, () => {
      const raw: string = '"dialog|DIV|dialog|_4cbcd96|1100x900"';
      expect(parseOverlayKind(raw)).assertEqual(OVERLAY_DIALOG);
      expect(parseOverlayKind(raw, false)).assertEqual('dialog|DIV|dialog|_4cbcd96|1100x900');
      expect(parseOverlayKind('"menu|DIV|menu|_abc|120x80"')).assertEqual(OVERLAY_MENU);
      expect(parseOverlayKind('"closable|BUTTON||_x|28x28"')).assertEqual(OVERLAY_CLOSABLE);
    });
  });

  // 编辑历史消息 + 键盘弹出时隐藏主对话框：判定全靠结构（不依赖站点哈希类名），
  // 写歪了要么该隐藏时不隐藏、要么把正常输入框也隐藏掉，都属于明显回归
  describe('composer auto hide', () => {
    const script: string = buildComposerAutoHideScript();

    it('is_idempotent_and_exposes_an_apply_hook', 0, () => {
      expect(script).assertContain('__dsComposerAutoHide');
      expect(script).assertContain('__dsApplyComposerAutoHide');
      expect(script).assertContain("'already'");
    });

    // 键盘状态由应用侧推入（网页自己无法把「窗口变小」与「键盘弹起」分开）
    it('depends_on_the_keyboard_flag_pushed_by_the_app', 0, () => {
      expect(script).assertContain('__dsKeyboardUp');
      expect(script).assertContain(COMPOSER_HIDDEN_CLASS);
    });

    it('finds_the_composer_as_a_bottom_fixed_container', 0, () => {
      // 只认 fixed / sticky：曾经允许「底边贴底的非定位元素」，
      // 结果编辑态下把消息气泡里的编辑卡片当成主对话框藏掉，键盘立刻收起
      expect(script).assertContain("position === 'fixed'");
      expect(script).assertContain("position === 'sticky'");
      // 几何扫描仍然保留贴底 / 半屏等约束（高度阈值收到 0.4：
      // 消息列表 ds-virtual-list 也满足「sticky + 贴底」，会被误当成主对话框整块隐藏）
      expect(script).assertContain('vh * 0.4');
      expect(script).assertContain('vh - 32');
    });

    // 关键：主输入框自己也在固定底栏里，只有「焦点不在固定底栏内」才算内联编辑
    it('only_hides_while_the_focus_is_outside_the_bottom_card', 0, () => {
      expect(script).assertContain('isInBottomCard');
      expect(script).assertContain('inlineEdit');
      expect(script).assertContain('activeElement');
    });

    it('scrolls_the_edited_element_into_view_and_re_evaluates', 0, () => {
      expect(script).assertContain('scrollIntoView');
      expect(script).assertContain('focusin');
      expect(script).assertContain('focusout');
    });

    it('reports_its_state_for_diagnostics', 0, () => {
      expect(script).assertContain('__dsComposerAutoHideInfo');
      expect(script).assertContain('cardPos');
    });

    // 关键回归（键盘闪现）：绝不能隐藏「当前聚焦元素所在的容器」——
    // 那会让正在编辑的输入框立刻失焦、键盘随即收起（实机复现：hide 后约 35ms 键盘变 0）。
    // 容器里同时装着编辑卡片与主对话框时，只隐藏「不含焦点且贴底」的那个子元素。
    it('never_hides_a_container_holding_the_focused_element', 0, () => {
      expect(script).assertContain('containsActive');
      expect(script).assertContain('hideTargetFor');
      // 已经错误隐藏过的要能纠正回来
      expect(script).assertContain('__dsHiddenCard');
      // 底部固定容器只认 fixed / sticky，避免把消息气泡里的编辑卡片当成主对话框
      expect(script).assertContain("position === 'fixed'");
      expect(script).assertContain("position === 'sticky'");
    });

    // 问题一：含图片 + 长文本时，卡片的取消/保存按钮会被挤出可视区。
    // 做法是标记「内联编辑卡片」并用 CSS 限高（列向 flex，文本域自己滚动、按钮留在卡内）
    it('marks_the_inline_edit_card_and_keeps_buttons_visible', 0, () => {
      expect(script).assertContain(EDITOR_CARD_CLASS);
      expect(script).assertContain('findEditCard');
      // 找到卡片后按「贴底对齐」滚动 —— 按钮行在卡片下方，居中反而可能被键盘挡住
      expect(script).assertContain("block: 'end'");
    });

    // 问题二：编辑态是异步渲染的，程序化 focus 可能被顶掉 → 焦点丢了要补回来；
    // 同时把焦点事件上报给应用侧，由应用侧在键盘没弹起时兜底
    it('heals_lost_focus_and_reports_it_to_the_app', 0, () => {
      expect(script).assertContain('scheduleFocusHeal');
      expect(script).assertContain('__dsLastEditFocus');
      expect(script).assertContain('__dsFocus:');
      expect(script).assertContain('refocus');
      // 只在焦点真的丢了、且没有别的可编辑元素接管时才补，避免打乱光标
      expect(script).assertContain('document.activeElement');
    });

    // 点卡片空白处也要能开始编辑（用户的手指天然带 user activation，键盘能正常拉起）
    // 收起态点击卡片不再坍塌、也不再需要点两次：脚本不再挂 pointerdown 去补聚焦
    // （它会在 pointerdown 与 click 之间改变布局）。这条锁住「不挂 pointerdown」这个决定。
    it('does_not_hook_pointerdown_to_force_focus', 0, () => {
      expect(script).assertContain('__dsEditScrolled');
      expect(script.indexOf('pointerdown')).assertEqual(-1);
    });

    it('exposes_a_retry_hook_for_the_app_side', 0, () => {
      expect(script).assertContain('__dsRetryEditFocus');
      const retry: string = buildRetryFocusScript();
      expect(retry).assertContain('__dsRetryEditFocus');
      expect(retry).assertContain('not-installed');
    });

    // 内联编辑卡片的限高规则必须进样式表，且要能覆盖「直接子元素」那条上限
    it('injects_edit_card_rules_with_enough_specificity', 0, () => {
      const fix: string = buildViewportFixScript(768);
      expect(fix).assertContain('div.' + EDITOR_CARD_CLASS);
      expect(fix).assertContain(EDITOR_MAX_VAR);
      expect(fix).assertContain('min-height:0 !important');
      // 卡片里的图片不参与顶高
      expect(fix).assertContain('max-height:20vh !important');
    });

    it('keyboard_state_script_toggles_the_flag_and_reports_state', 0, () => {
      const up: string = buildKeyboardStateScript(true);
      const down: string = buildKeyboardStateScript(false);
      expect(up).assertContain('window.__dsKeyboardUp = true');
      expect(up).assertContain('__dsApplyComposerAutoHide');
      expect(down).assertContain('window.__dsKeyboardUp = false');
      // 回带判定详情，实机排查不必再单独出诊断包
      expect(up).assertContain('__dsComposerAutoHideInfo');
      expect(up).assertContain('JSON.stringify');
    });

    // 隐藏规则必须写进注入的样式表里
    it('injects_the_hide_rule_into_the_style_tag', 0, () => {
      const fix: string = buildViewportFixScript(768);
      expect(fix).assertContain('.' + COMPOSER_HIDDEN_CLASS + '{display:none !important;}');
    });
  });

  describe('overlay dismiss', () => {
    const script: string = buildOverlayDismissScript();

    it('tries_close_affordance_then_trigger_then_outside_click', 0, () => {
      expect(script).assertContain('关闭');
      const closeHit: number = script.indexOf('clicked-close');
      const triggerHit: number = script.indexOf('clicked-trigger');
      const outsideHit: number = script.indexOf('clicked-outside');
      expect(closeHit > 0).assertTrue();
      expect(triggerHit > 0).assertTrue();
      expect(outsideHit > 0).assertTrue();
      expect(closeHit < triggerHit).assertTrue();
      expect(triggerHit < outsideHit).assertTrue();
      // 文字「取消 / 关闭」按钮也要点（手机上选择对话/分享选择就是它）
      expect(script).assertContain('innerText');
    });

    // 「展开态触发按钮再点一次」是最贴近用户操作的收起方式
    it('clicks_the_expanded_trigger_to_collapse', 0, () => {
      expect(script).assertContain('[aria-expanded="true"]');
      expect(script).assertContain('clicked-trigger');
    });

    // 关键回归（窄屏 / 抽屉形态）：只能把外部点击派发到 body，
    // 绝不能按坐标点内容区 —— 那里正是抽屉遮罩，「收起侧栏」会被一起触发
    it('never_clicks_by_coordinates_into_the_drawer_backdrop', 0, () => {
      expect(script).assertContain('clicked-outside-body');
      expect(script).assertContain('document.body');
      // 旧的按坐标取元素的做法必须已经去掉
      expect(script.indexOf('elementFromPoint') < 0).assertTrue();
      expect(script.indexOf('clicked-outside\'') < 0).assertTrue();
    });

    it('fires_real_pointer_events_with_coordinates', 0, () => {
      // 合成事件必须带坐标（不是 0,0）且冒泡，否则站点的外部点击判定可能不认
      expect(script).assertContain('mousedown');
      expect(script).assertContain('mouseup');
      expect(script).assertContain('clientX');
      expect(script).assertContain('bubbles: true');
    });

    it('reports_what_it_did', 0, () => {
      expect(script).assertContain('clicked-close');
      expect(script).assertContain('none:');
      expect(script).assertContain('catch');
    });

    // 回归：runJavaScript 的字符串返回值带引号，直接拿原文判断会把「点到了」
    // 误判成「没点到」，从而多走一次兜底后退（把网页翻走）
    it('parses_the_result_as_quoted_by_run_javascript', 0, () => {
      expect(isDismissClicked('"clicked-outside"')).assertTrue();
      expect(isDismissClicked('"clicked-close"')).assertTrue();
      expect(isDismissClicked('clicked-outside')).assertTrue();
      expect(isDismissClicked("'clicked-outside-body'")).assertTrue();
      expect(isDismissClicked('"none:no-target"')).assertFalse();
      expect(isDismissClicked('"none:error"')).assertFalse();
      expect(isDismissClicked('')).assertFalse();
      expect(isDismissClicked('undefined')).assertFalse();
    });
  });
}
