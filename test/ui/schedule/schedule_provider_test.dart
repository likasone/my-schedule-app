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
      expect(state.isLoading, isFalse);
    });

    test('便签记事的添加与删除', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      final notifier = container.read(scheduleProvider.notifier);
      await notifier.addQuickMemo('临时代办：给服务器更新证书');

      var state = container.read(scheduleProvider);
      expect(state.memos.first, equals('临时代办：给服务器更新证书'));

      await notifier.deleteQuickMemo(0);
      state = container.read(scheduleProvider);
      expect(state.memos.contains('临时代办：给服务器更新证书'), isFalse);
    });
  });
}
