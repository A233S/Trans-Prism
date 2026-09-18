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
import androidx.glance.appwidget.cornerRadius
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import com.daanser.transprism.R

/**
 * 中卡 / 小卡共用的原子组件。
 *
 * 实现约束（已对照 Glance 1.2.0 字节码核实）：
 *  - **没有 `border` modifier** → 空心点与描边按钮一律用「双层 Box + 圆角差」
 *    模拟，不引入 `border`。
 *  - **没有 `fillMaxWidth(fraction)`，`defaultWeight()` 也不接受权重参数**
 *    → 按比例填充只能交给 `LinearProgressIndicator(progress = ...)`。
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
 * 中卡右上角的小号**实心粉胶囊**。
 * 高度约 22dp（11sp 文字 + 4dp 上下内边距），圆角取半高即胶囊形。
 */
@Composable
fun SolidPillButton(text: String, action: Action) {
    Box(
        modifier = GlanceModifier
            .background(MedsTokens.pink)
            .cornerRadius(12.dp)
            .padding(horizontal = 11.dp, vertical = 4.dp)
            .clickable(action),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = text,
            style = TextStyle(
                color = MedsTokens.onPink,
                fontSize = MedsDims.fsPill,
                fontWeight = FontWeight.Bold,
            ),
            maxLines = 1,
        )
    }
}

/** 小卡主按钮：**实心粉**胶囊（不是浅紫、不是系统默认白边） */
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
 * 小卡次按钮：**琥珀描边**胶囊。
 *
 * Glance 1.2.0 无 `border` modifier，故用「琥珀底 + 卡片色内层」双层 Box 造出
 * 1dp 描边 —— 视觉等同 HTML 的 `border: 1px solid var(--amber)`，
 * 且**不是** OutlinedButton 的系统默认白边。
 */
@Composable
fun StrokeButton(text: String, action: Action, modifier: GlanceModifier = GlanceModifier) {
    Box(
        modifier = modifier
            .height(MedsDims.smallBtnHeight)
            .background(MedsTokens.amber)
            .cornerRadius(MedsDims.smallBtnHeight / 2)
            .clickable(action),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            modifier = GlanceModifier
                .fillMaxSize()
                .background(MedsTokens.card)
                .cornerRadius(MedsDims.smallBtnHeight / 2 - MedsDims.strokeWidth),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = text,
                style = TextStyle(
                    color = MedsTokens.amber,
                    fontSize = MedsDims.fsSmallBtn,
                    fontWeight = FontWeight.Bold,
                ),
                maxLines = 1,
            )
        }
    }
}
