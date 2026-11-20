import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';

import 'api_client.dart';

class FacebookConnectService {
  FacebookConnectService(this.api);

  final ApiClient api;

  static const List<String> _permissions = [
    'public_profile',
    'pages_show_list',
    'pages_messaging',
    'pages_manage_metadata',
  ];

  /// Gửi user token ngắn hạn 1 lần cho máy chủ đổi sang page token mã hóa và xóa ngay khỏi app.
  Future<List<Map<String, dynamic>>> connect() async {
    LoginResult result;
    try {
      result = await FacebookAuth.instance.login(permissions: _permissions);
    } catch (_) {
      throw const ApiException(
        0,
        'Không mở được đăng nhập Facebook. Kiểm tra ứng dụng Facebook và kết nối mạng.',
      );
    }

    if (result.status == LoginStatus.cancelled) {
      throw const ApiException(0, 'Bạn đã huỷ đăng nhập Facebook.');
    }
    if (result.status != LoginStatus.success) {
      throw const ApiException(
        0,
        'Đăng nhập Facebook chưa thành công. Vui lòng thử lại.',
      );
    }

    final userToken = result.accessToken?.tokenString;
    if (userToken == null || userToken.isEmpty) {
      throw const ApiException(0, 'Không nhận được xác thực từ Facebook.');
    }

    try {
      final body = await api.post(
        '/auth/facebook/exchange-token',
        {'accessToken': userToken},
      );
      final rawPages = body['pages'];
      final pages = rawPages is List
          ? rawPages.whereType<Map<String, dynamic>>().toList()
          : <Map<String, dynamic>>[];
      if (pages.isEmpty) {
        throw const ApiException(
          0,
          'Tài khoản Facebook này chưa quản lý Fanpage nào.',
        );
      }
      return pages;
    } on ApiException catch (e) {
      if (e.message.contains('PAGE_ALREADY_BOUND')) {
        throw const ApiException(
          0,
          'Fanpage này đã được kết nối với một tiệm khác.',
        );
      }
      if (e.message.contains('INVALID_FACEBOOK_TOKEN')) {
        throw const ApiException(
          0,
          'Phiên xác thực Facebook không hợp lệ hoặc đã hết hạn. Vui lòng bấm kết nối lại.',
        );
      }
      rethrow;
    } finally {
      // Xóa token khỏi bộ nhớ ứng dụng ngay sau khi gửi cho máy chủ.
      try {
        await FacebookAuth.instance.logOut();
      } catch (_) {
        // Bỏ qua lỗi dọn phiên cục bộ nếu có.
      }
    }
  }
}
