import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/app_data_directory.dart';
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
              priority: SchedulePriority.values.firstWhere(
                (p) => p.name == (map['priority'] as String?),
                orElse: () => SchedulePriority.none,
              ),
              subTasks: (map['subTasks'] as List?)
                      ?.map(SubTaskItem.fromJson)
                      .toList() ??
                  const [],
              isAllDay: map['isAllDay'] as bool? ?? false,
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

      // 启动第三方自动导入热目录异步检测（Hot Folder / Inbox）
      Future.microtask(scanAndAutoImportHotFolder);
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
              'priority': e.priority.name,
              'subTasks': e.subTasks.map((s) => s.toJson()).toList(),
              'isAllDay': e.isAllDay,
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

  /// 创建单项日程待办项（支持指定具体日期和时间点，并可配置强提醒与周期性重复、优先级与子清单）
  Future<void> createSingleSchedule({
    required String title,
    required DateTime time,
    String notes = '',
    bool hasReminder = true,
    int reminderMinutesBefore = 0,
    ScheduleRepeatRule repeatRule = ScheduleRepeatRule.none,
    SchedulePriority priority = SchedulePriority.none,
    bool isAllDay = false,
    List<SubTaskItem> subTasks = const [],
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
      priority: priority,
      isAllDay: isAllDay,
      subTasks: subTasks,
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

  /// 更新修改已有的日程待办项（包括标题、日期、时分、备注、提醒规则、重复周期、优先级、全天模式、子清单）
  Future<void> updateScheduleEntry({
    required String id,
    required String title,
    required String scheduledDate,
    String notes = '',
    DateTime? reminderTime,
    bool hasReminder = false,
    int reminderMinutesBefore = 0,
    ScheduleRepeatRule repeatRule = ScheduleRepeatRule.none,
    SchedulePriority priority = SchedulePriority.none,
    bool isAllDay = false,
    List<SubTaskItem> subTasks = const [],
  }) async {
    ScheduleEntry? oldEntry;
    for (final e in state.entries) {
      if (e.id == id) {
        oldEntry = e;
        break;
      }
    }
    if (oldEntry == null) return;

    // 若此前设置过提醒，且提醒设置有变，先撤销旧提醒
    if (oldEntry.hasReminder && oldEntry.reminderTime != null) {
      try {
        final reminderService = ref.read(reminderServiceProvider);
        await reminderService.cancelReminder(
          ReminderItem(
            id: oldEntry.id,
            title: oldEntry.title,
            reminderTime: oldEntry.reminderTime!,
          ),
        );
      } catch (e) {
        debugPrint('更新日程时取消旧提醒异常: $e');
      }
    }

    // 若新配置激活了提醒，重新注册系统级闹钟与日历事件
    if (hasReminder && reminderTime != null) {
      try {
        final reminderService = ref.read(reminderServiceProvider);
        final actualAlertTime = reminderTime.subtract(Duration(minutes: reminderMinutesBefore));
        await reminderService.scheduleComprehensiveReminder(
          ReminderItem(
            id: id,
            title: title.trim(),
            notes: notes.trim().isNotEmpty ? notes.trim() : '日程提醒',
            reminderTime: actualAlertTime,
            rrule: repeatRule.rrule,
          ),
        );
      } catch (e) {
        debugPrint('更新日程时挂载新提醒异常: $e');
      }
    }

    final updatedEntries = state.entries.map((entry) {
      if (entry.id == id) {
        return entry.copyWith(
          title: title.trim(),
          scheduledDate: scheduledDate,
          notes: notes.trim(),
          reminderTime: reminderTime,
          hasReminder: hasReminder,
          reminderMinutesBefore: reminderMinutesBefore,
          repeatRule: repeatRule,
          priority: priority,
          isAllDay: isAllDay,
          subTasks: subTasks,
        );
      }
      return entry;
    }).toList();

    state = state.copyWith(entries: updatedEntries, isLoading: false);
    await _persist(state.plans, updatedEntries, state.memos);
  }

  /// 切换指定日程条目下的子待办清单完成状态（Checklist 打勾/取消打勾）
  Future<void> toggleSubTaskCompletion(String entryId, String subTaskId) async {
    final updatedEntries = state.entries.map((entry) {
      if (entry.id == entryId) {
        final newSubTasks = entry.subTasks.map((sub) {
          if (sub.id == subTaskId) {
            return sub.copyWith(isCompleted: !sub.isCompleted);
          }
          return sub;
        }).toList();
        return entry.copyWith(subTasks: newSubTasks);
      }
      return entry;
    }).toList();

    state = state.copyWith(entries: updatedEntries, isLoading: false);
    await _persist(state.plans, updatedEntries, state.memos);
  }

  /// 更新修改已有的计划项（支持修改名称、备注与调整起始日期）
  /// 若调整了起始日期，将自动平移该计划下所有未完成的排程阶段节点
  Future<void> updatePlan({
    required String planId,
    required String title,
    String notes = '',
    String? newStartDateIso,
  }) async {
    PlanItem? targetPlan;
    for (final p in state.plans) {
      if (p.id == planId) {
        targetPlan = p;
        break;
      }
    }
    if (targetPlan == null) return;

    final trimmedTitle = title.trim();
    final trimmedNotes = notes.trim();
    final updatedStartDate = newStartDateIso ?? targetPlan.startDate;
    final isStartDateChanged = updatedStartDate != targetPlan.startDate;

    // 1. 更新计划自身基本信息
    final updatedPlans = state.plans.map((p) {
      if (p.id == planId) {
        return p.copyWith(
          title: trimmedTitle.isNotEmpty ? trimmedTitle : p.title,
          notes: trimmedNotes,
          startDate: updatedStartDate,
        );
      }
      return p;
    }).toList();

    // 2. 如果调整了起始基准日，智能平移未完成的排程阶段节点
    List<ScheduleEntry> updatedEntries = state.entries;
    if (isStartDateChanged) {
      final daysDiff = PlanScheduler.daysBetween(targetPlan.startDate, updatedStartDate);
      updatedEntries = state.entries.map((entry) {
        if (entry.planId == planId && !entry.isCompleted) {
          final newScheduledDate = PlanScheduler.addDays(entry.scheduledDate, daysDiff);
          DateTime? newReminderTime;
          if (entry.reminderTime != null) {
            newReminderTime = entry.reminderTime!.add(Duration(days: daysDiff));
          }
          return entry.copyWith(
            scheduledDate: newScheduledDate,
            reminderTime: newReminderTime,
          );
        }
        return entry;
      }).toList();
    } else {
      // 若仅修改了计划名称，同步更新该计划关联节点中标题前缀
      updatedEntries = state.entries.map((entry) {
        if (entry.planId == planId && entry.title.startsWith(targetPlan!.title)) {
          final suffix = entry.title.substring(targetPlan.title.length);
          return entry.copyWith(title: '$trimmedTitle$suffix');
        }
        return entry;
      }).toList();
    }

    state = state.copyWith(
      plans: updatedPlans,
      entries: updatedEntries,
      isLoading: false,
    );
    await _persist(updatedPlans, updatedEntries, state.memos);
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

  /// 添加快速便签记事（支持设置标题、拟真花笺纸色、分类标签与置顶）
  Future<void> addQuickMemo(
    String memo, {
    String title = '',
    int colorIndex = 0,
    String tag = '闪念',
    bool isPinned = false,
  }) async {
    final text = memo.trim();
    final memoTitle = title.trim();
    if (text.isEmpty && memoTitle.isEmpty) return;

    final now = DateTime.now();
    final newMemo = MemoItem(
      id: 'memo_${now.millisecondsSinceEpoch}',
      title: memoTitle,
      colorIndex: colorIndex,
      content: text,
      createdAt: now,
      tag: tag,
      isPinned: isPinned,
    );

    final updatedMemos = [newMemo, ...state.memos];
    state = state.copyWith(memos: updatedMemos, isLoading: false);
    await _persist(state.plans, state.entries, updatedMemos);
  }

  /// 编辑更新已有的记事便签内容与属性（支持更新标题与花笺纸色）
  Future<void> updateMemo({
    required String id,
    required String content,
    String? title,
    int? colorIndex,
    String? tag,
    bool? isPinned,
  }) async {
    final text = content.trim();
    final trimmedTitle = title?.trim();
    if (text.isEmpty && (trimmedTitle == null || trimmedTitle.isEmpty)) return;

    final updatedMemos = state.memos.map((m) {
      if (m.id == id) {
        return m.copyWith(
          title: trimmedTitle,
          colorIndex: colorIndex,
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

  /// 删除指定单项日程待办（并同步取消相关的系统/桌面强提醒）
  Future<void> deleteScheduleEntry(String entryId) async {
    ScheduleEntry? targetEntry;
    for (final e in state.entries) {
      if (e.id == entryId) {
        targetEntry = e;
        break;
      }
    }

    // 若存在已绑定的提醒，通知提醒调度器取消该条目的定时通知
    if (targetEntry != null && targetEntry.hasReminder && targetEntry.reminderTime != null) {
      try {
        final reminderService = ref.read(reminderServiceProvider);
        await reminderService.cancelReminder(
          ReminderItem(
            id: targetEntry.id,
            title: targetEntry.title,
            reminderTime: targetEntry.reminderTime!,
          ),
        );
      } catch (e) {
        debugPrint('取消待办日程提醒异常: $e');
      }
    }

    // 从列表中过滤剔除该日程条目
    final updatedEntries = state.entries.where((e) => e.id != entryId).toList();
    state = state.copyWith(entries: updatedEntries, isLoading: false);
    await _persist(state.plans, updatedEntries, state.memos);
  }

  /// 删除指定艾宾浩斯复习计划（级联删除该计划创建的所有复习日程节点）
  Future<void> deletePlan(String planId) async {
    // 移除计划本体
    final updatedPlans = state.plans.where((p) => p.id != planId).toList();
    // 级联清理属于该计划的所有复习节点条目
    final updatedEntries = state.entries.where((e) => e.planId != planId).toList();

    state = state.copyWith(plans: updatedPlans, entries: updatedEntries, isLoading: false);
    await _persist(updatedPlans, updatedEntries, state.memos);
  }

  /// 导出日程、计划与便签数据为标准 JSON 字符串
  Future<String> exportScheduleDataJson() async {
    // 将计划列表转为可序列化的 Map 集合
    final plansData = state.plans.map((p) => {
      'id': p.id,
      'title': p.title,
      'startDate': p.startDate,
      'dayCount': p.dayCount,
      'reviewOffsets': p.reviewOffsets,
      'createdAt': p.createdAt.toIso8601String(),
      'notes': p.notes,
    }).toList();

    // 将日程条目转为 Map 集合
    final entriesData = state.entries.map((e) => {
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
      'priority': e.priority.name,
      'subTasks': e.subTasks.map((s) => s.toJson()).toList(),
      'isAllDay': e.isAllDay,
    }).toList();

    // 将便签列表转为 Map 集合
    final memosData = state.memos.map((m) => m.toJson()).toList();

    // 组合成标准全量备份对象结构
    final payload = {
      'version': 1,
      'exportTime': DateTime.now().toIso8601String(),
      'plans': plansData,
      'entries': entriesData,
      'memos': memosData,
    };

    // 格式化输出为美观缩进的 JSON
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// 导入日程计划与便签数据接口（支持合并或覆盖）
  /// 返回成功导入/合并的有效记录总数量
  Future<int> importScheduleDataJson(
    String jsonString, {
    bool overwrite = false,
  }) async {
    // 校验输入非空
    if (jsonString.trim().isEmpty) {
      throw const FormatException('导入的数据内容为空');
    }

    // 解码 JSON 结构
    final decoded = jsonDecode(jsonString.trim());
    final List<PlanItem> parsedPlans = [];
    final List<ScheduleEntry> parsedEntries = [];
    final List<MemoItem> parsedMemos = [];

    // 解析计划集合
    if (decoded is Map<String, dynamic> && decoded['plans'] is List) {
      final list = decoded['plans'] as List;
      for (final item in list) {
        if (item is Map<String, dynamic>) {
          parsedPlans.add(
            PlanItem(
              id: item['id'] as String? ?? 'plan_${DateTime.now().microsecondsSinceEpoch}',
              title: item['title'] as String? ?? '未命名计划',
              startDate: item['startDate'] as String? ?? PlanScheduler.formatIsoDate(DateTime.now()),
              dayCount: item['dayCount'] as int? ?? 365,
              reviewOffsets: (item['reviewOffsets'] as List?)?.cast<int>() ?? [1, 2, 4, 7, 15, 30],
              createdAt: item['createdAt'] != null
                  ? DateTime.tryParse(item['createdAt'] as String) ?? DateTime.now()
                  : DateTime.now(),
              notes: item['notes'] as String? ?? '',
            ),
          );
        }
      }
    }

    // 解析日程待办条目集合
    if (decoded is Map<String, dynamic> && decoded['entries'] is List) {
      final list = decoded['entries'] as List;
      for (final item in list) {
        if (item is Map<String, dynamic>) {
          final reminderTimeStr = item['reminderTime'] as String?;
          parsedEntries.add(
            ScheduleEntry(
              id: item['id'] as String? ?? 'entry_${DateTime.now().microsecondsSinceEpoch}',
              planId: item['planId'] as String? ?? 'standalone_single_task',
              title: item['title'] as String? ?? '待办任务',
              scheduledDate: item['scheduledDate'] as String? ?? PlanScheduler.formatIsoDate(DateTime.now()),
              stepIndex: item['stepIndex'] as int? ?? 0,
              kind: ScheduleEntryKind.values.firstWhere(
                (k) => k.name == (item['kind'] as String?),
                orElse: () => ScheduleEntryKind.task,
              ),
              isCompleted: item['isCompleted'] as bool? ?? false,
              originalDueDate: item['originalDueDate'] as String?,
              notes: item['notes'] as String? ?? '',
              reminderTime: reminderTimeStr != null ? DateTime.tryParse(reminderTimeStr) : null,
              hasReminder: item['hasReminder'] as bool? ?? (reminderTimeStr != null),
              reminderMinutesBefore: item['reminderMinutesBefore'] as int? ?? 0,
              repeatRule: ScheduleRepeatRule.values.firstWhere(
                (r) => r.name == (item['repeatRule'] as String?),
                orElse: () => ScheduleRepeatRule.none,
              ),
              priority: SchedulePriority.values.firstWhere(
                (p) => p.name == (item['priority'] as String?),
                orElse: () => SchedulePriority.none,
              ),
              subTasks: (item['subTasks'] as List?)
                      ?.map(SubTaskItem.fromJson)
                      .toList() ??
                  const [],
              isAllDay: item['isAllDay'] as bool? ?? false,
            ),
          );
        }
      }
    }

    // 解析灵感与备忘便签集合
    if (decoded is Map<String, dynamic> && decoded['memos'] is List) {
      final list = decoded['memos'] as List;
      for (final item in list) {
        if (item is Map<String, dynamic>) {
          parsedMemos.add(MemoItem.fromJson(item));
        }
      }
    }

    // 若传入的是单一便签数组形式，进行智能兼容解析
    if (decoded is List) {
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          if (item.containsKey('reviewOffsets')) {
            parsedPlans.add(PlanItem(
              id: item['id'] as String? ?? 'plan_${DateTime.now().microsecondsSinceEpoch}',
              title: item['title'] as String? ?? '导入计划',
              startDate: item['startDate'] as String? ?? PlanScheduler.formatIsoDate(DateTime.now()),
              dayCount: item['dayCount'] as int? ?? 365,
              reviewOffsets: (item['reviewOffsets'] as List?)?.cast<int>() ?? [1, 2, 4, 7, 15, 30],
              createdAt: DateTime.now(),
              notes: item['notes'] as String? ?? '',
            ));
          } else if (item.containsKey('scheduledDate')) {
            parsedEntries.add(ScheduleEntry(
              id: item['id'] as String? ?? 'entry_${DateTime.now().microsecondsSinceEpoch}',
              planId: item['planId'] as String? ?? 'standalone_single_task',
              title: item['title'] as String? ?? '待办任务',
              scheduledDate: item['scheduledDate'] as String? ?? PlanScheduler.formatIsoDate(DateTime.now()),
              stepIndex: item['stepIndex'] as int? ?? 0,
              kind: ScheduleEntryKind.task,
              notes: item['notes'] as String? ?? '',
            ));
          } else if (item.containsKey('content')) {
            parsedMemos.add(MemoItem.fromJson(item));
          }
        }
      }
    }

    // 计算导入的有效数据总量
    final totalCount = parsedPlans.length + parsedEntries.length + parsedMemos.length;
    if (totalCount == 0) {
      throw const FormatException('未识别到有效的日程、计划或便签数据');
    }

    List<PlanItem> finalPlans;
    List<ScheduleEntry> finalEntries;
    List<MemoItem> finalMemos;

    if (overwrite) {
      // 覆盖模式：直接替换现有数据
      finalPlans = parsedPlans;
      finalEntries = parsedEntries;
      finalMemos = parsedMemos;
    } else {
      // 合并模式：按 ID 去重合并
      final planMap = {for (final p in state.plans) p.id: p};
      for (final p in parsedPlans) {
        planMap[p.id] = p;
      }
      finalPlans = planMap.values.toList();

      final entryMap = {for (final e in state.entries) e.id: e};
      for (final e in parsedEntries) {
        entryMap[e.id] = e;
      }
      finalEntries = entryMap.values.toList();

      final memoMap = {for (final m in state.memos) m.id: m};
      for (final m in parsedMemos) {
        memoMap[m.id] = m;
      }
      finalMemos = memoMap.values.toList();
    }

    // 持久化存储到本地
    await _persist(finalPlans, finalEntries, finalMemos);

    // 更新内存状态，刷新页面响应
    state = state.copyWith(
      plans: finalPlans,
      entries: finalEntries,
      memos: finalMemos,
      isLoading: false,
    );

    return totalCount;
  }

  /// 扫描第三方程序自动导入热目录（Auto-Import Hot Folder / Inbox）
  /// [第三方程序对接标准]：外部程序（Python、Node.js、批处理脚本等）只需将符合模板规范的 .json 文件
  /// 复制保存至本应用的 auto_import/ 目录下，应用启动或刷新时将全自动完成静默导入、去重合并入库，
  /// 并自动将原文件重命名为 .imported 归档，彻底免去人工在界面上的点击操作。
  Future<int> scanAndAutoImportHotFolder() async {
    try {
      final List<Directory> candidateDirs = [];

      // 1. 优先扫描桌面端可执行程序所在同级目录下的 auto_import 文件夹（便携与绿色部署友好）
      try {
        final exeFile = File(Platform.resolvedExecutable);
        final exeFolder = Directory(exeFile.parent.path);
        candidateDirs.add(Directory('${exeFolder.path}${Platform.pathSeparator}auto_import'));
      } catch (_) {}

      // 2. 扫描跨平台文档/数据根目录下的 auto_import 文件夹（全平台兼容）
      try {
        final appDir = await appDataRootDirectory();
        candidateDirs.add(Directory('${appDir.path}${Platform.pathSeparator}auto_import'));
      } catch (_) {}

      int totalImportedCount = 0;

      for (final dir in candidateDirs) {
        // 若目录尚不存在，自动创建目录并写入中文对接说明与参考模板
        if (!await dir.exists()) {
          try {
            await dir.create(recursive: true);
            final readmeFile = File('${dir.path}${Platform.pathSeparator}README_导入说明.txt');
            if (!await readmeFile.exists()) {
              await readmeFile.writeAsString(
                '【第三方程序直接导入说明】\r\n'
                '1. 外部程序只需将符合规范的日程与计划 JSON 文件（以 .json 结尾）写入本文件夹。\r\n'
                '2. 本应用启动或重新切回前台时，将自动扫描、校验并安全合并导入。\r\n'
                '3. 导入成功后，本应用会自动将文件改名为 .imported 归档，防止重复导入。\r\n'
              );
            }
          } catch (_) {}
          continue;
        }

        // 检索该目录下所有待处理的 JSON 文件（过滤掉以 .imported 结尾的已归档文件）
        final files = dir.listSync().whereType<File>().where((f) {
          final filename = f.path.split(Platform.pathSeparator).last.toLowerCase();
          return filename.endsWith('.json') && !filename.contains('.imported');
        });

        for (final file in files) {
          try {
            // 读取文件文本内容
            final content = await file.readAsString();
            if (content.trim().isNotEmpty) {
              // 调用底层合并导入接口（保持去重合并安全模式）
              final count = await importScheduleDataJson(content, overwrite: false);
              totalImportedCount += count;
              debugPrint('[AutoImport] 成功自动导入第三方数据文件: ${file.path}, 新增/更新 $count 条记录');

              // 导入成功后重命名为 .imported 归档文件，保证操作幂等
              final archiveName = '${file.path}.${DateTime.now().millisecondsSinceEpoch}.imported';
              await file.rename(archiveName);
            }
          } catch (err) {
            debugPrint('[AutoImport] 解析第三方文件失败 ${file.path}: $err');
          }
        }
      }

      return totalImportedCount;
    } catch (e) {
      debugPrint('[AutoImport] 自动扫描热目录失败: $e');
      return 0;
    }
  }
}
