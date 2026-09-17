import { webview } from '@kit.ArkWeb';
import { bundleManager, common, Want } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { fileIo as fs, fileUri, picker } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { resourceManager, i18n } from '@kit.LocalizationKit';
import { connection } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window, promptAction } from '@kit.ArkUI';
import { camera, cameraPicker } from '@kit.CameraKit';
import { UPLOAD_FILTER_EXTENSIONS } from '../common/AllowedFileExtensions';
import { DEEPSEEK_URL, DEEPSEEK_HOST, FEEDBACK_URL,
  SHARE_SCHEME_PREFIX, UA_PRODUCT_PREFIX } from '../common/AppConfig';
import { isChatHost, isDeepSeekDomain, isDownloadUrl, isChatRootPage }
  from '../common/UrlRules';
import { toBCP47 } from '../common/LanguageUtil';
import { buildPhotoTempPath } from '../common/PhotoTempFiles';
import { sanitizeFileName, buildDownloadTempPath, fileNameFromTempPath,
  ensureDownloadTempDir, removeDownloadTempFile } from '../common/DownloadFiles';
import { ensurePermission, MICROPHONE_PERMISSION } from '../common/AppPermissions';
import { buildUserAgent, buildViewportFixScript, buildResizeNotifyScript,
  buildProbeScript, buildOverlayProbeScript, buildOverlayDismissScript, parseOverlayKind,
  isDismissClicked, buildComposerAutoHideScript, buildKeyboardStateScript, buildRetryFocusScript,
  VIEWPORT_RESIZE_DEBOUNCE_MS } from '../common/WebViewport';
import { buildFocusGuardScript, ENABLE_IMAGE_TAP_FOCUS_GUARD } from '../common/WebInputGuard';
import { decideBackAction, BackContext, EXIT_CONFIRM_WINDOW_MS,
  BACK_ACTION_DISMISS_MODAL, BACK_ACTION_DISMISS_OVERLAY, BACK_ACTION_WEB_BACK,
  BACK_ACTION_PROMPT_EXIT } from '../common/BackPolicy';
import { PageProgress } from '../components/PageProgress';
import { ErrorView } from '../components/ErrorView';
import { RefreshConfirmDialog } from '../components/RefreshConfirmDialog';
import { FloatingBar } from '../components/FloatingBar';
import { SettingsSheet } from '../components/SettingsSheet';
import { UploadSheet } from '../components/UploadSheet';
import { isRefreshButtonEnabled, setRefreshButtonEnabled,
  isRefreshConfirmSkipped, setRefreshConfirmSkipped } from '../common/UiPrefs';

const DOMAIN = 0x0001;
const TAG = 'DeepSeekIndex';
/**
 * 真机调参用的**定时诊断取样**间隔（毫秒）；0 = 关闭。
 *
 * 为什么需要它：探针原本只在 onPageEnd / onPageShow 触发，而这两处都无法在
 * 「输入了长文本、键盘正开着」的那一刻取样（`aa start` 不会让已在前台的页面重新
 * onPageShow，HOME 键也未必真让应用切后台）。定位 composer 布局问题时必须能在任意
 * 时刻取样，因此留了这个开关。
 *
 * **仅用于排查问题，定位完成后应改回 0** —— 打开后会周期性打印一条较长的诊断日志。
 */
const DEBUG_PROBE_INTERVAL_MS: number = 0;

/**
 * 返回手势决策里「查网页弹层」这一步的兜底超时（毫秒）。
 *
 * onBackPress 必须同步返回，因此它固定消费事件、把决策放到异步里做；万一
 * runJavaScript 迟迟不回来（页面正在销毁、内核异常等），必须有兜底把它按
 * 「没有网页弹层」处理并继续决策 —— 返回键是主导航手段，不能因为一次异步
 * 失败就失灵。正常情况下这一步只要几毫秒。
 */
const BACK_PROBE_TIMEOUT_MS: number = 500;

@Entry
@Component
struct Index {
  @State loadingProgress: number = 0;
  @State isLoading: boolean = true;
  @State isError: boolean = false;
  @State isNetworkError: boolean = false;
  // 当前错误页是否由「加载超时」这一**暂时性**判断触发。
  //
  // 必须区分错误成因：超时只是「等太久了」的推测，页面若最终加载成功，错误页就得撤销；
  // 而 HTTP / 网络错误是确定性失败，必须保留到用户主动重新加载。
  // 关键在于**两种情况 onPageEnd 都会触发**（服务器返回 500 也算一次加载结束），
  // 所以不能在 onPageEnd 里无条件清错误态，否则错误页会一闪而过。
  private errorFromTimeout: boolean = false;
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
  // 视口重排通知的防抖定时器：窗口尺寸连续变化（自由多窗拖拽）时只在稳定后通知一次
  private viewportResizeTimer: number = -1;
  // 调试用诊断取样定时器（DEBUG_PROBE_INTERVAL_MS > 0 时才启动）
  private debugProbeTimer: number = -1;
  // 2in1/PC 设备标识：用于返回按钮
  @State isPC: boolean = false;
  // 返回按钮：2in1 设备上访问非 DeepSeek 域名且有回退历史时显示
  @State showBackButton: boolean = false;
  // 上传方式选择模态框
  @State showUploadModal: boolean = false;
  // 上次「再按一次返回桌面」提示的时间戳（0 表示本次还没提示过）。
  // 与 EXIT_CONFIRM_WINDOW_MS 配合实现「连按两次才退出」，避免误触直接退出。
  private lastExitPromptAt: number = 0;
  // 返回决策是否正在异步进行（查网页弹层）：未完成前的重复按下直接忽略，
  // 避免一次连击被当成两次动作
  private backDecisionPending: boolean = false;
  // 键盘避让高度（vp）。键盘是浮层、不改变窗口尺寸，页面底部会落到键盘之下，
  // 悬浮操作条需要按此抬高，否则会被键盘遮挡。
  @State keyboardHeightVp: number = 0;
  // 状态栏避让高度（vp）。底部沉浸开启后布局延伸到系统栏区域，顶部需要按此补 padding，
  // 视觉上仍是一条正常的状态栏，而不是内容压到状态栏文字下面。
  @State statusBarHeightVp: number = 0;
  private avoidAreaHandler: ((data: window.AvoidAreaOptions) => void) | null = null;
  // 页面可用尺寸（vp），由根容器 onAreaChange 提供，传给悬浮操作条用于边界限制与键盘避让。
  // 操作条自身的位置状态、拖拽手势与位置持久化都在 components/FloatingBar.ets 内。
  @State pageW: number = 0;
  @State pageH: number = 0;
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
    this.restoreUiPrefs();
    this.startDebugProbe();
    // 冷启动携带的 DeepLink 直接作为 Web 的初始 src。
    // 不能等到 onPageShow 再 loadUrl —— 那会比 onControllerAttached 早约 35ms，
    // 控制器尚未绑定必然抛异常；即便推迟到 onControllerAttached，
    // 组件的初始 src（首页）加载也会覆盖该次导航。作为初始 src 可彻底避开竞态。
    if (this.deepLinkUrl && this.deepLinkUrl !== '') {
      this.initialUrl = this.deepLinkUrl;
      hilog.info(DOMAIN, TAG, 'Cold-start DeepLink used as initial src');
      // 已消费，立即清空，避免 onPageShow / onDeepLinkChange 重复处理
      AppStorage.setOrCreate<string>('deepLinkUrl', '');
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
    // 清理视口重排的防抖定时器
    if (this.viewportResizeTimer !== -1) {
      clearTimeout(this.viewportResizeTimer);
      this.viewportResizeTimer = -1;
    }
    // 清理调试诊断取样定时器
    if (this.debugProbeTimer !== -1) {
      clearInterval(this.debugProbeTimer);
      this.debugProbeTimer = -1;
    }
    // 释放挂起的文件选择回调：它是 onShowFileSelector 存下的闭包，持有 Web 侧的
    // FileSelectorResult。页面销毁后不会再有人调用它，留着会让事件结果与页面对象
    // 无法回收（用户打开上传框后直接退出页面就会走到这里）。
    this.pendingFileListHandler = null;
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
          // ⚠️ 关键：显式开启 meta viewport 解析。
          //
          // 内核的默认规则是「UA 不含 Mobile 字段 → 禁用 viewport」。手机默认 UA 含
          // Mobile 所以一直正常；而平板/2in1 的默认 UA 不含 Mobile，网页里的
          // width=device-width 就不被解析，布局视口退回约 980px 的默认宽度 ——
          // 于是窗口拖窄了，网页仍按桌面大屏排版，表现为挤压 / 留白 / 错位。
          // 显式传 true 可覆盖该禁用状态（SDK 中 metaViewport 的 API Note 明确说明）。
          //
          // 注意：2in1 设备无论传 true 还是 false 都**不支持** viewport，
          // 它走桌面式布局（布局视口跟随窗口），因此对 2in1 不做额外干预。
          .metaViewport(true)
          // 软键盘避让：RESIZE_CONTENT = 可视视口与**布局视口**一起收缩，
          // 网页会因此重排（内容区收缩、输入框留在可视区内），而不是被键盘顶出去。
          // 这本就是该属性的默认值，显式写出以固定语义、避免默认值变更带来的回退。
          .keyboardAvoidMode(WebKeyboardAvoidMode.RESIZE_CONTENT)
          // 键盘收起时让网页输入框**失焦**（焦点回到 body）。
          //
          // 默认值是 SILENT —— 键盘隐藏但输入框仍持有焦点。这个「残留焦点」正是
          // 「点图片莫名弹出键盘」的根源之一：点图片使 Web 组件的焦点/激活状态发生变化，
          // 内核按自动策略又为那个仍然聚焦的输入框把键盘弹了回来。
          // 改成 BLUR 后不存在残留焦点，从机制上断掉这条链路。
          .blurOnKeyboardHideMode(BlurOnKeyboardHideMode.BLUR)
          .darkMode(2)  // WebDarkMode.Auto: 跟随系统深色模式，传递 prefers-color-scheme 给网页
          .backgroundColor($r('app.color.web_background'))
          .width('100%')
          .height('100%')
          .onControllerAttached(() => {
            try {
              // 版本号从应用信息读取，避免与 AppScope/app.json5 的 versionName 脱节。
              // UA 本身保持内核默认（带有正确的设备身份），只附加产品标识；
              // 是否附加 Mobile 标记见 common/WebViewport 里 APPEND_MOBILE_UA_TOKEN 的说明。
              const customUA: string = buildUserAgent(
                this.controller.getUserAgent(), UA_PRODUCT_PREFIX, this.appVersionName());
              this.controller.setCustomUserAgent(customUA);
            } catch (err) {
              hilog.error(DOMAIN, TAG, 'Failed to set user agent');
            }
            this.setupDownloadDelegate();
            // 关闭内核的「自动软键盘」策略。
            //
            // 默认行为是：Web 组件获得/失去焦点、或激活状态在 inactive/active 之间切换时，
            // 系统会**自动隐藏或显示**软键盘 —— 这会拿残留的输入框焦点做文章，
            // 造成「点图片弹出键盘」。改为 DISABLE_AUTO_KEYBOARD_ON_ACTIVE 后，
            // 键盘只在用户明确点到可输入元素时才出现。
            // 必须在控制器挂载后调用，否则抛 17100001（未与 Web 组件关联）。
            // 键盘没弹起来时的临时切换见 ensureSoftKeyboardForEdit。
            this.setKeyboardAutoMode(false);
            this.controllerReady = true;
          })
          // 网页用约定的 console 前缀上报「可编辑元素获得焦点」。
          //
          // 为什么需要这条通道：编辑历史消息时，站点是异步渲染编辑框的 —— 程序化 focus
          // 可能被后到的 DOM 变更顶掉，或者内核因为组件刚好在做激活状态切换而没有拉起键盘，
          // 表现为「点了输入框但键盘有概率不弹」。网页侧只能知道焦点，键盘只有应用侧知道，
          // 因此由网页上报焦点、应用侧在键盘确实没起来时兜底。
          //
          // 组件侧可用的手段只有 setSoftKeyboardBehaviorMode：IME 的 showSoftKeyboard
          // 需要系统级权限 ohos.permission.CONNECT_IME_ABILITY，普通应用调用会抛 201。
          .onConsole((event) => {
            try {
              const msg: string = event && event.message ? event.message.getMessage() : '';
              if (msg.indexOf('__dsFocus:') === 0) {
                hilog.info(DOMAIN, TAG, 'Edit focus reported: %{public}s', msg);
                // 只对「用户真实操作导致的聚焦」兜底：
                //   inline   —— 用户点了编辑框 / 站点渲染完成后聚焦
                //   card-tap —— 用户点了卡片空白处（脚本补的聚焦）
                // **必须忽略 retry / refocus**：那两个是兜底自己造成的焦点事件，
                // 一旦也当成触发条件就会形成「兜底 → blur+focus → 再兜底」的死循环，
                // 表现就是键盘不停闪现（实机已复现）。再加一道冷却作为双保险。
                if (msg === '__dsFocus:inline' || msg === '__dsFocus:card-tap') {
                  const now: number = Date.now();
                  if (now - this.lastKeyboardFallbackAt > Index.KEYBOARD_FALLBACK_COOLDOWN_MS) {
                    this.lastKeyboardFallbackAt = now;
                    this.ensureSoftKeyboardForEdit();
                  } else {
                    hilog.info(DOMAIN, TAG, 'Keyboard fallback in cooldown, skipped');
                  }
                }
              }
            } catch (err) {
              hilog.warn(DOMAIN, TAG, 'onConsole handling failed');
            }
            // 不消费，保持页面自身 console 行为不变
            return false;
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
            // 只撤销「超时」这一暂时性判断：超时后页面若最终加载成功，错误页必须撤掉，
            // 否则慢网下用户会看着一个已经加载好的页面被错误页盖住。
            // 确定性失败（HTTP 4xx/5xx、主框架网络错误）**不能**在这里清 ——
            // 服务器返回错误同样会触发 onPageEnd，无条件清空会让错误页一闪而过。
            if (this.errorFromTimeout) {
              this.errorFromTimeout = false;
              this.isError = false;
              this.isNetworkError = false;
            }
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
            // 修正视口：确保存在 width=device-width 的 viewport 声明，
            // 并给输入框加高度上限（内容再多也不会无限向上扩张）。
            // 每个新文档都要重新注入 —— 注入的 style 会随旧文档一起丢弃。
            this.applyViewportFix();
            // 装上「点图片不聚焦输入框」的防护，同样是每个新文档都要重新装
            this.applyWebInputGuard();
            // 装上「编辑历史消息 + 键盘弹出时隐藏主对话框」的脚本，
            // 并把当前键盘状态同步过去（可能在键盘已经弹着的时候页面才加载完）
            this.applyComposerAutoHide();

            // 打印一次运行时视口诊断，便于实机确认 viewport 是否真的生效
            this.probeViewport();
            this.updateBackButtonState();
          })
          .onErrorReceive((event) => {
            if (event && event.error && event.error.getErrorCode() !== 0) {
              hilog.warn(DOMAIN, TAG, 'WebView net err: code=%{public}d, info=%{public}s',
                event.error.getErrorCode(), event.error.getErrorInfo());
              // 仅主框架的导航错误才触发错误页（过滤子资源错误）。
              // 主框架失败一律进错误页：网络可达也可能是服务端不可用、连接被重置或 DNS 异常，
              // 旧逻辑要求「无网络」才报错，会把这类失败静默吞掉，用户只能干等 15s 超时。
              // 网络状态只用来决定文案（断网 / 加载失败）。若该次导航随后实际成功，
              // onPageEnd 会复位错误态，因此不会误报到一个已经加载好的页面上。
              if (event.request && event.request.isMainFrame()) {
                this.isNetworkError = !this.checkNetworkAvailable();
                this.isError = true;
                // 确定性失败：错误页保留到用户主动重新加载（下次导航的 onPageBegin 会复位）
                this.errorFromTimeout = false;
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
                // 确定性失败：服务器返回 4xx/5xx 同样会触发 onPageEnd，
                // 因此必须标记为「非超时」，避免 onPageEnd 把错误页清掉
                this.errorFromTimeout = false;
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
              // 仅在聊天主站弹出上传方式选择框（精确匹配 host，见 UrlRules.isChatHost）
              if (!isChatHost(pageUrl)) {
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
            // 自定义 scheme 由注入脚本触发，直接唤起系统分享
            if (requestUrl.startsWith(SHARE_SCHEME_PREFIX)) {
              const shareUrl: string =
                decodeURIComponent(requestUrl.substring(SHARE_SCHEME_PREFIX.length));
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
          // 网页请求设备权限（麦克风等）。官方规范要求实现该回调：
          // 不实现时网页侧的请求会被直接拒绝，语音输入等功能静默失效。
          .onPermissionRequest((event) => {
            if (event) {
              this.handleWebPermissionRequest(event.request);
            }
          })
          // SSL 证书错误：一律取消，不提供「继续访问」——本应用无法向用户解释证书风险，
          // 静默绕过等同于主动把 TLS 降级。handleCancel(true) 会取消该请求并停留在当前页，
          // 而不是留下白屏。
          .onSslErrorEventReceive((event) => {
            if (!event) {
              return;
            }
            hilog.error(DOMAIN, TAG, 'SSL error: %{public}d', event.error);
            try {
              event.handler.handleCancel(true);
            } catch (err) {
              hilog.warn(DOMAIN, TAG, 'handleCancel failed');
            }
            // 首屏加载期间的证书错误意味着主框架拿不到内容，直接进错误页给出明确反馈；
            // 页面已渲染后的子资源证书错误只取消该请求，不打断用户。
            if (this.isLoading) {
              this.isNetworkError = false;
              this.isError = true;
              // 证书错误是确定性失败，同样不能被 onPageEnd 清掉
              this.errorFromTimeout = false;
              this.isLoading = false;
              this.clearLoadTimeout();
            }
          })
          // 新窗口请求（window.open / target="_blank"）。
          // 单 Web 组件架构下不另开窗口，但必须显式调用 setWebController(null) 释放
          // 被挂起的渲染流程 —— 官方文档明确：不调用该接口会阻塞渲染进程。
          // 站内地址在当前 Web 内继续导航，站外地址交系统浏览器（复用已有的确认弹窗）。
          .onWindowNew((event) => {
            if (!event) {
              return;
            }
            const target: string = event.targetUrl;
            hilog.info(DOMAIN, TAG, 'New window request: %{public}s', target);
            try {
              if (isDeepSeekDomain(target)) {
                this.controller.loadUrl(target);
              } else if (event.isUserTrigger) {
                this.openInSystemBrowser(target);
              }
            } catch (err) {
              hilog.warn(DOMAIN, TAG, 'Failed to handle new window request');
            }
            try {
              event.handler.setWebController(null);
            } catch (err) {
              hilog.warn(DOMAIN, TAG, 'setWebController(null) not supported');
            }
          })

        // 窗口拖动不再由应用自绘手柄承担 —— 窗口已完全交由系统管理（非沉浸式），
        // 系统标题栏即拖动区，且不自绘任何窗口部件。

        if (this.isLoading) {
          PageProgress({ progress: this.loadingProgress })
        }

        // 2in1 返回按钮：非 DeepSeek 域名且有回退历史时，左上角显示方形返回按钮
        if (this.showBackButton) {
          Button() {
            // 用系统符号替代 '←' 字符：字形字符的字重/基线随字体变化，符号与系统保持一致
            SymbolGlyph($r('sys.symbol.arrow_left'))
              .fontSize(20)
              .fontColor([$r('app.color.text_primary')])
          }
          // 44×44：满足无障碍最小触摸目标（原 36×36 偏小，单手操作容易点空）
          .width(44)
          .height(44)
          .type(ButtonType.Normal)
          .borderRadius(10)
          .backgroundColor($r('app.color.floating_button_bg'))
          .position({ x: 32, y: 32 })
          .shadow({
            radius: 8,
            color: $r('app.color.floating_button_shadow'),
            offsetX: 0,
            offsetY: 2
          })
          // 纯图标按钮必须给出朗读文案，否则读屏只能念出「按钮」
          .accessibilityText($r('app.string.a11y_back'))
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

        // 上传方式选择模态框（内容见 components/UploadSheet.ets）
        if (this.showUploadModal) {
          UploadSheet({
            onTakePhoto: () => this.handleTakePhoto(),
            onPickFromAlbum: () => this.handlePickFromAlbum(),
            onPickFile: () => this.handlePickFile(),
            onDismiss: () => this.dismissUploadModal()
          })
        }

        // 右下角悬浮操作条（刷新 + 设置）。位置状态、拖拽手势、边界限制与位置持久化
        // 全部收在 components/FloatingBar.ets 内；页面只决定「刷新要不要弹确认框」，
        // 并把页面可用尺寸与键盘高度传下去供其计算边界与避让。
        FloatingBar({
          pageW: this.pageW,
          pageH: this.pageH,
          keyboardHeightVp: this.keyboardHeightVp,
          refreshEnabled: this.refreshButtonEnabled,
          onRefresh: () => this.onFloatingRefresh(),
          onOpenSettings: () => {
            this.showSettings = true;
          }
        })
      }
      .width('100%')
      .layoutWeight(1)
      // 把实际可用的坐标空间交给悬浮操作条：它才是靠 100% 定位的一方，
      // 需要用这两个值把按钮限制在窗口内并计算键盘避让。
      // 非全屏（悬浮窗/自由多窗）时这里就是应用窗口的尺寸。
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        this.pageW = newValue.width as number;
        this.pageH = newValue.height as number;
        // 窗口尺寸变化后通知网页重排。
        // 自由多窗拖拽时这里会高频触发，因此内部做了防抖（见 scheduleViewportResize）：
        // 只在尺寸稳定下来之后才通知一次，绝不重载页面，避免闪烁与丢失输入。
        this.scheduleViewportResize();
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
    this.errorFromTimeout = false;
    this.refreshPage();
  }

  /** 页面隐藏（含切到后台）：记住时间点 */
  onPageHide(): void {
    this.pageHiddenAt = Date.now();
  }

  onPageShow(): void {
    if (this.deepLinkUrl && this.deepLinkUrl !== '') {
      this.navigateToUrl(this.deepLinkUrl);
      AppStorage.setOrCreate<string>('deepLinkUrl', '');
    }
    // 回到前台时补打一次视口诊断。
    // 除了 onPageEnd，这里也给了一个**可主动触发**的取样点：把应用切到后台再切回来
    // 就会重新取样，因此在真机上「输入一段长文本 → 切后台再切回 → 看日志」
    // 就能拿到输入框此时的实际高度与样式，不必接调试器。
    this.probeViewport();
    // 从后台回到前台：重载页面同步服务端最新内容。
    // 站内切会话、弹面板不会走到这里，因此日常使用不会闪；
    // 「去别的设备 / 网页发完消息再回来」正是这条路径。
    if (this.pageHiddenAt > 0 && Date.now() - this.pageHiddenAt > 5000) {
      hilog.info(DOMAIN, TAG, 'Returned to foreground after %{public}d ms',
        Date.now() - this.pageHiddenAt);
      this.refreshConversationFromServer();
    }
    this.pageHiddenAt = 0;
  }

  // 响应热启动时 onNewWant 设置的 deepLinkUrl 变化（onPageShow 仅在冷/温启动触发）
  onDeepLinkChange(): void {
    if (this.deepLinkUrl && this.deepLinkUrl !== '') {
      hilog.info(DOMAIN, TAG, 'DeepLink change detected: %{private}s', this.deepLinkUrl);
      this.navigateToUrl(this.deepLinkUrl);
      AppStorage.setOrCreate<string>('deepLinkUrl', '');
    }
  }

  /**
   * 系统返回（侧滑返回手势 / 返回键）。
   *
   * 策略与判定规则见 common/BackPolicy.ets（纯函数，有单测）：
   *   · **网页自己的弹层**（设置弹窗等）——交给网页后退去关掉它；
   *   · **对话界面**（聊天主站根级页面：首页、会话页）——**不执行网页后退**，
   *     改为「再按一次返回桌面」：第一次只弹提示，在确认窗口内再按一次才退出；
   *   · **二三级界面**（`/sign_in`、`/share/…` 等站内其他页面）——**保持原样**，
   *     网页还有历史就照旧后退；
   *   · 网页退无可退时也给一次确认，避免一次误触直接退出。
   *
   * 为什么这里要**异步**：判断「网页弹层是否开着」必须查 DOM（runJavaScript 只有
   * 异步形式），而 onBackPress 必须同步返回。因此这里**固定消费掉事件**，
   * 由 {@link dispatchBackDecision} 在几十毫秒内完成决策并执行对应动作；
   * 代价是「退出到桌面」不能靠 `return false`，必须自己调 terminateSelf()。
   */
  onBackPress(): boolean {
    // 全部交给异步决策（见 dispatchBackDecision）：应用自己的弹层同样由
    // BackPolicy 的 dismiss-modal 分支处理，保证判定只有一处实现。
    this.dispatchBackDecision();
    return true;
  }

  /**
   * 异步决策并执行返回动作。
   *
   * 先查网页的瞬时界面（runJavaScript），再按 BackPolicy 决定：
   * web-back → 网页后退；dismiss-overlay → 点掉网页菜单/多选模式；
   * prompt-exit → 提示并消费；exit-now → 退出到桌面。
   *
   * 两个健壮性措施：
   *   · **兜底超时**：DOM 查询若迟迟不回来（异常、页面已销毁等），按「没有瞬时界面」
   *     继续走决策 —— 返回键是主导航手段，绝不能因为一次异步失败而失灵；
   *   · **去重**：一次决策未完成前的重复按下直接忽略，避免连击触发两次动作。
   */
  private dispatchBackDecision(): void {
    if (this.backDecisionPending) {
      return;
    }
    this.backDecisionPending = true;
    let settled: boolean = false;
    const settle = (overlayKind: string, overlayDetail: string): void => {
      if (settled) {
        return;
      }
      settled = true;
      this.backDecisionPending = false;
      this.applyBackDecision(overlayKind, overlayDetail);
    };
    const settleRaw = (raw: string): void => {
      settle(parseOverlayKind(raw), parseOverlayKind(raw, false));
    };

    // 兜底：超时按「网页没有瞬时界面」处理
    setTimeout(() => settle(parseOverlayKind(''), parseOverlayKind('', false)), BACK_PROBE_TIMEOUT_MS);
    try {
      this.controller.runJavaScript(buildOverlayProbeScript())
        .then((raw: string) => settleRaw(raw))
        .catch((err: BusinessError) => {
          hilog.warn(DOMAIN, TAG, 'overlay probe failed: %{public}d', err.code);
          settleRaw('');
        });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Failed to run overlay probe');
      settleRaw('');
    }
  }

  /** 按 BackPolicy 的决策执行动作 */
  private applyBackDecision(webOverlay: string, overlayDetail: string): void {
    let canGoBack: boolean = false;
    let currentUrl: string = '';
    try {
      canGoBack = this.controllerReady ? this.controller.accessBackward() : false;
      currentUrl = this.controllerReady ? this.controller.getUrl() : '';
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to read web back state');
    }

    const context: BackContext = {
      modalOpen: this.showUploadModal || this.showSettings,
      webOverlay: webOverlay,
      onChatRoot: isChatRootPage(currentUrl),
      canGoBack: canGoBack,
      msSinceExitPrompt: this.lastExitPromptAt > 0 ? (Date.now() - this.lastExitPromptAt) : -1
    };
    const action: string = decideBackAction(context);
    hilog.info(DOMAIN, TAG,
      'Back action: %{public}s (overlay=%{public}s canGoBack=%{public}s onChatRoot=%{public}s detail=%{public}s)',
      action, webOverlay === '' ? 'none' : webOverlay,
      String(canGoBack), String(context.onChatRoot), overlayDetail);

    // 应用自己的弹层（上传方式选择 / 设置面板）：关掉它，不再往下走
    if (action === BACK_ACTION_DISMISS_MODAL) {
      if (this.showUploadModal) {
        this.dismissUploadModal();
      } else {
        this.showSettings = false;
      }
      return;
    }

    // 网页自己的瞬时界面（菜单 / 侧栏多选模式 / 无历史的弹窗）：点掉它。
    // 有历史的弹窗（系统设置）不走这里 —— 见 BackPolicy 中的说明。
    if (action === BACK_ACTION_DISMISS_OVERLAY) {
      this.dismissWebOverlay();
      return;
    }

    if (action === BACK_ACTION_WEB_BACK) {
      try {
        this.controller.backward();
        this.updateBackButtonState();
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'backward failed');
      }
      return;
    }

    if (action === BACK_ACTION_PROMPT_EXIT) {
      this.lastExitPromptAt = Date.now();
      this.showBackAgainToast();
      return;
    }

    // exit-now：事件已被消费，必须自己退出（等价于旧实现的 return false）
    this.lastExitPromptAt = 0;
    this.showBackButton = false;
    this.exitToDesktop();
  }

  /**
   * 点掉网页自己的瞬时界面（菜单 / 侧栏多选模式），并回读执行结果便于诊断。
   *
   * 走到这里的只有「不靠历史关闭」的界面：菜单、多选模式，以及没有历史的弹窗。
   * 有历史的弹窗（如系统设置）由 BackPolicy 直接判为网页后退 —— 它没有可点的
   * 关闭入口、又盖满屏幕点不到外面，DOM 点不掉，后退才是它自己的关闭动作。
   */
  private dismissWebOverlay(): void {
    try {
      this.controller.runJavaScript(buildOverlayDismissScript())
        .then((result: string) => {
          hilog.info(DOMAIN, TAG, 'Web overlay dismissed: %{public}s', result);
          // 用 isDismissClicked 解析：runJavaScript 的字符串返回值带引号，
          // 直接拿原文判断会把「点到了」误判成「没点到」
          if (!isDismissClicked(result)) {
            hilog.warn(DOMAIN, TAG, 'No dismiss target found for the web overlay');
          }
        })
        .catch((err: BusinessError) => {
          hilog.warn(DOMAIN, TAG, 'overlay dismiss failed: %{public}d', err.code);
        });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Failed to dismiss web overlay');
    }
  }

  /** 退出到桌面。事件已被 onBackPress 消费，所以只能主动结束本 Ability */
  private exitToDesktop(): void {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      ctx.terminateSelf().catch((err: BusinessError) => {
        hilog.error(DOMAIN, TAG, 'terminateSelf failed: %{public}s', err.message);
      });
      hilog.info(DOMAIN, TAG, 'Exit to desktop by double back press');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to terminate self');
    }
  }

  /**
   * 装上「编辑历史消息 + 键盘弹出时隐藏主对话框」的脚本，并同步一次键盘状态。
   *
   * 为什么键盘状态要由应用侧推：网页侧只能靠「可视高度变小」推断，而自由多窗 /
   * 悬浮窗拖拽同样会让可视高度变小，两者分不开；ArkUI 侧有权威信号
   * （avoidAreaChange 的 TYPE_KEYBOARD 底部避让高度）。
   */
  private applyComposerAutoHide(): void {
    try {
      this.controller.runJavaScript(buildComposerAutoHideScript())
        .then((result: string) => {
          hilog.info(DOMAIN, TAG, 'Composer auto-hide: %{public}s', result);
          this.syncKeyboardStateToWeb(this.keyboardHeightVp > 0);
        })
        .catch((err: BusinessError) => {
          hilog.warn(DOMAIN, TAG, 'composer auto-hide failed: %{public}d', err.code);
        });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Failed to install composer auto-hide');
    }
  }

  /** 把键盘弹起/收起状态推给网页（网页据此决定要不要隐藏主对话框） */
  private syncKeyboardStateToWeb(keyboardUp: boolean): void {
    try {
      this.controller.runJavaScript(buildKeyboardStateScript(keyboardUp))
        .then((result: string) => {
          hilog.info(DOMAIN, TAG, 'Keyboard state -> web: %{public}s', result);
        })
        .catch((err: BusinessError) => {
          hilog.warn(DOMAIN, TAG, 'keyboard state sync failed: %{public}d', err.code);
        });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Failed to sync keyboard state');
    }
  }

  /**
   * 兜底拉起软键盘（仅在「内联编辑态聚焦了编辑框、但键盘确实没弹起来」时触发）。
   *
   * 只做一件事：临时把键盘策略切回 DEFAULT，并让网页重新 focus 一次当前编辑元素 ——
   * DISABLE_AUTO_KEYBOARD_ON_ACTIVE 保证的是「组件激活状态切换时不自动弹键盘」，
   * 本身不阻止焦点驱动那一路；编辑态下组件激活与页面聚焦常常同时发生，
   * 切回 DEFAULT 能让内核的焦点驱动路径生效。切换窗口只保留 150ms，
   * 用完全局立即恢复防线（那是「点图片不弹键盘」的保护）。
   *
   * 两条实机结论决定了这里的写法：
   *   1. **不能调 `inputMethod.showTextInput()`**：实测 WebView 的输入框并未绑定 IME 客户端，
   *      调用必然失败（日志 `ShowTextInputInner,not bound!` / 12800009 client detached），
   *      只会白刷日志；`showSoftKeyboard()` 则需要系统级权限 CONNECT_IME_ABILITY，更用不了。
   *   2. **必须防止自我循环**：这里的 `blur()+focus()` 会产生新的焦点事件，
   *      若再次触发兜底就会「兜底 → 聚焦 → 再兜底」，键盘不停闪现（实机已复现）。
   *      因此调用方对 retry / refocus 一律忽略，并且整体带冷却。
   */
  private ensureSoftKeyboardForEdit(): void {
    // 给内核一点时间：正常路径下 focus 之后键盘会自己起来，不要抢
    setTimeout(() => {
      if (this.keyboardHeightVp > 0) {
        hilog.info(DOMAIN, TAG, 'Soft keyboard already shown, no fallback needed');
        return;
      }
      hilog.info(DOMAIN, TAG, 'Soft keyboard missing for inline edit, switching mode and refocusing');
      this.setKeyboardAutoMode(true);
      try {
        this.controller.runJavaScript(buildRetryFocusScript())
          .then((result: string) => {
            hilog.info(DOMAIN, TAG, 'Retry edit focus: %{public}s', result);
          })
          .catch((err: BusinessError) => {
            hilog.warn(DOMAIN, TAG, 'retry focus failed: %{public}d', err.code);
          });
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'Failed to retry edit focus');
      }
      // 切换窗口尽量短：只要新的 focus 事件已经产生，就可以立刻把防线恢复
      setTimeout(() => {
        this.setKeyboardAutoMode(false);
        hilog.info(DOMAIN, TAG, 'Keyboard fallback done, keyboardHeightVp=%{public}d',
          this.keyboardHeightVp);
      }, 150);
    }, 350);
  }

  /**
   * 切换内核的软键盘自动策略。
   *
   * @param allowAuto true = DEFAULT（组件激活状态变化时系统可自动显示/隐藏键盘），
   *                  false = DISABLE_AUTO_KEYBOARD_ON_ACTIVE（默认防线）
   */
  private setKeyboardAutoMode(allowAuto: boolean): void {
    try {
      this.controller.setSoftKeyboardBehaviorMode(allowAuto
        ? webview.WebSoftKeyboardBehaviorMode.DEFAULT
        : webview.WebSoftKeyboardBehaviorMode.DISABLE_AUTO_KEYBOARD_ON_ACTIVE);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'setSoftKeyboardBehaviorMode failed');
    }
  }

  /** 上次因切换会话而重载页面的时间戳（冷却用，避免连续切换时反复整页重载） */
  private lastConvRefreshAt: number = 0;

  /** 页面进入后台的时间戳（判断是否从后台回来） */
  private pageHiddenAt: number = 0;

  /**
   * 切到别的会话后重新加载页面，同步服务端最新内容。
   *
   * 站点是 SPA：切会话走前端路由、用内存里缓存的会话数据，不会重新向服务端拉取，
   * 所以在网页端 / 其它设备刚发过消息时，切进来看到的还是旧的。应用侧没有它的数据接口，
   * 唯一能保证拿到最新内容的手段就是让页面重新加载一次（SPA 启动时会重新拉取）。
   * 3 秒冷却：连续切换时只重载一次，避免来回闪。
   */
  private refreshConversationFromServer(): void {
    const now: number = Date.now();
    if (now - this.lastConvRefreshAt < 3000) {
      hilog.info(DOMAIN, TAG, 'Conversation refresh skipped (cooldown)');
      return;
    }
    this.lastConvRefreshAt = now;
    hilog.info(DOMAIN, TAG, 'Reloading page to sync conversation from server');
    try {
      this.controller.refresh();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Failed to reload page for conversation sync');
    }
  }
  /** 提示「再按一次返回桌面」。时长与确认窗口一致，提示消失即窗口结束 */
  private showBackAgainToast(): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message: $r('app.string.toast_back_again_to_exit'),
        duration: EXIT_CONFIRM_WINDOW_MS
      });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Failed to show back-again toast');
    }
  }

  // 上次触发「键盘兜底」的时间戳：兜底会 blur+focus 制造新的焦点事件，
  // 必须有冷却，否则会自我循环、键盘不停闪现（实机已复现）
  private lastKeyboardFallbackAt: number = 0;

  /** 键盘兜底的冷却时间（毫秒） */
  private static readonly KEYBOARD_FALLBACK_COOLDOWN_MS: number = 3000;

  private startLoadTimeout(): void {
    this.clearLoadTimeout();
    this.pageLoadTimer = setTimeout(() => {
      hilog.error(DOMAIN, TAG, 'Page load timeout after %{public}d ms', this.LOAD_TIMEOUT_MS);
      this.isLoading = false;
      // 超时时检测网络：无网络则为网络错误，有网络则为加载失败
      this.isNetworkError = !this.checkNetworkAvailable();
      this.isError = true;
      // 标记为「暂时性」判断：页面若在此之后加载完成，onPageEnd 会把错误页撤销
      this.errorFromTimeout = true;
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

  /**
   * 修正网页视口：保证存在 `width=device-width` 的 viewport 声明，
   * 并给输入框加高度上限，避免长文本时输入框无限向上扩张。
   * 脚本内容见 common/WebViewport.buildViewportFixScript。
   */
  private applyViewportFix(): void {
    try {
      // 把「应用窗口宽度」传进脚本：布局视口必须等于窗口宽度。
      // 不能依赖网页自带的 width=device-width —— 那是**屏幕**宽度，
      // 在自由多窗/悬浮窗下窗口远窄于屏幕，页面会按整屏排版再整体缩小（UI 看起来变小）。
      // 回读执行结果：注入失败（比如 head 尚未就绪）时必须能看见，
      // 否则「样式没生效」在应用侧完全无声，只能靠猜。
      this.controller.runJavaScript(buildViewportFixScript(this.pageW))
        .then((result: string) => {
          hilog.info(DOMAIN, TAG, 'Viewport fix: %{public}s', result);
        })
        .catch((err: BusinessError) => {
          hilog.warn(DOMAIN, TAG, 'viewport fix failed: %{public}d', err.code);
        });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Failed to apply viewport fix');
    }
  }

  /**
   * 窗口尺寸变化后通知网页重排（已完成防抖）。
   *
   * 自由多窗拖拽时 onAreaChange 会高频触发，这里只保留「最后一次」，
   * 窗口稳定后才通知一次。**不重载页面** —— 重载会闪烁且丢掉正在输入的内容。
   */
  private scheduleViewportResize(): void {
    if (this.viewportResizeTimer !== -1) {
      clearTimeout(this.viewportResizeTimer);
    }
    this.viewportResizeTimer = setTimeout(() => {
      this.viewportResizeTimer = -1;
      this.notifyViewportResize();
    }, VIEWPORT_RESIZE_DEBOUNCE_MS);
  }

  /** 补发一次 resize 事件，唤醒「只在加载时读一次宽度」的 SPA */
  private notifyViewportResize(): void {
    // 窗口宽度变了 → 布局视口宽度也必须跟着变，否则页面仍按旧宽度排版
    //（自由多窗拖拽时宽度连续变化，这里已经过防抖）
    this.applyViewportFix();
    try {
      this.controller.runJavaScript(buildResizeNotifyScript())
        .then((result: string) => {
          hilog.info(DOMAIN, TAG, 'Viewport resize notified: %{public}s', result);
        })
        .catch((err: BusinessError) => {
          hilog.warn(DOMAIN, TAG, 'resize notify failed: %{public}d', err.code);
        });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Failed to notify viewport resize');
    }
  }

  /**
   * 打印一次运行时视口诊断。
   *
   * 为什么需要它：本应用无法在设备上调试，而「viewport 到底有没有生效」只能看运行时的
   * 真实数值。关键看 **clientW 是否随窗口宽度变化**：
   *   · clientW 跟随窗口宽度  → viewport 已生效，方案奏效；
   *   · clientW 固定在 ~980   → 说明 metaViewport(true) 的覆盖没生效，
   *     此时把 common/WebViewport 的 APPEND_MOBILE_UA_TOKEN 改为 true 兜底。
   * 顺带打印输入框的实际高度，用于判断高度上限是否命中。
   */
  private probeViewport(): void {
    // 顺带打印「网页能否后退 / 是否对话界面」：返回手势策略依赖这两个值
    try {
      if (this.controllerReady) {
        hilog.info(DOMAIN, TAG, 'Web back state canGoBack=%{public}s onChatRoot=%{public}s',
          String(this.controller.accessBackward()),
          String(isChatRootPage(this.controller.getUrl())));
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Failed to read web back state in probe');
    }
    try {
      this.controller.runJavaScript(buildProbeScript())
        .then((result: string) => {
          hilog.info(DOMAIN, TAG, 'Viewport probe: %{public}s', result);
        })
        .catch((err: BusinessError) => {
          hilog.warn(DOMAIN, TAG, 'viewport probe failed: %{public}d', err.code);
        });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Failed to run viewport probe');
    }
  }

  /**
   * 装上「点图片不聚焦输入框」的防护脚本。
   *
   * 与内核侧的两个开关配合，覆盖它们管不到的那条路径：
   *   · .blurOnKeyboardHideMode(BLUR) + setSoftKeyboardBehaviorMode(...)
   *     —— 消除内核基于残留焦点的自动弹键盘；
   *   · 本脚本 —— 应对网页自己把焦点移回输入框（例如把「点击输入区即聚焦」
   *     的处理器挂在了包含图片预览的容器上，点图片冒泡上去就聚焦了）。
   *
   * 脚本的防误伤设计见 common/WebInputGuard 的模块注释。
   */
  private applyWebInputGuard(): void {
    if (!ENABLE_IMAGE_TAP_FOCUS_GUARD) {
      return;
    }
    try {
      this.controller.runJavaScript(buildFocusGuardScript())
        .then((result: string) => {
          hilog.info(DOMAIN, TAG, 'Focus guard: %{public}s', result);
        })
        .catch((err: BusinessError) => {
          hilog.warn(DOMAIN, TAG, 'focus guard failed: %{public}d', err.code);
        });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Failed to install focus guard');
    }
  }

  /**
   * 启动调试用的诊断取样定时器（仅在 DEBUG_PROBE_INTERVAL_MS > 0 时生效）。
   * 便于在「键盘开着、输入框里有长文本」的任意时刻抓取一次运行时快照。
   */
  private startDebugProbe(): void {
    if (DEBUG_PROBE_INTERVAL_MS <= 0) {
      return;
    }
    this.debugProbeTimer = setInterval(() => {
      this.probeViewport();
    }, DEBUG_PROBE_INTERVAL_MS);
    hilog.info(DOMAIN, TAG, 'Debug probe interval started: %{public}d ms', DEBUG_PROBE_INTERVAL_MS);
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
                window.location.href = '${SHARE_SCHEME_PREFIX}' + encodeURIComponent(text);
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

  /** 读取应用版本名（供 User-Agent 使用）；读取失败返回空串，不影响网页加载 */
  private appVersionName(): string {
    try {
      return bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT).versionName;
    } catch (err) {
      return '';
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
      // 只有离开聊天主站后才提供返回入口（精确匹配 host，见 UrlRules.isChatHost）
      this.showBackButton = !isChatHost(pageUrl);
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

  /**
   * 处理网页的权限请求。
   *
   * 官方链路分两步，缺一不可：
   *   1. 网页 → 应用：在 onPermissionRequest 里决定 grant / deny；
   *   2. 应用 → 系统：应用自身必须已持有对应系统权限（user_grant 需运行时申请）。
   * 只做第 1 步时网页会以为已授权、实际采不到数据，语音输入表现为「按了没反应」。
   *
   * 放行范围严格与 module.json5 的声明保持一致：目前只放行语音输入所需的麦克风，
   * 其余资源（摄像头 / 传感器 / MIDI）一律拒绝，不申请用不到的敏感权限。
   */
  private async handleWebPermissionRequest(request: PermissionRequest): Promise<void> {
    let resources: Array<string> = [];
    try {
      resources = request.getAccessibleResource();
      hilog.info(DOMAIN, TAG, 'Web permission request from %{public}s: %{public}s',
        request.getOrigin(), resources.join(','));
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Failed to read permission request');
      request.deny();
      return;
    }

    if (!resources.includes(ProtectedResourceType.AUDIO_CAPTURE)) {
      hilog.info(DOMAIN, TAG, 'Deny resource that the app has not declared');
      request.deny();
      return;
    }

    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const granted: boolean = await ensurePermission(context, MICROPHONE_PERMISSION);
      if (!granted) {
        // 系统权限没拿到就没必要再打扰用户，直接拒绝（网页会收到 denied）
        request.deny();
        return;
      }
      this.confirmWebMicrophone(request, resources);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Permission flow failed');
      request.deny();
    }
  }

  /** 系统权限就绪后，再向用户确认是否允许**当前网页**使用麦克风 */
  private confirmWebMicrophone(request: PermissionRequest, resources: Array<string>): void {
    try {
      this.getUIContext().getPromptAction().showDialog({
        title: $r('app.string.permission_request_title'),
        message: $r('app.string.permission_request_mic'),
        buttons: [
          { text: $r('app.string.common_deny'), color: $r('app.color.text_button_secondary') },
          { text: $r('app.string.common_agree'), color: $r('app.color.accent') }
        ]
      }).then((result: promptAction.ShowDialogSuccessResponse) => {
        // 按钮顺序为 [拒绝, 同意]，index 1 才是同意
        if (result.index === 1) {
          request.grant(resources);
        } else {
          request.deny();
        }
      }).catch((err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'Permission dialog failed: %{public}d', err.code);
        // 弹窗失败时保守拒绝：绝不能在用户无感知的情况下放行麦克风
        request.deny();
      });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Failed to show permission dialog');
      request.deny();
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
        // 键盘高度变化会改变悬浮操作条的可用范围，
        // 由 FloatingBar 的 @Watch 自行重算边界与避让量，页面无需再手动介入。
        // 同时把「键盘是否弹起」推给网页：编辑历史消息时据此隐藏主对话框。
        this.syncKeyboardStateToWeb(vp > 0);
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
   * 恢复页面侧持有的界面偏好：刷新按钮开关、「不再显示刷新确认」。
   * 悬浮操作条的拖拽位置与「长按可拖动」提示归 FloatingBar 自己管。
   * 存储读取失败都不影响使用，只是回到默认值。
   */
  private restoreUiPrefs(): void {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.refreshButtonEnabled = isRefreshButtonEnabled(ctx);
      this.refreshSkipConfirm = isRefreshConfirmSkipped(ctx);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Failed to restore UI prefs');
    }
  }

  /**
   * 悬浮操作条点「刷新」后的业务决策。
   *
   * 手势状态（长按拖拽后抑制本次点击）留在 FloatingBar 内部，
   * 这里只回答「要不要先弹确认框」——「不再显示」偏好与确认弹窗都归页面所有。
   */
  private onFloatingRefresh(): void {
    if (this.refreshSkipConfirm) {
      this.doRefresh();
    } else {
      this.noMoreRefreshPrompt = false;
      this.showRefreshConfirm();
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
   * 设置面板的 builder。
   *
   * bindSheet 需要的是一个 CustomBuilder，因此这里保留一个极薄的 @Builder，
   * 只做「属性进、回调出」的转接；面板内容本身在 components/SettingsSheet.ets，
   * 那里全部使用官方组件（Toggle / Divider）与语义化颜色资源，深浅色自动适配。
   */
  @Builder
  settingsSheet() {
    SettingsSheet({
      refreshButtonEnabled: this.refreshButtonEnabled,
      onToggleRefresh: (enabled: boolean) => this.onToggleRefreshButton(enabled),
      onClearCache: () => this.clearAppCache(),
      onOpenFeedback: () => this.openInSystemBrowser(FEEDBACK_URL),
      onClose: () => {
        this.showSettings = false;
      }
    })
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
      // 降级也必须留在当前页：直接回首页会把用户正在进行的会话丢掉。
      // getUrl 在控制器未挂载时同样会抛异常，因此单独兜一层。
      let current: string = '';
      try {
        current = this.controller.getUrl();
      } catch (e) {
        current = '';
      }
      this.navigateToUrl(current !== '' ? current : DEEPSEEK_URL);
    }
  }

  // 注册 Web 下载代理：处理下载开始/进度/完成/失败，下载完成后可另存至公开目录
  private setupDownloadDelegate(): void {
    try {
      // guid → 沙箱中转路径。落盘文件名为 `<guid>_<净化后的原始名>`：
      // 既避免同名并发下载互相覆盖，又能从路径反推出用户可见的文件名。
      const downloadPathMap: Map<string, string> = new Map<string, string>();

      this.delegate.onBeforeDownload((webDownloadItem: webview.WebDownloadItem) => {
        const guid: string = webDownloadItem.getGuid();
        const cacheDir: string = this.getUIContext().getHostContext()!.cacheDir;
        // 服务端给出的文件名不可信：先净化，避免路径穿越与非法字符导致落盘失败
        const safeName: string = sanitizeFileName(webDownloadItem.getSuggestedFileName());
        ensureDownloadTempDir(cacheDir);
        const cachePath: string = buildDownloadTempPath(cacheDir, guid, safeName);
        hilog.info(DOMAIN, TAG, 'Download start: %{public}s, guid=%{public}s', safeName, guid);
        downloadPathMap.set(guid, cachePath);
        webDownloadItem.start(cachePath);
      });

      this.delegate.onDownloadUpdated((webDownloadItem: webview.WebDownloadItem) => {
        const percent: number = webDownloadItem.getPercentComplete();
        hilog.info(DOMAIN, TAG, 'Download progress: %{public}d%%', percent);
      });

      this.delegate.onDownloadFinish((webDownloadItem: webview.WebDownloadItem) => {
        const guid: string = webDownloadItem.getGuid();
        const savePath: string | undefined = downloadPathMap.get(guid);
        hilog.info(DOMAIN, TAG, 'Download finish: %{public}s', guid);
        downloadPathMap.delete(guid);
        // 此处不再提示"下载完成"：文件此刻只在应用沙箱内，尚未落到用户可见目录。
        // 保存成功由 saveToPublicDownload 里的 toast_save_done 提示；用户若取消
        // 保存对话框则不作提示 —— 原先在此处提前弹"下载完成"，取消后会造成误导。
        if (savePath) {
          // 文件名以沙箱实际落盘的名字为准（已净化，且与待复制的中转文件一一对应）
          this.saveToPublicDownload(fileNameFromTempPath(savePath, guid), savePath);
        } else {
          hilog.warn(DOMAIN, TAG, 'Download finished but sandbox path missing, guid=%{public}s', guid);
        }
      });

      this.delegate.onDownloadFailed((webDownloadItem: webview.WebDownloadItem) => {
        const guid: string = webDownloadItem.getGuid();
        hilog.error(DOMAIN, TAG, 'Download failed: code=%{public}d, guid=%{public}s',
          webDownloadItem.getLastErrorCode(), guid);
        // 清掉半截的中转文件与映射，避免残留占用空间
        const failedPath: string | undefined = downloadPathMap.get(guid);
        if (failedPath) {
          removeDownloadTempFile(failedPath);
          downloadPathMap.delete(guid);
        }
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
          // 用户取消或未选择目录：清掉中转文件，避免沙箱里堆积副本
          removeDownloadTempFile(srcPath);
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
          // 无论复制成功与否，中转文件都不再需要：成功了内容已进公共目录，
          // 失败了也没有保留价值。缺了这一步，每下载一次就在沙箱里永久留一份副本。
          removeDownloadTempFile(srcPath);
        }
      }).catch((err: BusinessError) => {
        hilog.info(DOMAIN, TAG, 'User cancelled save dialog');
        removeDownloadTempFile(srcPath);
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
