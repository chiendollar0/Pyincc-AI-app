import 'api_client.dart';

class CatalogItem {
  final String id;
  final String category; // 'eyebrow' | 'lip' | 'other'
  final String name;
  final String? description;
  final String? imageUrl;

  const CatalogItem({
    required this.id,
    required this.category,
    required this.name,
    this.description,
    this.imageUrl,
  });

  factory CatalogItem.fromJson(Map<String, dynamic> json) {
    return CatalogItem(
      id: (json['id'] ?? '').toString(),
      category: (json['category'] ?? 'other').toString(),
      name: (json['name'] ?? '').toString(),
      description: json['description']?.toString(),
      imageUrl: json['image_url']?.toString(),
    );
  }
}

class CatalogService {
  final ApiClient apiClient;

  const CatalogService(this.apiClient);

  Future<List<CatalogItem>> fetchItems() async {
    final data = await apiClient.get('/catalog');
    final raw = data['items'];
    if (raw is! List) return const <CatalogItem>[];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(CatalogItem.fromJson)
        .toList();
  }

  Future<CatalogItem> createItem({
    required String name,
    required String category,
    String? description,
    String? imageUrl,
  }) async {
    final data = await apiClient.post('/catalog', {
      'name': name.trim(),
      'category': category.trim(),
      if (description != null && description.trim().isNotEmpty)
        'description': description.trim(),
      if (imageUrl != null && imageUrl.trim().isNotEmpty)
        'image_url': imageUrl.trim(),
    });
    final item = data['item'];
    if (item is! Map<String, dynamic>) {
      throw const ApiException(0, 'Không đọc được danh mục vừa tạo.');
    }
    return CatalogItem.fromJson(item);
  }

  Future<CatalogItem> updateItem({
    required String id,
    required String name,
    required String category,
    String? description,
    String? imageUrl,
  }) async {
    final data = await apiClient.put('/catalog/${Uri.encodeComponent(id)}', {
      'name': name.trim(),
      'category': category.trim(),
      'description': description?.trim(),
      'image_url': imageUrl?.trim(),
    });
    final item = data['item'];
    if (item is! Map<String, dynamic>) {
      throw const ApiException(0, 'Không đọc được danh mục vừa cập nhật.');
    }
    return CatalogItem.fromJson(item);
  }

  Future<void> deleteItem(String id) async {
    await apiClient.delete('/catalog/${Uri.encodeComponent(id)}');
  }
}
