package com.daanser.transprism.widget

import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.util.Log
import com.daanser.transprism.MainActivity

/**
 * 小组件点击的**广播中转** Receiver —— HyperOS / 澎湃 OS 兼容的关键一环。
 *
 * ## ⚠️ 当前状态：**备用路径，未接线**（2026-09-21）
 *
 * 真机（小米 / 澎湃 OS）实测：**删除并重新添加小组件后，本 Receiver 的自检计数仍为 0**
 * —— 即 HyperOS 根本不把小组件点击交给我们的广播，与「自启动 / 电池优化 /
 * 后台弹出界面」无关（三项用户都已允许）。
 *
 * 因此小组件点击已改回 `PendingIntent.getActivity` 直跳（见 `widgetClickAction`），
 * 本类**保留但不再被接线**：一是留作可一行切回的备选，二是它的计数本身
 * 就是「广播路径在真机上到底通不通」的证据。
 *
 * ---
 *
 * ## 为什么要绕这一道
 *
 * 原本小组件点击直接产出 `PendingIntent.getActivity(...)` 指向 `MainActivity`。
 * 这在原生 Android 上完全正常（Pixel / Android 16 实测通过），但在
 * **小米 HyperOS / 澎湃 OS 上被拦截**：卡片显示正常、点击毫无反应。
 *
 * 这不是猜测 —— 同级的参考项目
 * `calendar_countdown_widget`（一个专门为 HyperOS 写的原生小组件）在
 * README 的「踩坑记录（HyperOS 开发注意事项）」里写得很明确：
 *
 * > **小组件的 `PendingIntent` 不能直接从桌面进程启动"另一个 App 的 Activity"**
 * > —— HyperOS 会拦截。可行方案：发**广播**给自己的 Provider，
 * > 自己进程里再 `startActivity()` 跳转，这是应用内主动发起的调用，不受此限制。
 *
 * 其 `CountdownWidgetProvider` 的实现注释也是同一结论：
 * 「HyperOS blocks a widget's PendingIntent from directly targeting another app's
 * Activity, but is fine with an app-initiated startActivity() once we're running
 * our own code.」
 *
 * 于是链路从：
 * ```
 * 点击 → PendingIntent.getActivity → MainActivity          ❌ HyperOS 拦截
 * ```
 * 改为：
 * ```
 * 点击 → PendingIntent.getBroadcast → MedsWidgetClickReceiver.onReceive
 *      → context.startActivity(makeMainActivity(MainActivity))   ✅
 * ```
 *
 * ## 为什么 Glance 的广播 action 是安全的
 *
 * 反编译 `glance-appwidget:1.2.0` 确认：`applyTrampolineIntent`（那套
 * `exported="false"` 的中转 Activity）**只在 `getFillInIntentForAction` 里被调用**
 * —— 即只服务于 ListView / 集合类小部件的 fill-in intent。
 * `getPendingIntentForAction` 的 `SendBroadcastAction` 分支是**直接**
 * `PendingIntent.getBroadcast(ctx, requestCode, intent, flags or FLAG_IMMUTABLE)`，
 * 目标就是我们自己的 Receiver，不经过任何中转 Activity。
 *
 * 这一点很重要：参考项目还提到「中转 Activity 若设为 `exported="false"`，
 * 也可能被 HyperOS 拦截」。我们这条路径上没有中转 Activity，同时
 * 本 Receiver 在 manifest 里显式声明 `android:exported="true"` 并带 intent-filter，
 * 与参考项目（其 Provider 也是 `exported="true"` + 自定义 action 的 intent-filter）保持一致。
 *
 * ## 为什么 `startActivity` 在这里是合法的
 *
 * Receiver 被广播唤醒时，应用会获得一个短暂的「后台启动 Activity」豁免窗口，
 * 因此这一步 `startActivity()` 不会被后台启动限制拦掉 ——
 * 这正是参考项目所说的「应用内主动发起的调用」。
 */
class MedsWidgetClickReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        // 严格校验 action：本 Receiver 是 exported 的，只认自己那一个 action
        if (intent.action != ACTION_WIDGET_CLICK) return

        val widgetAction = intent.getStringExtra(MedsWidgetActions.EXTRA_ACTION)
        val drugId = intent.getStringExtra(MedsWidgetActions.EXTRA_DRUG_ID)
        Log.d(TAG, "小组件点击已送达（广播中转）: action=$widgetAction drugId=${drugId ?: "-"}")

        // 与桌面图标启动**同形**的 Intent：ACTION_MAIN + CATEGORY_LAUNCHER + 显式 component。
        //
        // ⚠️ `Intent.makeMainActivity()` **不带** FLAG_ACTIVITY_NEW_TASK —— 实测
        // （API 36 模拟器，用 `adb shell am broadcast` 直发本 Receiver）会直接抛：
        //   AndroidRuntimeException: Calling startActivity() from outside of an
        //   Activity context requires the FLAG_ACTIVITY_NEW_TASK flag.
        // 从 Receiver 这种非 Activity context 启动 Activity 必须**显式**加上它。
        // 再补 launcher 也会加的 RESET_TASK_IF_NEEDED（把已存在的任务正确拉回前台，
        // 而不是另起一个）。刻意不加 CLEAR_TOP —— 桌面图标也不加，
        // 加了会清掉用户压在栈上的页面。
        val launch = Intent.makeMainActivity(
            ComponentName(context, MainActivity::class.java),
        ).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED,
            )
            // 把小组件的语义参数原样带给 Dart 侧（onNewIntent → getLaunchAction）
            putExtra(MedsWidgetActions.EXTRA_ACTION, widgetAction)
            putExtra(MedsWidgetActions.EXTRA_DRUG_ID, drugId)
            putExtra(
                MedsWidgetActions.EXTRA_DRUG_NAME,
                intent.getStringExtra(MedsWidgetActions.EXTRA_DRUG_NAME),
            )
        }

        try {
            context.startActivity(launch)
            Log.d(
                TAG,
                "已 startActivity(MainActivity) flags=0x${Integer.toHexString(launch.flags)}",
            )
            recordClick(context, widgetAction, ok = true)
        } catch (e: Exception) {
            // 理论上不会走到；真走到说明被系统拦了，留日志便于真机排查
            Log.e(TAG, "startActivity 失败: $e")
            recordClick(context, widgetAction, ok = false)
        }
    }

    /** 落盘自检，见 [`MedsWidgetDiag`]。 */
    private fun recordClick(context: Context, action: String?, ok: Boolean) =
        MedsWidgetDiag.recordClick(context, action, ok)

    companion object {
        private const val TAG = "TP-Widget"

        /** 小组件点击广播的 action；manifest 的 intent-filter 必须与之一致 */
        const val ACTION_WIDGET_CLICK = "com.daanser.transprism.widget.action.CLICK"
    }
}

