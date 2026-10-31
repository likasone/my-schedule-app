import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';

import '../../../core/services/plan_scheduler.dart';
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

            // 水平交互式日历条（支持切换日期与完整月历选择）
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '日程与计划中心',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
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
                ),
                // 新建快捷按钮组
                Row(
                  children: [
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

  /// 分段导航切换组件
  Widget _buildSegmentedTabs(
    BuildContext context,
    ScheduleState state,
    ScheduleNotifier notifier,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          _buildTabItem(
            context,
            index: 0,
            title: '日程/复习待办 (${state.selectedDateEntries.length})',
            isSelected: state.selectedTab == 0,
            onTap: () => notifier.setTab(0),
          ),
          const SizedBox(width: 8),
          _buildTabItem(
            context,
            index: 1,
            title: '全部计划 (${state.plans.length})',
            isSelected: state.selectedTab == 1,
            onTap: () => notifier.setTab(1),
          ),
          const SizedBox(width: 8),
          _buildTabItem(
            context,
            index: 2,
            title: '随手记事 (${state.memos.length})',
            isSelected: state.selectedTab == 2,
            onTap: () => notifier.setTab(2),
          ),
        ],
      ),
    );
  }

  /// 单个 Tab 胶囊组件
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
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16.0),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10.0),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected
                ? colorScheme.primaryContainer
                : colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16.0),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary.withValues(alpha: 0.4)
                  : colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          child: Text(
            title,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
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
                    // 任务标题
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
                    Text(
                      plan.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${(progress * 100).toInt()}%',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
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

  /// 视图 3：随手记事便签板
  Widget _buildMemosView(
    BuildContext context,
    ScheduleState state,
    ScheduleNotifier notifier,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final memos = state.memos;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _quickMemoController,
                  decoration: InputDecoration(
                    hintText: '随手记录闪念灵感、临时待办...',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onSubmitted: (text) {
                    notifier.addQuickMemo(text);
                    _quickMemoController.clear();
                  },
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: () {
                  notifier.addQuickMemo(_quickMemoController.text);
                  _quickMemoController.clear();
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: memos.isEmpty
                ? Center(
                    child: Text(
                      '便签板暂无内容，随时记下一笔吧',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: memos.length,
                    itemBuilder: (context, index) {
                      final memo = memos[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(memo, style: theme.textTheme.bodyMedium),
                          trailing: IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => notifier.deleteQuickMemo(index),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
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

  /// 弹窗：新建单项日程提醒（支持精确日历选择与时间设定）
  void _showCreateScheduleDialog(
    BuildContext context,
    ScheduleState state,
    ScheduleNotifier notifier,
  ) {
    final titleController = TextEditingController();
    final notesController = TextEditingController();

    // 默认使用当前选定日期并配合当前时分
    final baseDate = PlanScheduler.parseIsoDate(state.effectiveDateIso);
    final now = DateTime.now();
    DateTime scheduleTime = DateTime(
      baseDate.year,
      baseDate.month,
      baseDate.day,
      now.hour,
      now.minute,
    ).add(const Duration(hours: 1)); // 默认设为 1 小时后

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('新建日程提醒'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: '日程待办内容',
                    hintText: '如：项目评审、电话沟通、重要待办',
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(
                    labelText: '备注',
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                const Text(
                  '选择提醒日期与时间:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                // 日期与时间选择器操作区
                Row(
                  children: [
                    // 选择日期按钮（弹出日历大盘）
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_month, size: 16),
                        label: Text(DateFormat('M月d日').format(scheduleTime)),
                        onPressed: () async {
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
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 选择时间按钮（弹出时钟大盘）
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.access_time, size: 16),
                        label: Text(DateFormat('HH:mm').format(scheduleTime)),
                        onPressed: () async {
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
                      ),
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
                  notifier.createSingleSchedule(
                    title: titleController.text,
                    time: scheduleTime,
                    notes: notesController.text,
                  );
                  Navigator.of(ctx).pop();
                }
              },
              child: const Text('保存并设定提醒'),
            ),
          ],
        ),
      ),
    );
  }
}
