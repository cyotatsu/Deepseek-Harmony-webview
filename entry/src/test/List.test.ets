import localUnitTest from './LocalUnit.test';
import downloadFilesTest from './DownloadFiles.test';
import webViewportTest from './WebViewport.test';
import webInputGuardTest from './WebInputGuard.test';
import backPolicyTest from './BackPolicy.test';

export default function testsuite() {
  localUnitTest();
  downloadFilesTest();
  webViewportTest();
  webInputGuardTest();
  backPolicyTest();
}
