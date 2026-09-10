import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0001;
const TAG = 'DeepSeekUiPrefs';

/** 应用界面偏好存储：刷新按钮位置、「长按可拖动」提示是否已展示 */
const STORE_NAME: string = 'deepseek_ui';
const KEY_BTN_DX: string = 'refresh_btn_dx';
const KEY_BTN_DY: string = 'refresh_btn_dy';
const KEY_HINT_SHOWN: string = 'refresh_btn_hint_shown';
const KEY_REFRESH_ENABLED: string = 'refresh_btn_enabled';
const KEY_REFRESH_CONFIRM_SKIPPED: string = 'refresh_confirm_skipped';

function openStore(context: common.Context): preferences.Preferences | null {
  try {
    return preferences.getPreferencesSync(context, { name: STORE_NAME });
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'Failed to open preferences store');
    return null;
  }
}

/**
 * 读取刷新按钮的拖拽位移，返回 [dx, dy]。
 * 读取失败或从未保存过时返回 [0, 0]，即默认的右下角位置。
 */
export function loadRefreshButtonOffset(context: common.Context): number[] {
  const store: preferences.Preferences | null = openStore(context);
  if (!store) {
    return [0, 0];
  }
  try {
    const dx: number = store.getSync(KEY_BTN_DX, 0) as number;
    const dy: number = store.getSync(KEY_BTN_DY, 0) as number;
    return [dx, dy];
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'Failed to load refresh button offset');
    return [0, 0];
  }
}

/** 保存刷新按钮的拖拽位移（拖动结束时调用） */
export function saveRefreshButtonOffset(context: common.Context, dx: number, dy: number): void {
  const store: preferences.Preferences | null = openStore(context);
  if (!store) {
    return;
  }
  try {
    store.putSync(KEY_BTN_DX, dx);
    store.putSync(KEY_BTN_DY, dy);
    store.flush().catch(() => {
      hilog.warn(DOMAIN, TAG, 'Failed to flush refresh button offset');
    });
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'Failed to save refresh button offset');
  }
}

/**
 * 「长按可拖动」提示是否已经展示过。
 * 读取失败时返回 true（当作已展示），宁可不提示，也不要在每次启动时反复打扰用户。
 */
export function isRefreshHintShown(context: common.Context): boolean {
  const store: preferences.Preferences | null = openStore(context);
  if (!store) {
    return true;
  }
  try {
    return store.getSync(KEY_HINT_SHOWN, false) as boolean;
  } catch (err) {
    return true;
  }
}

/** 标记「长按可拖动」提示已展示 */
export function markRefreshHintShown(context: common.Context): void {
  const store: preferences.Preferences | null = openStore(context);
  if (!store) {
    return;
  }
  try {
    store.putSync(KEY_HINT_SHOWN, true);
    store.flush().catch(() => {
      hilog.warn(DOMAIN, TAG, 'Failed to flush refresh hint flag');
    });
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'Failed to mark refresh hint shown');
  }
}

/** 刷新按钮是否启用（设置面板里的开关）。读取失败时按启用处理。 */
export function isRefreshButtonEnabled(context: common.Context): boolean {
  const store: preferences.Preferences | null = openStore(context);
  if (!store) {
    return true;
  }
  try {
    return store.getSync(KEY_REFRESH_ENABLED, true) as boolean;
  } catch (err) {
    return true;
  }
}

/** 保存刷新按钮的启用状态 */
export function setRefreshButtonEnabled(context: common.Context, enabled: boolean): void {
  const store: preferences.Preferences | null = openStore(context);
  if (!store) {
    return;
  }
  try {
    store.putSync(KEY_REFRESH_ENABLED, enabled);
    store.flush().catch(() => {
      hilog.warn(DOMAIN, TAG, 'Failed to flush refresh button enabled flag');
    });
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'Failed to save refresh button enabled flag');
  }
}

/**
 * 用户是否已勾选「不再显示」刷新确认弹窗。
 * 读取失败返回 false（照常提示），宁可多问一次，也不要静默跳过。
 */
export function isRefreshConfirmSkipped(context: common.Context): boolean {
  const store: preferences.Preferences | null = openStore(context);
  if (!store) {
    return false;
  }
  try {
    return store.getSync(KEY_REFRESH_CONFIRM_SKIPPED, false) as boolean;
  } catch (err) {
    return false;
  }
}

/** 保存「不再显示刷新确认」的选择 */
export function setRefreshConfirmSkipped(context: common.Context, skipped: boolean): void {
  const store: preferences.Preferences | null = openStore(context);
  if (!store) {
    return;
  }
  try {
    store.putSync(KEY_REFRESH_CONFIRM_SKIPPED, skipped);
    store.flush().catch(() => {
      hilog.warn(DOMAIN, TAG, 'Failed to flush refresh confirm skipped flag');
    });
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'Failed to save refresh confirm skipped flag');
  }
}
