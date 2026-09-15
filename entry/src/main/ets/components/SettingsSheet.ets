/**
 * 设置面板内容（官方半模态组件 bindSheet 的内容区）。
 *
 * 从 Index 的 @Builder 抽成独立组件：内容全是静态文案与开关，
 * 自身不持有状态，开关值与三个动作都通过属性/回调进出。
 * 全部使用项目既有的语义化颜色资源，深浅色由资源限定词自动适配。
 */
@Component
export struct SettingsSheet {
  /** 刷新按钮开关的当前值（单向传入，变更通过 onToggleRefresh 回传） */
  @Prop refreshButtonEnabled: boolean = true;
  onToggleRefresh: (enabled: boolean) => void = () => {};
  onClearCache: () => void = () => {};
  onOpenFeedback: () => void = () => {};
  onClose: () => void = () => {};

  build() {
    Column() {
      // 标题栏自绘，配合 bindSheet 里的 showClose: false 使用。
      //
      // 为什么必须自绘：手机端用的 SheetType.CONTENT_COVER 是「内容全屏覆盖」形态，
      // 系统在该形态下**不渲染标题栏与关闭按钮**（真机截图可见面板没有标题也没有 ✕，
      // 只能靠返回手势退出）。而 CENTER 形态（平板）系统会渲染，所以那里必须
      // 显式关掉 showClose，否则系统那颗与自绘的会叠在同一位置 —— 表现为一个
      // 「圆形斜线 + 叉」的怪异图标，容易被误判为字形缺失。
      Row() {
        Text($r('app.string.settings_title'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        // 关闭：官方符号 xmark，外面套一个圆形浅底并加阴影，
        // 与系统半模态自带的关闭按钮观感一致（系统那颗也是「圆形浅底 + 叉」）。
        // 用 Row 包一层是为了确保符号在圆内居中，SymbolGlyph 直接设宽高不保证居中。
        Row() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(16)
            .fontColor([$r('app.color.text_secondary')])
        }
        // 40×40：在 56 高的标题栏内尽量贴近无障碍最小触摸目标
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor($r('app.color.surface_tile'))
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .shadow({
          radius: 8,
          color: $r('app.color.floating_button_shadow'),
          offsetX: 0,
          offsetY: 2
        })
        .accessibilityText($r('app.string.common_close'))
        .onClick(() => this.onClose())
      }
      .width('100%')
      .height(56)
      .padding({ left: 20, right: 12, top: 8 })
      .alignItems(VerticalAlign.Center)

      Divider().color($r('app.color.progress_track')).opacity(0.15)

      // 刷新按钮开关
      Row() {
        Column() {
          Text($r('app.string.settings_refresh_button'))
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
          Text($r('app.string.settings_refresh_button_desc'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 3 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.refreshButtonEnabled })
          .onChange((isOn: boolean) => {
            this.onToggleRefresh(isOn);
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 16, bottom: 16 })
      .alignItems(VerticalAlign.Center)

      Divider().color($r('app.color.progress_track')).opacity(0.15)

      // 清理应用缓存
      Row() {
        Column() {
          Text($r('app.string.settings_clear_cache'))
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
          Text($r('app.string.settings_clear_cache_desc'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 3 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 16, bottom: 16 })
      .onClick(() => this.onClearCache())

      Divider().color($r('app.color.progress_track')).opacity(0.15)

      // 问题反馈：按官方规范用 Want(action=viewData + browsable) 交给系统浏览器打开，
      // 不走应用内 WebView —— 用户需要看到地址栏，也便于登录 GitHub。
      Row() {
        Column() {
          Text($r('app.string.settings_feedback'))
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
          Text($r('app.string.settings_feedback_desc'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 3 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        SymbolGlyph($r('sys.symbol.arrow_right_up_and_square'))
          .fontSize(16)
          .fontColor([$r('app.color.text_secondary')])
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 16, bottom: 16 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => this.onOpenFeedback())
    }
    .width('100%')
    .backgroundColor($r('app.color.surface_card'))
  }
}
