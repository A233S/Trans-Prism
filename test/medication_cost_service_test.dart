import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trans_prism/models/drug_model.dart';
import 'package:trans_prism/models/medication_purchase.dart';
import 'package:trans_prism/services/medication_cost_service.dart';
import 'package:trans_prism/services/medication_service.dart';
import 'package:trans_prism/storage/medication_price_repository.dart';
import 'package:trans_prism/utils/currency.dart';

// ──────────────────────────────────────────────
// 测试辅助
// ──────────────────────────────────────────────

Drug _drug({
  String id = 'm1',
  String name = '戊酸雌二醇',
  double stock = 12,
  double dosage = 5,
  int intervalValue = 12,
  IntervalUnit intervalUnit = IntervalUnit.hours,
  List<String> times = const [],
  String? doseUnit,
  Map<String, double>? specConversions,
}) {
  return Drug(
    id: id,
    name: name,
    currentStock: stock,
    dosage: dosage,
    intervalValue: intervalValue,
    intervalUnit: intervalUnit,
    dailyReminderTimes: List<String>.from(times),
    doseUnit: doseUnit,
    specConversions: specConversions,
  );
}

MedicationPurchase _p({
  String id = 'p1',
  String medId = 'm1',
  DateTime? ts,
  double stockAmount = 1,
  double? totalPrice,
  double? specQuantity,
  String? specUnit,
  double? doses,
  String? note,
}) {
  return MedicationPurchase(
    id: id,
    medicationId: medId,
    timestamp: ts ?? DateTime(2025, 1, 1),
    stockAmount: stockAmount,
    totalPrice: totalPrice,
    specQuantity: specQuantity,
    specUnit: specUnit,
    doses: doses,
    note: note,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ===========================================================================
  // 主指标：按「次」加权
  // ===========================================================================
  group('avgCostPerDose 按够用次数加权', () {
    test('¥100/10次 + ¥80/5次 → ¥12.00/次（不是 ¥13.00 的算术平均）', () {
      final purchases = [
        _p(id: 'a', totalPrice: 100, doses: 10, specQuantity: 10, specUnit: '片'),
        _p(id: 'b', totalPrice: 80, doses: 5, specQuantity: 5, specUnit: '片'),
      ];

      final avg = MedicationCostService.avgCostPerDose(purchases);

      // 加权：(100 + 80) / (10 + 5) = 12.00
      expect(avg, isNotNull);
      expect(avg, closeTo(12.00, 1e-9));
      // 算术平均（每单价的均值）是 (10 + 16) / 2 = 13.00，必须不等于它
      expect(avg, isNot(closeTo(13.00, 1e-6)));
      expect(CurrencyFormat.format(avg, CurrencyFormat.cny), '¥12.00');
    });

    test('30元 / 14片（14 次）→ ¥2.14/次', () {
      final avg = MedicationCostService.avgCostPerDose([
        _p(totalPrice: 30, doses: 14, specQuantity: 14, specUnit: '片'),
      ]);

      expect(avg, closeTo(2.14, 0.01));
      expect(CurrencyFormat.format(avg, CurrencyFormat.cny), '¥2.14');
    });

    test('1000元 / 1针（1 次）→ ¥1,000.00/次', () {
      final avg = MedicationCostService.avgCostPerDose([
        _p(totalPrice: 1000, doses: 1, specQuantity: 1, specUnit: '针'),
      ]);

      expect(avg, closeTo(1000.0, 1e-9));
      expect(CurrencyFormat.format(avg, CurrencyFormat.cny), '¥1,000.00');
    });

    test('30元 / 28mg（5.6 次）→ ¥5.36/次（§5.3 可复算样例）', () {
      final drug = _drug(doseUnit: 'mg', dosage: 5);
      final doses = MedicationCostService.resolveDoses(
        specQuantity: 28,
        specUnit: 'mg',
        drug: drug,
      );
      expect(doses, closeTo(5.6, 1e-9));

      final avg = MedicationCostService.avgCostPerDose([
        _p(totalPrice: 30, specQuantity: 28, specUnit: 'mg', doses: doses),
      ]);
      expect(avg, closeTo(5.36, 0.01));
    });
  });

  // ===========================================================================
  // 换算表（D9 自动折算）
  // ===========================================================================
  group('resolveDoses 换算表折算', () {
    test('1针 + {针:5} + dosage 5 → 1.0 次', () {
      final drug = _drug(doseUnit: 'mg', dosage: 5, specConversions: {'针': 5});
      expect(
        MedicationCostService.resolveDoses(
            specQuantity: 1, specUnit: '针', drug: drug),
        closeTo(1.0, 1e-9),
      );
    });

    test('28mg + 隐式 c=1 + dosage 5 → 5.6 次', () {
      final drug = _drug(doseUnit: 'mg', dosage: 5, specConversions: {'针': 5});
      expect(
        MedicationCostService.resolveDoses(
            specQuantity: 28, specUnit: 'mg', drug: drug),
        closeTo(5.6, 1e-9),
      );
    });

    test('14片 + {片:5} + dosage 5 → 14.0 次', () {
      final drug = _drug(doseUnit: 'mg', dosage: 5, specConversions: {'片': 5});
      expect(
        MedicationCostService.resolveDoses(
            specQuantity: 14, specUnit: '片', drug: drug),
        closeTo(14.0, 1e-9),
      );
    });

    test('未知规格单位 → null（交给 UI 去问用户）', () {
      final drug = _drug(doseUnit: 'mg', dosage: 5, specConversions: {'针': 5});
      expect(
        MedicationCostService.resolveDoses(
            specQuantity: 1, specUnit: '支', drug: drug),
        isNull,
      );
    });

    test('specUnit 为 null → 隐式 c=1', () {
      final drug = _drug(doseUnit: 'mg', dosage: 5);
      expect(
        MedicationCostService.resolveDoses(
            specQuantity: 28, specUnit: null, drug: drug),
        closeTo(5.6, 1e-9),
      );
    });

    test('非法输入（dosage<=0 / 数量<=0）→ null', () {
      final bad = _drug(doseUnit: 'mg', dosage: 0);
      expect(
        MedicationCostService.resolveDoses(
            specQuantity: 1, specUnit: 'mg', drug: bad),
        isNull,
      );

      final ok = _drug(doseUnit: 'mg', dosage: 5);
      expect(
        MedicationCostService.resolveDoses(
            specQuantity: 0, specUnit: 'mg', drug: ok),
        isNull,
      );
      expect(
        MedicationCostService.resolveDoses(
            specQuantity: -1, specUnit: 'mg', drug: ok),
        isNull,
      );
    });
  });

  // ===========================================================================
  // 缺失值 / 零值语义
  // ===========================================================================
  group('缺失与零值语义', () {
    test('混合缺失：1 条 null + 1 条 priced → 只按有效那条算', () {
      final purchases = [
        _p(id: 'unpriced', totalPrice: null, specQuantity: 14, doses: 14),
        _p(id: 'priced', totalPrice: 40, specQuantity: 10, doses: 10),
      ];

      expect(MedicationCostService.avgCostPerDose(purchases), closeTo(4.0, 1e-9));
      // 未填价格的那条不贡献金额
      expect(MedicationCostService.totalSpent(purchases), closeTo(40.0, 1e-9));
    });

    test('全部缺失 → null（不是 0）', () {
      final purchases = [
        _p(id: 'a', totalPrice: null, specQuantity: 14, doses: 14),
        _p(id: 'b', totalPrice: null),
      ];

      final avg = MedicationCostService.avgCostPerDose(purchases);
      expect(avg, isNull);
      expect(avg, isNot(equals(0.0)));
      expect(MedicationCostService.totalSpent(purchases), 0.0);

      expect(MedicationCostService.avgCostPerDose(const []), isNull);
    });

    test('totalPrice == 0 是合法价格（赠药）→ 均价 0.0，与「未设价格」区分', () {
      final free = [_p(totalPrice: 0, doses: 14, specQuantity: 14)];
      final avg = MedicationCostService.avgCostPerDose(free);
      expect(avg, isNotNull);
      expect(avg, equals(0.0));
      expect(CurrencyFormat.format(avg, CurrencyFormat.cny), '¥0.00');
      expect(free.single.priced, isTrue);
    });

    test('doses <= 0 不参与均价，但钱仍计入 spent', () {
      final purchases = [
        _p(id: 'valid', totalPrice: 100, doses: 10, specQuantity: 10),
        // 脏数据：有价格但折算次数为 0
        _p(id: 'dirty0', totalPrice: 50, doses: 0, specQuantity: 5),
        _p(id: 'dirtyN', totalPrice: 25, doses: -3, specQuantity: 5),
        _p(id: 'noDoses', totalPrice: 10, specQuantity: 5),
      ];

      // 均价只按 valid 算：100 / 10 = 10.0（50 / 0 / 25 / 10 都不参与）
      expect(MedicationCostService.avgCostPerDose(purchases), closeTo(10.0, 1e-9));
      // 但累计花费包含全部（钱确实花了）：100 + 50 + 25 + 10
      expect(MedicationCostService.totalSpent(purchases), closeTo(185.0, 1e-9));
      expect(purchases[1].priced, isFalse);
      expect(purchases[2].priced, isFalse);
      expect(purchases[3].priced, isFalse);
    });
  });

  // ===========================================================================
  // dosage <= 0 防御（绝不产生 Infinity / NaN）
  // ===========================================================================
  group('dosage <= 0 防御', () {
    test('remainingDoses / monthlyCost / stockValue 为 null，且无 Infinity/NaN', () {
      final drug = _drug(dosage: 0, stock: 12);
      final purchases = [_p(totalPrice: 1000, doses: 1, specQuantity: 1, specUnit: '针')];

      final cost = MedicationCostService.forDrug(drug, purchases);

      // 均价本身仍然可算（与 dosage 无关）
      expect(cost.costPerDose, closeTo(1000.0, 1e-9));
      expect(MedicationCostService.remainingDoses(drug), isNull);
      expect(cost.remainingDoses, isNull);
      expect(cost.monthlyCost, isNull);
      expect(cost.stockValue, isNull);

      expect(cost.dosesPerDay, isNotNull);
      expect(cost.dosesPerDay!.isFinite, isTrue);
      expect(cost.costPerDose!.isFinite, isTrue);
    });

    test('非法间隔（intervalValue = 0）→ dosesPerDay = 0，月成本有限', () {
      final drug = _drug(intervalValue: 0, dosage: 5);
      final purchases = [_p(totalPrice: 100, doses: 10, specQuantity: 10)];

      expect(MedicationCostService.dosesPerDay(drug), 0.0);

      final cost = MedicationCostService.forDrug(drug, purchases);
      expect(cost.monthlyCost, isNotNull);
      expect(cost.monthlyCost!.isFinite, isTrue);
      expect(cost.monthlyCost, 0.0);
      expect(cost.stockValue, isNotNull);
      expect(cost.stockValue!.isFinite, isTrue);
    });
  });

  // ===========================================================================
  // forDrug：月成本 / 库存估值
  // ===========================================================================
  group('forDrug 派生指标', () {
    test('monthlyCost = costPerDose × dosesPerDay × 30；stockValue = costPerDose × 剩余次数', () {
      // 12 小时间隔 → 每天 2 次；dosage 5；库存 12 → 剩余 2.4 次
      final drug = _drug(stock: 12, dosage: 5, intervalValue: 12);
      final purchases = [_p(totalPrice: 100, doses: 10, specQuantity: 10)];

      final cost = MedicationCostService.forDrug(drug, purchases);

      expect(MedicationCostService.dosesPerDay(drug), closeTo(2.0, 1e-9));
      expect(cost.costPerDose, closeTo(10.0, 1e-9));
      expect(cost.remainingDoses, closeTo(2.4, 1e-9));
      expect(cost.monthlyCost, closeTo(10.0 * 2.0 * 30, 1e-9));
      expect(cost.stockValue, closeTo(10.0 * 2.4, 1e-9));
      expect(cost.spent, closeTo(100.0, 1e-9));
      expect(cost.pricedCount, 1);
    });

    test('离散模式：dosesPerDay = dailyReminderTimes.length', () {
      final drug = _drug(
        stock: 18,
        dosage: 5,
        times: ['08:00', '20:00'],
        doseUnit: 'mg',
      );
      final purchases = [
        _p(
          totalPrice: 30,
          specQuantity: 28,
          specUnit: 'mg',
          doses: 5.6,
        ),
      ];

      final cost = MedicationCostService.forDrug(drug, purchases);

      expect(MedicationCostService.dosesPerDay(drug), 2.0);
      expect(cost.costPerDose, closeTo(5.36, 0.01));
      expect(cost.remainingDoses, closeTo(3.6, 1e-9));
      // 精确公式：cpd(30/5.6) × 2 次/天 × 30 天
      expect(cost.monthlyCost, closeTo(30 / 5.6 * 2 * 30, 1e-6));
      expect(cost.stockValue, closeTo(30 / 5.6 * 3.6, 1e-6));
    });

    test('§5.3 可复算样例：每 7 天一次 → 月 ¥22.96、库存估值 ¥19.29', () {
      final drug = _drug(
        stock: 18,
        dosage: 5,
        intervalValue: 7,
        intervalUnit: IntervalUnit.days,
        doseUnit: 'mg',
      );
      final purchases = [
        _p(totalPrice: 30, specQuantity: 28, specUnit: 'mg', doses: 5.6),
      ];

      final cost = MedicationCostService.forDrug(drug, purchases);

      expect(MedicationCostService.dosesPerDay(drug), closeTo(1 / 7, 1e-9));
      expect(CurrencyFormat.format(cost.costPerDose, CurrencyFormat.cny), '¥5.36');
      expect(CurrencyFormat.format(cost.monthlyCost, CurrencyFormat.cny), '¥22.96');
      expect(CurrencyFormat.format(cost.stockValue, CurrencyFormat.cny), '¥19.29');
      expect(CurrencyFormat.format(cost.spent, CurrencyFormat.cny), '¥30.00');
      // 均价 = 30 / 28 = ¥1.07/mg
      expect(CurrencyFormat.format(cost.avgUnitPrice, CurrencyFormat.cny), '¥1.07');
      expect(cost.specUnit, 'mg');
    });

    test('specUnit 取最近一条有价格记录的规格单位', () {
      final drug = _drug();
      final purchases = [
        _p(
          id: 'old',
          ts: DateTime(2025, 1, 1),
          totalPrice: 100,
          doses: 10,
          specQuantity: 10,
          specUnit: '片',
        ),
        _p(
          id: 'new',
          ts: DateTime(2025, 3, 1),
          totalPrice: 200,
          doses: 10,
          specQuantity: 10,
          specUnit: '针',
        ),
      ];

      expect(MedicationCostService.forDrug(drug, purchases).specUnit, '针');
    });
  });

  // ===========================================================================
  // summarize
  // ===========================================================================
  group('summarize 汇总', () {
    test('未定价药物不计入任何合计', () {
      final drugs = [
        _drug(id: 'm1', name: '已定价药', stock: 12, dosage: 5, intervalValue: 12),
        _drug(id: 'm2', name: '未定价药', stock: 5, dosage: 1, intervalValue: 24),
      ];
      final purchases = [
        _p(medId: 'm1', totalPrice: 100, doses: 10, specQuantity: 10),
        // m2 有记录但未填价格
        _p(id: 'p2', medId: 'm2', totalPrice: null, specQuantity: 5, doses: 5),
      ];

      final summary = MedicationCostService.summarize(drugs, purchases);

      expect(summary.drugs.length, 2);
      expect(summary.pricedDrugCount, 1);
      expect(summary.unpricedDrugCount, 1);

      final unpriced = summary.drugs[1];
      expect(unpriced.costPerDose, isNull);
      expect(unpriced.monthlyCost, isNull);
      expect(unpriced.stockValue, isNull);
      expect(unpriced.spent, 0.0);
      expect(unpriced.pricedCount, 0);

      // 合计只含 m1：cpd=10, dpd=2 → 月 600；剩余 12/5=2.4 → 估值 24
      expect(summary.totalMonthlyCost, closeTo(600.0, 1e-9));
      expect(summary.totalStockValue, closeTo(24.0, 1e-9));
      // 总花费仍是全部记录的 Σ totalPrice
      expect(summary.totalSpent, closeTo(100.0, 1e-9));
    });

    test('全部未定价 → 合计为 0、pricedDrugCount = 0', () {
      final drugs = [_drug(id: 'm1'), _drug(id: 'm2')];
      final summary = MedicationCostService.summarize(drugs, const []);

      expect(summary.totalMonthlyCost, 0.0);
      expect(summary.totalStockValue, 0.0);
      expect(summary.totalSpent, 0.0);
      expect(summary.pricedDrugCount, 0);
      expect(summary.unpricedDrugCount, 2);
    });

    test('forDrug 按 medicationId 过滤（可传全部记录）', () {
      final drug = _drug(id: 'm1');
      final purchases = [
        _p(id: 'a', medId: 'm1', totalPrice: 100, doses: 10, specQuantity: 10),
        _p(id: 'b', medId: 'm2', totalPrice: 9999, doses: 1, specQuantity: 1),
      ];

      final cost = MedicationCostService.forDrug(drug, purchases);
      expect(cost.costPerDose, closeTo(10.0, 1e-9));
      expect(cost.spent, closeTo(100.0, 1e-9));
      expect(cost.pricedCount, 1);

      // 完全不属于该药的记录 → 未定价
      final other = MedicationCostService.forDrug(
          _drug(id: 'm3'), purchases);
      expect(other.costPerDose, isNull);
    });
  });

  // ===========================================================================
  // cumulativeSeries
  // ===========================================================================
  group('cumulativeSeries 累计支出序列', () {
    test('按 timestamp 升序累加，跳过未填价格的记录', () {
      final purchases = [
        _p(id: 'c', ts: DateTime(2025, 3, 1), totalPrice: 50, doses: 5),
        _p(id: 'a', ts: DateTime(2025, 1, 1), totalPrice: 100, doses: 10),
        _p(id: 'skip', ts: DateTime(2025, 2, 1), totalPrice: null, doses: 5),
        _p(id: 'b', ts: DateTime(2025, 4, 1), totalPrice: 0, doses: 5),
      ];

      final series = MedicationCostService.cumulativeSeries(purchases);

      // 未填价格的那条不产生点（它不是支出事件）
      expect(series.length, 3);
      expect(series[0].time, DateTime(2025, 1, 1));
      expect(series[0].cumulative, closeTo(100.0, 1e-9));
      expect(series[1].time, DateTime(2025, 3, 1));
      expect(series[1].cumulative, closeTo(150.0, 1e-9));
      expect(series[2].time, DateTime(2025, 4, 1));
      expect(series[2].cumulative, closeTo(150.0, 1e-9));
    });

    test('空列表 → 空序列', () {
      expect(MedicationCostService.cumulativeSeries(const []), isEmpty);
    });
  });

  // ===========================================================================
  // MedicationPurchase 序列化与容错
  // ===========================================================================
  group('MedicationPurchase JSON', () {
    test('空 map / 缺字段不抛异常', () {
      late MedicationPurchase p;
      expect(() => p = MedicationPurchase.fromJson(const {}), returnsNormally);
      expect(p.id, '');
      expect(p.medicationId, '');
      expect(p.stockAmount, 0.0);
      expect(p.totalPrice, isNull);
      expect(p.specQuantity, isNull);
      expect(p.specUnit, isNull);
      expect(p.doses, isNull);
      expect(p.note, isNull);
      expect(p.priced, isFalse);
      expect(p.unitPrice, isNull);
      expect(p.timestamp, DateTime.fromMillisecondsSinceEpoch(0));
    });

    test('字符串数字 / 脏类型容错', () {
      final p = MedicationPurchase.fromJson(const {
        'id': 'p1',
        'medicationId': 'm1',
        'timestamp': '2025-01-02T03:04:05.000',
        'stockAmount': '12.5',
        'totalPrice': '1000',
        'specQuantity': '1',
        'specUnit': '针',
        'doses': '1',
        'note': 42,
      });

      expect(p.stockAmount, 12.5);
      expect(p.totalPrice, 1000.0);
      expect(p.specQuantity, 1.0);
      expect(p.specUnit, '针');
      expect(p.doses, 1.0);
      expect(p.note, '42');
      expect(p.timestamp, DateTime(2025, 1, 2, 3, 4, 5));
      expect(p.priced, isTrue);
      expect(p.unitPrice, closeTo(1000.0, 1e-9));
    });

    test('非法数值 → null，不抛异常', () {
      final p = MedicationPurchase.fromJson(const {
        'id': 'p1',
        'stockAmount': 'abc',
        'totalPrice': 'abc',
        'specQuantity': 'x',
        'doses': [],
        'timestamp': 'not-a-date',
        'specUnit': 3,
      });

      expect(p.stockAmount, 0.0);
      expect(p.totalPrice, isNull);
      expect(p.specQuantity, isNull);
      expect(p.doses, isNull);
      expect(p.specUnit, '3');
      expect(p.timestamp, DateTime.fromMillisecondsSinceEpoch(0));
    });

    test('unitPrice 在 specQuantity <= 0 / null 时为 null', () {
      expect(_p(totalPrice: 100, specQuantity: 0).unitPrice, isNull);
      expect(_p(totalPrice: 100, specQuantity: -5).unitPrice, isNull);
      expect(_p(totalPrice: 100).unitPrice, isNull);
      expect(_p(totalPrice: null, specQuantity: 10).unitPrice, isNull);
      expect(_p(totalPrice: 100, specQuantity: 4).unitPrice, closeTo(25.0, 1e-9));
    });

    test('priced 语义：0 元有效、null / doses<=0 无效', () {
      expect(_p(totalPrice: 0, doses: 1).priced, isTrue);
      expect(_p(totalPrice: null, doses: 5).priced, isFalse);
      expect(_p(totalPrice: 100, doses: 0).priced, isFalse);
      expect(_p(totalPrice: 100).priced, isFalse);
    });

    test('toJson / fromJson 往返稳定，可空字段非 null 才写入', () {
      final p = _p(
        id: 'p1',
        medId: 'm1',
        ts: DateTime(2025, 5, 30, 21, 4),
        stockAmount: 28,
        totalPrice: 30,
        specQuantity: 28,
        specUnit: 'mg',
        doses: 5.6,
        note: '药店促销',
      );

      final json = p.toJson();
      final back = MedicationPurchase.fromJson(json);

      expect(back.id, p.id);
      expect(back.medicationId, p.medicationId);
      expect(back.timestamp, p.timestamp);
      expect(back.stockAmount, p.stockAmount);
      expect(back.totalPrice, p.totalPrice);
      expect(back.specQuantity, p.specQuantity);
      expect(back.specUnit, p.specUnit);
      expect(back.doses, p.doses);
      expect(back.note, p.note);

      // 未填价格的记录不应把 null 写成 key
      final bare = _p(totalPrice: null).toJson();
      expect(bare.containsKey('totalPrice'), isFalse);
      expect(bare.containsKey('doses'), isFalse);
      expect(bare.containsKey('specUnit'), isFalse);
      expect(bare.containsKey('note'), isFalse);
      // 必填字段始终存在
      expect(bare.containsKey('stockAmount'), isTrue);
      expect(bare.containsKey('timestamp'), isTrue);
    });

    test('listFromJson / listToJson 容错', () {
      expect(MedicationPurchase.listFromJson(''), isEmpty);
      expect(MedicationPurchase.listFromJson('not json'), isEmpty);
      expect(MedicationPurchase.listFromJson('{"a":1}'), isEmpty);
      // 列表里夹带非对象条目 → 跳过而不是抛异常
      expect(
        MedicationPurchase.listFromJson('[{"id":"a","stockAmount":1}, 5, "x"]')
            .length,
        1,
      );

      final list = [
        _p(id: 'a', totalPrice: 30, doses: 5.6, specQuantity: 28, specUnit: 'mg'),
        _p(id: 'b', totalPrice: null),
      ];
      final round = MedicationPurchase.listFromJson(
        MedicationPurchase.listToJson(list),
      );
      expect(round.length, 2);
      expect(round[0].id, 'a');
      expect(round[0].doses, 5.6);
      expect(round[1].totalPrice, isNull);
    });

    test('copyWith 支持 clearX 清空可空字段', () {
      final p = _p(
        totalPrice: 30,
        specQuantity: 28,
        specUnit: 'mg',
        doses: 5.6,
        note: 'n',
      );

      final cleared = p.copyWith(
        clearTotalPrice: true,
        clearDoses: true,
        clearSpecUnit: true,
        clearNote: true,
      );
      expect(cleared.totalPrice, isNull);
      expect(cleared.doses, isNull);
      expect(cleared.specUnit, isNull);
      expect(cleared.note, isNull);
      // 未指定的字段保持原值
      expect(cleared.specQuantity, 28.0);
      expect(cleared.priced, isFalse);

      final updated = p.copyWith(totalPrice: 45, clearSpecQuantity: true);
      expect(updated.totalPrice, 45.0);
      expect(updated.specQuantity, isNull);
    });
  });

  // ===========================================================================
  // MedicationPriceRepository（SharedPreferences）
  // ===========================================================================
  group('MedicationPriceRepository', () {
    late MedicationPriceRepository repo;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      repo = MedicationPriceRepository();
    });

    test('空存储 → 空列表', () async {
      expect(await repo.getAll(), isEmpty);
      expect(await repo.getForDrug('m1'), isEmpty);
    });

    test('add → getAll 保留记录并可往返', () async {
      await repo.add(_p(
        id: 'p1',
        medId: 'm1',
        stockAmount: 28,
        totalPrice: 30,
        specQuantity: 28,
        specUnit: 'mg',
        doses: 5.6,
      ));

      final all = await repo.getAll();
      expect(all.length, 1);
      expect(all.single.id, 'p1');
      expect(all.single.totalPrice, 30.0);
      expect(all.single.doses, 5.6);
      expect(all.single.specUnit, 'mg');
    });

    test('getForDrug 按 timestamp 升序过滤', () async {
      await repo.add(_p(id: 'late', medId: 'm1', ts: DateTime(2025, 3, 1)));
      await repo.add(_p(id: 'other', medId: 'm2', ts: DateTime(2025, 2, 1)));
      await repo.add(_p(id: 'early', medId: 'm1', ts: DateTime(2025, 1, 1)));

      final m1 = await repo.getForDrug('m1');
      expect(m1.map((p) => p.id).toList(), ['early', 'late']);
    });

    test('deleteByDrug 只删该药记录', () async {
      await repo.add(_p(id: 'a', medId: 'm1'));
      await repo.add(_p(id: 'b', medId: 'm2'));

      await repo.deleteByDrug('m1');

      final all = await repo.getAll();
      expect(all.length, 1);
      expect(all.single.id, 'b');
      // 无匹配时不报错
      await repo.deleteByDrug('nope');
      expect((await repo.getAll()).length, 1);
    });

    test('clearAll 清空', () async {
      await repo.add(_p(id: 'a', medId: 'm1'));
      await repo.clearAll();
      expect(await repo.getAll(), isEmpty);
    });

    test('存储键为 medication_purchase_records 且可被 SP 读取', () async {
      await repo.add(_p(id: 'a', medId: 'm1', totalPrice: 30, doses: 5.6));
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(MedicationPriceRepository.storageKey);
      expect(raw, isNotNull);
      expect(raw, contains('m1'));
    });

    test('存储内容损坏 → 空列表，不抛异常', () async {
      SharedPreferences.setMockInitialValues({
        MedicationPriceRepository.storageKey: '{{{ broken',
      });
      expect(await MedicationPriceRepository().getAll(), isEmpty);
    });
  });

  // ===========================================================================
  // MedicationService.upsertDrug
  // ===========================================================================
  group('MedicationService.upsertDrug', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('空存储 → 新增并持久化', () async {
      await MedicationService.upsertDrug(_drug(
        id: 'm1',
        name: '戊酸雌二醇',
        doseUnit: 'mg',
        specConversions: {'针': 5},
      ));

      final drugs = await MedicationService.loadAllDrugs();
      expect(drugs.length, 1);
      expect(drugs.single.id, 'm1');
      expect(drugs.single.doseUnit, 'mg');
      expect(drugs.single.specConversions, {'针': 5});
    });

    test('同 id → 覆盖而不是追加', () async {
      await MedicationService.upsertDrug(_drug(id: 'm1', doseUnit: 'mg'));
      await MedicationService.upsertDrug(_drug(
        id: 'm1',
        doseUnit: '片',
        specConversions: {'盒': 28},
      ));

      final drugs = await MedicationService.loadAllDrugs();
      expect(drugs.length, 1);
      expect(drugs.single.doseUnit, '片');
      expect(drugs.single.specConversions, {'盒': 28});
    });

    test('不破坏列表里的其它药物', () async {
      await MedicationService.upsertDrug(_drug(id: 'm1', name: 'A'));
      await MedicationService.upsertDrug(_drug(id: 'm2', name: 'B'));
      await MedicationService.upsertDrug(
          _drug(id: 'm1', name: 'A', specConversions: {'针': 5}));

      final drugs = await MedicationService.loadAllDrugs();
      expect(drugs.length, 2);
      expect(drugs.map((d) => d.id).toList(), ['m1', 'm2']);
      expect(drugs.first.specConversions, {'针': 5});
      expect(drugs.last.name, 'B');
    });
  });

  // ===========================================================================
  // Drug 老 JSON 回归（绝不允许破坏既有兼容性）
  // ===========================================================================
  group('Drug 老数据回归', () {
    // 手写一段「老版本」JSON：没有 doseUnit / specConversions
    const oldJson = <String, dynamic>{
      'id': 'd1',
      'name': '戊酸雌二醇',
      'currentStock': 12.5,
      'dosage': 5.0,
      'intervalValue': 7,
      'intervalUnit': 'days',
      'dailyReminderTimes': <String>[],
      'nextDoseTime': '2025-03-01T08:00:00.000',
      'reminderEnabled': false,
    };

    test('反序列化后逐字段与改动前一致', () {
      final drug = Drug.fromJson(oldJson);

      expect(drug.id, 'd1');
      expect(drug.name, '戊酸雌二醇');
      expect(drug.currentStock, 12.5);
      expect(drug.dosage, 5.0);
      expect(drug.intervalValue, 7);
      expect(drug.intervalUnit, IntervalUnit.days);
      expect(drug.dailyReminderTimes, isEmpty);
      expect(drug.nextDoseTime, DateTime(2025, 3, 1, 8));
      expect(drug.reminderEnabled, isFalse);
      expect(drug.isDiscreteMode, isFalse);

      // 新增字段在老数据上必须是 null
      expect(drug.doseUnit, isNull);
      expect(drug.specConversions, isNull);
    });

    test('toJson 对老数据不新增 key（往返稳定）', () {
      final drug = Drug.fromJson(oldJson);
      final json = drug.toJson();

      expect(json.containsKey('doseUnit'), isFalse);
      expect(json.containsKey('specConversions'), isFalse);
      expect(json.length, oldJson.length);

      // 往返后逐字段一致
      final again = Drug.fromJson(json);
      expect(again.id, drug.id);
      expect(again.name, drug.name);
      expect(again.currentStock, drug.currentStock);
      expect(again.dosage, drug.dosage);
      expect(again.intervalValue, drug.intervalValue);
      expect(again.intervalUnit, drug.intervalUnit);
      expect(again.dailyReminderTimes, drug.dailyReminderTimes);
      expect(again.nextDoseTime, drug.nextDoseTime);
      expect(again.reminderEnabled, drug.reminderEnabled);
      expect(again.doseUnit, isNull);
      expect(again.specConversions, isNull);

      // jsonEncode 也应该稳定
      expect(Drug.listToJson([again]), Drug.listToJson([drug]));
    });

    test('老数据的 listFromJson 正常', () {
      final list = Drug.listFromJson('[${jsonEncode(oldJson)}]');
      expect(list.length, 1);
      expect(list.single.doseUnit, isNull);
      expect(Drug.listToJson(list).contains('doseUnit'), isFalse);
    });
  });

  // ===========================================================================
  // Drug 新字段读写 + 容错 + copyWith
  // ===========================================================================
  group('Drug 新字段', () {
    test('toJson / fromJson 往返保留新字段', () {
      final drug = _drug(
        doseUnit: 'mg',
        specConversions: {'针': 5, '片': 0.5},
      );

      final json = drug.toJson();
      expect(json['doseUnit'], 'mg');
      expect(json['specConversions'], {'针': 5, '片': 0.5});

      final back = Drug.fromJson(json);
      expect(back.doseUnit, 'mg');
      expect(back.specConversions, {'针': 5, '片': 0.5});
      expect(Drug.listToJson([back]), Drug.listToJson([drug]));
    });

    test('fromJson 对脏数据类型完全容错', () {
      final drug = Drug.fromJson({
        ..._drugOldJson(),
        'doseUnit': 123,
        'specConversions': 'not-a-map',
      });
      expect(drug.doseUnit, isNull);
      expect(drug.specConversions, isNull);

      // 非法条目跳过，合法条目保留
      final mixed = Drug.fromJson({
        ..._drugOldJson(),
        'specConversions': {
          '针': 5,
          '片': '0.5',
          'bad': 'abc',
          'nil': null,
          'list': [1, 2],
          7: 3,
          '  ': 9,
        },
      });
      expect(mixed.specConversions, {'针': 5.0, '片': 0.5});

      // 空 Map 保留为空 Map（保证往返稳定）
      final empty = Drug.fromJson({
        ..._drugOldJson(),
        'specConversions': <String, dynamic>{},
      });
      expect(empty.specConversions, isEmpty);
      expect(empty.specConversions, isNotNull);

      // 空白字符串单位 → null
      final blank = Drug.fromJson({..._drugOldJson(), 'doseUnit': '   '});
      expect(blank.doseUnit, isNull);
    });

    test('copyWith 新增字段 + clearX 标志位', () {
      final drug = _drug(doseUnit: 'mg', specConversions: {'针': 5});

      // 不传 → 保持原值
      final same = drug.copyWith(name: '新名字');
      expect(same.doseUnit, 'mg');
      expect(same.specConversions, {'针': 5});
      expect(same.name, '新名字');

      // 修改
      final changed = drug.copyWith(
        doseUnit: '片',
        specConversions: {'盒': 28},
      );
      expect(changed.doseUnit, '片');
      expect(changed.specConversions, {'盒': 28});
      // copyWith 后仍是可变字段（后续可就地写换算表）
      changed.specConversions!['针'] = 5;
      expect(changed.specConversions, {'盒': 28, '针': 5});

      // 清空
      final cleared = drug.copyWith(
        clearDoseUnit: true,
        clearSpecConversions: true,
      );
      expect(cleared.doseUnit, isNull);
      expect(cleared.specConversions, isNull);
      expect(cleared.name, drug.name);
    });
  });
}

/// 最小可用的老版本 Drug JSON（无新字段）
Map<String, dynamic> _drugOldJson() {
  return <String, dynamic>{
    'id': 'd1',
    'name': '测试药',
    'currentStock': 10.0,
    'dosage': 2.0,
    'intervalValue': 12,
    'intervalUnit': 'hours',
    'dailyReminderTimes': <String>[],
    'nextDoseTime': null,
    'reminderEnabled': true,
  };
}
