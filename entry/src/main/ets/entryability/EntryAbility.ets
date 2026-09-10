import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { webview } from '@kit.ArkWeb';
import { window } from '@kit.ArkUI';
import { url } from '@kit.ArkTS';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { i18n } from '@kit.LocalizationKit';
import { DEEPSEEK_URL, DEEPSEEK_HOST } from '../common/AppConfig';
import { cleanupPhotoTempFiles } from '../common/PhotoTempFiles';

const DOMAIN = 0x0001;
const TAG = 'DeepSeekEntryAbility';
let webEngineInitialized: boolean = false;
let mainWindowClass: window.Window | null = null;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // Web引擎只初始化一次，避免重复初始化导致异常
    if (!webEngineInitialized) {
      try {
        webview.WebviewController.initializeWebEngine();
        // 预解析、预连接首页域名，加速首屏加载（须在 initializeWebEngine 之后调用）
        webview.WebviewController.prepareForPageLoad(DEEPSEEK_URL, true, 2);
        webEngineInitialized = true;
        hilog.info(DOMAIN, TAG, 'WebEngine initialized & preconnected');
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'Failed to initialize WebEngine');
      }
    }

    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to set colorMode');
    }

    // 将当前系统颜色模式存入 AppStorage，供 WebView 深色模式适配
    AppStorage.setOrCreate<ConfigurationConstant.ColorMode>('currentColorMode', this.context.config.colorMode);
    hilog.info(DOMAIN, TAG, 'Initial colorMode: %{public}d', this.context.config.colorMode);

    // 将当前系统语言存入 AppStorage，供 WebView 语言适配
    try {
      const systemLanguage: string = i18n.System.getSystemLanguage();
      AppStorage.setOrCreate<string>('systemLanguage', systemLanguage);
      hilog.info(DOMAIN, TAG, 'Initial systemLanguage: %{public}s', systemLanguage);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to get system language');
    }

    // 处理Deep Link跳转（冷启动）
    this.handleDeepLink(want);

    // 清理上次运行遗留的拍照临时文件。
    // handleTakePhoto 预创建的文件在上传成功后不便立即删除（WebView 可能仍在校验读取），
    // 因此改为启动时统一清理 —— 此刻不可能有上传在进行，安全且能让目录自愈。
    cleanupPhotoTempFiles(this.context.filesDir);

    // 非DeepLink启动：清空残留URL，防止旧值干扰
    if (!want?.uri) {
      AppStorage.setOrCreate('deepLinkUrl', '');
    }

    hilog.info(DOMAIN, TAG, 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'Ability onDestroy');
  }

  // 监听系统深色/浅色模式切换，同步更新 AppStorage 与状态栏样式
  onConfigurationUpdate(newConfig: Configuration): void {
    const newColorMode: ConfigurationConstant.ColorMode | undefined = newConfig.colorMode;
    if (newColorMode === undefined) {
      return;
    }
    const currentColorMode: ConfigurationConstant.ColorMode | undefined = AppStorage.get('currentColorMode');
    if (currentColorMode !== newColorMode) {
      AppStorage.setOrCreate<ConfigurationConstant.ColorMode>('currentColorMode', newColorMode);
      hilog.info(DOMAIN, TAG, 'ColorMode changed: %{public}d -> %{public}d', currentColorMode, newColorMode);
      this.applyWindowBackground(newColorMode);
    }

    // 监听系统语言变化，同步更新 AppStorage
    const newLanguage: string | undefined = newConfig.language;
    if (newLanguage !== undefined) {
      const currentLanguage: string | undefined = AppStorage.get('systemLanguage');
      if (currentLanguage !== newLanguage) {
        AppStorage.setOrCreate<string>('systemLanguage', newLanguage);
        hilog.info(DOMAIN, TAG, 'Language changed: %{public}s -> %{public}s', currentLanguage, newLanguage);
      }
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, 'Succeeded in loading the content.');

      // 设置窗口全屏沉浸：内容延伸至状态栏后方，状态栏透明
      mainWindowClass = windowStage.getMainWindowSync();
      if (mainWindowClass) {
        // 立即设置窗口背景色，避免启动闪白/闪黑（与 DeepSeek 官网颜色一致）
        // 注：编译器对下面这行报 "This API is unavailable to phone, tablet, 2in1" 告警，
        // 但经核对：SDK 声明中该方法并无任何设备限定（@crossplatform since 10、@since 9），
        // 且真机（平板）实测调用成功、背景色生效。判定为编译期元数据误报（本项目
        // targetSdk 23 与 compileSdk 26 存在版本差）。请勿据此删除该调用，
        // 否则会失去启动防闪屏能力。
        const isDark: boolean =
          this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
        try {
          mainWindowClass.setWindowBackgroundColor(isDark ? '#FF1A1A1A' : '#FFFFFFFF');
        } catch (err) {
          hilog.warn(DOMAIN, TAG, 'setWindowBackgroundColor not supported');
        }

        // 窗口形态交由系统管理，不做自定义窗口部件：
        //   · 不启用旧式沉浸（setImmersiveModeEnabledState）
        //   · 不隐藏系统标题栏（setWindowDecorVisible）
        //   · 不改标题栏高度（setWindowDecorHeight）
        // 标题栏、状态栏，以及拖动 / 最大化 / 最小化 / 关闭全部由系统按官方规范提供。
        //
        // 仅额外开启「底部沉浸」：让布局延伸到系统栏区域，使内容铺到屏幕最底部。
        // 官方现状：全面屏手势导航条本身就是透明的，但它的颜色**无法单独设置**
        // （SystemBarProperties.navigationBarColor 只对传统三键导航栏生效），
        // 因此底部沉浸的唯一做法是 setWindowLayoutFullScreen(true) 取消默认避让，
        // 再由页面把底部 padding 留为 0。
        // 顶部不做沉浸：页面会按状态栏避让高度补 padding，视觉上仍是一条正常状态栏，
        // 那里用 statusBarContentColor 保证图标/文字可读。
        try {
          mainWindowClass.setWindowLayoutFullScreen(true);
          hilog.info(DOMAIN, TAG, 'Layout full screen enabled (bottom immersive)');
        } catch (err) {
          hilog.warn(DOMAIN, TAG, 'setWindowLayoutFullScreen not supported');
        }
      }
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'Ability onForeground');
    // 回到前台时按当前模式重新同步一次状态栏/窗口底色：
    // 深色模式可能在应用处于后台期间被系统改过，而那种情况下
    // onConfigurationUpdate 不保证会触发。此处不传参，读 context.config 即为最新值。
    this.applyWindowBackground();
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'Ability onBackground');
  }

  /**
   * 按深浅色模式设置窗口背景色与状态栏文字颜色。
   *
   * 背景色与 DeepSeek 官网保持一致，避免启动闪白/闪黑。
   * 状态栏文字颜色必须设置：底部沉浸开启后布局延伸到系统栏区域，状态栏变为透明、
   * 透出应用底色，若不反色会出现「白底白字」不可读。
   *
   * @param colorMode 调用方显式传入的新模式。**必须由 onConfigurationUpdate 传入** ——
   *   该方法触发时 this.context.config 可能尚未更新，若在此处重新读取会拿到旧值，
   *   导致切换深浅色后状态栏不反色。不传则回退到 context.config（启动时使用）。
   */
  private applyWindowBackground(colorMode?: ConfigurationConstant.ColorMode): void {
    if (!mainWindowClass) {
      return;
    }
    // 取值优先级：调用方显式传入 > context.config（启动/回前台时）
    // context.config.colorMode 本身是可选字段，取不到时按「未设置」处理（等同浅色）。
    let mode: ConfigurationConstant.ColorMode;
    if (colorMode !== undefined) {
      mode = colorMode;
    } else {
      const ctxMode: ConfigurationConstant.ColorMode | undefined = this.context.config.colorMode;
      mode = ctxMode !== undefined ? ctxMode : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    }
    const isDark: boolean = mode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;

    // 浅色→#FFFFFFFF（白）  深色→#FF1A1A1A（暗）
    try {
      const winBgColor: string = isDark ? '#FF1A1A1A' : '#FFFFFFFF';
      mainWindowClass.setWindowBackgroundColor(winBgColor);
      hilog.info(DOMAIN, TAG, 'Window bg color set: %{public}s (isDark=%{public}s)',
        winBgColor, String(isDark));
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'setWindowBackgroundColor not supported');
    }

    // 状态栏文字反色。setWindowSystemBarProperties 在 2in1 上不生效（SDK 明确说明），
    // 故 2in1 直接跳过，避免无谓的异步调用与误导性日志。
    if (deviceInfo.deviceType !== '2in1') {
      try {
        mainWindowClass.setWindowSystemBarProperties({
          statusBarContentColor: isDark ? '#FFFFFF' : '#000000'
        }).then(() => {
          hilog.info(DOMAIN, TAG, 'Status bar content color set (isDark=%{public}s)', String(isDark));
        }).catch((err: BusinessError) => {
          hilog.warn(DOMAIN, TAG, 'setWindowSystemBarProperties failed: %{public}d', err.code);
        });
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'setWindowSystemBarProperties exception');
      }
    }
  }

  /**
   * 热启动时接收新的Deep Link
   */
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'onNewWant');
    this.handleDeepLink(want);
  }

  /**
   * 解析并处理Deep Link URL
   * 支持的URL格式：https://chat.deepseek.com/share/...
   */
  private handleDeepLink(want: Want): void {
    const uri = want?.uri;
    if (!uri) {
      return;
    }

    hilog.info(DOMAIN, TAG, 'Received DeepLink URI: %{private}s', uri);

    try {
      const urlObject = url.URL.parseURL(uri);
      const host = urlObject.hostname;
      const path = urlObject.pathname;

      // 处理DeepSeek分享链接
      if (host === DEEPSEEK_HOST && path.startsWith('/share')) {
        hilog.info(DOMAIN, TAG, 'DeepSeek share link detected, navigating to: %{private}s', uri);
        AppStorage.setOrCreate('deepLinkUrl', uri);
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to parse DeepLink URI');
    }
  }
}
