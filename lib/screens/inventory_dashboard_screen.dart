import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/drug_model.dart';
import '../models/medication_purchase.dart';
import '../services/medication_cost_service.dart';
import '../services/medication_service.dart';
import '../services/notification_service.dart';
import '../services/permission_manager.dart';
import '../storage/medication_price_repository.dart';
import '../utils/currency.dart';
import '../widgets/battery_optimization_dialog.dart';
import '../widgets/branded_toast.dart';
import '../widgets/loading_indicator.dart';
import '../widgets/medication_card.dart';
import '../widgets/restock_sheet.dart';
import 'medication_cost_screen.dart';
import 'medication_report_export_screen.dart';

/// 药物存量仪表盘与本地用药提醒系统
class InventoryDashboardScreen extends StatefulWidget {
  const InventoryDashboardScreen({super.key});

  @override
  State<InventoryDashboardScreen> createState() =>
      _InventoryDashboardScreenState();
}

class _InventoryDashboardScreenState extends State<InventoryDashboardScreen> {
  static const String _storageKey = 'drug_inventory_list';

  List<Drug> _drugs = [];
  bool _isLoading = true;

  /// 成本汇总（供汇总卡与卡片「单次花费」使用）
  MedicationCostSummary? _costSummary;

  /// 当前显示币种（「我的 → 用药成本」可切换；仅换符号不换算汇率）
  Currency _currency = CurrencyFormat.cny;

  final NotificationService _notificationService = NotificationService();
  final MedicationPriceRepository _priceRepo = MedicationPriceRepository();

  @override
  void initState() {
    super.initState();
    _loadDrugs();
    _setupNotificationCallback();
  }

  Future<void> _loadDrugs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_storageKey);
    if (jsonStr != null && jsonStr.isNotEmpty) {
      _drugs = Drug.listFromJson(jsonStr);
    }
    // 按下次服药时间升序排列（最紧急的在前，未设置的在最后）
    _drugs.sort((a, b) {
      final aTime = a.nextDoseTime;
      final bTime = b.nextDoseTime;
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return aTime.compareTo(bTime);
    });
    if (!mounted) return;

    // ── 价格 / 成本数据（与药物列表解耦；即使为空也不影响药物功能）──
    final purchases = await _priceRepo.getAll();
    final currency = await CurrencyFormat.current();
    final summary = MedicationCostService.summarize(_drugs, purchases);

    if (!mounted) return;
    setState(() {
      _costSummary = summary;
      _currency = currency;
      _isLoading = false;
    });
    _rescheduleAllReminders();
    // 加载完成后检查通知权限
    _checkNotificationPermission();
  }

  /// 只重算成本视图（药物列表未变时用，避免重复触发通知权限检查）
  Future<void> _refreshCost() async {
    final purchases = await _priceRepo.getAll();
    if (!mounted) return;
    setState(() {
      _costSummary = MedicationCostService.summarize(_drugs, purchases);
    });
  }

  /// 取某个药物的成本明细（未定价时字段为 null，UI 显示「—」）
  DrugCost? _costFor(Drug drug) {
    final summary = _costSummary;
    if (summary == null) return null;
    for (final c in summary.drugs) {
      if (c.drugId == drug.id) return c;
    }
    return null;
  }

  /// 检查通知权限，未授权时弹出说明对话框
  Future<void> _checkNotificationPermission() async {
    final hasPerm = await _notificationService.hasPermission();
    if (hasPerm) {
      debugPrint('🔔 [TP-Perm] 通知权限已授予');
      return;
    }
    if (!mounted) return;
    debugPrint('🔔 [TP-Perm] 通知权限未授予，弹出说明对话框');
    final granted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.notifications_active_rounded,
                color: Color(0xFFF5A9B8), size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                '开启用药提醒',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Trans Prism 需要通知权限来为您提供本地用药提醒服务。',
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
            SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check_circle_outline,
                    size: 18, color: Color(0xFFF5A9B8)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '不授予权限仍可使用药物库存等其他功能',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.security_rounded,
                    size: 18, color: Color(0xFF4CAF50)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Trans Prism 是非盈利软件，绝不会推送任何广告或垃圾信息',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('暂不开启', style: TextStyle(color: Colors.grey)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFF5A9B8),
            ),
            child: const Text('允许通知'),
          ),
        ],
      ),
    );
    if (granted == true && mounted) {
      await _notificationService.requestPermission();
    }
  }

  Future<void> _saveDrugs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, Drug.listToJson(_drugs));
  }

  void _setupNotificationCallback() {
    // 通知回调：用户从通知栏点击"已服药"
    // 此处无 UI，直接通过 MedicationService 执行纯数据操作
    _notificationService.onDoseRecorded = (drugId) async {
      debugPrint('💊 [TP-Dash] ========== onDoseRecorded(通知) ==========');
      debugPrint('💊 [TP-Dash] drugId=$drugId');

      await MedicationService.executeMedicationDose(drugId);

      // 重新加载最新数据更新 UI
      await _loadDrugs();
      debugPrint('💊 [TP-Dash] ========== onDoseRecorded 完成 ==========');
    };

    _notificationService.onSnoozeRequested = (drugId) async {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_storageKey);
      if (jsonStr == null || jsonStr.isEmpty) return;
      final drugs = Drug.listFromJson(jsonStr);
      final index = drugs.indexWhere((d) => d.id == drugId);
      if (index == -1) return;
      final drug = drugs[index];
      drug.setNextDoseTime(DateTime.now().add(const Duration(minutes: 5)));
      await prefs.setString(_storageKey, Drug.listToJson(drugs));
      if (mounted) {
        setState(() {
          _drugs = drugs;
        });
      }
      await _notificationService.scheduleMedicineReminder(drug);
      if (mounted) {
        BrandedToast.success(context, '已设置5分钟后提醒 💊');
      }
    };
  }

  Future<void> _rescheduleAllReminders() async {
    for (final drug in _drugs) {
      await _notificationService.scheduleMedicineReminder(drug);
    }
  }

  Future<void> _addDrug() async {
    final result = await _DrugFormPage.show(context);
    if (result == null) return;
    setState(() {
      _drugs.add(result.drug);
    });
    await _saveDrugs();
    await _notificationService.scheduleMedicineReminder(result.drug);
    // 首次添加时若填了价格，补一条价格记录；留空则**完全跳过**（不产生记录）
    final firstPurchase = result.firstPurchase;
    if (firstPurchase != null) {
      await _priceRepo.add(firstPurchase);
    }
    await _refreshCost();
  }

  Future<void> _editDrug(int index) async {
    final drug = _drugs[index];
    final result = await _DrugFormPage.show(context, existingDrug: drug);
    if (result == null) return;
    setState(() {
      _drugs[index] = result.drug;
    });
    await _saveDrugs();
    await _notificationService.scheduleMedicineReminder(result.drug);
    await _refreshCost();
  }

  Future<void> _deleteDrug(int index) async {
    final drug = _drugs[index];
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除药物'),
        content: Text('确定要删除 "${drug.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() {
      _drugs.removeAt(index);
    });
    await _saveDrugs();
    // 清理该药的价格记录，避免留下孤儿数据（会污染总花费统计）
    await _priceRepo.deleteByDrug(drug.id);
    await _notificationService.cancelDrugReminders(drug.id);
    await _refreshCost();
  }

  Future<void> _toggleReminder(int index, bool enabled) async {
    final drug = _drugs[index];
    setState(() {
      _drugs[index].reminderEnabled = enabled;
    });
    await _saveDrugs();
    if (enabled) {
      // 1. 检查通知权限
      final hasPerm = await _notificationService.hasPermission();
      if (!hasPerm && mounted) {
        await _checkNotificationPermission();
      }

      // 2. 检查电池优化状态，未授权时弹出醒目保活引导
      if (mounted) {
        final permStatuses =
            await PermissionManager().checkPermissionStatuses();
        final batteryOptGranted = permStatuses['battery_optimization'] ?? false;
        if (!batteryOptGranted && mounted) {
          await BatteryOptimizationDialog.show(context);
        }
      }

      // 3. 调度提醒
      await _notificationService.scheduleMedicineReminder(drug);
    } else {
      await _notificationService.cancelDrugReminders(drug.id);
    }
  }

  /// 补货：改用带「价格 / 规格」录入的 `RestockSheet`
  ///
  /// `RestockSheet` 内部完成 `addStock` + `upsertDrug`（含换算表学习）+
  /// 可选的价格记录；此处只负责刷新成本视图与卡片显示。
  Future<void> _addStock(int index) async {
    final drug = _drugs[index];
    final submitted = await RestockSheet.show(context, drug: drug);
    if (submitted != true) return;
    // drug 与列表里是同一实例，currentStock / specConversions 已在面板内就地更新
    setState(() {});
    await _refreshCost();
  }

  // ==================== 主 UI ====================

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor =
        isDark ? const Color(0xFFEDEDF0) : const Color(0xFF333333);

    if (_isLoading) {
      return const Scaffold(
        body: LoadingIndicator(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '💊 药物存量仪表盘',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: textColor,
          ),
        ),
        actions: [
          // 成本明细入口
          IconButton(
            tooltip: '用药成本',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const MedicationCostScreen(),
                ),
              );
              if (mounted) await _loadDrugs();
            },
          ),
          // 导出记录 PNG 入口（三个模式 × 打码在导出页里选）
          IconButton(
            tooltip: '导出记录图片',
            icon: const Icon(Icons.image_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const MedicationReportExportScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: _drugs.isEmpty ? _buildEmptyState() : _buildContent(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addDrug,
        backgroundColor: const Color(0xFFF5A9B8),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('添加药物'),
      ),
    );
  }

  Widget _buildEmptyState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.medication_liquid_outlined,
              size: 72,
              color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              '还没有药物记录',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '点击下方按钮添加你的第一种药物\n开始追踪存量与用药提醒',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.tonalIcon(
              onPressed: _addDrug,
              icon: const Icon(Icons.add),
              label: const Text('添加第一种药物'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor =
        isDark ? const Color(0xFFEDEDF0) : const Color(0xFF333333);

    double totalStockPercentage = 0;
    int minRunwayDays = 999;

    if (_drugs.isNotEmpty) {
      double totalStock = 0;
      double totalBurn = 0;
      for (final drug in _drugs) {
        totalStock += drug.currentStock;
        totalBurn += drug.dailyBurnRate;
        if (drug.runwayDays < minRunwayDays) {
          minRunwayDays = drug.runwayDays;
        }
      }
      if (totalBurn > 0) {
        final thirtyDayNeed = totalBurn * 30;
        totalStockPercentage = (totalStock / thirtyDayNeed).clamp(0.0, 1.0);
      } else {
        totalStockPercentage = 1.0;
      }
    }

    if (minRunwayDays == 999) minRunwayDays = 0;
    if (_drugs.isEmpty) minRunwayDays = 0;

    return RefreshIndicator(
      onRefresh: _loadDrugs,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          _buildSummaryCard(totalStockPercentage, minRunwayDays),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              '药物清单 (${_drugs.length})',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
          ),
          ...List.generate(_drugs.length, (i) {
            final drug = _drugs[i];
            return MedicationCard(
              key: ValueKey(drug.id),
              drug: drug,
              cost: _costFor(drug),
              currency: _currency,
              onDoseRecorded: () {
                // 服药成功后重新加载数据
                _loadDrugs();
              },
              onToggleReminder: (enabled) {
                _toggleReminder(i, enabled);
              },
              onEdit: () {
                _editDrug(i);
              },
              onDelete: () {
                _deleteDrug(i);
              },
              onAddStock: () {
                _addStock(i);
              },
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(double percentage, int runwayDays) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor =
        isDark ? const Color(0xFFEDEDF0) : const Color(0xFF333333);

    // 成本摘要：仅统计**已定价**药物；未定价的数量必须显式标注出来
    final summary = _costSummary;
    String? costLine;
    if (summary != null && summary.pricedDrugCount > 0) {
      final unpricedNote = summary.unpricedDrugCount > 0
          ? '（不含未设价格的 ${summary.unpricedDrugCount} 种）'
          : '';
      costLine =
          '月预计 ${CurrencyFormat.format(summary.totalMonthlyCost, _currency)}'
          ' ｜ 库存估值 ${CurrencyFormat.format(summary.totalStockValue, _currency)}'
          '$unpricedNote';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF24242C) : Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.04),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            height: 84,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 84,
                  height: 84,
                  child: CircularProgressIndicator(
                    value: percentage,
                    strokeWidth: 7,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFFF5A9B8),
                    ),
                  ),
                ),
                Text(
                  '${(percentage * 100).toInt()}%',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: textColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '安全续航',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$runwayDays',
                      style: TextStyle(
                        fontSize: 44,
                        fontWeight: FontWeight.w900,
                        color:
                            runwayDays <= 3 ? Colors.red.shade400 : textColor,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '天',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  runwayDays <= 3 ? '⚠️ 库存紧张，请及时补仓' : '你的稳态库存量充足',
                  style: TextStyle(
                    fontSize: 12,
                    color: runwayDays <= 3
                        ? Colors.red.shade400
                        : Colors.grey.shade400,
                  ),
                ),
                if (costLine != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    costLine,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// 添加/编辑药物表单 — 独立 StatefulWidget
// =============================================================================

/// 药物表单的返回结果
///
/// [firstPurchase] 仅在**首次添加**且用户**主动填了价格**时非空 ——
/// 价格是可选项：默认整段折叠、留空，留空就**不产生任何价格记录**。
class DrugFormResult {
  final Drug drug;
  final MedicationPurchase? firstPurchase;

  const DrugFormResult(this.drug, this.firstPurchase);
}

/// 添加 / 编辑药物表单（**整屏页面**，左上角返回）
class _DrugFormPage extends StatefulWidget {
  final Drug? existingDrug;

  const _DrugFormPage({this.existingDrug});

  /// 以**整屏页面**方式打开（原为底部弹层，弹层过高且滚动体验差）
  static Future<DrugFormResult?> show(
    BuildContext context, {
    Drug? existingDrug,
  }) {
    return Navigator.of(context).push<DrugFormResult>(
      MaterialPageRoute(
        builder: (_) => _DrugFormPage(existingDrug: existingDrug),
      ),
    );
  }

  @override
  State<_DrugFormPage> createState() => _DrugFormPageState();
}

class _DrugFormPageState extends State<_DrugFormPage> {
  final _nameController = TextEditingController();
  final _stockController = TextEditingController();
  final _dosageController = TextEditingController();
  final _intervalValueController = TextEditingController();

  /// 「每次剂量」的单位（选填，仅用于价格折算，不改变库存语义）
  final _doseUnitController = TextEditingController();

  /// 规格换算表：规格单位 → 折合多少个剂量单位（如 针 → 5）
  final List<_ConversionEntry> _conversions = [];

  /// 换算区是否展开
  bool _showConversions = false;

  // ───────────── 首次购入价格（选填；默认折叠且全空）─────────────

  /// 价格区是否展开（默认收起 → 「默认不填写」）
  bool _showFirstPrice = false;

  final _firstPriceController = TextEditingController();
  final _firstSpecQtyController = TextEditingController();
  final _firstSpecUnitController = TextEditingController();
  final _firstDosesController = TextEditingController();

  /// 用户是否手改过「这份够用」（改过就不再被自动折算覆盖）
  bool _firstDosesTouched = false;

  /// 首次价格录入方式：false = 总价，true = 单价
  bool _firstPriceIsUnit = false;

  /// 当前币种（仅用于预览回显）
  Currency _currency = CurrencyFormat.cny;

  late List<String> _dailyReminderTimes;
  DateTime? _nextDoseTime;
  late IntervalUnit _selectedIntervalUnit;
  bool _isDiscreteMode = false;

  bool get _isEditing => widget.existingDrug != null;
  final _uuid = const Uuid();

  @override
  void initState() {
    super.initState();
    _loadCurrency();
    final existing = widget.existingDrug;
    _nameController.text = existing?.name ?? '';
    _stockController.text = existing?.currentStock.toStringAsFixed(1) ?? '';
    _dosageController.text = existing?.dosage.toStringAsFixed(1) ?? '';
    _doseUnitController.text = existing?.doseUnit ?? '';
    final existingConversions = existing?.specConversions;
    if (existingConversions != null) {
      existingConversions.forEach((unit, factor) {
        _conversions.add(_ConversionEntry(unit, _trimNumber(factor)));
      });
    }
    _dailyReminderTimes =
        List<String>.from(existing?.dailyReminderTimes ?? ['08:00', '20:00']);
    _nextDoseTime = existing?.nextDoseTime;
    _selectedIntervalUnit = existing?.intervalUnit ?? IntervalUnit.hours;
    _isDiscreteMode = existing?.dailyReminderTimes.isNotEmpty ?? false;

    if (existing != null) {
      _intervalValueController.text = existing.intervalValue.toString();
    } else {
      _intervalValueController.text = '12';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _stockController.dispose();
    _dosageController.dispose();
    _intervalValueController.dispose();
    _doseUnitController.dispose();
    for (final c in _conversions) {
      c.dispose();
    }
    _firstPriceController.dispose();
    _firstSpecQtyController.dispose();
    _firstSpecUnitController.dispose();
    _firstDosesController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    final stock = double.tryParse(_stockController.text.trim());
    final dosage = double.tryParse(_dosageController.text.trim());

    if (name.isEmpty) {
      BrandedToast.error(context, '请输入药物名称');
      return;
    }
    if (stock == null || stock < 0) {
      BrandedToast.error(context, '请输入有效的库存数量');
      return;
    }
    if (dosage == null || dosage <= 0) {
      BrandedToast.error(context, '请输入有效的每次剂量');
      return;
    }

    // 首次购入价格是**选填**的：只有用户真的填了才校验；
    // 默认折叠 + 默认留空 ⇒ 这一段完全不参与老流程。
    if (_firstPriceTyped) {
      if (_firstTotalPrice == null) {
        BrandedToast.error(context, '「按单价」模式下请先填写有效的规格数量');
        return;
      }
      final firstDoses = _firstDoses;
      if (firstDoses == null || firstDoses <= 0) {
        BrandedToast.error(context, '请填写「这份够用几次」（需大于 0）');
        return;
      }
    }

    if (_isDiscreteMode) {
      if (_dailyReminderTimes.isEmpty) {
        BrandedToast.error(context, '请至少添加一个提醒时间');
        return;
      }
      final drug = Drug(
        id: widget.existingDrug?.id ?? _uuid.v4(),
        name: name,
        currentStock: stock,
        dosage: dosage,
        intervalValue: 24,
        intervalUnit: IntervalUnit.hours,
        nextDoseTime: _nextDoseTime,
        dailyReminderTimes: List<String>.from(_dailyReminderTimes),
        reminderEnabled: widget.existingDrug?.reminderEnabled ?? true,
        doseUnit: _collectDoseUnit(),
        specConversions: _collectConversions(),
      );
      // 用户未设置下次给药时间时，自动按当前时间推算首次提醒
      if (drug.nextDoseTime == null) {
        drug.setNextDoseTime(drug.calculateNextDoseTime(DateTime.now()));
      }
      Navigator.pop(context, _buildResult(drug, stock));
    } else {
      final intervalVal = int.tryParse(_intervalValueController.text.trim());
      if (intervalVal == null || intervalVal <= 0) {
        BrandedToast.error(context, '请输入有效的间隔数值');
        return;
      }
      final drug = Drug(
        id: widget.existingDrug?.id ?? _uuid.v4(),
        name: name,
        currentStock: stock,
        dosage: dosage,
        intervalValue: intervalVal,
        intervalUnit: _selectedIntervalUnit,
        nextDoseTime: _nextDoseTime,
        dailyReminderTimes: [],
        reminderEnabled: widget.existingDrug?.reminderEnabled ?? true,
        doseUnit: _collectDoseUnit(),
        specConversions: _collectConversions(),
      );
      // 用户未设置下次给药时间时，自动按当前时间推算首次提醒
      if (drug.nextDoseTime == null) {
        drug.setNextDoseTime(drug.calculateNextDoseTime(DateTime.now()));
      }
      Navigator.pop(context, _buildResult(drug, stock));
    }
  }

  /// 收集「每次剂量单位」；空 → null
  String? _collectDoseUnit() {
    final u = _doseUnitController.text.trim();
    return u.isEmpty ? null : u;
  }

  /// 收集规格换算表；全空 → null（保持老数据 toJson 不新增 key）
  Map<String, double>? _collectConversions() {
    final map = <String, double>{};
    for (final e in _conversions) {
      final unit = e.unit.text.trim();
      final factor = double.tryParse(e.factor.text.trim());
      if (unit.isEmpty || factor == null || !factor.isFinite || factor <= 0) {
        continue;
      }
      map[unit] = factor;
    }
    return map.isEmpty ? null : map;
  }

  /// 去掉多余小数尾零，便于回填输入框
  static String _trimNumber(double v) {
    if (v == v.roundToDouble() && v.abs() < 1e9) {
      return v.toInt().toString();
    }
    return v
        .toStringAsFixed(4)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }

  // ───────────── 首次购入价格：派生 · 折算 · 组装 ─────────────

  Future<void> _loadCurrency() async {
    final c = await CurrencyFormat.current();
    if (!mounted) return;
    setState(() => _currency = c);
  }

  double? _num(TextEditingController c) {
    final v = double.tryParse(c.text.trim());
    if (v == null || !v.isFinite) return null;
    return v;
  }

  double? get _firstSpecQty => _num(_firstSpecQtyController);
  double? get _firstDoses => _num(_firstDosesController);

  String? get _firstSpecUnit {
    final t = _firstSpecUnitController.text.trim();
    return t.isEmpty ? null : t;
  }

  /// 本次总花费（「按单价」时 = 单价 × 规格数量）
  double? get _firstTotalPrice {
    final input = _num(_firstPriceController);
    if (input == null) return null;
    if (!_firstPriceIsUnit) return input;
    final qty = _firstSpecQty;
    if (qty == null || qty <= 0) return null;
    return input * qty;
  }

  /// 单次使用费用预览（总花费 ÷ 够用次数）
  double? get _firstCostPerDose {
    final price = _firstTotalPrice;
    final doses = _firstDoses;
    if (price == null || doses == null || doses <= 0) return null;
    return price / doses;
  }

  /// 用户是否**真的填了价格** —— 决定要不要产生价格记录。
  ///
  /// 只看输入框内容、**不看折叠状态**：用户填完价格后把面板收起来，
  /// 意图依然成立（否则收起动作会静默吞掉刚填的价格）。
  /// 从未展开 ⇒ 输入框为空 ⇒ 恒为 false ⇒ 老流程零变化（「默认不填写」）。
  bool get _firstPriceTyped =>
      !_isEditing && _firstPriceController.text.trim().isNotEmpty;

  /// 折算「够用次数」：优先换算表（含本表单刚配的），未知则预填 = 规格数量
  ///
  /// 折算口径与补货面板**共用** [MedicationCostService.resolveDosesFrom]；
  /// 此处是「药物尚未落库」的场景，所以直接传表单草稿字段而不是 [Drug]。
  void _recomputeFirstDoses() {
    if (_firstDosesTouched) return;
    final qty = _firstSpecQty;
    if (qty == null || qty <= 0) {
      _setCtrlText(_firstDosesController, '');
      return;
    }
    final dosage = double.tryParse(_dosageController.text.trim()) ?? 0;

    final auto = MedicationCostService.resolveDosesFrom(
      specQuantity: qty,
      specUnit: _firstSpecUnit,
      doseUnit: _collectDoseUnit(),
      dosage: dosage,
      specConversions: _collectConversions(),
    );

    // 换算未知 → 兜底「预填 = 规格数量」，用户可点 ⚡ 或手改
    _setCtrlText(_firstDosesController, _trimNumber(auto ?? qty));
  }

  static void _setCtrlText(TextEditingController c, String text) {
    if (c.text == text) return;
    c.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  /// ⚡ 按每次剂量折算：规格数量 ÷ 每次剂量
  void _applyFirstDoseDivision() {
    final qty = _firstSpecQty;
    final dosage = double.tryParse(_dosageController.text.trim());
    if (qty == null || qty <= 0) {
      BrandedToast.error(context, '请先填写本次规格数量');
      return;
    }
    if (dosage == null || dosage <= 0) {
      BrandedToast.error(context, '请先填写有效的每次剂量');
      return;
    }
    setState(() {
      _firstDosesTouched = true;
      _setCtrlText(_firstDosesController, _trimNumber(qty / dosage));
    });
  }

  /// 组装返回结果（含可选的首购价格记录）
  DrugFormResult _buildResult(Drug drug, double stock) {
    MedicationPurchase? first;
    if (_firstPriceTyped) {
      final total = _firstTotalPrice;
      final doses = _firstDoses;
      if (total != null && doses != null && doses > 0) {
        first = MedicationPurchase(
          id: _uuid.v4(),
          medicationId: drug.id,
          timestamp: DateTime.now(),
          stockAmount: stock,
          totalPrice: total,
          specQuantity: _firstSpecQty,
          specUnit: _firstSpecUnit,
          doses: doses,
        );
      }
    }
    return DrugFormResult(drug, first);
  }

  /// 规格换算（进阶·选填）：规格单位 → 折合多少个剂量单位
  ///
  /// 例：`1 针 = 5 mg`。配好后补货时填「针」即可自动折算出「够用几次」。
  Widget _buildConversionSection(bool isDark) {
    final textColor =
        isDark ? const Color(0xFFEDEDF0) : const Color(0xFF333333);
    final secondary =
        isDark ? const Color(0xFF8E8E96) : const Color(0xFF8A8A86);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.black12 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _showConversions = !_showConversions),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.swap_horiz_rounded,
                      size: 16, color: Colors.grey.shade500),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '规格换算（进阶·选填）',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                  ),
                  Text(
                    _conversions.isEmpty ? '未设置' : '${_conversions.length} 条',
                    style: TextStyle(fontSize: 11, color: secondary),
                  ),
                  Icon(
                    _showConversions
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: Colors.grey.shade500,
                  ),
                ],
              ),
            ),
          ),
          if (_showConversions) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Text(
                '例：1 针 = 5 mg。补货时填「针」即可自动折算出够用几次。',
                style: TextStyle(fontSize: 11, color: secondary, height: 1.4),
              ),
            ),
            for (var i = 0; i < _conversions.length; i++)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                child: Row(
                  children: [
                    Text('1 个',
                        style: TextStyle(fontSize: 12, color: secondary)),
                    const SizedBox(width: 8),
                    Expanded(child: _miniField(_conversions[i].unit, '针', isDark)),
                    const SizedBox(width: 6),
                    Text('=', style: TextStyle(fontSize: 13, color: secondary)),
                    const SizedBox(width: 6),
                    Expanded(
                        child: _miniField(_conversions[i].factor, '5', isDark)),
                    const SizedBox(width: 6),
                    Text(
                      _collectDoseUnit() ?? '单位',
                      style: TextStyle(fontSize: 12, color: secondary),
                    ),
                    IconButton(
                      onPressed: () => setState(() {
                        _conversions.removeAt(i).dispose();
                      }),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      color: Colors.grey.shade500,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () =>
                      setState(() => _conversions.add(_ConversionEntry('', ''))),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('添加换算', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFF5A9B8),
                    side: const BorderSide(color: Color(0xFFF5A9B8)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 首次购入价格（选填）——**默认折叠、默认留空**，留空则不产生任何价格记录
  Widget _buildFirstPriceSection(bool isDark) {
    final textColor =
        isDark ? const Color(0xFFEDEDF0) : const Color(0xFF333333);
    final secondary =
        isDark ? const Color(0xFF8E8E96) : const Color(0xFF8A8A86);

    final priceTyped = _firstPriceController.text.trim().isNotEmpty;
    final costText = _firstCostPerDose == null
        ? CurrencyFormat.emptyPlaceholder
        : CurrencyFormat.format(_firstCostPerDose, _currency);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.black12 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _showFirstPrice = !_showFirstPrice),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.payments_outlined,
                      size: 16, color: Colors.grey.shade500),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '首次购入价格（选填）',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                  ),
                  Text(
                    priceTyped ? '已填写' : '未填写',
                    style: TextStyle(fontSize: 11, color: secondary),
                  ),
                  Icon(
                    _showFirstPrice
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: Colors.grey.shade500,
                  ),
                ],
              ),
            ),
          ),
          if (_showFirstPrice) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Text(
                '这次买药花了多少钱？留空即可跳过 —— 之后在「补仓」时也能补记。',
                style: TextStyle(fontSize: 11, color: secondary, height: 1.4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: isDark ? Colors.black26 : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    _firstModeOption('按总价', false, secondary),
                    _firstModeOption('按单价', true, secondary),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: _miniField(
                _firstPriceController,
                _firstPriceIsUnit ? '每单位价格，如 1.07' : '总花费，如 30',
                isDark,
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Expanded(
                    child: _miniField(
                      _firstSpecQtyController,
                      '规格数量，如 28',
                      isDark,
                      onChanged: (_) {
                        _firstDosesTouched = false;
                        _recomputeFirstDoses();
                        setState(() {});
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _miniField(
                      _firstSpecUnitController,
                      '单位，如 mg / 片 / 针',
                      isDark,
                      onChanged: (_) {
                        _firstDosesTouched = false;
                        _recomputeFirstDoses();
                        setState(() {});
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Expanded(
                    child: _miniField(
                      _firstDosesController,
                      '这份够用几次',
                      isDark,
                      onChanged: (_) {
                        _firstDosesTouched = true;
                        setState(() {});
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 40,
                    child: OutlinedButton.icon(
                      onPressed: _applyFirstDoseDivision,
                      icon: const Icon(Icons.bolt_rounded, size: 14),
                      label: const Text('按剂量折算',
                          style: TextStyle(fontSize: 10)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFF5A9B8),
                        side: const BorderSide(color: Color(0xFFF5A9B8)),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Row(
                children: [
                  Text('单次 ', style: TextStyle(fontSize: 12, color: secondary)),
                  Text(
                    costText,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: priceTyped ? textColor : secondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _firstModeOption(String label, bool isUnit, Color secondary) {
    final selected = _firstPriceIsUnit == isUnit;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _firstPriceIsUnit = isUnit),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFF5A9B8) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? Colors.white : secondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniField(
    TextEditingController c,
    String hint,
    bool isDark, {
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: c,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade500),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        filled: true,
        fillColor: isDark ? Colors.black12 : Colors.white,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor =
        isDark ? const Color(0xFFEDEDF0) : const Color(0xFF333333);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      // 整屏页面（原为底部弹层）：左上角返回
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _isEditing ? '编辑药物' : '添加药物',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: textColor,
          ),
        ),
      ),
      body: Column(
        children: [
          // ── 表单内容 ──
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _FilledField(
                    controller: _nameController,
                    label: '药物名称',
                    hint: '如：雌二醇片',
                    isDark: isDark,
                  ),
                  const SizedBox(height: 14),

                  // 当前库存 + 每次剂量（并排）
                  Row(
                    children: [
                      Expanded(
                        child: _FilledField(
                          controller: _stockController,
                          label: '当前库存',
                          hint: '如：60',
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          isDark: isDark,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _FilledField(
                          controller: _dosageController,
                          label: '每次剂量',
                          hint: '如：2',
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          isDark: isDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // 剂量单位（选填）—— 仅用于把补货规格折算成「够用几次」
                  _FilledField(
                    controller: _doseUnitController,
                    label: '剂量单位（选填）',
                    hint: '如：mg / 片 / 针 —— 用于价格折算',
                    isDark: isDark,
                  ),
                  const SizedBox(height: 14),

                  _buildConversionSection(isDark),
                  const SizedBox(height: 14),

                  // 首次购入价格（仅「添加」时出现；选填、默认折叠留空）
                  if (!_isEditing) ...[
                    _buildFirstPriceSection(isDark),
                    const SizedBox(height: 16),
                  ],

                  // ── 模式切换 ──
                  _buildModeSwitch(isDark: isDark),
                  const SizedBox(height: 16),

                  // ── 周期选择（仅固定间隔模式） ──
                  if (!_isDiscreteMode) _buildCycleSection(isDark: isDark),
                  if (!_isDiscreteMode) const SizedBox(height: 14),

                  // ── 下次给药时间 ──
                  _buildNextDoseSection(isDark: isDark),
                  const SizedBox(height: 14),

                  // ── 每日提醒时间（仅日内离散模式） ──
                  if (_isDiscreteMode) _buildTimeSection(isDark: isDark),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),

          // ── 底部全宽 CTA（整屏页面：贴安全区）──
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFF5A9B8),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: Text(_isEditing ? '保存更改' : '添加药物'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 模式切换 ──
  Widget _buildModeSwitch({required bool isDark}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF5A9B8).withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isDiscreteMode ? '日内离散模式' : '固定间隔模式',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? const Color(0xFFEDEDF0)
                        : const Color(0xFF333333),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isDiscreteMode
                      ? '一日多次用药，如每日 08:00、20:00'
                      : '一天一次及以上，按固定间隔重复',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _isDiscreteMode,
            onChanged: (val) => setState(() => _isDiscreteMode = val),
            activeColor: const Color(0xFFF5A9B8),
          ),
        ],
      ),
    );
  }

  // ── 周期选择 ──
  Widget _buildCycleSection({required bool isDark}) {
    final textColor =
        isDark ? const Color(0xFFEDEDF0) : const Color(0xFF333333);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            '给药周期',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade500,
            ),
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF24242C) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 第一行：「每」+ 数值输入框
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '每',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 72,
                    child: TextField(
                      controller: _intervalValueController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // 第二行：单位 chips
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: IntervalUnit.values.map((unit) {
                  final isSelected = unit == _selectedIntervalUnit;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedIntervalUnit = unit),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFFF5A9B8)
                            : (isDark
                                ? const Color(0xFF333338)
                                : Colors.white.withOpacity(0.7)),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFFF5A9B8)
                              : (isDark
                                  ? Colors.grey.shade700
                                  : Colors.grey.shade200),
                        ),
                      ),
                      child: Text(
                        unit.label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? Colors.white : textColor,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── 下次给药时间 ──
  Widget _buildNextDoseSection({required bool isDark}) {
    final textColor =
        isDark ? const Color(0xFFEDEDF0) : const Color(0xFF333333);
    final displayText = _nextDoseTime != null
        ? '${_nextDoseTime!.year}/${_nextDoseTime!.month}/${_nextDoseTime!.day}  '
            '${_nextDoseTime!.hour.toString().padLeft(2, '0')}:${_nextDoseTime!.minute.toString().padLeft(2, '0')}'
        : '立即开始';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            '下次给药时间',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade500,
            ),
          ),
        ),
        Material(
          color: isDark ? const Color(0xFF24242C) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: _nextDoseTime ?? DateTime.now(),
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                builder: (context, child) {
                  return Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: Theme.of(context).colorScheme.copyWith(
                            primary: const Color(0xFFF5A9B8),
                          ),
                    ),
                    child: child!,
                  );
                },
              );
              if (date == null) return;
              if (!context.mounted) return;
              final time = await showTimePicker(
                context: context,
                initialTime: _nextDoseTime != null
                    ? TimeOfDay.fromDateTime(_nextDoseTime!)
                    : TimeOfDay.now(),
                builder: (ctx, child) {
                  return Theme(
                    data: Theme.of(ctx).copyWith(
                      colorScheme: Theme.of(ctx).colorScheme.copyWith(
                            primary: const Color(0xFFF5A9B8),
                          ),
                    ),
                    child: child!,
                  );
                },
              );
              if (!context.mounted) return;
              if (time == null) return;
              setState(() {
                _nextDoseTime = DateTime(
                  date.year,
                  date.month,
                  date.day,
                  time.hour,
                  time.minute,
                );
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    size: 20,
                    color: _nextDoseTime != null
                        ? const Color(0xFFF5A9B8)
                        : Colors.grey.shade400,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      displayText,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: _nextDoseTime != null
                            ? textColor
                            : Colors.grey.shade400,
                      ),
                    ),
                  ),
                  if (_nextDoseTime != null)
                    GestureDetector(
                      onTap: () => setState(() => _nextDoseTime = null),
                      child: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: Colors.grey.shade400,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── 每日提醒时间 ──
  Widget _buildTimeSection({required bool isDark}) {
    final textColor =
        isDark ? const Color(0xFFEDEDF0) : const Color(0xFF333333);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            '每日提醒时间',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade500,
            ),
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF24242C) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ..._dailyReminderTimes.map((time) {
                    return Chip(
                      label: Text(
                        time,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                      deleteIcon: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: Colors.grey.shade400,
                      ),
                      onDeleted: () {
                        setState(() {
                          _dailyReminderTimes.remove(time);
                        });
                      },
                      backgroundColor:
                          const Color(0xFFF5A9B8).withOpacity(0.08),
                      side: BorderSide.none,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    );
                  }),
                  ActionChip(
                    label: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.add_rounded,
                          size: 18,
                          color: Color(0xFFF5A9B8),
                        ),
                        SizedBox(width: 4),
                        Text(
                          '添加提醒时间',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFF5A9B8),
                          ),
                        ),
                      ],
                    ),
                    onPressed: () async {
                      final now = TimeOfDay.now();
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: now,
                        builder: (context, child) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme:
                                  Theme.of(context).colorScheme.copyWith(
                                        primary: const Color(0xFFF5A9B8),
                                      ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) {
                        // 统一 24h 格式避免 AM/PM 解析问题
                        final formatted =
                            '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                        if (!_dailyReminderTimes.contains(formatted)) {
                          setState(() {
                            _dailyReminderTimes.add(formatted);
                            _dailyReminderTimes.sort((a, b) => a.compareTo(b));
                          });
                        }
                      }
                    },
                    backgroundColor: const Color(0xFFF5A9B8).withOpacity(0.12),
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 无边框填充式输入框
class _FilledField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final TextInputType? keyboardType;
  final bool isDark;

  const _FilledField({
    required this.controller,
    required this.label,
    required this.hint,
    this.keyboardType,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: isDark ? const Color(0xFFEDEDF0) : const Color(0xFF333333),
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.grey.shade500,
        ),
        hintText: hint,
        hintStyle: TextStyle(
          fontSize: 16,
          color: Colors.grey.shade300,
        ),
        filled: true,
        fillColor: isDark ? const Color(0xFF24242C) : Colors.grey.shade100,
        // 圆角：与设置项 / 卡片统一取 16。
        // （原先 `InputBorder.none` → 纯直角矩形，与全局圆角语言不一致）
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        // 聚焦时给一圈品牌粉描边，弥补原先"无边框看不出焦点"的问题
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFF5A9B8), width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }
}

/// 规格换算表的一行：规格单位（如「针」）+ 折合多少个剂量单位（如 5）
class _ConversionEntry {
  final TextEditingController unit;
  final TextEditingController factor;

  _ConversionEntry(String u, String f)
      : unit = TextEditingController(text: u),
        factor = TextEditingController(text: f);

  void dispose() {
    unit.dispose();
    factor.dispose();
  }
}
