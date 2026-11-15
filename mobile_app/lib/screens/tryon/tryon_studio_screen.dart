import 'dart:io';
import 'dart:typed_data';

import 'package:before_after/before_after.dart';
import 'package:material_ui/material_ui.dart';
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
  String _note = 'Chọn ảnh mặt mộc của khách để bắt đầu.';
  String _selectedId = '1';

  static const List<Map<String, dynamic>> _catalog = [
    {'id': '1', 'name': 'Mày sợi Hairstroke Nâu Tây', 'category': 'eyebrow', 'prompt': 'natural hairstroke eyebrows, soft dark brown'},
    {'id': '2', 'name': 'Mày Shading Ombre', 'category': 'eyebrow', 'prompt': 'soft powder ombre shading eyebrows, espresso brown'},
    {'id': '3', 'name': 'Môi Collagen Cam Đào', 'category': 'lip', 'prompt': 'glossy peach coral lips, natural lip blush'},
    {'id': '4', 'name': 'Môi Khử Thâm Hồng Baby', 'category': 'lip', 'prompt': 'soft baby pink natural lips'},
  ];

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
      _note = 'Gemini đang phân tích khuôn mặt...';
    });

    try {
      final service = TryOnImageService(apiBaseUrl: widget.apiBaseUrl);
      final analysis = await service.analyzeFace(
        image: _originalImage!,
        catalog: _catalog,
      );

      if (!mounted) return;

      // Validate ID trả về từ Gemini
      final suggestedId = analysis['recommended_item_id']?.toString();
      final validIds = _catalog.map((e) => e['id']).toSet();
      if (suggestedId != null && validIds.contains(suggestedId)) {
        _selectedId = suggestedId;
      }

      setState(() {
        _note = 'Dáng mặt: ${analysis['face_shape']} | Da: ${analysis['skin_tone']}\n'
            'Gợi ý: ${analysis['consultation_script']}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _note = 'Lỗi phân tích: $e');
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Ghép Mẫu Mày / Môi'),
        actions: [
          IconButton(
            icon: const Icon(Icons.photo_library),
            tooltip: 'Chọn từ thư viện',
            onPressed: _isBusy ? null : () => _pickImage(ImageSource.gallery),
          ),
          IconButton(
            icon: const Icon(Icons.camera_alt),
            tooltip: 'Chụp ảnh',
            onPressed: _isBusy ? null : () => _pickImage(ImageSource.camera),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _originalImage == null
                  ? Center(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickImage(ImageSource.gallery),
                        icon: const Icon(Icons.add_a_photo),
                        label: const Text('Tải ảnh mặt mộc'),
                      ),
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: _aiResultBytes == null
                          ? Image.file(_originalImage!, fit: BoxFit.cover)
                          : BeforeAfter(
                              value: _sliderPosition,
                              before: Image.file(_originalImage!, fit: BoxFit.cover),
                              after: Image.memory(_aiResultBytes!, fit: BoxFit.cover),
                              onValueChanged: (v) =>
                                  setState(() => _sliderPosition = v),
                            ),
                    ),
            ),
          ),
          if (_isBusy) const LinearProgressIndicator(),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.pink.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(_note, style: const TextStyle(fontSize: 13)),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 50,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _catalog.length,
              itemBuilder: (context, index) {
                final item = _catalog[index];
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(item['name'] as String),
                    selected: _selectedId == item['id'],
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
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: (_originalImage == null || _isBusy) ? null : _generatePreview,
                    child: const Text('Tạo ảnh thử'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _aiResultBytes == null ? null : () {},
                    icon: const Icon(Icons.send),
                    label: const Text('Gửi cho khách'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
