import { webview } from '@kit.ArkWeb';
import { common, Want } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { fileIo as fs, fileUri, picker } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { resourceManager, i18n } from '@kit.LocalizationKit';
import { connection } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window, promptAction } from '@kit.ArkUI';
import { url } from '@kit.ArkTS';
import { camera, cameraPicker } from '@kit.CameraKit';
import { UPLOAD_FILTER_EXTENSIONS } from '../common/AllowedFileExtensions';
import { DEEPSEEK_URL, DEEPSEEK_HOST, FEEDBACK_URL } from '../common/AppConfig';
import { isDeepSeekDomain, isDownloadUrl } from '../common/UrlRules';
import { toBCP47 } from '../common/LanguageUtil';
import { buildPhotoTempPath } from '../common/PhotoTempFiles';
import { PageProgress } from '../components/PageProgress';
import { ErrorView } from '../components/ErrorView';
import { RefreshConfirmDialog } from '../components/RefreshConfirmDialog';
import { loadRefreshButtonOffset, saveRefreshButtonOffset, isRefreshHintShown,
  markRefreshHintShown, isRefreshButtonEnabled, setRefreshButtonEnabled,
  isRefreshConfirmSkipped, setRefreshConfirmSkipped } from '../common/UiPrefs';

const DOMAIN = 0x0001;
const TAG = 'DeepSeekIndex';

@Entry
@Component
struct Index {
  @State loadingProgress: number = 0;
  @State isLoading: boolean = true;
  @State isError: boolean = false;
  @State isNetworkError: boolean = false;
  @StorageLink('deepLinkUrl') @Watch('onDeepLinkChange') deepLinkUrl: string = '';
  // Web 控制器是否已挂载。冷启动期间为 false：此时 loadUrl 会抛异常。
  private controllerReady: boolean = false;
  // 因控制器未就绪而暂存的 DeepLink，待首页加载完成后补导航。
  private pendingDeepLink: string = '';
  // Web 的初始加载地址。冷启动带 DeepLink 时该值即为分享链接，否则为首页。
  private initialUrl: string = DEEPSEEK_URL;
  // 系统语言适配：监听系统语言变化以重新注入 WebView
  @StorageLink('systemLanguage') @Watch('onSystemLanguageChange') systemLanguage: string = '';
  controller: webview.WebviewController = new webview.WebviewController();
  delegate: webview.WebDownloadDelegate = new webview.WebDownloadDelegate();
  private pageLoadTimer: number = -1;
  private readonly LOAD_TIMEOUT_MS: number = 15000;
  // 2in1/PC 设备标识：用于返回按钮
  @State isPC: boolean = false;
  // 返回按钮：2in1 设备上访问非 DeepSeek 域名且有回退历史时显示
  @State showBackButton: boolean = false;
  // 上传方式选择模态框
  @State showUploadModal: boolean = false;
  // 右下角常驻刷新按钮（无状态：始终显示，点击后不隐藏）
  // 键盘避让高度（vp）。键盘是浮层、不改变窗口尺寸，页面底部会落到键盘之下，
  // 因此需要把右下角按钮抬高到键盘之上，否则会被键盘遮挡。
  @State keyboardHeightVp: number = 0;
  // 状态栏避让高度（vp）。底部沉浸开启后布局延伸到系统栏区域，顶部需要按此补 padding，
  // 视觉上仍是一条正常的状态栏，而不是内容压到状态栏文字下面。
  @State statusBarHeightVp: number = 0;
  private avoidAreaHandler: ((data: window.AvoidAreaOptions) => void) | null = null;
  // 刷新按钮的拖拽位移（相对默认的右下角位置）。长按后可拖到任意位置并停留。
  @State btnDragX: number = 0;
  @State btnDragY: number = 0;
  // 拖拽过程中的视觉反馈
  @State btnDragging: boolean = false;
  // 手势开始时的位移基准
  private btnDragBaseX: number = 0;
  private btnDragBaseY: number = 0;
  // 长按进入拖拽模式后，本次抬手不应再触发刷新
  private btnSuppressClick: boolean = false;
  // 刷新按钮直径与默认边距（vp），边界限制按这两个值计算
  private readonly BTN_SIZE: number = 44;
  private readonly BTN_MARGIN: number = 24;
  // 页面可用尺寸（vp），由根容器 onAreaChange 提供，用于把按钮限制在屏幕内
  @State pageW: number = 0;
  @State pageH: number = 0;
  // 首次启动时展示「长按可拖动」提示
  @State showRefreshHint: boolean = false;
  private refreshHintTimer: number = -1;
  // 设置面板开关
  @State showSettings: boolean = false;
  // 右下角刷新按钮是否启用（设置面板里的开关，持久化）
  @State refreshButtonEnabled: boolean = true;
  // 用户已勾选「不再显示」刷新确认弹窗（持久化）
  @State refreshSkipConfirm: boolean = false;
  // 本次弹窗里「不再显示」的勾选状态（每次弹出前重置，@Link 绑定给弹窗组件）
  @State noMoreRefreshPrompt: boolean = false;
  private pendingFileListHandler: ((fileList: Array<string>) => void) | null = null;

  aboutToAppear(): void {
    // 检测是否为 2in1/PC 设备
    this.isPC = deviceInfo.deviceType === '2in1';
    this.setupKeyboardAvoid();
    this.restoreRefreshButtonPrefs();
    // 冷启动携带的 DeepLink 直接作为 Web 的初始 src。
    // 不能等到 onPageShow 再 loadUrl —— 那会比 onControllerAttached 早约 35ms，
    // 控制器尚未绑定必然抛异常；即便推迟到 onControllerAttached，
    // 组件的初始 src（首页）加载也会覆盖该次导航。作为初始 src 可彻底避开竞态。
    if (this.deepLinkUrl && this.deepLinkUrl !== '') {
      this.initialUrl = this.deepLinkUrl;
      hilog.info(DOMAIN, TAG, 'Cold-start DeepLink used as initial src');
      // 已消费，立即清空，避免 onPageShow / onDeepLinkChange 重复处理
      AppStorage.set<string>('deepLinkUrl', '');
    }
    // 监听网络恢复：处于错误页时自动重连（NetworkKit NetConnection 官方用法）
    try {
      this.netConnection = connection.createNetConnection();
      this.netConnection.on('netAvailable', this.onNetAvailable);
      this.netConnection.register((error: BusinessError) => {
        if (error) {
          hilog.warn(DOMAIN, TAG, 'net register failed: %{public}d', error.code);
        }
      });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Failed to register netAvailable listener');
    }
  }

  aboutToDisappear(): void {
    // 组件销毁前清理定时器，避免内存泄漏和无效回调
    this.clearLoadTimeout();
    // 清理「长按可拖动」提示的定时器
    if (this.refreshHintTimer !== -1) {
      clearTimeout(this.refreshHintTimer);
      this.refreshHintTimer = -1;
    }
    // 取消避让区监听
    try {
      const handler: ((data: window.AvoidAreaOptions) => void) | null = this.avoidAreaHandler;
      if (handler) {
        const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
        window.getLastWindow(ctx).then((win: window.Window) => {
          win.off('avoidAreaChange', handler);
        }).catch(() => {
        });
        this.avoidAreaHandler = null;
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'avoid area unregister failed');
    }
    // 取消网络监听，避免内存泄漏
    try {
      if (this.netConnection) {
        this.netConnection.unregister((error: BusinessError) => {
          if (error) {
            hilog.warn(DOMAIN, TAG, 'net unregister failed: %{public}d', error.code);
          }
        });
        this.netConnection = null;
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Failed to unregister netAvailable listener');
    }
  }

  // 网络连接对象：用于订阅网络状态变化（NetworkKit NetConnection）
  private netConnection: connection.NetConnection | null = null;

  // 网络恢复回调：仅在当前显示错误页时自动重新加载，避免打断正常浏览
  private onNetAvailable: (data: connection.NetHandle) => void = (data: connection.NetHandle): void => {
    hilog.info(DOMAIN, TAG, 'Network available, netId=%{public}d', data.netId);
    if (this.isError) {
      hilog.info(DOMAIN, TAG, 'Auto reload after network recovery');
      this.refreshPage();
    }
  };

  /**
   * 状态栏样式不再由应用设置 —— 窗口已完全交由系统管理（非沉浸式），
   * 状态栏与标题栏均由系统按官方规范绘制，深浅色也由系统自动适配。
   */

  build() {
    Column() {
      Stack({ alignContent: Alignment.Top }) {
        Web({ src: this.initialUrl, controller: this.controller })
          .domStorageAccess(true)
          .javaScriptAccess(true)
          // fileAccess 必须为 true：自 API 12 起该属性默认值为 false，
          // 而拍照上传路径（handleTakePhoto → cameraPicker）返回的是应用沙箱内的
          // file:// URI，Web 需要文件系统访问权限才能读取并上传该文件。
          // 关闭该项会导致「拍照」上传失败，请勿"安全优化"为 false。
          .fileAccess(true)
          .mixedMode(MixedMode.None)  // 官方安全默认：禁止加载 HTTP/HTTPS 混合内容
          .imageAccess(true)
          .zoomAccess(true)
          .darkMode(2)  // WebDarkMode.Auto: 跟随系统深色模式，传递 prefers-color-scheme 给网页
          .backgroundColor($r('app.color.web_background'))
          .width('100%')
          .height('100%')
          .onControllerAttached(() => {
            try {
              const customUA: string = this.controller.getUserAgent() + ' DeepSeek-HarmonyOS/1.0';
              this.controller.setCustomUserAgent(customUA);
            } catch (err) {
              hilog.error(DOMAIN, TAG, 'Failed to set user agent');
            }
            this.setupDownloadDelegate();
            this.controllerReady = true;
          })
          .onPageBegin((event) => {
            this.isLoading = true;
            this.isError = false;
            this.isNetworkError = false;
            this.startLoadTimeout();
            // 在页面加载最早时机注入系统语言覆盖。
            // 说明：曾改用 Web 组件的 javaScriptOnDocumentStart 做"文档开始前"注入，
            // 但真机实测该属性对首次加载不生效（注入标记位始终为 undefined），
            // 遂保留此运行时注入路径，避免功能整体失效。
            this.injectLanguageOverride();
          })
          .onProgressChange((event) => {
            if (event) {
              this.loadingProgress = event.newProgress;
            }
          })
          .onPageEnd(() => {
            this.isLoading = false;
            this.clearLoadTimeout();
            // 控制器就绪前被推迟的 DeepLink 在此补导航。
            // 不能放在 onControllerAttached —— 那里会和组件的初始 src 加载相互覆盖。
            if (this.pendingDeepLink !== '') {
              const deferred: string = this.pendingDeepLink;
              this.pendingDeepLink = '';
              hilog.info(DOMAIN, TAG, 'Flushing deferred DeepLink navigation');
              this.navigateToUrl(deferred);
            }
            // 每次页面加载完成后注入剪贴板拦截脚本
            this.injectShareInterceptor();
            this.updateBackButtonState();
          })
          .onErrorReceive((event) => {
            if (event && event.error && event.error.getErrorCode() !== 0) {
              hilog.warn(DOMAIN, TAG, 'WebView net err: code=%{public}d, info=%{public}s',
                event.error.getErrorCode(), event.error.getErrorInfo());
              // 仅主框架的导航错误才触发错误页（过滤子资源错误）
              if (event.request && event.request.isMainFrame() && !this.checkNetworkAvailable()) {
                this.isNetworkError = true;
                this.isError = true;
                this.isLoading = false;
                this.clearLoadTimeout();
              }
            }
          })
          .onHttpErrorReceive((event) => {
            if (event && event.response) {
              const statusCode: number = event.response.getResponseCode();
              // 仅主框架的 HTTP 错误才触发错误页（过滤子资源如 API、图片等返回的 404/500）
              const isMainFrame: boolean = event.request ? event.request.isMainFrame() : false;
              if (statusCode >= 400 && isMainFrame) {
                hilog.error(DOMAIN, TAG, 'HTTP error: %{public}d', statusCode);
                // 先检测网络状态，再决定错误类型
                this.isNetworkError = !this.checkNetworkAvailable();
                this.isError = true;
                this.isLoading = false;
                this.clearLoadTimeout();
              } else {
                hilog.warn(DOMAIN, TAG, 'HTTP non-error status: %{public}d, mainFrame=%{public}s',
                  statusCode, String(isMainFrame));
              }
            }
          })
          .onRenderExited((event) => {
            if (event && event.renderExitReason === 2) {
              hilog.error(DOMAIN, TAG, 'Render crashed, reloading...');
              try {
                this.controller.refresh();
              } catch (err) {
                hilog.error(DOMAIN, TAG, 'Failed to refresh after crash');
              }
            }
          })
          .onShowFileSelector((event) => {
            if (!event) {
              return false;
            }
            // 仅在 chat.deepseek.com 域名下弹出上传模态框
            try {
              const pageUrl: string = this.controller.getUrl();
              const isChatDeepSeek: boolean = url.URL.parseURL(pageUrl).hostname === DEEPSEEK_HOST;
              if (!isChatDeepSeek) {
                event.result.handleFileList([]);
                return true;
              }
            } catch (err) {
              event.result.handleFileList([]);
              return true;
            }
            // 存储 FileSelectorResult，弹出上传方式选择模态框供用户选择
            this.pendingFileListHandler = (fileList: Array<string>) => {
              event.result.handleFileList(fileList);
            };
            this.showUploadModal = true;
            return true;
          })
          .onLoadIntercept((event) => {
            if (!event) {
              return false;
            }
            const requestUrl: string = event.data.getRequestUrl();
            // share://?url=... 由 JS 注入触发，直接唤起系统分享
            const shareScheme: string = 'share://?url=';
            if (requestUrl.startsWith(shareScheme)) {
              const shareUrl: string = decodeURIComponent(requestUrl.substring(shareScheme.length));
              this.triggerShare(shareUrl);
              return true;
            }
            if (requestUrl.startsWith('intent://share')) {
              this.shareCurrentPage();
              return true;
            }
            // 非 DeepSeek 域名的页面跳转：仅拦截主框架导航，放行子请求（下载/资源等）
            if (!isDeepSeekDomain(requestUrl) && event.data.isMainFrame()
              && !isDownloadUrl(requestUrl)) {
              this.openInSystemBrowser(requestUrl);
              return true;
            }
            return false;
          })

        // 窗口拖动不再由应用自绘手柄承担 —— 窗口已完全交由系统管理（非沉浸式），
        // 系统标题栏即拖动区，且不自绘任何窗口部件。

        if (this.isLoading) {
          PageProgress({ progress: this.loadingProgress })
        }

        // 2in1 返回按钮：非 DeepSeek 域名且有回退历史时，左上角显示方形返回按钮
        if (this.showBackButton) {
          Button() {
            Text('←')
              .fontSize(20)
              .fontColor($r('app.color.text_primary'))
          }
          .width(36)
          .height(36)
          .type(ButtonType.Normal)
          .borderRadius(8)
          .backgroundColor($r('app.color.floating_button_bg'))
          .position({ x: 36, y: 36 })
          .shadow({
            radius: 8,
            color: $r('app.color.floating_button_shadow'),
            offsetX: 0,
            offsetY: 2
          })
          .onClick(() => {
            try {
              this.controller.backward();
              this.updateBackButtonState();
            } catch (err) {
              hilog.error(DOMAIN, TAG, 'backward failed');
            }
          })
          .zIndex(12)
        }

        if (this.isError) {
          ErrorView({
            isNetworkError: this.isNetworkError,
            onRetry: () => this.onErrorRetry()
          })
        }

        // 上传方式选择模态框
        if (this.showUploadModal) {
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
                .onClick(() => this.handleTakePhoto())

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
                .onClick(() => this.handlePickFromAlbum())

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
                .onClick(() => this.handlePickFile())
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
            .onClick(() => {})
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor($r('app.color.modal_scrim'))
          .onClick(() => this.dismissUploadModal())
          .zIndex(100)
        }

        // 首次启动的「长按可拖动」提示：位于操作条正上方、水平居中对齐，
        // 6 秒后自动收起，用户长按进入拖拽时也会立即收起。只在首次启动提示一次。
        if (this.showRefreshHint && this.refreshButtonEnabled) {
          Text($r('app.string.refresh_drag_hint'))
            .fontSize(13)
            .fontColor($r('app.color.text_on_accent'))
            .backgroundColor($r('app.color.accent'))
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(14)
            .position({ x: '100%', y: '100%' })
            // 锚点取下边缘中点：这样 translate 给出的就是气泡「底边中心」的位置，
            // 与操作条的水平中心对齐，气泡整体落在条的上方。
            .markAnchor({ x: '50%', y: '100%' })
            .translate({
              // 水平：与操作条中心对齐（条右边缘在 pageW - BTN_MARGIN + btnDragX，
              // 再左移半个条宽即为中心）
              x: -this.BTN_MARGIN + this.btnDragX - this.btnBarWidth() / 2,
              // 垂直：条顶边再上移 8vp（条的顶边 = 基准位置 - 条高 - 键盘避让抬高）
              y: -this.BTN_MARGIN + this.btnDragY - this.keyboardLiftVp() - this.BTN_SIZE - 8
            })
            .zIndex(102)
            .onClick(() => this.dismissRefreshHint())
        }

        // 右下角悬浮操作条：刷新 + 设置合并为一个圆角矩形。
        // 早先是两个独立圆形按钮，拖动后容易相互重叠；合并成一条后两者的相对位置固定，
        // 也不会各自与网页右下角的内容争抢空间。长按整条可拖动，松手停留、位置持久化。
        Row() {
          // 刷新：一键重新加载网页（可在设置面板中关闭）
          if (this.refreshButtonEnabled) {
            Row() {
              Text('↻')
                .fontSize(22)
                .fontColor($r('app.color.text_primary'))
            }
            .layoutWeight(1)
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .onClick(() => {
              if (this.btnSuppressClick) {
                // 本次是长按拖拽的抬手，不当作刷新
                this.btnSuppressClick = false;
                return;
              }
              // 刷新会丢弃未提交的输入，先征求确认；
              // 用户勾选过「不再显示」则直接刷新，不再打扰。
              if (this.refreshSkipConfirm) {
                this.doRefresh();
              } else {
                this.noMoreRefreshPrompt = false;
                this.showRefreshConfirm();
              }
            })

            Divider()
              .vertical(true)
              .height(20)
              .color($r('app.color.drag_indicator'))
          }

          // 设置：采用官方符号 gearshape（系统资源码位 0xF0020，线性齿轮）
          Row() {
            SymbolGlyph($r('sys.symbol.gearshape'))
              .fontSize(20)
              .fontColor([$r('app.color.text_primary')])
          }
          .layoutWeight(1)
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.showSettings = true;
          })
        }
        .width(this.btnBarWidth())
        .height(this.BTN_SIZE)
        .borderRadius(this.BTN_SIZE / 2)
        // 长按进入拖动态时给出高亮：底色提亮 + 阴影加深 + 整体放大
        .backgroundColor(this.btnDragging
          ? $r('app.color.floating_button_bg_active')
          : $r('app.color.floating_button_bg'))
        .shadow({
          radius: this.btnDragging ? 20 : 12,
          color: $r('app.color.floating_button_shadow'),
          offsetY: this.btnDragging ? 8 : 4
        })
        .scale({ x: this.btnDragging ? 1.12 : 1, y: this.btnDragging ? 1.12 : 1 })
        // animation 作用于「它之前声明的所有属性」，因此上面这些视觉属性会平滑过渡。
        // 务必把 .translate 放在它之后 —— 位置不参与动画，拖动才能完全跟手；
        // 若把 translate 写在 animation 之前，位移会被套上缓动，手感发飘、迟滞。
        .animation({ duration: 150, curve: Curve.FastOutSlowIn })
        .position({ x: '100%', y: '100%' })
        .markAnchor({ x: '100%', y: '100%' })
        .translate({
          // 基础位置：距右下角 BTN_MARGIN；再加上用户拖拽的位移；
          // 键盘确实遮挡时才按需抬高（不遮挡则完全不移动）。
          // 位于 .animation 之后 → 不参与动画 → 跟手无延迟。
          x: -this.BTN_MARGIN + this.btnDragX,
          y: -this.BTN_MARGIN + this.btnDragY - this.keyboardLiftVp()
        })
        // 每次新的触摸都重置「本次不刷新」标记
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.btnSuppressClick = false;
          }
        })
        // 长按后拖动：官方手势组合。用「长按 → 拖动」序列把拖拽与单击区分开，
        // 避免普通点击被误判为拖动。
        .gesture(
          GestureGroup(GestureMode.Sequence,
            LongPressGesture({ repeat: false, duration: 400 })
              .onAction(() => {
                // 先把当前的键盘避让量固化进 btnDragY（此刻 btnDragging 仍为 false，
                // keyboardLiftVp 还能算出真实值），使按钮在进入拖动瞬间保持原位、不跳动；
                // 随后 btnDragging 置 true，拖动全程不再参与避让，完全跟手。
                this.btnDragY = this.btnDragY - this.keyboardLiftVp();
                // 进入拖拽模式：给出视觉反馈，抑制随后的点击，并收起首次提示
                this.btnDragging = true;
                this.btnSuppressClick = true;
                this.dismissRefreshHint();
              })
              .onActionEnd(() => {
                this.btnDragging = false;
              })
              .onActionCancel(() => {
                this.btnDragging = false;
              }),
            PanGesture({ fingers: 1, direction: PanDirection.All, distance: 1 })
              .onActionStart(() => {
                this.btnDragBaseX = this.btnDragX;
                this.btnDragBaseY = this.btnDragY;
              })
              .onActionUpdate((event: GestureEvent) => {
                this.btnDragX = this.btnDragBaseX + event.offsetX;
                this.btnDragY = this.btnDragBaseY + event.offsetY;
                // 拖动过程中就做边界限制，使按钮到窗口边缘即停住，
                // 而不是拖出去、松手才弹回来
                this.clampBtnOffset();
              })
              .onActionEnd(() => {
                this.btnDragging = false;
                // 限制在屏幕内，并记住位置
                this.clampBtnOffset();
                this.saveButtonOffset();
                hilog.info(DOMAIN, TAG, 'Floating bar moved to (%{public}d, %{public}d)',
                  this.btnDragX, this.btnDragY);
              })
          )
        )
        .zIndex(101)
      }
      .width('100%')
      .layoutWeight(1)
      // 记录刷新按钮实际可用的坐标空间（Stack 才是按钮 100% 定位的参照），
      // 用于把按钮限制在窗口内；非全屏（悬浮窗/自由多窗）时这里就是应用窗口的尺寸。
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        this.pageW = newValue.width as number;
        this.pageH = newValue.height as number;
        this.clampBtnOffset();
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.web_background'))
    // 顶部按状态栏避让高度补 padding —— 底部保持 0，内容自然延伸到透明的手势导航条之下，
    // 即「顶部正常状态栏 + 底部沉浸」。详见 setupKeyboardAvoid 的说明。
    .padding({ top: this.statusBarHeightVp, bottom: 0 })
    // 设置面板：官方半模态组件 bindSheet。
    // 手机端用 CONTENT_COVER（全屏覆盖），平板/2in1 等大屏用 CENTER（屏幕中间独立窗口），
    // 这是官方对「大屏居中、小屏全屏」的标准处理方式。
    .bindSheet($$this.showSettings, this.settingsSheet(), {
      preferType: deviceInfo.deviceType === 'phone'
        ? SheetType.CONTENT_COVER : SheetType.CENTER,
      backgroundColor: $r('app.color.surface_card'),
      // 标题栏与关闭按钮一律自绘（见 settingsSheet 内的标题栏）。因此这里：
      //   · 不设 title      —— 避免与自绘标题重复；
      //   · showClose=false —— CENTER（平板）形态系统默认会渲染一颗关闭按钮，
      //                        不关掉就会与自绘的那颗叠在同一位置。
      // 手机端 CONTENT_COVER 形态系统本来就不渲染标题栏，自绘是唯一可行方案。
      showClose: false,
      onDisappear: () => {
        this.showSettings = false;
      }
    })
  }

  /** 错误页「重新加载」：清除错误状态并刷新当前页 */
  private onErrorRetry(): void {
    this.isError = false;
    this.isNetworkError = false;
    this.refreshPage();
  }

  onPageShow(): void {
    if (this.deepLinkUrl && this.deepLinkUrl !== '') {
      this.navigateToUrl(this.deepLinkUrl);
      AppStorage.set<string>('deepLinkUrl', '');
    }
  }

  // 响应热启动时 onNewWant 设置的 deepLinkUrl 变化（onPageShow 仅在冷/温启动触发）
  onDeepLinkChange(): void {
    if (this.deepLinkUrl && this.deepLinkUrl !== '') {
      hilog.info(DOMAIN, TAG, 'DeepLink change detected: %{private}s', this.deepLinkUrl);
      this.navigateToUrl(this.deepLinkUrl);
      AppStorage.set<string>('deepLinkUrl', '');
    }
  }

  onBackPress(): boolean {
    // 上传模态框打开时，优先关闭模态框，避免返回手势直接退出应用
    if (this.showUploadModal) {
      this.dismissUploadModal();
      return true;
    }
    try {
      if (this.controller.accessBackward()) {
        this.controller.backward();
        this.updateBackButtonState();
        return true;
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'onBackPress failed');
    }
    this.showBackButton = false;
    return false;
  }

  private startLoadTimeout(): void {
    this.clearLoadTimeout();
    this.pageLoadTimer = setTimeout(() => {
      hilog.error(DOMAIN, TAG, 'Page load timeout after %{public}d ms', this.LOAD_TIMEOUT_MS);
      this.isLoading = false;
      // 超时时检测网络：无网络则为网络错误，有网络则为加载失败
      this.isNetworkError = !this.checkNetworkAvailable();
      this.isError = true;
    }, this.LOAD_TIMEOUT_MS);
  }

  private clearLoadTimeout(): void {
    if (this.pageLoadTimer !== -1) {
      clearTimeout(this.pageLoadTimer);
      this.pageLoadTimer = -1;
    }
  }

  // 检测当前网络是否可用（基于系统网络管理 API）
  private checkNetworkAvailable(): boolean {
    try {
      // 1. 检查是否有默认激活的数据网络
      if (!connection.hasDefaultNetSync()) {
        hilog.info(DOMAIN, TAG, 'No default network');
        return false;
      }
      // 2. 获取默认网络句柄
      const netHandle = connection.getDefaultNetSync();
      if (!netHandle || netHandle.netId === 0) {
        hilog.info(DOMAIN, TAG, 'Default netId is 0');
        return false;
      }
      // 3. 验证网络是否通过互联网可达性验证
      const netCapabilities = connection.getNetCapabilitiesSync(netHandle);
      const caps: Array<connection.NetCap> = netCapabilities.networkCap || [];
      const isValidated = caps.includes(connection.NetCap.NET_CAPABILITY_VALIDATED);
      hilog.info(DOMAIN, TAG, 'Network available: %{public}s', String(isValidated));
      return isValidated;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'checkNetworkAvailable failed');
      // 异常时保守认定为无网络
      return false;
    }
  }

  // 注入 JS 覆写 navigator.clipboard.writeText：拦截 DeepSeek 分享链接转为系统分享
  private injectShareInterceptor(): void {
    try {
      this.controller.runJavaScript(`
        (function() {
          if (window.__deepseekShareHooked) return;
          window.__deepseekShareHooked = true;
          var PREFIX = 'https://${DEEPSEEK_HOST}/share/';
          if (navigator.clipboard && navigator.clipboard.writeText) {
            var _orig = navigator.clipboard.writeText.bind(navigator.clipboard);
            navigator.clipboard.writeText = function(text) {
              if (typeof text === 'string' && text.indexOf(PREFIX) === 0) {
                window.location.href = 'share://?url=' + encodeURIComponent(text);
                return Promise.resolve();
              }
              return _orig(text);
            };
          }
        })();
      `);
    } catch (err) {
      // JS 注入可能在受限页面失败，静默忽略
    }
  }

  // 读取当前系统语言并规范化为 BCP 47（规范化规则见 common/LanguageUtil.toBCP47）
  private getBCP47Language(): string {
    try {
      return toBCP47(this.systemLanguage || i18n.System.getSystemLanguage());
    } catch (err) {
      return 'en';
    }
  }

  /**
   * 生成语言覆盖脚本（覆盖 navigator.language / navigator.languages）。
   *
   * 注意：这里是字符串拼装 JS，因此对语言标识做白名单过滤，避免拼出意外语句。
   */
  private buildLanguageScript(): string {
    const bcp47Lang: string = this.getBCP47Language();
    const safeLang: string = bcp47Lang.replace(/[^A-Za-z0-9-]/g, '');
    return `(function () {
      var lang = '${safeLang}';
      // 注入标记：供自检确认"文档开始前注入"确实执行过（与分享拦截的
      // __deepseekShareHooked 同一思路），不参与业务逻辑。
      window.__deepseekLangInjected = lang;
      Object.defineProperty(Object.getPrototypeOf(navigator), 'language', {
        get: function () { return lang; },
        configurable: true
      });
      Object.defineProperty(Object.getPrototypeOf(navigator), 'languages', {
        get: function () { return [lang]; },
        configurable: true
      });
    })();`;
  }

  /**
   * 运行时语言切换：向「当前已加载的文档」补注入一次覆盖。
   *
   * 真机实测：注入后页面界面会随之自动更新，无需用户手动刷新。
   * （原注释曾断言「已渲染的文案不会因此改变、需手动刷新」，实测不成立。）
   */
  private injectLanguageOverride(): void {
    const bcp47Lang: string = this.getBCP47Language();
    hilog.info(DOMAIN, TAG, 'Re-injecting language into current document: %{public}s', bcp47Lang);
    try {
      this.controller.runJavaScript(this.buildLanguageScript());
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Failed to inject language override');
    }
  }

  // 系统语言变化时，重新注入 JS 覆盖 navigator.language。
  // 实测页面会随之自动更新，无需手动刷新；右下角的刷新按钮是通用刷新入口，
  // 与语言切换无关。
  onSystemLanguageChange(): void {
    if (this.systemLanguage && this.systemLanguage !== '') {
      hilog.info(DOMAIN, TAG, 'System language changed, re-injecting language override');
      this.injectLanguageOverride();
    }
  }

  // 统一分享入口：唤起系统分享面板
  private triggerShare(url: string): void {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const resMgr: resourceManager.ResourceManager = context.resourceManager;
      const description: string = resMgr.getStringSync($r('app.string.share_description').id);
      const contentPrefix: string = resMgr.getStringSync($r('app.string.share_content_prefix').id);
      const shareData = new systemShare.SharedData({
        utd: utd.UniformDataType.HYPERLINK,
        content: url,
        title: 'DeepSeek',
        description: description
      });
      shareData.addRecord({
        utd: utd.UniformDataType.PLAIN_TEXT,
        content: contentPrefix + ':\n' + url
      });
      const shareController = new systemShare.ShareController(shareData);
      shareController.on('dismiss', () => {
        hilog.info(DOMAIN, TAG, 'Share dismissed');
      });
      shareController.show(context, {
        previewMode: systemShare.SharePreviewMode.DETAIL,
        selectionMode: systemShare.SelectionMode.SINGLE
      }).catch((err: BusinessError) => {
        hilog.error(DOMAIN, TAG, 'Share failed: %{public}s', err.message);
      });
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Share error');
    }
  }

  // 分享当前页面 URL：获取 WebView 当前 URL 后唤起系统分享
  private shareCurrentPage(): void {
    try {
      let currentUrl: string = DEEPSEEK_URL;
      try {
        const webUrl: string = this.controller.getUrl();
        if (webUrl && webUrl !== '') {
          currentUrl = webUrl;
        }
      } catch (e) {
        // fallback to default URL
      }
      this.triggerShare(currentUrl);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Share error');
    }
  }

  // 更新 2in1 返回按钮显示状态：仅 PC 设备 + 有回退历史 + 当前页非 chat.deepseek.com 时显示
  private updateBackButtonState(): void {
    if (!this.isPC) {
      this.showBackButton = false;
      return;
    }
    try {
      const hasHistory: boolean = this.controller.accessBackward();
      if (!hasHistory) {
        this.showBackButton = false;
        return;
      }
      const pageUrl: string = this.controller.getUrl();
      if (pageUrl === '') {
        this.showBackButton = false;
        return;
      }
      const isChatDeepSeek: boolean = url.URL.parseURL(pageUrl).hostname === DEEPSEEK_HOST;
      this.showBackButton = !isChatDeepSeek;
    } catch (err) {
      this.showBackButton = false;
    }
  }

  /**
   * 打开外部链接。**先弹确认框，用户点「同意」后才跳转** ——
   * 跳浏览器会把应用切到后台、打断当前操作，属于需要用户明确同意的行为。
   *
   * 同意后走官方高层接口 openLink（@since 12）：
   *   · 先走 App Linking 匹配已注册该域名的应用；
   *   · appLinkingOnly 传 false（默认值），未匹配到时自动回退到 Deep Linking，
   *     由系统选定浏览器打开 —— 这正是「请求打开浏览器」的官方做法；
   *   · hideFailureTipDialog 传 true，避免无匹配应用时再弹一次系统提示框，
   *     失败改由我们自己的 toast 兜底。
   */
  private openInSystemBrowser(openUrl: string): void {
    try {
      this.getUIContext().getPromptAction().showDialog({
        title: $r('app.string.browser_confirm_title'),
        message: $r('app.string.browser_confirm_message'),
        buttons: [
          { text: $r('app.string.common_cancel'), color: $r('app.color.text_button_secondary') },
          { text: $r('app.string.common_agree'), color: $r('app.color.accent') }
        ]
      }).then((result: promptAction.ShowDialogSuccessResponse) => {
        // 按钮顺序为 [取消, 同意]，index 1 才是同意
        if (result.index === 1) {
          this.doOpenInBrowser(openUrl);
        } else {
          hilog.info(DOMAIN, TAG, 'User declined to open external link');
        }
      }).catch((err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'showDialog failed: %{public}d', err.code);
      });
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to show confirm dialog');
    }
  }

  // 用户同意后实际执行跳转
  private doOpenInBrowser(openUrl: string): void {
    let context: common.UIAbilityContext;
    try {
      context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to get ability context');
      return;
    }

    context.openLink(openUrl, { appLinkingOnly: false, hideFailureTipDialog: true })
      .then(() => {
        hilog.info(DOMAIN, TAG, 'openLink succeeded');
      })
      .catch((err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'openLink failed (%{public}d), fallback to startAbility', err.code);
        this.openViaStartAbility(context, openUrl);
      });
  }

  // openLink 的降级路径：经典 Want 方式，最稳妥
  private openViaStartAbility(context: common.UIAbilityContext, openUrl: string): void {
    try {
      const want: Want = {
        action: 'ohos.want.action.viewData',
        entities: ['entity.system.browsable'],
        uri: openUrl
      };
      context.startAbility(want).catch((err: BusinessError) => {
        hilog.error(DOMAIN, TAG, 'Failed to open system browser: %{public}s', err.message);
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.toast_external_link'), duration: 2000 });
      });
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'openViaStartAbility error');
    }
  }

  // 导航到指定 URL（用于 DeepLink 跳转）
  private navigateToUrl(url: string): void {
    // 冷启动时 onPageShow 早于 Web 的 onControllerAttached（真机实测相差约 35ms），
    // 此刻 loadUrl 必抛 "The WebviewController must be associated with a Web component"。
    // 原先直接失败并丢弃链接，导致冷启动分享链接 100% 打不开。故先暂存，待控制器挂载后补导航。
    if (!this.controllerReady) {
      this.pendingDeepLink = url;
      hilog.info(DOMAIN, TAG, 'Controller not attached yet, deferring DeepLink navigation');
      return;
    }
    try {
      this.controller.loadUrl(url);
      this.isError = false;
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'navigateToUrl failed: code=%{public}d, msg=%{public}s', e.code, e.message);
    }
  }

  /**
   * 订阅窗口避让区变化，分别记录状态栏高度与键盘高度。
   *
   * 底部沉浸（setWindowLayoutFullScreen(true)）让布局延伸到系统栏区域，
   * 因此：
   *   · 顶部需要按状态栏高度（TYPE_SYSTEM.topRect）补 padding，保持「正常状态栏」观感；
   *   · 底部 padding 保持 0，内容自然铺到屏幕最底部、延伸到透明的手势导航条之下；
   *   · 键盘是浮层、不改变窗口尺寸，需单独把右下角刷新按钮抬高，否则会被遮挡。
   * 避让区单位均为 px（SDK 说明），统一换算为 vp。
   */
  private setupKeyboardAvoid(): void {
    this.avoidAreaHandler = (data: window.AvoidAreaOptions) => {
      if (data.type === window.AvoidAreaType.TYPE_SYSTEM) {
        const topPx: number = data.area.visible ? data.area.topRect.height : 0;
        const topVp: number = topPx > 0 ? this.getUIContext().px2vp(topPx) : 0;
        if (topVp !== this.statusBarHeightVp) {
          this.statusBarHeightVp = topVp;
          hilog.info(DOMAIN, TAG, 'Status bar height: %{public}d px -> %{public}d vp', topPx, topVp);
        }
        return;
      }
      if (data.type !== window.AvoidAreaType.TYPE_KEYBOARD) {
        return;
      }
      const px: number = data.area.visible ? data.area.bottomRect.height : 0;
      const vp: number = px > 0 ? this.getUIContext().px2vp(px) : 0;
      if (vp !== this.keyboardHeightVp) {
        this.keyboardHeightVp = vp;
        hilog.info(DOMAIN, TAG, 'Keyboard avoid height: %{public}d px -> %{public}d vp', px, vp);
        // 键盘高度变化会改变按钮的可用范围，重新做一次边界限制
        this.clampBtnOffset();
      }
    };
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      window.getLastWindow(ctx).then((win: window.Window) => {
        // 先取一次初始值：监听只在变化时回调，启动时不会触发
        try {
          const sysArea: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
          this.statusBarHeightVp = this.getUIContext().px2vp(sysArea.topRect.height);
        } catch (err) {
          hilog.warn(DOMAIN, TAG, 'getWindowAvoidArea failed');
        }
        if (this.avoidAreaHandler) {
          win.on('avoidAreaChange', this.avoidAreaHandler);
        }
      }).catch(() => {
        hilog.warn(DOMAIN, TAG, 'getLastWindow failed for avoid area');
      });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'setupKeyboardAvoid exception');
    }
  }

  /**
   * 恢复刷新按钮上次被拖到的位置；若是首次启动，展示一次「长按可拖动」提示。
   * 存储读写失败都不影响使用，只是回到默认位置 / 不再提示。
   */
  private restoreRefreshButtonPrefs(): void {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const offset: number[] = loadRefreshButtonOffset(ctx);
      if (offset.length === 2) {
        this.btnDragX = offset[0];
        this.btnDragY = offset[1];
      }
      this.refreshButtonEnabled = isRefreshButtonEnabled(ctx);
      this.refreshSkipConfirm = isRefreshConfirmSkipped(ctx);
      if (!isRefreshHintShown(ctx)) {
        this.showRefreshHint = true;
        markRefreshHintShown(ctx);
        hilog.info(DOMAIN, TAG, 'Showing long-press hint for the first launch');
        // 6 秒后自动收起
        this.refreshHintTimer = setTimeout(() => {
          this.showRefreshHint = false;
          this.refreshHintTimer = -1;
        }, 6000);
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Failed to restore refresh button prefs');
    }
  }

  /**
   * 键盘实际遮挡刷新按钮时所需的抬高量（vp）；不遮挡返回 0，即完全不移动。
   *
   * 键盘浮在页面底部、占据下方 keyboardHeightVp；按钮底边（未避让时）位于
   * pageH - BTN_MARGIN + btnDragY。只有底边低于键盘上沿才算被遮挡，此时抬高到
   * 键盘上沿之上并保留 BTN_MARGIN 间距 —— 位移刚好够露出按钮，而不是无条件
   * 上移整个键盘高度（按钮本来就高于键盘时不应有任何动作）。
   *
   * **拖动过程中必须返回 0**：避让量本身是由 btnDragY 推导出来的，若拖动时仍参与
   * 计算，会得到恒等式「渲染位置 = -(BTN_MARGIN + 键盘高)」—— btnDragY 被完全抵消，
   * 表现为键盘弹起后按钮怎么拖都不动。进入拖动前已把当时的避让量固化进 btnDragY
   *（见 LongPressGesture.onAction），因此这里返回 0 不会造成跳动。
   */
  private keyboardLiftVp(): number {
    if (this.btnDragging || this.keyboardHeightVp <= 0 || this.pageH <= 0) {
      return 0;
    }
    const btnBottom: number = this.pageH - this.BTN_MARGIN + this.btnDragY;
    const keyboardTop: number = this.pageH - this.keyboardHeightVp;
    if (btnBottom <= keyboardTop) {
      return 0;
    }
    return btnBottom - keyboardTop + this.BTN_MARGIN;
  }

  // 悬浮操作条宽度：刷新可用时为两段（刷新 | 设置），关闭刷新后只剩设置一段
  private btnBarWidth(): number {
    return this.refreshButtonEnabled ? this.BTN_SIZE * 2 + 8 : this.BTN_SIZE;
  }

  /**
   * 把刷新按钮的拖拽位移限制在屏幕内，避免拖出可视区域后找不回来。
   * 按钮右下角位于 (pageW - BTN_MARGIN + dx, pageH - BTN_MARGIN + dy)，
   * 横向占用 btnBarWidth()、纵向占用 BTN_SIZE，据此反推位移的可用范围。
   * 键盘遮挡不在这里预留 —— 那是 keyboardLiftVp 的职责，避免重复抬高。
   */
  private clampBtnOffset(): void {
    if (this.pageW <= 0 || this.pageH <= 0) {
      return;
    }
    const barW: number = this.btnBarWidth();
    const maxDx: number = this.BTN_MARGIN;
    const minDx: number = -(this.pageW - barW - this.BTN_MARGIN);
    const maxDy: number = this.BTN_MARGIN;
    const minDy: number = -(this.pageH - this.BTN_SIZE - this.BTN_MARGIN);
    this.btnDragX = Math.min(maxDx, Math.max(minDx, this.btnDragX));
    this.btnDragY = Math.min(maxDy, Math.max(minDy, this.btnDragY));
  }

  // 收起「长按可拖动」提示
  private dismissRefreshHint(): void {
    this.showRefreshHint = false;
    if (this.refreshHintTimer !== -1) {
      clearTimeout(this.refreshHintTimer);
      this.refreshHintTimer = -1;
    }
  }

  // 保存刷新按钮位置（拖动结束时调用）
  private saveButtonOffset(): void {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      saveRefreshButtonOffset(ctx, this.btnDragX, this.btnDragY);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Failed to save refresh button offset');
    }
  }

  /**
   * 刷新确认弹窗控制器。
   *
   * 官方确认框（promptAction.showDialog）不支持内嵌勾选框，因此按官方推荐做法
   * 用 @CustomDialog 自定义弹窗内容（见 components/RefreshConfirmDialog.ets），
   * 内部用官方 Checkbox 组件实现「不再显示」。
   *
   * customStyle 保持默认 false：由框架提供弹窗容器（含圆角与背景），
   * 组件只负责内部内容，尺寸最稳妥。
   */
  private refreshConfirmDialog: CustomDialogController = new CustomDialogController({
    builder: RefreshConfirmDialog({
      noMore: $noMoreRefreshPrompt,
      onConfirm: (noMore: boolean) => {
        this.onRefreshConfirmed(noMore);
      },
      onCancel: () => {
        // 取消：仅关闭弹窗，不做其它处理
      }
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center
  });

  // 弹出刷新确认框（调用方已确认用户没有勾选过「不再显示」）
  private showRefreshConfirm(): void {
    this.noMoreRefreshPrompt = false;
    try {
      this.refreshConfirmDialog.open();
      hilog.info(DOMAIN, TAG, 'Refresh confirm dialog opened');
    } catch (err) {
      // 弹窗失败不能让刷新功能不可用：直接刷新
      hilog.warn(DOMAIN, TAG, 'Failed to open refresh confirm dialog, refresh directly');
      this.doRefresh();
    }
  }

  // 关闭刷新确认框（供需要程序化关闭的场景使用；按钮点击由弹窗组件自行关闭）
  private closeRefreshConfirm(): void {
    try {
      this.refreshConfirmDialog.close();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Failed to close refresh confirm dialog');
    }
  }

  // 用户点「继续刷新」：弹窗此时已自行关闭；若勾选了「不再显示」则持久化，随后执行刷新
  private onRefreshConfirmed(noMore: boolean): void {
    if (noMore && !this.refreshSkipConfirm) {
      this.refreshSkipConfirm = true;
      try {
        const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
        setRefreshConfirmSkipped(ctx, true);
        hilog.info(DOMAIN, TAG, 'Refresh confirm disabled by user');
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'Failed to persist refresh confirm skipped flag');
      }
    }
    this.doRefresh();
  }

  // 实际执行刷新
  private doRefresh(): void {
    try {
      this.controller.refresh();
      hilog.info(DOMAIN, TAG, 'Page refreshed');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Refresh failed');
    }
  }

  /**
   * 设置面板内容。
   * 用官方组件（Toggle / Divider）与项目既有的语义化颜色资源，
   * 深浅色由资源限定词自动适配，与页面其它部分风格一致。
   */
  @Builder
  settingsSheet() {
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
        // 关闭：官方符号 xmark（系统资源码位 0xF0056），外面套一个圆形浅底并加阴影，
        // 与系统半模态自带的关闭按钮观感一致（系统那颗也是「圆形浅底 + 叉」）。
        // 用 Row 包一层是为了确保符号在圆内居中，SymbolGlyph 直接设宽高不保证居中。
        Row() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(16)
            .fontColor([$r('app.color.text_secondary')])
        }
        .width(36)
        .height(36)
        .borderRadius(18)
        .backgroundColor($r('app.color.surface_tile'))
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .shadow({
          radius: 8,
          color: $r('app.color.floating_button_shadow'),
          offsetX: 0,
          offsetY: 2
        })
        .onClick(() => {
          this.showSettings = false;
        })
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
            this.onToggleRefreshButton(isOn);
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
      .onClick(() => {
        this.clearAppCache();
      })

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
      .onClick(() => {
        this.openInSystemBrowser(FEEDBACK_URL);
      })
    }
    .width('100%')
    .backgroundColor($r('app.color.surface_card'))
  }

  // 设置面板：刷新按钮开关，立即生效并持久化
  private onToggleRefreshButton(enabled: boolean): void {
    this.refreshButtonEnabled = enabled;
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      setRefreshButtonEnabled(ctx, enabled);
      hilog.info(DOMAIN, TAG, 'Refresh button enabled: %{public}s', String(enabled));
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Failed to persist refresh button enabled flag');
    }
  }

  /**
   * 设置面板：清理应用缓存。
   * removeCache(true) 清除 ROM + RAM 中的网页缓存（官方 API：作用于同应用内所有 Web 组件），
   * **不涉及 Cookie / DOM Storage**，因此登录状态与主题偏好会保留。
   */
  private clearAppCache(): void {
    try {
      this.controller.removeCache(true);
      hilog.info(DOMAIN, TAG, 'Web cache cleared');
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'removeCache failed');
    }
    try {
      this.getUIContext().getPromptAction().showToast({
        message: $r('app.string.toast_cache_cleared'),
        duration: 2000
      });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Failed to show cache toast');
    }
  }

  // 刷新当前页面
  private refreshPage(): void {
    try {
      this.controller.refresh();
      this.isError = false;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'refreshPage failed, fallback to loadUrl');
      this.navigateToUrl(DEEPSEEK_URL);
    }
  }

  // 注册 Web 下载代理：处理下载开始/进度/完成/失败，下载完成后可另存至公开目录
  private setupDownloadDelegate(): void {
    try {
      // 用 GUID 映射下载沙箱路径，避免多个并发生下载时路径覆盖
      const downloadPathMap: Record<string, string> = {};

      this.delegate.onBeforeDownload((webDownloadItem: webview.WebDownloadItem) => {
        const fileName: string = webDownloadItem.getSuggestedFileName();
        const guid: string = webDownloadItem.getGuid();
        hilog.info(DOMAIN, TAG, 'Download start: %{public}s, guid=%{public}s', fileName, guid);
        const cachePath: string =
          this.getUIContext().getHostContext()!.cacheDir + '/web/' + fileName;
        downloadPathMap[guid] = cachePath;
        webDownloadItem.start(cachePath);
      });

      this.delegate.onDownloadUpdated((webDownloadItem: webview.WebDownloadItem) => {
        const percent: number = webDownloadItem.getPercentComplete();
        hilog.info(DOMAIN, TAG, 'Download progress: %{public}d%%', percent);
      });

      this.delegate.onDownloadFinish((webDownloadItem: webview.WebDownloadItem) => {
        const guid: string = webDownloadItem.getGuid();
        const savePath: string = downloadPathMap[guid];
        hilog.info(DOMAIN, TAG, 'Download finish: %{public}s', guid);
        // 此处不再提示"下载完成"：文件此刻只在应用沙箱内，尚未落到用户可见目录。
        // 保存成功由 saveToPublicDownload 里的 toast_save_done 提示；用户若取消
        // 保存对话框则不作提示 —— 原先在此处提前弹"下载完成"，取消后会造成误导。
        if (savePath) {
          this.saveToPublicDownload(webDownloadItem.getSuggestedFileName(), savePath);
          downloadPathMap[guid] = '';
        } else {
          hilog.warn(DOMAIN, TAG, 'Download finished but sandbox path missing, guid=%{public}s', guid);
        }
      });

      this.delegate.onDownloadFailed((webDownloadItem: webview.WebDownloadItem) => {
        const guid: string = webDownloadItem.getGuid();
        hilog.error(DOMAIN, TAG, 'Download failed: code=%{public}d, guid=%{public}s',
          webDownloadItem.getLastErrorCode(), guid);
        // 清理失败下载的路径映射
        downloadPathMap[guid] = '';
        this.getUIContext().getPromptAction().showToast({
          message: $r('app.string.toast_download_fail'),
          duration: 2000
        });
      });

      this.controller.setDownloadDelegate(this.delegate);
      hilog.info(DOMAIN, TAG, 'Download delegate registered');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to setup download delegate');
    }
  }

  // 将已完成的下载从沙箱复制到用户选择的公开目录
  private saveToPublicDownload(fileName: string, srcPath: string): void {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const documentSaveOptions = new picker.DocumentSaveOptions();
      documentSaveOptions.pickerMode = picker.DocumentPickerMode.DOWNLOAD;
      // 注意：DOWNLOAD 模式下 newFileNames / defaultFilePathUri / fileSuffixChoices
      // 均不生效（见 SDK @ohos.file.picker.d.ts），该模式固定返回当前 hap 包名的
      // 文件夹路径，文件名由下方手动拼接，因此这里不设置 newFileNames。

      const documentViewPicker = new picker.DocumentViewPicker(context);
      documentViewPicker.save(documentSaveOptions).then((result: Array<string>) => {
        if (result.length === 0 || !result[0]) {
          return;
        }
        const uri: string = result[0];
        // DOWNLOAD 模式返回的是文件夹路径，需拼接文件名
        const pubDir: string = new fileUri.FileUri(uri).path;
        const pubFilePath: string = pubDir + '/' + fileName;
        hilog.info(DOMAIN, TAG, 'Copy from sandbox to public: %{public}s -> %{public}s',
          srcPath, pubFilePath);

        let srcFile: fs.File | null = null;
        let dstFile: fs.File | null = null;
        try {
          srcFile = fs.openSync(srcPath, fs.OpenMode.READ_ONLY);
          dstFile = fs.openSync(pubFilePath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
          fs.copyFileSync(srcFile.fd, dstFile.fd);
          this.getUIContext().getPromptAction().showToast({
            message: $r('app.string.toast_save_done'),
            duration: 2000
          });
        } catch (e) {
          const err = e as BusinessError;
          hilog.error(DOMAIN, TAG, 'File copy failed: code=%{public}d, msg=%{public}s',
            err.code, err.message);
        } finally {
          if (srcFile) {
            fs.closeSync(srcFile);
          }
          if (dstFile) {
            fs.closeSync(dstFile);
          }
        }
      }).catch((err: BusinessError) => {
        hilog.info(DOMAIN, TAG, 'User cancelled save dialog');
      });
    } catch (err) {
      hilog.info(DOMAIN, TAG, 'Save dialog not supported on this device');
    }
  }

  // 关闭上传模态框，若用户未选择则回传空列表
  private dismissUploadModal(): void {
    this.showUploadModal = false;
    if (this.pendingFileListHandler) {
      this.pendingFileListHandler([]);
      this.pendingFileListHandler = null;
    }
  }

  // 拍照：使用 CameraPicker 调用系统相机，结果通过 pendingFileListHandler 回传给 WebView
  private async handleTakePhoto(): Promise<void> {
    let pickerFileCreated: boolean = false;
    let filePath: string = '';
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const pathDir: string = context.filesDir;
      // 用带专用前缀的路径，便于应用启动时按前缀清理历史遗留（见 common/PhotoTempFiles）
      filePath = buildPhotoTempPath(pathDir);
      fs.createRandomAccessFileSync(filePath, fs.OpenMode.CREATE);
      pickerFileCreated = true;
      const saveUri: string = fileUri.getUriFromPath(filePath);
      const pickerProfile: cameraPicker.PickerProfile = {
        cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK,
        saveUri: saveUri
      };
      const result: cameraPicker.PickerResult = await cameraPicker.pick(
        context, [cameraPicker.PickerMediaType.PHOTO], pickerProfile);
      if (result.resultCode === 0 && result.resultUri) {
        if (this.pendingFileListHandler) {
          this.pendingFileListHandler([result.resultUri]);
        }
        this.showUploadModal = false;
        this.pendingFileListHandler = null;
      } else {
        // 用户取消或拍照失败：清理预创建的临时文件，保留模态框供用户重试
        this.tryDeleteTempFile(filePath);
      }
    } catch (err) {
      // 相机不可用或系统异常：清理临时文件，保留模态框
      if (pickerFileCreated) {
        this.tryDeleteTempFile(filePath);
      }
      hilog.warn(DOMAIN, TAG, 'CameraPicker cancelled or failed');
    }
  }

  // 安全删除临时文件（失败不抛异常）
  private tryDeleteTempFile(filePath: string): void {
    try {
      fs.unlinkSync(filePath);
    } catch (_e) {
      // 文件可能已被系统清理，忽略
    }
  }

  // 相册：使用 PhotoViewPicker 安全选择图片
  private handlePickFromAlbum(): void {
    try {
      const photoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      photoSelectOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      photoSelectOptions.maxSelectNumber = 5;
      const photoPicker = new photoAccessHelper.PhotoViewPicker();
      photoPicker.select(photoSelectOptions).then((photoResult) => {
        if (photoResult.photoUris && photoResult.photoUris.length > 0
          && this.pendingFileListHandler) {
          this.pendingFileListHandler(photoResult.photoUris);
          this.showUploadModal = false;
          this.pendingFileListHandler = null;
        }
        // 空结果（含取消）时保留模态框，不通知 web 端
      }).catch((err: BusinessError) => {
        hilog.error(DOMAIN, TAG, 'PhotoPicker err: %{public}s', err.message);
      });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'PhotoPicker failed');
    }
  }

  /**
   * 构造文件选择器的分组筛选条件。
   *
   * 扩展名数据来自 AllowedFileExtensions（纯数据，不含任何文字）；
   * 分组描述在此按**系统语言**取资源后拼接 —— 这样系统文档选择器里的
   * 「图片 / 文档 / 文本 / 代码 / 数据」会跟随系统语言，而不是固定显示中文。
   */
  private buildFileSuffixFilters(context: common.UIAbilityContext): Array<string> {
    const labels: Array<Resource> = [
      $r('app.string.filter_image'),
      $r('app.string.filter_doc'),
      $r('app.string.filter_text'),
      $r('app.string.filter_code'),
      $r('app.string.filter_data')
    ];
    try {
      const filters: Array<string> = [];
      for (let i = 0; i < UPLOAD_FILTER_EXTENSIONS.length && i < labels.length; i++) {
        filters.push(context.resourceManager.getStringSync(labels[i].id) + UPLOAD_FILTER_EXTENSIONS[i]);
      }
      return filters;
    } catch (err) {
      // 取不到资源时退回纯扩展名，至少不影响选择文件
      hilog.warn(DOMAIN, TAG, 'Failed to build file suffix filters, fallback to raw extensions');
      return UPLOAD_FILTER_EXTENSIONS;
    }
  }

  // 文件：使用 DocumentViewPicker 选择通用文件
  private handlePickFile(): void {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const docOptions = new picker.DocumentSelectOptions();
      docOptions.fileSuffixFilters = this.buildFileSuffixFilters(context);
      const docPicker = new picker.DocumentViewPicker(context);
      docPicker.select(docOptions).then((docResult) => {
        if (docResult && docResult.length > 0 && this.pendingFileListHandler) {
          this.pendingFileListHandler(docResult);
          this.showUploadModal = false;
          this.pendingFileListHandler = null;
        }
        // 空结果（含取消）时保留模态框，不通知 web 端
      }).catch((err: BusinessError) => {
        hilog.error(DOMAIN, TAG, 'DocPicker err: %{public}s', err.message);
      });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'DocPicker failed');
    }
  }
}
