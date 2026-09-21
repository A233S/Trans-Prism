package com.daanser.transprism.widget

import android.content.Context
import android.content.res.Configuration

/**
 * 小组件深浅色 **唯一来源**：App 内「我的 → 主题模式」的同一份偏好。
 *
 * ── 规则（产品定稿）─────────────────────────────────────────────
 * - 跟 **App 内** 的深浅色，**不跟壁纸**、**不跟系统** —— 除非用户把 App 明确设为
 *   「跟随系统」（此时才落到系统 uiMode）。
 * - 禁止小组件自己再做一套「跟壁纸取反」。
 *
 * ── 实现要点（这里踩过坑，改之前务必读完）───────────────────────
 * Flutter 的 `shared_preferences` 落在 `FlutterSharedPreferences.xml`，
 * 键前缀固定 `flutter.`；`ThemeService` 用的键名是 `theme_mode`
 * （取值 `light` / `dark` / `system`，见 `lib/services/theme_service.dart`）。
 * 本对象**只读**该文件，不写。
 *
 * ⚠️ **不能靠自定义 `ColorProvider` 实现来绑主题**。
 * `androidx.glance.unit.ColorProvider` 虽然是接口，但 Glance 1.2.0 的
 * `RemoteViewsTranslator` **不是按接口多态取色**，而是 `when` 穷举它自己认识的
 * 三种实现（`FixedColorProvider` / `DayNightColorProvider` / `ResourceColorProvider`），
 * 其它一律命中 `else` 分支：
 *
 * ```
 * W GlanceAppWidget: Unexpected background color modifier: <你的实现>
 * W GlanceAppWidget: Unexpected text color: <你的实现>
 * ```
 *
 * 然后**静默丢弃** —— 背景变透明、文字回退系统默认色、进度条丢色。
 * （2026-09-19 真机实测确认，logcat 如上。）
 *
 * 所以正确做法是：在 `provideGlance` 这个 suspend 上下文里**一次性**读偏好，
 * 解析出 [MedsWidgetColors]，再用 Glance 认识的固定色（`FixedColorProvider`）
 * 铺进组合树 —— 见 `MedsWidgetThemeProvider` / `MedsTokens`。
 *
 * 附带好处：取色与「谁触发了这次 update」无关。若改用
 * `DayNightColorProvider` + 包一层改过 `Configuration` 的 Context，
 * 那么系统触发的刷新（`updatePeriodMillis` / 开机广播）仍会按**系统**深浅色渲染，
 * 同一个小部件会随触发方变色。
 */
object MedsWidgetThemePrefs {

    private const val PREFS_NAME = "FlutterSharedPreferences"
    private const val KEY_PREFIX = "flutter."
    private const val KEY_THEME_MODE = "theme_mode"

    const val MODE_LIGHT = "light"
    const val MODE_DARK = "dark"
    const val MODE_SYSTEM = "system"

    /** 读取 App 主题模式；缺失/异常一律回退 `system`（与 ThemeService 默认值一致） */
    fun mode(context: Context): String = try {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_PREFIX + KEY_THEME_MODE, MODE_SYSTEM)
            ?.takeIf { it == MODE_LIGHT || it == MODE_DARK || it == MODE_SYSTEM }
            ?: MODE_SYSTEM
    } catch (e: Exception) {
        MODE_SYSTEM
    }

    /**
     * 当前是否用深色 token。
     *  - `light`  → 恒浅色（即使系统是深色）
     *  - `dark`   → 恒深色
     *  - `system` → 跟随系统 uiMode
     */
    fun isDark(context: Context): Boolean = when (mode(context)) {
        MODE_LIGHT -> false
        MODE_DARK -> true
        else -> {
            val uiMode = context.resources.configuration.uiMode
            (uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
        }
    }

    /** 当前应使用的整套 token —— 在 `provideGlance` 里取一次，注入组合树 */
    fun colorsFor(context: Context): MedsWidgetColors =
        if (isDark(context)) MedsWidgetTheme.Dark else MedsWidgetTheme.Light
}
