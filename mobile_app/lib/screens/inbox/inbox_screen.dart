// ignore_for_file: deprecated_member_use
import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/errors/user_message.dart';
import '../../core/theme/app_theme.dart';
import '../../services/handoff_service.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({
    super.key,
    required this.handoffService,
    required this.onOpenTryOn,
    this.onSignOut,
  });

  final HandoffService handoffService;
  final void Function({String? customerName}) onOpenTryOn;
  final VoidCallback? onSignOut;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  List<HandoffCase> _cases = const [];
  final Set<String> _busyIds = {};
  bool _loading = true;
  String? _error;
  String _filter = 'all';
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _load(silent: true),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final items = await widget.handoffService.fetchCases(
        status: 'new,failed,pending_review,approved',
      );
      if (!mounted) return;
      setState(() {
        _cases = items;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      if (!silent || _cases.isEmpty) {
        setState(() => _error = userMessage(error));
      }
    } finally {
      if (!silent && mounted) setState(() => _loading = false);
    }
  }

  List<HandoffCase> get _visible {
    if (_filter == 'all') return _cases;
    if (_filter == 'high') {
      return _cases.where((c) => c.risk == 'high').toList();
    }
    if (_filter == 'pending_review') {
      return _cases
          .where((c) =>
              c.status == 'pending_review' ||
              c.status == 'new' ||
              c.status == 'failed')
          .toList();
    }
    return _cases.where((c) => c.status == _filter).toList();
  }

  int _countOf(String key) {
    if (key == 'all') return _cases.length;
    if (key == 'high') return _cases.where((c) => c.risk == 'high').length;
    if (key == 'pending_review') {
      return _cases
          .where((c) =>
              c.status == 'pending_review' ||
              c.status == 'new' ||
              c.status == 'failed')
          .length;
    }
    return _cases.where((c) => c.status == key).length;
  }

  Future<void> _analyze(HandoffCase item) async {
    if (_busyIds.contains(item.id)) return;
    setState(() => _busyIds.add(item.id));
    try {
      await widget.handoffService.analyzeCase(item.id);
      if (!mounted) return;
      showAppMessage(context, 'Đã phân tích ca tư vấn (chưa gửi đi).');
      await _load(silent: true);
    } catch (error) {
      if (!mounted) return;
      showAppMessage(context, userMessage(error), isError: true);
    } finally {
      if (mounted) setState(() => _busyIds.remove(item.id));
    }
  }

  Future<void> _approve(HandoffCase item) async {
    if (_busyIds.contains(item.id)) return;
    final edited = await _editDraftDialog(item);
    if (edited == null || edited.isEmpty) return;

    setState(() => _busyIds.add(item.id));
    try {
      await widget.handoffService.approveCase(
        id: item.id,
        draftReply: edited,
      );
      if (!mounted) return;
      showAppMessage(context, 'Đã duyệt ca tư vấn (chưa gửi đi).');
      await _load(silent: true);
    } catch (error) {
      if (!mounted) return;
      showAppMessage(context, userMessage(error), isError: true);
    } finally {
      if (mounted) setState(() => _busyIds.remove(item.id));
    }
  }

  Future<void> _reject(HandoffCase item) async {
    if (_busyIds.contains(item.id)) return;
    setState(() => _busyIds.add(item.id));
    try {
      await widget.handoffService.rejectCase(item.id);
      if (!mounted) return;
      showAppMessage(context, 'Đã từ chối bản nháp.');
      await _load(silent: true);
    } catch (error) {
      if (!mounted) return;
      showAppMessage(context, userMessage(error), isError: true);
    } finally {
      if (mounted) setState(() => _busyIds.remove(item.id));
    }
  }

  Future<void> _send(HandoffCase item) async {
    if (_busyIds.contains(item.id)) return;
    setState(() => _busyIds.add(item.id));
    try {
      await widget.handoffService.sendCase(item.id);
      if (!mounted) return;
      showAppMessage(context, 'Đã gửi tin qua Messenger cho khách.');
      await _load(silent: true);
    } catch (error) {
      if (!mounted) return;
      showAppMessage(context, userMessage(error), isError: true);
    } finally {
      if (mounted) setState(() => _busyIds.remove(item.id));
    }
  }

  Future<void> _release(HandoffCase item) async {
    if (_busyIds.contains(item.id)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Trả hội thoại về Business AI'),
        content: const Text(
          'Xác nhận trả quyền kiểm soát hội thoại này về trạng thái rảnh (Business AI tiếp nhận lại)?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Trả quyền'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busyIds.add(item.id));
    try {
      await widget.handoffService.releaseCase(item.id);
      if (!mounted) return;
      showAppMessage(context, 'Đã trả hội thoại về Business AI.');
      await _load(silent: true);
    } catch (error) {
      if (!mounted) return;
      showAppMessage(context, userMessage(error), isError: true);
    } finally {
      if (mounted) setState(() => _busyIds.remove(item.id));
    }
  }

  Future<String?> _editDraftDialog(HandoffCase item) {
    final controller = TextEditingController(text: item.draftReply);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Duyệt nội dung trả lời'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Kiểm tra và chỉnh sửa nội dung trước khi duyệt. Sau khi duyệt bạn mới bấm Gửi.',
              style: TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 6,
              maxLength: 2000,
              decoration: const InputDecoration(labelText: 'Nội dung trả lời'),
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
            child: const Text('Xác nhận duyệt'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              onRefresh: _loading ? null : () => _load(),
              onSignOut: widget.onSignOut,
              loading: _loading,
            ),
            if (_error == null && !_loading && _cases.isNotEmpty) ...[
              _KpiStrip(
                total: _cases.length,
                highRisk: _countOf('high'),
                approved: _countOf('approved'),
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

  Widget _body(List<HandoffCase> visible) {
    if (_loading && _cases.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _cases.isEmpty) {
      return _StateView(
        icon: Icons.cloud_off_outlined,
        title: 'Chưa tải được danh sách ca',
        message: _error,
        actionLabel: 'Thử lại',
        onAction: () => _load(),
      );
    }
    if (_cases.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _load(),
        child: ListView(
          children: const [
            SizedBox(height: 48),
            _StateView(
              icon: Icons.inbox_outlined,
              title: 'Chưa có ca chờ duyệt',
              message:
                  'Ca chuyển từ Business AI hoặc ảnh chủ tiệm chụp ở Studio sẽ hiện tại đây.',
            ),
          ],
        ),
      );
    }
    if (visible.isEmpty) {
      return const _StateView(
        icon: Icons.filter_alt_off_outlined,
        title: 'Không có ca trong mục này',
        message: 'Chọn mục lọc khác để xem thêm.',
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: visible.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final item = visible[index];
          return _CaseCard(
            item: item,
            busy: _busyIds.contains(item.id),
            onAnalyze: () => _analyze(item),
            onApprove: () => _approve(item),
            onReject: () => _reject(item),
            onSend: () => _send(item),
            onRelease: () => _release(item),
            onStudio: () => widget.onOpenTryOn(
              customerName: item.source == 'business_ai_handover'
                  ? 'Khách Messenger'
                  : 'Khách tại tiệm',
            ),
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
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      'Hộp thư AI',
                      style:
                          TextStyle(fontSize: 13, color: AppColors.textMuted),
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
    required this.highRisk,
    required this.approved,
  });

  final int total;
  final int highRisk;
  final int approved;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          _KpiTile(
            label: 'Chờ xử lý',
            value: total,
            color: AppColors.primaryDark,
          ),
          const SizedBox(width: 10),
          _KpiTile(label: 'Rủi ro cao', value: highRisk, color: AppColors.danger),
          const SizedBox(width: 10),
          _KpiTile(label: 'Đã duyệt', value: approved, color: AppColors.success),
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
    ('pending_review', 'Chờ duyệt'),
    ('approved', 'Đã duyệt'),
    ('high', 'Rủi ro cao'),
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
          return ChoiceChip(
            label: Text('$label (${countOf(key)})'),
            selected: key == selected,
            onSelected: (_) => onChanged(key),
          );
        },
      ),
    );
  }
}

class _CaseCard extends StatelessWidget {
  const _CaseCard({
    required this.item,
    required this.busy,
    required this.onAnalyze,
    required this.onApprove,
    required this.onReject,
    required this.onSend,
    required this.onRelease,
    required this.onStudio,
  });

  final HandoffCase item;
  final bool busy;
  final VoidCallback onAnalyze;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onSend;
  final VoidCallback onRelease;
  final VoidCallback onStudio;

  Color get _riskColor {
    switch (item.risk) {
      case 'high':
        return AppColors.danger;
      case 'medium':
        return const Color(0xFFEF6C00);
      default:
        return AppColors.success;
    }
  }

  String get _riskLabel {
    switch (item.risk) {
      case 'high':
        return 'Rủi ro cao';
      case 'medium':
        return 'Rủi ro trung bình';
      default:
        return 'Rủi ro thấp';
    }
  }

  @override
  Widget build(BuildContext context) {
    final sourceLabel = item.source == 'business_ai_handover'
        ? 'Business AI chuyển ca'
        : 'Chủ tiệm chụp tại tiệm';
    final displayText = item.summary.isNotEmpty
        ? item.summary
        : item.customerText;
    final needsAnalysis = item.status == 'new' || item.status == 'failed';

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
              Expanded(
                child: Text(
                  sourceLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _riskColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  needsAnalysis ? 'Chưa phân tích' : _riskLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: needsAnalysis ? AppColors.primary : _riskColor,
                  ),
                ),
              ),
            ],
          ),
          if (displayText.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              displayText,
              style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
            ),
          ],
          if (item.imageUrl.isNotEmpty) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                item.imageUrl,
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 120,
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
          if (item.draftReply.isNotEmpty) ...[
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
                  Text(
                    item.status == 'approved'
                        ? 'Nội dung đã duyệt (sẵn sàng gửi)'
                        : 'Nội dung nháp AI đề xuất',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.draftReply,
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              TextButton(
                onPressed: busy ? null : onReject,
                child: const Text('Từ chối'),
              ),
              if (item.canRelease)
                TextButton(
                  onPressed: busy ? null : onRelease,
                  child: const Text('Trả Business AI'),
                ),
              if (needsAnalysis)
                OutlinedButton(
                  onPressed: busy ? null : onAnalyze,
                  child: const Text('Phân tích AI'),
                ),
              if (item.status == 'pending_review')
                OutlinedButton(
                  onPressed: busy ? null : onApprove,
                  child: const Text('Duyệt'),
                ),
              if (item.canSend)
                FilledButton(
                  onPressed: busy ? null : onSend,
                  child: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Gửi'),
                ),
            ],
          ),
        ],
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
