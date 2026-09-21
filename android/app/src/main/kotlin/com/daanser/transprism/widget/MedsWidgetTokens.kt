package com.daanser.transprism.widget

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.unit.ColorProvider

/**
 * Trans Prism 用药小组件 —— 设计 token
 *
 * ⚠️ 全部数值 1:1 摘自定稿预览（唯一视觉真相），禁止凭记忆重画、禁止「接近」。
 *
 * 浅色 / 深色两套语义完全同源：同一套圆角、同一套字号层级、同一套
 * hairline 比例，仅色值不同 —— 保证浅深色一眼看出是同一个 App。
 *
 * ── 深浅色是怎么定下来的（v2.1，重要）────────────────────────────
 * Glance 的 `RemoteViewsTranslator` **只认它自己的三种 ColorProvider**，
 * 自定义实现会被静默丢弃（见 [MedsWidgetThemePrefs] 类注释里的 logcat 实录）。
 *
 * 因此取色链路是：
 *
 * ```
 * provideGlance(context)                       ← suspend，能读 SharedPreferences
 *   └─ MedsWidgetThemePrefs.colorsFor(context) ← light / dark / system 在这里判定
 *        └─ MedsWidgetThemeProvider(colors) { … }   ← 注入 CompositionLocal
 *             └─ MedsTokens.card / .title / …         ← @Composable getter，取当前那一套
 *                  └─ FixedColorProvider(Color)      ← Glance 认识，不会被丢
 * ```
 *
 * 结果：卡片配色只由 **App 主题偏好** 决定，与「谁触发了这次 update」无关。
 *
 * ── 关于 GlanceTheme 的取舍 ────────────────────────────────────
 * Glance 的 `androidx.glance.color.ColorProviders` 不是「深浅两套色」的泛型容器，
 * 而是一个 **28 槽 Material 色板抽象类**，必须全量填充才能构造。而 TP 的品牌色是
 * **语义 token**（粉=逾期 / 青=未逾期 / 琥珀=库存告急），压进
 * primary/secondary/tertiary 会丢失语义并引入 20 项噪音槽位 —— 故不用。
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
    /** 进度条轨道 / 7 天空心点描边 / 环形轨道 */
    val track: Color,
    /** 细边（深色下是暖边，不是冷灰） */
    val hairline: Color,
    /** 粉底之上的文字色 */
    val onPink: Color,
    /**
     * 「下一剂」那一行的**极轻底色**（v3 起改为中性提亮）。
     *
     * v2 用的是「同色系 8%~14% 的品牌色浅底」，真机上整行像一块被选中的列表 item，
     * 而且会让人误以为「只有这一行能点」。v3 改成**中性、极低透明度**的提亮
     * （浅色 4% 黑 / 深色 8% 白）—— 只负责「这一行稍微亮一点」，
     * 真正的语义交给左侧 3.5dp 状态色竖条。
     */
    val rowHighlight: Color,
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
        rowHighlight = Color(0x0A000000),
    )

    /**
     * 深色：暖黑卡（#211C1A，与 App 米白同源的夜间，**不是** Material Dark 冷炭灰）。
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
        rowHighlight = Color(0x14FFFFFF),
    )

    /** 两套主题色（Light / Dark） */
    val all = listOf(Light, Dark)
}

/**
 * 当前这次组合要用的 token 集。
 *
 * 默认值只是兜底（真机上一定会被 [MedsWidgetThemeProvider] 覆盖）——
 * 组件**必须**由 `provideGlance` / `providePreview` 经 provider 包一层。
 */
internal val LocalMedsColors = staticCompositionLocalOf { MedsWidgetTheme.Light }

/**
 * 把 [MedsWidgetThemePrefs.colorsFor] 的结果注入组合树。
 *
 * 必须在两个 widget 的 `provideContent { }` 最外层调用。
 */
@Composable
fun MedsWidgetThemeProvider(colors: MedsWidgetColors, content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalMedsColors provides colors) {
        content()
    }
}

/** 固定色 → Glance 认识的 `FixedColorProvider`（唯一不会被丢的取色方式） */
private fun fixed(color: Color): ColorProvider = ColorProvider(color)

/**
 * 逐 token 的 [ColorProvider]，**按 App 主题偏好解析**（组合期由 CompositionLocal 决定）。
 *
 * ⚠️ 全部成员都是 `@Composable get()` —— 只能在 composable 里读。
 * 这是刻意的：色值必须在组合期确定，才能在交给 Glance 之前落成 `FixedColorProvider`。
 */
object MedsTokens {

    /** 当前这一套完整 token（环渲染等需要原始 `Color` 的场景用） */
    val current: MedsWidgetColors
        @Composable get() = LocalMedsColors.current

    val card: ColorProvider
        @Composable get() = fixed(LocalMedsColors.current.card)
    val title: ColorProvider
        @Composable get() = fixed(LocalMedsColors.current.title)
    val muted: ColorProvider
        @Composable get() = fixed(LocalMedsColors.current.muted)
    val pink: ColorProvider
        @Composable get() = fixed(LocalMedsColors.current.pink)
    val cyan: ColorProvider
        @Composable get() = fixed(LocalMedsColors.current.cyan)
    val amber: ColorProvider
        @Composable get() = fixed(LocalMedsColors.current.amber)
    val track: ColorProvider
        @Composable get() = fixed(LocalMedsColors.current.track)
    val hairline: ColorProvider
        @Composable get() = fixed(LocalMedsColors.current.hairline)
    val onPink: ColorProvider
        @Composable get() = fixed(LocalMedsColors.current.onPink)

    /** 7 天空心点描边：与轨道同色 */
    val dotOutline: ColorProvider
        @Composable get() = track

    /** 透明占位（未高亮的行保留同样的缩进，避免行间错位）—— 与主题无关，可作常量 */
    val transparent: ColorProvider = fixed(Color.Transparent)

    /** 进度条填充色 —— 三态语义，禁止串用 */
    @Composable
    fun barFill(color: MedsBarColor): ColorProvider = when (color) {
        MedsBarColor.AMBER -> amber   // 库存告急（且不拉满）
        MedsBarColor.PINK -> pink     // 逾期
        MedsBarColor.CYAN -> cyan     // 未逾期
    }

    /**
     * 状态圆点 / 「下一剂」左侧竖条颜色 —— **只区分逾期/未逾期**（粉 / 青）。
     * 琥珀仅用于库存告急的进度条与「库存不足」提示，**不用于状态点、不用于时间**。
     */
    @Composable
    fun statusDot(state: MedsTimeState): ColorProvider =
        if (state == MedsTimeState.OVERDUE) pink else cyan

    /** 时间文字颜色：逾期粉 / 未逾期青（琥珀不用于时间） */
    @Composable
    fun timeText(state: MedsTimeState): ColorProvider =
        if (state == MedsTimeState.OVERDUE) pink else cyan

    /** 「下一剂」那一行的极轻中性底色（配合左侧竖条，见 [MedsWidgetColors.rowHighlight]） */
    val rowHighlight: ColorProvider
        @Composable get() = fixed(LocalMedsColors.current.rowHighlight)

    /**
     * 小卡环形进度环 / 中心主数字的颜色：
     * **待服用青、已超用粉** —— v2 明确修掉的 UI 债
     * （旧版不论状态一律 `pink`，导致「待服」也显示粉色 9）。
     */
    @Composable
    fun ringAccent(overdue: Boolean): ColorProvider = if (overdue) pink else cyan
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
    val mediumPaddingTop: Dp = 14.dp
    val mediumPaddingBottom: Dp = 12.dp

    /**
     * 行容器左右内边距。
     * **所有行都套同样的 padding**（含未高亮的行）—— 只有背景色不同，
     * 这样高亮行不会把内容整体推开，三行的图标 / 药名 / 时间仍在同一竖线。
     */
    val rowPaddingH: Dp = 8.dp
    /** 行上下内边距。3×4 的竖向预算很紧，每多 1dp 就要从底栏抠 3dp */
    val rowPaddingV: Dp = 4.dp
    /**
     * 三行之间的固定间距。
     * v2 用「每行后一个 `defaultWeight()` 均分富余」，真机上被撑到 ~22dp/行，
     * 三行显得很散；v3 改成固定间距，富余空间统一留给底栏上方（见 MediumMedsWidget）。
     */
    val rowGap: Dp = 5.dp
    val rowRadius: Dp = 10.dp
    /** 「下一剂」左侧竖条（3.5dp 宽，固定高度；Glance 下比 fillMaxHeight 更可控） */
    val nextBarWidth: Dp = 3.5.dp
    val nextBarHeight: Dp = 30.dp
    val nextBarGap: Dp = 8.dp

    /** 进度条左缩进 = 药名文字左边缘（竖条 3.5 + 间隙 8 + 图标 15 + 间隙 5 + 状态点 6 + 间隙 8） */
    val barInset: Dp = 45.5.dp
    val barHeight: Dp = 2.dp

    val iconSize: Dp = 15.dp
    /** 小卡针筒 */
    val iconSizeSmall: Dp = 13.dp
    val iconDotGap: Dp = 5.dp
    val statusDot: Dp = 6.dp
    /** 7 天圆点 —— 不是胶囊条 */
    val weekDot: Dp = 7.dp
    val weekDotGap: Dp = 6.dp
    val hairlineHeight: Dp = 1.dp
    /** 底栏上下留白 */
    val weekPadV: Dp = 5.dp

    /**
     * 时间列固定宽度 + 右对齐。
     * Glance 1.2.0 的 `TextStyle` **不支持 `fontFeatureSettings`**，
     * 无法真正开启 `tabular-nums`；用「固定宽 + TextAlign.End」达到
     * 同样的观感：三行时间数字的**右边缘落在同一竖线**（等宽列）。
     */
    val timeColumnWidth: Dp = 74.dp

    // ── 小卡 ──
    val smallPaddingH: Dp = 12.dp
    val smallPaddingTop: Dp = 12.dp
    /** 比左右略大一点：按钮不顶死底边，留出与卡片圆角一致的呼吸 */
    val smallPaddingBottom: Dp = 13.dp
    val smallBtnHeight: Dp = 30.dp
    /** 描边按钮的内缩量 = 边框粗细（Glance 无 border，用双层 Box 模拟） */
    val strokeWidth: Dp = 1.dp
    /** 环位图兜底边长（真实边长按组件尺寸 × 密度推导，见 SmallMedsWidget） */
    val ringFallbackPx: Int = 240
    val ringMinPx: Int = 64
    val ringMaxPx: Int = 288

    // ── 字号（HTML px → sp） ──
    val fsMediumTitle: TextUnit = 13.sp      // 今日 1/4
    val fsPill: TextUnit = 11.sp             // 记 螺内酯（中卡胶囊）
    val fsMedName: TextUnit = 13.sp          // 药名
    val fsStock: TextUnit = 10.5.sp          // 库存不足 0 次 / 剩 4 次
    val fsTime: TextUnit = 12.5.sp           // 已超 9 小时 / 1天20小时
    val fsWeekLabel: TextUnit = 10.5.sp      // 近 7 天
    val fsWeekCount: TextUnit = 11.sp        // 5/7
    /** 中卡右上角的说明文字「点对应药物服药」—— muted 小字，**不是按钮** */
    val fsHint: TextUnit = 10.5.sp

    val fsSmallName: TextUnit = 11.5.sp      // 小卡药名
    val fsSmallState: TextUnit = 10.5.sp     // 待服 / 已超（环下小标签）
    val fsSmallNum: TextUnit = 26.sp         // 环心主数字
    val fsSmallUnit: TextUnit = 9.5.sp       // 小时 / 分钟
    val fsSmallBtn: TextUnit = 11.5.sp       // 记 螺内酯
    val fsSmallCritical: TextUnit = 9.5.sp   // 库存不足（琥珀小字）

    // ── 触控区 ──
    /** 无障碍最小可点高度 */
    val minTouchTarget: Dp = 48.dp

    // ── 已知限制 ──
    // Glance 1.2.0 的 `androidx.glance.text.TextStyle` 只有
    // color / fontSize / fontWeight / fontStyle / textAlign / textDecoration / fontFamily
    // 七个参数，**不支持 fontFeatureSettings**，故 HTML 里的
    // `font-variant-numeric: tabular-nums` 无法在 widget 内生效。
    // v2 以「固定宽度时间列 + TextAlign.End」达到等效的等宽右对齐观感。
}
