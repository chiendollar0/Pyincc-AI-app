// ignore_for_file: deprecated_member_use
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/errors/image_prepare_exception.dart';
import '../../core/errors/user_message.dart';
import '../../core/theme/app_theme.dart';
import '../../services/handoff_service.dart';

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
    required this.handoffService,
    this.customerName,
    this.onSignOut,
  });

  final HandoffService handoffService;
  final String? customerName;
  final VoidCallback? onSignOut;

  @override
  State<TryOnStudioScreen> createState() => _TryOnStudioScreenState();
}

class _TryOnStudioScreenState extends State<TryOnStudioScreen> {
  final _picker = ImagePicker();

  File? _image;
  HandoffCase? _caseResult;
  String _filter = 'all';
  String? _selectedId;
  bool _busy = false;
  bool _approved = false;

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
    await _capture(File(path));
  }

  Future<bool> _confirmConsent() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận trước khi phân tích'),
        content: const Text(
          'Ảnh khách sẽ được gửi lên máy chủ để phân tích dáng mặt và tư vấn nội bộ. '
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

  Future<void> _capture(File file) async {
    setState(() {
      _image = file;
      _caseResult = null;
      _approved = false;
      _busy = true;
    });
    try {
      final result = await widget.handoffService.captureCase(file);
      if (!mounted) return;
      setState(() {
        _caseResult = result;
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

  Future<void> _approveCurrentCase() async {
    final c = _caseResult;
    if (c == null || _busy || c.draftReply.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.handoffService.approveCase(
        id: c.id,
        draftReply: c.draftReply,
      );
      if (!mounted) return;
      setState(() => _approved = true);
      showAppMessage(context, 'Đã duyệt ca tư vấn (chưa gửi đi).');
    } catch (error) {
      if (!mounted) return;
      showAppMessage(context, userMessage(error), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _reset() => setState(() {
        _image = null;
        _caseResult = null;
        _selectedId = null;
        _approved = false;
      });

  Future<void> _copyNote() async {
    final note = _caseResult?.draftReply ?? '';
    if (note.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: note));
    if (mounted) {
      showAppMessage(
        context,
        'Đã sao chép gợi ý để nhân viên kiểm tra trước khi tư vấn.',
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
            _resultCard(_caseResult),
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

  Widget _resultCard(HandoffCase? c) {
    if (_image == null) return const SizedBox.shrink();
    if (c == null) {
      return const _Card(child: Text('Đang phân tích ca tư vấn...'));
    }
    if (!c.faceDetected) {
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
          if (c.summary.isNotEmpty) ...[
            Text(
              'Tóm tắt: ${c.summary}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
          ],
          Text('Mức rủi ro: ${c.risk}'),
          if (c.draftReply.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              'Gợi ý tham khảo',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(c.draftReply),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _copyNote,
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Sao chép gợi ý'),
                ),
                FilledButton(
                  onPressed: (_busy || _approved) ? null : _approveCurrentCase,
                  child: Text(_approved ? 'Đã duyệt' : 'Duyệt'),
                ),
              ],
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
