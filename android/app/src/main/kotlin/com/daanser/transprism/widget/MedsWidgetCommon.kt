package com.daanser.transprism.widget

import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.glance.ColorFilter
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.action.Action
import androidx.glance.action.clickable
import androidx.glance.appwidget.LinearProgressIndicator
import androidx.glance.appwidget.cornerRadius
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.daanser.transprism.R

/**
 * 中卡 / 小卡共用的原子组件。
 *
 * 实现约束（已对照 Glance 1.2.0 字节码核实）：
 *  - **没有 `border` modifier** → 空心点一律用「双层 Box + 圆角差」模拟。
 *  - **没有 `fillMaxWidth(fraction)`，`defaultWeight()` 也不接受权重参数**
 *    → 按比例填充只能交给 `LinearProgressIndicator(progress = ...)`。
 *  - **没有 Canvas / DrawScope** → 小卡的环形进度用预渲染位图
 *    （见 [MedsRingRenderer]），不是现场绘制的。
 */

/** 针筒小图标（描边色随 muted，深浅色自动切换） */
@Composable
fun MedIcon(size: Dp = MedsDims.iconSize) {
    Image(
        provider = ImageProvider(R.drawable.ic_syringe),
        contentDescription = null,
        modifier = GlanceModifier.size(size),
        colorFilter = ColorFilter.tint(MedsTokens.muted),
    )
}

/** 状态圆点：粉=逾期强调 / 青=未逾期（琥珀不用于状态点） */
@Composable
fun StatusDot(timeState: MedsTimeState) {
    Box(
        modifier = GlanceModifier
            .size(MedsDims.statusDot)
            .background(MedsTokens.statusDot(timeState))
            .cornerRadius(MedsDims.statusDot / 2),
    ) {}
}

/**
 * 「下一剂」行左侧的竖条（3dp 宽）。
 *
 * 用**固定高度**而不是 `fillMaxHeight()`：Glance 里 match_parent 高度在
 * wrap_content 的 Row 中行为不稳，固定 30dp 才能保证一定画得出来。
 * 颜色 = 状态色（待服青 / 已超粉）。
 */
@Composable
fun NextDoseBar(timeState: MedsTimeState) {
    Box(
        modifier = GlanceModifier
            .width(MedsDims.nextBarWidth)
            .height(MedsDims.nextBarHeight)
            .background(MedsTokens.statusDot(timeState))
            .cornerRadius(MedsDims.nextBarWidth / 2),
    ) {}
}

/**
 * 近 7 天的单个点 —— **圆点，不是胶囊条**。
 * 完成 = 粉实心；未完成 = 暖灰空心（双层 Box 模拟 1dp 环）。
 */
@Composable
fun WeekDot(done: Boolean) {
    val radius = MedsDims.weekDot / 2
    if (done) {
        Box(
            modifier = GlanceModifier
                .size(MedsDims.weekDot)
                .background(MedsTokens.pink)
                .cornerRadius(radius),
        ) {}
    } else {
        Box(
            modifier = GlanceModifier
                .size(MedsDims.weekDot)
                .background(MedsTokens.dotOutline)
                .cornerRadius(radius),
            contentAlignment = Alignment.Center,
        ) {
            Box(
                modifier = GlanceModifier
                    .size(MedsDims.weekDot - MedsDims.strokeWidth * 2)
                    .background(MedsTokens.card)
                    .cornerRadius(radius - MedsDims.strokeWidth),
            ) {}
        }
    }
}

/**
 * 小卡**唯一**的主按钮：实心粉胶囊，**满宽**。
 *
 * v3 起它的行为是**打开该药的「记录用药」Sheet**（不是直接打卡）——
 * 文案仍是「记 {药名}」，但点下去只是把用户带到确认界面。
 * 「库存告急」不是第二个按钮，改为药名旁的一行琥珀小字（见 [CriticalNote]）。
 */
@Composable
fun SolidButton(text: String, action: Action, modifier: GlanceModifier = GlanceModifier) {
    Box(
        modifier = modifier
            .height(MedsDims.smallBtnHeight)
            .background(MedsTokens.pink)
            .cornerRadius(MedsDims.smallBtnHeight / 2)
            .clickable(action),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = text,
            style = TextStyle(
                color = MedsTokens.onPink,
                fontSize = MedsDims.fsSmallBtn,
                fontWeight = FontWeight.Bold,
            ),
            maxLines = 1,
        )
    }
}

/**
 * 「库存不足」琥珀小字。
 *
 * **只在 `stockState == CRITICAL` 时出现**；库存充足时完全不渲染
 * （旧版无论库存多少都摆一个「库存告急」按钮，属 UI 债）。
 */
@Composable
fun CriticalNote() {
    Text(
        text = "库存不足",
        style = TextStyle(
            color = MedsTokens.amber,
            fontSize = MedsDims.fsSmallCritical,
            fontWeight = FontWeight.Medium,
        ),
        maxLines = 1,
    )
}

/**
 * 中卡一行底部的细进度条。
 *
 * 按比例填充只能靠 `LinearProgressIndicator` —— Glance 1.2.0 无
 * `fillMaxWidth(fraction)`。库存告急时给固定 0.22 的**短琥珀条**，不拉满。
 */
@Composable
fun RowProgressBar(item: MedsWidgetItem) {
    Column(modifier = GlanceModifier.fillMaxWidth()) {
        Spacer(GlanceModifier.height(3.dp))
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
            LinearProgressBar(
                progress = item.barWidthFraction,
                color = MedsTokens.barFill(item.barColor),
            )
        }
    }
}

@Composable
private fun LinearProgressBar(progress: Float, color: ColorProvider) {
    LinearProgressIndicator(
        progress = progress,
        modifier = GlanceModifier
            .fillMaxWidth()
            .height(MedsDims.barHeight),
        color = color,
        backgroundColor = MedsTokens.track,
    )
}
