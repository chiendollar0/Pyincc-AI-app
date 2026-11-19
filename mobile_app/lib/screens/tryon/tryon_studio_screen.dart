// ignore_for_file: deprecated_member_use
import 'dart:io';
import 'dart:typed_data';

import 'package:before_after/before_after.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/errors/user_message.dart';
import '../../core/theme/app_theme.dart';
import '../../services/tryon_image_service.dart';

class TryOnStudioScreen extends StatefulWidget {
  final String apiBaseUrl;
  final String authToken;
  final String? customerPsid;
  final String? customerName;
  final VoidCallback? onSignOut;

  const TryOnStudioScreen({
    super.key,
    required this.apiBaseUrl,
    this.authToken = '',
    this.customerPsid,
    this.customerName,
    this.onSignOut,
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

  bool _isUnrecognizedFace(Map<String, dynamic> analysis) {
    if (analysis['face_detected'] == false) return true;
    final faceShape = (analysis['face_shape'] ?? '').toString().toLowerCase();
    final skinTone = (analysis['skin_tone'] ?? '').toString().toLowerCase();
    return faceShape.contains('không thể xác định') ||
        faceShape.contains('không xác định') ||
        skinTone.contains('không thể xác định') ||
        skinTone.contains('không xác định');
  }

  Future<void> _pickImage(ImageSource source) async {
    XFile? picked;
    try {
      picked = await _picker.pickImage(source: source, imageQuality: 85);
    } catch (_) {
      if (!mounted) return;
      showAppMessage(
        context,
        'Không mở được thư viện ảnh hoặc máy ảnh. Vui lòng kiểm tra quyền truy cập.',
        isError: true,
      );
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
      final service = TryOnImageService(
        apiBaseUrl: widget.apiBaseUrl,
        authToken: widget.authToken,
      );
      final analysis = await service.analyzeFace(
        image: _originalImage!,
        catalog: _catalog,
      );

      if (!mounted) return;

      if (_isUnrecognizedFace(analysis)) {
        setState(() {
          _faceSummary = 'Chưa nhận diện được khuôn mặt';
          _note =
              'Chưa nhận diện được khuôn mặt. Vui lòng chụp lại ảnh rõ mặt, nhìn thẳng vào camera.';
        });
        return;
      }

      final suggestedId = analysis['recommended_item_id']?.toString();
      final validIds = _catalog.map((e) => e['id']).toSet();
      if (suggestedId != null && validIds.contains(suggestedId)) {
        _selectedId = suggestedId;
      }

      final faceShape = (analysis['face_shape'] ?? 'Cân đối').toString().trim();
      final skinTone = (analysis['skin_tone'] ?? 'Tự nhiên').toString().trim();
      final script = (analysis['consultation_note'] ??
              analysis['consultation_script'] ??
              analysis['observations'] ??
              '')
          .toString()
          .trim();

      setState(() {
        _faceSummary = 'Mặt: $faceShape • Da: $skinTone';
        _note = script.isNotEmpty
            ? script
            : 'Đã gợi ý mẫu phù hợp nhất trong danh mục của tiệm.';
      });
    } catch (error) {
      if (!mounted) return;
      final friendly = userMessage(error);
      setState(() {
        _faceSummary = 'Đã tải ảnh khách';
        _note = '$friendly Bạn vẫn có thể chọn mẫu bên dưới.';
      });
      showAppMessage(context, friendly, isError: true);
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
      final service = TryOnImageService(
        apiBaseUrl: widget.apiBaseUrl,
        authToken: widget.authToken,
      );
      final bytes = await service.generatePreview(
        image: image,
        category: item['category'] as String,
        prompt: item['prompt'] as String,
      );
      if (!mounted) return;
      setState(() => _aiResultBytes = bytes);
    } catch (error) {
      if (!mounted) return;
      showAppMessage(context, userMessage(error), isError: true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _approveAndSendToCustomer() async {
    final bytes = _aiResultBytes;
    final item = _selectedItem;
    if (bytes == null || item == null) return;

    final psidCtrl = TextEditingController(
      text: widget.customerPsid ?? '',
    );
    final captionCtrl = TextEditingController(
      text:
          'Dạ em gửi chị xem trước ảnh mô phỏng mẫu ${item['name']} (${item['price']}) bên em nhé ạ!',
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          widget.customerName != null
              ? 'Duyệt & gửi ảnh cho ${widget.customerName}'
              : 'Duyệt & gửi ảnh thử cho khách',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: psidCtrl,
                decoration: const InputDecoration(
                  labelText: 'Mã khách hàng (để trống nếu chỉ lưu hồ sơ)',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: captionCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Lời nhắn gửi kèm ảnh',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.send, size: 16),
            label: const Text('Xác nhận gửi'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isBusy = true);
    try {
      final service = TryOnImageService(
        apiBaseUrl: widget.apiBaseUrl,
        authToken: widget.authToken,
      );
      final result = await service.sendApprovedPreview(
        imageBytes: bytes,
        recipientId: psidCtrl.text,
        caption: captionCtrl.text,
      );
      if (!mounted) return;
      final delivered = result['deliveredToMessenger'] == true;
      showAppMessage(
        context,
        delivered
            ? 'Đã lưu ảnh và gửi qua Messenger cho khách thành công.'
            : 'Đã lưu ảnh mô phỏng vào hồ sơ khách hàng thành công.',
      );
    } catch (error) {
      if (!mounted) return;
      showAppMessage(context, userMessage(error), isError: true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedItem = _selectedItem;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            BrandHeader(
              subtitle: 'Studio AI',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.photo_library_outlined),
                    tooltip: 'Chọn ảnh từ thư viện',
                    onPressed:
                        _isBusy ? null : () => _pickImage(ImageSource.gallery),
                  ),
                  IconButton(
                    icon: const Icon(Icons.camera_alt_outlined),
                    tooltip: 'Chụp ảnh khách',
                    onPressed:
                        _isBusy ? null : () => _pickImage(ImageSource.camera),
                  ),
                  if (widget.onSignOut != null)
                    IconButton(
                      onPressed: widget.onSignOut,
                      icon: const Icon(Icons.logout),
                      tooltip: 'Đăng xuất',
                    ),
                ],
              ),
            ),
            if (_isBusy) const LinearProgressIndicator(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.14),
                    ),
                  ),
                  child: _originalImage == null
                      ? Center(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 16,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.face_retouching_natural,
                                  size: 48,
                                  color: AppColors.primary.withValues(alpha: 0.5),
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  'Chưa có ảnh mặt mộc của khách',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Chọn ảnh từ thư viện hoặc chụp trực tiếp để phân tích dáng mặt và mô phỏng mẫu mày/môi.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 8,
                                  alignment: WrapAlignment.center,
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
                            ),
                          ),
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(15),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              _aiResultBytes == null
                                  ? Image.file(
                                      _originalImage!,
                                      fit: BoxFit.cover,
                                    )
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
                              Positioned(
                                top: 10,
                                left: 10,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'Ảnh mô phỏng bằng AI',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ),
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.14),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.auto_awesome,
                        size: 16,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _faceSummary,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: AppColors.primaryDark,
                          ),
                        ),
                      ),
                      if (selectedItem != null)
                        Text(
                          'Giá niêm yết: ${selectedItem['price']}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: AppColors.textPrimary,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _note,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
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
                padding: const EdgeInsets.symmetric(horizontal: 16),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
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
                      onPressed: (_aiResultBytes == null || _isBusy)
                          ? null
                          : _approveAndSendToCustomer,
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
