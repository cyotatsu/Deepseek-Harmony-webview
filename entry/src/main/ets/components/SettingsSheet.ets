import { promptAction } from '@kit.ArkUI';
import { TEXT_ZOOM_MIN, TEXT_ZOOM_MAX, TEXT_ZOOM_STEP,
  normalizeTextZoom, formatTextZoom } from '../common/FontZoom';

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

  // ── 网页显示相关 ──
  /**
   * 网页文字缩放百分比（100 = 内核默认）。
   *
   * 用 @Link 双向绑定到页面的 AppStorage 值：拖滑块时 Web 组件的
   * textZoomRatio 立刻跟着变（平板上设置面板居中、网页可见，就是实时预览）；
   * 但只在滑块落定（松手 / 点轨道）时通过 onCommitFontSize 落盘。
   */
  @Link fontSize: number;
  onCommitFontSize: (zoom: number) => void = () => {};
  onResetFontSize: () => void = () => {};

  /**
   * 是否正在拖动字号滑块。
   *
   * 拖动时面板只留调节条：标题栏与其它设置项用 visibility Hidden 隐藏（Hidden 仍占位，
   * 因此滑块不会跳动），面板底色与遮罩同时转透明，对话界面原样露出；松手立刻恢复。
   * 状态放在 Index，是因为遮罩色与面板底色都是 bindSheet 的选项。
   */
  @Link fontDragging: boolean;

  /** 是否停在「字体大小」子页（列表 → 字号页），由列表里的字号行进入 */
  @Link fontPage: boolean;

  /** 网页正文的实际字号（CSS px），由 Index 在页面加载后量得，用作预览基准 */
  @Prop baseFontPx: number = 16;
  /**
   * 系统底部导航条（手势条）高度（vp），由页面传入。
   *
   * 页面是沉浸式的，底部弹窗会铺到屏幕最下沿，字号页最下面那行「恢复默认」正好压在
   * 手势条上、不好点；这里按它补出底部留白。
   */
  @Prop bottomInset: number = 0;

  /** 字号调节条：轨道厚度 / 圆点直径 / 控件高度（vp）——参考图是「粗胶囊轨道 + 白色圆点」 */
  private readonly SLIDER_TRACK_H: number = 14;
  private readonly SLIDER_BLOCK_D: number = 12;
  private readonly SLIDER_H: number = 28;

  /** 字号页的高度（vp）：预览卡 + 档位行 + 调节条 + 恢复默认，留一点余量 */
  /** 字号页里「预览卡以外」的固定高度（vp）：标题栏 + 档位行 + 调节条 + 恢复默认 + 内边距 */
  private readonly FONT_PAGE_BASE_H: number = 176;
  /** 字号页底部留白的下限（vp） */
  private readonly FONT_BOTTOM_PAD: number = 64;

  /**
   * 字号页底部实际留白（vp）：取「下限」与「导航条高度 + 余量」中的较大者。
   * 留白既作用于内容内边距，也计入面板高度，二者必须用同一个值，
   * 否则内容会被裁掉或面板底部多出一截空白。
   */
  private bottomPad(): number {
    return Math.max(this.FONT_BOTTOM_PAD, this.bottomInset + 12);
  }

  /** 当前生效的卡片高度：拖动中用冻结值，其余时候用实测值 */
  private effectiveCardH(): number {
    return this.fontDragging ? this.frozenCardH : this.cardH();
  }

  /** 字号页里除预览卡之外的固定高度（含底部留白） */
  private fontBaseH(): number {
    return this.FONT_PAGE_BASE_H + this.bottomPad();
  }
  /** 样例文字的实测高度（vp）：文字只按宽度换行，高度不受面板高度约束，可放心用来算整页高度 */
  @State previewTextH: number = 51;
  /** 卡片里除样例文字外的固定开销：小标题 + 间距 + 上下内边距 */
  private readonly PREVIEW_CHROME_H: number = 55;
  /** 拖动开始那一刻的预览卡高度：拖动中按它冻结，滑块不会被增高的卡片顶走 */
  @State frozenCardH: number = 106;

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

  /**
   * 预览样例文字的字号 = 网页正文字号 × 当前缩放比。
   *
   * 基准不写死 16：Index 每次页面加载完会量一次站点正文的实际 CSS px 传进来，
   * 这样预览里的样例文字与对话正文是同一个字号量级。
   */
  private fpSize(): number {
    const base: number = this.baseFontPx > 0 ? this.baseFontPx : 16;
    return Math.round(base * this.fontSize / 100 * 10) / 10;
  }

  /** 当前字号百分比文案，列表入口与字号页共用（如 115%） */
  private percentText(): string {
    return formatTextZoom(this.fontSize);
  }

  /** 当前档位名称：小 / 标准 / 大 / 特大 */
  private levelLabel(): Resource {
    if (this.fontSize <= 90) {
      return $r('app.string.settings_font_level_small');
    }
    if (this.fontSize < 110) {
      return $r('app.string.settings_font_level_normal');
    }
    if (this.fontSize < 140) {
      return $r('app.string.settings_font_level_large');
    }
    return $r('app.string.settings_font_level_xlarge');
  }

  /** 预览卡高度 = 样例文字实测高度 + 固定开销 */
  private cardH(): number {
    return Math.round(this.previewTextH + this.PREVIEW_CHROME_H);
  }

  /** 字号页标题栏：返回 + 标题/副标题 + 关闭 */
  @Builder
  fontHeader() {
    Row() {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(18)
          .fontColor([$r('app.color.text_primary')])
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .backgroundColor($r('app.color.surface_tile'))
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .accessibilityText($r('app.string.common_back'))
      .onClick(() => {
        this.fontPage = false;
      })

      Column() {
        Text($r('app.string.settings_font_size'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text($r('app.string.settings_font_size_subtitle'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12 })

      Row() {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(16)
          .fontColor([$r('app.color.text_secondary')])
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .backgroundColor($r('app.color.surface_tile'))
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .accessibilityText($r('app.string.common_close'))
      .onClick(() => this.onClose())
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
  }

  /**
   * 字号页内容：预览卡 + 档位/数值 + 调节条 + 恢复默认。
   *
   * 拖动调节条时只有「卡片高度」被冻结，其余内容照常显示 —— 既不隐藏任何东西，
   * 也保证调节条不会在手指底下上下移动。
   */
  @Builder
  fontBody() {
    Column() {
      this.fontHeader()

      Column() {
        // 预览：样例文字按当前字号渲染，卡片高度跟着文字走（文字下面不留空白）
        Column() {
          Text($r('app.string.settings_font_preview'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
          Text($r('app.string.settings_font_preview_text'))
            .fontSize(this.fpSize())
            .lineHeight(this.fpSize() * 1.6)
            .fontColor($r('app.color.text_primary'))
            .margin({ top: 6 })
            // 只测文字高度：它按宽度换行、不受面板高度约束，所以不会出现
            // 「面板高度依赖卡片、卡片高度又被面板限制」的循环
            .onAreaChange((oldArea: Area, newArea: Area) => {
              const h: number = Number(newArea.height);
              if (!isNaN(h) && h > 8 && Math.abs(h - this.previewTextH) > 0.5) {
                this.previewTextH = h;
              }
            })
        }
        .width('100%')
        // 卡片高度＝样例文字实测高度 + 固定开销：刚好包住文字，下面不留空白。
        // 拖动中改用进入拖动那一刻的冻结值：否则字号变大使卡片变高，会把下面的
        // 调节条一路往下顶（手指底下的滑轨跑掉）。
        .height(this.effectiveCardH())
        .alignItems(HorizontalAlign.Start)
        .padding(16)
        .borderRadius(14)
        .backgroundColor($r('app.color.surface_tile'))

        // 名称 + 档位 + 当前值
        Row() {
          Column() {
            Text($r('app.string.settings_font_size'))
              .fontSize(15)
              .fontColor($r('app.color.text_primary'))
            Text(this.levelLabel())
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 3 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Text(this.percentText())
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.accent'))
        }
        .width('100%')
        .margin({ top: 22 })
        .alignItems(VerticalAlign.Center)

        // 调节条：小 A —— 滑轨 —— 大 A
        Row() {
          Text('A')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
          Slider({
            value: this.fontSize,
            min: TEXT_ZOOM_MIN,
            max: TEXT_ZOOM_MAX,
            step: TEXT_ZOOM_STEP,
            // InSet：圆点嵌在轨道内部，配合加粗的轨道就是参考图那种胶囊形滑条
            style: SliderStyle.InSet
          })
            .layoutWeight(1)
            // 高度要放得下 InSet 的轨道与圆点，否则内核会退回默认尺寸
            .height(this.SLIDER_H)
            .margin({ left: 12, right: 12 })
            .trackThickness(this.SLIDER_TRACK_H)
            .blockSize({ width: this.SLIDER_BLOCK_D, height: this.SLIDER_BLOCK_D })
            .selectedColor($r('app.color.accent'))
            .trackColor($r('app.color.slider_track'))
            .blockColor($r('app.color.slider_thumb'))
            .accessibilityText($r('app.string.a11y_font_size'))
            .onChange((value: number, mode: SliderChangeMode) => {
              // 拖动中只更新预览值（面板与网页同时变）；松开 / 点轨道时才落盘
              this.fontSize = normalizeTextZoom(value);
              if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
                if (!this.fontDragging) {
                  // 进入拖动前冻结卡片高度：拖动中字号在变、卡片会被文字撑高，
                  // 不冻结就会把下面的调节条一路往下顶。
                  this.frozenCardH = this.cardH();
                }
                this.fontDragging = true;
              }
              if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                this.fontDragging = false;
                this.onCommitFontSize(this.fontSize);
              }
            })
          Text('A')
            .fontSize(21)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .margin({ top: 6 })
        .alignItems(VerticalAlign.Center)

        // 恢复默认
        Row() {
          Blank()
          Text($r('app.string.settings_font_size_reset'))
            .fontSize(13)
            .fontColor($r('app.color.accent'))
            .padding({ left: 12, top: 8, bottom: 8 })
            .onClick(() => {
              this.onResetFontSize();
              // 点了就给反馈：字号是全局设置，用户不一定马上注意到对话界面变了
              this.getUIContext().getPromptAction().showToast({
                message: $r('app.string.toast_font_size_reset'),
                duration: 1600
              });
            })
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 20, right: 20, bottom: this.bottomPad() })
    }
    .width('100%')
    .layoutWeight(1)
  }

  build() {
    Column() {
      if (this.fontPage) {
        this.fontBody()
      } else {
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

      // 内容区可滚动：设置项变多后（悬浮按钮 + 显示 + 其它）在平板横屏这种
      // 高度有限的情况下放不下，底部「问题反馈」会被面板边缘直接裁掉（实机可见）。
      // 标题栏保持固定，其余内容放进 Scroll，放不下时内部滚动。
      Scroll() {
        Column() {

          // 说明：这里原有一个「刷新按钮」开关，用于控制悬浮条是否显示刷新按钮。
          // 现已移除 —— 刷新改为常显（见 components/FloatingBar.ets 的子菜单顺序）。
          // 若将来要恢复可配置，需要同时带回 @Prop refreshButtonEnabled 与 onToggleRefresh，
          // 以及 Index.ets 里的偏好读写（UiPrefs 的 isRefreshButtonEnabled/setRefreshButtonEnabled）。

          Column() {
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

          }
          .width('100%')

          // ── 显示 ──
          this.sectionTitle($r('app.string.settings_section_display'))

          // 字号入口：只显示当前值，点进去才是字号页（带预览与滑杆）
          Row() {
            this.actionRow($r('app.string.settings_font_size'), $r('app.string.settings_font_size_desc'))
            Text(this.percentText())
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.accent'))
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(14)
              .fontColor([$r('app.color.text_secondary')])
              .margin({ left: 6 })
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 14, bottom: 14 })
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.fontPage = true;
          })

          Divider().color($r('app.color.progress_track')).opacity(0.15)
          Column() {
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
          }
        .width('100%')
      }
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    // 必须给确定高度：bindSheet 给内容区的高度有上限（平板横屏约 82% 屏高），
    // 根节点若自适应高度，超出的部分会被面板边缘直接裁掉、不会出现滚动；
    // 撑满后内部的 Scroll 才有可滚动空间（layoutWeight(1) 拿到剩余高度）。
    // 列表页撑满（需要内部滚动）；字号页＝固定部分 + 预览卡实测高度，正好包住内容，
    // 底部不会留下大片空白；拖动中用冻结值，滑块位置保持不动。
    .height(this.fontPage
      ? this.fontBaseH() + this.effectiveCardH()
      : '100%')
    .backgroundColor($r('app.color.surface_card'))
  }
}
