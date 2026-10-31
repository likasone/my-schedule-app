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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final state = ref.watch(scheduleProvider);
    final notifier = ref.read(scheduleProvider.notifier);

    // 格式化当前日期为中文展示格式
    final now = DateTime.now();
    final dateStr = DateFormat('yyyy年M月d日 EEEE', 'zh_CN').format(now);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            // 顶部核心信息与操作看板
            _buildHeaderCard(context, state, notifier, dateStr),

            // 分类导航标签（今日待办 / 全部计划 / 灵感便签）
            _buildSegmentedTabs(context, state, notifier),

            // 主内容视图区
            Expanded(
              child: state.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : IndexedStack(
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
    final todayList = state.todayEntries;
    final completedCount = todayList.where((e) => e.isCompleted).length;
    final rate = state.todayCompletionRate;

    return Padding(
      padding: const EdgeInsets.all(16.0),
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
                    Text(
                      '日程与计划中心',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
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
                      onPressed: () => _showCreateScheduleDialog(context, notifier),
                      icon: const FaIcon(FontAwesomeIcons.calendarPlus, size: 14),
                      label: const Text('加日程'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () => _showCreatePlanDialog(context, notifier),
                      icon: const FaIcon(FontAwesomeIcons.brain, size: 14),
                      label: const Text('建计划'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 今日完成度进度条
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

  /// 分段导航切换组件
  Widget _buildSegmentedTabs(
    BuildContext context,
    ScheduleState state,
    ScheduleNotifier notifier,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        children: [
          _buildTabItem(
            context,
            index: 0,
            title: '今日待办 (${state.todayEntries.length})',
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
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? colorScheme.primaryContainer
                : colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? colorScheme.primary : Colors.transparent,
              width: 1.5,
            ),
          ),
          alignment: Alignment.center,
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

  /// 视图 1：今日待办与艾宾浩斯复习清单
  Widget _buildTodayView(
    BuildContext context,
    ScheduleState state,
    ScheduleNotifier notifier,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final todayItems = state.todayEntries;

    if (todayItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FaIcon(
              FontAwesomeIcons.circleCheck,
              size: 48,
              color: colorScheme.primary.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 16),
            Text(
              '今日任务与复习已全部完成！',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '享受充实的一天，或点击上方新建计划与日程。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: todayItems.length,
      itemBuilder: (context, index) {
        final item = todayItems[index];
        final isRemedial = item.kind == ScheduleEntryKind.remedial;
        final isReview = item.kind == ScheduleEntryKind.review;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 0,
          color: item.isCompleted
              ? colorScheme.surfaceContainerLow.withValues(alpha: 0.4)
              : colorScheme.surfaceContainerHigh.withValues(alpha: 0.7),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isRemedial
                  ? colorScheme.error.withValues(alpha: 0.5)
                  : colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 完成打卡复选框
                    Checkbox(
                      value: item.isCompleted,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      onChanged: (_) => notifier.toggleEntryCompletion(item.id),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              // 阶段或分类标签
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isRemedial
                                      ? colorScheme.errorContainer
                                      : colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  isRemedial
                                      ? '强化补救'
                                      : (isReview ? '第 ${item.stepIndex + 1} 阶段复习' : '初次学习'),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: isRemedial
                                        ? colorScheme.onErrorContainer
                                        : colorScheme.onPrimaryContainer,
                                  ),
                                ),
                              ),
                              if (item.originalDueDate != null) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: colorScheme.tertiaryContainer,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '逾期前移',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: colorScheme.onTertiaryContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            item.title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              decoration: item.isCompleted ? TextDecoration.lineThrough : null,
                              color: item.isCompleted
                                  ? colorScheme.onSurface.withValues(alpha: 0.5)
                                  : colorScheme.onSurface,
                            ),
                          ),
                          if (item.notes.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              item.notes,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                // 艾宾浩斯复习记忆反馈选项
                if (!item.isCompleted && (isReview || isRemedial)) ...[
                  const Divider(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text('记忆反馈: ', style: theme.textTheme.labelSmall),
                      TextButton.icon(
                        onPressed: () => notifier.toggleEntryCompletion(
                          item.id,
                          feedback: ReviewFeedback.remembered,
                        ),
                        icon: const Icon(Icons.sentiment_very_satisfied, size: 16),
                        label: const Text('牢固'),
                      ),
                      TextButton.icon(
                        onPressed: () => notifier.toggleEntryCompletion(
                          item.id,
                          feedback: ReviewFeedback.fuzzy,
                        ),
                        icon: const Icon(Icons.sentiment_neutral, size: 16),
                        label: const Text('模糊'),
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: colorScheme.error),
                        onPressed: () {
                          notifier.toggleEntryCompletion(
                            item.id,
                            feedback: ReviewFeedback.forgotten,
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已自动为您在明天安排强化补救复习！')),
                          );
                        },
                        icon: const Icon(Icons.sentiment_very_dissatisfied, size: 16),
                        label: const Text('遗忘'),
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
          '暂无活跃计划，点击上方【建计划】添加艾宾浩斯复习计划',
          style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: plans.length,
      itemBuilder: (context, index) {
        final plan = plans[index];
        final planEntries = state.entries.where((e) => e.planId == plan.id).toList();
        final progress = PlanScheduler.calculatePlanProgress(planEntries);
        final completedSteps = planEntries.where((e) => e.isCompleted).length;

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.6),
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(20.0),
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
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '进度 $completedSteps/${planEntries.length}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSecondaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '起始日期: ${plan.startDate} · 周期: ${plan.reviewOffsets.join(', ')} 天',
                  style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
                if (plan.notes.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    plan.notes,
                    style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface),
                  ),
                ],
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: colorScheme.surfaceContainerLowest,
                    valueColor: AlwaysStoppedAnimation<Color>(colorScheme.secondary),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 视图 3：随手灵感便签
  Widget _buildMemosView(
    BuildContext context,
    ScheduleState state,
    ScheduleNotifier notifier,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          // 快速记事输入条
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _quickMemoController,
                  decoration: InputDecoration(
                    hintText: '记录灵感、待办或临时备忘...',
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onSubmitted: (val) {
                    notifier.addQuickMemo(val);
                    _quickMemoController.clear();
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                icon: const Icon(Icons.add),
                onPressed: () {
                  notifier.addQuickMemo(_quickMemoController.text);
                  _quickMemoController.clear();
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 便签卡片瀑布列表
          Expanded(
            child: state.memos.isEmpty
                ? Center(
                    child: Text(
                      '便签箱为空，随手记下第一条灵感吧',
                      style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  )
                : ListView.builder(
                    itemCount: state.memos.length,
                    itemBuilder: (context, index) {
                      final memo = state.memos[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        color: colorScheme.surfaceContainerLow.withValues(alpha: 0.6),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.2)),
                        ),
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

  /// 弹窗：新建艾宾浩斯复习计划
  void _showCreatePlanDialog(BuildContext context, ScheduleNotifier notifier) {
    final titleController = TextEditingController();
    final notesController = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建艾宾浩斯计划'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
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
          ],
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
                );
                Navigator.of(ctx).pop();
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  /// 弹窗：新建单项日程提醒
  void _showCreateScheduleDialog(BuildContext context, ScheduleNotifier notifier) {
    final titleController = TextEditingController();
    final notesController = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建日程提醒'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: '日程待办名称',
                hintText: '如：项目评审、电话会议',
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
          ],
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
                  time: DateTime.now(),
                  notes: notesController.text,
                );
                Navigator.of(ctx).pop();
              }
            },
            child: const Text('保存并设定提醒'),
          ),
        ],
      ),
    );
  }
}
