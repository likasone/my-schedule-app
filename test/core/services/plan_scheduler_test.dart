import 'package:flutter_test/flutter_test.dart';
import 'package:node_diary/core/services/plan_scheduler.dart';

void main() {
  group('PlanScheduler 艾宾浩斯复习调度与周期算法测试', () {
    test('calculateDayOffsets 正确将自然天数转换为相对基准日的偏移量', () {
      // 验证经典 1, 2, 4, 7, 15, 30 天的相对位移
      final offsets = PlanScheduler.calculateDayOffsets([1, 2, 4, 7, 15, 30]);
      expect(offsets, equals([0, 1, 3, 6, 14, 29]));
    });

    test('generateInitialSchedule 能够为学习计划生成连续的艾宾浩斯复习阶段节点', () {
      final plan = PlanItem(
        id: 'plan_test_01',
        title: 'Flutter 核心架构',
        startDate: '2026-10-01',
        dayCount: 90,
        createdAt: DateTime(2026, 10, 1),
      );

      final entries = PlanScheduler.generateInitialSchedule(plan: plan);

      // 验证生成 6 个阶梯阶段
      expect(entries.length, equals(6));

      // 阶段 1：首日初学
      expect(entries[0].stepIndex, equals(0));
      expect(entries[0].scheduledDate, equals('2026-10-01'));
      expect(entries[0].kind, equals(ScheduleEntryKind.initial));

      // 阶段 2：第 2 天复习（偏移 1 天）
      expect(entries[1].stepIndex, equals(1));
      expect(entries[1].scheduledDate, equals('2026-10-02'));
      expect(entries[1].kind, equals(ScheduleEntryKind.review));

      // 阶段 3：第 4 天复习（偏移 3 天）
      expect(entries[2].stepIndex, equals(2));
      expect(entries[2].scheduledDate, equals('2026-10-04'));

      // 阶段 6：第 30 天复习（偏移 29 天）
      expect(entries[5].stepIndex, equals(5));
      expect(entries[5].scheduledDate, equals('2026-10-30'));
    });

    test('handleFeedbackAndAdaptiveReschedule 当标记遗忘时自动生成次日高优先级补救复习条目', () {
      final entry = ScheduleEntry(
        id: 'entry_01',
        planId: 'plan_01',
        title: 'Dart 异步多线程机制',
        scheduledDate: '2026-10-15',
        stepIndex: 2,
        kind: ScheduleEntryKind.review,
      );

      final remedial = PlanScheduler.handleFeedbackAndAdaptiveReschedule(
        currentEntry: entry,
        feedback: ReviewFeedback.forgotten,
        todayIso: '2026-10-15',
      );

      expect(remedial, isNotNull);
      expect(remedial!.kind, equals(ScheduleEntryKind.remedial));
      expect(remedial.scheduledDate, equals('2026-10-16')); // 次日立即复习
      expect(remedial.title, contains('强化补救'));
    });

    test('resolveDailyViewEntries 能够平滑将过去逾期未完成条目顺延至今日展示', () {
      final pastEntry = ScheduleEntry(
        id: 'entry_past',
        planId: 'plan_01',
        title: '昨天未完成的记忆卡片',
        scheduledDate: '2026-10-20',
        stepIndex: 1,
        kind: ScheduleEntryKind.review,
        isCompleted: false,
      );

      final completedPastEntry = ScheduleEntry(
        id: 'entry_done',
        planId: 'plan_01',
        title: '昨天已完成的历史条目',
        scheduledDate: '2026-10-20',
        stepIndex: 0,
        kind: ScheduleEntryKind.initial,
        isCompleted: true,
      );

      final todayEntries = PlanScheduler.resolveDailyViewEntries(
        allEntries: [pastEntry, completedPastEntry],
        todayIso: '2026-10-25',
      );

      // 仅过去未完成的逾期项自动浮现到今天
      expect(todayEntries.length, equals(1));
      expect(todayEntries.first.id, equals('entry_past'));
      expect(todayEntries.first.scheduledDate, equals('2026-10-25'));
      expect(todayEntries.first.originalDueDate, equals('2026-10-20'));
    });

    test('calculatePlanProgress 正确统计计算计划总进度比例', () {
      final entries = [
        ScheduleEntry(
          id: 'e1',
          planId: 'p1',
          title: 't1',
          scheduledDate: '2026-10-01',
          stepIndex: 0,
          kind: ScheduleEntryKind.initial,
          isCompleted: true,
        ),
        ScheduleEntry(
          id: 'e2',
          planId: 'p1',
          title: 't2',
          scheduledDate: '2026-10-02',
          stepIndex: 1,
          kind: ScheduleEntryKind.review,
          isCompleted: false,
        ),
      ];

      expect(PlanScheduler.calculatePlanProgress(entries), equals(0.5));
    });
  });
}
