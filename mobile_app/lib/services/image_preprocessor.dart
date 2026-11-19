import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

class ImagePreprocessor {
  static const int maxSide = 1024;
  static const int maxBytes = 1500 * 1024; // 1.5 MB sau khi nén

  /// Trả về JPEG đã xoay đúng chiều, không metadata, cạnh dài tối đa 1024 px.
  static Future<Uint8List> prepare(File file) async {
    final raw = await file.readAsBytes();
    final decoded = img.decodeImage(raw);
    if (decoded == null) {
      throw const FormatException('Không đọc được ảnh. Vui lòng chọn ảnh khác.');
    }

    // Áp dụng xoay theo EXIF rồi bỏ metadata khi encode lại.
    var out = img.bakeOrientation(decoded);
    final longest = out.width > out.height ? out.width : out.height;
    if (longest > maxSide) {
      out = out.width >= out.height
          ? img.copyResize(out, width: maxSide)
          : img.copyResize(out, height: maxSide);
    }

    for (final quality in [85, 75, 65]) {
      final bytes = Uint8List.fromList(img.encodeJpg(out, quality: quality));
      if (bytes.length <= maxBytes) return bytes;
    }
    throw const FormatException(
      'Ảnh quá lớn. Vui lòng chụp lại ở độ phân giải thấp hơn.',
    );
  }
}
