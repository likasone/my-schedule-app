import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';

import '../../../core/services/plan_scheduler.dart';
import '../../../core/services/reminder_service.dart';
import '../providers/schedule_provider.dart';

/// 日程、计划、复习与便签核心页面（Schedule & Plan Page）
/// 专为跨平台原生打造，在 Windows 宽屏桌面与移动端竖屏均提供自适应的高效体验。
class SchedulePage extends ConsumerStatefulWidget {
  const SchedulePage({super.key});

  @override
  ConsumerState<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends ConsumerState<SchedulePage> {
  final TextEditingController _quickMemoController = TextEditingController();
  String _selectedNewMemoTag = '闪念';
  bool _isNewMemoPinned = false;
  int _selectedNewMemoColor = 0; // 花笺纸色索引（0: 霜白, 1: 樱落, 2: 竹韵, 3: 麦穗, 4: 晴川, 5: 暮薰）

  /// 花笺（Floral Notepaper）拟真 6 色低饱和东方信笺纸色板
  static const List<({String name, Color lightBg, Color darkBg, Color border, Color accent})> floralSkins = [
    (name: '霜白', lightBg: Color(0xFFFBF9F5), darkBg: Color(0xFF222120), border: Color(0xFFE8E1D3), accent: Color(0xFF6B6B62)),
    (name: '樱落', lightBg: Color(0xFFFDF2F4), darkBg: Color(0xFF332025), border: Color(0xFFF6D6DC), accent: Color(0xFFD4697F)),
    (name: '竹韵', lightBg: Color(0xFFEBF5EE), darkBg: Color(0xFF1B2E22), border: Color(0xFFCDE4D4), accent: Color(0xFF2D5A3D)),
    (name: '麦穗', lightBg: Color(0xFFFBF4E6), darkBg: Color(0xFF30271A), border: Color(0xFFF1E2C3), accent: Color(0xFFB5832E)),
    (name: '晴川', lightBg: Color(0xFFEDF5FA), darkBg: Color(0xFF1B2835), border: Color(0xFFD0E3F0), accent: Color(0xFF3B7EA1)),
    (name: '暮薰', lightBg: Color(0xFFF6F0F8), darkBg: Color(0xFF2B1F33), border: Color(0xFFE5D5EC), accent: Color(0xFF885A9E)),
  ];

  @override
  void initState() {
    super.initState();
    // 注册桌面端与全局提醒监听，到期时在前台弹窗展示并发出提示
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final reminderService = ref.read(reminderServiceProvider);
      reminderService.onDesktopReminderTriggered = (item) {
        if (!mounted) return;
        _showDesktopReminderAlert(item);
      };
    });
  }

  /// 桌面端与前台到期提醒展示弹窗
  void _showDesktopReminderAlert(ReminderItem item) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.alarm_on, color: Colors.amber, size: 48),
        title: Text('⏰ 日程提醒: ${item.title}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('提醒时间: ${DateFormat('yyyy年M月d日 HH:mm').format(item.reminderTime)}'),
            if (item.notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('备注: ${item.notes}'),
            ],
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _quickMemoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(scheduleProvider);
    final notifier = ref.read(scheduleProvider.notifier);

    // 解析当前选中的有效日期与今日日期
    final effectiveDate = PlanScheduler.parseIsoDate(state.effectiveDateIso);
    final dateDisplayStr = DateFormat('yyyy年M月d日 EEEE', 'zh_CN').format(effectiveDate);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            // 顶部核心看板（数据总览与新建按钮）
            _buildHeaderCard(context, state, notifier, dateDisplayStr),

            // 水平交互式日历条（仅在日程与计划视图展示，灵感便签下隐藏，为安卓窄屏释放 64px 空间）
            if (state.selectedTab != 2)
              _buildCalendarStrip(context, state, notifier),

            // 分类导航标签（日程待办 / 全部计划 / 灵感便签）
            _buildSegmentedTabs(context, state, notifier),

            // 主内容视图区（移除阻塞式全屏 loading，直接响应式渲染，彻底杜绝转圈）
            Expanded(
              child: IndexedStack(
                index: state.selectedTab,
                children: [
                  _buildTodayView(context, state, notifier),
                  _buildPlansView(context, state, notifier),
                  _buildMemosView(context, state, notifier),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 顶部核心信息与操作看板组件
  Widget _buildHeaderCard(
    BuildContext context,
    ScheduleState state,
    ScheduleNotifier notifier,
    String dateStr,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final todayList = state.selectedDateEntries;
    final completedCount = todayList.where((e) => e.isCompleted).length;
    final rate = state.todayCompletionRate;

    final isToday = state.effectiveDateIso == PlanScheduler.formatIsoDate(DateTime.now());

    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
      child: Container(
        padding: const EdgeInsets.all(20.0),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(24.0),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 响应式顶部操作栏：在移动端/安卓竖屏时自适应换行，避免拥挤溢出；在桌面端优雅横向平铺
            LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 640;
                final titleBlock = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '日程与计划中心',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                            fontSize: isCompact ? 18 : 22,
                          ),
                        ),
                        if (!isToday) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '指定日视图',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.onSecondaryContainer,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dateStr,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                );

                if (isCompact) {
                  // 安卓等小屏设备：标题栏独立置顶，操作按钮整齐平铺于下方，彻底杜绝混乱溢出
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: titleBlock),
                          IconButton.outlined(
                            tooltip: '立即测试提醒弹窗',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.notifications_active_outlined, size: 18),
                            onPressed: () => notifier.triggerTestReminder(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: () => _showCreateScheduleDialog(context, state, notifier),
                              icon: const FaIcon(FontAwesomeIcons.calendarPlus, size: 14),
                              label: const Text('加日程'),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => _showCreatePlanDialog(context, state, notifier),
                              icon: const FaIcon(FontAwesomeIcons.brain, size: 14),
                              label: const Text('建计划'),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                }

                // Windows 等大屏设备：横向两端对齐展示
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    titleBlock,
                    Row(
                      children: [
                        IconButton.outlined(
                          tooltip: '立即测试提醒弹窗',
                          icon: const Icon(Icons.notifications_active_outlined, size: 18),
                          onPressed: () => notifier.triggerTestReminder(),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonalIcon(
                          onPressed: () => _showCreateScheduleDialog(context, state, notifier),
                          icon: const FaIcon(FontAwesomeIcons.calendarPlus, size: 14),
                          label: const Text('加日程'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: () => _showCreatePlanDialog(context, state, notifier),
                          icon: const FaIcon(FontAwesomeIcons.brain, size: 14),
                          label: const Text('建计划'),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            // 完成度进度条
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8.0),
                    child: LinearProgressIndicator(
                      value: todayList.isEmpty ? 1.0 : rate,
                      minHeight: 8,
                      backgroundColor: colorScheme.surfaceContainerLowest,
                      valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  todayList.isEmpty
                      ? '无待办'
                      : '$completedCount/${todayList.length} (${(rate * 100).toInt()}%)',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 水平交互式日历条（支持快速切换前后两周日期与完整月历选择）
  Widget _buildCalendarStrip(
    BuildContext context,
    ScheduleState state,
    ScheduleNotifier notifier,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final now = DateTime.now();
    final todayIso = PlanScheduler.formatIsoDate(now);

    // 生成前后共 28 天的日期序列供快速横向滑动选择
    final dayOffsets = List<int>.generate(29, (i) => i - 7); // 前 7 天到未来 21 天

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: SizedBox(
        height: 64,
        child: Row(
          children: [
            // 回到今天快捷按钮
            IconButton.filledTonal(
              tooltip: '回到今天',
              icon: const Icon(Icons.today, size: 18),
              onPressed: () => notifier.selectToday(),
            ),
            const SizedBox(width: 6),
            // 完整月历大盘选择按钮
            IconButton.outlined(
              tooltip: '选择任意日期',
              icon: const Icon(Icons.calendar_month, size: 18),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: PlanScheduler.parseIsoDate(state.effectiveDateIso),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2035),
                  helpText: '选择日程查看日期',
                  confirmText: '确定',
                  cancelText: '取消',
                );
                if (picked != null) {
                  notifier.selectDate(PlanScheduler.formatIsoDate(picked));
                }
              },
            ),
            const SizedBox(width: 8),
            // 横向滑动日期胶囊列表
            Expanded(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: dayOffsets.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final targetDate = now.add(Duration(days: dayOffsets[index]));
                  final iso = PlanScheduler.formatIsoDate(targetDate);
                  final isSelected = iso == state.effectiveDateIso;
                  final isToday = iso == todayIso;

                  // 中文星期缩写
                  const weekNames = ['一', '二', '三', '四', '五', '六', '日'];
                  final weekName = weekNames[targetDate.weekday - 1];

                  return InkWell(
                    onTap: () => notifier.selectDate(iso),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: 48,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? colorScheme.primary
                            : (isToday
                                ? colorScheme.primaryContainer.withValues(alpha: 0.5)
                                : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4)),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected
                              ? colorScheme.primary
                              : (isToday
                                  ? colorScheme.primary.withValues(alpha: 0.6)
                                  : colorScheme.outlineVariant.withValues(alpha: 0.3)),
                          width: isToday || isSelected ? 1.5 : 1.0,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            isToday ? '今' : weekName,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: isToday || isSelected ? FontWeight.bold : FontWeight.normal,
                              color: isSelected
                                  ? colorScheme.onPrimary
                                  : (isToday ? colorScheme.primary : colorScheme.onSurfaceVariant),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${targetDate.day}',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 分段导航切换组件（防闪烁、平滑动画过渡）
  Widget _buildSegmentedTabs(
    BuildContext context,
    ScheduleState state,
    ScheduleNotifier notifier,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          // 选项卡 0：日程待办
          _buildTabItem(
            context,
            index: 0,
            title: '日程待办 (${state.selectedDateEntries.length})',
            isSelected: state.selectedTab == 0,
            onTap: () => notifier.setTab(0),
          ),
          const SizedBox(width: 8),
          // 选项卡 1：全部计划
          _buildTabItem(
            context,
            index: 1,
            title: '全部计划 (${state.plans.length})',
            isSelected: state.selectedTab == 1,
            onTap: () => notifier.setTab(1),
          ),
          const SizedBox(width: 8),
          // 选项卡 2：灵感便签（便签选项）
          _buildTabItem(
            context,
            index: 2,
            title: '灵感便签 (${state.memos.length})',
            isSelected: state.selectedTab == 2,
            onTap: () => notifier.setTab(2),
          ),
        ],
      ),
    );
  }

  /// 单个 Tab 胶囊组件
  /// [优化关键]：引入 AnimatedContainer 平滑颜色与边框过渡（200ms），
  /// 并显式屏蔽 Windows 平台下的焦点闪烁（focusColor/highlightColor/splashColor），
  /// 彻底根除点击切换便签选项时先前选中按钮的突变与闪烁现象（Flicker-Free）。
  Widget _buildTabItem(
    BuildContext context, {
    required int index,
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Expanded(
      child: Material(
        // 绑定确定性 Key 防止树重建混乱
        key: ValueKey('segmented_tab_btn_$index'),
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16.0),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16.0),
          // 彻底禁用 Windows 桌面端由于 FocusNode 焦点转移引发的高亮闪烁
          focusColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: colorScheme.primary.withValues(alpha: 0.04),
          child: AnimatedContainer(
            // 200ms 平滑动画曲线，消除颜色与尺寸跳变
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            padding: const EdgeInsets.symmetric(vertical: 10.0),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected
                  ? colorScheme.primaryContainer
                  : colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16.0),
              border: Border.all(
                color: isSelected
                    ? colorScheme.primary.withValues(alpha: 0.5)
                    : colorScheme.outlineVariant.withValues(alpha: 0.3),
                width: isSelected ? 1.5 : 1.0,
              ),
            ),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              style: (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
              ),
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 视图 1：今日待办与艾宾浩斯复习任务列表
  Widget _buildTodayView(
    BuildContext context,
    ScheduleState state,
    ScheduleNotifier notifier,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final entries = state.selectedDateEntries;

    if (entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FaIcon(
              FontAwesomeIcons.circleCheck,
              size: 48,
              color: colorScheme.outline.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              '当前日期没有待办或复习任务',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '点击上方「加日程」或「建计划」，或切换日历查看其他日期',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.outline,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final isReview = entry.kind == ScheduleEntryKind.review ||
            entry.kind == ScheduleEntryKind.remedial;

        return Card(
          margin: const EdgeInsets.only(bottom: 12.0),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18.0)),
          color: entry.isCompleted
              ? colorScheme.surfaceContainerLow.withValues(alpha: 0.6)
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
          elevation: entry.isCompleted ? 0 : 1,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // 打卡勾选框
                    Checkbox(
                      value: entry.isCompleted,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      onChanged: (_) => notifier.toggleEntryCompletion(entry.id),
                    ),
                    const SizedBox(width: 8),
                    // 阶段类型标识徽章
                    _buildKindBadge(context, entry.kind, entry.stepIndex),
                    const SizedBox(width: 8),
                    // 任务标题与优先级徽章
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              entry.title,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                                decoration: entry.isCompleted ? TextDecoration.lineThrough : null,
                                color: entry.isCompleted ? colorScheme.outline : colorScheme.onSurface,
                              ),
                            ),
                          ),
                          if (entry.isAllDay) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('全天', style: TextStyle(fontSize: 10, color: Colors.blue, fontWeight: FontWeight.bold)),
                            ),
                          ],
                          if (entry.priority != SchedulePriority.none) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: switch (entry.priority) {
                                  SchedulePriority.high => Colors.red.withValues(alpha: 0.15),
                                  SchedulePriority.medium => Colors.orange.withValues(alpha: 0.15),
                                  SchedulePriority.low => Colors.green.withValues(alpha: 0.15),
                                  _ => Colors.grey.withValues(alpha: 0.15),
                                },
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                entry.priority.label,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: switch (entry.priority) {
                                    SchedulePriority.high => Colors.red[700],
                                    SchedulePriority.medium => Colors.orange[800],
                                    SchedulePriority.low => Colors.green[700],
                                    _ => Colors.grey,
                                  },
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // 编辑日程待办按钮（唤起小米待办全能编辑弹窗）
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      color: theme.hintColor,
                      tooltip: '编辑日程',
                      onPressed: () => _showEditScheduleDialog(context, entry, notifier),
                    ),
                    // 删除日程待办按钮
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      color: theme.hintColor,
                      tooltip: '删除日程',
                      onPressed: () => _confirmDeleteScheduleEntry(context, entry, notifier),
                    ),
                  ],
                ),
                if (entry.notes.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(left: 48.0),
                    child: Text(
                      entry.notes,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
                // 历史逾期顺延提示
                if (entry.originalDueDate != null && !entry.isCompleted) ...[
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(left: 48.0),
                    child: Row(
                      children: [
                        Icon(Icons.history_toggle_off, size: 14, color: colorScheme.error),
                        const SizedBox(width: 4),
                        Text(
                          '逾期前移自 ${entry.originalDueDate}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.error,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                // 提醒时间与状态专属标签行
                if (entry.reminderTime != null || entry.repeatRule != ScheduleRepeatRule.none) ...[
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(left: 48.0),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (entry.reminderTime != null)
                          InkWell(
                            onTap: () => notifier.toggleEntryReminder(entry.id),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: entry.hasReminder
                                    ? (entry.isCompleted
                                        ? colorScheme.surfaceContainer
                                        : colorScheme.primaryContainer.withValues(alpha: 0.7))
                                    : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: entry.hasReminder
                                      ? colorScheme.primary.withValues(alpha: 0.4)
                                      : colorScheme.outlineVariant.withValues(alpha: 0.4),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    entry.hasReminder ? Icons.alarm_on : Icons.alarm_off,
                                    size: 13,
                                    color: entry.hasReminder
                                        ? colorScheme.primary
                                        : colorScheme.outline,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${DateFormat('HH:mm').format(entry.reminderTime!)} '
                                    '${entry.hasReminder ? '强提醒已就绪' : '提醒已暂停 (点击开启)'}',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: entry.hasReminder
                                          ? colorScheme.onPrimaryContainer
                                          : colorScheme.outline,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (entry.repeatRule != ScheduleRepeatRule.none)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: colorScheme.secondaryContainer.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: colorScheme.secondary.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.repeat, size: 13, color: colorScheme.secondary),
                                const SizedBox(width: 4),
                                Text(
                                  '周期: ${entry.repeatRule.label}',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colorScheme.onSecondaryContainer,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                // 小米笔记待办：子步骤 Checklist 清单展示与快捷核销
                if (entry.subTasks.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 48.0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: colorScheme.surface.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '子步骤清单',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.primary,
                                ),
                              ),
                              Text(
                                '${entry.subTasks.where((s) => s.isCompleted).length}/${entry.subTasks.length} 完成',
                                style: TextStyle(fontSize: 11, color: colorScheme.outline, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          ...entry.subTasks.map((sub) {
                            return InkWell(
                              onTap: () => notifier.toggleSubTaskCompletion(entry.id, sub.id),
                              borderRadius: BorderRadius.circular(6),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2.0),
                                child: Row(
                                  children: [
                                    Icon(
                                      sub.isCompleted ? Icons.check_box_outlined : Icons.check_box_outline_blank,
                                      size: 16,
                                      color: sub.isCompleted ? colorScheme.primary : colorScheme.outline,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        sub.title,
                                        style: TextStyle(
                                          fontSize: 12,
                                          decoration: sub.isCompleted ? TextDecoration.lineThrough : null,
                                          color: sub.isCompleted ? colorScheme.outline : colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                ],
                // 艾宾浩斯复习专属：记忆反馈反馈按钮条（牢固 / 模糊 / 遗忘）
                if (isReview && !entry.isCompleted) ...[
                  const Divider(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        '记忆反馈:',
                        style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.outline),
                      ),
                      const SizedBox(width: 8),
                      _buildFeedbackButton(
                        context,
                        label: '牢固',
                        color: Colors.green,
                        onTap: () => notifier.toggleEntryCompletion(
                          entry.id,
                          feedback: ReviewFeedback.remembered,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _buildFeedbackButton(
                        context,
                        label: '模糊',
                        color: Colors.orange,
                        onTap: () => notifier.toggleEntryCompletion(
                          entry.id,
                          feedback: ReviewFeedback.fuzzy,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _buildFeedbackButton(
                        context,
                        label: '遗忘',
                        color: Colors.red,
                        onTap: () => notifier.toggleEntryCompletion(
                          entry.id,
                          feedback: ReviewFeedback.forgotten,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// 徽章类型标签渲染
  Widget _buildKindBadge(BuildContext context, ScheduleEntryKind kind, int stepIndex) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    String label;
    Color bgColor;
    Color textColor;

    switch (kind) {
      case ScheduleEntryKind.initial:
        label = '初学';
        bgColor = colorScheme.tertiaryContainer;
        textColor = colorScheme.onTertiaryContainer;
      case ScheduleEntryKind.review:
        label = '第${stepIndex + 1}次复习';
        bgColor = colorScheme.primaryContainer;
        textColor = colorScheme.onPrimaryContainer;
      case ScheduleEntryKind.remedial:
        label = '遗忘补救';
        bgColor = colorScheme.errorContainer;
        textColor = colorScheme.onErrorContainer;
      case ScheduleEntryKind.task:
        label = '日程待办';
        bgColor = colorScheme.secondaryContainer;
        textColor = colorScheme.onSecondaryContainer;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: textColor,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// 记忆反馈打卡按钮
  Widget _buildFeedbackButton(
    BuildContext context, {
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ),
    );
  }

  /// 视图 2：全部计划管理看板
  Widget _buildPlansView(
    BuildContext context,
    ScheduleState state,
    ScheduleNotifier notifier,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final plans = state.plans;

    if (plans.isEmpty) {
      return Center(
        child: Text(
          '尚未创建任何计划，点击右上角「建计划」开始吧',
          style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: plans.length,
      itemBuilder: (context, index) {
        final plan = plans[index];
        final relatedEntries = state.entries.where((e) => e.planId == plan.id).toList();
        final progress = PlanScheduler.calculatePlanProgress(relatedEntries);

        return Card(
          margin: const EdgeInsets.only(bottom: 12.0),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.0)),
          child: Padding(
            padding: const EdgeInsets.all(18.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        plan.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      '${(progress * 100).toInt()}%',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      color: theme.hintColor,
                      tooltip: '编辑计划',
                      onPressed: () => _showEditPlanDialog(context, plan, notifier),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      color: theme.hintColor,
                      tooltip: '删除计划',
                      onPressed: () => _confirmDeletePlan(context, plan, notifier),
                    ),
                  ],
                ),
                if (plan.notes.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    plan.notes,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: progress,
                  borderRadius: BorderRadius.circular(4),
                  minHeight: 6,
                ),
                const SizedBox(height: 8),
                Text(
                  '起始日期: ${plan.startDate}  •  周期阶段: ${relatedEntries.length} 节',
                  style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.outline),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 视图 3：随手记事便签板（支持多行输入、标签分类、快速搜索、置顶、一键转日程）
  Widget _buildMemosView(
    BuildContext context,
    ScheduleState state,
    ScheduleNotifier notifier,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final memos = state.filteredMemos;
    final isSearching = state.memoSearchQuery.isNotEmpty;
    const availableTags = ['全部', '闪念', '灵感', '待办', '备忘', '随想'];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        children: [
          // 1. 顶部独立全宽搜索栏（配置 scrollPadding 彻底防止软键盘与输入框遮挡）
          SizedBox(
            height: 40,
            child: TextField(
              scrollPadding: const EdgeInsets.only(bottom: 240),
              decoration: InputDecoration(
                hintText: '搜索便签内容或标签...',
                hintStyle: const TextStyle(fontSize: 12),
                prefixIcon: const Icon(Icons.search, size: 17),
                suffixIcon: isSearching
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 15),
                        onPressed: () => notifier.setMemoSearchQuery(''),
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onChanged: (val) => notifier.setMemoSearchQuery(val),
            ),
          ),

          const SizedBox(height: 8),

          // 2. 标签分类横向滚动条（自适应全宽展示，平滑切换）
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: availableTags.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, idx) {
                final tag = availableTags[idx];
                final isSelected = state.selectedMemoTag == tag;
                return _buildMemoFilterTagCapsule(
                  context: context,
                  tag: tag,
                  isSelected: isSelected,
                  onTap: () => notifier.setSelectedMemoTag(tag),
                );
              },
            ),
          ),

          const SizedBox(height: 10),

          // 3. 记事新建卡片（采用花笺纸质感底色与自适应多行输入，彻底解决输入框过小问题）
          if (!isSearching) ...[
            Builder(
              builder: (context) {
                final isDarkTheme = theme.brightness == Brightness.dark;
                final activeSkin = floralSkins[_selectedNewMemoColor.clamp(0, floralSkins.length - 1)];
                final cardBg = isDarkTheme ? activeSkin.darkBg : activeSkin.lightBg;
                final cardBorder = activeSkin.border;

                return Container(
                  padding: const EdgeInsets.all(14.0),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: cardBorder, width: 1.2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDarkTheme ? 0.3 : 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 输入框与全屏信笺按钮
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _quickMemoController,
                              minLines: 3,
                              maxLines: 7,
                              scrollPadding: const EdgeInsets.only(bottom: 240),
                              decoration: InputDecoration(
                                hintText: '花笺随想：随时记下闪念、要点、工作灵感...\n(输入框已全面扩展，支持多行随笔)',
                                hintStyle: TextStyle(
                                  color: isDarkTheme ? Colors.white38 : Colors.black38,
                                  fontSize: 13,
                                ),
                                border: InputBorder.none,
                                isDense: true,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.open_in_full, size: 17, color: activeSkin.accent),
                            tooltip: '全屏沉浸信笺',
                            onPressed: () => _showFloralMemoEditor(context, notifier),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // 花笺 6 色调色板选择条
                      Row(
                        children: [
                          Text(
                            '花笺:',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isDarkTheme ? Colors.white60 : Colors.black54,
                            ),
                          ),
                          const SizedBox(width: 6),
                          ...floralSkins.asMap().entries.map((entrySkin) {
                            final idx = entrySkin.key;
                            final s = entrySkin.value;
                            final isSel = _selectedNewMemoColor == idx;
                            return GestureDetector(
                              onTap: () {
                                setState(() => _selectedNewMemoColor = idx);
                              },
                              child: Container(
                                margin: const EdgeInsets.only(right: 6),
                                width: 18,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: isDarkTheme ? s.darkBg : s.lightBg,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSel ? s.accent : s.border,
                                    width: isSel ? 2.0 : 1.0,
                                  ),
                                ),
                                child: isSel
                                    ? Icon(Icons.check, size: 10, color: s.accent)
                                    : null,
                              ),
                            );
                          }),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // 响应式底部工具栏：移动端/安卓窄屏自适应分层，桌面端宽屏两端对齐
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isCompact = constraints.maxWidth < 520;

                          // 1. 快速便签标签胶囊列表
                          final tagsBlock = Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: ['闪念', '灵感', '待办', '备忘'].map((tag) {
                              final isSel = _selectedNewMemoTag == tag;
                              return _buildQuickMemoTagCapsule(
                                context: context,
                                tag: tag,
                                isSelected: isSel,
                                onTap: () {
                                  setState(() => _selectedNewMemoTag = tag);
                                },
                              );
                            }).toList(),
                          );

                          // 2. 置顶开关按钮组件
                          final pinButton = InkWell(
                            onTap: () {
                              setState(() => _isNewMemoPinned = !_isNewMemoPinned);
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: _isNewMemoPinned
                                    ? Colors.amber.withValues(alpha: 0.15)
                                    : colorScheme.surfaceContainerLow.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _isNewMemoPinned
                                      ? Colors.amber.withValues(alpha: 0.6)
                                      : colorScheme.outlineVariant.withValues(alpha: 0.35),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _isNewMemoPinned ? Icons.push_pin : Icons.push_pin_outlined,
                                    size: 15,
                                    color: _isNewMemoPinned ? Colors.amber[800] : colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _isNewMemoPinned ? '已置顶' : '置顶',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: _isNewMemoPinned ? Colors.amber[800] : colorScheme.onSurfaceVariant,
                                      fontWeight: _isNewMemoPinned ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );

                          // 3. 记一笔核心添加按钮组件
                          final submitButton = FilledButton.icon(
                            onPressed: () {
                              final text = _quickMemoController.text.trim();
                              if (text.isNotEmpty) {
                                notifier.addQuickMemo(
                                  text,
                                  colorIndex: _selectedNewMemoColor,
                                  tag: _selectedNewMemoTag,
                                  isPinned: _isNewMemoPinned,
                                );
                                _quickMemoController.clear();
                                setState(() => _isNewMemoPinned = false);
                              }
                            },
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('记一笔'),
                            style: FilledButton.styleFrom(
                              backgroundColor: activeSkin.accent,
                              foregroundColor: Colors.white,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          );

                          if (isCompact) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                tagsBlock,
                                const SizedBox(height: 10),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    pinButton,
                                    submitButton,
                                  ],
                                ),
                              ],
                            );
                          }

                          return Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              tagsBlock,
                              Row(
                                children: [
                                  pinButton,
                                  const SizedBox(width: 8),
                                  submitButton,
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
          ],

          const SizedBox(height: 12),

          // 3. 便签列表展示
          Expanded(
            child: memos.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.note_alt_outlined,
                          size: 48,
                          color: colorScheme.outline.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          state.memoSearchQuery.isNotEmpty
                              ? '未找到匹配“${state.memoSearchQuery}”的便签'
                              : '便签板暂无内容，随时记下灵感并支持一键转日程',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: memos.length,
                    itemBuilder: (context, index) {
                      final memo = memos[index];
                      return _buildMemoCard(context, memo, notifier);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// 新建便签卡片中的小标签选择胶囊（无闪烁、平滑动画过渡）
  /// [防闪烁关键]：替代 Material 3 ChoiceChip，采用 AnimatedContainer 与透明 Material，
  /// 彻底阻断 Windows 平台下 RawChip 内部动画与鼠标 Hover 冲突造成的白光闪烁。
  Widget _buildQuickMemoTagCapsule({
    required BuildContext context,
    required String tag,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      key: ValueKey('quick_memo_tag_$tag'),
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        focusColor: Colors.transparent,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: colorScheme.primary.withValues(alpha: 0.05),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant.withValues(alpha: 0.4),
              width: 1.0,
            ),
          ),
          child: Text(
            tag,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  /// 便签分类检索标签胶囊（无闪烁、平滑动画过渡）
  /// [防闪烁关键]：横向列表项赋予确定性 ValueKey，平滑过渡选中状态，不产生焦点跳动。
  Widget _buildMemoFilterTagCapsule({
    required BuildContext context,
    required String tag,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      key: ValueKey('memo_filter_tag_$tag'),
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        focusColor: Colors.transparent,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: colorScheme.primary.withValues(alpha: 0.05),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant.withValues(alpha: 0.35),
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Text(
            tag,
            style: theme.textTheme.labelMedium?.copyWith(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  /// 单项便签卡片渲染（融合花笺拟真信笺纸色彩、抬头、置顶标记、标签、时间戳、一键复制、一键转日程与沉浸编辑）
  Widget _buildMemoCard(
    BuildContext context,
    MemoItem memo,
    ScheduleNotifier notifier,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final skin = floralSkins[memo.colorIndex.clamp(0, floralSkins.length - 1)];
    final cardBg = isDark ? skin.darkBg : skin.lightBg;
    final cardBorder = memo.isPinned ? Colors.amber.withValues(alpha: 0.8) : skin.border;
    final textColor = isDark ? Colors.white.withValues(alpha: 0.9) : const Color(0xFF1A1A18);
    final timeStr = DateFormat('M月d日 HH:mm').format(memo.createdAt);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: cardBorder,
          width: memo.isPinned ? 1.8 : 1.2,
        ),
      ),
      color: cardBg,
      elevation: memo.isPinned ? 2 : 0,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 卡片顶栏：花笺名色标 + 分类标签 + 时间戳 + 置顶标记
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: skin.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    skin.name,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: skin.accent,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    memo.tag,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  timeStr,
                  style: TextStyle(
                    fontSize: 11,
                    color: textColor.withValues(alpha: 0.45),
                  ),
                ),
                const Spacer(),
                if (memo.isPinned) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.push_pin, size: 12, color: Colors.amber),
                        SizedBox(width: 2),
                        Text('置顶', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),

            // 信笺抬头标题（若存在）
            if (memo.title.trim().isNotEmpty) ...[
              Text(
                memo.title.trim(),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 6),
            ],

            // 便签正文（轻触直接进入沉浸式花笺编辑器）
            InkWell(
              onTap: () => _showFloralMemoEditor(context, notifier, initialMemo: memo),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2.0),
                child: Text(
                  memo.content,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: textColor.withValues(alpha: 0.9),
                  ),
                ),
              ),
            ),

            Divider(height: 20, color: skin.border.withValues(alpha: 0.6)),

            // 卡片底部快捷操作条（置顶 / 转日程 / 复制 / 编辑 / 删除）
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // 置顶按钮
                IconButton(
                  tooltip: memo.isPinned ? '取消置顶' : '置顶便签',
                  icon: Icon(
                    memo.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                    size: 16,
                    color: memo.isPinned ? Colors.amber[800] : skin.accent,
                  ),
                  onPressed: () => notifier.togglePinMemo(memo.id),
                ),
                // 一键转日程待办
                TextButton.icon(
                  icon: const Icon(Icons.event_available, size: 14),
                  label: const Text('转日程', style: TextStyle(fontSize: 12)),
                  onPressed: () => _showConvertMemoToScheduleDialog(context, memo, notifier),
                ),
                // 复制全文
                IconButton(
                  tooltip: '复制全文',
                  icon: const Icon(Icons.copy, size: 16),
                  onPressed: () {
                    final fullText = memo.title.isNotEmpty ? '【${memo.title}】\n${memo.content}' : memo.content;
                    Clipboard.setData(ClipboardData(text: fullText));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('已复制花笺便签内容到剪贴板'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
                // 编辑修改（直接唤起沉浸式花笺编辑器）
                IconButton(
                  tooltip: '编辑便签',
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  onPressed: () => _showFloralMemoEditor(context, notifier, initialMemo: memo),
                ),
                // 删除
                IconButton(
                  tooltip: '删除便签',
                  icon: const Icon(Icons.delete_outline, size: 16),
                  onPressed: () => notifier.deleteMemo(memo.id),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 弹窗：编辑记事便签内容与属性（直接复用沉浸式花笺编辑器）
  void _showEditMemoDialog(
    BuildContext context,
    MemoItem memo,
    ScheduleNotifier notifier,
  ) {
    _showFloralMemoEditor(context, notifier, initialMemo: memo);
  }

  /// 弹窗：一键将随手记事转换为正式日程待办
  void _showConvertMemoToScheduleDialog(
    BuildContext context,
    MemoItem memo,
    ScheduleNotifier notifier,
  ) {
    final titleController = TextEditingController(
      text: memo.content.length > 20 ? '${memo.content.substring(0, 20)}...' : memo.content,
    );
    DateTime targetTime = DateTime.now().add(const Duration(hours: 1));
    bool enableReminder = true;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.event_available, color: Colors.blue),
              SizedBox(width: 8),
              Text('将便签转为日程'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: '日程待办标题'),
                ),
                const SizedBox(height: 14),
                const Text('设定执行与提醒时间:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_today, size: 14),
                        label: Text(DateFormat('M月d日').format(targetTime)),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: targetTime,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2035),
                          );
                          if (picked != null) {
                            setDialogState(() {
                              targetTime = DateTime(
                                picked.year,
                                picked.month,
                                picked.day,
                                targetTime.hour,
                                targetTime.minute,
                              );
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.access_time, size: 14),
                        label: Text(DateFormat('HH:mm').format(targetTime)),
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.fromDateTime(targetTime),
                          );
                          if (picked != null) {
                            setDialogState(() {
                              targetTime = DateTime(
                                targetTime.year,
                                targetTime.month,
                                targetTime.day,
                                picked.hour,
                                picked.minute,
                              );
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('开启强提醒', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  value: enableReminder,
                  onChanged: (val) => setDialogState(() => enableReminder = val),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                notifier.convertMemoToSchedule(
                  memoId: memo.id,
                  scheduleTime: targetTime,
                  title: titleController.text,
                  hasReminder: enableReminder,
                );
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('已成功将便签转为日程待办，并在日程中心生成！'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              child: const Text('立即转换'),
            ),
          ],
        ),
      ),
    );
  }

  /// 弹窗：新建艾宾浩斯复习计划（支持指定日历起始日期）
  void _showCreatePlanDialog(
    BuildContext context,
    ScheduleState state,
    ScheduleNotifier notifier,
  ) {
    final titleController = TextEditingController();
    final notesController = TextEditingController();

    // 默认起始日期为当前在主日历上选中的日期
    DateTime selectedStartDate = PlanScheduler.parseIsoDate(state.effectiveDateIso);

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('新建艾宾浩斯计划'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: '计划主题 / 知识点',
                    hintText: '如：算法复习、背单词、架构设计',
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(
                    labelText: '补充备注',
                    hintText: '要点摘录或重点提示',
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                // 日历起始日期选择行
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('计划起始日期:'),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text(DateFormat('yyyy-MM-dd').format(selectedStartDate)),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedStartDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2035),
                          helpText: '选择计划起始日期',
                        );
                        if (picked != null) {
                          setDialogState(() {
                            selectedStartDate = picked;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (titleController.text.trim().isNotEmpty) {
                  notifier.createPlan(
                    title: titleController.text,
                    notes: notesController.text,
                    customStartDateIso: PlanScheduler.formatIsoDate(selectedStartDate),
                  );
                  Navigator.of(ctx).pop();
                }
              },
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
  }

  /// 确认删除指定单项日程待办弹窗
  void _confirmDeleteScheduleEntry(
    BuildContext context,
    ScheduleEntry entry,
    ScheduleNotifier notifier,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_outline, color: Colors.red),
            SizedBox(width: 8),
            Text('删除日程待办'),
          ],
        ),
        content: Text('确定要删除日程「${entry.title}」吗？\n若已配置高穿透强提醒，该提醒也将一并取消。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () {
              notifier.deleteScheduleEntry(entry.id);
              Navigator.of(ctx).pop();
            },
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
  }

  /// 确认删除艾宾浩斯复习计划弹窗
  void _confirmDeletePlan(
    BuildContext context,
    PlanItem plan,
    ScheduleNotifier notifier,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_forever_outlined, color: Colors.red),
            SizedBox(width: 8),
            Text('删除复习计划'),
          ],
        ),
        content: Text('确定要删除计划「${plan.title}」吗？\n注意：此操作将级联删除该计划生成的所有复习日程节点！'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () {
              notifier.deletePlan(plan.id);
              Navigator.of(ctx).pop();
            },
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
  }

  /// 弹窗：编辑修改已有的计划项（支持修改名称、备注与调整起始日期并智能平移节点）
  void _showEditPlanDialog(
    BuildContext context,
    PlanItem plan,
    ScheduleNotifier notifier,
  ) {
    final titleController = TextEditingController(text: plan.title);
    final notesController = TextEditingController(text: plan.notes);
    DateTime pickedStartDate = PlanScheduler.parseIsoDate(plan.startDate);

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final theme = Theme.of(context);
          final colorScheme = theme.colorScheme;
          final dateStr = PlanScheduler.formatIsoDate(pickedStartDate);

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Icon(Icons.edit_calendar_rounded, color: colorScheme.primary),
                const SizedBox(width: 8),
                const Text('编辑复习计划'),
              ],
            ),
            content: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: titleController,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      decoration: const InputDecoration(
                        labelText: '计划名称',
                        hintText: '如：高等数学知识点总复习',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: '计划备注',
                        hintText: '补充备考重点或复习要求',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text('起始基准日期:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    Material(
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: pickedStartDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2035),
                            helpText: '调整计划起始日期',
                          );
                          if (picked != null) {
                            setDialogState(() => pickedStartDate = picked);
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Row(
                            children: [
                              Icon(Icons.calendar_month, size: 18, color: colorScheme.primary),
                              const SizedBox(width: 8),
                              Text(
                                dateStr,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              const Spacer(),
                              Text('点击修改', style: TextStyle(fontSize: 12, color: colorScheme.outline)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '提示：调整起始日期将智能平移未完成的复习阶段，已完成打卡历史将妥善保留。',
                      style: TextStyle(fontSize: 11, color: colorScheme.outline),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  final newTitle = titleController.text.trim();
                  if (newTitle.isNotEmpty) {
                    notifier.updatePlan(
                      planId: plan.id,
                      title: newTitle,
                      notes: notesController.text.trim(),
                      newStartDateIso: dateStr,
                    );
                    Navigator.of(ctx).pop();
                  }
                },
                child: const Text('保存修改'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 辅助计算小米笔记待办快捷改期时间
  DateTime _calculateQuickScheduleDate(String type, DateTime current) {
    final now = DateTime.now();
    switch (type) {
      case 'today':
        return DateTime(now.year, now.month, now.day, current.hour, current.minute);
      case 'tomorrow':
        final t = now.add(const Duration(days: 1));
        return DateTime(t.year, t.month, t.day, current.hour, current.minute);
      case 'weekend':
        final daysUntilSaturday = (DateTime.saturday - now.weekday + 7) % 7;
        final target = now.add(Duration(days: daysUntilSaturday == 0 ? 7 : daysUntilSaturday));
        return DateTime(target.year, target.month, target.day, current.hour, current.minute);
      case 'next_monday':
        final daysUntilMonday = (DateTime.monday - now.weekday + 7) % 7;
        final target = now.add(Duration(days: daysUntilMonday == 0 ? 7 : daysUntilMonday));
        return DateTime(target.year, target.month, target.day, current.hour, current.minute);
      default:
        return current;
    }
  }

  /// 弹窗：小米笔记待办风格——新建/编辑日程待办项
  /// 支持快捷改期（今天/明天/本周末/下周一）、全天模式、四级优先级、Checklist 子步骤核销清单
  void _showEditScheduleDialog(
    BuildContext context,
    ScheduleEntry entry,
    ScheduleNotifier notifier, {
    bool isCreating = false,
  }) {
    final titleController = TextEditingController(text: entry.title);
    final notesController = TextEditingController(text: entry.notes);
    final subTaskInputController = TextEditingController();

    final baseDate = PlanScheduler.parseIsoDate(entry.scheduledDate);
    DateTime scheduleTime = entry.reminderTime ?? DateTime(
      baseDate.year,
      baseDate.month,
      baseDate.day,
      9,
      0,
    );

    bool enableReminder = entry.hasReminder;
    int advanceMinutes = entry.reminderMinutesBefore;
    ScheduleRepeatRule selectedRepeatRule = entry.repeatRule;
    SchedulePriority selectedPriority = entry.priority;
    bool isAllDay = entry.isAllDay;
    List<SubTaskItem> subTasks = List<SubTaskItem>.from(entry.subTasks);

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final theme = Theme.of(context);
          final colorScheme = theme.colorScheme;
          final actualTriggerTime = scheduleTime.subtract(Duration(minutes: advanceMinutes));
          final weekdayStr = const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][scheduleTime.weekday - 1];

          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
              child: Padding(
                padding: const EdgeInsets.all(22.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. 顶栏：标题 + 关闭
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.edit_calendar_rounded, color: colorScheme.primary, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isCreating ? '新建日程与待办' : '编辑日程与待办',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 17,
                                ),
                              ),
                              Text(
                                isCreating
                                    ? '参考小米待办：支持快捷改期、全天模式、优先级与子清单'
                                    : '修改待办内容、调整执行时间、优先级或核销子步骤',
                                style: TextStyle(fontSize: 11, color: theme.hintColor),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          tooltip: '关闭',
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // 中间可滚动区域
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // 2. 事项标题与备注
                            TextField(
                              controller: titleController,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                              decoration: InputDecoration(
                                hintText: '日程标题',
                                filled: true,
                                fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                                prefixIcon: const Icon(Icons.check_circle_outline, size: 20),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: notesController,
                              maxLines: 2,
                              style: const TextStyle(fontSize: 13),
                              decoration: InputDecoration(
                                hintText: '补充备注（可选）',
                                filled: true,
                                fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                                prefixIcon: const Icon(Icons.notes_rounded, size: 18),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // 3. 小米待办特色：快捷改期胶囊 + 日期时间规划卡片
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.event_note_rounded, size: 16, color: colorScheme.primary),
                                          const SizedBox(width: 6),
                                          Text(
                                            '执行时间',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: colorScheme.primary,
                                            ),
                                          ),
                                        ],
                                      ),
                                      // 全天开关（小米笔记待办标志性功能）
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text('全天', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                                          Switch(
                                            value: isAllDay,
                                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                            onChanged: (val) {
                                              setDialogState(() => isAllDay = val);
                                            },
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),

                                  // 小米式快捷改期胶囊按钮：今天 / 明天 / 本周末 / 下周一
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      _buildQuickDateChip(
                                        label: '今天',
                                        colorScheme: colorScheme,
                                        onTap: () {
                                          setDialogState(() {
                                            scheduleTime = _calculateQuickScheduleDate('today', scheduleTime);
                                          });
                                        },
                                      ),
                                      _buildQuickDateChip(
                                        label: '明天',
                                        colorScheme: colorScheme,
                                        onTap: () {
                                          setDialogState(() {
                                            scheduleTime = _calculateQuickScheduleDate('tomorrow', scheduleTime);
                                          });
                                        },
                                      ),
                                      _buildQuickDateChip(
                                        label: '本周末',
                                        colorScheme: colorScheme,
                                        onTap: () {
                                          setDialogState(() {
                                            scheduleTime = _calculateQuickScheduleDate('weekend', scheduleTime);
                                          });
                                        },
                                      ),
                                      _buildQuickDateChip(
                                        label: '下周一',
                                        colorScheme: colorScheme,
                                        onTap: () {
                                          setDialogState(() {
                                            scheduleTime = _calculateQuickScheduleDate('next_monday', scheduleTime);
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),

                                  // 日期与时分选择行
                                  Row(
                                    children: [
                                      // 日期按钮
                                      Expanded(
                                        flex: isAllDay ? 10 : 6,
                                        child: Material(
                                          color: colorScheme.surface,
                                          borderRadius: BorderRadius.circular(10),
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(10),
                                            onTap: () async {
                                              final pickedDate = await showDatePicker(
                                                context: context,
                                                initialDate: scheduleTime,
                                                firstDate: DateTime(2020),
                                                lastDate: DateTime(2035),
                                                helpText: '选择日程日期',
                                              );
                                              if (pickedDate != null) {
                                                setDialogState(() {
                                                  scheduleTime = DateTime(
                                                    pickedDate.year,
                                                    pickedDate.month,
                                                    pickedDate.day,
                                                    scheduleTime.hour,
                                                    scheduleTime.minute,
                                                  );
                                                });
                                              }
                                            },
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                              child: Row(
                                                children: [
                                                  const Icon(Icons.calendar_month_outlined, size: 18, color: Colors.blueAccent),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      '${DateFormat('M月d日').format(scheduleTime)} $weekdayStr',
                                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (!isAllDay) ...[
                                        const SizedBox(width: 8),
                                        // 时间按钮
                                        Expanded(
                                          flex: 4,
                                          child: Material(
                                            color: colorScheme.surface,
                                            borderRadius: BorderRadius.circular(10),
                                            child: InkWell(
                                              borderRadius: BorderRadius.circular(10),
                                              onTap: () async {
                                                final pickedTime = await showTimePicker(
                                                  context: context,
                                                  initialTime: TimeOfDay.fromDateTime(scheduleTime),
                                                  helpText: '设定提醒时间',
                                                );
                                                if (pickedTime != null) {
                                                  setDialogState(() {
                                                    scheduleTime = DateTime(
                                                      scheduleTime.year,
                                                      scheduleTime.month,
                                                      scheduleTime.day,
                                                      pickedTime.hour,
                                                      pickedTime.minute,
                                                    );
                                                  });
                                                }
                                              },
                                              child: Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                                child: Row(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    const Icon(Icons.access_time_rounded, size: 18, color: Colors.orangeAccent),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      DateFormat('HH:mm').format(scheduleTime),
                                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),

                            // 4. 小米待办四级优先级选择卡片（无/低/中/高）
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.35)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.flag_rounded, size: 16, color: colorScheme.primary),
                                      const SizedBox(width: 6),
                                      Text(
                                        '优先级设定',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: colorScheme.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      (SchedulePriority.none, '无优先级', Colors.grey),
                                      (SchedulePriority.low, '低优先级', Colors.green),
                                      (SchedulePriority.medium, '中优先级', Colors.orange),
                                      (SchedulePriority.high, '高优先级', Colors.red),
                                    ].map((item) {
                                      final isSel = selectedPriority == item.$1;
                                      return ChoiceChip(
                                        label: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              width: 8,
                                              height: 8,
                                              decoration: BoxDecoration(
                                                color: item.$3,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(item.$2),
                                          ],
                                        ),
                                        selected: isSel,
                                        showCheckmark: false,
                                        onSelected: (selected) {
                                          if (selected) {
                                            setDialogState(() => selectedPriority = item.$1);
                                          }
                                        },
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),

                            // 5. Checklist 子待办清单（小米笔记标志性多级任务核销）
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.35)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.checklist_rounded, size: 16, color: colorScheme.primary),
                                          const SizedBox(width: 6),
                                          Text(
                                            '子步骤清单 (Checklist)',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: colorScheme.primary,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Text(
                                        '${subTasks.where((s) => s.isCompleted).length}/${subTasks.length}',
                                        style: TextStyle(fontSize: 11, color: colorScheme.outline, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),

                                  // 子任务列表渲染
                                  if (subTasks.isNotEmpty) ...[
                                    ...subTasks.asMap().entries.map((entryItem) {
                                      final idx = entryItem.key;
                                      final sub = entryItem.value;
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 3.0),
                                        child: Row(
                                          children: [
                                            InkWell(
                                              onTap: () {
                                                setDialogState(() {
                                                  subTasks[idx] = sub.copyWith(isCompleted: !sub.isCompleted);
                                                });
                                              },
                                              borderRadius: BorderRadius.circular(4),
                                              child: Icon(
                                                sub.isCompleted ? Icons.check_box_outlined : Icons.check_box_outline_blank,
                                                size: 18,
                                                color: sub.isCompleted ? colorScheme.primary : colorScheme.outline,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                sub.title,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  decoration: sub.isCompleted ? TextDecoration.lineThrough : null,
                                                  color: sub.isCompleted ? colorScheme.outline : colorScheme.onSurface,
                                                ),
                                              ),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.close, size: 16),
                                              color: theme.hintColor,
                                              tooltip: '移除子步骤',
                                              onPressed: () {
                                                setDialogState(() {
                                                  subTasks.removeAt(idx);
                                                });
                                              },
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                                    const Divider(height: 16),
                                  ],

                                  // 添加子步骤输入栏
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: subTaskInputController,
                                          style: const TextStyle(fontSize: 12),
                                          decoration: InputDecoration(
                                            hintText: '输入子步骤，如：准备材料、发送确认邮件',
                                            isDense: true,
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                          onSubmitted: (val) {
                                            final t = val.trim();
                                            if (t.isNotEmpty) {
                                              setDialogState(() {
                                                subTasks.add(SubTaskItem(
                                                  id: 'sub_${DateTime.now().microsecondsSinceEpoch}',
                                                  title: t,
                                                ));
                                                subTaskInputController.clear();
                                              });
                                            }
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      FilledButton.tonal(
                                        style: FilledButton.styleFrom(
                                          visualDensity: VisualDensity.compact,
                                          padding: const EdgeInsets.symmetric(horizontal: 10),
                                        ),
                                        onPressed: () {
                                          final t = subTaskInputController.text.trim();
                                          if (t.isNotEmpty) {
                                            setDialogState(() {
                                              subTasks.add(SubTaskItem(
                                                id: 'sub_${DateTime.now().microsecondsSinceEpoch}',
                                                title: t,
                                              ));
                                              subTaskInputController.clear();
                                            });
                                          }
                                        },
                                        child: const Text('添加'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),

                            // 6. 强提醒与重复周期卡片
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: enableReminder
                                    ? colorScheme.primaryContainer.withValues(alpha: 0.16)
                                    : colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: enableReminder
                                      ? colorScheme.primary.withValues(alpha: 0.3)
                                      : colorScheme.outlineVariant.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            enableReminder ? Icons.notifications_active_rounded : Icons.notifications_off_outlined,
                                            size: 18,
                                            color: enableReminder ? colorScheme.primary : theme.disabledColor,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            '定时强提醒',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: enableReminder ? colorScheme.onSurface : theme.disabledColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Switch(
                                        value: enableReminder,
                                        onChanged: (val) {
                                          setDialogState(() => enableReminder = val);
                                        },
                                      ),
                                    ],
                                  ),
                                  if (enableReminder) ...[
                                    const Divider(height: 16),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        (0, '准时'),
                                        (5, '提前5分'),
                                        (15, '提前15分'),
                                        (30, '提前30分'),
                                        (60, '提前1小时'),
                                      ].map((item) {
                                        final isSel = advanceMinutes == item.$1;
                                        return ChoiceChip(
                                          label: Text(item.$2),
                                          selected: isSel,
                                          showCheckmark: false,
                                          onSelected: (selected) {
                                            if (selected) {
                                              setDialogState(() => advanceMinutes = item.$1);
                                            }
                                          },
                                        );
                                      }).toList(),
                                    ),
                                    const SizedBox(height: 10),
                                    const Text('重复周期:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: ScheduleRepeatRule.values.map((rule) {
                                        final isSel = selectedRepeatRule == rule;
                                        return ChoiceChip(
                                          label: Text(rule.label),
                                          selected: isSel,
                                          showCheckmark: false,
                                          onSelected: (selected) {
                                            if (selected) {
                                              setDialogState(() => selectedRepeatRule = rule);
                                            }
                                          },
                                        );
                                      }).toList(),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // 底部确定保存栏
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('取消'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          icon: const Icon(Icons.check, size: 16),
                          label: Text(isCreating ? '保存日程' : '保存修改'),
                          onPressed: () {
                            final newTitle = titleController.text.trim();
                            if (newTitle.isNotEmpty) {
                              final isoDate = PlanScheduler.formatIsoDate(scheduleTime);
                              if (isCreating) {
                                notifier.createSingleSchedule(
                                  title: newTitle,
                                  time: scheduleTime,
                                  notes: notesController.text.trim(),
                                  hasReminder: enableReminder,
                                  reminderMinutesBefore: advanceMinutes,
                                  repeatRule: selectedRepeatRule,
                                  priority: selectedPriority,
                                  isAllDay: isAllDay,
                                  subTasks: subTasks,
                                );
                              } else {
                                notifier.updateScheduleEntry(
                                  id: entry.id,
                                  title: newTitle,
                                  scheduledDate: isoDate,
                                  notes: notesController.text.trim(),
                                  reminderTime: scheduleTime,
                                  hasReminder: enableReminder,
                                  reminderMinutesBefore: advanceMinutes,
                                  repeatRule: selectedRepeatRule,
                                  priority: selectedPriority,
                                  isAllDay: isAllDay,
                                  subTasks: subTasks,
                                );
                              }
                              Navigator.of(ctx).pop();
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 小米笔记快捷改期微按钮
  Widget _buildQuickDateChip({
    required String label,
    required ColorScheme colorScheme,
    required VoidCallback onTap,
  }) {
    return Material(
      color: colorScheme.primaryContainer.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
        ),
      ),
    );
  }

  /// 弹窗：花笺（Floral Notepaper）沉浸式信笺编辑器
  /// 融合东方信笺拟真 6 色低饱和底色、实时字数统计、信笺抬头与大篇幅 Markdown 创作
  void _showFloralMemoEditor(
    BuildContext context,
    ScheduleNotifier notifier, {
    MemoItem? initialMemo,
  }) {
    final isEditing = initialMemo != null;
    final titleController = TextEditingController(text: initialMemo?.title ?? '');
    final contentController = TextEditingController(text: initialMemo?.content ?? '');
    String currentTag = initialMemo?.tag ?? _selectedNewMemoTag;
    bool isPinned = initialMemo?.isPinned ?? _isNewMemoPinned;
    int currentColorIndex = initialMemo?.colorIndex ?? _selectedNewMemoColor;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final skin = floralSkins[currentColorIndex.clamp(0, floralSkins.length - 1)];
          final paperColor = isDark ? skin.darkBg : skin.lightBg;
          final borderColor = skin.border;
          final textColor = isDark ? Colors.white.withValues(alpha: 0.9) : const Color(0xFF1A1A18);
          final textStats = '${contentController.text.length} 字  •  ${contentController.text.split('\n').length} 行';

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620, maxHeight: 760),
              child: Container(
                decoration: BoxDecoration(
                  color: paperColor,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: borderColor, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1. 信笺顶栏：拟真信笺装饰夹 + 置顶图钉 + 关闭按钮
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: skin.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '花笺 · ${skin.name}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: skin.accent,
                              ),
                            ),
                          ),
                          const Spacer(),
                          // 置顶图钉
                          IconButton(
                            icon: Icon(
                              isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                              color: isPinned ? Colors.amber[800] : skin.accent,
                              size: 20,
                            ),
                            tooltip: isPinned ? '取消置顶' : '置顶便签',
                            onPressed: () {
                              setDialogState(() => isPinned = !isPinned);
                            },
                          ),
                          // 关闭按钮
                          IconButton(
                            icon: Icon(Icons.close, color: textColor.withValues(alpha: 0.6), size: 20),
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // 2. 信笺抬头标题输入框
                      TextField(
                        controller: titleController,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                        decoration: InputDecoration(
                          hintText: '信笺抬头（可选标题）',
                          hintStyle: TextStyle(color: textColor.withValues(alpha: 0.4), fontSize: 16),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      Divider(color: borderColor, height: 18),

                      // 3. 信笺大正文输入区（彻底解决便签输入框太小的问题）
                      Expanded(
                        child: TextField(
                          controller: contentController,
                          maxLines: null,
                          expands: true,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.6,
                            color: textColor,
                          ),
                          decoration: InputDecoration(
                            hintText: '在此挥洒灵感、记叙闪念、记录重要事项...\n支持大段 Markdown 与多行随笔排版。',
                            hintStyle: TextStyle(color: textColor.withValues(alpha: 0.35)),
                            border: InputBorder.none,
                          ),
                          onChanged: (_) => setDialogState(() {}),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // 4. 花笺 6 色调色板选择行
                      Row(
                        children: [
                          Text(
                            '纸笺色调:',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: textColor.withValues(alpha: 0.7),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ...floralSkins.asMap().entries.map((entrySkin) {
                            final idx = entrySkin.key;
                            final s = entrySkin.value;
                            final isSel = currentColorIndex == idx;
                            return GestureDetector(
                              onTap: () {
                                setDialogState(() => currentColorIndex = idx);
                              },
                              child: Container(
                                margin: const EdgeInsets.only(right: 8),
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: isDark ? s.darkBg : s.lightBg,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSel ? s.accent : s.border,
                                    width: isSel ? 2.5 : 1.0,
                                  ),
                                ),
                                child: isSel
                                    ? Icon(Icons.check, size: 14, color: s.accent)
                                    : null,
                              ),
                            );
                          }),
                          const Spacer(),
                          // 动态字数统计
                          Text(
                            textStats,
                            style: TextStyle(
                              fontSize: 11,
                              color: textColor.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // 5. 分类标签胶囊选择
                      Row(
                        children: [
                          Text(
                            '标签:',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: textColor.withValues(alpha: 0.7),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: ['闪念', '灵感', '待办', '备忘', '随想'].map((tag) {
                                  final isSel = currentTag == tag;
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 6.0),
                                    child: ChoiceChip(
                                      label: Text(tag),
                                      selected: isSel,
                                      showCheckmark: false,
                                      selectedColor: skin.accent.withValues(alpha: 0.2),
                                      labelStyle: TextStyle(
                                        fontSize: 11,
                                        fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                        color: isSel ? skin.accent : textColor.withValues(alpha: 0.7),
                                      ),
                                      onSelected: (selected) {
                                        if (selected) {
                                          setDialogState(() => currentTag = tag);
                                        }
                                      },
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // 6. 底部保存与操作栏
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: Text('取消', style: TextStyle(color: textColor.withValues(alpha: 0.7))),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: skin.accent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.check, size: 16),
                            label: Text(isEditing ? '保存修改' : '落笺珍藏'),
                            onPressed: () {
                              final text = contentController.text.trim();
                              final tTitle = titleController.text.trim();
                              if (text.isNotEmpty || tTitle.isNotEmpty) {
                                if (isEditing) {
                                  notifier.updateMemo(
                                    id: initialMemo.id,
                                    title: tTitle,
                                    colorIndex: currentColorIndex,
                                    content: text,
                                    tag: currentTag,
                                    isPinned: isPinned,
                                  );
                                } else {
                                  notifier.addQuickMemo(
                                    text,
                                    title: tTitle,
                                    colorIndex: currentColorIndex,
                                    tag: currentTag,
                                    isPinned: isPinned,
                                  );
                                }
                                Navigator.of(ctx).pop();
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 弹窗：新建单项日程提醒（全面集成小米笔记待办架构：快捷改期、全天模式、四级优先级与 Checklist 子步骤）
  void _showCreateScheduleDialog(
    BuildContext context,
    ScheduleState state,
    ScheduleNotifier notifier,
  ) {
    final baseDate = PlanScheduler.parseIsoDate(state.effectiveDateIso);
    final now = DateTime.now();
    final scheduleTime = DateTime(
      baseDate.year,
      baseDate.month,
      baseDate.day,
      now.hour,
      now.minute,
    ).add(const Duration(hours: 1));

    final tempEntry = ScheduleEntry(
      id: 'entry_${DateTime.now().millisecondsSinceEpoch}',
      planId: 'single_task',
      title: '',
      scheduledDate: state.effectiveDateIso,
      stepIndex: 0,
      kind: ScheduleEntryKind.task,
      reminderTime: scheduleTime,
      hasReminder: true,
      priority: SchedulePriority.none,
      isAllDay: false,
      subTasks: const [],
    );

    _showEditScheduleDialog(context, tempEntry, notifier, isCreating: true);
  }

  /// 快捷时间微按钮
  Widget _buildTimeShortcutPill({
    required String label,
    required ColorScheme colorScheme,
    required VoidCallback onTap,
  }) {
    return Material(
      color: colorScheme.surface,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}
