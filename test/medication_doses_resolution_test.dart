import 'package:flutter_test/flutter_test.dart';
import 'package:trans_prism/models/drug_model.dart';
import 'package:trans_prism/services/medication_cost_service.dart';

/// 「够用次数」折算口径的测试。
///
/// 为什么单独测它：这段折算原本在**补货面板**与**添加药物表单**里各写了一份
/// （表单那份的药物还没落库，拿不到 `Drug`）。两处 UI 各写一份最容易悄悄跑偏，
/// 所以抽成 `MedicationCostService.resolveDosesFrom` 这个纯函数，由两处共用。
/// 本文件既锁住口径本身，也锁住"抽取重构没有改变原行为"。
void main() {
  Drug drug({
    String? doseUnit,
    double dosage = 5,
    Map<String, double>? conversions,
  }) {
    final d = Drug(
      id: 'd1',
      name: '戊酸雌二醇',
      currentStock: 20,
      dosage: dosage,
      intervalValue: 7,
      intervalUnit: IntervalUnit.days,
    );
    d.doseUnit = doseUnit;
    d.specConversions = conversions;
    return d;
  }

  group('resolveDosesFrom 基本口径', () {
    test('规格单位 == 剂量单位 → 隐式系数 1', () {
      expect(
        MedicationCostService.resolveDosesFrom(
          specQuantity: 28,
          specUnit: 'mg',
          doseUnit: 'mg',
          dosage: 5,
          specConversions: null,
        ),
        closeTo(5.6, 1e-9),
      );
    });

    test('规格单位为空 → 同样按隐式系数 1', () {
      expect(
        MedicationCostService.resolveDosesFrom(
          specQuantity: 28,
          specUnit: null,
          doseUnit: 'mg',
          dosage: 5,
          specConversions: null,
        ),
        closeTo(5.6, 1e-9),
      );
    });

    test('剂量单位为空且规格单位非空、无换算 → 未知（null）', () {
      expect(
        MedicationCostService.resolveDosesFrom(
          specQuantity: 28,
          specUnit: 'mg',
          doseUnit: null,
          dosage: 5,
          specConversions: null,
        ),
        isNull,
      );
    });

    test('换算表命中 → 数量 × 系数 ÷ 剂量', () {
      // 1 针 = 5 mg，每次 5 mg → 1 针够用 1 次
      expect(
        MedicationCostService.resolveDosesFrom(
          specQuantity: 1,
          specUnit: '针',
          doseUnit: 'mg',
          dosage: 5,
          specConversions: {'针': 5},
        ),
        closeTo(1.0, 1e-9),
      );
      // 14 片 × (1 片 = 5 mg) ÷ 5 mg = 14 次
      expect(
        MedicationCostService.resolveDosesFrom(
          specQuantity: 14,
          specUnit: '片',
          doseUnit: 'mg',
          dosage: 5,
          specConversions: {'片': 5},
        ),
        closeTo(14.0, 1e-9),
      );
    });

    test('未知规格单位 → null（交给 UI 去问用户「1 针 = ? mg」）', () {
      expect(
        MedicationCostService.resolveDosesFrom(
          specQuantity: 1,
          specUnit: '支',
          doseUnit: 'mg',
          dosage: 5,
          specConversions: {'针': 5},
        ),
        isNull,
      );
    });
  });

  group('resolveDosesFrom 非法输入防御（绝不返回 Infinity / NaN）', () {
    test('数量 <= 0 → null', () {
      for (final q in [0.0, -1.0]) {
        expect(
          MedicationCostService.resolveDosesFrom(
            specQuantity: q,
            specUnit: 'mg',
            doseUnit: 'mg',
            dosage: 5,
          ),
          isNull,
        );
      }
    });

    test('剂量 <= 0 → null', () {
      for (final d in [0.0, -5.0]) {
        expect(
          MedicationCostService.resolveDosesFrom(
            specQuantity: 28,
            specUnit: 'mg',
            doseUnit: 'mg',
            dosage: d,
          ),
          isNull,
        );
      }
    });

    test('数量 / 剂量为 NaN 或 Infinity → null', () {
      expect(
        MedicationCostService.resolveDosesFrom(
          specQuantity: double.nan,
          specUnit: 'mg',
          doseUnit: 'mg',
          dosage: 5,
        ),
        isNull,
      );
      expect(
        MedicationCostService.resolveDosesFrom(
          specQuantity: double.infinity,
          specUnit: 'mg',
          doseUnit: 'mg',
          dosage: 5,
        ),
        isNull,
      );
      expect(
        MedicationCostService.resolveDosesFrom(
          specQuantity: 28,
          specUnit: 'mg',
          doseUnit: 'mg',
          dosage: double.infinity,
        ),
        isNull,
      );
    });

    test('换算系数为 0 → 结果为 0（下游按「未定价」处理，不是 null）', () {
      // 这是既有约定：只有 c 为 null / 非有限才算「换算未知」。
      expect(
        MedicationCostService.resolveDosesFrom(
          specQuantity: 10,
          specUnit: '片',
          doseUnit: 'mg',
          dosage: 5,
          specConversions: {'片': 0},
        ),
        0.0,
      );
    });
  });

  group('两个录入口的实际场景（补货面板 / 添加药物表单）', () {
    test('场景一：1000 元 1 针，已配「1 针 = 5 mg」，每次 5 mg → 够 1 次', () {
      final doses = MedicationCostService.resolveDosesFrom(
        specQuantity: 1,
        specUnit: '针',
        doseUnit: 'mg',
        dosage: 5,
        specConversions: {'针': 5},
      );
      expect(doses, closeTo(1.0, 1e-9));
      // 单次 = 1000 ÷ 1 = ¥1000
      expect(1000 / doses!, closeTo(1000.0, 1e-9));
    });

    test('场景二：30 元 28 mg，剂量单位就是 mg → 够 5.6 次 → 单次 ¥5.36', () {
      final doses = MedicationCostService.resolveDosesFrom(
        specQuantity: 28,
        specUnit: 'mg',
        doseUnit: 'mg',
        dosage: 5,
        specConversions: null,
      );
      expect(doses, closeTo(5.6, 1e-9));
      expect(30 / doses!, closeTo(5.36, 0.005));
    });

    test('场景三（表单草稿）：剂量单位与换算表都刚在输入框里配好，尚未落库', () {
      // 表单里：剂量单位 = mg、规格换算 = {针: 5}、每次剂量 = 5
      final dosesFromForm = MedicationCostService.resolveDosesFrom(
        specQuantity: 2,
        specUnit: '针',
        doseUnit: 'mg',
        dosage: 5,
        specConversions: {'针': 5},
      );
      expect(dosesFromForm, closeTo(2.0, 1e-9));
    });
  });

  group('抽取重构的等价性（resolveDoses 必须与 resolveDosesFrom 完全一致）', () {
    test('对一大组输入，两个入口结果逐一相同', () {
      final cases = <({double qty, String? unit, Drug d})>[
        (qty: 1, unit: '针', d: drug(doseUnit: 'mg', conversions: {'针': 5})),
        (qty: 28, unit: 'mg', d: drug(doseUnit: 'mg', conversions: {'针': 5})),
        (qty: 14, unit: '片', d: drug(doseUnit: 'mg', conversions: {'片': 5})),
        (qty: 1, unit: '支', d: drug(doseUnit: 'mg', conversions: {'针': 5})),
        (qty: 28, unit: null, d: drug(doseUnit: 'mg')),
        (qty: 28, unit: 'mg', d: drug(doseUnit: null)),
        (qty: 0, unit: 'mg', d: drug(doseUnit: 'mg')),
        (qty: -3, unit: 'mg', d: drug(doseUnit: 'mg')),
        (qty: 28, unit: 'mg', d: drug(doseUnit: 'mg', dosage: 0)),
        (qty: 28, unit: 'mg', d: drug(doseUnit: 'mg', dosage: -1)),
        (qty: 10, unit: '片', d: drug(doseUnit: 'mg', conversions: {'片': 0})),
        (qty: 2.5, unit: 'mg', d: drug(doseUnit: 'mg', dosage: 1.25)),
      ];

      for (final c in cases) {
        final viaDrug = MedicationCostService.resolveDoses(
          specQuantity: c.qty,
          specUnit: c.unit,
          drug: c.d,
        );
        final viaFields = MedicationCostService.resolveDosesFrom(
          specQuantity: c.qty,
          specUnit: c.unit,
          doseUnit: c.d.doseUnit,
          dosage: c.d.dosage,
          specConversions: c.d.specConversions,
        );

        expect(
          viaDrug,
          viaFields,
          reason: '输入 qty=${c.qty} unit=${c.unit} '
              'doseUnit=${c.d.doseUnit} dosage=${c.d.dosage} '
              'conversions=${c.d.specConversions} 时两个入口结果不一致',
        );
      }
    });
  });
}
