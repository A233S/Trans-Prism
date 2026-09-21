import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 桌面用药小组件（Android / Glance）的 **App 侧桥接**。
///
/// 通道名与 `android/.../MainActivity.kt` 的 `CHANNEL_WIDGET`
/// （`com.daanser.transprism/widget_action`）一致。
///
/// 职责边界：
/// - 只做「请求原生刷新」与「请求 pin 到主屏幕」两件事；
/// - **不碰任何用药数据** —— 打卡仍走既有的
///   `MedicationService.executeMedicationDose()`，小组件展示侧只读
///   `FlutterSharedPreferences`。
///
/// 非 Android 平台（iOS/macOS/Windows/Web）调用会静默降级：
/// 没有原生实现时 `MissingPluginException` 被吞掉，不影响 App 其他功能。
class MedsWidgetService {
  MedsWidgetService._();

  static const MethodChannel _channel =
      MethodChannel('com.daanser.transprism/widget_action');

  /// 小组件尺寸标识（与原生 `MainActivity.SIZE_MEDIUM / SIZE_SMALL` 对齐）
  static const String sizeMedium = 'medium';
  static const String sizeSmall = 'small';

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// 请求原生重渲染桌面上**所有**用药小组件实例（幂等，无实例时静默返回）。
  ///
  /// 两个调用时机：
  /// 1. 打卡成功后（`_recordDoseFromWidget`）—— 今日 n/4、该行时间、近 7 天点一起更新；
  /// 2. **主题偏好变化后**（`ThemeService.setThemeMode`）—— 小组件取色绑定的是
  ///    App 内的 light/dark/system 偏好，改了必须重渲染才能换 token。
  static Future<void> refresh() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('refreshWidgets');
    } on MissingPluginException {      // 该平台没有原生实现，忽略
    } catch (e) {
      debugPrint('⚠️ [TP-Widget] 刷新小组件失败(非致命): $e');
    }
  }

  /// 本机是否支持系统级「pin 到主屏幕」。
  ///
  /// Android 8.0（API 26）起提供 `AppWidgetManager.requestPinAppWidget`，
  /// 但最终取决于 Launcher 是否实现（`isRequestPinAppWidgetSupported`）。
  /// 返回 false 时应退化为「长按桌面 → 小组件 → TP」的文字说明。
  static Future<bool> canPin() async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('canPinMedsWidget') ?? false;
    } on MissingPluginException {
      return false;
    } catch (e) {
      debugPrint('⚠️ [TP-Widget] 查询 pin 能力失败(非致命): $e');
      return false;
    }
  }

  /// 请求把指定尺寸的用药小组件 pin 到主屏幕。
  ///
  /// 系统会弹出「添加到主屏幕」确认框（**不跳系统设置页**）。
  /// 返回 true = 已发起请求；false = 本机不支持，调用方需给出降级说明。
  static Future<bool> pin({required String size}) async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'pinMedsWidget',
            <String, dynamic>{'size': size},
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } catch (e) {
      debugPrint('⚠️ [TP-Widget] pin 小组件失败: $e');
      return false;
    }
  }

  /// 读取小组件自检记录（卡片渲染时刻 / 被拉起次数 / 广播次数）。
  ///
  /// ## 为什么需要它
  ///
  /// 澎湃 OS 上排查「点小组件不弹应用」时反复卡在**分不清哪一段断了**：
  /// 卡片是旧的？点击没送达？还是 App 被拉起了但被拦？远程测试者没有 adb，
  /// 所以由原生把三个关键事实落盘（见 `MedsWidgetDiag`），这里读出来展示。
  ///
  /// 返回 null 表示非 Android 或读取失败（UI 侧应隐藏该块）。
  static Future<WidgetClickDiag?> clickDiag() async {
    if (!_isAndroid) return null;
    try {
      final raw = await _channel
          .invokeMethod<Map<Object?, Object?>>('getWidgetClickDiag');
      if (raw == null) return null;
      return WidgetClickDiag(
        renderAt: (raw['renderAt'] as num?)?.toInt() ?? 0,
        launchCount: (raw['launchCount'] as num?)?.toInt() ?? 0,
        launchAt: (raw['launchAt'] as num?)?.toInt() ?? 0,
        clickCount: (raw['clickCount'] as num?)?.toInt() ?? 0,
        clickAt: (raw['clickAt'] as num?)?.toInt() ?? 0,
        lastAction: raw['lastAction'] as String?,
        clickOk: raw['clickOk'] as bool? ?? false,
      );
    } on MissingPluginException {
      return null;
    } catch (e) {
      debugPrint('⚠️ [TP-Widget] 读取点击诊断失败(非致命): $e');
      return null;
    }
  }
}

/// 小组件自检结果，见 [`MedsWidgetService.clickDiag`]。
class WidgetClickDiag {
  /// **卡片最近一次渲染时刻**（epoch millis）；0 表示从未渲染。
  ///
  /// 用来排除「桌面上是旧卡片」——只要它是新的，就说明跑的是当前这版代码。
  final int renderAt;

  /// **App 被小组件拉起的次数**（终点指标）；0 表示点击从未真正拉起过 App
  final int launchCount;
  final int launchAt;

  /// 广播备用路径收到点击的次数（真机实测澎湃 OS 上恒为 0）
  final int clickCount;
  final int clickAt;

  /// 最近一次的语义动作
  final String? lastAction;

  /// 广播路径最近一次 `startActivity` 是否未抛异常
  final bool clickOk;

  const WidgetClickDiag({
    required this.renderAt,
    required this.launchCount,
    required this.launchAt,
    required this.clickCount,
    required this.clickAt,
    required this.lastAction,
    required this.clickOk,
  });

  DateTime? get renderTime =>
      renderAt > 0 ? DateTime.fromMillisecondsSinceEpoch(renderAt) : null;
  DateTime? get launchTime =>
      launchAt > 0 ? DateTime.fromMillisecondsSinceEpoch(launchAt) : null;

  /// 小组件点击是否真的拉起过 App
  bool get everLaunched => launchCount > 0;
}
