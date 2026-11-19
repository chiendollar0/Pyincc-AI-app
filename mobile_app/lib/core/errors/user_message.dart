// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'api_exception.dart';

class AuthFailure implements Exception {
  final String message;

  const AuthFailure(this.message);

  @override
  String toString() => message;
}

String userMessage(Object error) {
  if (error is AuthFailure) return error.message;
  if (error is FormatException) return error.message;
  if (error is ApiException) {
    if (error.status == 0) return error.message;
    switch (error.status) {
      case 401:
        return 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.';
      case 403:
        return 'Tài khoản của bạn chưa có quyền thực hiện thao tác này.';
      case 404:
        return 'Không tìm thấy dữ liệu. Có thể đã bị xoá.';
      case 409:
        return 'Thao tác này đang được xử lý hoặc đã hoàn tất.';
      case 413:
        return 'Ảnh quá lớn. Vui lòng chọn ảnh nhỏ hơn.';
      case 415:
        return 'Định dạng ảnh chưa được hỗ trợ. Vui lòng dùng JPG, PNG hoặc WebP.';
      case 422:
        if (error.message.contains('OUTSIDE_24H_WINDOW')) {
          return 'Đã quá khung 24 giờ kể từ tin nhắn cuối của khách. Cần chờ khách nhắn lại.';
        }
        return 'Chưa có Fanpage hoặc mã khách để gửi. Vui lòng kiểm tra lại.';
      case 429:
        return 'Đã đạt giới hạn trong 24 giờ. Vui lòng thử lại sau.';
      case 501:
        return 'Tính năng này đang được hoàn thiện.';
      case 502:
      case 503:
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
