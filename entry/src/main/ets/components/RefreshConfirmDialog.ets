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
  // 点「继续刷新」：回传是否勾选了「不再显示」
  onConfirm: (noMore: boolean) => void = () => {};
  // 点「取消」
  onCancel: () => void = () => {};

  build() {
    Column() {
      Text($r('app.string.refresh_confirm_title'))
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))

      Text($r('app.string.refresh_confirm_message'))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 12 })
        .textAlign(TextAlign.Center)
        .lineHeight(20)

      // 「不再显示」：整行可点，命中区域比小方框友好
      Row() {
        Checkbox({ name: 'noMoreRefreshPrompt', group: 'refreshConfirmGroup' })
          .select(this.noMore)
          .selectedColor($r('app.color.accent'))
          .onChange((value: boolean) => {
            this.noMore = value;
          })
        Text($r('app.string.refresh_confirm_no_more'))
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
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
          .backgroundColor($r('app.color.surface_button_secondary'))
          .fontColor($r('app.color.text_primary'))
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
          .backgroundColor($r('app.color.accent'))
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
    // 只负责内容：容器尺寸、圆角、背景由 CustomDialogController 的默认容器提供
    //（customStyle 保持默认 false）。曾尝试 customStyle: true 自行控制尺寸，
    // 真机上出现「弹窗已打开但完全不显示」——自定义尺寸在弹窗容器里容易塌缩。
    .width('100%')
    .padding(24)
    .alignItems(HorizontalAlign.Center)
  }
}
