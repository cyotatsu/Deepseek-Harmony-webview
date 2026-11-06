import { UiPalette, uiPalette } from '../common/UiPalette';

/**
 * 加载失败 / 网络异常错误页。
 *
 * 只依赖 isNetworkError 一个状态与 onRetry 回调，与 Index 的其余状态无关，
 * 因此可以独立重绘。
 */
@Component
export struct ErrorView {
  @Prop isNetworkError: boolean = false;
  /**
   * 网页当前是否深色。
   *
   * 错误页盖在网页之上，整页底色必须与网页一致，否则站点为深色、系统为浅色时
   * 会先闪一版白底再变黑（或反过来）。配色走 `UiPalette`，与设置面板同源。
   */
  @Prop webDark: boolean = false;

  onRetry: () => void = () => {};

  private pal(): UiPalette {
    return uiPalette(this.webDark);
  }

  build() {
    Column() {
      // 使用系统符号资源（sys.symbol.*），不依赖 Nerd Font 私有区字符
      SymbolGlyph(this.isNetworkError
        ? $r('sys.symbol.wifi_slash')
        : $r('sys.symbol.exclamationmark_circle'))
        .fontSize(48)
        .fontColor([this.pal().textSecondary])
        .margin({ top: 80, bottom: 16 })
      Text(this.isNetworkError ? $r('app.string.error_network_title') : $r('app.string.error_load_title'))
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.pal().textPrimary)
        .margin({ bottom: 8 })
      Text(this.isNetworkError ? $r('app.string.error_network_desc') : $r('app.string.error_load_desc'))
        .fontSize(14)
        .fontColor(this.pal().textSecondary)
        .margin({ bottom: 24 })
      Button($r('app.string.retry_button'))
        .type(ButtonType.Normal)
        .fontSize(16).width(160).height(40).borderRadius(20)
        .backgroundColor(this.pal().accent).fontColor(this.pal().textOnAccent)
        .onClick(() => this.onRetry())
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.pal().page)
  }
}
