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
  onTakePhoto: () => void = () => {};
  onPickFromAlbum: () => void = () => {};
  onPickFile: () => void = () => {};
  onDismiss: () => void = () => {};

  build() {
    Column() {
      Column() {
        Text($r('app.string.upload_modal_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .margin({ bottom: 20 })

        // 横向排列：拍照 / 相册 / 文件
        Row() {
          // 拍照
          Column() {
            SymbolGlyph($r('sys.symbol.camera_fill'))
              .fontSize(28)
              .margin({ bottom: 8 })
            Text($r('app.string.upload_photo'))
              .fontSize(13)
          }
          .width('30%')
          .aspectRatio(1)
          .borderRadius(14)
          .justifyContent(FlexAlign.Center)
          .backgroundColor($r('app.color.surface_tile'))
          .onClick(() => this.onTakePhoto())

          // 相册
          Column() {
            SymbolGlyph($r('sys.symbol.picture_fill'))
              .fontSize(28)
              .margin({ bottom: 8 })
            Text($r('app.string.upload_album'))
              .fontSize(13)
          }
          .width('30%')
          .aspectRatio(1)
          .borderRadius(14)
          .justifyContent(FlexAlign.Center)
          .backgroundColor($r('app.color.surface_tile'))
          .onClick(() => this.onPickFromAlbum())

          // 文件
          Column() {
            SymbolGlyph($r('sys.symbol.doc_text_fill'))
              .fontSize(28)
              .margin({ bottom: 8 })
            Text($r('app.string.upload_file'))
              .fontSize(13)
          }
          .width('30%')
          .aspectRatio(1)
          .borderRadius(14)
          .justifyContent(FlexAlign.Center)
          .backgroundColor($r('app.color.surface_tile'))
          .onClick(() => this.onPickFile())
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceEvenly)
      }
      .width('85%')
      .constraintSize({ maxWidth: 360 })
      .padding(24)
      .borderRadius(16)
      .backgroundColor($r('app.color.surface_card'))
      .shadow({ radius: 24, color: $r('app.color.card_shadow'), offsetY: 8 })
      // 卡片自身吞掉点击，避免穿透到遮罩把弹窗关掉
      .onClick(() => {
      })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.modal_scrim'))
    .onClick(() => this.onDismiss())
    .zIndex(100)
  }
}
