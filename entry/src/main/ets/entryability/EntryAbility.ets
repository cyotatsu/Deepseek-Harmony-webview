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
      this.applyStatusBarStyle();
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

        // 手机/平板：窗口沉浸式布局，内容延伸至状态栏后方
        // setWindowLayoutFullScreen 已废弃，使用 setImmersiveModeEnabledState 替代
        try {
          mainWindowClass.setImmersiveModeEnabledState(true);
          hilog.info(DOMAIN, TAG, 'Immersive mode enabled');
        } catch (err) {
          hilog.warn(DOMAIN, TAG, 'setImmersiveModeEnabledState not supported');
        }

        // 系统标题栏的显隐按窗口模式决定，而不是一律隐藏。
        //
        // 应用市场、设置等系统应用从不隐藏系统标题栏，因此它们在自由多窗下天然带有
        // 「图标 + 应用名 + 最大化/最小化/关闭」，也天然可以拖动窗口。本应用为沉浸
        // 外观隐藏了标题栏 —— 而 SDK 说明指出：标题栏隐藏后，主窗口进入全屏时
        // **只有鼠标光标悬停热区**才会浮出标题栏；触屏没有悬停，于是自由多窗下既没有
        // 应用标识、也没有拖动入口。
        //
        // 因此：自由多窗下保留系统标题栏（与其它应用表现一致，且它是拖动窗口的唯一
        // 入口）；其余形态（含平板正常使用时的全屏）维持隐藏以保持沉浸。
        const applyDecor = (win: window.Window | null): void => {
          if (!win) {
            return;
          }
          let keepDecor: boolean = true;
          try {
            keepDecor = win.isInFreeWindowMode();
          } catch (err) {
            hilog.warn(DOMAIN, TAG, 'isInFreeWindowMode not available, keep decor shown');
          }
          try {
            win.setWindowDecorVisible(keepDecor);
            hilog.info(DOMAIN, TAG, 'Window decor visible: %{public}s', String(keepDecor));
          } catch (err) {
            hilog.warn(DOMAIN, TAG, 'setWindowDecorVisible not available');
          }
        };
        applyDecor(mainWindowClass);
        try {
          mainWindowClass.on('freeWindowModeChange', (inFreeWindowMode: boolean) => {
            hilog.info(DOMAIN, TAG, 'Free window mode changed: %{public}s', String(inFreeWindowMode));
            applyDecor(mainWindowClass);
          });
        } catch (err) {
          hilog.warn(DOMAIN, TAG, 'freeWindowModeChange listener not available');
        }
        try {
          mainWindowClass.setWindowDecorHeight(40);
          hilog.info(DOMAIN, TAG, 'Window decor height set to 40');
        } catch (err) {
          hilog.warn(DOMAIN, TAG, 'setWindowDecorHeight not available');
        }

        // 初始设置状态栏内容颜色（根据当前模式）
        this.applyStatusBarStyle();
      }
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'Ability onBackground');
  }

  /**
   * 设置状态栏透明 + 窗口背景 + 内容颜色跟随深色/浅色模式
   * 手机端：状态栏背景透明，透出 DeepSeek 网页顶部背景色
   * 2in1端：窗口背景色与 DeepSeek 官网一致，隐藏标题栏 logo/文字后实现沉浸
   */
  private applyStatusBarStyle(): void {
    if (!mainWindowClass) {
      return;
    }
    const isDark: boolean =
      this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;

    // 状态栏透明 + 内容文字颜色适配。
    // setWindowSystemBarProperties 在 2in1 上不生效（SDK 文档明确说明
    // "This API does not take effect on 2-in-1 devices"），故 2in1 直接跳过，
    // 既省掉一次无意义的异步调用，也避免打出会误导排查的 "StatusBar updated" 日志。
    if (deviceInfo.deviceType !== '2in1') {
      const sysBarProps: window.SystemBarProperties = {
        statusBarColor: '#00000000',
        statusBarContentColor: isDark ? '#FFFFFF' : '#000000'
      };
      try {
        mainWindowClass.setWindowSystemBarProperties(sysBarProps).then(() => {
          hilog.info(DOMAIN, TAG, 'StatusBar updated');
        }).catch((err: BusinessError) => {
          hilog.warn(DOMAIN, TAG, 'setWindowSystemBarProperties failed: %{public}d', err.code);
        });
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'applyStatusBarStyle exception');
      }
    }

    // 设置窗口背景色，与 DeepSeek 官网颜色一致
    // 浅色→#FFFFFFFF（白）  深色→#FF1A1A1A（暗）
    // 2in1端隐藏标题栏后，窗口背景会从标题栏区域透出，颜色需与网页顶部一致
    try {
      const winBgColor: string = isDark ? '#FF1A1A1A' : '#FFFFFFFF';
      mainWindowClass.setWindowBackgroundColor(winBgColor);
      hilog.info(DOMAIN, TAG, 'Window bg color set: %{public}s', winBgColor);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'setWindowBackgroundColor not supported');
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
