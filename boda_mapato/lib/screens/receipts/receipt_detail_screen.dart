import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../constants/theme_constants.dart';
import '../../models/payment_receipt.dart';
import '../../services/api_service.dart';
import '../../services/app_events.dart';
import '../../services/localization_service.dart';
import '../../utils/responsive_helper.dart';

class ReceiptDetailScreen extends StatefulWidget {
  const ReceiptDetailScreen({required this.pendingReceipt, super.key});

  final PendingReceiptItem pendingReceipt;

  @override
  State<ReceiptDetailScreen> createState() => _ReceiptDetailScreenState();
}

class _ReceiptDetailScreenState extends State<ReceiptDetailScreen>
    with TickerProviderStateMixin {
  final ApiService _api = ApiService();

  bool _isGenerating = false;
  bool _isSending = false;
  Map<String, dynamic>? _generatedReceipt; // from preview/generate
  Map<String, dynamic>? _existingReceipt; // if receipt already exists

  // Send options
  ReceiptSendMethod _sendMethod = ReceiptSendMethod.whatsapp;
  final TextEditingController _contactController = TextEditingController();

  // Animations
  late AnimationController _fadeController;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fade = CurvedAnimation(parent: _fadeController, curve: Curves.easeIn);
    _fadeController.forward();

    // Prefill contact
    _contactController.text = widget.pendingReceipt.driver.phone.isNotEmpty
        ? widget.pendingReceipt.driver.phone
        : (widget.pendingReceipt.driver.email ?? '');

    // Check if receipt already exists for this payment
    _checkExistingReceipt();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  Future<void> _checkExistingReceipt() async {
    try {
      // Ask API for any receipts related to this payment. We'll validate by payment_id locally.
      final response = await _api.getReceipts(
        query: widget.pendingReceipt.paymentId,
        limit: 5,
      );

      final Map<String, dynamic> data = _extractData(response);
      final List<dynamic> receiptsData = (data['receipts'] is List)
          ? (data['receipts'] as List)
          : (data['data'] is List)
              ? (data['data'] as List)
              : <dynamic>[];

      // Find an exact match by payment_id/paymentId or nested payment.id
      final String pid = widget.pendingReceipt.paymentId;
      Map<String, dynamic>? match;
      for (final dynamic item in receiptsData) {
        if (item is Map) {
          final Map<String, dynamic> m = item.cast<String, dynamic>();
          final String a = _asString(m['payment_id']);
          final String b = _asString(m['paymentId']);
          final String c = _asString(
              (m['payment'] is Map) ? (m['payment'] as Map)['id'] : null);
          if (a == pid || b == pid || c == pid) {
            match = m;
            break;
          }
        }
      }

      if (match != null) {
        if (mounted) setState(() => _existingReceipt = match);
      } else {
        if (mounted) setState(() => _existingReceipt = null);
      }
    } on Exception catch (_) {
      // Ignore errors when checking existing receipts
    } finally {
      // no-op
    }
  }

  Map<String, dynamic> _extractData(Map<String, dynamic> res) {
    if (res['data'] is Map<String, dynamic>) {
      return res['data'] as Map<String, dynamic>;
    }
    if (res['success'] == true || res['status'] == 'success') {
      final dynamic d = res['data'];
      if (d is Map<String, dynamic>) {
        return d;
      }
    }
    return res;
  }

  String _asString(v) => v == null ? '' : v.toString().trim();

  Future<void> _generateReceipt() async {
    // Check if receipt already exists
    if (_existingReceipt != null) {
      _showSnack(
          LocalizationService.instance
              .translate('receipt_already_generated_for_payment'),
          isError: true);
      return;
    }

    setState(() => _isGenerating = true);
    try {
      final res =
          await _api.generatePaymentReceipt(widget.pendingReceipt.paymentId);
      if (res['success'] == true) {
        setState(() {
          _generatedReceipt = res['data'] as Map<String, dynamic>;
          _existingReceipt =
              res['data'] as Map<String, dynamic>; // Mark as existing
        });
        _showSnack(LocalizationService.instance.translate('receipt_generated'));
        await _refreshPage();
        AppEvents.instance.emit(AppEventType.receiptsUpdated);
        AppEvents.instance.emit(AppEventType.dashboardShouldRefresh);
      } else {
        // Check if the error is about duplicate receipt
        final errorMessage = res['message']?.toString() ??
            LocalizationService.instance
                .translate('failed_to_generate_receipt');
        if (errorMessage.toLowerCase().contains('already exists') ||
            errorMessage.toLowerCase().contains('duplicate') ||
            errorMessage.toLowerCase().contains('tayari')) {
          _showSnack(
              LocalizationService.instance
                  .translate('receipt_already_generated_for_payment'),
              isError: true);
          // Try to find the existing receipt
          await _checkExistingReceipt();
        } else {
          throw Exception(errorMessage);
        }
      }
    } on Exception catch (e) {
      _showSnack(
          '${LocalizationService.instance.translate('error')}: ${e.toString().replaceFirst('Exception: ', '')}',
          isError: true);
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _refreshPage() async {
    await _checkExistingReceipt();
    if (mounted) setState(() {});
  }

  Future<void> _sendReceipt() async {
    if (_generatedReceipt == null) {
      await _generateReceipt();
      if (_generatedReceipt == null) return;
    }

    final receiptId = _generatedReceipt!['id']?.toString() ??
        _generatedReceipt!['receipt_id']?.toString() ??
        '';
    if (receiptId.isEmpty) {
      _showSnack(LocalizationService.instance.translate('missing_receipt_id'),
          isError: true);
      return;
    }

    if (_contactController.text.trim().isEmpty) {
      _showSnack(LocalizationService.instance.translate('enter_contact_info'),
          isError: true);
      return;
    }

    setState(() => _isSending = true);
    try {
      final res = await _api.sendPaymentReceipt(
        receiptId: receiptId,
        sendVia: _sendMethod.value,
        contactInfo: _contactController.text.trim(),
      );
      if (res['success'] == true) {
        // Try to capture updated receipt payload if provided
        if (res['data'] is Map<String, dynamic>) {
          setState(() {
            _generatedReceipt = res['data'] as Map<String, dynamic>;
            // keep _existingReceipt in sync if present
            _existingReceipt = _generatedReceipt;
          });
        }
        _showSnack(LocalizationService.instance.translate('receipt_sent'));
        await _refreshPage();
        AppEvents.instance.emit(AppEventType.receiptsUpdated);
        AppEvents.instance.emit(AppEventType.dashboardShouldRefresh);
        // Optionally keep user on this screen to see refreshed state.
      } else {
        throw Exception(res['message'] ??
            LocalizationService.instance.translate('failed_to_send_receipt'));
      }
    } on Exception catch (e) {
      _showSnack('${LocalizationService.instance.translate('error')}: $e',
          isError: true);
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (isError) {
      ThemeConstants.showErrorSnackBar(context, msg);
    } else {
      ThemeConstants.showSuccessSnackBar(context, msg);
    }
  }

  @override
  Widget build(BuildContext context) {
    ResponsiveHelper.init(context);

    return Consumer<LocalizationService>(
      builder: (context, l10n, _) {
        return ThemeConstants.buildScaffold(
          title: l10n.translate('receipt_details'),
          body: FadeTransition(
            opacity: _fade,
            child: RefreshIndicator(
              onRefresh: _refreshPage,
              color: ThemeConstants.primaryBlue,
              backgroundColor: Colors.white,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 16),
                    _buildPaymentInfoCard(),
                    const SizedBox(height: 16),
                    _buildGenerateSection(),
                    const SizedBox(height: 16),
                    _buildSendSection(),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    final r = widget.pendingReceipt;
    return ThemeConstants.buildGlassCardStatic(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: ThemeConstants.primaryOrange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child:
                  const Icon(Icons.person, color: ThemeConstants.primaryOrange),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.driver.name,
                    style: const TextStyle(
                      color: ThemeConstants.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    r.driver.phone,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.2)),
              ),
              child: Text(
                r.formattedAmount,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12.sp,
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentInfoCard() {
    final r = widget.pendingReceipt;
    final l10n = LocalizationService.instance;
    return ThemeConstants.buildGlassCardStatic(
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row(l10n.translate('payment_date'), r.formattedDate),
            SizedBox(height: 8.h),
            _row(l10n.translate('payment_method'), r.formattedPaymentChannel),
            const SizedBox(height: 8),
            _row(l10n.translate('payment_period'), r.paymentPeriod),
            const SizedBox(height: 8),
            _row(l10n.translate('covered_days'), r.coveredDaysCount.toString()),
            const SizedBox(height: 8),
            _row(l10n.translate('debt_on_dates'),
                _formatCoveredDays(r.coveredDays)),
            if (r.hasRemainingDebt) ...[
              const SizedBox(height: 8),
              _debtNotice(
                  r.remainingDebtTotal, r.unpaidDaysCount, r.unpaidDates),
            ],
            if ((r.remarks ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              _row(l10n.translate('remarks'), r.remarks!),
            ],
          ],
        ),
      ),
    );
  }

  Map<String, dynamic>? get _receipt => _existingReceipt ?? _generatedReceipt;

  Widget _buildGenerateSection() {
    final bool isAlreadyGenerated = _receipt != null;

    return ThemeConstants.buildGlassCardStatic(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              LocalizationService.instance.translate('step_1_generate_receipt'),
              style: const TextStyle(
                color: ThemeConstants.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _existingReceipt != null
                  ? LocalizationService.instance
                      .translate('receipt_already_generated_for_payment')
                  : (_generatedReceipt == null
                      ? LocalizationService.instance
                          .translate('press_below_to_generate_receipt')
                      : LocalizationService.instance
                          .translate('receipt_generated_you_can_send')),
              style: TextStyle(
                color: _existingReceipt != null
                    ? ThemeConstants.primaryOrange
                    : ThemeConstants.textSecondary,
                fontWeight: _existingReceipt != null
                    ? FontWeight.w600
                    : FontWeight.normal,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (_isGenerating || isAlreadyGenerated)
                    ? null
                    : _generateReceipt,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isAlreadyGenerated
                      ? Colors.grey
                      : ThemeConstants.primaryOrange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: _isGenerating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.receipt),
                label: Text(
                  isAlreadyGenerated
                      ? LocalizationService.instance
                          .translate('already_generated')
                      : (_isGenerating
                          ? LocalizationService.instance.translate('generating')
                          : LocalizationService.instance
                              .translate('generate_receipt')),
                ),
              ),
            ),
            // Preview moved to main layout when generated
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _receiptPaperPreviewLegacy() {
    final Map<String, dynamic> map = _receipt ?? <String, dynamic>{};
    final Map<String, dynamic> rd = (map['receipt_data'] is Map)
        ? (map['receipt_data'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};

    String s(v) => v?.toString() ?? '';
    double d(v) {
      if (v == null) return 0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0;
    }

    final String company = s(rd['company_name']).isNotEmpty
        ? s(rd['company_name'])
        : '3 IN ONE';
    final String companyAddress = s(rd['company_address']);
    final String companyPhone = s(rd['company_phone']);
    final String receiptNumber = s(map['receipt_number']);
    final String driverName = s(map['driver_name'].toString().isNotEmpty
        ? map['driver_name']
        : rd['driver_name']);
    final String driverPhone = s(rd['driver_phone']);
    final String vehicleInfo = s(rd['vehicle_info']);
    final double amount = d(map['amount'].toString().isNotEmpty
        ? map['amount']
        : rd['payment_amount']);
    final String issueDate = s(rd['issue_date']);
    final String issueTime = s(rd['issue_time']);
    final String paymentChannel =
        s(map['payment_channel'] ?? rd['payment_channel']);
    final String coveredPeriod = s(rd['covered_period']);

    TextStyle label() => const TextStyle(color: Colors.black54, fontSize: 12);
    TextStyle value() => const TextStyle(
        color: Colors.black87, fontSize: 13, fontWeight: FontWeight.w600);

    Widget dashedDivider() => LayoutBuilder(
          builder: (context, constraints) {
            final int dashes = (constraints.maxWidth / 6).floor();
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(
                dashes,
                (int _) =>
                    Container(width: 3, height: 1, color: Colors.black26),
              ),
            );
          },
        );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 6)),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top stub
              Container(
                  height: 6,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(3))),
              const SizedBox(height: 12),
              // Company
              Text(company.toUpperCase(),
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87)),
              if (companyAddress.isNotEmpty)
                Text(companyAddress,
                    style: label(), textAlign: TextAlign.center),
              if (companyPhone.isNotEmpty)
                Text(LocalizationService.instance.translateWith('contact_2', <Object?>[companyPhone]).toUpperCase(),
                    style: label(), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              dashedDivider(),
              const SizedBox(height: 8),
              Text(LocalizationService.instance.translate('payment_receipt').toUpperCase(),
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87)),
              const SizedBox(height: 6),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(LocalizationService.instance.translateWith('date_2', <Object?>[issueDate]).toUpperCase(), style: label()),
                Text(LocalizationService.instance.translateWith('time_3', <Object?>[issueTime]).toUpperCase(), style: label()),
              ]),
              const SizedBox(height: 8),
              dashedDivider(),
              const SizedBox(height: 8),
              // Receipt meta
              _kv(LocalizationService.instance.translate('receipt_number_2'), receiptNumber, label, value),
              _kv(LocalizationService.instance.translate('driver_2'), driverName, label, value),
              if (driverPhone.isNotEmpty)
                _kv(LocalizationService.instance.translate('contact'), driverPhone, label, value),
              if (vehicleInfo.isNotEmpty)
                _kv(LocalizationService.instance.translate('registration'), vehicleInfo, label, value),
              if (coveredPeriod.isNotEmpty)
                _kv(LocalizationService.instance.translate('period'), coveredPeriod, label, value),
              const SizedBox(height: 8),
              dashedDivider(),
              const SizedBox(height: 8),
              // Amount
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(LocalizationService.instance.translate('total').toUpperCase(),
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87)),
                Text('TSh ${_formatAmount(amount)}',
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.black)),
              ]),
              const SizedBox(height: 4),
              _kv(LocalizationService.instance.translate('payment_method_label'), paymentChannel, label, value),
              const SizedBox(height: 8),
              dashedDivider(),
              const SizedBox(height: 8),
              Text('${LocalizationService.instance.translate('thank_you_for_using_our_services').toUpperCase()}!',
                  style: TextStyle(color: Colors.black54, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(
          String k, String v, TextStyle Function() l, TextStyle Function() s) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Expanded(child: Text(k, style: l())),
            const SizedBox(width: 8),
            Text(v, style: s(), textAlign: TextAlign.right),
          ],
        ),
      );

  String _formatAmount(double v) {
    final String s = v.toStringAsFixed(0);
    return s.replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},');
  }

  Widget _buildSendSection() {
    bool isAlreadySent() {
      final String status =
          (_existingReceipt?['status'] ?? _generatedReceipt?['status'])
                  ?.toString()
                  .toLowerCase() ??
              '';
      return status == 'sent' || status == 'delivered';
    }

    final bool alreadySent = isAlreadySent();

    return ThemeConstants.buildGlassCardStatic(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              LocalizationService.instance.translate('step_2_send_receipt'),
              style: const TextStyle(
                color: ThemeConstants.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _methodChip(ReceiptSendMethod.whatsapp, Icons.chat_outlined),
                _methodChip(ReceiptSendMethod.email, Icons.email_outlined),
                _methodChip(ReceiptSendMethod.system, Icons.sms_outlined),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _contactController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: _sendMethod == ReceiptSendMethod.email
                    ? LocalizationService.instance.translate('recipient_email')
                    : LocalizationService.instance.translate('recipient_phone'),
                labelStyle:
                    const TextStyle(color: ThemeConstants.textSecondary),
                filled: true,
                fillColor: Colors.white.withOpacity(0.06),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: ThemeConstants.primaryOrange),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (_isSending || alreadySent) ? null : _sendReceipt,
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      alreadySent ? Colors.grey : ThemeConstants.successGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: _isSending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send),
                label: Text(
                  _isSending
                      ? LocalizationService.instance.translate('sending')
                      : (alreadySent
                          ? LocalizationService.instance.translate('sent')
                          : LocalizationService.instance
                              .translate('send_receipt')),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              LocalizationService.instance
                  .translate('after_sending_status_will_change'),
              style: const TextStyle(
                  color: ThemeConstants.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  String _formatCoveredDays(List<String> days) {
    if (days.isEmpty) return '-';
    if (days.length == 1) return _formatDate(days.first);
    final String first = _formatDate(days.first);
    final String last = _formatDate(days.last);
    final String daysLabel =
        LocalizationService.instance.translate('days').toLowerCase();
    return '$first - $last ($daysLabel ${days.length})';
  }

  String _formatDate(String isoOrYmd) {
    try {
      final DateTime d = DateTime.tryParse(isoOrYmd) ?? DateTime.now();
      return '${d.day}/${d.month}/${d.year}';
    } on Exception catch (_) {
      return isoOrYmd;
    }
  }

  Widget _debtNotice(double remaining, int days, List<String> sampleDates) {
    final sample = sampleDates.isNotEmpty
        ? ' — ${sampleDates.map(_formatDate).join(', ')}'
        : '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: ThemeConstants.errorRed.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ThemeConstants.errorRed.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: ThemeConstants.errorRed, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              LocalizationService.instance.translateWith('remaining_debt_tsh_days', <Object?>[_formatAmount(remaining), days, sample]),
              style: const TextStyle(
                  color: ThemeConstants.errorRed,
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _methodChip(ReceiptSendMethod method, IconData icon) {
    final bool selected = _sendMethod == method;
    const Color base = Color(0xFF4169E1); // Midnight Blue
    final Color bgColor = selected ? ThemeConstants.primaryOrange : base;
    const Color textColor = Colors.white;
    const Color iconColor = Colors.white;
    final Color borderColor = selected
        ? Colors.white.withOpacity(0.6)
        : Colors.white.withOpacity(0.2);

    return ChoiceChip(
      label: Text(method.displayName),
      selected: selected,
      avatar: Icon(icon, color: iconColor, size: 18),
      selectedColor: bgColor, // when selected
      labelStyle: const TextStyle(
        color: textColor,
        fontWeight: FontWeight.w600,
      ),
      backgroundColor: bgColor, // when not selected
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor),
      ),
      onSelected: (_) {
        setState(() {
          _sendMethod = method;
        });
      },
    );
  }

  Widget _row(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: ThemeConstants.textSecondary,
              fontSize: 13.sp,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: ThemeConstants.textPrimary,
              fontSize: 13.sp,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ),
      ],
    );
  }
}
