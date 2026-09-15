/**
 * Web 视口（viewport）与窗口尺寸适配。
 *
 * 背景：本应用要跑在手机全屏 / 悬浮小窗 / 平板全屏 / 平板自由多窗 / 2in1 等多种窗口形态下。
 * 窗口宽度连续可变，网页必须跟着切换桌面端/移动端布局，否则会出现
 * 「窗口已经很窄、网页仍是桌面大屏布局」的挤压与错位。
 *
 * 关键结论（均已对照 SDK 声明核实）：
 *
 *  1. **viewport 是否生效取决于 UA 是否含 Mobile**。
 *     web.d.ts 的 metaViewport 注释原文：
 *     「If a User-Agent does not contain the Mobile field, the viewport property in the
 *      meta tag is disabled by default. In this case, you can explicitly set the
 *      metaViewport property to true to overwrite the disabled state.」
 *     平板等形态的默认 UA 不含 Mobile，于是网页的 `width=device-width` 不被解析，
 *     布局视口退回到默认宽度（约 980px）→ 窗口再窄网页也按大屏排版。
 *     **因此正确的解法是显式调用 Web 组件的 metaViewport(true)，而不是去改 UA。**
 *     实机已验证：平板 UA 为 `(Tablet; OpenHarmony ...)`、`mobileToken=false`，
 *     开启后 `clientW` 精确等于「窗口宽度 ÷ dpr」。
 *
 *  2. **2in1 设备不支持 viewport**（同一段注释）：
 *     「If the device is 2-in-1, the viewport property is not supported ...
 *      the viewport property will not be parsed and a default layout will be used.」
 *     2in1 走的是桌面式布局（布局视口跟随窗口），本身就随窗口宽度重排，
 *     所以对它不做 UA/viewport 干预，只发 resize 通知（见下）。
 *
 *  3. **不采用「宽窗用桌面 UA、窄窗用移动 UA」的动态切换方案**：
 *     `setCustomUserAgent` 只对**后续加载**生效，切换断点必须重载页面 ——
 *     在自由多窗拖拽时窗口宽度连续变化，会反复跨断点，导致频繁重载、闪烁，
 *     并且会丢掉 SPA 里正在输入的内容。而 `metaViewport(true)` 让网页自身的
 *     响应式 CSS 依据**实时布局视口宽度**连续重排，天然覆盖所有宽度，无需重载。
 *
 *  4. **不使用 layoutMode(WebLayoutMode.FIT_CONTENT)**：官方注释明确
 *     「Width adaptation is not supported. Only height adaptation is supported.」
 *     且「Frequent changes to the page width and height will trigger a re-layout」——
 *     既解决不了宽度问题，又恰好命中自由多窗拖拽的场景。
 *
 * 本模块只做**纯字符串逻辑**（脚本拼装与 UA 拼装），不依赖任何系统 API，
 * 因此可以在宿主机上跑单元测试。
 */

/** 注入样式节点的 id，重复注入时据此去重 */
export const VIEWPORT_STYLE_ID: string = 'ds-viewport-style';

/**
 * 输入框高度上限：占「当前可视高度」的比例。
 *
 * 需求是「键盘弹出时，输入框必须短于可显示区域」。只写一个 `vh` 值做得到，
 * 但它默认 `vh` 的基准正确；一旦内核没有按预期收缩布局视口，比例就会失真
 *（例如键盘以浮层方式覆盖时，`vh` 仍按整窗高度算 → 上限可能反而大于可视区）。
 *
 * 因此这里改成**由脚本按实时可视高度算出像素上限**，写进 CSS 变量
 * `--ds-composer-max`，再由样式规则 `max-height:var(--ds-composer-max,32vh)` 取用：
 *   · 可视高度 = `documentElement.clientHeight`（键盘弹出时已被 RESIZE_CONTENT 收缩）
 *     与 `visualViewport.height` 中较小者；
 *   · 上限 = clamp(MIN_PX, 可视高度 × RATIO, MAX_PX)；
 *   · 键盘弹出/收起会触发 resize，脚本重新计算，因此**始终跟随当前可视区**。
 *
 * 由此得到的硬保证：只要可视高度 ≥ MIN_PX / RATIO（≈171 CSS px），
 * 输入框上限就 ≤ 可视高度的 28%，必然短于可显示区域。
 */
export const COMPOSER_MAX_RATIO: number = 0.28;

/** 输入框高度上限的绝对上限（px）。防止无键盘时按比例算出过大的框 */
export const COMPOSER_MAX_PX: number = 160;

/** 输入框高度下限（px）。可视区极小时仍保证至少能看两行 */
export const COMPOSER_MIN_PX: number = 48;

/**
 * 脚本未执行时的 `vh` 兜底值。
 *
 * 正常流程下 CSS 变量一定会被写入，这条只是保险：万一脚本没跑（或自定义属性
 * 不被支持），仍然有一个相对可视区的上限，而不是完全放开。
 */
export const COMPOSER_FALLBACK_VH: number = 32;

/** 承载输入框高度上限的 CSS 自定义属性名 */
export const COMPOSER_CAP_VAR: string = '--ds-composer-max';

/**
 * 「隐藏主对话框」用的类名。
 *
 * 场景：**编辑历史消息**时，网页会在消息气泡里就地展开一个编辑框；此时软键盘弹出，
 * 底部那个主对话框（输入框 + 深度思考/智能搜索 + 附件 + 发送按钮）既没被隐藏、
 * 又占掉一截可视区，正在编辑的内容反而被挤住。给它加这个类、用 `display:none` 让位；
 * 键盘收起或退出编辑态时移除，恢复正常显示。
 */
export const COMPOSER_HIDDEN_CLASS: string = 'ds-composer-hidden';

/**
 * 「内联编辑卡片」用的类名 —— 编辑历史消息时，网页在消息气泡位置就地展开的那个
 * 卡片（文本域 + 取消 / 保存按钮）。
 *
 * 为什么需要单独处理：实测「历史记录含图片 + 编辑长文本」时，卡片的**取消 / 保存按钮
 * 会被挤出可视区**。原因是卡片的整体高度没有被限制 —— 现有规则只压了 `textarea`
 * 和「直接子元素」，而图片、外层留白等仍会把卡片顶高。
 * 这里由 {@link buildComposerAutoHideScript} 给卡片加类，再用 CSS 把它约束成
 * 「列向 flex + 限高」，让文本域自己滚动、按钮行始终留在卡片内。
 */
export const EDITOR_CARD_CLASS: string = 'ds-inline-editor';

/**
 * 「编辑卡片里的按钮行」用的类名 —— 由 {@link buildComposerAutoHideScript} 动态加到
 * 「按钮所在的、卡片的最外层子元素」上（也就是按钮行的直接父级，通常是站点的一个
 * 工具栏 div）。CSS 据此把它 `position:sticky; bottom:0`：
 *
 * 卡片被限高后文本域会滚动，但站点的按钮行**不一定在卡片最后一位**（它后面可能还有
 * 提示文案、占位节点等）。sticky 让按钮行钉在卡片底部，无论它原来在文档流的哪里，
 * 都能留在可视区内 —— 比"用 order 把它拖到最后"侵入性小得多。
 *
 * 只加给「卡片的最外层子元素」，是为了拿 `bottom:0` 相对卡片 padding box 定位；
 * 加在更深的层级上，贴的就不是卡片底边了。
 */
export const EDITOR_ACTION_ROW_CLASS: string = 'ds-edit-actions';

/**
 * 内联编辑卡片高度上限占「当前可视高度」的比例。
 *
 * 取值为什么是 0.62：卡片必须**连着按钮行**一起落在可视区内，所以上限不能吃掉整个
 * 可视高度 —— 键盘弹出时网页顶部还有消息列表、底部还有（正在让位的）主对话框。
 * 0.62 留给文本域约六成可视高度（手机上约 5~12 行），其余留给上下的正常界面；
 * 超出的部分由文本域自己滚动吸收，按钮行始终留在卡片内。
 */
export const EDITOR_MAX_RATIO: number = 0.62;

/** 内联编辑卡片高度上限的绝对值（px）：防止在电脑 / 2in1 大屏上被算得过大 */
export const EDITOR_MAX_PX: number = 560;

/** 内联编辑卡片高度下限（px）：可视区极小时也要能放下文本域 + 按钮行 */
export const EDITOR_MIN_PX: number = 140;

/** 承载内联编辑卡片高度上限的 CSS 自定义属性名 */
export const EDITOR_MAX_VAR: string = '--ds-editor-max';

/** 承载「按钮行贴底所需内边距」的 CSS 自定义属性名（避免按钮行被卡片圆角/内边距裁掉） */
export const EDITOR_BOTTOM_PAD_VAR: string = '--ds-editor-action-pad';

/** 卡片内图片的高度上限（占可视高度的比例）：图片不能和按钮行抢空间 */
export const EDITOR_IMAGE_MAX_VH: number = 20;

/**
 * 内联编辑卡片的样式规则（由 {@link buildViewportFixScript} 注入到样式表里）。
 *
 * 解决的是**问题一**：历史记录含图片 + 编辑长文本时，卡片的「取消 / 确认」按钮
 * 被挤出可视区。三层约束缺一不可：
 *
 *  1. **卡片硬限高 + 列向 flex**：上限由 `{@link EDITOR_MAX_VAR}` 给出（按实时可视
 *     高度算出的像素值），`overflow:hidden` 保证卡片永远不会高于上限。这样卡片
 *     「总高 ≤ 62% 可视高度」，按钮行必然在卡片内部。
 *  2. **文本域是唯一的伸缩项**：`flex:1 1 auto; min-height:0` —— `min-height:0` 是关键，
 *     否则 flex 项的默认 `min-height:auto` 会让长文本把文本域顶到内容高度，
 *     卡片再被顶高（限高就形同虚设）。文本域内部的滚动条吸收超长内容。
 *  3. **按钮行贴底置顶**：按钮行的直接父元素被脚本标成 {@link EDITOR_ACTION_ROW_CLASS}
 *     （见 buildComposerAutoHideScript），这里给它 `position:sticky; bottom:0`。
 *     既然卡片是 `overflow:hidden`，卡片本身不滚动，"贴底"就等价于**固定在卡片底部** ——
 *     即使站点的按钮行在卡片内不在最后一位、或后面还有别的节点，按钮也不会被卷走。
 *
 * 为什么按钮行不加 `order:999`：靠 CSS `order` 把按钮强行拖到卡片末尾会改变站点
 * 自己的信息层级，且一旦按钮不在卡片直接子级就完全失效。sticky 是"就地固定"，
 * 不改变文档流顺序，对站点布局的侵入最小。
 *
 * 选择器一律带 `div.` 前缀并写在既有规则之后：站点自己的类名（哈希类）特异性与
 * `div.自定义类` 相同，靠"后写"取胜；而这条又必须盖过上面那条「卡片直接子元素」
 * 的上限（`div:has(> textarea) > *`），所以顺序不能调。
 */
export function buildEditorCardCss(): string {
  return 'div.' + EDITOR_CARD_CLASS + '{display:flex !important;flex-direction:column !important;' +
    'max-height:var(' + EDITOR_MAX_VAR + ',' + COMPOSER_FALLBACK_VH + 'vh) !important;' +
    'overflow:hidden !important;}' +
    'div.' + EDITOR_CARD_CLASS + ' > *{max-height:none !important;flex:0 0 auto !important;}' +
    'div.' + EDITOR_CARD_CLASS + ' textarea,div.' + EDITOR_CARD_CLASS +
    ' [contenteditable="true"]{flex:1 1 auto !important;min-height:0 !important;' +
    'max-height:none !important;overflow-y:auto !important;}' +
    // 按钮行：sticky 贴卡片底部。padding-bottom 兜住卡片自身的底部内边距，
    // 否则按钮行会有一部分落在卡片 padding 里被 overflow:hidden 裁掉一点边
    'div.' + EDITOR_ACTION_ROW_CLASS + '{position:sticky !important;bottom:0 !important;' +
    'flex:0 0 auto !important;z-index:2 !important;' +
    'padding-bottom:var(' + EDITOR_BOTTOM_PAD_VAR + ',0px) !important;}' +
    // 卡片里的图片/视频按可视高度限高：图片 + 长文本一起顶高卡片是本次问题的直接成因之一
    'div.' + EDITOR_CARD_CLASS + ' img,div.' + EDITOR_CARD_CLASS + ' video{' +
    'max-height:' + EDITOR_IMAGE_MAX_VH + 'vh !important;width:auto !important;' +
    'object-fit:contain !important;}';
}

/**
 * 把 composer 的高度压回「输入框上限」——同时管住父容器**和它的直接子元素**。
 *
 * 实机 DOM 实测（键盘弹出、可视高度 353 CSS px、输入框内容 1680 字）：
 *   TEXTAREA                       h=99    ← 被上限压住
 *   DIV._24fad49（直接父）          h=336   ← 多出的 237px 就是那片空白
 *     ├ DIV.ds-scroll-area__gutters h=336   ← 兄弟元素，撑高了父容器
 *     ├ TEXTAREA                    h=99
 *     └ DIV.b13855df                h=336   ← 兄弟元素，撑高了父容器
 *   DIV._020ab5b (flex)            h=394
 *   DIV._77cefa5 (overflow:hidden) h=400   ← 比可视区(353)还高，把底部工具栏裁掉
 *   → chipTextInDom: true          ← 工具栏一直在 DOM 里，只是被裁掉了
 *
 * 关键点：父容器的 336px **来自它的子元素**，所以只写 `height:auto` 是没用的
 *（实测：`:has()` 规则匹配成功，但祖先高度一格未变）。页面把「输入框未封顶时算出的
 * 高度」同时写在了直接父和那两个兄弟元素上，因此必须**一并**限制。
 * 父容器一收缩，上面两层随之收缩，composer 回到可视区内，工具栏自然重新可见。
 *
 * 用 `:has()` 而不是页面那串哈希类名：哈希随站点构建而变，`div:has(> textarea)`
 * 只依赖结构，稳定得多。`:has()` 自 Chromium 105 起支持，本设备为 144。
 */
export const COMPOSER_UNSTRETCH_CSS: string =
  'div:has(> textarea){height:auto !important;min-height:0 !important;flex:0 0 auto !important;}' +
  'div:has(> textarea) > *{max-height:var(--ds-composer-max,32vh) !important;}';

/**
 * 由「当前可视高度」计算输入框高度上限（px）。
 *
 * 纯函数，便于单测 —— 脚本里用的是同一组常量与同一个公式，
 * 这样「上限必然小于可视高度」这条保证可以直接用单测钉住，而不是只靠实机碰运气。
 */
export function computeComposerCapPx(visibleHeightPx: number): number {
  if (!visibleHeightPx || visibleHeightPx <= 0) {
    return COMPOSER_MIN_PX;
  }
  const scaled: number = visibleHeightPx * COMPOSER_MAX_RATIO;
  const clamped: number = Math.min(COMPOSER_MAX_PX, Math.max(COMPOSER_MIN_PX, scaled));
  return Math.round(clamped);
}

/**
 * 是否在 User-Agent 中附加 `Mobile` 标记。
 *
 * **默认关闭**，因为只需要 `metaViewport(true)` 就能让 viewport 生效，
 * 而附加 Mobile 还有**额外副作用**：站点会据此改发移动端页面。
 * 在平板/2in1 全屏这种大屏场景下，强制移动端页面反而会降低体验（当前是正常的）。
 *
 * 什么时候需要打开：实机测试后若发现 probe 日志里 `mobileToken=false` 且
 * `clientW` 明显不随窗口宽度变化（即 metaViewport 覆盖没生效），
 * 才把它改为 true 作为兜底 —— 这会顺带让站点走移动端页面。
 */
export const APPEND_MOBILE_UA_TOKEN: boolean = false;

/** 附加到 UA 的移动端标记 */
export const MOBILE_UA_TOKEN: string = 'Mobile';

/** 窗口尺寸稳定多久之后才通知网页（毫秒）。自由多窗拖拽时 onAreaChange 会高频触发 */
export const VIEWPORT_RESIZE_DEBOUNCE_MS: number = 260;

/** 判定「可输入元素」的选择器，与输入框高度上限使用同一套 */
export const EDITABLE_SELECTOR: string = 'textarea,input,[contenteditable="true"]';

/**
 * 组装 Web 的 User-Agent。
 *
 * 保持内核默认 UA 不变（它带有正确的设备身份：Phone / Tablet / PC），
 * 只做两件事：附加本应用的产品标识；以及在兜底模式下附加 Mobile 标记。
 */
export function buildUserAgent(baseUa: string, productPrefix: string,
  versionName: string, appendMobile: boolean = APPEND_MOBILE_UA_TOKEN): string {
  const base: string = baseUa && baseUa.length > 0 ? baseUa : '';
  const parts: Array<string> = [];
  if (base.length > 0) {
    parts.push(base);
  }
  if (appendMobile && !isMobileUa(base)) {
    parts.push(MOBILE_UA_TOKEN);
  }
  if (productPrefix.length > 0) {
    parts.push(versionName.length > 0 ? `${productPrefix}/${versionName}` : productPrefix);
  }
  return parts.join(' ');
}

/** UA 是否已含 Mobile 标记（决定内核是否默认解析 viewport） */
export function isMobileUa(ua: string): boolean {
  return /mobile/i.test(ua);
}

/**
 * 视口修正脚本。
 *
 * 做三件事：
 *  1. **把布局视口宽度显式设成「应用窗口宽度」**（`viewportWidthVp`，单位 vp ≈ CSS px）。
 *     不能依赖网页自带的 `width=device-width`：Chromium 里 `device-width` 指的是
 *     **屏幕**宽度而不是窗口宽度。全屏时两者恰好相等所以看不出问题；但在**自由多窗 /
 *     悬浮窗**下窗口远窄于屏幕，页面会按整屏宽度排版再整体缩小塞进小窗 ——
 *     表现就是「UI 显得很小」。显式给出窗口宽度后，1 CSS px 就等于 1 vp，恢复正常尺寸，
 *     同时网页的响应式 CSS 也按真实窗口宽度断点。
 *     只替换 `width=` 这一段，保留站点自己的 `maximum-scale` / `user-scalable` 等设置。
 *  2. 页面没有 viewport 声明时补一个（兜底）。
 *  3. 给输入框加高度上限，避免内容过多时无限向上扩张。
 *
 * 返回 'ok:<最终 content>' / 'no-head' / 'error'，供应用侧日志确认注入结果 ——
 * 这三者必须可区分，否则「样式没生效」在应用侧完全无声。
 *
 * @param viewportWidthVp 应用窗口宽度（vp）。≤ 0 表示尚未测得，退回 `width=device-width`。
 */
export function buildViewportFixScript(viewportWidthVp: number = 0): string {
  const targetWidth: number = viewportWidthVp > 0 ? Math.round(viewportWidthVp) : 0;
  return `(function () {
    try {
      var d = document;
      if (!d || !d.head) { return 'no-head'; }

      var m = d.querySelector('meta[name="viewport"]');
      if (!m) {
        m = d.createElement('meta');
        m.setAttribute('name', 'viewport');
        d.head.appendChild(m);
      }
      var content = m.getAttribute('content') || '';
      var target = ${targetWidth};
      if (target > 0) {
        // 显式指定布局视口宽度 = 应用窗口宽度（device-width 是屏幕宽度，不能用）
        var lower = content.toLowerCase();
        var wi = lower.indexOf('width=');
        if (wi >= 0) {
          var rest = content.substring(wi);
          var comma = rest.indexOf(',');
          content = content.substring(0, wi) + 'width=' + target +
            (comma >= 0 ? rest.substring(comma) : '');
        } else {
          content = 'width=' + target + (content ? ', ' + content : ', initial-scale=1');
        }
      } else if (content.toLowerCase().indexOf('width') < 0) {
        content = 'width=device-width, initial-scale=1, viewport-fit=cover';
      }
      m.setAttribute('content', content);

      if (!d.getElementById('${VIEWPORT_STYLE_ID}')) {
        var s = d.createElement('style');
        s.id = '${VIEWPORT_STYLE_ID}';
        // 上限由 JS 按实时可视高度算成像素值写入 CSS 变量；
        // var() 的兜底值保证即使脚本没跑，也仍有一个相对可视区的上限。
        s.textContent =
          '${COMPOSER_UNSTRETCH_CSS}' +
          'textarea,[contenteditable="true"]{max-height:var(${COMPOSER_CAP_VAR},${COMPOSER_FALLBACK_VH}vh) !important;overflow-y:auto !important;}' +
          // 编辑历史消息 + 键盘弹出时，主对话框让位（类由 buildComposerAutoHideScript 增删）
          '.${COMPOSER_HIDDEN_CLASS}{display:none !important;}' +
          // 内联编辑卡片：限高 + 列向 flex + 按钮行 sticky 贴底 —— 取消/确认按钮
          // 在「图片 + 长文本」下也不会被挤出可视区。详见 buildEditorCardCss 的说明。
          '${buildEditorCardCss()}';
        d.head.appendChild(s);
      }

      // 按当前可视高度计算输入框上限，并在键盘弹出/收起时重算。
      // 幂等：只安装一次，避免重复叠加监听器。
      if (!window.__dsComposerCap) {
        window.__dsComposerCap = true;
        var applyCap = function () {
          try {
            var vv = window.visualViewport;
            var h = d.documentElement ? d.documentElement.clientHeight : 0;
            if (vv && vv.height && vv.height < h) { h = vv.height; }
            if (!h || h <= 0) { return; }
            var cap = Math.min(${COMPOSER_MAX_PX},
              Math.max(${COMPOSER_MIN_PX}, h * ${COMPOSER_MAX_RATIO}));
            cap = Math.round(cap);
            d.documentElement.style.setProperty('${COMPOSER_CAP_VAR}', cap + 'px');
            // 内联编辑卡片的上限：按**实时可视高度**算，且必须明显小于可视高度 ——
            // 卡片连同按钮行一起落进可视区，靠的就是这个上限。
            var editCap = Math.min(${EDITOR_MAX_PX},
              Math.max(${EDITOR_MIN_PX}, h * ${EDITOR_MAX_RATIO}));
            editCap = Math.round(editCap);
            d.documentElement.style.setProperty('${EDITOR_MAX_VAR}', editCap + 'px');
            // 按钮行 sticky 贴底时，卡片自身的底部内边距要补进按钮行的 padding，
            // 否则按钮行有概率被卡片的 overflow:hidden 裁掉下一小截
            var cardPad = 0;
            var cardEl = window.__dsEditCard;
            if (cardEl && document.contains(cardEl)) {
              cardPad = parseFloat(window.getComputedStyle(cardEl).paddingBottom) || 0;
            }
            d.documentElement.style.setProperty('${EDITOR_BOTTOM_PAD_VAR}',
              Math.max(0, Math.round(cardPad)) + 'px');
            window.__dsComposerCapInfo = {
              visibleH: Math.round(h),
              capPx: cap,
              editCapPx: editCap,
              ratio: Number((cap / h).toFixed(3))
            };
          } catch (e) { }
        };
        applyCap();
        window.addEventListener('resize', applyCap);
        if (window.visualViewport) {
          // 键盘为浮层时可能只改可视视口、不触发 window.resize，因此两个都监听
          window.visualViewport.addEventListener('resize', applyCap);
        }
      }
      return 'ok:' + content;
    } catch (e) {
      return 'error';
    }
  })();`;
}

/**
 * 把「软键盘是否弹起」推给网页。
 *
 * 为什么由应用侧推、而不是网页自己猜：网页侧只能靠「可视高度变小」推断，
 * 而**自由多窗 / 悬浮窗拖拽同样会让可视高度变小**，两者无法区分，会误判。
 * ArkUI 侧有权威信号 —— `avoidAreaChange` 的 `TYPE_KEYBOARD` 底部避让高度，
 * 键盘弹起时 > 0、收起时为 0。
 *
 * 写入 `window.__dsKeyboardUp` 并立即重算一次主对话框的显隐。
 */
export function buildKeyboardStateScript(keyboardUp: boolean): string {
  const flag: string = keyboardUp ? 'true' : 'false';
  return `(function () {
    try {
      window.__dsKeyboardUp = ${flag};
      if (window.__dsApplyComposerAutoHide) { window.__dsApplyComposerAutoHide(); }
      // 回带一次判定详情：实机出问题时，日志里直接能看到「有没有找到主对话框、
      // 它是不是固定底栏、当前算不算内联编辑态」，不必再单独出诊断包
      var info = window.__dsComposerAutoHideInfo || null;
      return 'kb:' + (window.__dsKeyboardUp ? 'up' : 'down') + ' ' + JSON.stringify(info);
    } catch (e) {
      return 'kb-error';
    }
  })();`;
}

/**
 * 让网页重新聚焦「当前编辑元素」并回报结果。
 *
 * 用途：应用侧确认过键盘没弹起来时调用 —— 先 `blur()` 再 `focus()` 会产生一次新的
 * focus 事件，配合此刻临时切回 `WebSoftKeyboardBehaviorMode.DEFAULT`，
 * 内核的「焦点驱动」路径就会把软键盘拉起（DISABLE_AUTO_KEYBOARD_ON_ACTIVE 只保证
 * 组件激活状态切换时不自动弹键盘，本身不阻止焦点驱动这一路）。
 *
 * 注意 `inputMethod` 的 showSoftKeyboard 需要系统级权限 CONNECT_IME_ABILITY，
 * 普通应用调用会抛 201，因此这里不采用那条路。
 */
export function buildRetryFocusScript(): string {
  return `(function () {
    try {
      if (!window.__dsRetryEditFocus) { return 'not-installed'; }
      return window.__dsRetryEditFocus();
    } catch (e) {
      return 'retry-error';
    }
  })();`;
}

/**
 * 安装「编辑历史消息时隐藏主对话框」的脚本。
 *
 * 需求：**键盘弹出 + 正在内联编辑历史消息**时，底部主对话框（输入框 + 深度思考 /
 * 智能搜索 + 附件 + 发送按钮）应隐藏，把可视区让给正在编辑的内容；其余情况保持原样。
 *
 * 判定依据（都是结构性的，不依赖站点哈希类名）：
 *   · **键盘**：由 {@link buildKeyboardStateScript} 推入的 `window.__dsKeyboardUp`；
 *   · **主对话框**：从「除了当前聚焦元素之外的另一个可编辑元素」向上找**底部固定容器**
 *     —— 优先 `position: fixed | sticky` 的祖先（站点把主对话框做成固定底栏），
 *     找不到再退回「底边贴着可视区底部、且高度不超过可视高度 45%」的最高祖先；
 *   · **内联编辑态**：当前聚焦的是可编辑元素，**且它不在底部固定容器里**
 *     （在固定底栏里的就是主输入框自己，不该隐藏它）。
 *
 * 命中时给主对话框加 {@link COMPOSER_HIDDEN_CLASS}（`display:none`）让位，
 * 并把正在编辑的元素 `scrollIntoView` 到可视区中央；条件不满足则移除该类恢复显示。
 * 幂等安装，监听 focusin / focusout / resize，随焦点与尺寸变化自愈。
 */
export function buildComposerAutoHideScript(): string {
  return `(function () {
    try {
      if (window.__dsComposerAutoHide) {
        if (window.__dsApplyComposerAutoHide) { window.__dsApplyComposerAutoHide(); }
        return 'already';
      }
      window.__dsComposerAutoHide = true;

      function styleOf(el) {
        try { return window.getComputedStyle(el); } catch (e) { return null; }
      }
      // 从元素向上找「底部固定容器」
      function findBottomCard(el) {
        var de = document.documentElement;
        var vh = de ? de.clientHeight : 0;
        var node = el;
        var depth = 0;
        var fixedCard = null;
        var nearBottom = null;
        while (node && node !== document.body && depth < 8) {
          var cs = styleOf(node);
          if (cs) {
            if (cs.position === 'fixed' || cs.position === 'sticky') { fixedCard = node; break; }
            var r = node.getBoundingClientRect();
            if (vh > 0 && r.height > 0 && r.height <= vh * 0.45 && r.bottom >= vh - 48) {
              nearBottom = node;
            }
          }
          node = node.parentElement;
          depth++;
        }
        return fixedCard || nearBottom;
      }
      // 元素是否位于底部固定容器内（是则它本身就是主对话框的一部分）
      function isInBottomCard(el) {
        var node = el;
        var depth = 0;
        while (node && node !== document.body && depth < 8) {
          var cs = styleOf(node);
          if (cs && (cs.position === 'fixed' || cs.position === 'sticky')) { return true; }
          node = node.parentElement;
          depth++;
        }
        return false;
      }
      // 独立的「底部固定栏」扫描：**不依赖可编辑元素**。
      // 实机实测：进入编辑历史消息态后，主对话框的输入框会被站点换成占位元素
      // （不再是 textarea），于是「找另一个可编辑元素」这条路会落空 ——
      // 表现为 keyboardUp/inlineEdit 都判对了、hasCard 却是 false，什么都没隐藏。
      function findBottomCardByGeometry() {
        var de = document.documentElement;
        var vh = de ? de.clientHeight : 0;
        var vw = de ? de.clientWidth : 0;
        if (!vh || !vw) { return null; }
        var all = document.querySelectorAll('body *');
        var limit = all.length < 4000 ? all.length : 4000;
        var best = null;
        var bestArea = -1;
        for (var i = 0; i < limit; i++) {
          var el = all[i];
          var cs = styleOf(el);
          if (!cs) { continue; }
          if (cs.position !== 'fixed' && cs.position !== 'sticky') { continue; }
          if (cs.display === 'none' || cs.visibility === 'hidden') { continue; }
          var r = el.getBoundingClientRect();
          if (r.width < vw * 0.5 || r.height <= 0) { continue; }
          if (r.height > vh * 0.5) { continue; }
          // 底边贴底：主对话框下面还可能有「内容由 AI 生成」那一行，因此留 32px 容差；
          // 该行的外层包装与主对话框同为 sticky，取面积最大的那个即整个底部区域
          if (r.bottom < vh - 32) { continue; }
          var area = r.width * r.height;
          if (area > bestArea) { bestArea = area; best = el; }
        }
        return best;
      }

      // 内联编辑卡片 = 从被聚焦的编辑元素向上找到「同时含有取消 / 保存这类按钮」的最近祖先。
      // 用它来：① 限高（按钮不被顶出可视区）② 点击卡片空白处能聚焦到编辑框 ③ 滚动到按钮可见
      var CANCEL_TEXT = /^(取消|关闭|保存|确认|完成|发送|cancel|save|done|send)$/i;
      function findEditCard(el) {
        var node = el;
        var depth = 0;
        while (node && node !== document.body && depth < 8) {
          var btns = node.querySelectorAll('button,[role="button"]');
          for (var i = 0; i < btns.length; i++) {
            var t = String(btns[i].innerText || btns[i].textContent || '').trim();
            var lab = String(btns[i].getAttribute('aria-label') || '').trim();
            if (CANCEL_TEXT.test(t) || CANCEL_TEXT.test(lab)) { return node; }
          }
          node = node.parentElement;
          depth++;
        }
        return null;
      }

      window.__dsApplyComposerAutoHide = function () {
        try {
          var ae = document.activeElement;
          var aeEditable = !!(ae && ae.matches && ae.matches('${EDITABLE_SELECTOR}'));
          var list = document.querySelectorAll('${EDITABLE_SELECTOR}');
          var mainEdit = null;
          for (var i = 0; i < list.length; i++) {
            if (list[i] !== ae) { mainEdit = list[i]; break; }
          }
          var card = mainEdit ? findBottomCard(mainEdit) : null;
          // 主输入框在编辑态会退化成占位元素、不再是可编辑节点，
          // 因此上面这条路可能落空，用独立的几何扫描兜底；
          // 再退一步用「上次隐藏的那个」—— 它已经 display:none，几何扫描会跳过它，
          // 不记住引用就会「藏起来后再也恢复不了」
          if (!card && window.__dsHiddenCard && document.contains(window.__dsHiddenCard)) {
            card = window.__dsHiddenCard;
          }
          if (!card) { card = findBottomCardByGeometry(); }
          var keyboardUp = !!window.__dsKeyboardUp;
          // 内联编辑态：焦点在可编辑元素上，且它不在底部固定容器里
          var inlineEdit = keyboardUp && aeEditable && !isInBottomCard(ae);
          if (card) {
            if (inlineEdit) {
              card.classList.add('${COMPOSER_HIDDEN_CLASS}');
              window.__dsHiddenCard = card;
            } else {
              card.classList.remove('${COMPOSER_HIDDEN_CLASS}');
              window.__dsHiddenCard = null;
            }
          }

          // 内联编辑卡片：只要被聚焦的编辑元素不在底部固定栏里，就把它所在的卡片标记出来，
          // CSS 据此限高（按钮行不被顶出可视区）、并让点击卡片空白处聚焦到编辑框
          var editCard = null;
          if (aeEditable && !isInBottomCard(ae)) {
            editCard = findEditCard(ae);
            if (editCard) {
              editCard.classList.add('${EDITOR_CARD_CLASS}');
              if (window.__dsEditCard && window.__dsEditCard !== editCard) {
                window.__dsEditCard.classList.remove('${EDITOR_CARD_CLASS}');
              }
              window.__dsEditCard = editCard;
              // 卡片贴底对齐滚动：文本域在上面、按钮行在下面，
              // block:'end' 能保证按钮行落在可视区内（居中反而可能把按钮推到键盘后面）
              try { editCard.scrollIntoView({ block: 'end' }); } catch (e4) { }
            }
          } else if (window.__dsEditCard) {
            window.__dsEditCard.classList.remove('${EDITOR_CARD_CLASS}');
            window.__dsEditCard = null;
          }

          window.__dsComposerAutoHideInfo = {
            keyboardUp: keyboardUp,
            activeEditable: aeEditable,
            inlineEdit: inlineEdit,
            hasCard: !!card,
            hidden: card ? card.classList.contains('${COMPOSER_HIDDEN_CLASS}') : false,
            cardPos: card ? String((styleOf(card) || {}).position || '') : '',
            cardCls: card ? String(card.className || '').slice(0, 40) : '',
            cardH: card ? Math.round(card.getBoundingClientRect().height) : 0,
            editCardCls: editCard ? String(editCard.className || '').slice(0, 40) : '',
            editCardH: editCard ? Math.round(editCard.getBoundingClientRect().height) : 0,
            editCardMax: String((styleOf(editCard) || {}).maxHeight || '')
          };
          return 'ok';
        } catch (e3) {
          return 'apply-error';
        }
      };

      // 把「可编辑元素获得焦点」上报给应用侧（console 前缀是约定的通道）。
      // 应用侧据此在键盘没弹起来时兜底拉起 —— 组件侧只有 setSoftKeyboardBehaviorMode
      // 这一个可用手段（IME 的 showSoftKeyboard 需要系统级权限，普通应用拿不到）。
      function reportFocus(kind) {
        try { console.info('__dsFocus:' + kind); } catch (e5) { }
      }

      // 内联编辑态下，站点是异步渲染的：程序化 focus 可能被后到的 DOM 变更顶掉，
      // 表现为「点了输入框但键盘不弹」。这里在焦点丢失时补一次 focus（只在真的丢了、
      // 且没有别的可编辑元素接管时才补，避免打乱用户的光标位置）。
      function scheduleFocusHeal(el) {
        var delays = [120, 320, 700];
        for (var i = 0; i < delays.length; i++) {
          setTimeout(function () {
            try {
              if (!el || !document.contains(el)) { return; }
              var last = window.__dsLastEditFocus;
              if (!last || last !== el) { return; }
              var ae = document.activeElement;
              if (ae === el) { return; }
              if (ae && ae.matches && ae.matches('${EDITABLE_SELECTOR}')) { return; }
              el.focus();
              reportFocus('refocus');
            } catch (e6) { }
          }, delays[i]);
        }
      }

      document.addEventListener('focusin', function (ev) {
        var t = ev.target;
        if (t && t.matches && t.matches('${EDITABLE_SELECTOR}')) {
          var inline = !isInBottomCard(t);
          window.__dsLastEditFocus = inline ? t : null;
          reportFocus(inline ? 'inline' : 'composer');
          if (inline) { scheduleFocusHeal(t); }
        }
        window.__dsApplyComposerAutoHide();
      }, true);
      document.addEventListener('focusout', function () {
        // 焦点切换有先后：延后一帧再评估，避免读到「还没有新焦点」的中间态
        setTimeout(function () { window.__dsApplyComposerAutoHide(); }, 50);
      }, true);
      window.addEventListener('resize', function () { window.__dsApplyComposerAutoHide(); });

      // 点卡片空白处也能聚焦到编辑框：编辑卡片里除了文本域还有留白，
      // 用户点上去本该开始编辑，但站点没把点击转发给文本域，于是「点了没反应」。
      // 只在焦点落在非交互元素上时补一次 focus（用户的手指就是 user activation，
      // 因此这一路能把软键盘正常拉起）。
      document.addEventListener('pointerdown', function (ev) {
        try {
          var ec = window.__dsEditCard;
          if (!ec || !ec.contains(ev.target)) { return; }
          var t = ev.target;
          if (t.matches && t.matches('${EDITABLE_SELECTOR}')) { return; }
          if (t.closest && t.closest('button,[role="button"],a,input,textarea,select,[contenteditable="true"],img,video')) { return; }
          var ta = ec.querySelector('${EDITABLE_SELECTOR}');
          if (!ta) { return; }
          setTimeout(function () {
            try {
              if (document.activeElement !== ta) { ta.focus(); }
              reportFocus('card-tap');
            } catch (e7) { }
          }, 0);
        } catch (e8) { }
      }, true);

      // 供应用侧调用：重新聚焦当前编辑元素（配合 setSoftKeyboardBehaviorMode 兜底拉键盘）
      window.__dsRetryEditFocus = function () {
        try {
          var el = window.__dsLastEditFocus;
          if (!el || !document.contains(el)) { return 'no-target'; }
          try { el.blur(); } catch (e9) { }
          el.focus();
          reportFocus('retry');
          return 'retried';
        } catch (e10) {
          return 'retry-error';
        }
      };
      window.__dsApplyComposerAutoHide();
      return 'installed';
    } catch (e) {
      return 'install-error';
    }
  })();`;
}

/**
 * 通知网页「容器尺寸变了」。
 *
 * 补发一次 resize 事件：部分 SPA 只在加载时读一次 window.innerWidth 决定布局，
 * 之后不再监听尺寸变化；补发事件能把这类实现唤醒。
 * 由 ArkTS 侧做防抖后调用，避免拖拽过程中高频触发。
 */
export function buildResizeNotifyScript(): string {
  return `(function () {
    try {
      window.dispatchEvent(new Event('resize'));
      return 'resized:' + window.innerWidth + 'x' + window.innerHeight;
    } catch (e) {
      return 'resize-error';
    }
  })();`;
}

/** 探测结果：没有可关闭的网页瞬时 UI */
export const OVERLAY_NONE: string = '';
/** 探测结果：网页弹窗（`role="dialog"` / `aria-modal`）——它会把历史顶出一条，用后退即可关闭 */
export const OVERLAY_DIALOG: string = 'dialog';
/** 探测结果：网页菜单（`role="menu"`）——不进历史，只能点掉 */
export const OVERLAY_MENU: string = 'menu';
/** 探测结果：带「关闭」入口的网页界面（如侧栏多选模式）——不进历史，只能点掉 */
export const OVERLAY_CLOSABLE: string = 'closable';

/**
 * 检测**网页自己的瞬时界面**是否开着，并指出是**哪一类**（供返回手势决策使用）。
 *
 * 为什么要分类，而不是只回答「开没开」：两类界面的关闭手段根本不同。
 * 实机实测（MatePad 11.5，DeepSeek 网页）：
 *
 * | 状态 | role="menu" | 「关闭」按钮 | histLen | 能否用后退关闭 |
 * |------|-------------|--------------|---------|----------------|
 * | 什么都不开 | 0 | 无 | 1 | — |
 * | 会话「…」菜单打开 | **1** | 无 | 1 | **不能**（不进历史，且 Esc 无效） |
 * | 「选择对话」多选模式 | 0 | **有** | 1 | **不能**（不进历史） |
 * | 「系统设置」弹窗 | 0 | 有 | **2** | 能（它 push 了一条历史） |
 *
 * 因此：弹窗走 `backward()`；菜单 / 多选模式只能由
 * {@link buildOverlayDismissScript} 点掉。**探测失败一律返回空串**，
 * 即回落到「按界面层级决策」，不会因为一次探测失败就把返回手势让给网页。
 */
export function buildOverlayProbeScript(): string {
  return `(function () {
    try {
      function visible(el, minW, minH) {
        var cs = window.getComputedStyle(el);
        if (!cs) { return false; }
        if (cs.display === 'none' || cs.visibility === 'hidden') { return false; }
        if (cs.opacity !== '' && Number(cs.opacity) === 0) { return false; }
        var r = el.getBoundingClientRect();
        return r.width >= minW && r.height >= minH;
      }
      // 命中时把「是谁触发的」一并带出去：日志里能看到具体元素，
      // 将来某台设备/某个形态判错了，不必再专门出一个诊断包
      function hit(kind, el) {
        var r = el.getBoundingClientRect();
        return kind + '|' + el.tagName + '|' + (el.getAttribute('role') || '') + '|' +
          String(el.className || '').slice(0, 24) + '|' +
          Math.round(r.width) + 'x' + Math.round(r.height);
      }
      var i;
      // 1) 弹窗：有 role=dialog / aria-modal，且有实际尺寸（过滤隐藏模板）
      var dialogs = document.querySelectorAll('[role="dialog"],[aria-modal="true"]');
      for (i = 0; i < dialogs.length; i++) {
        if (visible(dialogs[i], 80, 80)) { return hit('${OVERLAY_DIALOG}', dialogs[i]); }
      }
      // 2) 菜单
      var menus = document.querySelectorAll('[role="menu"]');
      for (i = 0; i < menus.length; i++) {
        if (visible(menus[i], 1, 1)) { return hit('${OVERLAY_MENU}', menus[i]); }
      }
      // 3) 带「关闭 / 取消」入口的界面（多选 / 选择对话 / 分享选择等）
      var cands = document.querySelectorAll('[aria-label],[title]');
      for (i = 0; i < cands.length; i++) {
        var lab = String(cands[i].getAttribute('aria-label') ||
          cands[i].getAttribute('title') || '').trim();
        if (!/^(close|关闭|取消|关闭对话框|close dialog)$/i.test(lab)) { continue; }
        if (visible(cands[i], 4, 4)) { return hit('${OVERLAY_CLOSABLE}', cands[i]); }
      }
      // 3b) 只有**文字**的「取消 / 关闭」按钮（手机上「选择对话」顶部就是文字「取消」，
      //     没有 aria-label）。为了不误判成页面里的普通文案，要求同时满足：
      //       · 是叶子节点（整段文字就是这四个字，不是长句的一部分）
      //       · 尺寸像按钮（宽 ≤ 320、高 ≤ 120，留出渲染差异与内边距）
      //     命中后日志里的 detail= 会给出它到底是什么元素。
      var leaves = document.querySelectorAll('body *');
      var limit = leaves.length < 4000 ? leaves.length : 4000;
      for (i = 0; i < limit; i++) {
        var el = leaves[i];
        if (el.children && el.children.length > 0) { continue; }
        var txt = String(el.innerText || '').trim();
        if (!/^(取消|关闭)$/.test(txt)) { continue; }
        if (!visible(el, 4, 4)) { continue; }
        var lr = el.getBoundingClientRect();
        if (lr.width > 320 || lr.height > 120) { continue; }
        return hit('${OVERLAY_CLOSABLE}', el);
      }
      return '${OVERLAY_NONE}';
    } catch (e) {
      return '${OVERLAY_NONE}';
    }
  })();`;
}

/**
 * 解析 {@link buildOverlayProbeScript} 的返回值，取出「是哪一类瞬时界面」。
 *
 * 返回值形如 `dialog|DIV||_4cbcd96|1100x900`（含触发元素的身份，供日志定位），
 * 这里只取第一段；runJavaScript 会把字符串再包一层引号，也要去掉。
 * **认不出来的值一律当作「没有瞬时界面」**。
 *
 * @param kindOnly 只取类别（默认），false 时返回去掉引号的完整串用于日志
 */
export function parseOverlayKind(raw: string, kindOnly: boolean = true): string {
  if (!raw) {
    return OVERLAY_NONE;
  }
  const v: string = raw.replace(/"/g, '').replace(/'/g, '').trim();
  const kind: string = v.indexOf('|') >= 0 ? v.substring(0, v.indexOf('|')) : v;
  if (!kindOnly) {
    return v;
  }
  if (kind === OVERLAY_DIALOG || kind === OVERLAY_MENU || kind === OVERLAY_CLOSABLE) {
    return kind;
  }
  return OVERLAY_NONE;
}

/**
 * 点掉网页自己的瞬时界面（菜单 / 多选模式），按三步依次尝试：
 *   1. 它自己的「关闭」入口（多选模式实测有 `aria-label="关闭"`）；
 *   2. 处于展开态的触发按钮（`aria-expanded="true"`）—— 再点一次即收起；
 *   3. 把「点外面」的点击**派发到 body**，由挂在 document 上的外部点击处理器收掉。
 *
 * > **绝不能去点全屏遮罩、也不能按坐标点内容区的元素**：实测那层全屏 fixed 遮罩
 * > 属于**侧边栏抽屉**。宽屏下侧栏是常驻列、内容区在它右边，按坐标点没事；
 * > 但窄屏（手机、平板悬浮窗等非全屏形态）侧栏就是抽屉、内容区正好被它盖住，
 * > 按坐标点过去会命中这层遮罩 —— 于是「菜单关了，侧栏也被一起收起」。
 * > 派发到 body 则不同：事件仍冒泡到 document（外部点击处理器能收到），
 * > 而遮罩不在 body → document 的路径上，它的「收起侧栏」处理器不会触发。
 *
 * 返回 `clicked-close` / `clicked-outside` / `clicked-outside-body` / `none:<原因>`，
 * 供应用侧日志确认到底走了哪条路径。
 */
export function buildOverlayDismissScript(): string {
  return `(function () {
    try {
      function visible(el, minW, minH) {
        var cs = window.getComputedStyle(el);
        if (!cs) { return false; }
        if (cs.display === 'none' || cs.visibility === 'hidden') { return false; }
        var r = el.getBoundingClientRect();
        return r.width >= minW && r.height >= minH;
      }
      function fire(el, x, y) {
        try {
          var opts = {
            bubbles: true, cancelable: true, view: window,
            clientX: x, clientY: y
          };
          el.dispatchEvent(new MouseEvent('mousedown', opts));
          el.dispatchEvent(new MouseEvent('mouseup', opts));
          el.dispatchEvent(new MouseEvent('click', opts));
        } catch (e2) { }
      }
      var i;
      var cands = document.querySelectorAll('[aria-label],[title]');
      for (i = 0; i < cands.length; i++) {
        var lab = String(cands[i].getAttribute('aria-label') ||
          cands[i].getAttribute('title') || '').trim();
        if (!/^(close|关闭|取消|关闭对话框|close dialog)$/i.test(lab)) { continue; }
        if (!visible(cands[i], 4, 4)) { continue; }
        var crc = cands[i].getBoundingClientRect();
        fire(cands[i], Math.round(crc.left + crc.width / 2), Math.round(crc.top + crc.height / 2));
        return 'clicked-close';
      }
      // 1b) 只有文字的「取消 / 关闭」按钮（手机上「选择对话 / 分享选择」顶部就是文字「取消」）：
      //     同样要求叶子节点 + 按钮尺寸，避免误点页面里的普通文案
      var leaves = document.querySelectorAll('body *');
      var limit2 = leaves.length < 4000 ? leaves.length : 4000;
      for (i = 0; i < limit2; i++) {
        var le = leaves[i];
        if (le.children && le.children.length > 0) { continue; }
        var ltxt = String(le.innerText || '').trim();
        if (!/^(取消|关闭)$/.test(ltxt)) { continue; }
        if (!visible(le, 4, 4)) { continue; }
        var lrc = le.getBoundingClientRect();
        if (lrc.width > 320 || lrc.height > 120) { continue; }
        fire(le, Math.round(lrc.left + lrc.width / 2), Math.round(lrc.top + lrc.height / 2));
        return 'clicked-close';
      }
      // 2) 「展开态」的触发按钮：菜单通常就挂在它下面（aria-expanded="true"）。
      //    再点一次即是**收起**，语义上最贴近用户操作，且完全不碰其它层。
      var expanders = document.querySelectorAll('[aria-expanded="true"]');
      for (i = 0; i < expanders.length; i++) {
        if (!visible(expanders[i], 4, 4)) { continue; }
        var erc = expanders[i].getBoundingClientRect();
        fire(expanders[i], Math.round(erc.left + erc.width / 2), Math.round(erc.top + erc.height / 2));
        return 'clicked-trigger';
      }
      // 3) 兜底：模拟「点菜单外面」，把事件派发到 body 上。
      //
      // ⚠️ 绝不能去点那些全屏 fixed 遮罩、也不能按坐标去点内容区的元素：
      //    实测那一层全屏遮罩属于**侧边栏抽屉** —— 窄屏（手机 / 平板悬浮窗等
      //    非全屏形态）下侧栏就是抽屉，内容区正好被它盖住，按坐标点过去会命中
      //    这层遮罩，于是「菜单关了，侧栏也被一起收起」（用户可见的回归）。
      //    改派发到 body：事件仍会冒泡到 document，挂在 document 上的
      //    「点外部关闭」能收到；而遮罩元素不在 body → document 的路径上，
      //    它的「收起侧栏」处理器不会触发 —— 菜单关闭而侧栏保持展开。
      var host = document.body || document.documentElement;
      if (!host) { return 'none:no-target'; }
      var cx = Math.round((window.innerWidth || 2) / 2);
      var cy = Math.round((window.innerHeight || 2) / 2);
      fire(host, cx, cy);
      return 'clicked-outside-body';
    } catch (e) {
      return 'none:error';
    }
  })();`;
}

/**
 * 解析 {@link buildOverlayDismissScript} 的返回值：这一步是否**真的点到了东西**。
 *
 * 注意 runJavaScript 的返回是字符串化的：字符串会再包一层引号
 * （实测拿到的是 `"clicked-outside"` 而不是 `clicked-outside`）。
 * 必须先去掉引号再判断，否则会误判成「没点到」而多走一次兜底后退 ——
 * 那一步会把网页翻走，正是本功能要避免的事。
 */
export function isDismissClicked(raw: string): boolean {
  if (!raw) {
    return false;
  }
  const v: string = raw.replace(/"/g, '').replace(/'/g, '').trim();
  return v.indexOf('clicked-') === 0;
}

/**
 * 视口诊断脚本（返回 JSON 字符串）。
 *
 * 存在的意义：本应用无法在设备上调试，而「viewport 到底有没有生效」「输入框上限
 * 有没有真的注入」只能看运行时的真实数值。一次实机运行即可判定：
 *   · clientW 是否随窗口宽度变化   → viewport 是否生效
 *   · capStyle 是否为 null         → 注入的样式是否真的在文档里
 *   · composer.maxH / scrollH      → 上限生效成了多少
 *   · ancestors                    → 上限应该加在哪一层容器上
 *   · chipTextInDom                → 工具栏是被挤出可视区还是被页面移除
 */
export function buildProbeScript(): string {
  return `(function () {
    try {
      var de = document.documentElement;
      var vv = window.visualViewport;
      var m = document.querySelector('meta[name="viewport"]');
      var el = document.querySelector('${EDITABLE_SELECTOR}');
      var composer = null;
      var ancestors = [];
      if (el) {
        var p = el.parentElement;
        var cs = window.getComputedStyle(el);
        composer = {
          tag: el.tagName,
          h: Math.round(el.getBoundingClientRect().height),
          cls: String(el.className || '').slice(0, 80),
          parentCls: p ? String(p.className || '').slice(0, 80) : '',
          valueLen: (el.value === undefined || el.value === null) ? -1 : String(el.value).length,
          scrollH: el.scrollHeight,
          maxH: cs ? cs.maxHeight : '',
          overflowY: cs ? cs.overflowY : '',
          inlineH: String((el.style && el.style.height) || '')
        };

        // 输入框向上的祖先链：判断「高度上限该加在哪一层」。
        // 实测只压 textarea 会把 composer 卡片的可用空间挤变形，需要看清各级容器。
        var node = el;
        for (var ai = 0; node && ai < 6; ai++) {
          var ast = window.getComputedStyle(node);
          ancestors.push({
            tag: node.tagName,
            cls: String(node.className || '').slice(0, 36),
            h: Math.round(node.getBoundingClientRect().height),
            disp: ast ? ast.display : '',
            ofY: ast ? ast.overflowY : ''
          });
          node = node.parentElement;
        }
      }

      // 输入框「兄弟节点」的高度：用于回答「直接父容器为什么这么高」
      //（若父容器高度来自内容，光改 height:auto 是没用的，必须找出那个撑高的兄弟）
      var parentKids = [];
      if (el && el.parentElement) {
        var kids = el.parentElement.children;
        for (var ki = 0; ki < kids.length && ki < 6; ki++) {
          var ke = kids[ki];
          parentKids.push({
            tag: ke.tagName,
            cls: String(ke.className || '').slice(0, 30),
            h: Math.round(ke.getBoundingClientRect().height),
            isSelf: ke === el
          });
        }
      }

      // 我们那条 :has() 规则到底有没有匹配到元素（未匹配时规则等于没写）
      var hasRuleMatch = false;
      try { hasRuleMatch = !!document.querySelector('div:has(> textarea)'); } catch (e2) { }

      var styleEl = document.getElementById('${VIEWPORT_STYLE_ID}');
      var bodyText = (document.body && document.body.innerText) || '';

      var act = document.activeElement;
      var active = act ? {
        tag: act.tagName,
        cls: String(act.className || '').slice(0, 60),
        editable: !!(act.matches && act.matches('${EDITABLE_SELECTOR}'))
      } : null;

      // 弹层诊断：用于判断「返回手势该不该交给网页去关弹层」。
      // 网页自己的弹层（设置、分享、图片预览…）通常有两种实现：
      //   a) 打开时 pushState 一条历史 → 把返回交给网页就能关掉它；
      //   b) 不碰历史 → 返回手势无论如何都关不掉，只能点它自己的关闭按钮。
      // 因此「有没有可识别的弹层」与「历史长度」必须一起看，缺一不可。
      var overlay = { dialogs: 0, ariaModals: 0, fullscreenFixed: 0, top: null };
      try {
        overlay.dialogs = document.querySelectorAll('[role="dialog"]').length;
        overlay.ariaModals = document.querySelectorAll('[aria-modal="true"]').length;
        var vpArea = (window.innerWidth || 1) * (window.innerHeight || 1);
        var all = document.querySelectorAll('body *');
        var best = null;
        var bestArea = 0;
        // 限制遍历量：诊断脚本会周期性执行，不能在超大 DOM 上跑太久
        var limit = all.length < 3000 ? all.length : 3000;
        for (var oi = 0; oi < limit; oi++) {
          var oe = all[oi];
          var ocs = window.getComputedStyle(oe);
          if (!ocs || ocs.position !== 'fixed') { continue; }
          if (ocs.display === 'none' || ocs.visibility === 'hidden') { continue; }
          var orc = oe.getBoundingClientRect();
          var oarea = orc.width * orc.height;
          if (oarea < vpArea * 0.4) { continue; }
          overlay.fullscreenFixed++;
          if (oarea > bestArea) {
            bestArea = oarea;
            var btns = oe.querySelectorAll('button,[role="button"]');
            var closeBtn = 0;
            for (var bi = 0; bi < btns.length; bi++) {
              var label = String(btns[bi].getAttribute('aria-label') ||
                btns[bi].getAttribute('title') || btns[bi].innerText || '').trim();
              if (/close|关闭|取消|✕|×/i.test(label)) { closeBtn++; }
            }
            best = {
              tag: oe.tagName,
              role: oe.getAttribute('role') || '',
              ariaModal: oe.getAttribute('aria-modal') || '',
              cls: String(oe.className || '').slice(0, 60),
              w: Math.round(orc.width),
              h: Math.round(orc.height),
              z: ocs.zIndex,
              buttons: btns.length,
              closeButtons: closeBtn,
              text: String(oe.innerText || '').replace(/\s+/g, ' ').slice(0, 30)
            };
          }
        }
        overlay.top = best;
      } catch (e3) { }

      // 瞬时 UI 诊断：侧栏右键菜单 / 多选模式这类「网页自己的临时状态」既不是
      // role=dialog，也不进历史，需要单独找出可识别的标记与「关闭」入口。
      // 只统计**可见**元素，避免把隐藏模板算进来。
      var ui = { roles: {}, checked: 0, labels: [] };
      try {
        var all2 = document.querySelectorAll('body *');
        var limit2 = all2.length < 4000 ? all2.length : 4000;
        for (var qi = 0; qi < limit2; qi++) {
          var qe = all2[qi];
          var qrole = qe.getAttribute ? qe.getAttribute('role') : '';
          var qaria = qe.getAttribute ? qe.getAttribute('aria-checked') : '';
          if (qrole === 'checkbox' || qaria === 'true' || qaria === 'false') { ui.checked++; }
          if (!qrole) { continue; }
          var qcs = window.getComputedStyle(qe);
          if (!qcs || qcs.display === 'none' || qcs.visibility === 'hidden') { continue; }
          var qrc = qe.getBoundingClientRect();
          if (qrc.width <= 0 || qrc.height <= 0) { continue; }
          ui.roles[qrole] = (ui.roles[qrole] || 0) + 1;
        }
        var closers = document.querySelectorAll('button,[role="button"],[role="menuitem"],a[aria-label]');
        for (var ci = 0; ci < closers.length && ui.labels.length < 14; ci++) {
          var ce = closers[ci];
          var clab = String((ce.getAttribute('aria-label') || ce.getAttribute('title') || '')).trim();
          if (!clab) { continue; }
          var crc = ce.getBoundingClientRect();
          if (crc.width <= 0 || crc.height <= 0) { continue; }
          ui.labels.push({
            l: clab.slice(0, 20),
            x: Math.round(crc.x), y: Math.round(crc.y),
            w: Math.round(crc.width), h: Math.round(crc.height)
          });
        }
      } catch (e4) { }

      return JSON.stringify({
        ua: navigator.userAgent,
        mobileToken: /Mobile/i.test(navigator.userAgent),
        histLen: window.history ? window.history.length : -1,
        overlay: overlay,
        ui: ui,
        innerW: window.innerWidth,
        clientW: de ? de.clientWidth : -1,
        clientH: de ? de.clientHeight : -1,
        vvW: vv ? Math.round(vv.width) : -1,
        vvH: vv ? Math.round(vv.height) : -1,
        vvScale: vv ? Number(vv.scale.toFixed(3)) : -1,
        dpr: window.devicePixelRatio,
        viewportMeta: m ? m.getAttribute('content') : null,
        capStyle: styleEl ? String(styleEl.textContent || '').slice(0, 110) : null,
        // 脚本算出的上限与它所依据的可视高度：用于验证
        //「输入框上限 ≤ 可视高度 × RATIO」这条硬保证是否成立
        capInfo: window.__dsComposerCapInfo || null,
        composer: composer,
        ancestors: ancestors,
        parentKids: parentKids,
        hasRuleMatch: hasRuleMatch,
        chipTextInDom: bodyText.indexOf('深度思考') >= 0,
        active: active
      });
    } catch (e) {
      return 'probe-error';
    }
  })();`;
}
