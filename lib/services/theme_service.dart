import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'meds_widget_service.dart';

/// 主题模式偏好管理
///
/// 将用户的亮/暗/系统跟随主题选择持久化到 SharedPreferences。
///
/// 这份偏好同时是**桌面用药小组件的唯一深浅色来源**：
/// 原生侧 `MedsWidgetThemePrefs` 直读同一个 key（`flutter.theme_mode`），
/// 所以每次变更都要通知原生重渲染卡片，否则小组件会停在旧的一套 token 上。
class ThemeService extends ChangeNotifier {
  static const String _prefsKey = 'theme_mode';
  static const String _colorPrefsKey = 'theme_color';
  static const String _stylePrefsKey = 'theme_style';

  ThemeMode _themeMode = ThemeMode.system;
  Color _themeColor = const Color(0xFFF5A9B8); // 默认跨旗粉
  String _themeStyle = 'minimal'; // 默认简约风: 'minimal' | 'liquid'

  ThemeMode get themeMode => _themeMode;
  Color get themeColor => _themeColor;
  String get themeStyle => _themeStyle;

  /// 是否处于暗色模式（基于当前 themeMode 判断）
  bool get isDarkMode {
    if (_themeMode == ThemeMode.system) {
      final brightness =
          WidgetsBinding.instance.platformDispatcher.platformBrightness;
      return brightness == Brightness.dark;
    }
    return _themeMode == ThemeMode.dark;
  }

  /// 加载持久化的主题偏好
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getString(_prefsKey);
    if (savedMode != null) {
      _themeMode = _themeModeFromString(savedMode);
    }

    final savedColor = prefs.getInt(_colorPrefsKey);
    if (savedColor != null) {
      _themeColor = Color(savedColor);
    }

    final savedStyle = prefs.getString(_stylePrefsKey);
    if (savedStyle != null) {
      _themeStyle = savedStyle;
    }

    notifyListeners();
  }

  /// 设置主题模式并持久化
  ///
  /// 持久化完成后立即请求刷新桌面用药小组件 —— 小组件的 ColorProvider 绑定的
  /// 就是这份偏好（light / dark / system），不刷新就会与 App 内首页脱节。
  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, _themeModeToString(mode));

    await MedsWidgetService.refresh();
  }

  /// 设置主题色并持久化
  Future<void> setThemeColor(Color color) async {
    _themeColor = color;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_colorPrefsKey, color.value);
  }

  /// 设置主题风格并持久化
  Future<void> setThemeStyle(String style) async {
    _themeStyle = style;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_stylePrefsKey, style);
  }

  /// 切换亮/暗（如果当前是 system 则切换到亮）
  Future<void> toggle() async {
    if (_themeMode == ThemeMode.dark) {
      await setThemeMode(ThemeMode.light);
    } else {
      await setThemeMode(ThemeMode.dark);
    }
  }

  String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  ThemeMode _themeModeFromString(String value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }
}
