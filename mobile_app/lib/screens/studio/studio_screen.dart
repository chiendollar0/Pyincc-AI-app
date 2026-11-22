import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/errors/user_message.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui/widgets.dart';
import '../../data/crm_repo.dart';
import '../../services/image_preprocessor.dart';

class StudioScreen extends StatefulWidget {
  const StudioScreen({
    super.key,
    required this.repo,
    required this.onOpenInbox,
    this.catalogVersion = 0,
    this.onCaseCreated,
  });

  final CrmRepo repo;
  final VoidCallback onOpenInbox;
  final int catalogVersion;
  final VoidCallback? onCaseCreated;

  @override
  State<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends State<StudioScreen> {
  final _picker = ImagePicker();
  List<Map<String, dynamic>> _catalog = [];
  bool _catalogLoading = true;
  String _group = 'Tất cả';
  String? _selectedId;
  File? _image;
  bool _consent = false;
  bool _busy = false;
  Map<String, dynamic>? _analysis;
  String? _analyzeError;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  @override
  void didUpdateWidget(covariant StudioScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.catalogVersion != oldWidget.catalogVersion) {
      _loadCatalog();
    }
  }

  Future<void> _loadCatalog() async {
    setState(() => _catalogLoading = true);
    try {
      final rows = await widget.repo.catalog();
      if (!mounted) return;
      setState(() {
        _catalog = rows.where((e) => e['active'] != false).toList();
        if (_selectedItem() == null) _selectedId = null;
        if (!_groups.contains(_group)) _group = 'Tất cả';
      });
    } catch (e) {
      if (mounted) showAppMessage(context, userMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _catalogLoading = false);
    }
  }

  Map<String, dynamic>? _selectedItem() {
    for (final item in _catalog) {
      if (item['id']?.toString() == _selectedId) return item;
    }
    return null;
  }

  List<String> get _groups {
    final seen = <String>{};
    final out = <String>['Tất cả'];
    for (final e in _catalog) {
      final label = (e['group_label'] ?? 'Khác').toString().trim();
      final display = label.isEmpty ? 'Khác' : label;
      final key = display.toLowerCase();
      if (seen.add(key)) out.add(display);
    }
    return out;
  }

  List<Map<String, dynamic>> get _visible => _group == 'Tất cả'
      ? _catalog
      : _catalog
          .where(
            (e) =>
                (e['group_label'] ?? 'Khác').toString().trim().toLowerCase() ==
                _group.toLowerCase(),
          )
          .toList();

  Future<void> _pick(ImageSource source) async {
    if (_busy) return;
    try {
      final picked = await _picker.pickImage(source: source, imageQuality: 90);
      if (picked == null || !mounted) return;
      setState(() {
        _image = File(picked.path);
        _analysis = null;
        _analyzeError = null;
        _consent = false;
      });
    } catch (_) {
      if (mounted) {
        showAppMessage(
          context,
          'Không mở được ảnh. Kiểm tra quyền truy cập ảnh hoặc camera.',
          isError: true,
        );
      }
    }
  }

  Future<void> _analyze() async {
    final image = _image;
    if (image == null || !_consent || _busy) return;
    setState(() {
      _busy = true;
      _analyzeError = null;
    });
    try {
      final bytes = await ImagePreprocessor.prepare(image);
      final res = await widget.repo.capture(
        imageBase64: base64Encode(bytes),
        selectedItemId: _selectedId,
      );
      if (!mounted) return;
      setState(() {
        _analysis = res['analysis'] is Map
            ? Map<String, dynamic>.from(res['analysis'] as Map)
            : <String, dynamic>{};
      });
      widget.onCaseCreated?.call();
      showAppMessage(context, 'Đã tạo ca trong Hộp thư để chủ duyệt.');
    } catch (e) {
      if (!mounted) return;
      final msg = e is ImagePrepareException ? e.message : userMessage(e);
      setState(() => _analyzeError = msg);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedItem();
    return Column(
      children: [
        BrandHeader(
          title: 'Studio AI',
          subtitle: 'Tư vấn cho chủ tiệm',
          actions: [
            IconButton(
              tooltip: 'Chọn ảnh',
              onPressed: _busy ? null : () => _pick(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
            ),
            IconButton(
              tooltip: 'Chụp ảnh',
              onPressed: _busy ? null : () => _pick(ImageSource.camera),
              icon: const Icon(Icons.photo_camera_outlined),
            ),
          ],
        ),
        if (_busy) const LinearProgressIndicator(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              _imageCard(),
              if (_image != null) _consentCard(),
              if (_analyzeError != null) _errorCard(),
              if (_analysis != null) _resultCard(),
              _catalogCard(selected),
              _demoCard(selected),
            ],
          ),
        ),
      ],
    );
  }

  Widget _imageCard() {
    if (_image == null) {
      return SectionCard(
        child: EmptyState(
          icon: Icons.face_retouching_natural,
          title: 'Chưa có ảnh khách',
          message: 'Chọn ảnh từ thư viện hoặc chụp trực tiếp tại tiệm.',
          action: FilledButton.icon(
            onPressed: _busy ? null : () => _pick(ImageSource.camera),
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Chụp ảnh'),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.file(
          _image!,
          height: 300,
          width: double.infinity,
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  Widget _consentCard() => SectionCard(
        child: Column(
          children: [
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _consent,
              onChanged:
                  _busy ? null : (v) => setState(() => _consent = v ?? false),
              title: const Text('Khách đã đồng ý cho tiệm xử lý ảnh để tư vấn'),
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (_consent && !_busy) ? _analyze : null,
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('Phân tích và gửi lên Hộp thư'),
              ),
            ),
          ],
        ),
      );

  Widget _errorCard() => SectionCard(
        title: 'Chưa phân tích được',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _analyzeError!,
              style: const TextStyle(color: AppColors.danger),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: (_consent && !_busy) ? _analyze : null,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Thử lại'),
            ),
          ],
        ),
      );

  Widget _resultCard() {
    final a = _analysis!;
    if (a['face_detected'] == false) {
      return const SectionCard(
        title: 'Kết quả',
        child: Text(
          'Chưa nhận diện được khuôn mặt. Chụp lại ảnh rõ mặt, nhìn thẳng vào camera.',
        ),
      );
    }
    final observation =
        (a['brow_or_lip_observation'] ?? a['summary'] ?? '').toString();
    return SectionCard(
      title: 'Nhận xét tham khảo (cho chủ tiệm)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (observation.isNotEmpty) Text('Quan sát: $observation'),
          if ((a['fit_note'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Lưu ý: ${a['fit_note']}'),
          ],
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: widget.onOpenInbox,
            child: const Text('Mở Hộp thư để duyệt'),
          ),
        ],
      ),
    );
  }

  Widget _catalogCard(Map<String, dynamic>? selected) {
    if (_catalogLoading) {
      return const SectionCard(
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_catalog.isEmpty) {
      return const SectionCard(
        title: 'Mẫu của tiệm',
        child: Text('Chưa có mẫu. Thêm mẫu trong Cài đặt → Catalog mẫu.'),
      );
    }
    return SectionCard(
      title: 'Mẫu khách chọn',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final g in _groups)
                ChoiceChip(
                  label: Text(g),
                  selected: _group == g,
                  onSelected: (_) => setState(() => _group = g),
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
                  label: Text((item['name'] ?? '').toString()),
                  selected: _selectedId == item['id']?.toString(),
                  onSelected: _busy
                      ? null
                      : (_) => setState(
                            () => _selectedId = item['id']?.toString(),
                          ),
                ),
            ],
          ),
          if (selected != null) ...[
            const SizedBox(height: 8),
            Text(
              'Đã chọn: ${selected['name']}',
              style: const TextStyle(color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _demoCard(Map<String, dynamic>? selected) => SectionCard(
        title: 'Ảnh demo theo mẫu đã chọn',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              selected == null
                  ? 'Chọn một mẫu để xem demo.'
                  : 'Demo theo mẫu "${selected['name']}" sẽ bật khi có model tạo ảnh.',
              style: const TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 8),
            const OutlinedButton(
              onPressed: null,
              child: Text('Tạo ảnh demo (chờ model)'),
            ),
          ],
        ),
      );
}
