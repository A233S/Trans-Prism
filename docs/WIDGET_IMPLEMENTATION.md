# 桌面用药小组件实装说明（Android / Glance）

> 目标：把定稿的 Trans Prism 用药小组件从 HTML 预览实装进 App。
> 视觉唯一真相：`outputs/widget_preview.html` + 预览截图。
> **未改动**：业务逻辑、文案、App 首页、既有存储结构。

---

## 一、Token 表（自 HTML 逐值摘出）

### 浅色

| Token | Hex | 用途 |
|---|---|---|
| `card` | `#FFFFFF` | 卡片底（纯白） |
| `title` | `#1A1A1A` | 标题、药名、时间（未逾期）、周计数 |
| `muted` | `#8A8580` | 库存文案、「近 7 天」、小卡「已超」/「小时」、图标 |
| `pink` | `#E8899A` | 进度条（逾期）、状态点（逾期）、7 天完成点、「记一次」按钮 |
| `cyan` | `#4AB8C8` | 进度条（未逾期）、状态点（未逾期）、剩余时间文字 |
| `amber` | `#D4A017` | **仅**库存告急：短进度条 + 「库存告急」描边 |
| `track` | `#EDE8E4` | 进度条轨道、7 天空心点 |
| `hairline` | `#EFE7E1` | 底栏分割线、卡片细边 |
| `onPink` | `#FFFFFF` | 粉底之上的文字 |

### 深色

| Token | Hex | 用途 |
|---|---|---|
| `card` | `#211C1A` | **暖黑**卡片底（与 App 米白同源的夜间，**非** Material `#121212`） |
| `title` | `#F3EEEA` | 标题、药名、时间（未逾期） |
| `muted` | `#A39A94` | 库存文案、说明文字、图标 |
| `pink` | `#F0A3B0` | 逾期强调、主按钮 |
| `cyan` | `#6BC9D4` | 未逾期的剩余时间 |
| `amber` | `#E0B84A` | **仅**库存告急 |
| `track` | `#3A322E` | 进度条轨道、7 天空心点（暖灰，非冷灰） |
| `hairline` | `#3A322E` | 细边（暖） |
| `onPink` | `#211C1A` | 粉底之上的文字（暖黑） |

### 尺寸 / 字号（HTML px → dp/sp 同值）

| 项 | 值 |
|---|---|
| 卡片圆角 | `24dp` |
| 中卡内边距 | `20 / 18 / 20 / 16 dp`（start/top/end/bottom） |
| 进度条 | 高 `2dp`，左缩进 `27dp`（与药名左边缘对齐） |
| 状态点 | `6dp` 圆 |
| 7 天圆点 | `7dp` 圆，间距 `6dp` |
| 中卡字号 | 标题 `13`、药名 `13`、库存 `10.5`、时间 `12.5`、周标签 `10.5`、周计数 `11` |
| 小卡字号 | 药名 `11.5`、状态 `11`、**大数字 `62`**、单位 `13`、按钮 `11.5` |
| 按钮高度 | 中卡胶囊 ≈`22dp`；小卡 `30dp` |

> 实现位置：`android/app/src/main/kotlin/com/daanser/transprism/widget/MedsWidgetTokens.kt`
> 逐 token 以 `ColorProvider(day, night)` 注入 —— 与 GlanceTheme 同源、自动响应系统深浅色。

---

## 二、文件清单

### 新增（Android 原生）

| 文件 | 职责 |
|---|---|
| `widget/MedsWidgetTokens.kt` | 设计 token（色 / 尺寸 / 字号）+ 语义取色函数 |
| `widget/MedsWidgetData.kt` | 展示模型 + 只读 Flutter SharedPreferences + 预览假数据 |
| `widget/MedsWidgetActions.kt` | 动作契约（action key / extra key / 参数组装） |
| `widget/MedsWidgetCommon.kt` | 共享原子组件（图标、状态点、周点、三种按钮） |
| `widget/MediumMedsWidget.kt` | **中卡** Glance composable（4x2 / 4x3） |
| `widget/SmallMedsWidget.kt` | **小卡** Glance composable（2x2） |
| `widget/MedsWidgetReceivers.kt` | 两个 Receiver + `MedsWidgetUpdater.refreshAll()` |
| `res/xml/meds_widget_medium_info.xml` | 中卡 appwidget-provider（尺寸 / resize / 描述） |
| `res/xml/meds_widget_small_info.xml` | 小卡 appwidget-provider |
| `res/drawable/ic_syringe.xml` | 针筒 vector（路径转自 HTML 内联 SVG） |
| `res/values/strings.xml` | 两个 widget 的 label / description |

### 修改

| 文件 | 改动 |
|---|---|
| `android/settings.gradle` | 加 `org.jetbrains.kotlin.plugin.compose` 2.2.20 |
| `android/app/build.gradle` | apply kotlin + compose 插件；`buildFeatures.compose = true`；`minSdk = max(flutter.minSdkVersion, 23)`；加 `androidx.glance:glance-appwidget:1.2.0` |
| `android/app/src/main/AndroidManifest.xml` | 注册两个 AppWidget Receiver（`exported=true`） |
| `android/.../MainActivity.kt` | 新增 `widget_action` MethodChannel（`getLaunchAction` / `refreshWidgets` / `onNewIntent` 推送）；相册逻辑未动 |
| `lib/main.dart` | 新增 `appNavigatorKey`、`widgetTabRequest`、`_widgetChannel`；`_AppRootControllerState` 加 `_initWidgetActions()`；`_MainDashboardState` 加 Tab 监听 |

---

## 三、数据流与动作闭环

### 展示（只读，不新增存储）

```
Flutter SharedPreferences (FlutterSharedPreferences, key 前缀 flutter.)
  ├─ flutter.drug_inventory_list  → 药名 / 库存 / 剂量 / 间隔 / nextDoseTime
  └─ flutter.medication_logs      → 近 7 天打卡、今日已打卡数
        ↓  (Kotlin 只读解析)
   MedsWidgetDataLoader.load()
        ↓
   MedsWidgetData { headerText, items[], week, small }
        ↓
   MediumMedsWidget / SmallMedsWidget
```

- 打卡、扣库存、重排通知**仍全部由 Dart 侧执行**，原生侧不复制任何写入逻辑 → 无双写口子。

### 动作（点击 → 既有 use case）

```
小组件按钮 → actionStartActivity<MainActivity>(extra: tp_widget_action / drug_id)
        ↓
MainActivity.widgetActionFrom(intent)
        ↓  MethodChannel "com.daanser.transprism/widget_action"
Dart _dispatchWidgetAction()
        ├─ record_dose  → MedicationService.executeMedicationDose(drugId)   ← 既有 use case
        │                 → invokeMethod('refreshWidgets') 刷新桌面卡片
        ├─ stock_alert  → Navigator.push(InventoryDashboardScreen)          ← 既有页面
        └─ open_meds    → widgetTabRequest = 0（切到首页，含用药模块）
```

- 冷启动：动作暂存于 `pendingWidgetAction`，Dart 启动后调 `getLaunchAction` 取走（取完即清）。
- 热启动（`singleTop`）：`onNewIntent` 直接推送 `onWidgetAction`。

### 文案映射（与预览逐字一致）

| 预览 | 推导规则 |
|---|---|
| `今日 1/4` | 分子 = 今日打卡条数（**按分母封顶**：补打卡超额时显示 `4/4` 而非 `6/4`）；分母 = Σ 每药今日计划次数（离散模式按时刻数，间隔模式按 `24h/间隔`，至少 1） |
| `已超 9 小时` | `nextDoseTime` 已过 → `已超 {小时} 小时` |
| `1天20小时` | 未逾期且 ≥24h → `{天}天{小时}小时`（无空格）；不足一天 → `{小时} 小时` |
| `库存不足 1 次` | 剩余次数 ≤ 2 → `库存不足 {n} 次`（琥珀） |
| `剩 4 次` | 否则 → `剩 {n} 次` |
| `5/7` | 近 7 天有打卡记录的天数 / 7 |
| 进度条宽度 | 告急固定 `0.22`；否则 `剩余次数/30`，clamp 到 `[0.28, 0.78]` —— **永不拉满** |

> 若「今日 x/y」的产品口径不同（例如按药物去重），只需改 `MedsWidgetDataLoader.todayPlanned()` 一个函数。

---

## 四、对照截图的差异表

> 已实际解包 `glance-appwidget-1.2.0.aar` 逐项核对字节码，以下偏差**均为 Glance 1.2.0 的能力边界**，非设计改动。

| # | 设计稿 | 实装 | 偏差 | 原因 / 处置 |
|---|---|---|---|---|
| 1 | `font-variant-numeric: tabular-nums` | **无法实现** | 单行内数字间距略不匀（每行 ≤2 个数字，目视 < 1px） | Glance 1.2.0 的 `androidx.glance.text.TextStyle` 只有 color/fontSize/fontWeight/fontStyle/textAlign/textDecoration/fontFamily 七个参数，**无 `fontFeatureSettings`**。右对齐仍由 `defaultWeight` 布局保证 —— 对齐感不丢 |
| 2 | 进度条 2px 圆角短条 | `LinearProgressIndicator(progress, …)` + `height(2.dp)` | 实际高度可能 2–4px | Glance 无 `fillMaxWidth(fraction)`，`defaultWeight()` 也不接受权重参数，**无法手工按比例绘制**；`LinearProgressIndicator` 是唯一按比例填充途径，其 `progressDrawable` 内边距不受控。**需真机确认实际高度** |
| 3 | 空心点 / 琥珀描边（`border: 1px`） | 双层 Box + 圆角差 1dp | 视觉等价 | Glance 1.2.0 **没有 `border` modifier**（已确认字节码无 BorderKt） |
| 4 | 浅色卡 `box-shadow: 0 1px 2px rgba(60,40,30,.04)` | 无阴影 | 不可见（alpha 0.04） | Glance 无阴影 API；该阴影在 HTML 中本身已极轻 |
| 5 | 深色卡 `rgba(33,28,26,0.92)`（半透） | `#211C1A` 不透明 | 深色卡不透壁纸 | Android 12+ 系统会给 widget 背景施加不透明遮罩，半透明不可靠；取不透明以保证壁纸上的对比度 |
| 6 | 字重 500 / 600 | `Medium(500)` / `Bold(700)` | 按钮与数字略粗 | Glance 的 `FontWeight` 只有 Normal / Medium / Bold 三档 |
| 7 | 卡片圆角 24px | `cornerRadius(24.dp)` | 系统可能叠加自身圆角遮罩 | Android 12+ 由系统统一裁切 widget 圆角，实际观感随设备。**需真机确认** |

**未偏离**：全部色值、字号、间距、圆点大小、条宽比例、信息层级、文案、三态色彩语义（粉=逾期 / 青=未逾期 / 琥珀=仅库存告急）。

---

## 五、构建与验收

### 构建

```bash
flutter pub get
flutter build apk --debug          # 或 flutter run
```

> ⚠️ 本 worktree 的 `android/local.properties` 为空、`flutter` 不在 PATH，
> **本次改动未经过编译验证**，请在有 Flutter SDK 的环境执行首次构建。
> 首次构建会拉取 Compose / Glance 依赖（本机 Gradle 缓存已存在
> `androidx.glance:glance-appwidget:1.2.0` 与 `compose runtime 1.7.8`）。

### 验收清单

- [ ] 主屏深色壁纸上添加中卡 + 小卡，粉/青/琥珀与预览截图同一套
- [ ] 切系统浅色模式，卡片与 HTML 下半截一致（白底暖边、粉按钮）
- [ ] 中卡三行时间右对齐同一竖线；库存文案在药名正下方且字号更小
- [ ] 「近 7 天」是 7 个圆点（完成粉实心 / 未完成暖灰空心），右侧 `5/7`
- [ ] 库存不足那行是**短琥珀条**，未拉满整行
- [ ] 小卡不是空海报：药名贴顶、「已超」紧随、`9` 居中偏上、「小时」跟数字旁、双按钮贴底
- [ ] 「记一次」实心粉；「库存告急」琥珀描边（非系统白边）
- [ ] 点小卡「记一次」→ 写入一条用药记录（`medication_logs` +1、库存扣减），且桌面卡片**立即刷新**
- [ ] 点「库存告急」→ 打开库存仪表板
- [ ] 点整卡 → 回到 App 首页（用药模块）
- [ ] 文案逐字一致：`今日 1/4`、`已超 9 小时`、`库存不足 1 次`、`近 7 天`、`5/7`

### 设计预览

两个 widget 均实现了 `providePreview()`，用 `MedsWidgetDataLoader.preview()`
的定稿假数据渲染，**不读真实存储**，可在 Android Studio 的 Glance Preview
中直接查看深浅两套。

---

## 六、明确未做（遵守范围约束）

- 未改 App 首页 UI、未改任何既有页面
- 未改文案、未新增药物、未新增功能
- 未改 `drug_inventory_list` / `medication_logs` 的读写路径（原生侧**只读**）
- 未重构 `MedicationService`、`NotificationService`、库存页等无关模块
- `MainActivity` 的相册保存逻辑逐字保留

---

## 七、实机验证记录

环境：Pixel 模拟器 `sdk_gphone16k_arm64`（16K page / density 480 / 1280×2856）

### 构建与安装

```
✓ flutter build apk --debug   →  app-debug.apk (91M)
✓ adb install -r              →  Success
✓ 系统识别两个 Provider：MediumMedsWidgetReceiver / SmallMedsWidgetReceiver
```

### 实测发现并修正的问题

| # | 现象 | 根因 | 处置 |
|---|---|---|---|
| 1 | 中卡 4x2 时「近 7 天」底栏被裁 | 4x2 实际渲染高度 ≈203dp，内容需 ≈234dp | 改为 **4x3**（`targetCellHeight=3`、`minHeight=180dp`） |
| 2 | 中卡中间大片空白 | `Column` 用 `fillMaxWidth`（高度 wrap-content），多余空间无处分配 | 改 `fillMaxSize`；每行后加 `Spacer(defaultWeight())` 均分剩余高度，高度不足时自动收缩为 0 |

### 编译期修正（Glance 1.2.0 的真实签名）

| 位置 | 错误 | 正确写法 |
|---|---|---|
| `MedsWidgetTokens.kt` | `ColorProvider(day=, night=)` 无法解析 | 该工厂函数在 **`androidx.glance.color`** 包（顶层函数，与类型 `androidx.glance.unit.ColorProvider` 同名），用 `import ... as colorProviderOf` 区分 |
| `MedsWidgetActions.kt` | `actionParametersOf(key to value)` 类型不匹配 | 入参是 Glance 自己的 `ActionParameters.Pair`（非标准库 Pair）；改用 `mutableActionParametersOf()` + `set(key, value)` |
| `MedsWidgetTokens.kt` | `iconSizeSmall` 未定义 | 补 `MedsDims.iconSizeSmall = 12.dp` |

### 功能验证

- **数据来源**：widget 显示了设备上真实存在的 `drug_inventory_list`（螺内酯 / 戊酸雌二醇 / 黄体酮注射液），证明只读 Flutter SharedPreferences 成功。
- **「记一次」闭环**（logcat 实录，业务逻辑零复制）：
  ```
  🧩 [TP-Widget] action=record_dose drugId=drug-spiro name=螺内酯
  💊 [TP-MedSvc] ===== executeMedicationDose =====
  💊 [TP-MedSvc] 当前库存: 42.0  →  库存更新: 42.0 → 40.0
  💊 [TP-MedSvc] 下次服药时间: 2026-09-19 08:00:00.000
  💊 [TP-MedSvc] 用药日志已持久化 / 通知已重新调度
  ```
- **卡片自动刷新**（打卡后无需手动干预）：

  | | 打卡前 | 打卡后 |
  |---|---|---|
  | header | `今日 3/4` | `今日 4/4` |
  | 螺内酯库存 | `剩 21 次` | `剩 20 次` |
  | 螺内酯时间 | `1天18小时` | `10 小时` |
  | 小卡大字 | `42` | `10` |

### 浅色 / 深色实机对照

| 项 | 浅色 | 深色 |
|---|---|---|
| 卡片底 | `#FFFFFF` | `#211C1A` **暖黑**（非 Material 冷灰） |
| 品牌 / 逾期 | 粉 `#E8899A` | 粉 `#F0A3B0` |
| 未逾期时间 | 青 `#4AB8C8` | 青 `#6BC9D4` |
| 库存告急 | 琥珀 `#D4A017` | 琥珀 `#E0B84A` |
| 结构 / 圆角 / 字号层级 | 完全同源 | 完全同源 |

### 三个动作实测

| 动作 | 结果 |
|---|---|
| 小卡「记一次」 | ✓ 调 `executeMedicationDose`：扣库存 + 写日志 + 重排通知 + 卡片自动刷新 |
| 小卡「库存告急」 | ✓ `Navigator.push(InventoryDashboardScreen)`；logcat `action=stock_alert drugId=drug-spiro` |
| 点击整卡 | 未单独点击（与上者同走 `open_meds` 路径，置 `widgetTabRequest=0` 切首页） |

### 尚未验证

- 浅色下**未完成圆点**的可见度：`#EDE8E4` 描边在白卡上对比度天然极低（HTML 同样如此），实机接近不可见 —— 属设计取值，未擅自加深

### 构建环境注意事项（与代码无关，但会阻断构建）

本机 `~/.gradle/init.d/mirrors.gradle` 会把 google / mavenCentral 全部改写成 aliyun；
而 `~/.gradle/gradle.properties` 里的 `127.0.0.1:7890` 代理**当时不可用**，导致每次依赖下载
`Remote host terminated the handshake`。绕过方式（不改全局配置）：

```bash
export GRADLE_OPTS="-Dhttp.nonProxyHosts=* -Dhttps.nonProxyHosts=*"
```

彻底解决：启动 Clash，或注释掉 `~/.gradle/gradle.properties` 中那 4 行代理配置
（实测直连 aliyun 0.068s、google 1.86s，无需代理）。
