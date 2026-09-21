package com.daanser.transprism.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.glance.ExperimentalGlanceApi
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalContext
import androidx.glance.LocalSize
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.ContentScale
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
import kotlin.math.roundToInt

/**
 * 小尺寸（2×2）**下一剂专用环形**小组件 —— v3。
 *
 * 结构（与首页「续航环」同构）：
 * ```
 * 针 螺内酯                    库存不足        ← critical 才有琥珀小字
 *            ╭─────╮
 *            │  1  │                          ← 中心：剩余 / 已超 的主数字
 *            │ 小时 │
 *            ╰─────╯
 *             待服                            ← 环下小标签
 *      [     记 螺内酯     ]                  ← 单按钮，左右留卡片同款 padding
 * ```
 *
 * ── 规则（定稿）───────────────────────────────────────────────
 * - **只展示「下一剂」那一条** —— 与 3×4 的高亮行是同一条药。
 * - 待服：环和数字用**青**；已超：环和数字用**粉**，标签写「已超」。
 * - 「库存告急」**不做第二个按钮**：仅当该药 critical 时，药名旁加一行琥珀小字。
 * - 环是预渲染位图（Glance 无 Canvas），无复杂动画，见 [MedsRingRenderer]。
 *
 * ── v3 核心：**点环 / 点按钮都不再打卡** ─────────────────────────
 * v2 点一下就直接扣库存。v3 起两者都只做一件事：
 * **带 medId 唤起 App，拉起该药的「记录用药」Sheet**；
 * 只有 Sheet 里点「确认服药」才真正写入。取消 / 返回不改任何数据。
 *
 * ── v3 视觉收敛 ────────────────────────────────────────────────
 * - 环线宽 8.5% → **6.2%**，并给环与位图边缘留白：中心「1 / 小时」更有呼吸感，
 *   观感向 App 首页续航环靠拢。
 * - 按钮底部留白 10dp → **13dp**，不再顶死底边；左右仍是与卡片一致的 12dp。
 *
 * ── v2 修掉的 UI 债（保留） ────────────────────────────────────
 * 1. 「待服」的大数字**不再用粉**（旧版不论状态一律 `MedsTokens.pink`）。
 * 2. 库存充足时**不再出现**「库存告急」按钮。
 * 3. 不再「放大数字 + 双按钮」—— 改为环形 + 单按钮。
 */
class SmallMedsWidget : GlanceAppWidget() {

    override val sizeMode: SizeMode = MEDS_WIDGET_SIZE_MODE

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        // ⚠️⚠️ 数据与主题**必须在 `provideContent` 的组合 lambda 内读取**，不能提到外面。
        // Glance 的会话是长驻的，`provideGlance` 只在会话创建时跑一次；
        // 之后每次 `update()` 只是重组同一棵组合树，闭包捕获的旧数据不会刷新。
        // 详见 MediumMedsWidget.provideGlance 的注释（同一个坑）。
        provideContent {
            // 自检：记录「卡片最近一次渲染时刻」（与中卡共用一份记录）
            MedsWidgetDiag.recordRender(context)
            val colors = MedsWidgetThemePrefs.colorsFor(context)
            val data = MedsWidgetDataLoader.load(context)
            MedsWidgetThemeProvider(colors) { SmallMedsContent(data.small) }
        }
    }

    /**
     * 预览矩阵入口。
     *
     * 四态假数据在 `MedsWidgetDataLoader.previewSmall(SmallPreviewState)`：
     * `WAITING_IN_STOCK` / `WAITING_CRITICAL` / `OVERDUE_IN_STOCK` / `OVERDUE_CRITICAL`
     * —— **待服 / 已超 × 缺货 / 库存足**。
     *
     * 浅色 / 深色两套由 **App 主题偏好** 决定（`我的 → 主题模式`），
     * 不在这里出变体：切完主题重开预览即可。
     *
     * 想逐个看四态：把 [PREVIEW_SMALL_STATE] 改成目标枚举即可。
     */
    override suspend fun providePreview(context: Context, widgetCategory: Int) {
        val colors = MedsWidgetThemePrefs.colorsFor(context)
        provideContent {
            MedsWidgetThemeProvider(colors) {
                SmallMedsContent(MedsWidgetDataLoader.previewSmall(PREVIEW_SMALL_STATE))
            }
        }
    }
}

/** 预览默认渲染的态（四态矩阵见 [SmallMedsWidget.providePreview]） */
private val PREVIEW_SMALL_STATE: SmallPreviewState = SmallPreviewState.OVERDUE_CRITICAL

@Composable
private fun SmallMedsContent(focus: MedsSmallFocus?) {
    Box(
        modifier = GlanceModifier
            .fillMaxSize()
            .background(MedsTokens.card)
            .cornerRadius(MedsDims.cardRadius)
            // 点击整卡空白处（非环 / 非按钮）→ 今日用药页
            .clickable(widgetClickAction(MedsWidgetActions.ACTION_OPEN_MEDS)),
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
                // ── 药名贴顶：针筒 + 药名（一行截断）+（critical 时）琥珀小字 ──
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
                    if (focus.isCritical) {
                        Spacer(GlanceModifier.width(4.dp))
                        CriticalNote()
                    }
                }

                Spacer(GlanceModifier.height(4.dp))

                // ── 环 + 中心数字 + 环下标签：整块可点 = 打开该药的记录用药 Sheet ──
                // v3：只唤起 App 拉起 Sheet，**不直接打卡**。
                Column(
                    modifier = GlanceModifier
                        .fillMaxWidth()
                        .defaultWeight()
                        .clickable(openRecordSheetAction(focus.drugId, focus.name)),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    // ⚠️ 环的容器只能用 `fillMaxWidth().defaultWeight()`，
                    // **不能用 `fillMaxSize()`** —— 那会把本 Column 的高度全吃光，
                    // 紧跟其后的「待服 / 已超」标签被挤成 0 高（真机实测：标签完全不渲染）。
                    // `defaultWeight()` 是 ColumnScope 的成员，所以只能由调用点传进来。
                    NextDoseRing(
                        focus = focus,
                        modifier = GlanceModifier.fillMaxWidth().defaultWeight(),
                    )
                    Spacer(GlanceModifier.height(2.dp))
                    Text(
                        text = focus.stateText,
                        style = TextStyle(
                            color = MedsTokens.ringAccent(focus.isOverdue),
                            fontSize = MedsDims.fsSmallState,
                            fontWeight = FontWeight.Medium,
                            textAlign = TextAlign.Center,
                        ),
                        maxLines = 1,
                    )
                }

                Spacer(GlanceModifier.height(4.dp))

                // ── 唯一按钮，满宽；文案带药名（v3：点它只是打开 Sheet，不直接记） ──
                SolidButton(
                    text = "记 ${focus.name}",
                    action = openRecordSheetAction(focus.drugId, focus.name),
                    modifier = GlanceModifier.fillMaxWidth(),
                )
            }
        }
    }
}

/**
 * 环形进度 + 中心主数字。
 *
 * 环 = [MedsRingRenderer] 预渲染的方形位图，`ContentScale.Fit` 摆进可用区域，
 * 因此组件被拉伸/压缩时环会自动等比缩放，不会变形。
 * 中心文字用 `Box` 叠加在环上（Glance 的 Box 是 FrameLayout，可重叠）。
 */
@OptIn(ExperimentalGlanceApi::class)
@Composable
private fun NextDoseRing(focus: MedsSmallFocus, modifier: GlanceModifier = GlanceModifier) {
    val context = LocalContext.current
    val widgetSize = LocalSize.current
    val density = context.resources.displayMetrics.density

    // 位图边长按组件实际尺寸 × 密度推导；Fit 会等比缩放，
    // 略大一点只会被缩小（更清晰），不会变形。
    val shortestDp = minOf(widgetSize.width.value, widgetSize.height.value)
    val ringPx = if (shortestDp.isFinite() && shortestDp > 0f) {
        (shortestDp * density).roundToInt().coerceIn(MedsDims.ringMinPx, MedsDims.ringMaxPx)
    } else {
        MedsDims.ringFallbackPx
    }

    val bitmap = MedsRingRenderer.render(
        colors = MedsTokens.current,
        progress = focus.progress,
        overdue = focus.isOverdue,
        sizePx = ringPx,
    )

    Box(
        modifier = modifier,
        contentAlignment = Alignment.Center,
    ) {
        Image(
            provider = ImageProvider(bitmap),
            contentDescription = null,
            modifier = GlanceModifier.fillMaxSize(),
            contentScale = ContentScale.Fit,
        )
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                text = focus.numberText,
                style = TextStyle(
                    // 待服青 / 已超粉 —— 唯一取色口，禁止再写死 pink
                    color = MedsTokens.ringAccent(focus.isOverdue),
                    fontSize = MedsDims.fsSmallNum,
                    fontWeight = FontWeight.Bold,
                    textAlign = TextAlign.Center,
                ),
                maxLines = 1,
            )
            Text(
                text = focus.unitText,
                style = TextStyle(
                    color = MedsTokens.muted,
                    fontSize = MedsDims.fsSmallUnit,
                    fontWeight = FontWeight.Medium,
                    textAlign = TextAlign.Center,
                ),
                maxLines = 1,
            )
        }
    }
}
