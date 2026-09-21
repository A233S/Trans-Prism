# 桌面用药小组件实装说明（Android / Glance）

> 目标：把定稿的 Trans Prism 用药小组件从 HTML 预览实装进 App。
> 视觉唯一真相：`outputs/widget_preview.html` + 预览截图。
> **未改动**：业务逻辑、文案、App 首页、既有存储结构。

> **v2（2026-09-19）**：真机反馈驱动的一轮改造 —— 主题绑定 App 偏好、3×4 解决
> 「记一次不知道记谁」、2×2 改环形、修 5 项 UI 债、「我的」加 pin 入口。
> 完整变更见文末 **「八、v2 变更」**；下面一~七节是 v1 的原始记录，其中
> 「取色按系统深浅色解析」「小卡放大数字 + 双按钮」等描述**已被 v2 取代**。

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

---

## 八、v2 变更（2026-09-19）

真机现状（浅色 3×4 + 2×2，壁纸深色）暴露的问题与本轮改造一一对应。

### 8.1 主题：跟 App 内的深浅色，不跟壁纸、不跟系统

| 项 | v1 | v2 |
|---|---|---|
| 取色机制 | `androidx.glance.color.ColorProvider(day, night)` —— 按**系统 uiMode** 解析 | 组合期解析出 `MedsWidgetColors`，用 `FixedColorProvider` 注入（见下方链路） |
| 偏好来源 | 无 | `FlutterSharedPreferences` → `flutter.theme_mode`（`light`/`dark`/`system`），与「我的 → 主题模式」同一个 key |
| 变更联动 | 无 | `ThemeService.setThemeMode()` → `MedsWidgetService.refresh()` → `MedsWidgetUpdater.requestRefresh()` |
| 「跟随系统」 | 实际是「永远跟随系统」 | 只有偏好为 `system` 时才落回系统 uiMode |

**取色链路（改这块前必读）**：

```
provideGlance(context)                       ← suspend，能读 SharedPreferences
  └─ MedsWidgetThemePrefs.colorsFor(context) ← light / dark / system 在这里判定
       └─ MedsWidgetThemeProvider(colors) { … }   ← 注入 CompositionLocal
            └─ MedsTokens.card / .title / …       ← @Composable getter，取当前那一套
                 └─ FixedColorProvider(Color)     ← Glance 认识，不会被丢
```

> ⚠️ **绝对不要试图用「自定义 `ColorProvider` 实现」来绑主题。**
> `androidx.glance.unit.ColorProvider` 虽然是接口，但 Glance 1.2.0 的
> `RemoteViewsTranslator` **不是按接口多态取色**，而是 `when` 穷举它自己认识的
> 三种实现（`FixedColorProvider` / `DayNightColorProvider` / `ResourceColorProvider`），
> 其余全部命中 `else` 分支并**静默丢弃**：
>
> ```
> W GlanceAppWidget: Unexpected background color modifier: <你的实现>
> W GlanceAppWidget: Unexpected text color: <你的实现>
> ```
>
> 后果：卡片背景变**透明**、文字回退系统默认色、进度条丢色 —— 而组件**不会崩**，
> 所以极难从「页面长得不对」反推到这里。这是本项目实际踩过的坑
> （真机 logcat 实录，见 §9.2）。

`MedsWidgetThemePrefs` **只读** Flutter 的 SP 文件，不写、不新增存储。

> 为什么不用 `GlanceTheme`：Glance 的 `ColorProviders` 是 28 槽 Material 色板抽象类，
> 而 TP 的品牌色是语义 token（粉=逾期 / 青=未服 / 琥珀=缺货），压进去会丢语义。
>
> 为什么不「包一层改过 `Configuration` 的 Context 再交给 `DayNightColorProvider`」：
> 那样只有**我们主动触发**的刷新会按 App 偏好渲染，而系统触发的刷新
> （`updatePeriodMillis` / 开机广播）仍按**系统**深浅色 —— 同一个小部件会随触发方变色。

### 8.2 3×4：解决「记一次不知道记谁」

| # | 要求 | 实现 |
|---|---|---|
| 1 | 明确「下一剂」 | 排序 = 已超最久 → 待服剩余最短（既有排序），**第 0 行**即下一剂；该行加 **3dp 粉/青竖条 + 同色系浅底（圆角 10dp）** |
| 2 | 右上按钮带药名 | 「记 螺内酯」（`记 {下一剂药名}`），不再光秃秃「记一次」 |
| 3 | 每行整行可点 | 行级 `clickable` → `record_dose` + 该行 `drugId`；右上按钮 = 快捷记「下一剂」，**与高亮行同一条药、同一个 action 构造函数**（`recordDoseAction()`），不存在两套逻辑 |
| 4 | 打卡后刷新 | Dart 侧 `executeMedicationDose()` 完成后回调 `refreshWidgets` → 今日 n/4、该行时间、近 7 天点一起更新 |

每行**不**再加第二个大按钮（3×4 高度不够）。

新增展示字段：`MedsWidgetItem.drugId` / `isNext`；`MedsWidgetData.nextDrugName`。

**对齐细节**：未高亮的行也套同样的 `rowPaddingH/rowPaddingV` 并留出 3dp 透明占位，
只有背景色不同 —— 三行的图标 / 药名 / 时间仍在同一竖线。

### 8.3 2×2：改环形（下一剂专用）

```
针 螺内酯                    库存不足     ← 仅 critical 时的琥珀小字
           ╭─────╮
           │  9  │                        ← 环心：剩余 / 已超 主数字
           │ 小时 │
           ╰─────╯
             待服                          ← 环下小标签
     [     记 螺内酯     ]                 ← 单按钮，满宽
```

- 只展示「下一剂」那一条，与 3×4 高亮行**同一条**（同一个 `computed.firstOrNull()`）。
- **待服 → 环和数字用青；已超 → 用粉**，标签写「已超」。
- 「库存告急」不做第二按钮；仅 critical 时药名旁加一行琥珀小字「库存不足」。
- **点环或点按钮都是记这一剂**（环所在的整块 Column 可点）。

#### 环进度怎么算（唯一口径，已写进 `MedsRingRenderer` 注释）

**选「距下次剂量的时间进度」**，不是今日完成度：

```
progress = 1 − 距下次剂量剩余分钟 / 该药给药间隔分钟
```

- 刚打完卡 → 剩余 ≈ 整个间隔 → `progress ≈ 0`（环空）
- 时间流逝 → 环逐渐填满；已超 → `progress = 1.0`（整圈，粉）
- 间隔取值：离散时刻模式（`dailyReminderTimes` 非空）取 `24h / 时刻数`；
  否则取 `intervalValue` 折算小时；都拿不到时兜底 24h（`intervalMinutesOf()`）

#### 环怎么画（Glance 能力边界）

Glance 1.2.0 **没有 Canvas / DrawScope**；自带的
`androidx.glance.appwidget.CircularProgressIndicator` 只有 `(modifier, color)`
两个参数 —— 它是**不定进度**的转圈 loader，**不能**当环形进度条用。

因此用 `android.graphics.Canvas` 把环**预渲染成方形位图**，经
`ImageProvider(bitmap)`（`androidx.glance.ImageKt.ImageProvider(Bitmap)` 已确认存在）
交给 `Image(..., contentScale = ContentScale.Fit)` 摆放：

- 位图边长 = `min(组件宽, 组件高) × 密度`，clamp 到 `64..384 px`；
- 进度按 **1% 分桶**后进 `LruCache`（8 条），避免每帧生成新位图；
- 无动画。

### 8.4 「我的」→ 添加到主屏幕

- 位置：**外观与显示**分组，`_showAddToHomeSheet()`（`lib/main.dart`）。
- 主路径：`AppWidgetManager.requestPinAppWidget`（Android 8+ / API 26），
  系统直接弹「添加到主屏幕」确认框 —— **不跳系统设置迷宫页**。
- 两个尺寸入口：**3×4 一览**（`今日用药`）/ **2×2 下一剂**（`待服用`）。
- 降级：`isRequestPinAppWidgetSupported == false`（低版本或 Launcher 未实现）时，
  弹层改为文字说明「长按桌面空白处 → 小组件 → Trans Prism」。

新增桥接方法（`MainActivity.kt` 的 `CHANNEL_WIDGET`）：
`canPinMedsWidget` / `pinMedsWidget(size)`；Dart 侧封装在
`lib/services/meds_widget_service.dart`。

### 8.5 顺手修掉的 UI 债

| # | 现象 | 处置 |
|---|---|---|
| 1 | 2×2「待服」的大数字是**粉色**（错） | 环与数字统一走 `MedsTokens.ringAccent(overdue)` —— 待服青 / 已超粉 |
| 2 | 库存充足的药也出现「库存告急」按钮 | 第二按钮**整条删除**；告急改为 `CriticalNote()` 琥珀小字，且只在 `isCritical` 时渲染 |
| 3 | icon 像回形针 | `ic_syringe.xml` **重绘**为横向针筒（针头 + 带刻度筒身 + 推杆横档）；旧版 Lucide 斜向路径在 13~15dp 下筒身被压成一圈细环 |
| 4 | 「近 7 天」只画出 5 个点，与 `5/7` 对不上 | 数据侧本就恒 7 个点（`(6 downTo 0)`）；真因是**圆点 Row 给了 `defaultWeight()`** 被压缩裁点 —— 去掉权重，改用后置 `Spacer(defaultWeight())` 顶开计数。**修完又踩到 `Row` 最多 10 个子元素**（见 §9.2 问题 2），最终把间隔做进每个点自带的 `padding(end)` |
| 5 | 黄体酮「库存不足 0 次」琥珀条 | 保持 `BAR_CRITICAL = 0.22` **短条**，不拉满 |
| 6 | 3×4 时间未等宽右对齐 | 时间列**固定宽 74dp + `TextAlign.End`**；Glance 的 `TextStyle` 无 `fontFeatureSettings`（无法真开 `tabular-nums`），固定宽右对齐是等效观感 |

### 8.6 Preview 矩阵

**设计对照稿**：v2 见 [`docs/widget_preview_v2.html`](widget_preview_v2.html:1)（**历史稿**，页内已标注差异）；当前实现见 v3 稿 —— 浏览器直接打开，
右上角切换浅色 / 深色 token，一屏看全 3×4 与 2×2 的
**浅/深 × 待服/已超 × 缺货/库存足**。色值 / 尺寸 / 字号与 `MedsWidgetTokens.kt` 逐项同源。

**代码侧**（Android Studio 的 Glance Preview）：

| 组件 | `providePreview` 渲染 |
|---|---|
| 中卡 | `MedsWidgetDataLoader.previewMedium()` —— **一张卡覆盖三态**：已超+缺货（高亮行）/ 已超+库存足 / 待服+库存足 |
| 小卡 | `MedsWidgetDataLoader.previewSmall(PREVIEW_SMALL_STATE)` —— 四态枚举 `WAITING_IN_STOCK` / `WAITING_CRITICAL` / `OVERDUE_IN_STOCK` / `OVERDUE_CRITICAL` |

**浅色 / 深色不出变体**：它由 App 主题偏好决定（跟 App、不跟系统），
在「我的 → 主题模式」切换后重开预览即可看到另一套 —— 这本身就是验收点。

想逐个看小卡四态：改 `SmallMedsWidget.kt` 的 `PREVIEW_SMALL_STATE` 即可。

### 8.7 未做 / 边界

- 未改打卡 use case（`MedicationService.executeMedicationDose` 一字未动）；
- 未改药名文案、未改 token 色值（粉青琥珀暖白暖黑全部原值）；
- 未改非小组件页面 —— 除「我的」新增的「添加到主屏幕」入口外；
- `MedsWidgetData.kt` 只**扩展**展示模型与只读解析，未新增任何写入路径；
- Glance 的 `Text` 无 `ellipsize` 参数，药名超出时是**硬截断**（无省略号）。

### 8.8 验收清单（v2 增量）

- [ ] App 主题设为**深色**、系统为浅色 → 桌面卡片是暖黑；反过来 App 设浅色、系统深色 → 卡片是暖白
- [ ] App 主题设「跟随系统」→ 切系统深浅色后回到 App（触发刷新）→ 卡片跟着变
- [ ] 3×4 第 1 行有粉/青竖条 + 浅底；右上按钮文案是「记 {该行药名}」
- [ ] 点 3×4 第 2 行 → logcat `action=record_dose drugId=<第2行的药>`（不是第 1 行）
- [ ] 点右上按钮 → 记的是高亮行那条药
- [ ] 2×2「待服」时环与数字是**青**色；「已超」时是**粉**色
- [ ] 2×2 库存充足时**没有**「库存不足」小字
- [ ] 点 2×2 的环 → 同样记这一剂
- [ ] 3×4「近 7 天」恒 7 个点，与右侧 `n/7` 对得上
- [ ] 「我的 → 外观与显示 → 添加到主屏幕」→ 选尺寸 → 系统弹 pin 确认框
- [ ] 库存不足那行仍是**短**琥珀条，不拉满

---

## 九、真机验证记录（v2.1，2026-09-19）

环境：Pixel 模拟器 `emulator-5554`（sdk_gphone16k_arm64 / Android 17 / API 37 / density 480 / 1280×2856）。
**系统深浅色 = 浅色，App `theme_mode` = dark** —— 这组错位条件正好用来验证「跟 App 不跟系统」。

真机截图：[`widget_v2_real_dark.png`](widget_v2_real_dark.png)（App 深色 / 系统浅色）·
[`widget_v2_real_light.png`](widget_v2_real_light.png)（App 浅色）。

### 9.1 逐项验收结果

| # | 验收项 | 结果 | 证据 |
|---|---|---|---|
| 1 | 主题跟 App 不跟系统 | ✅ | 系统浅色 + App 深色 → 卡片**暖黑** `#211C1A`；改 App 为浅色 → 卡片**纯白** |
| 2 | 3×4「下一剂」高亮 | ✅ | 第 1 行左侧 3dp 青色竖条 + 同色系浅底 |
| 3 | 右上按钮带药名 | ✅ | 文案「记 螺内酯」= 高亮行那条药 |
| 4 | 点哪行记哪行 | ✅ | 点第 2 行 → `action=record_dose drugId=drug-es name=戊酸雌二醇`；点第 3 行 → `drugId=drug-prog`；点第 1 行 → `drugId=drug-spiro` |
| 5 | 右上按钮 = 记「下一剂」 | ✅ | `drugId=drug-spiro`，与高亮行一致 |
| 6 | 打卡后自动刷新 | ✅ | 螺内酯 `剩 15 次` → 点行后约 3s 变 `剩 14 次`；`今日 n/4`、该行时间、7 天点同步更新 |
| 7 | 近 7 天恒 7 个点 | ✅ | 7 个点 + 右侧 `6/7` 一致 |
| 8 | 2×2 环形（待服青 / 已超粉） | ✅ | 待服 → 青环 + 青色 `1`；环按时间进度填充（1−96/720 ≈ 87%） |
| 9 | 2×2 单按钮满宽 + 带药名 | ✅ | 「记 螺内酯」 |
| 10 | 点环也记这一剂 | ✅ | 点环心 → `drugId=drug-spiro`，库存 28→26 |
| 11 | 库存充足不出「库存不足」 | ✅ | 螺内酯 剩 14 次时无该小字；戊酸雌二醇 剩 2 次时出现琥珀小字 |
| 12 | 库存不足仍是**短**琥珀条 | ✅ | 宽度固定 0.22，不拉满 |
| 13 | 时间右对齐等宽 | ✅ | 三行时间右边缘同一竖线 |
| 14 | 「我的 → 添加到主屏幕」pin | ✅ | 弹层 → 选「3×4 一览」→ 系统 `CONFIRM_PIN_APPWIDGET`（`QuickstepAddItemActivity`）→「Add to home screen」成功 |
| 15 | 针筒图标 | ✅ | 横向针筒，13~15dp 下可辨 |

### 9.2 真机暴露并修掉的两个问题（**改小组件必读**）

#### 问题 1：自定义 `ColorProvider` 被 Glance 静默丢弃

- **现象**：卡片背景**透明**（壁纸直接透出来）、文字颜色错乱、进度条无色。组件不崩。
- **根因**：见 §8.1 的警告框 —— `RemoteViewsTranslator` 只认 Glance 自己的三种实现。
- **修复**：改为「组合期解析 + `FixedColorProvider` + CompositionLocal」链路。
- **教训**：**看到「布局对但颜色不对/背景没了」，先 grep logcat 的
  `Unexpected (text|background) color`。**

#### 问题 2：`Row` 最多 10 个子元素

- **现象**：`E GlanceAppWidget: java.lang.IllegalArgumentException: Row container cannot have more than 10 elements`
  —— 整张卡渲染失败（旧 RemoteViews 留在桌面上，看起来像「没刷新」）。
- **根因**：「近 7 天」的 7 个点 + 6 个间隔如果**摊平**进外层 Row，会到 13 个子元素。
- **修复**：① 点包进**内层 Row**（7 个），间隔做成每个点自带的 `padding(end)`；
  ② 中卡三行药也单独包一层 Column，避免「行 + Spacer」摊平后逼近上限。
- **教训**：`Row`/`Column` 都要数子元素个数，别靠 `forEach` 摊平。

#### 问题 3：刷新撞车导致渲染旧数据

- **现象**：点小组件打卡后，卡片停在**打卡前**的数据（`剩 16 次 / 今日 2/4`），
  而库里已是 `剩 15 次 / 今日 4/4`，要等下一次刷新才追上。
- **根因**：刷新有**两个**触发源且几乎同时到达 ——
  ① 点小组件 → `MainActivity` 起来 → `onResume` 的「回前台刷新」；
  ② Dart 侧 `executeMedicationDose()` 完成后的「打卡后刷新」。
  两次相隔约 100ms，**Glance 把它们合并成一次会话**，而会话在**启动时**就读
  `SharedPreferences` —— 读到的还是打卡前的值。
- **修复**：`MedsWidgetUpdater.requestRefresh()` 加 **700ms 尾沿去抖**
  （`pending?.cancel()` + `delay` + `refreshAll`），无论几个触发源最终只渲染一次，
  且渲染的一定是最后那次的库状态。另在 `_initWidgetActions()` 里补一次启动刷新，
  兜住「`resumed` 事件早于观察者注册」的冷启动路径。

#### 问题 4：`fillMaxSize()` 把同 Column 的兄弟节点挤成 0 高

- **现象**：2×2 的「待服 / 已超」标签**完全不渲染**（环和按钮都在，中间是空的）。
- **根因**：环容器 `NextDoseRing` 的根 `Box` 用了 `GlanceModifier.fillMaxSize()`，
  而它是「带 `defaultWeight()` 的 Column」的第一个子节点 ——
  `fillMaxSize` 把该 Column 的高度**全吃光**，后面的 `Spacer` + 标签拿到 0 高度。
- **修复**：环容器改为 `fillMaxWidth().defaultWeight()`（`defaultWeight()` 是
  `ColumnScope` 成员，所以由**调用点**作为参数传进去，见 `SmallMedsWidget.kt`）。
- **教训**：在带权重的容器里，子节点要 `defaultWeight()` 去**分**剩余空间，
  而不是 `fillMaxSize()` 去**占**全部空间。

### 9.3 已知限制 / 后续可选优化

- **`updatePeriodMillis` = 30 分钟**：`system` 模式下属系统深浅色被切换时，
  卡片最迟 30 分钟内自愈；用户打开 App 会立即刷新。
- **pin 弹层里的预览图**仍是 App 图标（`android:previewImage="@mipmap/ic_launcher"`）。
  若要显示真实小组件外观，可改用 `GlanceAppWidgetManager.setWidgetPreview(...)`（API 31+）
  或在 `res/xml/*_info.xml` 里配 `previewLayout`。
- Glance 的 `Text` 无 `ellipsize`，药名超长是**硬截断**（无省略号）。
- `MedsWidgetDataLoader.load()` / `MedsWidgetUpdater.refreshAll()` 保留了
  `Log.d("TP-Widget", …)` 一行摘要 —— 排查「卡片没跟上数据」时先看它：
  能直接区分「读到旧快照」与「数据是新的但没推给 Launcher」。

---

## 十、v3 变更（2026-09-19）—— 小组件不再打卡

真机截图：[`widget_v3_real_dark.png`](widget_v3_real_dark.png) · [`widget_v3_real_light.png`](widget_v3_real_light.png)

**设计对照稿**：[`docs/widget_preview_v3.html`](widget_preview_v3.html:1) —— 浏览器直接打开，
可切换浅色 / 深色 token，一屏看全 3×4 与 2×2 的
**浅/深 × 待服/已超 × 缺货/库存足**。色值 / 尺寸 / 字号与 `MedsWidgetTokens.kt` 逐项同源。

### 10.1 核心交互：从「直接记一笔」改成「打开确认 Sheet」

**问题**：v2 点行 / 点「记 xx」**直接打卡扣库存**，没有确认。口袋误触、滑动误触都会真的记一笔药。

**v3 规则**：

| 入口 | 行为 |
|---|---|
| 3×4 点任意一行 | 带该行 `drugId` 唤起 App → 拉起该药的「记录用药」Sheet。**不写任何数据。** |
| 2×2 点环 | 同上 |
| 2×2 点「记 螺内酯」 | 同上 |
| Sheet 点「确认服药」 | **只有这里**才走 `executeMedicationDose()` → 写日志 + 扣库存 + 重排通知 + 刷新小组件 |
| Sheet 点「取消」/ 系统返回 | 什么都不发生（日志：`记录用药 Sheet 已取消，未写入任何数据`） |

**动作契约**：新增 `ACTION_OPEN_RECORD_SHEET = "open_record_sheet"`，必须带 `EXTRA_DRUG_ID`。
Dart 侧 `_openRecordSheetFromWidget()` 加载该药后复用既有
`RecordDoseDialog.show(context, drug: drug)` —— **没有另做一套小组件专用打卡**。

> 旧版残留在桌面上的 PendingIntent 仍会发 `record_dose`；
> Dart 侧把它与 `open_record_sheet` **合并处理**（同样只开 Sheet），
> 保证**不存在任何「无确认就记一笔」的路径**。

**冷启动时序**：`getLaunchAction` 可能早于首帧返回，故 `_awaitNavigatorReady()`
先等根 Navigator 就绪再 `showModalBottomSheet`。

### 10.2 3×4 右上角

删掉「记 螺内酯」粉胶囊（与「点行打开」重复，且看着就像会直接记），
改为一句 **muted 小字说明「点对应药物服药」**：无粉底、无描边、无点击。
「今日 4/4」仍在左上。

### 10.3 视觉收敛

| 项 | v2 | v3 |
|---|---|---|
| 高亮行底色 | 品牌色 8%~14% 浅底（整块，像被选中的列表 item） | **中性极轻提亮**（浅色 4% 黑 / 深色 8% 白）+ 左侧 3.5dp 状态色竖条 |
| 三行间距 | 每行后 `defaultWeight()` 均分富余 → 实测 ~22dp/行，太散 | **固定 5dp**，行块整体在剩余空间里垂直居中 |
| 进度条 | 2px | 2px（不变） |
| 近 7 天 | 7 点 + `n/7` | 不变（已对齐） |
| 2×2 环线宽 | 8.5% | **6.2%** + 环与边缘留白 → 中心「1 / 小时」有呼吸感 |
| 2×2 按钮 | 底边 10dp | 底边 **13dp**，不顶死底边；左右仍是 12dp |

深浅色继续跟 App 内主题偏好，不跟壁纸。

### 10.4 真机验证（Pixel 模拟器 / Android 17 / API 37）

| # | 验收项 | 结果 | 证据 |
|---|---|---|---|
| 1 | 3×4 点行 → 打开对应药 Sheet，库存不变 | ✅ | 点第 2 行 → `open_record_sheet drugId=drug-es`；SP 前后一致（65.0 / 今日 11 条） |
| 2 | 2×2 点环 / 点按钮 → 同一张 Sheet | ✅ | `drugId=drug-spiro` |
| 3 | Sheet 确认后才写入 | ✅ | 库存 60.0→55.0、今日 12→13、`TP-RDD 用药记录成功`，随后 `refreshAll` |
| 4 | 确认后小组件更新 | ✅ | 卡片 `剩 13 次` → `剩 12 次` → 再确认 → `剩 11 次` |
| 5 | 取消 / 系统返回不记一笔 | ✅ | 日志 `Sheet 已取消，未写入任何数据`；SP 前后一致 |
| 6 | 右上角是说明文字不是按钮 | ✅ | 截图：muted 小字「点对应药物服药」，无粉底 |
| 7 | 假按桌面空白处不记一笔 | ✅ | 整卡点击只走 `open_meds`（切首页），不写数据 |

### 10.5 真机暴露的第 5 个坑（**最隐蔽的一个，必读**）

#### `provideGlance` 里读到的数据会被闭包捕获，重组时不会刷新

- **现象**：打卡后 `refreshAll: medium=1 small=1` 有日志、系统也收到了
  `notify widget update`，但卡片**停在打卡前的值**；`provideGlance` 之后再没进入过，
  `load:` 也没有。而**重装 APK（进程重启 → 新会话）后立刻显示正确**。
- **根因**：Glance 的会话是**长驻**的 —— `provideGlance` 只在会话创建时执行一次，
  之后每次 `update()` 只是**重组同一棵组合树**（不会再次进入 `provideGlance`）。
  所以这样写是错的：

  ```kotlin
  // ❌ 错：data 在会话创建时读一次，之后被闭包捕获，重组时永远不变
  override suspend fun provideGlance(context: Context, id: GlanceId) {
      val data = MedsWidgetDataLoader.load(context)
      provideContent { MediumMedsContent(data) }
  }
  ```

  正确写法是**把读取放进组合 lambda 里**：

  ```kotlin
  // ✅ 对：每次重组都会重新读，永远是最新值
  override suspend fun provideGlance(context: Context, id: GlanceId) {
      provideContent {
          val colors = MedsWidgetThemePrefs.colorsFor(context)
          val data = MedsWidgetDataLoader.load(context)
          MedsWidgetThemeProvider(colors) { MediumMedsContent(data) }
      }
  }
  ```

  `load()` / `colorsFor()` 都是**同步**函数（读内存里的 SharedPreferences），
  放进组合里没有 suspend 问题。

- **教训**：**凡是要跟着数据变化的东西，一律写在 `provideContent { }` 里。**
  提到 `provideGlance` 顶部的任何 `val` 都会变成「只在会话创建时算一次」。

#### 附带发现：前台发出的刷新不会立即重组

即使修好了上面这条，实测「App 停在前台时发出的刷新请求」仍不会马上重组卡片
（`refreshAll` 有日志、`load:` 没有）；App 在后台 / 刚启动时发出的请求都正常。

因此 `didChangeAppLifecycleState` 里**除了 `resumed` 也处理 `paused`**：
用户从桌面点小组件 → Sheet 确认 → 按 home 回桌面，走的正是 `paused` 这条路径，
补一次刷新即可**保证用户看到卡片时它已经是最新的**。
原生侧有 700ms 尾沿去抖，两次请求会合并成一次。

---

## 十一、国产 ROM 排障：点小组件不弹应用（2026-09-19 追查）

**反馈**：小米澎湃 OS 4 用户报告「点小组件后不弹应用」。

### 11.1 第一步：先分诊，别猜

新增了一条**原生侧**日志（`MainActivity.onCreate` / `onNewIntent`），
它比 Dart 侧日志更早，**Flutter 引擎起不来也能留下痕迹**：

```
D TP-Widget: MainActivity.onCreate ← action=open_meds drugId=- cmp=.../.MainActivity flags=0x10400000
D TP-Widget: MainActivity.onNewIntent ← action=open_meds drugId=- ...
```

| 现象 | 结论 |
|---|---|
| 有 `MainActivity.* ← action=...` | 点击**已送达 App**，问题在 App 内部（继续看 Dart 侧 `🧩 [TP-Widget]`） |
| 完全没有这条日志 | 系统/桌面**根本没把这次启动交给我们** → 走 §11.2 的 ROM 侧原因 |
| `action=(非小组件启动)` | 是桌面图标/最近任务启动的，不是小组件点击 |

### 11.2 已确认的两条 ROM 侧机制

#### A. App 被**强行停止**后，小组件变成不可点的占位图

`am force-stop`（等价于用户「强行停止」、或 ROM 省电策略清理）后，
桌面会清掉该 App 的 RemoteViews，显示**灰色占位图（App 图标居中）**。
占位图**没有点击处理器**，所以点击毫无反应；要等 App 重新运行、小组件重新渲染后才恢复。

- **本地实测（Pixel 模拟器 / Android 17）**：可复现，但**时好时坏** ——
  取决于点的那一刻小组件是否已经重新渲染出内容。
  同一个 `am force-stop` 后，我观察到过「点了没反应」和「正常拉起」两种结果。
- 对照实验：`am kill`（普通内存回收，不置 stopped 标志）后点击**始终正常**
  （`BAL_ALLOW_VISIBLE_WINDOW [realCaller]` → `Displayed MainActivity`）。
- 所以关键变量是 **stopped 状态 / RemoteViews 是否还在**，而不是进程死没死。

> 澎湃 OS 官方 FAQ 提到「宿主（桌面/负一屏）会**缓存 RemoteViews**」，
> 因此真实设备上更可能表现为「卡片看着是好的（其实是缓存），但点了没反应」。

#### B. 「后台弹出界面」权限在澎湃 OS 上**默认拒绝**

小米官方《后台弹出页面权限管理说明》原文：

> 该权限默认为拒绝的，即为应用默认不允许在后台弹出页面，针对特殊应用会提供白名单。

这是「点小组件不弹应用」在小米系上最可能的**直接**原因：
小组件点击本质是 `PendingIntent` 拉起 Activity，若被判定为「后台弹出」就会被拦掉。

### 11.3 已做的处理

#### ① 原生侧分诊日志（见 §11.1）

把「点击没送达」和「送达了但没起来」彻底分开。这是排查的第一步，也是唯一能
在**不做任何猜测**的前提下缩小范围的手段。

#### ② 「后台弹出界面」：可检测 + 一键跳转（不再只是文字提示）

小米把该权限做成了 **AppOps `op 10021`**（`OP_BACKGROUND_START_ACTIVITY`），
没有公开 API，但**可以反射 `checkOpNoThrow` 查到状态**：

```kotlin
val ops = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
val m = ops.javaClass.getMethod("checkOpNoThrow", Int::class.javaPrimitiveType,
                                Int::class.javaPrimitiveType, String::class.java)
val mode = m.invoke(ops, 10021, Process.myUid(), packageName) as Int
mode == AppOpsManager.MODE_ALLOWED
```

于是新增了一条完整的「检测 → 提示 → 跳转」链路：

| 层 | 文件 | 内容 |
|---|---|---|
| 原生 | [`MainActivity.kt`](../android/app/src/main/kotlin/com/daanser/transprism/MainActivity.kt:1) | 新通道 `com.daanser.transprism/oem_permissions`：`isMiuiFamily` / `isBackgroundPopupAllowed` / `openBackgroundPopupSettings` |
| Dart | [`oem_permission_service.dart`](../lib/services/oem_permission_service.dart:1) | 对应三个静态方法，含非 Android 平台短路与异常兜底 |
| UI | [`battery_optimization_guide_card.dart`](../lib/widgets/battery_optimization_guide_card.dart:1) | **仅小米系**显示「后台弹出界面」状态项（实时反映 op 状态），点击弹说明 → 跳小米安全中心权限页 |

跳转按 MIUI 版本依次尝试
`PermissionsEditorActivity` → `AppPermissionsEditorActivity` → 系统「应用详情」页兜底。

**检测不到（op 号在个别版本可能变动）时一律按「未允许」处理** ——
宁可多提示一次，也不要让用户卡在「点了没反应且毫无解释」的状态。

> ⚠️ 非小米机型上这一行**不显示**（`isMiuiFamily() == false`），
> 避免给不需要的人添噪音。已在 Pixel 模拟器上验证该行正确隐藏。

#### ③ 保活引导补两条小米专属步骤

「厂商后台自启动」的说明弹窗里追加：
- 省电策略改为「无限制」（避免被强行停止 → 小组件变占位图）
- 开启「后台弹出界面」（澎湃 OS 默认关闭）

### 11.5 修复：把点击 Intent 改成与桌面图标启动**同形**（2026-09-19 深夜）

#### 先做了完整静态审计（结论：链路本身是标准的）

反编译 `glance-appwidget:1.2.0` 逐条确认了点击路径的真实构造：

```kotlin
// ApplyActionKt.getPendingIntentForAction → StartActivityAction 分支
val intent = getStartActivityIntent(action, ctx, params)   // Intent(context, MainActivity::class.java)
if (intent.data == null) intent.data = createUniqueUri(...)  // glance-action://… 仅用于区分 PendingIntent
PendingIntent.getActivity(ctx, requestCode, intent, flags or 0x08000000 /* FLAG_IMMUTABLE */, null)
```

> 更正一个此前的误判：**activity 分支并不经过 `ActionTrampolineActivity`**
> （trampoline 只用于 CALLBACK / Service / Broadcast 分支）。
> 模拟器 logcat 里 `cmp=.../.MainActivity` + `realCallingUid=10197`（桌面）也印证了这点。

审计结论 —— 以下**全部没有问题**：

| 检查项 | 结果 |
|---|---|
| Intent 是否显式 | ✅ `Intent(context, MainActivity::class.java)`，非隐式 |
| `android:exported` | ✅ `true` |
| `launchMode` | ✅ `singleTop`（配合 `LAUNCH_SINGLE_TOP` 走 `onNewIntent`） |
| PendingIntent flag | ✅ 由 Glance 统一 `or FLAG_IMMUTABLE`（Android 12+ 必需） |
| requestCode / Intent 复用 | ✅ Glance 用 `createUniqueUri` 保证每个 action 的 PendingIntent 互不相等 |
| 隐式 Intent / 动态 BroadcastReceiver | ✅ 都没有 |
| 自定义 Application | ✅ 无（用 Flutter 默认 `${applicationName}`） |
| 多 Activity | ✅ 只有 `MainActivity` 一个 |
| ProGuard / R8 裁掉组件 | ✅ 未开启 minify（无自定义规则文件） |
| package / namespace / applicationId | ✅ 三处一致 `com.daanser.transprism` |
| Flutter embedding | ✅ v2（`flutterEmbedding=2`） |

#### 根因

**链路没有错，差的是 Intent 的「形态」。**

Glance 产出的是 `Intent(context, MainActivity::class.java) + FLAG_ACTIVITY_NEW_TASK` ——
这在原生 Android（Pixel / Android 16 实测）完全正常，但小米澎湃 OS 上**点击毫无反应**；
而**同一台机器点桌面图标能正常打开 App**。

两者唯一的差别就是 Intent 形态：桌面图标走的是 launcher 形态
（`ACTION_MAIN` + `CATEGORY_LAUNCHER` + 显式 component +
`FLAG_ACTIVITY_NEW_TASK | FLAG_ACTIVITY_RESET_TASK_IF_NEEDED`）。
澎湃 OS 对「来自小组件的裸显式 Intent」与「launcher 形态 Intent」的放行策略不同，
前者被拦、后者放行 —— 这解释了「卡片能显示（RemoteViews 正常）但点击不打开 App」。

#### 最小修复

[`MedsWidgetActions.kt`](../android/app/src/main/kotlin/com/daanser/transprism/widget/MedsWidgetActions.kt:1)
新增 `openAppAction()`，改用 [`Intent.makeMainActivity`]：

```kotlin
@Composable
fun openAppAction(parameters: ActionParameters): Action {
    val context = LocalContext.current
    val intent = Intent.makeMainActivity(
        ComponentName(context, MainActivity::class.java),
    ).apply { addFlags(Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED) }
    return StartActivityIntentAction(intent, parameters, null)
}
```

`Intent.makeMainActivity` 自带 `ACTION_MAIN` / `CATEGORY_LAUNCHER` / 显式 component /
`FLAG_ACTIVITY_NEW_TASK`，这里只补 launcher 也会加的 `RESET_TASK_IF_NEEDED`。
**刻意不加 `FLAG_ACTIVITY_CLEAR_TOP`** —— launcher 不这么做，加了会清掉用户压在栈上的页面。

`StartActivityIntentAction` 是 Glance 的公开类，`getStartActivityIntent` 对它直接
`return action.intent`，因此可以安全地传入自定义 Intent（这是 Glance 唯一支持的
「自带 Intent」入口；`when` 的 `else` 分支会抛异常，不能自己实现 `StartActivityAction`）。

改动范围：**只改了两个调用点**（中卡整卡背景 + `openRecordSheetAction`），
Dart 层、Flutter 启动逻辑、图标启动路径**均未改动**。

#### 真机验证（Pixel 模拟器 / Android 16 / API 36）

修复后点击的系统记录：

```
START u0 {act=android.intent.action.MAIN cat=[android.intent.category.LAUNCHER]
          dat=glance-action:/... flg=0x10200000 cmp=com.daanser.transprism/.MainActivity}
with LAUNCH_SINGLE_TOP ... (BAL_ALLOW_VISIBLE_WINDOW [realCaller]) result code=0
D TP-Widget: MainActivity.onCreate ← action=open_meds flags=0x10200000
```

`flg=0x10200000` = `FLAG_ACTIVITY_NEW_TASK(0x10000000) | FLAG_ACTIVITY_RESET_TASK_IF_NEEDED(0x00200000)`
—— 与 launcher 图标点击**逐项一致**。

回归：桌面图标启动仍正常（`action=(非小组件启动) flags=0x10000000`）。

#### 关于 `android:taskAffinity=""`（查了，但**没动**）

`MainActivity` 上有个不常见的 `taskAffinity=""`，一度怀疑它导致小组件另起任务栈。
但实测「图标启动」与「小组件点击」**落在同一个任务**；
且 launcher 图标点击本身就带 `FLAG_ACTIVITY_NEW_TASK`（`flags=0x10000000`）——
既然那条路在澎湃 OS 上是通的，`taskAffinity` 就不是拦截原因。**因此保持原样，不做无依据改动。**

### 11.6 定稿方案：广播中转（依据同级参考项目，2026-09-20）

#### 证据来源

工作区同级目录下有两个**已实际针对 HyperOS** 的开源项目，逐项比对后的结论：

| | `calendar_countdown_widget`（原生 Java，专为 HyperOS 写） | `life-798`（Kotlin） |
|---|---|---|
| 小组件点击 PI | **`PendingIntent.getBroadcast`** → 自己的 Provider | **`getBroadcast`** → 自己的 Provider |
| 打开 App 的方式 | `onReceive()` 里 `ctx.startActivity(...)` | 打开配置页用 `getActivity`（未配置态） |
| HyperOS 注释 | **README 有专章「踩坑记录（HyperOS 开发注意事项）」** | 「不使用 `android:configure`（HyperOS 不兼容）」 |
| Provider 注册 | `exported="true"` + 自定义 action 写进 `intent-filter` | `exported="true"` |

`calendar_countdown_widget` README 原文（**直接命中我们的症状**）：

> **小组件的 `PendingIntent` 不能直接从桌面进程启动「另一个 App 的 Activity」**
> —— HyperOS 会拦截，**静默回退成打开小组件自己的 App**。可行方案：发**广播**给自己的
> Provider，自己进程里再 `startActivity()` 跳转，这是应用内主动发起的调用，不受此限制。

> **中转 Activity 若设为 `exported="false"`，也可能被 HyperOS 拦截**
> （即使 PendingIntent 理论上不受 exported 限制）。

其 `CountdownWidgetProvider` 源码注释同结论：
「HyperOS blocks a widget's PendingIntent from directly targeting another app's Activity,
but is fine with an app-initiated startActivity() once we're running our own code.」

> `life-798` 的「`android:configure` 不兼容」与我们无关 ——
> 我们两个 widget XML **都没有声明 `android:configure`**（已核对）。

#### 最终架构

```
点击 → PendingIntent.getBroadcast → MedsWidgetClickReceiver.onReceive
     → context.startActivity(Intent.makeMainActivity(MainActivity))    ✅
```

- Glance 侧用 **`actionSendBroadcast(Intent)`**（`androidx.glance.appwidget.action`）。
  反编译确认 `getPendingIntentForAction` 的 `SendBroadcastAction` 分支是**直接**
  `PendingIntent.getBroadcast(...)`，`applyTrampolineIntent` **只**在
  `getFillInIntentForAction` 里调用 —— 即不经过任何 `exported="false"` 的中转 Activity，
  正好同时避开参考项目提到的第二个坑。
- 新文件 [`MedsWidgetClickReceiver.kt`](../android/app/src/main/kotlin/com/daanser/transprism/widget/MedsWidgetClickReceiver.kt:1)，
  manifest 声明 `android:exported="true"` + `intent-filter`（与参考项目的 Provider 同形），
  `onReceive` 严格校验 action。
- **data URI 必须逐点击目标唯一**：`PendingIntent` 去重依据是 `Intent.filterEquals`，
  它**忽略 extras**。若只用 extras 区分不同药的行，几行会被判成同一个 PendingIntent，
  `FLAG_UPDATE_CURRENT` 让最后一个覆盖全部 → **点哪行都开同一味药**。
  故写入 `transprism://widget/{action}/{drugId}`。

#### 踩到的坑（本地 adb 测试抓到，非真机试错）

`Intent.makeMainActivity()` **不带 `FLAG_ACTIVITY_NEW_TASK`**。从 Receiver 这种非
Activity context 调 `startActivity` 会直接抛：

```
AndroidRuntimeException: Calling startActivity() from outside of an Activity context
requires the FLAG_ACTIVITY_NEW_TASK flag.
```

必须**显式**加。补充说明：之前那条 `PendingIntent.getActivity` 路径的 logcat 里
`flg=0x10200000` 曾让我误以为 `makeMainActivity` 自带 NEW_TASK ——
实际上那是 **AMS 在 PendingIntent 路径上自动补的**，直发 Receiver 时不会补。

#### 真机级验证（Pixel 模拟器 / Android 16 / API 36，release 包）

| 场景 | 结果 |
|---|---|
| 冷启动（App 完全未运行） | `BAL_ALLOW_TOKEN` → `MainActivity.onCreate` → Dart 收到 `action=open_meds` ✅ |
| App 在后台（未杀） | `BAL_ALLOW_TOKEN` → `onNewIntent` → Dart 收到 ✅ |
| App 在前台 | `onNewIntent` → Dart 收到 ✅ |
| 回归·桌面图标启动 | `onCreate ← action=(非小组件启动)`，未受影响 ✅ |

**逐行唯一性验证**（注入 3 味药：螺内酯·已超9h / 黄体酮注射液·已超2h / 戊酸雌二醇·5h，
每次点击前 `am force-stop` 走冷启动）：

| 点第几行 | 期望 | 实际 |
|---|---|---|
| 1 | `drug-spiro` 螺内酯 | ✅ `drugId=drug-spiro name=螺内酯` |
| 2 | `drug-progesterone` 黄体酮注射液 | ✅ `drugId=drug-progesterone name=黄体酮注射液` |
| 3 | `drug-estradiol` 戊酸雌二醇 | ✅ `drugId=drug-estradiol name=戊酸雌二醇` |

第 2 行点击后弹出的 Sheet 标题确为「记录用药 / 黄体酮注射液」，库存 30.0 / 剂量 5.0 ——
**证明 data URI 唯一性生效，没有出现「点哪行都开同一味药」的 PendingIntent 覆盖问题。**

关键日志：

```
D TP-Widget: 小组件点击已送达（广播中转）: action=open_meds drugId=-
I ActivityTaskManager: START u0 {act=MAIN cat=[LAUNCHER] flg=0x10200000 cmp=.../.MainActivity}
   from uid 10237 (com.daanser.transprism) (BAL_ALLOW_TOKEN) result code=0
D TP-Widget: 已 startActivity(MainActivity) flags=0x10200000
D TP-Widget: MainActivity.onCreate ← action=open_meds ...
I flutter : 🧩 [TP-Widget] action=open_meds drugId=null name=null
```

> ⚠️ **`BAL_ALLOW_TOKEN` 是这次验证最重要的发现。**
> 用 `adb shell am broadcast` 直发 Receiver 时得到的是 **`BAL_BLOCK`**（被拦），
> 因为发送方是 shell（不可见）；而**真实小组件点击的发送方是桌面（可见）**，
> 系统会给接收方一个临时放行 → `BAL_ALLOW_TOKEN`。
> 也就是说：广播中转这条路**在真实点击下是放行的**，
> 但不能用 `am broadcast` 来模拟验证——会得出错误结论。

### 11.7 真机反馈「要点很多下才能进去一次」→ 加自检（2026-09-21）

#### 症状变化本身就是信息

| 阶段 | 用户反馈 | 说明 |
|---|---|---|
| 原始（`PendingIntent.getActivity`） | 点击**完全没反应** | 单一跳转被拦死 |
| 11.5（launcher 形态 Intent） | 还是不行 | — |
| 11.6（**广播中转**） | **点很多下才能进去一次** | **从「从不」变成「间歇」** → 广播链路本身是通的 |

**结论：广播中转方向是对的，剩下的是「间歇性投递/放行」问题。**

#### 两种可能，必须区分

1. **广播没送到 App** —— MIUI 限制后台应用接收广播 / 未允许「自启动」/ 省电策略过严；
2. **广播到了，但最后一步 `startActivity` 被拦** —— 「后台弹出界面」/ BAL 不一致。

两者**修法完全不同**（一个是用户设置，一个在启动链路），不能再猜。

#### 做法：App 内自检（不需要 adb）

远程测试者没有 adb，所以把判断依据做进 App：

- [`MedsWidgetClickReceiver`](../android/app/src/main/kotlin/com/daanser/transprism/widget/MedsWidgetClickReceiver.kt:1)
  每次收到点击就落盘到独立 SP `meds_widget_click_diag`：
  `last_click_at` / `last_click_action` / `last_click_start_ok` / `click_count`。
  用 `commit()` 而非 `apply()` —— Receiver 返回后进程随时可能被冻结，异步落盘有丢失风险。
- 原生通道 `widget_action` 新增 `getWidgetClickDiag`。
- Dart [`MedsWidgetService.clickDiag()`](../lib/services/meds_widget_service.dart:1) → 
  「我的 → 高级 → 通知权限与保活」底部展示**「小组件点击自检」**：
  `累计收到 N 次 · 最近一次 MM-DD HH:mm` + 对应结论提示。

**怎么用**：让测试者点几次小组件，再进这一页看：
- **次数不涨** → 广播没送到 → 去开「自启动」+ 省电策略「无限制」；
- **次数涨了但仍打不开** → 广播到了 → 是 `startActivity` 被拦 → 去开「后台弹出界面」。

### 11.8 定案：HyperOS 上广播路径不可达 → 退回 `getActivity` 直跳（2026-09-21）

#### 决定性证据

用户真机截图（小米 / 澎湃 OS，四项权限**全部已允许**）：

| 项 | 状态 |
|---|---|
| 系统通知权限 / 忽略电池优化 / 厂商后台自启动 | 已开启 / 已允许 / 已允许 |
| **后台弹出界面** | **已允许** |
| **小组件点击自检** | **累计收到 0 次 · 从未收到** |

**删除并重新添加小组件后仍为 0** → 结论：

> **HyperOS 根本不把小组件的点击交给我们的广播接收器。**
> 与「自启动 / 电池优化 / 后台弹出界面」无关（三项都已允许）。

参考项目 `calendar_countdown_widget` 的广播方案在它自己身上成立，**在本 App 上不成立 —— 不能照搬**。
（它把广播发给**自己的 `AppWidgetProvider`**；我们发给了独立的 Receiver。这可能是差异所在，
但既然真机实测为 0，没有继续沿这条路的依据。）

#### 因此退回单跳的 `PendingIntent.getActivity`

少一个失败环节，且这是唯一会被系统尝试投递的路径。
Intent 仍与**桌面图标启动同形**（`Intent.makeMainActivity` + 显式
`FLAG_ACTIVITY_NEW_TASK | FLAG_ACTIVITY_RESET_TASK_IF_NEEDED`）—— 那条路径在 HyperOS 上已验证可用。

`MedsWidgetClickReceiver` **保留但不再接线**（见其类注释）：留作一行可切回的备选，
且它的计数本身就是「广播路径在真机上到底通不通」的证据。

#### 自检升级：把指标做在「终点」上

之前的自检只测中间那一跳（广播），这次改成三个指标（原生 [`MedsWidgetDiag`]）：

| 指标 | 写入方 | 作用 |
|---|---|---|
| **卡片最近渲染** | 小组件 `provideContent` | **永久排除「桌面上是旧卡片」这个干扰项** |
| **被小组件拉起** | `MainActivity.onCreate/onNewIntent` | **终点指标** —— >0 就说明点击真能拉起 App |
| 广播收到 | `MedsWidgetClickReceiver`（备用） | 广播路径通不通 |

UI 会直接给结论：
- 被拉起 > 0 → 「点击能正常拉起 App ✅」
- 渲染时间是新的但被拉起 = 0 → 「卡片是当前版本，但点击没能拉起 App —— 系统层面拦下了，与权限无关」
- 从未渲染 → 「卡片还没渲染过」

**这一步同时修掉了我们前三轮最大的盲区**：反复「还是不行」里，
一直无法区分「卡片是旧的」和「点击真没送达」——现在一眼可辨。

### 11.9 真机对照实验收敛（2026-09-21）

#### 第一张截图：把「卡片是旧的」这个干扰项永久钉死

自检三行上线后，用户真机（澎湃 OS）截图：

```
卡片最近渲染  09-21 02:30     ← 卡片是当前版本
被小组件拉起  0 次
广播收到      2 次            ← ★ 广播其实送到了
```

**「广播收到 2 次」直接推翻了我 11.8 的结论**：11.8 里看到的「0 次」
**不是 HyperOS 不投递广播，而是桌面上那张卡片是旧的**（覆盖安装会取消 PendingIntent）。
按提示**删除并重新添加小组件后，计数立刻变成 2** —— 广播是能送到的。

> **排查陷阱（务必记住）**：看到「累计收到 0 次」时，
> **必须先确认「卡片最近渲染」是当前版本**，否则会得出完全相反的结论。
> 我因此多绕了一整轮。

#### 第二张截图：直跳其实能成，只是不稳定

```
卡片最近渲染  09-21 02:31
被小组件拉起  1 次 · 最近 09-21 02:31   ← ★ 成功拉起了
广播收到      2 次
点击能正常拉起 App ✅
```

**所以不是「从不」，是「偶尔」。** 两条路都测过，都能成，只是都不稳定：

| 路径 | 投递 | 最终拉起 |
|---|---|---|
| `getBroadcast` → Receiver → `startActivity` | 送达（2 次） | 不稳定 |
| `getActivity` 单跳 | — | 能成（≥1 次） |

#### 关键判断：参考项目那条限制**不适用于我们**

`calendar_countdown_widget` README 原文：

> 小组件的 `PendingIntent` 不能直接从桌面进程启动**「另一个 App 的 Activity」**
> —— HyperOS 会拦截，**静默回退成打开小组件自己的 App**。

**关键是「另一个 App 的」**：它要跳系统日历，被拦后才退化成打开自己。
而**我们的目标本来就是自己的 App** —— 那个「回退」正是我们要的结果。
所以广播中转属于**过度设计**（多一个投递环节 = 多一个失败点），已改回**单跳直拉**。

#### 本轮两处修改

**① 点击改回 `PendingIntent.getActivity` 单跳**（[`MedsWidgetActions.kt`]）
Intent 仍与桌面图标启动同形：`Intent.makeMainActivity` + **显式**
`FLAG_ACTIVITY_NEW_TASK | FLAG_ACTIVITY_RESET_TASK_IF_NEEDED`。

**② 移除 `MainActivity` 上的 `android:taskAffinity=""`**（[`AndroidManifest.xml`]）

这是整个 manifest 里**唯一非标准**的声明，也是「偶尔才成」最合理的解释：

- 空 affinity + `FLAG_ACTIVITY_NEW_TASK`（小组件点击 / 通知 / 中转 Receiver 都用它）
  属于**未定义地带**：系统可能每次都**新建一个 task**，而不是把已有的 app task 拉回前台；
- 而「从后台新建 task」正是 ROM 最容易拦的一类操作；
- 移除后 affinity 回落到默认值（包名），launch 行为与「点桌面图标」**完全一致**——
  那条路径在澎湃上被验证是稳定可用的。

manifest 里已加注释说明，避免以后被误加回来。

### 11.10 找到症结：后台启动 Activity 限制（BAL）→ 用悬浮窗权限豁免（2026-09-21）

#### 症状拼图

把几轮反馈按时间排开，模式就出来了：

| 时刻 | 状态 | 结果 |
|---|---|---|
| 用户刚在 App 里看完自检 | 应用**刚在前台** | 点击**能**拉起（1 次 → 2 次）|
| 隔一阵再点 | 应用**已在后台** | **不涨**（点了没用）|

**「刚用完 App 能成、过一阵就不行」正是后台启动限制（BAL）的指纹** ——
不是 ROM 随机抽风，而是应用的前台状态决定放不放行。

#### 正解：`SYSTEM_ALERT_WINDOW` 是 BAL 的豁免项之一

Android 10+ 限制应用在**后台启动 Activity**。而小组件点击的本质就是
「从后台启动 Activity」。Android 的 BAL **豁免清单里有一条：持有
`SYSTEM_ALERT_WINDOW`（显示在其他应用上层）的应用**。

旁证：早先查国产 ROM 资料时，**OPPO 的「后台弹出界面」判据就是
`Settings.canDrawOverlays(context)`** —— 说明国产 ROM 用的正是这条豁免。

#### 本轮改动

1. **声明权限**：`AndroidManifest.xml` 加 `android.permission.SYSTEM_ALERT_WINDOW`
   （附注释说明它为什么与用药 App 有关，避免以后被当成多余权限删掉）。
2. **检测 + 引导**：[`PermissionManager`](../lib/services/permission_manager.dart:1)
   新增 `hasSystemAlertWindow()` / `requestSystemAlertWindow()`（走 `permission_handler`
   的 `Permission.systemAlertWindow`，无需自写原生代码）。
3. **UI**：[`battery_optimization_guide_card.dart`](../lib/widgets/battery_optimization_guide_card.dart:1)
   新增一行「**显示在其他应用上层**」，未授权时显示「点小组件打不开？去开启」，
   点开有说明弹窗 → 跳系统设置 → 回来自动刷新。**所有机型都显示**
   （BAL 限制是 Android 10+ 通用的，不只小米）。
4. **自检提示修正**：原文写「与权限设置无关」是**错的** —— 已改为
   「这是系统拦掉了『从后台启动界面』，请开启上方的『显示在其他应用上层』」。

#### 为什么这次不一样

前几轮一直在改**启动链路**（Intent 形态、广播中转、taskAffinity），
但真正的闸门是**系统层面的后台启动策略**，链路上怎么改都绕不过去。
这次改的是**让应用获得豁免资格**。

### 11.4 未完成 / 待真机确认

- **本地无澎湃 OS 设备，无法直接复现用户环境**。上面两条是「官方文档 + 本地可复现的
  相邻现象」推出的最可能原因，**尚未在澎湃 OS 4 真机上验证**。
- 用户反馈（2026-09-19）：「**显示是正常的，但是点击没办法打开应用**」。
  这**排除了机制 A**（占位图）——RemoteViews 正常应用了，问题只在最后那一步
  Activity 启动。指向 **B**。
- 下一步只需确认一件事：**「后台弹出界面」是否已允许**。
  现在 App 内即可自查：**我的 → 高级 → 通知权限与保活**，
  小米/澎湃机型会多出一行「后台弹出界面」，未允许时显示「点小组件没反应？去开启」。
- 若开启后仍无效，再抓 `logcat | grep TP-Widget` 看有没有 `MainActivity.*` 那行：
  有 → 问题在 App 内；没有 → 说明连中转 Activity 都没起来，需要走下面的退路。
- **退路**（若确认是该权限且拿不到白名单）：把小组件点击改成
  **发一条通知**（通知点击由系统 UI 发起，不受该权限限制），用户从通知进入 App。
  代价是多一次点击，但比「点了完全没反应」好。
