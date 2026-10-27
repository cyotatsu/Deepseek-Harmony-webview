import { describe, it, expect } from '@ohos/hypium';
import { TEXT_ZOOM_MIN, TEXT_ZOOM_MAX, TEXT_ZOOM_STEP, TEXT_ZOOM_DEFAULT,
  clampTextZoom, normalizeTextZoom, formatTextZoom } from '../main/ets/common/FontZoom';

/**
 * 字体大小（网页文字缩放）纯逻辑的本地单元测试。
 *
 * 这些判定直接决定「滑到头会不会越界」「读坏存储会不会把字号设成 0」，
 * 而弹窗本身依赖 ArkUI、无法在宿主机上测，因此把边界逐条钉住。
 */
export default function fontZoomTest() {
  describe('text zoom bounds', () => {
    it('exposes_the_documented_range_and_default', 0, () => {
      expect(TEXT_ZOOM_MIN).assertEqual(80);
      expect(TEXT_ZOOM_MAX).assertEqual(160);
      expect(TEXT_ZOOM_STEP).assertEqual(5);
      expect(TEXT_ZOOM_DEFAULT).assertEqual(100);
    });

    it('keeps_an_in_range_value_untouched', 0, () => {
      expect(clampTextZoom(100)).assertEqual(100);
      expect(clampTextZoom(115)).assertEqual(115);
      expect(clampTextZoom(TEXT_ZOOM_MAX)).assertEqual(TEXT_ZOOM_MAX);
      expect(clampTextZoom(TEXT_ZOOM_MIN)).assertEqual(TEXT_ZOOM_MIN);
    });

    it('clamps_below_the_minimum_instead_of_going_tiny', 0, () => {
      expect(clampTextZoom(0)).assertEqual(TEXT_ZOOM_MIN);
      expect(clampTextZoom(79)).assertEqual(TEXT_ZOOM_MIN);
      expect(clampTextZoom(-40)).assertEqual(TEXT_ZOOM_MIN);
    });

    it('clamps_above_the_maximum_instead_of_breaking_layout', 0, () => {
      expect(clampTextZoom(161)).assertEqual(TEXT_ZOOM_MAX);
      expect(clampTextZoom(1000)).assertEqual(TEXT_ZOOM_MAX);
    });

    it('falls_back_to_default_when_the_stored_value_is_not_a_number', 0, () => {
      expect(clampTextZoom(NaN)).assertEqual(TEXT_ZOOM_DEFAULT);
    });

    it('rounds_fractional_percentages_to_whole_numbers', 0, () => {
      // 内核只接受整数百分比，115.4 / 115.6 必须分别落到 115 / 116
      expect(clampTextZoom(115.4)).assertEqual(115);
      expect(clampTextZoom(115.6)).assertEqual(116);
    });
  });

  describe('text zoom snapping', () => {
    it('snaps_a_value_to_the_nearest_step', 0, () => {
      expect(normalizeTextZoom(117)).assertEqual(115);
      expect(normalizeTextZoom(118)).assertEqual(120);
      expect(normalizeTextZoom(100)).assertEqual(100);
    });

    it('snaps_before_clamping_so_edges_stay_on_the_grid', 0, () => {
      // 79 先夹到 80；161 先夹到 160；两者都落在 5 的网格上
      expect(normalizeTextZoom(79)).assertEqual(TEXT_ZOOM_MIN);
      expect(normalizeTextZoom(161)).assertEqual(TEXT_ZOOM_MAX);
      expect(normalizeTextZoom(1000)).assertEqual(TEXT_ZOOM_MAX);
    });

    it('returns_default_for_a_non_numeric_input', 0, () => {
      expect(normalizeTextZoom(NaN)).assertEqual(TEXT_ZOOM_DEFAULT);
    });
  });

  describe('text zoom label', () => {
    it('formats_the_percentage_with_a_trailing_sign', 0, () => {
      expect(formatTextZoom(100)).assertEqual('100%');
      expect(formatTextZoom(115)).assertEqual('115%');
      expect(formatTextZoom(TEXT_ZOOM_MAX)).assertEqual('160%');
    });

    it('clamps_before_formatting_so_the_label_never_lies', 0, () => {
      expect(formatTextZoom(79)).assertEqual('80%');
      expect(formatTextZoom(999)).assertEqual('160%');
      expect(formatTextZoom(NaN)).assertEqual('100%');
    });
  });
}
