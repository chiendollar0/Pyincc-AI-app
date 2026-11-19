import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/errors/user_message.dart';

class AuthSession {
  final String accessToken;
  final String email;

  const AuthSession({
    required this.accessToken,
    required this.email,
  });
}

class AuthService {
  final String supabaseUrl;
  final String supabaseAnonKey;

  const AuthService({
    required this.supabaseUrl,
    required this.supabaseAnonKey,
  });

  Uri _endpoint(String path) {
    final base = supabaseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$base$path');
  }

  Future<AuthSession> signInWithPassword({
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim();
    if (cleanEmail.isEmpty || password.isEmpty) {
      throw const AuthFailure('Vui lòng nhập đầy đủ Email và Mật khẩu.');
    }
    if (supabaseAnonKey.trim().isEmpty) {
      throw const AuthFailure(
        'Ứng dụng chưa được cấu hình đầy đủ để đăng nhập.',
      );
    }

    late final http.Response response;
    try {
      response = await http
          .post(
            _endpoint('/auth/v1/token?grant_type=password'),
            headers: {
              'Content-Type': 'application/json',
              'apikey': supabaseAnonKey.trim(),
            },
            body: jsonEncode({
              'email': cleanEmail,
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 15));
    } on SocketException {
      throw const SocketException('auth_network_unreachable');
    }

    if (response.statusCode == 400 || response.statusCode == 401) {
      throw const AuthFailure('Email hoặc mật khẩu chưa đúng.');
    }
    if (response.statusCode != 200) {
      throw const AuthFailure(
        'Hệ thống xác thực tạm thời gián đoạn. Vui lòng thử lại sau.',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const AuthFailure('Không thể đọc dữ liệu phiên đăng nhập.');
    }

    final accessToken = (decoded['access_token'] ?? '').toString().trim();
    if (accessToken.isEmpty) {
      throw const AuthFailure('Không nhận được phiên đăng nhập hợp lệ.');
    }

    final userObj = decoded['user'];
    final userEmail = userObj is Map<String, dynamic>
        ? (userObj['email'] ?? cleanEmail).toString()
        : cleanEmail;

    return AuthSession(
      accessToken: accessToken,
      email: userEmail,
    );
  }

  Future<void> signOut(String accessToken) async {
    if (accessToken.trim().isEmpty || supabaseAnonKey.trim().isEmpty) return;
    try {
      await http
          .post(
            _endpoint('/auth/v1/logout'),
            headers: {
              'apikey': supabaseAnonKey.trim(),
              'Authorization': 'Bearer ${accessToken.trim()}',
            },
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Luôn dọn phiên cục bộ dù không có mạng
    }
  }
}
