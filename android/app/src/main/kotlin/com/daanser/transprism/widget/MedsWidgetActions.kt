package com.daanser.transprism.widget

import androidx.glance.action.ActionParameters
import androidx.glance.action.mutableActionParametersOf

/**
 * 小组件 → App 的动作契约。
 *
 * 小组件跑在原生进程，无法直接调用 Dart 侧的
 * `MedicationService.executeMedicationDose()`。
 * 因此所有点击统一走 `actionStartActivity<MainActivity>` 携带 action extra 唤起 App，
 * 由 MainActivity 经 MethodChannel 交给 Dart 侧**既有 use case** 执行 ——
 * 打卡 / 扣库存 / 重排通知的业务逻辑**零复制**，不产生第二套写入路径。
 */
object MedsWidgetActions {

    /** 「记一次」—— 打卡 */
    const val ACTION_RECORD_DOSE = "record_dose"

    /** 「库存告急」—— 库存页 / 补货深链，无则打开该药详情 */
    const val ACTION_STOCK_ALERT = "stock_alert"

    /** 点击整卡 —— 打开今日用药页 */
    const val ACTION_OPEN_MEDS = "open_meds"

    /** 与 MainActivity / Dart 侧约定的 Intent extra key */
    const val EXTRA_ACTION = "tp_widget_action"
    const val EXTRA_DRUG_ID = "tp_widget_drug_id"
    const val EXTRA_DRUG_NAME = "tp_widget_drug_name"

    val KEY_ACTION = ActionParameters.Key<String>(EXTRA_ACTION)
    val KEY_DRUG_ID = ActionParameters.Key<String>(EXTRA_DRUG_ID)
    val KEY_DRUG_NAME = ActionParameters.Key<String>(EXTRA_DRUG_NAME)

    /**
     * 组装 action 参数。
     *
     * [drugId] / [drugName] 为空时不下发对应键 —— 中卡顶部「记一次」是通用入口，
     * 不绑定具体药物，由 App 侧决定打卡哪一条。
     */
    fun params(
        action: String,
        drugId: String? = null,
        drugName: String? = null,
    ): ActionParameters {
        // 用 MutableActionParameters 而不是 actionParametersOf(vararg)：
        // 后者的入参是 Glance 自己的 ActionParameters.Pair，
        // Kotlin 的 `key to value` 得到的是标准库 Pair，类型不匹配。
        val p = mutableActionParametersOf()
        p.set(KEY_ACTION, action)
        if (drugId != null) p.set(KEY_DRUG_ID, drugId)
        if (drugName != null) p.set(KEY_DRUG_NAME, drugName)
        return p
    }
}
