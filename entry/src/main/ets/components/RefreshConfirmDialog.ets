/**
 * 刷新确认弹窗。
 *
 * 用官方 @CustomDialog 声明，由 CustomDialogController 承载。
 * 之所以不用 promptAction.showDialog：官方确认框不支持内嵌勾选框，
 * 而本弹窗需要「不再显示」这一项，因此按官方推荐做法自行组装 ——
 * 弹窗容器交给框架，内容用官方 Checkbox / Button 组件搭建。
 *
 * 配色沿用项目既有的语义化颜色资源，深浅色由资源限定词自动适配。
 */
import { UiPalette, uiPalette } from '../common/UiPalette';

@CustomDialog
export struct RefreshConfirmDialog {
  // 由 CustomDialogController 注入，用于关闭自身
  controller?: CustomDialogController;
  /**
   * 「不再显示」的勾选状态。
   * 用 @Link 与调用方双向绑定：调用方在每次弹出前把它重置为 false，
   * 避免上次的勾选残留到下一次。
   */
  @Link noMore: boolean;
  /** 网页当前是否深色主题（弹窗配色跟着网页走，见 common/UiPalette.ets） */
  @Prop webDark: boolean = false;

  private pal(): UiPalette {
    return uiPalette(this.webDark);
  }
  // 点「继续刷新」：回传是否勾选了「不再显示」
  onConfirm: (noMore: boolean) => void = () => {};
  // 点「取消」
  onCancel: () => void = () => {};

  build() {
    Column() {
      Text($r('app.string.refresh_confirm_title'))
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.pal().textPrimary)

      Text($r('app.string.refresh_confirm_message'))
        .fontSize(14)
        .fontColor(this.pal().textSecondary)
        .margin({ top: 12 })
        .textAlign(TextAlign.Center)
        .lineHeight(20)

      // 「不再显示」：整行可点，命中区域比小方框友好
      Row() {
        Checkbox({ name: 'noMoreRefreshPrompt', group: 'refreshConfirmGroup' })
          .select(this.noMore)
          .selectedColor(this.pal().accent)
          // 未选中态默认取系统主题色，网页深浅色与系统不一致时会串色
          .unselectedColor(this.pal().switchOff)
          .onChange((value: boolean) => {
            this.noMore = value;
          })
        Text($r('app.string.refresh_confirm_no_more'))
          .fontSize(13)
          .fontColor(this.pal().textSecondary)
          .margin({ left: 8 })
      }
      .margin({ top: 18 })
      .onClick(() => {
        this.noMore = !this.noMore;
      })

      Row() {
        Button($r('app.string.common_cancel'))
          .layoutWeight(1)
          .height(40)
          .fontSize(15)
          .backgroundColor(this.pal().buttonSecondary)
          .fontColor(this.pal().textPrimary)
          .onClick(() => {
            this.onCancel();
            // 必须用框架注入的 controller 关闭自身：
            // 父组件传进来的 onCancel 只是业务回调，不负责关弹窗。
            this.controller?.close();
          })
        Button($r('app.string.refresh_confirm_ok'))
          .layoutWeight(1)
          .height(40)
          .fontSize(15)
          .backgroundColor(this.pal().accent)
          .fontColor($r('app.color.text_on_accent'))
          .margin({ left: 12 })
          .onClick(() => {
            // 先关弹窗再回调，避免父组件里再次 close 造成重复关闭
            this.controller?.close();
            this.onConfirm(this.noMore);
          })
      }
      .width('100%')
      .margin({ top: 22 })
    }
    // 卡片外观由自己画：CustomDialogController 设了 customStyle: true（见 Index.ets），
    // 系统默认容器底色取自**系统**深浅色，而这里的文字颜色跟的是**网页**深浅色，
    // 两者不一致时会出现「白底白字 / 黑底黑字」。所以必须自己给底色与圆角。
    // 尺寸必须显式给：customStyle 下内容若只有 width('100%')，真机会塌缩成 0 宽。
    .width('86%')
    .constraintSize({ maxWidth: 380 })
    .padding(24)
    .borderRadius(20)
    .backgroundColor(this.pal().card)
    .shadow({ radius: 24, color: this.pal().shadow, offsetY: 8 })
    .alignItems(HorizontalAlign.Center)
  }
}
