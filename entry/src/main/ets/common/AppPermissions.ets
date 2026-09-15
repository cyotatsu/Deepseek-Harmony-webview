import { abilityAccessCtrl, bundleManager, common, PermissionRequestResult, Permissions } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

const DOMAIN = 0x0001;
const TAG = 'DeepSeekAppPermissions';

/**
 * 应用级权限申请。
 *
 * 背景：ArkWeb 的 onPermissionRequest 只负责「网页 → 应用」这一层放行，
 * 真正能否采集音频还取决于**应用自身**是否已获得系统权限（ohos.permission.MICROPHONE，
 * user_grant 类型，必须运行时申请）。只 grant 网页请求而不申请系统权限，
 * 网页侧的录音会拿到流但采不到数据。
 *
 * 因此这里按官方链路补齐第二步：checkAccessToken → requestPermissionsFromUser。
 */

/** 语音输入所需的系统权限 */
export const MICROPHONE_PERMISSION: Permissions = 'ohos.permission.MICROPHONE';

/** 是否已获得某系统权限（同步查询，失败时保守返回 false） */
export function hasPermission(permission: Permissions): boolean {
  try {
    const tokenId: number = bundleManager.getBundleInfoForSelfSync(
      bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION).appInfo.accessTokenId;
    const status: abilityAccessCtrl.GrantStatus =
      abilityAccessCtrl.createAtManager().checkAccessTokenSync(tokenId, permission);
    return status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'checkAccessToken failed');
    return false;
  }
}

/**
 * 确保已获得指定系统权限；未获得则弹系统授权框。
 *
 * @returns 最终是否已授权。任何异常都按未授权处理 —— 权限问题宁可拒绝也不误放行。
 */
export async function ensurePermission(
  context: common.UIAbilityContext, permission: Permissions): Promise<boolean> {
  if (hasPermission(permission)) {
    return true;
  }
  try {
    const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    const result: PermissionRequestResult =
      await atManager.requestPermissionsFromUser(context, [permission]);
    if (result.authResults.length > 0 && result.authResults[0] === 0) {
      hilog.info(DOMAIN, TAG, 'Permission granted by user');
      return true;
    }
    hilog.info(DOMAIN, TAG, 'Permission denied by user');
    return false;
  } catch (err) {
    const e = err as BusinessError;
    hilog.warn(DOMAIN, TAG, 'requestPermissionsFromUser failed: %{public}d', e.code);
    return false;
  }
}
