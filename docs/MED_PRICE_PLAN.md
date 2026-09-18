# Trans Prism · 药物价格计算器与用药记录导出计划

> 状态：**已实现并验收**（P0–P4 全部落地；实现记录见文末 §11）
> 目标版本：v1.7.0（建议）
> 关联文档：[`REPO_MAP.md`](../REPO_MAP.md:1) §1 HRT 用药追踪 / [`DATA_EXPORT_COMPATIBILITY.md`](DATA_EXPORT_COMPATIBILITY.md:1)
> 架构约束：✅ 纯 `StatefulWidget` + `setState`　✅ 无 Riverpod　✅ 无 SQLite　✅ `SharedPreferences` 单存储　✅ 纯本地、零网络

---

## 0. 需求与决策（已全部收敛）

### 0.1 需求转写
1. 用户可为正在使用的药物**录入价格**。
2. 录入口在**用药提醒 / 状态表**两处，时机是**每次补货时**问「这次价格是多少」。
3. 价格**可填可不填**：不填 → **已有价格的药品按平均价格计算**；**没有价格的药品不计入**（**不是按 0 元算**）。
4. 按**使用情况 + 平均价格**显示**每次使用费用（平均）**。
5. 母页面提供**导出记录 PNG**：**仅记录 / 仅价格 / 价格+记录** 三模式，每种可**选是否打码**，图中带 **logo + App 名**。

### 0.2 决策台账

| # | 决策 | 结论 |
|---|---|---|
| **D1** | 录入口径 | **自定义规格 + 价格双输入框**。例 `30元/28mg`、`30元/14片`、`1000元/1针`；**同时支持按总价或按单价录入** |
| **D2** | 平均口径 | **加权平均**（权重 = **够用次数**，见 §3.1） |
| **D3** | 打码范围 | 藏**药名 / 剂量 / 部位 / 备注**，**保留金额** |
| **D8** | 展示位点 | **四处全做**：仪表盘汇总卡、首页存量摘要、卡片「单次花费」栏、**新增独立成本详情页** |
| **D9** | 「够用次数」来源 | **两者都要**：① 药物级**剂量单位 + 规格换算表**自动折算；② 补货面板 **⚡ 一键按剂量折算** 作手动兜底 |
| **D5** | 币种 | **默认 CNY**，可在**「我的」**里修改（仅换符号，**不换算汇率**） |
| **D6** | 打卡时记价？ | **不输入**。打卡扣库存，支出**由日志 × 单次费用自动派生**（用户原话：「打卡时候药物减少就自动按周期算支出了啊」） |
| **D7** | 均价时间感知？ | **不做**（统一用当前均价）。理由见 §3.4 —— 按**次数加权**的均值能让**总额自动自洽**，无需给日志加字段 |
| **D4** | 超长记录 | **自动分片多张 PNG**（默认，用户未反对） |

---

## 1. 现状盘点（已核对代码）

| 关注点 | 现状 | 结论 |
|---|---|---|
| 药物模型 | [`Drug`](../lib/models/drug_model.dart:64)：id/name/stock/dosage/interval/nextDose…**无价格、无单位** | 需新增字段（D9） |
| **单位** | **全 app 无单位字段**：`dosage` / `currentStock` 都是**无单位纯数字**，UI 一律硬编码「单位」（[`medication_card.dart:481`](../lib/widgets/medication_card.dart:481)、[`record_dose_dialog.dart:210`](../lib/widgets/record_dose_dialog.dart:210)） | ⚠️ 本计划核心难点，见 §3.1–3.3 |
| 药物表单 | [`_DrugFormPage`](../lib/screens/inventory_dashboard_screen.dart:586)：名称/库存/每次剂量/模式/周期/提醒时间 | 需加「剂量单位」+ 换算表入口 |
| 补货入口 ① | [`InventoryDashboardScreen._addStock()`](../lib/screens/inventory_dashboard_screen.dart:271)：`AlertDialog` 只问「增加数量」 | 需扩展为价格+规格录入 |
| 补货入口 ② | [`MedicationCard`](../lib/widgets/medication_card.dart:560)「补仓」→ 回调 `onAddStock` → **复用①同一实现** | 改一处即覆盖两入口 |
| 补货入口 ③ | 通知栏动作只有 `take_dose` / `snooze_5min`（[`notification_service.dart:152`](../lib/services/notification_service.dart:152)） | 系统通知**无法输入文本**，不做输入 |
| 用药执行 | [`executeMedicationDose()`](../lib/services/medication_service.dart:52)：写 `MedicationLog` + 扣库存 + 重排通知 | 日志**不改结构**（§3.4） |
| 日志读取 | `getAllLogs()` / `getLogsForDrug()` 已存在，**全仓库无 UI 消费** | 「用药记录」目前只有数据、没有界面 |
| 状态表 | [`MedicationStockSummary`](../lib/widgets/medication_stock_summary.dart:16)（首页）+ [`_buildSummaryCard()`](../lib/screens/inventory_dashboard_screen.dart:473)（仪表盘） | 两处都加成本摘要 |
| 我的页 | [`ProfileTab`](../lib/main.dart:1893)：身份资料 / 外观与显示 / **高级** / 系统；设置项经 [`_buildSettingsTile`](../lib/main.dart:2270) 渲染且**统一无副标题** | 币种设置入口（D5） |
| PNG 导出 | [`ImageExportService`](../lib/services/image_export_service.dart:26) 只做 **SVG→位图**；[`SvgExportService.saveBytes`](../lib/services/svg_export_service.dart:1) 落盘；[`GallerySaverService`](../lib/services/gallery_saver_service.dart:13) 存相册；`share_plus` 已在用 | **无「任意 Widget → PNG」能力**，需新建 |
| 图表 | `fl_chart ^0.69.2` 已在 `pubspec.yaml` | 成本趋势图零新依赖（可选） |
| 品牌素材 | `assets/logo_in.png`（首页/向导）、`assets/logo_foreground.png`（关于页） | 导出页眉直接复用，**无需新素材** |
| 备份 | [`exportData()`](../lib/utils/data_migration_service.dart:48) 遍历 `prefs.getKeys()` 全量导出；`importData()` 全量回写 | **新 SP key 自动进备份，零改动** |
| 依赖 | `image` / `share_plus` / `path_provider` / `file_picker` / `flutter_image_compress` / `fl_chart` 全在 | **本期无需任何新第三方依赖** |

---

## 2. 设计目标

1. **零摩擦**：补货多问一句，可整段留空跳过；不填不影响任何既有功能。
2. **数据不污染**：`Drug` 新增字段全部**可选 + 容错**，老用户数据 100% 兼容。
3. **语义正确**：严格区分「没填价格」(`null`) 与「价格 = 0」（赠药）；缺失值绝不当作 0 拉低平均。
4. **单位可解释**：所有金额都能说清「哪个规格 × 多少钱 ÷ 够用几次」。
5. **纯本地**：价格与记录不出设备；导出图本地生成，零网络。

---

## 3. 数据层设计

### 3.1 核心公式：以「次」为锚

**主指标**
```
每次使用费用（平均） = Σ(本次花费) / Σ(本次够用次数)
```

- 用户只需回答一个**它本来就知道**的问题：「这次买的量够我用几次？」
- `30元 / 14片`（一次 1 片）→ 14 次 → `¥2.14/次`
- `1000元 / 1针`（一次 1 针）→ 1 次 → `¥1000.00/次`
- `30元 / 28mg`（一次 5mg）→ 5.6 次 → `¥5.36/次`
- **月成本** = `单次费用 × 每日次数 × 30`，`每日次数 = 24 ÷ 间隔小时`（离散模式 = `dailyReminderTimes.length`）
- **库存估值** = `单次费用 × 剩余可用次数`，`剩余可用次数 = currentStock ÷ dosage`

> 这两个式子**完全不依赖任何单位**，因此绕开了「app 无单位字段」这一结构性限制。

### 3.2 够用次数从哪来（D9 = 自动折算 + 手动兜底）

**A. 自动折算（药物级换算表）**

`Drug` 新增两个可选字段：

```dart
final String? doseUnit;                  // 「每次剂量」的单位，如 'mg' / '片' / '针'；null = 未设置
final Map<String, double>? specConversions;
// 规格单位 → 折合多少个 doseUnit。例：{'针': 5} 表示 1针 = 5 mg
// 规格单位 == doseUnit 时无需登记，隐式 c = 1
```

折合公式：
```
折合剂量 = 规格数量 × c(规格单位)
够用次数 = 折合剂量 ÷ dosage
```

| 场景 | doseUnit | dosage | 补货规格 | 换算 | 够用次数 |
|---|---|---|---|---|---|
| 1000元 1针 | mg | 5 | 1 针 | `{针: 5}` | `1×5÷5 = 1` ✅ |
| 30元 28mg | mg | 5 | 28 mg | 隐式 c=1 | `28×1÷5 = 5.6` ✅ |
| 30元 14片 | mg | 5 | 14 片 | `{片: 5}` | `14×5÷5 = 14` ✅ |

**配置入口（渐进式，不强迫提前配置）**
1. **药物表单**（添加/编辑）：`每次剂量` 旁新增**剂量单位**下拉（`mg / ml / 片 / 粒 / 针 / 支 / 单位` + **允许自由输入**）；换算表放在可折叠「规格换算（进阶）」里。
2. **补货面板内联学习**：遇到**未知规格单位**时，就地问 `1 [针] = [5] [mg]`，勾选「记住这次换算」即写入该药物的 `specConversions`。→ 用户在**需要时**才配置，绝大多数人只配一次。

**B. 手动兜底（⚡ 一键折算）**
换算缺失或用户不想配时，补货面板的「这份够用」框：
- **预填 = 规格数量**（覆盖 `14片`/`1针` 多数场景）；
- 右侧一个 ⚡ 按钮：`按每次剂量 5.0 折算 → 5.6 次`，一点即填，**仍可手改**。

**优先级**：`用户手改` > `换算表自动` > `预填=规格数量`。UI 始终回显推导过程，让错值当场暴露。

### 3.3 新模型 `MedicationPurchase`

新文件 `lib/models/medication_purchase.dart`：

```dart
class MedicationPurchase {
  final String id;
  final String medicationId;
  final DateTime timestamp;

  /// 计入库存的补货数量（沿用现有「单位」语义，必填）
  final double stockAmount;

  // ── 价格与规格（整段可留空 = 本次不记价格）──
  final double? totalPrice;    // 本次总花费；null = 未填
  final double? specQuantity;  // 规格数量：28 / 14 / 1
  final String? specUnit;      // 规格单位：mg / 片 / 针 / 支（自由文本）
  final double? doses;         // 本次折合「够用次数」← 加权平均的权重
  final String? note;

  bool get priced => totalPrice != null && (doses ?? 0) > 0;

  /// 派生（不落库）：每规格单位单价
  double? get unitPrice => (totalPrice != null && (specQuantity ?? 0) > 0)
      ? totalPrice! / specQuantity!
      : null;
}
```

- 序列化沿用仓库风格（对齐 [`MedicationLog`](../lib/models/medication_log.dart:37)）：`toJson` / `fromJson` / `listFromJson` / `listToJson`；数值一律 `as num?` 容错。

### 3.4 价格为什么不挂在 `MedicationLog` 上（D7 = 不做时间感知）

需求是「每次使用费用（**平均**）」，不是逐次精确记账。关键性质：

> 按**次数加权**的均值使**总额自动自洽**。例：先 `¥30/14次` 再 `¥40/14次`，均价 `= 70/28 = ¥2.50/次`，28 次 × ¥2.50 = **¥70 = 实际总支出** ✅ 无需逐条快照。

因此：日志**保持纯用法记录**（时间/剂量/部位），**不新增字段** → **零迁移风险**；成本由统计层实时派生。报告里注明「按当前平均单价估算」。
（若将来要逐次精确，可给 `MedicationLog` 加一个 `double? unitCostAtDose` 快照字段；本期明确不做。）

### 3.5 新持久化 Key

| SP Key | 内容 | 默认 |
|---|---|---|
| `medication_purchase_records` | `MedicationPurchase[]` JSON | `[]` |
| `cost_currency_code` | 币种代码（D5） | `'CNY'` |

- `Drug` 的 `doseUnit` / `specConversions` **就地存在 `drug_inventory_list` 里**（随药物走），不另开 key。
- 备份：`exportData()` 全量遍历 key → **自动包含**；恢复：`importData()` 全量回写 → **自动恢复**。
- 老版本 App 读到新 key：`_setValue` 原样写入 SP，**无害**。
- 新版本读老备份 / 老数据：字段缺失 → 空列表 / `null` → 全部显示「未设价格」，**不崩**。

### 3.6 新仓储 `MedicationPriceRepository`

新文件 `lib/storage/medication_price_repository.dart`（对齐 [`MedicationProfileRepository`](../lib/storage/medication_profile_repository.dart:14)）：

```
Future<List<MedicationPurchase>> getAll()
Future<List<MedicationPurchase>> getForDrug(String medId)   // 时间升序
Future<void> add(MedicationPurchase p)
Future<void> deleteByDrug(String medId)                     // 删药时清理孤儿
Future<void> clearAll()
```

### 3.7 新统计服务 `MedicationCostService`（纯函数，可单测）

新文件 `lib/services/medication_cost_service.dart`：

| 方法 | 语义 |
|---|---|
| `avgCostPerDose(purchases)` | **主指标** `Σ totalPrice / Σ doses`，仅计 `priced == true`；无有效记录 → `null` |
| `avgUnitPrice(purchases)` | `Σ totalPrice / Σ specQuantity`（仅供「仅价格」报告的单价行） |
| `totalSpent(purchases)` | `Σ totalPrice` |
| `cumulativeSeries(purchases)` | 累计支出时间序列（成本页趋势图用，可选） |
| `dosesPerDay(Drug d)` | `24 / _intervalInHours`（复用 [`drug_model.dart:253`](../lib/models/drug_model.dart:253) 口径）；离散模式按提醒点数 |
| `remainingDoses(Drug d)` | `currentStock / dosage` |
| `DrugCost.monthlyCost`（**字段**，非方法） | `avgCostPerDose × dosesPerDay × 30` |
| `DrugCost.stockValue`（**字段**，非方法） | `avgCostPerDose × remainingDoses` |
| `summarize(drugs, purchases)` | → `MedicationCostSummary`：总花费 / 月预计 / 库存估值 / 已定价数 / **未定价数** |

**硬规则（验收点）：**
1. 未定价药物：`avgCostPerDose == null` → UI 一律「—」，**不计入任何合计**；汇总必须显式标注「不含未设价格的 N 种」。
2. `totalPrice = 0` 是**合法价格**（赠药），参与平均；`totalPrice = null` 才是「未填」。
3. `doses <= 0` 的记录不参与均价（防御脏数据）。
4. `dosage <= 0` → `remainingDoses` / `monthlyCost` 返回 `null`，**不产生 `Infinity` / `NaN`**。
5. 金额格式化统一走 §3.8。

### 3.8 币种（D5）

新文件 `lib/utils/currency.dart`：

```dart
class Currency {
  final String code;    // 'CNY'
  final String symbol;  // '¥'
  final String label;   // '人民币'
  final int decimals;   // 2（JPY/KRW 为 0）
}

class CurrencyFormat {
  static const Currency cny = Currency('CNY', '¥', '人民币', 2);
  /// 预设列表（getter；内部为不可变 const 列表）
  /// CNY ¥ / USD $ / EUR € / GBP £ / JPY JP¥(0 位) / HKD HK$ / TWD NT$ / KRW ₩(0 位)
  static List<Currency> get presets;

  /// 读 SP；缺失/非法 → 回退 CNY
  static Future<Currency> current();
  static Future<void> set(Currency c);
  static String format(double? amount, Currency c);  // null / NaN / Infinity → '—'
}
```

- **只存数字，币种是纯显示层设置**；切换时选择器内明确写一句 **「仅更换显示符号，不做汇率换算」**（诚实、零实现风险）。
- 设置入口：「我的」→ 新增设置项 **「用药成本」** → 币种选择 `glass_sheet`。遵既有 UI 约定：**`_buildSettingsTile` 统一 `subtitle: null`**，当前币种以 `trailing` 值形式呈现（与「血药浓度模拟端口」同类交互）。
- 需在 `ProfileTab` 设置分组里**按类别新增一行**，不与「外观与显示」混排（遵 UI 约定③）。

---

## 4. 交互层设计

### 4.1 补货面板 `RestockSheet`（新组件，收敛两处入口）

新文件 `lib/widgets/restock_sheet.dart`，替换 [`_addStock()`](../lib/screens/inventory_dashboard_screen.dart:271) 里的裸 `AlertDialog`：

```
┌───────────────────────────────────────────────┐
│  ═══                                          │
│  补货 · 戊酸雌二醇                              │
│  当前库存 12.0 单位 ｜ 历史均价 ¥1,000.00 / 针   │
│  ───────────────────────────────────────────  │
│  本次补货数量 *   [ 1            ]            │ ← 库存增加量（沿用现有语义）
│                                               │
│  价格与规格（选填，可整段留空）                  │
│  ┌─────────────────────────────────────────┐  │
│  │ 录入方式   ( ● 总价 )  ( ○ 单价 )        │  │ ← D1「也可以按单价」
│  │ 本次花费   [ 1000.00 ] 元                │  │
│  │ 本次规格   [ 1      ]  [ 针 ▾ ]          │  │ ← 单位可下拉可选、也可手输
│  │ 折合       = 5 mg  →  够用 1 次          │  │ ← 换算表自动折算（A）
│  │ 这份够用   [ 1      ]  次   ⚡ 按剂量折算 │  │ ← 手动兜底（B）
│  │            ↳ 1针=? [ 5 ] mg  ☑ 记住换算   │  │ ← 未知单位时就地学习
│  │ 实时：单次 ¥1,000.00 ｜ ¥1,000.00 / 针    │  │
│  └─────────────────────────────────────────┘  │
│  备注（选填） [                ]              │
│  ───────────────────────────────────────────  │
│  [取消]                        [确认补货]      │
└───────────────────────────────────────────────┘
```

行为约定：
1. **数量必填**且 > 0，否则 `BrandedToast.error`（沿用既有校验风格）。
2. **价格整段留空** → 只调 `Drug.addStock(amount)`，**不写** `MedicationPurchase`（补货与定价**完全解耦**）。
3. **填了价格** → `addStock` + `add(purchase)`；`totalPrice` 允许为 `0`。
4. **录入方式切换只换算输入框**（`单价 × 规格数量 = 总价`），**存储永远只存 `totalPrice`** → 杜绝双份真相。
5. **够用次数优先级**：手改 > 换算表自动 > 预填 = 规格数量；UI 始终显示推导式。
6. **「本次规格数量」与「补货数量」默认联动**（改一个同步另一个），可手动解绑 → 免重复输入；单位**仅作标签**，**不改变现有库存语义**。
7. 规格单位下拉：`mg / ml / 片 / 粒 / 针 / 支 / 单位` + **允许自由输入**。
8. 非数字/负数 → 内联报错，不提交。
9. 用 `showModalBottomSheet`（对齐 [`RecordDoseDialog`](../lib/widgets/record_dose_dialog.dart:27)），规避 `AlertDialog` 在键盘弹起时被顶飞的既有痛点。

### 4.1b 首次添加药物时的价格录入（用户补充需求）

**问题**：`§4.1` 的补货面板只能给**已存在**的药物录价格；用户第一次添加药物、直接填了「当前库存」时，那笔购入花费**无处可填**。

**方案**：在 [`_DrugFormPage`](../lib/screens/inventory_dashboard_screen.dart:730) 里加一段**可折叠的「首次购入价格（选填）」**，与补货面板同一套语义：

| 约定 | 实现 |
|---|---|
| **必须可选、默认不填写** | `_showFirstPrice = false` 默认**收起**；4 个输入框初始全空；`_firstPriceTyped` 只看输入框内容 → 未展开时恒为 `false`，**老流程行为零变化** |
| 只在「添加」时出现 | `if (!_isEditing)` —— 编辑药物不是一次购买，不显示（也就不会重复记账） |
| 与补货面板同口径 | 支持**按总价 / 按单价**切换；`够用次数` 同样是「用户手改 > 换算表 → 预填 = 规格数量」；带 ⚡ 按剂量折算；表单里刚配的「剂量单位 / 规格换算」**立即参与折算** |
| 折算结果可见 | 实时回显「单次 ¥x.xx」，让错值当场暴露 |
| 收起不吞数据 | `_firstPriceTyped` **不看折叠状态**：填完价格再收起，记录依然成立（否则收起会静默丢用户输入） |
| 返回值 | `_DrugFormPage.show()` 改为返回 `DrugFormResult(drug, firstPurchase?)`；`_addDrug()` 在写入药物后，**仅当 `firstPurchase != null`** 才追加价格记录 |

> 两处价格 UI（补货面板 / 添加表单）有意**共用 `MedicationCostService` 的纯函数**来保证口径一致；UI 层面保留各自实现（表单更紧凑）。若后续要收敛为单一组件，见 §10 非目标的延伸。

### 4.1c 药物表单改为整屏页面（用户反馈）

**问题**：`_DrugFormPage` 原先是底部弹层（`showModalBottomSheet` + `isScrollControlled`）。字段越加越多（名称 / 库存 / 剂量 / 剂量单位 / 规格换算 / 首次购入价格 / 模式 / 周期 / 下次给药 / 提醒时间）之后，弹层被撑到接近满屏，**滚动区被顶部标题与底部 CTA 夹在中间，可用高度很小**，体验接近"半屏里塞一屏内容"。

**方案**：改为**整屏页面**。

| 项 | 改动 |
|---|---|
| 打开方式 | `showModalBottomSheet` → `Navigator.of(context).push(MaterialPageRoute)` |
| 顶部 | 新增 `AppBar`：左上角 `Icons.arrow_back_rounded` 返回（`tooltip: '返回'`）+ 标题「添加药物 / 编辑药物」<br>替换掉原来的**拖拽指示条**（整屏页里没有"拖拽关闭"语义） |
| 内容区 | `Flexible` → **`Expanded`** + `SingleChildScrollView`，滚动区拿到整屏剩余高度 |
| 底部 CTA | 由 `Padding(bottom: 32)` 改为 **`SafeArea(top: false)`** + `Padding(bottom: 16)`，固定在底部且避开手势条 |
| 键盘 | 删掉手写的 `MediaQuery.viewInsets.bottom` 占位 —— 整屏 `Scaffold` 的 `resizeToAvoidBottomInset`（默认 true）已正确处理 |
| 类名 | `_DrugFormSheet` → **`_DrugFormPage`**（`_DrugFormPageState`），避免名字继续误导后续维护者 |
| 返回值 | 不变：仍 `Navigator.pop(context, DrugFormResult(...))`，`show()` 的对外签名与调用点不受影响 |

> `show()` 静态方法名保留（语义为"呈现该表单"），仅内部实现由弹层换为页面路由。

### 4.2 展示位点（D8：四处全做）

| 位点 | 内容 | 文件 |
|---|---|---|
| ① 药物卡片库存面板 | 「日消耗」右侧新增 **「单次花费」**（`¥5.36` 或 `—`） | [`medication_card.dart:481`](../lib/widgets/medication_card.dart:481) `_infoCell` |
| ② 仪表盘汇总卡 | 追加 **「月预计 ¥xx ｜ 库存估值 ¥xx」**，小字注明「不含未设价格的 N 种」 | [`inventory_dashboard_screen.dart:473`](../lib/screens/inventory_dashboard_screen.dart:473) |
| ③ 首页存量摘要 | 已有「续航」行后追加 `｜ 月花费 ¥xx`（**无价格时整段不显示**，不留空位） | [`medication_stock_summary.dart`](../lib/widgets/medication_stock_summary.dart:1) |
| ④ **成本详情页**（新） | 顶部合计（总花费/月预计/库存估值）→ 每药物卡：单次花费 / 均价 / 补货历史（时间·金额·规格·次数）/ 月成本 / 库存估值 → **累计支出趋势**（`fl_chart`，可选）；入口：仪表盘汇总卡点击 | 新文件 `lib/screens/medication_cost_screen.dart` |

> **UI 约定遵循**：不引入功能开关（价格是数据不是开关），单一数据源仍是 SP；说明只写一句短提示；布局用确定性行结构（约定⑤）。

### 4.3 用药提醒 / 打卡路径（D6：不输入，自动派生）

- 通知栏动作**不新增**「填价格」——系统通知无法承载文本输入。
- **打卡（`executeMedicationDose`）完全不改**：扣库存 + 写日志，与价格无关。
- **支出来自派生**：`成本详情页 / 导出报告` 里，每条打卡记录的费用 = `当前单次费用`，累计 = `打卡次数 × 单次费用` → 与「按次数加权的均价」总额天然自洽（§3.4）。
- 「提醒 → 记账」的价格入口落在**卡片 / 仪表盘的补货按钮**（§4.1 两个入口）。

---

## 5. 导出 PNG 设计

### 5.1 入口（母页面）

**主入口**：药物存量仪表盘 AppBar 右侧新增 `Icons.image_outlined` → `MedicationReportExportScreen`。
理由：该页是药物数据母页面，AppBar 目前**无多余按钮**，不冲突。
**次入口（可选）**：`我的 → 数据导出与恢复` 下方并列「导出用药记录图片」，复用同页。

### 5.2 配置页 `MedicationReportExportScreen`

新文件 `lib/screens/medication_report_export_screen.dart`：

| 控件 | 选项 | 默认 |
|---|---|---|
| **内容模式**（三选一） | 仅记录 / 仅价格 / 价格+记录 | 价格+记录 |
| **打码**（开关，每种模式各自可选） | 开 / 关 | 关 |
| **时间范围** | 近 30 天 / 近 90 天 / 全部 | 近 90 天 |
| **药物范围** | 全部 / 勾选若干 | 全部 |
| 预览区 | 实时刷新报告长图 | — |
| 底部操作 | 保存到相册 / 保存为文件 / 分享 | — |

### 5.3 报告内容

```
┌──────────────────────────────────────────────┐
│ [logo_in.png]  Trans Prism · 稳态光盒          │ ← 页眉：logo + App 名
│                用药记录与费用报告              │
│                2025-03-01 ~ 2025-05-30        │
│                生成于 2025-05-30 21:04        │
│                ⚠ 已打码                        │ ← 仅打码时出现
├──────────────────────────────────────────────┤
│ ① 仅记录                                      │
│   汇总：用药 42 次 ｜ 覆盖 31 天 ｜ 平均间隔 2.1 天 │
│   时间线：05-30 20:00 · 戊酸雌二醇 · 5.0 mg · 左臂 │
│          …                                    │
├──────────────────────────────────────────────┤
│ ② 仅价格                                      │
│   戊酸雌二醇 单次 ¥5.36 · 月 ¥22.96 · 累计 ¥30  │
│            均价 ¥1.07/mg · 库存估值 ¥19.29     │
│   合计：月预计 ¥22.96 ｜ 库存估值 ¥19.29        │
│   * 不含未设价格的 1 种药物                     │
├──────────────────────────────────────────────┤
│ ③ 价格+记录 → ① 时间线每行右侧带该次费用 + ② 汇总 │
├──────────────────────────────────────────────┤
│ [非医疗建议声明] 本图由 Trans Prism 本地生成，   │
│ 不包含任何身份信息，未上传网络。                 │
│ 费用按当前平均单价估算。                        │
└──────────────────────────────────────────────┘
```

> **上例②③ 的数据（可复算）**：戊酸雌二醇 `doseUnit=mg`、`dosage=5`，补货 `30元 / 28mg` → 够用 `28÷5 = 5.6` 次 → 单次 `30÷5.6 = ¥5.36`、均价 `30÷28 = ¥1.07/mg`、累计 `¥30.00`；设每 7 天一次（`dosesPerDay = 1/7`）→ 月 `5.36 × 30/7 = ¥22.96`；当前库存 18 → 剩余 `18÷5 = 3.6` 次 → 库存估值 `5.36 × 3.6 = ¥19.29`。

### 5.4 打码规则（D3）

| 字段 | 打码后 |
|---|---|
| 药名 | 稳定映射「药物 A / B / C」（按首次出现顺序，同一次导出内一致） |
| 剂量数值 | `—` |
| 注射部位 | 隐藏 |
| 备注 | 隐藏 |
| **金额** | **保留**（价格模式的核心价值） |
| 文件名 | 不含药名，固定 `transprism_med_report_yyyyMMdd.png` |

### 5.5 渲染与保存

| 环节 | 方案 | 理由 |
|---|---|---|
| 报告构建 | 新文件 `lib/widgets/medication_report_view.dart`：**纯展示、无交互、固定宽度 750px** | 预览与导出**同一份 Widget**，杜绝「所见非所得」 |
| 栅格化 | `RepaintBoundary` + `RenderRepaintBoundary.toImage(pixelRatio: 3.0)` → `toByteData(png)` | 零新依赖；复用已验证范式 [`svg_preview_screen.dart:178`](../lib/screens/svg_preview_screen.dart:178) |
| 长图保护（D4） | 单图高度上限 **8000px**；超出按内容切片输出多张 `_1.png` `_2.png` | 规避 GPU 最大纹理尺寸导致的 `toImage` 失败/白图 |
| 落盘 | 复刻 `SvgExportService.saveBytes` 写法（`path_provider` + `File.writeAsBytes`） | 与既有导出一致 |
| 保存相册 | [`GallerySaverService.saveImage()`](../lib/services/gallery_saver_service.dart:22)；`MissingPluginException` 降级为「已保存到文件」 | 完全复用 |
| 分享 | `share_plus` `Share.shareXFiles` | 已有依赖（[`image_converter_screen.dart:591`](../lib/screens/image_converter_screen.dart:591)） |
| Web | `toImage` 走 CanvasKit；保存走分享/下载分支（对齐 `image_converter_screen` 的 `kIsWeb` 处理） | 平台一致性 |

### 5.6 隐私红线

- 导出图**不含** 药物 id / uuid / 设备信息 / 备份数据。
- 生成全程**零网络请求**。
- 打码为**默认推荐**但不强制（用户明确要求三种模式各自可选）。

---

## 6. 涉及文件清单

### 新增
| 文件 | 职责 | 阶段 |
|---|---|---|
| `lib/models/medication_purchase.dart` | 价格+规格记录模型 + JSON | P0 |
| `lib/storage/medication_price_repository.dart` | SP 读写 | P0 |
| `lib/services/medication_cost_service.dart` | 均价/单次/月成本/汇总（纯函数） | P0 |
| `lib/utils/currency.dart` | 币种定义 + 格式化 + SP 持久化 | P0 |
| `lib/widgets/restock_sheet.dart` | 补货 + 价格/规格/换算录入面板 | P1 |
| `lib/widgets/medication_report_view.dart` | 报告长图 Widget（预览=导出同源） | P3 |
| `lib/services/medication_report_renderer.dart` | Widget → PNG bytes（含分片） | P3 |
| `lib/screens/medication_report_export_screen.dart` | 导出配置 + 预览 + 保存 | P3 |
| `lib/screens/medication_cost_screen.dart` | 用药成本详情页（D8 ④） | P2 |
| `test/medication_cost_service_test.dart` | 统计算法单测 | P0 |
| `test/currency_test.dart` | 格式化/回退单测 | P0 |

### 修改
| 文件 | 改动 | 阶段 |
|---|---|---|
| `lib/models/drug_model.dart` | 新增 `doseUnit` / `specConversions`（**可选字段**，`toJson`/`fromJson` 容错；`copyWith` 需加 `clearX` 标志位，参考 [`MedicationLog.copyWith`](../lib/models/medication_log.dart:77) 的写法） | P0 |
| `lib/screens/inventory_dashboard_screen.dart` | 药物表单加「剂量单位」+ 换算表折叠区；`_addStock` 改用 `RestockSheet`；`_deleteDrug` 清理价格记录；汇总卡加成本行（D8 ②）；AppBar 加导出入口；成本页入口 | P0/P1/P2/P3 |
| `lib/main.dart` | `ProfileTab` 新增设置项「用药成本」→ 币种选择（D5） | P2 |
| `lib/widgets/medication_card.dart` | 库存面板加「单次花费」栏（D8 ①） | P2 |
| `lib/widgets/medication_stock_summary.dart` | 摘要行追加月花费（D8 ③） | P2 |
| `docs/DATA_EXPORT_COMPATIBILITY.md` | 补 `medication_purchase_records` / `cost_currency_code` / `Drug` 新字段说明 | P4 |
| `REPO_MAP.md` | §1 表格补新文件与价格数据流 | P4 |
| `ARCHITECTURE_DECISIONS.md`（workspace 根） | 追加 ADR：价格独立存储 + 次数锚定 + 币种为显示层 + 纯本地 PNG 导出 | P4 |
| `README.md` | 功能列表补「用药成本」 | P4 |

### 明确不改
`pubspec.yaml`（无新依赖）、`medication_log.dart`（D7 ✅）、`medication_service.dart` 的打卡路径（D6 ✅）、`data_migration_service.dart`（全量 key 遍历已覆盖）、`notification_service.dart`。

---

## 7. 实施阶段与验收

### P0 · 数据层（可独立验证）
- 产出：§3 四个新文件 + `Drug` 新字段 + 单测。
- 验收（`flutter test`）：
  - 按**次数**加权：`¥100/10次` + `¥80/5次` → **¥12.00/次**（非 ¥13.00 的算术平均）；
  - `30元/14片`（14 次）→ `¥2.14/次`；`1000元/1针`（1 次）→ `¥1000.00/次`；
  - **换算表**：`doseUnit=mg, dosage=5, {针:5}` + `1针` → 次数 `1`；`28mg` → `5.6`；`{片:5}` + `14片` → `14`；
  - 混合缺失：1 条 `null` + 1 条 `priced` → 只按后者算；
  - 全缺失 → `null`（**不返回 0**）；
  - `totalPrice = 0` → 有效值 `¥0.00`，与「未设价格」严格区分；
  - `doses <= 0` / `dosage <= 0` → 优雅 `null`，无 `Infinity`/`NaN`；
  - 币种：缺失/非法 code → 回退 `CNY`；`JPY` 无小数位；`¥1,000.00` 千分位正确；
  - **回归**：`Drug` 老 JSON（无 `doseUnit`/`specConversions`）反序列化结果与改动前**逐字段一致**，且 `toJson` 往返稳定。

### P1 · 录入口
- 产出：`RestockSheet` + 仪表盘接入 + 删药清理 + 换算表学习。
- 验收：两个补货按钮弹出**同一面板**；整段留空后库存增加且**无**价格记录；填价格后均价即时刷新；总价/单价切换只换算输入框、落库一致；未知规格单位「记住换算」后**下次自动折算**；删药后其价格记录消失。

### P2 · 展示（四处 + 币种设置）
- 产出：卡片「单次花费」栏、汇总卡成本行、首页摘要行、成本详情页、我的页币种设置。
- 验收：未定价药物显示「—」且不计入合计；汇总显式标注未定价数量；成本页补货历史与金额正确；**切换币种后全 app 金额符号同步变化且不换算数值**；浅色/深色主题无溢出。

### P3 · 导出 PNG
- 产出：报告 Widget + 渲染器 + 导出页 + 仪表盘入口。
- 验收：三种模式 × 打码开关 = **6 种组合**均生成正确 PNG；图含 logo 与 App 名；**打码后断言报告文本不含任何原药名/剂量/部位**；长记录不白图（触发分片）；相册/文件/分享三路可用；导出图无 id 类信息；币种符号与设置一致。

### P4 · 文档与回归
- 产出：§6「修改」中的文档项 + ADR。
- 验收：老备份导入后 app 正常、全部显示「未设价格」；新备份导出/导入价格记录与换算表无损；`flutter analyze` 无新增告警。

### 命令
```bash
cd Trans-Prism
flutter analyze
flutter test
flutter build apk --debug   # 冒烟（实现者本地）
```
> ⚠️ 本机已实测：`flutter --version` / `flutter analyze` / `flutter test` 在 `danger-full-access` 下可用（Flutter 3.44.4 / Dart 3.12.2）。
> **基线（改动前实测）**：`flutter analyze` = **157 issues = 0 error / 11 warning / 146 info**；`flutter test` = 通过（`test/widget_test.dart` 1 例）。
> 因此实现者的验收线是：**不引入任何 `error •`**，且**不要去修既有的 info 告警**。

### 7.1 实现注记（captain 接口复核时发现，P1/P2/P3 必读）

1. **`DrugCost.spent` 是非空 `double`**（无价格记录时为 `0.0`）。UI 判断「未设价格」必须用 **`costPerDose == null`**（或 `pricedCount == 0`），**绝不能用 `spent == 0`** —— 因为 `totalPrice == 0`（赠药/免费）是**合法价格**，此时 `spent` 同样是 `0.0`，但该药**已定价**，必须参与合计。
2. **`_DrugFormPage._submit()` 是「新建 `Drug(...)`」而不是 `copyWith`**（见 [`inventory_dashboard_screen.dart:672`](../lib/screens/inventory_dashboard_screen.dart:672) 起的两个分支）。因此编辑药物时**必须显式带上 `doseUnit` / `specConversions`**，否则用户**编辑一次药物就会静默丢失剂量单位与换算表**。
3. `Drug.copyWith` 已支持 `clearDoseUnit` / `clearSpecConversions` 标志位（[`drug_model.dart:446`](../lib/models/drug_model.dart:446)）。
4. **并发开发纪律**：多个 agent 并行改同一个 Flutter package 时，`flutter analyze` / `flutter test` 是**全工程**的，必然看到别人尚未写完的文件。请**只处理自己文件内的错误**，**绝不要去「修」自己 scope 之外的文件**；最终由 captain 跑一次权威的全量 `flutter analyze` + `flutter test` 收口。

---

## 8. 决策点状态

| # | 决策 | 状态 |
|---|---|---|
| D1 | 录入口径 | ✅ 自定义规格 + 价格，支持总价/单价 |
| D2 | 平均口径 | ✅ 加权平均（权重 = 够用次数） |
| D3 | 打码范围 | ✅ 藏药名/剂量/部位/备注，保留金额 |
| D4 | 超长记录 | ✅ 自动分片多张 PNG |
| D5 | 币种 | ✅ 默认 CNY，「我的」可改（仅换符号，不换算汇率） |
| D6 | 打卡记价 | ✅ 不输入，支出自动派生 |
| D7 | 均价时间感知 | ✅ 不做（次数加权使总额自洽，§3.4） |
| D8 | 展示位点 | ✅ 四处全做 |
| D9 | 够用次数来源 | ✅ 换算表自动折算 **+** ⚡ 手动兜底（两者都做） |

**无待确认项** → 可直接进入 P0。

---

## 9. 风险与规避

| 风险 | 等级 | 规避 |
|---|---|---|
| 「够用次数」填错 → 均价失真 | **高** | UI 始终回显推导式（`= 5 mg → 够用 1 次`）+ 实时「单次 ¥x」+ 历史均价对照，错值当场暴露 |
| 换算表配置门槛劝退用户 | 中 | **渐进式**：不提前配置，遇到未知单位时才就地问一次 + 「记住」；⚡ 按钮永远可绕过 |
| 长图 `toImage` 超 GPU 最大纹理 → 白图/异常 | 中 | 8000px 上限 + 分片（D4）+ 失败兜底 Toast |
| 打码不彻底泄露隐私（图会发到公开渠道） | **高** | 打码映射集中在报告 Widget 的**数据注入层单一出口** + 单测断言「打码后文本不含任何原药名」 |
| `Drug` 加字段破坏老数据 | **高** | 字段全部**可选 + `as num?`/`as String?` 容错**；P0 加**逐字段回归断言**；`copyWith` 用 `clearX` 标志位 |
| 均价随补货变动让历史数字「变化」引发困惑 | 中 | 报告/成本页标注「按当前平均单价估算」；总额自洽（§3.4） |
| 总价/单价双录入导致双份真相 | 中 | **只存 `totalPrice`**，切换仅换算输入框 |
| 币种切换被误解为汇率换算 | 中 | 选择器内明写「仅更换显示符号，不做汇率换算」 |
| 删药产生孤儿价格记录 | 低 | `_deleteDrug` 内 `deleteByDrug` + 单测 |
| `totalPrice = 0` 被误判为「未填」 | 中 | 模型层 `double?` 严格区分 + 单测 |
| 深色/浅色主题与既有玻璃组件风格不一致 | 低 | 复用 `BrandedToast` / `GlassXxx` / `Theme.of(context)` 颜色口径，两主题自查 |

---

## 10. 非目标（本期不做）

- 不做云端同步 / 多设备价格共享。
- 不做小票 OCR 或药品价格联网查询。
- 不做**汇率换算**（币种仅换符号）。
- 不做逐次精确记账快照（D7）。
- 不改动 PK 模拟（WebView/Oyama）侧的任何数据。
- 不重构 app 既有「单位」体系（`dosage` / `currentStock` 仍为无单位数字；`doseUnit` 是**叠加**的可选标签，不改变库存/扣减语义）。

---

## 11. 实现落地记录（P0–P4）

### 交付文件

| 文件 | 类型 | 职责 |
|---|---|---|
| `lib/models/medication_purchase.dart` | 新增 | 价格 + 规格记录模型（JSON 全容错） |
| `lib/storage/medication_price_repository.dart` | 新增 | SP key `medication_purchase_records` 读写 |
| `lib/services/medication_cost_service.dart` | 新增 | 均价 / 单次 / 月成本 / 汇总（纯函数） |
| `lib/utils/currency.dart` | 新增 | 币种定义 + 格式化 + SP 持久化 |
| `lib/widgets/restock_sheet.dart` | 新增 | 补货 + 价格 / 规格 / 换算录入面板 |
| `lib/screens/medication_cost_screen.dart` | 新增 | 成本详情页（含累计支出趋势） |
| `lib/widgets/medication_report_view.dart` | 新增 | 报告长图（预览 = 导出同源） |
| `lib/services/medication_report_renderer.dart` | 新增 | Widget → PNG（含长图分片） |
| `lib/screens/medication_report_export_screen.dart` | 新增 | 导出配置 + 预览 + 保存 / 分享 |
| `test/medication_doses_resolution_test.dart` | 新增 | 「够用次数」折算口径单测（13 例，含抽取重构的等价性验证） |
| `lib/models/drug_model.dart` | 修改 | +`doseUnit` / `specConversions`（可选、容错、**+65 行 0 删除**） |
| `lib/services/medication_service.dart` | 修改 | +`upsertDrug()`（仅新增） |
| `lib/screens/inventory_dashboard_screen.dart` | 修改 | 补货改用面板、表单剂量单位与换算表、删药清理、汇总卡成本行、AppBar 两个入口 |
| `lib/widgets/medication_card.dart` | 修改 | 库存面板新增「单次花费 ｜ 月」行 |
| `lib/widgets/medication_stock_summary.dart` | 修改 | 首页摘要追加「月花费」（无价格时该行不显示） |
| `lib/main.dart` | 修改 | 「我的」新增「用药成本明细」+「成本币种」两项 |

**未改动**：`pubspec.yaml`（**0 新依赖**）、`medication_log.dart`（D7 决策）、`data_migration_service.dart`（全量 key 遍历已自动覆盖新 key）、`notification_service.dart`。

### 验收证据

| 项 | 结果 |
|---|---|
| `flutter analyze` | **0 error**；warning 11 条与改动前基线**逐条一致（0 新增）**；新增 10 条 `info` 全为 `withOpacity` 弃用提示，与仓库既有风格一致 |
| `flutter test` | **全部通过 94 例**（数据层 67 + 报告验收 13 + 折算口径 13 + 既有 `widget_test` 1） |
| 6 种导出组合 | `test/medication_report_view_test.dart` 逐一构建断言（3 模式 × 打码开关） |
| 隐私红线 | 单测断言：打码后文本**不含任何原药名 / 剂量 / 部位**，且**金额保留** |
| `Drug` 向后兼容 | 单测断言：老 JSON 反序列化逐字段一致、`toJson` **连 key 数量都不变** |

### 交付后补充实现（用户反馈）

- **首次添加药物时也能录价格**：原设计只在「补货」时录价，导致新药第一次填「当前库存」时那笔花费无处可填。现于 `_DrugFormPage` 增加**可折叠的「首次购入价格（选填）」**（默认收起、默认留空；编辑药物时不显示），`_DrugFormPage.show()` 返回类型由 `Drug?` 改为 `DrugFormResult(drug, firstPurchase?)`，`_addDrug()` 仅在 `firstPurchase != null` 时追加价格记录。详见 §4.1b。
- **药物表单改为整屏页面**（原为过高的底部弹层）。详见 §4.1c。
- **「够用次数」折算抽成共用纯函数**：新增 [`MedicationCostService.resolveDosesFrom`](../lib/services/medication_cost_service.dart:224)，直接接收 `specQuantity / specUnit / doseUnit / dosage / specConversions` 字段。这样**药物尚未落库的表单草稿**也能用同一套口径折算 —— 原先补货面板与添加表单各写了一份 `c = (unit == doseUnit) ? 1 : conversions[unit]`，是最容易悄悄跑偏的重复逻辑。既有的 `resolveDoses({Drug})` 改为**委托**该函数，行为逐位不变（由新增的 12 组等价性用例锁死）。新增测试文件 [`test/medication_doses_resolution_test.dart`](../test/medication_doses_resolution_test.dart:1)（13 例）。
- **修复输入框缺圆角**：`_FilledField`（药物名称 / 当前库存 / 每次剂量 / 剂量单位）原先用 `InputBorder.none`，是**纯直角矩形**，与全局「卡片/设置项圆角 16」的语言不一致；改为 `OutlineInputBorder(borderRadius: 16)`，并补上**品牌粉聚焦描边**（原先无边框导致看不出焦点）。

### 与规划的两处偏差（文档已同步更正）

1. `monthlyCost` / `stockValue` 实现为 **`DrugCost` 的字段**，而非 `MedicationCostService` 的独立静态方法（§3.7 已更正）。
2. `CurrencyFormat.presets` 是 **getter**、`format` 接受**可空** `double?`（`null` / `NaN` / `Infinity` → `—`）（§3.8 已更正）。

### 实现期修正的真实缺陷

- 加权平均的「算术平均对照值」原稿写成 `¥11.00`，实为 `(10+16)/2 = ¥13.00`（已更正，并被单测锁死为断言 `≠ 13.00`）。
- `RenderRepaintBoundary.layer` 是 `@protected`，无法从外部访问 → 改为自定义 `MedicationReportBoundary`（子类内合法暴露 `layer`），分片才能用**纯公开 API** 实现。

### 已知限制

- 「够用次数」在规格单位 ≠ 剂量单位且**未配换算表**时按「规格数量」预填，用户可点 ⚡ 按剂量折算或补配换算表；**不做静默纠错**（不替用户猜）。
- 分片上限 24 张；极端超长会截断并在控制台告警，建议缩短时间范围。
- 币种仅换符号，**不做汇率换算**（决策 D5）。
- 报告长图固定 750px 宽，预览区靠双指缩放查看（保证导出尺寸与设备无关）。
