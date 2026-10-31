import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 日程提醒项配置模型（Reminder Request）
@immutable
class ReminderItem {
  const ReminderItem({
    required this.id,
    required this.title,
    this.notes = '',
    required this.reminderTime,
    this.durationMinutes = 30,
    this.calendarEventId,
    this.rrule,
  });

  /// 业务层提醒标识
  final String id;

  /// 提醒标题（如：复习 Flutter 异步模型、重要会议）
  final String title;

  /// 详细备注或知识要点
  final String notes;

  /// 设定提醒的时间点
  final DateTime reminderTime;

  /// 日程占用时长（分钟）
  final int durationMinutes;

  /// 关联的系统原生日历事件 ID（若已同步至日历）
  final int? calendarEventId;

  /// RFC 5545 循环规则（如 FREQ=DAILY, FREQ=WEEKLY 等）
  final String? rrule;

  /// 拷贝并更新字段
  ReminderItem copyWith({
    int? calendarEventId,
    DateTime? reminderTime,
    String? title,
    String? notes,
    String? rrule,
  }) {
    return ReminderItem(
      id: id,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      reminderTime: reminderTime ?? this.reminderTime,
      durationMinutes: durationMinutes,
      calendarEventId: calendarEventId ?? this.calendarEventId,
      rrule: rrule ?? this.rrule,
    );
  }
}

/// 跨平台高穿透日程提醒服务（Reminder Service）
///
/// 特性与核心机制：
/// 1. Android 端（含小米 HyperOS / MIUI、华为 HarmonyOS、vivo OriginOS 等）：
///    - 采用系统日历提供者（CalendarProvider）写入系统日程，利用系统级日历不可杀的特权实现 100% 穿透保活；
///    - 辅助使用硬件级闹钟（AlarmManager.setAlarmClock）拉起前台全屏警报，状态栏常驻闹钟图标。
/// 2. Windows 桌面端：
///    - 桌面运行期间维护内存优先级的定时器队列，支持准时弹窗与系统托盘消息通知。
class ReminderService {
  ReminderService({MethodChannel? channel})
    : _channel =
          channel ??
          const MethodChannel('com.jotsy.diary/calendar_reminder');

  final MethodChannel _channel;

  /// 桌面端运行时的内存定时提醒队列
  final Map<String, Timer> _activeTimers = {};

  /// 桌面端提醒触发回调函数（供 UI 层弹窗监听）
  void Function(ReminderItem reminder)? onDesktopReminderTriggered;

  /// 判断当前平台是否为 Android
  bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// 判断当前平台是否为 Windows 桌面端
  bool get isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  /// 检查当前是否已获得系统日历读写权限（仅 Android 生效，桌面端默认返回 true）
  Future<bool> hasCalendarPermission() async {
    if (!isAndroid) return true;
    try {
      final result = await _channel.invokeMethod<bool>('hasCalendarPermission');
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('检查日历权限异常: ${e.message}');
      return false;
    }
  }

  /// 向用户申请系统日历读写权限
  Future<bool> requestCalendarPermission() async {
    if (!isAndroid) return true;
    try {
      final result = await _channel.invokeMethod<bool>(
        'requestCalendarPermission',
      );
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('申请日历权限异常: ${e.message}');
      return false;
    }
  }

  /// 写入或更新系统日历事件（借力小米/安卓系统日历原生强提醒）
  /// 返回写入成功的系统 Calendar Event ID；失败或不支持时返回 null。
  Future<int?> scheduleCalendarEvent(ReminderItem item) async {
    if (!isAndroid) {
      // 桌面端进入轻量定时调度逻辑
      _scheduleDesktopTimer(item);
      return null;
    }

    try {
      // 校验并请求日历权限
      final hasPermission = await hasCalendarPermission();
      if (!hasPermission) {
        final granted = await requestCalendarPermission();
        if (!granted) {
          debugPrint('用户拒绝日历权限，无法写入系统日历');
          return null;
        }
      }

      // 将 DateTime 转换为 Unix 毫秒时间戳传给 Kotlin 原生层
      final startTimeMillis = item.reminderTime.millisecondsSinceEpoch;
      final eventId = await _channel.invokeMethod<int>(
        'createOrUpdateCalendarEvent',
        <String, dynamic>{
          'title': item.title,
          'notes': item.notes,
          'startTimeMillis': startTimeMillis,
          'durationMinutes': item.durationMinutes,
          'existingEventId': item.calendarEventId,
          'rrule': item.rrule,
        },
      );

      return eventId;
    } on PlatformException catch (e) {
      debugPrint('创建系统日历事件失败: ${e.message}');
      return null;
    }
  }

  /// 从系统日历中删除日程事件
  Future<bool> deleteCalendarEvent(int calendarEventId) async {
    if (!isAndroid) return true;
    try {
      final result = await _channel.invokeMethod<bool>('deleteCalendarEvent', <
        String,
        dynamic
      >{'eventId': calendarEventId});
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('删除系统日历事件失败: ${e.message}');
      return false;
    }
  }

  /// 触发高穿透硬件级闹钟（AlarmManager.setAlarmClock）
  /// 在 Android 系统状态栏点亮闹钟标识，能够穿透系统低电耗模式（Doze Mode）
  Future<bool> scheduleExactAlarmClock({
    required DateTime triggerTime,
    required String title,
    String notes = '',
  }) async {
    if (!isAndroid) return true;

    try {
      final triggerMillis = triggerTime.millisecondsSinceEpoch;
      final result = await _channel.invokeMethod<bool>('setExactAlarmClock', <
        String,
        dynamic
      >{
        'triggerTimeMillis': triggerMillis,
        'title': title,
        'notes': notes,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('设置高精度闹钟失败: ${e.message}');
      return false;
    }
  }

  /// 统一调度接口：整合系统日历与高穿透闹钟
  Future<ReminderItem> scheduleComprehensiveReminder(ReminderItem item) async {
    var updated = item;

    // 1. 若支持且处于 Android，同步写入系统日历（获取免杀系统级提醒）
    if (isAndroid) {
      final eventId = await scheduleCalendarEvent(item);
      if (eventId != null) {
        updated = updated.copyWith(calendarEventId: eventId);
      }

      // 2. 辅助挂载精确系统闹钟
      await scheduleExactAlarmClock(
        triggerTime: item.reminderTime,
        title: item.title,
        notes: item.notes,
      );
    } else {
      // 3. 桌面端（Windows）启用本地定时调度
      _scheduleDesktopTimer(item);
    }

    return updated;
  }

  /// 取消指定的提醒与定时器
  Future<void> cancelReminder(ReminderItem item) async {
    // 清除桌面端计时器
    final existingTimer = _activeTimers.remove(item.id);
    existingTimer?.cancel();

    // Android 端清除系统日历关联项
    if (isAndroid && item.calendarEventId != null) {
      await deleteCalendarEvent(item.calendarEventId!);
    }
  }

  /// 桌面端内部计时调度实现
  void _scheduleDesktopTimer(ReminderItem item) {
    // 移除原有计时器
    _activeTimers[item.id]?.cancel();

    final now = DateTime.now();
    final difference = item.reminderTime.difference(now);

    // 已逾期的时间点不启动计时
    if (difference.isNegative) return;

    _activeTimers[item.id] = Timer(difference, () {
      _activeTimers.remove(item.id);
      // 触发桌面端提醒广播
      onDesktopReminderTriggered?.call(item);
    });
  }

  /// 供测试与即时预览验证桌面端提醒响应
  // @visibleForTesting 注释保留，允许UI测试触发
  void triggerDesktopReminder(ReminderItem item) {
    onDesktopReminderTriggered?.call(item);
  }

  /// 释放与销毁所有正在等待的定时任务
  void dispose() {
    for (final timer in _activeTimers.values) {
      timer.cancel();
    }
    _activeTimers.clear();
  }
}

/// Riverpod 全局单例依赖注入 Provider
final reminderServiceProvider = Provider<ReminderService>((Ref ref) {
  final service = ReminderService();
  ref.onDispose(() => service.dispose());
  return service;
});
