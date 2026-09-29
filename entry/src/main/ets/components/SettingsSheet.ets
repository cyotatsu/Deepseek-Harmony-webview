/**
 * 设置面板内容（官方半模态组件 bindSheet 的内容区）。
 *
 * 从 Index 的 @Builder 抽成独立组件：内容全是静态文案与开关，
 * 自身不持有状态，开关值与三个动作都通过属性/回调进出。
 * 全部使用项目既有的语义化颜色资源，深浅色由资源限定词自动适配。
 */
@Component
export struct SettingsSheet {
  // ── 悬浮按钮相关（单向传入 + 回调回传，面板自身不持有状态）──
  /** 左右贴边时是否半隐藏 */
  @Prop hideOnSnap: boolean = true;
  /** 是否启用空闲自动吸附 */
  @Prop autoSnap: boolean = true;
  /** 重置悬浮按钮位置 */
  onResetFabPosition: () => void = () => {};
  onToggleHideOnSnap: (enabled: boolean) => void = () => {};
  onToggleAutoSnap: (enabled: boolean) => void = () => {};

  onClearCache: () => void = () => {};
  onOpenFeedback: () => void = () => {};
  onClose: () => void = () => {};

  /** 分组小标题（设置项多起来后需要分组，否则一排文字看不出层次） */
  @Builder
  sectionTitle(text: Resource) {
    Text(text)
      .fontSize(12)
      .fontColor($r('app.color.text_secondary'))
      .width('100%')
      .padding({ left: 20, right: 20, top: 18, bottom: 6 })
  }

  /** 可点击的设置项行（标题 + 说明 + 可选右侧内容由调用方给出） */
  @Builder
  actionRow(title: Resource, desc: Resource) {
    Column() {
      Text(title)
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
      Text(desc)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 3 })
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
  }

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

      // 说明：这里原有一个「刷新按钮」开关，用于控制悬浮条是否显示刷新按钮。
      // 现已移除 —— 刷新改为常显（见 components/FloatingBar.ets 的子菜单顺序）。
      // 若将来要恢复可配置，需要同时带回 @Prop refreshButtonEnabled 与 onToggleRefresh，
      // 以及 Index.ets 里的偏好读写（UiPrefs 的 isRefreshButtonEnabled/setRefreshButtonEnabled）。

      // ── 悬浮按钮 ──
      this.sectionTitle($r('app.string.settings_section_fab'))

      // 重置悬浮按钮位置：按钮可能被拖到偏下/与输入框重叠，这里给一个恢复入口
      Row() {
        this.actionRow($r('app.string.settings_reset_fab'), $r('app.string.settings_reset_fab_desc'))
        SymbolGlyph($r('sys.symbol.arrow_counterclockwise'))
          .fontSize(16)
          .fontColor([$r('app.color.text_secondary')])
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 12, bottom: 12 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => this.onResetFabPosition())

      Divider().color($r('app.color.progress_track')).opacity(0.15)

      // 空闲自动吸附开关
      Row() {
        this.actionRow($r('app.string.settings_auto_snap'), $r('app.string.settings_auto_snap_desc'))
        Toggle({ type: ToggleType.Switch, isOn: this.autoSnap })
          .onChange((isOn: boolean) => this.onToggleAutoSnap(isOn))
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 12, bottom: 12 })
      .alignItems(VerticalAlign.Center)

      Divider().color($r('app.color.progress_track')).opacity(0.15)

      // 贴边半隐藏开关
      Row() {
        this.actionRow($r('app.string.settings_hide_on_snap'), $r('app.string.settings_hide_on_snap_desc'))
        Toggle({ type: ToggleType.Switch, isOn: this.hideOnSnap })
          .onChange((isOn: boolean) => this.onToggleHideOnSnap(isOn))
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 12, bottom: 12 })
      .alignItems(VerticalAlign.Center)

      Divider().color($r('app.color.progress_track')).opacity(0.15)

      // ── 其它 ──
      this.sectionTitle($r('app.string.settings_section_misc'))

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
