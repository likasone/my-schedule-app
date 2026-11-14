import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:node_diary/app/launch_brand_mark.dart';
import 'package:node_diary/app/node_diary_app.dart';
import 'package:node_diary/core/services/third_party_licenses.dart';

Future<void> main(List<String> args) async {
  // 确保 Flutter 原生平台绑定完成
  WidgetsFlutterBinding.ensureInitialized();
  registerThirdPartyLicenses();

  // 检查第三方程序 CLI 命令行直接导入参数（例如：jotsy.exe --import "D:\path\to\template.json"）
  for (int i = 0; i < args.length; i++) {
    final arg = args[i];
    String? filePath;
    if (arg == '--import' && i + 1 < args.length) {
      filePath = args[i + 1];
    } else if (arg.startsWith('--import=')) {
      filePath = arg.substring('--import='.length);
    }
    if (filePath != null && filePath.isNotEmpty) {
      try {
        final srcFile = File(filePath);
        if (srcFile.existsSync()) {
          // 提取可执行文件所在根目录下的 auto_import 热目录
          final exeFolder = Directory(File(Platform.resolvedExecutable).parent.path);
          final hotFolder = Directory('${exeFolder.path}${Platform.pathSeparator}auto_import');
          if (!hotFolder.existsSync()) {
            hotFolder.createSync(recursive: true);
          }
          final destFileName = 'cli_import_${DateTime.now().millisecondsSinceEpoch}_${srcFile.uri.pathSegments.last}';
          // 将目标文件直接暂存至热目录，待日程状态服务加载时全自动安全去重合并入库
          srcFile.copySync('${hotFolder.path}${Platform.pathSeparator}$destFileName');
        }
      } catch (_) {}
    }
  }

  runApp(
    ProviderScope(
      child: NodeDiaryApp(
        launchBrandMark: args.contains(launchBrandMarkEntrypointArg),
      ),
    ),
  );
}
