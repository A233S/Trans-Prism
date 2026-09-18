package com.daanser.transprism

import android.content.ContentValues
import android.content.Intent
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import com.daanser.transprism.widget.MedsWidgetActions
import com.daanser.transprism.widget.MedsWidgetUpdater
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.io.File
import java.io.FileInputStream

class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL_GALLERY = "com.daanser.transprism/gallery_saver"

        /** 桌面用药小组件 → App 的动作通道 */
        const val CHANNEL_WIDGET = "com.daanser.transprism/widget_action"

        /** Dart 主动拉取「冷启动时的待处理动作」 */
        const val M_GET_LAUNCH_ACTION = "getLaunchAction"

        /** Dart 打卡完成后请求刷新桌面卡片 */
        const val M_REFRESH_WIDGETS = "refreshWidgets"

        /** 热启动时由原生主动推送动作给 Dart */
        const val M_ON_WIDGET_ACTION = "onWidgetAction"
    }

    private val ioScope = CoroutineScope(Dispatchers.Main.immediate + SupervisorJob())

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
                            ioScope.launch {
                                try {
                                    MedsWidgetUpdater.refreshAll(applicationContext)
                                    result.success(true)
                                } catch (e: Exception) {
                                    result.error("REFRESH_FAILED", e.message, null)
                                }
                            }
                        }

                        else -> result.notImplemented()
                    }
                }
            }

        // 冷启动：先把 Intent 里的动作收好，等 Dart 来取
        pendingWidgetAction = widgetActionFrom(intent)
    }

    /**
     * 热启动（Activity 已存在，launchMode=singleTop）：
     * 小组件点击走这里，直接推给 Dart。
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)

        val action = widgetActionFrom(intent) ?: return
        val channel = widgetChannel
        if (channel != null) {
            channel.invokeMethod(M_ON_WIDGET_ACTION, action)
        } else {
            pendingWidgetAction = action
        }
    }

    override fun onDestroy() {
        ioScope.cancel()
        super.onDestroy()
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
