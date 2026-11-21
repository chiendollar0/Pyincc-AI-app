import '../services/api_client.dart';

class CrmRepo {
  CrmRepo(this.api);

  final ApiClient api;

  static List<Map<String, dynamic>> _rows(dynamic v) => v is List
      ? v.whereType<Map<String, dynamic>>().toList()
      : <Map<String, dynamic>>[];

  // Tiệm và cài đặt
  Future<Map<String, dynamic>> tenant() => api.get('/tenant');
  Future<void> updateTenant(Map<String, dynamic> body) =>
      api.put('/tenant', body);
  Future<Map<String, dynamic>> aiUsage() => api.get('/ai-usage');

  // Kết nối
  Future<Map<String, dynamic>> connectionStatus() =>
      api.get('/connection/status');
  Future<List<Map<String, dynamic>>> connectedPages() async =>
      _rows((await api.get('/connected-pages'))['pages']);

  // Hộp thư (ca)
  Future<List<Map<String, dynamic>>> handoffCases(String status) async =>
      _rows((await api.get(
        '/handoff-cases?status=${Uri.encodeQueryComponent(status)}',
      ))['cases']);
  Future<void> approve(String id, String text) => api.post(
        '/handoff-cases/${Uri.encodeComponent(id)}/approve',
        {'draft_reply': text},
      );
  Future<void> reject(String id) => api.post(
        '/handoff-cases/${Uri.encodeComponent(id)}/reject',
        const {},
      );
  Future<void> send(String id) => api.post(
        '/handoff-cases/${Uri.encodeComponent(id)}/send',
        const {},
        timeout: const Duration(seconds: 25),
      );

  // Studio
  Future<Map<String, dynamic>> capture({
    required String imageBase64,
    String? selectedItemId,
    String? note,
  }) =>
      api.post(
        '/handoff-cases/capture',
        {
          'image_base64': imageBase64,
          if (selectedItemId != null) 'selected_item_id': selectedItemId,
          if (note != null && note.isNotEmpty) 'note': note,
        },
        timeout: const Duration(seconds: 90),
      );

  // Catalog
  Future<List<Map<String, dynamic>>> catalog() async =>
      _rows((await api.get('/catalog'))['items']);
  Future<void> addCatalogItem(Map<String, dynamic> body) =>
      api.post('/catalog', body);
  Future<void> updateCatalogItem(String id, Map<String, dynamic> body) =>
      api.put('/catalog/${Uri.encodeComponent(id)}', body);

  // Lịch
  Future<List<Map<String, dynamic>>> bookings() async =>
      _rows((await api.get('/bookings'))['bookings']);
  Future<void> createBooking(Map<String, dynamic> body) =>
      api.post('/bookings', body);
}
