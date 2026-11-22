import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'auth_service.dart';

class SessionStorage {
  static const String _sessionKey = 'pyincc_auth_session_v1';

  const SessionStorage({FlutterSecureStorage? storage}) : _storage = storage;

  final FlutterSecureStorage? _storage;

  FlutterSecureStorage get _client =>
      _storage ??
      const FlutterSecureStorage(
        aOptions: AndroidOptions(
          encryptedSharedPreferences: true,
          resetOnError: true,
        ),
      );

  Future<AuthSession?> read() async {
    try {
      final raw = await _client.read(key: _sessionKey);
      if (raw == null || raw.trim().isEmpty) return null;
      final parsed = jsonDecode(raw);
      if (parsed is! Map<String, dynamic>) return null;
      final session = AuthSession.fromJson(parsed);
      if (session.accessToken.isEmpty && session.refreshToken.isEmpty) {
        return null;
      }
      return session;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(AuthSession session) async {
    try {
      await _client.write(
        key: _sessionKey,
        value: jsonEncode(session.toJson()),
      );
    } on MissingPluginException {
      // Bỏ qua trong môi trường widget test không có plugin native
    } on PlatformException {
      // Không để lỗi lưu khóa làm gián đoạn phiên đăng nhập hiện tại
    } catch (_) {
      // Bỏ qua lỗi ghi cục bộ
    }
  }

  Future<void> clear() async {
    try {
      await _client.delete(key: _sessionKey);
    } on MissingPluginException {
      // Bỏ qua trong môi trường widget test
    } on PlatformException {
      // Bỏ qua lỗi xóa cục bộ
    } catch (_) {
      // Bỏ qua lỗi xóa cục bộ
    }
  }
}
