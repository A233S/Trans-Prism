package com.daanser.transprism.widget

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.util.LruCache
import androidx.compose.ui.graphics.toArgb
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * 2×2 小卡的**环形进度**渲染器。
 *
 * ── 为什么自己画位图 ────────────────────────────────────────────
 * Glance 1.2.0 **没有 Canvas / DrawScope**，也**没有**确定进度的圆形指示器：
 * `androidx.glance.appwidget.CircularProgressIndicator` 只有
 * `(modifier, color)` 两个参数 —— 它是**不定进度**的转圈 loader，
 * 没有 `progress`、没有轨道色，不能当环形进度条用。
 *
 * 但 Glance 支持 `Image(provider = ImageProvider(bitmap))`
 * （`androidx.glance.ImageKt.ImageProvider(Bitmap)` 已确认存在）。
 * 所以这里用 `android.graphics.Canvas` 把环**预渲染成一张方图**，
 * 交给 Glance 用 `ContentScale.Fit` 摆进小卡 —— 无动画、无第三方依赖。
 *
 * ── 环进度口径（定稿，写死在注释里以免以后被改歪）─────────────────
 * **「距离下次剂量的时间进度」**，不是今日完成度：
 *
 *     progress = 1 − 距下次剂量剩余分钟 / 该药的给药间隔分钟
 *
 * - 刚打完卡 → 剩余 ≈ 整个间隔 → `progress ≈ 0`（环空）
 * - 时间流逝 → 环逐渐填满
 * - 已超时 → `progress = 1.0`（整圈，且用粉色）
 *
 * 给药间隔取值：离散时刻模式（`dailyReminderTimes` 非空）取 `24h / 时刻数`；
 * 否则取 `intervalValue` 折算的小时数；都拿不到时兜底 24h。
 * 该换算在 [MedsWidgetDataLoader] 里完成，本类只负责画。
 *
 * ── 缓存 ────────────────────────────────────────────────────────
 * 进度按 **1% 分桶**（`bucket`）后再进 LRU，避免每帧生成新位图；
 * 缓存键含解析后的两个色值 —— 主题偏好变了会自然落到新键上。
 */
object MedsRingRenderer {

    private const val MAX_CACHE_ENTRIES = 8
    /**
     * 环线宽 = 边长 × 该比例。
     * v3 从 0.085 收细到 0.062 —— 真机上 0.085 显得「环太粗、中心发闷」，
     * 收细后中心「1 / 小时」才有呼吸感，观感也更接近 App 首页的续航环。
     */
    private const val STROKE_RATIO = 0.062f
    /** 环与位图边缘再留一点白，避免环贴着可用区域边线 */
    private const val INNER_MARGIN_RATIO = 0.035f
    /** 12 点方向起笔 */
    private const val START_ANGLE = -90f
    /** 进度极小时也留一小段圆头，否则「刚打完卡」看起来像没有环 */
    private const val MIN_SWEEP = 3f

    private val cache = LruCache<String, Bitmap>(MAX_CACHE_ENTRIES)

    /**
     * 渲染（或命中缓存）一张边长 [sizePx] 的方形环位图。
     *
     * @param colors  当前这次组合的 token 集（由 `MedsTokens.current` 提供）——
     *                环色不走 Glance 的 ColorProvider（位图里已经烤死了），
     *                所以这里直接收原始 `Color`。
     * @param progress 0f..1f，见类注释的口径
     * @param overdue  true = 已超（环用粉）；false = 待服（环用青）
     * @param sizePx   位图边长（像素）；内部会 clamp 到
     *                 [MedsDims.ringMinPx]..[MedsDims.ringMaxPx]
     */
    fun render(
        colors: MedsWidgetColors,
        progress: Float,
        overdue: Boolean,
        sizePx: Int,
    ): Bitmap {
        val side = sizePx.coerceIn(MedsDims.ringMinPx, MedsDims.ringMaxPx)
        val arcColor = if (overdue) colors.pink else colors.cyan
        val trackColor = colors.track
        val bucket = (progress.coerceIn(0f, 1f) * 100f).roundToInt()
        val key = "$side|$bucket|${arcColor.toArgb()}|${trackColor.toArgb()}"

        cache.get(key)?.let { return it }

        val bitmap = Bitmap.createBitmap(side, side, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val stroke = max(side * STROKE_RATIO, 2f)
        val inset = stroke / 2f + side * INNER_MARGIN_RATIO
        val box = RectF(inset, inset, side - inset, side - inset)

        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = stroke
            strokeCap = Paint.Cap.ROUND
        }

        // 轨道：整圈，与进度条轨道同一个 token
        paint.color = trackColor.toArgb()
        canvas.drawArc(box, 0f, 360f, false, paint)

        // 进度弧：bucket == 0 时不画，避免「刚打完卡」出现一个起点圆点
        if (bucket > 0) {
            paint.color = arcColor.toArgb()
            canvas.drawArc(box, START_ANGLE, max(bucket / 100f * 360f, MIN_SWEEP), false, paint)
        }

        cache.put(key, bitmap)
        return bitmap
    }
}
