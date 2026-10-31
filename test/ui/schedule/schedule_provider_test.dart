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
    test('初始状态能够自动创建开箱即用的示例计划与便签', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // 等待异步 _loadFromStorage 完成
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final state = container.read(scheduleProvider);
      expect(state.plans, isNotEmpty);
      expect(state.entries, isNotEmpty);
      expect(state.memos, isNotEmpty);
    });

    test('createPlan 能够生成多阶段艾宾浩斯复习条目', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      final notifier = container.read(scheduleProvider.notifier);
      await notifier.createPlan(
        title: 'Python 异步与高并发',
        notes: '深入 asyncio 事件循环',
      );

      final state = container.read(scheduleProvider);
      final newPlan = state.plans.firstWhere((p) => p.title == 'Python 异步与高并发');
      expect(newPlan, isNotNull);

      final relatedEntries = state.entries.where((e) => e.planId == newPlan.id).toList();
      // 验证依据 1, 2, 4, 7, 15, 30 经典曲线生成了 6 个阶段节点
      expect(relatedEntries.length, equals(6));
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
        (e) => e.kind == ScheduleEntryKind.remedial && e.planId == entry.planId,
      );

      expect(remedial, isTrue);
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
