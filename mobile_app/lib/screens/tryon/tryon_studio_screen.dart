// ignore_for_file: deprecated_member_use
import 'dart:io';
import 'dart:typed_data';

import 'package:before_after/before_after.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/tryon_image_service.dart';

class TryOnStudioScreen extends StatefulWidget {
  final String apiBaseUrl;

  const TryOnStudioScreen({
    super.key,
    required this.apiBaseUrl,
  });

  @override
  State<TryOnStudioScreen> createState() => _TryOnStudioScreenState();
}

class _TryOnStudioScreenState extends State<TryOnStudioScreen> {
  final ImagePicker _picker = ImagePicker();

  File? _originalImage;
  Uint8List? _aiResultBytes;
  bool _isBusy = false;
  double _sliderPosition = 0.5;
  String _categoryFilter = 'all';
  String _faceSummary = 'Chưa có ảnh';
  String _note =
      'Tải ảnh mặt mộc từ thư viện hoặc chụp trực tiếp để AI phân tích dáng mặt và gợi ý mẫu phù hợp.';
  String _selectedId = '1';

  static const List<Map<String, dynamic>> _catalog = [
    {
      'id': '1',
      'name': 'Mày sợi Hairstroke Nâu Tây',
      'category': 'eyebrow',
      'price': '3.500.000đ',
      'prompt': 'natural hairstroke eyebrows, soft dark brown',
    },
    {
      'id': '2',
      'name': 'Mày Shading Ombre',
      'category': 'eyebrow',
      'price': '2.800.000đ',
      'prompt': 'soft powder ombre shading eyebrows, espresso brown',
    },
    {
      'id': '3',
      'name': 'Môi Collagen Cam Đào',
      'category': 'lip',
      'price': '4.000.000đ',
      'prompt': 'glossy peach coral lips, natural lip blush',
    },
    {
      'id': '4',
      'name': 'Môi Khử Thâm Hồng Baby',
      'category': 'lip',
      'price': '3.800.000đ',
      'prompt': 'soft baby pink natural lips',
    },
  ];

  List<Map<String, dynamic>> get _filteredCatalog {
    if (_categoryFilter == 'all') return _catalog;
    return _catalog
        .where((item) => item['category'] == _categoryFilter)
        .toList();
  }

  Map<String, dynamic>? get _selectedItem {
    for (final item in _catalog) {
      if (item['id'] == _selectedId) return item;
    }
    return null;
  }

  Future<void> _pickImage(ImageSource source) async {
    XFile? picked;
    try {
      picked = await _picker.pickImage(source: source, imageQuality: 85);
    } catch (e) {
      if (!mounted) return;
      setState(() => _note = 'Không mở được thư viện/camera: $e');
      return;
    }

    if (picked == null) return;

    setState(() {
      _originalImage = File(picked!.path);
      _aiResultBytes = null;
      _isBusy = true;
      _faceSummary = 'Đang phân tích...';
      _note = 'AI đang nhận diện dáng mặt và tông da của khách...';
    });

    try {
      final service = TryOnImageService(apiBaseUrl: widget.apiBaseUrl);
      final analysis = await service.analyzeFace(
        image: _originalImage!,
        catalog: _catalog,
      );

      if (!mounted) return;

      final suggestedId = analysis['recommended_item_id']?.toString();
      final validIds = _catalog.map((e) => e['id']).toSet();
      if (suggestedId != null && validIds.contains(suggestedId)) {
        _selectedId = suggestedId;
      }

      setState(() {
        _faceSummary =
            'Mặt: ${analysis['face_shape'] ?? 'Cân đối'} • Da: ${analysis['skin_tone'] ?? 'Tự nhiên'}';
        _note =
            '${analysis['consultation_script'] ?? 'Đã chọn mẫu phù hợp nhất trong danh mục.'}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _faceSummary = 'Đã tải ảnh khách';
        _note = 'Chưa phân tích tự động ($e). Bạn vẫn có thể chọn mẫu bên dưới để ghép thử.';
      });
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _generatePreview() async {
    final image = _originalImage;
    final item = _selectedItem;
    if (image == null || item == null) return;

    setState(() => _isBusy = true);
    try {
      final service = TryOnImageService(apiBaseUrl: widget.apiBaseUrl);
      final bytes = await service.generatePreview(
        image: image,
        category: item['category'] as String,
        prompt: item['prompt'] as String,
      );
      if (!mounted) return;
      setState(() => _aiResultBytes = bytes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedItem = _selectedItem;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Studio AI • Thử Mày & Môi'),
        actions: [
          IconButton(
            icon: const Icon(Icons.photo_library_outlined),
            tooltip: 'Chọn ảnh từ thư viện',
            onPressed: _isBusy ? null : () => _pickImage(ImageSource.gallery),
          ),
          IconButton(
            icon: const Icon(Icons.camera_alt_outlined),
            tooltip: 'Chụp ảnh khách',
            onPressed: _isBusy ? null : () => _pickImage(ImageSource.camera),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_isBusy) const LinearProgressIndicator(),
            // 1. Khung ảnh Trước / Sau ổn định
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: _originalImage == null
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.face_retouching_natural,
                              size: 56,
                              color: Colors.pink.shade300,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Chưa có ảnh mặt mộc của khách',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 32),
                              child: Text(
                                'Chọn ảnh từ thư viện hoặc chụp trực tiếp để xem so sánh Trước & Sau khi làm mày/môi.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.black54,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 10,
                              children: [
                                FilledButton.icon(
                                  onPressed: () =>
                                      _pickImage(ImageSource.gallery),
                                  icon: const Icon(Icons.add_photo_alternate),
                                  label: const Text('Chọn ảnh thư viện'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () =>
                                      _pickImage(ImageSource.camera),
                                  icon: const Icon(Icons.camera_alt),
                                  label: const Text('Chụp ảnh'),
                                ),
                              ],
                            ),
                          ],
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(15),
                          child: _aiResultBytes == null
                              ? Image.file(_originalImage!, fit: BoxFit.cover)
                              : BeforeAfter(
                                  value: _sliderPosition,
                                  before: Image.file(
                                    _originalImage!,
                                    fit: BoxFit.cover,
                                  ),
                                  after: Image.memory(
                                    _aiResultBytes!,
                                    fit: BoxFit.cover,
                                  ),
                                  onValueChanged: (v) =>
                                      setState(() => _sliderPosition = v),
                                ),
                        ),
                ),
              ),
            ),

            // 2. Thẻ tóm tắt tư vấn AI
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.pink.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.auto_awesome,
                        size: 16,
                        color: Colors.pink,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _faceSummary,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Colors.pink,
                          ),
                        ),
                      ),
                      if (selectedItem != null)
                        Text(
                          'Giá: ${selectedItem['price']}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _note,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // 3. Bộ lọc nhóm dịch vụ + Danh sách mẫu
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('Tất cả'),
                    selected: _categoryFilter == 'all',
                    onSelected: (_) => setState(() => _categoryFilter = 'all'),
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: const Text('Chân mày'),
                    selected: _categoryFilter == 'eyebrow',
                    onSelected: (_) =>
                        setState(() => _categoryFilter = 'eyebrow'),
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: const Text('Môi'),
                    selected: _categoryFilter == 'lip',
                    onSelected: (_) => setState(() => _categoryFilter = 'lip'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 44,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _filteredCatalog.length,
                itemBuilder: (context, index) {
                  final item = _filteredCatalog[index];
                  final isSelected = _selectedId == item['id'];
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('${item['name']} (${item['price']})'),
                      selected: isSelected,
                      onSelected: _isBusy
                          ? null
                          : (_) => setState(() {
                                _selectedId = item['id'] as String;
                                _aiResultBytes = null;
                              }),
                    ),
                  );
                },
              ),
            ),

            // 4. Thanh thao tác cố định
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: (_originalImage == null || _isBusy)
                          ? null
                          : _generatePreview,
                      icon: const Icon(Icons.auto_fix_high, size: 18),
                      label: const Text('Tạo ảnh thử AI'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _aiResultBytes == null
                          ? null
                          : () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Đã lưu ảnh demo vào hồ sơ tư vấn khách!',
                                  ),
                                ),
                              );
                            },
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      label: const Text('Duyệt gửi khách'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
