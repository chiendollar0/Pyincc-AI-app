import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../core/errors/image_prepare_exception.dart';

export '../core/errors/image_prepare_exception.dart';

img.Decoder? _selectDecoder(Uint8List raw) {
  if (raw.length >= 3 && raw[0] == 0xFF && raw[1] == 0xD8 && raw[2] == 0xFF) {
    return img.JpegDecoder();
  }
  if (raw.length >= 8 &&
      raw[0] == 0x89 &&
      raw[1] == 0x50 &&
      raw[2] == 0x4E &&
      raw[3] == 0x47 &&
      raw[4] == 0x0D &&
      raw[5] == 0x0A &&
      raw[6] == 0x1A &&
      raw[7] == 0x0A) {
    return img.PngDecoder();
  }
  if (raw.length >= 12 &&
      raw[0] == 0x52 &&
      raw[1] == 0x49 &&
      raw[2] == 0x46 &&
      raw[3] == 0x46 &&
      raw[8] == 0x57 &&
      raw[9] == 0x45 &&
      raw[10] == 0x42 &&
      raw[11] == 0x50) {
    return img.WebPDecoder();
  }
  return null;
}

img.Image _fitLongestSide(img.Image source, int maxSide) {
  final longest = source.width > source.height ? source.width : source.height;
  if (longest <= maxSide) return source;
  return source.width >= source.height
      ? img.copyResize(
          source,
          width: maxSide,
          interpolation: img.Interpolation.average,
        )
      : img.copyResize(
          source,
          height: maxSide,
          interpolation: img.Interpolation.average,
        );
}

Uint8List _processImageBytes(Uint8List raw) {
  final decoder = _selectDecoder(raw);
  if (decoder == null) {
    throw const ImagePrepareException(
      'Định dạng ảnh chưa được hỗ trợ. Vui lòng dùng JPG, PNG hoặc WebP.',
    );
  }

  final img.DecodeInfo? info;
  try {
    info = decoder.startDecode(raw);
  } catch (_) {
    throw const ImagePrepareException(
      'Không đọc được ảnh. Vui lòng chọn ảnh khác.',
    );
  }

  if (info == null || info.width <= 0 || info.height <= 0) {
    throw const ImagePrepareException(
      'Không đọc được ảnh. Vui lòng chọn ảnh khác.',
    );
  }

  if (info.width * info.height > ImagePreprocessor.maxPixels) {
    throw const ImagePrepareException(
      'Ảnh quá lớn. Vui lòng chụp lại ở độ phân giải thấp hơn.',
    );
  }

  final img.Image? decoded;
  try {
    decoded = decoder.decodeFrame(0);
  } catch (_) {
    throw const ImagePrepareException(
      'Không đọc được ảnh. Vui lòng chọn ảnh khác.',
    );
  }

  if (decoded == null) {
    throw const ImagePrepareException(
      'Không đọc được ảnh. Vui lòng chọn ảnh khác.',
    );
  }

  // Áp dụng xoay theo EXIF rồi tạo ảnh RGB mới không mang EXIF/GPS/ICC metadata.
  final oriented = img.bakeOrientation(decoded);
  final rgb = oriented.convert(format: img.Format.uint8, numChannels: 3);
  final pixels = rgb.toUint8List();
  final clean = img.Image.fromBytes(
    width: rgb.width,
    height: rgb.height,
    bytes: pixels.buffer,
    bytesOffset: pixels.offsetInBytes,
    numChannels: 3,
    format: img.Format.uint8,
  );

  for (final side in const [ImagePreprocessor.maxSide, 768, 512]) {
    final resized = _fitLongestSide(clean, side);
    for (final quality in const [85, 75, 65]) {
      final bytes = Uint8List.fromList(img.encodeJpg(resized, quality: quality));
      if (bytes.length <= ImagePreprocessor.maxBytes) {
        return bytes;
      }
    }
  }

  throw const ImagePrepareException(
    'Ảnh quá phức tạp để xử lý. Vui lòng chụp lại.',
  );
}

class ImagePreprocessor {
  static const int maxSide = 1024;
  static const int maxBytes = 1500 * 1024; // 1.5 MB sau khi nén
  static const int maxPixels = 24 * 1000 * 1000; // 24 MP tối đa trước khi decode

  /// Trả về JPEG đã xoay đúng chiều, không metadata (EXIF/GPS/ICC), cạnh dài tối đa 1024 px.
  static Future<Uint8List> prepare(File file) async {
    final raw = await file.readAsBytes();
    return compute(_processImageBytes, raw);
  }

  @visibleForTesting
  static Uint8List processBytesForTest(Uint8List raw) => _processImageBytes(raw);
}
