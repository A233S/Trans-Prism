package com.daanser.transprism.widget

import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.glance.LocalContext
import androidx.glance.action.Action
import androidx.glance.action.ActionParameters
import androidx.glance.action.mutableActionParametersOf
import androidx.glance.appwidget.action.StartActivityIntentAction
import com.daanser.transprism.MainActivity

/**
 * 小组件 → App 的动作契约。
 *
 * 小组件跑在原生进程，无法直接调用 Dart 侧的
 * `MedicationService.executeMedicationDose()`。
 * 因此所有点击统一经 [`widgetClickAction`]（`getActivity` 单跳，Intent 与桌面图标同形）
 * 携带 action extra 唤起 App，
 * 由 MainActivity 经 MethodChannel 交给 Dart 侧处理。
 *
 * ── v3 核心原则：**小组件永不写入数据** ──────────────────────────
 * v2 及以前，点行 / 点按钮会**直接打卡扣库存**，没有确认，极易误触
 * （口袋误触、滑动误触都会真的记一笔药）。
 *
 * v3 起小组件只做一件事：**带 medId 唤起 App，并让 App 拉起该药的
 * 「记录用药」Sheet**（`RecordDoseDialog`，含 当前库存 / 本次剂量 / 下次计划 /
 * 取消 / 确认服药）。真正的写入只发生在 Sheet 里点「确认服药」那一刻。
 *
 * 于是：
 * - 点行 / 点环 / 点按钮 → [ACTION_OPEN_RECORD_SHEET]（**不写数据**）
 * - 取消 / 系统返回 → 什么都不发生
 * - 只有 `RecordDoseDialog._confirmDose()` 会走 `executeMedicationDose()`
 */
object MedsWidgetActions {

    /**
     * **打开「记录用药」Sheet** —— v3 起小组件唯一的打卡入口。
     *
     * 必须带 [EXTRA_DRUG_ID]；Dart 侧据此加载该药并 `RecordDoseDialog.show(...)`。
     */
    const val ACTION_OPEN_RECORD_SHEET = "open_record_sheet"

    /**
     * 旧版「直接打卡」动作 —— **v3 起小组件不再发出**。
     *
     * 保留常量仅为兼容旧版小组件残留的 PendingIntent：
     * Dart 侧把它与 [ACTION_OPEN_RECORD_SHEET] **合并处理**（同样只开 Sheet、不写入），
     * 这样即使桌面上还挂着旧卡，也绝不会出现「无确认就记一笔」的路径。
     */
    const val ACTION_RECORD_DOSE = "record_dose"

    /**
     * 「库存告急」—— 库存页 / 补货深链。
     *
     * ⚠️ v2 起小组件不再发出：小卡的「库存告急」第二按钮已删除，
     * 库存告急改为药名旁的一行琥珀小字「库存不足」。常量与 Dart 侧处理保留，
     * 以便将来若有其他入口（如通知动作）复用同一契约。
     */
    const val ACTION_STOCK_ALERT = "stock_alert"

    /** 点击整卡空白处 —— 打开今日用药页 */
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
     * [drugName] 只用于日志/兜底展示；真正定位药物靠 [drugId]。
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

/**
 * 构造「打开 App」的点击 Action —— **`PendingIntent.getActivity` 单跳直拉**。
 *
 * ## 为什么不用广播中转（走过弯路，记录在此避免重蹈）
 *
 * 同级参考项目 `calendar_countdown_widget` 用「广播 → 自己的 Provider → `startActivity`」
 * 绕开 HyperOS，其 README 原文是：
 *
 * > 小组件的 `PendingIntent` 不能直接从桌面进程启动**「另一个 App 的 Activity」**
 * > —— HyperOS 会拦截，**静默回退成打开小组件自己的 App**。
 *
 * **关键在于「另一个 App 的」**：它要跳系统日历，被拦后才退化成打开自己。
 * 而**我们的目标本来就是自己的 App** —— 那个「回退」正是我们想要的结果。
 * 所以这条限制不该套到我们头上，广播中转属于过度设计（多一个投递环节 = 多一个失败点）。
 *
 * ## 真机实测（小米 / 澎湃 OS，卡片为当前版本）
 *
 * | 路径 | 结果 |
 * |---|---|
 * | `getBroadcast` → Receiver → `startActivity` | 点击能送达，但最终拉起**不稳定** |
 * | **`getActivity` 单跳**（本实现） | **能拉起**（自检「被小组件拉起」≥ 1） |
 *
 * ## Intent 形态：与桌面图标启动完全同形
 *
 * `Intent.makeMainActivity` 给出 `ACTION_MAIN` + `CATEGORY_LAUNCHER` + 显式 component。
 *
 * ⚠️ **必须显式补 `FLAG_ACTIVITY_NEW_TASK`**：`Intent.makeMainActivity()` **不自带**它。
 * （logcat 里 `flg=0x10200000` 带 NEW_TASK，那是 **AMS 在 PendingIntent 路径上自动补的**，
 * 不是 `makeMainActivity` 给的 —— 别被它误导。）
 * 再补 launcher 也会加的 `RESET_TASK_IF_NEEDED`；**刻意不加 `CLEAR_TOP`**
 * —— launcher 不加，加了会清掉用户压在栈上的页面。
 *
 * ## data 必须逐点击目标唯一
 *
 * `PendingIntent` 去重依据是 `Intent.filterEquals`，它**忽略 extras**。
 * 若只靠 extras 区分不同药的行，几行会被判成同一个 PendingIntent，
 * `FLAG_UPDATE_CURRENT` 让最后一个覆盖全部 → 表现是**点哪行都开同一味药**。
 * 故写入带 action + drugId 的 data URI。
 */
@Composable
fun widgetClickAction(
    action: String,
    drugId: String? = null,
    drugName: String? = null,
): Action {
    val context = LocalContext.current
    val intent = Intent.makeMainActivity(
        ComponentName(context, MainActivity::class.java),
    ).apply {
        addFlags(
            Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED,
        )
        data = Uri.parse("transprism://widget/$action/${drugId ?: "-"}")
        putExtra(MedsWidgetActions.EXTRA_ACTION, action)
        putExtra(MedsWidgetActions.EXTRA_DRUG_ID, drugId)
        putExtra(MedsWidgetActions.EXTRA_DRUG_NAME, drugName)
    }
    // StartActivityIntentAction 是 Glance 的公开类，getStartActivityIntent 对它
    // 直接 `return action.intent` —— 这是 Glance 唯一支持的「自带 Intent」入口
    // （`when` 的 else 分支会抛异常，不能自己实现 StartActivityAction）。
    return StartActivityIntentAction(
        intent,
        MedsWidgetActions.params(action, drugId, drugName),
        null,
    )
}
