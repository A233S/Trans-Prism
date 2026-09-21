package com.daanser.transprism.widget

import android.content.Context
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import kotlin.math.abs
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

/** 2×2 预览矩阵的四个状态：待服/已超 × 缺货/库存足 */
enum class SmallPreviewState {
    WAITING_IN_STOCK,
    WAITING_CRITICAL,
    OVERDUE_IN_STOCK,
    OVERDUE_CRITICAL,
}

data class MedsWidgetItem(
    /**
     * 药物 id —— **整行点击记的就是这一条**（v2 起每行独立可点）。
     * 旧版中卡整卡只有一个通用「记一次」，用户无法判断写入哪条。
     */
    val drugId: String,
    val name: String,
    /** 药名正下方，字号小于药名：「库存不足 1 次」/「剩 4 次」 */
    val stockText: String,
    /** 右对齐同一竖线，固定宽 + TextAlign.End：「已超 9 小时」/「1天20小时」 */
    val timeText: String,
    val timeState: MedsTimeState,
    val stockState: MedsStockState,
    val barColor: MedsBarColor,
    /** 0f..1f，**不拉满**：库存不足给短琥珀条 */
    val barWidthFraction: Float,
    /**
     * 是否为「下一剂」—— **整个小组件里唯一的默认写入目标**。
     * 排序：已超最久 → 待服剩余最短（见 [MedsWidgetDataLoader] 的 `computed` 排序）。
     * 该行左侧画粉/青竖条 + 浅底高亮，右上按钮也指向同一条药。
     */
    val isNext: Boolean,
)

data class MedsWidgetWeek(
    /** 7 个点，索引 0 = 6 天前，索引 6 = 今天。**恒为 7 个**，与右侧 `n/7` 对得上。 */
    val days: List<Boolean>,
    /** 「5/7」 */
    val countText: String,
) {
    /** 「近 7 天」 */
    val label: String = "近 7 天"
}

/** 小卡聚焦的单条药 —— **只展示「下一剂」那一条**（与 3×4 高亮行同一条） */
data class MedsSmallFocus(
    /** 药物 id —— 打卡的真实目标 */
    val drugId: String,
    val name: String,
    /** 「待服」/「已超」—— 环下小标签 */
    val stateText: String,
    /** 「9」—— 环心主数字 */
    val numberText: String,
    /** 「小时」/「分钟」—— 主数字下方小字 */
    val unitText: String,
    /** 逾期 → 环与数字用粉；未逾期 → 用青 */
    val isOverdue: Boolean,
    /** 库存告急 → 药名旁加一行琥珀小字「库存不足」（**不**做第二个按钮） */
    val isCritical: Boolean,
    /**
     * 环形进度 0f..1f。
     * 口径 = **距离下次剂量的时间进度**（已超恒为 1f），
     * 详见 [MedsRingRenderer] 类注释 —— 这是写进注释的唯一口径，不要换成「今日完成度」。
     */
    val progress: Float,
)

data class MedsWidgetData(
    /** 「今日 1/4」 */
    val headerText: String,
    /**
     * 中卡三行（最多 3 条）。**第 0 条（`isNext == true`）就是「下一剂」**，
     * 也是右上按钮「记 {药名}」指向的那一条 —— 两者同源，不会各说各话。
     */
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

    private const val TAG = "TP-Widget"
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

    /** 兜底给药间隔：拿不到 interval / dailyTimes 时按 24h 算环进度 */
    private const val FALLBACK_INTERVAL_MINUTES = 24.0 * 60.0

    fun load(context: Context): MedsWidgetData {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val drugs = parseDrugs(prefs.getString(KEY_PREFIX + KEY_DRUGS, null))
        val logs = parseLogs(prefs.getString(KEY_PREFIX + KEY_LOGS, null))
        val data = build(drugs, logs)
        // 排查「卡片没跟上数据」时看这一行：它能直接区分
        // ① 小组件读到的是旧快照，还是 ② 数据是新的但没推给 Launcher
        Log.d(
            TAG,
            "load: ${drugs.size} 药 / ${logs.size} 日志 → ${data.headerText} | " +
                data.items.joinToString { "${it.name}·${it.timeText}" },
        )
        return data
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

    /** 单味药算出的「距下次剂量还有多少分钟」+ 是否已超 */
    private data class Computed(val drug: RawDrug, val minutes: Long, val overdue: Boolean)

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
        val computed = drugs
            .filter { it.reminderEnabled }
            .mapNotNull { d ->
                val next = d.nextDoseTime ?: return@mapNotNull null
                val minutes = java.time.Duration.between(now, next).toMinutes()
                Computed(d, minutes, minutes < 0)
            }
            // 逾期最久的排最前 —— 中卡第一行、小卡那一条都是「最该处理的那条」
            .sortedWith(compareByDescending<Computed> { it.overdue }.thenBy { it.minutes })

        val items = computed.take(MEDIUM_ROWS).mapIndexed { index, c ->
            val remaining = remainingDoses(c.drug)
            val critical = remaining <= CRITICAL_DOSES
            MedsWidgetItem(
                drugId = c.drug.id,
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
                // 第 0 行 = 下一剂 = 唯一默认写入目标（高亮行）
                isNext = index == 0,
            )
        }

        // 近 7 天：索引 0 = 6 天前 … 索引 6 = 今天，**恒 7 个点**
        val loggedDays = logs.map { it.timestamp.toLocalDate() }.toSet()
        val days = (6 downTo 0).map { offset -> today.minusDays(offset.toLong()) in loggedDays }
        val done = days.count { it }

        // 小卡聚焦：与中卡第 0 行**同一条**（逾期最久；全部未逾期则取最近待服）
        val focus = computed.firstOrNull()
        val small = focus?.let { c ->
            val overdue = c.overdue
            val minutes = abs(c.minutes)
            val critical = remainingDoses(c.drug) <= CRITICAL_DOSES
            MedsSmallFocus(
                drugId = c.drug.id,
                name = c.drug.name,
                stateText = if (overdue) "已超" else "待服",
                numberText = if (minutes >= 60) (minutes / 60).toString() else minutes.toString(),
                unitText = if (minutes >= 60) "小时" else "分钟",
                isOverdue = overdue,
                isCritical = critical,
                progress = ringProgress(c),
            )
        }

        return MedsWidgetData(
            headerText = todayProgressText(drugs, logs, today),
            items = items,
            week = MedsWidgetWeek(days = days, countText = "$done/7"),
            small = small,
        )
    }

    /**
     * 环形进度口径 = **距离下次剂量的时间进度**（唯一口径，见 [MedsRingRenderer]）：
     *
     *     progress = 1 − 剩余分钟 / 给药间隔分钟
     *
     * 已超时恒为 1f（整圈）。
     */
    private fun ringProgress(c: Computed): Float {
        if (c.overdue) return 1f
        val interval = intervalMinutesOf(c.drug)
        if (interval <= 0.0) return 0f
        val elapsed = interval - c.minutes.toDouble()
        return (elapsed / interval).coerceIn(0.0, 1.0).toFloat()
    }

    /** 给药间隔（分钟）：离散时刻模式按 24h/时刻数，否则用 intervalValue 折算 */
    private fun intervalMinutesOf(d: RawDrug): Double = when {
        d.dailyTimes.isNotEmpty() -> FALLBACK_INTERVAL_MINUTES / d.dailyTimes.size
        d.intervalHours > 0 -> d.intervalHours * 60.0
        else -> FALLBACK_INTERVAL_MINUTES
    }

    /** 剩余可用次数（库存 / 单次剂量） */
    private fun remainingDoses(d: RawDrug): Int {
        if (d.dosage <= 0.0) return 0
        return max(0, (d.currentStock / d.dosage).toInt())
    }

    /**
     * 时间文案：
     *  - 逾期  → 「已超 9 小时」（带空格，粉）/ 不足 1 小时 → 「已超 20 分钟」
     *  - 未逾期 → 「1天20小时」（无空格，青）；不足一天则「3 小时」/「20 分钟」
     */
    private fun timeTextOf(minutes: Long, overdue: Boolean): String {
        val absMinutes = abs(minutes)
        if (absMinutes < 60) return if (overdue) "已超 $absMinutes 分钟" else "$absMinutes 分钟"
        val hours = absMinutes / 60
        return if (overdue) {
            "已超 $hours 小时"
        } else {
            if (hours >= 24) "${hours / 24}天${hours % 24}小时" else "$hours 小时"
        }
    }

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
     * 中卡预览数据：**一张卡同时覆盖三种状态**，便于一眼验收配色。
     *
     * | 行 | 状态 | 高亮 | 库存 | 条色 |
     * |---|---|---|---|---|
     * | 1 | 已超 9 小时 | ✅ 下一剂（粉竖条 + 粉浅底） | 缺货 0 次 | 短琥珀 |
     * | 2 | 已超 3 小时 | — | 剩 4 次 | 粉 |
     * | 3 | 待服 1天20小时 | — | 剩 21 次 | 青 |
     *
     * 文案逐字取自定稿预览：今日 1/4、已超 9 小时、库存不足 0 次、剩 4 次、1天20小时、5/7。
     */
    fun previewMedium(): MedsWidgetData = MedsWidgetData(
        headerText = "今日 1/4",
        items = listOf(
            MedsWidgetItem(
                drugId = "preview-drug-progesterone",
                name = "黄体酮注射液",
                stockText = "库存不足 0 次",
                timeText = "已超 9 小时",
                timeState = MedsTimeState.OVERDUE,
                stockState = MedsStockState.CRITICAL,
                barColor = MedsBarColor.AMBER,
                barWidthFraction = 0.22f,
                isNext = true,
            ),
            MedsWidgetItem(
                drugId = "preview-drug-estradiol",
                name = "戊酸雌二醇",
                stockText = "剩 4 次",
                timeText = "已超 3 小时",
                timeState = MedsTimeState.OVERDUE,
                stockState = MedsStockState.OK,
                barColor = MedsBarColor.PINK,
                barWidthFraction = 0.52f,
                isNext = false,
            ),
            MedsWidgetItem(
                drugId = "preview-drug-spiro",
                name = "螺内酯",
                stockText = "剩 21 次",
                timeText = "1天20小时",
                timeState = MedsTimeState.REMAINING,
                stockState = MedsStockState.OK,
                barColor = MedsBarColor.CYAN,
                barWidthFraction = 0.68f,
                isNext = false,
            ),
        ),
        week = MedsWidgetWeek(
            days = listOf(false, true, true, false, true, true, true),
            countText = "5/7",
        ),
        small = previewSmall(SmallPreviewState.OVERDUE_CRITICAL),
    )

    /**
     * 小卡预览矩阵 —— **待服 / 已超 × 缺货 / 库存足** 四态。
     *
     * 浅色 / 深色两套由 [MedsWidgetThemePrefs] 决定（跟 App 主题偏好），
     * 所以「浅/深」不在这里出变体：在 App「我的 → 主题模式」切一下即可。
     *
     * 默认渲染哪一态见 `SmallMedsWidget.PREVIEW_SMALL_STATE`。
     */
    fun previewSmall(state: SmallPreviewState): MedsSmallFocus {
        val overdue = state == SmallPreviewState.OVERDUE_IN_STOCK ||
                state == SmallPreviewState.OVERDUE_CRITICAL
        val critical = state == SmallPreviewState.WAITING_CRITICAL ||
                state == SmallPreviewState.OVERDUE_CRITICAL
        return MedsSmallFocus(
            drugId = "preview-drug-progesterone",
            name = "黄体酮注射液",
            stateText = if (overdue) "已超" else "待服",
            numberText = if (overdue) "9" else "4",
            unitText = "小时",
            isOverdue = overdue,
            isCritical = critical,
            // 待服：走了 4/12 个间隔 → 0.33；已超：整圈
            progress = if (overdue) 1f else 0.33f,
        )
    }
}
