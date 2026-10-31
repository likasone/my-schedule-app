import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:node_diary/core/services/reminder_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.jotsy.diary/calendar_reminder');
  final log = <MethodCall>[];

  setUp(() {
    log.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          log.add(methodCall);
          switch (methodCall.method) {
            case 'hasCalendarPermission':
              return true;
            case 'requestCalendarPermission':
              return true;
            case 'createOrUpdateCalendarEvent':
              return 1024; // 模拟返回生成的日历事件 ID
            case 'deleteCalendarEvent':
              return true;
            case 'setExactAlarmClock':
              return true;
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('ReminderService 高穿透日程提醒与系统日历服务测试', () {
    test('hasCalendarPermission 能够通过平台通道正确校验权限状态', () async {
      final service = ReminderService(channel: channel);
      final hasPerm = await service.hasCalendarPermission();
      expect(hasPerm, isTrue);
    });

    test('scheduleCalendarEvent 能够准确传递毫秒时间戳与事件详情', () async {
      final service = ReminderService(channel: channel);
      final testTime = DateTime(2026, 11, 1, 9, 30);
      final item = ReminderItem(
        id: 'rem_01',
        title: '每日艾宾浩斯复习',
        notes: '重点巩固网络并发模型',
        reminderTime: testTime,
        durationMinutes: 45,
      );

      final eventId = await service.scheduleCalendarEvent(item);

      // 验证返回的系统事件 ID
      expect(eventId, equals(1024));

      // 验证平台通道调用参数格式
      expect(
        log.any((call) => call.method == 'createOrUpdateCalendarEvent'),
        isTrue,
      );
      final createCall = log.firstWhere(
        (call) => call.method == 'createOrUpdateCalendarEvent',
      );
      final args = createCall.arguments as Map<dynamic, dynamic>;

      expect(args['title'], equals('每日艾宾浩斯复习'));
      expect(args['notes'], equals('重点巩固网络并发模型'));
      expect(args['durationMinutes'], equals(45));
      expect(args['startTimeMillis'], equals(testTime.millisecondsSinceEpoch));
    });

    test('deleteCalendarEvent 正确调用通道删除日历条目', () async {
      final service = ReminderService(channel: channel);
      final deleted = await service.deleteCalendarEvent(1024);

      expect(deleted, isTrue);
      expect(log.any((call) => call.method == 'deleteCalendarEvent'), isTrue);
      final deleteCall = log.firstWhere(
        (call) => call.method == 'deleteCalendarEvent',
      );
      expect(deleteCall.arguments['eventId'], equals(1024));
    });

    test('scheduleExactAlarmClock 正确调用硬件级闹钟通道', () async {
      final service = ReminderService(channel: channel);
      final testTime = DateTime(2026, 11, 1, 14, 0);

      final result = await service.scheduleExactAlarmClock(
        triggerTime: testTime,
        title: '会议提醒',
        notes: '周一研发周会',
      );

      expect(result, isTrue);
      expect(log.any((call) => call.method == 'setExactAlarmClock'), isTrue);
      final alarmCall = log.firstWhere(
        (call) => call.method == 'setExactAlarmClock',
      );
      expect(alarmCall.arguments['title'], equals('会议提醒'));
      expect(
        alarmCall.arguments['triggerTimeMillis'],
        equals(testTime.millisecondsSinceEpoch),
      );
    });

    test('桌面端回调设置与触发响应', () {
      final service = ReminderService(channel: channel);
      ReminderItem? triggeredItem;

      service.onDesktopReminderTriggered = (item) {
        triggeredItem = item;
      };

      final item = ReminderItem(
        id: 'desktop_test',
        title: '桌面端即时提醒',
        reminderTime: DateTime(2026, 11, 1),
      );

      service.triggerDesktopReminder(item);

      expect(triggeredItem, isNotNull);
      expect(triggeredItem?.id, equals('desktop_test'));
      expect(triggeredItem?.title, equals('桌面端即时提醒'));

      service.dispose();
    });
  });
}
