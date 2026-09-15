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
   * **网页自己的**弹层是否开着（`role="dialog"` / `aria-modal` 且可见）。
   *
   * 必须由 DOM 探测得出，不能拿 `canGoBack` 代替 —— 实测「打开设置弹窗」与
   * 「切换到一个历史会话」都会让 `canGoBack` 变 true，但期望的返回行为相反。
   */
  webOverlayOpen: boolean;
  /** 当前是否处于对话界面（聊天主站根级页面，由 UrlRules.isChatRootPage 判定） */
  onChatRoot: boolean;
  /** 网页是否还能后退 */
  canGoBack: boolean;
  /** 距上次「再按一次」提示的毫秒数；负数表示本次会话还没提示过 */
  msSinceExitPrompt: number;
}

/**
 * 返回手势决策。调用方按返回值执行：
 *   dismiss-modal → 关掉自己的弹层并消费事件
 *   web-back      → 调 controller.backward() 并消费事件
 *   prompt-exit   → 弹提示并消费事件，同时记下本次提示时间
 *   exit-now      → 真正退出到桌面（调用方负责 terminateSelf）
 */
export function decideBackAction(ctx: BackContext): string {
  if (ctx.modalOpen) {
    return BACK_ACTION_DISMISS_MODAL;
  }
  // 网页自己的弹层优先交给网页：它打开时 push 的那条历史正是为「返回关弹层」准备的
  //（实测：「系统设置」弹窗 open 后 histLen 1→2，backward() 可将其关闭）
  if (ctx.webOverlayOpen && ctx.canGoBack) {
    return BACK_ACTION_WEB_BACK;
  }
  // 对话界面：屏蔽网页后退，统一按「再按一次返回桌面」处理
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
