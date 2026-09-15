import { describe, it, expect } from '@ohos/hypium';
import {
  decideBackAction, isWithinExitWindow, BackContext,
  EXIT_CONFIRM_WINDOW_MS,
  BACK_ACTION_DISMISS_MODAL, BACK_ACTION_WEB_BACK,
  BACK_ACTION_PROMPT_EXIT, BACK_ACTION_EXIT_NOW
} from '../main/ets/common/BackPolicy';

/**
 * common/BackPolicy 的本地（宿主）单元测试。
 *
 * 这里只测**判定逻辑**：URL → 「是不是对话界面」的识别在 UrlRules.isChatRootPage，
 * 它依赖 @kit.ArkTS 的 url 解析、宿主环境不可用，因此放在设备侧的
 * entry/src/ohosTest/ets/test/UrlRules.test.ets 里测（与本模块解耦正是为此）。
 *
 * 返回手势的判定决定了「侧滑一下就退出」还是「侧滑一下就跑到别的页面」，
 * 判错的体感非常明显，所以每条规则都钉在测试里。
 * 真正的手势行为（侧滑是否走到 onBackPress）必须实机验证，不在本地测试范围内。
 */

/** 只用于测试的上下文构造器：默认值即「对话界面、没历史、没提示过、无任何弹层」 */
class BackCtx implements BackContext {
  modalOpen: boolean;
  webOverlayOpen: boolean;
  onChatRoot: boolean;
  canGoBack: boolean;
  msSinceExitPrompt: number;

  constructor(onChatRoot: boolean = true, canGoBack: boolean = false,
    msSinceExitPrompt: number = -1, modalOpen: boolean = false,
    webOverlayOpen: boolean = false) {
    this.onChatRoot = onChatRoot;
    this.canGoBack = canGoBack;
    this.msSinceExitPrompt = msSinceExitPrompt;
    this.modalOpen = modalOpen;
    this.webOverlayOpen = webOverlayOpen;
  }
}

export default function backPolicyTest() {
  describe('exit confirm window', () => {
    // 负值表示「本次会话还没提示过」，必须与「刚提示过」区分开
    it('is_open_only_after_a_prompt_and_within_the_window', 0, () => {
      expect(isWithinExitWindow(-1)).assertFalse();
      expect(isWithinExitWindow(0)).assertTrue();
      expect(isWithinExitWindow(EXIT_CONFIRM_WINDOW_MS - 1)).assertTrue();
      expect(isWithinExitWindow(EXIT_CONFIRM_WINDOW_MS)).assertTrue();
      expect(isWithinExitWindow(EXIT_CONFIRM_WINDOW_MS + 1)).assertFalse();
    });
  });

  describe('back decisions', () => {
    it('closes_own_modal_first', 0, () => {
      expect(decideBackAction(new BackCtx(true, false, -1, true)))
        .assertEqual(BACK_ACTION_DISMISS_MODAL);
      // 二三级界面上弹层开着时同样优先关弹层
      expect(decideBackAction(new BackCtx(false, true, -1, true)))
        .assertEqual(BACK_ACTION_DISMISS_MODAL);
    });

    it('prompts_before_exiting_from_chat_root', 0, () => {
      expect(decideBackAction(new BackCtx())).assertEqual(BACK_ACTION_PROMPT_EXIT);
      // 窗口已过 → 重新提示，不能直接退出
      expect(decideBackAction(new BackCtx(true, false, EXIT_CONFIRM_WINDOW_MS + 1)))
        .assertEqual(BACK_ACTION_PROMPT_EXIT);
    });

    it('exits_on_second_press_within_the_window', 0, () => {
      expect(decideBackAction(new BackCtx(true, false, 300))).assertEqual(BACK_ACTION_EXIT_NOW);
    });

    // 本次改动的核心：对话界面即使网页还有历史，也绝不执行网页后退
    it('never_goes_web_back_from_chat_root_even_with_history', 0, () => {
      expect(decideBackAction(new BackCtx(true, true, -1))).assertEqual(BACK_ACTION_PROMPT_EXIT);
      expect(decideBackAction(new BackCtx(true, true, 300))).assertEqual(BACK_ACTION_EXIT_NOW);
    });

    // 网页自己的弹层优先交给网页：它打开时 push 的那条历史正是为「返回关弹层」准备的。
    // 实测：系统设置弹窗打开后 histLen 1→2；仅仅切换历史会话同样 1→2，
    // 所以这个分支必须由 DOM 探测（webOverlayOpen）触发，不能由 canGoBack 触发。
    it('hands_back_to_the_web_when_its_own_overlay_is_open', 0, () => {
      expect(decideBackAction(new BackCtx(true, true, -1, false, true)))
        .assertEqual(BACK_ACTION_WEB_BACK);
      // 刚提示过退出也一样：弹层优先
      expect(decideBackAction(new BackCtx(true, true, 100, false, true)))
        .assertEqual(BACK_ACTION_WEB_BACK);
    });

    // 弹层开着但网页没有历史 → 后退无路可走，回落到界面层级规则（不误触发网页后退）
    it('ignores_overlay_without_history', 0, () => {
      expect(decideBackAction(new BackCtx(true, false, -1, false, true)))
        .assertEqual(BACK_ACTION_PROMPT_EXIT);
      expect(decideBackAction(new BackCtx(false, false, -1, false, true)))
        .assertEqual(BACK_ACTION_PROMPT_EXIT);
    });

    // 自己的弹层优先级高于网页弹层
    it('prefers_own_modal_over_web_overlay', 0, () => {
      expect(decideBackAction(new BackCtx(true, true, -1, true, true)))
        .assertEqual(BACK_ACTION_DISMISS_MODAL);
    });

    // 二三级界面不受影响：有历史就照旧后退
    it('keeps_web_back_on_sub_pages_with_history', 0, () => {
      expect(decideBackAction(new BackCtx(false, true, -1))).assertEqual(BACK_ACTION_WEB_BACK);
      // 即使刚刚提示过退出，二三级界面仍以后退为先
      expect(decideBackAction(new BackCtx(false, true, 10))).assertEqual(BACK_ACTION_WEB_BACK);
    });

    it('confirms_before_exiting_from_a_dead_end_sub_page', 0, () => {
      expect(decideBackAction(new BackCtx(false, false, -1)))
        .assertEqual(BACK_ACTION_PROMPT_EXIT);
      expect(decideBackAction(new BackCtx(false, false, 300)))
        .assertEqual(BACK_ACTION_EXIT_NOW);
    });

    // 四个动作必须是四个互不相同的值：写重一个会让调用方的分支静默失效
    it('keeps_the_four_actions_distinct', 0, () => {
      const a: string = BACK_ACTION_DISMISS_MODAL;
      const b: string = BACK_ACTION_WEB_BACK;
      const c: string = BACK_ACTION_PROMPT_EXIT;
      const d: string = BACK_ACTION_EXIT_NOW;
      expect(a === b).assertFalse();
      expect(a === c).assertFalse();
      expect(a === d).assertFalse();
      expect(b === c).assertFalse();
      expect(b === d).assertFalse();
      expect(c === d).assertFalse();
    });
  });
}
