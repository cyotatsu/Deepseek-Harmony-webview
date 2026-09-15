/**
 * 网页输入焦点防护。
 *
 * 背景问题：点聊天里的图片会莫名其妙弹出软键盘。
 *
 * 造成这件事有两条可能路径，本模块与 Web 组件的两个官方属性一起把两条都堵上：
 *
 * **路径一（内核自动行为）**：键盘收起时输入框仍持有焦点（BlurOnKeyboardHideMode 默认为
 * SILENT —— 键盘隐藏时不失焦），此后点图片让 Web 组件的焦点 / 激活状态发生变化，内核按
 * WebSoftKeyboardBehaviorMode.DEFAULT 的语义「自动显示软键盘」。这条由 Web 组件的
 * `blurOnKeyboardHideMode(BlurOnKeyboardHideMode.BLUR)` 与
 * `setSoftKeyboardBehaviorMode(DISABLE_AUTO_KEYBOARD_ON_ACTIVE)` 消除（见 Index.ets）。
 *
 * **路径二（网页自身行为）**：网页自己把焦点移回输入框（例如把
 * 「点击输入区任意位置都聚焦输入框」的处理器挂在了包含图片预览的容器上，
 * 点图片冒泡上去就把输入框聚焦了）。内核侧无法区分这次聚焦是不是用户本意，
 * 因此需要本模块的脚本：**只在「用户刚点了图片」这一种情况下**抑制随后落到
 * 输入框上的焦点。
 *
 * 防误伤设计（很重要）：
 *  · 只认图片类目标（IMG / PICTURE / FIGURE 及其向上 4 层祖先），
 *    点发送按钮（通常是 svg / button）、点加号、点输入框本身都不受影响 ——
 *    「发送后网页把焦点移回输入框」这种正常行为因此不会被破坏；
 *  · 每次点击**最多抑制一次**：即便网页在 blur 之后又把焦点抢回来，也不会形成
 *    「blur → 网页抢焦点 → 再 blur」的死循环；
 *  · 标记带 600ms 自动过期，避免一次点击的影响泄漏到后续操作。
 *
 * 本模块只做**纯字符串逻辑**（脚本拼装），不依赖系统 API，可在宿主机上单测。
 */

/**
 * 是否启用「点图片不聚焦输入框」的防护。
 *
 * 若实机发现它误伤了某个正常交互（例如点图片后确实需要输入），把它改成 false 即可，
 * 官方那两项内核开关仍在生效、不会一起失效。
 */
export const ENABLE_IMAGE_TAP_FOCUS_GUARD: boolean = true;

/** 视作「图片」的标签，命中其一即认为是图片点击 */
const IMAGE_TAGS: string = 'IMG,PICTURE,FIGURE';

/** 向上查找祖先的层数上限 */
const IMAGE_ANCESTOR_DEPTH: number = 4;

/** 「刚点过图片」标记的有效期（毫秒），超时自动失效 */
const IMAGE_TAP_FLAG_TTL_MS: number = 600;

/** 判定「可输入元素」的选择器，与输入框高度上限使用同一套 */
export const EDITABLE_SELECTOR: string = 'textarea,input,[contenteditable="true"]';

/**
 * 生成焦点防护脚本。
 *
 * 返回 'installed' / 'already' / 'error'，便于在日志里确认注入是否成功。
 */
export function buildFocusGuardScript(): string {
  return `(function () {
    try {
      if (window.__dsFocusGuard) { return 'already'; }
      window.__dsFocusGuard = true;

      var EDITABLE = '${EDITABLE_SELECTOR}';
      var IMAGE_TAGS = '${IMAGE_TAGS}';
      var DEPTH = ${IMAGE_ANCESTOR_DEPTH};
      var TTL = ${IMAGE_TAP_FLAG_TTL_MS};

      var tappedImage = false;
      var resetTimer = -1;

      function isEditable(el) {
        return !!(el && el.matches && el.matches(EDITABLE));
      }

      function isImageTarget(target) {
        var el = target;
        for (var i = 0; el && i < DEPTH; i++) {
          if (el.tagName && IMAGE_TAGS.indexOf(el.tagName) >= 0) { return true; }
          el = el.parentElement;
        }
        return false;
      }

      document.addEventListener('pointerdown', function (e) {
        tappedImage = isImageTarget(e.target);
        if (resetTimer !== -1) { clearTimeout(resetTimer); resetTimer = -1; }
        if (tappedImage) {
          resetTimer = setTimeout(function () {
            tappedImage = false;
            resetTimer = -1;
          }, TTL);
        }
      }, true);

      document.addEventListener('focusin', function (e) {
        if (!tappedImage) { return; }
        var t = e.target;
        if (!isEditable(t)) { return; }
        // 先清标记再 blur：每次点击最多抑制一次，杜绝反复抢焦点的死循环
        tappedImage = false;
        try { t.blur(); } catch (err) { }
      }, true);

      return 'installed';
    } catch (err) {
      return 'error';
    }
  })();`;
}
