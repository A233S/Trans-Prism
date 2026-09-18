package com.daanser.transprism.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.LinearProgressIndicator
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
import androidx.glance.text.TextStyle
import com.daanser.transprism.MainActivity

/**
 * 中尺寸（4x2 / 4x3）用药列表小组件。
 *
 * 信息架构 1:1 对齐定稿预览：
 * ```
 * 今日 1/4                    [记一次]
 * ● 针 黄体酮注射液            已超 9 小时
 * 库存不足 1 次
 * ──琥珀短条──
 * ● 针 戊酸雌二醇              已超 3 小时
 * 剩 4 次
 * ──粉条──
 * ● 针 螺内酯                  1天20小时（青）
 * 剩 21 次
 * ──淡粉/青──
 * 近 7 天  ○ ● ● ○ ● ● ●   5/7
 * ```
 */
class MediumMedsWidget : GlanceAppWidget() {

    override val sizeMode: SizeMode = MEDS_WIDGET_SIZE_MODE

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val data = MedsWidgetDataLoader.load(context)
        provideContent { MediumMedsContent(data) }
    }

    /**
     * 设计预览 / Android Studio Preview 通道：用定稿假数据渲染，
     * 不触碰真实存储 —— 深浅色两套均由 token 自动切换。
     */
    override suspend fun providePreview(context: Context, appWidgetCategory: Int) {
        provideContent { MediumMedsContent(MedsWidgetDataLoader.preview()) }
    }
}

@Composable
private fun MediumMedsContent(data: MedsWidgetData) {
    Box(
        modifier = GlanceModifier
            .fillMaxSize()
            .background(MedsTokens.card)
            .cornerRadius(MedsDims.cardRadius)
            // 点击整卡（非按钮）→ 今日用药页
            .clickable(
                actionStartActivity<MainActivity>(
                    MedsWidgetActions.params(MedsWidgetActions.ACTION_OPEN_MEDS)
                )
            ),
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
            MediumHeader(data.headerText)
            Spacer(GlanceModifier.height(8.dp))
            data.items.forEach { item ->
                MediumRow(item)
                // 每行后均分剩余高度：4x3 下三行舒展铺满卡片，
                // 高度不足时该 Spacer 收缩为 0，不会把底栏顶出可视区。
                Spacer(GlanceModifier.defaultWeight())
            }
            MediumWeekRow(data.week)
        }
    }
}

/** 顶栏：「今日 1/4」+ 小号实心粉胶囊「记一次」 */
@Composable
private fun MediumHeader(headerText: String) {
    Row(
        modifier = GlanceModifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = headerText,
            modifier = GlanceModifier.defaultWeight(),
            style = TextStyle(
                color = MedsTokens.title,
                fontSize = MedsDims.fsMediumTitle,
                fontWeight = FontWeight.Medium,
            ),
            maxLines = 1,
        )
        SolidPillButton(
            text = "记一次",
            action = actionStartActivity<MainActivity>(
                MedsWidgetActions.params(MedsWidgetActions.ACTION_RECORD_DOSE)
            ),
        )
    }
}

/**
 * 单行药：`[针 点] 药名 / 库存 …… 时间`
 *
 * 时间列靠 `defaultWeight()` 把药名列撑开而自然**右对齐到同一竖线**；
 * 库存文案在药名正下方、字号更小（13sp → 10.5sp）。
 */
@Composable
private fun MediumRow(item: MedsWidgetItem) {
    Column(modifier = GlanceModifier.fillMaxWidth()) {
        Row(
            modifier = GlanceModifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // col1：针筒 + 状态点
            Row(
                modifier = GlanceModifier.width(MedsDims.iconBoxWidth),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                MedIcon()
                Spacer(GlanceModifier.width(1.dp))
                StatusDot(item.timeState)
            }
            Spacer(GlanceModifier.width(MedsDims.iconGap))

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
                style = TextStyle(
                    color = MedsTokens.timeText(item.timeState),
                    fontSize = MedsDims.fsTime,
                    fontWeight = FontWeight.Medium,
                ),
                maxLines = 1,
            )
        }

        Spacer(GlanceModifier.height(2.dp))

        // 进度条：2px，左缩进与药名左边缘对齐。
        // 按比例填充只能靠 LinearProgressIndicator —— Glance 1.2.0 无 fillMaxWidth(fraction)。
        Row(
            modifier = GlanceModifier
                .fillMaxWidth()
                .padding(
                    start = MedsDims.barInset,
                    top = 0.dp,
                    end = 0.dp,
                    bottom = 0.dp,
                ),
        ) {
            LinearProgressIndicator(
                progress = item.barWidthFraction,
                modifier = GlanceModifier
                    .fillMaxWidth()
                    .height(MedsDims.barHeight),
                color = MedsTokens.barFill(item.barColor),
                backgroundColor = MedsTokens.track,
            )
        }

        Spacer(GlanceModifier.height(4.dp))
    }
}

/** 底栏：细分割线 + 「近 7 天」+ 7 个圆点 + 「5/7」 */
@Composable
private fun MediumWeekRow(week: MedsWidgetWeek) {
    Column(modifier = GlanceModifier.fillMaxWidth()) {
        Spacer(GlanceModifier.height(8.dp))
        Box(
            modifier = GlanceModifier
                .fillMaxWidth()
                .height(MedsDims.hairlineHeight)
                .background(MedsTokens.hairline),
        ) {}
        Spacer(GlanceModifier.height(8.dp))

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

            Row(
                modifier = GlanceModifier.defaultWeight(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                week.days.forEachIndexed { index, done ->
                    if (index > 0) Spacer(GlanceModifier.width(MedsDims.weekDotGap))
                    WeekDot(done)
                }
            }

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
