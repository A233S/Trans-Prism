package com.daanser.transprism.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.action.actionStartActivity
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
import androidx.glance.text.TextStyle
import com.daanser.transprism.MainActivity

/**
 * 小尺寸（2x2）单药小组件。
 *
 * 信息架构 1:1 对齐定稿预览：
 * ```
 * ● 针 黄体酮注射液
 * 已超
 *    9      小时
 * [ 记一次 ] [库存告急]
 * ```
 *
 * 关键：**不是一张空海报** —— 药名贴顶、「已超」紧贴药名下、
 * 「9」以 `defaultWeight()` 吃掉中部剩余空间后居中偏上、两个按钮贴底 1:1 分栏。
 */
class SmallMedsWidget : GlanceAppWidget() {

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val data = MedsWidgetDataLoader.load(context)
        provideContent { SmallMedsContent(data.small) }
    }
}

@Composable
private fun SmallMedsContent(focus: MedsSmallFocus?) {
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
        if (focus != null) {
            Column(
                modifier = GlanceModifier
                    .fillMaxSize()
                    .padding(
                        start = MedsDims.smallPaddingH,
                        top = MedsDims.smallPaddingTop,
                        end = MedsDims.smallPaddingH,
                        bottom = MedsDims.smallPaddingBottom,
                    ),
            ) {
                // ── 药名贴顶：针筒 + 药名 + 状态点 ──
                Row(
                    modifier = GlanceModifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    MedIcon(size = MedsDims.iconSizeSmall)
                    Spacer(GlanceModifier.width(5.dp))
                    Text(
                        text = focus.name,
                        modifier = GlanceModifier.defaultWeight(),
                        style = TextStyle(
                            color = MedsTokens.title,
                            fontSize = MedsDims.fsSmallName,
                            fontWeight = FontWeight.Medium,
                        ),
                        maxLines = 1,
                    )
                    StatusDot(
                        if (focus.isOverdue) MedsTimeState.OVERDUE else MedsTimeState.REMAINING
                    )
                }

                Spacer(GlanceModifier.height(8.dp))

                // ── 「已超」紧贴药名下方，小字 ──
                Text(
                    text = focus.stateText,
                    style = TextStyle(
                        color = MedsTokens.muted,
                        fontSize = MedsDims.fsSmallState,
                        fontWeight = FontWeight.Medium,
                    ),
                    maxLines = 1,
                )

                // ── 主视觉：「9」巨大居中偏上，「小时」跟在数字旁 ──
                Box(
                    modifier = GlanceModifier
                        .fillMaxWidth()
                        .defaultWeight(),
                    contentAlignment = Alignment.Center,
                ) {
                    Row(verticalAlignment = Alignment.Bottom) {
                        Text(
                            text = focus.numberText,
                            style = TextStyle(
                                color = MedsTokens.pink,
                                fontSize = MedsDims.fsSmallNum,
                                fontWeight = FontWeight.Bold,
                            ),
                            maxLines = 1,
                        )
                        Spacer(GlanceModifier.width(5.dp))
                        Text(
                            text = focus.unitText,
                            style = TextStyle(
                                color = MedsTokens.muted,
                                fontSize = MedsDims.fsSmallUnit,
                                fontWeight = FontWeight.Medium,
                            ),
                            maxLines = 1,
                        )
                    }
                }

                // ── 按钮贴底：实心粉 + 琥珀描边，1:1 分栏 ──
                Row(
                    modifier = GlanceModifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    SolidButton(
                        text = "记一次",
                        action = actionStartActivity<MainActivity>(
                            MedsWidgetActions.params(
                                action = MedsWidgetActions.ACTION_RECORD_DOSE,
                                drugId = focus.drugId,
                                drugName = focus.name,
                            )
                        ),
                        modifier = GlanceModifier.defaultWeight(),
                    )
                    Spacer(GlanceModifier.width(MedsDims.smallBtnGap))
                    StrokeButton(
                        text = "库存告急",
                        action = actionStartActivity<MainActivity>(
                            MedsWidgetActions.params(
                                action = MedsWidgetActions.ACTION_STOCK_ALERT,
                                drugId = focus.drugId,
                                drugName = focus.name,
                            )
                        ),
                        modifier = GlanceModifier.defaultWeight(),
                    )
                }
            }
        }
    }
}
