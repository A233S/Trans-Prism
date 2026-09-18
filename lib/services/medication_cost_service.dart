import '../models/drug_model.dart';
import '../models/medication_purchase.dart';

/// 单个药物的成本汇总（纯派生数据，不落库）
class DrugCost {
  /// 药物 ID
  final String drugId;

  /// 药物名称
  final String drugName;

  /// 平均单次使用费用；null = 未定价（UI 一律显示「—」）
  final double? costPerDose;

  /// 平均每规格单位单价（如 ¥/mg，仅「仅价格」报告用）
  final double? avgUnitPrice;

  /// 展示用单位（取最近一条有价格的记录的 specUnit）
  final String? specUnit;

  /// 该药累计花费（Σ totalPrice，含 doses<=0 的脏数据记录）
  final double? spent;

  /// 有价格的记录数（priced == true 的条数）
  final int pricedCount;

  /// 每日使用次数（固定间隔 = 24/间隔小时；离散 = 提醒点个数）
  final double? dosesPerDay;

  /// 月预计花费 = costPerDose × dosesPerDay × 30；未定价 / dosage<=0 → null
  final double? monthlyCost;

  /// 剩余可用次数 = currentStock / dosage；dosage<=0 → null
  final double? remainingDoses;

  /// 库存估值 = costPerDose × remainingDoses；未定价 → null
  final double? stockValue;

  const DrugCost({
    required this.drugId,
    required this.drugName,
    required this.costPerDose,
    required this.avgUnitPrice,
    required this.specUnit,
    required this.spent,
    required this.pricedCount,
    required this.dosesPerDay,
    required this.monthlyCost,
    required this.remainingDoses,
    required this.stockValue,
  });

  /// 是否已定价（UI 判断「—」与合计是否纳入）
  bool get priced => costPerDose != null;

  @override
  String toString() {
    return 'DrugCost($drugName, costPerDose=$costPerDose, '
        'monthly=$monthlyCost, stockValue=$stockValue, priced=$pricedCount)';
  }
}

/// 成本总览（成本详情页 / 汇总卡 / 导出报告用）
class MedicationCostSummary {
  /// 每种药物的成本（顺序与传入的 drugs 一致）
  final List<DrugCost> drugs;

  /// 全部记录累计花费
  final double totalSpent;

  /// 月预计合计（**仅累加已定价药物**）
  final double totalMonthlyCost;

  /// 库存估值合计（**仅累加已定价药物**）
  final double totalStockValue;

  /// 已定价药物数
  final int pricedDrugCount;

  /// 未定价药物数（UI 必须显式标注「不含未设价格的 N 种」）
  final int unpricedDrugCount;

  const MedicationCostSummary({
    required this.drugs,
    required this.totalSpent,
    required this.totalMonthlyCost,
    required this.totalStockValue,
    required this.pricedDrugCount,
    required this.unpricedDrugCount,
  });

  @override
  String toString() {
    return 'MedicationCostSummary(drugs=${drugs.length}, '
        'totalSpent=$totalSpent, totalMonthly=$totalMonthlyCost, '
        'totalStock=$totalStockValue, priced=$pricedDrugCount, '
        'unpriced=$unpricedDrugCount)';
  }
}

/// 累计支出序列中的一个点（趋势图用）
class CumulativePoint {
  /// 该点对应的时间
  final DateTime time;

  /// 截至该时间的累计支出
  final double cumulative;

  const CumulativePoint(this.time, this.cumulative);

  @override
  String toString() => 'CumulativePoint($time, $cumulative)';
}

/// 用药成本统计服务（**纯函数**，无 IO，可单测）
///
/// 核心口径（§3.1）：**以「次」为锚**
/// ```
/// 每次使用费用（平均） = Σ totalPrice / Σ doses
/// ```
/// 之所以锚定「够用次数」而不是任何单位：本 app 的 `dosage` / `currentStock`
/// 都是**无单位纯数字**，只有「够几次」这一口径既不依赖单位、又能让总额自洽。
///
/// 硬规则：
/// 1. 未定价药物 → [DrugCost.costPerDose] == null，且**不计入任何合计**；
/// 2. `totalPrice == 0` 是合法价格（赠药），参与平均；只有 `null` 才是「未填」；
/// 3. `doses <= 0` 的记录不参与均价，但**仍计入** `spent`（钱确实花了）；
/// 4. `dosage <= 0` → [DrugCost.remainingDoses] / [DrugCost.monthlyCost] 为 null，
///    **绝不产生 Infinity / NaN**。
class MedicationCostService {
  MedicationCostService._(); // 私有构造，纯静态服务

  // ──────────────────────────────────────────────
  // 主指标
  // ──────────────────────────────────────────────

  /// 主指标：`Σ totalPrice / Σ doses`
  ///
  /// 仅统计 [MedicationPurchase.priced] == true 的记录
  /// （即 totalPrice 非 null **且** doses > 0）。
  /// 无任何有效记录 → 返回 **null**（不是 0）。
  static double? avgCostPerDose(List<MedicationPurchase> purchases) {
    double sumPrice = 0;
    double sumDoses = 0;
    for (final p in purchases) {
      if (!p.priced) continue;
      sumPrice += p.totalPrice!;
      sumDoses += p.doses!;
    }
    if (sumDoses <= 0 || !sumDoses.isFinite) return null;
    final v = sumPrice / sumDoses;
    return v.isFinite ? v : null;
  }

  /// `Σ totalPrice / Σ specQuantity`（仅 specQuantity > 0 且有价格的记录）
  ///
  /// 无有效记录 → null。仅供「仅价格」报告的单价行使用。
  static double? avgUnitPrice(List<MedicationPurchase> purchases) {
    double sumPrice = 0;
    double sumQty = 0;
    for (final p in purchases) {
      final price = p.totalPrice;
      final qty = p.specQuantity;
      if (price == null || qty == null || qty <= 0 || !qty.isFinite) continue;
      sumPrice += price;
      sumQty += qty;
    }
    if (sumQty <= 0 || !sumQty.isFinite) return null;
    final v = sumPrice / sumQty;
    return v.isFinite ? v : null;
  }

  /// 累计花费：`Σ totalPrice`
  ///
  /// **包含** `doses <= 0` 的脏数据记录 —— 钱确实花了，只是算不出均价。
  static double totalSpent(List<MedicationPurchase> purchases) {
    double sum = 0;
    for (final p in purchases) {
      final price = p.totalPrice;
      if (price != null && price.isFinite) sum += price;
    }
    return sum.isFinite ? sum : 0;
  }

  // ──────────────────────────────────────────────
  // 药物维度
  // ──────────────────────────────────────────────

  /// 每日使用次数
  ///
  /// - 离散模式（[Drug.isDiscreteMode]）：`dailyReminderTimes.length`
  /// - 固定间隔：`24 / 间隔小时`（口径对齐 `Drug.dailyBurnRate`）
  /// - 非法间隔（<= 0）→ 返回 0（绝不返回 Infinity / NaN）
  static double dosesPerDay(Drug drug) {
    if (drug.isDiscreteMode) {
      return drug.dailyReminderTimes.length.toDouble();
    }
    final hours = _intervalInHours(drug);
    if (!hours.isFinite || hours <= 0) return 0;
    final v = 24.0 / hours;
    return v.isFinite ? v : 0;
  }

  /// 剩余可用次数 = `currentStock / dosage`
  ///
  /// `dosage <= 0` → null（绝不产生 Infinity / NaN）。
  static double? remainingDoses(Drug drug) {
    final dosage = drug.dosage;
    if (!dosage.isFinite || dosage <= 0) return null;
    final v = drug.currentStock / dosage;
    return v.isFinite ? v : null;
  }

  /// 折算「够用次数」的**唯一口径**（纯函数，UI 与单测共用）
  ///
  /// ```
  /// c = (specUnit == null || specUnit == doseUnit) ? 1.0
  ///                                               : specConversions?[specUnit]
  /// 够用次数 = specQuantity × c ÷ dosage
  /// ```
  ///
  /// 与 [resolveDoses] 的唯一区别是：这里直接接收字段而不是一个 [Drug]，
  /// 因此**尚未落库的表单草稿**（药物还在编辑中、剂量单位与换算表只存在于
  /// 输入框里）也能用同一套口径折算 —— 补货面板与「添加药物」表单都走这里，
  /// 避免两处 UI 各写一份而悄悄产生口径分歧。
  ///
  /// - `c == null`（**换算未知**）→ 返回 null，由 UI 决定要不要就地问用户；
  /// - `specQuantity <= 0` / `dosage <= 0` → null；
  /// - 结果非有限 → null（绝不返回 Infinity / NaN）。
  static double? resolveDosesFrom({
    required double specQuantity,
    required String? specUnit,
    required String? doseUnit,
    required double dosage,
    Map<String, double>? specConversions,
  }) {
    if (!specQuantity.isFinite || specQuantity <= 0) return null;
    if (!dosage.isFinite || dosage <= 0) return null;

    final double? c;
    if (specUnit == null || specUnit == doseUnit) {
      // 规格单位与「每次剂量」单位一致（或未指定）→ 隐式换算系数 1
      c = 1.0;
    } else {
      c = specConversions?[specUnit];
    }
    if (c == null || !c.isFinite) return null;

    final v = specQuantity * c / dosage;
    return v.isFinite ? v : null;
  }

  /// 折算「够用次数」（D9 自动折算：药物级剂量单位 + 规格换算表）
  ///
  /// 规则见 [resolveDosesFrom]（本方法只是把 [Drug] 的字段拆出来委托过去）。
  static double? resolveDoses({
    required double specQuantity,
    required String? specUnit,
    required Drug drug,
  }) {
    return resolveDosesFrom(
      specQuantity: specQuantity,
      specUnit: specUnit,
      doseUnit: drug.doseUnit,
      dosage: drug.dosage,
      specConversions: drug.specConversions,
    );
  }

  // ──────────────────────────────────────────────
  // 汇总
  // ──────────────────────────────────────────────

  /// 汇总单个药物的成本
  ///
  /// [purchases] 可传该药的全部记录（[MedicationPriceRepository.getForDrug]）
  /// 或全部记录 —— 内部会按 `medicationId == drug.id` 过滤。
  static DrugCost forDrug(Drug drug, List<MedicationPurchase> purchases) {
    final scoped =
        purchases.where((p) => p.medicationId == drug.id).toList(growable: false);

    final costPerDose = avgCostPerDose(scoped);
    final avgUnit = avgUnitPrice(scoped);
    final remaining = remainingDoses(drug);

    double? monthlyCost;
    if (costPerDose != null && drug.dosage > 0) {
      final v = costPerDose * dosesPerDay(drug) * 30;
      if (v.isFinite) monthlyCost = v;
    }

    double? stockValue;
    if (costPerDose != null && remaining != null) {
      final v = costPerDose * remaining;
      if (v.isFinite) stockValue = v;
    }

    return DrugCost(
      drugId: drug.id,
      drugName: drug.name,
      costPerDose: costPerDose,
      avgUnitPrice: avgUnit,
      specUnit: _latestSpecUnit(scoped),
      spent: totalSpent(scoped),
      pricedCount: scoped.where((p) => p.priced).length,
      dosesPerDay: dosesPerDay(drug),
      monthlyCost: monthlyCost,
      remainingDoses: remaining,
      stockValue: stockValue,
    );
  }

  /// 汇总全部药物
  ///
  /// - [totalMonthlyCost] / [totalStockValue] **仅累加已定价药物**；
  /// - [unpricedDrugCount] 供 UI 显式标注「不含未设价格的 N 种」；
  /// - [totalSpent] 为**全部**价格记录之和（`Σ totalPrice`）。
  static MedicationCostSummary summarize(
    List<Drug> drugs,
    List<MedicationPurchase> purchases,
  ) {
    final byDrug = <String, List<MedicationPurchase>>{};
    for (final p in purchases) {
      byDrug.putIfAbsent(p.medicationId, () => <MedicationPurchase>[]).add(p);
    }

    final costs = drugs
        .map((d) => forDrug(d, byDrug[d.id] ?? const <MedicationPurchase>[]))
        .toList();

    double totalMonthly = 0;
    double totalStock = 0;
    int pricedDrugs = 0;
    for (final c in costs) {
      if (c.costPerDose != null) pricedDrugs++;
      if (c.monthlyCost != null) totalMonthly += c.monthlyCost!;
      if (c.stockValue != null) totalStock += c.stockValue!;
    }

    return MedicationCostSummary(
      drugs: costs,
      totalSpent: totalSpent(purchases),
      totalMonthlyCost: totalMonthly.isFinite ? totalMonthly : 0,
      totalStockValue: totalStock.isFinite ? totalStock : 0,
      pricedDrugCount: pricedDrugs,
      unpricedDrugCount: drugs.length - pricedDrugs,
    );
  }

  // ──────────────────────────────────────────────
  // 趋势
  // ──────────────────────────────────────────────

  /// 累计支出序列（按 timestamp **升序**累加 totalPrice），供趋势图
  ///
  /// 只有**填了价格**（`totalPrice != null`）的记录才产生一个点：
  /// 未填价格的补货不构成支出事件，不会制造无意义的水平段。
  static List<CumulativePoint> cumulativeSeries(
    List<MedicationPurchase> purchases,
  ) {
    final sorted = purchases
        .where((p) => p.totalPrice != null && p.totalPrice!.isFinite)
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final points = <CumulativePoint>[];
    double running = 0;
    for (final p in sorted) {
      running += p.totalPrice!;
      points.add(CumulativePoint(p.timestamp, running));
    }
    return points;
  }

  // ──────────────────────────────────────────────
  // 内部工具
  // ──────────────────────────────────────────────

  /// 间隔折合小时数（口径对齐 `Drug._intervalInHours`）
  static double _intervalInHours(Drug drug) {
    final value = drug.intervalValue;
    if (!value.isFinite || value <= 0) return 0;
    switch (drug.intervalUnit) {
      case IntervalUnit.hours:
        return value.toDouble();
      case IntervalUnit.days:
        return value * 24.0;
      case IntervalUnit.weeks:
        return value * 7 * 24.0;
      case IntervalUnit.months:
        return value * 30 * 24.0;
    }
  }

  /// 展示用规格单位：取**最近一条有价格且带单位**的记录的 specUnit
  static String? _latestSpecUnit(List<MedicationPurchase> purchases) {
    final withUnit = purchases
        .where((p) =>
            p.totalPrice != null &&
            p.specUnit != null &&
            p.specUnit!.trim().isNotEmpty)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return withUnit.isEmpty ? null : withUnit.first.specUnit;
  }
}
