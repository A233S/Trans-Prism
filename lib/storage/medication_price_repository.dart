import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/medication_purchase.dart';

/// 药物补货价格记录本地持久化存储
///
/// 存储 [MedicationPurchase] 列表，用于「每次使用费用（平均）」的统计。
/// 与药物列表（`drug_inventory_list`）**分表存储**，互不影响：
/// - 删药物时用 [deleteByDrug] 清理孤儿记录；
/// - 老版本数据里没有该 key → [getAll] 返回空列表，全部显示「未设价格」。
///
/// 数据格式：`MedicationPurchase[]` 的 JSON 字符串
/// 存储位置：SharedPreferences key "medication_purchase_records"
class MedicationPriceRepository {
  /// SharedPreferences 存储键（备份/恢复全量遍历 key 时会自动包含）
  static const String storageKey = 'medication_purchase_records';

  // ──────────────────────────────────────────────
  // 读取
  // ──────────────────────────────────────────────

  /// 获取全部价格记录（保持写入顺序；解析失败按空列表兜底）
  Future<List<MedicationPurchase>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(storageKey);
    if (jsonStr == null || jsonStr.isEmpty) {
      return [];
    }
    try {
      return MedicationPurchase.listFromJson(jsonStr);
    } catch (e) {
      debugPrint('💰 [TP-Cost] 价格记录解析失败，按空列表处理: $e');
      return [];
    }
  }

  /// 获取指定药物的价格记录（按 timestamp **升序**）
  ///
  /// 升序是为了让「累计支出序列」与「最近一次补货」都能直接按序遍历。
  Future<List<MedicationPurchase>> getForDrug(String medId) async {
    final all = await getAll();
    return all.where((p) => p.medicationId == medId).toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  // ──────────────────────────────────────────────
  // 写入
  // ──────────────────────────────────────────────

  /// 追加一条价格记录
  Future<void> add(MedicationPurchase purchase) async {
    final all = await getAll();
    all.add(purchase);
    await _saveAll(all);
    debugPrint(
        '💰 [TP-Cost] 价格记录已保存: medId=${purchase.medicationId}, totalPrice=${purchase.totalPrice}, doses=${purchase.doses}');
  }

  /// 删除指定药物的全部价格记录（删药时清理孤儿）
  Future<void> deleteByDrug(String medId) async {
    final all = await getAll();
    final before = all.length;
    all.removeWhere((p) => p.medicationId == medId);
    if (all.length == before) {
      debugPrint('💰 [TP-Cost] deleteByDrug: 无匹配记录 medId=$medId');
      return;
    }
    await _saveAll(all);
    debugPrint(
        '💰 [TP-Cost] deleteByDrug: medId=$medId，删除 ${before - all.length} 条');
  }

  /// 清空全部价格记录
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(storageKey);
    debugPrint('💰 [TP-Cost] 价格记录已清空');
  }

  /// 全量覆盖写入
  Future<void> _saveAll(List<MedicationPurchase> purchases) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, MedicationPurchase.listToJson(purchases));
  }
}
