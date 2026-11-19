import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';

import 'api_client.dart';

class FacebookConnectService {
  FacebookConnectService(this.api);

  final ApiClient api;

  // Giai đoạn 1 chỉ xin quyền đọc danh sách Fanpage; pages_messaging thuộc giai đoạn 2.
  static const List<String> _permissions = ['public_profile', 'pages_show_list'];

  /// Gửi user token ngắn hạn 1 lần cho máy chủ đổi sang page token mã hóa và xóa ngay khỏi app.
  Future<List<Map<String, dynamic>>> connect() async {
    final result = await FacebookAuth.instance.login(permissions: _permissions);

    if (result.status == LoginStatus.cancelled) {
      throw const ApiException(0, 'Bạn đã huỷ đăng nhập Facebook.');
    }
    if (result.status != LoginStatus.success) {
      throw const ApiException(
        0,
        'Đăng nhập Facebook chưa thành công. Vui lòng thử lại hoặc kiểm tra quyền tài khoản.',
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
      if (rawPages is List) {
        return rawPages.whereType<Map<String, dynamic>>().toList();
      }
      return const [];
    } finally {
      // Xóa token khỏi bộ nhớ ứng dụng ngay sau khi gửi cho máy chủ.
      try {
        await FacebookAuth.instance.logOut();
      } catch (_) {
        // Bỏ qua lỗi dọn phiên cục bộ nếu có
      }
    }
  }
}
