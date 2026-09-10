import { describe, it, expect } from '@ohos/hypium';
import { toBCP47 } from '../main/ets/common/LanguageUtil';

/**
 * common/LanguageUtil 的本地（宿主）单元测试。
 *
 * 用 `hvigorw test` 运行，结果见
 * entry/.test/default/intermediates/test/coverage_data/test_result.txt
 *
 * 为什么这里只测 toBCP47：它是纯字符串处理，不依赖任何系统 API。
 * UrlRules 的两个函数依赖 @kit.ArkTS 的 url.URL.parseURL，该 API 在本地测试
 * 环境不可用 —— 调用一律抛异常并落入 catch 分支，断言会全部失真。
 * 因此它们放在 entry/src/ohosTest 下，由设备侧运行（hvigorw ohosTest）。
 */
export default function localUnitTest() {
  describe('toBCP47', () => {
    // 本次修复的核心用例：原实现对 zh-Hans / zh-Hant 一律只取首段，
    // 两者都退化成 "zh"，繁体用户会被网页按简体处理。
    it('zh_Hant_keeps_script_subtag', 0, () => {
      expect(toBCP47('zh-Hant')).assertEqual('zh-Hant');
    });

    it('zh_Hans_falls_back_to_bare_zh', 0, () => {
      // Hans 是简体的默认写法，裸 "zh" 已隐含简体，保持返回 "zh" 以免改变现网行为
      expect(toBCP47('zh-Hans')).assertEqual('zh');
    });

    it('region_wins_over_script', 0, () => {
      expect(toBCP47('zh-Hans-CN')).assertEqual('zh-CN');
    });

    it('zh_Hant_with_region', 0, () => {
      expect(toBCP47('zh-Hant-HK')).assertEqual('zh-HK');
      expect(toBCP47('zh-Hant-TW')).assertEqual('zh-TW');
    });

    it('plain_language_tags', 0, () => {
      expect(toBCP47('zh')).assertEqual('zh');
      expect(toBCP47('en')).assertEqual('en');
      expect(toBCP47('ru')).assertEqual('ru');
    });

    it('language_with_region', 0, () => {
      expect(toBCP47('en-US')).assertEqual('en-US');
      expect(toBCP47('ru-RU')).assertEqual('ru-RU');
    });

    it('normalises_case', 0, () => {
      expect(toBCP47('ZH-hans-cn')).assertEqual('zh-CN');
      expect(toBCP47('EN-us')).assertEqual('en-US');
    });

    it('empty_input_falls_back_to_en', 0, () => {
      expect(toBCP47('')).assertEqual('en');
    });
  });
}
