/**
 * 加载失败 / 网络异常错误页。
 *
 * 只依赖 isNetworkError 一个状态与 onRetry 回调，与 Index 的其余状态无关，
 * 因此可以独立重绘。
 */
@Component
export struct ErrorView {
  @Prop isNetworkError: boolean = false;
  onRetry: () => void = () => {};

  build() {
    Column() {
      // 使用系统符号资源（sys.symbol.*），不依赖 Nerd Font 私有区字符
      SymbolGlyph(this.isNetworkError
        ? $r('sys.symbol.wifi_slash')
        : $r('sys.symbol.exclamationmark_circle'))
        .fontSize(48)
        .fontColor([$r('app.color.text_secondary')])
        .margin({ top: 80, bottom: 16 })
      Text(this.isNetworkError ? $r('app.string.error_network_title') : $r('app.string.error_load_title'))
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .margin({ bottom: 8 })
      Text(this.isNetworkError ? $r('app.string.error_network_desc') : $r('app.string.error_load_desc'))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ bottom: 24 })
      Button($r('app.string.retry_button'))
        .type(ButtonType.Normal)
        .fontSize(16).width(160).height(40).borderRadius(20)
        .backgroundColor($r('app.color.accent')).fontColor($r('app.color.text_on_accent'))
        .onClick(() => this.onRetry())
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.web_background'))
  }
}
