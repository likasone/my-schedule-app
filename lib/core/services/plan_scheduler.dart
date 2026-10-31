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

  /// 复制并更新部分属性
  ScheduleEntry copyWith({
    bool? isCompleted,
    DateTime? completedAt,
    ReviewFeedback? feedback,
    String? scheduledDate,
    String? originalDueDate,
    String? notes,
  }) {
    return ScheduleEntry(
      id: id,
      planId: planId,
      title: title,
      scheduledDate: scheduledDate ?? this.scheduledDate,
      stepIndex: stepIndex,
      kind: kind,
      isCompleted: isCompleted ?? this.isCompleted,
      completedAt: completedAt ?? this.completedAt,
      feedback: feedback ?? this.feedback,
      originalDueDate: originalDueDate ?? this.originalDueDate,
      notes: notes ?? this.notes,
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
        startDate: plan.startDate,
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
}
