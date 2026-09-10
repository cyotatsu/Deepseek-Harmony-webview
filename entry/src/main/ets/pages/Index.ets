import { webview } from '@kit.ArkWeb';
import { common, ConfigurationConstant, Want } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { fileIo as fs, fileUri, picker } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { resourceManager, i18n } from '@kit.LocalizationKit';
import { connection } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { url } from '@kit.ArkTS';
import { camera, cameraPicker } from '@kit.CameraKit';
import { ALLOWED_UPLOAD_EXTENSIONS } from '../common/AllowedFileExtensions';
import { DEEPSEEK_URL, DEEPSEEK_HOST } from '../common/AppConfig';
import { isDeepSeekDomain, isDownloadUrl } from '../common/UrlRules';
import { toBCP47 } from '../common/LanguageUtil';
import { buildPhotoTempPath } from '../common/PhotoTempFiles';
import { PageProgress } from '../components/PageProgress';
import { ErrorView } from '../components/ErrorView';

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
  // 深色模式适配（组件配色改由资源限定词自动适配，见 resources/*/element/color.json）
  @StorageProp('currentColorMode') @Watch('onColorModeChange')
  currentColorMode: ConfigurationConstant.ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
  // 2in1/PC 设备标识：用于显示拖拽手柄
  @State isPC: boolean = false;
  // 返回按钮：2in1 设备上访问非 DeepSeek 域名且有回退历史时显示
  @State showBackButton: boolean = false;
  // 上传方式选择模态框
  @State showUploadModal: boolean = false;
  // 语言切换后显示右下角刷新按钮
  @State showLangRefreshBtn: boolean = false;
  private pendingFileListHandler: ((fileList: Array<string>) => void) | null = null;

  aboutToAppear(): void {
    // 检测是否为 2in1/PC 设备
    this.isPC = deviceInfo.deviceType === '2in1';
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
    // 初始化背景色
    this.onColorModeChange();
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

  // 系统深色模式切换时同步状态栏样式。
  // 页面背景色已改由资源限定词（resources/dark/element/color.json）自动适配，
  // 不再需要手动改 webBgColor，也就不会因该状态变化触发额外重绘。
  onColorModeChange(): void {
    this.applyStatusBarColor();
  }

  /**
   * 状态栏自动反色：根据当前深色/浅色模式设置状态栏文字颜色，
   * 避免状态栏文字与背景重叠导致内容无法辨认。
   * 参考《开发应用沉浸式效果》官方文档的 setWindowSystemBarProperties 用法。
   */
  private applyStatusBarColor(): void {
    // setWindowSystemBarProperties 在 2in1 上不生效（见 SDK 文档），跳过以免无谓调用
    if (deviceInfo.deviceType === '2in1') {
      return;
    }
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const contentColor: string = this.currentColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK
        ? '#FFFFFF' : '#000000';
      window.getLastWindow(ctx).then((win: window.Window) => {
        win.setWindowSystemBarProperties({
          statusBarContentColor: contentColor
        }).catch((err: BusinessError) => {
          hilog.warn(DOMAIN, TAG, 'setStatusBarContentColor failed: %{public}d', err.code);
        });
      }).catch((err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'getLastWindow failed: %{public}d', err.code);
      });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'applyStatusBarColor exception');
    }
  }

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

        // 2in1/PC 拖拽手柄：隐藏标题栏后，用户可通过拖拽此区域移动窗口。
        // 注意：外层容器必须设为 HitTestMode.None 触摸穿透，否则整条顶部 24px 会
        // 阻塞下层 Web 的点击（DeepSeek 网页顶栏按钮会点不动）；只有中间的手柄
        // 区域响应拖动，其余区域的点击事件透传给网页。
        if (this.isPC) {
          Row() {
            Row() {
              Row().width(3).height(3).borderRadius(1.5).backgroundColor($r('app.color.drag_indicator'))
              Row().width(3).height(3).borderRadius(1.5).backgroundColor($r('app.color.drag_indicator'))
                .margin({ left: 3, right: 3 })
              Row().width(3).height(3).borderRadius(1.5).backgroundColor($r('app.color.drag_indicator'))
            }
            .height(24)
            .padding({ left: 16, right: 16 })
            .justifyContent(FlexAlign.Center)
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Down) {
                try {
                  const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
                  window.getLastWindow(ctx).then((win: window.Window) => {
                    win.startMoving().catch((err: BusinessError) => {
                      hilog.warn(DOMAIN, TAG, 'startMoving failed: %{public}d', err.code);
                    });
                  }).catch(() => {
                    hilog.warn(DOMAIN, TAG, 'getLastWindow failed');
                  });
                } catch (err) {
                  hilog.warn(DOMAIN, TAG, 'startMoving exception');
                }
              }
            })
            .hitTestBehavior(HitTestMode.Block)
          }
          .width('100%')
          .height(24)
          .justifyContent(FlexAlign.Center)
          .hitTestBehavior(HitTestMode.None)
          .zIndex(10)
        }

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

        // 语言切换刷新按钮：系统语言变化时在右下角显示圆形刷新按钮
        if (this.showLangRefreshBtn) {
          Button() {
            Text('↻')
              .fontSize(22)
              .fontColor($r('app.color.text_primary'))
          }
          .width(44)
          .height(44)
          .type(ButtonType.Circle)
          .backgroundColor($r('app.color.floating_button_bg'))
          .shadow({
            radius: 12,
            color: $r('app.color.floating_button_shadow'),
            offsetY: 4
          })
          .position({ x: '100%', y: '100%' })
          .markAnchor({ x: '100%', y: '100%' })
          .translate({ x: -24, y: -24 })
          .onClick(() => {
            try {
              this.controller.refresh();
            } catch (err) {
              hilog.error(DOMAIN, TAG, 'Language refresh failed');
            }
            this.showLangRefreshBtn = false;
          })
          .transition(TransitionEffect.OPACITY.animation({ duration: 300 }))
          .zIndex(101)
        }
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.web_background'))
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
   * 已渲染的界面文案不会因此改变，所以 onSystemLanguageChange 仍会提示用户手动刷新。
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

  // 系统语言变化时，重新注入 JS 覆盖 navigator.language 并显示刷新按钮。
  // 用户可点击按钮手动刷新以应用新语言，避免自动刷新打断当前操作。
  onSystemLanguageChange(): void {
    if (this.systemLanguage && this.systemLanguage !== '') {
      hilog.info(DOMAIN, TAG, 'System language changed, re-injecting language override');
      this.injectLanguageOverride();
      this.showLangRefreshBtn = true;
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

  // 调用系统浏览器打开外部链接
  private openInSystemBrowser(openUrl: string): void {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
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
      hilog.error(DOMAIN, TAG, 'openInSystemBrowser error');
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

  // 文件：使用 DocumentViewPicker 选择通用文件
  private handlePickFile(): void {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const docOptions = new picker.DocumentSelectOptions();
      docOptions.fileSuffixFilters = ALLOWED_UPLOAD_EXTENSIONS;
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
