import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../constants/theme_constants.dart';
import '../../services/api_service.dart';
import '../../services/localization_service.dart';

class PaymentsManagementScreen extends StatefulWidget {
  const PaymentsManagementScreen({super.key, this.initialDriverId});
  final String? initialDriverId;

  @override
  State<PaymentsManagementScreen> createState() =>
      _PaymentsManagementScreenState();
}

class _PaymentsManagementScreenState extends State<PaymentsManagementScreen> {
  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ThemeConstants.showErrorSnackBar(context, message);
  }

  final ApiService _api = ApiService();

  // Helper method to convert various types to double
  double _toDouble(Object? value) {
    if (value == null) return 0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      return double.tryParse(value) ?? 0;
    }
    return 0;
  }

  bool _loadingDrivers = true;
  bool _loadingSummary = false;
  String? _error;

  List<Map<String, dynamic>> _drivers = <Map<String, dynamic>>[];
  String? _selectedDriverId;
  Map<String, dynamic>?
      _summary; // { driver_id, driver_name, total_debt, unpaid_days, debt_records: [] }

  @override
  void initState() {
    super.initState();
    _selectedDriverId = widget.initialDriverId;
    _loadDrivers();
    if (widget.initialDriverId != null) {
      _loadSummary(widget.initialDriverId!);
    }
  }

  Future<void> _loadDrivers() async {
    if (!mounted) return;
    setState(() {
      _loadingDrivers = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> res = await _api.getDebtDrivers();
      if (!mounted) return;
      final dynamic data = res['data'];
      final List<dynamic> list = (data is Map && data['drivers'] is List)
          ? (data['drivers'] as List)
          : <dynamic>[];
      _drivers = list.map((e) => (e as Map).cast<String, dynamic>()).toList();
      if (_selectedDriverId != null) {
        await _loadSummary(_selectedDriverId!);
      }
    } on Exception catch (e) {
      if (!mounted) return;
      _error = LocalizationService.instance.translateWith('could_not_load_data', <Object?>[e]);
    } finally {
      if (mounted) setState(() => _loadingDrivers = false);
    }
  }

  Future<void> _loadSummary(String driverId) async {
    if (!mounted) return;
    setState(() {
      _loadingSummary = true;
      _error = null;
      _selectedDriverId = driverId;
    });
    try {
      final Map<String, dynamic> res =
          await _api.getDriverDebtSummary(driverId);
      if (!mounted) return;
      _summary = (res['data'] as Map?)?.cast<String, dynamic>();
    } on Exception catch (e) {
      if (!mounted) return;
      _error = LocalizationService.instance.translateWith('could_not_load_the_summary', <Object?>[e]);
    } finally {
      if (mounted) setState(() => _loadingSummary = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LocalizationService>(
      builder: (context, localizationService, child) =>
          ThemeConstants.buildResponsiveScaffold(
        context,
        title: localizationService.translate('manage_payments'),
        body: _loadingDrivers
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(_error!,
                          style: const TextStyle(color: Colors.white)),
                    ),
                  )
                : LayoutBuilder(
                    builder:
                        (BuildContext context, BoxConstraints constraints) {
                      final bool isNarrow = constraints.maxWidth < 800;
                      if (isNarrow) {
                        // Stack vertically on small screens to avoid overflow
                        return SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 80),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                SizedBox(
                                    height: 280, child: _buildDriversList()),
                                const SizedBox(height: 12),
                                _buildSummaryPane(),
                              ],
                            ),
                          ),
                        );
                      }
                      // Side-by-side on wide screens
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(flex: 5, child: _buildDriversList()),
                          Expanded(flex: 7, child: _buildSummaryPane()),
                        ],
                      );
                    },
                  ),
        floatingActionButton: (_selectedDriverId != null &&
                (_summary?['debt_records'] is List))
            ? FloatingActionButton.extended(
                onPressed: _showRecordPaymentDialog,
                backgroundColor: ThemeConstants.primaryOrange,
                foregroundColor: Colors.white,
                icon: const Icon(Icons.add),
                label: Text(localizationService.translate('record_payment')),
              )
            : null,
      ),
    );
  }

  Widget _buildDriversList() {
    if (_drivers.isEmpty) {
      return Center(
        child: Text(LocalizationService.instance.translate('no_drivers_found_2'),
            style: TextStyle(color: Colors.white70)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _drivers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (BuildContext context, int index) {
        final Map<String, dynamic> d = _drivers[index];
        final String id = (d['id'] ?? '').toString();
        final String name = (d['name'] ?? '').toString();
        final String vehicle = (d['vehicle_number'] ?? '').toString();
        final double debt = _toDouble(d['total_debt']);
        final int days =
            int.tryParse((d['unpaid_days'] ?? '0').toString()) ?? 0;
        final bool selected = id == _selectedDriverId;
        return InkWell(
          onTap: () => _loadSummary(id),
          child: Container(
            decoration: BoxDecoration(
              color: ThemeConstants.cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.15)),
            ),
            padding: const EdgeInsets.all(12),
            child: Row(
              children: <Widget>[
                CircleAvatar(
                  backgroundColor:
                      ThemeConstants.primaryOrange.withOpacity(0.2),
                  child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style:
                          const TextStyle(color: ThemeConstants.primaryOrange)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(name,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600)),
                      if (vehicle.isNotEmpty)
                        Text(vehicle,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Text('TSH ${_formatCurrency(debt)}',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                    Text(LocalizationService.instance.translateWith('days_2', <Object?>[days]),
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12)),
                  ],
                ),
                if (selected)
                  const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(Icons.check, color: Colors.white)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSummaryPane() {
    if (_selectedDriverId == null) {
      return Center(
        child: Text(LocalizationService.instance.translate('select_a_driver_on_the_left'),
            style: TextStyle(color: Colors.white70)),
      );
    }
    if (_loadingSummary) {
      return const Center(child: CircularProgressIndicator());
    }
    final Map<String, dynamic> s = _summary ?? <String, dynamic>{};
    final String name = (s['driver_name'] ?? '').toString();
    final double totalDebt = _toDouble(s['total_debt']);
    final List<dynamic> records = (s['debt_records'] as List?) ?? <dynamic>[];
    final List<Map<String, dynamic>> unpaid = records
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .where((m) => m['is_paid'] != true && m['is_paid'] != 1)
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: ThemeConstants.cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.15)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(LocalizationService.instance.translateWith('total_debt_tsh', <Object?>[_formatCurrency(totalDebt)]),
                    style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(LocalizationService.instance.translate('unpaid_days'),
              style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 8),
          if (unpaid.isEmpty)
            Text(LocalizationService.instance.translate('no_pending_debt'),
                style: TextStyle(color: Colors.white, fontSize: 12))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: unpaid.map((m) {
                final String iso = (m['date'] ?? '').toString();
                final DateTime? dt = DateTime.tryParse(iso);
                final String label =
                    dt != null ? DateFormat('dd/MM').format(dt) : iso;
                final double rem = _toDouble(m['remaining_amount']);
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.15)),
                  ),
                  child: Text('$label • ${rem.toStringAsFixed(0)}',
                      style:
                          const TextStyle(color: Colors.white, fontSize: 12)),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Future<void> _showRecordPaymentDialog() async {
    final List<Map<String, dynamic>> records =
        (_summary?['debt_records'] as List?)
                ?.whereType<Map>()
                .map((e) => e.cast<String, dynamic>())
                .where((m) => m['is_paid'] != true && m['is_paid'] != 1)
                .toList() ??
            <Map<String, dynamic>>[];

    final GlobalKey<FormState> formKey = GlobalKey<FormState>();
    final TextEditingController amountCtrl = TextEditingController();
    final TextEditingController remarksCtrl = TextEditingController();
    String channel = 'cash';
    final Set<String> selectedDays = records
        .map((m) => (m['date'] ?? '').toString())
        .where((s) => s.isNotEmpty)
        .toSet();

    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (BuildContext context,
            void Function(void Function()) setStateDialog) {
          return AlertDialog(
            backgroundColor: ThemeConstants.primaryBlue,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              LocalizationService.instance.translate('record_payment'),
              style: TextStyle(color: Colors.white),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    TextFormField(
                      controller: amountCtrl,
                      keyboardType: TextInputType.number,
                      decoration: _input(LocalizationService.instance.translate('amount_tsh')),
                      style: const TextStyle(color: Colors.white),
                      validator: (v) {
                        final double? a = double.tryParse((v ?? '').trim());
                        if (a == null || a <= 0) return LocalizationService.instance.translate('enter_a_valid_amount');
                        return null;
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: channel,
                      decoration: _input(LocalizationService.instance.translate('payment_method_label')),
                      dropdownColor: ThemeConstants.primaryBlue,
                      style: const TextStyle(color: Colors.white),
                      items: [
                        DropdownMenuItem(
                            value: 'cash', child: Text(LocalizationService.instance.translate('cash'))),
                        DropdownMenuItem(
                            value: 'mobile', child: Text(LocalizationService.instance.translate('mobile_money'))),
                        DropdownMenuItem(
                            value: 'bank', child: Text(LocalizationService.instance.translate('bank_transfer'))),
                        DropdownMenuItem(
                            value: 'other', child: Text(LocalizationService.instance.translate('other'))),
                      ],
                      onChanged: (v) =>
                          setStateDialog(() => channel = v ?? channel),
                    ),
                    const SizedBox(height: 10),
                    Text(LocalizationService.instance.translate('select_the_days_being_paid'),
                        style: TextStyle(color: Colors.white70)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: records.map((m) {
                        final String iso = (m['date'] ?? '').toString();
                        final DateTime? dt = DateTime.tryParse(iso);
                        final String label =
                            dt != null ? DateFormat('dd/MM').format(dt) : iso;
                        final bool selected = selectedDays.contains(iso);
                        return ChoiceChip(
                          selected: selected,
                          label: Text(label,
                              style: const TextStyle(color: Colors.white)),
                          selectedColor: ThemeConstants.primaryOrange,
                          backgroundColor: Colors.white.withOpacity(0.08),
                          onSelected: (_) => setStateDialog(() {
                            if (selected) {
                              selectedDays.remove(iso);
                            } else {
                              selectedDays.add(iso);
                            }
                          }),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: remarksCtrl,
                      maxLines: 3,
                      decoration: _input(LocalizationService.instance.translate('note_optional')),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(LocalizationService.instance.translate('cancel_2')),
              ),
              TextButton(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;
                  if (selectedDays.isEmpty) return;
                  Navigator.pop(context);
                  try {
                    final Map<String, dynamic> payload = <String, dynamic>{
                      'driver_id': _selectedDriverId,
                      'amount': double.parse(amountCtrl.text.trim()),
                      'payment_channel': channel,
                      'covers_days': selectedDays.toList(),
                      if (remarksCtrl.text.trim().isNotEmpty)
                        'remarks': remarksCtrl.text.trim(),
                    };
                    await _api.recordPayment(payload);
                    if (!mounted) return;
                    ThemeConstants.showSuccessSnackBar(context, LocalizationService.instance.translate('payment_saved_successfully'));
                    await _loadSummary(_selectedDriverId!);
                    await _loadDrivers();
                  } on Exception catch (e) {
                    if (!mounted) return;
                    ThemeConstants.showErrorSnackBar(context, LocalizationService.instance.translateWith('could_not_save', <Object?>[e]));
                  }
                },
                child: Text(LocalizationService.instance.translate('save')),
              ),
            ],
          );
        },
      ),
    );
  }

  InputDecoration _input(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        filled: true,
        fillColor: Colors.white.withOpacity(0.10),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.25)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: ThemeConstants.primaryOrange, width: 2),
        ),
      );

  String _formatCurrency(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}K';
    return v.toStringAsFixed(0);
  }
}
/*
      color: ThemeConstants.primaryBlue,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: payments.length,
        itemBuilder: (final BuildContext context, final int index) {
          final Map<String, dynamic> payment = payments[index];
          return _buildPaymentCard(payment);
        },
      ),
    );
  }

  Widget _buildEmptyState() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(
              Icons.payment_outlined,
              size: 80,
              color: Colors.white70,
            ),
            const SizedBox(height: 16),
            const Text(
              "Hakuna malipo yaliyopatikana",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Jaribu kubadilisha vichujio vyako",
              style: TextStyle(
                fontSize: 14,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      );

  Widget _buildPaymentCard(final Map<String, dynamic> payment) {
    final String status = (payment["status"]?.toString() ?? '');
    final double amount = _toDouble(payment["amount"]);
    final DateTime? dueDate = payment["due_date"] as DateTime?;
    final DateTime? paidDate = payment["paid_date"] as DateTime?;
    final String id = payment['id']?.toString() ?? '';
    final String? rowLoading = _rowActionLoading[id];
    final String overlayText = () {
      switch (rowLoading) {
        case 'mark_paid':
          return 'Inathibitisha malipo...';
        case 'delete':
          return 'Inafuta malipo...';
        default:
          return 'Inasindika...';
      }
    }();

    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (status) {
      case "paid":
        statusColor = ThemeConstants.successGreen;
        statusIcon = Icons.check_circle;
        statusText = "YALIYOLIPWA";
      case "pending":
        statusColor = Colors.amber;
        statusIcon = Icons.pending;
        statusText = "YANAYOSUBIRI";
      case "overdue":
        statusColor = ThemeConstants.errorRed;
        statusIcon = Icons.warning;
        statusText = "YALIYOCHELEWA";
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.help;
        statusText = "HAIJULIKANI";
    }

    return Stack(
      children: <Widget>[
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: ThemeConstants.cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    // Status indicator
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(25),
                      ),
                      child: Icon(
                        statusIcon,
                        color: statusColor,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Payment info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  payment["driver_name"]?.toString() ?? '',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  statusText,
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            payment["vehicle_number"]?.toString() ?? '',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          if (dueDate != null) ...<Widget>[
                            Row(
                              children: <Widget>[
                                Icon(
                                  Icons.schedule,
                                  size: 14,
                                  color: Colors.white70,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  "Tarehe ya kulipa: ${DateFormat("dd/MM/yyyy").format(dueDate)}",
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (paidDate != null) ...<Widget>[
                            const SizedBox(height: 2),
                            Row(
                              children: <Widget>[
                                const Icon(
                                  Icons.check,
                                  size: 14,
                                  color: ThemeConstants.successGreen,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  "Ililipwa: ${DateFormat("dd/MM/yyyy HH:mm").format(paidDate)}",
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: ThemeConstants.successGreen,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Amount and actions
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        Text(
                          "TSH ${_formatCurrency(amount)}",
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (rowLoading != null)
                          SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                            ),
                          )
                        else
                          PopupMenuButton<String>(
                            onSelected: (final String value) =>
                                _handlePaymentAction(value, payment),
                            itemBuilder: (final BuildContext context) =>
                                <PopupMenuEntry<String>>[
                              const PopupMenuItem(
                                value: "view",
                                child: Row(
                                  children: <Widget>[
                                    Icon(Icons.visibility,
                                        color: ThemeConstants.primaryBlue),
                                    SizedBox(width: 8),
                                    Text("Ona"),
                                  ],
                                ),
                              ),
                              if (status == "pending" || status == "overdue")
                                const PopupMenuItem(
                                  value: "mark_paid",
                                  child: Row(
                                    children: <Widget>[
                                      Icon(Icons.check_circle,
                                          color: ThemeConstants.successGreen),
                                      SizedBox(width: 8),
                                      Text("Weka Kuwa Yaliyolipwa"),
                                    ],
                                  ),
                                ),
                              if (status == "paid")
                                const PopupMenuItem(
                                  value: "receipt",
                                  child: Row(
                                    children: <Widget>[
                                      Icon(Icons.receipt, color: Colors.orange),
                                      SizedBox(width: 8),
                                      Text("Ona Risiti"),
                                    ],
                                  ),
                                ),
                              const PopupMenuItem(
                                value: "edit",
                                child: Row(
                                  children: <Widget>[
                                    Icon(Icons.edit, color: Colors.orange),
                                    SizedBox(width: 8),
                                    Text("Hariri"),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: "delete",
                                child: Row(
                                  children: <Widget>[
                                    Icon(Icons.delete,
                                        color: ThemeConstants.errorRed),
                                    SizedBox(width: 8),
                                    Text("Futa"),
                                  ],
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
                if (payment["notes"] != null &&
                    payment["notes"].isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withOpacity(0.18)),
                    ),
                    child: Text(
                      payment["notes"],
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                // Payment details row
                Row(
                  children: <Widget>[
                    _buildPaymentDetail(
                      "Aina",
                      _getPaymentTypeText(payment["payment_type"]?.toString() ?? ''),
                      Icons.category,
                    ),
                    if (payment["payment_method"] != null)
                      _buildPaymentDetail(
                        "Njia",
                        _getPaymentMethodText(payment["payment_method"]?.toString() ?? ''),
                        Icons.payment,
                      ),
                    if (payment["receipt_number"] != null)
                      _buildPaymentDetail(
                        "Risiti",
                        payment["receipt_number"]?.toString() ?? '',
                        Icons.receipt,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (rowLoading != null)
          Positioned.fill(
            child: AbsorbPointer(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: AnimatedOpacity(
                  opacity: 0.5,
                  duration: const Duration(milliseconds: 150),
                  child: ColoredBox(
                    color: Colors.white,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const CircularProgressIndicator(
                            strokeWidth: 3,
                            valueColor: AlwaysStoppedAnimation<Color>(ThemeConstants.primaryBlue),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            overlayText,
                            style: const TextStyle(
                              color: Colors.black87,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPaymentDetail(
    final String label,
    final String value,
    final IconData icon,
  ) =>
      Expanded(
        child: Row(
          children: <Widget>[
            Icon(
              icon,
              size: 14,
              color: Colors.white,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _buildFloatingActionButton() => FloatingActionButton.extended(
        onPressed: _showRecordPaymentDialog,
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text(
          "Rekodi Malipo",
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      );

  String _formatCurrency(final double amount) {
    if (amount >= 1000000) {
      return "${(amount / 1000000).toStringAsFixed(1)}M";
    } else if (amount >= 1000) {
      return "${(amount / 1000).toStringAsFixed(0)}K";
    } else {
      return amount.toStringAsFixed(0);
    }
  }

  String _getPaymentTypeText(final String type) {
    switch (type) {
      case "daily":
        return "Kila siku";
      case "weekly":
        return "Kila wiki";
      case "monthly":
        return "Kila mwezi";
      default:
        return type;
    }
  }

  String _getPaymentMethodText(final String method) {
    switch (method) {
      case "cash":
        return "Fedha taslimu";
      case "mobile_money":
        return "Pesa za simu";
      case "bank_transfer":
        return "Uhamisho wa benki";
      default:
        return method;
    }
  }

  void _handlePaymentAction(
    final String action,
    final Map<String, dynamic> payment,
  ) {
    switch (action) {
      case "view":
        _showPaymentDetails(payment);
      case "mark_paid":
        _markPaymentAsPaid(payment);
      case "receipt":
        _showReceipt(payment);
      case "edit":
        _showEditPaymentDialog(payment);
      case "delete":
        _confirmDeletePayment(payment);
    }
  }

  void _showPaymentDetails(final Map<String, dynamic> payment) {
    final String driverName = payment["driver_name"]?.toString() ?? '';
    final String vehicleNumber = payment["vehicle_number"]?.toString() ?? '';
    final String amountText = _formatCurrency(_toDouble(payment["amount"]));
    final String paymentType = _getPaymentTypeText(payment["payment_type"]?.toString() ?? '');
    final String status = payment["status"]?.toString() ?? '';
    final DateTime? dueDate = payment["due_date"] as DateTime?;
    final DateTime? paidDate = payment["paid_date"] as DateTime?;
    final String? method = payment["payment_method"]?.toString();
    final String? receiptNo = payment["receipt_number"]?.toString();
    final String? notes = payment["notes"]?.toString();

    showDialog(
      context: context,
      builder: (final BuildContext context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: AutoSizeText(
          "Maelezo ya Malipo - $driverName",
          maxLines: 1,
          minFontSize: 12,
          stepGranularity: 0.5,
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _buildDetailRow("Dereva:", driverName),
              _buildDetailRow("Gari:", vehicleNumber),
              _buildDetailRow(
                "Kiasi:",
                "TSH $amountText",
              ),
              _buildDetailRow(
                "Aina ya Malipo:",
                paymentType,
              ),
              _buildDetailRow("Hali:", status),
              if (dueDate != null)
                _buildDetailRow(
                  "Tarehe ya Kulipa:",
                  DateFormat("dd/MM/yyyy").format(dueDate),
                ),
              if (paidDate != null)
                _buildDetailRow(
                  "Ililipwa:",
                  DateFormat("dd/MM/yyyy HH:mm").format(paidDate),
                ),
              if (method != null)
                _buildDetailRow(
                  "Njia ya Malipo:",
                  _getPaymentMethodText(method),
                ),
              if (receiptNo != null)
                _buildDetailRow("Namba ya Risiti:", receiptNo),
              if (notes != null && notes.isNotEmpty)
                _buildDetailRow("Maelezo:", notes),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Funga"),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(final String label, final String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 120,
              child: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  color: Colors.black54,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );

  void _markPaymentAsPaid(final Map<String, dynamic> payment) {
    showDialog(
      context: context,
      builder: (final BuildContext context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const AutoSizeText(
          "Weka Kuwa Yaliyolipwa",
          maxLines: 1,
          minFontSize: 12,
          stepGranularity: 0.5,
        ),
        content: Text(
          "Je, una uhakika malipo ya ${payment["driver_name"]} ya TSH ${_formatCurrency(_toDouble(payment["amount"]))} yamelipwa?",
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Hapana"),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
                ThemeConstants.showSuccessSnackBar(
                  context,
                  "Malipo yamewekwa kuwa yaliyolipwa",
                );
              } on ApiException catch (e) {
                ThemeConstants.showErrorSnackBar(
                    context, "Imeshindikana kuweka kuwa imelipwa: ${e.message}");
              } on Exception catch (e) {
                ThemeConstants.showErrorSnackBar(context, "Hitilafu: $e");
              } finally {
                if (mounted) {
                  setState(() {
                    _rowActionLoading.remove(paymentId);
                  });
                }
              }
            },
            child: const Text(
              "Ndio",
              style: TextStyle(color: ThemeConstants.successGreen),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showReceipt(final Map<String, dynamic> payment) async {
    try {
      final String paymentId = payment['id'].toString();
      final Map<String, dynamic> gen =
          await _apiService.generatePaymentReceipt(paymentId);
      final dynamic data = gen['data'] ?? gen['receipt'] ?? gen;
      final String receiptId = data is Map && data['id'] != null
          ? data['id'].toString()
          : (payment['receipt_id']?.toString() ?? '');

      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (BuildContext ctx) {
          final String guessed = payment['driver_phone']?.toString() ??
              payment['phone']?.toString() ??
              payment['email']?.toString() ?? '';
          final TextEditingController contactCtrl =
              TextEditingController(text: guessed);
          String method = 'system';
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text(
                  'Risiti ya Malipo',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text('Receipt ID: ${receiptId.isEmpty ? 'N/A' : receiptId}'),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: method,
                  items: const [
                    DropdownMenuItem(value: 'system', child: Text('Mfumo (in-app)')),
                    DropdownMenuItem(value: 'whatsapp', child: Text('WhatsApp')),
                    DropdownMenuItem(value: 'email', child: Text('Barua pepe')),
                  ],
                  decoration: const InputDecoration(labelText: 'Tuma kwa'),
                  onChanged: (val) => method = val ?? method,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: contactCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Mawasiliano (namba/email)',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Funga'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          try {
                            final String contact = contactCtrl.text.trim();
                            if (method != 'system' && contact.isEmpty) {
                              ThemeConstants.showWarningSnackBar(ctx, 'Weka mawasiliano sahihi');
                              return;
                            }
                            await _apiService.sendPaymentReceipt(
                              receiptId: receiptId,
                              sendVia: method,
                              contactInfo: contact,
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                            ThemeConstants.showSuccessSnackBar(context, 'Risiti imetumwa kikamilifu');
                          } on ApiException catch (e) {
                            ThemeConstants.showErrorSnackBar(ctx, 'Hitilafu: ${e.message}');
                          } on Exception catch (e) {
                            ThemeConstants.showErrorSnackBar(ctx, 'Hitilafu: $e');
                          }
                        },
                        child: const Text('Tuma'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    } on ApiException catch (e) {
      ThemeConstants.showErrorSnackBar(context, 'Imeshindikana kuandaa risiti: ${e.message}');
    } on Exception catch (e) {
      ThemeConstants.showErrorSnackBar(context, 'Hitilafu: $e');
    }
  }

  void _showEditPaymentDialog(final Map<String, dynamic> payment) {
    final TextEditingController amountCtrl = TextEditingController(
      text: _toDouble(payment['amount']).toStringAsFixed(0),
    );
    final TextEditingController notesCtrl =
        TextEditingController(text: payment['notes']?.toString() ?? '');
    String method = (payment['payment_method']?.toString() ?? 'cash');

    showDialog(
      context: context,
      builder: (final BuildContext context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: AutoSizeText(
              "Hariri Malipo - ${payment["driver_name"]}",
              maxLines: 1,
              minFontSize: 12,
              stepGranularity: 0.5,
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TextField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Kiasi (TSh)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: method,
                    items: const [
                      DropdownMenuItem(value: 'cash', child: Text('Fedha taslimu')),
                      DropdownMenuItem(value: 'mobile_money', child: Text('Pesa za simu')),
                      DropdownMenuItem(value: 'bank_transfer', child: Text('Uhamisho wa benki')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Njia ya Malipo',
                    ),
                    onChanged: (val) => setStateDialog(() => method = val ?? method),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Maelezo (hiari)',
                    ),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Ghairi"),
              ),
              TextButton(
                onPressed: () async {
                  final double? amt = double.tryParse(amountCtrl.text);
                  final NavigatorState nav = Navigator.of(context);
                  if (amt == null || amt <= 0) {
                    ThemeConstants.showWarningSnackBar(context, 'Weka kiasi sahihi');
                    return;
                  }
                  try {
                    final String paymentId = payment['id'].toString();
                    final Map<String, dynamic> payload = <String, dynamic>{
                      'amount': amt,
                      'payment_method': method,
                      'notes': notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
                    };
                    await _apiService.updatePayment(paymentId, payload);

                    setState(() {
                      payment['amount'] = amt;
                      payment['payment_method'] = method;
                      payment['notes'] = payload['notes'];
                    });
                    _filterPayments();
                    nav.pop();
                    ThemeConstants.showSuccessSnackBar(context, 'Taarifa za malipo zimehifadhiwa');
                  } on ApiException catch (e) {
                    ThemeConstants.showErrorSnackBar(context, 'Imeshindikana kuhariri: ${e.message}');
                  } on Exception catch (e) {
                    ThemeConstants.showErrorSnackBar(context, 'Hitilafu: $e');
                  }
                },
                child: const Text("Hifadhi"),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmDeletePayment(final Map<String, dynamic> payment) {
    showDialog(
      context: context,
      builder: (final BuildContext context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const AutoSizeText(
          "Futa Malipo",
          maxLines: 1,
          minFontSize: 12,
          stepGranularity: 0.5,
        ),
        content: Text(
          "Je, una uhakika unataka kufuta malipo ya ${payment["driver_name"]} ya TSH ${_formatCurrency(_toDouble(payment["amount"]))}? Kitendo hiki hakiwezi kurudishwa.",
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Hapana"),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final OverlayState overlay = Overlay.of(context);
              final String paymentId = payment['id'].toString();
              setState(() {
                _rowActionLoading[paymentId] = 'delete';
              });
              try {
                await _apiService.deletePayment(paymentId);
                setState(() {
                  _payments.removeWhere(
                    (final Map<String, dynamic> p) => p["id"].toString() == paymentId,
                  );
                });
                _filterPayments();
                ThemeConstants.showTopBanner(
                  overlay,
                  "Malipo ya ${payment["driver_name"]} yamefutwa",
                  backgroundColor: ThemeConstants.errorRed,
                  icon: Icons.check_circle,
                );
              } on ApiException catch (e) {
                ThemeConstants.showTopBanner(
                  overlay,
                  "Imeshindikana kufuta malipo: ${e.message}",
                  backgroundColor: ThemeConstants.errorRed,
                  icon: Icons.error,
                );
              } on Exception catch (e) {
                ThemeConstants.showTopBanner(
                  overlay,
                  "Hitilafu: $e",
                  backgroundColor: ThemeConstants.errorRed,
                  icon: Icons.error,
                );
              } finally {
                if (mounted) {
                  setState(() {
                    _rowActionLoading.remove(paymentId);
                  });
                }
              }
            },
            child: const Text(
              "Futa",
              style: TextStyle(color: ThemeConstants.errorRed),
            ),
          ),
        ],
      ),
    );
  }

  void _showRecordPaymentDialog() {
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();
    final TextEditingController amountCtrl = TextEditingController();
    final TextEditingController notesCtrl = TextEditingController();
    String channel = 'cash';

    String? selectedDriverId = widget.initialDriverId;
    bool lockDriver = widget.initialDriverId != null;

    // Driver list state
    bool loadingDrivers = false;
    String? driversError;
    List<Map<String, String>> drivers = <Map<String, String>>[];

    // Agreement-derived defaults
    bool fetchingAgreement = false;
    String? agreementError;
    String paymentType = 'daily'; // default
    List<DateTime> coversDays = <DateTime>[DateTime.now()];

    Future<void> loadDrivers() async {
      try {
        loadingDrivers = true;
        driversError = null;
        final Map<String, dynamic> res = await _apiService.getDrivers(page: 1, limit: 200);
        final dynamic data = res['data'];
        List<dynamic> list;
        if (data is Map<String, dynamic>) {
          list = (data['data'] as List<dynamic>? ?? <dynamic>[]);
        } else if (data is List) {
          list = data;
        } else {
          list = <dynamic>[];
        }
        drivers = list.map((dynamic j) {
          final Map<String, dynamic> m = (j as Map<String, dynamic>);
          final String id = (m['id'] ?? '').toString();
          final String name = (m['name'] ?? '').toString();
          final String vehicle = (m['vehicle_number'] ?? '').toString();
          final String label = vehicle.isNotEmpty ? '$name • $vehicle' : name;
          return <String, String>{'id': id, 'label': label};
        }).toList();
      } on Exception catch (e) {
        driversError = readableErrorMessage(e);
      } finally {
        loadingDrivers = false;
      }
    }

    Future<void> fetchAgreementFor(String driverId, void Function(void Function()) setStateDialog) async {
      try {
        setStateDialog(() {
          fetchingAgreement = true;
          agreementError = null;
        });
        final Map<String, dynamic> res = await _apiService.getDriverAgreementByDriverId(driverId);
        final Map<String, dynamic>? data = res['data'] as Map<String, dynamic>?;

        // Try best-effort defaults
        double defAmount = 0;
        defAmount = _toDouble(data?['default_amount']);
        if (defAmount == 0) defAmount = _toDouble(data?['daily_amount']);
        if (defAmount == 0) defAmount = _toDouble(data?['amount']);
        if (defAmount == 0) defAmount = _toDouble(data?['agreed_amount']);
        if (defAmount > 0 && (amountCtrl.text.isEmpty || amountCtrl.text == '0')) {
          amountCtrl.text = defAmount.toStringAsFixed(0);
        }

        // Payment frequency
        String? type;
        final dynamic freqs = data?['payment_frequencies'];
        if (freqs is List && freqs.isNotEmpty) {
          final String first = (freqs.first ?? '').toString();
          if (first.isNotEmpty) type = first;
        }
        // Some backends might use 'payment_type'
        type ??= (data?['payment_type']?.toString());
        if (type != null && type.isNotEmpty) {
          setStateDialog(() => paymentType = type!);
        }
      } on Exception catch (e) {
        setStateDialog(() => agreementError = readableErrorMessage(e));
      } finally {
        setStateDialog(() => fetchingAgreement = false);
      }
    }

    bool dialogInitialized = false;

    showDialog(
      context: context,
      builder: (final BuildContext context) => StatefulBuilder(
        builder: (BuildContext context, void Function(void Function()) setStateDialog) {
          // One-time initialization inside dialog
          if (!dialogInitialized) {
            dialogInitialized = true;
            if (selectedDriverId != null && selectedDriverId!.isNotEmpty) {
              // Preload agreement for initial driver
              fetchAgreementFor(selectedDriverId!, setStateDialog);
            }
          }

          Widget driverSelector;
          if (lockDriver && (selectedDriverId != null)) {
            driverSelector = TextFormField(
              readOnly: true,
              initialValue: selectedDriverId,
style: const TextStyle(color: Colors.white, fontSize: 16),
              decoration: InputDecoration(
                labelText: 'Driver ID (imetolewa)',
labelStyle: const TextStyle(color: Colors.white70, fontSize: 14),
                filled: true,
                fillColor: Colors.white.withOpacity(0.10),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.25)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: ThemeConstants.primaryOrange, width: 2),
                ),
                suffixIcon: IconButton(
                    icon: Icon(Icons.lock_open, color: ThemeConstants.primaryOrange, size: 18.sp),
                  tooltip: 'Badilisha dereva',
                  onPressed: () async {
                    setStateDialog(() {
                      lockDriver = false;
                    });
                    if (drivers.isEmpty && !loadingDrivers) {
                      await loadDrivers();
                      setStateDialog(() {});
                    }
                  },
                ),
              ),
            );
          } else {
            if (drivers.isEmpty && !loadingDrivers) {
              // Lazy load drivers on first unlock
              loadDrivers().then((_) => setStateDialog(() {}));
            }
            driverSelector = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: selectedDriverId,
                  dropdownColor: ThemeConstants.primaryBlue,
style: const TextStyle(color: Colors.white, fontSize: 16),
                    iconEnabledColor: Colors.white70,
                    icon: Icon(Icons.arrow_drop_down, size: 18.sp, color: Colors.white70),
                  decoration: InputDecoration(
                    labelText: 'Chagua Dereva',
labelStyle: const TextStyle(color: Colors.white70, fontSize: 14),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.10),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.25)),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                      borderSide: BorderSide(color: ThemeConstants.primaryOrange, width: 2),
                    ),
                  ),
                  items: drivers
                      .map((e) => DropdownMenuItem<String>(
                            value: e['id'],
                            child: Text(e['label'] ?? ''),
                          ))
                      .toList(),
                  onChanged: (String? v) {
                    setStateDialog(() {
                      selectedDriverId = v;
                    });
                    if (v != null && v.isNotEmpty) {
                      fetchAgreementFor(v, setStateDialog);
                    }
                  },
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Chagua dereva'
                      : null,
                ),
                if (loadingDrivers)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                if (driversError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      driversError!,
                      style: const TextStyle(color: ThemeConstants.errorRed, fontSize: 12),
                    ),
                  ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: selectedDriverId == null
                        ? null
                        : () => setStateDialog(() => lockDriver = true),
                    icon: Icon(Icons.lock, size: 16.sp),
                    label: const Text('Funga chaguo'),
                  ),
                ),
              ],
            );
          }

          return AlertDialog(
            backgroundColor: ThemeConstants.primaryBlue,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text(
              "Rekodi Malipo",
style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
            ),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    driverSelector,
                    const SizedBox(height: 8),
                    // Payment frequency
                    DropdownButtonFormField<String>(
                      value: paymentType,
                      dropdownColor: ThemeConstants.primaryBlue,
style: const TextStyle(color: Colors.white, fontSize: 16),
                      iconEnabledColor: Colors.white70,
                      icon: Icon(Icons.arrow_drop_down, size: 18.sp, color: Colors.white70),
                      items: const <DropdownMenuItem<String>>[
                        DropdownMenuItem(value: 'daily', child: Text('Kila siku')),
                        DropdownMenuItem(value: 'weekly', child: Text('Kila wiki')),
                        DropdownMenuItem(value: 'monthly', child: Text('Kila mwezi')),
                      ],
                      onChanged: (String? v) => setStateDialog(() {
                        if (v != null) paymentType = v;
                      }),
                      decoration: InputDecoration(
                        labelText: 'Aina ya Malipo',
labelStyle: const TextStyle(color: Colors.white70, fontSize: 14),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.10),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.25)),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                          borderSide: BorderSide(color: ThemeConstants.primaryOrange, width: 2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: amountCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
style: const TextStyle(color: Colors.white, fontSize: 18),
                      decoration: InputDecoration(
                        labelText: 'Kiasi (TSh)',
labelStyle: const TextStyle(color: Colors.white70, fontSize: 15),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.10),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.25)),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                          borderSide: BorderSide(color: ThemeConstants.primaryOrange, width: 2),
                        ),
                        suffixIcon: fetchingAgreement
                            ? const Padding(
                                padding: EdgeInsets.all(10.0),
                                child: SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            : null,
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Weka kiasi';
                        final a = double.tryParse(v);
                        if (a == null || a <= 0) return 'Kiasi si sahihi';
                        return null;
                      },
                    ),
                    if (agreementError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          agreementError!,
                          style: const TextStyle(color: ThemeConstants.errorRed, fontSize: 12),
                        ),
                      ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: channel,
                      dropdownColor: ThemeConstants.primaryBlue,
style: const TextStyle(color: Colors.white, fontSize: 16),
                      iconEnabledColor: Colors.white70,
                      items: const [
                        DropdownMenuItem(value: 'cash', child: Text('Fedha taslimu')),
                        DropdownMenuItem(value: 'mobile', child: Text('Pesa za simu')),
                        DropdownMenuItem(value: 'bank', child: Text('Uhamisho wa benki')),
                        DropdownMenuItem(value: 'mpesa', child: Text('M-Pesa')),
                        DropdownMenuItem(value: 'other', child: Text('Nyingine')),
                      ],
                      onChanged: (val) => channel = val ?? channel,
                      decoration: InputDecoration(
                        labelText: 'Njia ya Malipo',
labelStyle: const TextStyle(color: Colors.white70, fontSize: 14),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.10),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.25)),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                          borderSide: BorderSide(color: ThemeConstants.primaryOrange, width: 2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Covers days picker (backend requires at least one day)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Siku zinazofunikwa',
                        style: const TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ...coversDays
                            .map(
                              (d) => Chip(
                                label: Text(
                                  DateFormat('dd/MM/yyyy').format(d),
                                  style: const TextStyle(color: Colors.white),
                                ),
                                backgroundColor: Colors.white.withOpacity(0.10),
                                deleteIconColor: Colors.white70,
                                onDeleted: () => setStateDialog(() {
                                  coversDays.remove(d);
                                }),
                              ),
                            )
                            .toList(),
                        ActionChip(
                          avatar: Icon(Icons.add, size: 16.sp, color: Colors.white),
                          label: const Text('Ongeza Siku', style: TextStyle(color: Colors.white)),
                          backgroundColor: ThemeConstants.primaryOrange.withOpacity(0.8),
                          onPressed: () async {
                            final DateTime initial = coversDays.isNotEmpty
                                ? coversDays.last
                                : DateTime.now();
                            final DateTime? picked = await showDatePicker(
                              context: context,
                              initialDate: initial,
                              firstDate: DateTime.now().subtract(const Duration(days: 365)),
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                            );
                            if (picked != null) {
                              setStateDialog(() {
                                if (!coversDays.any((e) => e.year == picked.year && e.month == picked.month && e.day == picked.day)) {
                                  coversDays.add(picked);
                                  coversDays.sort((a, b) => a.compareTo(b));
                                }
                              });
                            }
                          },
                        ),
                        ActionChip(
                          avatar: Icon(Icons.date_range, size: 16.sp, color: Colors.white),
                          label: const Text('Chagua Kipindi', style: TextStyle(color: Colors.white)),
                          backgroundColor: ThemeConstants.primaryBlue.withOpacity(0.8),
                          onPressed: () async {
                            final DateTimeRange? range = await showDateRangePicker(
                              context: context,
                              firstDate: DateTime.now().subtract(const Duration(days: 365)),
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                            );
                            if (range != null) {
                              setStateDialog(() {
                                DateTime d = DateTime(range.start.year, range.start.month, range.start.day);
                                final DateTime end = DateTime(range.end.year, range.end.month, range.end.day);
                                while (!d.isAfter(end)) {
                                  if (!coversDays.any((e) => e.year == d.year && e.month == d.month && e.day == d.day)) {
                                    coversDays.add(d);
                                  }
                                  d = d.add(const Duration(days: 1));
                                }
                                coversDays.sort((a, b) => a.compareTo(b));
                              });
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: notesCtrl,
                      maxLines: 3,
style: const TextStyle(color: Colors.white, fontSize: 16),
                      decoration: InputDecoration(
                        labelText: 'Maelezo (hiari)',
labelStyle: const TextStyle(color: Colors.white70, fontSize: 14),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.10),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.25)),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                          borderSide: BorderSide(color: ThemeConstants.primaryOrange, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Ghairi"),
              ),
              TextButton(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;
                  if ((selectedDriverId == null || selectedDriverId!.trim().isEmpty)) {
                    // Ensure driver selected
                    return;
                  }
                  Navigator.pop(context);
                  try {
                    final Map<String, dynamic> payload = <String, dynamic>{
'driver_id': selectedDriverId!.trim(),
                      'amount': double.parse(amountCtrl.text.trim()),
                      'payment_channel': channel,
                      'covers_days': coversDays
                          .map((d) => DateFormat('yyyy-MM-dd').format(d))
                          .toList(),
                      'remarks': notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
                    };
                    await _apiService.recordPayment(payload);
                    ThemeConstants.showSuccessSnackBar(context, 'Malipo yamehifadhiwa kikamilifu');
                    await _loadPayments(refresh: true);
                  } on ApiException catch (e) {
                    ThemeConstants.showErrorSnackBar(context, 'Imeshindikana kuhifadhi: ${e.message}');
                  } on Exception catch (e) {
                    ThemeConstants.showErrorSnackBar(context, 'Hitilafu: $e');
                  }
                },
                child: const Text("Hifadhi"),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showDateRangePicker() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _selectedDateRange,
    );

    if (picked != null) {
      setState(() {
        _selectedDateRange = picked;
      });
      _filterPayments();
    }
  }

  Future<void> _exportPayments() async {
    if (kIsWeb) {
      ThemeConstants.showErrorSnackBar(context, "Uhamishaji wa faili haupatikani kwenye web. Tumia simu/desktop.");
      return;
    }
    try {
      final String csv = _buildPaymentsCsv(_payments);
      final Directory dir = await getApplicationDocumentsDirectory();
      final String timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final String filePath = "${dir.path}/payments_$timestamp.csv";
      final File file = File(filePath);
      await file.writeAsString(csv);
      if (!mounted) return;
      ThemeConstants.showSuccessSnackBar(context, "Faili limehifadhiwa: $filePath");
    } on Exception catch (e) {
      _showErrorSnackBar("Imeshindikana kuhamisha malipo: $e");
    }
  }

  String _buildPaymentsCsv(List<Map<String, dynamic>> items) {
    String esc(String? v) {
      final String s = (v ?? '').replaceAll('"', '""');
      if (s.contains(',') || s.contains('"') || s.contains('\n')) {
        return '"$s"';
      }
      return s;
    }

    const String header = 'id,driver_name,vehicle_number,amount,status,due_date,paid_date,receipt_number,payment_channel,covers_days,remarks';

    final List<String> lines = <String>[
      header,
      ...items.map((p) => [
            esc(p['id']?.toString()),
            esc(p['driver_name']?.toString()),
            esc(p['vehicle_number']?.toString()),
            esc(_toDouble(p['amount']).toStringAsFixed(0)),
            esc(p['status']?.toString()),
            esc(p['due_date'] is DateTime
                ? DateFormat('yyyy-MM-dd').format(p['due_date'] as DateTime)
                : p['due_date']?.toString()),
            esc(p['paid_date'] is DateTime
                ? DateFormat('yyyy-MM-dd HH:mm').format(p['paid_date'] as DateTime)
                : p['paid_date']?.toString()),
            esc(p['receipt_number']?.toString()),
            esc((p['payment_channel'] ?? p['payment_method'])?.toString()),
            esc(() {
              final v = p['covers_days'];
              if (v is List) {
                // join as semicolon-separated dates if already strings
                return v.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).join(';');
              }
              return '';
            }()),
            esc((p['remarks'] ?? p['notes'])?.toString()),
          ].join(',')),
    ];

    return lines.join('\n');
  }

  Future<void> _importPayments() async {
    final OverlayState overlay = Overlay.of(context);
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: <String>['csv'],
        withData: true,
      );
      if (result == null) return;

      String csvContent;
      final PlatformFile file = result.files.first;
      if (kIsWeb || file.bytes != null) {
        csvContent = utf8.decode(file.bytes!);
      } else if (file.path != null) {
        csvContent = await File(file.path!).readAsString();
      } else {
        _showErrorSnackBar("Imeshindikana kusoma faili");
        return;
      }

      final List<Map<String, String>> rows = _parsePaymentsCsv(csvContent);
      if (rows.isEmpty) {
        _showErrorSnackBar("Hakuna rekodi kwenye faili");
        return;
      }
      // Validate headers (minimum required)
      final Set<String> required = {'driver_id', 'amount'};
      final Set<String> headers = rows.first.keys.toSet();
      if (!headers.containsAll(required)) {
        _showErrorSnackBar("Faili halina vichwa sahihi. Vinavyotakiwa angalau: driver_id, amount");
        return;
      }

      int success = 0;
      int failed = 0;

      const Set<String> allowedChannels = {'cash','mobile','bank','mpesa','other'};

      String _normalizeDate(String s) {
        // Expect YYYY-MM-DD; attempt to parse common formats and reformat
        final String t = s.trim();
        if (t.isEmpty) return '';
        DateTime? d = DateTime.tryParse(t);
        if (d == null) {
          try {
            // Try dd/MM/yyyy
            final parts = t.split('/');
            if (parts.length == 3) {
              final int day = int.parse(parts[0]);
              final int month = int.parse(parts[1]);
              final int year = int.parse(parts[2]);
              d = DateTime(year, month, day);
            }
          } catch (_) {}
        }
        return d != null ? DateFormat('yyyy-MM-dd').format(d) : '';
      }

      for (final Map<String, String> r in rows) {
        try {
          final String? driverId = (r['driver_id'] ?? r['driver'])?.trim();
          final double? amount = double.tryParse((r['amount'] ?? '').trim());
          if (driverId == null || driverId.isEmpty || amount == null) {
            failed++;
            continue;
          }

          String channel = (r['payment_channel'] ?? r['channel'] ?? '').toLowerCase().trim();
          if (!allowedChannels.contains(channel)) {
            channel = 'cash';
          }

          // Parse covers_days: semicolon-separated list
          final String rawDays = (r['covers_days'] ?? '').trim();
          List<String> coversDays = <String>[];
          if (rawDays.isNotEmpty) {
            coversDays = rawDays
                .split(';')
                .map((e) => _normalizeDate(e))
                .where((e) => e.isNotEmpty)
                .toList();
          }
          if (coversDays.isEmpty) {
            coversDays = <String>[DateFormat('yyyy-MM-dd').format(DateTime.now())];
          }

          final String? remarks = (r['remarks'] ?? r['notes'])?.trim();

          final Map<String, dynamic> payload = <String, dynamic>{
            'driver_id': driverId,
            'amount': amount,
            'payment_channel': channel,
            'covers_days': coversDays,
            if (remarks != null && remarks.isNotEmpty) 'remarks': remarks,
          };
          await _apiService.recordPayment(payload);
          success++;
        } on Exception {
          failed++;
        }
      }

      ThemeConstants.showTopBanner(
        overlay,
        "Uingizaji wa malipo: $success mafanikio, $failed imeshindikana",
        backgroundColor:
            failed == 0 ? ThemeConstants.successGreen : ThemeConstants.warningAmber,
        icon: failed == 0 ? Icons.check_circle : Icons.warning,
      );

      await _loadPayments(refresh: true);
    } on Exception catch (e) {
      _showErrorSnackBar("Imeshindikana kuingiza malipo: $e");
    }
  }

  Future<void> _exportPaymentsTemplate() async {
    if (kIsWeb) {
      ThemeConstants.showErrorSnackBar(context, 'Upakuaji wa faili kwenye web haupatikani');
      return;
    }
    try {
      const String header = 'driver_id,amount,payment_channel,covers_days,remarks';
      const String example = '12345,10000,cash,"2025-10-12;2025-10-13",malipo ya siku';
      const String csv = '$header\n$example\n';
      final Directory dir = await getApplicationDocumentsDirectory();
      final String filePath = "${dir.path}/payments_template.csv";
      await File(filePath).writeAsString(csv);
      if (!mounted) return;
      ThemeConstants.showSuccessSnackBar(context, 'Template imehifadhiwa: $filePath');
    } on Exception catch (e) {
      _showErrorSnackBar('Imeshindikana kutengeneza template: $e');
    }
  }

  List<Map<String, String>> _parsePaymentsCsv(String content) {
    final List<String> lines = content.split(RegExp(r"\r?\n"));
    if (lines.isEmpty) return <Map<String, String>>[];
    final List<String> headers = _splitCsvLine(lines.first);
    final List<Map<String, String>> rows = <Map<String, String>>[];

    for (int i = 1; i < lines.length; i++) {
      final String line = lines[i].trim();
      if (line.isEmpty) continue;
      final List<String> cols = _splitCsvLine(line);
      final Map<String, String> row = <String, String>{};
      for (int j = 0; j < headers.length && j < cols.length; j++) {
        row[headers[j].trim().toLowerCase()] = cols[j];
      }
      rows.add(row);
    }
    return rows;
  }

  List<String> _splitCsvLine(String line) {
    final List<String> out = <String>[];
    final StringBuffer cur = StringBuffer();
    bool inQuotes = false;
    for (int i = 0; i < line.length; i++) {
      final String ch = line[i];
      if (ch == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          cur.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (ch == ',' && !inQuotes) {
        out.add(cur.toString());
        cur.clear();
      } else {
        cur.write(ch);
      }
    }
    out.add(cur.toString());
    return out;
  }

  void _showBulkActionDialog() {
    showDialog(
      context: context,
      builder: (final BuildContext context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const AutoSizeText(
          "Vitendo vya Wingi",
          maxLines: 1,
          minFontSize: 12,
          stepGranularity: 0.5,
        ),
        content: const Text("Kipengele hiki kinatengenezwa. Subiri kidogo!"),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Sawa"),
          ),
        ],
      ),
    );
  }

  // Helper method to safely convert dynamic values to double
  double _toDouble(value) {
    if (value == null) return 0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      return double.tryParse(value) ?? 0.0;
    }
    return 0;
  }
}
*/
