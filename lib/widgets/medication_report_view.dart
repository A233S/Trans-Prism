import 'package:flutter/material.dart';

import '../models/drug_model.dart';
import '../models/medication_log.dart';
import '../models/medication_purchase.dart';
import '../services/medication_cost_service.dart';
import '../utils/currency.dart';

/// 报告内容模式（决策：三选一，每种都可叠加打码）
enum ReportMode {
  /// 仅记录：用药时间线 + 用量汇总
  recordsOnly,

  /// 仅价格：每药均价 / 单次 / 月 / 累计 / 库存估值 + 合计
  pricesOnly,

  /// 价格 + 记录：时间线每行带该次费用，并附价格合计
  recordsAndPrices,
}

/// 用药记录与费用报告（长图）
///
/// ⚠️ 这个 Widget 同时是**预览**与**导出的同一份实现**，杜绝「所见非所得」。
/// 因此它：
/// - **固定宽度 750**（导出图尺寸稳定，与设备屏幕宽度无关）；
/// - **不依赖 `Scaffold` / `AppBar` / 主题继承**，颜色全部显式写死（导出稳定）；
/// - 白底深字（导出图不应是深色主题）。
///
/// 打码（决策 D3）：药名 → 「药物 A / B / C」（**按 `drugs` 顺序稳定映射**，
/// 同一次导出内一致）；**剂量 / 注射部位 / 备注一律隐藏**；**金额保留**。
/// 打码映射集中在 [_buildMaskMap] 这个**单一出口**，便于测试断言。
class MedicationReportView extends StatelessWidget {
  final ReportMode mode;
  final bool masked;
  final List<Drug> drugs;
  final List<MedicationLog> logs;
  final List<MedicationPurchase> purchases;
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final Currency currency;
  final DateTime generatedAt;

  const MedicationReportView({
    super.key,
    required this.mode,
    required this.masked,
    required this.drugs,
    required this.logs,
    required this.purchases,
    required this.rangeStart,
    required this.rangeEnd,
    required this.currency,
    required this.generatedAt,
  });

  /// 导出图固定宽度
  static const double width = 750;

  // ── 打印安全色（不随主题变化）──
  static const Color _ink = Color(0xFF1F1F24);
  static const Color _muted = Color(0xFF7A7A82);
  static const Color _line = Color(0xFFE6E6EA);
  static const Color _accent = Color(0xFFF5A9B8);

  @override
  Widget build(BuildContext context) {
    final mask = _buildMaskMap();
    final costSummary = MedicationCostService.summarize(drugs, purchases);
    final nameById = {for (final d in drugs) d.id: d.name};
    final costByDrugId = {for (final c in costSummary.drugs) c.drugId: c};

    return Container(
      width: width,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(40, 36, 40, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 22),
          if (mode == ReportMode.recordsOnly ||
              mode == ReportMode.recordsAndPrices) ...[
            _buildRecordsSection(
              mask: mask,
              nameById: nameById,
              costByDrugId: costByDrugId,
              withCost: mode == ReportMode.recordsAndPrices,
            ),
            const SizedBox(height: 26),
          ],
          if (mode == ReportMode.pricesOnly ||
              mode == ReportMode.recordsAndPrices) ...[
            _buildPricesSection(costSummary, mask),
            const SizedBox(height: 26),
          ],
          _buildFooter(),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  // 打码：唯一出口
  // ──────────────────────────────────────────────

  /// 药名 → 「药物 X」的稳定映射（按 `drugs` 列表顺序）。
  ///
  /// 未打码时返回空表，调用方通过 [_displayName] 统一取名。
  Map<String, String> _buildMaskMap() {
    if (!masked) return const <String, String>{};
    final map = <String, String>{};
    var index = 0;
    for (final d in drugs) {
      final name = d.name;
      if (name.isEmpty || map.containsKey(name)) continue;
      map[name] = '药物 ${_letterLabel(index)}';
      index++;
    }
    return map;
  }

  static String _letterLabel(int i) {
    const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    if (i < letters.length) return letters[i];
    return '${letters[(i ~/ letters.length) - 1]}${letters[i % letters.length]}';
  }

  String _displayName(String? rawName, Map<String, String> mask) {
    if (rawName == null || rawName.isEmpty) return '未知药物';
    if (!masked) return rawName;
    // 药名可能已不在 drugs 列表（药物被删）→ 用占位而不是泄露原名
    return mask[rawName] ?? '药物 ?';
  }

  // ──────────────────────────────────────────────
  // 页眉 / 页脚
  // ──────────────────────────────────────────────

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 品牌 logo（与 App 内一致）
            SizedBox(
              width: 56,
              height: 56,
              child: Image.asset(
                'assets/logo_in.png',
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Trans Prism · 稳态光盒',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: _ink,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    mode == ReportMode.recordsOnly
                        ? '用药记录报告'
                        : (mode == ReportMode.pricesOnly
                            ? '用药费用报告'
                            : '用药记录与费用报告'),
                    style: const TextStyle(fontSize: 14, color: _muted),
                  ),
                ],
              ),
            ),
            if (masked)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _accent.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '⚠ 已打码',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFC98A98),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          '${_formatDate(rangeStart)} ~ ${_formatDate(rangeEnd)}'
          '　｜　生成于 ${_formatDateTime(generatedAt)}',
          style: const TextStyle(fontSize: 12, color: _muted),
        ),
        const SizedBox(height: 14),
        Container(height: 2, color: _accent),
      ],
    );
  }

  Widget _buildFooter() {
    final showCostNote = mode != ReportMode.recordsOnly;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(height: 1, color: _line),
        const SizedBox(height: 12),
        Text(
          '本图由 Trans Prism 本地生成，不包含任何身份信息，未上传网络。'
          '${showCostNote ? '费用按当前平均单价估算。' : ''}',
          style: const TextStyle(fontSize: 11, color: _muted, height: 1.6),
        ),
        const SizedBox(height: 4),
        const Text(
          '本内容仅用于个人记录，不构成任何医疗建议。',
          style: TextStyle(fontSize: 11, color: _muted, height: 1.6),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────
  // ① 用药记录
  // ──────────────────────────────────────────────

  Widget _buildRecordsSection({
    required Map<String, String> mask,
    required Map<String, String> nameById,
    required Map<String, DrugCost> costByDrugId,
    required bool withCost,
  }) {
    final sorted = List<MedicationLog>.from(logs)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    // 汇总
    final coveredDays = logs
        .map((l) => DateTime(l.timestamp.year, l.timestamp.month, l.timestamp.day))
        .toSet()
        .length;
    String intervalText = '—';
    if (sorted.length >= 2) {
      final newest = sorted.first.timestamp;
      final oldest = sorted.last.timestamp;
      final days = newest.difference(oldest).inHours / 24.0;
      if (days > 0) {
        intervalText = (days / (sorted.length - 1)).toStringAsFixed(1);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('用药记录'),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F7F9),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '用药 ${logs.length} 次　｜　覆盖 $coveredDays 天　｜　平均间隔 $intervalText 天',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _ink,
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (sorted.isEmpty)
          const Text('该时间范围内没有用药记录。',
              style: TextStyle(fontSize: 12, color: _muted))
        else
          for (final log in sorted)
            _buildLogRow(
              log: log,
              mask: mask,
              drugName: nameById[log.medicationId],
              cost: costByDrugId[log.medicationId],
              withCost: withCost,
            ),
      ],
    );
  }

  Widget _buildLogRow({
    required MedicationLog log,
    required Map<String, String> mask,
    required String? drugName,
    required DrugCost? cost,
    required bool withCost,
  }) {
    final name = _displayName(drugName, mask);
    // 打码时剂量与部位一律隐藏
    final doseText = masked ? '剂量 —' : '${log.dosage.toStringAsFixed(1)} 单位';
    final siteText = masked || log.injectionSite == null
        ? ''
        : ' · ${log.injectionSite}';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _line, width: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              _formatShortDateTime(log.timestamp),
              style: const TextStyle(fontSize: 12, color: _muted),
            ),
          ),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _ink,
              ),
            ),
          ),
          Expanded(
            child: Text(
              '$doseText$siteText',
              style: const TextStyle(fontSize: 12, color: _muted),
            ),
          ),
          if (withCost)
            SizedBox(
              width: 110,
              child: Text(
                cost?.costPerDose == null
                    ? CurrencyFormat.emptyPlaceholder
                    : CurrencyFormat.format(cost!.costPerDose, currency),
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: cost?.costPerDose == null ? _muted : _ink,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  // ② 价格
  // ──────────────────────────────────────────────

  Widget _buildPricesSection(
      MedicationCostSummary summary, Map<String, String> mask) {
    final priced = summary.drugs
        .where((c) => c.costPerDose != null)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('费用统计'),
        const SizedBox(height: 10),
        if (priced.isEmpty)
          const Text('该时间范围内没有填写过价格的药物。',
              style: TextStyle(fontSize: 12, color: _muted))
        else
          for (final c in priced) _buildPriceRow(c, mask),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F7F9),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '合计：累计花费 ${CurrencyFormat.format(summary.totalSpent, currency)}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '月预计 ${CurrencyFormat.format(summary.totalMonthlyCost, currency)}'
                '　｜　剩余库存估值 ${CurrencyFormat.format(summary.totalStockValue, currency)}',
                style: const TextStyle(fontSize: 12, color: _ink),
              ),
              if (summary.unpricedDrugCount > 0) ...[
                const SizedBox(height: 4),
                Text(
                  '* 不含未设价格的 ${summary.unpricedDrugCount} 种药物',
                  style: const TextStyle(fontSize: 11, color: _muted),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPriceRow(DrugCost c, Map<String, String> mask) {
    final unitText = c.avgUnitPrice == null
        ? CurrencyFormat.emptyPlaceholder
        : CurrencyFormat.formatWithUnit(c.avgUnitPrice, currency, c.specUnit);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _line, width: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _displayName(c.drugName, mask),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
              ),
              Text(
                '单次 ${CurrencyFormat.format(c.costPerDose, currency)}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFC98A98),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            '均价 $unitText　｜　月 ${CurrencyFormat.format(c.monthlyCost, currency)}'
            '　｜　累计 ${CurrencyFormat.format(c.spent, currency)}'
            '　｜　库存估值 ${CurrencyFormat.format(c.stockValue, currency)}',
            style: const TextStyle(fontSize: 11.5, color: _muted, height: 1.5),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────

  Widget _sectionTitle(String text) {
    return Row(
      children: [
        Container(width: 4, height: 16, color: _accent),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w900,
            color: _ink,
          ),
        ),
      ],
    );
  }

  static String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _formatDateTime(DateTime d) =>
      '${_formatDate(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  static String _formatShortDateTime(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
