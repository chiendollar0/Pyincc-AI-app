import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/errors/user_message.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui/widgets.dart';
import '../../data/crm_repo.dart';

const _statusLabels = {
  'pending_review': 'Chờ duyệt',
  'new': 'Mới',
  'approved': 'Đã duyệt',
  'sending': 'Đang gửi',
  'sent': 'Đã gửi',
  'rejected': 'Đã từ chối',
  'failed': 'Lỗi',
};

const _statusColors = {
  'pending_review': Color(0xFFEF6C00),
  'new': Color(0xFF8E24AA),
  'approved': Color(0xFF1565C0),
  'sending': Color(0xFF1565C0),
  'sent': Color(0xFF2E7D32),
  'rejected': Color(0xFF7A6470),
  'failed': Color(0xFFC62828),
};

class InboxScreen extends StatefulWidget {
  const InboxScreen({
    super.key,
    required this.repo,
    this.refreshVersion = 0,
  });

  final CrmRepo repo;
  final int refreshVersion;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  String _status = 'pending_review';
  List<Map<String, dynamic>> _cases = [];
  bool _loading = true;
  bool _fetching = false;
  String? _error;
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _autoRefreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _load(silent: true),
    );
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant InboxScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshVersion != oldWidget.refreshVersion) {
      _load();
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (_fetching && silent) return;
    _fetching = true;
    final requestedStatus = _status;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final rows = await widget.repo.handoffCases(requestedStatus);
      if (mounted && _status == requestedStatus) {
        setState(() {
          _cases = rows;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && _status == requestedStatus && !silent) {
        setState(() => _error = userMessage(e));
      }
    } finally {
      _fetching = false;
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  void _select(String status) {
    setState(() => _status = status);
    _load();
  }

  Future<void> _open(Map<String, dynamic> data) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CaseSheet(repo: widget.repo, data: data),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final handover =
        _cases.where((c) => c['source'] == 'business_ai_handover').toList();
    final own =
        _cases.where((c) => c['source'] != 'business_ai_handover').toList();

    return Column(
      children: [
        BrandHeader(
          title: 'Pyincc AI CRM',
          subtitle: 'Hộp thư',
          actions: [
            IconButton(
              tooltip: 'Làm mới',
              onPressed: _loading ? null : () => _load(),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final e in _statusLabels.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(e.value),
                    selected: _status == e.key,
                    onSelected: (_) => _select(e.key),
                  ),
                ),
            ],
          ),
        ),
        Expanded(child: _body(handover, own)),
      ],
    );
  }

  Widget _body(
    List<Map<String, dynamic>> handover,
    List<Map<String, dynamic>> own,
  ) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Chưa tải được hộp thư',
        message: _error,
        action: OutlinedButton(
          onPressed: () => _load(),
          child: const Text('Thử lại'),
        ),
      );
    }
    if (_cases.isEmpty) {
      return const EmptyState(
        icon: Icons.inbox_outlined,
        title: 'Chưa có ca nào',
        message:
            'Khách được Business AI chuyển sang và ảnh chủ tiệm chụp sẽ hiện ở đây.',
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (handover.isNotEmpty) ...[
            _GroupTitle('Khách chuyển từ Business AI (${handover.length})'),
            for (final c in handover) _CaseCard(data: c, onTap: () => _open(c)),
          ],
          if (own.isNotEmpty) ...[
            _GroupTitle('Ảnh chủ tiệm chụp (${own.length})'),
            for (final c in own) _CaseCard(data: c, onTap: () => _open(c)),
          ],
        ],
      ),
    );
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 8, 2, 8),
        child: Text(
          text,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: AppColors.textMuted,
          ),
        ),
      );
}

class _CaseCard extends StatelessWidget {
  const _CaseCard({required this.data, required this.onTap});

  final Map<String, dynamic> data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = (data['status'] ?? '').toString();
    final analysis = data['analysis'] is Map
        ? Map<String, dynamic>.from(data['analysis'] as Map)
        : <String, dynamic>{};
    final summary = (analysis['brow_or_lip_observation'] ??
            analysis['summary'] ??
            data['customer_text'] ??
            '')
        .toString();
    final imageUrl = (data['image_url'] ?? '').toString();

    return SectionCard(
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    data['source'] == 'business_ai_handover'
                        ? 'Khách chuyển từ Business AI'
                        : 'Ảnh chủ tiệm chụp',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                StatusPill(
                  label: _statusLabels[status] ?? status,
                  color: _statusColors[status] ?? AppColors.textMuted,
                ),
              ],
            ),
            if (summary.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(summary, maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
            if (imageUrl.isNotEmpty) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  imageUrl,
                  height: 120,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(
                    height: 120,
                    child: Center(child: Text('Không tải được ảnh')),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CaseSheet extends StatefulWidget {
  const _CaseSheet({required this.repo, required this.data});

  final CrmRepo repo;
  final Map<String, dynamic> data;

  @override
  State<_CaseSheet> createState() => _CaseSheetState();
}

class _CaseSheetState extends State<_CaseSheet> {
  late final TextEditingController _draft;
  late Map<String, dynamic> _analysis;
  late String _status;
  bool _busy = false;
  bool _changed = false;

  bool get _fromHandover => widget.data['source'] == 'business_ai_handover';
  bool get _hasRecipient =>
      (widget.data['psid'] ?? '').toString().isNotEmpty &&
      (widget.data['page_id'] ?? '').toString().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _status = (widget.data['status'] ?? '').toString();
    _analysis = widget.data['analysis'] is Map
        ? Map<String, dynamic>.from(widget.data['analysis'] as Map)
        : <String, dynamic>{};
    _draft = TextEditingController(
      text: (widget.data['draft_reply'] ?? _analysis['draft_reply'] ?? '')
          .toString(),
    );
  }

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Future<void> _run(
    Future<void> Function() action,
    String okText, {
    bool close = true,
    String? nextStatus,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      _changed = true;
      showAppMessage(context, okText);
      if (close) {
        Navigator.of(context).pop(true);
      } else if (nextStatus != null) {
        setState(() => _status = nextStatus);
      }
    } catch (e) {
      if (!mounted) return;
      showAppMessage(context, userMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _analyze(String id) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final res = await widget.repo.analyzeCase(id);
      if (!mounted) return;
      final nextAnalysis = res['analysis'] is Map
          ? Map<String, dynamic>.from(res['analysis'] as Map)
          : <String, dynamic>{};
      final draft = (nextAnalysis['draft_reply'] ?? '').toString();
      setState(() {
        _changed = true;
        _status = (res['status'] ?? 'pending_review').toString();
        _analysis = nextAnalysis;
        if (draft.isNotEmpty) _draft.text = draft;
      });
      showAppMessage(context, 'Đã phân tích AI xong. Vui lòng xem và duyệt.');
    } catch (e) {
      if (!mounted) return;
      showAppMessage(context, userMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve(String id) {
    final text = _draft.text.trim();
    if (text.isEmpty) {
      showAppMessage(context, 'Nội dung trả lời đang trống.', isError: true);
      return Future.value();
    }
    return _run(
      () => widget.repo.approve(id, text),
      'Đã duyệt. Bấm Gửi khi sẵn sàng.',
      close: false,
      nextStatus: 'approved',
    );
  }

  Future<void> _confirmSend(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gửi cho khách?'),
        content: Text(_draft.text.trim()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Gửi'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _run(() => widget.repo.send(id), 'Đã gửi cho khách.');
    }
  }

  Future<void> _confirmRelease(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Trả quyền về Business AI?'),
        content: const Text(
          'Hội thoại này sẽ được trả lại cho Business AI của Meta tiếp tục trả lời khách.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Trả Business AI'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _run(
        () => widget.repo.releaseCase(id),
        'Đã trả hội thoại về Business AI.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.data['id'].toString();
    final editable = _status == 'pending_review';
    final canAnalyze = _status == 'new' || _status == 'failed';
    final observation =
        (_analysis['brow_or_lip_observation'] ?? _analysis['summary'] ?? '')
            .toString();
    final customerText = (widget.data['customer_text'] ?? '').toString().trim();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _fromHandover
                    ? 'Khách chuyển từ Business AI'
                    : 'Ảnh chủ tiệm chụp',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              if (customerText.isNotEmpty) ...[
                Text(
                  'Ghi chú / yêu cầu: $customerText',
                  style: const TextStyle(color: AppColors.textMuted),
                ),
                const SizedBox(height: 6),
              ],
              if (_analysis['face_detected'] == false)
                const Text(
                  'Chưa nhận diện được khuôn mặt. Không dùng ảnh này để tư vấn.',
                ),
              if (observation.isNotEmpty) Text('Quan sát: $observation'),
              if ((_analysis['fit_note'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Lưu ý cho chủ: ${_analysis['fit_note']}'),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _draft,
                enabled: editable && !_busy,
                maxLines: 6,
                maxLength: 2000,
                decoration: InputDecoration(
                  labelText: 'Nội dung trả lời khách',
                  helperText: canAnalyze
                      ? 'Bấm Phân tích AI để tạo bản nháp gợi ý'
                      : editable
                          ? 'Sửa trước khi duyệt'
                          : 'Đã duyệt, không sửa được',
                ),
              ),
              if (_fromHandover && !_hasRecipient)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'Thiếu thông tin người nhận, không thể gửi.',
                    style: TextStyle(color: AppColors.danger),
                  ),
                ),
              if (!_fromHandover && !_hasRecipient)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'Ca tự chụp tại tiệm chưa gắn người nhận Messenger.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 12),
              _actions(id, editable, canAnalyze),
              if (_fromHandover &&
                  _hasRecipient &&
                  _status != 'sending' &&
                  _status != 'rejected') ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _confirmRelease(id),
                    icon: const Icon(Icons.undo, size: 18),
                    label: const Text('Trả Business AI'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _actions(String id, bool editable, bool canAnalyze) {
    if (canAnalyze) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _run(() => widget.repo.reject(id), 'Đã từ chối.'),
              child: const Text('Từ chối'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.icon(
              onPressed: _busy ? null : () => _analyze(id),
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.auto_awesome, size: 18),
              label: Text(_busy ? 'Đang phân tích...' : 'Phân tích AI'),
            ),
          ),
        ],
      );
    }
    if (editable) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _run(() => widget.repo.reject(id), 'Đã từ chối.'),
              child: const Text('Từ chối'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              onPressed: _busy ? null : () => _approve(id),
              child: const Text('Duyệt'),
            ),
          ),
        ],
      );
    }
    if (_status == 'approved') {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _run(() => widget.repo.reject(id), 'Đã từ chối.'),
              child: const Text('Từ chối'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.icon(
              onPressed: _hasRecipient && !_busy ? () => _confirmSend(id) : null,
              icon: const Icon(Icons.send, size: 18),
              label: const Text('Gửi cho khách'),
            ),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }
}
