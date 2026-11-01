import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:node_diary/l10n/app_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../app/theme/app_radii.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/expressive_surfaces.dart';
import '../../app_surface/widgets/app_glass_scope.dart';
import '../../app_surface/widgets/app_glass_surface.dart';
import '../../../app/theme/app_effects.dart';
import '../../widgets/expressive_image_frame.dart';
import '../controllers/app_update_controller.dart';
import '../models/app_update_state.dart';
import '../widgets/app_update_badge.dart';
import 'app_update_page.dart';
import 'changelog_page.dart';
import '../../widgets/form_width.dart';
import 'package:node_diary/ui/app_surface/models/app_surface_enums.dart';
import 'package:node_diary/ui/app_surface/widgets/app_page_background.dart';

/// 关于页面：以阅读化卡片布局展示应用版本、核心更新入口与开源许可协议。
class AboutPage extends ConsumerStatefulWidget {
  const AboutPage({super.key});

  /// 应用显示名称
  static const String _appName = 'Jotsy';

  /// 应用图标静态资产路径
  static const String _appIconAssetPath = 'assets/app_icon/mingcute_icon.png';

  /// 异步获取当前平台编译的应用版本号与构建号
  static Future<String> _loadAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (info.buildNumber.trim().isEmpty) {
      return info.version;
    }
    return '${info.version}+${info.buildNumber}';
  }

  @override
  ConsumerState<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends ConsumerState<AboutPage> {
  /// 缓存版本号 Future，防止页面重绘时重复触发异步平台通道读取
  late final Future<String> _appVersionFuture;

  @override
  void initState() {
    super.initState();
    // 初始化时一次性加载应用版本号
    _appVersionFuture = AboutPage._loadAppVersion();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _appVersionFuture,
      builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
        final appVersion = snapshot.data ?? '--';
        return _buildContent(context, appVersion: appVersion);
      },
    );
  }

  /// 构建页面主体结构
  Widget _buildContent(BuildContext context, {required String appVersion}) {
    final l10n = context.l10n;
    final textTheme = Theme.of(context).textTheme;
    final topSafeInset = MediaQuery.paddingOf(context).top;
    final bottomSafeInset = MediaQuery.paddingOf(context).bottom;
    final contentTopPadding =
        topSafeInset + _AboutHeader.contentHeight + AppSpacing.m;

    return AppPageBackground(
      area: AppBackgroundArea.settings,
      child: Builder(
        builder: (BuildContext context) => Scaffold(
          backgroundColor: AppPageBackdrop.pageColorOf(context),
          body: Stack(
            children: <Widget>[
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final side = FormWidth.gutter(constraints.maxWidth);
                  return CustomScrollView(
                    slivers: <Widget>[
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          side,
                          contentTopPadding,
                          side,
                          0,
                        ),
                        sliver: SliverList.list(
                          children: <Widget>[
                            // 1. 顶部应用品牌卡片：展示图标、应用名称、版本号与标语
                            _SectionCard(
                              child: Builder(
                                builder: (BuildContext context) {
                                  final colorScheme = Theme.of(
                                    context,
                                  ).colorScheme;
                                  return Column(
                                    children: <Widget>[
                                      // 应用图标容器
                                      Container(
                                        width: 92,
                                        height: 92,
                                        decoration: BoxDecoration(
                                          color: colorScheme
                                              .surfaceContainerHighest,
                                          borderRadius: BorderRadius.circular(
                                            28,
                                          ),
                                        ),
                                        alignment: Alignment.center,
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          child: Image.asset(
                                            AboutPage._appIconAssetPath,
                                            width: 72,
                                            height: 72,
                                            fit: BoxFit.cover,
                                            frameBuilder:
                                                expressiveImageFrameBuilder,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      // 应用名称
                                      Text(
                                        AboutPage._appName,
                                        style: textTheme.headlineSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      const SizedBox(height: 6),
                                      // 应用版本号
                                      Text(
                                        '${l10n.aboutVersion} $appVersion',
                                        style: textTheme.bodySmall?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      // 品牌标语 Slogan
                                      Text(
                                        l10n.aboutPageSlogan,
                                        textAlign: TextAlign.center,
                                        style: textTheme.bodyMedium?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                          height: 1.5,
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 14),
                            // 2. 核心操作列表卡片：聚焦软件更新、更新日志与开源协议
                            _SectionCard(
                              padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                              child: Column(
                                children: <Widget>[
                                  // 检查最新版本
                                  const _CheckUpdateTile(),
                                  const Divider(height: 1),
                                  // 更新日志入口
                                  _AboutActionTile(
                                    icon: FontAwesomeIcons.clockRotateLeft,
                                    title: l10n.aboutChangelog,
                                    onTap: () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (BuildContext context) =>
                                            const ChangelogPage(),
                                      ),
                                    ),
                                  ),
                                  const Divider(height: 1),
                                  // 第三方开源组件与协议入口
                                  _AboutActionTile(
                                    icon: FontAwesomeIcons.fileContract,
                                    title: l10n.aboutOpenSourceLicenses,
                                    onTap: () {
                                      showLicensePage(
                                        context: context,
                                        applicationName: AboutPage._appName,
                                        applicationVersion: appVersion,
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 3. 底部版权信息
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            AppSpacing.xl,
                            AppSpacing.l,
                            AppSpacing.xl,
                            AppSpacing.l + bottomSafeInset,
                          ),
                          child: Builder(
                            builder: (BuildContext context) {
                              final colorScheme = Theme.of(context).colorScheme;
                              return Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: <Widget>[
                                  Text(
                                    l10n.aboutFooterCopyright,
                                    style: textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              // 固定顶部导航返回栏
              _AboutHeader(
                title: l10n.aboutTitle,
                onBack: () => Navigator.of(context).maybePop(),
                backTooltip: l10n.commonBack,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 关于页面顶部导航栏组件
class _AboutHeader extends StatelessWidget {
  const _AboutHeader({
    required this.title,
    required this.onBack,
    required this.backTooltip,
  });

  static const double contentHeight = 56;

  final String title;
  final VoidCallback onBack;
  final String backTooltip;

  @override
  Widget build(BuildContext context) {
    final topSafeInset = MediaQuery.paddingOf(context).top;
    final textTheme = Theme.of(context).textTheme;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: ColoredBox(
        // 实色顶栏：设了纯色背景时与页面同色，图片背景时保持不透明
        color: AppPageBackdrop.solidBarColorOf(context),
        child: Padding(
          padding: EdgeInsets.only(top: topSafeInset),
          child: SizedBox(
            height: contentHeight,
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) =>
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal:
                          AppSpacing.m + FormWidth.extra(constraints.maxWidth),
                    ),
                    child: Row(
                      children: <Widget>[
                        // 返回按钮
                        IconButton(
                          tooltip: backTooltip,
                          onPressed: onBack,
                          icon: const FaIcon(
                            FontAwesomeIcons.angleLeft,
                            size: 18,
                          ),
                        ),
                        // 居中标题
                        Expanded(
                          child: Center(
                            child: Text(
                              title,
                              style: textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 通用分组卡片组件，支持毛玻璃与经典表面
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(12, 12, 12, 12),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // 毛玻璃材质分支
    if (AppGlass.of(context).isGlass(AppGlassComponent.cards)) {
      return AppGlassSurface(
        component: AppGlassComponent.cards,
        borderRadius: const BorderRadius.all(Radius.circular(AppRadii.card)),
        shadow: true,
        child: Padding(padding: padding, child: child),
      );
    }
    // 经典 Material 实体卡片分支
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.card),
        boxShadow: AppEffects.restingCardShadow(colorScheme),
      ),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: ExpressiveSurfaces.cardColor(colorScheme),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: ExpressiveSurfaces.cardBorderSide(colorScheme),
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// “检查更新”行：打开软件更新页；副标题随全局更新状态动态提示
class _CheckUpdateTile extends ConsumerWidget {
  const _CheckUpdateTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(appUpdateControllerProvider);
    final release = state.release;
    final fraction = state.progress?.fraction;
    final String? subtitle = switch (state.phase) {
      AppUpdatePhase.downloading when fraction != null =>
        l10n.aboutUpdateSubtitleDownloading((fraction * 100).floor()),
      AppUpdatePhase.readyToInstall => l10n.aboutUpdateSubtitleReady,
      AppUpdatePhase.upToDate => l10n.appUpdateUpToDate,
      _ when state.hasUpdate && release != null =>
        l10n.aboutUpdateSubtitleAvailable('v${release.version.name}'),
      _ => null,
    };
    return _AboutActionTile(
      icon: FontAwesomeIcons.arrowsRotate,
      title: l10n.aboutCheckUpdate,
      subtitle: subtitle,
      trailing: state.hasUpdate
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const AppUpdateBadge(),
                const SizedBox(width: 8),
                FaIcon(
                  FontAwesomeIcons.angleRight,
                  size: 15,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            )
          : null,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => const AppUpdatePage(),
        ),
      ),
    );
  }
}

/// 通用操作行组件
class _AboutActionTile extends StatelessWidget {
  const _AboutActionTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.onTap,
  });

  final FaIconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final iconColor = colorScheme.onSurfaceVariant;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 18, 6, 18),
        child: Row(
          children: <Widget>[
            // 左侧图标
            SizedBox(
              width: 34,
              child: FaIcon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 10),
            // 中间标题与副标题
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            // 右侧尾随部件（默认向右箭头）
            trailing ??
                FaIcon(FontAwesomeIcons.angleRight, size: 15, color: iconColor),
          ],
        ),
      ),
    );
  }
}
