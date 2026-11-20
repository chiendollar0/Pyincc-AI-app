// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../../core/errors/user_message.dart';
import '../../core/theme/app_theme.dart';
import '../../services/inbox_service.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({
    super.key,
    required this.inboxService,
    required this.onOpenTryOn,
    this.onSignOut,
  });

  final InboxService inboxService;
  final void Function({
    String? psid,
    String? customerName,
    String? pageId,
  }) onOpenTryOn;
  final VoidCallback? onSignOut;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  List<Map<String, dynamic>> _items = [];
  final Set<String> _sendingIds = {};
  bool _loading = true;
  String? _error;
  String _filter = 'all';

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
      final items = await widget.inboxService.fetchMessages(limit: 50);
      if (!mounted) return;
      setState(() => _items = items);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = userMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _countOf(String key) => key == 'all'
      ? _items.length
      : _items.where((e) => e['tagType'] == key).length;

  List<Map<String, dynamic>> get _visible => _filter == 'all'
      ? _items
      : _items.where((e) => e['tagType'] == _filter).toList();

  Future<void> _approveAndSend(Map<String, dynamic> item) async {
    final id = item['id'].toString();
    final psid = (item['psid'] ?? '').toString().trim();
    final draft = (item['aiSuggestion'] ?? '').toString().trim();
    if (_sendingIds.contains(id) || psid.isEmpty || draft.isEmpty) return;

    final text = await _confirmDialog(item, draft);
    if (text == null || text.isEmpty) return;

    setState(() => _sendingIds.add(id));
    try {
      await widget.inboxService.approveAndSend(
        messageRecordId: id,
        text: text,
      );
      if (!mounted) return;
      setState(() {
        item['tagType'] = 'replied';
        item['aiSuggestion'] = '';
      });
      showAppMessage(context, 'Đã gửi tin cho khách.');
    } catch (error) {
      if (!mounted) return;
      showAppMessage(context, userMessage(error), isError: true);
    } finally {
      if (mounted) setState(() => _sendingIds.remove(id));
    }
  }

  Future<String?> _confirmDialog(Map<String, dynamic> item, String draft) {
    final controller = TextEditingController(text: draft);
    final name = (item['name'] ?? 'Khách hàng').toString();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Gửi tin cho $name'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Kiểm tra nội dung trước khi gửi. Tin sẽ được gửi qua Messenger.',
              style: TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 6,
              maxLength: 2000,
              decoration: const InputDecoration(labelText: 'Nội dung tin nhắn'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Gửi cho khách'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  void _openStudio(Map<String, dynamic> item) {
    widget.onOpenTryOn(
      psid: item['psid']?.toString(),
      customerName: item['name']?.toString(),
      pageId: item['pageId']?.toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              onRefresh: _loading ? null : _load,
              onSignOut: widget.onSignOut,
              loading: _loading,
            ),
            if (_error == null && !_loading && _items.isNotEmpty) ...[
              _KpiStrip(
                total: _items.length,
                urgent: _countOf('urgent'),
                lead: _countOf('lead'),
              ),
              _FilterBar(
                selected: _filter,
                countOf: _countOf,
                onChanged: (key) => setState(() => _filter = key),
              ),
            ],
            Expanded(child: _body(visible)),
          ],
        ),
      ),
    );
  }

  Widget _body(List<Map<String, dynamic>> visible) {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _StateView(
        icon: Icons.cloud_off_outlined,
        title: 'Chưa tải được hội thoại',
        message: _error,
        actionLabel: 'Thử lại',
        onAction: _load,
      );
    }
    if (_items.isEmpty) {
      return const _StateView(
        icon: Icons.inbox_outlined,
        title: 'Chưa có hội thoại',
        message: 'Tin nhắn từ Fanpage của tiệm sẽ hiện ở đây.',
      );
    }
    if (visible.isEmpty) {
      return const _StateView(
        icon: Icons.filter_alt_off_outlined,
        title: 'Không có hội thoại trong mục này',
        message: 'Chọn mục khác để xem thêm.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: visible.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final item = visible[index];
          return _ConversationCard(
            item: item,
            sending: _sendingIds.contains(item['id'].toString()),
            onStudio: () => _openStudio(item),
            onSend: () => _approveAndSend(item),
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.onRefresh,
    required this.loading,
    this.onSignOut,
  });

  final VoidCallback? onRefresh;
  final VoidCallback? onSignOut;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/brand/logo.png',
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.spa_outlined,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pyincc AI CRM',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      'Hộp thư AI',
                      style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Làm mới',
                onPressed: onRefresh,
                icon: loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
              ),
              if (onSignOut != null)
                IconButton(
                  tooltip: 'Đăng xuất',
                  onPressed: onSignOut,
                  icon: const Icon(Icons.logout),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }
}

class _KpiStrip extends StatelessWidget {
  const _KpiStrip({
    required this.total,
    required this.urgent,
    required this.lead,
  });

  final int total;
  final int urgent;
  final int lead;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          _KpiTile(
            label: 'Tổng hội thoại',
            value: total,
            color: AppColors.primaryDark,
          ),
          const SizedBox(width: 10),
          _KpiTile(label: 'Cần xử lý', value: urgent, color: AppColors.danger),
          const SizedBox(width: 10),
          _KpiTile(
            label: 'Hỏi giá & lịch',
            value: lead,
            color: const Color(0xFFEF6C00),
          ),
        ],
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$value',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.selected,
    required this.countOf,
    required this.onChanged,
  });

  final String selected;
  final int Function(String key) countOf;
  final ValueChanged<String> onChanged;

  static const _filters = <(String, String)>[
    ('all', 'Tất cả'),
    ('urgent', 'Cần xử lý'),
    ('lead', 'Hỏi giá & lịch'),
    ('image', 'Gửi ảnh'),
    ('replied', 'Đã phản hồi'),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: _filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final (key, label) = _filters[index];
          final isSelected = key == selected;
          return ChoiceChip(
            label: Text('$label (${countOf(key)})'),
            selected: isSelected,
            onSelected: (_) => onChanged(key),
          );
        },
      ),
    );
  }
}

class _ConversationCard extends StatelessWidget {
  const _ConversationCard({
    required this.item,
    required this.sending,
    required this.onStudio,
    required this.onSend,
  });

  final Map<String, dynamic> item;
  final bool sending;
  final VoidCallback onStudio;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final name = (item['name'] ?? 'Khách hàng').toString();
    final summary = (item['summary'] ?? '').toString();
    final imageUrl = (item['imageUrl'] ?? '').toString();
    final draft = (item['aiSuggestion'] ?? '').toString().trim();
    final type = (item['tagType'] ?? 'normal').toString();
    final tag = _tagStyles[type] ?? _tagStyles['normal']!;
    final canSend =
        draft.isNotEmpty && (item['psid'] ?? '').toString().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: tag.color.withValues(alpha: 0.12),
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: tag.color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              _TagChip(label: tag.label, color: tag.color),
            ],
          ),
          const SizedBox(height: 10),
          if (summary.isNotEmpty)
            Text(
              summary,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
            ),
          if (imageUrl.isNotEmpty) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                imageUrl,
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : Container(
                        height: 160,
                        color: AppColors.surface,
                        alignment: Alignment.center,
                        child: const CircularProgressIndicator(strokeWidth: 2),
                      ),
                errorBuilder: (_, __, ___) => Container(
                  height: 160,
                  color: AppColors.surface,
                  alignment: Alignment.center,
                  child: const Text(
                    'Không tải được ảnh',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                ),
              ),
            ),
          ],
          if (draft.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Nội dung đề xuất',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    draft,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (imageUrl.isNotEmpty)
                TextButton(
                  onPressed: onStudio,
                  child: const Text('Mở Studio'),
                ),
              const SizedBox(width: 8),
              if (canSend)
                FilledButton(
                  onPressed: sending ? null : onSend,
                  child: sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Duyệt & gửi'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _StateView extends StatelessWidget {
  const _StateView({
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 56,
              color: AppColors.primary.withValues(alpha: 0.45),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class _TagStyle {
  const _TagStyle(this.label, this.color);

  final String label;
  final Color color;
}

const Map<String, _TagStyle> _tagStyles = {
  'urgent': _TagStyle('Cần xử lý', Color(0xFFC62828)),
  'lead': _TagStyle('Hỏi giá & lịch', Color(0xFFEF6C00)),
  'image': _TagStyle('Gửi ảnh', Color(0xFF1565C0)),
  'replied': _TagStyle('Đã phản hồi', Color(0xFF2E7D32)),
  'normal': _TagStyle('Tin mới', Color(0xFF7A6470)),
};
