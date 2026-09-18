import 'dart:convert';

/// 单次补货的价格 / 规格记录
///
/// 与 [MedicationLog]（纯用法记录）**完全解耦**：
/// - 日志回答「什么时候用了几次」，本模型回答「这次买了多少、花了多少钱、够用几次」。
/// - 价格统计锚定在「**够用次数**」（[doses]）而不是任何度量单位，
///   因为全 app 的 `Drug.dosage` / `Drug.currentStock` 都是**无单位纯数字**。
///
/// 关键语义区分（硬规则）：
/// - `totalPrice == null` → 用户**没填**价格，该记录不参与均价；
/// - `totalPrice == 0`   → **合法价格**（赠药 / 免费），必须参与均价。
class MedicationPurchase {
  /// 唯一标识
  final String id;

  /// 对应的药物 ID
  final String medicationId;

  /// 补货时间
  final DateTime timestamp;

  /// 计入库存的补货数量（沿用现有「单位」语义，必填）
  final double stockAmount;

  /// 本次总花费；null = 用户未填价格
  final double? totalPrice;

  /// 规格数量，如 28 / 14 / 1
  final double? specQuantity;

  /// 规格单位，如 'mg' / '片' / '针'（自由文本，仅作标签）
  final String? specUnit;

  /// 折合「够用次数」← 加权平均的权重（Σ totalPrice / Σ doses）
  final double? doses;

  /// 备注（可选）
  final String? note;

  MedicationPurchase({
    required this.id,
    required this.medicationId,
    required this.timestamp,
    required this.stockAmount,
    this.totalPrice,
    this.specQuantity,
    this.specUnit,
    this.doses,
    this.note,
  });

  // ==================== 派生属性（不落库） ====================

  /// 是否构成一条有效价格记录
  ///
  /// 要求**同时**有价格且够用次数 > 0：
  /// `totalPrice == 0` 也算有效（赠药），只有 `null` 才是「未填」。
  bool get priced => totalPrice != null && (doses ?? 0) > 0;

  /// 派生（不落库）：每规格单位单价
  ///
  /// `specQuantity` 为 null 或 <= 0 时返回 null（无法定义单位单价）。
  double? get unitPrice {
    final qty = specQuantity;
    final price = totalPrice;
    if (price == null || qty == null || qty <= 0 || !qty.isFinite) {
      return null;
    }
    final v = price / qty;
    return v.isFinite ? v : null;
  }

  // ==================== JSON 序列化 ====================

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'medicationId': medicationId,
      'timestamp': timestamp.toIso8601String(),
      'stockAmount': stockAmount,
      if (totalPrice != null) 'totalPrice': totalPrice,
      if (specQuantity != null) 'specQuantity': specQuantity,
      if (specUnit != null) 'specUnit': specUnit,
      if (doses != null) 'doses': doses,
      if (note != null) 'note': note,
    };
  }

  /// 完全容错的反序列化：缺字段 / 脏数据 / 字符串数字都**不抛异常**
  factory MedicationPurchase.fromJson(Map<String, dynamic> json) {
    return MedicationPurchase(
      id: _asString(json['id']) ?? '',
      medicationId: _asString(json['medicationId']) ?? '',
      timestamp: _asTimestamp(json['timestamp']),
      stockAmount: _asDouble(json['stockAmount']) ?? 0.0,
      totalPrice: _asDouble(json['totalPrice']),
      specQuantity: _asDouble(json['specQuantity']),
      specUnit: _asString(json['specUnit']),
      doses: _asDouble(json['doses']),
      note: _asString(json['note']),
    );
  }

  /// 批量反序列化：非列表 / 非对象条目一律跳过，绝不抛异常
  static List<MedicationPurchase> listFromJson(String jsonStr) {
    final result = <MedicationPurchase>[];
    if (jsonStr.isEmpty) return result;
    dynamic decoded;
    try {
      decoded = jsonDecode(jsonStr);
    } catch (_) {
      return result;
    }
    if (decoded is! List) return result;
    for (final e in decoded) {
      if (e is Map) {
        result.add(MedicationPurchase.fromJson(Map<String, dynamic>.from(e)));
      }
    }
    return result;
  }

  static String listToJson(List<MedicationPurchase> purchases) {
    return jsonEncode(purchases.map((p) => p.toJson()).toList());
  }

  // ==================== 容错解析工具 ====================

  /// 数值统一 `as num?` → `toDouble()`；额外容忍字符串数字；非法 → null
  static double? _asDouble(dynamic raw) {
    if (raw is num) {
      final v = raw.toDouble();
      return v.isFinite ? v : null;
    }
    if (raw is String) {
      final v = double.tryParse(raw.trim());
      if (v != null && v.isFinite) return v;
    }
    return null;
  }

  /// 字符串字段容错：null 透传，非字符串则 toString()
  static String? _asString(dynamic raw) {
    if (raw == null) return null;
    if (raw is String) return raw;
    return raw.toString();
  }

  /// 时间戳容错：ISO 字符串 / 毫秒数；非法 → Unix epoch（保证排序稳定）
  static DateTime _asTimestamp(dynamic raw) {
    if (raw is String) {
      final parsed = DateTime.tryParse(raw.trim());
      if (parsed != null) return parsed;
    } else if (raw is int) {
      return DateTime.fromMillisecondsSinceEpoch(raw);
    } else if (raw is num) {
      return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  // ==================== 便捷方法 ====================

  /// 复制并修改；可空字段需用 `clearX` 标志位才能真正清空
  MedicationPurchase copyWith({
    String? id,
    String? medicationId,
    DateTime? timestamp,
    double? stockAmount,
    double? totalPrice,
    double? specQuantity,
    String? specUnit,
    double? doses,
    String? note,
    bool clearTotalPrice = false,
    bool clearSpecQuantity = false,
    bool clearSpecUnit = false,
    bool clearDoses = false,
    bool clearNote = false,
  }) {
    return MedicationPurchase(
      id: id ?? this.id,
      medicationId: medicationId ?? this.medicationId,
      timestamp: timestamp ?? this.timestamp,
      stockAmount: stockAmount ?? this.stockAmount,
      totalPrice: clearTotalPrice ? null : (totalPrice ?? this.totalPrice),
      specQuantity:
          clearSpecQuantity ? null : (specQuantity ?? this.specQuantity),
      specUnit: clearSpecUnit ? null : (specUnit ?? this.specUnit),
      doses: clearDoses ? null : (doses ?? this.doses),
      note: clearNote ? null : (note ?? this.note),
    );
  }
}
