import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 国产 ROM 的私有权限适配 —— 目前只有小米 / 澎湃 OS 的「后台弹出界面」。
///
/// ## 为什么需要它
///
/// 小米把「后台弹出界面」做成了 **AppOps `op 10021`**（`OP_BACKGROUND_START_ACTIVITY`），
/// 且官方文档明确「**该权限默认为拒绝**」。它会拦掉「App 在后台时 `startActivity`」。
///
/// 桌面用药小组件的点击**正好走这条路径**：
/// ```
/// 点击 → PendingIntent → Glance 的中转 Activity → MainActivity
/// ```
/// 一旦被拦，表现就是「**卡片显示完全正常，但点了不弹应用**」——
/// 因为 RemoteViews 早就渲染好了，被拦掉的只是最后那一步 Activity 启动。
///
/// ## 为什么是反射
///
/// 该权限没有公开 API，只能：
/// - 用 `AppOpsManager.checkOpNoThrow(op = 10021, uid, pkg)` 反射查询是否已允许；
/// - 用 `miui.intent.action.APP_PERM_EDITOR` 跳到小米安全中心的权限页。
///
/// 检测不到（不同 MIUI 版本 op 号可能变动）时**一律按「未允许」处理** ——
/// 宁可多提示一次，也不要让用户卡在「点了没反应」且毫无解释的状态。
class OemPermissionService {
  static const MethodChannel _channel =
      MethodChannel('com.daanser.transprism/oem_permissions');

  static bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  /// 本机是否小米系（小米 / 红米 / POCO / 澎湃 OS）。
  ///
  /// 红米与 POCO 的 `MANUFACTURER` 仍是 `Xiaomi`，所以原生侧同时看了 `BRAND`。
  static Future<bool> isMiuiFamily() async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('isMiuiFamily') ?? false;
    } catch (e) {
      debugPrint('⚠️ [TP-OemPerm] isMiuiFamily 失败: $e');
      return false;
    }
  }

  /// 「后台弹出界面」是否已允许。非小米机型恒为 `true`（不适用）。
  static Future<bool> isBackgroundPopupAllowed() async {
    if (!_isAndroid) return true;
    try {
      return await _channel
              .invokeMethod<bool>('isBackgroundPopupAllowed') ??
          false;
    } catch (e) {
      debugPrint('⚠️ [TP-OemPerm] 检测「后台弹出界面」失败: $e');
      return false;
    }
  }

  /// 跳到小米安全中心的「后台弹出界面」权限页；失败时原生侧会退回系统「应用详情」页。
  static Future<bool> openBackgroundPopupSettings() async {
    if (!_isAndroid) return false;
    try {
      return await _channel
              .invokeMethod<bool>('openBackgroundPopupSettings') ??
          false;
    } catch (e) {
      debugPrint('⚠️ [TP-OemPerm] 跳转「后台弹出界面」失败: $e');
      return false;
    }
  }
}
