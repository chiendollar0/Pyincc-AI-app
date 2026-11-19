class ImagePrepareException implements Exception {
  final String message;

  const ImagePrepareException(this.message);

  @override
  String toString() => message;
}
