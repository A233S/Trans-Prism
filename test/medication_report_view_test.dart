import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trans_prism/models/drug_model.dart';
import 'package:trans_prism/models/medication_log.dart';
import 'package:trans_prism/models/medication_purchase.dart';
import 'package:trans_prism/utils/currency.dart';
import 'package:trans_prism/widgets/medication_report_view.dart';

/// 报告长图的验收测试：
/// 1. **3 模式 × 打码开关 = 6 种组合**都必须能正常构建（不出异常）；
/// 2. **打码后报告文本里绝不能出现任何原药名 / 剂量 / 部位**（隐私红线）；
/// 3. 打码必须**保留金额**（价格模式的核心价值）。
void main() {
  Drug makeDrug(String id, String name) {
    final d = Drug(
      id: id,
      name: name,
      currentStock: 20,
      dosage: 5,
      intervalValue: 7,
      intervalUnit: IntervalUnit.days,
    );
    d.doseUnit = 'mg';
    return d;
  }

  final drugs = <Drug>[
    makeDrug('d1', '戊酸雌二醇'),
    makeDrug('d2', '螺内酯'),
  ];

  final logs = <MedicationLog>[
    MedicationLog(
      id: 'l1',
      medicationId: 'd1',
      timestamp: DateTime(2025, 5, 30, 20),
      dosage: 5,
      injectionSite: '左臂',
    ),
    MedicationLog(
      id: 'l2',
      medicationId: 'd2',
      timestamp: DateTime(2025, 5, 28, 9),
      dosage: 2,
    ),
  ];

  // d1：30 元 / 28mg，剂量 5mg → 够 5.6 次 → 单次 30/5.6 = ¥5.36
  // d2：40 元 / 14片 → 够 14 次
  final purchases = <MedicationPurchase>[
    MedicationPurchase(
      id: 'p1',
      medicationId: 'd1',
      timestamp: DateTime(2025, 5, 1),
      stockAmount: 28,
      totalPrice: 30,
      specQuantity: 28,
      specUnit: 'mg',
      doses: 5.6,
    ),
    MedicationPurchase(
      id: 'p2',
      medicationId: 'd2',
      timestamp: DateTime(2025, 5, 2),
      stockAmount: 14,
      totalPrice: 40,
      specQuantity: 14,
      specUnit: '片',
      doses: 14,
    ),
  ];

  Future<void> pumpView(
    WidgetTester tester, {
    required ReportMode mode,
    required bool masked,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MedicationReportView(
              mode: mode,
              masked: masked,
              drugs: drugs,
              logs: logs,
              purchases: purchases,
              rangeStart: DateTime(2025, 3, 1),
              rangeEnd: DateTime(2025, 5, 30),
              currency: CurrencyFormat.cny,
              generatedAt: DateTime(2025, 5, 30, 21, 4),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// 收集当前树里所有非空 Text 文案（报告是纯文本结构，足以做隐私断言）
  String allText(WidgetTester tester) {
    return tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .where((s) => s.isNotEmpty)
        .join('\n');
  }

  group('6 种组合都能正常构建', () {
    for (final mode in ReportMode.values) {
      for (final masked in <bool>[false, true]) {
        testWidgets('$mode / masked=$masked', (tester) async {
          await pumpView(tester, mode: mode, masked: masked);
          expect(tester.takeException(), isNull);
          // 页眉恒定携带 App 名（决策：导出图必须带 logo + App 名）
          expect(allText(tester).contains('Trans Prism'), isTrue);
        });
      }
    }
  });

  group('三种模式的内容边界', () {
    testWidgets('仅记录 → 有「用药记录」，无「费用统计」', (tester) async {
      await pumpView(tester, mode: ReportMode.recordsOnly, masked: false);
      final text = allText(tester);
      expect(text.contains('用药记录'), isTrue);
      expect(text.contains('费用统计'), isFalse);
    });

    testWidgets('仅价格 → 有「费用统计」，无「用药记录」', (tester) async {
      await pumpView(tester, mode: ReportMode.pricesOnly, masked: false);
      final text = allText(tester);
      expect(text.contains('费用统计'), isTrue);
      expect(text.contains('用药记录'), isFalse);
    });

    testWidgets('价格+记录 → 两者都有', (tester) async {
      await pumpView(tester, mode: ReportMode.recordsAndPrices, masked: false);
      final text = allText(tester);
      expect(text.contains('用药记录'), isTrue);
      expect(text.contains('费用统计'), isTrue);
    });
  });

  group('打码（隐私红线）', () {
    testWidgets('打码后不含任何原药名 / 剂量 / 部位，但保留金额', (tester) async {
      await pumpView(tester, mode: ReportMode.recordsAndPrices, masked: true);
      final text = allText(tester);

      // 原药名绝不能出现
      expect(text.contains('戊酸雌二醇'), isFalse);
      expect(text.contains('螺内酯'), isFalse);
      // 注射部位必须隐藏
      expect(text.contains('左臂'), isFalse);
      // 剂量数值必须隐藏（保留「剂量」字样但值被抹掉）
      expect(text.contains('5.0 单位'), isFalse);
      expect(text.contains('2.0 单位'), isFalse);

      // 稳定映射为「药物 A / 药物 B」
      expect(text.contains('药物 A'), isTrue);
      expect(text.contains('药物 B'), isTrue);
      // 打码徽标
      expect(text.contains('已打码'), isTrue);

      // 金额保留（d1 单次 = 30 / 5.6 = ¥5.36）
      expect(text.contains('¥'), isTrue);
      expect(text.contains('¥5.36'), isTrue);
    });

    testWidgets('未打码时正常显示原药名与部位', (tester) async {
      await pumpView(tester, mode: ReportMode.recordsAndPrices, masked: false);
      final text = allText(tester);
      expect(text.contains('戊酸雌二醇'), isTrue);
      expect(text.contains('螺内酯'), isTrue);
      expect(text.contains('左臂'), isTrue);
      expect(text.contains('已打码'), isFalse);
    });

    testWidgets('药物顺序决定打码字母（稳定映射）', (tester) async {
      await pumpView(tester, mode: ReportMode.pricesOnly, masked: true);
      final text = allText(tester);
      // drugs 顺序是 [戊酸雌二醇, 螺内酯] → A, B
      final idxA = text.indexOf('药物 A');
      final idxB = text.indexOf('药物 B');
      expect(idxA, isNonNegative);
      expect(idxB, isNonNegative);
      expect(idxA, lessThan(idxB));
    });
  });

  group('费用口径回显', () {
    testWidgets('合计含「不含未设价格的 N 种」提示与月成本', (tester) async {
      await pumpView(tester, mode: ReportMode.pricesOnly, masked: false);
      final text = allText(tester);
      expect(text.contains('合计'), isTrue);
      expect(text.contains('月预计'), isTrue);
      // 两种药都有价格 → 不应出现「不含未设价格」提示
      expect(text.contains('不含未设价格的'), isFalse);
    });
  });
}
