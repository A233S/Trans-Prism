import 'package:flutter/material.dart';

import '../services/meds_widget_service.dart';
import '../services/oem_permission_service.dart';
import '../services/permission_manager.dart';
import 'gradient_icon.dart';

// =============================================================================
// BatteryOptimizationGuideCard — 「通知到达率优化」状态检测卡片
//
// 功能：
//   1. 动态检测并展示 3 项关键保活权限的状态
//   2. 点击「去设置」跳转对应的系统设置页
//   3. 图标 + 颜色直观反映状态（绿/红/橙）
// =============================================================================
class BatteryOptimizationGuideCard extends StatefulWidget {
  const BatteryOptimizationGuideCard({super.key});

  @override
  State<BatteryOptimizationGuideCard> createState() =>
      _BatteryOptimizationGuideCardState();
}

class _BatteryOptimizationGuideCardState
    extends State<BatteryOptimizationGuideCard> {
  final PermissionManager _permManager = PermissionManager();

  /// 当前权限状态缓存：true=已授权，false=未授权
  Map<String, bool> _statuses = {
    'notification': false,
    'exact_alarm': false,
    'battery_optimization': false,
  };

  /// 是否正在加载
  bool _loading = true;

  /// 本机是否小米系（小米 / 红米 / POCO / 澎湃 OS）——
  /// 只有这类机型才有「后台弹出界面」这个权限项
  bool _isMiui = false;

  /// 「后台弹出界面」是否已允许（仅小米系有意义）
  bool _bgPopupAllowed = false;

  /// 小组件点击自检；null = 非 Android 或读取失败（UI 隐藏该块）
  WidgetClickDiag? _clickDiag;

  /// 是否已授予「显示在其他应用上层」（SYSTEM_ALERT_WINDOW）
  ///
  /// 这是**小组件点击能否打开 App 的真正关键**：Android 10+ 限制后台启动 Activity，
  /// 而持有该权限的应用在 BAL 豁免名单内。
  bool _overlayGranted = false;

  @override
  void initState() {
    super.initState();
    _refreshStatuses();
  }

  Future<void> _refreshStatuses() async {
    setState(() => _loading = true);
    final statuses = await _permManager.checkPermissionStatuses();
    final isMiui = await OemPermissionService.isMiuiFamily();
    final bgPopup =
        isMiui ? await OemPermissionService.isBackgroundPopupAllowed() : true;
    final diag = await MedsWidgetService.clickDiag();
    final overlay = await _permManager.hasSystemAlertWindow();
    if (mounted) {
      setState(() {
        _statuses = statuses;
        _isMiui = isMiui;
        _bgPopupAllowed = bgPopup;
        _clickDiag = diag;
        _overlayGranted = overlay;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor =
        isDark ? const Color(0xFFEDEDF0) : const Color(0xFF333333);
    final secondaryColor =
        isDark ? const Color(0xFF8E8E96) : const Color(0xFF8A8A86);
    final cardBg = isDark ? const Color(0xFF24242C) : Colors.white;
    final cardBorderColor =
        isDark ? const Color(0xFF333338) : const Color(0xFFE5E5E5);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cardBorderColor, width: 0.5),
      ),
      color: cardBg,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 标题行 ──
            Row(
              children: [
                Icon(
                  Icons.notifications_active_outlined,
                  size: 22,
                  color: secondaryColor,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '通知到达率优化',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '确保系统不拦截您的用药提醒',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: secondaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                // 刷新按钮
                IconButton(
                  icon: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          Icons.refresh_rounded,
                          size: 20,
                          color: isDark
                              ? Colors.grey.shade500
                              : Colors.grey.shade400,
                        ),
                  onPressed: _loading ? null : _refreshStatuses,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── 3 项状态条目 ──
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else ...[
              _buildStatusItem(
                isDark: isDark,
                icon: Icons.notifications_outlined,
                title: '系统通知权限',
                granted: _statuses['notification'] ?? false,
                grantedLabel: '已开启',
                deniedLabel: '去开启',
                onDeniedTap: () => _handlePermissionAction(
                  context,
                  'notification',
                  _permManager.requestNotificationPermission,
                ),
              ),
              const Divider(height: 1, indent: 0),
              _buildStatusItem(
                isDark: isDark,
                icon: Icons.battery_charging_full_outlined,
                title: '忽略电池优化',
                granted: _statuses['battery_optimization'] ?? false,
                grantedLabel: '已允许',
                deniedLabel: '去设置',
                onDeniedTap: () => _handlePermissionAction(
                  context,
                  'battery_optimization',
                  _permManager.requestIgnoreBatteryOptimization,
                ),
              ),
              const Divider(height: 1, indent: 0),
              _buildStatusItem(
                isDark: isDark,
                icon: Icons.power_settings_new_rounded,
                title: '厂商后台自启动',
                granted: _statuses['battery_optimization'] ?? false,
                grantedLabel: '已允许',
                deniedLabel: '强烈建议去设置',
                onDeniedTap: () => _handleOpenAutoStart(context),
                // 自启动无法通过 API 判断，跟随电池优化状态作为参考
                // 如果电池优化已允许，标记为黄色「建议确认」
                // 如果未允许，标记为红色「强烈建议」
              ),
              // 小米 / 澎湃 OS 专属：该权限默认拒绝，会拦掉小组件点击后的 Activity 启动
              if (_isMiui) ...[
                const Divider(height: 1, indent: 0),
                _buildStatusItem(
                  isDark: isDark,
                  icon: Icons.widgets_outlined,
                  title: '后台弹出界面',
                  granted: _bgPopupAllowed,
                  grantedLabel: '已允许',
                  deniedLabel: '点小组件没反应？去开启',
                  onDeniedTap: () => _handleOpenBackgroundPopup(context),
                ),
              ],
              // 「显示在其他应用上层」—— 小组件点击能否打开 App 的关键（所有机型都显示）
              const Divider(height: 1, indent: 0),
              _buildStatusItem(
                isDark: isDark,
                icon: Icons.layers_outlined,
                title: '显示在其他应用上层',
                granted: _overlayGranted,
                grantedLabel: '已允许',
                deniedLabel: '点小组件打不开？去开启',
                onDeniedTap: () => _handleOpenOverlayPermission(context),
              ),
              // 小组件点击自检：区分「广播没送到」与「Activity 启动被拦」
              if (_clickDiag != null) ...[
                const Divider(height: 1, indent: 0),
                _buildClickDiagBlock(
                  isDark: isDark,
                  textColor: textColor,
                  secondaryColor: secondaryColor,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  /// 小组件点击自检块 —— 把「哪一段断了」直接摆出来，不需要 adb。
  ///
  /// 三个指标（原生 `MedsWidgetDiag` 落盘）：
  /// - **卡片最近渲染**：排除「桌面上是旧卡片」这个干扰项；
  /// - **被小组件拉起**：终点指标 —— 只要 > 0，就说明点击真能把 App 拉起来；
  /// - **广播收到**：备用广播路径的计数（澎湃 OS 实测恒为 0）。
  Widget _buildClickDiagBlock({
    required bool isDark,
    required Color textColor,
    required Color secondaryColor,
  }) {
    final d = _clickDiag!;

    String two(int n) => n.toString().padLeft(2, '0');
    String fmt(DateTime? t) => t == null
        ? '从未'
        : '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';

    final String hint;
    final Color hintColor;
    if (d.everLaunched) {
      hint = '点击能正常拉起 App ✅';
      hintColor = const Color(0xFF2E9E5B);
    } else if (d.renderTime != null) {
      hint = '卡片是当前版本（渲染时间见上），但点击没能拉起 App —— '
          '这是系统拦掉了「从后台启动界面」。'
          '请开启上方的「显示在其他应用上层」，再点一次小组件。';
      hintColor = const Color(0xFFD08700);
    } else {
      hint = '卡片还没渲染过：请先在桌面上添加用药小组件，再回来查看。';
      hintColor = secondaryColor;
    }

    final launchText =
        d.everLaunched ? '${d.launchCount} 次 · 最近 ${fmt(d.launchTime)}' : '0 次';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights_outlined, size: 18, color: secondaryColor),
              const SizedBox(width: 8),
              Text(
                '小组件点击自检',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _diagLine('卡片最近渲染', fmt(d.renderTime), textColor, secondaryColor),
          const SizedBox(height: 4),
          _diagLine('被小组件拉起', launchText, textColor, secondaryColor),
          const SizedBox(height: 4),
          _diagLine(
            '广播收到',
            '${d.clickCount} 次',
            textColor,
            secondaryColor,
          ),
          const SizedBox(height: 8),
          Text(
            hint,
            style: TextStyle(fontSize: 12, height: 1.5, color: hintColor),
          ),
        ],
      ),
    );
  }

  /// 自检块里的「标签 —— 值」一行
  Widget _diagLine(
    String label,
    String value,
    Color textColor,
    Color secondaryColor,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 104,
          child: Text(
            label,
            style: TextStyle(fontSize: 12.5, color: secondaryColor),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ),
      ],
    );
  }

  /// 构建单条状态条目
  Widget _buildStatusItem({
    required bool isDark,
    required IconData icon,
    required String title,
    required bool granted,
    required String grantedLabel,
    required String deniedLabel,
    required VoidCallback onDeniedTap,
  }) {
    final textColor =
        isDark ? const Color(0xFFEDEDF0) : const Color(0xFF333333);
    final secondaryColor =
        isDark ? const Color(0xFF8E8E96) : const Color(0xFF8A8A86);
    final okColor = isDark ? const Color(0xFF6BBE7A) : const Color(0xFF4CAF50);
    final warnColor =
        isDark ? const Color(0xFFE57373) : const Color(0xFFC44A4A);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: granted ? null : onDeniedTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Row(
            children: [
              // 状态图标
              Icon(
                granted ? Icons.check_rounded : Icons.error_outline,
                size: 20,
                color: granted ? okColor : warnColor,
              ),
              const SizedBox(width: 12),
              // 标题
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                    color: textColor,
                  ),
                ),
              ),
              // 状态文本 / 操作按钮
              if (granted)
                Text(
                  grantedLabel,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: okColor,
                  ),
                )
              else
                GestureDetector(
                  onTap: onDeniedTap,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        deniedLabel,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: warnColor,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: warnColor,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ────────────── 交互逻辑 ──────────────

  /// 请求权限并刷新状态
  Future<void> _handlePermissionAction(
    BuildContext context,
    String permissionKey,
    Future<bool> Function() requestFn,
  ) async {
    final granted = await requestFn();
    if (mounted) {
      // 刷新状态
      _refreshStatuses();

      if (!granted) {
        // 如果用户拒绝，引导到系统设置
        final shouldOpenSettings = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.info_outline,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFFE5E5EA)
                        : const Color(0xFF333338)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '需要手动授权',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            content: const Text(
              '系统拒绝了此次授权申请，请前往系统设置中手动开启。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('暂不'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                ),
                child: const Text('去系统设置'),
              ),
            ],
          ),
        );
        if (shouldOpenSettings == true && mounted) {
          await _permManager.openAppSettings();
        }
      }
    }
  }

  /// 引导用户前往自启动设置
  Future<void> _handleOpenAutoStart(BuildContext context) async {
    final shouldOpen = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.power_settings_new_rounded,
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFFE5E5EA)
                    : const Color(0xFF333338)),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                '厂商后台自启动',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '不同手机品牌（小米、华为、OPPO、vivo 等）的后台管理策略不同，'
              'APP 无法直接代码授权自启动。请按以下步骤操作：',
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
            SizedBox(height: 12),
            _StepLabel(
              number: '1',
              text: '在系统设置中搜索「自启动」或「后台管理」',
            ),
            SizedBox(height: 6),
            _StepLabel(
              number: '2',
              text: '找到「Trans Prism」并开启自启动开关',
            ),
            SizedBox(height: 6),
            _StepLabel(
              number: '3',
              text: '在近期任务列表中将本应用下划锁定 🔒',
            ),
            SizedBox(height: 14),
            Text(
              '小米 / 澎湃 OS 请额外确认以下两项：',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1.5,
              ),
            ),
            SizedBox(height: 8),
            _StepLabel(
              number: '4',
              text: '省电策略改为「无限制」\n'
                  '（设置 → 应用设置 → 应用管理 → Trans Prism → 省电策略）。'
                  '被系统强行停止后，桌面小组件会变成灰色占位图且点击无反应。',
            ),
            SizedBox(height: 6),
            _StepLabel(
              number: '5',
              text: '开启「后台弹出界面」\n'
                  '（设置 → 应用设置 → Trans Prism → 权限管理 → 后台弹出界面）。'
                  '该权限在澎湃 OS 上默认关闭，未开启时点桌面小组件不会打开 App。',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
            child: const Text('去系统设置'),
          ),
        ],
      ),
    );
    if (shouldOpen == true && mounted) {
      await _permManager.openAutoStartSettings();
    }
  }

  /// 「显示在其他应用上层」引导 + 跳转。
  ///
  /// 这是小组件点击问题的**正解**：Android 10+ 的「后台启动 Activity 限制」（BAL）
  /// 会拦掉「从后台拉起 App」，而小组件点击正是这种操作 ——
  /// 表现为「刚看完 App 时能点开，过一阵就点不开了」。
  ///
  /// Android 的 BAL 豁免清单里有一条：**持有 `SYSTEM_ALERT_WINDOW` 的应用**。
  /// 该权限必须用户手动授予，所以这里做「检测 → 说明 → 跳转 → 回来自动刷新」。
  Future<void> _handleOpenOverlayPermission(BuildContext context) async {
    final shouldOpen = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.layers_outlined,
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFFE5E5EA)
                  : const Color(0xFF333338),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                '显示在其他应用上层',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '系统限制应用在「后台」启动界面。桌面小组件的点击正属于这种操作，'
              '所以未开启时会出现「点小组件打不开、或者要点很多次」。',
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
            SizedBox(height: 12),
            _StepLabel(number: '1', text: '点下方「去开启」，进入本应用的悬浮窗开关'),
            SizedBox(height: 6),
            _StepLabel(number: '2', text: '打开「允许显示在其他应用上层」'),
            SizedBox(height: 6),
            _StepLabel(number: '3', text: '返回桌面再点小组件，即可稳定打开'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
            child: const Text('去开启'),
          ),
        ],
      ),
    );
    if (shouldOpen == true && mounted) {
      await _permManager.requestSystemAlertWindow();
      if (mounted) await _refreshStatuses();
    }
  }

  /// 小米 / 澎湃 OS：「后台弹出界面」引导 + 跳转
  ///
  /// 这条是「桌面小组件点了不弹应用」的直接嫌疑：小组件点击要走
  /// `PendingIntent → 中转 Activity → MainActivity`，而该权限默认拒绝、
  /// 会拦掉后台的 Activity 启动。卡片本身渲染不受影响，所以用户看到的是
  /// 「显示正常但点了没反应」。
  Future<void> _handleOpenBackgroundPopup(BuildContext context) async {
    final shouldOpen = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.widgets_outlined,
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFFE5E5EA)
                  : const Color(0xFF333338),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                '后台弹出界面',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '小米 / 澎湃 OS 的「后台弹出界面」权限默认是关闭的。'
              '关闭时，点桌面用药小组件不会打开 App（卡片显示正常，但点了没反应）。',
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
            SizedBox(height: 12),
            _StepLabel(number: '1', text: '点下方「去开启」，进入权限管理页'),
            SizedBox(height: 6),
            _StepLabel(number: '2', text: '找到「后台弹出界面」并选择「允许」'),
            SizedBox(height: 6),
            _StepLabel(
              number: '3',
              text: '回到桌面再点一次小组件即可正常打开',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
            child: const Text('去开启'),
          ),
        ],
      ),
    );
    if (shouldOpen == true && mounted) {
      await OemPermissionService.openBackgroundPopupSettings();
      // 用户可能已经开启，回来自动刷新一次状态
      if (mounted) await _refreshStatuses();
    }
  }
}

/// 步骤说明小部件
class _StepLabel extends StatelessWidget {
  final String number;
  final String text;

  const _StepLabel({
    required this.number,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(
              number,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
        ),
      ],
    );
  }
}
