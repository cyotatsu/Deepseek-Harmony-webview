import { OVERLAY_DIALOG, OVERLAY_NONE, OVERLAY_PREVIEW, OVERLAY_CONFIRM } from './WebViewport';

/**
 * 返回手势（侧滑返回 / 返回键）策略。
 *
 * 背景：本应用是单 Web 组件容器，网页自己的会话历史会参与返回。侧滑返回原先一律
 * 映射成「网页后退」，这在**对话界面**上不是用户期望的行为 —— 用户在会话里连续
 * 侧滑，期望的是像其他应用那样退出到桌面，而不是被网页后退带到另一个页面
 *（例如刚登录完，后退还能退回登录页；或退回到上一个会话）。
 *
 * 目标：
 *   · **网页自己的弹层**（设置、分享、图片预览…）—— 交给网页处理（`backward()`），
 *     它打开时 push 的那条历史就是为「返回关弹层」准备的；
 *   · **对话界面**（聊天主站的根级页面，识别见 UrlRules.isChatRootPage）
 *     —— 不执行网页后退，改为「再按一次返回桌面」：第一次只提示，
 *     在确认窗口内再按一次才真正退出；
 *   · **二三级界面**（站内其他页面，例如 `/sign_in`、`/share/…`，以及任何
 *     网页自己还有历史的页面）—— **保持原样**，仍然是网页后退；
 *   · 已经退无可退（网页没有历史）—— 同样走「再按一次」确认，避免误退出。
 *
 * 本模块与 URL 解析解耦：调用方传进来的就是「当前是否在对话界面」这个结论
 *（由 UrlRules.isChatRootPage 判定）。这样这里只剩纯判定逻辑，不依赖任何
 * 系统 API，可以在宿主机上直接跑单元测试 —— `@kit.ArkTS` 的 url 解析在宿主
 * 环境不可用，一旦耦合进来就会让断言整体失真。
 */

/** 退出确认窗口（毫秒）：两次返回手势间隔不超过该值，才算「再按一次」 */
export const EXIT_CONFIRM_WINDOW_MS: number = 2000;

/** 决策：关闭应用内自己的弹层 */
export const BACK_ACTION_DISMISS_MODAL: string = 'dismiss-modal';
/** 决策：点掉网页自己的瞬时界面（菜单 / 多选模式） */
export const BACK_ACTION_DISMISS_OVERLAY: string = 'dismiss-overlay';
/**
 * 决策：**退出图片/文件预览**，回到对话界面。
 *
 * 与 dismiss-overlay 分开的原因：预览的关闭方式更严格（要点遮罩空白或它自己的关闭入口，
 * 绝不能碰到图片本体），而且**必须先于任何 backward/退出判断** ——
 * 预览层通常不往历史里 push，若落到 dialog 分支的 `canGoBack ? backward : dismiss-overlay`，
 * 两条路都关不掉预览，系统随即把这次返回当成退出应用（实机表现：侧滑后直接回桌面）。
 */
export const BACK_ACTION_DISMISS_PREVIEW: string = 'dismiss-preview';
/**
 * 决策：**关闭确认类弹窗**（删除确认等）。
 *
 * 同样必须前置于 backward/退出：确认弹窗一般不 push 历史，
 * 一旦被判成"无历史 + 在对话根"就会走「再按一次退出桌面」，而用户只是想把弹窗关掉。
 */
export const BACK_ACTION_DISMISS_CONFIRM: string = 'dismiss-confirm';
/** 决策：交给网页后退 */
export const BACK_ACTION_WEB_BACK: string = 'web-back';
/** 决策：提示「再按一次返回桌面」 */
export const BACK_ACTION_PROMPT_EXIT: string = 'prompt-exit';
/** 决策：真正退出（返回 false，交给系统回到桌面） */
export const BACK_ACTION_EXIT_NOW: string = 'exit-now';

/** 两次返回手势是否落在「再按一次」的确认窗口内（负数表示本次还没提示过） */
export function isWithinExitWindow(msSinceExitPrompt: number): boolean {
  return msSinceExitPrompt >= 0 && msSinceExitPrompt <= EXIT_CONFIRM_WINDOW_MS;
}

/** 返回手势的上下文 */
export interface BackContext {
  /** 应用内自己的弹层是否开着（开着时优先关弹层） */
  modalOpen: boolean;
  /**
   * **网页自己的**瞬时界面类型（见 WebViewport.buildOverlayProbeScript）：
   * 空串 = 没有；`dialog` = 网页弹窗；`menu` = 网页菜单；`closable` = 带关闭入口的界面。
   *
   * 必须由 DOM 探测得出，不能拿 `canGoBack` 代替 —— 实测「打开设置弹窗」与
   * 「切换到一个历史会话」都会让 `canGoBack` 变 true，但期望的返回行为相反。
   */
  webOverlay: string;
  /** 当前是否处于对话界面（聊天主站根级页面，由 UrlRules.isChatRootPage 判定） */
  onChatRoot: boolean;
  /** 网页是否还能后退 */
  canGoBack: boolean;
  /** 距上次「再按一次」提示的毫秒数；负数表示本次会话还没提示过 */
  msSinceExitPrompt: number;
}

/**
 * 「点掉网页瞬时界面」失败后的**降级动作**。
 *
 * 背景（这是一个真实漏洞的修复）：
 *   onBackPress 固定返回 true（把返回事件消费掉了），后续动作全靠异步执行。
 *   当判成 dismiss-overlay 时，若关闭脚本**没点到任何目标**（实测会返回 no-host ——
 *   因为"取消/关闭"文字按钮可能并不在任何浮层容器内），
 *   返回键就被白白消费掉了：什么都没发生，用户感知就是「返回失灵」。
 *
 * 因此点不掉时必须降级，而不是就此结束：
 *   · 网页还有历史 ⇒ 走网页后退（至少让用户能退，而不是原地不动）；
 *   · 没有历史 ⇒ 走「再按一次退出」的确认，而不是静默丢弃。
 *
 * @param canGoBack 网页是否还能后退
 * @param msSinceExitPrompt 距上次「再按一次」提示的毫秒数；负数表示本次会话还没提示过
 * @returns 降级后的动作（web-back / prompt-exit / exit-now）
 */
export function decideOverlayDismissFallback(canGoBack: boolean,
  msSinceExitPrompt: number): string {
  if (canGoBack) {
    return BACK_ACTION_WEB_BACK;
  }
  return isWithinExitWindow(msSinceExitPrompt)
    ? BACK_ACTION_EXIT_NOW : BACK_ACTION_PROMPT_EXIT;
}

/**
 * 返回手势决策。调用方按返回值执行：
 *   dismiss-modal   → 关掉应用自己的弹层
 *   dismiss-overlay → 点掉网页自己的瞬时界面（菜单 / 多选模式）
 *   web-back        → 调 controller.backward()
 *   prompt-exit     → 弹提示并记下本次提示时间
 *   exit-now        → 真正退出到桌面（调用方负责 terminateSelf）
 */
export function decideBackAction(ctx: BackContext): string {
  if (ctx.modalOpen) {
    return BACK_ACTION_DISMISS_MODAL;
  }
  // **预览态优先**：点图片是缩放而非关闭、且多数不 push 历史，
  // 因此绝不 backward、绝不进入"再按一次退出"的判定。
  if (ctx.webOverlay === OVERLAY_PREVIEW) {
    return BACK_ACTION_DISMISS_PREVIEW;
  }
  // **确认弹窗优先**：同上。用户按返回的意图是"取消这次操作"。
  if (ctx.webOverlay === OVERLAY_CONFIRM) {
    return BACK_ACTION_DISMISS_CONFIRM;
  }
  // 网页**弹窗**：它打开时会 push 一条历史，后退就是它自己的关闭动作 ——
  // 实测「系统设置」弹窗关闭按钮没有 aria-label、且模态弹窗覆盖全屏，
  // 「点外面」也点不到，DOM 点不掉它，只能用后退。
  if (ctx.webOverlay === OVERLAY_DIALOG) {
    return ctx.canGoBack ? BACK_ACTION_WEB_BACK : BACK_ACTION_DISMISS_OVERLAY;
  }
  // 菜单 / 多选模式：实测都不进历史（histLen 始终为 1，Esc 也无效），
  // 后退关不掉，只能点掉它自己的关闭入口或点菜单外面
  if (ctx.webOverlay !== OVERLAY_NONE) {
    return BACK_ACTION_DISMISS_OVERLAY;
  }
  // 对话界面：不执行网页后退，统一按「再按一次返回桌面」处理
  if (ctx.onChatRoot) {
    return isWithinExitWindow(ctx.msSinceExitPrompt)
      ? BACK_ACTION_EXIT_NOW : BACK_ACTION_PROMPT_EXIT;
  }
  // 二三级界面：网页还有历史就照旧后退，不受本次改动影响
  if (ctx.canGoBack) {
    return BACK_ACTION_WEB_BACK;
  }
  // 退无可退：也给一次确认，避免一次误触直接退出
  return isWithinExitWindow(ctx.msSinceExitPrompt)
    ? BACK_ACTION_EXIT_NOW : BACK_ACTION_PROMPT_EXIT;
}
