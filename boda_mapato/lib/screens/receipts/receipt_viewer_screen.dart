import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../constants/theme_constants.dart';
import '../../models/receipt.dart';
import '../../services/api_service.dart';
import '../../services/localization_service.dart';
import '../../utils/responsive_helper.dart';

// ignore_for_file: avoid_catches_without_on_clauses
class ReceiptViewerScreen extends StatefulWidget {
  const ReceiptViewerScreen({required this.receipt, super.key});

  final Receipt receipt;

  @override
  State<ReceiptViewerScreen> createState() => _ReceiptViewerScreenState();
}

class _ReceiptViewerScreenState extends State<ReceiptViewerScreen>
    with TickerProviderStateMixin {
  final ApiService _api = ApiService();

  bool _isLoading = true;
  bool _isSending = false;
  String? _errorMessage;

  // Detailed payload fetched from API (used for missing fields like payment_id, trips_total)
  Map<String, dynamic>? _detail;

  // Send options
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

    _loadReceiptDetails();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  Future<void> _loadReceiptDetails() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final response = await _api.getReceipt(widget.receipt.id);

      if (response['success'] == true) {
        // Prefill contact with driver's phone (fallback to email) if empty and store detail payload
        final dynamic data = response['data'];
        String? phone;
        String? email;
        if (data is Map<String, dynamic>) {
          _detail = data;
          phone = data['driver_phone']?.toString();
          email = data['driver_email']?.toString();
          final dynamic rd = data['receipt_data'];
          if ((phone == null || phone.isEmpty) && rd is Map<String, dynamic>) {
            phone = rd['driver_phone']?.toString();
          }
          if ((email == null || email.isEmpty) && rd is Map<String, dynamic>) {
            email = rd['driver_email']?.toString();
          }
        }
        if (mounted && _contactController.text.trim().isEmpty) {
          _contactController.text =
              (phone != null && phone.isNotEmpty) ? phone : (email ?? '');
        }
        setState(() {
          _isLoading = false;
        });
      } else {
        throw Exception(
            response['message'] ?? LocalizationService.instance.translate('could_not_load_the_receipt_details'));
      }
    } on Exception catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _resendReceipt() async {
    if (_contactController.text.trim().isEmpty) {
      ThemeConstants.showErrorSnackBar(context,
          LocalizationService.instance.translate('phone_or_email_required'));
      return;
    }

    // Build a message including remarks/covered days
    final String msg = _composeMessage();

    setState(() => _isSending = true);
    try {
      final response = await _api.sendPaymentReceipt(
        receiptId: widget.receipt.id,
        sendVia: 'whatsapp', // Default to WhatsApp
        contactInfo: _contactController.text.trim(),
        message: msg,
      );

      if (response['success'] == true) {
        if (!mounted) return;
        ThemeConstants.showSuccessSnackBar(
            context, LocalizationService.instance.translate('receipt_resent'));
      } else {
        throw Exception(response['message'] ??
            LocalizationService.instance.translate('failed_to_send_receipt'));
      }
    } on Exception catch (e) {
      if (!mounted) return;
      ThemeConstants.showErrorSnackBar(context,
          '${LocalizationService.instance.translate('error')}: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  String _composeMessage() {
    final r = widget.receipt;
    final l10n = LocalizationService.instance;
    // Real line breaks (this used to send the two characters backslash-n).
    final String days = r.paidDates.isNotEmpty
        ? '\n${l10n.translate('days')}: ${r.paidDates.join(', ')}'
        : '';
    final String remarks = (r.remarks != null && r.remarks!.isNotEmpty)
        ? '\n${l10n.translate('remarks')}: ${r.remarks!}'
        : '';
    // Who the receipt is from: the business that issued it (the server puts it on the receipt).
    final dynamic rd = _detail?['receipt_data'];
    final String company = (rd is Map ? rd['company_name'] : null)?.toString().trim() ?? '';
    final String from = company.isNotEmpty ? '$company\n' : '';
    return '$from${l10n.translate('receipt')} ${r.receiptNumber}\n${l10n.translate('amount')}: TSH ${r.amount.toStringAsFixed(0)}$days$remarks';
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
            child: _buildContent(),
          ),
        );
      },
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.white.withOpacity(0.5),
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadReceiptDetails,
                style: ElevatedButton.styleFrom(
                  backgroundColor: ThemeConstants.primaryOrange,
                ),
                child:
                    Text(LocalizationService.instance.translate('try_again')),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildReceiptHeader(),
          const SizedBox(height: 16),
          _buildReceiptDetails(),
          const SizedBox(height: 16),
          _buildPaymentInfo(),
          const SizedBox(height: 16),
          _buildTripsInfo(),
          const SizedBox(height: 16),
          _buildOutstandingInfo(),
          const SizedBox(height: 16),
          if (widget.receipt.status.toLowerCase() == 'sent') ...[
            _buildSentInfo(),
            const SizedBox(height: 16),
          ],
          if (widget.receipt.status.toLowerCase() != 'cancelled')
            _buildResendSection(),
        ],
      ),
    );
  }

  Widget _buildReceiptHeader() {
    return ThemeConstants.buildGlassCardStatic(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: ThemeConstants.primaryOrange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.receipt_long,
                    color: ThemeConstants.primaryOrange,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.receipt.receiptNumber,
                        style: const TextStyle(
                          color: ThemeConstants.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.receipt.driverName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                  decoration: BoxDecoration(
                    color: _getStatusColor(widget.receipt.status),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    LocalizationService.instance.translate(
                        'receipt_status_${widget.receipt.status.toLowerCase()}'),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.2)),
              ),
              child: Column(
                children: [
                  Text(
                    LocalizationService.instance.translate('total_payment'),
                    style: const TextStyle(
                      color: ThemeConstants.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'TSH ${_formatCurrency(widget.receipt.amount)}',
                    style: TextStyle(
                      color: ThemeConstants.textPrimary,
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReceiptDetails() {
    return ThemeConstants.buildGlassCardStatic(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              LocalizationService.instance.translate('receipt_details'),
              style: TextStyle(
                color: ThemeConstants.textPrimary,
                fontSize: 16.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            _buildDetailRow(
                LocalizationService.instance.translate('receipt_number'),
                widget.receipt.receiptNumber),
            _buildDetailRow(
                LocalizationService.instance.translate('payment_id'),
                _extractPaymentId()),
            _buildDetailRow(LocalizationService.instance.translate('driver'),
                widget.receipt.driverName),
            if (widget.receipt.vehicleNumber != null &&
                widget.receipt.vehicleNumber!.isNotEmpty)
              _buildDetailRow(
                  LocalizationService.instance.translate('vehicle_plate'),
                  widget.receipt.vehicleNumber!),
            _buildDetailRow(
                LocalizationService.instance.translate('generated_date'),
                _formatDate(widget.receipt.generatedAt)),
            if (widget.receipt.remarks != null &&
                widget.receipt.remarks!.isNotEmpty)
              _buildDetailRow(LocalizationService.instance.translate('remarks'),
                  widget.receipt.remarks!),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentInfo() {
    return ThemeConstants.buildGlassCardStatic(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              LocalizationService.instance.translate('payment_details'),
              style: const TextStyle(
                color: ThemeConstants.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            _buildDetailRow(LocalizationService.instance.translate('amount'),
                'TSH ${_formatCurrency(widget.receipt.amount)}'),
            _buildDetailRow(
                LocalizationService.instance.translate('payment_method'),
                widget.receipt.paymentChannelDisplayName),
            if (widget.receipt.paidDates.isNotEmpty)
              _buildDetailRow(
                  LocalizationService.instance.translate('covered_days'),
                  _formatPaidDates(widget.receipt.paidDates)),
          ],
        ),
      ),
    );
  }

  Widget _buildTripsInfo() {
    final trips = _extractTripsTotal();
    return ThemeConstants.buildGlassCardStatic(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.route, color: ThemeConstants.primaryOrange, size: 20.sp),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${LocalizationService.instance.translate('trips')}: $trips',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _extractPaymentId() {
    // Try multiple possible locations
    final d = _detail;
    String? s;
    String? as(v) => v?.toString();
    if (d != null) {
      s = as(d['payment_id']) ?? as(d['paymentId']);
      if ((s == null || s.isEmpty) && d['payment'] is Map<String, dynamic>) {
        final p = d['payment'] as Map<String, dynamic>;
        s = as(p['id']) ?? as(p['payment_id']);
      }
      if ((s == null || s.isEmpty) &&
          d['receipt_data'] is Map<String, dynamic>) {
        final rd = d['receipt_data'] as Map<String, dynamic>;
        s = as(rd['payment_id']) ?? as(rd['paymentId']);
      }
    }
    return (s != null && s.isNotEmpty) ? s : widget.receipt.paymentId;
  }

  int _extractTripsTotal() {
    // Prefer API detail payload fields
    final d = _detail;
    if (d != null) {
      // common keys: trips_total, trips, total_trips; also nested under receipt_data
      final dynamic direct = d['trips_total'] ?? d['trips'] ?? d['total_trips'];
      if (direct is num) return direct.toInt();
      if (direct is String) {
        final int? v = int.tryParse(direct);
        if (v != null) return v;
      }
      final dynamic rd = d['receipt_data'];
      if (rd is Map<String, dynamic>) {
        final dynamic nested =
            rd['trips_total'] ?? rd['trips'] ?? rd['total_trips'];
        if (nested is num) return nested.toInt();
        if (nested is String) {
          final int? v = int.tryParse(nested);
          if (v != null) return v;
        }
      }
    }
    // Fallback: count paid dates from list item
    final List<String> days = widget.receipt.paidDates;
    return days.isNotEmpty ? days.length : 0;
  }

  Widget _buildOutstandingInfo() {
    // This screen doesn't hold full preview payload; show placeholder that backend included when sending
    // Admin page primarily; outstanding is informative before/after sending
    return ThemeConstants.buildGlassCardStatic(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: Colors.orangeAccent, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                LocalizationService.instance
                    .translate('outstanding_info_message'),
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSentInfo() {
    return ThemeConstants.buildGlassCardStatic(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.check_circle,
                  color: ThemeConstants.successGreen,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  LocalizationService.instance.translate('send_info'),
                  style: const TextStyle(
                    color: ThemeConstants.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (widget.receipt.sentAt != null)
              _buildDetailRow(
                  LocalizationService.instance.translate('sent_date'),
                  _formatDate(widget.receipt.sentAt!)),
            if (widget.receipt.sentTo != null &&
                widget.receipt.sentTo!.isNotEmpty)
              _buildDetailRow(LocalizationService.instance.translate('sent_to'),
                  widget.receipt.sentTo!),
          ],
        ),
      ),
    );
  }

  Widget _buildResendSection() {
    return ThemeConstants.buildGlassCardStatic(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              LocalizationService.instance.translate('resend_receipt'),
              style: const TextStyle(
                color: ThemeConstants.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _contactController,
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText:
                    LocalizationService.instance.translate('phone_or_email'),
                hintText:
                    _contactController.text.isEmpty ? 'Mf. +2557XXXXXXX' : null,
                hintStyle: const TextStyle(color: ThemeConstants.textSecondary),
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
                onPressed: _isSending ? null : _resendReceipt,
                style: ElevatedButton.styleFrom(
                  backgroundColor: ThemeConstants.successGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: _isSending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send),
                label: Text(_isSending
                    ? LocalizationService.instance.translate('sending')
                    : LocalizationService.instance.translate('send_again')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(
                color: ThemeConstants.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: const TextStyle(
                color: ThemeConstants.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'generated':
        return Colors.blue;
      case 'sent':
        return ThemeConstants.successGreen;
      case 'cancelled':
        return ThemeConstants.errorRed;
      case 'pending':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  String _formatCurrency(double amount) {
    return NumberFormat('#,##0', 'sw_TZ').format(amount);
  }

  String _formatDate(DateTime date) {
    return DateFormat('dd/MM/yyyy HH:mm').format(date);
  }

  String _formatPaidDates(List<String> dates) {
    if (dates.isEmpty) return '-';
    if (dates.length == 1) return _formatDateString(dates.first);
    return LocalizationService.instance.translateWith('days_4', <Object?>[_formatDateString(dates.first), _formatDateString(dates.last), dates.length]);
  }

  String _formatDateString(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('dd/MM/yyyy').format(date);
    } catch (e) {
      return dateStr;
    }
  }
}
