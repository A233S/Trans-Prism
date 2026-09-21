package com.daanser.transprism.widget

import android.content.Context
import android.util.Log

/**
 * 小组件点击 / 渲染的**落盘自检**，供 App 内「我的 → 高级 → 通知权限与保活」展示。
 *
 * ## 为什么需要它
 *
 * 小米澎湃 OS 上排查「点小组件不弹应用」时，反复卡在**分不清是哪一段断了**：
 * 是卡片是旧的？是点击没送达？还是 App 被拉起了但启动被拦？
 * 远程测试者没有 adb，所以把三个关键事实都落盘，让 App 自己说出来。
 *
 * ## 记什么
 *
 * | 字段 | 写入方 | 含义 |
 * |---|---|---|
 * | [KEY_RENDER_AT] | 小组件 `provideContent` | **卡片最近一次渲染时刻** —— 用来排除「桌面上是旧卡片」 |
 * | [KEY_LAUNCH_COUNT] / [KEY_LAUNCH_AT] | `MainActivity.onCreate/onNewIntent` | **App 被小组件拉起过几次** —— 终点指标 |
 * | [KEY_CLICK_COUNT] / [KEY_CLICK_AT] | `MedsWidgetClickReceiver`（备用路径） | 广播路径收到过几次 |
 *
 * **重点看「渲染时刻」和「拉起次数」**：只要渲染时刻是新的，就说明桌面上跑的是当前这版代码；
 * 此时若拉起次数仍是 0，就说明点击确实没被系统投递给 App，与权限设置无关。
 *
 * ## 为什么用 `commit()`
 *
 * 这些都是从 `BroadcastReceiver.onReceive` / `Activity.onCreate` 里写的，
 * 返回后进程随时可能被系统冻结；`apply()` 的异步落盘有丢失风险。
 * 单文件、字段极少，同步写代价可忽略。
 */
object MedsWidgetDiag {

    private const val TAG = "TP-Widget"

    /** 独立 SP 文件，不碰 Flutter 的 `FlutterSharedPreferences` */
    const val PREFS = "meds_widget_click_diag"

    /** 卡片最近一次渲染时刻（epoch millis） */
    const val KEY_RENDER_AT = "last_render_at"

    /** App 被小组件拉起的次数 / 最近时刻 */
    const val KEY_LAUNCH_COUNT = "launch_count"
    const val KEY_LAUNCH_AT = "last_launch_at"

    /** 广播路径（备用）收到点击的次数 / 最近时刻 / 动作 / 启动是否成功 */
    const val KEY_CLICK_COUNT = "click_count"
    const val KEY_CLICK_AT = "last_click_at"
    const val KEY_CLICK_ACTION = "last_click_action"
    const val KEY_CLICK_OK = "last_click_start_ok"

    /** 小组件渲染时调用：刷新「卡片最近渲染时刻」。 */
    fun recordRender(context: Context) {
        write(context) { it.putLong(KEY_RENDER_AT, System.currentTimeMillis()) }
    }

    /** `MainActivity` 收到带小组件 action 的 Intent 时调用（冷启动 / 热启动都算）。 */
    fun recordLaunch(context: Context, action: String?) {
        val prefs = prefs(context)
        write(context) {
            it.putLong(KEY_LAUNCH_AT, System.currentTimeMillis())
                .putString(KEY_CLICK_ACTION, action ?: "-")
                .putInt(KEY_LAUNCH_COUNT, prefs.getInt(KEY_LAUNCH_COUNT, 0) + 1)
        }
    }

    /** 广播中转 Receiver 收到点击时调用（当前为备用路径）。 */
    fun recordClick(context: Context, action: String?, ok: Boolean) {
        val prefs = prefs(context)
        write(context) {
            it.putLong(KEY_CLICK_AT, System.currentTimeMillis())
                .putString(KEY_CLICK_ACTION, action ?: "-")
                .putBoolean(KEY_CLICK_OK, ok)
                .putInt(KEY_CLICK_COUNT, prefs.getInt(KEY_CLICK_COUNT, 0) + 1)
        }
    }

    /** 供 `MainActivity` 通过 MethodChannel 回给 Dart。 */
    fun snapshot(context: Context): Map<String, Any?> {
        val p = prefs(context)
        return mapOf(
            "renderAt" to p.getLong(KEY_RENDER_AT, 0L),
            "launchCount" to p.getInt(KEY_LAUNCH_COUNT, 0),
            "launchAt" to p.getLong(KEY_LAUNCH_AT, 0L),
            "clickCount" to p.getInt(KEY_CLICK_COUNT, 0),
            "clickAt" to p.getLong(KEY_CLICK_AT, 0L),
            "lastAction" to p.getString(KEY_CLICK_ACTION, null),
            "clickOk" to p.getBoolean(KEY_CLICK_OK, false),
        )
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private inline fun write(context: Context, block: (android.content.SharedPreferences.Editor) -> Unit) {
        try {
            val editor = prefs(context).edit()
            block(editor)
            editor.commit()
        } catch (e: Exception) {
            Log.w(TAG, "写入小组件自检失败: $e")
        }
    }
}
