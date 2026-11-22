import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';

class SessionStorage {
  static const String _sessionKey = 'pyincc_auth_session_v1';

  const SessionStorage();

  Future<AuthSession?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_sessionKey);
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_sessionKey, jsonEncode(session.toJson()));
    } on MissingPluginException {
      // Bỏ qua trong môi trường widget test không có plugin native
    } on PlatformException {
      // Không để lỗi lưu cục bộ làm gián đoạn phiên đăng nhập hiện tại
    } catch (_) {
      // Bỏ qua lỗi ghi cục bộ
    }
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_sessionKey);
    } on MissingPluginException {
      // Bỏ qua trong môi trường widget test
    } on PlatformException {
      // Bỏ qua lỗi xóa cục bộ
    } catch (_) {
      // Bỏ qua lỗi xóa cục bộ
    }
  }
}
