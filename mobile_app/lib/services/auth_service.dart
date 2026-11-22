import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/errors/user_message.dart';

class AuthSession {
  final String accessToken;
  final String refreshToken;
  final String email;
  final DateTime? expiresAt;

  const AuthSession({
    required this.accessToken,
    this.refreshToken = '',
    required this.email,
    this.expiresAt,
  });

  bool get isExpiringSoon {
    final exp = expiresAt;
    if (exp == null) return false;
    return DateTime.now().isAfter(exp.subtract(const Duration(minutes: 5)));
  }

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'email': email,
        if (expiresAt != null) 'expiresAtMs': expiresAt!.millisecondsSinceEpoch,
      };

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final expMs = json['expiresAtMs'];
    return AuthSession(
      accessToken: (json['accessToken'] ?? '').toString().trim(),
      refreshToken: (json['refreshToken'] ?? '').toString().trim(),
      email: (json['email'] ?? '').toString().trim(),
      expiresAt: expMs is int
          ? DateTime.fromMillisecondsSinceEpoch(expMs)
          : null,
    );
  }
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

  AuthSession _parseSessionResponse(
    Map<String, dynamic> decoded, {
    required String fallbackEmail,
    String fallbackRefreshToken = '',
  }) {
    final accessToken = (decoded['access_token'] ?? '').toString().trim();
    if (accessToken.isEmpty) {
      throw const AuthFailure('Không nhận được phiên đăng nhập hợp lệ.');
    }
    final refreshToken = (decoded['refresh_token'] ?? '').toString().trim();
    final userObj = decoded['user'];
    final userEmail = userObj is Map<String, dynamic>
        ? (userObj['email'] ?? fallbackEmail).toString()
        : fallbackEmail;

    DateTime? expiresAt;
    final rawExpiresAt = decoded['expires_at'];
    final rawExpiresIn = decoded['expires_in'];
    if (rawExpiresAt is num && rawExpiresAt > 0) {
      expiresAt = DateTime.fromMillisecondsSinceEpoch(
        rawExpiresAt.toInt() * 1000,
      );
    } else if (rawExpiresIn is num && rawExpiresIn > 0) {
      expiresAt = DateTime.now().add(Duration(seconds: rawExpiresIn.toInt()));
    }

    return AuthSession(
      accessToken: accessToken,
      refreshToken:
          refreshToken.isNotEmpty ? refreshToken : fallbackRefreshToken,
      email: userEmail,
      expiresAt: expiresAt,
    );
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

    return _parseSessionResponse(decoded, fallbackEmail: cleanEmail);
  }

  /// Làm mới access_token bằng refresh_token.
  /// Trả về null nếu refresh_token đã hết hạn / bị thu hồi (cần đăng nhập lại).
  /// Ném lỗi mạng nếu tạm thời mất kết nối (không tự đăng xuất người dùng).
  Future<AuthSession?> refreshSession(
    String refreshToken, {
    String fallbackEmail = '',
  }) async {
    final cleanRefresh = refreshToken.trim();
    if (cleanRefresh.isEmpty || supabaseAnonKey.trim().isEmpty) return null;

    late final http.Response response;
    try {
      response = await http
          .post(
            _endpoint('/auth/v1/token?grant_type=refresh_token'),
            headers: {
              'Content-Type': 'application/json',
              'apikey': supabaseAnonKey.trim(),
            },
            body: jsonEncode({'refresh_token': cleanRefresh}),
          )
          .timeout(const Duration(seconds: 15));
    } on SocketException {
      throw const SocketException('auth_network_unreachable');
    }

    if (response.statusCode == 400 ||
        response.statusCode == 401 ||
        response.statusCode == 403) {
      return null;
    }
    if (response.statusCode != 200) {
      throw const AuthFailure('Không thể làm mới phiên đăng nhập lúc này.');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return null;
    return _parseSessionResponse(
      decoded,
      fallbackEmail: fallbackEmail,
      fallbackRefreshToken: cleanRefresh,
    );
  }

  Future<void> requestPasswordReset(String email) async {
    final cleanEmail = email.trim();
    if (cleanEmail.isEmpty || !cleanEmail.contains('@')) {
      throw const AuthFailure('Vui lòng nhập địa chỉ Email hợp lệ.');
    }
    if (supabaseAnonKey.trim().isEmpty) {
      throw const AuthFailure(
        'Ứng dụng chưa được cấu hình đầy đủ để gửi email khôi phục.',
      );
    }

    late final http.Response response;
    try {
      response = await http
          .post(
            _endpoint('/auth/v1/recover'),
            headers: {
              'Content-Type': 'application/json',
              'apikey': supabaseAnonKey.trim(),
            },
            body: jsonEncode({'email': cleanEmail}),
          )
          .timeout(const Duration(seconds: 15));
    } on SocketException {
      throw const SocketException('auth_network_unreachable');
    }

    if (response.statusCode == 429) {
      throw const AuthFailure(
        'Bạn vừa gửi yêu cầu đặt lại mật khẩu. Vui lòng chờ ít phút rồi thử lại.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const AuthFailure(
        'Chưa gửi được email đặt lại mật khẩu. Vui lòng thử lại sau.',
      );
    }
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
