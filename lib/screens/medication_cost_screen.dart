import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/medication_purchase.dart';
import '../services/medication_cost_service.dart';
import '../services/medication_service.dart';
import '../storage/medication_price_repository.dart';
import '../utils/currency.dart';
import '../widgets/loading_indicator.dart';

/// 用药成本详情页
///
/// 展示口径（详见 `docs/MED_PRICE_PLAN.md` §4.2 ④）：
/// - 顶部合计：累计花费 / 月预计 / 剩余库存估值；
/// - 每药物：单次使用费用（平均）、平均单价、累计、月成本、库存估值、补货历史；
/// - 底部：累计支出趋势（`fl_chart`）。
///
/// **硬规则**：判断「未设价格」一律用 `DrugCost.costPerDose == null`，
/// **绝不能用 `spent == 0`** —— 赠药（`totalPrice == 0`）是合法价格，
/// 其 `spent` 同样是 `0.0`，但它**已定价**。
class MedicationCostScreen extends StatefulWidget {
  const MedicationCostScreen({super.key});

  @override
  State<MedicationCostScreen> createState() => _MedicationCostScreenState();
}

class _MedicationCostScreenState extends State<MedicationCostScreen> {
  bool _loading = true;
  List<MedicationPurchase> _purchases = [];
  MedicationCostSummary? _summary;
  Currency _currency = CurrencyFormat.cny;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final drugs = await MedicationService.loadAllDrugs();
    final purchases = await MedicationPriceRepository().getAll();
    final currency = await CurrencyFormat.current();
    if (!mounted) return;
    setState(() {
      _purchases = purchases;
      _currency = currency;
      _summary = MedicationCostService.summarize(drugs, purchases);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor =
        isDark ? const Color(0xFFEDEDF0) : const Color(0xFF333333);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '💰 用药成本',
          style: TextStyle(fontWeight: FontWeight.w800, color: textColor),
        ),
      ),
      body: _loading
          ? const LoadingIndicator()
          : RefreshIndicator(onRefresh: _load, child: _buildBody(isDark)),
    );
  }

  Widget _buildBody(bool isDark) {
    final summary = _summary;
    if (summary == null) {
      return const Center(child: Text('暂无数据'));
    }

    final children = <Widget>[
      _buildTotalsCard(isDark, summary),
      const SizedBox(height: 20),
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(
          '分药明细 (${summary.drugs.length})',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: isDark ? const Color(0xFFEDEDF0) : const Color(0xFF333333),
          ),
        ),
      ),
    ];

    for (final cost in summary.drugs) {
      children.add(_buildDrugCard(isDark, cost));
      children.add(const SizedBox(height: 12));
    }

    final series = MedicationCostService.cumulativeSeries(_purchases);
    if (series.length >= 2) {
      children.add(const SizedBox(height: 8));
      children.add(_buildTrendCard(isDark, series));
    }

    children.add(const SizedBox(height: 32));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: children,
    );
  }

  // ──────────────────────────────────────────────
  // 顶部合计
  // ──────────────────────────────────────────────

  Widget _buildTotalsCard(bool isDark, MedicationCostSummary summary) {
    final textColor =
        isDark ? const Color(0xFFEDEDF0) : const Color(0xFF333333);
    final secondary =
        isDark ? const Color(0xFF8E8E96) : const Color(0xFF8A8A86);

    // 完全没有价格记录时给出引导，而不是显示一堆 ¥0.00
    if (summary.pricedDrugCount == 0) {
      return _card(
        isDark,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '还没有价格记录',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '在「补货」时填写这次买药花了多少钱（也可以只填规格），\n'
              '就能算出每次用药的平均花费。留空则不计入统计。',
              style: TextStyle(fontSize: 12, height: 1.6, color: secondary),
            ),
          ],
        ),
      );
    }

    return _card(
      isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('累计花费',
              style: TextStyle(fontSize: 13, color: secondary)),
          const SizedBox(height: 4),
          Text(
            CurrencyFormat.format(summary.totalSpent, _currency),
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: textColor,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 16),
          Divider(
            height: 1,
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _miniStat(
                  '月预计',
                  CurrencyFormat.format(summary.totalMonthlyCost, _currency),
                  textColor,
                  secondary,
                ),
              ),
              Expanded(
                child: _miniStat(
                  '剩余库存估值',
                  CurrencyFormat.format(summary.totalStockValue, _currency),
                  textColor,
                  secondary,
                ),
              ),
            ],
          ),
          if (summary.unpricedDrugCount > 0) ...[
            const SizedBox(height: 12),
            Text(
              '不含未设价格的 ${summary.unpricedDrugCount} 种药物',
              style: TextStyle(fontSize: 11, color: secondary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _miniStat(
      String label, String value, Color textColor, Color secondary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: secondary)),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: textColor,
          ),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────
  // 单药卡片
  // ──────────────────────────────────────────────

  Widget _buildDrugCard(bool isDark, DrugCost cost) {
    final textColor =
        isDark ? const Color(0xFFEDEDF0) : const Color(0xFF333333);
    final secondary =
        isDark ? const Color(0xFF8E8E96) : const Color(0xFF8A8A86);
    final priced = cost.costPerDose != null;

    final history = _purchases
        .where((p) => p.medicationId == cost.drugId)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return _card(
      isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  cost.drugName,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: textColor,
                  ),
                ),
              ),
              if (!priced)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '未设价格',
                    style: TextStyle(fontSize: 10, color: secondary),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _miniStat(
                  '单次花费',
                  CurrencyFormat.format(cost.costPerDose, _currency),
                  textColor,
                  secondary,
                ),
              ),
              Expanded(
                child: _miniStat(
                  '平均单价',
                  currencyUnitText(cost.avgUnitPrice, _currency, cost.specUnit),
                  textColor,
                  secondary,
                ),
              ),
              Expanded(
                child: _miniStat(
                  '累计',
                  CurrencyFormat.format(cost.spent, _currency),
                  textColor,
                  secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _miniStat(
                  '月预计',
                  CurrencyFormat.format(cost.monthlyCost, _currency),
                  textColor,
                  secondary,
                ),
              ),
              Expanded(
                child: _miniStat(
                  '剩余库存估值',
                  CurrencyFormat.format(cost.stockValue, _currency),
                  textColor,
                  secondary,
                ),
              ),
            ],
          ),
          if (history.isNotEmpty) ...[
            const SizedBox(height: 12),
            Divider(
              height: 1,
              color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
            ),
            const SizedBox(height: 10),
            Text(
              '补货历史 (${history.length})',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: secondary,
              ),
            ),
            const SizedBox(height: 6),
            for (final p in history.take(8))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Text(
                      _formatDate(p.timestamp),
                      style: TextStyle(fontSize: 11, color: secondary),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _specText(p),
                        style: TextStyle(fontSize: 11, color: secondary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      p.totalPrice == null
                          ? '未填价格'
                          : CurrencyFormat.format(p.totalPrice, _currency),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: p.totalPrice == null
                            ? secondary
                            : textColor,
                      ),
                    ),
                  ],
                ),
              ),
            if (history.length > 8)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '… 另有 ${history.length - 8} 条',
                  style: TextStyle(fontSize: 10, color: secondary),
                ),
              ),
          ],
        ],
      ),
    );
  }

  String _specText(MedicationPurchase p) {
    final qty = p.specQuantity;
    if (qty == null) {
      return '${p.stockAmount.toStringAsFixed(1)} 单位';
    }
    final qtyText = qty == qty.roundToDouble()
        ? qty.toInt().toString()
        : qty.toStringAsFixed(2);
    final unit = p.specUnit;
    final base = unit == null ? qtyText : '$qtyText $unit';
    final doses = p.doses;
    if (doses == null) return base;
    final dosesText = doses == doses.roundToDouble()
        ? doses.toInt().toString()
        : doses.toStringAsFixed(2);
    return '$base · 够 $dosesText 次';
  }

  static String _formatDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  // ──────────────────────────────────────────────
  // 累计支出趋势
  // ──────────────────────────────────────────────

  Widget _buildTrendCard(bool isDark, List<CumulativePoint> series) {
    final secondary =
        isDark ? const Color(0xFF8E8E96) : const Color(0xFF8A8A86);
    final spots = <FlSpot>[];
    for (var i = 0; i < series.length; i++) {
      spots.add(FlSpot(i.toDouble(), series[i].cumulative));
    }

    return _card(
      isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '累计支出',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isDark ? const Color(0xFFEDEDF0) : const Color(0xFF333333),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 120,
            child: LineChart(
              LineChartData(
                minY: 0,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: const FlTitlesData(show: false),
                lineTouchData: const LineTouchData(enabled: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: false,
                    barWidth: 2,
                    color: const Color(0xFFF5A9B8),
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: const Color(0xFFF5A9B8).withOpacity(0.12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '按补货时间累计；未填价格的补货不构成支出事件，不产生数据点。',
            style: TextStyle(fontSize: 11, color: secondary),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────

  Widget _card(bool isDark, {required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF24242C) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.04),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// 金额 + 单位（如 `¥1.07 / mg`）；金额为 null → `—`
String currencyUnitText(double? amount, Currency currency, String? unit) {
  if (amount == null) return CurrencyFormat.emptyPlaceholder;
  return CurrencyFormat.formatWithUnit(amount, currency, unit);
}
