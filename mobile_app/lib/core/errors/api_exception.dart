class ApiException implements Exception {
  final int status;
  final String message;
  final String? caseId;

  const ApiException(this.status, this.message, {this.caseId});

  @override
  String toString() => message;
}
