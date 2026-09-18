import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 币种定义（**纯显示层**，不含任何汇率信息）
///
/// 本 app 只存金额数字，币种仅决定「符号 + 小数位」的呈现方式。
/// 切换币种 **不换算任何数值**（§3.8 D5）。
class Currency {
  /// 币种代码，如 'CNY'
  final String code;

  /// 显示符号，如 '¥'
  final String symbol;

  /// 中文名称，如 '人民币'
  final String label;

  /// 小数位数（JPY / KRW 为 0）
  final int decimals;

  const Currency(this.code, this.symbol, this.label, this.decimals);

  /// 以 code 判等，便于 `expect(await current(), CurrencyFormat.cny)`
  @override
  bool operator ==(Object other) => other is Currency && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => 'Currency($code, $symbol, $decimals)';
}

/// 币种读写与金额格式化
///
/// 存储位置：SharedPreferences key "cost_currency_code"（只存 code）
class CurrencyFormat {
  CurrencyFormat._(); // 私有构造，纯静态工具

  /// 默认币种
  static const Currency cny = Currency('CNY', '¥', '人民币', 2);

  /// 预设币种（顺序即选择器展示顺序）
  static const List<Currency> _presets = [
    cny,
    Currency('USD', r'$', '美元', 2),
    Currency('EUR', '€', '欧元', 2),
    Currency('GBP', '£', '英镑', 2),
    // 用 JP¥ 与 CNY 的 ¥ 区分，避免同日元/人民币混淆
    Currency('JPY', 'JP¥', '日元', 0),
    Currency('HKD', r'HK$', '港币', 2),
    Currency('TWD', r'NT$', '新台币', 2),
    Currency('KRW', '₩', '韩元', 0),
  ];

  /// 预设币种列表
  static List<Currency> get presets => _presets;

  /// SharedPreferences 存储键
  static const String storageKey = 'cost_currency_code';

  /// 未定价金额的占位符（UI 与报告统一口径）
  static const String emptyPlaceholder = '—';

  // ──────────────────────────────────────────────
  // 持久化
  // ──────────────────────────────────────────────

  /// 读取当前币种；缺失 / 非法 / 读取异常 → 回退 [cny]
  static Future<Currency> current() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return byCode(prefs.getString(storageKey));
    } catch (e) {
      debugPrint('💰 [TP-Cost] 读取币种失败，回退 CNY: $e');
      return cny;
    }
  }

  /// 按 code 查找币种（大小写不敏感）；找不到 / 传 null → 回退 [cny]
  static Future<Currency> byCode(String? code) async {
    if (code == null) return cny;
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) return cny;
    for (final c in _presets) {
      if (c.code == normalized) return c;
    }
    debugPrint('💰 [TP-Cost] 未知币种 code="$code"，回退 CNY');
    return cny;
  }

  /// 保存当前币种（只存 code）
  static Future<void> set(Currency c) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, c.code);
    debugPrint('💰 [TP-Cost] 币种已设置为 ${c.code}');
  }

  // ──────────────────────────────────────────────
  // 格式化
  // ──────────────────────────────────────────────

  /// 金额格式化
  ///
  /// - `null` → [emptyPlaceholder]（`—`），与「0 元（赠药）」严格区分；
  /// - 千分位分隔 + 按 [Currency.decimals] 定小数位；
  /// - 负数正常显示（`-¥1,234.50`）；
  /// - 非有限值（NaN / Infinity）按 `—` 处理，避免脏数据进入 UI。
  static String format(double? amount, Currency c) {
    if (amount == null || !amount.isFinite) return emptyPlaceholder;

    final decimals = c.decimals < 0 ? 0 : c.decimals;
    final negative = amount < 0;
    final fixed = amount.abs().toStringAsFixed(decimals);

    final dot = fixed.indexOf('.');
    final intPart = dot == -1 ? fixed : fixed.substring(0, dot);
    final decPart = dot == -1 ? '' : fixed.substring(dot + 1);

    final grouped = StringBuffer();
    for (var i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) grouped.write(',');
      grouped.write(intPart[i]);
    }

    final sb = StringBuffer();
    if (negative) sb.write('-');
    sb.write(c.symbol);
    sb.write(grouped.toString());
    if (decimals > 0) {
      sb.write('.');
      sb.write(decPart);
    }
    return sb.toString();
  }

  /// 带单位金额：`¥1,000.00 / 针`；[unit] 为空则等同 [format]
  ///
  /// 未定价（`null` / 非有限值）时只返回占位符 `—`，不拼接单位，
  /// 避免出现 `— / 针` 这种半截文案。
  static String formatWithUnit(double? amount, Currency c, String? unit) {
    if (amount == null || !amount.isFinite) return emptyPlaceholder;
    final base = format(amount, c);
    final u = unit?.trim();
    if (u == null || u.isEmpty) return base;
    return '$base / $u';
  }
}
