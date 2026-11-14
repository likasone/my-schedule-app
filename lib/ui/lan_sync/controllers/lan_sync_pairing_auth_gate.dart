// 确认配对前的身份验证（docs/lan_sync.md §8）。
//
// - 输入：设备身份验证服务、读取“应用锁是否开启”与书架列表的两个回调、
//   平台是否支持身份验证（默认取 `AppPlatform.supportsDeviceAuth`）；
// - 输出：[LanSyncPairingAuthOutcome]；
// - 副作用：需要时弹出系统身份验证。
//
// 判断时机放在用户点“一致，配对”的那一刻（而不是面板打开时）：应用锁与
// 上锁日记本随时可能被改动，读到的是确认那一刻的状态；不需要验证的绝大
// 多数用户也不会因为面板打开就多读一次数据库。读取失败（设置或书架加载
// 出错）按“需要验证”处理——宁可多验证一次，也不在拿不准时放行。

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/app_platform.dart';
import '../../../core/services/app_service.dart';
import '../../../core/services/device_auth_service.dart';
import '../../app_lock/controllers/identity_verifier.dart';
import '../../notebooks/providers/notebook_providers.dart';
import '../../notebooks/viewmodels/notebook_view.dart';
import '../models/lan_sync_pairing_auth.dart';

/// 见文件头注释。
class LanSyncPairingAuthGate {
  const LanSyncPairingAuthGate({
    this.auth,
    this.verifier,
    required this.loadAppLockEnabled,
    required this.loadNotebooks,
    this.platformSupportsAuth = _platformSupportsAuth,
  });

  // 设备级验证服务（移动端锁屏/指纹回退）
  final DeviceAuthService? auth;
  // 统一身份验证入口（支持桌面端独立应用密码与验证弹窗）
  final IdentityVerifier? verifier;
  // 检查应用锁开关状态的回调
  final Future<bool> Function() loadAppLockEnabled;
  // 获取笔记本视图列表的回调（用于检查是否存在上锁笔记本）
  final Future<List<NotebookView>> Function() loadNotebooks;
  // 检查当前运行平台是否具备身份验证能力
  final bool Function() platformSupportsAuth;

  static bool _platformSupportsAuth() => AppPlatform.supportsDeviceAuth;

  /// 需要时验证身份；[context] 用于应用密码验证弹窗的路由呈现（桌面端/设置应用密码时使用）；
  /// [reason] 为系统验证面板或密码弹窗上的提示文字。
  ///
  /// 验证中途切到后台视为取消（与进入上锁日记本同一口径），回来后由用户重新点“一致，配对”。
  Future<LanSyncPairingAuthOutcome> authorize({
    BuildContext? context,
    required String reason,
  }) async {
    // 平台完全不支持验证时直接放行
    if (!platformSupportsAuth()) return LanSyncPairingAuthOutcome.allowed;
    bool required;
    try {
      // 评估是否开启应用锁或包含隐私上锁笔记本
      required = lanSyncPairingRequiresAuth(
        platformSupportsAuth: true,
        appLockEnabled: await loadAppLockEnabled(),
        notebooks: await loadNotebooks(),
      );
    } catch (_) {
      // 状态读取异常时保守处理，宁可多验证一次也不放行
      required = true;
    }
    if (!required) return LanSyncPairingAuthOutcome.allowed;

    // 优先经由 IdentityVerifier 执行验证（完美覆盖 Windows 桌面端独立密码解锁与移动端指纹）
    if (verifier != null) {
      // 检查当前设备环境验证方式是否就绪（桌面端有密码，或移动端有锁屏）
      final available = await verifier!.isAvailable();
      if (!available) {
        return LanSyncPairingAuthOutcome.unsupported;
      }
      // 若带有有效的 BuildContext，弹出标准应用密码验证页 PasscodeVerifyPage
      if (context != null && context.mounted) {
        final passed = await verifier!.verify(
          context,
          reason: reason,
          purpose: IdentityPurpose.unlock,
        );
        return passed
            ? LanSyncPairingAuthOutcome.allowed
            : LanSyncPairingAuthOutcome.failed;
      }
      // 无 Context 时降级调用系统验证
      final passed = await verifier!.verifySystem(
        reason: reason,
        persistAcrossBackgrounding: false,
      );
      return passed
          ? LanSyncPairingAuthOutcome.allowed
          : LanSyncPairingAuthOutcome.failed;
    }

    // 兼容既有单元测试或仅注入 auth 的场景
    if (auth != null) {
      if (!await auth!.isSupported()) return LanSyncPairingAuthOutcome.unsupported;
      final passed = await auth!.authenticate(
        reason: reason,
        persistAcrossBackgrounding: false,
      );
      return passed
          ? LanSyncPairingAuthOutcome.allowed
          : LanSyncPairingAuthOutcome.failed;
    }

    return LanSyncPairingAuthOutcome.unsupported;
  }
}

/// 配对前的身份验证门；测试覆盖为带假验证服务的实例。
///
/// 书架取 `notebooksProvider` 的当前一份（它在应用里常驻订阅，通常已经
/// 加载好）；日记本功能关闭时上锁的本子仍然存在、仍会随同步交出去，所以
/// 照样计入。
final lanSyncPairingAuthGateProvider = Provider<LanSyncPairingAuthGate>((
  Ref ref,
) {
  return LanSyncPairingAuthGate(
    auth: ref.read(deviceAuthServiceProvider),
    verifier: ref.read(identityVerifierProvider),
    loadAppLockEnabled: () async =>
        (await ref.read(settingsServiceProvider.future)).isAppLockEnabled,
    loadNotebooks: () => ref.read(notebooksProvider.future),
  );
});
