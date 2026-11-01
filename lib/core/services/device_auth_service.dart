import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:node_diary/core/services/app_platform.dart';

/// 设备身份验证（指纹、面容或锁屏密码）。
///
/// 应用锁与上锁的日记本共用：两处的口径必须一致——设备“支持”指系统能弹出
/// 验证（生物识别或设备凭据任一可用），验证允许回落到锁屏密码
/// （`biometricOnly: false`）。任何插件异常都按“不支持 / 未通过”处理，
/// 调用方不必再包 try/catch。
class DeviceAuthService {
  DeviceAuthService([LocalAuthentication? localAuthentication])
    : _localAuthentication = localAuthentication ?? LocalAuthentication();

  final LocalAuthentication _localAuthentication;

  /// 这台设备能否验证身份：
  /// - 在桌面平台（Windows / Linux）：由于 local_auth_windows 在缺乏物理生物识别传感器时，
  ///   即使有系统密码/PIN，底层调用 authenticate 仍会抛出 NoHardware 异常导致应用死锁；
  ///   因此桌面平台必须严格要求检测到实际生物识别硬件（如指纹仪或红外人脸模组）才判定为支持；
  /// - 在移动平台（Android / iOS）：支持锁屏密码或生物硬件任一可用即可。
  Future<bool> isSupported() async {
    try {
      // 检查物理生物识别传感器硬件支持
      final canBiometrics = await _localAuthentication.canCheckBiometrics;
      if (canBiometrics) {
        return true;
      }
      final available = await _localAuthentication.getAvailableBiometrics();
      if (available.isNotEmpty) {
        return true;
      }
      // 桌面平台（如 Windows / Linux）：若无实体生物硬件，严禁开启生物锁，防止无解死锁
      if (AppPlatform.isDesktop) {
        return false;
      }
      // 移动端若支持设备锁屏密码（PIN/图案）亦可放行
      return await _localAuthentication.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// 弹出系统验证，[reason] 为系统面板上的说明。通过返回 true；取消、失败
  /// 或插件异常返回 false。
  ///
  /// [persistAcrossBackgrounding] 为 true 时，验证中途切到后台再回来系统会
  /// 继续这次验证（应用锁需要），否则视为取消。
  Future<bool> authenticate({
    required String reason,
    bool persistAcrossBackgrounding = true,
  }) async {
    try {
      // 桌面平台若无生物硬件支持直接阻断，避免触发 local_auth_windows 的 NoHardware 异常
      if (AppPlatform.isDesktop) {
        final supported = await isSupported();
        if (!supported) {
          return false;
        }
      }
      return await _localAuthentication.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        sensitiveTransaction: true,
        persistAcrossBackgrounding: persistAcrossBackgrounding,
        authMessages: const <AuthMessages>[
          // Android 原生指纹与生物识别中文提示（全版本通用核心参数）
          AndroidAuthMessages(
            signInTitle: '指纹与安全解锁',
            cancelButton: '取消',
          ),
        ],
      );
    } catch (_) {
      return false;
    }
  }
}

/// 设备身份验证服务；测试覆盖为假的实现。
final deviceAuthServiceProvider = Provider<DeviceAuthService>(
  (Ref ref) => DeviceAuthService(),
);
