package com.daanser.transprism

import android.app.AppOpsManager
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Process
import android.provider.MediaStore
import android.provider.Settings
import android.util.Log
import com.daanser.transprism.widget.MedsWidgetActions
import com.daanser.transprism.widget.MedsWidgetDiag
import com.daanser.transprism.widget.MedsWidgetUpdater
import com.daanser.transprism.widget.MediumMedsWidgetReceiver
import com.daanser.transprism.widget.SmallMedsWidgetReceiver
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class MainActivity : FlutterActivity() {

    private companion object {
        const val TAG = "TP-Widget"

        const val CHANNEL_GALLERY = "com.daanser.transprism/gallery_saver"

        /** 桌面用药小组件 → App 的动作通道 */
        const val CHANNEL_WIDGET = "com.daanser.transprism/widget_action"

        /** Dart 主动拉取「冷启动时的待处理动作」 */
        const val M_GET_LAUNCH_ACTION = "getLaunchAction"

        /** Dart 打卡完成后请求刷新桌面卡片 */
        const val M_REFRESH_WIDGETS = "refreshWidgets"

        /** 热启动时由原生主动推送动作给 Dart */
        const val M_ON_WIDGET_ACTION = "onWidgetAction"

        /** Dart 侧「我的 → 添加到主屏幕」请求 pin 小组件（Android 8+） */
        const val M_PIN_WIDGET = "pinMedsWidget"

        /** 查询本机是否支持 requestPinAppWidget（Android 8+ 且 Launcher 实现） */
        const val M_CAN_PIN_WIDGET = "canPinMedsWidget"

        /** 读取「小组件点击是否送达」诊断（澎湃 OS 间歇性点击失效的定性手段） */
        const val M_GET_CLICK_DIAG = "getWidgetClickDiag"

        /** pin 尺寸参数值 */
        const val SIZE_MEDIUM = "medium"
        const val SIZE_SMALL = "small"

        /** OEM 权限通道（小米「后台弹出界面」检测 / 跳转） */
        const val CHANNEL_OEM_PERM = "com.daanser.transprism/oem_permissions"
        const val M_IS_MIUI_FAMILY = "isMiuiFamily"
        const val M_BG_POPUP_ALLOWED = "isBackgroundPopupAllowed"
        const val M_OPEN_BG_POPUP = "openBackgroundPopupSettings"

        /**
         * 小米「后台弹出界面」对应的 AppOps op 号。
         * 未在 `AppOpsManager` 中公开，社区实测值为 10021
         * （见小米《后台弹出页面权限管理说明》对应的权限项）。
         */
        const val OP_BACKGROUND_START_ACTIVITY = 10021
    }

    private var widgetChannel: MethodChannel? = null

    /**
     * 冷启动时 MethodChannel 尚未建立，先把动作暂存，
     * 等 Dart 侧 `getLaunchAction` 主动来取（取完即清，避免重复执行）。
     */
    private var pendingWidgetAction: Map<String, String?>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── 相册保存（既有实现，行为未改动） ──
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_GALLERY)
            .setMethodCallHandler { call, result ->
                if (call.method == "saveImage") {
                    val filePath = call.argument<String>("filePath")
                    if (filePath != null) {
                        try {
                            saveImageToGallery(filePath)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SAVE_FAILED", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARG", "filePath is null", null)
                    }
                } else {
                    result.notImplemented()
                }
            }

        // ── 桌面用药小组件动作（新增） ──
        widgetChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_WIDGET).apply {
                setMethodCallHandler { call, result ->
                    when (call.method) {
                        M_GET_LAUNCH_ACTION -> {
                            val action = pendingWidgetAction ?: widgetActionFrom(intent)
                            pendingWidgetAction = null
                            result.success(action)
                        }

                        M_REFRESH_WIDGETS -> {
                            // 尾沿去抖：多个触发源（回前台 / 打卡完成）在同一瞬间
                            // 撞车时只渲染一次，且渲染的一定是**最后**那次的库状态。
                            // 详见 MedsWidgetUpdater 的类注释。
                            MedsWidgetUpdater.requestRefresh(applicationContext)
                            result.success(true)
                        }

                        M_CAN_PIN_WIDGET -> result.success(canPinMedsWidget())

                        M_GET_CLICK_DIAG -> result.success(widgetClickDiag())

                        M_PIN_WIDGET -> {
                            val size = call.argument<String>("size") ?: SIZE_MEDIUM
                            result.success(pinMedsWidget(size))
                        }

                        else -> result.notImplemented()
                    }
                }
            }

        // ── OEM 权限（小米「后台弹出界面」）──
        // 该权限默认拒绝，且会拦掉「后台 startActivity」——桌面小组件点击正好走这条路，
        // 症状是「卡片显示正常但点了不弹应用」。所以必须能检测 + 一键跳转设置页。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_OEM_PERM)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    M_IS_MIUI_FAMILY -> result.success(isMiuiFamily())
                    M_BG_POPUP_ALLOWED -> result.success(isBackgroundPopupAllowed())
                    M_OPEN_BG_POPUP -> result.success(openBackgroundPopupSettings())
                    else -> result.notImplemented()
                }
            }

        // 冷启动：先把 Intent 里的动作收好，等 Dart 来取
        pendingWidgetAction = widgetActionFrom(intent)
    }

    /**
     * 冷启动：在 Flutter 引擎起来之前就把 Intent 记一笔。
     *
     * ⚠️ 这一行是排查「点小组件不弹应用」的**唯一分界点**：
     * - 日志出现 → 点击已送达 App，问题在 App 内部（继续看 Dart 侧 `🧩 [TP-Widget]`）。
     * - 日志不出现 → 系统/桌面**根本没把这次启动交给我们**：
     *   典型原因是 OEM 限制（小米/澎湃的「后台弹出界面」默认拒绝、
     *   或 App 被强停后小组件只剩灰色占位图）。
     *
     * 放在 `super.onCreate` 之前，确保 Flutter 初始化失败也能留下痕迹。
     */
    override fun onCreate(savedInstanceState: Bundle?) {
        Log.d(TAG, "MainActivity.onCreate ← ${describeIntent(intent)}")
        super.onCreate(savedInstanceState)
        // 终点自检：只要 Intent 带小组件 action，就记一次「被小组件拉起」
        widgetActionFrom(intent)?.get("action")?.let {
            MedsWidgetDiag.recordLaunch(this, it)
        }
    }

    /**
     * 热启动（Activity 已存在，launchMode=singleTop）：
     * 小组件点击走这里，直接推给 Dart。
     */
    override fun onNewIntent(intent: Intent) {
        Log.d(TAG, "MainActivity.onNewIntent ← ${describeIntent(intent)}")
        super.onNewIntent(intent)
        setIntent(intent)

        val action = widgetActionFrom(intent) ?: return
        MedsWidgetDiag.recordLaunch(this, action["action"])
        val channel = widgetChannel
        if (channel != null) {
            channel.invokeMethod(M_ON_WIDGET_ACTION, action)
        } else {
            pendingWidgetAction = action
        }
    }

    /** 把 Intent 压成一行，便于 logcat 比对「有没有收到这次点击」 */
    private fun describeIntent(intent: Intent?): String {
        if (intent == null) return "intent=null"
        val action = intent.getStringExtra(MedsWidgetActions.EXTRA_ACTION) ?: "(非小组件启动)"
        val drugId = intent.getStringExtra(MedsWidgetActions.EXTRA_DRUG_ID)
        return "action=$action drugId=${drugId ?: "-"} " +
            "cmp=${intent.component?.flattenToShortString() ?: "-"} " +
            "flags=0x${Integer.toHexString(intent.flags)}"
    }

    /** 从 Intent 解析小组件动作；非小组件启动返回 null */
    private fun widgetActionFrom(intent: Intent?): Map<String, String?>? {
        val action = intent?.getStringExtra(MedsWidgetActions.EXTRA_ACTION) ?: return null
        return mapOf(
            "action" to action,
            "drugId" to intent.getStringExtra(MedsWidgetActions.EXTRA_DRUG_ID),
            "drugName" to intent.getStringExtra(MedsWidgetActions.EXTRA_DRUG_NAME),
        )
    }

    /**
     * 读取小组件点击诊断（由 [`MedsWidgetClickReceiver`] 落盘）。
     *
     * 用途：澎湃 OS 上「要点很多下才能进去一次」属于间歇性失败，必须区分
     * **广播没送到** 还是 **广播到了但 Activity 启动被拦**。
     * 远程测试者没有 adb，所以由 App 内自检页直接展示这份记录。
     *
     * 返回 `{ count, lastAt, lastAction, lastOk }`；从未收到过则 `count = 0`。
     */
    private fun widgetClickDiag(): Map<String, Any?> = MedsWidgetDiag.snapshot(this)

    // ════════════════════════════════════════════════════════════
    //  OEM 权限：小米 / 澎湃 OS 的「后台弹出界面」
    // ════════════════════════════════════════════════════════════

    /**
     * 本机是否小米系（小米 / 红米 / POCO / 澎湃 OS）。
     *
     * 注意 `MANUFACTURER` 在红米 / POCO 上仍然是 `Xiaomi`，
     * 而 `BRAND` 才是 `Redmi` / `POCO`，所以两个都看。
     */
    private fun isMiuiFamily(): Boolean {
        val m = Build.MANUFACTURER.orEmpty()
        val b = Build.BRAND.orEmpty()
        return m.equals("xiaomi", true) || b.equals("xiaomi", true) ||
            b.equals("redmi", true) || b.equals("poco", true)
    }

    /**
     * 「后台弹出界面」是否已允许。
     *
     * 背景：小米把该权限做成 **AppOps op 10021**（`OP_BACKGROUND_START_ACTIVITY`），
     * 没有公开 API，只能反射 `checkOpNoThrow`。默认拒绝，会拦掉
     * 「App 在后台时 startActivity」—— 桌面小组件点击正好走这条路径
     * （Glance 的 PendingIntent → 中转 Activity → MainActivity），
     * 表现就是「卡片显示正常，但点了不弹应用」。
     *
     * 非小米机型不适用，直接返回 true。
     */
    private fun isBackgroundPopupAllowed(): Boolean {
        if (!isMiuiFamily()) return true
        return try {
            val ops = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val method = ops.javaClass.getMethod(
                "checkOpNoThrow",
                Int::class.javaPrimitiveType,
                Int::class.javaPrimitiveType,
                String::class.java,
            )
            val mode = method.invoke(
                ops,
                OP_BACKGROUND_START_ACTIVITY,
                Process.myUid(),
                packageName,
            ) as Int
            mode == AppOpsManager.MODE_ALLOWED
        } catch (e: Exception) {
            // 不同 MIUI 版本 op 号可能变动，取不到就当作「未知 → 未允许」，
            // 让 UI 显示成「去设置」，宁可多提示也不要漏掉
            Log.w(TAG, "检测「后台弹出界面」失败: $e")
            false
        }
    }

    /**
     * 跳到小米安全中心的「后台弹出界面」权限页。
     * 不同 MIUI 版本类名不同，逐个尝试；全失败则退回系统「应用详情」页。
     */
    private fun openBackgroundPopupSettings(): Boolean {
        val candidates = listOf(
            "com.miui.permcenter.permissions.PermissionsEditorActivity",
            "com.miui.permcenter.permissions.AppPermissionsEditorActivity",
        )
        for (cls in candidates) {
            try {
                startActivity(
                    Intent("miui.intent.action.APP_PERM_EDITOR")
                        .setClassName("com.miui.securitycenter", cls)
                        .putExtra("extra_pkgname", packageName),
                )
                return true
            } catch (e: Exception) {
                Log.d(TAG, "打开 $cls 失败，尝试下一个: ${e.message}")
            }
        }
        return try {
            startActivity(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                    .setData(Uri.fromParts("package", packageName, null)),
            )
            true
        } catch (e: Exception) {
            Log.w(TAG, "打开应用详情页也失败: $e")
            false
        }
    }

    // ──────────────────────────────────────────────
    // 桌面小组件 pin（「我的 → 添加到主屏幕」）
    //
    // 走 AppWidgetManager.requestPinAppWidget —— 系统弹出「添加到主屏幕」确认框，
    // 不需要用户自己进桌面长按、也不跳系统设置页。
    // 仅 Android 8.0（API 26）起提供，且取决于 Launcher 是否实现
    // （isRequestPinAppWidgetSupported）；不支持时返回 false，由 Dart 侧
    // 退化为「长按桌面 → 小组件 → TP」的文字说明。
    // ──────────────────────────────────────────────

    private fun canPinMedsWidget(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return try {
            AppWidgetManager.getInstance(applicationContext).isRequestPinAppWidgetSupported
        } catch (e: Exception) {
            false
        }
    }

    private fun pinMedsWidget(size: String): Boolean {
        if (!canPinMedsWidget()) return false
        val receiver = if (size == SIZE_SMALL) {
            SmallMedsWidgetReceiver::class.java
        } else {
            MediumMedsWidgetReceiver::class.java
        }
        return try {
            AppWidgetManager.getInstance(applicationContext).requestPinAppWidget(
                ComponentName(applicationContext, receiver),
                null,
                null,
            )
            true
        } catch (e: Exception) {
            false
        }
    }

    // ──────────────────────────────────────────────
    // 相册保存（既有实现，未改动）
    // ──────────────────────────────────────────────

    private fun saveImageToGallery(filePath: String) {
        val file = File(filePath)
        if (!file.exists()) throw Exception("File not found: $filePath")

        val fileName = file.name
        val mimeType = when {
            fileName.endsWith(".png", ignoreCase = true) -> "image/png"
            fileName.endsWith(".jpg", ignoreCase = true) ||
                    fileName.endsWith(".jpeg", ignoreCase = true) -> "image/jpeg"
            fileName.endsWith(".webp", ignoreCase = true) -> "image/webp"
            else -> "image/*"
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // Android 10+ (API 29+): 使用 MediaStore
            val contentValues = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, fileName)
                put(MediaStore.Images.Media.MIME_TYPE, mimeType)
                put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES)
                put(MediaStore.Images.Media.IS_PENDING, 1)
            }

            val resolver = contentResolver
            val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, contentValues)
                ?: throw Exception("Failed to create MediaStore entry")

            resolver.openOutputStream(uri)?.use { outputStream ->
                FileInputStream(file).use { inputStream ->
                    inputStream.copyTo(outputStream)
                }
            } ?: throw Exception("Failed to open output stream")

            contentValues.clear()
            contentValues.put(MediaStore.Images.Media.IS_PENDING, 0)
            resolver.update(uri, contentValues, null, null)
        } else {
            // Android 9 及以下: 使用旧版 API
            MediaStore.Images.Media.insertImage(
                contentResolver,
                filePath,
                fileName,
                "Saved from Trans Prism"
            )
        }
    }
}
