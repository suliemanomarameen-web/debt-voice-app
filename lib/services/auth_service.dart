import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static final _auth = LocalAuthentication();
  static const _keyEnabled = 'biometric_enabled';

  static Future<bool> isEnabled() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_keyEnabled) ?? false;
  }

  static Future<void> setEnabled(bool value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_keyEnabled, value);
  }

  static Future<bool> canUseBiometrics() async {
    try {
      final supported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      return supported && canCheck;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> authenticate({String reason = 'افتح دفتر الديون'}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
          useErrorDialogs: true,
        ),
      );
    } on PlatformException {
      return false;
    }
  }
}
