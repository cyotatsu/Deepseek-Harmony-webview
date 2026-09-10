/**
 * 页面加载进度条（顶部 3px）。
 *
 * 单独抽成组件的原因：loadingProgress 在页面加载过程中会变化数十次，
 * 若内联在 Index.build() 里，每次变化都会重算整个页面（含各弹窗与错误页）。
 * 抽出来后只有本组件重新求值。
 */
@Component
export struct PageProgress {
  @Prop progress: number = 0;

  build() {
    Progress({ value: this.progress, type: ProgressType.Linear })
      .width('100%')
      .height(3)
      .color($r('app.color.accent'))
      .backgroundColor($r('app.color.progress_track'))
  }
}
