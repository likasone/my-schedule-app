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
    this.selectedTab = 0, // 0: 日程/复习待办, 1: 全部计划, 2: 灵感便签
    this.isLoading = false,
    this.selectedDateIso,
    this.memoSearchQuery = '',
    this.selectedMemoTag = '全部',
  });

  /// 所有的计划集合
  final List<PlanItem> plans;

  /// 所有的排程执行条目（含初学、艾宾浩斯复习、自适应补救）
  final List<ScheduleEntry> entries;

  /// 快速记事便签列表（实体列表）
  final List<MemoItem> memos;

  /// 记事检索关键词
  final String memoSearchQuery;

  /// 当前选中的记事分类标签（'全部' / '闪念' / '灵感' / '待办' / '备忘' / '随想'）
  final String selectedMemoTag;

  /// 当前选中的视图 Tab
  final int selectedTab;

  /// 数据加载状态（默认为 false，杜绝死锁转圈）
  final bool isLoading;

  /// 当前选中的日历查看日期（格式：YYYY-MM-DD，为空则默认为今日）
  final String? selectedDateIso;

  /// 经过排序与搜索过滤后的便签列表（置顶优先，其次按更新/创建时间倒序）
  List<MemoItem> get filteredMemos {
    var list = memos;
    if (selectedMemoTag != '全部') {
      list = list.where((m) => m.tag == selectedMemoTag).toList();
    }
    if (memoSearchQuery.trim().isNotEmpty) {
      final q = memoSearchQuery.trim().toLowerCase();
      list = list.where((m) => m.content.toLowerCase().contains(q)).toList();
    }
    return List<MemoItem>.from(list)..sort((a, b) {
      if (a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }
      final timeA = a.updatedAt ?? a.createdAt;
      final timeB = b.updatedAt ?? b.createdAt;
      return timeB.compareTo(timeA);
    });
  }

  /// 获取当前有效的查看日期 ISO 字符串
  String get effectiveDateIso =>
      selectedDateIso ?? PlanScheduler.formatIsoDate(DateTime.now());

  /// 筛选出当前选定日期的待执行/复习任务项
  List<ScheduleEntry> get selectedDateEntries {
    final today = PlanScheduler.formatIsoDate(DateTime.now());
    final isViewingToday = effectiveDateIso == today;
    return PlanScheduler.filterEntriesForDate(
      allEntries: entries,
      targetDateIso: effectiveDateIso,
      includeOverdue: isViewingToday, // 仅在查看“今天”时自动将历史未打卡的逾期任务平滑前移浮现
    );
  }

  /// 今日条目别名（兼容现有组件属性）
  List<ScheduleEntry> get todayEntries => selectedDateEntries;

  /// 计算当前选定日期的完成率（0.0 ~ 1.0）
  double get todayCompletionRate {
    final list = selectedDateEntries;
    if (list.isEmpty) return 0.0;
    final completedCount = list.where((e) => e.isCompleted).length;
    return completedCount / list.length;
  }

  /// 复制并更新部分属性
  ScheduleState copyWith({
    List<PlanItem>? plans,
    List<ScheduleEntry>? entries,
    List<MemoItem>? memos,
    int? selectedTab,
    bool? isLoading,
    String? selectedDateIso,
    String? memoSearchQuery,
    String? selectedMemoTag,
  }) {
    return ScheduleState(
      plans: plans ?? this.plans,
      entries: entries ?? this.entries,
      memos: memos ?? this.memos,
      selectedTab: selectedTab ?? this.selectedTab,
      isLoading: isLoading ?? this.isLoading,
      selectedDateIso: selectedDateIso ?? this.selectedDateIso,
      memoSearchQuery: memoSearchQuery ?? this.memoSearchQuery,
      selectedMemoTag: selectedMemoTag ?? this.selectedMemoTag,
    );
  }
}

/// 全局 NotifierProvider 状态注入
final scheduleProvider =
    NotifierProvider<ScheduleNotifier, ScheduleState>(ScheduleNotifier.new);

/// 日程与计划状态控制器（Schedule Notifier）
/// 基于 Flutter Riverpod 3.x 现代 Notifier 架构打造
class ScheduleNotifier extends Notifier<ScheduleState> {
  static const _plansStorageKey = 'app_schedule_plans_v1';
  static const _entriesStorageKey = 'app_schedule_entries_v1';
  static const _memosStorageKey = 'app_schedule_memos_v1';

  @override
  ScheduleState build() {
    // 异步排队加载存储数据，初始返回 isLoading: false，确保 Windows/移动端秒级响应，永不阻塞死锁
    Future.microtask(_loadFromStorage);
    return const ScheduleState(isLoading: false);
  }

  /// 切换当前在日历上选中的日期
  void selectDate(String isoDate) {
    state = state.copyWith(selectedDateIso: isoDate, isLoading: false);
  }

  /// 回到今日
  void selectToday() {
    state = state.copyWith(
      selectedDateIso: PlanScheduler.formatIsoDate(DateTime.now()),
      isLoading: false,
    );
  }

  /// 供外部（如 WebDAV 坚果云还原备份数据后）主动触发重载
  Future<void> reloadFromStorage() async {
    await _loadFromStorage();
  }

  /// 从本地持久化存储（SharedPreferences）中异步读取数据
  Future<void> _loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final plansJson = prefs.getString(_plansStorageKey);
      final entriesJson = prefs.getString(_entriesStorageKey);
      final memosJson = prefs.getString(_memosStorageKey);

      List<PlanItem> loadedPlans = [];
      List<ScheduleEntry> loadedEntries = [];
      List<MemoItem> loadedMemos = [];

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
              reviewOffsets:
                  (map['reviewOffsets'] as List?)?.cast<int>() ??
                  [1, 2, 4, 7, 15, 30],
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
            final reminderTimeStr = map['reminderTime'] as String?;
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
              reminderTime: reminderTimeStr != null ? DateTime.tryParse(reminderTimeStr) : null,
              hasReminder: map['hasReminder'] as bool? ?? (reminderTimeStr != null),
              reminderMinutesBefore: map['reminderMinutesBefore'] as int? ?? 0,
              repeatRule: ScheduleRepeatRule.values.firstWhere(
                (r) => r.name == (map['repeatRule'] as String?),
                orElse: () => ScheduleRepeatRule.none,
              ),
            );
          }).toList();
        } catch (e) {
          debugPrint('解析已保存条目失败: $e');
        }
      }

      if (memosJson != null && memosJson.isNotEmpty) {
        try {
          final decoded = jsonDecode(memosJson) as List;
          loadedMemos = decoded.map(MemoItem.fromJson).toList();
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
          MemoItem(
            id: 'memo_demo_01',
            content: '欢迎使用日程与计划中心！这里支持任务规划、智能艾宾浩斯复习和随手记事。',
            createdAt: now,
            isPinned: true,
            tag: '备忘',
          ),
          MemoItem(
            id: 'memo_demo_02',
            content: 'Windows 桌面端与安卓端已实现全链路安全存储、加密同步与高穿透系统级提醒。',
            createdAt: now,
            tag: '灵感',
          ),
        ];

        await _persist(loadedPlans, loadedEntries, loadedMemos);
      }

      state = state.copyWith(
        plans: loadedPlans,
        entries: loadedEntries,
        memos: loadedMemos,
        isLoading: false,
      );
    } catch (e) {
      debugPrint('加载日程存储发生异常: $e');
      state = state.copyWith(isLoading: false);
    }
  }

  /// 序列化并写入本地持久化
  Future<void> _persist(
    List<PlanItem> plans,
    List<ScheduleEntry> entries,
    List<MemoItem> memos,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final plansData = plans
          .map(
            (p) => {
              'id': p.id,
              'title': p.title,
              'startDate': p.startDate,
              'dayCount': p.dayCount,
              'reviewOffsets': p.reviewOffsets,
              'createdAt': p.createdAt.toIso8601String(),
              'notes': p.notes,
            },
          )
          .toList();

      final entriesData = entries
          .map(
            (e) => {
              'id': e.id,
              'planId': e.planId,
              'title': e.title,
              'scheduledDate': e.scheduledDate,
              'stepIndex': e.stepIndex,
              'kind': e.kind.name,
              'isCompleted': e.isCompleted,
              'originalDueDate': e.originalDueDate,
              'notes': e.notes,
              'reminderTime': e.reminderTime?.toIso8601String(),
              'hasReminder': e.hasReminder,
              'reminderMinutesBefore': e.reminderMinutesBefore,
              'repeatRule': e.repeatRule.name,
            },
          )
          .toList();

      final memosData = memos.map((m) => m.toJson()).toList();

      await prefs.setString(_plansStorageKey, jsonEncode(plansData));
      await prefs.setString(_entriesStorageKey, jsonEncode(entriesData));
      await prefs.setString(_memosStorageKey, jsonEncode(memosData));
    } catch (e) {
      debugPrint('持久化存储写入失败: $e');
    }
  }

  /// 切换主视图 Tab
  void setTab(int index) {
    state = state.copyWith(selectedTab: index, isLoading: false);
  }

  /// 创建全新艾宾浩斯复习计划（支持指定日历起始日期）
  Future<void> createPlan({
    required String title,
    String notes = '',
    String? customStartDateIso,
    DateTime? reminderTime,
  }) async {
    final now = DateTime.now();
    // 若未传起始日，默认使用当前在日历上选定的日期
    final startIso = customStartDateIso ?? state.effectiveDateIso;
    final plan = PlanItem(
      id: 'plan_${DateTime.now().millisecondsSinceEpoch}',
      title: title.trim(),
      startDate: startIso,
      createdAt: now,
      notes: notes.trim(),
    );

    // 依艾宾浩斯遗忘曲线生成全阶段任务节点
    final newEntries = PlanScheduler.generateInitialSchedule(plan: plan);
    final updatedPlans = [...state.plans, plan];
    final updatedEntries = [...state.entries, ...newEntries];

    // 若指定了具体提醒时间点，联动 ReminderService 挂载系统闹钟与日历提醒
    if (reminderTime != null) {
      try {
        final reminderService = ref.read(reminderServiceProvider);
        await reminderService.scheduleComprehensiveReminder(
          ReminderItem(
            id: plan.id,
            title: '【计划执行】${plan.title}',
            notes: plan.notes,
            reminderTime: reminderTime,
          ),
        );
      } catch (e) {
        debugPrint('联动设置提醒异常: $e');
      }
    }

    state = state.copyWith(
      plans: updatedPlans,
      entries: updatedEntries,
      isLoading: false, // 显式解除 loading，保证界面秒级更新
    );
    await _persist(updatedPlans, updatedEntries, state.memos);
  }

  /// 创建单项日程待办项（支持指定具体日期和时间点，并可配置强提醒与周期性重复）
  Future<void> createSingleSchedule({
    required String title,
    required DateTime time,
    String notes = '',
    bool hasReminder = true,
    int reminderMinutesBefore = 0,
    ScheduleRepeatRule repeatRule = ScheduleRepeatRule.none,
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
      reminderTime: time,
      hasReminder: hasReminder,
      reminderMinutesBefore: reminderMinutesBefore,
      repeatRule: repeatRule,
    );

    final updatedEntries = [...state.entries, entry];

    // 若开启了强提醒，挂载系统日历与闹钟提醒（带异常保护，支持 RFC 5545 周期重复）
    if (hasReminder) {
      try {
        final reminderService = ref.read(reminderServiceProvider);
        final actualAlertTime = time.subtract(Duration(minutes: reminderMinutesBefore));
        await reminderService.scheduleComprehensiveReminder(
          ReminderItem(
            id: entry.id,
            title: entry.title,
            notes: entry.notes.isNotEmpty ? entry.notes : '日程提醒',
            reminderTime: actualAlertTime,
            rrule: repeatRule.rrule,
          ),
        );
      } catch (e) {
        debugPrint('调度高穿透提醒异常，已保存日程: $e');
      }
    }

    state = state.copyWith(
      entries: updatedEntries,
      isLoading: false, // 显式解除 loading，防止任何转圈卡顿
    );
    await _persist(state.plans, updatedEntries, state.memos);
  }

  /// 切换指定条目的提醒状态（开启/关闭）
  Future<void> toggleEntryReminder(String entryId) async {
    final updatedEntries = state.entries.map((entry) {
      if (entry.id == entryId) {
        final newHasReminder = !entry.hasReminder;
        return entry.copyWith(hasReminder: newHasReminder);
      }
      return entry;
    }).toList();

    state = state.copyWith(entries: updatedEntries, isLoading: false);
    await _persist(state.plans, updatedEntries, state.memos);
  }

  /// 触发即时桌面/端侧提醒测试（供用户直观检验闹钟与通知弹窗）
  Future<void> triggerTestReminder({String? customTitle}) async {
    final reminderService = ref.read(reminderServiceProvider);
    final now = DateTime.now();
    final testItem = ReminderItem(
      id: 'test_reminder_${now.millisecondsSinceEpoch}',
      title: customTitle ?? '【测试提醒】日程与高穿透闹钟正常运作',
      notes: '测试时间: ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}',
      reminderTime: now,
    );

    // 触发桌面端/平台即时提醒测试
    reminderService.triggerDesktopReminder(testItem);
  }

  /// 标记条目打卡完成，并响应记忆反馈（牢固/模糊/遗忘）与周期性任务自动流转
  Future<void> toggleEntryCompletion(
    String entryId, {
    ReviewFeedback? feedback,
  }) async {
    final todayIso = PlanScheduler.formatIsoDate(DateTime.now());
    ScheduleEntry? remedialCreated;
    ScheduleEntry? recurringNextCreated;

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

        // 若为周期性重复任务（如每日习惯、工作日例会等），打卡完成时自动推演并生成下一周期的执行节点
        if (newCompleted && entry.repeatRule != ScheduleRepeatRule.none) {
          final nextIso = PlanScheduler.calculateNextRepeatDate(entry.scheduledDate, entry.repeatRule);
          final nextExists = state.entries.any(
            (e) => e.planId == entry.planId && e.scheduledDate == nextIso && e.title == entry.title,
          );
          if (!nextExists) {
            DateTime? nextReminderTime;
            if (entry.reminderTime != null) {
              final nextBase = PlanScheduler.parseIsoDate(nextIso);
              nextReminderTime = DateTime(
                nextBase.year,
                nextBase.month,
                nextBase.day,
                entry.reminderTime!.hour,
                entry.reminderTime!.minute,
              );
            }
            recurringNextCreated = ScheduleEntry(
              id: 'entry_${DateTime.now().millisecondsSinceEpoch}_repeat',
              planId: entry.planId,
              title: entry.title,
              scheduledDate: nextIso,
              stepIndex: entry.stepIndex + 1,
              kind: entry.kind,
              notes: entry.notes,
              reminderTime: nextReminderTime,
              hasReminder: entry.hasReminder,
              reminderMinutesBefore: entry.reminderMinutesBefore,
              repeatRule: entry.repeatRule,
            );
          }
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

    // 如果打卡完成触发了下一周期重复任务，动态追加
    if (recurringNextCreated != null) {
      updatedEntries.add(recurringNextCreated!);
    }

    state = state.copyWith(
      entries: updatedEntries,
      isLoading: false,
    );
    await _persist(state.plans, updatedEntries, state.memos);
  }

  /// 添加快速便签记事（支持设置分类标签与置顶）
  Future<void> addQuickMemo(
    String memo, {
    String tag = '闪念',
    bool isPinned = false,
  }) async {
    final text = memo.trim();
    if (text.isEmpty) return;

    final now = DateTime.now();
    final newMemo = MemoItem(
      id: 'memo_${now.millisecondsSinceEpoch}',
      content: text,
      createdAt: now,
      tag: tag,
      isPinned: isPinned,
    );

    final updatedMemos = [newMemo, ...state.memos];
    state = state.copyWith(memos: updatedMemos, isLoading: false);
    await _persist(state.plans, state.entries, updatedMemos);
  }

  /// 编辑更新已有的记事便签内容与属性
  Future<void> updateMemo({
    required String id,
    required String content,
    String? tag,
    bool? isPinned,
  }) async {
    final text = content.trim();
    if (text.isEmpty) return;

    final updatedMemos = state.memos.map((m) {
      if (m.id == id) {
        return m.copyWith(
          content: text,
          tag: tag,
          isPinned: isPinned,
          updatedAt: DateTime.now(),
        );
      }
      return m;
    }).toList();

    state = state.copyWith(memos: updatedMemos, isLoading: false);
    await _persist(state.plans, state.entries, updatedMemos);
  }

  /// 切换指定便签的置顶状态（📌 置顶）
  Future<void> togglePinMemo(String id) async {
    final updatedMemos = state.memos.map((m) {
      if (m.id == id) {
        return m.copyWith(isPinned: !m.isPinned, updatedAt: DateTime.now());
      }
      return m;
    }).toList();

    state = state.copyWith(memos: updatedMemos, isLoading: false);
    await _persist(state.plans, state.entries, updatedMemos);
  }

  /// 根据 ID 删除便签记事
  Future<void> deleteMemo(String id) async {
    final updatedMemos = state.memos.where((m) => m.id != id).toList();
    state = state.copyWith(memos: updatedMemos, isLoading: false);
    await _persist(state.plans, state.entries, updatedMemos);
  }

  /// 根据索引删除便签记事（兼容旧单元测试接口）
  Future<void> deleteQuickMemo(int index) async {
    if (index < 0 || index >= state.memos.length) return;
    final updatedMemos = List<MemoItem>.from(state.memos)..removeAt(index);
    state = state.copyWith(memos: updatedMemos, isLoading: false);
    await _persist(state.plans, state.entries, updatedMemos);
  }

  /// 设置记事搜索关键词
  void setMemoSearchQuery(String query) {
    state = state.copyWith(memoSearchQuery: query);
  }

  /// 切换记事分类标签
  void setSelectedMemoTag(String tag) {
    state = state.copyWith(selectedMemoTag: tag);
  }

  /// 将随手记事一键转化为正式日程待办（并设置定时强提醒）
  Future<void> convertMemoToSchedule({
    required String memoId,
    required DateTime scheduleTime,
    String? title,
    bool hasReminder = true,
  }) async {
    final memo = state.memos.firstWhere((m) => m.id == memoId);
    final taskTitle = title?.trim().isNotEmpty == true
        ? title!.trim()
        : (memo.content.length > 20 ? '${memo.content.substring(0, 20)}...' : memo.content);

    await createSingleSchedule(
      title: taskTitle,
      time: scheduleTime,
      notes: memo.content,
      hasReminder: hasReminder,
    );
  }
}
