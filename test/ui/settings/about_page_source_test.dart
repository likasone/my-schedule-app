import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('about page focuses cleanly on update, changelog and licenses', () async {
    final source = await File(
      'lib/ui/settings/pages/about_page.dart',
    ).readAsString();

    // 核心信息与入口
    expect(source, contains("static const String _appName = 'Jotsy'"));
    expect(source, contains('_CheckUpdateTile()'));
    expect(source, contains('ChangelogPage()'));
    expect(source, contains('showLicensePage('));
    expect(source, contains('aboutFooterCopyright'));

    // 验证多余原作者外部渠道已彻底剔除
    expect(source, isNot(contains('_qqFeedbackGroupNumber')));
    expect(source, isNot(contains('FontAwesomeIcons.qq')));
    expect(source, isNot(contains('showSupportDeveloperSheet')));
    expect(source, isNot(contains('_showPrivacyDialog')));
    expect(source, isNot(contains('_repoUrl')));
    expect(source, isNot(contains('_issueUrl')));
  });
}
