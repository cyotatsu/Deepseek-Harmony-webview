import { UiPalette, uiPalette } from '../common/UiPalette';

/**
 * 上传方式选择模态框（拍照 / 相册 / 文件）。
 *
 * 从 Index.build() 中抽出的纯展示组件：自身不持有任何状态，
 * 三个选项与遮罩点击全部通过回调交回页面处理。
 *
 * 抽出来的收益：上传相关状态（showUploadModal 等）变化时只重绘本组件，
 * 不再连带重算包含 Web 组件的整个页面。
 */
@Component
export struct UploadSheet {
  /**
   * 网页当前是否深色。
   *
   * 配色不能用 `app.color.*`：那套资源只跟随**系统**深浅色，而站点可以在系统为
   * 浅色时把网页切成深色 —— 那样网页全黑、这个面板惨白。改由页面把网页的
   * 真实深浅色传下来，按 `UiPalette` 取色（与设置面板同一套表）。
   */
  @Prop webDark: boolean = false;

  onTakePhoto: () => void = () => {};
  onPickFromAlbum: () => void = () => {};
  onPickFile: () => void = () => {};
  onDismiss: () => void = () => {};

  private pal(): UiPalette {
    return uiPalette(this.webDark);
  }

  build() {
    Column() {
      Column() {
        Text($r('app.string.upload_modal_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.pal().textPrimary)
          .margin({ bottom: 20 })

        // 横向排列：拍照 / 相册 / 文件
        Row() {
          // 拍照
          Column() {
            SymbolGlyph($r('sys.symbol.camera_fill'))
              .fontSize(28)
              .fontColor([this.pal().textPrimary])
              .margin({ bottom: 8 })
            Text($r('app.string.upload_photo'))
              .fontSize(13)
              .fontColor(this.pal().textPrimary)
          }
          .width('30%')
          .aspectRatio(1)
          .borderRadius(14)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.pal().tile)
          .onClick(() => this.onTakePhoto())

          // 相册
          Column() {
            SymbolGlyph($r('sys.symbol.picture_fill'))
              .fontSize(28)
              .fontColor([this.pal().textPrimary])
              .margin({ bottom: 8 })
            Text($r('app.string.upload_album'))
              .fontSize(13)
              .fontColor(this.pal().textPrimary)
          }
          .width('30%')
          .aspectRatio(1)
          .borderRadius(14)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.pal().tile)
          .onClick(() => this.onPickFromAlbum())

          // 文件
          Column() {
            SymbolGlyph($r('sys.symbol.doc_text_fill'))
              .fontSize(28)
              .fontColor([this.pal().textPrimary])
              .margin({ bottom: 8 })
            Text($r('app.string.upload_file'))
              .fontSize(13)
              .fontColor(this.pal().textPrimary)
          }
          .width('30%')
          .aspectRatio(1)
          .borderRadius(14)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.pal().tile)
          .onClick(() => this.onPickFile())
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceEvenly)
      }
      .width('85%')
      .constraintSize({ maxWidth: 360 })
      .padding(24)
      .borderRadius(16)
      .backgroundColor(this.pal().card)
      .shadow({ radius: 24, color: this.pal().cardShadow, offsetY: 8 })
      // 卡片自身吞掉点击，避免穿透到遮罩把弹窗关掉
      .onClick(() => {
      })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.pal().scrim)
    .onClick(() => this.onDismiss())
    .zIndex(100)
  }
}
