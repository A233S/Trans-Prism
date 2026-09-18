package com.daanser.transprism.widget

import android.content.Context
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode

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
 * 调用时机：Dart 侧完成一次打卡（`MedicationService.executeMedicationDose`）后，
 * 经 MethodChannel 通知 MainActivity 调用本方法，保证桌面卡片立即反映新库存与新倒计时。
 */
object MedsWidgetUpdater {

    /** 刷新两个尺寸 widget 的全部实例（幂等，无实例时静默返回） */
    suspend fun refreshAll(context: Context) {
        val manager = GlanceAppWidgetManager(context)
        val medium = MediumMedsWidget()
        manager.getGlanceIds(MediumMedsWidget::class.java)
            .forEach { id -> medium.update(context, id) }

        val small = SmallMedsWidget()
        manager.getGlanceIds(SmallMedsWidget::class.java)
            .forEach { id -> small.update(context, id) }
    }
}

/** 两个 widget 共用 `SizeMode.Exact` —— 布局用 `fillMaxSize` + `defaultWeight` 自适应，不写死尺寸。 */
internal val MEDS_WIDGET_SIZE_MODE: SizeMode = SizeMode.Exact
