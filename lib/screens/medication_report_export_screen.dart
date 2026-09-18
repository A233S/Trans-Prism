import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/drug_model.dart';
import '../models/medication_log.dart';
import '../models/medication_purchase.dart';
import '../services/gallery_saver_service.dart';
import '../services/medication_report_renderer.dart';
import '../services/medication_service.dart';
import '../services/svg_export_service.dart';
import '../storage/medication_price_repository.dart';
import '../utils/currency.dart';
import '../widgets/branded_toast.dart';
import '../widgets/loading_indicator.dart';
import '../widgets/medication_report_view.dart';

/// 时间范围预设
enum _RangePreset { days30, days90, all }

/// 导出目标
enum _ExportTarget { album, file, share }

/// 用药记录 / 费用报告导出页
///
/// 三种内容模式 × 可选打码 = 6 种组合，均在本页配置并**实时预览**。
/// 预览与导出共用同一个 [`MedicationReportView`]，杜绝「所见非所得」。
class MedicationReportExportScreen extends StatefulWidget {
  const MedicationReportExportScreen({super.key});

  @override
  State<MedicationReportExportScreen> createState() =>
      _MedicationReportExportScreenState();
}

class _MedicationReportExportScreenState
    extends State<MedicationReportExportScreen> {
  final GlobalKey _boundaryKey = GlobalKey();
  final MedicationPriceRepository _priceRepo = MedicationPriceRepository();

  bool _loading = true;
  bool _busy = false;

  List<Drug> _drugs = [];
  List<MedicationLog> _logs = [];
  List<MedicationPurchase> _purchases = [];
  Currency _currency = CurrencyFormat.cny;

  ReportMode _mode = ReportMode.recordsAndPrices;
  bool _masked = false;
  _RangePreset _range = _RangePreset.days90;

  /// null = 全部药物；否则为选中的药物 id 集合
  Set<String>? _selectedDrugIds;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final drugs = await MedicationService.loadAllDrugs();
    final logs = await MedicationService.getAllLogs();
    final purchases = await _priceRepo.getAll();
    final currency = await CurrencyFormat.current();
    if (!mounted) return;
    setState(() {
      _drugs = drugs;
      _logs = logs;
      _purchases = purchases;
      _currency = currency;
      _loading = false;
    });
  }

  // ──────────────────────────────────────────────
  // 过滤
  // ──────────────────────────────────────────────

  DateTime get _rangeStart {
    final now = DateTime.now();
    switch (_range) {
      case _RangePreset.days30:
        return now.subtract(const Duration(days: 30));
      case _RangePreset.days90:
        return now.subtract(const Duration(days: 90));
      case _RangePreset.all:
        DateTime? earliest;
        for (final l in _logs) {
          if (earliest == null || l.timestamp.isBefore(earliest)) {
            earliest = l.timestamp;
          }
        }
        for (final p in _purchases) {
          if (earliest == null || p.timestamp.isBefore(earliest)) {
            earliest = p.timestamp;
          }
        }
        return earliest ?? now.subtract(const Duration(days: 365));
    }
  }

  bool _inScope(String medicationId) {
    final sel = _selectedDrugIds;
    return sel == null || sel.contains(medicationId);
  }

  List<Drug> get _scopeDrugs {
    final sel = _selectedDrugIds;
    if (sel == null) return _drugs;
    return _drugs.where((d) => sel.contains(d.id)).toList(growable: false);
  }

  List<MedicationLog> get _filtLogs {
    final start = _rangeStart;
    final end = DateTime.now().add(const Duration(days: 1));
    return _logs
        .where((l) =>
            !l.timestamp.isBefore(start) &&
            l.timestamp.isBefore(end) &&
            _inScope(l.medicationId))
        .toList(growable: false);
  }

  List<MedicationPurchase> get _filtPurchases {
    final start = _rangeStart;
    final end = DateTime.now().add(const Duration(days: 1));
    return _purchases
        .where((p) =>
            !p.timestamp.isBefore(start) &&
            p.timestamp.isBefore(end) &&
            _inScope(p.medicationId))
        .toList(growable: false);
  }

  // ──────────────────────────────────────────────
  // 导出
  // ──────────────────────────────────────────────

  String _stamp() {
    final now = DateTime.now();
    return '${now.year}${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _export(_ExportTarget target) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // logo 必须先解码完成，否则导出图里页眉 logo 会是空白
      await precacheImage(const AssetImage('assets/logo_in.png'), context);
      await WidgetsBinding.instance.endOfFrame;

      final slices = await MedicationReportRenderer.renderPng(
        _boundaryKey,
        pixelRatio: 3.0,
      );
      if (!mounted) return;
      if (slices.isEmpty) {
        BrandedToast.error(context, '导出失败：报告渲染不出来，请重试');
        return;
      }

      final stamp = _stamp();
      final paths = <String>[];
      for (var i = 0; i < slices.length; i++) {
        final fileName = slices.length == 1
            ? 'transprism_med_report_$stamp.png'
            : 'transprism_med_report_${stamp}_${i + 1}.png';
        final saved =
            await SvgExportService.saveBytes(slices[i], fileName);
        if (saved != null) paths.add(saved);
      }

      if (!mounted) return;
      if (paths.isEmpty) {
        BrandedToast.error(context, '导出失败：文件写入失败');
        return;
      }

      switch (target) {
        case _ExportTarget.album:
          var okCount = 0;
          for (final p in paths) {
            final ok = await GallerySaverService.saveImage(p);
            if (ok) okCount++;
          }
          if (!mounted) return;
          if (okCount == paths.length) {
            BrandedToast.success(
                context, '已保存 ${paths.length} 张到相册');
          } else if (okCount > 0) {
            BrandedToast.success(context, '已保存 $okCount 张到相册');
          } else {
            // 平台不支持相册 → 降级为文件提示
            BrandedToast.success(
                context, '当前平台不支持写相册，已保存到文件：${paths.first}');
          }
          break;
        case _ExportTarget.file:
          BrandedToast.success(
            context,
            paths.length == 1
                ? '已保存：${paths.first}'
                : '已保存 ${paths.length} 张（首张：${paths.first}）',
          );
          break;
        case _ExportTarget.share:
          await Share.shareXFiles(
            paths.map((p) => XFile(p)).toList(),
            text: 'Trans Prism 用药记录',
          );
          break;
      }
      debugPrint('📤 [TP-Report] 导出完成: target=$target, ${paths.length} 张');
    } catch (e) {
      debugPrint('📤 [TP-Report] ❌ 导出异常: $e');
      if (mounted) BrandedToast.error(context, '导出出错：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ──────────────────────────────────────────────
  // UI
  // ──────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor =
        isDark ? const Color(0xFFEDEDF0) : const Color(0xFF333333);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '导出用药记录',
          style: TextStyle(fontWeight: FontWeight.w800, color: textColor),
        ),
      ),
      body: _loading
          ? const LoadingIndicator()
          : Stack(
              children: [
                _buildForm(isDark),
                if (_busy)
                  Container(
                    color: Colors.black.withOpacity(0.25),
                    child: const Center(child: LoadingIndicator()),
                  ),
              ],
            ),
    );
  }

  Widget _buildForm(bool isDark) {
    final textColor =
        isDark ? const Color(0xFFEDEDF0) : const Color(0xFF333333);
    final secondary =
        isDark ? const Color(0xFF8E8E96) : const Color(0xFF8A8A86);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        _sectionLabel('内容模式', secondary),
        const SizedBox(height: 8),
        _optionGroup<ReportMode>(
          isDark: isDark,
          value: _mode,
          options: const {
            ReportMode.recordsOnly: '仅记录',
            ReportMode.pricesOnly: '仅价格',
            ReportMode.recordsAndPrices: '价格 + 记录',
          },
          onChanged: (v) => setState(() => _mode = v),
        ),

        const SizedBox(height: 18),
        _sectionLabel('时间范围', secondary),
        const SizedBox(height: 8),
        _optionGroup<_RangePreset>(
          isDark: isDark,
          value: _range,
          options: const {
            _RangePreset.days30: '近 30 天',
            _RangePreset.days90: '近 90 天',
            _RangePreset.all: '全部',
          },
          onChanged: (v) => setState(() => _range = v),
        ),

        const SizedBox(height: 18),
        _sectionLabel('药物范围', secondary),
        const SizedBox(height: 8),
        _buildDrugScope(isDark, secondary),

        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF24242C) : Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _masked,
            activeColor: const Color(0xFFF5A9B8),
            title: Text(
              '打码',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
            subtitle: Text(
              '药名显示为「药物 A/B/C」，并隐藏剂量、注射部位与备注；金额保留',
              style: TextStyle(fontSize: 11, color: secondary, height: 1.4),
            ),
            onChanged: (v) => setState(() => _masked = v),
          ),
        ),

        const SizedBox(height: 18),
        _sectionLabel('预览（可双指缩放 / 拖动）', secondary),
        const SizedBox(height: 8),
        _buildPreview(isDark),

        const SizedBox(height: 18),
        _buildActions(isDark),
        const SizedBox(height: 10),
        Text(
          '导出图为本地生成，不上传任何数据。记录较多时会自动分成多张图片。',
          style: TextStyle(fontSize: 11, color: secondary, height: 1.5),
        ),
      ],
    );
  }

  Widget _buildDrugScope(bool isDark, Color secondary) {
    if (_drugs.isEmpty) {
      return Text('暂无药物', style: TextStyle(fontSize: 12, color: secondary));
    }
    final allSelected = _selectedDrugIds == null;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _chip(
          label: '全部（${_drugs.length}）',
          selected: allSelected,
          onTap: () => setState(() => _selectedDrugIds = null),
        ),
        for (final d in _drugs)
          _chip(
            label: d.name,
            selected: !allSelected && _selectedDrugIds!.contains(d.id),
            onTap: () => setState(() {
              final set = Set<String>.from(_selectedDrugIds ?? <String>{});
              if (set.contains(d.id)) {
                set.remove(d.id);
              } else {
                set.add(d.id);
              }
              _selectedDrugIds = set.isEmpty ? null : set;
            }),
          ),
      ],
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF5A9B8) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? const Color(0xFFF5A9B8) : Colors.grey.shade400,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? Colors.white : null,
          ),
        ),
      ),
    );
  }

  Widget _optionGroup<T>({
    required bool isDark,
    required T value,
    required Map<T, String> options,
    required ValueChanged<T> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF24242C) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (final entry in options.entries)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(entry.key),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: value == entry.key
                        ? const Color(0xFFF5A9B8)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    entry.value,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          value == entry.key ? FontWeight.w700 : FontWeight.w500,
                      color: value == entry.key ? Colors.white : null,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPreview(bool isDark) {
    return Container(
      height: 340,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF15151A) : const Color(0xFFEFEFF3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InteractiveViewer(
        constrained: false,
        minScale: 0.2,
        maxScale: 3.0,
        boundaryMargin: const EdgeInsets.all(60),
        child: MedicationReportBoundary(
          key: _boundaryKey,
          child: MedicationReportView(
            mode: _mode,
            masked: _masked,
            drugs: _scopeDrugs,
            logs: _filtLogs,
            purchases: _filtPurchases,
            rangeStart: _rangeStart,
            rangeEnd: DateTime.now(),
            currency: _currency,
            generatedAt: DateTime.now(),
          ),
        ),
      ),
    );
  }

  Widget _buildActions(bool isDark) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _actionButton(
                icon: Icons.photo_library_outlined,
                label: '保存到相册',
                primary: true,
                onTap: () => _export(_ExportTarget.album),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _actionButton(
                icon: Icons.save_alt_rounded,
                label: '保存为文件',
                primary: false,
                onTap: () => _export(_ExportTarget.file),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: _actionButton(
            icon: Icons.ios_share_rounded,
            label: '分享',
            primary: false,
            onTap: () => _export(_ExportTarget.share),
          ),
        ),
      ],
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required bool primary,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 50,
      child: primary
          ? FilledButton.icon(
              onPressed: _busy ? null : onTap,
              icon: Icon(icon, size: 18),
              label: Text(label,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFF5A9B8),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            )
          : OutlinedButton.icon(
              onPressed: _busy ? null : onTap,
              icon: Icon(icon, size: 18),
              label: Text(label,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
    );
  }

  Widget _sectionLabel(String text, Color color) => Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      );
}
