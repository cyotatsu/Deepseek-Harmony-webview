/**
 * 应用自有界面（设置面板 / 弹窗 / 状态栏）的配色表。
 *
 * 为什么要它：这些界面原本直接用 `app.color.*` 资源，而资源只跟随**系统**深浅色。
 * 站点自己的「系统设置 → 主题」可以在系统为浅色时把网页切成深色，两边就会打架
 * （网页全黑、设置面板惨白）。
 *
 * 方案：由页面把「网页当前是否深色」作为 `webDark` 传下来，组件按它取色。
 * 这里刻意**不**调用 `ApplicationContext.setColorMode` —— 那会把整个应用的资源模式
 * 翻过去，连带改变 Web 内核上报的 `prefers-color-scheme`，于是站点选「跟随系统」时
 * 永远回到深色，形成死循环。
 *
 * 取值与 resources/{base,dark}/element/color.json 保持一致，改配色时两边要同步。
 */
export interface UiPalette {
  card: string;
  tile: string;
  textPrimary: string;
  textSecondary: string;
  buttonSecondary: string;
  accent: string;
  sliderTrack: string;
  sliderThumb: string;
  // Switch / Checkbox 未选中时的轨道底色。
  // 这两个控件的默认底色来自系统主题（深色下是 10% 白、浅色下是 10% 黑），
  // 系统深色而网页浅色时会在浅底上画一条几乎看不见的白条，所以显式给值。
  switchOff: string;
  shadow: string;
  /** 错误页整页底色（对应 web_background） */
  page: string;
  /** 模态遮罩（上传方式面板用） */
  scrim: string;
  /** 卡片投影（上传方式面板用） */
  cardShadow: string;
  /** 强调色按钮上的文字色 */
  textOnAccent: string;
}

/** 按网页深浅色取一套配色 */
export function uiPalette(dark: boolean): UiPalette {
  if (dark) {
    return {
      card: '#2A2A2A',
      tile: '#3A3A3A',
      textPrimary: '#FFFFFF',
      textSecondary: '#BBBBBB',
      buttonSecondary: '#3A3A3A',
      accent: '#4D6BFE',
      sliderTrack: '#3A3A3C',
      sliderThumb: '#FFFFFF',
      switchOff: '#4A4A4A',
      shadow: '#CC000000',
      page: '#000000',
      scrim: '#80000000',
      cardShadow: '#4D000000',
      textOnAccent: '#FFFFFF'
    };
  }
  return {
    card: '#FFFFFF',
    tile: '#F5F5F5',
    textPrimary: '#333333',
    textSecondary: '#999999',
    buttonSecondary: '#F0F0F0',
    accent: '#4D6BFE',
    sliderTrack: '#E5E5EA',
    sliderThumb: '#FFFFFF',
    switchOff: '#D8D8DC',
    shadow: '#1A000000',
    page: '#FFFFFF',
    scrim: '#80000000',
    cardShadow: '#4D000000',
    textOnAccent: '#FFFFFF'
  };
}
