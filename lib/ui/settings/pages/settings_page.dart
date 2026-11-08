import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:node_diary/l10n/app_localizations.dart';
import 'package:node_diary/ui/settings/pages/appearance_language_page.dart';
import 'package:node_diary/ui/settings/pages/about_page.dart';
import 'package:node_diary/ui/settings/pages/app_features_page.dart';
import 'package:node_diary/ui/settings/pages/data_privacy_page.dart';
import 'package:node_diary/ui/settings/pages/editor_settings_page.dart';
import 'package:node_diary/ui/settings/pages/tag_management_page.dart';
import '../../../app/theme/expressive_surfaces.dart';
import '../../../core/services/app_platform.dart';
import '../../../core/services/app_service.dart';
import '../../../core/services/device_auth_service.dart';
import '../../../core/services/settings_service.dart';
import '../../app_surface/widgets/app_glass_scope.dart';
import '../../app_surface/widgets/app_glass_surface.dart';
import '../../app_surface/widgets/app_page_backdrop.dart';
import '../../home/widgets/home_bar/home_top_bar_surface.dart';
import '../../notebooks/pages/notebooks_page.dart';
import '../../widgets/form_width.dart';
import '../../widgets/page_header.dart';
import '../../../app/theme/app_effects.dart';
import '../controllers/app_update_controller.dart';
import '../providers/app_features_provider.dart';
import '../widgets/app_update_badge.dart';

/// 设置页：按语义分组展示一级入口，降低首屏复杂度。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, this.pageBackgroundColor});

  final Color? pageBackgroundColor;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // 顶栏下缘看得见时（玻璃顶栏，或设置区域有背景、实色栏与透明页面底
    // 分开），第一张卡片紧贴它显得挤：留出四个 Tab 统一的顶部间距，与探索
    // 页、日历页、日记页第一块内容离顶栏一样远。经典且无背景时栏与页面
    // 同色、下缘看不出来，不留，与改版前一致。
    final topContentGap = HomeTopBarSurface.contentGapOf(context);
    final headerHeight =
        MediaQuery.paddingOf(context).top + PageHeader.contentHeight;
    // 玻璃底栏悬浮在内容之上时，底部 padding 是底栏槽位高度（实色时为 0）：
    // 列表滚到胶囊下方，末尾多留这一段让最后一项完整露出。
    final listBottomPadding = 8.0 + MediaQuery.paddingOf(context).bottom;
    // 设置区域设了背景时页面底透明，露出首页画的背景（见 AppPagedBackground）。
    final pageBgColor =
        pageBackgroundColor ?? AppPageBackdrop.pageColorOf(context);

    return Stack(
      children: <Widget>[
        Positioned.fill(child: ColoredBox(color: pageBgColor)),
        // 宽窗口：入口卡片保持一列、最宽 720 并居中（卡片自带左右 16，
        // 列表再补齐其余留白）；手机上补的留白为 0，与原来一致。
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final side = FormWidth.extra(constraints.maxWidth);
            return ListView(
              padding: EdgeInsets.only(
                left: side,
                top: headerHeight + topContentGap,
                right: side,
                bottom: listBottomPadding,
              ),
              children: <Widget>[
                _SettingsDestination(
                  icon: FontAwesomeIcons.palette,
                  title: l10n.settingsAppearanceLanguage,
                  subtitle: l10n.settingsLanguageSubtitle,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (BuildContext context) {
                          return const AppearanceLanguagePage();
                        },
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                _SettingsDestination(
                  icon: FontAwesomeIcons.penNib,
                  title: l10n.settingsEditorTitle,
                  subtitle: l10n.settingsEditorSubtitle,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (BuildContext context) {
                          return const EditorSettingsPage();
                        },
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                _SettingsDestination(
                  icon: FontAwesomeIcons.toggleOn,
                  title: l10n.settingsFeaturesTitle,
                  subtitle: l10n.settingsFeaturesSubtitle,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (BuildContext context) {
                          return const AppFeaturesPage();
                        },
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
                _SettingsDestination(
                  icon: FontAwesomeIcons.tags,
                  title: l10n.settingsTagManagement,
                  subtitle: l10n.settingsTagManagementSubtitle,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (BuildContext context) {
                          return const TagManagementPage();
                        },
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                // 日记本功能关闭时连同其后的间距一起隐藏，避免出现双倍间隔。
                Consumer(
                  builder:
                      (BuildContext context, WidgetRef ref, Widget? child) {
                        final enabled = ref.watch(
                          appFeaturesProvider.select((f) => f.notebooks),
                        );
                        if (!enabled) return const SizedBox.shrink();
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            _SettingsDestination(
                              icon: FontAwesomeIcons.book,
                              title: l10n.notebookTitle,
                              subtitle: l10n.notebookSettingsSubtitle,
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (BuildContext context) {
                                      return const NotebooksPage();
                                    },
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 12),
                          ],
                        );
                      },
                ),
                _SettingsDestination(
                  icon: FontAwesomeIcons.shieldHalved,
                  title: l10n.settingsDataPrivacy,
                  subtitle: l10n.settingsDataPrivacySubtitle,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (BuildContext context) {
                          return const DataPrivacyPage();
                        },
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                // 指纹安全锁卡片：位于数据与隐私之后，在设置首页直接呈现保护状态与切换开关
                const _FingerprintLockCard(),
                const SizedBox(height: 12),
                // 有新版本时在“关于”入口上提示（自动检查或手动检查发现的）。
                Consumer(
                  builder:
                      (BuildContext context, WidgetRef ref, Widget? child) {
                        final hasUpdate = ref.watch(
                          appUpdateControllerProvider.select(
                            (state) => state.hasUpdate,
                          ),
                        );
                        return _SettingsDestination(
                          icon: FontAwesomeIcons.circleInfo,
                          title: l10n.settingsAbout,
                          subtitle: l10n.settingsAboutSubtitle,
                          badge: hasUpdate ? const AppUpdateBadge() : null,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (BuildContext context) {
                                  return const AboutPage();
                                },
                              ),
                            );
                          },
                        );
                      },
                ),
              ],
            );
          },
        ),
        PageHeader(
          title: l10n.settingsTitle,
          contentMaxWidth: FormWidth.maxWidth,
        ),
      ],
    );
  }
}

class _SettingsDestination extends StatelessWidget {
  const _SettingsDestination({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });

  final FaIconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// 显示在右侧箭头之前的标记（如“新版本”）。
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tile = ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.primaryContainer.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(14),
        ),
        child: FaIcon(icon, size: 18, color: colors.onPrimaryContainer),
      ),
      title: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontSize: 16.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (badge != null) ...<Widget>[badge!, const SizedBox(width: 8)],
          FaIcon(
            FontAwesomeIcons.angleRight,
            size: 14,
            color: colors.onSurfaceVariant.withValues(alpha: 0.6),
          ),
        ],
      ),
      onTap: onTap,
    );
    const radius = BorderRadius.all(Radius.circular(20));
    // 玻璃材质时整张卡改为内容玻璃（共用页面背景读取、无背景图不模糊）；
    // 经典分支保持原来的 Card.filled 写法不变。
    if (AppGlass.of(context).isGlass(AppGlassComponent.cards)) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: AppGlassSurface(
          component: AppGlassComponent.cards,
          borderRadius: radius,
          shadow: true,
          child: tile,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: AppEffects.restingCardShadow(colors),
        ),
        child: Card.filled(
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: ExpressiveSurfaces.cardBorderSide(colors),
          ),
          color: ExpressiveSurfaces.cardColor(colors),
          child: tile,
        ),
      ),
    );
  }
}

/// 设置页指纹锁安全卡片组件（Fingerprint Lock Card）
/// 职责：在设置首页直接呈现指纹/生物识别锁状态并支持一键开启或关闭。
/// [技术原理]：
/// 1. 响应式监听 [settingsServiceProvider] 与 [appLockEnabledNotifier]；
/// 2. 状态切换时调用 [DeviceAuthService] 触发操作系统底层生物识别硬件（指纹/面容/凭据）核验；
/// 3. 自适应材质渲染：支持液态玻璃质感（AppGlassSurface）与 Material Expressive 卡片规范。
class _FingerprintLockCard extends ConsumerWidget {
  const _FingerprintLockCard();

  /// 切换指纹保护状态
  /// [安全关键]：无论开启还是解除，均调用硬件级生物识别核验，确保本人操作
  Future<void> _toggleFingerprint(
    BuildContext context,
    WidgetRef ref,
    SettingsService settingsService,
    bool currentEnabled,
  ) async {
    // 获取设备生物识别认证服务实例
    final deviceAuth = ref.read(deviceAuthServiceProvider);
    // 目标状态：当前开启则目标为关闭，当前未开则目标为开启
    final target = !currentEnabled;

    // 开启前先验证底层硬件支持状态
    final isSupported = await deviceAuth.isSupported();
    if (!isSupported) {
      if (!context.mounted) return;
      // 若当前操作是解除应用锁，而设备根本不支持硬件生物识别，直接放行关闭
      if (!target) {
        await settingsService.setAppLockEnabled(false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚠️ 检测到当前设备不支持生物识别，已直接解除应用锁保护')),
        );
        return;
      }
      // 若设备未配备指纹模块或系统未录入指纹，给出直观提醒
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前设备未检测到指纹硬件或尚未在系统设置中录入指纹/密码')),
      );
      return;
    }

    // 调用系统级指纹/生物识别核验弹窗
    final verified = await deviceAuth.authenticate(
      reason: target ? '请验证指纹以开启应用锁保护' : '请验证指纹以解除应用锁保护',
    );

    // 仅在生物识别核验成功通过后才持久化更新配置
    if (verified) {
      await settingsService.setAppLockEnabled(target);
      if (!context.mounted) return;
      // 成功状态提示
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(target ? '✅ 已成功开启指纹锁保护，下次打开应用生效' : '⚠️ 已关闭指纹锁保护'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 获取持久化设置服务实例
    final settingsService = ref.watch(settingsServiceProvider).asData?.value;
    // 获取当前应用主题色彩体系
    final colors = Theme.of(context).colorScheme;
    // 检测当前运行操作系统平台是否支持生物识别
    final supported = AppPlatform.supportsDeviceAuth;

    // 若配置服务初始化中，渲染占位符保持平滑过渡
    if (settingsService == null) {
      return const SizedBox.shrink();
    }

    // 监听应用锁开关状态 Notifier 变更并局部精准重构 UI
    return ValueListenableBuilder<bool>(
      valueListenable: settingsService.appLockEnabledNotifier,
      builder: (BuildContext context, bool enabled, Widget? child) {
        // 当前指纹保护是否有效生效（平台支持且用户开启）
        final isLocked = supported && enabled;

        // 构建 ListTile 卡片核心内容
        final tile = ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          // 左侧指纹高亮图标微容器
          leading: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              // 开启时展现安全绿色半透底色，未开启时展现柔和的主题色
              color: isLocked
                  ? Colors.green.withValues(alpha: 0.15)
                  : colors.primaryContainer.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(14),
            ),
            child: FaIcon(
              FontAwesomeIcons.fingerprint,
              size: 20,
              color: isLocked ? Colors.green : colors.onPrimaryContainer,
            ),
          ),
          // 标题：指纹锁
          title: Text(
            '指纹锁',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontSize: 16.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          // 动态副标题：直观反映当前保护状态
          subtitle: Text(
            !supported
                ? '当前平台不支持本地身份验证'
                : (isLocked ? '已开启保护，进入应用需验证指纹' : '未开启，点击开启以保护隐私与记事'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          // 右侧开关组件
          trailing: Switch(
            value: isLocked,
            onChanged: supported
                ? (_) => _toggleFingerprint(context, ref, settingsService, isLocked)
                : null,
          ),
          // 点击卡片任意非开关区域同样触发指纹安全切换
          onTap: supported
              ? () => _toggleFingerprint(context, ref, settingsService, isLocked)
              : null,
        );

        // 卡片圆角规格：与全局设置卡片一致统一采用 20
        const radius = BorderRadius.all(Radius.circular(20));

        // 玻璃材质时整张卡渲染为内容玻璃（共用全局背景模糊体系）
        if (AppGlass.of(context).isGlass(AppGlassComponent.cards)) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: AppGlassSurface(
              component: AppGlassComponent.cards,
              borderRadius: radius,
              shadow: true,
              child: tile,
            ),
          );
        }

        // 经典材质：Material Expressive 柔和投影与边框体系
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: AppEffects.restingCardShadow(colors),
            ),
            child: Card.filled(
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: ExpressiveSurfaces.cardBorderSide(colors),
              ),
              color: ExpressiveSurfaces.cardColor(colors),
              child: tile,
            ),
          ),
        );
      },
    );
  }
}
