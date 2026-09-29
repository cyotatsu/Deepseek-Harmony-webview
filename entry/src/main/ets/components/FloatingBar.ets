import { common } from '@kit.AbilityKit';
import { curves, display, window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { loadRefreshButtonOffset, saveRefreshButtonOffset,
  loadRefreshButtonSnapped, setRefreshButtonSnapped } from '../common/UiPrefs';
import { KEY_FAB_HIDE_ON_SNAP, KEY_FAB_AUTO_SNAP, KEY_FAB_RESET_POS } from '../common/AppConfig';
import { FloatGeometry, SnapResult, snapToNearestEdge, keyboardLift,
  clampDragX, clampDragY, cxAtLeftEdge, cxAtRightEdge, cxWhenUnsnapped, minCenterY, maxCenterY,
  snapToNearestEdgeWithin, swipeSnapEdge, autoSnapEdge, relayoutCenterX, EDGE_LEFT, EDGE_RIGHT }
  from '../common/FloatingLayout';

const DOMAIN = 0x0001;
const TAG = 'DeepSeekFloatingBar';

/**
 * 折叠式悬浮按钮（主按钮 + 向上展开的子菜单）。
 *
 * 设计目标：**最大化减少对网页内容的遮挡**。默认只留一颗 48vp 的圆形主按钮，
 * 其余功能收进弹出子菜单，并配合自动贴边 / 边缘半隐藏 / 闲置透明化。
 *
 * 交互约定：
 *   · 点主按钮（三条横线）→ 展开 / 收起；
 *   · 子菜单**固定向上展开**；「不延伸到状态栏后面」由纵向下限保证
 *     （见 common/FloatingLayout 的 minCenterY：下限里含子菜单整段高度），
 *     因此**不需要任何方向判断**；
 *   · 长按后拖动，松手在**靠近边缘时**吸附、中间区域自由悬停；
 *   · 键盘弹出时按钮会被抬高避让；
 *   · 3 秒无操作整体渐隐到 0.3；一触摸立即恢复；
 *   · 点网页空白处 → 由页面侧调用 onReady 回传的回调收起。
 */
@Component
export struct FloatingBar {
  // ── 来自页面 ──
  /**
   * 按钮可用区域的宽/高（vp），由页面测量后传入。
   *
   * 用 @Prop + @Watch：页面在 onAreaChange 里拿到真实可用区（悬浮窗 / 自由多窗下
   * 不等于整屏）后更新，必须能触发重新定位。
   */
  @Prop @Watch('onMetricsChange') pageW: number = 0;
  @Prop @Watch('onMetricsChange') pageH: number = 0;
  @Prop @Watch('onMetricsChange') keyboardHeightVp: number = 0;
  /** 承载本组件的窗口左上角在屏幕坐标中的位置（vp）；同窗口场景为 0 */
  @Prop winX: number = 0;
  @Prop winY: number = 0;
  /** 刷新子按钮是否启用（开关在设置面板里，状态由页面持有） */
  @Prop refreshEnabled: boolean = true;

  // ── 来自设置面板（经 AppStorage，二者无直接引用）──
  /** 左右贴边时是否半隐藏 */
  @StorageLink(KEY_FAB_HIDE_ON_SNAP) @Watch('onLayoutPrefChange') hideOnSnap: boolean = true;
  /** 是否启用空闲自动吸附 */
  @StorageLink(KEY_FAB_AUTO_SNAP) autoSnapEnabled: boolean = true;
  /** 请求重置位置（写 true 后由本组件复位并清零） */
  @StorageLink(KEY_FAB_RESET_POS) @Watch('onResetRequested') resetRequested: boolean = false;

  // ── 回给页面 ──
  onRefresh: () => void = () => {};
  onOpenSettings: () => void = () => {};
  /** 把「收起」能力交给页面：点网页空白处时由页面调用它 */
  onReady: (collapse: () => void) => void = () => {};
  /**
   * 拖动状态变化回调：拖动期间手指会滑出按钮、落到网页上，
   * 可能让网页聚焦输入框而误弹键盘。组件不便处理（拖动中改视图结构会打断手势），
   * 因此把状态抛给页面，由页面用内核级手段一次性压制。
   */
  onDragStateChange: (dragging: boolean) => void = () => {};

  // ── 自身状态 ──
  /** 主按钮中心点（相对根 Stack 左上角，vp） */
  @State btnCx: number = 0;
  @State btnCy: number = 0;
  @State isExpanded: boolean = false;
  /**
   * 是否处于「吸附到边缘」的状态（左右贴边为半隐藏）。
   *
   * 用于两段式点击：**第一次点按只解除吸附、让按钮完整归位，第二次点按才展开子菜单**。
   * 吸附态由「拖动松手」与「首次默认贴边」置位，由 {@link unsnap} 清除。
   */
  @State snapped: boolean = true;
  /** 已进入拖动态（长按已触发）：高亮 + 放大 + 描边 */
  @State isDragging: boolean = false;
  /** 手指按住按钮（未达长按时长也算）：给一点轻微反馈 */
  @State isPressed: boolean = false;
  /** 闲置透明化：3 秒无操作后降到 0.3 */
  @State idleFaded: boolean = false;

  // ── 尺寸常量（vp） ──
  /**
   * 主按钮视觉直径。
   * 与图标同步放大到 48vp：图标 30vp 配 48vp 按钮约六成占比，视觉最平衡。
   */
  private readonly FAB_SIZE: number = 48;
  /** 主按钮命中区域边长：比视觉尺寸大一圈，更好按（视觉仍是 48 的圆） */
  private readonly FAB_HIT_SIZE: number = 56;
  /**
   * 主按钮**响应区域**边长（vp）：比命中区每侧外扩 20vp，容错"手指按偏"。
   *
   * 只影响命中测试（见 build 的 responseRegion），**不改变视觉尺寸与遮挡面积**。
   * 太小则手指按偏时触摸穿透到下层 Web 组件，触发网页的文本选择放大镜；
   * 太大（曾用到每侧 56vp）则那圈区域内的网页文字既选不中也点不动，遮挡感重。
   */
  private readonly FAB_TOUCH_SIZE: number = 96;
  /** 子按钮直径（图标 25vp 配 44vp，占比与主按钮一致） */
  private readonly SUB_SIZE: number = 44;
  /** 子按钮之间、以及子按钮与主按钮之间的间距 */
  private readonly SUB_GAP: number = 10;
  /** 吸附后距屏幕边缘的安全边距（配合半隐藏） */
  private readonly EDGE_MARGIN: number = 5;
  /** 拖动时保留的边距：保证按钮始终完整可见（比吸附边距大） */
  private readonly DRAG_MARGIN: number = 24;
  /** 右下角默认位置距边缘的边距 */
  private readonly DEFAULT_MARGIN: number = 20;
  /**
   * 顶部系统安全区（状态栏高度，vp）。
   *
   * 为什么必须留：贴顶吸附后按钮若紧贴屏幕最上沿就会落进**状态栏**，
   * 触摸被系统截走 —— 实机现象正是「按钮可见但点不动」，展开也无从谈起。
   * 初值 40vp（多数平板的横屏状态栏高度），aboutToAppear 里会用系统避免区实测值覆盖。
   */
  private topSafeInset: number = 40;
  /** 右上角「控制中心」热区宽度（vp）：贴右边缘且比这更靠上时需额外下移 */
  private readonly CONTROL_CENTER_INSET: number = 72;
  /** 边缘半隐藏比例：中心比屏幕边缘外移该比例 × 直径 */
  private readonly HIDE_RATIO: number = 0.4;
  /** 由设置决定的有效半隐藏比例：关闭「贴边半隐藏」时为 0（完整显示） */
  private effHideRatio(): number {
    return this.hideOnSnap ? this.HIDE_RATIO : 0;
  }
  /**
   * 解除吸附后相对竖边的额外内缩量（vp）。
   *
   * **刻意取小值**：解除吸附只需要「按钮完整可见」，因此最小内缩即可。
   * 取大值会让按钮离边缘过远、看起来"漂"在页面中间（实机反馈），
   * 同时也不必要地遮挡更多网页内容。
   */
  private readonly UNSNAP_INSET: number = 4;
  /**
   * 进入拖动所需的**长按时长**（ms）。
   *
   * 400ms 是上一版验证过的值；本轮收到 320ms，目的是缩短"按住不动"的窗口，
   * 降低系统把这串触摸判定为长按手势、进而弹出「放大显示」的概率
   *（系统放大要等长按成立后再持续一小段，320ms 通常已进入拖动、触摸被消费）。
   * 不要再往下压：太短会和轻点/滑动混淆，导致点击被误判成拖动。
   */
  private readonly LONG_PRESS_MS: number = 320;
  /**
   * 闲置时的不透明度。
   *
   * 原为 0.3。深色模式下按钮底与网页底本就接近，淡到 0.3 后几乎认不出是按钮
   *（实机取样：唤醒时是正常灰底，闲置时淡到与页面底几乎同色）。
   * 取 0.55 既保留"闲置"的提示，又不至于看不见。
   */
  private readonly IDLE_FADED_OPACITY: number = 0.55;
  /** 闲置多久开始渐隐（毫秒） */
  private readonly IDLE_FADE_MS: number = 3000;
  /** 闲置渐隐动画时长（毫秒） */
  private readonly FADE_DURATION_MS: number = 260;
  /** 弹出 / 吸附动画时长 */
  private readonly SPRING_MS: number = 340;

  // 手势基准
  private dragBaseCx: number = 0;
  private dragBaseCy: number = 0;
  private idleTimer: number = -1;
  // ── 位置持久化 ──
  /** 上次保存的位移（相对右下角默认位置）；拿到页面尺寸后换算成屏幕坐标 */
  private savedDx: number = 0;
  private savedDy: number = 0;
  /** 是否存在有效的位置记录 */
  private hasSavedPos: boolean = false;
  /** 上次保存时是否处于贴边态（未贴边就不要恢复成贴边） */
  private snappedPref: boolean = true;
  /**
   * 当前吸附在哪条竖边（EDGE_LEFT / EDGE_RIGHT；未吸附为空串）。
   *
   * ⚠️ 必须**记住**这条边，不能每次按当前位置重新推导：
   * 窗口尺寸变化时位置会被夹取，夹完可能落到另一半，
   * 于是「右 → 小窗 → 全屏」会变成贴左边（实机复现）。
   */
  private snappedEdge: string = EDGE_RIGHT;
  /** 屏幕尺寸（vp）：仅作最后兜底用，正常定位用 boundsW/boundsH（窗口尺寸） */
  private screenW: number = 0;
  private screenH: number = 0;
  /**
   * 「顺向甩动吸附」的位移阈值（vp）。
   *
   * 取 48vp（约按钮直径）：够大到不会被拖动中的抖动误判为甩动，
   * 又够小到一次轻快的横向甩手就能触发。
   */
  private readonly SWIPE_SNAP_PX: number = 48;
  /** 拖动过程中最近一次横向位移（vp），松手时用于判断顺向甩动 */
  private lastOffX: number = 0;
  /** 拖动过程中最近一次纵向位移（vp） */
  private lastOffY: number = 0;
  /**
   * 「空闲自动吸附」的邻近判定距离（vp）。
   *
   * 比拖动吸附阈值（边距 + 半径 ≈ 48vp）宽一些：空闲兜底是**帮用户归位**，
   * 可以比"手动拖到边上才吸"更宽容；取 120vp 约屏幕宽度的 1/9，
   * 中间区域（自由悬停）仍不会被自动搬走。
   */
  private readonly AUTO_SNAP_NEAR_PX: number = 120;
  /** 是否已经完成一次「位置恢复或默认落位」——防止默认位置覆盖已恢复的位置 */
  private posRestored: boolean = false;
  /**
   * 偏好是否已读取完毕。
   *
   * onMetricsChange 在 prefsRead 为 false 时必须**直接返回**：
   * readScreenSize() 会先于 restorePrefs() 触发它，若此时就落位，
   * 按钮会被放到默认位置、恢复逻辑随后失效（实机 bug：重载后位置从不恢复）。
   */
  private prefsRead: boolean = false;

  aboutToAppear(): void {
    // 先量顶部系统安全区，再定位 —— 贴顶吸附的下限要用到它
    this.readTopSafeInset();
    // 尺寸自给：不依赖 pageW/pageH 这两个 Prop 的到达时机。
    // 同窗口场景下页面会通过 onAreaChange 传入更准确的可用区（@Prop @Watch 会重新定位）；
    // 这里只在页面还没给出值时用屏幕尺寸兜底，避免按钮停在容器原点（实机踩过：点不中）。
    this.readScreenSize();
    this.restorePrefs();
    this.scheduleIdleFade();
    try {
      this.onReady(() => this.collapse());
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'onReady callback failed');
    }
  }

  /**
   * 量取顶部系统安全区高度（状态栏 + 余量，vp）。
   *
   * 用窗口避免区（AvoidAreaType.TYPE_SYSTEM）的实测高度加 8vp 余量；
   * 取不到时保留保守默认值 52vp —— 宁可多留一点，也不要让按钮落进状态栏
   *（实机现象：按钮可见但触摸被系统截走、完全点不动）。
   */
  private readTopSafeInset(): void {
    // 用**回调重载**：ArkTS 下 getLastWindow 的 Promise 重载会把返回类型推断成
    // void & Promise<Window>，且 ArkTS 禁止用 unknown 中转，因此走回调形式。
    try {
      window.getLastWindow(this.getUIContext().getHostContext(),
        (err: BusinessError, win: window.Window) => {
          if (err && err.code) {
            hilog.warn(DOMAIN, TAG, 'getLastWindow failed, keep default inset');
            return;
          }
          try {
            const area: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
            const h: number = this.getUIContext().px2vp(area.topRect.height);
            if (h > 0) {
              // 直接用状态栏实测高度，**不加额外余量** ——
              // 加了余量会让"纵向下限 = 安全区 + 半径"偏高，按钮拖不到顶部（实机反馈）。
              this.topSafeInset = h;
              // 安全区变化会影响贴顶下限，重新定位一次
              this.onMetricsChange();
              hilog.info(DOMAIN, TAG, 'Top safe inset = %{public}dvp (statusBar %{public}d)',
                Math.round(this.topSafeInset), Math.round(h));
            }
          } catch (e) {
            hilog.warn(DOMAIN, TAG, 'read avoid area failed: %{public}s', JSON.stringify(e));
          }
        });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'readTopSafeInset failed, keep default %{public}d: %{public}s',
        this.topSafeInset, JSON.stringify(err));
    }
  }

  /**
   * 读取屏幕尺寸作为活动范围（vp）。
   *
   * 只在 Prop 还没给出有效尺寸时兜底：同窗口场景下 pageW/pageH 由页面测量得到，
   * 那比屏幕尺寸更准确（例如悬浮窗/自由多窗下不等于整屏），仍以页面值为准。
   */
  private readScreenSize(): void {
    // 只记录屏幕尺寸作为**最后兜底**，绝不作为定位依据：
    // 定位一律用 boundsW/boundsH（窗口尺寸），否则小窗下按钮会被放到窗口外。
    try {
      const d: display.Display = display.getDefaultDisplaySync();
      this.screenW = this.getUIContext().px2vp(d.width);
      this.screenH = this.getUIContext().px2vp(d.height);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'readScreenSize failed: %{public}s', JSON.stringify(err));
    }
    if (this.pageW > 0 && this.pageH > 0) {
      return;   // 页面已给出窗口尺寸，无需兜底
    }
    // 页面还没测量：先用屏幕尺寸占位，等 onAreaChange 传入真实窗口尺寸后会重新夹取
    if (this.screenW > 0 && this.screenH > 0) {
      this.pageW = this.screenW;
      this.pageH = this.screenH;
      hilog.info(DOMAIN, TAG, 'Window metrics fallback to screen %{public}dx%{public}dvp',
        Math.round(this.screenW), Math.round(this.screenH));
      this.onMetricsChange();
    }
  }

  aboutToDisappear(): void {
    this.clearIdleTimer();
  }

  // ────────────────────────── 位置与边界 ──────────────────────────

  /** 子菜单整体高度（含与主按钮的间距） */
  private subStackHeight(): number {
    const count: number = this.refreshEnabled ? 2 : 1;
    return this.SUB_SIZE * count + this.SUB_GAP * count;
  }

  /**
   * 设置里的布局项变了（目前是「贴边半隐藏」）：重新落位一次，
   * 否则要等用户拖动才会用上新比例。
   */
  private onLayoutPrefChange(): void {
    if (this.posRestored) {
      this.relayoutForWindow();
    }
  }

  /**
   * 设置面板请求「重置悬浮按钮位置」：清掉记录并把按钮放回默认位置。
   * 复位后把请求键清零，避免下次渲染重复触发。
   */
  private onResetRequested(): void {
    if (!this.resetRequested) {
      return;
    }
    this.resetRequested = false;
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      // 位移清零 = 回到默认位置（存的是相对默认位置的位移）
      saveRefreshButtonOffset(ctx, 0, 0);
      setRefreshButtonSnapped(ctx, true);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'reset position: clear prefs failed');
    }
    this.hasSavedPos = false;
    this.posRestored = false;
    this.placeByDefault();
    hilog.info(DOMAIN, TAG, 'Position reset to default');
  }

  /** 把当前状态打包成纯逻辑模块需要的几何参数 */
  private geom(cx: number = this.btnCx, cy: number = this.btnCy): FloatGeometry {
    return {
      cx: cx,
      cy: cy,
      // ⚠️ 用**窗口**尺寸（见 boundsW/boundsH），不是整屏尺寸：
      // 按钮坐标是相对组件所在窗口的，用整屏算会把按钮放到窗口外（小窗/自由多窗下直接丢失）。
      pageW: this.boundsW(),
      pageH: this.boundsH(),
      fabSize: this.FAB_SIZE,
      edgeMargin: this.EDGE_MARGIN,
      dragMargin: this.DRAG_MARGIN,
      hideRatio: this.effHideRatio(),
      subStackHeight: this.subStackHeight(),
      // 顶部系统安全区（状态栏 + 余量）；控制中心热区宽度
      statusBarInset: this.topSafeInset,
      controlCenterInset: this.CONTROL_CENTER_INSET
    };
  }

  /**
   * 悬浮条的活动范围（宽/高，vp）——**以组件所在窗口为准**。
   *
   * 为什么不能直接用整屏尺寸：按钮的 translate 是相对本组件（即所在窗口）的坐标。
   * 平板小窗 / 自由多窗 / 悬浮窗下窗口远小于屏幕，若按整屏算默认位置，
   * 按钮会被放到窗口之外 —— 窗口是独立 surface，超出部分直接不绘制，
   * 实机表现就是「小窗模式下按钮直接丢失」。
   *
   * pageW/pageH 由页面 onAreaChange 实测传入（就是窗口可用区），因此优先用它；
   * 只有在页面还没测量出来时，才退回屏幕尺寸兜底（那时由 restorePrefs 的
   * `posRestored` 保护，不会把整屏坐标当成窗口坐标用）。
   */
  private boundsW(): number {
    if (this.pageW > 0) {
      return this.pageW;
    }
    if (this.screenW > 0) {
      return this.screenW;
    }
    return this.pageW;
  }

  private boundsH(): number {
    if (this.pageH > 0) {
      return this.pageH;
    }
    if (this.screenH > 0) {
      return this.screenH;
    }
    return this.pageH;
  }

  private minCy(): number {
    return minCenterY(this.geom());
  }

  private maxCy(): number {
    return maxCenterY(this.geom());
  }

  private cxLeft(): number {
    return cxAtLeftEdge(this.geom());
  }

  private cxRight(): number {
    return cxAtRightEdge(this.geom());
  }

  /** 贴右边缘、且未吸附时的等效中心 x（用于把位置换算成可持久化的位移） */
  private cxRightUnsnapped(): number {
    const w: number = this.boundsW();
    if (w <= 0) {
      return 0;
    }
    return w - this.DEFAULT_MARGIN - this.FAB_SIZE / 2;
  }


  /**
   * 键盘实际遮挡按钮时所需的抬高量（vp）；不遮挡返回 0。
   *
   * 判定与边界都由 common/FloatingLayout 的纯函数负责（可单测），这里只取结果。
   * **拖动过程中返回 0**：避让量由 btnCy 推导，拖动时再叠加会互相抵消
   *（表现为「键盘弹起后按钮怎么拖都不动」）。进入拖动前已把当时的避让量固化进 btnCy。
   */
  private keyboardLiftVp(): number {
    return keyboardLift(this.btnCx, this.btnCy, this.boundsH(), this.keyboardHeightVp,
      this.FAB_SIZE, this.DRAG_MARGIN, this.isDragging);
  }

  /** 未保存过位置时的默认中心 y（与 placeByDefault 保持一致，作为位移基准） */
  /**
   * 默认位置的纵坐标：**顶部**（与默认的右上角一致）。
   *
   * 这里同时是保存位移的基准 —— 存取两侧必须用同一个基准，
   * 因此改默认位置只会改变"默认落在哪"，不会让已保存的位置整体偏移。
   */
  private cyByDefault(): number {
    return this.minCy();
  }

  /**
   * 恢复上次的吸附位置。
   *
   * 存储格式仍是「相对右下角默认位置的位移 [dx, dy]」（沿用旧版 UiPrefs，不改存储结构）。
   * ⚠️ 这里**必须在拿到页面尺寸后**才能换算：位移要加上默认位置才是屏幕坐标。
   * 早期实现直接把位移当成屏幕坐标（`btnCy = dy`，而 dy 恒为 0），
   * 导致重启后按钮总是回到默认纵向位置 —— 也就是「重载后吸附位置不变」。
   */
  private restorePrefs(): void {
    let dx: number = 0;
    let dy: number = 0;
    this.hasSavedPos = false;
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const offset: number[] = loadRefreshButtonOffset(ctx);
      if (offset.length === 2 && (offset[0] !== 0 || offset[1] !== 0)) {
        dx = offset[0];
        dy = offset[1];
        this.hasSavedPos = true;
      }
      this.snappedPref = loadRefreshButtonSnapped(ctx);
    } catch (err) {
      // 这条以前是静默的：读失败时字段保持 0，表现与「从没保存过」完全一样，
      // 因此必须把原因打出来（实机排查时就是它掩盖了问题）。
      hilog.error(DOMAIN, TAG, 'restorePrefs failed: %{public}s', JSON.stringify(err));
    }
    // 记下位移。**这里不急着应用**：`readScreenSize()` 内部可能已经先触发过一次
    // onMetricsChange（那时偏好还没读），把按钮放到默认位置；若这里再应用，
    // 就会与「默认落位」互相覆盖 —— 实机正是这个竞态导致重载后位置不变。
    // 因此改为两阶段：这里只记录，由 onMetricsChange 在「尺寸就绪 + 偏好已读」时统一落位。
    this.savedDx = dx;
    this.savedDy = dy;
    this.prefsRead = true;
    // 尺寸若已就绪，立刻补一次落位（否则等 onMetricsChange）
    this.applyRestoredPosition();
  }

  /**
   * 把保存的位移换算成屏幕坐标并应用。
   * 位移是相对「右下角默认位置」的，因此必须加上默认位置；页面尺寸未就绪时先不处理，
   * 留待 onMetricsChange（会再调一次）。
   */
  private applyRestoredPosition(): void {
    if (!this.hasSavedPos || this.posRestored) {
      return;
    }
    if (this.boundsW() <= 0 || this.boundsH() <= 0) {
      return;
    }
    if (this.snappedPref) {
      // 贴边态：直接贴到当前窗口的对应边（半隐藏位），与窗口尺寸无关，最稳。
      // 用保存的位移符号判断原来贴哪边，并**记住**它。
      const toRight: boolean = this.savedDx >= 0;
      this.btnCx = toRight ? this.cxRight() : this.cxLeft();
      this.cyFromSaved();
      this.snappedEdge = toRight ? EDGE_RIGHT : EDGE_LEFT;
    } else {
      // 自由位置：位移是相对旧窗口算的，窗口变小/换形态后可能落在外面，
      // 因此夹进当前窗口范围（见 clampIntoBounds）——否则会出现"按钮丢失"。
      this.btnCx = this.cxRightUnsnapped() + this.savedDx;
      this.btnCy = this.cyByDefault() + this.savedDy;
      this.clampIntoBounds();
    }
    this.snapped = this.snappedPref;
    this.posRestored = true;
    hilog.info(DOMAIN, TAG, 'Restored position to (%{public}d, %{public}d) snapped=%{public}s',
      Math.round(this.btnCx), Math.round(this.btnCy), String(this.snappedPref));
  }

  /** 恢复纵向位置并夹进范围 */
  private cyFromSaved(): void {
    this.btnCy = this.cyByDefault() + this.savedDy;
    this.btnCy = Math.min(this.maxCy(), Math.max(this.minCy(), this.btnCy));
  }

  /**
   * 把按钮位置夹进**当前窗口**范围。
   *
   * 为什么必须有：窗口形态会变（平板小窗 / 自由多窗 / 分屏 / 全屏），
   * 保存的位置是按旧窗口算的；窗口变小后旧坐标跑到窗口外，
   * 而窗口是独立 surface，超出部分不绘制 —— 实机表现就是「小窗下按钮直接丢失」。
   */
  private clampIntoBounds(): void {
    const w: number = this.boundsW();
    const h: number = this.boundsH();
    if (w <= 0 || h <= 0) {
      return;
    }
    const minX: number = this.EDGE_MARGIN + this.FAB_SIZE / 2;
    const maxX: number = Math.max(minX, w - this.EDGE_MARGIN - this.FAB_SIZE / 2);
    this.btnCx = Math.min(maxX, Math.max(minX, this.btnCx));
    this.btnCy = Math.min(this.maxCy(), Math.max(this.minCy(), this.btnCy));
  }

  /** 进入贴边态并记住贴的是哪条边 */
  private setSnappedEdge(edge: string): void {
    this.snappedEdge = edge;
    this.snapped = true;
  }

  /** 解除贴边态（自由悬停） */
  private clearSnappedEdge(): void {
    this.snapped = false;
  }

  /**
   * 窗口尺寸变化后重新落位（全屏 ⇄ 小窗 ⇄ 自由多窗 ⇄ 分屏 都会走这里）。
   *
   * **贴边态贴回「原来那条边」**：用记住的 snappedEdge，绝不按当前位置重新推导 ——
   * 窗口变窄时位置会被夹取，夹完可能落到另一半，于是"右 → 小窗 → 全屏"就变成了贴左边
   *（实机复现的 bug）。
   * 自由位置则夹进窗口范围，避免被推出窗口外（窗口是独立 surface，超出即不绘制）。
   */
  private relayoutForWindow(): void {
    if (this.boundsW() <= 0) {
      return;
    }
    // 横向落点交给纯函数（可单测）：贴边态只看**记住的边**，不看当前位置 ——
    // 否则窗口变窄时的夹取会让判定换边（实机：右 → 小窗 → 全屏 变成贴左边）。
    this.btnCx = relayoutCenterX(this.snapped, this.snappedEdge, this.btnCx, this.geom());
    this.btnCy = Math.min(this.maxCy(), Math.max(this.minCy(), this.btnCy));
  }

  /**
   * 保存当前吸附位置：位移 + 是否贴边。
   *
   * **必须把纵向位移一并写入**（旧实现第二个参数写死 0，纵向位置因此从不持久化）。
   */
  private saveOffset(): void {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const dx: number = this.btnCx - this.cxRightUnsnapped();
      const dy: number = this.btnCy - this.cyByDefault();
      saveRefreshButtonOffset(ctx, dx, dy);
      setRefreshButtonSnapped(ctx, this.snapped);
      hilog.info(DOMAIN, TAG, 'Saved position dx=%{public}d dy=%{public}d snapped=%{public}s',
        Math.round(dx), Math.round(dy), String(this.snapped));
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Failed to save floating bar position');
    }
  }

  /** 首次给出默认位置（右下角，处于吸附态） */
  private placeByDefault(): void {
    if (this.boundsW() <= 0 || this.boundsH() <= 0) {
      return;
    }
    if (this.hasSavedPos) {
      // 有保存位置却走到默认落位，说明恢复链路又被绕开了 —— 留痕便于定位
      hilog.warn(DOMAIN, TAG, 'placeByDefault called while a saved position exists');
    }
    this.btnCx = this.cxRight();
    this.btnCy = this.cyByDefault();
    this.setSnappedEdge(EDGE_RIGHT);
    this.posRestored = true;
    hilog.info(DOMAIN, TAG, 'Default position (top-right) at (%{public}d, %{public}d)',
      Math.round(this.btnCx), Math.round(this.btnCy));
  }

  private onMetricsChange(): void {
    if (this.boundsW() <= 0 || this.boundsH() <= 0) {
      return;
    }
    // ⚠️ 关键：偏好还没读完就**直接返回**，绝不能落位。
    // readScreenSize() 会先于 restorePrefs() 触发本方法；若此时就落位，
    // 按钮会被放到默认位置且 posRestored 被置位，随后的恢复就被永久跳过 ——
    // 实机表现正是「重载后位置从来不变」（本 bug 的真正原因）。
    if (!this.prefsRead) {
      return;
    }
    if (!this.posRestored) {
      // 第一次落位：优先用保存的位置，没有记录才用默认位置
      if (this.hasSavedPos) {
        this.applyRestoredPosition();
      } else {
        this.placeByDefault();
      }
    } else {
      // 已落位：窗口尺寸变化时重新落位（贴边态贴回**原来那条边**，见 relayoutForWindow）
      this.relayoutForWindow();
    }
  }

  /**
   * 松手后吸附到**最近的四条边之一**（含顶/底）。
   *
   * 判定与落点全在纯函数 {@link snapToNearestEdge} 里（可单测），这里只负责动画与持久化。
   */
  private snapToNearestEdge(): void {
    if (this.boundsW() <= 0 || this.boundsH() <= 0) {
      return;
    }
    // 阈值 = 边距 + 半径：视觉上就是「按钮贴到边缘才吸上去」。
    // 中间区域内不吸附，按钮可以任意悬停（本轮需求）。
    const edgeX: number = this.DRAG_MARGIN + this.FAB_SIZE / 2;
    const edgeY: number = this.DRAG_MARGIN + this.FAB_SIZE / 2;
    const res: SnapResult = snapToNearestEdgeWithin(this.geom(), edgeX, edgeY);
    this.getUIContext().animateTo({
      duration: this.SPRING_MS,
      curve: curves.springMotion(0.55, 0.9)
    }, () => {
      this.btnCx = res.cx;
      this.btnCy = res.cy;
      // 只有真的贴到某条边才算吸附态；自由悬停时不进入吸附态，
      // 这样第一次点按会直接展开（而不是先"解除吸附"却看不出变化）
      if (res.edge === EDGE_LEFT || res.edge === EDGE_RIGHT) {
        this.setSnappedEdge(res.edge);
      } else {
        this.clearSnappedEdge();
      }
    });
    hilog.info(DOMAIN, TAG, 'Release -> %{public}s at (%{public}d, %{public}d)',
      res.edge, Math.round(res.cx), Math.round(res.cy));
  }

  /**
   * 解除吸附：把按钮从边缘收到「舒适区」——完整可见，且横向留出足够空间，
   * 保证随后展开的子菜单不会被屏幕边缘裁掉。
   *
   * 交互约定（两段式，本轮需求）：**第一次点按先脱吸附，第二次点按才展开**。
   * 理由是吸附态下按钮是半隐藏的（贴在屏幕边缘、有一半在屏外），
   * 直接展开会让子菜单贴着边缘、看着局促；先归位再展开更符合直觉也更好点。
   */
  private unsnap(): void {
    if (this.boundsW() <= 0 || this.boundsH() <= 0) {
      return;
    }
    const tx: number = cxWhenUnsnapped(this.geom(), this.UNSNAP_INSET);
    // 纵向：夹进允许范围，保证展开后子菜单仍在屏内
    const ty: number = clampDragY(this.geom(tx, this.btnCy));
    this.getUIContext().animateTo({
      duration: this.SPRING_MS,
      curve: curves.springMotion(0.55, 0.9)
    }, () => {
      this.btnCx = tx;
      this.btnCy = ty;
      this.clearSnappedEdge();
      // 位置变了，弹出方向必须跟着重算（否则会出现「在顶部却向上弹」）
    });
    hilog.info(DOMAIN, TAG, 'Unsnapped to (%{public}d, %{public}d)', Math.round(tx), Math.round(ty));
  }

  // ────────────────────────── 展开 / 收起 ──────────────────────────

  /**
   * 点击主按钮的两段式行为：
   *   ① 已展开 → 收起；
   *   ② 未展开但处于吸附态 → **只解除吸附、先不展开**（第一次点按）；
   *   ③ 未展开且未吸附 → 展开（第二次点按）。
   *
   * 注意：这只管**轻点**（几乎无位移）。拖动是另一条路径、**与吸附状态无关** ——
   * 无论按钮贴在边缘（半隐藏）还是已经归位，按住后直接拖即可移动
   *（见 {@link onFabDragStart}）。
   */
  private onFabTap(): void {
    this.wakeUp();
    if (this.isExpanded) {
      this.collapse();
      this.scheduleIdleFade();
      return;
    }
    if (this.snapped) {
      this.unsnap();
      this.scheduleIdleFade();
      return;
    }
    this.toggleExpand();
  }

  /**
   * 顺向甩动即吸附。
   *
   * 规则（本轮需求）：按钮已在**右半边**时向右甩 → 直接吸附到**右边缘**；
   * 在**左半边**时向左甩 → 直接吸附到**左边缘**。
   * 「顺向」= 甩动方向与按钮当前所在半边一致，因此反方向甩不会误吸附。
   *
   * 为什么单独做：默认吸附有距离阈值（离边足够近才吸），停在中间时甩一下吸不上；
   * 这个手势给用户一个"快速归边"的入口，不必精确拖到边缘。
   *
   * @returns 是否已按甩动完成吸附（true 时调用方不要再走常规吸附）
   */
  private trySwipeSnap(): boolean {
    // 判定逻辑抽在纯函数里（可单测）：起手半边 + 横甩方向 + 阈值
    const edge: string | null = swipeSnapEdge(this.dragBaseCx, this.lastOffX, this.lastOffY,
      this.boundsW(), this.SWIPE_SNAP_PX);
    if (edge === null) {
      return false;
    }
    const toRight: boolean = edge === EDGE_RIGHT;
    const targetCx: number = toRight ? this.cxRight() : this.cxLeft();
    const targetCy: number = Math.min(this.maxCy(), Math.max(this.minCy(), this.btnCy));
    this.getUIContext().animateTo({
      duration: this.SPRING_MS,
      curve: curves.springMotion(0.55, 0.9)
    }, () => {
      this.btnCx = targetCx;
      this.btnCy = targetCy;
      this.setSnappedEdge(edge);
    });
    hilog.info(DOMAIN, TAG, 'Swipe snap to %{public}s edge (offX=%{public}d)',
      toRight ? 'right' : 'left', Math.round(this.lastOffX));
    return true;
  }

  /**
   * 进入拖动态（由 PanGesture 在位移达到阈值时调用）。
   *
   * 名称保留 historic 语义：这里是「拖动开始」而不是「长按」——
   * 现在没有长按步骤了（长按会触发系统放大显示，见 build 里的说明）。
   *
   * **与吸附状态无关**：无论按钮贴在边缘（半隐藏）还是已归位，拖动都能直接开始。
   * 吸附态下先把位置基准固定在当前（半隐藏）坐标，拖动过程中再按边界夹取。
   */
  private onFabDragStart(): void {
    this.wakeUp();
    this.isDragging = true;
    this.dragBaseCx = this.btnCx;
    this.dragBaseCy = this.btnCy;
    // 清零位移记录：顺向甩动的判断只看本次拖动
    this.lastOffX = 0;
    this.lastOffY = 0;
    // 通知页面压制键盘（拖动中手指会滑出按钮落到网页上）
    try {
      this.onDragStateChange(true);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'onDragStateChange(true) failed');
    }
    hilog.info(DOMAIN, TAG, 'Drag started from (%{public}d, %{public}d), snapped=%{public}s',
      Math.round(this.btnCx), Math.round(this.btnCy), String(this.snapped));
  }

  /** 结束拖动态（松手 / 取消都要走到，保证页面的键盘压制一定被恢复） */
  private endDrag(): void {
    if (!this.isDragging) {
      return;
    }
    this.isDragging = false;
    this.isPressed = false;
    try {
      this.onDragStateChange(false);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'onDragStateChange(false) failed');
    }
  }

  private toggleExpand(): void {
    this.wakeUp();
    const next: boolean = !this.isExpanded;
    // 展开前先按当前位置定好弹出方向，避免先弹错方向再翻
    this.getUIContext().animateTo({
      duration: this.SPRING_MS,
      curve: curves.springMotion(0.6, 0.95)
    }, () => {
      this.isExpanded = next;
    });
    this.scheduleIdleFade();
  }

  private collapse(): void {
    if (!this.isExpanded) {
      return;
    }
    this.getUIContext().animateTo({
      duration: 240,
      curve: curves.springMotion(0.6, 1)
    }, () => {
      this.isExpanded = false;
    });
  }

  // ────────────────────────── 闲置透明化 ──────────────────────────

  /**
   * 空闲计时到点后的**单一出口**（原先在多个分支里各自重新调度定时器，易漏易重）。
   *
   * 顺序：展开 → 先收起（若已在边缘可吸附区则同时归边）；否则尝试归边；都没有才渐隐。
   * 收起/归边都改变了状态，因此**重新开始计时**，把渐隐留给下一次空闲。
   */
  private onIdleTimeout(): void {
    const wasExpanded: boolean = this.isExpanded;
    if (wasExpanded) {
      this.collapse();
    }
    if (wasExpanded || this.tryAutoSnap()) {
      this.scheduleIdleFade();
      return;
    }
    this.getUIContext().animateTo({ duration: this.FADE_DURATION_MS, curve: Curve.FastOutSlowIn }, () => {
      this.idleFaded = true;
    });
  }

  private scheduleIdleFade(): void {
    this.clearIdleTimer();
    this.idleTimer = setTimeout(() => {
      this.idleTimer = -1;
      this.onIdleTimeout();
    }, this.IDLE_FADE_MS);
  }

  /**
   * 空闲自动吸附：按钮**已经在竖边附近**时自动贴上去；停在画面中间则不动。
   *
   * 与拖动松手吸附的区别：那个要求离边很近（拖到边上才吸），这个是**空闲兜底**，
   * 给"停在边缘附近但没完全贴边"的按钮一个自动归位的机会，
   * 同时不去打扰刻意停在中间（自由悬停）的按钮。
   *
   * 拖动态与展开态都不动：正在操作/子菜单开着时移动按钮会打断用户。
   *
   * @returns 是否发生了吸附
   */
  private tryAutoSnap(): boolean {
    if (this.isDragging || this.isExpanded || this.boundsW() <= 0) {
      return false;
    }
    if (!this.autoSnapEnabled) {
      return false;   // 设置里关掉了空闲自动吸附
    }
    const edge: string | null = autoSnapEdge(this.btnCx, this.boundsW(), this.AUTO_SNAP_NEAR_PX);
    if (edge === null) {
      return false;
    }
    const toRight: boolean = edge === EDGE_RIGHT;
    const targetCx: number = toRight ? this.cxRight() : this.cxLeft();
    // ⚠️ 已经在目标吸附位就不要重复吸附：
    // 半隐藏位置（中心在屏幕内约半个半径处）本身就落在邻近阈值内，
    // 不做这个判断会每 3 秒自我触发一次，按钮永远不渐隐（实机已复现）。
    if (Math.abs(this.btnCx - targetCx) <= 1) {
      return false;
    }
    this.getUIContext().animateTo({
      duration: this.SPRING_MS,
      curve: curves.springMotion(0.55, 0.9)
    }, () => {
      this.btnCx = targetCx;
      this.setSnappedEdge(edge);
    });
    // 吸附改变了位置：持久化，并重新开始空闲计时（让"刚吸过去"这件事可见）
    this.saveOffset();
    hilog.info(DOMAIN, TAG, 'Auto snap to %{public}s edge (idle)', toRight ? 'right' : 'left');
    return true;
  }

  private wakeUp(): void {
    if (this.idleFaded) {
      this.getUIContext().animateTo({ duration: 140, curve: Curve.FastOutSlowIn }, () => {
        this.idleFaded = false;
      });
    }
    this.scheduleIdleFade();
  }

  private clearIdleTimer(): void {
    if (this.idleTimer !== -1) {
      clearTimeout(this.idleTimer);
      this.idleTimer = -1;
    }
  }

  // ────────────────────────── 子按钮 ──────────────────────────

  /**
   * 刷新子按钮被关闭时的**等高占位**：整列按固定锚点定位，列高一旦变化主按钮就会跳，
   * 补一个同尺寸空节点保证列高恒定。
   */
  @Builder
  subPlaceholder() {
    Stack()
      .width(this.SUB_SIZE)
      .height(this.SUB_SIZE)
      .hitTestBehavior(HitTestMode.None)
  }

  /**
   * 子按钮：圆形 + 毛玻璃 + 阴影；折叠时缩小并淡出。
   *
   * 说明：原先还有 index 参数用于展开错峰动画，但两个子按钮的 index 都是常量，
   * 实际没有错峰效果，属死参数，已删除以免误导。
   */
  @Builder
  subButton(symbol: Resource, a11y: Resource, action: () => void) {
    Stack() {
      // 图标：品牌蓝 + 细线条；再放大一号（子按钮 25vp）
      // 图标色分深浅色：深色模式为纯白（配纯黑底，做成完全黑白），浅色为主色调
      SymbolGlyph(symbol)
        .fontSize(25)
        .fontWeight(FontWeight.Regular)
        .fontColor([$r('app.color.floating_button_icon')])
        .renderingStrategy(SymbolRenderingStrategy.SINGLE)
    }
    .width(this.SUB_SIZE)
    .height(this.SUB_SIZE)
    .borderRadius(this.SUB_SIZE / 2)
    .backgroundColor($r('app.color.floating_button_bg'))
    // 一圈描边：深色模式是纯黑底 + 纯白描边（完全黑白），浅色是淡灰收边。
    .border({ width: 1, color: $r('app.color.floating_button_border') })
    .shadow({ radius: 10, color: $r('app.color.floating_button_shadow'), offsetY: 3 })
    .opacity(this.isExpanded ? 1 : 0)
    // 错峰：离主按钮越远的子按钮，展开时越晚一点出现、收起时越早消失 —— 更有"弹出"的层次感
    .animation({
      duration: 300,
      curve: curves.springMotion(0.62, 0.92)
    })
    .translate({ y: this.isExpanded ? 0 : 10 })
    .scale({
      x: this.isExpanded ? 1 : 0.5,
      y: this.isExpanded ? 1 : 0.5,
      centerY: '100%'
    })
    // ⚠️ 命中测试必须跟随展开状态。
    // 收起时子按钮只是 opacity(0)（仍在视图树里、仍占布局位置），
    // 若这里恒为 Block，隐藏的设置/刷新按钮**依然可点** ——
    // 实机表现就是"点悬浮球下方那块区域会莫名打开设置界面"。
    .hitTestBehavior(this.isExpanded ? HitTestMode.Block : HitTestMode.None)
    .accessibilityText(a11y)
    .onClick(() => {
      this.wakeUp();
      action();
      // 执行动作后自动收起
      this.collapse();
    })
  }

  /** 主按钮：三个点（更多操作） */
  @Builder
  fabButton() {    Stack() {
      // 图标：品牌蓝 + 细线条 + 比子按钮更大一号（30vp）；拖动态略加粗放大
      //
      // 用 line_3_horizontal（三条横线）而不是原来的 ellipsis_circle（圆 + 三个圆点）：
      // 后者自带一个圆形轮廓 + 三个圆点，长按时这些**圆点/圆环**很容易被系统当作
      // 可放大对象（实机截图里按钮被整体放大成一个气泡，就是这个效果）。
      // 三条横线是更纯净的"更多"符号，视觉上没有任何圆点，也更贴合扁平风格。
      SymbolGlyph($r('sys.symbol.line_3_horizontal'))
        .fontSize(this.isDragging ? 32 : 30)
        .fontWeight(this.isDragging ? FontWeight.Medium : FontWeight.Regular)
        .fontColor([$r('app.color.floating_button_icon')])
        .renderingStrategy(SymbolRenderingStrategy.SINGLE)
    }
    .width(this.FAB_SIZE)
    .height(this.FAB_SIZE)
    .borderRadius(this.FAB_SIZE / 2)
    // 拖动态高亮：与上一版一致 —— 底色提亮 + 阴影加深 + 整体放大。
    // 刻意**不加描边**：上一版没有描边，加了反而显得突兀；
    // 放大倍数也回到 1.12（上一版的观感），而 1.22 偏夸张。
    .backgroundColor(this.isDragging
      ? $r('app.color.floating_button_bg_active')
      : $r('app.color.floating_button_bg'))
    // 描边：拖动时用强调色（高亮反馈），平时用资源色 —— 深色模式下是 30% 白圈，
    // 保证按钮在黑色网页上依然有清晰轮廓。
    // 拖动态用**加粗描边**表达（而不是把底色翻白）：
    // 深色模式是纯黑底 + 纯白图标，若拖动态翻成白底，白图标会看不见。
    .border({
      width: this.isDragging ? 3 : 1,
      color: this.isDragging ? $r('app.color.floating_button_icon') : $r('app.color.floating_button_border')
    })
    .shadow({
      radius: this.isDragging ? 20 : 12,
      color: $r('app.color.floating_button_shadow'),
      offsetY: this.isDragging ? 8 : 4
    })
    .scale({
      x: this.isDragging ? 1.12 : (this.isPressed ? 1.04 : 1),
      y: this.isDragging ? 1.12 : (this.isPressed ? 1.04 : 1)
    })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // ⚠️ 拖动全程**不得改动视图结构**：曾试过在拖动态插入全屏捕获层挡网页键盘，
      // 结果插入/移除节点直接打断了正在进行的手势（拖动断续、跳变）。
      // 键盘问题改由页面侧关闭内核自动键盘策略解决（Index.ets 的 onDragStateChange）。
      Column({ space: this.SUB_GAP }) {
        // 主按钮：视觉 48，外层命中区 56（更好按，且不影响布局锚点）
        Stack() {
          this.fabButton()
        }
        .width(this.FAB_HIT_SIZE)
        .height(this.FAB_HIT_SIZE)
        // ⚠️ 把**响应区域**扩大到视觉尺寸之外，但**不改宽度/高度**。
        //
        // 这是本轮「长按偶尔弹出系统放大显示」的根因修复。
        // 实机取证：按住按钮 2 秒 —— 不会出现放大镜；按住网页文字 —— 立刻出现系统的
        // 文本选择放大镜。也就是说放大显示不是按钮长按引起的，而是**长按落到了下面的
        // 网页文字上**：按钮就贴在网页正文旁边，命中区只有 56vp，
        // 手指按下去稍偏一点、或轻微滑动一下就滑出按钮，触摸穿透到 Web 组件，
        // 触发内核的文本选择放大镜。
        //
        // 因此把响应区域放大到 FAB_TOUCH_SIZE（对称外扩），让"手指有点偏"仍然落在按钮上。
        // 用 responseRegion 而不是直接加大宽高：宽高会改变布局锚点与遮挡面积，
        // responseRegion 只影响命中测试 —— 视觉尺寸与遮挡完全不变。
        .responseRegion({
          x: -(this.FAB_TOUCH_SIZE - this.FAB_HIT_SIZE) / 2,
          y: -(this.FAB_TOUCH_SIZE - this.FAB_HIT_SIZE) / 2,
          width: this.FAB_TOUCH_SIZE,
          height: this.FAB_TOUCH_SIZE
        })
        .hitTestBehavior(HitTestMode.Block)
        .accessibilityText($r('app.string.a11y_more_actions'))
        .onClick(() => this.onFabTap())
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.isPressed = true;
            this.wakeUp();
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.isPressed = false;
          }
        })
        // 手势：**轻点 → 展开/收起；长按后拖动 → 移动按钮**。
        //
        // ⚠️ 「长按」这一步不能删：按钮上有单击行为时，单击识别器会把触摸"吃掉"，
        // 同一节点上的 PanGesture 永远不会激活（换成 TapGesture、Parallel 手势组、
        // 降低阈值、延长按压都试过，均无效）。长按是拖动能生效的功能性前提。
        //
        // 位置换算（跟手的关键）：整列被 translate 拖动 off 后，主按钮又相对整列偏移 off，
        // 故按钮绝对位置 = 基准 + off + off；把基准也加 off 即严格 1:1 跟手。
        .gesture(
          GestureGroup(GestureMode.Sequence,
            LongPressGesture({ repeat: false, duration: this.LONG_PRESS_MS })
              .onAction(() => {
                this.onFabDragStart();
              }),
            PanGesture({ fingers: 1, direction: PanDirection.All, distance: 1 })
              .onActionUpdate((event: GestureEvent) => {
                const offX: number = event.offsetX;
                const offY: number = event.offsetY;
                // 记录本次拖动的位移，松手时据此判断「顺向甩动」
                this.lastOffX = offX;
                this.lastOffY = offY;
                // 夹取交给纯函数（可单测），保证拖到边界即停、不越界
                this.btnCx = clampDragX(this.geom(this.dragBaseCx + offX, this.btnCy));
                this.btnCy = clampDragY(this.geom(this.btnCx, this.dragBaseCy + offY));
              })
              .onActionEnd(() => {
                this.endDrag();
                // 顺向甩动优先：按钮已在右半边右甩 → 吸右边；左半边左甩 → 吸左边。
                // 命中就不再走常规吸附，避免被"最近边"改判。
                if (!this.trySwipeSnap()) {
                  this.snapToNearestEdge();
                }
                this.saveOffset();
              })
              .onActionCancel(() => {
                this.endDrag();
                this.snapToNearestEdge();
              })
          )
        )
        // 子按钮排在主按钮**下方**（自下而上顺序改为：设置 → 刷新 → … 见下方注释）
        this.subButton($r('sys.symbol.gearshape'), $r('app.string.settings_title'), () => {
          this.onOpenSettings();
        })

        if (this.refreshEnabled) {
          this.subButton($r('sys.symbol.arrow_clockwise'), $r('app.string.a11y_refresh'), () => {
            this.onRefresh();
          })
        } else {
          this.subPlaceholder()
        }

        // 子菜单**向下**展开：列尾留白用 flexGrow 吃掉下方富余空间，
        // 于是主按钮钉在锚点（按钮上缘）、子按钮在其下方依次排开。
        Stack().width(1).height(0).flexGrow(1).hitTestBehavior(HitTestMode.None)
      }
      // 位置：整列以**顶边中点**为锚点，钉在 (btnCx, btnCy - FAB_SIZE/2)。
      // btnCy 是主按钮中心；锚点取「按钮上缘」，因为子菜单**向下**展开 ——
      // 主按钮钉在锚点、子按钮在其下方依次排开（早期向上展开时用的是下缘锚点）。
      //
      // 减去 winX/winY 的原因：btnCx/btnCy 是**屏幕坐标**（吸附与边界都按整屏算），
      // 而 translate 是**本窗口内坐标**。放进 overlay 小窗口后窗口原点不为 0，
      // 不做这个换算按钮会整体偏移。窗口移动/缩放时这两个 Prop 更新，位置自动跟随。
      .position({ x: 0, y: 0 })
      .markAnchor({ x: '50%', y: '0%' })
      .animation({ duration: this.SPRING_MS, curve: curves.springMotion(0.55, 0.9) })
      // 闲置透明化：拖动态始终保持不透明
      .opacity(this.idleFaded && !this.isDragging ? this.IDLE_FADED_OPACITY : 1)
      // ⚠️ translate 必须写在 .animation 之后：animation 作用于它之前声明的属性，
      // 放在前面会把拖动位移也套上缓动 —— 手感发飘、迟滞、不跟手。
      .translate({ x: this.btnCx - this.winX, y: this.btnCy - this.FAB_SIZE / 2 - this.winY })
      // 键盘避让同样放在 .animation 之后（必须即时生效，不能被缓动拖后）
      .offset({ x: 0, y: -this.keyboardLiftVp() })
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.wakeUp();
        }
      })
      .zIndex(101)
    }
    .width('100%')
    .height('100%')
    // ⚠️ 只能是 Transparent，不能改成 None。
    //   · None        = 自身不参与命中测试；在当前结构下（根 Stack + 内层 Column 定位）
    //     实测按钮**完全无响应**（轻点不展开、长按不拖动），触摸全漏给网页。
    //   · Transparent = 自身响应且**下层节点也能响应**：按钮可点可拖，代价是触摸会同时
    //     分发给下层 Web 组件（这是网页文本选择放大镜的来源）。
    // 折中：保留 Transparent，靠按钮自身那层 Block 拦住落在响应区内的触摸。
    .hitTestBehavior(HitTestMode.Transparent)
  }
}
