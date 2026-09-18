import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/drug_model.dart';
import '../models/medication_purchase.dart';
import '../services/medication_cost_service.dart';
import '../services/medication_service.dart';
import '../storage/medication_price_repository.dart';
import '../utils/currency.dart';
import 'branded_toast.dart';

/// 价格录入口径：本次填的是「总价」还是「单价」
enum _PriceEntryMode { total, unit }

/// 补货 + 价格 / 规格录入面板
///
/// 设计要点（详见 `docs/MED_PRICE_PLAN.md` §4.1）：
/// - **补货与定价完全解耦**：价格整段可留空；留空时只加库存、**不写**价格记录。
/// - `totalPrice == 0`（赠药 / 免费）是**合法价格**，与「未填」(`null`) 严格区分。
/// - **总价 / 单价两种录入口径只是输入换算**，落库永远只存 `totalPrice` —— 杜绝双份真相。
/// - 「够用次数」优先级：**用户手改 > 换算表自动 > 预填 = 规格数量**。
/// - 遇到**未知规格单位**时就地问「1 针 = ? 剂量单位」，可勾选记住写入
///   [`Drug.specConversions`]，下次自动折算。
///
/// 使用方式：
/// ```dart
/// final ok = await RestockSheet.show(context, drug: drug);
/// if (ok == true) { /* 父级重新加载列表 */ }
/// ```
class RestockSheet extends StatefulWidget {
  final Drug drug;

  const RestockSheet({super.key, required this.drug});

  /// 弹出补货面板，返回 `true` 表示已提交（库存已增加）。
  static Future<bool?> show(BuildContext context, {required Drug drug}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RestockSheet(drug: drug),
    );
  }

  @override
  State<RestockSheet> createState() => _RestockSheetState();
}

class _RestockSheetState extends State<RestockSheet> {
  static const Uuid _uuid = Uuid();

  /// 规格单位的常用候选（下拉快捷填充，仍允许自由输入）
  static const List<String> _unitPresets = [
    'mg',
    'ml',
    '片',
    '粒',
    '针',
    '支',
    '单位',
  ];

  final _amountController = TextEditingController();
  final _priceController = TextEditingController();
  final _specQtyController = TextEditingController();
  final _specUnitController = TextEditingController();
  final _dosesController = TextEditingController();
  final _conversionController = TextEditingController();
  final _doseUnitNameController = TextEditingController();
  final _noteController = TextEditingController();

  final MedicationPriceRepository _repo = MedicationPriceRepository();

  _PriceEntryMode _entryMode = _PriceEntryMode.total;

  /// 规格数量是否与补货数量联动（默认联动，用户改动其一手动解绑）
  bool _linked = true;

  /// 用户是否直接改过「够用次数」（改过就不再被自动折算覆盖）
  bool _dosesTouched = false;

  /// 本次临时换算（用户没勾「记住」时使用，不写入药物配置）
  double? _transientConversion;

  /// 是否记住这次换算（写入药物换算表）
  bool _rememberConversion = true;

  bool _submitting = false;

  Currency _currency = CurrencyFormat.cny;

  /// 该药的历史均价（有价格记录时非空），用于给用户一个参照
  double? _historyCostPerDose;
  String? _historySpecUnit;
  int _historyCount = 0;

  @override
  void initState() {
    super.initState();
    _conversionController.text = '';
    _doseUnitNameController.text = widget.drug.doseUnit ?? '';
    _loadHistory();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _priceController.dispose();
    _specQtyController.dispose();
    _specUnitController.dispose();
    _dosesController.dispose();
    _conversionController.dispose();
    _doseUnitNameController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final currency = await CurrencyFormat.current();
    final purchases = await _repo.getForDrug(widget.drug.id);
    if (!mounted) return;
    setState(() {
      _currency = currency;
      _historyCostPerDose = MedicationCostService.avgCostPerDose(purchases);
      _historySpecUnit = purchases
          .where((p) =>
              p.totalPrice != null &&
              p.specUnit != null &&
              p.specUnit!.trim().isNotEmpty)
          .map((p) => p.specUnit)
          .lastOrNull;
      _historyCount = purchases.where((p) => p.priced).length;
    });
  }

  // ──────────────────────────────────────────────
  // 输入联动
  // ──────────────────────────────────────────────

  /// 补货数量变化：联动规格数量（未解绑时）
  ///
  /// ⚠️ 只用 TextField 的 `onChanged`（**仅用户输入触发**），不用 controller
  /// listener —— 否则下面「程序化写入规格数量」会反过来触发联动，形成回环覆盖
  /// 用户的手动输入。
  void _onAmountChanged(String value) {
    if (_linked && _specQtyController.text != value) {
      _specQtyController.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }
    _dosesTouched = false;
    _recomputeDoses();
    if (mounted) setState(() {});
  }

  /// 规格数量被用户手改 → 与补货数量解绑，并重新允许自动折算
  void _onSpecQtyChanged(String value) {
    if (value != _amountController.text) _linked = false;
    _dosesTouched = false;
    _recomputeDoses();
    if (mounted) setState(() {});
  }

  /// 规格单位变化 → 换算关系变了，重新折算
  void _onSpecUnitChanged(String value) {
    _dosesTouched = false;
    _recomputeDoses();
    if (mounted) setState(() {});
  }

  /// 按「用户手改 > 换算表自动 > 预填 = 规格数量」决定 doses
  void _recomputeDoses() {
    if (_dosesTouched) return;

    final specQty = _specQty;
    if (specQty == null || specQty <= 0) {
      _setDosesText('');
      return;
    }

    // 1) 换算表（或本次临时换算）自动折算
    final auto = _resolveDoses();
    // 2) 兜底：预填 = 规格数量（覆盖 14片 / 1针 等多数场景）
    final value = auto ?? specQty;
    _setDosesText(_formatDoses(value));
  }

  /// 折算「够用次数」：优先药物换算表，其次本次临时换算（未勾「记住」时）
  ///
  /// 口径统一由 [MedicationCostService.resolveDosesFrom] 提供（与「添加药物」
  /// 表单共用同一份实现），这里只负责把「本次临时换算」并入换算表。
  double? _resolveDoses() {
    final qty = _specQty;
    if (qty == null || qty <= 0) return null;

    final unit = _specUnit;
    final transient = _transientConversion;
    Map<String, double>? conversions = widget.drug.specConversions;

    if (transient != null &&
        transient.isFinite &&
        transient > 0 &&
        unit != null) {
      // 用户当下手填的换算优先于药物表（最贴近其当前意图）
      conversions = <String, double>{...?conversions, unit: transient};
    }

    return MedicationCostService.resolveDosesFrom(
      specQuantity: qty,
      specUnit: unit,
      doseUnit: widget.drug.doseUnit,
      dosage: widget.drug.dosage,
      specConversions: conversions,
    );
  }

  void _setDosesText(String text) {
    if (_dosesController.text == text) return;
    _dosesController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  static String _formatDoses(double v) {
    if (v == v.roundToDouble() && v.abs() < 1e9) {
      return v.toInt().toString();
    }
    // 最多 4 位小数，去掉尾随 0
    return v
        .toStringAsFixed(4)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }

  void _onDosesManuallyEdited() {
    _dosesTouched = true;
    setState(() {});
  }

  /// ⚡ 按「每次剂量」折算：规格数量 ÷ dosage
  void _applyDoseDivision() {
    final specQty = _specQty;
    final dosage = widget.drug.dosage;
    if (specQty == null || specQty <= 0) {
      BrandedToast.error(context, '请先填写本次规格数量');
      return;
    }
    if (dosage <= 0) {
      BrandedToast.error(context, '该药物的每次剂量无效，无法折算');
      return;
    }
    setState(() {
      _dosesTouched = true;
      _setDosesText(_formatDoses(specQty / dosage));
    });
  }

  void _applyLearnedConversion() {
    final c = double.tryParse(_conversionController.text.trim());
    if (c == null || c <= 0) {
      BrandedToast.error(context, '请输入有效的换算系数');
      return;
    }
    final unit = _specUnit;
    if (unit == null) {
      BrandedToast.error(context, '请先填写本次规格单位');
      return;
    }
    setState(() {
      if (_rememberConversion) {
        widget.drug.specConversions ??= <String, double>{};
        widget.drug.specConversions![unit] = c;
        final existingUnit = widget.drug.doseUnit;
        if (existingUnit == null || existingUnit.trim().isEmpty) {
          final entered = _doseUnitNameController.text.trim();
          widget.drug.doseUnit = entered.isEmpty ? '单位' : entered;
        }
      } else {
        // 不记住：仅本次生效，不污染药物配置
        _transientConversion = c;
      }
      _dosesTouched = false;
      _recomputeDoses();
    });
    BrandedToast.success(
      context,
      _rememberConversion
          ? '已记住：1 $unit = $c ${widget.drug.doseUnit}'
          : '本次按 1 $unit = $c 折算（未记住）',
    );
  }

  // ──────────────────────────────────────────────
  // 派生值
  // ──────────────────────────────────────────────

  double? get _amount => _parse(_amountController.text);
  double? get _specQty => _parse(_specQtyController.text);
  double? get _doses => _parse(_dosesController.text);

  String? get _specUnit {
    final t = _specUnitController.text.trim();
    return t.isEmpty ? null : t;
  }

  static double? _parse(String raw) {
    final v = double.tryParse(raw.trim());
    if (v == null || !v.isFinite) return null;
    return v;
  }

  /// 本次总花费（单价模式时 = 单价 × 规格数量）
  double? get _totalPrice {
    final input = _parse(_priceController.text);
    if (input == null) return null;
    if (_entryMode == _PriceEntryMode.total) return input;
    final qty = _specQty;
    if (qty == null || qty <= 0) return null;
    return input * qty;
  }

  /// 单次使用费用（均价口径：本次总花费 ÷ 够用次数）
  double? get _costPerDose {
    final price = _totalPrice;
    final doses = _doses;
    if (price == null || doses == null || doses <= 0) return null;
    return price / doses;
  }

  /// 每规格单位单价
  double? get _unitPrice {
    final price = _totalPrice;
    final qty = _specQty;
    if (price == null || qty == null || qty <= 0) return null;
    return price / qty;
  }

  /// 换算未知（规格单位与剂量单位不同且表里没有）
  bool get _needsConversion {
    final unit = _specUnit;
    final qty = _specQty;
    if (unit == null || qty == null || qty <= 0) return false;
    return _resolveDoses() == null;
  }

  // ──────────────────────────────────────────────
  // 提交
  // ──────────────────────────────────────────────

  Future<void> _confirm() async {
    if (_submitting) return;

    final amount = _amount;
    if (amount == null || amount <= 0) {
      BrandedToast.error(context, '请输入有效的补货数量');
      return;
    }

    // 价格整段是否被填写：以「花费输入框非空」为准（0 也算填写 → 赠药）
    final priceRaw = _priceController.text.trim();
    final priceTyped = priceRaw.isNotEmpty;

    final total = _totalPrice;
    if (priceTyped && total == null) {
      BrandedToast.error(context, '单价模式下请先填写有效的规格数量');
      return;
    }

    final doses = _doses;
    if (priceTyped && (doses == null || doses <= 0)) {
      BrandedToast.error(context, '请填写「这份够用几次」（需 > 0）');
      return;
    }

    if (_needsConversion && priceTyped && _conversionController.text.trim().isEmpty) {
      // 不阻断提交：允许用户不记换算，但 doses 已经用手改/预填的值
      debugPrint('💰 [TP-Cost] 换算未知且未填写，按预填次数记录');
    }

    setState(() => _submitting = true);
    try {
      // 1) 库存 +（可选）换算表 一次落库
      widget.drug.addStock(amount);
      await MedicationService.upsertDrug(widget.drug);

      // 2) 价格与价格记录完全解耦：没填就不写记录
      if (priceTyped && total != null && doses != null && doses > 0) {
        await _repo.add(
          MedicationPurchase(
            id: _uuid.v4(),
            medicationId: widget.drug.id,
            timestamp: DateTime.now(),
            stockAmount: amount,
            totalPrice: total,
            specQuantity: _specQty,
            specUnit: _specUnit,
            doses: doses,
            note: _noteController.text.trim().isEmpty
                ? null
                : _noteController.text.trim(),
          ),
        );
      }

      debugPrint(
          '💰 [TP-Cost] 补货完成: +$amount, 价格=${priceTyped ? total : "未填"}');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('💰 [TP-Cost] ❌ 补货失败: $e');
      if (mounted) BrandedToast.error(context, '补货失败：$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
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
    final secondary =
        isDark ? const Color(0xFF8E8E96) : const Color(0xFF8A8A86);

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖拽指示条
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // 标题
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5A9B8).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.add_shopping_cart_rounded,
                    color: Color(0xFFF5A9B8),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '补货',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: textColor,
                        ),
                      ),
                      Text(
                        widget.drug.name,
                        style: TextStyle(fontSize: 13, color: secondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoRow(
                    icon: Icons.inventory_2_outlined,
                    label: '当前库存',
                    value: '${widget.drug.currentStock.toStringAsFixed(1)} 单位',
                    valueColor: textColor,
                  ),
                  if (_historyCostPerDose != null) ...[
                    const SizedBox(height: 8),
                    _infoRow(
                      icon: Icons.history_rounded,
                      label: '历史均价',
                      value:
                          '${CurrencyFormat.formatWithUnit(_historyCostPerDose, _currency, _historySpecUnit)} / 次（$_historyCount 次记录）',
                      valueColor: secondary,
                    ),
                  ],
                  const SizedBox(height: 16),
                  Divider(
                    height: 1,
                    color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                  ),
                  const SizedBox(height: 16),

                  _label('本次补货数量 *', secondary),
                  const SizedBox(height: 6),
                  _textField(
                    controller: _amountController,
                    isDark: isDark,
                    hint: '如：1',
                    suffix: '单位',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: _onAmountChanged,
                  ),
                  const SizedBox(height: 16),

                  _buildPriceSection(isDark, textColor, secondary),
                  const SizedBox(height: 16),

                  _label('备注（选填）', secondary),
                  const SizedBox(height: 6),
                  _textField(
                    controller: _noteController,
                    isDark: isDark,
                    hint: '如：某药房 / 医保',
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),

          // 底部按钮
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: OutlinedButton(
                      onPressed:
                          _submitting ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: secondary,
                        side: BorderSide(
                          color: isDark
                              ? Colors.grey.shade700
                              : Colors.grey.shade300,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text('取消'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _submitting ? null : _confirm,
                      style: FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      icon: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_circle_outline, size: 20),
                      label: Text(_submitting ? '提交中...' : '确认补货'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 价格与规格（选填）整段
  Widget _buildPriceSection(bool isDark, Color textColor, Color secondary) {
    final priceTyped = _priceController.text.trim().isNotEmpty;
    final singleCostText = _costPerDose == null
        ? CurrencyFormat.emptyPlaceholder
        : CurrencyFormat.format(_costPerDose, _currency);
    final unitPriceText = _unitPrice == null
        ? null
        : CurrencyFormat.formatWithUnit(_unitPrice, _currency, _specUnit);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF5A9B8).withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.payments_outlined,
                  size: 16, color: Color(0xFFF5A9B8)),
              const SizedBox(width: 6),
              Text(
                '价格与规格',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
              const Spacer(),
              Text(
                '选填 · 可整段留空',
                style: TextStyle(fontSize: 11, color: secondary),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 录入方式：总价 / 单价
          _buildEntryModeToggle(isDark, secondary),
          const SizedBox(height: 12),

          // 本次花费
          _label(
            _entryMode == _PriceEntryMode.total ? '本次花费' : '每单位价格',
            secondary,
          ),
          const SizedBox(height: 6),
          _textField(
            controller: _priceController,
            isDark: isDark,
            hint: _entryMode == _PriceEntryMode.total ? '如：30' : '如：1.07',
            suffix: '元',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) {
              if (mounted) setState(() {});
            },
          ),
          const SizedBox(height: 12),

          // 本次规格：数量 + 单位
          _label('本次规格', secondary),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _textField(
                  controller: _specQtyController,
                  isDark: isDark,
                  hint: '如：28 / 14 / 1',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: _onSpecQtyChanged,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 4,
                child: _textField(
                  controller: _specUnitController,
                  isDark: isDark,
                  hint: 'mg / 片 / 针',
                  unitPicker: true,
                  onChanged: _onSpecUnitChanged,
                ),
              ),
            ],
          ),

          if (_needsConversion) ...[
            const SizedBox(height: 10),
            _buildConversionLearner(isDark, textColor, secondary),
          ],

          const SizedBox(height: 12),

          // 这份够用 N 次
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('这份够用', secondary),
                    const SizedBox(height: 6),
                    _textField(
                      controller: _dosesController,
                      isDark: isDark,
                      hint: '如：14',
                      suffix: '次',
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      onChanged: (_) => _onDosesManuallyEdited(),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 46,
                child: OutlinedButton.icon(
                  onPressed: _applyDoseDivision,
                  icon: const Icon(Icons.bolt_rounded, size: 16),
                  label: Text(
                    '按剂量 ${widget.drug.dosage.toStringAsFixed(1)} 折算',
                    style: const TextStyle(fontSize: 11),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFF5A9B8),
                    side: const BorderSide(color: Color(0xFFF5A9B8)),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),

          // 推导过程回显 —— 让错值当场暴露
          if (_specQty != null && _specQty! > 0) ...[
            const SizedBox(height: 8),
            Text(
              _derivationText(),
              style: TextStyle(fontSize: 11, color: secondary, height: 1.4),
            ),
          ],

          const SizedBox(height: 10),
          Divider(
            height: 1,
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
          ),
          const SizedBox(height: 10),

          // 实时结果
          Row(
            children: [
              Text('单次 ', style: TextStyle(fontSize: 12, color: secondary)),
              Text(
                singleCostText,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: priceTyped ? textColor : secondary,
                ),
              ),
              if (unitPriceText != null) ...[
                Text(' ｜ ',
                    style: TextStyle(fontSize: 12, color: secondary)),
                Text(
                  unitPriceText,
                  style: TextStyle(fontSize: 12, color: secondary),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// 回显推导过程，例如「28 mg ÷ 5.0 mg/次 = 5.6 次」
  String _derivationText() {
    final qty = _specQty!;
    final unit = _specUnit;
    final doseUnit = widget.drug.doseUnit;
    final dosage = widget.drug.dosage;
    final doses = _doses;

    final qtyText = _formatDoses(qty);
    final specText = unit == null ? qtyText : '$qtyText $unit';

    if (doseUnit != null && unit != null && unit != doseUnit) {
      final c = widget.drug.specConversions?[unit];
      if (c != null) {
        return '$specText × $c $doseUnit/$unit ÷ ${dosage.toStringAsFixed(1)} $doseUnit/次'
            '${doses != null ? ' = ${_formatDoses(doses)} 次' : ''}';
      }
    }
    if (unit != null && (doseUnit == null || unit == doseUnit)) {
      return '$specText ÷ ${dosage.toStringAsFixed(1)} $doseUnit/次'
          '${doses != null ? ' = ${_formatDoses(doses)} 次' : ''}';
    }
    return '本次量按 ${doses != null ? _formatDoses(doses) : '?'} 次计';
  }

  Widget _buildEntryModeToggle(bool isDark, Color secondary) {
    Widget option(String label, _PriceEntryMode mode) {
      final selected = _entryMode == mode;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _entryMode = mode),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFFF5A9B8)
                  : Colors.transparent,
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

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isDark ? Colors.black26 : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          option('按总价', _PriceEntryMode.total),
          option('按单价', _PriceEntryMode.unit),
        ],
      ),
    );
  }

  /// 未知规格单位时就地学习换算
  Widget _buildConversionLearner(
      bool isDark, Color textColor, Color secondary) {
    final unit = _specUnit ?? '';
    final doseUnitLabel = widget.drug.doseUnit ?? '剂量单位';
    final needDoseUnitName =
        widget.drug.doseUnit == null || widget.drug.doseUnit!.trim().isEmpty;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? Colors.black26 : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF5A9B8).withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '第一次见到「$unit」，它等于多少 $doseUnitLabel？',
            style: TextStyle(fontSize: 11, color: secondary),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('1 $unit =',
                  style: TextStyle(fontSize: 12, color: textColor)),
              const SizedBox(width: 8),
              Expanded(
                child: _textField(
                  controller: _conversionController,
                  isDark: isDark,
                  hint: '如：5',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
              if (needDoseUnitName) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: _textField(
                    controller: _doseUnitNameController,
                    isDark: isDark,
                    hint: '单位名，如 mg',
                  ),
                ),
              ],
              const SizedBox(width: 8),
              SizedBox(
                height: 44,
                child: FilledButton(
                  onPressed: _applyLearnedConversion,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFF5A9B8),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('折算', style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Checkbox(
                value: _rememberConversion,
                activeColor: const Color(0xFFF5A9B8),
                onChanged: (v) =>
                    setState(() => _rememberConversion = v ?? false),
              ),
              Expanded(
                child: Text(
                  '记住这次换算（下次自动折算）',
                  style: TextStyle(fontSize: 11, color: secondary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ──────── 基础小组件 ────────

  Widget _label(String text, Color color) => Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      );

  Widget _infoRow({
    required IconData icon,
    required String label,
    required String value,
    required Color valueColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade400),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: valueColor,
            ),
          ),
        ),
      ],
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required bool isDark,
    String? hint,
    String? suffix,
    TextInputType? keyboardType,
    bool unitPicker = false,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500),
        suffixText: suffix,
        suffixStyle: TextStyle(fontSize: 12, color: Colors.grey.shade500),
        suffixIcon: unitPicker
            ? PopupMenuButton<String>(
                icon: const Icon(Icons.arrow_drop_down, size: 20),
                tooltip: '选择单位',
                onSelected: (v) {
                  controller.text = v;
                  _onSpecUnitChanged(v);
                },
                itemBuilder: (_) => _unitPresets
                    .map((u) => PopupMenuItem<String>(
                          value: u,
                          height: 40,
                          child: Text(u, style: const TextStyle(fontSize: 13)),
                        ))
                    .toList(),
              )
            : null,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: isDark ? Colors.black12 : Colors.white,
      ),
    );
  }
}
