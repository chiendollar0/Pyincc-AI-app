// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../../core/errors/user_message.dart';
import '../../core/theme/app_theme.dart';
import '../../services/catalog_service.dart';

class CatalogManagementScreen extends StatefulWidget {
  const CatalogManagementScreen({
    super.key,
    required this.catalogService,
    this.onChanged,
  });

  final CatalogService catalogService;
  final VoidCallback? onChanged;

  @override
  State<CatalogManagementScreen> createState() =>
      _CatalogManagementScreenState();
}

class _CatalogManagementScreenState extends State<CatalogManagementScreen> {
  List<CatalogItem> _items = const [];
  String _filter = 'all';
  bool _loading = true;
  String? _error;
  final Set<String> _busyIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<CatalogItem> get _visible {
    if (_filter == 'all') return _items;
    return _items.where((i) => i.category == _filter).toList();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.catalogService.fetchItems();
      if (!mounted) return;
      setState(() => _items = items);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = userMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openEditor({CatalogItem? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    String category = existing?.category ?? 'eyebrow';

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Thêm dịch vụ mới' : 'Sửa dịch vụ'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Danh mục nội bộ dùng cho AI gợi ý dáng phù hợp (không lưu giá trong app; giá do Business AI tư vấn).',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tên dịch vụ / mẫu',
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Nhóm dịch vụ',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final c in const [
                      ('eyebrow', 'Chân mày'),
                      ('lip', 'Môi'),
                      ('other', 'Khác'),
                    ])
                      ChoiceChip(
                        label: Text(c.$2),
                        selected: category == c.$1,
                        onSelected: (_) =>
                            setDialogState(() => category = c.$1),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Mô tả ngắn (không ghi giá)',
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
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(existing == null ? 'Thêm' : 'Lưu'),
            ),
          ],
        ),
      ),
    );

    final name = nameCtrl.text.trim();
    final desc = descCtrl.text.trim();
    nameCtrl.dispose();
    descCtrl.dispose();
    if (saved != true || name.isEmpty) return;

    try {
      if (existing == null) {
        await widget.catalogService.createItem(
          name: name,
          category: category,
          description: desc.isEmpty ? null : desc,
        );
        if (!mounted) return;
        widget.onChanged?.call();
        showAppMessage(context, 'Đã thêm "$name" vào danh mục.');
      } else {
        await widget.catalogService.updateItem(
          id: existing.id,
          name: name,
          category: category,
          description: desc.isEmpty ? null : desc,
        );
        if (!mounted) return;
        widget.onChanged?.call();
        showAppMessage(context, 'Đã cập nhật "$name".');
      }
      await _load();
    } catch (error) {
      if (!mounted) return;
      showAppMessage(context, userMessage(error), isError: true);
    }
  }

  Future<void> _deleteItem(CatalogItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa dịch vụ'),
        content: Text('Xóa "${item.name}" khỏi danh mục của tiệm?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busyIds.add(item.id));
    try {
      await widget.catalogService.deleteItem(item.id);
      if (!mounted) return;
      widget.onChanged?.call();
      showAppMessage(context, 'Đã xóa "${item.name}".');
      await _load();
    } catch (error) {
      if (!mounted) return;
      showAppMessage(context, userMessage(error), isError: true);
    } finally {
      if (mounted) setState(() => _busyIds.remove(item.id));
    }
  }

  String _categoryLabel(String category) {
    switch (category) {
      case 'eyebrow':
        return 'Chân mày';
      case 'lip':
        return 'Môi';
      default:
        return 'Khác';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Danh mục dịch vụ'),
        actions: [
          IconButton(
            tooltip: 'Làm mới',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Thêm dịch vụ',
            onPressed: () => _openEditor(),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                for (final f in const [
                  ('all', 'Tất cả'),
                  ('eyebrow', 'Chân mày'),
                  ('lip', 'Môi'),
                  ('other', 'Khác'),
                ]) ...[
                  ChoiceChip(
                    label: Text(f.$2),
                    selected: _filter == f.$1,
                    onSelected: (_) => setState(() => _filter = f.$1),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Chưa tải được danh mục',
        message: _error,
        onRetry: _load,
      );
    }
    final list = _visible;
    if (list.isEmpty) {
      return EmptyState(
        icon: Icons.style_outlined,
        title: 'Chưa có dịch vụ nào',
        message: 'Bấm dấu + ở góc trên để thêm mẫu dịch vụ của tiệm.',
        retryLabel: 'Thêm dịch vụ',
        onRetry: () => _openEditor(),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: list.length,
        itemBuilder: (context, index) {
          final item = list[index];
          final busy = _busyIds.contains(item.id);
          return Card(
            child: ListTile(
              title: Text(
                item.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                [
                  _categoryLabel(item.category),
                  if ((item.description ?? '').isNotEmpty) item.description!,
                ].join(' • '),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Sửa',
                    onPressed: busy ? null : () => _openEditor(existing: item),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: 'Xóa',
                    onPressed: busy ? null : () => _deleteItem(item),
                    icon: const Icon(
                      Icons.delete_outline,
                      color: AppColors.danger,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
