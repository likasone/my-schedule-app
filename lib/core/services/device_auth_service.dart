import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:node_diary/core/services/app_platform.dart';

/// 设备身份验证结果封装模型。
///
/// 区分“用户核验未通过/取消”与“设备硬件缺失/系统未配置/插件调用异常”。
class DeviceAuthResult {
  const DeviceAuthResult({
    required this.isSuccess,
    this.isHardwareUnavailable = false,
    this.errorCode,
  });

  /// 身份核验是否成功通过（指纹/面容/凭据匹配成功）
  final bool isSuccess;

  /// 是否因硬件缺失、系统未录入凭证或平台不支持导致验证根本无法唤起
  final bool isHardwareUnavailable;

  /// 底层平台抛出的错误代码（若有）
  final String? errorCode;
}

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

  /// 这台设备能否验证身份：系统级凭据（Windows Hello / PIN / 锁屏密码）或生物识别任一可用即可。
  Future<bool> isSupported() async {
    try {
      if (await _localAuthentication.isDeviceSupported()) {
        return true;
      }
      return await _localAuthentication.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  /// 弹出系统验证，返回包含详细硬件可用性状态的结果对象 [DeviceAuthResult]。
  ///
  /// 在桌面平台（Windows / Linux / macOS）：若设备缺少指纹模组或未设置 Windows Hello，
  /// 会将 [DeviceAuthResult.isHardwareUnavailable] 标为 true，避免将环境不可用误判为密码错误。
  Future<DeviceAuthResult> authenticateWithResult({
    required String reason,
    bool persistAcrossBackgrounding = true,
  }) async {
    try {
      final success = await _localAuthentication.authenticate(
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
      return DeviceAuthResult(isSuccess: success);
    } on PlatformException catch (e) {
      // 常见硬件缺失与未配置的系统异常代码
      const unavailableCodes = {
        'NotAvailable',
        'PasscodeNotSet',
        'NotEnrolled',
        'DeviceNotPresent',
        'NotConfiguredForUser',
        'no_biometrics_available',
        'DisabledByPolicy',
      };
      final isUnavailable =
          unavailableCodes.contains(e.code) || AppPlatform.isDesktop;
      return DeviceAuthResult(
        isSuccess: false,
        isHardwareUnavailable: isUnavailable,
        errorCode: e.code,
      );
    } catch (e) {
      return DeviceAuthResult(
        isSuccess: false,
        isHardwareUnavailable: AppPlatform.isDesktop,
        errorCode: e.toString(),
      );
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
    final result = await authenticateWithResult(
      reason: reason,
      persistAcrossBackgrounding: persistAcrossBackgrounding,
    );
    return result.isSuccess;
  }
}

/// 设备身份验证服务；测试覆盖为假的实现。
final deviceAuthServiceProvider = Provider<DeviceAuthService>(
  (Ref ref) => DeviceAuthService(),
);
