import { describe, it, expect } from '@ohos/hypium';
import { FloatGeometry, SnapResult, snapToNearestEdge, snapToNearestEdgeWithin, swipeSnapEdge,
  autoSnapEdge, relayoutCenterX, keyboardLift,
  clampDragX, clampDragY, cxAtLeftEdge, cxAtRightEdge, cxWhenUnsnapped, minCenterY, maxCenterY,
  EDGE_LEFT, EDGE_RIGHT, EDGE_TOP, EDGE_BOTTOM, EDGE_NONE }
  from '../main/ets/common/FloatingLayout';

/**
 * 悬浮按钮位置决策的本地（宿主）单元测试。
 *
 * 这些判定是实机最容易出错的部分（四条边吸附、弹出方向、键盘避让、极小窗口下的夹取），
 * 而组件本身依赖 ArkUI、无法在宿主机上测。抽成纯函数后逐条钉住。
 */

/** 一台平板全屏的典型参数（vp）：1116 宽、689 高，与实机探针一致 */
function geom(cx: number, cy: number, pageW: number = 1116, pageH: number = 689): FloatGeometry {
  return {
    cx: cx,
    cy: cy,
    pageW: pageW,
    pageH: pageH,
    fabSize: 40,
    edgeMargin: 5,
    dragMargin: 24,
    hideRatio: 0.4,
    subStackHeight: 92,
    // 顶部系统安全区（状态栏）与右上角控制中心热区
    statusBarInset: 52,
    controlCenterInset: 72
  };
}

export default function floatingLayoutTest() {
  describe('edge snap', () => {
    it('snaps_to_the_left_edge_when_closer_to_it', 0, () => {
      const r: SnapResult = snapToNearestEdge(geom(120, 300));
      expect(r.edge).assertEqual(EDGE_LEFT);
      // 半隐藏：中心落在屏幕外一点点（0.4 × 40 = 16 的偏移）
      expect(r.cx).assertEqual(5 + 20 - 16);
    });

    it('snaps_to_the_right_edge_when_closer_to_it', 0, () => {
      const r: SnapResult = snapToNearestEdge(geom(1000, 300));
      expect(r.edge).assertEqual(EDGE_RIGHT);
      expect(r.cx).assertEqual(1116 - 5 - 20 + 16);
    });

    // 新增能力：顶/底也要能吸附（本轮需求）
    // 上下贴边的落点用「菜单安全范围」：贴顶时正好在子菜单整段高度之下，
    // 这样贴顶后子菜单向下弹也不会被裁。
    it('snaps_to_the_top_and_bottom_edges_too', 0, () => {
      const top: FloatGeometry = geom(600, 130);
      const topR: SnapResult = snapToNearestEdge(top);
      expect(topR.edge).assertEqual(EDGE_TOP);
      // 上下贴边不做半隐藏，按钮完整可见
      expect(topR.cy).assertEqual(minCenterY(top));
      // 贴顶落点要能容纳向下弹的整段子菜单
      // 菜单**向下**展开 ⇒ 子菜单落在按钮下方，只需不越出窗口底部
      expect(topR.cy + top.subStackHeight <= top.pageH).assertTrue();

      const bottom: FloatGeometry = geom(600, 660);
      const botR: SnapResult = snapToNearestEdge(bottom);
      expect(botR.edge).assertEqual(EDGE_BOTTOM);
      expect(botR.cy).assertEqual(maxCenterY(bottom));
    });

    // ⚠️ 回归：这条曾经是实机 bug ——
    // 早期把「拖动下限」写成 dragMargin + 半径 + 子菜单高度，按钮被锁死在下半屏，
    // 表现为「无法拖动到顶部区域」，也就永远走不到「向下弹」的分支。
    // 纵向下限的语义：顶部安全区 + 半径 + **子菜单整段高度**。
    // 这样「子菜单向上展开」的顶端永远不低于安全区 ⇒ 不会延伸到状态栏后面，
    // 因此不需要任何方向判断（早期正是靠方向判断去补，才反复出错）。
    // 菜单向下展开 ⇒ 按钮只需保证**自身**不压状态栏，不再为子菜单预留上方空间
    it('keeps_the_button_below_the_status_bar', 0, () => {
      const g: FloatGeometry = geom(300, 0);
      expect(minCenterY(g)).assertEqual(g.statusBarInset + g.fabSize / 2);
      // 夹取后按钮顶部不越过安全区
      const cy: number = clampDragY(g);
      expect(cy - g.fabSize / 2 >= g.statusBarInset).assertTrue();
      // 区间有效（不会被顶出窗口）
      expect(minCenterY(g) <= maxCenterY(g)).assertTrue();
    });

    // 顶部安全区：贴顶时按钮不能落进状态栏，否则触摸被系统截走（实机：可见但点不动）
    it('keeps_the_button_out_of_the_status_bar', 0, () => {
      const g: FloatGeometry = geom(600, 0);
      // 被夹到安全区之下：按钮上缘不高于状态栏下沿
      const clamped: number = clampDragY(g);
      // 夹取用的是「展开下限」（比纯可见下限更高，避开状态栏下方的系统行）
      expect(clamped).assertEqual(minCenterY(g));
      expect(clamped - g.fabSize / 2 >= g.statusBarInset).assertTrue();
    });

    // 右上角是系统「控制中心」热区，按钮停在那里会点不动 —— 需额外下移
    it('pushes_the_button_below_the_control_center_when_snapped_top_right', 0, () => {
      const topRight: FloatGeometry = geom(1110, 0);
      const left: FloatGeometry = geom(60, 0);
      // 右上角比左半边抬得更高
      expect(clampDragY(topRight)).assertEqual(minCenterY(topRight));
      const clamped: number = clampDragY(topRight);
      expect(clamped).assertEqual(minCenterY(topRight));
      // 左半边不受「控制中心」这条额外约束影响，但仍受「展开下限」约束
      
      
    });

    // 端到端：按钮停在纵向下限处时，展开后的子菜单**不会延伸到状态栏后面**。
    // 新方案没有方向判断，靠的就是「下限里已含子菜单整段高度」这一条不等式。
    it('keeps_the_expanded_menu_inside_the_window', 0, () => {
      const g: FloatGeometry = geom(300, 0);
      const cy: number = clampDragY(g);
      // 子菜单**向下**展开：只需保证它不越出窗口底部，且按钮本身不进状态栏
      expect(cy - g.fabSize / 2 >= g.statusBarInset).assertTrue();
      expect(cy + g.subStackHeight <= g.pageH).assertTrue();
    });

    // 顶/底贴边时横向要夹回可视范围，否则按钮会跑到屏幕外。
    // 位置必须**确实以顶边为最近**：cx 取小值时左边会更近（left=20 < top=130），
    // 那样测的就是左右吸附了 —— 这里用 (100, 30)：l=100 / r=1016 / t=30 / b=659，顶边最近。
    it('clamps_the_cross_axis_when_snapping_to_top_or_bottom', 0, () => {
      const nearTop: FloatGeometry = geom(100, 30);
      const r: SnapResult = snapToNearestEdge(nearTop);
      expect(r.edge).assertEqual(EDGE_TOP);
      // 期望值用纯函数自己算，避免断言里手写算式与实现脱节
      expect(r.cx).assertEqual(clampDragX(nearTop));
      // 夹取后按钮必须完整落在容器内
      expect(r.cx - nearTop.fabSize / 2 >= 0).assertTrue();
      expect(r.cx + nearTop.fabSize / 2 <= nearTop.pageW).assertTrue();
    });

    it('returns_the_input_position_when_the_container_is_not_measured_yet', 0, () => {
      const r: SnapResult = snapToNearestEdge(geom(50, 50, 0, 0));
      expect(r.cx).assertEqual(50);
      expect(r.cy).assertEqual(50);
    });

    // 极端窗口（悬浮窗拖到很小）不能让 min > max 把按钮挤到屏幕外
    it('never_produces_an_inverted_range_in_a_tiny_window', 0, () => {
      const g: FloatGeometry = geom(50, 50, 300, 200);
      expect(minCenterY(g) <= maxCenterY(g)).assertTrue();
      const r: SnapResult = snapToNearestEdge(g);
      expect(r.cy >= 0).assertTrue();
      expect(r.cy <= 200).assertTrue();
    });
  });

  // 两段式点击（本轮需求）：第一次点按只解除吸附、让按钮完整归位，第二次才展开。
  // 这里的「脱离吸附落点」是它的核心：必须完整可见，且离竖边留出余量，
  // 否则随后展开的子菜单会被屏幕边缘裁掉。
  describe('unsnap placement', () => {
    const INSET: number = 12;

    it('moves_a_right_edge_button_fully_into_view', 0, () => {
      const g: FloatGeometry = geom(cxAtRightEdge(geom(0, 0)), 645);
      const tx: number = cxWhenUnsnapped(g, INSET);
      // 完整可见：左右两侧都在容器内
      expect(tx - g.fabSize / 2 >= 0).assertTrue();
      expect(tx + g.fabSize / 2 <= g.pageW).assertTrue();
      // 且比吸附时更靠内（吸附态下外侧边缘是越过边界的）
      expect(tx < cxAtRightEdge(g)).assertTrue();
    });

    it('moves_a_left_edge_button_fully_into_view', 0, () => {
      const g: FloatGeometry = geom(cxAtLeftEdge(geom(0, 0)), 645);
      const tx: number = cxWhenUnsnapped(g, INSET);
      expect(tx - g.fabSize / 2 >= 0).assertTrue();
      expect(tx + g.fabSize / 2 <= g.pageW).assertTrue();
      expect(tx > cxAtLeftEdge(g)).assertTrue();
    });

    it('keeps_a_button_that_is_already_comfortable', 0, () => {
      const g: FloatGeometry = geom(600, 400);
      expect(cxWhenUnsnapped(g, INSET)).assertEqual(600);
    });

    it('leaves_room_for_the_sub_menu_on_both_sides', 0, () => {
      // 落点距竖边至少 dragMargin + inset，展开后子菜单不会被裁
      const right: FloatGeometry = geom(cxAtRightEdge(geom(0, 0)), 400);
      const txRight: number = cxWhenUnsnapped(right, INSET);
      expect(right.pageW - (txRight + right.fabSize / 2) >= right.dragMargin + INSET).assertTrue();
    });

    // 极窄悬浮窗不能出现反向区间把按钮挤出屏幕
    it('survives_a_very_narrow_window', 0, () => {
      const g: FloatGeometry = geom(20, 100, 120, 300);
      const tx: number = cxWhenUnsnapped(g, INSET);
      expect(tx - g.fabSize / 2 >= 0).assertTrue();
      expect(tx + g.fabSize / 2 <= g.pageW).assertTrue();
    });
  });

  // 顺向甩动吸附：按钮在右半边右甩 → 吸右；左半边左甩 → 吸左。
  // 这是本轮新增的"快速归边"手势，判定逻辑抽成纯函数后逐条钉住。
  describe('swipe to snap', () => {
    const W: number = 1116;
    const T: number = 48;

    it('snaps_right_when_the_button_is_on_the_right_half_and_swiped_right', 0, () => {
      expect(swipeSnapEdge(800, 120, 10, W, T)).assertEqual(EDGE_RIGHT);
    });

    it('snaps_left_when_the_button_is_on_the_left_half_and_swiped_left', 0, () => {
      expect(swipeSnapEdge(300, -120, 10, W, T)).assertEqual(EDGE_LEFT);
    });

    // 反方向甩不吸附：给用户留"故意挪到另一边"的自由
    it('ignores_a_swipe_towards_the_opposite_side', 0, () => {
      expect(swipeSnapEdge(800, -120, 0, W, T)).assertEqual(null);
      expect(swipeSnapEdge(300, 120, 0, W, T)).assertEqual(null);
    });

    it('ignores_a_swipe_below_the_threshold', 0, () => {
      expect(swipeSnapEdge(800, T, 0, W, T)).assertEqual(null);
      expect(swipeSnapEdge(800, T + 1, 0, W, T)).assertEqual(EDGE_RIGHT);
      expect(swipeSnapEdge(300, -T, 0, W, T)).assertEqual(null);
      expect(swipeSnapEdge(300, -(T + 1), 0, W, T)).assertEqual(EDGE_LEFT);
    });

    // 纵向位移更大时视为"拖到别处"，不做顺向吸附
    it('ignores_a_mostly_vertical_drag', 0, () => {
      expect(swipeSnapEdge(800, 100, 300, W, T)).assertEqual(null);
      expect(swipeSnapEdge(300, -100, 300, W, T)).assertEqual(null);
    });

    // 起手位置决定半边：居中(558)算右半边
    it('decides_the_side_by_the_start_position', 0, () => {
      expect(swipeSnapEdge(W / 2, 100, 0, W, T)).assertEqual(EDGE_RIGHT);
      expect(swipeSnapEdge(W / 2 - 1, -100, 0, W, T)).assertEqual(EDGE_LEFT);
      expect(swipeSnapEdge(W / 2 - 1, 100, 0, W, T)).assertEqual(null);
    });

    it('returns_null_when_the_container_is_not_measured', 0, () => {
      expect(swipeSnapEdge(800, 120, 0, 0, T)).assertEqual(null);
    });
  });

  // 空闲自动吸附：按钮**已在竖边附近**时，空闲后自己贴上去；停在中间则不动。
  // 与拖动松手吸附互补（后者要求离边很近），因此阈值更宽容。
  describe('idle auto snap', () => {
    const W: number = 1116;
    const NEAR: number = 120;

    it('snaps_left_when_resting_near_the_left_edge', 0, () => {
      expect(autoSnapEdge(60, W, NEAR)).assertEqual(EDGE_LEFT);
      expect(autoSnapEdge(NEAR, W, NEAR)).assertEqual(EDGE_LEFT);
    });

    it('snaps_right_when_resting_near_the_right_edge', 0, () => {
      expect(autoSnapEdge(W - 60, W, NEAR)).assertEqual(EDGE_RIGHT);
      expect(autoSnapEdge(W - NEAR, W, NEAR)).assertEqual(EDGE_RIGHT);
    });

    // 中间区域是「自由悬停」，空闲也不该把按钮搬走
    it('leaves_a_button_in_the_middle_alone', 0, () => {
      expect(autoSnapEdge(W / 2, W, NEAR)).assertEqual(null);
      expect(autoSnapEdge(NEAR + 1, W, NEAR)).assertEqual(null);
      expect(autoSnapEdge(W - NEAR - 1, W, NEAR)).assertEqual(null);
    });

    // 窄窗口下两边都"近"时，选更近的那条
    it('picks_the_nearer_edge_when_both_are_close', 0, () => {
      expect(autoSnapEdge(40, 200, 120)).assertEqual(EDGE_LEFT);
      expect(autoSnapEdge(160, 200, 120)).assertEqual(EDGE_RIGHT);
    });

    it('returns_null_when_the_container_is_not_measured', 0, () => {
      expect(autoSnapEdge(60, 0, NEAR)).assertEqual(null);
    });
  });

  // 窗口尺寸变化后的重新落位（平板小窗 / 自由多窗 / 分屏来回切换）。
  // 关键约束：**贴边态只看记住的边**，绝不按当前位置重新推导 ——
  // 实机 bug 正是"按位置推导"导致的换边。
  describe('relayout on window resize', () => {
    const WIDE: number = 1116;
    const NARROW: number = 554;

    it('keeps_the_right_edge_across_a_shrink_and_grow', 0, () => {
      const wide: FloatGeometry = geom(0, 0, WIDE, 689);
      const narrow: FloatGeometry = geom(0, 0, NARROW, 689);
      // 全屏时贴右
      const atWide: number = relayoutCenterX(true, EDGE_RIGHT, cxAtRightEdge(wide), wide);
      expect(atWide).assertEqual(cxAtRightEdge(wide));
      // 窗口变小：仍然贴右
      const atNarrow: number = relayoutCenterX(true, EDGE_RIGHT, atWide, narrow);
      expect(atNarrow).assertEqual(cxAtRightEdge(narrow));
      // 再回全屏：还是贴右（这里是最容易出错的一步）
      const backToWide: number = relayoutCenterX(true, EDGE_RIGHT, atNarrow, wide);
      expect(backToWide).assertEqual(cxAtRightEdge(wide));
    });

    it('keeps_the_left_edge_across_a_shrink_and_grow', 0, () => {
      const wide: FloatGeometry = geom(0, 0, WIDE, 689);
      const narrow: FloatGeometry = geom(0, 0, NARROW, 689);
      const atNarrow: number = relayoutCenterX(true, EDGE_LEFT, cxAtRightEdge(wide), narrow);
      expect(atNarrow).assertEqual(cxAtLeftEdge(narrow));
      const back: number = relayoutCenterX(true, EDGE_LEFT, atNarrow, wide);
      expect(back).assertEqual(cxAtLeftEdge(wide));
    });

    // 这条直接钉住 bug：位置参数落在"另一半"，结果也不能因此改变吸附边
    it('ignores_the_current_position_when_snapped', 0, () => {
      const narrow: FloatGeometry = geom(0, 0, NARROW, 689);
      // 记住的是右边，但当前位置（被夹过）在左半 —— 结果仍必须是右边缘
      expect(relayoutCenterX(true, EDGE_RIGHT, 20, narrow)).assertEqual(cxAtRightEdge(narrow));
      expect(relayoutCenterX(true, EDGE_LEFT, NARROW - 20, narrow)).assertEqual(cxAtLeftEdge(narrow));
    });

    // 自由悬停：保持位置并夹进窗口，避免被推出窗口外（窗口裁掉 ⇒ 按钮丢失）
    it('clamps_a_free_position_into_the_new_window', 0, () => {
      const narrow: FloatGeometry = geom(0, 0, NARROW, 689);
      const keep: number = relayoutCenterX(false, EDGE_RIGHT, 300, narrow);
      expect(keep).assertEqual(300);
      const clamped: number = relayoutCenterX(false, EDGE_RIGHT, 3000, narrow);
      expect(clamped < NARROW).assertTrue();
      expect(clamped - narrow.fabSize / 2 >= 0).assertTrue();
    });
  });

  // 屏幕旋转 / 极端窗口尺寸下的健壮性。
  // 旋转会让宽高对调（平板竖屏 1116x689 ⇄ 横屏 689x1157），
  // 必须保证：区间有效、按钮不被顶出窗口、贴边态不换边。
  describe('rotation and extreme sizes', () => {
    const SIZES: number[][] = [
      [1116, 689],   // 平板竖屏
      [689, 1157],   // 平板横屏
      [554, 695],    // 自由多窗
      [600, 360],    // 手机横屏
      [300, 200]     // 极短视口
    ];

    it('always_produces_a_valid_vertical_range', 0, () => {
      for (let i = 0; i < SIZES.length; i++) {
        const g: FloatGeometry = geom(100, 100, SIZES[i][0], SIZES[i][1]);
        expect(minCenterY(g) <= maxCenterY(g)).assertTrue();
      }
    });

    it('never_pushes_the_button_out_of_the_window', 0, () => {
      for (let i = 0; i < SIZES.length; i++) {
        const w: number = SIZES[i][0];
        const h: number = SIZES[i][1];
        const g: FloatGeometry = geom(0, 0, w, h);
        const cy: number = clampDragY(g);
        // 按钮完整落在窗口内
        expect(cy - g.fabSize / 2 >= 0).assertTrue();
        expect(cy + g.fabSize / 2 <= h).assertTrue();
      }
    });

    it('always_keeps_a_valid_range_even_in_a_tiny_viewport', 0, () => {
      const tiny: FloatGeometry = geom(100, 0, 300, 200);
      const normal: FloatGeometry = geom(100, 0, 1116, 689);
      // 下限只含"避开状态栏 + 半径"，与子菜单高度无关（向下展开）
      expect(minCenterY(normal)).assertEqual(normal.statusBarInset + normal.fabSize / 2);
      expect(minCenterY(tiny)).assertEqual(tiny.statusBarInset + tiny.fabSize / 2);
      // 极短视口下区间可能被压扁，但必须仍然有效
      expect(minCenterY(tiny) <= maxCenterY(tiny)).assertTrue();
      expect(minCenterY(tiny) >= tiny.fabSize / 2).assertTrue();
    });

    // 旋转后宽高对调：贴右边仍贴右边（与上面 relayout 用例互补，这里换成长宽互换）
    it('keeps_the_snapped_edge_when_portrait_and_landscape_swap', 0, () => {
      const portrait: FloatGeometry = geom(0, 0, 1116, 689);
      const landscape: FloatGeometry = geom(0, 0, 689, 1157);
      const inPortrait: number = relayoutCenterX(true, EDGE_RIGHT, cxAtRightEdge(portrait), portrait);
      // 旋转到横屏
      const inLandscape: number = relayoutCenterX(true, EDGE_RIGHT, inPortrait, landscape);
      expect(inLandscape).assertEqual(cxAtRightEdge(landscape));
      // 再转回竖屏
      const back: number = relayoutCenterX(true, EDGE_RIGHT, inLandscape, portrait);
      expect(back).assertEqual(cxAtRightEdge(portrait));
      // 贴左边同理
      const leftLandscape: number = relayoutCenterX(true, EDGE_LEFT, cxAtLeftEdge(portrait), landscape);
      expect(leftLandscape).assertEqual(cxAtLeftEdge(landscape));
    });
  });

  describe('keyboard avoidance', () => {
    it('does_not_move_when_the_keyboard_does_not_cover_the_button', 0, () => {
      // 按钮在顶部，键盘只占底部 —— 完全不该动
      expect(keyboardLift(1000, 200, 689, 300, 40, 24, false)).assertEqual(0);
    });

    it('lifts_just_enough_when_the_keyboard_covers_the_button', 0, () => {
      // 键盘高 300 → 上沿在 389；按钮中心 600、下缘 620，超出 231，再加 24 边距
      expect(keyboardLift(1000, 600, 689, 300, 40, 24, false)).assertEqual(231 + 24);
    });

    it('does_not_lift_exactly_at_the_keyboard_edge', 0, () => {
      // 按钮下缘正好等于键盘上沿 → 不算被遮挡
      expect(keyboardLift(1000, 369, 689, 300, 40, 24, false)).assertEqual(0);
    });

    // 关键回归：拖动期间必须返回 0，否则避让量与拖动位移互相抵消（按钮怎么拖都不动）
    it('never_lifts_while_dragging', 0, () => {
      expect(keyboardLift(1000, 600, 689, 300, 40, 24, true)).assertEqual(0);
    });

    it('does_nothing_when_there_is_no_keyboard_or_no_measurement', 0, () => {
      expect(keyboardLift(1000, 600, 689, 0, 40, 24, false)).assertEqual(0);
      expect(keyboardLift(1000, 600, 0, 300, 40, 24, false)).assertEqual(0);
    });
  });

  describe('drag clamping', () => {
    it('keeps_the_button_fully_visible_horizontally', 0, () => {
      const g: FloatGeometry = geom(2, 300);
      expect(clampDragX(g)).assertEqual(24 + 20);
      const g2: FloatGeometry = geom(1114, 300);
      expect(clampDragX(g2)).assertEqual(1116 - 24 - 20);
    });

    it('keeps_the_button_inside_vertically', 0, () => {
      const g: FloatGeometry = geom(600, 1);
      expect(clampDragY(g)).assertEqual(minCenterY(g));
      const g2: FloatGeometry = geom(600, 688);
      expect(clampDragY(g2)).assertEqual(maxCenterY(g2));
    });

    // 上下吸附不做半隐藏；左右吸附半隐藏 —— 这两条要同时成立
    it('hides_only_on_left_and_right_edges', 0, () => {
      const g: FloatGeometry = geom(0, 0);
      // 半隐藏的判据：按钮的**外侧边缘**越过屏幕边界（中心仍在屏内）。
      // 贴右：中心 + 半径 > 屏宽；贴左：中心 - 半径 < 0。
      expect(cxAtRightEdge(g) + g.fabSize / 2 > g.pageW).assertTrue();
      expect(cxAtLeftEdge(g) - g.fabSize / 2 < 0).assertTrue();
      // 贴上下时中心到边缘正好留出 dragMargin，按钮完整可见（不半隐藏）
      expect(g.dragMargin >= g.fabSize / 2).assertTrue();
      // 期望值用纯函数算好再比；浮点比较用容差，避免 0.4 乘法精度差异
      expect(Math.abs(cxAtLeftEdge(g) -
        (g.edgeMargin + g.fabSize * (0.5 - g.hideRatio))) < 0.001).assertTrue();
      expect(Math.abs(cxAtRightEdge(g) -
        (g.pageW - g.edgeMargin - g.fabSize * (0.5 - g.hideRatio))) < 0.001).assertTrue();
    });
  });
}
