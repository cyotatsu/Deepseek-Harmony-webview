import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { loadRefreshButtonOffset, saveRefreshButtonOffset,
  isRefreshHintShown, markRefreshHintShown } from '../common/UiPrefs';

const DOMAIN = 0x0001;
const TAG = 'DeepSeekFloatingBar';

/**
 * 右下角悬浮操作条（刷新 + 设置）。
 *
 * 从 Index 里整体抽出的组件：**位置状态、拖拽手势、边界限制、位置持久化**
 * 全部收在这里，页面只负责「刷新按钮要不要弹确认框」这类业务决策。
 *
 * 为什么值得抽：拖拽会让 btnDragX/btnDragY 每帧变化，状态留在页面时
 * 整个页面（含 Web 组件）都会跟着重算；下沉到本组件后只有这一小块重新求值。
 *
 * ⚠️ 布局上的关键点：提示气泡与操作条原本是**页面 Stack 的两个平级绝对定位子节点**，
 * 都靠 `.position({ x: '100%', y: '100%' })` 相对页面定位。收进组件后必须由本组件的
 * 根节点充当那个「页面大小的参照系」，因此根节点是撑满的 Stack ——
 * **必须设置 `hitTestBehavior(HitTestMode.None)`**，否则这个撑满全屏的容器会
 * 吞掉所有落在空白处的触摸，表现为「整个网页点不动、划不动」。
 */
@Component
export struct FloatingBar {
  // ── 来自页面：三者共同决定按钮能被拖到哪里、是否需要为键盘让位 ──
  @Prop @Watch('onMetricsChange') pageW: number = 0;
  @Prop @Watch('onMetricsChange') pageH: number = 0;
  @Prop @Watch('onMetricsChange') keyboardHeightVp: number = 0;
  // 刷新按钮是否启用（开关在设置面板里，状态由页面持有）
  @Prop refreshEnabled: boolean = true;

  // ── 回给页面：业务动作留在页面侧 ──
  onRefresh: () => void = () => {};
  onOpenSettings: () => void = () => {};

  // ── 自身状态：位置与拖拽 ──
  @State btnDragX: number = 0;
  @State btnDragY: number = 0;
  @State btnDragging: boolean = false;
  @State showHint: boolean = false;

  // 手势开始时的位移基准
  private dragBaseX: number = 0;
  private dragBaseY: number = 0;
  // 长按进入拖拽模式后，本次抬手不应再触发刷新
  private suppressClick: boolean = false;
  private hintTimer: number = -1;
  // 操作条直径与默认边距（vp），边界限制按这两个值计算
  private readonly BTN_SIZE: number = 44;
  private readonly BTN_MARGIN: number = 24;

  aboutToAppear(): void {
    this.restorePrefs();
  }

  aboutToDisappear(): void {
    if (this.hintTimer !== -1) {
      clearTimeout(this.hintTimer);
      this.hintTimer = -1;
    }
  }

  /**
   * 恢复上次被拖到的位置；若是首次启动，展示一次「长按可拖动」提示。
   * 存储读写失败都不影响使用，只是回到默认位置 / 不再提示。
   */
  private restorePrefs(): void {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const offset: number[] = loadRefreshButtonOffset(ctx);
      if (offset.length === 2) {
        this.btnDragX = offset[0];
        this.btnDragY = offset[1];
      }
      if (!isRefreshHintShown(ctx)) {
        this.showHint = true;
        markRefreshHintShown(ctx);
        hilog.info(DOMAIN, TAG, 'Showing long-press hint for the first launch');
        // 6 秒后自动收起
        this.hintTimer = setTimeout(() => {
          this.showHint = false;
          this.hintTimer = -1;
        }, 6000);
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Failed to restore floating bar prefs');
    }
  }

  /**
   * 页面尺寸或键盘高度变化后重新做边界限制。
   * 原实现由页面在两个地方手动调用 clampBtnOffset()，现在改由 @Watch 驱动，
   * 页面只管把度量值传下来。
   */
  private onMetricsChange(): void {
    this.clampOffset();
  }

  /**
   * 键盘实际遮挡刷新按钮时所需的抬高量（vp）；不遮挡返回 0，即完全不移动。
   *
   * 键盘浮在页面底部、占据下方 keyboardHeightVp；按钮底边（未避让时）位于
   * pageH - BTN_MARGIN + btnDragY。只有底边低于键盘上沿才算被遮挡，此时抬高到
   * 键盘上沿之上并保留 BTN_MARGIN 间距 —— 位移刚好够露出按钮，而不是无条件
   * 上移整个键盘高度（按钮本来就高于键盘时不应有任何动作）。
   *
   * **拖动过程中必须返回 0**：避让量本身是由 btnDragY 推导出来的，若拖动时仍参与
   * 计算，会得到恒等式「渲染位置 = -(BTN_MARGIN + 键盘高)」—— btnDragY 被完全抵消，
   * 表现为键盘弹起后按钮怎么拖都不动。进入拖动前已把当时的避让量固化进 btnDragY
   *（见 LongPressGesture.onAction），因此这里返回 0 不会造成跳动。
   */
  private keyboardLiftVp(): number {
    if (this.btnDragging || this.keyboardHeightVp <= 0 || this.pageH <= 0) {
      return 0;
    }
    const btnBottom: number = this.pageH - this.BTN_MARGIN + this.btnDragY;
    const keyboardTop: number = this.pageH - this.keyboardHeightVp;
    if (btnBottom <= keyboardTop) {
      return 0;
    }
    return btnBottom - keyboardTop + this.BTN_MARGIN;
  }

  // 操作条宽度：刷新可用时为两段（刷新 | 设置），关闭刷新后只剩设置一段
  private barWidth(): number {
    return this.refreshEnabled ? this.BTN_SIZE * 2 + 8 : this.BTN_SIZE;
  }

  /**
   * 把拖拽位移限制在屏幕内，避免拖出可视区域后找不回来。
   * 按钮右下角位于 (pageW - BTN_MARGIN + dx, pageH - BTN_MARGIN + dy)，
   * 横向占用 barWidth()、纵向占用 BTN_SIZE，据此反推位移的可用范围。
   * 键盘遮挡不在这里预留 —— 那是 keyboardLiftVp 的职责，避免重复抬高。
   */
  private clampOffset(): void {
    if (this.pageW <= 0 || this.pageH <= 0) {
      return;
    }
    const barW: number = this.barWidth();
    const maxDx: number = this.BTN_MARGIN;
    const minDx: number = -(this.pageW - barW - this.BTN_MARGIN);
    const maxDy: number = this.BTN_MARGIN;
    const minDy: number = -(this.pageH - this.BTN_SIZE - this.BTN_MARGIN);
    this.btnDragX = Math.min(maxDx, Math.max(minDx, this.btnDragX));
    this.btnDragY = Math.min(maxDy, Math.max(minDy, this.btnDragY));
  }

  // 收起「长按可拖动」提示
  private dismissHint(): void {
    this.showHint = false;
    if (this.hintTimer !== -1) {
      clearTimeout(this.hintTimer);
      this.hintTimer = -1;
    }
  }

  // 保存位置（拖动结束时调用）
  private saveOffset(): void {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      saveRefreshButtonOffset(ctx, this.btnDragX, this.btnDragY);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Failed to save floating bar offset');
    }
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      // 首次启动的「长按可拖动」提示：位于操作条正上方、水平居中对齐，
      // 6 秒后自动收起，用户长按进入拖拽时也会立即收起。只在首次启动提示一次。
      if (this.showHint && this.refreshEnabled) {
        Text($r('app.string.refresh_drag_hint'))
          .fontSize(13)
          .fontColor($r('app.color.text_on_accent'))
          .backgroundColor($r('app.color.accent'))
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .borderRadius(14)
          .position({ x: '100%', y: '100%' })
          // 锚点取下边缘中点：这样 translate 给出的就是气泡「底边中心」的位置，
          // 与操作条的水平中心对齐，气泡整体落在条的上方。
          .markAnchor({ x: '50%', y: '100%' })
          .translate({
            // 水平：与操作条中心对齐（条右边缘在 pageW - BTN_MARGIN + btnDragX，
            // 再左移半个条宽即为中心）
            x: -this.BTN_MARGIN + this.btnDragX - this.barWidth() / 2,
            // 垂直：条顶边再上移 8vp（条的顶边 = 基准位置 - 条高 - 键盘避让抬高）
            y: -this.BTN_MARGIN + this.btnDragY - this.keyboardLiftVp() - this.BTN_SIZE - 8
          })
          .zIndex(102)
          .onClick(() => this.dismissHint())
      }

      // 右下角悬浮操作条：刷新 + 设置合并为一个圆角矩形。
      // 早先是两个独立圆形按钮，拖动后容易相互重叠；合并成一条后两者的相对位置固定，
      // 也不会各自与网页右下角的内容争抢空间。长按整条可拖动，松手停留、位置持久化。
      Row() {
        // 刷新：一键重新加载网页（可在设置面板中关闭）
        if (this.refreshEnabled) {
          Row() {
            // 用系统符号替代 '↻' 字符
            SymbolGlyph($r('sys.symbol.arrow_clockwise'))
              .fontSize(20)
              .fontColor([$r('app.color.text_primary')])
          }
          .layoutWeight(1)
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .accessibilityText($r('app.string.a11y_refresh'))
          .onClick(() => {
            if (this.suppressClick) {
              // 本次是长按拖拽的抬手，不当作刷新
              this.suppressClick = false;
              return;
            }
            // 刷新会丢弃未提交的输入，是否弹确认框由页面决定
            //（「不再显示」偏好与确认弹窗都归页面所有）
            this.onRefresh();
          })

          Divider()
            .vertical(true)
            .height(20)
            .color($r('app.color.drag_indicator'))
        }

        // 设置：采用官方符号 gearshape（系统资源码位 0xF0020，线性齿轮）
        Row() {
          SymbolGlyph($r('sys.symbol.gearshape'))
            .fontSize(20)
            .fontColor([$r('app.color.text_primary')])
        }
        .layoutWeight(1)
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .accessibilityText($r('app.string.settings_title'))
        .onClick(() => this.onOpenSettings())
      }
      .width(this.barWidth())
      .height(this.BTN_SIZE)
      .borderRadius(this.BTN_SIZE / 2)
      // 长按进入拖动态时给出高亮：底色提亮 + 阴影加深 + 整体放大
      .backgroundColor(this.btnDragging
        ? $r('app.color.floating_button_bg_active')
        : $r('app.color.floating_button_bg'))
      .shadow({
        radius: this.btnDragging ? 20 : 12,
        color: $r('app.color.floating_button_shadow'),
        offsetY: this.btnDragging ? 8 : 4
      })
      .scale({ x: this.btnDragging ? 1.12 : 1, y: this.btnDragging ? 1.12 : 1 })
      // animation 作用于「它之前声明的所有属性」，因此上面这些视觉属性会平滑过渡。
      // 务必把 .translate 放在它之后 —— 位置不参与动画，拖动才能完全跟手；
      // 若把 translate 写在 animation 之前，位移会被套上缓动，手感发飘、迟滞。
      .animation({ duration: 150, curve: Curve.FastOutSlowIn })
      .position({ x: '100%', y: '100%' })
      .markAnchor({ x: '100%', y: '100%' })
      .translate({
        // 基础位置：距右下角 BTN_MARGIN；再加上用户拖拽的位移；
        // 键盘确实遮挡时才按需抬高（不遮挡则完全不移动）。
        // 位于 .animation 之后 → 不参与动画 → 跟手无延迟。
        x: -this.BTN_MARGIN + this.btnDragX,
        y: -this.BTN_MARGIN + this.btnDragY - this.keyboardLiftVp()
      })
      // 每次新的触摸都重置「本次不刷新」标记
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.suppressClick = false;
        }
      })
      // 长按后拖动：官方手势组合。用「长按 → 拖动」序列把拖拽与单击区分开，
      // 避免普通点击被误判为拖动。
      .gesture(
        GestureGroup(GestureMode.Sequence,
          LongPressGesture({ repeat: false, duration: 400 })
            .onAction(() => {
              // 先把当前的键盘避让量固化进 btnDragY（此刻 btnDragging 仍为 false，
              // keyboardLiftVp 还能算出真实值），使按钮在进入拖动瞬间保持原位、不跳动；
              // 随后 btnDragging 置 true，拖动全程不再参与避让，完全跟手。
              this.btnDragY = this.btnDragY - this.keyboardLiftVp();
              // 进入拖拽模式：给出视觉反馈，抑制随后的点击，并收起首次提示
              this.btnDragging = true;
              this.suppressClick = true;
              this.dismissHint();
            })
            .onActionEnd(() => {
              this.btnDragging = false;
            })
            .onActionCancel(() => {
              this.btnDragging = false;
            }),
          PanGesture({ fingers: 1, direction: PanDirection.All, distance: 1 })
            .onActionStart(() => {
              this.dragBaseX = this.btnDragX;
              this.dragBaseY = this.btnDragY;
            })
            .onActionUpdate((event: GestureEvent) => {
              this.btnDragX = this.dragBaseX + event.offsetX;
              this.btnDragY = this.dragBaseY + event.offsetY;
              // 拖动过程中就做边界限制，使按钮到窗口边缘即停住，
              // 而不是拖出去、松手才弹回来
              this.clampOffset();
            })
            .onActionEnd(() => {
              this.btnDragging = false;
              // 限制在屏幕内，并记住位置
              this.clampOffset();
              this.saveOffset();
              hilog.info(DOMAIN, TAG, 'Floating bar moved to (%{public}d, %{public}d)',
                this.btnDragX, this.btnDragY);
            })
        )
      )
      .zIndex(101)
    }
    .width('100%')
    .height('100%')
    // ⚠️ 必须为 None：根节点撑满全屏，若参与命中测试会吞掉网页的触摸。
    // None = 自身不响应触摸，但**子节点正常响应**（两颗按钮仍可点、可拖）。
    .hitTestBehavior(HitTestMode.None)
  }
}
