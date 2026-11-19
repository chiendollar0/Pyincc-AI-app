import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

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
      throw Exception('Vui lòng nhập đầy đủ Email và Mật khẩu.');
    }
    if (supabaseAnonKey.trim().isEmpty) {
      throw Exception(
        'Chưa cấu hình SUPABASE_ANON_KEY khi khởi chạy ứng dụng.',
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
    } on SocketException catch (e) {
      throw Exception('Không kết nối được máy chủ xác thực: $e');
    }

    if (response.statusCode != 200) {
      throw Exception(
        'Đăng nhập không thành công (HTTP ${response.statusCode}). Vui lòng kiểm tra lại Email hoặc Mật khẩu.',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Phản hồi xác thực không hợp lệ.');
    }

    final accessToken = (decoded['access_token'] ?? '').toString().trim();
    if (accessToken.isEmpty) {
      throw Exception('Không nhận được access_token từ Supabase Auth.');
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
      // Clear local session regardless of network status
    }
  }
}
