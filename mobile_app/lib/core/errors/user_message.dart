// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/api_client.dart';
import '../theme/app_theme.dart';

class AuthFailure implements Exception {
  final String message;

  const AuthFailure(this.message);

  @override
  String toString() => message;
}

String userMessage(Object error) {
  if (error is AuthFailure) {
    return error.message;
  }
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
  if (error is SocketException || error is TimeoutException) {
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
      backgroundColor: isError ? AppColors.primaryDark : AppColors.success,
    ),
  );
}
