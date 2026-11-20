// ignore_for_file: deprecated_member_use
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/errors/image_prepare_exception.dart';
import '../../core/errors/user_message.dart';
import '../../core/theme/app_theme.dart';
import '../../services/tryon_image_service.dart';

class _Item {
  const _Item(this.id, this.name, this.category);
  final String id;
  final String name;
  final String category; // 'eyebrow' | 'lip'
}

const _catalog = <_Item>[
  _Item('1', 'Mày sợi Hairstroke Nâu Tây', 'eyebrow'),
  _Item('2', 'Mày Shading Ombre', 'eyebrow'),
  _Item('3', 'Môi Collagen Cam Đào', 'lip'),
  _Item('4', 'Môi Khử Thâm Hồng Baby', 'lip'),
];

class TryOnStudioScreen extends StatefulWidget {
  const TryOnStudioScreen({
    super.key,
    this.authToken = '',
    this.customerName,
    this.onSignOut,
  });

  final String authToken;
  final String? customerName;
  final VoidCallback? onSignOut;

  @override
  State<TryOnStudioScreen> createState() => _TryOnStudioScreenState();
}

class _TryOnStudioScreenState extends State<TryOnStudioScreen> {
  final _picker = ImagePicker();
  late final _service = TryOnImageService(authToken: widget.authToken);

  File? _image;
  FaceAnalysis? _analysis;
  String _filter = 'all';
  String? _selectedId;
  bool _busy = false;

  List<_Item> get _visible => _filter == 'all'
      ? _catalog
      : _catalog.where((e) => e.category == _filter).toList();

  Future<void> _pick(ImageSource source) async {
    if (_busy) return;
    XFile? picked;
    try {
      picked = await _picker.pickImage(source: source, imageQuality: 90);
    } catch (_) {
      if (mounted) {
        showAppMessage(
          context,
          'Không mở được ảnh. Vui lòng kiểm tra quyền truy cập.',
          isError: true,
        );
      }
      return;
    }
    if (picked == null || !mounted) return;
    final path = picked.path;
    if (!await _confirmConsent()) return;
    await _analyze(File(path));
  }

  Future<bool> _confirmConsent() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận trước khi phân tích'),
        content: const Text(
          'Ảnh khách sẽ được gửi để phân tích dáng mặt và tông da. '
          'Chỉ tiếp tục khi khách đã đồng ý.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Khách đã đồng ý'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _analyze(File file) async {
    setState(() {
      _image = file;
      _analysis = null;
      _busy = true;
    });
    try {
      final result = await _service.analyzeFace(file);
      if (!mounted) return;
      setState(() {
        _analysis = result;
        final rec = result.recommendedItemId;
        if (result.faceDetected &&
            rec != null &&
            _catalog.any((e) => e.id == rec)) {
          _selectedId = rec;
        }
      });
    } catch (error) {
      if (!mounted) return;
      final msg =
          error is ImagePrepareException ? error.message : userMessage(error);
      showAppMessage(context, msg, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _reset() => setState(() {
        _image = null;
        _analysis = null;
        _selectedId = null;
      });

  Future<void> _copyNote() async {
    final note = _analysis?.consultationNote ?? '';
    if (note.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: note));
    if (mounted) {
      showAppMessage(
        context,
        'Đã sao chép. Dán vào hộp thư để nhân viên chỉnh sửa trước khi gửi.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.customerName == null
                        ? 'Studio AI'
                        : 'Studio AI • ${widget.customerName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Chọn ảnh',
                  onPressed: _busy ? null : () => _pick(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                ),
                IconButton(
                  tooltip: 'Chụp ảnh',
                  onPressed: _busy ? null : () => _pick(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt_outlined),
                ),
                if (widget.onSignOut != null)
                  IconButton(
                    tooltip: 'Đăng xuất',
                    onPressed: widget.onSignOut,
                    icon: const Icon(Icons.logout),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _imageArea(),
            const SizedBox(height: 12),
            _resultCard(_analysis),
            const SizedBox(height: 12),
            _catalogSection(),
            const SizedBox(height: 16),
            const Text(
              'Kết quả chỉ là gợi ý nội bộ. Nhân viên xác nhận trước khi tư vấn cho khách.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imageArea() {
    if (_image == null) {
      return _Card(
        child: Column(
          children: [
            Icon(
              Icons.face_retouching_natural,
              size: 48,
              color: AppColors.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 8),
            const Text(
              'Chọn ảnh mặt mộc của khách',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Ảnh rõ mặt, nhìn thẳng, đủ sáng.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : () => _pick(ImageSource.gallery),
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Chọn ảnh'),
            ),
          ],
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          Image.file(
            _image!,
            height: 280,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
          if (_busy)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x66000000),
                child: Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
            ),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton.filledTonal(
              tooltip: 'Xóa ảnh',
              onPressed: _busy ? null : _reset,
              icon: const Icon(Icons.close),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultCard(FaceAnalysis? a) {
    if (_image == null) return const SizedBox.shrink();
    if (a == null) {
      return const _Card(child: Text('Đang phân tích dáng mặt...'));
    }
    if (!a.faceDetected) {
      return const _Card(
        child: Text(
          'Chưa nhận diện được khuôn mặt. Vui lòng chụp lại ảnh rõ mặt, nhìn thẳng vào camera.',
        ),
      );
    }
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Dáng mặt: ${a.faceShape.isEmpty ? 'Chưa xác định' : a.faceShape}',
          ),
          const SizedBox(height: 2),
          Text(
            'Tông da: ${a.skinTone.isEmpty ? 'Chưa xác định' : a.skinTone}',
          ),
          if (a.observations.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(a.observations),
          ],
          if (a.consultationNote.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              'Gợi ý tham khảo',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(a.consultationNote),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _copyNote,
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Sao chép gợi ý'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _catalogSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final f in const [
              ('all', 'Tất cả'),
              ('eyebrow', 'Chân mày'),
              ('lip', 'Môi'),
            ])
              ChoiceChip(
                label: Text(f.$2),
                selected: _filter == f.$1,
                onSelected: (_) => setState(() => _filter = f.$1),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in _visible)
              ChoiceChip(
                label: Text(item.name),
                selected: _selectedId == item.id,
                onSelected: (_) => setState(() => _selectedId = item.id),
              ),
          ],
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
        ),
        child: child,
      );
}
