import { describe, it, expect } from '@ohos/hypium';
import { sanitizeFileName, buildDownloadTempPath, fileNameFromTempPath,
  DOWNLOAD_TEMP_DIR } from '../main/ets/common/DownloadFiles';

/**
 * common/DownloadFiles 的本地（宿主）单元测试。
 *
 * 只覆盖**纯字符串逻辑**：文件名净化与中转路径推导。
 * 这两件事是下载链路的安全边界 —— 文件名来自服务端 Content-Disposition，
 * 属于不可信输入，被拿去做路径拼接。因此必须能被独立验证，
 * 而不是只靠「构建通过」来担保。
 *
 * ensureDownloadTempDir / removeDownloadTempFile / cleanupDownloadTempFiles
 * 依赖 @kit.CoreFileKit，在宿主测试环境不可用，不在本地测试范围内。
 */
export default function downloadFilesTest() {
  describe('sanitizeFileName', () => {
    // 核心安全用例：路径分隔符必须被切断，只保留最后一段
    it('strips_directory_components', 0, () => {
      expect(sanitizeFileName('../../etc/passwd')).assertEqual('passwd');
      expect(sanitizeFileName('/etc/passwd')).assertEqual('passwd');
      expect(sanitizeFileName('..\\..\\windows\\system32\\evil.exe')).assertEqual('evil.exe');
      expect(sanitizeFileName('a/b/c/report.pdf')).assertEqual('report.pdf');
      expect(sanitizeFileName('C:\\Users\\x\\.ohos\\config\\secret.p12')).assertEqual('secret.p12');
    });

    // 纯点号名字净化后为空，必须回退，不能产出 "." / ".." 这类目录项
    it('neutralises_dot_only_names', 0, () => {
      expect(sanitizeFileName('..')).assertEqual('download');
      expect(sanitizeFileName('.')).assertEqual('download');
      expect(sanitizeFileName('...')).assertEqual('download');
    });

    it('replaces_illegal_characters', 0, () => {
      expect(sanitizeFileName('a<b>c:d"e|f?g*h.txt')).assertEqual('a_b_c_d_e_f_g_h.txt');
    });

    // Windows 系文件系统不允许以点或空格结尾
    it('trims_trailing_dots_and_spaces', 0, () => {
      expect(sanitizeFileName('report.txt.')).assertEqual('report.txt');
      expect(sanitizeFileName('report.txt   ')).assertEqual('report.txt');
    });

    it('falls_back_when_empty_or_blank', 0, () => {
      expect(sanitizeFileName('')).assertEqual('download');
      expect(sanitizeFileName('   ')).assertEqual('download');
    });

    // 正常文件名不能被误伤（含空格与中文）
    it('keeps_normal_names_untouched', 0, () => {
      expect(sanitizeFileName('report 2026.pdf')).assertEqual('report 2026.pdf');
      expect(sanitizeFileName('DeepSeek-对话记录.md')).assertEqual('DeepSeek-对话记录.md');
    });

    // 超长名字要截断，但扩展名必须保留
    it('limits_length_and_keeps_extension', 0, () => {
      const long: string = 'a'.repeat(200) + '.pdf';
      const out: string = sanitizeFileName(long);
      expect(out.length <= 120).assertTrue();
      expect(out.endsWith('.pdf')).assertTrue();
    });
  });

  describe('download temp path', () => {
    it('temp_dir_name_is_web', 0, () => {
      expect(DOWNLOAD_TEMP_DIR).assertEqual('web');
    });

    // 路径 → 文件名 的往返必须一致，否则落到公共目录的名字会和中转文件对不上
    it('round_trips_file_name', 0, () => {
      const p: string = buildDownloadTempPath('/cache', 'GUID-1', '报告.pdf');
      expect(p).assertEqual('/cache/web/GUID-1_报告.pdf');
      expect(fileNameFromTempPath(p, 'GUID-1')).assertEqual('报告.pdf');
    });

    // guid 前缀的意义：同名文件并发下载不能落到同一个文件上
    it('keeps_same_name_downloads_apart', 0, () => {
      const a: string = buildDownloadTempPath('/cache', 'g1', 'a.txt');
      const b: string = buildDownloadTempPath('/cache', 'g2', 'a.txt');
      expect(a === b).assertFalse();
    });
  });
}
