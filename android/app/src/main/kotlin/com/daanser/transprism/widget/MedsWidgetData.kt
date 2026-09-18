package com.daanser.transprism.widget

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import kotlin.math.max
import kotlin.math.roundToInt

// =============================================================================
// 展示模型 —— 字段名与定稿预览一一对应
// =============================================================================

/** 时间语义：逾期（粉强调）/ 未逾期（青） */
enum class MedsTimeState { OVERDUE, REMAINING }

/** 库存语义：告急（琥珀）/ 正常 */
enum class MedsStockState { CRITICAL, OK }

/** 进度条颜色：琥珀=库存告急，粉=逾期，青=未逾期 */
enum class MedsBarColor { AMBER, PINK, CYAN }

data class MedsWidgetItem(
    val name: String,
    /** 药名正下方，字号小于药名：「库存不足 1 次」/「剩 4 次」 */
    val stockText: String,
    /** 右对齐同一竖线，tabular-nums：「已超 9 小时」/「1天20小时」 */
    val timeText: String,
    val timeState: MedsTimeState,
    val stockState: MedsStockState,
    val barColor: MedsBarColor,
    /** 0f..1f，**不拉满**：库存不足给短琥珀条 */
    val barWidthFraction: Float,
)

data class MedsWidgetWeek(
    /** 7 个点，索引 0 = 6 天前，索引 6 = 今天 */
    val days: List<Boolean>,
    /** 「5/7」 */
    val countText: String,
) {
    /** 「近 7 天」 */
    val label: String = "近 7 天"
}

/** 小卡聚焦的单条药 */
data class MedsSmallFocus(
    /** 药物 id —— 打卡 / 库存深链的真实目标 */
    val drugId: String,
    val name: String,
    /** 「已超」 */
    val stateText: String,
    /** 「9」—— 主视觉大字 */
    val numberText: String,
    /** 「小时」—— 跟在数字旁的小字 */
    val unitText: String,
    /** 逾期 → 状态点粉；未逾期 → 青 */
    val isOverdue: Boolean,
)

data class MedsWidgetData(
    /** 「今日 1/4」 */
    val headerText: String,
    val items: List<MedsWidgetItem>,
    val week: MedsWidgetWeek,
    val small: MedsSmallFocus?,
)

// =============================================================================
// 数据来源 —— Flutter shared_preferences 的同一份 XML，只读，不写
// =============================================================================

/**
 * 从 Flutter 侧 `SharedPreferences`（文件名 `FlutterSharedPreferences`，
 * 键前缀 `flutter.`）读取用药数据。
 *
 * ⚠️ **只读**。打卡/扣库存/排通知仍全部走 Dart 侧
 *    `MedicationService.executeMedicationDose()`，本类不复制任何业务写入逻辑，
 *    因此不存在双写口子。
 *
 * 复用的既有存储键（见 REPO_MAP「数据持久化总览」）：
 *  - `drug_inventory_list`  → List<Drug>
 *  - `medication_logs`      → List<MedicationLog>
 */
object MedsWidgetDataLoader {

    private const val PREFS_NAME = "FlutterSharedPreferences"
    private const val KEY_PREFIX = "flutter."
    private const val KEY_DRUGS = "drug_inventory_list"
    private const val KEY_LOGS = "medication_logs"

    /** 中卡最多展示三行（与定稿预览一致） */
    private const val MEDIUM_ROWS = 3

    /** 库存告急阈值：剩余次数 ≤ 该值即判 CRITICAL */
    private const val CRITICAL_DOSES = 2

    /** 库存条基准：剩余 30 次视为「充足」，条宽封顶 0.78，永不拉满 */
    private const val BAR_BASE_DOSES = 30f
    private const val BAR_MIN = 0.28f
    private const val BAR_MAX = 0.78f
    /** 库存告急的短琥珀条（定稿：约 22%，不要拉满整行） */
    private const val BAR_CRITICAL = 0.22f

    fun load(context: Context): MedsWidgetData {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val drugs = parseDrugs(prefs.getString(KEY_PREFIX + KEY_DRUGS, null))
        val logs = parseLogs(prefs.getString(KEY_PREFIX + KEY_LOGS, null))
        return build(drugs, logs)
    }

    // ─────────────────────────── 解析 ───────────────────────────

    private data class RawDrug(
        val id: String,
        val name: String,
        val currentStock: Double,
        val dosage: Double,
        val intervalHours: Double,
        val dailyTimes: List<String>,
        val nextDoseTime: LocalDateTime?,
        val reminderEnabled: Boolean,
    )

    private data class RawLog(val medicationId: String, val timestamp: LocalDateTime)

    private fun parseDrugs(json: String?): List<RawDrug> {
        if (json.isNullOrBlank()) return emptyList()
        return try {
            val arr = JSONArray(json)
            (0 until arr.length()).mapNotNull { i ->
                val o = arr.optJSONObject(i) ?: return@mapNotNull null
                val unit = o.optString("intervalUnit", "hours")
                val value = o.optDouble("intervalValue", 0.0)
                val times = o.optJSONArray("dailyReminderTimes").toStringList()
                RawDrug(
                    id = o.optString("id"),
                    name = o.optString("name"),
                    currentStock = o.optDouble("currentStock", 0.0),
                    dosage = o.optDouble("dosage", 0.0),
                    intervalHours = intervalHoursOf(unit, value),
                    dailyTimes = times,
                    nextDoseTime = parseLocalDateTime(o.optString("nextDoseTime", "")),
                    reminderEnabled = o.optBoolean("reminderEnabled", true),
                )
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    private fun parseLogs(json: String?): List<RawLog> {
        if (json.isNullOrBlank()) return emptyList()
        return try {
            val arr = JSONArray(json)
            (0 until arr.length()).mapNotNull { i ->
                val o = arr.optJSONObject(i) ?: return@mapNotNull null
                val ts = parseLocalDateTime(o.optString("timestamp", ""))
                    ?: return@mapNotNull null
                RawLog(o.optString("medicationId"), ts)
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    private fun JSONArray?.toStringList(): List<String> {
        if (this == null) return emptyList()
        return (0 until length()).mapNotNull { optString(it, "").takeIf { s -> s.isNotBlank() } }
    }

    private fun intervalHoursOf(unit: String, value: Double): Double = when (unit) {
        "hours" -> value
        "days" -> value * 24
        "weeks" -> value * 24 * 7
        "months" -> value * 24 * 30
        else -> value
    }

    /** Flutter `DateTime.toIso8601String()` 兼容解析（带 Z / 不带 Z / 带毫秒） */
    private fun parseLocalDateTime(raw: String?): LocalDateTime? {
        if (raw.isNullOrBlank()) return null
        return try {
            if (raw.endsWith("Z")) {
                Instant.parse(raw).atZone(ZoneId.systemDefault()).toLocalDateTime()
            } else {
                LocalDateTime.parse(raw)
            }
        } catch (e: Exception) {
            null
        }
    }

    // ─────────────────────────── 组装 ───────────────────────────

    private fun build(drugs: List<RawDrug>, logs: List<RawLog>): MedsWidgetData {
        val now = LocalDateTime.now()
        val today = LocalDate.now()

        // 每味药算出「逾期 / 剩余」时长
        data class Computed(val drug: RawDrug, val minutes: Long, val overdue: Boolean)

        val computed = drugs
            .filter { it.reminderEnabled }
            .mapNotNull { d ->
                val next = d.nextDoseTime ?: return@mapNotNull null
                val minutes = java.time.Duration.between(now, next).toMinutes()
                Computed(d, minutes, minutes < 0)
            }
            // 逾期最久的排最前 —— 中卡第一行就是最该处理的那条
            .sortedWith(compareByDescending<Computed> { it.overdue }.thenBy { it.minutes })

        val items = computed.take(MEDIUM_ROWS).map { c ->
            val remaining = remainingDoses(c.drug)
            val critical = remaining <= CRITICAL_DOSES
            MedsWidgetItem(
                name = c.drug.name,
                stockText = if (critical) "库存不足 $remaining 次" else "剩 $remaining 次",
                timeText = timeTextOf(c.minutes, c.overdue),
                timeState = if (c.overdue) MedsTimeState.OVERDUE else MedsTimeState.REMAINING,
                stockState = if (critical) MedsStockState.CRITICAL else MedsStockState.OK,
                barColor = when {
                    critical -> MedsBarColor.AMBER
                    c.overdue -> MedsBarColor.PINK
                    else -> MedsBarColor.CYAN
                },
                barWidthFraction = if (critical) {
                    BAR_CRITICAL
                } else {
                    (remaining / BAR_BASE_DOSES).coerceIn(BAR_MIN, BAR_MAX)
                },
            )
        }

        // 近 7 天：索引 0 = 6 天前 … 索引 6 = 今天
        val loggedDays = logs.map { it.timestamp.toLocalDate() }.toSet()
        val days = (6 downTo 0).map { offset -> today.minusDays(offset.toLong()) in loggedDays }
        val done = days.count { it }

        // 小卡聚焦：逾期最久的那条；全部未逾期则取最近待服药的那条
        val focus = computed.firstOrNull()
        val small = focus?.let { c ->
            val overdueHours = if (c.overdue) (-c.minutes / 60) else 0
            MedsSmallFocus(
                drugId = c.drug.id,
                name = c.drug.name,
                stateText = if (c.overdue) "已超" else "待服",
                numberText = if (c.overdue) overdueHours.toString() else hoursOf(c.minutes).toString(),
                unitText = "小时",
                isOverdue = c.overdue,
            )
        }

        return MedsWidgetData(
            headerText = todayProgressText(drugs, logs, today),
            items = items,
            week = MedsWidgetWeek(days = days, countText = "$done/7"),
            small = small,
        )
    }

    /** 剩余可用次数（库存 / 单次剂量） */
    private fun remainingDoses(d: RawDrug): Int {
        if (d.dosage <= 0.0) return 0
        return max(0, (d.currentStock / d.dosage).toInt())
    }

    /**
     * 时间文案：
     *  - 逾期  → 「已超 9 小时」（带空格，粉）
     *  - 未逾期 → 「1天20小时」（无空格，青）；不足一天则「3 小时」
     */
    private fun timeTextOf(minutes: Long, overdue: Boolean): String {
        val abs = kotlin.math.abs(minutes)
        val hours = abs / 60
        return if (overdue) {
            "已超 $hours 小时"
        } else {
            if (hours >= 24) "${hours / 24}天${hours % 24}小时" else "$hours 小时"
        }
    }

    private fun hoursOf(minutes: Long): Long = kotlin.math.abs(minutes) / 60

    /** 今日已打卡条数 */
    private fun todayDone(drugs: List<RawDrug>, logs: List<RawLog>, today: LocalDate): Int {
        val ids = drugs.map { it.id }.toSet()
        return logs.count { it.timestamp.toLocalDate() == today && it.medicationId in ids }
    }

    /**
     * 今日应打卡次数：离散模式按固定时刻数量，间隔模式按 24h / 间隔（至少 1 次）。
     *
     * 口径说明：预览的「1/4」由真实数据推导，若产品口径不同（例如按药物去重计数），
     * 只需改这一个函数。
     */
    private fun todayPlanned(drugs: List<RawDrug>): Int {
        val enabled = drugs.filter { it.reminderEnabled }
        if (enabled.isEmpty()) return 0
        return enabled.sumOf { d ->
            if (d.dailyTimes.isNotEmpty()) {
                d.dailyTimes.size
            } else {
                if (d.intervalHours <= 0) 1 else max(1, (24.0 / d.intervalHours).roundToInt())
            }
        }
    }

    /**
     * 「今日 x/y」—— 分子按分母封顶。
     *
     * 用户补打卡时今日记录数可能超过计划数（例如计划 4 次却打了 6 次），
     * 直接显示 `6/4` 会像缺陷；header 语义是「今日进度」，故封顶到 y。
     */
    private fun todayProgressText(
        drugs: List<RawDrug>,
        logs: List<RawLog>,
        today: LocalDate,
    ): String {
        val planned = todayPlanned(drugs)
        if (planned <= 0) return "今日 0/0"
        val done = todayDone(drugs, logs, today).coerceAtMost(planned)
        return "今日 $done/$planned"
    }

    // ─────────────────────────── 预览用假数据 ───────────────────────────

    /**
     * 完全对齐定稿预览的假数据，供 Glance preview / @Preview 使用。
     * 文案逐字取自预览：今日 1/4、已超 9 小时、库存不足 1 次、剩 4 次、1天20小时、5/7。
     */
    fun preview(): MedsWidgetData = MedsWidgetData(
        headerText = "今日 1/4",
        items = listOf(
            MedsWidgetItem(
                name = "黄体酮注射液",
                stockText = "库存不足 1 次",
                timeText = "已超 9 小时",
                timeState = MedsTimeState.OVERDUE,
                stockState = MedsStockState.CRITICAL,
                barColor = MedsBarColor.AMBER,
                barWidthFraction = 0.22f,
            ),
            MedsWidgetItem(
                name = "戊酸雌二醇",
                stockText = "剩 4 次",
                timeText = "已超 3 小时",
                timeState = MedsTimeState.OVERDUE,
                stockState = MedsStockState.OK,
                barColor = MedsBarColor.PINK,
                barWidthFraction = 0.52f,
            ),
            MedsWidgetItem(
                name = "螺内酯",
                stockText = "剩 21 次",
                timeText = "1天20小时",
                timeState = MedsTimeState.REMAINING,
                stockState = MedsStockState.OK,
                barColor = MedsBarColor.CYAN,
                barWidthFraction = 0.68f,
            ),
        ),
        week = MedsWidgetWeek(
            days = listOf(false, true, true, false, true, true, true),
            countText = "5/7",
        ),
        small = MedsSmallFocus(
            drugId = "preview-drug-1",
            name = "黄体酮注射液",
            stateText = "已超",
            numberText = "9",
            unitText = "小时",
            isOverdue = true,
        ),
    )
}
