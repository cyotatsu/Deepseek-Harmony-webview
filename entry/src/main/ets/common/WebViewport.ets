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
          'textarea,[contenteditable="true"]{max-height:var(${COMPOSER_CAP_VAR},${COMPOSER_FALLBACK_VH}vh) !important;overflow-y:auto !important;}';
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
            window.__dsComposerCapInfo = {
              visibleH: Math.round(h),
              capPx: cap,
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

/**
 * 检测**网页自己的弹层**是否开着（供返回手势决策使用）。
 *
 * 为什么不能只看 `controller.accessBackward()`：实机实测（MatePad 11.5）
 *   · 打开「系统设置」弹窗：`histLen` 1 → 2，`canGoBack` false → true；
 *   · 仅仅是**切换到一个历史会话**：`histLen` 同样 1 → 2，`canGoBack` 同样变 true。
 * 两者在历史长度上完全一样，而期望的返回行为相反：前者要把返回交给网页去关弹窗，
 * 后者要「再按一次返回桌面」。只有 DOM 能区分 —— 实测弹窗打开时
 * `role="dialog"` / `aria-modal="true"` 的可见元素个数由 0 变 1。
 *
 * 返回 `1` / `0`。**探测失败一律当 0**：即回落到「按界面层级决策」，
 * 不会因为一次探测失败就把返回手势永久让给网页。
 */
export function buildOverlayProbeScript(): string {
  return `(function () {
    try {
      var list = document.querySelectorAll('[role="dialog"],[aria-modal="true"]');
      for (var i = 0; i < list.length; i++) {
        var el = list[i];
        var cs = window.getComputedStyle(el);
        if (!cs) { continue; }
        if (cs.display === 'none' || cs.visibility === 'hidden') { continue; }
        if (cs.opacity !== '' && Number(cs.opacity) === 0) { continue; }
        var r = el.getBoundingClientRect();
        // 过滤掉隐藏的「模板」弹层：必须真的有尺寸
        if (r.width < 80 || r.height < 80) { continue; }
        return 1;
      }
      return 0;
    } catch (e) {
      return 0;
    }
  })();`;
}

/**
 * 解析 {@link buildOverlayProbeScript} 的返回值。
 *
 * runJavaScript 的返回值是字符串化的：脚本返回数字时通常拿到 `1`，
 * 但不同版本/不同返回类型可能带引号，因此两种形式都要认，其余一律当未打开。
 */
export function isOverlayOpenResult(raw: string): boolean {
  if (!raw) {
    return false;
  }
  const v: string = raw.replace(/"/g, '').replace(/'/g, '').trim();
  return v === '1' || v === 'true';
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

      return JSON.stringify({
        ua: navigator.userAgent,
        mobileToken: /Mobile/i.test(navigator.userAgent),
        histLen: window.history ? window.history.length : -1,
        overlay: overlay,
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
