/**
 * 悬浮按钮的位置决策（纯逻辑，不依赖任何系统 API）。
 *
 * 从 components/FloatingBar.ets 里抽出来的原因：**这些判定是实机最容易出错的部分**
 *（四条边吸附、弹出方向、键盘避让，以及在极小窗口下的夹取），
 * 而组件本身依赖 ArkUI，无法在宿主机上跑测试。抽成纯函数后：
 *   · 吸附到哪条边、落点坐标、键盘抬高量、子菜单朝哪弹，全部可单测；
 *   · 组件只负责调用与渲染，逻辑不再散落在 @State 更新里。
 *
 * 坐标约定：位置用**主按钮中心点** (cx, cy) 表示，单位 vp，
 * 相对根容器左上角。所有边界判断都基于这个中心点。
 */

/** 四条边 */
export const EDGE_LEFT: string = 'left';
export const EDGE_RIGHT: string = 'right';
export const EDGE_TOP: string = 'top';
export const EDGE_BOTTOM: string = 'bottom';
/** 未吸附（停在中间自由悬停） */
export const EDGE_NONE: string = 'none';

/** 输入参数：位置、容器尺寸与几何常量 */
export interface FloatGeometry {
  /** 主按钮中心 x */
  cx: number;
  /** 主按钮中心 y */
  cy: number;
  /** 容器宽（vp） */
  pageW: number;
  /** 容器高（vp） */
  pageH: number;
  /** 主按钮直径 */
  fabSize: number;
  /** 吸附后距边缘的边距（配合半隐藏） */
  edgeMargin: number;
  /** 拖动时保留的边距（保证按钮完整可见） */
  dragMargin: number;
  /** 边缘半隐藏比例：中心比边缘外移 ratio × 直径 */
  hideRatio: number;
  /** 子菜单总高度（含与主按钮的间距）；纵向夹取要为它预留空间 */
  subStackHeight: number;
  /**
   * 顶部系统区域高度（状态栏；右上角还含控制中心热区），vp。
   * 按钮纵向下限要在此基础上再加半径，贴顶时才不会落进系统区。
   */
  statusBarInset: number;
  /** 右侧「控制中心」热区宽度（vp）：按钮贴右边缘且比这更靠上时需额外下移 */
  controlCenterInset: number;
}

/** 吸附结果 */
export interface SnapResult {
  cx: number;
  cy: number;
  edge: string;
}

/** 贴左边缘时的中心 x（半隐藏：中心在屏幕外） */
export function cxAtLeftEdge(g: FloatGeometry): number {
  return g.edgeMargin + g.fabSize / 2 - g.fabSize * g.hideRatio;
}

/** 贴右边缘时的中心 x（半隐藏） */
export function cxAtRightEdge(g: FloatGeometry): number {
  return g.pageW - g.edgeMargin - g.fabSize / 2 + g.fabSize * g.hideRatio;
}


/**
 * 判断一次拖动是否属于**顺向甩动**，以及应该吸附到哪条竖边。
 *
 * 规则（产品需求）：按钮已在**右半边**时向右甩 → 吸右边；在**左半边**时向左甩 → 吸左边。
 * 「顺向」= 甩动方向与起手所在半边一致，因此反方向甩不会误吸附。
 *
 * 为什么以**起手位置**判断半边：甩动过程中按钮会移动，用结束位置会漂移，
 * 出现"本来在右边、甩一下却判定成左边"的抖动。
 *
 * @param startCx 起手时的中心 x
 * @param offX 本次拖动的横向位移（vp，右为正）
 * @param offY 本次拖动的纵向位移（vp）
 * @param pageW 活动区域宽
 * @param threshold 判定为甩动的最小横向位移（vp）
 * @returns 'left' / 'right' 表示应吸附的边；null 表示不是顺向甩动
 */
export function swipeSnapEdge(startCx: number, offX: number, offY: number,
  pageW: number, threshold: number): string | null {
  if (pageW <= 0) {
    return null;
  }
  // 必须横甩为主：纵向位移更大时视为"拖到别处"，不做顺向吸附
  if (Math.abs(offY) > Math.abs(offX)) {
    return null;
  }
  const startOnRight: boolean = startCx >= pageW / 2;
  if (startOnRight && offX > threshold) {
    return EDGE_RIGHT;
  }
  if (!startOnRight && offX < -threshold) {
    return EDGE_LEFT;
  }
  return null;
}

/**
 * 判断按钮是否「已经在边缘附近」，可以在空闲后自动吸附，以及该吸到哪条边。
 *
 * 产品规则（本轮需求）：按钮已经在最边缘（附近）且一段时间没操作 → 自动吸附到竖边。
 * 与拖动松手时的吸附互补：那个要求离边足够近才吸；这个是**空闲兜底**，
 * 让停在边缘附近的按钮自己归位，而不去打扰停在画面中间（自由悬停）的按钮。
 *
 * @param cx 按钮中心 x
 * @param pageW 活动区域宽
 * @param threshold 视为「在边缘附近」的最大距离（vp）。取滑块区间的量级，
 *                  而不是拖动吸附的阈值 —— 空闲兜底可以比手动吸附宽容一些。
 * @returns 'left' / 'right'；null 表示离两边都还远，保持不动
 */
export function autoSnapEdge(cx: number, pageW: number, threshold: number): string | null {
  if (pageW <= 0) {
    return null;
  }
  const distLeft: number = cx;
  const distRight: number = pageW - cx;
  if (distLeft <= threshold && distLeft <= distRight) {
    return EDGE_LEFT;
  }
  if (distRight <= threshold) {
    return EDGE_RIGHT;
  }
  return null;
}

/**
 * 窗口尺寸变化后，按钮横向位置的落点。
 *
 * **贴边态必须用「记住的边」直接算，绝不按当前位置重新推导** —— 这是本函数存在的理由。
 * 早期写法是「看当前 x 落在新窗口的哪一半」，于是：
 *   贴右边 → 窗口变窄、位置被夹到左半 → 再回全屏时被判定为"贴左边" → 按钮换边。
 * 实机复现路径正是「按钮吸附在右侧，全屏-小窗-全屏后吸附到了左侧」。
 *
 * 自由位置（未贴边）则保持当前 x 并夹进新窗口，避免被推出窗口外
 *（窗口是独立 surface，超出部分不绘制 ⇒ 按钮"丢失"）。
 *
 * @param snapped 当前是否处于贴边态
 * @param rememberedEdge 记住的吸附边（EDGE_LEFT / EDGE_RIGHT）
 * @param currentCx 当前位置
 * @param g 以**新**窗口尺寸构造的几何参数
 * @returns 横向落点（vp）
 */
export function relayoutCenterX(snapped: boolean, rememberedEdge: string,
  currentCx: number, g: FloatGeometry): number {
  if (g.pageW <= 0) {
    return currentCx;
  }
  if (snapped) {
    // 只看记住的边。注意：**不能**参考 currentCx，否则窗口变窄时的夹取会改变结论。
    return rememberedEdge === EDGE_LEFT ? cxAtLeftEdge(g) : cxAtRightEdge(g);
  }
  const lo: number = g.edgeMargin + g.fabSize / 2;
  const hi: number = Math.max(lo, g.pageW - g.edgeMargin - g.fabSize / 2);
  return Math.min(hi, Math.max(lo, currentCx));
}

/**
 * 纵向可用范围：**保证展开后的整个子菜单都落在状态栏之下**，不需要方向判断。
 *
 * 之前的做法分两步：先判断按钮在上半屏还是下半屏（后来改成按几何算上方放不放得下），
 * 再决定子菜单向上还是向下弹。那套判断既复杂又反复出错（实机多次"顶部仍向上弹"）。
 *
 * 现在改为**只用一条位置约束**表达需求：
 *   · 子菜单**固定向上**展开（挂在按钮上方，见 FloatingBar 的 build）；
 *   · 按钮纵向下限 = 顶部安全区 + 半径 + 子菜单整段高度，
 *     于是「子菜单顶端」永远不低于顶部安全区 ⇒ 展开后不会延伸到状态栏后面。
 *
 * 好处：方向判定逻辑全部消失，只剩一条可单测的不等式，行为完全可预测。
 * 代价：按钮被限制在偏下的区域（下方是输入框，本来也不适合停按钮）。
 */
export function minCenterY(g: FloatGeometry): number {
  // 菜单向下展开 ⇒ 按钮只需保证**自身**不压状态栏，不再需要为子菜单预留
  return g.statusBarInset + g.fabSize / 2;
}

export function maxCenterY(g: FloatGeometry): number {
  if (g.pageH <= 0) {
    return minCenterY(g);
  }
  // 上限要同时满足两件事：
  //   1) 按钮自身不出窗口底部；
  //   2) **子菜单向下展开时整段仍在窗口内** —— 这是"向下弹"的自然约束，
  //      否则按钮停在偏下位置时子菜单会被窗口底边裁掉（实机：598 位置展开到 706 > 727 窗口）。
  // 因此取两者中更严的那个 ⇒ 按钮被限制在**上部区域**，正好对应
  //「拖动限制区域从上部改成下部」的需求（下方留给展开的菜单）。
  const keepButtonVisible: number = g.pageH - g.dragMargin - g.fabSize / 2;
  const keepMenuFitting: number = g.pageH - g.dragMargin - g.subStackHeight;
  // 视口比"菜单整段高度"还矮时（手机横屏 / 极小的自由窗口），
  // 保证整段菜单装下会让区间塌缩成 0（按钮既拖不动也吸不上），
  // 此时退化为「只保证按钮可见」——菜单可能被底边裁一点，但控件保持可用。
  const menuCanEverFit: boolean = g.pageH - g.dragMargin * 2 >= g.subStackHeight;
  const upper: number = menuCanEverFit ? Math.min(keepButtonVisible, keepMenuFitting) : keepButtonVisible;
  return Math.max(minCenterY(g), upper);
}

/** 拖动过程中的横向夹取：保证按钮完整可见 */
export function clampDragX(g: FloatGeometry): number {
  const lo: number = g.dragMargin + g.fabSize / 2;
  const hi: number = g.pageW - g.dragMargin - g.fabSize / 2;
  return Math.min(Math.max(hi, lo), Math.max(lo, g.cx));
}

/**
 * 纵向可用范围（**拖动用**）。
 *
 * 子菜单**向下**展开后，按钮占用的是「按钮在锚点、子菜单在其下方」这一段，
 * 因此限制区在**上部**：
 *   · 下限 = 顶部安全区 + 半径 ⇒ 按钮顶部不压状态栏；
 *   · 上限 = 窗口高 − 边距 − 半径 ⇒ 按钮底部不出窗口。
 *（早期向上展开时是「下限留出子菜单高度、可拖到下部」，现在正好相反。）
 */
export function clampDragY(g: FloatGeometry): number {
  return Math.min(maxCenterY(g), Math.max(minCenterY(g), g.cy));
}


/**
 * 吸附到**最近的边**——但只在按钮离那条边足够近时才吸附。
 *
 * 与「永远吸到最近边」的区别（本轮需求）：中间区域要能**自由悬停**，
 * 否则按钮一旦靠近顶部就必然被顶到顶边，用户无法把它停在偏上的任意位置。
 * 因此引入距离阈值 {@link SnapThreshold}：四条边都在阈值内才吸附，否则原地不动。
 *
 * 左右贴边时**半隐藏**（中心外移，只露小半圆）；上下贴边**不半隐藏** ——
 * 上下没有"半边"可露，藏了反而影响辨识与点击。
 *
 * @param byEdge 水平/垂直方向的吸附阈值（vp）。取 dragMargin + 半径即可：
 *               视觉上就是「按钮贴住边缘时吸上去」，中间留出完整自由区。
 */
export function snapToNearestEdgeWithin(g: FloatGeometry, byEdgeX: number, byEdgeY: number): SnapResult {
  if (g.pageW <= 0 || g.pageH <= 0) {
    return { cx: g.cx, cy: g.cy, edge: EDGE_NONE };
  }
  const distLeft: number = g.cx;
  const distRight: number = g.pageW - g.cx;
  const distTop: number = g.cy;
  const distBottom: number = g.pageH - g.cy;
  const min: number = Math.min(distLeft, distRight, distTop, distBottom);

  // 四边都够远 ⇒ 自由悬停，不吸附；位置仍夹在允许范围内保证可见
  if (min > Math.max(byEdgeX, byEdgeY)) {
    return { cx: clampDragX(g), cy: clampDragY(g), edge: EDGE_NONE };
  }

  // 先看横向（左右吸附的视觉收益最大：半隐藏省空间）
  if ((distLeft <= byEdgeX || distRight <= byEdgeX) &&
    Math.min(distLeft, distRight) <= Math.min(distTop, distBottom)) {
    const toLeft: boolean = distLeft <= distRight;
    return {
      cx: toLeft ? cxAtLeftEdge(g) : cxAtRightEdge(g),
      cy: clampDragY(g),
      edge: toLeft ? EDGE_LEFT : EDGE_RIGHT
    };
  }
  // 再看纵向
  if (distTop <= byEdgeY || distBottom <= byEdgeY) {
    const toTop: boolean = distTop <= distBottom;
    return {
      cx: clampDragX(g),
      cy: toTop ? minCenterY(g) : maxCenterY(g),
      edge: toTop ? EDGE_TOP : EDGE_BOTTOM
    };
  }
  // 到这里说明四条边都超出了各自方向的阈值 —— 但首段守卫已排除了这种情况
  // （min > max(byEdgeX, byEdgeY) 时早已 return EDGE_NONE）。
  // 原先这里还挂了一次「按最近边吸附」的兜底调用，属**不可达代码**，已删除。
  return { cx: clampDragX(g), cy: clampDragY(g), edge: EDGE_NONE };
}

/**
 * 吸附到**最近的四条边之一**（无阈值版，保留给需要"必定贴边"的场景与单测）。
 *
 * 四边都参与比较：只要按钮被拖到靠近顶部或底部，就近贴边最符合直觉，也最省空间。
 * 左右贴边时**半隐藏**；上下贴边**不半隐藏**。
 *
 * 上下贴边的落点用「菜单安全范围」：贴顶时按钮落在「子菜单整段高度 + 边距」之下，
 * 也就是子菜单向下弹的落点；贴底时落在对称位置（子菜单向上弹）。
 * 贴边后另一轴一律夹回允许范围，避免按钮跑到屏幕外找不回来。
 */
export function snapToNearestEdge(g: FloatGeometry): SnapResult {
  if (g.pageW <= 0 || g.pageH <= 0) {
    return { cx: g.cx, cy: g.cy, edge: EDGE_RIGHT };
  }
  const distLeft: number = g.cx;
  const distRight: number = g.pageW - g.cx;
  const distTop: number = g.cy;
  const distBottom: number = g.pageH - g.cy;
  const min: number = Math.min(distLeft, distRight, distTop, distBottom);

  if (min === distLeft || min === distRight) {
    const toLeft: boolean = min === distLeft;
    return {
      cx: toLeft ? cxAtLeftEdge(g) : cxAtRightEdge(g),
      cy: clampDragY(g),
      edge: toLeft ? EDGE_LEFT : EDGE_RIGHT
    };
  }
  const toTop: boolean = min === distTop;
  return {
    // 贴顶/底用菜单安全落点：贴顶时正好留出「子菜单整段高度」，向下弹不会被裁
    cy: toTop ? minCenterY(g) : maxCenterY(g),
    cx: clampDragX(g),
    edge: toTop ? EDGE_TOP : EDGE_BOTTOM
  };
}

/**
 * 解除吸附后的**横向**落点：把按钮从边缘收到「舒适区」，
 * 与最近竖边留出 inset，保证随后展开的子菜单不会被屏幕边缘裁掉。
 *
 * 为什么单独成函数：这条位置约束既影响观感（按钮不能贴在边上），
 * 又影响可用性（子菜单不能被裁），属于容易被后续改动破坏的规则，因此可单测。
 * 窗口极窄时用 min/max 兜底，避免出现上界小于下界的反向区间。
 */
export function cxWhenUnsnapped(g: FloatGeometry, inset: number): number {
  const half: number = g.fabSize / 2;
  const lo: number = Math.min(g.pageW / 2, g.dragMargin + half + inset);
  const hi: number = Math.max(lo, g.pageW - g.dragMargin - half - inset);
  return Math.min(Math.max(lo, g.cx), hi);
}


/**
 * 键盘遮挡按钮时所需的抬高量（vp）；不遮挡返回 0（完全不动）。
 *
 * 只有按钮下缘低于键盘上沿才算被遮挡，此时抬高到键盘上沿之上并保留 dragMargin ——
 * 位移刚好够露出按钮，而不是无条件上移整个键盘高度。
 *
 * @param dragging 拖动过程中必须返回 0：避让量由位置推导，拖动时再叠加会互相抵消
 *                 （表现为「键盘弹起后按钮怎么拖都不动」）。进入拖动前已把当时的
 *                 避让量固化进基准位置。
 */
export function keyboardLift(cx: number, cy: number, pageH: number, keyboardHeight: number,
  fabSize: number, dragMargin: number, dragging: boolean): number {
  if (dragging || keyboardHeight <= 0 || pageH <= 0) {
    return 0;
  }
  const btnBottom: number = cy + fabSize / 2;
  const keyboardTop: number = pageH - keyboardHeight;
  if (btnBottom <= keyboardTop) {
    return 0;
  }
  return btnBottom - keyboardTop + dragMargin;
}
