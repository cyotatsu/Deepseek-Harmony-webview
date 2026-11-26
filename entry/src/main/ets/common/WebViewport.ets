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
 *  1. **卡片硬限高**：上限由 `{@link EDITOR_MAX_VAR}` 给出（按实时可视高度算出的
 *     像素值）——卡片「总高 ≤ 62% 可视高度」，按钮行必然在卡片内部；
 *     `overflow-y:auto` 让超高内容由**卡片自己滚动**吸收，而不是把它顶出可视区。
 *  2. **图片按可视高度限高**：图片是「图片 + 长文本」组合里最不可压缩的一项，
 *     不限高的话它自己就能吃掉大半个可视区。
 *  3. **按钮行 sticky 贴底**：按钮行的直接父元素被脚本标成
 *     {@link EDITOR_ACTION_ROW_CLASS}（见 buildComposerAutoHideScript），
 *     这里给它 `position:sticky; bottom:0` —— 卡片内部滚动时按钮钉在可视底边，
 *     即使站点把按钮行放在卡片中间、后面还有别的节点也不会被卷走。
 *
 * 为什么按钮行不用 `order:999` 拖到卡片末尾：那会改变站点自己的信息层级，
 * 且一旦按钮不在卡片直接子级就完全失效。sticky 是"就地固定"，不改文档流顺序，
 * 对站点布局的侵入最小 —— 关键的是它**不需要卡片变成 flex 容器**，
 * 因此不会重蹈「长文本下文本框末尾留大片空白」的覆辙（详见函数内注释）。
 *
 * 选择器一律带 `div.` 前缀并写在既有规则之后：站点自己的类名（哈希类）特异性与
 * `div.自定义类` 相同，靠"后写"取胜；而这条又必须盖过上面那条「卡片直接子元素」
 * 的上限（`div:has(> textarea) > *`），所以顺序不能调。
 */
export function buildEditorCardCss(): string {
  // 三条**真正防裁切**的规则，各管一件事：
  //   ① 卡片限高 + 超出可滚动：图片 + 长文本不再把卡片顶得超过可视区；
  //   ② 卡片内图片按可视高度限高：它是「按钮被挤出可视区」的直接成因；
  //   ③ 按钮行 sticky 贴底：卡片被限高后内部可以滚动，站点若把按钮行放在
  //      卡片中间（后面还有提示文案 / 占位节点），滚动时按钮会被卷出可视区 ——
  //      sticky 把它钉在卡片可视底边，**无论站点怎么排卡片内部**按钮都露着。
  //
  // ⚠️ 早先这一整套里还包含列向 flex（`display:flex` + `> *{flex:0 0 auto}` +
  // `:has(textarea){flex:1 1 auto}`），结果是「插入长文本后文本框下方留一大片空白」：
  // 卡片到限高后，被允许伸长的那一支吃掉了剩余空间，而且随内容增长越来越长。
  // 那套 flex 已经撤掉，**本条 sticky 与它无关**，可以单独成立：
  //   · sticky 是**相对定位**元素，不改变父容器高度，也不会吃掉剩余空间；
  //   · 卡片本身就是滚动容器（① 的 overflow-y:auto），所以 bottom:0 贴的是
  //     卡片可视底边，正是按钮行该待的地方；
  //   · 卡片内部布局仍然完全交回站点 —— 这里只移动按钮行自己的绘制位置。
  return 'div.' + EDITOR_CARD_CLASS + '{max-height:var(' + EDITOR_MAX_VAR + ',' +
    COMPOSER_FALLBACK_VH + 'vh) !important;overflow-y:auto !important;overflow-x:hidden !important;}' +
    'div.' + EDITOR_CARD_CLASS + ' img,div.' + EDITOR_CARD_CLASS + ' video{' +
    'max-height:' + EDITOR_IMAGE_MAX_VH + 'vh !important;width:auto !important;' +
    'object-fit:contain !important;}' +
    // 按钮行贴底。z-index 提到内容之上，避免站点给卡片内容设了更高层级时按钮被盖住；
    // padding-bottom 用卡片自身的底部内边距补齐（由 applyCap 写入变量），
    // 否则按钮行会有一截落在卡片的 padding 区域里、被滚动容器裁掉。
    'div.' + EDITOR_ACTION_ROW_CLASS + '{position:sticky !important;bottom:0 !important;' +
    'z-index:3 !important;padding-bottom:var(' + EDITOR_BOTTOM_PAD_VAR + ',0px) !important;}' +
  // 站点用的是「悬浮式滚动条」，只在滚动瞬间显形、停下即淡出，触屏上基本看不到。
  // 这里**只给编辑卡片**补一根常驻细滚动条（上一版是全局强制，才会波及其它弹层、
  // 甚至出现两根条）；主对话框不动 —— 它自带的那根本来就正常。
  'div.' + EDITOR_CARD_CLASS + '{scrollbar-width:thin !important;' +
  'scrollbar-color:rgba(0,0,0,0.30) transparent !important;}' +
  'div.' + EDITOR_CARD_CLASS + '::-webkit-scrollbar{width:8px !important;}' +
  'div.' + EDITOR_CARD_CLASS + '::-webkit-scrollbar-thumb{' +
  'background-color:rgba(0,0,0,0.28) !important;border-radius:4px !important;' +
  'min-height:32px !important;}' +
  'div.' + EDITOR_CARD_CLASS + '::-webkit-scrollbar-track{background-color:transparent !important;}';
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
 * 由「当前可视高度」计算内联编辑卡片的高度上限（px）。
 *
 * 纯函数，便于单测 —— 脚本里用的是同一个公式。**必须保证结果 ≤ 可视高度**：
 * 卡片刻意留出上下空间（卡片连同按钮行一起落进可视区，靠的就是这个上限），
 * 正常屏幕上取可视高度的 {@link EDITOR_MAX_RATIO}，并在
 * {@link EDITOR_MIN_PX}～{@link EDITOR_MAX_PX} 之间夹紧。
 *
 * 下限要先对可视高度取 min：`EDITOR_MIN_PX` 是给正常屏幕兜底的，
 * 可视区极小时（悬浮窗拖到很小、自由多窗）若直接用它当下限，
 * 算出的上限会反过来超过可视区本身 —— 卡片反而比可视区还高，按钮照样看不见。
 */
export function computeEditorCapPx(visibleHeightPx: number): number {
  if (!visibleHeightPx || visibleHeightPx <= 0) {
    return EDITOR_MIN_PX;
  }
  const floor: number = Math.min(EDITOR_MIN_PX, Math.round(visibleHeightPx * 0.6));
  const scaled: number = Math.max(floor, visibleHeightPx * EDITOR_MAX_RATIO);
  return Math.round(Math.min(EDITOR_MAX_PX, scaled));
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
 * 主对话框（底部那个「输入框 + 深度思考 / 智能搜索 + 发送」）的**文字标记**。
 *
 * 为什么需要它：识别主对话框原先只有两条路 —— ①从「另一个可编辑元素」向上找固定
 * 定位祖先；②全文档几何扫描「固定/粘性 + 贴底 + 矮条」。两者都会**内容的形态**影响：
 *
 *   · 路①依赖「除编辑框外还有别的可编辑元素」。进入编辑态后站点会把主输入框换成
 *     占位元素，这条路经常直接落空；
 *   · 路②有节点数上限（4000），而且要求候选元素此刻恰好贴在可视区底边。
 *     历史回答里**带数学公式 / 表格**时，回答节点的数量和高度都远大于纯文本 ——
 *     实测现象正是「有公式或表格时主对话框不隐藏，纯文本时正常」。
 *
 * 文字标记则与回答内容完全无关：只要主对话框还在 DOM 里，这几个串就去找得到它，
 * 再由它向上收敛到「固定定位的祖先」或「贴底的那一层」。多语言站点上这些串会变，
 * 因此匹配是**多标记、任一命中即可**，并且允许调用方再叠加结构性判据。
 */
export const COMPOSER_MARKER_TEXTS: Array<string> = [
  '给 DeepSeek 发送消息',
  '给DeepSeek发送消息',
  '深度思考',
  '智能搜索',
  '内容由 AI 生成',
];

/**
 * 主对话框文字标记的正则（由 {@link COMPOSER_MARKER_TEXTS} 直接拼出，避免两处脱节）。
 *
 * 只做「包含」判断而不做全等：站点会给这些串套上高亮/换行用的子节点，
 * 元素自身的 textContent 可能带空白或拼接了别的字符。
 */
export function buildComposerMarkerPattern(): string {
  return COMPOSER_MARKER_TEXTS.join('|');
}

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
          // 内联编辑卡片：限高 + 图片限高 + 按钮行 sticky 贴底 —— 取消/确认按钮
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
            // 公式与 computeEditorCapPx 完全一致（含「极窄可视区时下限不得反超」那条），
            // 单测直接钉住那个纯函数，这里只把常量代进来。
            var editFloor = Math.min(${EDITOR_MIN_PX}, Math.round(h * 0.6));
            var editCap = Math.min(${EDITOR_MAX_PX},
              Math.max(editFloor, h * ${EDITOR_MAX_RATIO}));
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
      // 兜底安全网：键盘收起时**强制**把所有隐藏类拆干净。
      //
      // 为什么不能只依赖 applyComposerAutoHide：它的恢复逻辑可能因为「那一刻
      // 恰好没找到主对话框」而只是把引用清掉，而类已经加在了**另一个**元素上
      //（实机日志抓到过：隐藏目标从 DIV._020ab5b 换成了外层 DIV._871cbca，
      // 两个都带过这个类）。这里再扫一遍文档，确保「键盘收起 ⇒ 主对话框可见」
      // 这条保证不依赖任何单点判据。
      var swept = 0;
      if (!window.__dsKeyboardUp) {
        try {
          var still = document.querySelectorAll('.${COMPOSER_HIDDEN_CLASS}');
          for (var si = 0; si < still.length; si++) {
            still[si].classList.remove('${COMPOSER_HIDDEN_CLASS}');
            swept++;
          }
          window.__dsHiddenCard = null;
        } catch (eSw) { }
      }
      // 回带一次判定详情：实机出问题时，日志里直接能看到「有没有找到主对话框、
      // 它是不是固定底栏、当前算不算内联编辑态」，不必再单独出诊断包。
      // 关键：键盘弹起/收起的那一刻就是「该不该隐藏」的决策点，所以这里除了
      // autoHideInfo，还要带上「编辑卡片认没认出来」和 apply 的现场（__dsLastApply）——
      // 实机问题正是「键盘起来了、主对话框却没隐藏」，这三项一起看即可定位。
      var info = window.__dsComposerAutoHideInfo || null;
      var extra = {
        pick: String(window.__dsComposerPickPath || ''),
        editCard: window.__dsEditCard
          ? (String(window.__dsEditCard.tagName || '?') + '.' +
            String(window.__dsEditCard.className || '').split(' ')[0] +
            '/h' + Math.round(window.__dsEditCard.getBoundingClientRect().height))
          : null,
        last: window.__dsLastApply || null
      };
      return 'kb:' + (window.__dsKeyboardUp ? 'up' : 'down') + ' swept=' + swept + ' ' +
        JSON.stringify(info) + ' | ' + JSON.stringify(extra);
    } catch (e) {
      return 'kb-error';
    }
  })();`;
}

/**
 * 量一次网页正文的实际字号（CSS px），用于让设置里的「字体大小」预览与对话一致。
 *
 * 为什么需要它：预览卡里的样例文字是 ArkTS 自己画的，如果按「100% = 16vp」硬编码，
 * 与站点实际正文（由站点 CSS 决定）可能差 1~2px，用户会觉得「预览和对话不一样」。
 * 这里读站点正文段落的 computed font-size，回带数字；取不到时回带 0，
 * 由调用方退回默认基准。
 *
 * 优先级：消息正文段落 → 普通 p → body，逐级兜底。
 */
export function buildBaseFontProbeScript(): string {
  return `(function () {
    try {
      function readPx(el) {
        if (!el) { return 0; }
        var fs = window.getComputedStyle(el).fontSize;
        var px = parseFloat(fs);
        return (px > 0) ? px : 0;
      }
      var px = 0;
      var md = document.querySelector('[class*="ds-markdown"] p');
      if (md) { px = readPx(md); }
      if (!px) { px = readPx(document.querySelector('p')); }
      if (!px) { px = readPx(document.body); }
      if (!px) { return '0'; }
      return String(Math.round(px * 10) / 10);
    } catch (e) {
      return '0';
    }
  })();`;
}

/**
 * 探测网页当前是深色还是浅色主题。
 *
 * 为什么需要：悬浮球是 ArkUI 组件，颜色取自 app.color.*，而 app.color.* 只跟随
 * **系统**深浅色。站点自己的「系统设置 → 主题」可以在系统为浅色时把网页切成深色
 *（或反之），这时按钮会与网页底色打架（白底白图标 / 黑底黑图标）。
 *
 * 判定顺序（任一成立即深色）：
 *   1. <html> 或 <body> 带 dark 类名 / data-theme="dark" / data-color-mode="dark"
 *   2. <html> 的 color-scheme 计算值含 dark
 *   3. body 背景色的相对亮度 < 0.5（兜底：站点换实现方式时也不会立刻失效）
 *
 * 返回 '1' 深色 / '0' 浅色 / 'x' 未知（文档未就绪或读取异常）；调用方只在拿到 0/1 时更新。
 */
export function buildPageThemeProbeScript(): string {
  return `(function () {
    try {
      var html = document.documentElement;
      var body = document.body;
      // 文档还没就绪（刚点完刷新 / 新页面首帧之前）时返回未知 'x'：
      // 此刻 body 里没有任何内容，按背景色兜底会得到白色 → 被误判成「浅色主题」，
      // 悬浮球就会先白一下再变回深色。宁可这次不更新，也不要用假数据覆盖已知状态。
      if (!html || !body || document.readyState === 'loading' || !body.firstElementChild) {
        return 'x';
      }
      function hasDarkMark(el) {
        if (!el) { return false; }
        var cls = el.className;
        if (typeof cls === 'string' && /(^|\\s)dark(\\s|$)/i.test(cls)) { return true; }
        var dt = el.getAttribute && el.getAttribute('data-theme');
        if (dt && dt.toLowerCase() === 'dark') { return true; }
        var dm = el.getAttribute && el.getAttribute('data-color-mode');
        if (dm && dm.toLowerCase() === 'dark') { return true; }
        var ds = el.getAttribute && el.getAttribute('data-scheme');
        if (ds && ds.toLowerCase() === 'dark') { return true; }
        return false;
      }
      function hasLightMark(el) {
        if (!el) { return false; }
        var cls = el.className;
        if (typeof cls === 'string' && /(^|\\s)light(\\s|$)/i.test(cls)) { return true; }
        var dt = el.getAttribute && el.getAttribute('data-theme');
        if (dt && dt.toLowerCase() === 'light') { return true; }
        return false;
      }
      if (hasDarkMark(html) || hasDarkMark(body)) { return '1'; }
      // 站点把主题写在 body 的类名里（实测：zh_CN light / zh_CN dark）。
      // 认到显式 light 就提前返回，避免下面按背景色猜时被透明底误导。
      if (hasLightMark(html) || hasLightMark(body)) { return '0'; }
      var cs = window.getComputedStyle(html).colorScheme || '';
      if (cs.toLowerCase().indexOf('dark') >= 0) { return '1'; }
      // 背景色可能挂在 html 上、也可能挂在 body 上（body 常常是透明的），逐个试
      var els = [body, html];
      for (var i = 0; i < els.length; i++) {
        var el = els[i];
        if (!el) { continue; }
        var bg = window.getComputedStyle(el).backgroundColor || '';
        var m = bg.match(/rgba?\(([^)]+)\)/);
        if (!m) { continue; }
        var parts = m[1].split(',');
        var r = parseFloat(parts[0]) || 0;
        var g = parseFloat(parts[1]) || 0;
        var b = parseFloat(parts[2]) || 0;
        var a = (parts.length > 3) ? parseFloat(parts[3]) : 1;
        if (a <= 0.5) { continue; }
        var lum = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
        return (lum < 0.5) ? '1' : '0';
      }
      return '0';
    } catch (e) {
      return '0';
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
 * 判定依据（顺序即优先级，每一步都排除「编辑卡片自己」）：
 *   · **键盘**：由 {@link buildKeyboardStateScript} 推入的 `window.__dsKeyboardUp`；
 *   · **主对话框**：
 *     ① **文字标记**（{@link COMPOSER_MARKER_TEXTS}）—— 与回答形态完全无关，
 *        由标记元素向上收敛到固定定位祖先 / 贴底容器。**带数学公式、表格的回答靠这一步**；
 *     ② 从「除当前聚焦元素之外的另一个可编辑元素」向上找 `position: fixed | sticky` 祖先；
 *     ③ 全文档几何扫描（有节点上限，内容复杂时可能落空，只作最后兜底）；
 *   · **内联编辑态**：当前聚焦的是可编辑元素，**且它不在主对话框里**
 *     （在主对话框里的就是主输入框自己，不该隐藏它）。
 *
 * 命中时给主对话框加 {@link COMPOSER_HIDDEN_CLASS}（`display:none`）让位，
 * 条件不满足则移除该类恢复显示。幂等安装，监听 focusin / focusout / resize，随焦点与尺寸变化自愈。
 *
 * 命中路径会写进 `__dsComposerAutoHideInfo.pickPath`（marker / editable / geometry / cached / none），
 * 实机上「该隐藏却没隐藏」时看它即可判断是不是回答形态（公式、表格）把路径挤掉了。
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
      // 绝不允许隐藏「当前聚焦元素所在的容器」。
      //
      // 实机踩坑：编辑态下若把包含正在编辑的文本域的容器 display:none 掉，
      // 浏览器会立刻让它失焦并收起键盘 —— 表现就是「键盘闪现」：
      // 日志里能看到 hide 之后约 35ms 键盘高度就变回 0，然后站点再聚焦、再被收起，循环往复。
      function containsActive(el) {
        var ae = document.activeElement;
        if (!ae || !el) { return false; }
        return el === ae || !!(el.contains && el.contains(ae));
      }
      // 从元素向上找「底部固定容器」。**只认 fixed / sticky**：
      // 历史版本还允许「底边贴底的非定位元素」，结果编辑态下把消息气泡里的编辑卡片
      // 当成了主对话框藏掉，键盘立刻收起（键盘闪现）。定位方式是这个判据的关键。
      function findBottomCard(el) {
        var node = el;
        var depth = 0;
        while (node && node !== document.body && depth < 8) {
          var cs = styleOf(node);
          if (cs && (cs.position === 'fixed' || cs.position === 'sticky')) { return node; }
          node = node.parentElement;
          depth++;
        }
        return null;
      }
      // 元素是否位于底部固定容器内（是则它本身就是主对话框的一部分）。
      //
      // **当前已无调用方**（保留下来是为了留住下面这条坑的说明）：
      // 判断「是不是主对话框」的地方都已改成 {@link isInComposer} 的真实包含关系判据。
      //
      // ⚠️ **不要用它判断「是不是在编辑卡片里」**：这个判据只看祖先链上有没有
      // position: fixed / sticky，而**消息列表本身就是 sticky**（实测 ds-virtual-list）。
      // 于是「编辑卡片在消息列表里」会让它一律返回 true —— 历史版本据此认为
      // 「正在编辑的是主对话框」，把 inlineEdit 判死，主对话框就永远不隐藏了。
      // 实机现象正是「回答里带数学公式 / 表格时不隐藏，纯文本时正常」：
      // 公式/表格让列表进入 sticky + 可滚动的状态，纯文本下往往还没触发。
      // 判断「是否属于主对话框」请用 {@link isInComposer}。
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

      // 「这个可编辑元素是不是主对话框自己的输入框」—— 判据是**真实包含关系**，
      // 不是"祖先链上有没有定位元素"。
      function isInComposer(el, composer) {
        if (!el || !composer || !document.contains(composer)) { return false; }
        return composer === el || (!!composer.contains && composer.contains(el));
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
          // 主对话框是个矮条；消息列表（ds-virtual-list，实测 h≈687）也满足
          // 「sticky + 贴底」，一旦被当成主对话框就会被整块隐藏。用高度把它排除掉。
          if (r.height > vh * 0.4) { continue; }
          // 底边贴底：主对话框下面还可能有「内容由 AI 生成」那一行，因此留 32px 容差；
          // 该行的外层包装与主对话框同为 sticky，取面积最大的那个即整个底部区域
          if (r.bottom < vh - 32) { continue; }
          var area = r.width * r.height;
          if (area > bestArea) { bestArea = area; best = el; }
        }
        return best;
      }

      // 主对话框的**文字标记**：与回答内容无关，因此在「带公式 / 表格的回答」下依然成立。
      // 值来自 COMPOSER_MARKER_TEXTS（应用侧常量），保证两边不会脱节。
      var COMPOSER_MARKER_TEXTS = ${JSON.stringify(COMPOSER_MARKER_TEXTS)};
      var COMPOSER_MARKERS = new RegExp('${buildComposerMarkerPattern()}');

      // 按文字标记找主对话框 —— 与几何、节点数量都无关。
      //
      // 实机问题（本函数存在的理由）：历史回答里带**数学公式 / 表格**时，主对话框不会收起；
      // 纯文本回答则正常。两条旧路径都会被内容形态影响：
      //   · 「找另一个可编辑元素」在编辑态常常落空（主输入框被换成占位元素）；
      //   · 几何扫描有 4000 节点上限，且要求候选此刻恰好贴底 —— 公式/表格让回答节点
      //     数与高度都大幅上升，扫描要么提前截断、要么候选项不再满足「贴底矮条」。
      // 文字标记只依赖「主对话框还在 DOM 里」，因此不受回答形态影响。
      //
      // 性能：历史对话很长时 DOM 可能上万节点，**绝不能在它上面无脑全量遍历并读 textContent**。
      // 所以先用「包含指定文字」的选择器让内核在 C++ 侧筛（:contains() 是内核扩展，
      // **实机 ArkWeb 7.0 实测不支持、会直接抛错**，所以它只是「能用就更快」的快路径）；
      // 真正兜底是**有上限**的全量扫描：只对叶子级小元素跑正则。
      function findComposerByMarker() {
        var best = null;
        var bestBottom = -1;
        function consider(el) {
          if (!el) { return; }
          var target = containerOfMarker(el);
          if (!target) { return; }
          var r = target.getBoundingClientRect();
          if (r.height <= 0 || r.width <= 0) { return; }
          // 同名元素可能不止一处（页面别处也可能有「深度思考」字样），
          // 主对话框一定最靠下，取 bottom 最大的那个
          if (r.bottom > bestBottom) { bestBottom = r.bottom; best = target; }
        }
        // ① 选择器优先：:contains() 是内核扩展（非标准），用 try 包住；不支持时它会直接抛错
        var textHit = false;
        for (var k = 0; k < ${COMPOSER_MARKER_TEXTS.length}; k++) {
          var text = COMPOSER_MARKER_TEXTS[k];
          var nodes = null;
          try { nodes = document.querySelectorAll('body *:contains("' + text + '")'); } catch (eSel) { nodes = null; }
          if (!nodes || !nodes.length) { continue; }
          textHit = true;
          // **从后往前**取：:contains() 会连同「包含这段文字的所有祖先」一起命中，
          // 而文档顺序是祖先在前、叶子在后。倒着找才能优先命中真正的小元素
          //（顺着的头几个一定是 html/body/各层包装，取它们会把整个页面当成主对话框）。
          var cap = nodes.length < 24 ? nodes.length : 24;
          for (var n = nodes.length - 1; n >= 0 && n >= nodes.length - cap; n--) {
            consider(nodes[n]);
          }
        }
        if (textHit) { return best; }
        // ② 兜底：有上限的全量扫描。只对**叶子级**小元素跑正则 ——
        //    标记文字在深层小节点里，沿途每个祖先都会命中，没必要逐个检查
        try {
          var all = document.querySelectorAll('body *');
          var limit = all.length < 6000 ? all.length : 6000;
          for (var i = 0; i < limit; i++) {
            var el = all[i];
            if (el.children && el.children.length > 0) { continue; }
            var own = String(el.textContent || '').trim();
            if (!own || own.length > 40) { continue; }
            if (!COMPOSER_MARKERS.test(own)) { continue; }
            consider(el);
          }
        } catch (eScan) { }
        return best;
      }

      // 实机拿到的底栏结构（MatePad，可视高度 689、输入框宽 774），供判据参考：
      //
      //   TEXTAREA._27c9245        h60  w774   输入框
      //   └ DIV._24fad49           h60  w774   输入框外层
      //     └ DIV._020ab5b         h118 w774   ← **整条底栏**（输入框 + 工具栏 + 附件/发送）
      //       ├ …输入框…
      //       └ DIV.ec4f5d61       h58  w774   ← 工具栏（"深度思考智能搜索"）
      //         └ DIV._77cefa5     h124 w776   ← 紧贴底栏的包装
      //           └ DIV.aaff8b8f   h124 w776     ← 再外层
      //             └ DIV._871cbca h152 w1053    ← **页面底栏容器**（含"内容由 AI 生成"）
      //               └ DIV.ds-virtual-list h601 w1117  ← 消息列表，绝不能收
      //
      // 结论：想连「深度思考 / 智能搜索 / 附件 / 发送」一起收掉，就必须收到
      // **同时装着输入框与工具栏的那一层**（上面的 _020ab5b）。只按宽度收会收到
      // 输入框外层（_24fad49，h60），于是留下一细条工具栏 —— 实机就是这么复现的。
      //
      // 判据因此改成**语义式**的：从锚点向上，找第一个「同时包含锚点、又包含
      // 工具栏文字标记」的祖先。这条判据与尺寸无关，站点改版换类名、改字号都不影响；
      // 唯一需要的兜底是那条 **高度 ≤ 可视高度 45%** —— 否则会一路收上去，
      // 把整张消息列表（h601）或右侧侧栏抽屉当成底栏藏掉。
      //
      // 文字标记用**预设文字探测**（parentTextIncludes）而不是读每个叶子元素的
      // textContent：后者要在长对话里把每个祖先的整棵子树文本都读出来，
      // 代价太高；前者只读 3 个短标记，命中即返回。
      function parentTextIncludes(el, texts) {
        if (!el || !el.closest) { return false; }
        for (var i = 0; i < texts.length; i++) {
          try { if (el.closest('*:contains("' + texts[i] + '")')) { return true; } } catch (ePt) { }
        }
        return false;
      }

      // 实机确认 :contains() 会被内核拒绝（lastInvoke.hasMarker = "no-selector"），
      // 因此上面的探测基本走不通；真正生效的是这条**有上限的叶子扫描**。
      // 从候选祖先向下找「叶子级小元素」并比对文字：命中即认定这一层装着工具栏。
      function subtreeHasMarkerText(el) {
        if (!el) { return false; }
        try {
          var leaves = el.querySelectorAll('*');
          var lim = leaves.length < 400 ? leaves.length : 400;
          for (var i = 0; i < lim; i++) {
            var n = leaves[i];
            if (n.children && n.children.length > 0) { continue; }
            var t = String(n.textContent || '').trim();
            if (!t || t.length > 24) { continue; }
            if (COMPOSER_MARKERS.test(t)) { return true; }
          }
        } catch (eSm) { }
        return false;
      }

      // 从「命中的标记元素」向上收敛到该被隐藏的那一层容器。
      function containerOfMarker(el) {
        var de = document.documentElement;
        var vh = de ? de.clientHeight : 0;
        var node = el;
        var depth = 0;
        // 一路向上，记住最后一个「高度仍然合理」的祖先，作为找不到工具栏时的退路：
        // 只要它比锚点大，至少能把输入框连它的外层一起收掉。
        var fallback = null;
        while (node && node !== document.body && depth < 12) {
          var r = node.getBoundingClientRect();
          // 高度护栏：超过可视高度 45% 的祖先不再是「底栏」，而是消息列表 / 侧栏抽屉，
          // 收掉它们会把整个界面弄空。遇到就直接停，返回已经找到的退路。
          if (vh > 0 && r.height > vh * 0.45) { break; }
          if (r.height > 0) {
            if (node !== el) { fallback = node; }
            // 这一层同时装着工具栏 → 就是整条底栏
            if (node !== el && subtreeHasMarkerText(node)) { return node; }
          }
          node = node.parentElement;
          depth++;
        }
        return fallback;
      }

      // 按**主输入框占位文案**找主对话框 —— 最可靠的锚点。
      //
      // 实机实测（探针 textareaCands）：主输入框的 placeholder 是「给 DeepSeek 发送消息 」，
      // 而且**编辑历史消息时它依然留在 DOM 里**（编辑卡片是另一个 textarea，
      // 挂在消息列表里），因此这条锚点在两种状态下都成立。
      //
      // 用 indexOf 而不是全等：实测该 placeholder 带尾随空格，站点也可能改前后空白。
      function findComposerByPlaceholder(excludeCard) {
        try {
          var tas = document.querySelectorAll(
            'textarea[placeholder],[contenteditable="true"][placeholder],input[placeholder],' +
            'textarea,[contenteditable="true"]');
          for (var i = 0; i < tas.length; i++) {
            var ta = tas[i];
            if (excludeCard && excludeCard.contains(ta)) { continue; }
            var ph = String((ta.getAttribute && ta.getAttribute('placeholder')) || '');
            var lab = String((ta.getAttribute && ta.getAttribute('aria-label')) || '');
            var hit = false;
            for (var k = 0; k < COMPOSER_MARKER_TEXTS.length; k++) {
              var t = COMPOSER_MARKER_TEXTS[k];
              if (ph.indexOf(t) >= 0 || lab.indexOf(t) >= 0) { hit = true; break; }
            }
            if (!hit) { continue; }
            var c = containerOfMarker(ta);
            if (c && (!excludeCard || (!c.contains(excludeCard) && !excludeCard.contains(c)))) {
              return c;
            }
          }
          return null;
        } catch (ePh) {
          return null;
        }
      }

      // 选定「该隐藏的主对话框」。按可靠性从高到低依次尝试，前一步命中就用它：
      //   ① **主输入框占位文案**（最可靠：与回答形态无关，编辑历史消息时它仍在 DOM 里）；
      //   ② **文字标记**（深度思考 / 智能搜索 / 内容由 AI 生成 —— 与回答形态无关）；
      //   ③ 从「另一个可编辑元素」向上找底部容器（历史路径）；
      //   ④ 全文档几何扫描（最后的兜底，有节点上限，内容复杂时可能落空）。
      // 每一步都排除「编辑卡片自己」：卡片被误当成主对话框藏掉，正在编辑的文本域会
      // 立刻失焦、键盘随即收起（实机复现过的「键盘闪现」）。
      // 同时记下是**哪条路径**命中的（path），实机上「该隐藏却没隐藏」时一眼可辨。
      function pickComposer(mainEdit, editCard) {
        var hidden = window.__dsHiddenCard;
        function usable(el) {
          if (!el || !document.contains(el)) { return false; }
          // 含焦点的候选绝不能隐藏：会让正在编辑的输入框失焦、键盘随即收起
          if (containsActive(el)) { return false; }
          // 编辑卡片（及其子树）绝不能当主对话框隐藏
          if (editCard && (el === editCard || el.contains(editCard) || editCard.contains(el))) {
            return false;
          }
          return true;
        }
        var byPlaceholder = findComposerByPlaceholder(editCard);
        if (usable(byPlaceholder)) { window.__dsComposerPickPath = 'placeholder'; return byPlaceholder; }
        var byMarker = findComposerByMarker();
        if (usable(byMarker)) { window.__dsComposerPickPath = 'marker'; return byMarker; }
        var byEditable = mainEdit ? findBottomCard(mainEdit) : null;
        if (usable(byEditable)) { window.__dsComposerPickPath = 'editable'; return byEditable; }
        var byGeometry = findBottomCardByGeometry();
        if (usable(byGeometry)) { window.__dsComposerPickPath = 'geometry'; return byGeometry; }
        // 最后退一步用「上次隐藏的那个」的父元素：它已经 display:none，
        // 上面几条路都会跳过它，不记住引用就会「藏起来后再也恢复不了」
        if (hidden && document.contains(hidden)) {
          var parent = hidden.parentElement || hidden;
          if (usable(parent)) { window.__dsComposerPickPath = 'cached'; return parent; }
        }
        window.__dsComposerPickPath = 'none';
        return null;
      }

      // 内联编辑卡片 = 从被聚焦的编辑元素向上找到**最近的**、含有「取消 / 保存 / 发送」
      // 这类操作按钮的祖先。
      // 两个坑都踩过：
      //   · 按钮集里不能放「关闭」—— 文本域自带清除按钮就可能带 aria-label="关闭"，
      //     会让最近祖先只框住文本域本身；
      //   · 不能取「最外层」匹配 —— 整张消息列表也在编辑卡片外面，取最外层会拿到
      //     消息列表（实测 ds-virtual-list），限高后把编辑卡片压扁、按钮反而看不见了。
      var CARD_BTN_TEXT = /^(取消|保存|发送|确认|cancel|save|send|done)$/i;
      function findEditCard(el) {
        var node = el;
        var depth = 0;
        while (node && node !== document.body && depth < 8) {
          var btns = node.querySelectorAll('button,[role="button"]');
          for (var i = 0; i < btns.length; i++) {
            var t = String(btns[i].innerText || btns[i].textContent || '').trim();
            if (CARD_BTN_TEXT.test(t)) { return node; }
          }
          node = node.parentElement;
          depth++;
        }
        return null;
      }

      // 按钮行的直接父元素（卡片的某个子元素）—— 标上类后由 CSS 做 sticky 贴底。
      // 取「卡片里最外层那个含按钮的子元素」：sticky 的 bottom:0 是相对卡片的 padding box 的，
      // 加在更深的层级上贴的就不是卡片底边了。
      function findActionRow(card, el) {
        if (!card || !card.children) { return null; }
        var kids = card.children;
        var hit = null;
        for (var i = 0; i < kids.length; i++) {
          var k = kids[i];
          if (k.contains && k.contains(el)) { hit = k; }
        }
        if (!hit) { return null; }
        // 该子元素里必须真的有取消 / 保存 / 发送这类按钮，否则不是按钮行
        var btns = hit.querySelectorAll('button,[role="button"]');
        for (var j = 0; j < btns.length; j++) {
          var t = String(btns[j].innerText || btns[j].textContent || '').trim();
          if (CARD_BTN_TEXT.test(t)) { return hit; }
        }
        return null;
      }

      // 把卡片「贴底对齐」到可视区内：文本域在上面、按钮行在下面，
      // block:'end' 让卡片底边对齐可视底边 —— 按钮行因此落在可视区内
      //（居中反而可能把按钮推到键盘后面）。
      //
      // **只在键盘弹起时做**：apply 会被 resize 触发，而收起键盘同样触发 resize，
      // 若每次都滚，收起键盘时编辑框会被强行拉到最底部（实机现象：
      // 「历史对话内容足够多时，一收键盘对话框自动坍塌到底部」）。
      function alignEditCard() {
        var card = window.__dsEditCard;
        if (!card || !document.contains(card)) { return; }
        try { card.scrollIntoView({ block: 'end' }); } catch (e4) { }
        // 记下当前外高与内容高：下一次据此判断「卡片是不是又长高了」
        window.__dsEditCardMetric = Math.round(card.getBoundingClientRect().height) + '/' +
          card.scrollHeight;
      }

      // 卡片是否比上次记录的又长高了（只认**内容变高**）。
      //
      // 为什么用「内容高」而不是「外高」：卡片被限高后外高是封顶的，图片加载完 / 长文本
      // 贴进来只会让 scrollHeight 变大，继续拿外高比较会漏判 —— 而漏判的后果就是
      // 按钮行被挤出可视区却没有人去重新对齐（本轮要修的现象）。
      // 只认"长高"不认"变矮"：收起键盘只会让尺寸变小，因此绝不会把编辑框拽到最底部
      //（那是上一版「一收键盘就坍塌到底部」的成因）。
      function cardGrew(card) {
        var now = Math.round(card.getBoundingClientRect().height) + '/' + card.scrollHeight;
        var last = window.__dsEditCardMetric;
        if (!last) { window.__dsEditCardMetric = now; return false; }
        if (last === now) { return false; }
        var lastScroll = parseInt(String(last).split('/')[1], 10) || 0;
        var nowScroll = parseInt(String(now).split('/')[1], 10) || 0;
        var lastH = parseInt(String(last).split('/')[0], 10) || 0;
        var nowH = parseInt(String(now).split('/')[0], 10) || 0;
        return nowScroll > lastScroll || nowH > lastH;
      }

      // 键盘弹起 + 卡片长高时，重新贴底对齐一次。由**轻量路径**（输入 / DOM 变化）调用：
      // 站点在编辑历史消息时是异步渲染的 —— 图片解码完成后撑高卡片、长文本贴进来撑高卡片，
      // 都发生在「第一次滚完」之后，只靠 resize 根本等不到。
      // 未弹键盘时只更新基线、不动滚动位置。
      function realignEditCardIfGrown() {
        try {
          var card = window.__dsEditCard;
          if (!card || !document.contains(card)) { return; }
          if (!cardGrew(card)) { return; }
          window.__dsEditCardMetric = Math.round(card.getBoundingClientRect().height) + '/' +
            card.scrollHeight;
          if (window.__dsKeyboardUp) { alignEditCard(); }
        } catch (eGrow) { }
      }

      // 说明：容器里**可能同时**装着「内联编辑卡片」和「主对话框」（实测手机端就是），
      // 历史版本因此写过一个专门的函数：容器含焦点时只隐藏其中「不含焦点」的子元素。
      // 现在改由 pickComposer 用**真实包含关系**挑选主对话框本身（并带 containsActive 兜底），
      // 不会再选到含焦点的容器，那个函数已无调用方，故移除，避免留下两条打架的判据。

      // 拆掉**所有**还带着隐藏类的元素，并清空引用。
      //
      // 为什么要扫全文档、而不是只拆 __dsHiddenCard 那一个：
      // 实机日志抓到了两个元素**先后**都被加过这个类（编辑过程中隐藏目标从
      // DIV._020ab5b 变成了外层的 DIV._871cbca）。原来恢复时只 remove 引用记的那一个，
      // 另一个的类就永久留下了 —— 表现正是「点一次修改，主对话框再也回不来」，
      // 而且因为它的 display:none 还在，输入框祖先链里那一层始终是 d=n/h0。
      // 更糟的是站点重新渲染后引用会变成**游离节点**，那时连 remove 都无从谈起。
      // 所以恢复一律以 DOM 为准：谁带着这个类就拆谁，拆完再清引用。
      function clearHiddenClassEverywhere() {
        try {
          var marked = document.querySelectorAll('.${COMPOSER_HIDDEN_CLASS}');
          for (var i = 0; i < marked.length; i++) {
            marked[i].classList.remove('${COMPOSER_HIDDEN_CLASS}');
          }
          window.__dsHiddenCard = null;
          return marked.length;
        } catch (eClr) {
          return -1;
        }
      }

      window.__dsApplyComposerAutoHide = function () {
        try {
          var ae = document.activeElement;
          var aeEditable = !!(ae && ae.matches && ae.matches('${EDITABLE_SELECTOR}'));
          var keyboardUp = !!window.__dsKeyboardUp;
          // 键盘收起时复位「本次编辑已滚动过」标记：下次再弹起仍会滚一次，
          // 而收起过程中的 resize 不会再动滚动位置
          if (!keyboardUp) { window.__dsEditScrolled = false; }
          // 记一次「被调用」的现场：诊断时用来判断 apply 到底有没有跑、跑的时候焦点在哪。
          // 尤其要区分「apply 没被调用」与「调用但没找到目标」——两者的修法完全不同。
          window.__dsLastApply = {
            t: (typeof Date !== 'undefined' && Date.now) ? Date.now() : 0,
            kbd: !!window.__dsKeyboardUp,
            ae: ae ? ((ae.tagName || '?') + '|' + String(ae.className || '').slice(0, 20) +
              '|' + String(ae.getAttribute ? (ae.getAttribute('placeholder') || '') : '').slice(0, 16)) : 'null',
            editables: document.querySelectorAll('${EDITABLE_SELECTOR}').length,
            hasMarker: (function () {
              try { return document.querySelectorAll('body *:contains("深度思考")').length > 0; }
              catch (eMk0) { return 'no-selector'; }
            })()
          };
          var list = document.querySelectorAll('${EDITABLE_SELECTOR}');
          var mainEdit = null;
          for (var i = 0; i < list.length; i++) {
            if (list[i] !== ae) { mainEdit = list[i]; break; }
          }

          // 先算编辑卡片，再选主对话框（挑选时要排除卡片）。
          //
          // 「是不是内联编辑态」的判据**刻意不看 isInBottomCard**：那个函数只看祖先链上
          // 有没有 fixed/sticky，而**消息列表本身就是 sticky**（实测 ds-virtual-list），
          // 于是「编辑卡片在消息列表里」会被一律判成「在主对话框里」，inlineEdit 永远为
          // false、主对话框永不隐藏 —— 实机现象正是「回答带数学公式 / 表格时不隐藏，
          // 纯文本正常」。这里改成先找出主对话框，再用**真实包含关系**排除它，
          // 另外叠一条「焦点元素不能正好是主对话框节点本身」的保险。
          var editCard = null;
          var editArea = null;
          var priorComposer = window.__dsComposer;
          if (aeEditable &&
            (!isInComposer(ae, priorComposer) && ae !== priorComposer)) {
            editArea = ae;
            editCard = findEditCard(ae);
          } else if (window.__dsEditCard && document.contains(window.__dsEditCard) &&
            window.__dsEditCard.querySelector('${EDITABLE_SELECTOR}')) {
            // **收起键盘后编辑态仍然开着**（焦点可能已经不在输入框上）。
            // 此时如果撤掉标记，限高与粘性按钮行会一起失效，卡片长高后按钮被裁掉 ——
            // 实机现象就是「输入完收起键盘，按钮显示不全」。只要卡片还在，就继续标着。
            // 但要排除「这个卡片其实属于主对话框」——那说明当前不在内联编辑态。
            if (!isInComposer(window.__dsEditCard, priorComposer)) {
              editCard = window.__dsEditCard;
              editArea = window.__dsEditCard.querySelector('${EDITABLE_SELECTOR}');
            }
          }

          // 选主对话框：占位文案 → 文字标记 → 另一个可编辑元素的底部容器 → 几何扫描。
          // **只有「键盘确实收起了、且之前没有处于内联编辑」时才提前收工**：
          // 那一轮唯一要做的事就是把上一次隐藏的恢复出来（上面已做）。
          // 用一个**latch**（__dsWasInlineEdit）而不是「卡片此刻在不在」来判断：
          // 站点是异步渲染的，键盘弹起信号也可能晚到 —— 用户点开编辑框那一刻
          // 键盘标志还是 false，若只用 !keyboardUp 提前返回，就会连编辑卡片都不标记，
          // 于是限高与粘性按钮行一起失效（「一按回车按钮就被裁掉」会复发）。
          if (!keyboardUp && !window.__dsWasInlineEdit) {
            // 这一轮唯一要做的事：把主对话框放出来（扫全文档拆类，不看引用）
            clearHiddenClassEverywhere();
            window.__dsComposerAutoHideInfo = {
              keyboardUp: false,
              activeEditable: aeEditable,
              inlineEdit: false,
              restored: true,
              pickPath: String(window.__dsComposerPickPath || ''),
              editCardCls: '',
              editCardH: 0,
              rowFound: !!window.__dsActionRow,
              rowSticky: window.__dsActionRow
                ? String((styleOf(window.__dsActionRow) || {}).position || '') : ''
            };
            return 'ok';
          }
          var composer = pickComposer(mainEdit, editCard);
          // 记住这次选中的主对话框：markEditCardNow / focusin 都用它来判断
          // 「焦点是不是在主对话框里」，从而与 isInBottomCard 那条错误判据彻底脱钩
          window.__dsComposer = composer;
          // 选出来的主对话框绝不能包含正在编辑的元素：一旦包含，隐藏它会让文本域立刻
          // 失焦、键盘随即收起。宁可不隐藏。
          var target = composer;
          // 含焦点的容器绝不能保持隐藏（会让正在编辑的输入框失焦、键盘随即收起）
          if (window.__dsHiddenCard && containsActive(window.__dsHiddenCard)) {
            clearHiddenClassEverywhere();
          }

          // ⚠️ **「键盘收起 ⇒ 主对话框必须显示」是一条硬保证，无条件执行。**
          //
          // 实机问题（本段存在的理由）：点一次「修改」之后，无论接着做什么操作，
          // 主对话框都再也不回来。抓到的日志给出了确切原因：编辑过程中隐藏目标
          // 从 DIV._020ab5b 变成了外层 DIV._871cbca，**两个元素都带上了隐藏类**，
          // 而旧代码恢复时只 remove 引用记的那一个 —— 另一个永久留在 display:none。
          // 所以这里改成扫全文档拆类（clearHiddenClassEverywhere），
          // 不看引用、不看判据，只要键盘不在就一定把主对话框放出来。
          if (!keyboardUp) {
            clearHiddenClassEverywhere();
          }

          // 主对话框点「发送」后收起软键盘：实测手机端键盘不自动收起（平板端会）。
          // 发送动作本身已完成，这里只是主动 blur 掉焦点，让两端行为一致。
          // 监听只装一次（apply 会被频繁调用）。
          // 注意：这里**不要**再挂「发送后主动 blur」那套监听。
          // 实测它会把两端的原生行为都弄坏：平板端原本点发送会自动收起键盘，
          // 加上 click/pointerup/touchend 捕获监听 + 延迟 blur 之后反而收不起了
          // （推测是拦截了站点自己的失焦/收起流程）。键盘的显示与收起交回内核与站点：
          // 「点图片不弹键盘」仍由 setSoftKeyboardBehaviorMode(DISABLE_AUTO_KEYBOARD_ON_ACTIVE) 保证。
          // 内联编辑态：焦点在编辑卡片内的可编辑元素上（非主对话框的输入框）
          var inlineEdit = keyboardUp && !!editCard;
          // latch：本次「编辑历史消息」期间是否真的进入过内联编辑。
          // 键盘收起时清掉，供下一次编辑复用；上面那个提前收工的分支要看它。
          if (inlineEdit) { window.__dsWasInlineEdit = true; }
          else if (!keyboardUp) { window.__dsWasInlineEdit = false; }
          if (inlineEdit) {
            if (target) {
              target.classList.add('${COMPOSER_HIDDEN_CLASS}');
              window.__dsHiddenCard = target;
            }
          } else {
            // 恢复显示：一律扫全文档拆类（见 clearHiddenClassEverywhere 的说明）。
            // 只 remove 引用记的那一个是不够的 —— 先后可能有两个元素被加过这个类。
            if (target) { target.classList.remove('${COMPOSER_HIDDEN_CLASS}'); }
            clearHiddenClassEverywhere();
          }

          if (editCard) {
            editCard.classList.add('${EDITOR_CARD_CLASS}');
            if (window.__dsEditCard && window.__dsEditCard !== editCard) {
              window.__dsEditCard.classList.remove('${EDITOR_CARD_CLASS}');
              // 换了卡片，旧的尺寸基线作废，否则会误判成「长高了」
              window.__dsEditCardMetric = '';
            }
            window.__dsEditCard = editCard;
            // 按钮行（卡片的那个含按钮的子元素）单独标类 → CSS 给它 sticky 贴底，
            // 这样即使站点把按钮行放在卡片中间、后面还有别的节点，按钮也不会被卷走。
            // 键盘已收起时焦点不在输入框上，改用卡片里的输入框来定位按钮行。
            var rowAnchor = editArea || editCard.querySelector('${EDITABLE_SELECTOR}');
            var row = findActionRow(editCard, rowAnchor);
            if (window.__dsActionRow && window.__dsActionRow !== row) {
              window.__dsActionRow.classList.remove('${EDITOR_ACTION_ROW_CLASS}');
              window.__dsActionRow = null;
            }
            if (row) {
              row.classList.add('${EDITOR_ACTION_ROW_CLASS}');
              window.__dsActionRow = row;
            }
            // 什么时候需要重新贴底对齐：
            //   a) 键盘刚弹起、本次编辑还没滚过 —— 进入编辑态的正常时机；
            //   b) **卡片又长高了** —— 图片加载完、长文本被贴进来、换行重排都会
            //      让卡片在「第一次滚完之后」继续变高，一旦超过可视区，
            //      底部的按钮行就被挤出可视区（正是本轮要修的现象）。
            //      判断依据是"只认长高"，因此收起键盘（尺寸只减不增）不会触发，
            //      不会重蹈「一收键盘编辑框就坍塌到底部」。
            var grew = cardGrew(editCard);
            if (keyboardUp && (!window.__dsEditScrolled || grew)) {
              window.__dsEditScrolled = true;
              alignEditCard();
            } else {
              window.__dsEditCardMetric = Math.round(editCard.getBoundingClientRect().height) +
                '/' + editCard.scrollHeight;
            }
          } else if (window.__dsEditCard) {
            window.__dsEditCard.classList.remove('${EDITOR_CARD_CLASS}');
            window.__dsEditCard = null;
            window.__dsEditCardMetric = '';
            if (window.__dsActionRow) {
              window.__dsActionRow.classList.remove('${EDITOR_ACTION_ROW_CLASS}');
              window.__dsActionRow = null;
            }
          }

          window.__dsComposerAutoHideInfo = {
            keyboardUp: keyboardUp,
            activeEditable: aeEditable,
            inlineEdit: inlineEdit,
            hasCard: !!target,
            hidden: target ? target.classList.contains('${COMPOSER_HIDDEN_CLASS}') : false,
            // 是**哪条路径**找到的主对话框：marker / editable / geometry / cached / none。
            // 实机上「该隐藏却没隐藏」时先看这个 —— marker 表示文字标记命中（与回答形态无关）；
            // 只剩 geometry 或 none，说明回答形态把两条主路径都挤掉了。
            pickPath: String(window.__dsComposerPickPath || ''),
            cardPos: target ? String((styleOf(target) || {}).position || '') : '',
            cardCls: target ? String(target.className || '').slice(0, 40) : '',
            cardH: target ? Math.round(target.getBoundingClientRect().height) : 0,
            editCardCls: editCard ? String(editCard.className || '').slice(0, 40) : '',
            editCardH: editCard ? Math.round(editCard.getBoundingClientRect().height) : 0,
            editCardMax: String((styleOf(editCard) || {}).maxHeight || ''),
            // 按钮行诊断：实机上「按钮看不见」时，先看这两项 ——
            //   rowFound=false  → 没认出按钮行（选择器/按钮文字变了）
            //   rowSticky=false → 认出来了但 sticky 没生效（选择器没绑上或没被覆盖）
            rowFound: !!window.__dsActionRow,
            rowSticky: window.__dsActionRow
              ? String((styleOf(window.__dsActionRow) || {}).position || '') : '',
            rowH: window.__dsActionRow
              ? Math.round(window.__dsActionRow.getBoundingClientRect().height) : 0,
            // 祖先链诊断：编辑卡片到底是哪一层、限高有没有落在它身上。
            // 只有实机拿得到真实结构（站点类名是哈希的，猜不出来），出问题时看这一段即可。
            editChain: (function () {
              try {
                var out = [];
                var n = ae;
                var d = 0;
                while (n && n !== document.body && d < 6) {
                  var cs = styleOf(n) || {};
                  out.push(String(n.tagName) + '.' + String(n.className || '').split(' ')[0] +
                    '(h' + Math.round(n.getBoundingClientRect().height) +
                    ',mh' + String(cs.maxHeight || '') +
                    ',of' + String(cs.overflowY || '').charAt(0) +
                    ',fx' + String(cs.flexGrow || '') + ')');
                  n = n.parentElement;
                  d++;
                }
                return out.join(' < ');
              } catch (eCh) { return ''; }
            })()
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
      // 表现为「点了输入框但键盘不弹」。
      //
      // 与旧版的关键差别：旧版只认「当初那个元素」，一旦站点**把节点换掉**
      //（编辑卡片重渲染很常见），document.contains(el) 立刻为 false，
      // 后面几次补焦全部直接 return —— 焦点再也不回来，键盘自然也不弹。
      // 现在改为握着「卡片 + 编辑会话号」，每次补焦都**重新查一遍卡片里的活输入框**：
      //   · 节点被换掉 → 找到新的那个，照样能把焦点接回来；
      //   · 会话结束（用户点了取消/保存、或卡片被卸载）→ 会话号变化，整批补焦作废，
      //     绝不会在退出编辑后还去抢焦点。
      function currentEditable() {
        var card = window.__dsEditCard;
        if (!card || !document.contains(card)) { return null; }
        var ae = document.activeElement;
        if (ae && ae.matches && ae.matches('${EDITABLE_SELECTOR}') && card.contains(ae)) {
          return ae;
        }
        return card.querySelector('textarea,[contenteditable="true"]') ||
          card.querySelector('${EDITABLE_SELECTOR}');
      }

      // 是否该放弃这次补焦（焦点已经去了别处，说明用户/站点另有打算）。
      function healBlockedByOtherTarget(card) {
        var ae = document.activeElement;
        if (!ae || ae === document.body || ae === document.documentElement) { return false; }
        if (!ae.matches || !ae.matches('${EDITABLE_SELECTOR}')) { return false; }
        // 焦点落在别的可编辑元素上：在卡片里就是用户自己挪了位置，在卡片外则是
        // 主输入框等站点自己的行为 —— 两种情况都不该抢。
        return true;
      }

      function scheduleFocusHeal() {
        // 归一到数字：会话号在 focusin 里用 (x || 0) + 1 递增，
        // 这里若直接取 undefined 会让后续比较永远不等、补焦整批失效。
        var session = window.__dsEditSession || 0;
        var delays = [90, 240, 480, 900];
        for (var i = 0; i < delays.length; i++) {
          setTimeout(function () {
            try {
              // 会话已经变了（退出编辑 / 换了另一条消息）→ 这次补焦作废
              if (!window.__dsEditSession || window.__dsEditSession !== session) { return; }
              // 用户已经点了取消 / 保存 → 立刻停手，绝不和提交抢焦点
              if (window.__dsEditSubmitAt) { return; }
              var card = window.__dsEditCard;
              if (!card || !document.contains(card)) { return; }
              var el = currentEditable();
              if (!el) { return; }
              // 用户在此期间自己把光标放到了别的输入框上 → 不要抢
              if (healBlockedByOtherTarget(card)) { return; }
              if (document.activeElement === el) { return; }
              el.focus();
              window.__dsLastEditFocus = el;
              reportFocus('refocus');
            } catch (e6) { }
          }, delays[i]);
        }
      }

      document.addEventListener('focusin', function (ev) {
        var t = ev.target;
        if (t && t.matches && t.matches('${EDITABLE_SELECTOR}')) {
          // 判据统一为「是不是主对话框自己的输入框」（真实包含关系）。
          // 不能用 isInBottomCard：消息列表自身 sticky，会把列表里的编辑框误判成主对话框，
          // 于是编辑历史消息时既不补焦、也不上报 —— 正是「有公式/表格时不隐藏」的同一根因。
          var inline = !isInComposer(t, window.__dsComposer);
          if (inline) {
            // 进入（或切换）内联编辑：换一个会话号，让上一批补焦立即作废
            if (window.__dsLastEditFocus !== t) {
              window.__dsEditSession = (window.__dsEditSession || 0) + 1;
            }
            window.__dsLastEditFocus = t;
            reportFocus('inline');
            scheduleFocusHeal();
          } else {
            // 焦点回到主输入框 → 内联编辑结束，作废补焦并清掉「已提交」标记
            window.__dsLastEditFocus = null;
            window.__dsEditSession = (window.__dsEditSession || 0) + 1;
            window.__dsEditSubmitAt = 0;
            reportFocus('composer');
          }
        } else if (t && t.closest && !isInComposer(t, window.__dsComposer)) {
          // 点到编辑卡片里的「取消 / 保存 / 确认」：用户已经做了决定，补焦必须立刻停手
          //（否则卡片卸载的瞬间焦点落到 body，补焦会把光标抢回输入框、和提交打架）。
          var submitCard = window.__dsEditCard;
          if (submitCard && submitCard.contains(t) && t.closest('button,[role="button"]')) {
            window.__dsEditSubmitAt = Date.now();
            window.__dsEditSession = (window.__dsEditSession || 0) + 1;
          }
        }
        window.__dsApplyComposerAutoHide();
      }, true);
      document.addEventListener('focusout', function () {
        // 焦点切换有先后：延后一帧再评估，避免读到「还没有新焦点」的中间态
        setTimeout(function () { window.__dsApplyComposerAutoHide(); }, 50);
      }, true);
      window.addEventListener('resize', function () { window.__dsApplyComposerAutoHide(); });

      // 站点在输入（尤其是回车换行）时会重建编辑卡片的节点，我加的两个类会跟着节点一起丢，
      // CSS 限高随即失效、按钮又被裁掉 —— 实机现象就是「一按回车就复现」。
      // 这里把「重新标记」做成一条很轻的独立路径：只从当前焦点向上走几层，
      // 不跑几何扫描，因此可以挂在 DOM 变化与输入事件上频繁触发。
      function markEditCardNow() {
        try {
          var ae = document.activeElement;
          if (!ae || !ae.matches || !ae.matches('${EDITABLE_SELECTOR}')) { return; }
          // 判据是「真实包含关系」，不能用 isInBottomCard ——
          // 消息列表自身 sticky，会把列表里的编辑卡片误判成主对话框（详见该函数说明）。
          // 这里只排除「焦点确实在主对话框里」这一种情况（那是在输入新消息，不是编辑历史）。
          if (isInComposer(ae, window.__dsComposer)) { return; }
          if (window.__dsEditCard && window.__dsEditCard.contains(ae)) {
            // 已经标记过：只需确保长高时重新贴底对齐（下面的调用会处理）
            realignEditCardIfGrown();
            return;
          }
          var card = findEditCard(ae);
          if (card && !card.classList.contains('${EDITOR_CARD_CLASS}')) {
            if (window.__dsEditCard && window.__dsEditCard !== card) {
              window.__dsEditCard.classList.remove('${EDITOR_CARD_CLASS}');
            }
            card.classList.add('${EDITOR_CARD_CLASS}');
            window.__dsEditCard = card;
          }
          var row = card ? findActionRow(card, ae) : null;
          if (row && !row.classList.contains('${EDITOR_ACTION_ROW_CLASS}')) {
            if (window.__dsActionRow && window.__dsActionRow !== row) {
              window.__dsActionRow.classList.remove('${EDITOR_ACTION_ROW_CLASS}');
            }
            row.classList.add('${EDITOR_ACTION_ROW_CLASS}');
            window.__dsActionRow = row;
          }
          // 卡片长高了（图片加载完 / 长文本贴进来）就重新贴底对齐 ——
          // 这条路径在输入与 DOM 变化时都会跑，正好覆盖"第一次滚完之后才变高"的时机；
          // 未弹键盘时它只更新基线，不动滚动位置。
          realignEditCardIfGrown();
        } catch (eMk) { }
      }
      window.__dsMarkEditCard = markEditCardNow;

      // 输入 / 回车会重建节点：这两个事件立刻重标一次
      document.addEventListener('input', function () { markEditCardNow(); }, true);
      document.addEventListener('keyup', function () { markEditCardNow(); }, true);
      // 兜底：站点也可能在别处重建（例如换行后重排），用 observer 观察整棵树，
      // 变化后 60ms 防抖重标一次（重标本身很轻，不做几何扫描）
      if (window.MutationObserver && !window.__dsEditObserver) {
        window.__dsEditObserver = new MutationObserver(function () {
          if (window.__dsEditTimer) { clearTimeout(window.__dsEditTimer); }
          window.__dsEditTimer = setTimeout(function () { markEditCardNow(); }, 60);
        });
        try {
          window.__dsEditObserver.observe(document.body, { childList: true, subtree: true });
        } catch (eOb) { }
      }

      // 注意：这里**不能**再挂「指针按下」事件去补聚焦（即 addEventListener 的 down 事件）。
      // 实测它会在「指针按下」与 click 之间改变布局，导致三件事：
      //   ① 收起态点击卡片空白处时对话框坍塌收缩；
      //   ② 按钮周围出现一圈 focus 高亮边框；
      //   ③ 第一次点击落空，必须再点一次按钮才生效。
      // 站点自己的点击→聚焦逻辑本来就能唤起键盘（期望 6 要保留的正是它），所以整段移除。

      // 供应用侧调用：重新聚焦当前编辑元素（配合 setSoftKeyboardBehaviorMode 兜底拉键盘）。
      //
      // 这里也必须**重新查活节点**：旧版只认 __dsLastEditFocus，站点一旦把文本域节点换掉
      // 就返回 'no-target'，应用侧再怎么兜底都拉不起键盘 —— 正是「有概率不弹」里
      // 最难查的那一半。现在依次退：活焦点 → 卡片里现查的输入框 → 放弃。
      window.__dsRetryEditFocus = function () {
        try {
          // 用户已经点了取消 / 保存，或编辑态已经结束 → 不要抢焦点
          if (window.__dsEditSubmitAt) { return 'submitted'; }
          var card = window.__dsEditCard;
          var el = window.__dsLastEditFocus;
          if (!el || !document.contains(el)) {
            el = (card && document.contains(card)) ? currentEditable() : null;
          }
          if (!el || !document.contains(el)) { return 'no-target'; }
          try { el.blur(); } catch (e9) { }
          el.focus();
          window.__dsLastEditFocus = el;
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
 * 探测结果：**图片/文件预览态**。
 *
 * 与 dialog 的区别在**关闭方式**：预览层在全屏遮罩里、点图片本身是缩放而非关闭，
 * 且多数不往历史里 push。若当 dialog 处理会走 `canGoBack ? backward : dismiss-overlay`，
 * 两条路都关不掉 —— 用户侧滑后预览没关、系统把这次返回当退出应用，直接回到桌面。
 * 单列一类，强制走「关闭入口 / 点遮罩」路径，**绝不 backward、绝不退出**。
 */
export const OVERLAY_PREVIEW: string = 'preview';
/**
 * 探测结果：**确认类弹窗**（删除确认等，含「确认/删除」+「取消」成对按钮）。
 *
 * 单独识别的原因：这类弹窗常带「取消」文字按钮，会被下面的 closable 规则先命中，
 * 走「点关闭入口」那条路；点不中时返回就被当成退出应用（实机表现同样是回到桌面）。
 * 明确成 confirm 类后可用更可靠的关闭顺序（先点取消、再 Esc、最后点遮罩空白）。
 */
export const OVERLAY_CONFIRM: string = 'confirm';

/**
 * 站点通用浮层容器（`.ds-floating-position-wrapper`）：额度卡片、模型菜单等
 * **锚定式浮卡**。它们没有 role=dialog / aria-modal / 关闭按钮，返回键既不能
 * 后退（不进历史）也不能靠 DOM 关闭入口，只能「点外部」。
 *
 * 单独成类是为了让调用方知道：这一类**必须消费本次返回**——关闭失败也不能
 * 在同一次返回里退化成网页后退（否则卡片还在、会话却退了）。
 */
export const OVERLAY_FLOAT: string = 'float';

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
      // 0) 判定辅助：向上找「模态容器」。
      //
      // ⚠️ 实测（MatePad，删除确认弹窗）：DeepSeek 的 .ds-modal 是
      //    position:relative + z-index:auto，**不是** fixed/absolute。
      //    因此绝不能按 position/zIndex 找容器 —— 那样一个都匹配不到。
      //    改为按「尺寸像个弹窗」筛选：宽 120~96% 视口、高 80~92% 视口。
      function modalAncestorOf(el, maxUp) {
        var up = el, k = 0;
        while (up && up !== document.body && k < maxUp) {
          var r = up.getBoundingClientRect();
          if (r.width >= 120 && r.height >= 80 &&
            r.width <= window.innerWidth * 0.96 &&
            r.height <= window.innerHeight * 0.92) {
            return up;
          }
          up = up.parentElement; k++;
        }
        return null;
      }
      // 找「文字恰好等于 text」的可见元素。
      // ⚠️ 不要求叶子节点：实测按钮是 DIV(含 2 个子节点) > SPAN，
      //    要求 element.children.length === 0 会把按钮整个漏掉。
      //    改用 innerText 精确相等 + 尺寸像按钮 + 无子元素文本，三者共同约束。
      function findTextButton(root, text) {
        var all = root.querySelectorAll('body *, *');
        var lim = all.length < 3000 ? all.length : 3000;
        for (var i = 0; i < lim; i++) {
          var el = all[i];
          if (String(el.innerText || '').trim() !== text) { continue; }
          if (!visible(el, 4, 4)) { continue; }
          var r = el.getBoundingClientRect();
          if (r.width > 320 || r.height > 120) { continue; }
          // 取「最小的那个」匹配元素：外层 DIV 与其内 SPAN 文字相同，
          // 命中 SPAN 才是真正的按钮体（外层可能就是整个弹窗）。
          return el;
        }
        return null;
      }

      // 0a) 预览态：模态浮层里有一张**大尺寸图片**（接近全屏的查看器）。
      //     必须放在通用 dialog 之前 —— 预览层往往也带 role=dialog，被先抢走就会走错关闭路径。
      var imgs = document.querySelectorAll('img');
      for (i = 0; i < imgs.length; i++) {
        var im = imgs[i];
        if (!visible(im, 160, 160)) { continue; }
        var ir = im.getBoundingClientRect();
        var big = Math.min(ir.width, ir.height) >= window.innerHeight * 0.3 ||
          (ir.width * ir.height) >= (window.innerWidth * window.innerHeight) * 0.35;
        if (!big) { continue; }
        var host = modalAncestorOf(im, 10);
        if (!host) { continue; }
        var hr = host.getBoundingClientRect();
        // 宿主必须盖住大半屏，否则只是正文里的大图
        if (hr.width < window.innerWidth * 0.8 || hr.height < window.innerHeight * 0.7) { continue; }
        return hit('${OVERLAY_PREVIEW}', host);
      }

      // 0b) 确认类弹窗：「取消/关闭」+（确认/确定/删除…）成对出现在同一个弹窗容器里。
      //     实测文案："取消" 与 "删除" 同属一个 380x180 的 .ds-modal。
      var cancelEl = findTextButton(document, '取消') || findTextButton(document, '关闭') ||
        findTextButton(document, 'Cancel');
      if (cancelEl) {
        var host = modalAncestorOf(cancelEl, 10);
        if (host) {
          var confTexts = ['确认', '确定', '删除', '确认删除', '移除', '清空',
            '删除该对话', '删除对话', '继续', 'OK', 'Confirm', 'Delete'];
          for (i = 0; i < confTexts.length; i++) {
            if (findTextButton(host, confTexts[i])) {
              return hit('${OVERLAY_CONFIRM}', host);
            }
          }
        }
      }

      // 0c) **容器级兜底**：只要存在可见的模态弹窗容器，就归为确认类。
      //
      // 为什么需要它：0b 依赖具体按钮文案，而文案会随功能变化 ——
      // 实测同一个"删除"动作就有「删除」与「删除该对话」两种按钮文字，
      // 漏一个就会退回"关不掉 → 系统当成退出/网页后退"的老问题。
      // "存在可见弹窗容器"是稳定得多的结构信号，因此放在文案规则之后兜底。
      //
      // ⚠️ 不能无条件归类：实测「系统设置」弹窗没有可点的关闭入口、也不响应 Esc，
      //    **只能用 backward() 关**。若无条件归为确认类，会从"能关"退化成"关不掉"。
      //    因此要求容器内**确实存在可点的关闭/取消入口**才判定为确认类。
      // 同时排除靠近全屏的容器（那是抽屉/侧栏，已有专门处理）。
      var modals = document.querySelectorAll('.ds-modal, [role="dialog"], [aria-modal="true"]');
      for (i = 0; i < modals.length; i++) {
        var md = modals[i];
        if (!visible(md, 80, 80)) { continue; }
        var mr = md.getBoundingClientRect();
        if (mr.width > window.innerWidth * 0.96 && mr.height > window.innerHeight * 0.92) { continue; }
        var dismissible = !!findTextButton(md, '取消') || !!findTextButton(md, '关闭') ||
          !!findTextButton(md, 'Cancel');
        if (!dismissible) {
          var lbls = md.querySelectorAll('[aria-label],[title]');
          for (var li = 0; li < lbls.length; li++) {
            var lv = String(lbls[li].getAttribute('aria-label') ||
              lbls[li].getAttribute('title') || '').trim();
            if (/^(close|关闭|取消|close dialog)$/i.test(lv) && visible(lbls[li], 4, 4)) {
              dismissible = true; break;
            }
          }
        }
        if (dismissible) { return hit('${OVERLAY_CONFIRM}', md); }
      }

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
      // 2b) 站点的通用浮层容器：额度卡片这类「锚定式浮卡」没有 role/aria-modal，
      //     只有 .ds-floating-position-wrapper（position:absolute + z-index 1000+）。
      //     不认它就会一路落到 OVERLAY_NONE → 返回键变成网页后退/退出，而不是关卡片。
      //
      //     多个浮层同时存在时只关最上层一个：按 z-index 取最大，同层取 DOM 靠后的
      //     （后插入的通常在上面）。DOM 顺序本身不代表视觉层级，所以不能取第一个。
      var floats = document.querySelectorAll('.ds-floating-position-wrapper');
      var bestFloat = null;
      var bestZ = -1;
      var vw2 = window.innerWidth || 0;
      var vh2 = window.innerHeight || 0;
      for (i = 0; i < floats.length; i++) {
        var fe = floats[i];
        if (!visible(fe, 80, 60)) { continue; }
        var fs2 = window.getComputedStyle(fe);
        if (!fs2) { continue; }
        if (fs2.pointerEvents === 'none') { continue; }
        var fz = Number(fs2.zIndex);
        if (!(fz >= 100)) { continue; }
        var fr2 = fe.getBoundingClientRect();
        // 与视口相交才算数（旋转/分屏后可能被挪到视口外）
        if (fr2.right <= 0 || fr2.bottom <= 0 || fr2.left >= vw2 || fr2.top >= vh2) { continue; }
        if (fz >= bestZ) { bestZ = fz; bestFloat = fe; }
      }
      if (bestFloat) { return hit('${OVERLAY_FLOAT}', bestFloat); }
      // 3) 带「关闭 / 取消」入口的界面（多选 / 选择对话 / 分享选择等）
      var cands = document.querySelectorAll('[aria-label],[title]');
      for (i = 0; i < cands.length; i++) {
        var lab = String(cands[i].getAttribute('aria-label') ||
          cands[i].getAttribute('title') || '').trim();
        if (!/^(close|关闭|取消|关闭对话框|close dialog)$/i.test(lab)) { continue; }
        if (visible(cands[i], 4, 4)) { return hit('${OVERLAY_CLOSABLE}', cands[i]); }
      }
      // 3b) 兜底：只有文字「取消 / 关闭」的按钮（部分机型没有 aria-label）。
      //     复用 findTextButton —— 实测按钮是 DIV(含子节点) > SPAN，
      //     早先"要求叶子节点"的写法会把这类按钮整个漏掉。
      var textCancel = findTextButton(document, '取消') || findTextButton(document, '关闭');
      if (textCancel) {
        return hit('${OVERLAY_CLOSABLE}', textCancel);
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
  if (kind === OVERLAY_DIALOG || kind === OVERLAY_MENU || kind === OVERLAY_CLOSABLE ||
    kind === OVERLAY_PREVIEW || kind === OVERLAY_CONFIRM || kind === OVERLAY_FLOAT) {
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
/**
 * 关闭**预览态 / 确认弹窗**的脚本（与 {@link buildOverlayDismissScript} 分开）。
 *
 * 为什么不能复用菜单那套：菜单的关闭是「点自己的关闭入口 → 点展开态触发按钮 → 把点击派发到 body」；
 * 而预览层的遮罩属于它自己，派发到 body 关不掉，且**点图片本身是缩放而非关闭**。
 * 确认弹窗同理：必须点到它自己的「取消」才安全（点确认/删除会执行破坏性操作）。
 *
 * 策略顺序（按可靠度与安全性递减）：
 *   1. 浮层内明确的关闭入口（aria-label / title 含 close、关闭、取消）；
 *   2. 浮层内文字恰为「取消 / 关闭 / Cancel」的叶子按钮；
 *   3. 派发 Escape 键（多数模态监听 Esc 关闭）；
 *   4. 点遮罩空白 —— **必须避开图片本体**，否则会命中"点图片缩放"。
 *
 * @param kind 探测得到的界面类型（OVERLAY_PREVIEW / OVERLAY_CONFIRM）
 * @returns 可直接交给 runJavaScript 的 IIFE 脚本
 */
export function buildOverlayCloseScript(kind: string): string {
  const kindJs: string = JSON.stringify(kind);
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
      function modalAncestorOf(el, maxUp) {
        var up = el, k = 0;
        while (up && k < maxUp) {
          var st = window.getComputedStyle(up);
          if (st && (st.position === 'fixed' || st.position === 'absolute')) {
            var z = parseInt(st.zIndex, 10);
            if (!isNaN(z) && z >= 10) { return up; }
          }
          up = up.parentElement; k++;
        }
        return null;
      }
      function fire(el, x, y) {
        try {
          var opts = { bubbles: true, cancelable: true, view: window, clientX: x, clientY: y };
          el.dispatchEvent(new MouseEvent('mousedown', opts));
          el.dispatchEvent(new MouseEvent('mouseup', opts));
          el.dispatchEvent(new MouseEvent('click', opts));
        } catch (e2) { }
      }
      var kind = ${kindJs};
      var i, j;

      // 找「最上层的大浮层」作为作用域，避免点到页面其他地方
      var host = null;
      var all = document.querySelectorAll('body *');
      var lim = all.length < 4000 ? all.length : 4000;
      for (i = 0; i < lim; i++) {
        var el = all[i];
        var st = window.getComputedStyle(el);
        if (!st || (st.position !== 'fixed' && st.position !== 'absolute')) { continue; }
        var z = parseInt(st.zIndex, 10);
        if (isNaN(z) || z < 10) { continue; }
        if (!visible(el, 120, 80)) { continue; }
        var r = el.getBoundingClientRect();
        if (r.width < window.innerWidth * 0.6 || r.height < window.innerHeight * 0.5) { continue; }
        if (!host || z >= host.z) { host = { el: el, z: z }; }
      }
      if (!host) { return 'no-host'; }
      var scope = host.el;

      // 1) 明确的关闭入口
      var cands = scope.querySelectorAll('[aria-label],[title]');
      for (i = 0; i < cands.length; i++) {
        var lab = String(cands[i].getAttribute('aria-label') ||
          cands[i].getAttribute('title') || '').trim();
        if (!/^(close|关闭|取消|关闭对话框|close dialog|取消下载)$/i.test(lab)) { continue; }
        if (!visible(cands[i], 4, 4)) { continue; }
        fire(cands[i], 0, 0);
        return 'closed-by-label:' + lab;
      }

      // 2) 文字按钮：取消 / 关闭
      var leaves = scope.querySelectorAll('body *, *');
      var llim = leaves.length < 3000 ? leaves.length : 3000;
      for (i = 0; i < llim; i++) {
        var le = leaves[i];
        if (le.children && le.children.length > 0) { continue; }
        var t = String(le.innerText || '').trim();
        if (t !== '取消' && t !== '关闭' && t !== 'Cancel') { continue; }
        if (!visible(le, 4, 4)) { continue; }
        var lr = le.getBoundingClientRect();
        if (lr.width > 320 || lr.height > 120) { continue; }
        fire(le, lr.left + lr.width / 2, lr.top + lr.height / 2);
        return 'closed-by-text:' + t;
      }

      // 3) Escape 键
      try {
        var kev = { bubbles: true, cancelable: true, key: 'Escape', code: 'Escape', keyCode: 27, which: 27 };
        var tgt = document.activeElement || document.body;
        tgt.dispatchEvent(new KeyboardEvent('keydown', kev));
        tgt.dispatchEvent(new KeyboardEvent('keyup', kev));
        document.dispatchEvent(new KeyboardEvent('keydown', kev));
      } catch (e3) { }

      // 4) 点遮罩空白：九宫格取样，跳过图片/视频本体与浮层内的子内容
      var r2 = scope.getBoundingClientRect();
      var pts = [[0.04, 0.04], [0.96, 0.04], [0.04, 0.96], [0.96, 0.96], [0.5, 0.03], [0.5, 0.97]];
      for (i = 0; i < pts.length; i++) {
        var x = Math.round(r2.left + r2.width * pts[i][0]);
        var y = Math.round(r2.top + r2.height * pts[i][1]);
        var hitEl = document.elementFromPoint(x, y);
        if (!hitEl) { continue; }
        // 命中图片/视频/画布 ⇒ 那是"点图片缩放"，跳过
        var tag = String(hitEl.tagName || '').toUpperCase();
        if (tag === 'IMG' || tag === 'VIDEO' || tag === 'CANVAS') { continue; }
        // 命中浮层内部的内容盒子 ⇒ 也可能触发内容行为，跳过；只点遮罩层自身
        if (hitEl !== scope) { continue; }
        fire(hitEl, x, y);
        return 'closed-by-backdrop:' + x + ',' + y;
      }
      return 'not-closed:' + kind;
    } catch (e) {
      return 'close-error';
    }
  })();`;
}


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
      var vw3 = window.innerWidth || 0;
      var vh3 = window.innerHeight || 0;
      var cx = Math.round(vw3 / 2);
      var cy = Math.round(vh3 / 2);
      // 浮卡（.ds-floating-position-wrapper）可能正好盖住视口中心：那样「点外部」
      // 会点在浮卡自己身上，等于没点。这里按「视口内 + 浮卡外」筛候选点，
      // 全部不满足时**不点**（返回 no-safe-point，由调用方消费本次返回），
      // 绝不退化成网页后退，也不盲点第二次。
      var topFloat = null;
      var topZ = -1;
      try {
        var fl = document.querySelectorAll('.ds-floating-position-wrapper');
        for (i = 0; i < fl.length; i++) {
          if (!visible(fl[i], 80, 60)) { continue; }
          var fcs = window.getComputedStyle(fl[i]);
          if (!fcs || fcs.pointerEvents === 'none') { continue; }
          var fzv = Number(fcs.zIndex);
          if (!(fzv >= 100)) { continue; }
          if (fzv >= topZ) { topZ = fzv; topFloat = fl[i]; }
        }
      } catch (e11) { }
      if (topFloat) {
        var tr = topFloat.getBoundingClientRect();
        var pad = 8;
        var cands2 = [
          [Math.round(tr.left - 60), Math.round(tr.bottom - 40)],
          [Math.round(tr.right + 60), Math.round(tr.bottom - 40)],
          [Math.round(tr.left + 20), Math.round(tr.bottom + 48)],
          [Math.round(tr.left + 20), Math.round(tr.top - 48)],
          [12, 12],
          [vw3 - 12, 12],
          [12, vh3 - 12],
          [vw3 - 12, vh3 - 12]
        ];
        for (var ci = 0; ci < cands2.length; ci++) {
          var px2 = cands2[ci][0];
          var py2 = cands2[ci][1];
          if (px2 < 1 || py2 < 1 || px2 >= vw3 || py2 >= vh3) { continue; }
          var outside = !(px2 >= tr.left - pad && px2 <= tr.right + pad &&
            py2 >= tr.top - pad && py2 <= tr.bottom + pad);
          if (!outside) { continue; }
          // 注意：这里**不做坐标命中查询**。派发目标始终是 body，
          // 坐标只用于给站点的「点外部」判定一个有意义的落点；
          // 按坐标去找元素再点，正是会把抽屉遮罩一起收起的旧做法（有单测守着）。
          fire(host, px2, py2);
          return 'clicked-outside-body:' + px2 + ',' + py2;
        }
        return 'no-safe-point';
      }
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

      // 内联编辑态专项诊断。
      //
      // 存在的理由：实机「回答带公式/表格时主对话框不收起」只能靠真实 DOM 判定到底
      // 卡在哪一步，而这个结构无法在本地复现（站点类名是哈希的）。这里一次把关键判据
      // 全打出来，一次实机取样即可定位：
      //   · markerTexts  : 主对话框的文字标记到底有没有出现在 DOM 里（一条都没有 →
      //                    站点改了文案或结构，标记这条路整体失效）
      //   · pickPath     : applyComposerAutoHide 最后走的是哪条路径（none = 没找到）
      //   · picked       : 那条路径选中的元素是什么、算不算「已隐藏」
      //   · editCard     : 编辑卡片是否被认出来（null = 没认出来，那 inlineEdit 必为 false）
      //   · containers   : 标记文字的可见祖先里，哪些是 fixed/sticky 且贴底
      //   · fixedBottom  : 全文档 fixed/sticky 且贴底的容器（回答形态是否把它挤出候选）
      //   · lastInvoke   : applyComposerAutoHide 最近一次被调用的时刻与入参
      var editDiag = null;
      try {
        var de2 = document.documentElement;
        var vh2 = de2 ? de2.clientHeight : 0;
        var vw2 = de2 ? de2.clientWidth : 0;
        function brief(el) {
          if (!el) { return null; }
          var cs2 = window.getComputedStyle(el);
          var r2 = el.getBoundingClientRect();
          return (el.tagName || '?') + '|' + String(el.className || '').slice(0, 28) +
            '|pos=' + String(cs2 ? cs2.position : '') +
            '|' + Math.round(r2.top) + ',' + Math.round(r2.bottom) +
            '|h' + Math.round(r2.height) + '|w' + Math.round(r2.width) +
            '|txt=' + String(el.innerText || '').replace(/\s+/g, ' ').slice(0, 18);
        }
        // 1) 文字标记是否存在于 DOM
        var markerHits = [];
        try {
          for (var mi = 0; mi < COMPOSER_MARKER_TEXTS.length; mi++) {
            var mt = COMPOSER_MARKER_TEXTS[mi];
            var cnt = 0;
            try { cnt = document.querySelectorAll('body *:contains("' + mt + '")').length; } catch (eQ) { cnt = -1; }
            if (cnt !== 0) { markerHits.push(mt + ':' + cnt); }
          }
        } catch (eM1) { }
        // 2) 可见的标记元素 → 它的祖先里谁是 fixed/sticky、贴不贴底
        var containers = [];
        try {
          var leaves2 = document.querySelectorAll('body *');
          var lim2 = leaves2.length < 3500 ? leaves2.length : 3500;
          for (var li = 0; li < lim2 && containers.length < 8; li++) {
            var le2 = leaves2[li];
            if (le2.children && le2.children.length > 0) { continue; }
            var own2 = String(le2.textContent || '').trim();
            if (!own2 || own2.length > 30 || !COMPOSER_MARKERS.test(own2)) { continue; }
            var node2 = le2;
            var d2 = 0;
            while (node2 && node2 !== document.body && d2 < 12) {
              var cs3 = window.getComputedStyle(node2);
              if (cs3 && (cs3.position === 'fixed' || cs3.position === 'sticky')) {
                containers.push(brief(node2));
                break;
              }
              node2 = node2.parentElement;
              d2++;
            }
            if (!node2 || node2 === document.body) {
              containers.push('no-positioned-ancestor:' + brief(le2));
            }
          }
        } catch (eM2) { }
        // 2) 可见的标记元素 → 它的**完整祖先链**（每层的 position/rect）。
        // 为什么要把整条链都打出来：实机诊断发现主对话框并**不是**用 position:fixed/sticky
        // 贴底的 —— containers 与 fixedBottom 都是空数组，说明「向上找固定定位祖先」
        // 这条路根本无从下手。必须看清它到底靠什么贴在底部，才能写出正确判据。
        // 同时这也解释了一个陷阱：:contains() 是内核扩展，本设备（ArkWeb 7.0 / Chromium 144）
        // **不支持**，选择器会直接抛错（见 lastInvoke.hasMarker = "no-selector"），
        // 所以「文字标记」只能靠全量扫描实现，不能依赖该选择器。
        var markerChain = [];
        var markerRaw = [];
        try {
          var reSend = /发送消息|深度思考|智能搜索|内容由 AI 生成/;
          var reTerm = /发送|思考|搜索|生成/;
          var leaves3 = document.querySelectorAll('body *');
          var lim3 = leaves3.length < 12000 ? leaves3.length : 12000;
          for (var l3 = 0; l3 < lim3; l3++) {
            var le3 = leaves3[l3];
            if (le3.children && le3.children.length > 0) { continue; }
            var own3 = String(le3.textContent || '').trim();
            if (!own3 || own3.length > 30) { continue; }
            // 原始取样：把「含关键字、但正则没命中」的也记下来 ——
            // 用来排查「标记文案与预期不符 / 空白字符差异」这类问题
            if (markerRaw.length < 10 && reTerm.test(own3)) {
              var rawR = le3.getBoundingClientRect();
              markerRaw.push(JSON.stringify(own3.slice(0, 20)) + '@' +
                Math.round(rawR.top) + ',h' + Math.round(rawR.height) +
                ',cls=' + String(le3.className || '').slice(0, 18) +
                ',match=' + COMPOSER_MARKERS.test(own3));
            }
            if (!reSend.test(own3)) { continue; }
            var r3 = le3.getBoundingClientRect();
            if (r3.height <= 0 || r3.width <= 0) { continue; }
            if (markerChain.length >= 6) { continue; }
            var chain = [];
            var n4 = le3;
            var d4 = 0;
            while (n4 && n4 !== document.body && d4 < 10) {
              var c4 = window.getComputedStyle(n4);
              var rr4 = n4.getBoundingClientRect();
              chain.push((n4.tagName || '?') + '.' + String(n4.className || '').split(' ')[0] +
                '(pos=' + String(c4 ? c4.position : '') +
                ',ofY=' + String(c4 ? c4.overflowY : '').charAt(0) +
                ',t' + Math.round(rr4.top) + '-b' + Math.round(rr4.bottom) +
                ',h' + Math.round(rr4.height) + ',w' + Math.round(rr4.width) + ')');
              n4 = n4.parentElement;
              d4++;
            }
            markerChain.push('TXT[' + own3.slice(0, 12) + '] ' + chain.join(' < '));
          }
        } catch (eM4) { }

        // 3) 全文档 fixed/sticky 且贴底的容器（不依赖任何文字标记）
        var fixedBottom = [];
        try {
          // 放宽约束逐个列出：只要 fixed/sticky、宽度过半、高度在 (0, 0.7vh]，
          // 高度逐条可见 —— 用来判断「主对话框到底算不算固定底栏」。
          // 编辑态下它的输入框会被换成占位元素，某些判据（尺寸/文字）会失效，
          // 所以这里连尺寸一起打出来。
          var allv = document.querySelectorAll('body *');
          var limv = allv.length < 4000 ? allv.length : 4000;
          for (var vi = 0; vi < limv && fixedBottom.length < 10; vi++) {
            var ve = allv[vi];
            var vcs = window.getComputedStyle(ve);
            if (!vcs || (vcs.position !== 'fixed' && vcs.position !== 'sticky')) { continue; }
            if (vcs.display === 'none' || vcs.visibility === 'hidden') { continue; }
            var vr = ve.getBoundingClientRect();
            if (vr.width < vw2 * 0.5 || vr.height <= 0 || vr.height > vh2 * 0.7) { continue; }
            fixedBottom.push(brief(ve) + '|z' + String(vcs.zIndex) +
              '|bGap' + Math.round(vh2 - vr.bottom));
          }
        } catch (eM3) { }
        // 4) 编辑卡片是否被认出来
        var ec = window.__dsEditCard;
        editDiag = {
          pickPath: String(window.__dsComposerPickPath || ''),
          hiddenClassOn: window.__dsHiddenCard
            ? !!window.__dsHiddenCard.classList.contains('${COMPOSER_HIDDEN_CLASS}') : false,
          picked: brief(window.__dsHiddenCard || window.__dsComposer),
          editMarked: brief(ec),
          editAreaChain: (function () {
            try {
              var out2 = [];
              var n3 = window.__dsLastEditFocus;
              var d3 = 0;
              while (n3 && n3 !== document.body && d3 < 6) {
                var c3 = window.getComputedStyle(n3);
                out2.push((n3.tagName || '?') + '.' + String(n3.className || '').split(' ')[0] +
                  '(h' + Math.round(n3.getBoundingClientRect().height) +
                  ',pos' + String(c3 ? c3.position : '') + ')');
                n3 = n3.parentElement;
                d3++;
              }
              return out2.join(' < ');
            } catch (eC) { return ''; }
          })(),
          markerTexts: markerHits,
          containers: containers,
          markerChain: markerChain,
          markerRaw: markerRaw,
          textareaCands: (function () {
            try {
              var out = [];
              var tas = document.querySelectorAll('textarea,input,[contenteditable="true"]');
              for (var ti = 0; ti < tas.length && out.length < 8; ti++) {
                var ta = tas[ti];
                var tr = ta.getBoundingClientRect();
                out.push((ta.tagName || '?') + '|ph=' +
                  JSON.stringify(String(ta.getAttribute ? (ta.getAttribute('placeholder') || '') : '').slice(0, 18)) +
                  '|cls=' + String(ta.className || '').slice(0, 22) +
                  '|' + Math.round(tr.top) + '-' + Math.round(tr.bottom));
              }
              return out;
            } catch (eTa) { return null; }
          })(),
          fixedBottom: fixedBottom,
          // 主对话框的**子树结构**（含输入框外面每一层包装）：实机现在的现象是
          // 「输入区收起来了，但留了一条含 深度思考/智能搜索/附件/发送 的细长区域」，
          // 说明隐藏目标是输入框内部那一层，而不是整个底栏。
          // 必须看清底栏各层的真实尺寸，才能确定该收哪一层、以及用什么判据稳定地选到它。
          composerTree: (function () {
            try {
              var area = document.querySelector('textarea[placeholder]') ||
                document.querySelector('textarea');
              if (!area) { return 'no-textarea'; }
              // 用「分号分隔的扁平字符串」而不是嵌套对象数组：嵌套 JSON 太长且容易被
              // hilog 截断（实测只能拿到第一个元素），扁平串每层一小段，稳定可读。
              var out = [];
              var n = area;
              var d = 0;
              while (n && n !== document.body && d < 8) {
                var cs = n.__cs || window.getComputedStyle(n);
                var r = n.getBoundingClientRect();
                out.push((n.tagName || '?') + '.' +
                  String(n.className || '').split(' ').slice(0, 2).join('.') +
                  '{p=' + String(cs.position).charAt(0) +
                  ',o=' + String(cs.overflowY).charAt(0) +
                  ',d=' + String(cs.display).charAt(0) +
                  ',t' + Math.round(r.top) + 'b' + Math.round(r.bottom) +
                  ',h' + Math.round(r.height) + 'w' + Math.round(r.width) + '}');
                n = n.parentElement;
                d++;
              }
              // 再补一遍「各层祖先的最后一个子元素」：发送按钮 / 工具栏通常挂在那里。
              // 想确定「该收哪一层」，就必须知道每层里除输入框之外还有什么。
              var n2 = area.parentElement;
              var d2 = 0;
              while (n2 && n2 !== document.body && d2 < 4) {
                var last = n2.children && n2.children.length
                  ? n2.children[n2.children.length - 1] : null;
                if (last && last !== area) {
                  var lr = last.getBoundingClientRect();
                  out.push('LAST@L' + d2 + ':' + (last.tagName || '?') + '.' +
                    String(last.className || '').split(' ').slice(0, 2).join('.') +
                    '{t' + Math.round(lr.top) + 'b' + Math.round(lr.bottom) +
                    ',h' + Math.round(lr.height) + 'w' + Math.round(lr.width) + '}' +
                    '="' + String(last.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 22) + '"');
                }
                n2 = n2.parentElement;
                d2++;
              }
              return out.join(' ## ');
            } catch (eTree) { return 'tree-error'; }
          })(),
          // 说明：曾为「去掉免责声明下方那条 28vp 白带」临时加过一个 composerBottom 探针。
          // 结论已经拿到（截图像素实测：纯白 y=1520~1575，其后才是系统手势导航条；
          // 而 clientH=vvH=innerH=689 说明应用侧窗口本来就已沉浸、没有底部避让），
          // 那条白带是站点自己的底部安全间距。经确认保留现状，故该探针已移除，
          // 不把一次性的排查代码留在发布路径里。
          //
          // 同理，曾为「右侧定位历史对话面板」加过一次专项探针，也已移除 ——
          // 它给出的结论是：该面板**没有任何可识别的 DOM 标记**（不是 dialog/menu、
          // 没有关闭按钮、右半屏 fixed 容器数为 0），但打开时 history.length 会从 1 变 2。
          // 基于该结论的改动已按需回退，此处只留结论备查。
          lastInvoke: window.__dsLastApply || null,
          autoHideInfo: window.__dsComposerAutoHideInfo || null
        };
      } catch (eEd) { }

      return JSON.stringify({
        ua: navigator.userAgent,
        mobileToken: /Mobile/i.test(navigator.userAgent),
        histLen: window.history ? window.history.length : -1,
        overlay: overlay,
        ui: ui,
        editDiag: editDiag,
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

export function buildMathRepairScript(): string {
  return `(function () {
    try {
      var kx = window.katex;
      // 脚本版本标记：改逻辑就换一个，便于在日志里确认设备上跑的是哪一版
      var VER = 'mathfix=v3';
      if (!kx || typeof kx.renderToString !== 'function') { return VER + ' no-katex'; }
      // 最小自检：KaTeX 能用、且真能产出 katex 结构（注入成功但被站点脚本破坏时能看出来）
      var selfTest = 'bad';
      try {
        var st = kx.renderToString('x^2', { throwOnError: true, strict: 'ignore' });
        selfTest = (st && st.indexOf('katex') >= 0) ? 'ok' : 'bad';
      } catch (e0) { selfTest = 'bad'; }
      window.__dsMathFixVer = VER;
      var BS = String.fromCharCode(92);
      var NL = String.fromCharCode(10);
      var CR = String.fromCharCode(13);
      var TAB = String.fromCharCode(9);
      var CMD = new RegExp(BS + BS + '[a-zA-Z]{2,}');
      var MARK = 'ds-math-fix';
      // 渲染失败的文本节点按「节点 + 失败时的原文」记账：
      // 流式回答里同一个文本节点的内容会不断变长（先半截、后完整），只按节点一次性封杀，
      // 就会出现「流式期间渲染失败 → 消息结束后内容已经正确了，却永远不再尝试」——
      // 用户看到的表现就是「这条公式要等下一轮对话才突然变正常」。
      // 所以只在「文本没变」时才跳过，文本一变就重新试（失败会把新文本重新记上）。
      if (!window.__dsMathFixFailed) { window.__dsMathFixFailed = new WeakMap(); }
      var FAILED = window.__dsMathFixFailed;
      function trim(s) {
        var a = 0;
        var b = s.length;
        while (a < b) {
          var c = s.charCodeAt(a);
          if (c === 32 || c === 10 || c === 13 || c === 9) { a++; } else { break; }
        }
        while (b > a) {
          var d = s.charCodeAt(b - 1);
          if (d === 32 || d === 10 || d === 13 || d === 9) { b--; } else { break; }
        }
        return s.substring(a, b);
      }
      function flatten(s) {
        var o = '';
        for (var i = 0; i < s.length; i++) {
          var c = s.charAt(i);
          o += (c === NL || c === CR || c === TAB) ? ' ' : c;
        }
        return o;
      }
      // —— 模型写歪的公式救回来：逐层加激进，渲染成功即停（只在渲染层生效，不改原文）
      function isLetterCh(ch) {
        var cc = ch.charCodeAt(0);
        return (cc >= 65 && cc <= 90) || (cc >= 97 && cc <= 122);
      }
      // 只认完整命令：后一个字符不能是字母（否则 left 会命中 leftarrow）
      function findWordAt(s2, needle, from) {
        var at = s2.indexOf(needle, from || 0);
        while (at >= 0) {
          var after = (at + needle.length < s2.length) ? s2.charAt(at + needle.length) : '';
          if (after === '' || !isLetterCh(after)) { return at; }
          at = s2.indexOf(needle, at + 1);
        }
        return -1;
      }
      function countWordAt(s2, needle) {
        var n = 0;
        var at = 0;
        while (true) { at = findWordAt(s2, needle, at); if (at < 0) { return n; } n++; at += needle.length; }
      }
      function removeWordAt(s2, needle) {
        var out = s2;
        while (true) {
          var at = findWordAt(out, needle, 0);
          if (at < 0) { return out; }
          out = out.substring(0, at) + out.substring(at + needle.length);
        }
      }
      function closeBraceOf(s2, openAt) {
        var depth = 0;
        for (var i = openAt; i < s2.length; i++) {
          var c = s2.charAt(i);
          if (c === BS) { i++; continue; }
          if (c === '{') { depth++; } else if (c === '}') { depth--; if (depth === 0) { return i; } }
        }
        return -1;
      }
      function removeCmdArg(s2, name) {
        var out = s2;
        var at = 0;
        var key = BS + name;
        while (true) {
          var p2 = out.indexOf(key, at);
          if (p2 < 0) { return out; }
          var open = out.indexOf('{', p2 + key.length);
          if (open !== p2 + key.length) { at = p2 + key.length; continue; }
          var close = closeBraceOf(out, open);
          if (close < 0) { return out; }
          out = out.substring(0, p2) + out.substring(close + 1);
          at = p2;
        }
      }
      // 包裹的定界符：$$..$$ / $..$ / [ ] / ( )
      function stripDelims(s2) {
        var t = trim(s2);
        if (t.length > 4 && t.substring(0, 2) === '$$' && t.substring(t.length - 2) === '$$') { return trim(t.substring(2, t.length - 2)); }
        if (t.length > 4 && t.substring(0, 2) === BS + '[' && t.substring(t.length - 2) === BS + ']') { return trim(t.substring(2, t.length - 2)); }
        if (t.length > 4 && t.substring(0, 2) === BS + '(' && t.substring(t.length - 2) === BS + ')') { return trim(t.substring(2, t.length - 2)); }
        if (t.length > 2 && t.charAt(0) === '$' && t.charAt(t.length - 1) === '$') { return trim(t.substring(1, t.length - 1)); }
        return s2;
      }
      // tag / label / notag nonumber hfill noindent displaystyle：对渲染无用或容易报错
      function stripMeta(s2) {
        var out = s2;
        out = removeCmdArg(out, 'tag');
        out = removeCmdArg(out, 'label');
        out = removeWordAt(out, BS + 'notag');
        out = removeWordAt(out, BS + 'nonumber');
        out = removeWordAt(out, BS + 'hfill');
        out = removeWordAt(out, BS + 'noindent');
        out = removeWordAt(out, BS + 'displaystyle');
        return trim(out);
      }
      // left / right 数量不匹配时（模型常写漏一边）全去掉，定界符保留
      function balanceLeftRight(s2) {
        var l = countWordAt(s2, BS + 'left');
        var r = countWordAt(s2, BS + 'right');
        if (l === r) { return s2; }
        var out = removeWordAt(s2, BS + 'left');
        return removeWordAt(out, BS + 'right');
      }
      // begin{aligned} 写了开头忘了 end：补上
      function closeEnvs(s2) {
        var stack = [];
        var at = 0;
        while (true) {
          var b = s2.indexOf(BS + 'begin{', at);
          var e = s2.indexOf(BS + 'end{', at);
          var next = -1;
          var isBegin = false;
          if (b >= 0 && (e < 0 || b < e)) { next = b; isBegin = true; } else if (e >= 0) { next = e; }
          if (next < 0) { break; }
          var open = s2.indexOf('{', next);
          var close = (open >= 0) ? closeBraceOf(s2, open) : -1;
          if (close < 0) { break; }
          var env = s2.substring(open + 1, close);
          if (isBegin) { stack.push(env); } else if (stack.length > 0) { stack.pop(); }
          at = close + 1;
        }
        // 只补「恰好一个环境没闭合」的情况：多个同时缺 end 时缺口位置不唯一，
        // 猜出来的结构可能合法但含义不同，宁可让 KaTeX 报错走优雅跳过。
        if (stack.length !== 1) { return s2; }
        var out = s2;
        for (var i = stack.length - 1; i >= 0; i--) { out += BS + 'end{' + stack[i] + '}'; }
        return out;
      }
      function balanceBraces(s2) {
        var d = 0;
        var min = 0;
        var i = 0;
        while (i < s2.length) {
          var c = s2.charAt(i);
          if (c === BS) { i += 2; continue; }
          if (c === '{') { d++; } else if (c === '}') { d--; if (d < min) { min = d; } }
          i++;
        }
        // 只在「缺的是结尾的右括号」时补；中间多出过右括号说明缺口位置不唯一，
        // 补出来的可能是另一条合法但含义不同的公式 → 不猜，交给优雅跳过。
        if (min < 0) { return s2; }
        var out = s2;
        while (d > 0) { out += '}'; d--; }
        return out;
      }
      // ce{} 是 mhchem，KaTeX 没带；降级成 mathrm{} 并把箭头换成标准符号
      function convertCe(s2) {
        var out = s2;
        var at = 0;
        var key = BS + 'ce';
        while (true) {
          var p2 = out.indexOf(key, at);
          if (p2 < 0) { return out; }
          var open = p2 + key.length;
          if (out.charAt(open) !== '{') { at = open; continue; }
          var close = closeBraceOf(out, open);
          if (close < 0) { return out; }
          var inner = out.substring(open + 1, close);
          // 复杂化学式（电荷 ^2-、下标 _、嵌套花括号）转成 mathrm 会丢语义，
          // 宁可让它渲染失败走优雅跳过，也不出一张看起来对、实际变味的式子。
          if (inner.indexOf('^') >= 0 || inner.indexOf('_') >= 0 || inner.indexOf('{') >= 0) {
            at = close + 1;
            continue;
          }
          inner = inner.split('<->').join(BS + 'leftrightarrow ');
          inner = inner.split('->').join(BS + 'rightarrow ');
          inner = inner.split('=>').join(BS + 'Rightarrow ');
          inner = inner.split('<-').join(BS + 'leftarrow ');
          var rep = (inner.indexOf(BS) < 0) ? (BS + 'mathrm{' + inner + '}') : inner;
          out = out.substring(0, p2) + rep + out.substring(close + 1);
          at = p2 + rep.length;
        }
      }
      // 没有 begin{} 时裸 & 是非法字符
      function escapeAmp(s2) {
        if (s2.indexOf(BS + 'begin{') >= 0) { return s2; }
        if (s2.indexOf('&') < 0) { return s2; }
        var out = '';
        for (var i = 0; i < s2.length; i++) {
          var c = s2.charAt(i);
          if (c === BS) { out += s2.substring(i, i + 2); i++; continue; }
          out += (c === '&') ? (BS + '&') : c;
        }
        return out;
      }
      // 去掉某个命令词本身（保留它后面的定界符），用于 middle 这类只能出现在
      // left/right 内部的命令：单独出现时 KaTeX 会报错，去掉后竖线依然合法。
      function removeWordAll(s2, name) {
        var out = s2;
        var needle = BS + name;
        var guard = 0;
        while (guard < 6) {
          guard++;
          var at = out.indexOf(needle);
          if (at < 0) { break; }
          var after = out.charAt(at + needle.length);
          if (isLetterCh(after)) { break; }
          out = out.substring(0, at) + out.substring(at + needle.length);
        }
        return out;
      }
      var KNOWN_ENVS = ['aligned', 'align', 'align*', 'array', 'matrix', 'pmatrix',
        'bmatrix', 'Bmatrix', 'vmatrix', 'Vmatrix', 'cases', 'dcases', 'split',
        'gathered', 'gather', 'gather*', 'equation', 'equation*', 'subarray',
        'smallmatrix', 'CD'];
      function envIsKnown(name) {
        for (var i = 0; i < KNOWN_ENVS.length; i++) {
          if (KNOWN_ENVS[i] === name) { return true; }
        }
        return false;
      }
      // 站点/模型偶尔写出 KaTeX 不认识的块环境（渲染器扩展、自定义环境），
      // 这时把 begin/end 外壳剥掉、把内容留下来当普通公式渲染。
      function unwrapUnknownEnv(s2) {
        var bTok = BS + 'begin{';
        var at = s2.indexOf(bTok);
        if (at < 0) { return s2; }
        var nameEnd = s2.indexOf('}', at + bTok.length);
        if (nameEnd < 0) { return s2; }
        var name = trim(s2.substring(at + bTok.length, nameEnd));
        if (name.length === 0 || envIsKnown(name)) { return s2; }
        // 图表/绘图类环境剥壳只会把结构误显示成公式，直接放弃。
        var NOT_MATH_ENVS = ['mermaid', 'graphviz', 'dot', 'tikz', 'circuitikz', 'plantuml', 'svg'];
        for (var bi = 0; bi < NOT_MATH_ENVS.length; bi++) {
          if (name === NOT_MATH_ENVS[bi]) { return s2; }
        }
        if (s2.indexOf('&') >= 0) { return s2; }
        var out = s2.substring(0, at) + s2.substring(nameEnd + 1);
        var eTok = BS + 'end{' + name + '}';
        var eAt = out.indexOf(eTok);
        if (eAt >= 0) { out = out.substring(0, eAt) + out.substring(eAt + eTok.length); }
        return out;
      }
      // 站点 Markdown 会把 left 后面那个转义花括号的反斜杠吃掉：
      // 原文是 left 加反斜杠加左花括号，到了 DOM 里只剩 left 加左花括号。
      // KaTeX 于是把那个花括号当成 left 的分组，一直等一个永远不来的右花括号，
      // 报 Expected brace, got right（实机日志抓到过）。语法层面的修复，放最前面。
      function fixLeftRightBraces(s0) {
        var out = '';
        var i = 0;
        while (i < s0.length) {
          if (s0.substring(i, i + 6) === BS + 'left{') { out += BS + 'left' + BS + '{'; i += 6; continue; }
          if (s0.substring(i, i + 7) === BS + 'right}') { out += BS + 'right' + BS + '}'; i += 7; continue; }
          out += s0.charAt(i);
          i++;
        }
        return out;
      }
      function candidates(tex) {
        var list = [];
        var add = function (t) { if (t && t.length > 0 && list.indexOf(t) < 0) { list.push(t); } };
        add(tex);
        add(fixLeftRightBraces(tex));
        var s2 = stripDelims(tex);
        add(s2);
        add(fixLeftRightBraces(stripDelims(tex)));
        s2 = stripMeta(s2);
        add(s2);
        s2 = removeWordAll(s2, 'middle');
        add(s2);
        s2 = unwrapUnknownEnv(s2);
        add(s2);
        s2 = balanceLeftRight(s2);
        add(s2);
        s2 = closeEnvs(s2);
        add(s2);
        s2 = balanceBraces(s2);
        add(s2);
        s2 = convertCe(s2);
        add(s2);
        s2 = escapeAmp(s2);
        add(s2);
        s2 = trim(flatten(s2));
        add(s2);
        return list;
      }
      function blocked(node) {
        var n = node;
        var d = 0;
        while (n && d < 14) {
          var tn = n.nodeName ? String(n.nodeName).toLowerCase() : '';
          if (tn === 'math' || tn === 'pre' || tn === 'code' || tn === 'textarea' ||
              tn === 'input' || tn === 'script' || tn === 'style') { return true; }
          if (n.classList && (n.classList.contains('katex') || n.classList.contains(MARK))) { return true; }
          if (n.getAttribute && n.getAttribute('contenteditable')) { return true; }
          n = n.parentNode;
          d++;
        }
        return false;
      }
      var STRAY = [']', BS + ']', '$$', '$'];
      function stripStray(tex) {
        var s = tex;
        var changed = true;
        while (changed) {
          changed = false;
          for (var i = 0; i < STRAY.length; i++) {
            var tail = STRAY[i];
            if (s.length >= tail.length + 1 && s.substring(s.length - tail.length) === tail) {
              s = trim(s.substring(0, s.length - tail.length));
              changed = true;
            }
          }
        }
        return s;
      }
      var CJK = /[\u4e00-\u9fff\u3000-\u303f\uff00-\uffef]/;
      // 纯 ASCII 的显示公式（例如 D(t) = |PQ|^2 = (x_0 + mt - x_1)^2）里没有任何反斜杠命令，
      // 早先只认反斜杠命令的判据会漏掉它们；这里放宽：含上下标且不含中日韩文字才算数学。
      // 模型/站点兜底留下的定界符（$..$、$$..$$、[ ]、( ）本身就是数学的强信号
      function wrappedMath(v) {
        var t = trim(v);
        if (t.length > 4 && t.substring(0, 2) === '$$' && t.substring(t.length - 2) === '$$') { return true; }
        if (t.length > 4 && t.substring(0, 2) === BS + '[' && t.substring(t.length - 2) === BS + ']') { return true; }
        if (t.length > 4 && t.substring(0, 2) === BS + '(' && t.substring(t.length - 2) === BS + ')') { return true; }
        if (t.length > 2 && t.charAt(0) === '$' && t.charAt(t.length - 1) === '$') { return true; }
        return false;
      }
      // 直接写出的 Unicode 数学符号（∑ ∫ √ ≤ ∈ ∏ ∂ …）
      var UMS = '\u2211\u222b\u220f\u221a\u2264\u2265\u2260\u2248\u221e\u2202\u2207\u00b1\u00d7\u00f7\u2208\u2209\u2282\u2283\u222a\u2229\u2192\u21d2\u21d4\u2200\u2203\u2218\u2026\u00b7';
      function hasUniMath(v) {
        for (var i = 0; i < v.length; i++) { if (UMS.indexOf(v.charAt(i)) >= 0) { return true; } }
        return false;
      }
      // 纯 ASCII 方程（N(d)M'(d) - N'(d)M(d) = 0）：没有反斜杠命令、也没有上下标，
      // 但整段只由数学字符组成且含等号 + 括号/撇号时，才认为它是公式。
      var APOS = String.fromCharCode(39);
      // 去掉 {} ; # " < > | 这些偏代码/配置的字符，避免把正文里的 cfg 片段当公式。
      var ASCII_OK = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 +-*/=()[],.^_' + APOS;
      // 连续 4 个以上拉丁字母基本就是单词（timeout / config / equals），
      // 公式里的变量是单字母或缩写，靠这条把「正常英文/配置里的 ASCII 等式」挡在外面。
      function hasWordRun(v, n) {
        var run = 0;
        for (var i = 0; i < v.length; i++) {
          var c = v.charCodeAt(i);
          var isL = (c >= 65 && c <= 90) || (c >= 97 && c <= 122);
          run = isL ? (run + 1) : 0;
          if (run >= n) { return true; }
        }
        return false;
      }
      function asciiEquation(v) {
        if (v.length < 6 || v.length > 200) { return false; }
        if (v.indexOf('=') < 0) { return false; }
        if (v.indexOf('(') < 0 && v.indexOf(APOS) < 0) { return false; }
        if (hasWordRun(v, 4)) { return false; }
        for (var i = 0; i < v.length; i++) { if (ASCII_OK.indexOf(v.charAt(i)) < 0) { return false; } }
        return true;
      }
      function looksMath(v) {
        if (CMD.test(v)) { return true; }
        if (wrappedMath(v)) { return true; }
        if (CJK.test(v)) { return false; }
        if (hasUniMath(v)) { return true; }
        if (v.indexOf('^') >= 0 || v.indexOf('_') >= 0) { return /[=+\-]/.test(v); }
        return asciiEquation(v);
      }
      function render(tex, display) {
        var list = candidates(tex);
        for (var ci = 0; ci < list.length; ci++) {
          try {
            var html = kx.renderToString(list[ci], { displayMode: display, throwOnError: true, strict: 'ignore' });
            if (html) { return html; }
          } catch (e1) { }
        }
        return '';
      }
      function isStrayOnly(t) {
        if (t.length === 0 || t.length > 2) { return false; }
        for (var i = 0; i < STRAY.length; i++) {
          if (t === STRAY[i]) { return true; }
        }
        return false;
      }
      // 单独成段的噪音括号：模型常把收尾定界符写在下一段（另一个 p），
      // 只有紧邻补渲染结果的段落才敢动，正文里的方括号不碰。
      // 注意要跨过 <br>：站点的段落里公式与括号之间就夹着换行符，不跨过就永远找不到。
      function sweepSide(anchor, dir) {
        var cur = (dir < 0) ? anchor.previousSibling : anchor.nextSibling;
        var guard = 0;
        while (cur && guard < 8) {
          guard++;
          var isEl = (cur.nodeType === 1);
          if (isEl && String(cur.nodeName) === 'BR') {
            cur = (dir < 0) ? cur.previousSibling : cur.nextSibling;
            continue;
          }
          if (!isStrayOnly(trim(String(cur.textContent || '')))) { return; }
          try {
            if (cur.nodeType === 3) { cur.nodeValue = ''; } else { cur.style.display = 'none'; }
          } catch (e12) { return; }
          cur = (dir < 0) ? cur.previousSibling : cur.nextSibling;
        }
      }
      function cleanupStrays(anchor) {
        if (!anchor || !anchor.parentNode) { return; }
        sweepSide(anchor, -1);
        sweepSide(anchor, 1);
      }
      // 顺手清掉同一段落里只剩定界符的文本节点（右方括号 / 反斜杠右方括号 / 美元符）。
      // 模型的错误写法通常长这样：公式一行、下一行单独一个右方括号；渲染器放弃后
      // 两者都成了普通文字。公式补渲染完，这个孤零零的括号就是纯噪音。
      // 只清「同一段落内已经有补渲染结果」的段落，避免误删正文里的方括号。
      function paragraphOf(el) {
        var n = el;
        var d = 0;
        while (n && d < 6) {
          if (n.nodeName === 'P' || n.nodeName === 'LI') { return n; }
          n = n.parentNode;
          d++;
        }
        return null;
      }
      // 公式被站点降级成纯文本时，编号（tag{1} 的 1、或 (1)）会掉到段落里单独成行，
      // 公式补渲染之后它就是纯噪音；只在「同段落已经有补渲染结果」时才敢删。
      function isTagNumber(t) {
        if (t.length === 0 || t.length > 4) { return false; }
        var s2 = t;
        if (s2.length > 2) {
          var head = s2.charAt(0);
          var tail = s2.charAt(s2.length - 1);
          if ((head === '(' || head === '[') && (tail === ')' || tail === ']')) { s2 = s2.substring(1, s2.length - 1); }
        }
        if (s2.length === 0 || s2.length > 2) { return false; }
        for (var i = 0; i < s2.length; i++) {
          var c = s2.charCodeAt(i);
          if (c < 48 || c > 57) { return false; }
        }
        return true;
      }
      function stripInParagraph(par) {
        if (!par) { return; }
        // 先拷成静态数组：childNodes 是活的，边删 <br> 边遍历会漏掉后面的节点
        var kids = [];
        var rawKids = par.childNodes;
        for (var kk = 0; kk < rawKids.length; kk++) { kids.push(rawKids[kk]); }
        for (var k = 0; k < kids.length; k++) {
          var kid = kids[k];
          if (!kid) { continue; }
          var isText = (kid.nodeType === 3);
          var kv = trim(String(kid.textContent || ''));
          if (kv.length === 0 || kv.length > 2) { continue; }
          var isStray = false;
          for (var si = 0; si < STRAY.length; si++) {
            if (kv === STRAY[si]) { isStray = true; break; }
          }
          if (!isStray) {
            var hasFix = null;
            try { hasFix = par.querySelector ? par.querySelector('.' + MARK) : null; } catch (e13) { }
            if (hasFix && isTagNumber(kv)) { isStray = true; }
          }
          if (!isStray) { continue; }
          // 不要把已经渲染好的公式当噪音
          if (!isText && kid.querySelector && kid.querySelector('.katex')) { continue; }
          try {
            if (isText) { kid.nodeValue = ''; } else { kid.style.display = 'none'; }
          } catch (e7) { continue; }
          // 连它旁边的 <br> 一起去掉，否则会留下空行
          var before = kid.previousSibling;
          var after = kid.nextSibling;
          try {
            if (before && before.nodeName === 'BR' && before.parentNode === par) { par.removeChild(before); }
            if (after && after.nodeName === 'BR' && after.parentNode === par) { par.removeChild(after); }
          } catch (e4) { }
        }
        cleanupStrays(par);
      }
      // 站点是 React 渲染的，我们的改动之后它可能重绘把噪音节点放回来；
      // 所以每轮 scan 都按已有补渲染结果重新扫一遍段落，代价很低。
      function sweepStrays() {
        var fixes = null;
        try { fixes = document.querySelectorAll('.' + MARK); } catch (e9) { return; }
        if (!fixes) { return; }
        for (var f = 0; f < fixes.length; f++) {
          var host = fixes[f];
          stripInParagraph(host ? host.parentNode : null);
        }
      }
      // 段落里内联的 $..$ / $$..$$：站点整段放弃渲染时它们会以纯文本留在段落中间，
      // 这里只替换「明显是公式」的那些片段，其余文字原样保留。
      function inlineSegments(v) {
        var parts = [];
        var i = 0;
        var last = 0;
        var found = 0;
        while (i < v.length) {
          if (v.charAt(i) !== '$') { i++; continue; }
          var two = (v.substring(i, i + 2) === '$$');
          var w = two ? 2 : 1;
          var open = i + w;
          var close = -1;
          var probe = open;
          while (true) {
            close = v.indexOf(two ? '$$' : '$', probe);
            if (close < 0) { break; }
            var inner = v.substring(open, close);
            if (inner.length > 0 && inner.length <= 200 && (CMD.test(inner) || looksMath(inner))) { break; }
            probe = close + w;
            close = -1;
          }
          if (close < 0) { i = open; continue; }
          if (found >= 4) { break; }
          if (i > last) { parts.push({ text: v.substring(last, i) }); }
          parts.push({ tex: stripStray(trim(v.substring(open, close))), display: two });
          found++;
          last = close + w;
          i = last;
        }
        if (found === 0) { return null; }
        if (last < v.length) { parts.push({ text: v.substring(last) }); }
        return parts;
      }
      function inlineFix(node, par) {
        if (node.nodeType !== 3) { return 0; }
        var v = String(node.nodeValue || '');
        if (v.indexOf('$') < 0) { return 0; }
        var parts = inlineSegments(v);
        if (!parts) { return 0; }
        var frag = document.createDocumentFragment();
        var made = 0;
        for (var pi = 0; pi < parts.length; pi++) {
          var part = parts[pi];
          if (part.text) { frag.appendChild(document.createTextNode(part.text)); continue; }
          var html2 = render(part.tex, part.display);
          if (!html2) { frag.appendChild(document.createTextNode(part.tex)); continue; }
          var holder2 = document.createElement(part.display ? 'div' : 'span');
          holder2.className = MARK;
          holder2.innerHTML = html2;
          frag.appendChild(holder2);
          made++;
        }
        if (made === 0) { return 0; }
        try { par.replaceChild(frag, node); } catch (e5) { return 0; }
        return made;
      }
      // 行内语境：站点常把一段 Unicode 数学（A ∩ A = A）包在 <span> 里嵌进整句，
      // 这种「一条短式子夹在正文中间」不该被当成整段公式换成块级排版。
      // 站点包行内公式的元素名不固定（span / strong / div / 自造标签都出现过），所以不按标签名判断：
      // 看「段落里除了它还有没有别的文字」——有就是夹在句子中间的短式子，按行内处理。
      // 只有短（≤20 字）且不含反斜杠命令的才降级；长公式、\frac 之类仍按整段排版。
      function isInlineContext(node, tex) {
        var h = node.parentNode;
        if (!h || h.nodeType !== 1) { return false; }
        if (!tex || tex.length > 20 || tex.indexOf(BS) >= 0) { return false; }
        var para = paragraphOf(h);
        if (!para || para === h) { return false; }
        try {
          var whole = trim(String(para.textContent || ''));
          var own = trim(String(h.textContent || ''));
          return (whole.length - own.length) > 0;
        } catch (e8) { return false; }
      }
      function fix(nodes) {
        var done = 0;
        for (var i = 0; i < nodes.length; i++) {
          var node = nodes[i];
          var par = node.parentNode;
          if (!par) { continue; }
          var tex = stripStray(trim(String(node.nodeValue || '')));
          if (tex.length < 2) { continue; }
          var display = false;
          try {
            var parTxt = trim(String(par.textContent || ''));
            display = parTxt === tex || trim(stripStray(parTxt)) === tex;
          } catch (e0) { display = false; }
          // 段落里其余文字不为空 → 这是句子里的行内公式，保持行内，别换成块级排版。
          if (display && isInlineContext(node, tex)) { display = false; }
          var isCmd = CMD.test(tex);
          // 没有反斜杠命令的（纯 ASCII / 纯 Unicode 符号）公式只在「整段就是这条公式」时
          // 才敢整段替换，否则可能把一段普通文字换成公式排版。
          if ((isCmd || looksMath(tex)) && (isCmd || display)) {
            var html = render(tex, display);
            if (!html) { FAILED.set(node, tex); continue; }
            var holder = document.createElement(display ? 'div' : 'span');
            holder.className = MARK;
            holder.innerHTML = html;
            try { par.replaceChild(holder, node); } catch (e3) { continue; }
            stripInParagraph(par);
            if (display) {
              var para = paragraphOf(par);
              if (para && para !== par) { stripInParagraph(para); }
            }
            done++;
            continue;
          }
          done += inlineFix(node, par);
        }
        return done;
      }
      function scan() {
        if (!document.body) { return 0; }
        var walker = null;
        try { walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null); } catch (e4) {
          return 0;
        }
        var nodes = [];
        var t = null;
        while ((t = walker.nextNode())) {
          var v = String(t.nodeValue || '');
          if (!looksMath(v)) { continue; }
          if (blocked(t.parentNode)) { continue; }
          if (FAILED.has(t)) {
            var seen = FAILED.get(t);
            if (seen !== null && seen !== undefined && seen === stripStray(trim(v))) { continue; }
            FAILED.delete(t);
          }
          nodes.push(t);
          if (nodes.length >= 20) { break; }
        }
        if (!nodes.length) { sweepStrays(); return 0; }
        var n = fix(nodes);
        window.__dsMathFixCount = (window.__dsMathFixCount || 0) + n;
        sweepStrays();
        // 本轮被 20 个候选的上限截断 → 还有积压，主动续排一轮（不加定时器，避免空转）。
        if (nodes.length >= 20) { setTimeout(function () { try { scan(); } catch (e7) { } }, 300); }
        return n;
      }
      var first = scan();
      if (!window.__dsMathFixObserver && document.body) {
        try {
          window.__dsMathFixObserver = new MutationObserver(function () {
            if (window.__dsMathFixTimer) { return; }
            window.__dsMathFixTimer = setTimeout(function () {
              window.__dsMathFixTimer = 0;
              try { scan(); } catch (e5) { }
            }, 900);
          });
          window.__dsMathFixObserver.observe(document.body,
            { childList: true, subtree: true, characterData: true });
        } catch (e6) { }
      }
      // 每个文档一条：注入成功即带 installed，便于在设备日志里确认脚本版本与自检；
      // 真修了内容才追加修复数，避免 fixed=0 时信息被稳态过滤掉。
      return VER + ' self=' + selfTest + ' installed' + ((first > 0) ? (' fixed=' + first) : '');
    } catch (e) {
      return 'err ' + e;
    }
  })();`;
}

export function buildScrollFixScript(): string {
  return `(function() {
  var id = 'ds-scroll-fix';
  if (document.getElementById(id)) {
    return 'ok';
  }
  var st = document.createElement('style');
  st.id = id;
  st.textContent = 'pre,table,.katex-display{-webkit-overflow-scrolling:touch;overscroll-behavior-x:contain}'
    // overflow-y 必须显式 hidden：只写 overflow-x:auto 时另一轴的 visible 会按规范算成 auto，
    // 于是本来完整显示的公式也能上下滚几像素、右侧还冒出一条滚动条（实机现象）。
    + 'pre,.katex-display{overflow-x:auto;overflow-y:hidden}'
    // 表格样式只作用于 table.ds-tbl-fixed —— 也就是「确实显示异常」被 JS 打过标记的表
    //（超宽溢出或单元格内容溢出）。正常的表完全保持站点原样，不改列宽、不改行线、不改间距。
    + 'table.ds-tbl-fixed{border-collapse:collapse;font-variant-numeric:tabular-nums;table-layout:auto !important;width:auto !important;max-width:none !important}'
    + 'table.ds-tbl-fixed th,table.ds-tbl-fixed td{padding:8px 10px;vertical-align:top;line-height:1.65;text-align:left;white-space:normal;overflow-wrap:anywhere}'
    + 'table.ds-tbl-fixed th{font-weight:600}'
    + 'table.ds-tbl-fixed tr{border-bottom:1px solid rgba(127,127,127,0.35)}'
    + 'table.ds-tbl-fixed thead tr,table.ds-tbl-fixed tr:first-child{border-top:1px solid rgba(127,127,127,0.35)}'
    + 'table.ds-tbl-fixed th{border-bottom:1px solid rgba(127,127,127,0.55)}'
    + 'table.ds-tbl-fixed .katex-display{margin:0.2em 0}'
    // 异常表里的行内公式必须不可断行：white-space:normal 时浏览器会认为它能在任意位置折行，
    // 于是把列宽算得比公式实际宽度还窄，绘制时公式就压到右边那一列的文字上（实机现象）。
    + 'table.ds-tbl-fixed td .katex,table.ds-tbl-fixed th .katex{white-space:nowrap !important}'
    // 补渲染出来的公式块：继承段落 line-height 会把分数、根号、上下标压扁并相互重叠，
    // 所以强制 line-height:normal；上下留白让行间公式和正文分开；padding 防止
    // overflow-y:hidden 裁掉根号/下标的伸出行。
    + 'div.ds-math-fix{display:block;text-align:center;margin:0.8em 0;padding:0.18em 0}'
    + 'span.ds-math-fix{display:inline-block}'
    + '.ds-math-fix{overflow-x:auto;overflow-y:hidden;-webkit-overflow-scrolling:touch}'
    + '.ds-math-fix,.ds-math-fix .katex{line-height:normal !important}';
  (document.head || document.documentElement).appendChild(st);
  // 站点自己的表格样式里带了 width/min-width 的 !important，样式表压不过它，
  // 于是列宽被算窄、行内公式（KaTeX 不可断行）溢到右边那一列、与文字叠在一起。
  // 用**内联 !important** 才能稳胜：列宽按内容撑开、表格不再被拉伸，超宽交给外层横滑。
  var PROPS = [
    ['table-layout', 'auto'],
    ['width', 'auto'],
    ['min-width', '0'],
    ['max-width', 'none']
  ];
  // 用户要求：只优化「显示异常」的表格，正常表格必须保持站点原样。
  // 异常判定：①表格比所在容器还宽（横向溢出）②有关键单元格的内容比单元格宽（公式被裁或压列）。
  // 已打过标记的表不再判定：修好之后它看起来就「正常」了，若重新判定会放弃后续兜底。
  var FIX_CLS = 'ds-tbl-fixed';
  function tableIsBroken(t) {
    if (t.classList && t.classList.contains(FIX_CLS)) { return true; }
    var host = t.parentElement;
    var cw = (host && host.clientWidth) || 0;
    if (cw > 0 && t.scrollWidth > cw + 2) { return true; }
    var cs0 = t.querySelectorAll('td,th');
    for (var ci0 = 0; ci0 < cs0.length; ci0++) {
      if (cs0[ci0].scrollWidth > cs0[ci0].clientWidth + 2) { return true; }
    }
    return false;
  }
  function stampTable(t) {
    if (!tableIsBroken(t)) { return; }
    if (t.classList) { t.classList.add(FIX_CLS); }
    for (var pi = 0; pi < PROPS.length; pi++) {
      t.style.setProperty(PROPS[pi][0], PROPS[pi][1], 'important');
    }
    var ks = t.querySelectorAll('.katex');
    for (var ki = 0; ki < ks.length; ki++) {
      ks[ki].style.setProperty('white-space', 'nowrap', 'important');
    }
    // 列宽兜底：站点 CSS 会把列宽算得比不可断行的行内公式还窄，公式因此压到右边那一列上。
    // 只能按内容实测宽度写 min-width（window 变化时由 resize 监听重算，见 stampAll 调用处）。
    var cs2 = t.querySelectorAll('td,th');
    for (var ci = 0; ci < cs2.length; ci++) {
      var cell = cs2[ci];
      if (cell.scrollWidth > cell.clientWidth + 2) {
        cell.style.setProperty('min-width', cell.scrollWidth + 'px', 'important');
        // 打标记：只清理本脚本写过的宽度，绝不碰站点自己的内联样式。
        cell.setAttribute('data-ds-mw', '1');
      }
    }
  }
  // 上一轮按旧内容/旧窗口算出来的像素宽度必须先清掉再重算，
  // 否则内容变短或窗口变窄后，列会一直被旧宽度撑着（用户反馈过「窗口一变就不对」）。
  function clearStamp() {
    var cc = document.querySelectorAll('[data-ds-mw]');
    for (var ci0 = 0; ci0 < cc.length; ci0++) {
      cc[ci0].style.removeProperty('min-width');
      cc[ci0].removeAttribute('data-ds-mw');
    }
  }
  function stampAll() {
    clearStamp();
    var ts = document.querySelectorAll('table');
    for (var ti = 0; ti < ts.length; ti++) { stampTable(ts[ti]); }
  }
  stampAll();
  // 逐格 min-width 是按当时的像素算出来的：窗口变化 / 分屏 / 旋转之后必须重算一遍，
  // 否则列宽会停留在旧尺寸（用户反馈过「窗口一变就不对」）。
  if (!window.__dsTableStampResize) {
    window.__dsTableStampResize = 1;
    var rt = 0;
    window.addEventListener('resize', function () {
      if (rt) { clearTimeout(rt); }
      rt = setTimeout(function () {
        rt = 0;
        try { window.__dsTableStampAll(); } catch (eR) { }
      }, 250);
    });
  }
  window.__dsTableStampAll = stampAll;
  if (!window.__dsTableStampObs) {
    window.__dsTableStampObs = new MutationObserver(function () {
      if (window.__dsTableStampQueued) { return; }
      window.__dsTableStampQueued = true;
      setTimeout(function () {
        window.__dsTableStampQueued = false;
        stampAll();
      }, 300);
    });
    window.__dsTableStampObs.observe(document.body, { childList: true, subtree: true });
  }
  return 'ok';
})();`;
}

/** document-start 注入：只读嗅探，把模型原始 Markdown 重建后存到 window.__dsMd。 */
export function buildSniffScript(): string {
  return `(function(){
  if (window.__dsSniffInstalled) { return; }
  window.__dsSniffInstalled = 1;
  window.__dsXhrMap = {};
  window.__dsMd = '';
  window.__dsMdVersion = 0;
  function rebuild() {
    var keys = Object.keys(window.__dsXhrMap || {});
    var best = '';
    for (var i = 0; i < keys.length; i++) {
      if (keys[i].indexOf('/chat/completion') < 0) { continue; }
      var v = String(window.__dsXhrMap[keys[i]] || '');
      if (v.length > best.length) { best = v; }
    }
    if (!best) { return; }
    var md = '';
    var lines = best.split(String.fromCharCode(10));
    for (var j = 0; j < lines.length; j++) {
      var ln = lines[j];
      if (ln.indexOf('data: ') !== 0) { continue; }
      var o = null;
      try { o = JSON.parse(ln.slice(6)); } catch (e0) { continue; }
      if (o && typeof o.v === 'string' && typeof o.p === 'string' && o.p.indexOf('/content') >= 0) {
        md = (o.o === 'SET') ? String(o.v) : (md + String(o.v));
      } else if (o && typeof o.v === 'string' && typeof o.p === 'undefined') {
        md = md + o.v;
      } else if (o && o.v && o.v.response && o.v.response.content) {
        md = String(o.v.response.content);
      }
    }
    try {
      var k1 = best.indexOf('\"response_message_id\":');
      if (k1 >= 0) {
        var s1 = best.substring(k1 + 22, k1 + 44);
        var num1 = '';
        for (var q1 = 0; q1 < s1.length; q1++) {
          var ch1 = s1.charAt(q1);
          if (ch1 >= '0' && ch1 <= '9') { num1 += ch1; } else if (num1.length > 0) { break; }
        }
        if (num1.length > 0) { window.__dsStreamMsgId = num1; }
      }
    } catch (eS) { }
    if (md.length > 0 && md !== window.__dsMd) {
      window.__dsMd = md;
      window.__dsMdVersion = (window.__dsMdVersion || 0) + 1;
      if (window.__dsRepairTables && best.indexOf('FINISHED') >= 0) {
        setTimeout(function () { try { window.__dsRepairTables(); } catch (e2) { } }, 0);
      }
    }
  }
  function parseHistory(txt) {
    var o = null;
    try { o = JSON.parse(txt); } catch (e) { window.__dsHistDiag = 'badjson'; return; }
    var bd = o && o.data && o.data.biz_data;
    var keys = bd ? Object.keys(bd) : [];
    var m0 = bd && bd.chat_messages;
    window.__dsHistDiag = 'bk=' + keys.join(',') + ';cm=' + (m0 ? m0.length : -1);
    if (m0 && m0.length > 0) {
      var f = m0[0];
      window.__dsHistDiag += ';fk=' + (f ? Object.keys(f).join(',') : 'null');
      if (f && typeof f.content === 'string') { window.__dsHistDiag += ';ct=string'; }
      else if (f && f.content) { window.__dsHistDiag += ';ct=' + Object.keys(f.content).join('+'); }
    }
    var msgs = m0;
    if (!msgs || !msgs.length) { return; }
    if (!window.__dsHist) { window.__dsHist = []; }
    for (var i = 0; i < msgs.length; i++) {
      var m = msgs[i];
      if (!m) { continue; }
      var md = '';
      if (typeof m.content === 'string' && m.content) { md = m.content; }
      else if (m.content && typeof m.content.text === 'string') { md = m.content.text; }
      if (!md && m.fragments && m.fragments.length) {
        for (var fi = 0; fi < m.fragments.length; fi++) {
          var fr = m.fragments[fi];
          if (!fr) { continue; }
          var ty = String(fr.type || '');
          if (ty.indexOf('THINK') >= 0 || ty.indexOf('REQUEST') >= 0) { continue; }
          if (typeof fr.content === 'string') { md += fr.content; }
        }
      }
      if (!md) { continue; }
      var id = String(m.message_id || m.id || '');
      var hit = false;
      for (var j = 0; j < window.__dsHist.length; j++) {
        if (window.__dsHist[j].id === id) { window.__dsHist[j].md = md; hit = true; break; }
      }
      if (!hit && window.__dsHist.length < 80) { window.__dsHist.push({ id: id, md: md }); }
    }
    window.__dsHistCount = window.__dsHist.length;
  }
  window.__dsParseHist = parseHistory;
  function store(u, txt) {
    var full = String(u || '');
    var k = full.indexOf('history_messages') >= 0 ? full.slice(0, 240) : full.split('?')[0].slice(0, 160);
    if (!k) { return; }
    var prev = window.__dsXhrMap[k];
    if (!prev || txt.length > prev.length) {
      window.__dsXhrMap[k] = txt.length > 400000 ? txt.slice(txt.length - 400000) : txt;
      if (k.indexOf('history_messages') >= 0) {
        if (!window.__dsHistBest || txt.length > window.__dsHistBest.length) {
          window.__dsHistBest = String(txt).slice(0, 4000);
        }
        parseHistory(txt);
      }
      rebuild();
    }
  }
  try {
    var OX = window.XMLHttpRequest;
    if (OX && OX.prototype) {
      var oOpen = OX.prototype.open;
      var oSend = OX.prototype.send;
      OX.prototype.open = function(m, u) {
        var url = String(u);
        try {
          if (window.__dsStripCache === 1 && url.indexOf('/chat/history_messages') >= 0 && url.indexOf('cache_version') >= 0) {
            var qm = url.indexOf('?');
            var base = url.slice(0, qm);
            var parts = url.slice(qm + 1).split('&');
            var keep = [];
            for (var pi = 0; pi < parts.length; pi++) {
              if (parts[pi].indexOf('cache_version') === 0) { continue; }
              if (parts[pi].indexOf('cache_reset_at') === 0) { continue; }
              keep.push(parts[pi]);
            }
            url = base + '?' + keep.join('&');
          }
        } catch (e6) { }
        this.__dsUrl = url;
        this.__dsHdrs = {};
        var args2 = [];
        for (var ai = 0; ai < arguments.length; ai++) { args2.push(ai === 1 ? url : arguments[ai]); }
        return oOpen.apply(this, args2);
      };
      try {
        var oSetH = OX.prototype.setRequestHeader;
        if (oSetH) {
          OX.prototype.setRequestHeader = function (k, v) {
            try {
              if (!this.__dsHdrs) { this.__dsHdrs = {}; }
              this.__dsHdrs[String(k)] = String(v);
              if (String(this.__dsUrl || '').indexOf('/chat/history_messages') >= 0) {
                window.__dsHistHdrs = this.__dsHdrs;
              }
            } catch (e7) { }
            return oSetH.apply(this, arguments);
          };
        }
      } catch (e8) { }
      OX.prototype.send = function() {
        try {
          var self = this;
          var last = 0;
          self.addEventListener('progress', function() {
            try {
              var rt = String(self.responseType || '');
              var t = (rt === '' || rt === 'text') ? String(self.responseText || '') : '';
              if (t.length > last) { last = t.length; store(self.__dsUrl, t); }
            } catch (e9) { }
          });
          self.addEventListener('load', function() {
            try {
              var rt2 = String(self.responseType || '');
              if (rt2 === '' || rt2 === 'text') { store(self.__dsUrl, String(self.responseText || '')); }
            } catch (e10) { }
          });
        } catch (e8) { }
        return oSend.apply(this, arguments);
      };
    }
  } catch (e7) { }
})();`;
}

export function buildHistoryFetchScript(): string {
  return `(function(){
  var parts = String(location.pathname || '').split('/');
  var sid = '';
  for (var pi2 = 0; pi2 < parts.length; pi2++) {
    if (parts[pi2] === 's' && pi2 + 1 < parts.length) { sid = parts[pi2 + 1]; }
  }
  if (!sid) { return 'no-sid'; }
  var url = '/api/v0/chat/history_messages?chat_session_id=' + encodeURIComponent(sid);
  var hdr = {};
  try {
    var src = window.__dsHistHdrs || {};
    // 只复用「认证类 + 站点自定义 + 协商类」头，且只发往同源的 history 接口；
    // 不取 cookie/referer/origin，不打印、不持久化。
    for (var hk2 in src) {
      if (!Object.prototype.hasOwnProperty.call(src, hk2)) { continue; }
      var lk = String(hk2).toLowerCase();
      if (lk === 'authorization' || lk === 'accept' || lk === 'accept-language' ||
          lk === 'content-type' || lk.indexOf('x-') === 0) {
        hdr[hk2] = src[hk2];
      }
    }
  } catch (e9) { }
  if (!hdr['accept']) { hdr['accept'] = '*/*'; }
  try {
    fetch(url, { credentials: 'include', cache: 'no-store', headers: hdr })
      .then(function (r) { return r.text(); })
      .then(function (t) {
        try { if (window.__dsParseHist) { window.__dsParseHist(t); } } catch (e) { }
        window.__dsHistVersion = (window.__dsHistVersion || 0) + 1;
        window.__dsHistNet = 'ok:' + String(t).length + ':' + String(t).slice(0, 70);
      })
      .catch(function (e2) { window.__dsHistNet = 'err:' + String(e2).slice(0, 40); });
  } catch (e3) { return 'throw'; }
  return 'fetching:' + sid;
})();`;
}

/** 表格修复：仅对「单元格里残留未渲染 LaTeX」的表格，用原始 Markdown 重建并替换该表。 */
export function buildTableRepairScript(): string {
  return `(function(){
  if (!window.katex) { return 'wait-katex'; }
  if (window.__dsRepairInstalled) { return window.__dsRepairTables(); }
  window.__dsRepairInstalled = 1;
  function runRepair() {
  var md = String(window.__dsMd || '');
  var BS = String.fromCharCode(92);
  var BT = String.fromCharCode(96);
  var CMD = new RegExp(BS + BS + '[a-zA-Z]{2,}');
  function splitCells(line) {
    var out = []; var cur = ''; var i = 0; var n = line.length;
    var st = 0; var code = false;
    while (i < n) {
      var ch = line.charAt(i);
      var nx = line.charAt(i + 1);
      if (code) {
        cur += ch;
        if (ch === BT) { code = false; }
        i++; continue;
      }
      if (ch === BT && st === 0) { code = true; cur += ch; i++; continue; }
      if (ch === BS) {
        if (st === 0 && nx === '(') { st = 3; cur += ch + nx; i += 2; continue; }
        if (st === 0 && nx === '[') { st = 4; cur += ch + nx; i += 2; continue; }
        if (st === 3 && nx === ')') { st = 0; cur += ch + nx; i += 2; continue; }
        if (st === 4 && nx === ']') { st = 0; cur += ch + nx; i += 2; continue; }
        cur += ch + nx; i += 2; continue;
      }
      if (st === 0 && ch === '$') {
        if (nx === '$') { st = 2; cur += ch + nx; i += 2; continue; }
        st = 1; cur += ch; i++; continue;
      }
      if (st === 1 && ch === '$') { st = 0; cur += ch; i++; continue; }
      if (st === 2 && ch === '$' && nx === '$') { st = 0; cur += ch + nx; i += 2; continue; }
      if (st === 0 && ch === '|') { out.push(cur); cur = ''; i++; continue; }
      cur += ch; i++;
    }
    out.push(cur);
    return out;
  }
  function trimRow(cells) {
    var a = cells.slice(0);
    if (a.length > 0 && String(a[0]).trim() === '') { a.shift(); }
    if (a.length > 0 && String(a[a.length - 1]).trim() === '') { a.pop(); }
    return a;
  }
  function isSep(line) {
    var s = String(line).trim();
    if (s.indexOf('-') < 0 || s.indexOf('|') < 0) { return false; }
    for (var i = 0; i < s.length; i++) {
      var c = s.charAt(i);
      if (c === '|' || c === '-' || c === ':' || c === ' ') { continue; }
      return false;
    }
    return true;
  }
  function parseTables(text) {
    var rows = text.split(String.fromCharCode(10));
    var out = []; var i = 0;
    while (i < rows.length - 1) {
      var a = rows[i]; var b = rows[i + 1];
      if (a.indexOf('|') < 0 || !isSep(b)) { i++; continue; }
      var head = trimRow(splitCells(a));
      var body = []; var j = i + 2;
      while (j < rows.length && rows[j].indexOf('|') >= 0 && String(rows[j]).trim() !== '') {
        body.push(trimRow(splitCells(rows[j]))); j++;
      }
      if (head.length > 0) { out.push({ head: head, body: body }); }
      i = j;
    }
    return out;
  }
  function esc(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }
  function mathHtml(tex, disp) {
    try {
      return window.katex.renderToString(tex, { displayMode: !!disp, throwOnError: true, strict: 'ignore' });
    } catch (e) {
      return esc(tex);
    }
  }
  function mdText(s) {
    var out = ''; var i = 0; var n = s.length;
    while (i < n) {
      var ch = s.charAt(i);
      if (ch === BT) {
        var k0 = s.indexOf(BT, i + 1);
        if (k0 > i) { out += '<code>' + esc(s.slice(i + 1, k0)) + '</code>'; i = k0 + 1; continue; }
      }
      if (ch === '*' && s.charAt(i + 1) === '*') {
        var k1 = s.indexOf('**', i + 2);
        if (k1 > i + 1) { out += '<strong>' + mdText(s.slice(i + 2, k1)) + '</strong>'; i = k1 + 2; continue; }
      }
      out += esc(ch); i++;
    }
    return out;
  }
  function renderInline(text) {
    var s = String(text); var out = ''; var i = 0; var n = s.length; var buf = '';
    function flush() { if (buf.length) { out += mdText(buf); buf = ''; } }
    while (i < n) {
      var ch = s.charAt(i); var nx = s.charAt(i + 1);
      if (ch === BS && (nx === '(' || nx === '[')) {
        var close = (nx === '(') ? BS + ')' : BS + ']';
        var k = s.indexOf(close, i + 2);
        if (k > 0) { flush(); out += mathHtml(s.slice(i + 2, k), nx === '['); i = k + 2; continue; }
      }
      if (ch === '$') {
        var disp = (nx === '$');
        var open = disp ? 2 : 1;
        var j = i + open;
        var end = -1;
        while (j < n) {
          if (s.charAt(j) === BS) { j += 2; continue; }
          if (disp) { if (s.charAt(j) === '$' && s.charAt(j + 1) === '$') { end = j; break; } }
          else if (s.charAt(j) === '$') { end = j; break; }
          j++;
        }
        if (end > i) { flush(); out += mathHtml(s.slice(i + open, end), disp); i = end + open; continue; }
      }
      buf += ch; i++;
    }
    flush();
    return out.split(String.fromCharCode(10)).join('<br>');
  }
  function buildTable(t) {
    var tb = document.createElement('table');
    tb.className = 'ds-md-repaired ds-tbl-fixed';
    var thead = document.createElement('thead');
    var trh = document.createElement('tr');
    for (var i = 0; i < t.head.length; i++) {
      var th = document.createElement('th');
      th.innerHTML = renderInline(t.head[i]);
      trh.appendChild(th);
    }
    thead.appendChild(trh);
    tb.appendChild(thead);
    var tbody = document.createElement('tbody');
    for (var r = 0; r < t.body.length; r++) {
      var tr = document.createElement('tr');
      var row = t.body[r];
      for (var c = 0; c < t.head.length; c++) {
        var td = document.createElement('td');
        td.innerHTML = renderInline(c < row.length ? row[c] : '');
        tr.appendChild(td);
      }
      tbody.appendChild(tr);
    }
    tb.appendChild(tbody);
    return tb;
  }
  // —— 原文证据比对 ——
  // 单元格的「可见文本」：一片公式在页面里是两份（视觉层 + 无障碍 MathML），
  // 比对时必须剔掉 MathML，否则任何公式格都对不上。
  function visibleText(el) {
    var c = el.cloneNode(true);
    var mml = c.querySelectorAll ? c.querySelectorAll('.katex-mathml') : [];
    for (var i = 0; i < mml.length; i++) {
      if (mml[i].parentNode) { mml[i].parentNode.removeChild(mml[i]); }
    }
    return String(c.textContent || '');
  }
  // 比对用的归一化：只做 NFKC 与空白折叠，**不删**等号/括号等符号 ——
  // 删符号会把「内容真的丢了」也一起抹平。
  function normCmp(s) {
    var v = String(s || '');
    try { if (v.normalize) { v = v.normalize('NFKC'); } } catch (e) { }
    var out = '';
    var prevSpace = false;
    for (var i = 0; i < v.length; i++) {
      var code = v.charCodeAt(i);
      var sp = (code <= 32) || code === 160 || code === 8199 || code === 8239 || code === 12288;
      if (sp) {
        if (!prevSpace) { out += ' '; prevSpace = true; }
      } else {
        out += v.charAt(i); prevSpace = false;
      }
    }
    var a0 = 0, b0 = out.length;
    while (a0 < b0 && out.charAt(a0) === ' ') { a0++; }
    while (b0 > a0 && out.charAt(b0 - 1) === ' ') { b0--; }
    return out.substring(a0, b0);
  }
  function brokenCell(c) {
    var txt = String(c.textContent || '');
    if (txt.indexOf(BS) < 0) { return false; }
    if (c.querySelector('.katex')) { return false; }
    return new RegExp(BS + BS + '[a-zA-Z]{2,}').test(txt);
  }
  // 单元格是否像「被 | 切开的残片」：站点先按 | 切列再逐格渲染，绝对值/行列式里的竖线
  // 会把一条公式劈进两个格子，于是出现 (dV= 、,du,dv,dw) 这种片段 —— 它们本身没有反斜杠
  // 命令、甚至有一半还能正常渲染，brokenCell 抓不到，必须按形状判定。
  function fragmentCell(c) {
    var t2 = normCmp(visibleText(c));
    if (t2 === '' || t2.length > 40) { return false; }
    var open = 0;
    var close = 0;
    for (var fi = 0; fi < t2.length; fi++) {
      var ch2 = t2.charAt(fi);
      if (ch2 === '(') { open++; } else if (ch2 === ')') { close++; }
    }
    if (open !== close) { return true; }
    var first2 = t2.charAt(0);
    if (first2 === ',' || first2 === ';') { return true; }
    if (t2.charAt(t2.length - 1) === '=') { return true; }
    return false;
  }
  // 只有「等号开头」这一条额外形状：站点把 x2+y2+z2=rho2 吞成 =rho2 时只剩尾巴，
  // 这种形状**只用来决定要不要去查原文**，真正替换必须靠原文比对证明（damageProof）。
  function eqLeadingCell(c) {
    // 用可见文本判定：站点把 x2+y2+z2=rho2 吞成 =rho2 时，这一格仍是渲染好的公式，
    // 只有剔除 MathML 之后的可见文本才看得到那个开头的等号。
    var t3 = normCmp(visibleText(c));
    if (t3 === '' || t3.length > 40) { return false; }
    return t3.charAt(0) === '=';
  }
  // 疑似异常：只决定「要不要为这张表去找原始 Markdown」，不等于要替换。
  function suspiciousTable(tb) {
    var cells = tb.querySelectorAll('td,th');
    for (var i = 0; i < cells.length; i++) {
      if (brokenCell(cells[i]) || fragmentCell(cells[i]) || eqLeadingCell(cells[i])) { return true; }
    }
    return false;
  }
  function normText(s) {
    return String(s || '').replace(/\s+/g, ' ').trim();
  }
  var cands = [];
  var candId = [];
  // 解析缓存：runRepair 每 1.5s 跑一次，__dsHist 里的 Markdown 是稳定的，
  // 按 (messageId + hist 版本) 缓存 parseTables 结果，只有版本变化才重新切分。
  var pcache = window.__dsParseCache || (window.__dsParseCache = {});
  var pver = String(window.__dsHistVersion || 0);
  function histTablesOf(entry) {
    var key = String(entry.id || '') + '#' + pver;
    var hit = pcache[key];
    if (hit) { return hit; }
    var t = parseTables(String(entry.md || ''));
    pcache[key] = t;
    var nk = 0;
    var ks = Object.keys(pcache);
    for (var i = 0; i < ks.length; i++) {
      nk++;
      if (nk > 60) { delete pcache[ks[i]]; }
    }
    return t;
  }
  var streamTables = parseTables(md);
  for (var s0 = 0; s0 < streamTables.length; s0++) { cands.push(streamTables[s0]); candId.push(String(window.__dsStreamMsgId || '#LAST')); }
  var hist = window.__dsHist || [];
  for (var h0 = 0; h0 < hist.length; h0++) {
    var ht = histTablesOf(hist[h0]);
    for (var q0 = 0; q0 < ht.length; q0++) { cands.push(ht[q0]); candId.push(String(hist[h0].id || '')); }
  }
  var domTables = document.querySelectorAll('table');
  if (domTables.length === 0) { return 'no-dom-table'; }
  function normAll(s) {
    var src = String(s || '');
    var out = '';
    for (var i = 0; i < src.length; i++) {
      var ch = src.charAt(i);
      if (ch.charCodeAt(0) > 32) { out += ch; }
    }
    return out.toLowerCase();
  }
  function plainCells(t) {
    var out = [];
    var all = [];
    var i = 0;
    for (i = 0; i < t.head.length; i++) { all.push(t.head[i]); }
    for (i = 0; i < t.body.length; i++) {
      for (var j = 0; j < t.body[i].length; j++) { all.push(t.body[i][j]); }
    }
    for (i = 0; i < all.length && out.length < 14; i++) {
      var s = String(all[i] || '');
      if (s.indexOf(BS) >= 0) { continue; }
      var n = normAll(s);
      if (n.length < 3) { continue; }
      if (out.indexOf(n) < 0) { out.push(n); }
    }
    return out;
  }
  var candCells = [];
  for (var c0 = 0; c0 < cands.length; c0++) { candCells.push(plainCells(cands[c0])); }
  function itemKeyOf(el) {
    var p = el, lv = 0;
    while (p && lv < 8) {
      var k = null;
      try { k = p.getAttribute ? p.getAttribute('data-virtual-list-item-key') : null; } catch (e) { }
      if (k !== null && k !== '') { return String(k); }
      p = p.parentElement; lv++;
    }
    return '';
  }
  function lastMsgEl() {
    var all = document.querySelectorAll('.ds-message');
    return all.length > 0 ? all[all.length - 1] : null;
  }
  function fpOf(el, mid) {
    var head = '';
    try {
      var th = el.querySelector('th');
      head = th ? String(th.textContent || '') : '';
    } catch (e0) { }
    var s = '';
    for (var i = 0; i < head.length; i++) {
      var ch = head.charAt(i);
      if (ch.charCodeAt(0) > 32) { s += ch; }
    }
    return String(mid) + '|' + s.slice(0, 24);
  }
  // 用原文生成的参考表格逐格证明「站点确实丢了内容」。返回证据类型，'' 表示证明不了。
  //   tail : 站点只剩原文的末尾片段（例如原文 x2+y2+z2=rho2，站点只剩 =rho2）
  //   raw  : 站点留着未渲染的 LaTeX，而原文这边渲染成功
  //   frag : 站点以逗号/分号开头（被竖线切开的残片）
  //   cut  : 站点以等号结尾（后半截被切走）
  // 只留「有意义的字符」：字母、数字、CJK。用来做顺序包含判断，
  // 这样公式被渲染成 KaTeX 之后（\frac{1}{h'(y)} → h′(y)）也能和原文对上。
  function lettersOf(el) {
    var t = normCmp(visibleText(el));
    var o = '';
    for (var i = 0; i < t.length; i++) {
      var ch = t.charAt(i);
      var cc = t.charCodeAt(i);
      if ((cc >= 48 && cc <= 57) || (cc >= 65 && cc <= 90) || (cc >= 97 && cc <= 122)) { o += ch; }
      else if (cc >= 0x4e00 && cc <= 0x9fff) { o += ch; }
    }
    return o;
  }
  // 结构证明：站点把「一列」按竖线劈成了多列。
  // 判据 = 同一行里 DOM 的单元格数 > 参考表该行单元格数（忠实渲染不可能变多），
  // 且 DOM 这些碎片的字母序列能按顺序在参考行里逐段找到（证明碎片确实来自这一行，
  // 不是别的表的巧合）。两条同时成立才算证明成立。
  function splitProof(domTb, refTb) {
    var dr = domTb.querySelectorAll('tr');
    var rr = refTb.querySelectorAll('tr');
    if (dr.length === 0 || rr.length !== dr.length) { return ''; }
    for (var q = 0; q < dr.length; q++) {
      var dcs = dr[q].querySelectorAll('td,th');
      var rcs = rr[q].querySelectorAll('td,th');
      if (dcs.length <= rcs.length) { continue; }
      var refAll = lettersOf(rr[q]);
      if (refAll === '') { continue; }
      var cur = 0;
      var okAll = true;
      var hit = 0;
      for (var w = 0; w < dcs.length; w++) {
        var seg = lettersOf(dcs[w]);
        if (seg === '') { continue; }
        var at = refAll.indexOf(seg, cur);
        if (at < 0) { okAll = false; break; }
        cur = at + seg.length;
        hit++;
      }
      if (okAll && hit >= 2) { return 'split'; }
    }
    return '';
  }
  function damageProof(domTb, refTb) {
    var sp = splitProof(domTb, refTb);
    if (sp !== '') { return sp; }
    var dc = domTb.querySelectorAll('td,th');
    var rc = refTb.querySelectorAll('td,th');
    var n = dc.length < rc.length ? dc.length : rc.length;
    if (n === 0) { return ''; }

    for (var i = 0; i < n; i++) {
      var a = normCmp(visibleText(dc[i]));
      var e = normCmp(visibleText(rc[i]));
      if (a === e || a === '') { continue; }

      if (e.length > a.length && e.lastIndexOf(a) === e.length - a.length) { return 'tail'; }
      if (dc[i].querySelector('.katex') === null && rc[i].querySelector('.katex') !== null) {
        if (String(dc[i].textContent || '').indexOf(BS) >= 0) { return 'raw'; }
      }
      var f = a.charAt(0);
      if ((f === ',' || f === ';') && e.charAt(0) !== f) { return 'frag'; }
      if (a.charAt(a.length - 1) === '=' && e.charAt(a.length - 1) !== '=') { return 'cut'; }
    }
    return '';
  }
  // 已经证明不了的表不必每 1.5s 重算一遍参考表格：按 指纹+版本 记下结论。
  var rejected = 0;
  function rejKeyOf(fp) {
    return fp + '|' + String(window.__dsMdVersion || 0) + '|' + String(window.__dsHistVersion || 0);
  }
  var used = [];
  var fixed = 0;
  var need = [];
  for (var d = 0; d < domTables.length && fixed < 6; d++) {
    var dt = domTables[d];
    if (dt.className && String(dt.className).indexOf('ds-md-repaired') >= 0) { continue; }
    if (!suspiciousTable(dt)) { continue; }
    var mid = itemKeyOf(dt);
    var domText = normAll(dt.textContent);
    var bestScore = 0;
    var bestIdx = -1;
    var tie = false;
    if (mid === '') {
      // 没有虚拟列表键（个别布局/流式早期）：只有落在「最后一条消息」里的表才用当前流式原文，
      // 其余一律跳过 —— 不跨消息、不跨会话猜。
      var lm = lastMsgEl();
      if (lm && lm.contains(dt)) { mid = '#LAST'; }
    }
    if (mid === '') { continue; }
    var hasOwn = false;
    for (var z0 = 0; z0 < candId.length; z0++) { if (candId[z0] === mid) { hasOwn = true; break; } }
    if (!hasOwn) { need.push(fpOf(dt, mid)); continue; }
    for (var m = 0; m < cands.length; m++) {
      if (used.indexOf(m) >= 0) { continue; }
      if (candId[m] !== mid) { continue; }
      var sc = 0;
      var cc = candCells[m];
      for (var x = 0; x < cc.length; x++) {
        if (domText.indexOf(cc[x]) >= 0) { sc++; }
      }
      var firstTh = dt.querySelector('th');
      if (firstTh && normAll(firstTh.textContent) === normAll(cands[m].head[0])) { sc += 3; }
      if (sc > bestScore) { bestScore = sc; bestIdx = m; tie = false; }
      else if (sc === bestScore && sc > 0) { tie = true; }
    }
    if (bestIdx < 0 || bestScore < 2 || tie) {
      if (bestIdx >= 0) { need.push(fpOf(dt, mid)); }
      continue;
    }
    var built = buildTable(cands[bestIdx]);
    var rk = rejKeyOf(fpOf(dt, mid));
    var rej = window.__dsRej || (window.__dsRej = {});
    if (rej[rk]) { rejected++; continue; }
    var proof = damageProof(dt, built);
    if (proof === '') {
      // 形状可疑但原文证明不了「真的丢了内容」→ 保留站点原样，不替换。
      rej[rk] = 1;
      rejected++;
      continue;
    }
    used.push(bestIdx);
    if (dt.parentNode) {
      dt.parentNode.replaceChild(built, dt);
      fixed++;
    }
  }
  if (cands.length === 0 && need.length === 0) { return 'wait-md'; }
  var out2 = 'fixed=' + fixed + ' / mdv=' + String(window.__dsMdVersion || 0) +
    ' / histv=' + String(window.__dsHistVersion || 0);

  if (rejected > 0) { out2 += ' / rej=' + rejected; }
  if (need.length > 0) { out2 += ' / need=' + need.slice(0, 3).join(';'); }
  return out2;
  }
  window.__dsRepairTables = runRepair;
  try {
    if (!window.__dsRepairObs && window.MutationObserver) {
      window.__dsRepairObs = new MutationObserver(function () {
        if (window.__dsRepairScheduled) { return; }
        window.__dsRepairScheduled = 1;
        setTimeout(function () {
          window.__dsRepairScheduled = 0;
          try { runRepair(); } catch (e) { }
        }, 80);
      });
      window.__dsRepairObs.observe(document.body, { childList: true, subtree: true });
    }
  } catch (e) { }
  return runRepair();
})();`;
}

/**
 * 关闭「显示优化」时在页面里做的收尾：停掉两个观察者与挂起的定时器。
 *
 * 已经替换过的节点保持原样（要彻底回到站点原始渲染需要刷新页面），
 * 但不会再有任何新的扫描/替换，也不会再补拉历史原文。
 */
/**
 * 暂停表格修复（应用切到后台时调用）。
 *
 * 只摘掉表格修复的 DOM 观察者，**不动**公式补渲染那个观察者：后台不会产生 DOM 变化，
 * 留着一个随时可能触发 `runRepair()`（进而补拉历史原文）的观察者没有意义；
 * 回到前台后第一次轮询会重新安装它并立刻跑一轮，把后台期间新增的 DOM 补上。
 */
export function buildTableRepairPauseScript(): string {
  return `(function () {
    try {
      if (window.__dsRepairObs) { window.__dsRepairObs.disconnect(); window.__dsRepairObs = null; }
    } catch (e1) { }
    try {
      window.__dsRepairInstalled = false;
      window.__dsRepairTables = null;
      window.__dsRepairScheduled = false;
    } catch (e2) { }
    return 'table-repair-paused';
  })();`;
}
export function buildDisplayFixOffScript(): string {
  return `(function () {
    try {
      if (window.__dsMathFixObserver) {
        window.__dsMathFixObserver.disconnect();
        window.__dsMathFixObserver = null;
      }
    } catch (e1) { }
    try {
      if (window.__dsMathFixTimer) { clearTimeout(window.__dsMathFixTimer); window.__dsMathFixTimer = 0; }
    } catch (e2) { }
    try {
      if (window.__dsRepairObs) { window.__dsRepairObs.disconnect(); window.__dsRepairObs = null; }
    } catch (e3) { }
    try {
      window.__dsRepairInstalled = false;
      window.__dsRepairTables = null;
    } catch (e4) { }
    return 'display-fix-off';
  })();`;
}

