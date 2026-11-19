import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pyincc_app/core/errors/api_exception.dart';
import 'package:pyincc_app/core/errors/user_message.dart';
import 'package:pyincc_app/services/image_preprocessor.dart';

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final b in bytes) {
    crc ^= b;
    for (var i = 0; i < 8; i++) {
      if ((crc & 1) != 0) {
        crc = (crc >>> 1) ^ 0xEDB88320;
      } else {
        crc = crc >>> 1;
      }
    }
  }
  return (~crc) & 0xFFFFFFFF;
}

Uint8List _buildMinimalPngHeader(int width, int height) {
  // Valid 8-byte PNG signature + 25-byte IHDR chunk (with CRC32) + 12-byte IEND chunk
  final data = ByteData(45);
  const sig = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  for (var i = 0; i < sig.length; i++) {
    data.setUint8(i, sig[i]);
  }
  data.setUint32(8, 13, Endian.big); // IHDR length
  // 'IHDR'
  data.setUint8(12, 0x49);
  data.setUint8(13, 0x48);
  data.setUint8(14, 0x44);
  data.setUint8(15, 0x52);
  data.setUint32(16, width, Endian.big);
  data.setUint32(20, height, Endian.big);
  data.setUint8(24, 8); // bit depth
  data.setUint8(25, 2); // color type RGB
  data.setUint8(26, 0); // compression
  data.setUint8(27, 0); // filter
  data.setUint8(28, 0); // interlace
  final bytes = data.buffer.asUint8List();
  data.setUint32(29, _crc32(bytes.sublist(12, 29)), Endian.big);

  // Standard IEND chunk
  const iend = [0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82];
  for (var i = 0; i < iend.length; i++) {
    data.setUint8(33 + i, iend[i]);
  }
  return bytes;
}

void main() {
  group('ImagePreprocessor', () {
    test('rejects fake JPEG bytes with ImagePrepareException', () {
      final fakeBytes = Uint8List.fromList('not-a-real-image'.codeUnits);

      expect(
        () => ImagePreprocessor.processBytesForTest(fakeBytes),
        throwsA(isA<ImagePrepareException>()),
      );
    });

    test('rejects unsupported GIF format before decoding', () {
      final gifBytes = Uint8List.fromList(
        [0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00],
      );

      expect(
        () => ImagePreprocessor.processBytesForTest(gifBytes),
        throwsA(
          isA<ImagePrepareException>().having(
            (e) => e.message,
            'message',
            contains('JPG, PNG hoặc WebP'),
          ),
        ),
      );
    });

    test('rejects oversized (>24 MP) PNG from header without full pixel decode', () {
      final hugeHeader = _buildMinimalPngHeader(6000, 5000); // 30 MP

      expect(
        () => ImagePreprocessor.processBytesForTest(hugeHeader),
        throwsA(
          isA<ImagePrepareException>().having(
            (e) => e.message,
            'message',
            contains('Ảnh quá lớn'),
          ),
        ),
      );
    });

    test('strips EXIF/GPS metadata, resizes long side to <=1024, and outputs valid JPEG', () async {
      final source = img.Image(width: 1600, height: 800);
      img.fill(source, color: img.ColorRgb8(200, 120, 140));
      source.exif.gpsIfd.gpsLatitude = 10.762622;
      source.exif.gpsIfd.gpsLongitude = 106.660172;
      source.exif.imageIfd.make = 'TestPhone';
      final rawWithExif = Uint8List.fromList(img.encodeJpg(source, quality: 90));

      // Sanity check that input actually contained EXIF/GPS before processing
      final inputExif = img.decodeJpgExif(rawWithExif);
      expect(inputExif, isNotNull);
      expect(inputExif!.gpsIfd.isEmpty, isFalse);

      final tmpDir = await Directory.systemTemp.createTemp('pyincc_img_test_');
      addTearDown(() => tmpDir.delete(recursive: true));
      final inputFile = File('${tmpDir.path}/sample.jpg');
      await inputFile.writeAsBytes(rawWithExif);

      final output = await ImagePreprocessor.prepare(inputFile);
      expect(output.length, lessThanOrEqualTo(ImagePreprocessor.maxBytes));
      expect(output[0], equals(0xFF));
      expect(output[1], equals(0xD8));

      final outputExif = img.decodeJpgExif(output);
      expect(outputExif == null || outputExif.isEmpty, isTrue);

      final decodedOut = img.decodeJpg(output);
      expect(decodedOut, isNotNull);
      expect(decodedOut!.width, lessThanOrEqualTo(ImagePreprocessor.maxSide));
      expect(decodedOut.height, lessThanOrEqualTo(ImagePreprocessor.maxSide));
      expect(decodedOut.width, equals(1024));
      expect(decodedOut.height, equals(512));
    });
  });

  group('userMessage error mappings', () {
    test('returns friendly Vietnamese message for ImagePrepareException and backend codes', () {
      expect(
        userMessage(const ImagePrepareException('Ảnh quá lớn.')),
        equals('Ảnh quá lớn.'),
      );
      expect(
        userMessage(const FormatException('raw internal stack parse fail')),
        equals('Có lỗi xảy ra. Vui lòng thử lại.'),
      );
      expect(
        userMessage(const ApiException(403, 'SELF_APPROVAL_NOT_ALLOWED')),
        contains('không thể tự duyệt'),
      );
      expect(
        userMessage(const ApiException(409, 'INVITATION_ALREADY_EXISTS')),
        contains('đang chờ xác nhận'),
      );
      expect(
        userMessage(const ApiException(422, 'MISSING_PAGE_CONTEXT')),
        contains('Thiếu thông tin Fanpage'),
      );
    });
  });
}
