import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:node_diary/core/services/plan_scheduler.dart';
import 'package:node_diary/ui/schedule/providers/schedule_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ScheduleNotifier 日程与计划状态管理测试', () {
    test('初始状态能够自动创建开箱即用的示例计划与便签且 isLoading 为 false', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // 等待异步 _loadFromStorage 完成
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final state = container.read(scheduleProvider);
      expect(state.plans, isNotEmpty);
      expect(state.entries, isNotEmpty);
      expect(state.memos, isNotEmpty);
      // 验证绝不阻塞转圈
      expect(state.isLoading, isFalse);
    });

    test('createPlan 能够生成多阶段艾宾浩斯复习条目并解除 loading', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      final notifier = container.read(scheduleProvider.notifier);
      await notifier.createPlan(
        title: 'Python 异步与高并发',
        notes: '深入 asyncio 事件循环',
      );

      final state = container.read(scheduleProvider);
      final newPlan =
          state.plans.firstWhere((p) => p.title == 'Python 异步与高并发');
      expect(newPlan, isNotNull);

      final relatedEntries =
          state.entries.where((e) => e.planId == newPlan.id).toList();
      // 验证依据 1, 2, 4, 7, 15, 30 经典曲线生成了 6 个阶段节点
      expect(relatedEntries.length, equals(6));
      expect(state.isLoading, isFalse);
    });

    test('打卡标记遗忘时自动为次日生成强化补救复习', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      final notifier = container.read(scheduleProvider.notifier);
      await notifier.createPlan(title: '算法刷题');

      final state = container.read(scheduleProvider);
      final entry = state.entries.firstWhere((e) => e.stepIndex == 1);

      await notifier.toggleEntryCompletion(
        entry.id,
        feedback: ReviewFeedback.forgotten,
      );

      final updatedState = container.read(scheduleProvider);
      final remedial = updatedState.entries.any(
        (e) =>
            e.kind == ScheduleEntryKind.remedial && e.planId == entry.planId,
      );

      expect(remedial, isTrue);
      expect(updatedState.isLoading, isFalse);
    });

    test('日历选择特定日期并在该日期创建日程，列表即时精确呈现', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      final notifier = container.read(scheduleProvider.notifier);
      const futureDate = '2026-11-15';

      // 切换日历选中目标日期
      notifier.selectDate(futureDate);
      var state = container.read(scheduleProvider);
      expect(state.effectiveDateIso, equals(futureDate));

      // 在该日期添加日程
      await notifier.createSingleSchedule(
        title: '重要技术答辩',
        time: DateTime(2026, 11, 15, 14, 30),
        notes: '展示跨平台日程与高穿透提醒成果',
      );

      state = container.read(scheduleProvider);
      // 验证该日期的待办列表中包含了新增任务，且绝不转圈
      final targetEntry = state.selectedDateEntries.firstWhere(
        (e) => e.title == '重要技术答辩',
      );
      expect(targetEntry.scheduledDate, equals(futureDate));
      expect(targetEntry.hasReminder, isTrue);
      expect(targetEntry.reminderTime, equals(DateTime(2026, 11, 15, 14, 30)));
      expect(state.isLoading, isFalse);

      // 验证切换提醒开关
      await notifier.toggleEntryReminder(targetEntry.id);
      state = container.read(scheduleProvider);
      final updatedEntry = state.entries.firstWhere((e) => e.id == targetEntry.id);
      expect(updatedEntry.hasReminder, isFalse);
    });

    test('便签记事的添加、编辑、置顶与一键转日程', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      final notifier = container.read(scheduleProvider.notifier);
      await notifier.addQuickMemo(
        '临时代办：给服务器更新证书',
        tag: '待办',
        isPinned: false,
      );

      var state = container.read(scheduleProvider);
      final memo = state.memos.firstWhere((m) => m.content == '临时代办：给服务器更新证书');
      expect(memo.tag, equals('待办'));
      expect(memo.isPinned, isFalse);

      // 验证置顶功能
      await notifier.togglePinMemo(memo.id);
      state = container.read(scheduleProvider);
      final pinnedMemo = state.memos.firstWhere((m) => m.id == memo.id);
      expect(pinnedMemo.isPinned, isTrue);
      // 验证在 filteredMemos 中置顶排在最前
      expect(state.filteredMemos.first.id, equals(memo.id));

      // 验证编辑功能
      await notifier.updateMemo(
        id: memo.id,
        content: '临时代办：给核心集群更新 SSL 证书',
        tag: '备忘',
      );
      state = container.read(scheduleProvider);
      final updatedMemo = state.memos.firstWhere((m) => m.id == memo.id);
      expect(updatedMemo.content, equals('临时代办：给核心集群更新 SSL 证书'));
      expect(updatedMemo.tag, equals('备忘'));

      // 验证一键转日程待办
      final scheduleTargetTime = DateTime(2026, 11, 20, 16, 0);
      await notifier.convertMemoToSchedule(
        memoId: memo.id,
        scheduleTime: scheduleTargetTime,
      );
      state = container.read(scheduleProvider);
      final createdTask = state.entries.firstWhere(
        (e) => e.notes == updatedMemo.content,
      );
      expect(createdTask.scheduledDate, equals('2026-11-20'));
      expect(createdTask.hasReminder, isTrue);

      // 验证删除便签
      await notifier.deleteMemo(memo.id);
      state = container.read(scheduleProvider);
      expect(state.memos.any((m) => m.id == memo.id), isFalse);
    });

    test('周期性重复任务创建与打卡后自动生成下一周期待办', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      final notifier = container.read(scheduleProvider.notifier);
      final today = DateTime.now();

      // 验证算法计算下一个周期日期
      expect(
        PlanScheduler.calculateNextRepeatDate('2026-11-01', ScheduleRepeatRule.daily),
        equals('2026-11-02'),
      );
      // 周五 (2026-11-06) 下一个工作日为周一 (2026-11-09)
      expect(
        PlanScheduler.calculateNextRepeatDate('2026-11-06', ScheduleRepeatRule.workdays),
        equals('2026-11-09'),
      );
      // 每周循环 (7天后)
      expect(
        PlanScheduler.calculateNextRepeatDate('2026-11-01', ScheduleRepeatRule.weekly),
        equals('2026-11-08'),
      );

      // 创建一个每日重复的任务
      await notifier.createSingleSchedule(
        title: '每日早起晨读打卡',
        time: DateTime(today.year, today.month, today.day, 7, 30),
        repeatRule: ScheduleRepeatRule.daily,
      );

      var state = container.read(scheduleProvider);
      final createdEntry = state.entries.firstWhere((e) => e.title == '每日早起晨读打卡');
      expect(createdEntry.repeatRule, equals(ScheduleRepeatRule.daily));

      // 打卡完成当天的任务
      await notifier.toggleEntryCompletion(createdEntry.id);
      state = container.read(scheduleProvider);

      // 验证当天的任务标记为已完成
      final completedEntry = state.entries.firstWhere((e) => e.id == createdEntry.id);
      expect(completedEntry.isCompleted, isTrue);

      // 验证自动生成了次日的同名重复待办实例
      final tomorrowIso = PlanScheduler.addDays(PlanScheduler.formatIsoDate(today), 1);
      final nextInstance = state.entries.firstWhere(
        (e) => e.title == '每日早起晨读打卡' && e.scheduledDate == tomorrowIso,
      );
      expect(nextInstance, isNotNull);
      expect(nextInstance.isCompleted, isFalse);
      expect(nextInstance.repeatRule, equals(ScheduleRepeatRule.daily));
    });
  });
}
