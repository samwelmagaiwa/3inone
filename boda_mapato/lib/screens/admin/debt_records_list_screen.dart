import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../constants/theme_constants.dart';
import '../../providers/debts_provider.dart';
import '../../services/api_service.dart';
import '../../services/app_events.dart';
import '../../services/localization_service.dart';

class DebtRecordsListScreen extends StatefulWidget {
  const DebtRecordsListScreen(
      {required this.driverId, required this.driverName, super.key});
  final String driverId;
  final String driverName;

  @override
  State<DebtRecordsListScreen> createState() => _DebtRecordsListScreenState();
}

class _DebtRecordsListScreenState extends State<DebtRecordsListScreen> {
  final ApiService _api = ApiService();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _records = <Map<String, dynamic>>[];
  Map<String, dynamic>? _summary;
  bool _unpaidOnly = false;
  bool _paidOnly = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });
      // Use the new summary endpoint which consistently returns debt_records
      final Map<String, dynamic> res =
          await _api.getDriverDebtSummary(widget.driverId);
      final Map<String, dynamic>? data = res['data'] as Map<String, dynamic>?;
      _summary = Map<String, dynamic>.from(data ?? <String, dynamic>{});
      final List<dynamic> allItems = (data?['debt_records'] as List<dynamic>?) ??
          (res['debt_records'] as List<dynamic>?) ??
          <dynamic>[];
      // Compute paid vs unpaid totals from full list
      double totalPaid = 0;
      double totalUnpaid = 0;
      for (final dynamic e in allItems) {
        if (e is Map) {
          final m = e.cast<String, dynamic>();
          final v = m['is_paid'];
          final bool paid = v == true || v == 1;
          final double amount = double.tryParse(m['expected_amount']?.toString() ?? '') ?? 0;
          if (paid) {
            totalPaid += amount;
          } else {
            totalUnpaid += amount;
          }
        }
      }
      _summary!['total_paid_amount'] = totalPaid;
      _summary!['total_unpaid_amount'] = totalUnpaid;

      // Apply filter on client if requested
      List<dynamic> items = List<dynamic>.from(allItems);
      if (_unpaidOnly || _paidOnly) {
        items = items.where((e) {
          if (e is Map) {
            final m = e.cast<String, dynamic>();
            final v = m['is_paid'];
            final bool paid = v == true || v == 1;
            if (_unpaidOnly) return !paid;
            if (_paidOnly) return paid;
          }
          return true;
        }).toList();
      }
      _records = items.map((e) => (e as Map).cast<String, dynamic>()).toList();
    } on Exception catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: ThemeConstants.primaryBlue,
        appBar: ThemeConstants.buildAppBar(LocalizationService.instance.translateWith('debts_2', <Object?>[widget.driverName]),
            actions: <Widget>[
              IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
            ]),
        body: SafeArea(
          child: _loading
              ? ThemeConstants.buildLoadingWidget()
              : _error != null
                  ? Center(
                      child: Text(_error!,
                          style: const TextStyle(color: Colors.white70)))
                  : Column(
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Align(
                                alignment: Alignment.centerLeft,
                                child: ToggleButtons(
                                  isSelected: <bool>[_unpaidOnly, _paidOnly],
                                  onPressed: (int index) {
                                    setState(() {
                                      if (index == 0) {
                                        _unpaidOnly = !_unpaidOnly;
                                        if (_unpaidOnly) _paidOnly = false;
                                      } else {
                                        _paidOnly = !_paidOnly;
                                        if (_paidOnly) _unpaidOnly = false;
                                      }
                                    });
                                    _load();
                                  },
                                  borderRadius: BorderRadius.circular(10),
                                  color: Colors.white70,
                                  selectedColor: Colors.white,
                                  borderColor: Colors.white24,
                                  selectedBorderColor: Colors.white38,
                                  fillColor:
                                      ThemeConstants.primaryOrange.withOpacity(0.20),
                                  constraints: BoxConstraints(minHeight: 36.h, minWidth: 120.w),
                                  children: <Widget>[
                                    Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 12.w),
                                      child: Text(
                                        LocalizationService.instance
                                            .translate('filter_unpaid_only'),
                                        style: const TextStyle(color: Colors.white),
                                      ),
                                    ),
                                    Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 12.w),
                                      child: Text(
                                        LocalizationService.instance
                                            .translate('filter_paid_only'),
                                        style: const TextStyle(color: Colors.white),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (_summary != null) _SummaryHeader(summary: _summary!),
                            ],
                          ),
                        ),
                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: _load,
                            color: Colors.white,
                            backgroundColor: ThemeConstants.primaryBlue,
                            child: ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: _records.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (BuildContext context, int i) {
                                final Map<String, dynamic> r = _records[i];
                                final bool isPaid =
                                    r['is_paid'] as bool? ?? false;
                                return ThemeConstants.buildGlassCard(
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 4),
                                    title: Text(
                                        LocalizationService.instance.translateWith('date_2', <Object?>[r['formatted_date']]),
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600)),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Wrap(
                                        spacing: 8,
                                        runSpacing: 4,
                                        children: <Widget>[
                                          _chip(Icons.payments,
                                              LocalizationService.instance.translateWith('amount_2', <Object?>[r['expected_amount']])),
                                          if (r['license_number']
                                                  ?.toString()
                                                  .isNotEmpty ??
                                              false)
                                            _chip(Icons.badge,
                                                LocalizationService.instance.translateWith('license_2', <Object?>[r['license_number']])),
                                          _chip(
                                              isPaid
                                                  ? Icons.check_circle
                                                  : Icons.error_outline,
                                              isPaid
                                                  ? LocalizationService.instance.translate('settled')
                                                  : LocalizationService.instance.translate('unpaid_2'),
                                              color: isPaid
                                                  ? ThemeConstants.successGreen
                                                  : ThemeConstants.errorRed),
                                        ],
                                      ),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        IconButton(
                                          icon: Icon(Icons.edit,
                                              color: Colors.white70,
                                              size: 18.sp),
                                          onPressed: isPaid
                                              ? null
                                              : () async {
                                                  final bool? changed =
                                                      await Navigator.push(
                                                    context,
                                                    MaterialPageRoute<bool>(
                                                      builder: (BuildContext
                                                              context) =>
                                                          _EditDebtRecordScreen(
                                                              record: r),
                                                      fullscreenDialog: true,
                                                    ),
                                                  );
                                                  if (changed ?? false) {
                                                    await _load();
                                                    if (!context.mounted) {
                                                      return;
                                                    }
                                                    Provider.of<DebtsProvider>(
                                                            context,
                                                            listen: false)
                                                        .markChanged();

                                                    // Emit events to notify other screens of debt changes
                                                    AppEvents.instance.emit(
                                                        AppEventType
                                                            .debtsUpdated);
                                                    AppEvents.instance.emit(
                                                        AppEventType
                                                            .receiptsUpdated);
                                                    AppEvents.instance.emit(
                                                        AppEventType
                                                            .dashboardShouldRefresh);
                                                  }
                                                },
                                        ),
                                        IconButton(
                                          icon: Icon(Icons.delete,
                                              color: Colors.white70,
                                              size: 18.sp),
                                          onPressed: isPaid
                                              ? null
                                              : () => _confirmDelete(
                                                  r['id'].toString()),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
        ),
      );

  Widget _chip(IconData icon, String text, {Color color = Colors.white70}) =>
      Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Icon(icon, color: color, size: 14.sp),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(color: color, fontSize: 12.sp)),
        ]),
      );

  Future<void> _confirmDelete(String id) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: ThemeConstants.primaryBlue,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(LocalizationService.instance.translate('delete_debt'), style: TextStyle(color: Colors.white)),
        content: Text('${LocalizationService.instance.translate('are_you_sure_you_want_to_6')}?',
            style: TextStyle(color: Colors.white70)),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(LocalizationService.instance.translate('no'),
                  style: TextStyle(color: Colors.white70))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(LocalizationService.instance.translate('yes'),
                  style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (ok ?? false) {
      await _api.deleteDebtRecord(id);
      if (!mounted) return;
      Provider.of<DebtsProvider>(context, listen: false).markChanged();
      await _load();

      // Emit events to notify other screens of debt changes
      AppEvents.instance.emit(AppEventType.debtsUpdated);
      AppEvents.instance.emit(AppEventType.receiptsUpdated);
      AppEvents.instance.emit(AppEventType.dashboardShouldRefresh);
    }
  }
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({required this.summary});
  final Map<String, dynamic> summary;
  @override
  Widget build(BuildContext context) {
    String t(String k) => LocalizationService.instance.translate(k);
    double toDouble(Object? v) {
      if (v == null) return 0;
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? 0;
      return 0;
    }

    final double totalDebt = toDouble(summary['total_debt']);
    final double totalPaid = toDouble(summary['total_paid_amount']);
    final double totalUnpaid = toDouble(summary['total_unpaid_amount']);
    final int unpaidDays = int.tryParse(summary['unpaid_days']?.toString() ?? '0') ?? 0;
    final String? lastPaidIso = summary['last_payment_date']?.toString();
    String lastPaid = '';
    if (lastPaidIso != null && lastPaidIso.isNotEmpty) {
      final DateTime? dt = DateTime.tryParse(lastPaidIso);
      if (dt != null) {
        lastPaid = '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
      }
    }

    return ThemeConstants.buildGlassCard(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.w),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                AutoSizeText('${t('summary_total_debt')}: TSH ${_fmt(totalDebt)}',
                    maxLines: 1,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('${t('summary_unpaid_days')}: $unpaidDays',
                    style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 6),
                Row(children: <Widget>[
                  Expanded(
                    child: Text('${t('paid_total')}: TSH ${_fmt(totalPaid)}',
                        style: const TextStyle(color: Colors.white70)),
                  ),
                  Expanded(
                    child: Text('${t('unpaid_total')}: TSH ${_fmt(totalUnpaid)}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(color: Colors.white70)),
                  ),
                ]),
                ],
              ),
            ),
            if (lastPaid.isNotEmpty)
            Text('${t('last_payment')}: $lastPaid',
                style: const TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }

  String _fmt(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}K';
    return v.toStringAsFixed(0);
  }
}

class _EditDebtRecordScreen extends StatefulWidget {
  const _EditDebtRecordScreen({required this.record});
  final Map<String, dynamic> record;

  @override
  State<_EditDebtRecordScreen> createState() => _EditDebtRecordScreenState();
}

class _EditDebtRecordScreenState extends State<_EditDebtRecordScreen> {
  final ApiService _api = ApiService();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late TextEditingController _amount;
  late TextEditingController _notes;
  DateTime _date = DateTime.now();
  bool _promised = false;
  DateTime? _promiseDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
        text: (widget.record['expected_amount'] ?? '').toString());
    _notes =
        TextEditingController(text: (widget.record['notes'] ?? '').toString());
    final String? ds = widget.record['date']?.toString();
    if (ds != null && ds.isNotEmpty) _date = DateTime.tryParse(ds) ?? _date;
    _promised = (widget.record['promised_to_pay'] as bool?) ?? false;
    final String? ps = widget.record['promise_to_pay_at']?.toString();
    if (ps != null && ps.isNotEmpty) _promiseDate = DateTime.tryParse(ps);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: ThemeConstants.primaryBlue,
        appBar: ThemeConstants.buildAppBar(LocalizationService.instance.translate('edit_debt')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _label(LocalizationService.instance.translate('debt_date')),
                    const SizedBox(height: 6),
                    Row(children: <Widget>[
                      Expanded(child: _value(_fmt(_date))),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                          onPressed: _pickDate,
                          icon: const Icon(Icons.event),
                          label: Text(LocalizationService.instance.translate('select')),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: ThemeConstants.primaryOrange,
                              foregroundColor: Colors.white)),
                    ]),
                    const SizedBox(height: 12),
                    _label(LocalizationService.instance.translate('debt_amount_tsh')),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _amount,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: _input(LocalizationService.instance.translate('enter_the_amount')),
                      validator: (String? v) {
                        final double? a = double.tryParse((v ?? '').trim());
                        if (a == null || a <= 0) return LocalizationService.instance.translate('enter_a_valid_amount');
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    _label(LocalizationService.instance.translate('note_optional')),
                    const SizedBox(height: 6),
                    TextFormField(
                        controller: _notes,
                        minLines: 2,
                        maxLines: 4,
                        style: const TextStyle(color: Colors.white),
                        decoration: _input('${LocalizationService.instance.translate('write_details')}...')),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      value: _promised,
                      onChanged: (bool? v) =>
                          setState(() => _promised = v ?? false),
                      title: Text('${LocalizationService.instance.translate('did_they_promise_to_pay')}?',
                          style: TextStyle(color: Colors.white)),
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: ThemeConstants.primaryOrange,
                    ),
                    if (_promised) ...<Widget>[
                      Row(children: <Widget>[
                        Expanded(
                            child: _value(_promiseDate == null
                                ? LocalizationService.instance.translate('select_a_date')
                                : _fmt(_promiseDate!))),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                            onPressed: _pickPromiseDate,
                            icon: const Icon(Icons.event),
                            label: Text(LocalizationService.instance.translate('select')),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: ThemeConstants.primaryOrange,
                                foregroundColor: Colors.white)),
                      ]),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.save),
                        label: Text(
                            _saving ? '${LocalizationService.instance.translate('saving')}...' : LocalizationService.instance.translate('save_changes')),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: ThemeConstants.primaryOrange,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 48)),
                      ),
                    ),
                  ]),
            ),
          ),
        ),
      );

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
      builder: (BuildContext context, Widget? child) => Theme(
          data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.dark(
                  primary: ThemeConstants.primaryOrange,
                  surface: ThemeConstants.primaryBlue,
                  onPrimary: Colors.white),
              textButtonTheme: TextButtonThemeData(
                  style: TextButton.styleFrom(foregroundColor: Colors.white))),
          child: child!),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickPromiseDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _promiseDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
      builder: (BuildContext context, Widget? child) => Theme(
          data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.dark(
                  primary: ThemeConstants.primaryOrange,
                  surface: ThemeConstants.primaryBlue,
                  onPrimary: Colors.white),
              textButtonTheme: TextButtonThemeData(
                  style: TextButton.styleFrom(foregroundColor: Colors.white))),
          child: child!),
    );
    if (picked != null) setState(() => _promiseDate = picked);
  }

  InputDecoration _input(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white70),
        filled: true,
        fillColor: Colors.white.withOpacity(0.08),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
      );

  Widget _label(String t) =>
      Text(t, style: const TextStyle(color: Colors.white70, fontSize: 12));
  Widget _value(String t) => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12)),
      child: Text(t, style: const TextStyle(color: Colors.white)));
  String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await _api.updateDebtRecord(
        debtId: widget.record['id'].toString(),
        earningDate: _fmt(_date),
        expectedAmount: double.tryParse(_amount.text.trim()),
        notes: _notes.text.trim(),
        promisedToPay: _promised,
        promiseToPayAt: _promiseDate,
      );
      if (!mounted) return;
      Provider.of<DebtsProvider>(context, listen: false).markChanged();

      // Emit events to notify other screens of debt changes
      AppEvents.instance.emit(AppEventType.debtsUpdated);
      AppEvents.instance.emit(AppEventType.receiptsUpdated);
      AppEvents.instance.emit(AppEventType.dashboardShouldRefresh);

      Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
