// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'api_exception.dart';
import 'image_prepare_exception.dart';

class AuthFailure implements Exception {
  final String message;

  const AuthFailure(this.message);

  @override
  String toString() => message;
}

String userMessage(Object error) {
  if (error is AuthFailure) return error.message;
  if (error is ImagePrepareException) return error.message;
  if (error is ApiException) {
    if (error.status == 0) return error.message;
    switch (error.status) {
      case 400:
        if (error.message.contains('CANNOT_MODIFY_SELF')) {
          return 'Bạn không thể tự thay đổi quyền hoặc thu hồi chính tài khoản của mình.';
        }
        if (error.message.contains('INVITATION_NOT_ACCEPTED')) {
          return 'Nhân viên chưa đăng nhập nhận lời mời nên chưa thể kích hoạt lại.';
        }
        return 'Thông tin gửi lên chưa hợp lệ. Vui lòng kiểm tra lại.';
      case 401:
        return 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.';
      case 403:
        if (error.message.contains('SELF_APPROVAL_NOT_ALLOWED')) {
          return 'Nhân viên không thể tự duyệt ảnh do mình tạo. Vui lòng nhờ Chủ tiệm hoặc nhân viên khác duyệt.';
        }
        if (error.message.contains('NOT_APPROVED')) {
          return 'Ca tư vấn chưa được duyệt. Vui lòng duyệt nội dung trước khi gửi.';
        }
        return 'Tài khoản của bạn chưa có quyền thực hiện thao tác này.';
      case 404:
        return 'Không tìm thấy dữ liệu. Có thể đã bị xoá.';
      case 409:
        if (error.message.contains('INVITATION_ALREADY_EXISTS')) {
          return 'Lời mời cho nhân viên này đang chờ xác nhận.';
        }
        if (error.message.contains('LAST_OWNER_PROTECTED')) {
          return 'Không thể hạ quyền hoặc thu hồi Chủ tiệm cuối cùng của tiệm.';
        }
        if (error.message.contains('ALREADY_SENDING')) {
          return 'Tin nhắn này đang được gửi hoặc đã gửi thành công trước đó.';
        }
        return 'Thao tác này đang được xử lý hoặc đã hoàn tất.';
      case 413:
        return 'Ảnh quá lớn. Vui lòng chọn ảnh nhỏ hơn.';
      case 415:
        return 'Định dạng ảnh chưa được hỗ trợ. Vui lòng dùng JPG, PNG hoặc WebP.';
      case 422:
        if (error.message.contains('OUTSIDE_24H_WINDOW')) {
          return 'Đã quá khung 24 giờ kể từ tin nhắn cuối của khách. Cần chờ khách nhắn lại.';
        }
        if (error.message.contains('NO_RECIPIENT')) {
          return 'Ca chụp tại tiệm chưa gắn với hội thoại Messenger nên chỉ dùng để duyệt nội bộ hoặc sao chép.';
        }
        if (error.message.contains('MISSING_PAGE_CONTEXT') ||
            error.message.contains('PAGE_MISMATCH')) {
          return 'Thiếu thông tin Fanpage của hội thoại này. Vui lòng mở lại từ tin nhắn khách.';
        }
        return 'Chưa có Fanpage hoặc mã khách để gửi. Vui lòng kiểm tra lại.';
      case 429:
        if (error.message.contains('AI_DAILY_CAP')) {
          return 'Tiệm đã đạt giới hạn 50 lượt phân tích AI trong hôm nay. Hạn mức sẽ mở lại vào ngày mai.';
        }
        return 'Đã đạt giới hạn trong 24 giờ. Vui lòng thử lại sau.';
      case 501:
        return 'Tính năng này đang được hoàn thiện.';
      case 502:
      case 503:
        if (error.message.contains('GEMINI_NOT_CONFIGURED')) {
          return 'Máy chủ chưa cấu hình dịch vụ phân tích AI. Vui lòng liên hệ quản trị viên.';
        }
        return 'Hệ thống tạm thời gián đoạn. Vui lòng thử lại sau ít phút.';
    }
    return 'Có lỗi xảy ra. Vui lòng thử lại.';
  }
  if (error is SocketException ||
      error is TimeoutException ||
      error is HttpException) {
    return 'Không kết nối được máy chủ. Kiểm tra mạng và thử lại.';
  }
  return 'Có lỗi xảy ra. Vui lòng thử lại.';
}

void showAppMessage(
  BuildContext context,
  String text, {
  bool isError = false,
}) {
  final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(text),
      backgroundColor: isError ? AppColors.danger : AppColors.success,
    ),
  );
}
