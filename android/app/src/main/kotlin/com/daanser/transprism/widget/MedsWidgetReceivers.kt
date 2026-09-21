package com.daanser.transprism.widget

import android.content.Context
import android.util.Log
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * 中卡 / 小卡的 AppWidget Receiver。
 *
 * 两个 Receiver 共享同一份数据源（Flutter 侧 SharedPreferences），
 * 不持有任何独立状态。
 */

class MediumMedsWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = MediumMedsWidget()
}

class SmallMedsWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = SmallMedsWidget()
}

/**
 * 供 App 侧主动刷新 widget。
 *
 * Glance 1.2.0 的 `GlanceAppWidget` 已移除 `updateAll()`，需经
 * [GlanceAppWidgetManager.getGlanceIds] 枚举当前桌面上的所有实例再逐个 `update`。
 *
 * ── 为什么要去抖（这里踩过坑）───────────────────────────────────
 * 刷新有**两个**触发源，且经常在同一瞬间撞车：
 *  1. 点小组件打卡 → `MainActivity` 起来 → `onResume` 触发一次「回前台刷新」；
 *  2. 紧接着 Dart 侧 `executeMedicationDose()` 完成后又触发一次「打卡后刷新」。
 *
 * 两次请求相隔约 100ms。Glance 会把它们**合并成一次会话**，而会话在**启动时**
 * 就读 `SharedPreferences` —— 于是渲染出的是**打卡前**的数据
 * （真机实测：卡片停在「剩 16 次 / 今日 2/4」，而库里已是「剩 15 次 / 今日 4/4」，
 * 要等下一次刷新才追上）。
 *
 * 解法：**尾沿去抖**（trailing debounce）。只有静默 [DEBOUNCE_MS] 之后仍无新请求，
 * 才真正渲染一次 —— 那时数据早已落库，且无论几个触发源，最终只渲染一次。
 */
object MedsWidgetUpdater {

    /**
     * 去抖窗口。
     * 取 700ms：够覆盖「onResume → executeMedicationDose 落库」这段（实测 < 200ms），
     * 又短到用户点完打卡回到桌面时基本已经刷新完毕。
     */
    private const val DEBOUNCE_MS = 700L

    private val scope = CoroutineScope(Dispatchers.Main.immediate + SupervisorJob())
    private var pending: Job? = null

    /**
     * 请求刷新（**非挂起**，可安全地在 MethodChannel 回调里直接调）。
     *
     * 多次调用只在最后一次之后 [DEBOUNCE_MS] 真正执行一次 —— 天然做到
     * 「最后一次请求赢」，不会出现旧数据盖掉新数据。
     */
    fun requestRefresh(context: Context) {
        val appContext = context.applicationContext
        Log.d(TAG, "requestRefresh: 排入去抖队列")
        pending?.cancel()
        pending = scope.launch {
            delay(DEBOUNCE_MS)
            refreshAll(appContext)
        }
    }

    /**
     * 立即刷新两个尺寸 widget 的全部实例（幂等，无实例时静默返回）。
     *
     * 一般不要直接调它 —— 走 [requestRefresh] 以免与别的触发源撞车。
     */
    suspend fun refreshAll(context: Context) {
        val manager = GlanceAppWidgetManager(context)
        val medium = MediumMedsWidget()
        val mediumIds = manager.getGlanceIds(MediumMedsWidget::class.java)
        mediumIds.forEach { id -> medium.update(context, id) }

        val small = SmallMedsWidget()
        val smallIds = manager.getGlanceIds(SmallMedsWidget::class.java)
        smallIds.forEach { id -> small.update(context, id) }

        Log.d(TAG, "refreshAll: medium=${mediumIds.size} small=${smallIds.size}")
    }

    private const val TAG = "TP-Widget"
}

/** 两个 widget 共用 `SizeMode.Exact` —— 布局用 `fillMaxSize` + `defaultWeight` 自适应，不写死尺寸。 */
internal val MEDS_WIDGET_SIZE_MODE: SizeMode = SizeMode.Exact
