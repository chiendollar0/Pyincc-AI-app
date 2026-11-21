import 'package:flutter/material.dart';

import '../../core/errors/user_message.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui/widgets.dart';
import '../../data/crm_repo.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({
    super.key,
    required this.repo,
    this.onChanged,
  });

  final CrmRepo repo;
  final VoidCallback? onChanged;

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.repo.catalog();
      if (mounted) setState(() => _items = rows);
    } catch (e) {
      if (mounted) setState(() => _error = userMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(Map<String, dynamic> item, bool active) async {
    try {
      await widget.repo.updateCatalogItem(
        item['id'].toString(),
        {'active': active},
      );
      widget.onChanged?.call();
      _load();
    } catch (e) {
      if (mounted) showAppMessage(context, userMessage(e), isError: true);
    }
  }

  Future<void> _add() async {
    final result = await showDialog<
        ({String name, String groupLabel, String description})>(
      context: context,
      builder: (_) => const _AddCatalogItemDialog(),
    );
    if (result == null) return;
    try {
      await widget.repo.addCatalogItem({
        'name': result.name,
        'group_label': result.groupLabel.isEmpty ? 'Khác' : result.groupLabel,
        'description': result.description,
      });
      if (!mounted) return;
      widget.onChanged?.call();
      showAppMessage(context, 'Đã thêm mẫu.');
      _load();
    } catch (e) {
      if (mounted) showAppMessage(context, userMessage(e), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Catalog mẫu')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _add,
        icon: const Icon(Icons.add),
        label: const Text('Thêm mẫu'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? EmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: 'Chưa tải được catalog',
                  message: _error,
                  action: OutlinedButton(
                    onPressed: _load,
                    child: const Text('Thử lại'),
                  ),
                )
              : _items.isEmpty
                  ? const EmptyState(
                      icon: Icons.collections_outlined,
                      title: 'Chưa có mẫu nào',
                      message:
                          'Thêm các mẫu theo chuyên môn của tiệm. Ứng dụng không có mẫu mặc định.',
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Text(
                            'Không nhập giá ở đây. Giá do tiệm đặt trong Business Suite.',
                            style: TextStyle(color: AppColors.textMuted),
                          ),
                        ),
                        for (final item in _items)
                          SectionCard(
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        (item['name'] ?? '').toString(),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Text(
                                        (item['group_label'] ?? 'Khác')
                                            .toString(),
                                        style: const TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 12,
                                        ),
                                      ),
                                      if ((item['description'] ?? '')
                                          .toString()
                                          .isNotEmpty)
                                        Text(
                                          (item['description'] ?? '')
                                              .toString(),
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                    ],
                                  ),
                                ),
                                Switch(
                                  value: item['active'] != false,
                                  onChanged: (v) => _toggle(item, v),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
    );
  }
}

class _AddCatalogItemDialog extends StatefulWidget {
  const _AddCatalogItemDialog();

  @override
  State<_AddCatalogItemDialog> createState() => _AddCatalogItemDialogState();
}

class _AddCatalogItemDialogState extends State<_AddCatalogItemDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _group = TextEditingController();
  final TextEditingController _desc = TextEditingController();
  String? _validationError;

  @override
  void dispose() {
    _name.dispose();
    _group.dispose();
    _desc.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.length < 2) {
      setState(() => _validationError = 'Tên mẫu cần ít nhất 2 ký tự.');
      return;
    }
    Navigator.of(context).pop((
      name: name,
      groupLabel: _group.text.trim(),
      description: _desc.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Thêm mẫu'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              onChanged: (_) {
                if (_validationError != null) {
                  setState(() => _validationError = null);
                }
              },
              decoration: const InputDecoration(labelText: 'Tên mẫu'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _group,
              decoration: const InputDecoration(
                labelText: 'Nhóm (ví dụ: Chân mày, Môi, Khác)',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _desc,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Mô tả ngắn (không ghi giá)',
              ),
            ),
            if (_validationError != null) ...[
              const SizedBox(height: 8),
              Text(
                _validationError!,
                style: const TextStyle(color: AppColors.danger, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Lưu'),
        ),
      ],
    );
  }
}
