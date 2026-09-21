package com.daanser.transprism.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.action.Action
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextAlign
import androidx.glance.text.TextStyle

/**
 * 中尺寸（3×4）用药列表小组件 —— v3。
 *
 * 信息架构：
 * ```
 * 今日 4/4                          点对应药物服药      ← 右上：muted 小字说明，不是按钮
 * ┃ 针 ● 螺内酯                            1 小时        ← 下一剂：3.5dp 青/粉竖条 + 极轻提亮
 * ┃      剩 11 次
 * ┃      ──────────
 *
 *   针 ● 戊酸雌二醇                      6天23小时
 *        剩 13 次
 *        ──────
 *
 *   针 ● 黄体酮注射液                   13天23小时
 *        库存不足 0 次
 *        ──
 * ─────────────────────────────────────────────────
 * 近 7 天  ● ○ ● ● ● ● ●                      6/7
 * ```
 *
 * ── v3 核心：**小组件不再打卡** ─────────────────────────────────
 * v2 点行 / 点右上胶囊会**直接打卡扣库存**，无确认、极易误触。
 * v3 起：
 * - **点任意一行** → 带该行 `drugId` 唤起 App，并拉起该药的「记录用药」Sheet
 *   （当前库存 / 本次剂量 / 下次计划 / 取消 / 确认服药）。**不在小组件里写任何数据。**
 * - 右上角那枚粉胶囊已删除（和「点行打开」重复，且看着就像会直接记），
 *   改成一句 muted 小字说明「点对应药物服药」。
 * - 取消 / 系统返回 → 什么都不发生。
 *
 * ── v3 视觉收敛 ────────────────────────────────────────────────
 * - 高亮行不再是整块深浅色大底（真机上像被选中的列表 item），
 *   改成 **3.5dp 状态色竖条 + 极轻中性提亮**（浅色 4% 黑 / 深色 8% 白）。
 * - 三行间距改为**固定 5dp**：v2 用「每行后均分富余」被撑到 ~22dp/行，太散。
 * - 进度条仍 2px；「近 7 天」恒 7 个点，与右侧 `n/7` 对齐。
 *
 * ⚠️ 竖条只表示「最近一剂」，**不是「只有这行能点」** —— 三行都可点，
 * 所以高亮做得越轻越好。
 */
class MediumMedsWidget : GlanceAppWidget() {

    override val sizeMode: SizeMode = MEDS_WIDGET_SIZE_MODE

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        // ⚠️⚠️ 数据与主题**必须在 `provideContent` 的组合 lambda 内读取**，不能提到外面。
        //
        // Glance 的会话是**长驻**的：`provideGlance` 只在会话创建时执行一次，
        // 之后每次 `update()` 只是**重组同一棵组合树**（不会再次进入 provideGlance）。
        // 若在这里先 `val data = load(context)` 再闭包捕获，重组时用的还是
        // 会话创建那一刻的旧数据 —— 卡片就会永远停在旧值。
        //
        // 真机实测（2026-09-19）：打卡后 `refreshAll: medium=1 small=1` 有日志，
        // 但 `provideGlance` 之后再没进入过，`load:` 也没有，卡片停在打卡前。
        // 而重装 APK（进程重启 → 新会话）后立刻显示正确 —— 正是这个原因。
        //
        // `load()` / `colorsFor()` 都是**同步**函数（读内存里的 SharedPreferences），
        // 放进组合里没有 suspend 问题。
        provideContent {
            // 自检：记录「卡片最近一次渲染时刻」—— 用来永久排除「桌面上是旧卡片」这个干扰
            MedsWidgetDiag.recordRender(context)
            val colors = MedsWidgetThemePrefs.colorsFor(context)
            val data = MedsWidgetDataLoader.load(context)
            MedsWidgetThemeProvider(colors) { MediumMedsContent(data) }
        }
    }

    /**
     * 设计预览 / Android Studio Preview 通道：用定稿假数据渲染，
     * 不触碰真实存储。
     *
     * 一张卡即覆盖三种状态（已超+缺货 / 已超+库存足 / 待服+库存足）；
     * 浅色 / 深色由 **App 主题偏好** 决定 —— 在「我的 → 主题模式」切换后
     * 重新打开预览即可看到另一套，这里不另出变体。
     */
    override suspend fun providePreview(context: Context, widgetCategory: Int) {
        val colors = MedsWidgetThemePrefs.colorsFor(context)
        provideContent {
            MedsWidgetThemeProvider(colors) {
                MediumMedsContent(MedsWidgetDataLoader.previewMedium())
            }
        }
    }
}

@Composable
private fun MediumMedsContent(data: MedsWidgetData) {
    Box(
        modifier = GlanceModifier
            .fillMaxSize()
            .background(MedsTokens.card)
            .cornerRadius(MedsDims.cardRadius)
            // 点击整卡空白处（非行）→ 今日用药页
            .clickable(widgetClickAction(MedsWidgetActions.ACTION_OPEN_MEDS)),
    ) {
        Column(
            modifier = GlanceModifier
                .fillMaxSize()
                .padding(
                    start = MedsDims.mediumPaddingH,
                    top = MedsDims.mediumPaddingTop,
                    end = MedsDims.mediumPaddingH,
                    bottom = MedsDims.mediumPaddingBottom,
                ),
        ) {
            MediumHeader(data)
            Spacer(GlanceModifier.height(8.dp))

            // 三行药：固定间距，整体在剩余空间里垂直居中。
            // Glance 1.2.0 的 Row/Column **最多 10 个子元素**，超了直接抛
            // IllegalArgumentException 导致整张卡渲染失败 —— 所以行块单独包一层。
            Box(
                modifier = GlanceModifier
                    .fillMaxWidth()
                    .defaultWeight(),
                contentAlignment = Alignment.Center,
            ) {
                Column(modifier = GlanceModifier.fillMaxWidth()) {
                    data.items.forEachIndexed { index, item ->
                        if (index > 0) Spacer(GlanceModifier.height(MedsDims.rowGap))
                        MediumRow(item)
                    }
                }
            }

            MediumWeekRow(data.week)
        }
    }
}

/**
 * 顶栏：「今日 4/4」靠左 + 一句 muted 说明靠右。
 *
 * ⚠️ 右上角**不是按钮**：v2 那枚「记 螺内酯」粉胶囊既和「点行打开」重复，
 * 又长得像「点一下就直接记」。v3 换成纯说明文字，无粉底、无描边、无点击。
 */
@Composable
private fun MediumHeader(data: MedsWidgetData) {
    Row(
        modifier = GlanceModifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = data.headerText,
            modifier = GlanceModifier.defaultWeight(),
            style = TextStyle(
                color = MedsTokens.title,
                fontSize = MedsDims.fsMediumTitle,
                fontWeight = FontWeight.Medium,
            ),
            maxLines = 1,
        )
        Text(
            text = "点对应药物服药",
            style = TextStyle(
                color = MedsTokens.muted,
                fontSize = MedsDims.fsHint,
                fontWeight = FontWeight.Normal,
                textAlign = TextAlign.End,
            ),
            maxLines = 1,
        )
    }
}

/**
 * 单行药：`┃ [针 ●] 药名 / 库存 …… 时间`
 *
 * - 「下一剂」行：左侧 3.5dp 状态色竖条（待服青 / 已超粉）+ 极轻中性提亮。
 * - **整行可点** → 打开这一行药物的「记录用药」Sheet（v3 起不直接打卡）。
 * - 时间列**固定宽 74dp + TextAlign.End**，三行数字右边缘落在同一竖线；
 *   Glance 的 `TextStyle` 不支持 `fontFeatureSettings`（无法真开 tabular-nums），
 *   固定宽右对齐是等效观感。
 */
@Composable
private fun MediumRow(item: MedsWidgetItem) {
    Column(
        modifier = GlanceModifier
            .fillMaxWidth()
            .background(
                if (item.isNext) {
                    MedsTokens.rowHighlight
                } else {
                    MedsTokens.transparent
                }
            )
            .cornerRadius(MedsDims.rowRadius)
            .padding(horizontal = MedsDims.rowPaddingH, vertical = MedsDims.rowPaddingV)
            .clickable(openRecordSheetAction(item.drugId, item.name)),
    ) {
        Row(
            modifier = GlanceModifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // col0：下一剂竖条（未高亮的行用等宽透明占位，保证三行左边缘对齐）
            if (item.isNext) {
                NextDoseBar(item.timeState)
            } else {
                Spacer(GlanceModifier.width(MedsDims.nextBarWidth))
            }
            Spacer(GlanceModifier.width(MedsDims.nextBarGap))

            MedIcon()
            Spacer(GlanceModifier.width(MedsDims.iconDotGap))
            StatusDot(item.timeState)
            Spacer(GlanceModifier.width(MedsDims.nextBarGap))

            // col2：药名 + 库存（库存字号小于药名）
            Column(modifier = GlanceModifier.defaultWeight()) {
                Text(
                    text = item.name,
                    style = TextStyle(
                        color = MedsTokens.title,
                        fontSize = MedsDims.fsMedName,
                        fontWeight = FontWeight.Medium,
                    ),
                    maxLines = 1,
                )
                Text(
                    text = item.stockText,
                    style = TextStyle(
                        color = MedsTokens.muted,
                        fontSize = MedsDims.fsStock,
                        fontWeight = FontWeight.Normal,
                    ),
                    maxLines = 1,
                )
            }

            // col3：时间（逾期粉 / 未逾期青；琥珀不用于时间）
            Text(
                text = item.timeText,
                modifier = GlanceModifier.width(MedsDims.timeColumnWidth),
                style = TextStyle(
                    color = MedsTokens.timeText(item.timeState),
                    fontSize = MedsDims.fsTime,
                    fontWeight = FontWeight.Medium,
                    textAlign = TextAlign.End,
                ),
                maxLines = 1,
            )
        }

        RowProgressBar(item)
    }
}

/**
 * 底栏：细分割线 + 「近 7 天」+ **恰好 7 个**圆点 + 「5/7」。
 *
 * ⚠️ 两个坑（都踩过，真机 logcat 实录）：
 * 1. **Glance 1.2.0 的 Row 最多 10 个子元素**，超了抛
 *    `IllegalArgumentException: Row container cannot have more than 10 elements`，
 *    整张卡渲染失败。所以 7 个点 + 6 个间隔必须**包在内层 Row 里**，
 *    且间隔做成每个点自带的 `padding(end)` —— 内层 7 个、外层 5 个，都安全。
 * 2. 圆点 Row **不能**给 `defaultWeight()`：宽度被压缩时点会被裁掉，
 *    真机上就出现「只有 5 个点、却写 5/7」的错位。让它保持自然宽度，
 *    用后面的 `Spacer(defaultWeight())` 去吞掉剩余空间。
 */
@Composable
private fun MediumWeekRow(week: MedsWidgetWeek) {
    Column(modifier = GlanceModifier.fillMaxWidth()) {
        Spacer(GlanceModifier.height(MedsDims.weekPadV))
        Box(
            modifier = GlanceModifier
                .fillMaxWidth()
                .height(MedsDims.hairlineHeight)
                .background(MedsTokens.hairline),
        ) {}
        Spacer(GlanceModifier.height(MedsDims.weekPadV))

        Row(
            modifier = GlanceModifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = week.label,
                style = TextStyle(
                    color = MedsTokens.muted,
                    fontSize = MedsDims.fsWeekLabel,
                    fontWeight = FontWeight.Medium,
                ),
                maxLines = 1,
            )
            Spacer(GlanceModifier.width(10.dp))

            Row(verticalAlignment = Alignment.CenterVertically) {
                week.days.forEach { done ->
                    // 间隔做进点自己的 padding，避免多出 6 个 Spacer 子元素
                    Box(modifier = GlanceModifier.padding(end = MedsDims.weekDotGap)) {
                        WeekDot(done)
                    }
                }
            }

            Spacer(GlanceModifier.defaultWeight())

            Text(
                text = week.countText,
                style = TextStyle(
                    color = MedsTokens.title,
                    fontSize = MedsDims.fsWeekCount,
                    fontWeight = FontWeight.Medium,
                ),
                maxLines = 1,
            )
        }
    }
}

/**
 * 「打开该药的记录用药 Sheet」的统一 action 构造 ——
 * 中卡的行点击、小卡的按钮与环点击**全部**经这里产出，保证契约一致。
 *
 * ⚠️ **v3 起它只负责「打开 Sheet」，不做任何写入。**
 * 真正的 `MedicationService.executeMedicationDose()` 只由
 * `RecordDoseDialog._confirmDose()`（用户点「确认服药」）触发。
 *
 * 点击走广播中转（见 [`widgetClickAction`] / [`MedsWidgetClickReceiver`]），
 * 以绕开 HyperOS 对「小组件 PendingIntent 直接启动 Activity」的拦截。
 */
@Composable
internal fun openRecordSheetAction(drugId: String, drugName: String): Action =
    widgetClickAction(
        action = MedsWidgetActions.ACTION_OPEN_RECORD_SHEET,
        drugId = drugId,
        drugName = drugName,
    )
