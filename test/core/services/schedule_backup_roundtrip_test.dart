import 'package:flutter_test/flutter_test.dart';
import 'package:node_diary/core/services/backup_settings.dart';
import 'package:node_diary/core/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('日程与计划数据在备份及 WebDAV 同步中的导出与恢复闭环测试', () {
    test('BackupSettings 能够完整捕获并还原日程、艾宾浩斯计划与随手记事数据', () async {
      // 1. 初始化 Mock 持久化存储环境
      SharedPreferences.setMockInitialValues({
        'app_schedule_plans_v1': '[{"id":"plan_001","title":"计算机系统导论"}]',
        'app_schedule_entries_v1':
            '[{"id":"entry_001","title":"初学第一章","isCompleted":true}]',
        'app_schedule_memos_v1': '["临时备忘：准备演讲稿"]',
      });

      final settingsService = await SettingsService.create();

      // 2. 执行备份提取（Capture），验证数据被完整抓取
      final captured = BackupSettings.capture(settingsService);
      expect(
        captured['schedulePlansRaw'],
        equals('[{"id":"plan_001","title":"计算机系统导论"}]'),
      );
      expect(
        captured['scheduleEntriesRaw'],
        equals('[{"id":"entry_001","title":"初学第一章","isCompleted":true}]'),
      );
      expect(captured['scheduleMemosRaw'], equals('["临时备忘：准备演讲稿"]'));

      // 3. 清理当前数据模拟在新设备或恢复场景
      await settingsService.setSchedulePlansRaw(null);
      await settingsService.setScheduleEntriesRaw(null);
      await settingsService.setScheduleMemosRaw(null);

      expect(settingsService.schedulePlansRaw, isNull);
      expect(settingsService.scheduleEntriesRaw, isNull);
      expect(settingsService.scheduleMemosRaw, isNull);

      // 4. 执行还原恢复（Restore）
      await BackupSettings.restore(settingsService, captured);

      // 5. 验证数据已 100% 恢复
      expect(
        settingsService.schedulePlansRaw,
        equals('[{"id":"plan_001","title":"计算机系统导论"}]'),
      );
      expect(
        settingsService.scheduleEntriesRaw,
        equals('[{"id":"entry_001","title":"初学第一章","isCompleted":true}]'),
      );
      expect(
        settingsService.scheduleMemosRaw,
        equals('["临时备忘：准备演讲稿"]'),
      );
    });
  });
}
