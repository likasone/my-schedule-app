import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/plan_scheduler.dart';
import '../../../core/services/reminder_service.dart';

/// 日程与计划页面状态模型（Schedule State）
@immutable
class ScheduleState {
  const ScheduleState({
    this.plans = const [],
    this.entries = const [],
    this.memos = const [],
    this.selectedTab = 0, // 0: 今日待办, 1: 全部计划, 2: 灵感便签
    this.isLoading = false,
  });

  /// 所有的计划集合
  final List<PlanItem> plans;

  /// 所有的排程执行条目（含初学、艾宾浩斯复习、自适应补救）
  final List<ScheduleEntry> entries;

  /// 快速记事便签列表
  final List<String> memos;

  /// 当前选中的视图 Tab
  final int selectedTab;

  /// 数据加载状态标记
  final bool isLoading;

  /// 筛选出今日需要执行或过去逾期顺延至今日的条目
  List<ScheduleEntry> get todayEntries {
    final today = PlanScheduler.formatIsoDate(DateTime.now());
    return PlanScheduler.resolveDailyViewEntries(
      allEntries: entries,
      todayIso: today,
    );
  }

  /// 计算今日待办任务的完成率 (0.0 ~ 1.0)
  double get todayCompletionRate {
    final todayList = todayEntries;
    if (todayList.isEmpty) return 1.0;
    final done = todayList.where((e) => e.isCompleted).length;
    return done / todayList.length;
  }

  ScheduleState copyWith({
    List<PlanItem>? plans,
    List<ScheduleEntry>? entries,
    List<String>? memos,
    int? selectedTab,
    bool? isLoading,
  }) {
    return ScheduleState(
      plans: plans ?? this.plans,
      entries: entries ?? this.entries,
      memos: memos ?? this.memos,
      selectedTab: selectedTab ?? this.selectedTab,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// 日程与计划状态控制器（Schedule Notifier）
class ScheduleNotifier extends StateNotifier<ScheduleState> {
  ScheduleNotifier(this._ref) : super(const ScheduleState()) {
    _loadFromStorage();
  }

  final Ref _ref;
  static const _plansStorageKey = 'app_schedule_plans_v1';
  static const _entriesStorageKey = 'app_schedule_entries_v1';
  static const _memosStorageKey = 'app_schedule_memos_v1';

  /// 从本地持久化存储（SharedPreferences）中异步读取数据
  Future<void> _loadFromStorage() async {
    state = state.copyWith(isLoading: true);
    final prefs = await SharedPreferences.getInstance();

    final plansJson = prefs.getString(_plansStorageKey);
    final entriesJson = prefs.getString(_entriesStorageKey);
    final memosJson = prefs.getString(_memosStorageKey);

    List<PlanItem> loadedPlans = [];
    List<ScheduleEntry> loadedEntries = [];
    List<String> loadedMemos = [];

    if (plansJson != null && plansJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(plansJson) as List;
        loadedPlans = decoded.map((item) {
          final map = item as Map<String, dynamic>;
          return PlanItem(
            id: map['id'] as String,
            title: map['title'] as String,
            startDate: map['startDate'] as String,
            dayCount: map['dayCount'] as int? ?? 365,
            reviewOffsets: (map['reviewOffsets'] as List?)?.cast<int>() ?? [1, 2, 4, 7, 15, 30],
            createdAt: DateTime.parse(map['createdAt'] as String),
            notes: map['notes'] as String? ?? '',
          );
        }).toList();
      } catch (e) {
        debugPrint('解析已保存计划失败: $e');
      }
    }

    if (entriesJson != null && entriesJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(entriesJson) as List;
        loadedEntries = decoded.map((item) {
          final map = item as Map<String, dynamic>;
          return ScheduleEntry(
            id: map['id'] as String,
            planId: map['planId'] as String,
            title: map['title'] as String,
            scheduledDate: map['scheduledDate'] as String,
            stepIndex: map['stepIndex'] as int,
            kind: ScheduleEntryKind.values.firstWhere(
              (k) => k.name == (map['kind'] as String?),
              orElse: () => ScheduleEntryKind.task,
            ),
            isCompleted: map['isCompleted'] as bool? ?? false,
            originalDueDate: map['originalDueDate'] as String?,
            notes: map['notes'] as String? ?? '',
          );
        }).toList();
      } catch (e) {
        debugPrint('解析已保存条目失败: $e');
      }
    }

    if (memosJson != null && memosJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(memosJson) as List;
        loadedMemos = decoded.cast<String>();
      } catch (_) {}
    }

    // 若本地为空，初始化开箱即用的预设示例，让用户首次启动立刻看到内容
    if (loadedPlans.isEmpty && loadedEntries.isEmpty) {
      final now = DateTime.now();
      final todayIso = PlanScheduler.formatIsoDate(now);
      final demoPlan = PlanItem(
        id: 'plan_demo_01',
        title: '艾宾浩斯复习计划示例',
        startDate: todayIso,
        createdAt: now,
        notes: '按 1, 2, 4, 7, 15, 30 天周期智能生成的复习进阶计划',
      );
      final demoEntries = PlanScheduler.generateInitialSchedule(plan: demoPlan);

      loadedPlans = [demoPlan];
      loadedEntries = demoEntries;
      loadedMemos = [
        '欢迎使用日程与计划中心！这里支持任务、智能复习和轻便签。',
        'Windows 桌面端与安卓端已实现全链路安全存储与提醒穿透。',
      ];

      await _persist(loadedPlans, loadedEntries, loadedMemos);
    }

    state = state.copyWith(
      plans: loadedPlans,
      entries: loadedEntries,
      memos: loadedMemos,
      isLoading: false,
    );
  }

  /// 序列化并写入本地持久化
  Future<void> _persist(
    List<PlanItem> plans,
    List<ScheduleEntry> entries,
    List<String> memos,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    final plansData = plans.map((p) => {
      'id': p.id,
      'title': p.title,
      'startDate': p.startDate,
      'dayCount': p.dayCount,
      'reviewOffsets': p.reviewOffsets,
      'createdAt': p.createdAt.toIso8601String(),
      'notes': p.notes,
    }).toList();

    final entriesData = entries.map((e) => {
      'id': e.id,
      'planId': e.planId,
      'title': e.title,
      'scheduledDate': e.scheduledDate,
      'stepIndex': e.stepIndex,
      'kind': e.kind.name,
      'isCompleted': e.isCompleted,
      'originalDueDate': e.originalDueDate,
      'notes': e.notes,
    }).toList();

    await prefs.setString(_plansStorageKey, jsonEncode(plansData));
    await prefs.setString(_entriesStorageKey, jsonEncode(entriesData));
    await prefs.setString(_memosStorageKey, jsonEncode(memos));
  }

  /// 切换主视图 Tab
  void setTab(int index) {
    state = state.copyWith(selectedTab: index);
  }

  /// 创建全新艾宾浩斯复习计划
  Future<void> createPlan({
    required String title,
    String notes = '',
    DateTime? reminderTime,
  }) async {
    final now = DateTime.now();
    final todayIso = PlanScheduler.formatIsoDate(now);
    final plan = PlanItem(
      id: 'plan_${DateTime.now().millisecondsSinceEpoch}',
      title: title.trim(),
      startDate: todayIso,
      createdAt: now,
      notes: notes.trim(),
    );

    // 依艾宾浩斯遗忘曲线生成全阶段任务节点
    final newEntries = PlanScheduler.generateInitialSchedule(plan: plan);
    final updatedPlans = [...state.plans, plan];
    final updatedEntries = [...state.entries, ...newEntries];

    // 若指定了具体提醒时间点，联动 ReminderService 挂载系统闹钟与日历提醒
    if (reminderTime != null) {
      final reminderService = _ref.read(reminderServiceProvider);
      await reminderService.scheduleComprehensiveReminder(
        ReminderItem(
          id: plan.id,
          title: '【计划执行】${plan.title}',
          notes: plan.notes,
          reminderTime: reminderTime,
        ),
      );
    }

    state = state.copyWith(plans: updatedPlans, entries: updatedEntries);
    await _persist(updatedPlans, updatedEntries, state.memos);
  }

  /// 创建普通日程待办项
  Future<void> createSingleSchedule({
    required String title,
    required DateTime time,
    String notes = '',
  }) async {
    final isoDate = PlanScheduler.formatIsoDate(time);
    final entry = ScheduleEntry(
      id: 'entry_${DateTime.now().millisecondsSinceEpoch}',
      planId: 'single_task',
      title: title.trim(),
      scheduledDate: isoDate,
      stepIndex: 0,
      kind: ScheduleEntryKind.task,
      notes: notes.trim(),
    );

    final updatedEntries = [...state.entries, entry];

    // 挂载高穿透提醒
    final reminderService = _ref.read(reminderServiceProvider);
    await reminderService.scheduleComprehensiveReminder(
      ReminderItem(
        id: entry.id,
        title: entry.title,
        notes: entry.notes,
        reminderTime: time,
      ),
    );

    state = state.copyWith(entries: updatedEntries);
    await _persist(state.plans, updatedEntries, state.memos);
  }

  /// 标记条目打卡完成，并响应记忆反馈（牢固/模糊/遗忘）
  Future<void> toggleEntryCompletion(
    String entryId, {
    ReviewFeedback? feedback,
  }) async {
    final todayIso = PlanScheduler.formatIsoDate(DateTime.now());
    ScheduleEntry? remedialCreated;

    final updatedEntries = state.entries.map((entry) {
      if (entry.id == entryId) {
        final newCompleted = !entry.isCompleted;

        // 若用户标记了遗忘且处于复习阶段，自适应产生次日强力补救节点
        if (newCompleted && feedback != null) {
          remedialCreated = PlanScheduler.handleFeedbackAndAdaptiveReschedule(
            currentEntry: entry,
            feedback: feedback,
            todayIso: todayIso,
          );
        }

        return entry.copyWith(
          isCompleted: newCompleted,
          completedAt: newCompleted ? DateTime.now() : null,
          feedback: feedback,
        );
      }
      return entry;
    }).toList();

    // 如果自适应算法创建了补救复习条目，动态追加
    if (remedialCreated != null) {
      updatedEntries.add(remedialCreated!);
    }

    state = state.copyWith(entries: updatedEntries);
    await _persist(state.plans, updatedEntries, state.memos);
  }

  /// 添加快速便签记事
  Future<void> addQuickMemo(String memo) async {
    final text = memo.trim();
    if (text.isEmpty) return;

    final updatedMemos = [text, ...state.memos];
    state = state.copyWith(memos: updatedMemos);
    await _persist(state.plans, state.entries, updatedMemos);
  }

  /// 删除便签记事
  Future<void> deleteQuickMemo(int index) async {
    if (index < 0 || index >= state.memos.length) return;
    final updatedMemos = List<String>.from(state.memos)..removeAt(index);
    state = state.copyWith(memos: updatedMemos);
    await _persist(state.plans, state.entries, updatedMemos);
  }
}

/// 全局 StateNotifierProvider 注入
final scheduleProvider = StateNotifierProvider<ScheduleNotifier, ScheduleState>((ref) {
  return ScheduleNotifier(ref);
});
