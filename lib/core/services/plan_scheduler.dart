import 'package:flutter/foundation.dart';

/// 计划与学习排程类型（Plan Kind）
enum PlanKind {
  /// 艾宾浩斯遗忘曲线学习计划（包含新学、阶段复习与遗忘补救）
  learning,

  /// 日常打卡与周期性习惯（Routine）
  routine,

  /// 普通待办清单（Todo / Task）
  task,
}

/// 阶段复习记忆反馈等级（Review Feedback）
enum ReviewFeedback {
  /// 牢固记住（Remembered）：按原定间隔推进至下一阶段
  remembered,

  /// 记忆模糊（Fuzzy）：自适应插入轻度复习缓冲（2天后）
  fuzzy,

  /// 完全遗忘（Forgotten）：触发自适应强力补救（1天后立即重新复习）
  forgotten,
}

/// 计划调度条目类型（Schedule Entry Kind）
enum ScheduleEntryKind {
  /// 初次学习（New）
  initial,

  /// 周期性艾宾浩斯复习（Review）
  review,

  /// 遗忘自适应补救节点（Remedial）
  remedial,

  /// 普通待办执行项（Task）
  task,
}

/// 日程重复周期规则（Schedule Repeat Rule）
enum ScheduleRepeatRule {
  /// 不重复（单次任务）
  none,

  /// 每天重复（日常习惯、每日例行任务）
  daily,

  /// 工作日重复（周一至周五，工作会议、上班待办）
  workdays,

  /// 每周重复（按周循环）
  weekly,

  /// 每月重复（按月循环，如每月账单、月度报告）
  monthly;

  /// 中文展示文案
  String get label => switch (this) {
    ScheduleRepeatRule.none => '不重复',
    ScheduleRepeatRule.daily => '每天',
    ScheduleRepeatRule.workdays => '工作日(周一至周五)',
    ScheduleRepeatRule.weekly => '每周',
    ScheduleRepeatRule.monthly => '每月',
  };

  /// RFC 5545 格式的 RRULE 规则字符串，供写入安卓系统原生日历与小米 HyperOS
  String? get rrule => switch (this) {
    ScheduleRepeatRule.none => null,
    ScheduleRepeatRule.daily => 'FREQ=DAILY',
    ScheduleRepeatRule.workdays => 'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR',
    ScheduleRepeatRule.weekly => 'FREQ=WEEKLY',
    ScheduleRepeatRule.monthly => 'FREQ=MONTHLY',
  };
}

/// 日程重要度与优先级（Schedule Priority）
enum SchedulePriority {
  /// 普通无特殊标记
  none,

  /// 低优先级（绿色，灵活安排）
  low,

  /// 中优先级（黄色，日常重点）
  medium,

  /// 高优先级（红色，重要紧急）
  high;

  /// 中文标签
  String get label => switch (this) {
    SchedulePriority.none => '无优先级',
    SchedulePriority.low => '低优先级',
    SchedulePriority.medium => '中优先级',
    SchedulePriority.high => '高优先级',
  };
}

/// 子待办项清单模型（Sub Task Checklist Item）
@immutable
class SubTaskItem {
  const SubTaskItem({
    required this.id,
    required this.title,
    this.isCompleted = false,
  });

  /// 子任务唯一标识符
  final String id;

  /// 子任务简明标题
  final String title;

  /// 是否已完成勾选
  final bool isCompleted;

  /// 拷贝并更新属性
  SubTaskItem copyWith({
    String? id,
    String? title,
    bool? isCompleted,
  }) {
    return SubTaskItem(
      id: id ?? this.id,
      title: title ?? this.title,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }

  /// 序列化为 Map
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'isCompleted': isCompleted,
  };

  /// 反序列化容错解析
  factory SubTaskItem.fromJson(dynamic json) {
    if (json is Map<String, dynamic>) {
      return SubTaskItem(
        id: json['id'] as String? ?? 'sub_${DateTime.now().microsecondsSinceEpoch}',
        title: json['title'] as String? ?? '',
        isCompleted: json['isCompleted'] as bool? ?? false,
      );
    }
    return SubTaskItem(
      id: 'sub_${DateTime.now().microsecondsSinceEpoch}',
      title: json.toString(),
      isCompleted: false,
    );
  }
}

/// 单项计划实体模型（Plan Item）
@immutable
class PlanItem {
  const PlanItem({
    required this.id,
    required this.title,
    required this.startDate,
    this.dayCount = 365,
    this.reviewOffsets = const [1, 2, 4, 7, 15, 30],
    this.kind = PlanKind.learning,
    required this.createdAt,
    this.tags = const [],
    this.notes = '',
  });

  /// 计划唯一标识符（UUID / String）
  final String id;

  /// 计划标题或知识点主题
  final String title;

  /// 计划起始基准日期（格式：YYYY-MM-DD）
  final String startDate;

  /// 计划有效总天数（默认 365 天）
  final int dayCount;

  /// 经典艾宾浩斯复习第 N 天列表（例如：[1, 2, 4, 7, 15, 30]）
  final List<int> reviewOffsets;

  /// 计划属性分类
  final PlanKind kind;

  /// 创建时间戳
  final DateTime createdAt;

  /// 标签分组
  final List<String> tags;

  /// 补充说明或备注
  final String notes;

  /// 拷贝并更新计划属性
  PlanItem copyWith({
    String? title,
    String? startDate,
    int? dayCount,
    List<int>? reviewOffsets,
    PlanKind? kind,
    List<String>? tags,
    String? notes,
  }) {
    return PlanItem(
      id: id,
      title: title ?? this.title,
      startDate: startDate ?? this.startDate,
      dayCount: dayCount ?? this.dayCount,
      reviewOffsets: reviewOffsets ?? this.reviewOffsets,
      kind: kind ?? this.kind,
      createdAt: createdAt,
      tags: tags ?? this.tags,
      notes: notes ?? this.notes,
    );
  }
}

/// 单次排程节点明细实体（Schedule Entry）
@immutable
class ScheduleEntry {
  const ScheduleEntry({
    required this.id,
    required this.planId,
    required this.title,
    required this.scheduledDate,
    required this.stepIndex,
    required this.kind,
    this.isCompleted = false,
    this.completedAt,
    this.feedback,
    this.originalDueDate,
    this.notes = '',
    this.reminderTime,
    this.hasReminder = false,
    this.reminderMinutesBefore = 0,
    this.repeatRule = ScheduleRepeatRule.none,
    this.priority = SchedulePriority.none,
    this.subTasks = const [],
    this.isAllDay = false,
  });

  /// 排程节点唯一标识
  final String id;

  /// 关联的计划 ID
  final String planId;

  /// 任务节点标题
  final String title;

  /// 安排执行的具体日期（YYYY-MM-DD）
  final String scheduledDate;

  /// 阶段步骤序号（0 代表第 1 天初学，后续为各级复习阶段）
  final int stepIndex;

  /// 排程类型
  final ScheduleEntryKind kind;

  /// 是否已经完成打卡 / 复习
  final bool isCompleted;

  /// 实际打卡完成时间戳
  final DateTime? completedAt;

  /// 用户记忆反馈状态
  final ReviewFeedback? feedback;

  /// 若产生逾期顺延，此字段记录原定到期日
  final String? originalDueDate;

  /// 阶段笔记或反思总结
  final String notes;

  /// 设定提醒的具体时间戳（含时分秒）
  final DateTime? reminderTime;

  /// 是否激活定时强提醒（闹钟与日历事件）
  final bool hasReminder;

  /// 提前多少分钟发起提醒（默认 0 为准时提醒）
  final int reminderMinutesBefore;

  /// 重复周期规则（不重复、每天、工作日、每周、每月）
  final ScheduleRepeatRule repeatRule;

  /// 任务优先级（无/低/中/高，参考小米待办设计）
  final SchedulePriority priority;

  /// 子任务清单（Checklist 子待办，支持逐步核销）
  final List<SubTaskItem> subTasks;

  /// 是否为全天日程（全天不强绑定具体分钟，准点提醒）
  final bool isAllDay;

  /// 复制并更新部分属性
  ScheduleEntry copyWith({
    String? title,
    bool? isCompleted,
    DateTime? completedAt,
    ReviewFeedback? feedback,
    String? scheduledDate,
    String? originalDueDate,
    bool clearOriginalDueDate = false,
    String? notes,
    DateTime? reminderTime,
    bool? hasReminder,
    int? reminderMinutesBefore,
    ScheduleRepeatRule? repeatRule,
    SchedulePriority? priority,
    List<SubTaskItem>? subTasks,
    bool? isAllDay,
  }) {
    return ScheduleEntry(
      id: id,
      planId: planId,
      title: title ?? this.title,
      scheduledDate: scheduledDate ?? this.scheduledDate,
      stepIndex: stepIndex,
      kind: kind,
      isCompleted: isCompleted ?? this.isCompleted,
      completedAt: completedAt ?? this.completedAt,
      feedback: feedback ?? this.feedback,
      originalDueDate: clearOriginalDueDate ? null : (originalDueDate ?? this.originalDueDate),
      notes: notes ?? this.notes,
      reminderTime: reminderTime ?? this.reminderTime,
      hasReminder: hasReminder ?? this.hasReminder,
      reminderMinutesBefore: reminderMinutesBefore ?? this.reminderMinutesBefore,
      repeatRule: repeatRule ?? this.repeatRule,
      priority: priority ?? this.priority,
      subTasks: subTasks ?? this.subTasks,
      isAllDay: isAllDay ?? this.isAllDay,
    );
  }
}

/// 艾宾浩斯复习周期排程与计划引擎（Plan Scheduler Engine）
/// 严格继承自 Mnemo 核心算法，为 Windows 与 Android 提供跨端原生的智能复习推导。
class PlanScheduler {
  /// 艾宾浩斯经典复习曲线默认推荐间隔天数（第 1, 2, 4, 7, 15, 30 天）
  static const List<int> classicReviewDays = [1, 2, 4, 7, 15, 30];

  /// 日期标准格式转换辅助：将 DateTime 转为 YYYY-MM-DD 字符串
  static String formatIsoDate(DateTime date) {
    // 补齐两位数月份与日期，确保国际标准化对齐
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  /// 日期解析辅助：将 YYYY-MM-DD 字符串转为本地 0 点的 DateTime
  static DateTime parseIsoDate(String isoDate) {
    final parts = isoDate.split('-');
    // 提取年月日数值构建纯本地无时区偏差的起始时间点
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final day = int.parse(parts[2]);
    return DateTime(year, month, day);
  }

  /// 增加指定天数运算
  static String addDays(String isoDate, int days) {
    final base = parseIsoDate(isoDate);
    // 依据 Duration 计算跨月跨年平滑偏移
    final next = base.add(Duration(days: days));
    return formatIsoDate(next);
  }

  /// 计算下一个重复周期的有效日期（ISO 格式：YYYY-MM-DD）
  static String calculateNextRepeatDate(String currentIsoDate, ScheduleRepeatRule rule) {
    final current = parseIsoDate(currentIsoDate);
    switch (rule) {
      case ScheduleRepeatRule.none:
        return currentIsoDate;
      case ScheduleRepeatRule.daily:
        // 每日重复：直接递增 1 天
        return formatIsoDate(current.add(const Duration(days: 1)));
      case ScheduleRepeatRule.workdays:
        // 工作日重复：周五顺延到下周一，周六顺延到下周一，其余递增 1 天
        var next = current.add(const Duration(days: 1));
        if (next.weekday == DateTime.saturday) {
          next = next.add(const Duration(days: 2));
        } else if (next.weekday == DateTime.sunday) {
          next = next.add(const Duration(days: 1));
        }
        return formatIsoDate(next);
      case ScheduleRepeatRule.weekly:
        // 每周重复：自然递增 7 天
        return formatIsoDate(current.add(const Duration(days: 7)));
      case ScheduleRepeatRule.monthly:
        // 每月重复：自然递增 1 个月，并防止月末天数越界
        final year = current.month == 12 ? current.year + 1 : current.year;
        final month = current.month == 12 ? 1 : current.month + 1;
        final daysInNextMonth = DateTime(year, month + 1, 0).day;
        final day = current.day > daysInNextMonth ? daysInNextMonth : current.day;
        return formatIsoDate(DateTime(year, month, day));
    }
  }

  /// 计算两个 ISO 日期之间的绝对天数差值（后一个减前一个）
  static int daysBetween(String startIso, String endIso) {
    final start = parseIsoDate(startIso);
    final end = parseIsoDate(endIso);
    // 精确取整毫秒差并换算为标准天数
    return end.difference(start).inDays;
  }

  /// 校验指定日期是否在计划的有效天数覆盖范围内
  static bool isDateInsidePlan({
    required String startDate,
    required int dayCount,
    required String targetDate,
  }) {
    final offset = daysBetween(startDate, targetDate);
    // 目标日期必须在起始日当天或之后，且小于总有效天数跨度
    return offset >= 0 && offset < dayCount;
  }

  /// 将第 N 天的自然天数（如 [1, 2, 4, 7...]）转化为相对首日的偏移量（如 [0, 1, 3, 6...]）
  static List<int> calculateDayOffsets(List<int> reviewDays) {
    final sorted = List<int>.from(reviewDays)..sort();
    // 首日学习为第 1 天，对应偏移 0 天；后续天数依此递减 1
    return sorted.map((day) => (day > 0 ? day - 1 : 0)).toList();
  }

  /// 根据艾宾浩斯曲线为单项计划生成全套排程节点（Initial & Reviews）
  static List<ScheduleEntry> generateInitialSchedule({
    required PlanItem plan,
    String? customStartDate,
  }) {
    final start = customStartDate ?? plan.startDate;
    final offsets = calculateDayOffsets(
      plan.reviewOffsets.isEmpty ? classicReviewDays : plan.reviewOffsets,
    );
    final entries = <ScheduleEntry>[];

    for (var i = 0; i < offsets.length; i++) {
      final offsetDays = offsets[i];
      // 计算出该阶段的实际执行到期日
      final scheduledDate = addDays(start, offsetDays);

      // 超过计划最大生命周期上限的节点自动截断
      if (!isDateInsidePlan(
        startDate: start,
        dayCount: plan.dayCount,
        targetDate: scheduledDate,
      )) {
        break;
      }

      // 第 0 步为初次学习，后续步骤标记为艾宾浩斯阶段复习
      final entryKind = (plan.kind == PlanKind.learning)
          ? (i == 0 ? ScheduleEntryKind.initial : ScheduleEntryKind.review)
          : ScheduleEntryKind.task;

      entries.add(
        ScheduleEntry(
          id: '${plan.id}_step_${i}_${scheduledDate.replaceAll('-', '')}',
          planId: plan.id,
          title: '${plan.title} (第 ${i + 1} 阶段)',
          scheduledDate: scheduledDate,
          stepIndex: i,
          kind: entryKind,
          isCompleted: false,
        ),
      );
    }

    return entries;
  }

  /// 自适应遗忘调整算法：根据复习打卡反馈生成补充或推迟节点
  /// - forgotten (遗忘)：于第二天生成高优先级补救节点（Remedial）
  /// - fuzzy (模糊)：顺延该节点 2 天后重新验证
  /// - remembered (牢固)：按原节奏顺利打卡完成
  static ScheduleEntry? handleFeedbackAndAdaptiveReschedule({
    required ScheduleEntry currentEntry,
    required ReviewFeedback feedback,
    required String todayIso,
  }) {
    if (feedback == ReviewFeedback.forgotten) {
      // 产生次日补救节点：帮助强化突发性遗忘知识点
      final remedialDate = addDays(todayIso, 1);
      return ScheduleEntry(
        id: '${currentEntry.planId}_remedial_${DateTime.now().millisecondsSinceEpoch}',
        planId: currentEntry.planId,
        title: '【强化补救】${currentEntry.title}',
        scheduledDate: remedialDate,
        stepIndex: currentEntry.stepIndex,
        kind: ScheduleEntryKind.remedial,
        isCompleted: false,
        originalDueDate: currentEntry.scheduledDate,
        notes: '自适应算法因上一次标记【遗忘】而触发的重点复习项',
      );
    }

    // 模糊或通过不需要新增补救条目，由调用方直接更新当前节点状态
    return null;
  }

  /// 逾期自动前移机制（Overdue Carried to Today）：
  /// 过去未打卡的待办/复习条目，在今日视图中平滑浮现并标注原逾期日期，防止任务断层遗漏。
  static List<ScheduleEntry> resolveDailyViewEntries({
    required List<ScheduleEntry> allEntries,
    required String todayIso,
  }) {
    final result = <ScheduleEntry>[];

    for (final entry in allEntries) {
      if (entry.isCompleted) {
        // 已完成的历史条目：按实际安排日期归档展示
        if (entry.scheduledDate == todayIso) {
          result.add(entry);
        }
      } else {
        // 未完成条目：若到期日已早于今天（发生逾期），自动将其前移至今天，并记录原到期日
        if (entry.scheduledDate == todayIso) {
          result.add(entry);
        } else if (daysBetween(entry.scheduledDate, todayIso) > 0) {
          result.add(
            entry.copyWith(
              scheduledDate: todayIso,
              originalDueDate: entry.originalDueDate ?? entry.scheduledDate,
            ),
          );
        }
      }
    }

    return result;
  }

  /// 计算单个计划的总体完成进度百分比 (0.0 ~ 1.0)
  static double calculatePlanProgress(List<ScheduleEntry> planEntries) {
    if (planEntries.isEmpty) return 0.0;
    // 统计已完成条目数量并计算精确比例
    final completedCount = planEntries.where((e) => e.isCompleted).length;
    return completedCount / planEntries.length;
  }

  /// 筛选指定目标日期的待办/复习条目列表（默认携带历史逾期条目平滑前移至今天）
  static List<ScheduleEntry> filterEntriesForDate({
    required List<ScheduleEntry> allEntries,
    required String targetDateIso,
    bool includeOverdue = true,
  }) {
    if (includeOverdue) {
      return resolveDailyViewEntries(
        allEntries: allEntries,
        todayIso: targetDateIso,
      );
    }
    return allEntries.where((e) => e.scheduledDate == targetDateIso).toList();
  }
}

/// 闪念与随手记事便签实体模型（Memo Item）
/// 参考花笺（Floral Notepaper）美学设计，融合信笺拟真纸色与沉浸式随笔灵感。
@immutable
class MemoItem {
  const MemoItem({
    required this.id,
    required this.content,
    required this.createdAt,
    this.title = '',
    this.colorIndex = 0,
    this.updatedAt,
    this.isPinned = false,
    this.tag = '闪念',
    this.scheduledDate,
  });

  /// 便签唯一标识符
  final String id;

  /// 便签标题（花笺拟真信笺标题，可选）
  final String title;

  /// 花笺拟真低饱和纸色索引（0: 霜白, 1: 樱落, 2: 竹韵, 3: 麦穗, 4: 晴川, 5: 暮薰）
  final int colorIndex;

  /// 便签内容文本（支持多行随想、待办灵感、Markdown 格式）
  final String content;

  /// 创建时间戳
  final DateTime createdAt;

  /// 最后修改更新时间戳
  final DateTime? updatedAt;

  /// 是否置顶显示
  final bool isPinned;

  /// 分类标签（如：闪念、灵感、待办、备忘、随想）
  final String tag;

  /// 若已转化为日程待办，记录转入的目标执行日期（YYYY-MM-DD）
  final String? scheduledDate;

  /// 转换为 JSON 存储 Map
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'colorIndex': colorIndex,
    'content': content,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
    'isPinned': isPinned,
    'tag': tag,
    'scheduledDate': scheduledDate,
  };

  /// 从 JSON 容错反序列化，无缝兼容旧版本的纯文本 String 格式
  factory MemoItem.fromJson(dynamic json) {
    if (json is String) {
      return MemoItem(
        id: 'memo_${json.hashCode.abs()}',
        content: json,
        createdAt: DateTime.now(),
      );
    }
    if (json is Map<String, dynamic>) {
      return MemoItem(
        id: json['id'] as String? ?? 'memo_${DateTime.now().millisecondsSinceEpoch}',
        title: json['title'] as String? ?? '',
        colorIndex: json['colorIndex'] as int? ?? 0,
        content: json['content'] as String? ?? '',
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
            : DateTime.now(),
        updatedAt: json['updatedAt'] != null
            ? DateTime.tryParse(json['updatedAt'] as String)
            : null,
        isPinned: json['isPinned'] as bool? ?? false,
        tag: json['tag'] as String? ?? '闪念',
        scheduledDate: json['scheduledDate'] as String?,
      );
    }
    return MemoItem(
      id: 'memo_${DateTime.now().millisecondsSinceEpoch}',
      content: json.toString(),
      createdAt: DateTime.now(),
    );
  }

  /// 拷贝并更新属性
  MemoItem copyWith({
    String? title,
    int? colorIndex,
    String? content,
    DateTime? updatedAt,
    bool? isPinned,
    String? tag,
    String? scheduledDate,
  }) {
    return MemoItem(
      id: id,
      title: title ?? this.title,
      colorIndex: colorIndex ?? this.colorIndex,
      content: content ?? this.content,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isPinned: isPinned ?? this.isPinned,
      tag: tag ?? this.tag,
      scheduledDate: scheduledDate ?? this.scheduledDate,
    );
  }
}
