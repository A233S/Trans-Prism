package com.daanser.transprism.widget

import androidx.compose.runtime.Immutable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
// 深浅色工厂：androidx.glance.color 下的顶层函数 ColorProvider(day, night)，
// 与类型 androidx.glance.unit.ColorProvider 同名，故用别名区分。
import androidx.glance.color.ColorProvider as colorProviderOf
import androidx.glance.unit.ColorProvider

/**
 * Trans Prism 用药小组件 —— 设计 token
 *
 * ⚠️ 全部数值 1:1 摘自定稿预览 `outputs/widget_preview.html`（唯一视觉真相），
 *    禁止凭记忆重画、禁止「接近」。
 *
 * 浅色 / 深色两套语义完全同源：同一套圆角、同一套字号层级、同一套
 * hairline 比例，仅色值不同 —— 保证浅深色一眼看出是同一个 App。
 *
 * ── 关于 GlanceTheme 的取舍（重要）──────────────────────────────
 * Glance 1.2.0 的 `androidx.glance.color.ColorProviders` 不是「深浅两套色」的
 * 泛型容器，而是一个 **28 槽 Material 色板抽象类**
 * （primary/onPrimary/…/surfaceVariant/outline/widgetBackground），
 * 必须全量填充才能构造。而 TP 的品牌色是 9 项**语义 token**，其中
 * pink / cyan / amber 承载「逾期 / 未逾期 / 库存告急」三态语义，
 * 强行压进 primary/secondary/tertiary 会丢失语义、并引入 20 项噪音槽位。
 *
 * 因此本实现采用 Glance 官方支持的等价机制：
 * `ColorProvider(day, night)` 逐 token 注入（见 [MedsTokens]），
 * 由 Glance 在渲染时自动按系统深浅色解析 —— 与 GlanceTheme 同源、更精确。
 * 下方 [MedsWidgetTheme.Light] / [MedsWidgetTheme.Dark] 即两套完整主题色。
 */
@Immutable
data class MedsWidgetColors(
    /** 卡片底。浅色纯白；深色暖黑（#211C1A），**禁止** Material 默认 #121212 */
    val card: Color,
    /** 标题近黑 / 深色近白 */
    val title: Color,
    /** 说明中灰 */
    val muted: Color,
    /** 品牌粉：进度、逾期强调、主按钮 */
    val pink: Color,
    /** 品牌青：未逾期的剩余时间 */
    val cyan: Color,
    /** 琥珀：**只**用于库存告急，不用于时间 */
    val amber: Color,
    /** 进度条轨道 / 7 天空心点描边 */
    val track: Color,
    /** 细边（深色下是暖边，不是冷灰） */
    val hairline: Color,
    /** 粉底之上的文字色 */
    val onPink: Color,
)

object MedsWidgetTheme {

    /** 浅色：暖白底 + 纯白卡 + 柔粉 */
    val Light = MedsWidgetColors(
        card = Color(0xFFFFFFFF),
        title = Color(0xFF1A1A1A),
        muted = Color(0xFF8A8580),
        pink = Color(0xFFE8899A),
        cyan = Color(0xFF4AB8C8),
        amber = Color(0xFFD4A017),
        track = Color(0xFFEDE8E4),
        hairline = Color(0xFFEFE7E1),
        onPink = Color(0xFFFFFFFF),
    )

    /**
     * 深色：暖黑卡（#211C1A，与 App 米白同源的夜间，**不是** Material Dark 冷炭灰）。
     * 深色壁纸上对比度已按 HTML 校准。
     */
    val Dark = MedsWidgetColors(
        card = Color(0xFF211C1A),
        title = Color(0xFFF3EEEA),
        muted = Color(0xFFA39A94),
        pink = Color(0xFFF0A3B0),
        cyan = Color(0xFF6BC9D4),
        amber = Color(0xFFE0B84A),
        track = Color(0xFF3A322E),
        hairline = Color(0xFF3A322E),
        onPink = Color(0xFF211C1A),
    )

    /** 两套主题色（Light / Dark），即 ColorProviders 语义下的两套取值。 */
    val all = listOf(Light, Dark)
}

/**
 * 逐 token 的 [ColorProvider]（day = 浅色，night = 深色）。
 *
 * Glance 会在渲染时按系统深浅色自动解析，无需手动判断。
 * 直接用于 `GlanceModifier.background(...)` / `TextStyle(color = ...)` /
 * `LinearProgressIndicator(color = ...)`。
 */
object MedsTokens {
    val card = colorProviderOf(day = MedsWidgetTheme.Light.card, night = MedsWidgetTheme.Dark.card)
    val title = colorProviderOf(day = MedsWidgetTheme.Light.title, night = MedsWidgetTheme.Dark.title)
    val muted = colorProviderOf(day = MedsWidgetTheme.Light.muted, night = MedsWidgetTheme.Dark.muted)
    val pink = colorProviderOf(day = MedsWidgetTheme.Light.pink, night = MedsWidgetTheme.Dark.pink)
    val cyan = colorProviderOf(day = MedsWidgetTheme.Light.cyan, night = MedsWidgetTheme.Dark.cyan)
    val amber = colorProviderOf(day = MedsWidgetTheme.Light.amber, night = MedsWidgetTheme.Dark.amber)
    val track = colorProviderOf(day = MedsWidgetTheme.Light.track, night = MedsWidgetTheme.Dark.track)
    val hairline =
        colorProviderOf(day = MedsWidgetTheme.Light.hairline, night = MedsWidgetTheme.Dark.hairline)
    val onPink =
        colorProviderOf(day = MedsWidgetTheme.Light.onPink, night = MedsWidgetTheme.Dark.onPink)

    /** 7 天空心点描边：与轨道同色（HTML 中两者同值） */
    val dotOutline = track

    /** 进度条填充色 —— 三态语义，禁止串用 */
    fun barFill(color: MedsBarColor): ColorProvider = when (color) {
        MedsBarColor.AMBER -> amber   // 库存告急（且不拉满）
        MedsBarColor.PINK -> pink     // 逾期
        MedsBarColor.CYAN -> cyan     // 未逾期
    }

    /**
     * 状态圆点颜色 —— **只区分逾期/未逾期**（粉 / 青）。
     * 琥珀仅用于库存告急的进度条与「库存告急」按钮，**不用于状态点、不用于时间**。
     */
    fun statusDot(state: MedsTimeState): ColorProvider =
        if (state == MedsTimeState.OVERDUE) pink else cyan

    /** 时间文字颜色：逾期粉 / 未逾期青（琥珀不用于时间） */
    fun timeText(state: MedsTimeState): ColorProvider =
        if (state == MedsTimeState.OVERDUE) pink else cyan
}

/**
 * 尺寸 token —— 1:1 摘自 HTML（CSS px → dp/sp 同值映射）。
 *
 * HTML 是密度无关的设计稿，1px = 1dp；字号同理 1px = 1sp。
 */
object MedsDims {
    /** 卡片圆角 —— 跟 Pixel 小组件（约 24） */
    val cardRadius: Dp = 24.dp

    // ── 中卡 ──
    val mediumPaddingH: Dp = 20.dp
    val mediumPaddingTop: Dp = 18.dp
    val mediumPaddingBottom: Dp = 16.dp
    /** 进度条左缩进，与药名文字左边缘对齐（icon 18 + gap 9） */
    val barInset: Dp = 27.dp
    val barHeight: Dp = 2.dp

    val iconSize: Dp = 14.dp
    /** 小卡针筒（HTML `.s-head .syringe` = 12px） */
    val iconSizeSmall: Dp = 12.dp
    val iconBoxWidth: Dp = 18.dp
    val iconGap: Dp = 9.dp
    val statusDot: Dp = 6.dp
    /** 7 天圆点 —— 不是胶囊条 */
    val weekDot: Dp = 7.dp
    val weekDotGap: Dp = 6.dp
    val hairlineHeight: Dp = 1.dp

    // ── 小卡 ──
    val smallPaddingH: Dp = 14.dp
    val smallPaddingTop: Dp = 14.dp
    val smallPaddingBottom: Dp = 12.dp
    val smallBtnHeight: Dp = 30.dp
    val smallBtnGap: Dp = 7.dp
    /** 描边按钮的内缩量 = 边框粗细（Glance 无 border，用双层 Box 模拟） */
    val strokeWidth: Dp = 1.dp

    // ── 字号（HTML px → sp） ──
    val fsMediumTitle: TextUnit = 13.sp      // 今日 1/4
    val fsPill: TextUnit = 11.sp             // 记一次（中卡胶囊）
    val fsMedName: TextUnit = 13.sp          // 药名
    val fsStock: TextUnit = 10.5.sp          // 库存不足 1 次 / 剩 4 次
    val fsTime: TextUnit = 12.5.sp           // 已超 9 小时 / 1天20小时
    val fsWeekLabel: TextUnit = 10.5.sp      // 近 7 天
    val fsWeekCount: TextUnit = 11.sp        // 5/7

    val fsSmallName: TextUnit = 11.5.sp      // 小卡药名
    val fsSmallState: TextUnit = 11.sp       // 已超
    val fsSmallNum: TextUnit = 62.sp         // 9 —— 主视觉
    val fsSmallUnit: TextUnit = 13.sp        // 小时
    val fsSmallBtn: TextUnit = 11.5.sp       // 记一次 / 库存告急

    // ── 触控区 ──
    /** 无障碍最小可点高度（小卡按钮视觉高度低于此值时，用外层 Box 撑到该值） */
    val minTouchTarget: Dp = 48.dp

    // ── 已知限制 ──
    // Glance 1.2.0 的 `androidx.glance.text.TextStyle` 只有
    // color / fontSize / fontWeight / fontStyle / textAlign / textDecoration / fontFamily
    // 七个参数，**不支持 fontFeatureSettings**，故 HTML 里的
    // `font-variant-numeric: tabular-nums` 无法在 widget 内生效。
    // 影响与替代见 PR 说明「差异表」；右对齐仍由布局保证。
}
