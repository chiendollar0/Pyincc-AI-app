import 'package:flutter/material.dart';

import '../../core/errors/user_message.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui/widgets.dart';
import '../../data/crm_repo.dart';

String _dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

bool _sameDay(DateTime a, DateTime b) => _dayKey(a) == _dayKey(b);

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key, required this.repo});

  final CrmRepo repo;

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  List<Map<String, dynamic>> _all = [];
  bool _loading = true;
  String? _error;
  DateTime _day = DateTime.now();

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
      final rows = await widget.repo.bookings();
      if (mounted) setState(() => _all = rows);
    } catch (e) {
      if (mounted) setState(() => _error = userMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _dayBookings => _all.where((b) {
        final t =
            DateTime.tryParse((b['scheduled_at'] ?? '').toString())?.toLocal();
        return t != null && _sameDay(t, _day);
      }).toList()
        ..sort((a, b) => (a['scheduled_at'] ?? '')
            .toString()
            .compareTo((b['scheduled_at'] ?? '').toString()));

  List<Map<String, dynamic>> get _followUps {
    final today = _dayKey(DateTime.now());
    return _all.where((b) {
      final due = (b['follow_up_due'] ?? '').toString();
      return due.isNotEmpty && due.compareTo(today) <= 0;
    }).toList();
  }

  Future<void> _add() async {
    final result = await showDialog<
        ({
          String customer,
          String phone,
          String service,
          DateTime date,
          TimeOfDay time,
        })>(
      context: context,
      builder: (_) => _AddBookingDialog(initialDate: _day),
    );
    if (result == null) return;

    final hh = result.time.hour.toString().padLeft(2, '0');
    final mm = result.time.minute.toString().padLeft(2, '0');
    final scheduled = '${_dayKey(result.date)}T$hh:$mm:00+07:00';

    try {
      await widget.repo.createBooking({
        'customerName': result.customer,
        'customerPhone': result.phone,
        'serviceName': result.service,
        'scheduled_at': scheduled,
      });
      if (!mounted) return;
      showAppMessage(context, 'Đã thêm lịch hẹn.');
      setState(() => _day = result.date);
      _load();
    } catch (e) {
      if (mounted) showAppMessage(context, userMessage(e), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _dayBookings;
    return Column(
      children: [
        BrandHeader(
          title: 'Lịch hẹn',
          subtitle: _dayKey(_day),
          actions: [
            IconButton(
              tooltip: 'Ngày trước',
              onPressed: () =>
                  setState(() => _day = _day.subtract(const Duration(days: 1))),
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              tooltip: 'Ngày sau',
              onPressed: () =>
                  setState(() => _day = _day.add(const Duration(days: 1))),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? EmptyState(
                      icon: Icons.cloud_off_outlined,
                      title: 'Chưa tải được lịch',
                      message: _error,
                      action: OutlinedButton(
                        onPressed: _load,
                        child: const Text('Thử lại'),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
                        children: [
                          SectionCard(
                            title: 'Hẹn trong ngày (${items.length})',
                            child: items.isEmpty
                                ? const Text(
                                    'Chưa có lịch hẹn. Bấm Thêm lịch để nhập.',
                                    style:
                                        TextStyle(color: AppColors.textMuted),
                                  )
                                : Column(
                                    children: [
                                      for (final b in items) _BookingTile(b),
                                    ],
                                  ),
                          ),
                          SectionCard(
                            title: 'Cần nhắc kiểm tra sau dịch vụ',
                            child: _followUps.isEmpty
                                ? const Text(
                                    'Chưa có khách đến mốc 7 ngày.',
                                    style:
                                        TextStyle(color: AppColors.textMuted),
                                  )
                                : Column(
                                    children: [
                                      for (final b in _followUps)
                                        _BookingTile(b),
                                    ],
                                  ),
                          ),
                        ],
                      ),
                    ),
        ),
      ],
    ).withFab(
      FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Thêm lịch'),
      ),
    );
  }
}

class _AddBookingDialog extends StatefulWidget {
  const _AddBookingDialog({required this.initialDate});

  final DateTime initialDate;

  @override
  State<_AddBookingDialog> createState() => _AddBookingDialogState();
}

class _AddBookingDialogState extends State<_AddBookingDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _service = TextEditingController();
  late DateTime _date = widget.initialDate;
  TimeOfDay _time = const TimeOfDay(hour: 9, minute: 0);
  String? _validationError;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _service.dispose();
    super.dispose();
  }

  void _submit() {
    final customer = _name.text.trim();
    final serviceName = _service.text.trim();
    if (customer.length < 2 || serviceName.isEmpty) {
      setState(() => _validationError = 'Nhập tên khách và dịch vụ.');
      return;
    }
    Navigator.of(context).pop((
      customer: customer,
      phone: _phone.text.trim(),
      service: serviceName,
      date: _date,
      time: _time,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Thêm lịch hẹn'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              onChanged: (_) {
                if (_validationError != null) {
                  setState(() => _validationError = null);
                }
              },
              decoration: const InputDecoration(labelText: 'Tên khách'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Số điện thoại'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _service,
              onChanged: (_) {
                if (_validationError != null) {
                  setState(() => _validationError = null);
                }
              },
              decoration: const InputDecoration(labelText: 'Dịch vụ'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime.now().subtract(const Duration(days: 1)),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (d != null && mounted) setState(() => _date = d);
              },
              child: Text('Ngày: ${_dayKey(_date)}'),
            ),
            const SizedBox(height: 6),
            OutlinedButton(
              onPressed: () async {
                final t = await showTimePicker(
                  context: context,
                  initialTime: _time,
                );
                if (t != null && mounted) setState(() => _time = t);
              },
              child: Text('Giờ: ${_time.format(context)}'),
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

class _BookingTile extends StatelessWidget {
  const _BookingTile(this.b);

  final Map<String, dynamic> b;

  @override
  Widget build(BuildContext context) {
    final t = DateTime.tryParse((b['scheduled_at'] ?? '').toString())?.toLocal();
    final time = t == null
        ? '--:--'
        : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Text(time, style: const TextStyle(fontWeight: FontWeight.w800)),
      title: Text((b['customer_name'] ?? '').toString()),
      subtitle: Text(
        [
          (b['service_name'] ?? '').toString(),
          (b['customer_phone'] ?? '').toString(),
        ].where((s) => s.isNotEmpty).join(' • '),
      ),
    );
  }
}

extension _FabStack on Widget {
  Widget withFab(Widget fab) => Stack(
        children: [
          this,
          Positioned(right: 16, bottom: 16, child: fab),
        ],
      );
}
