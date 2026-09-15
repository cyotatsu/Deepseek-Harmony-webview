import { describe, it, expect } from '@ohos/hypium';
import {
  decideBackAction, isWithinExitWindow, BackContext,
  EXIT_CONFIRM_WINDOW_MS,
  BACK_ACTION_DISMISS_MODAL, BACK_ACTION_DISMISS_OVERLAY, BACK_ACTION_WEB_BACK,
  BACK_ACTION_PROMPT_EXIT, BACK_ACTION_EXIT_NOW
} from '../main/ets/common/BackPolicy';
import { OVERLAY_NONE, OVERLAY_DIALOG, OVERLAY_MENU, OVERLAY_CLOSABLE }
  from '../main/ets/common/WebViewport';

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
  webOverlay: string;
  onChatRoot: boolean;
  canGoBack: boolean;
  msSinceExitPrompt: number;

  constructor(onChatRoot: boolean = true, canGoBack: boolean = false,
    msSinceExitPrompt: number = -1, modalOpen: boolean = false,
    webOverlay: string = OVERLAY_NONE) {
    this.onChatRoot = onChatRoot;
    this.canGoBack = canGoBack;
    this.msSinceExitPrompt = msSinceExitPrompt;
    this.modalOpen = modalOpen;
    this.webOverlay = webOverlay;
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

    // 网页弹窗：它自己 push 了一条历史，后退就是它的关闭动作 ——
    // 实测它的关闭按钮没有 aria-label、模态弹窗又点不到「外面」，DOM 点不掉它
    it('uses_web_back_for_a_dialog_with_history', 0, () => {
      expect(decideBackAction(new BackCtx(true, true, -1, false, OVERLAY_DIALOG)))
        .assertEqual(BACK_ACTION_WEB_BACK);
      // 刚提示过退出也一样：弹窗优先
      expect(decideBackAction(new BackCtx(true, true, 100, false, OVERLAY_DIALOG)))
        .assertEqual(BACK_ACTION_WEB_BACK);
      // 没有历史时后退无路，只能尝试点掉
      expect(decideBackAction(new BackCtx(true, false, -1, false, OVERLAY_DIALOG)))
        .assertEqual(BACK_ACTION_DISMISS_OVERLAY);
    });

    // 菜单 / 多选模式：实测都不进历史，后退关不掉，必须点掉
    it('dismisses_menus_and_closable_ui_by_clicking', 0, () => {
      expect(decideBackAction(new BackCtx(true, false, -1, false, OVERLAY_MENU)))
        .assertEqual(BACK_ACTION_DISMISS_OVERLAY);
      expect(decideBackAction(new BackCtx(true, false, -1, false, OVERLAY_CLOSABLE)))
        .assertEqual(BACK_ACTION_DISMISS_OVERLAY);
      // 即便网页有历史（例如刚切换过会话），菜单也不该让网页后退 —— 那会翻到别的会话
      expect(decideBackAction(new BackCtx(true, true, -1, false, OVERLAY_MENU)))
        .assertEqual(BACK_ACTION_DISMISS_OVERLAY);
      // 多选模式：点掉优先于「再按一次退出」
      expect(decideBackAction(new BackCtx(true, true, 100, false, OVERLAY_CLOSABLE)))
        .assertEqual(BACK_ACTION_DISMISS_OVERLAY);
    });

    // 唯一允许「对话界面仍然后退」的情形就是上面那个有历史的网页弹窗；
    // 其余任何组合都不许把网页翻走（对话界面必须稳定地提示退出）
    it('never_navigates_the_web_on_a_chat_root_except_dialog_with_history', 0, () => {
      const kinds: Array<string> = [OVERLAY_NONE, OVERLAY_MENU, OVERLAY_CLOSABLE];
      for (const k of kinds) {
        for (const h of [true, false]) {
          const act: string = decideBackAction(new BackCtx(true, h, -1, false, k));
          expect(act === BACK_ACTION_WEB_BACK).assertFalse();
        }
      }
      // 弹窗但没有历史时也不许后退
      expect(decideBackAction(new BackCtx(true, false, -1, false, OVERLAY_DIALOG)))
        .assertEqual(BACK_ACTION_DISMISS_OVERLAY);
    });

    // 自己的弹层优先级高于网页瞬时界面
    it('prefers_own_modal_over_web_overlay', 0, () => {
      expect(decideBackAction(new BackCtx(true, true, -1, true, OVERLAY_MENU)))
        .assertEqual(BACK_ACTION_DISMISS_MODAL);
      expect(decideBackAction(new BackCtx(true, true, -1, true, OVERLAY_DIALOG)))
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

    // 五个动作必须是五个互不相同的值：写重一个会让调用方的分支静默失效
    it('keeps_the_five_actions_distinct', 0, () => {
      const acts: Array<string> = [BACK_ACTION_DISMISS_MODAL, BACK_ACTION_DISMISS_OVERLAY,
        BACK_ACTION_WEB_BACK, BACK_ACTION_PROMPT_EXIT, BACK_ACTION_EXIT_NOW];
      for (let i = 0; i < acts.length; i++) {
        for (let j = i + 1; j < acts.length; j++) {
          expect(acts[i] === acts[j]).assertFalse();
        }
      }
    });
  });
}
