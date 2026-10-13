import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../constants/theme_constants.dart';
import '../../services/localization_service.dart';
import '../../models/receipt.dart';
import '../../models/payment_receipt.dart';
import '../../services/api_service.dart';
import '../../services/app_events.dart';
import '../../utils/responsive_helper.dart';
import 'receipt_detail_screen.dart';
import 'receipt_viewer_screen.dart';

// ignore_for_file: directives_ordering
class ReceiptsScreen extends StatefulWidget {
  const ReceiptsScreen({super.key, this.initialFilter = 'all'});

  final String initialFilter;

  @override
  State<ReceiptsScreen> createState() => _ReceiptsScreenState();
}

class _ReceiptsScreenState extends State<ReceiptsScreen> {
  final ApiService _apiService = ApiService();
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  String? _errorMessage;
  List<Receipt> _receipts = <Receipt>[];
  List<PendingReceiptItem> _pendingReceipts = <PendingReceiptItem>[];
  int _totalReceipts = 0;
  String _selectedFilter = 'all'; // 'all' or 'pending'

  // Event subscription for automatic refresh
  late StreamSubscription<AppEvent> _eventSubscription;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _selectedFilter = widget.initialFilter;
    _loadReceipts();

    // Listen to app events for automatic refresh
    _eventSubscription = AppEvents.instance.stream.listen((event) {
      switch (event.type) {
        case AppEventType.receiptsUpdated:
        case AppEventType.paymentsUpdated:
        case AppEventType.debtsUpdated:
          // Refresh receipts when payments or receipts are updated
          if (mounted) {
            _loadReceipts();
          }
        case AppEventType.dashboardShouldRefresh:
          // Also refresh when dashboard requests refresh
          if (mounted) {
            _loadReceipts();
          }
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _eventSubscription.cancel();
    super.dispose();
  }

  Future<void> _loadReceipts() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      Map<String, dynamic> response;

      // Load receipts based on selected filter
      final String q = _searchController.text.trim();
      if (_selectedFilter == 'pending') {
        response = await _apiService.getPendingReceipts();
      } else {
        // Use backend search by query when available
        response =
            await _apiService.getReceipts(query: q.isNotEmpty ? q : null);
      }

      if (response['success'] == true) {
        final data = response['data'] as Map<String, dynamic>? ?? {};

        if (_selectedFilter == 'pending') {
          // For pending receipts, parse as PendingReceiptItem objects
          final pendingReceiptsData =
              data['pending_receipts'] as List<dynamic>? ??
                  data['data'] as List<dynamic>? ??
                  <dynamic>[];
          // Apply client-side filtering for pending list (by driver name/phone/reference)
          final String q = _searchController.text.trim().toLowerCase();
          final List<PendingReceiptItem> items = pendingReceiptsData
              .map((item) =>
                  PendingReceiptItem.fromJson(item as Map<String, dynamic>))
              .toList();
          final List<PendingReceiptItem> filtered = q.isEmpty
              ? items
              : items.where((e) {
                  final s =
                      '${e.driver.name} ${e.driver.phone} ${e.referenceNumber} ${e.paymentId}'
                          .toLowerCase();
                  return s.contains(q);
                }).toList();
          setState(() {
            _pendingReceipts = filtered;
            _receipts =
                <Receipt>[]; // Clear regular receipts when showing pending
            _totalReceipts = data['total'] as int? ??
                data['count'] as int? ??
                filtered.length;
            _isLoading = false;
          });
        } else {
          // For all receipts, parse as Receipt objects
          final receiptsData = data['receipts'] as List<dynamic>? ??
              data['data'] as List<dynamic>? ??
              <dynamic>[];
          // As a safety, client-side filter if backend search isn't available
          final String q = _searchController.text.trim().toLowerCase();
          final List<Receipt> items = receiptsData
              .map((item) => Receipt.fromJson(item as Map<String, dynamic>))
              .toList();
          final List<Receipt> filtered = q.isEmpty
              ? items
              : items.where((r) {
                  final s = '${r.driverName} ${r.receiptNumber} ${r.paymentId}'
                      .toLowerCase();
                  return s.contains(q);
                }).toList();
          setState(() {
            _receipts = filtered;
            _pendingReceipts =
                <PendingReceiptItem>[]; // Clear pending receipts when showing all
            _totalReceipts = data['total'] as int? ??
                data['count'] as int? ??
                filtered.length;
            _isLoading = false;
          });
        }
      } else {
        throw Exception(response['message'] ?? LocalizationService.instance.translate('could_not_load_the_receipts'));
      }
    } on Exception catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshReceipts() async {
    await _loadReceipts();
  }

  void _changeFilter(String filter) {
    setState(() {
      _selectedFilter = filter;
    });
    _loadReceipts();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _loadReceipts);
  }

  void _clearSearch() {
    if (_searchController.text.isEmpty) return;
    _searchController.clear();
    _loadReceipts();
  }

  @override
  Widget build(BuildContext context) {
    ResponsiveHelper.init(context);

    return Consumer<LocalizationService>(
      builder: (context, localizationService, child) => Scaffold(
        backgroundColor: ThemeConstants.primaryBlue,
        appBar: AppBar(
          backgroundColor: ThemeConstants.primaryBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(localizationService.translate('receipts')),
              if (!_isLoading) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: ThemeConstants.primaryOrange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: ThemeConstants.primaryOrange.withOpacity(0.3),
                    ),
                  ),
                  child: Text(
                    '$_totalReceipts',
                    style: const TextStyle(
                      color: ThemeConstants.primaryOrange,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _refreshReceipts,
            ),
          ],
        ),
        body: Column(
          children: [
            // Search bar
            _buildSearchBar(localizationService),

            const SizedBox(height: 16),

            // Content
            Expanded(
              child: _buildContent(localizationService),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(LocalizationService localizationService) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          // Search input field
          TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            onSubmitted: (_) => _loadReceipts(),
            textInputAction: TextInputAction.search,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: '${localizationService.translate('search')}...',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
              filled: true,
              fillColor: Colors.white.withOpacity(0.1),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(25),
                borderSide: BorderSide.none,
              ),
              prefixIcon: Icon(
                Icons.search,
                color: Colors.white.withOpacity(0.7),
              ),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: _clearSearch,
                    ),
            ),
          ),
          const SizedBox(height: 12),
          // Filter buttons row
          Row(
            children: [
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: _selectedFilter == 'pending'
                        ? ThemeConstants.primaryOrange
                        : Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: TextButton(
                    onPressed: () => _changeFilter('pending'),
                    child: Text(
                      localizationService.translate('pending'),
                      style: TextStyle(
                        color: _selectedFilter == 'pending'
                            ? Colors.white
                            : Colors.white.withOpacity(0.8),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: _selectedFilter == 'all'
                        ? ThemeConstants.primaryOrange
                        : Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: TextButton(
                    onPressed: () => _changeFilter('all'),
                    child: Text(
                      localizationService.translate('all'),
                      style: TextStyle(
                        color: _selectedFilter == 'all'
                            ? Colors.white
                            : Colors.white.withOpacity(0.8),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContent(LocalizationService localizationService) {
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
                onPressed: _refreshReceipts,
                style: ElevatedButton.styleFrom(
                  backgroundColor: ThemeConstants.primaryOrange,
                ),
                child: Text(localizationService.translate('try_again')),
              ),
            ],
          ),
        ),
      );
    }

    // Check if we have any data to show
    final bool hasData = (_selectedFilter == 'pending')
        ? _pendingReceipts.isNotEmpty
        : _receipts.isNotEmpty;

    if (!hasData) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _selectedFilter == 'pending'
                    ? Icons.pending_actions
                    : Icons.receipt_long,
                size: 80,
                color: Colors.white.withOpacity(0.5),
              ),
              const SizedBox(height: 20),
              Text(
                _selectedFilter == 'pending'
                    ? localizationService.translate('no_pending_receipts')
                    : localizationService.translate('no_receipts_generated'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _selectedFilter == 'pending'
                    ? localizationService
                        .translate('all_payments_have_receipts')
                    : localizationService.translate('receipts_list_empty'),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshReceipts,
      child: ListView.builder(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _selectedFilter == 'pending'
            ? _pendingReceipts.length
            : _receipts.length,
        itemBuilder: (context, index) {
          if (_selectedFilter == 'pending') {
            final pendingReceipt = _pendingReceipts[index];
            return _buildPendingReceiptCard(pendingReceipt);
          } else {
            final receipt = _receipts[index];
            return _buildReceiptCard(receipt);
          }
        },
      ),
    );
  }

  Widget _buildPendingReceiptCard(PendingReceiptItem pendingReceipt) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ReceiptDetailScreen(
              pendingReceipt: pendingReceipt,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withOpacity(0.2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    pendingReceipt.driver.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Builder(
                    builder: (context) => Text(
                      Provider.of<LocalizationService>(context, listen: false)
                          .translate('pending'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (pendingReceipt.driver.phone.isNotEmpty) ...<Widget>[
              Text(
                pendingReceipt.driver.phone,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'TSH ${_formatCurrency(pendingReceipt.amount)}',
                  style: const TextStyle(
                    color: ThemeConstants.primaryOrange,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${pendingReceipt.coveredDaysCount} ${Provider.of<LocalizationService>(context, listen: false).translate('days').toLowerCase()}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.touch_app,
                  color: ThemeConstants.primaryOrange,
                  size: 16,
                ),
                const SizedBox(width: 4),
                Builder(
                  builder: (context) => Text(
                    '${Provider.of<LocalizationService>(context, listen: false).translate('view_details')} • ${Provider.of<LocalizationService>(context, listen: false).translate('generate_receipt')}',
                    style: const TextStyle(
                      color: ThemeConstants.primaryOrange,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReceiptCard(Receipt receipt) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ReceiptViewerScreen(
              receipt: receipt,
            ),
          ),
        );
      },
      child: Container(
        margin: EdgeInsets.only(bottom: 12.h),
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(
            color: Colors.white.withOpacity(0.2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    receipt.receiptNumber.isNotEmpty
                        ? receipt.receiptNumber
                        : 'N/A',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 8.w,
                    vertical: 4.h,
                  ),
                  decoration: BoxDecoration(
                    color: _getStatusColor(receipt.status),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Builder(
                    builder: (context) {
                      final l10n = LocalizationService.instance;
                      final key =
                          'receipt_status_${receipt.status.toLowerCase()}';
                      return Text(
                        l10n.translate(key),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            SizedBox(height: 8.h),
            Text(
              receipt.driverName,
              style: TextStyle(
                color: Colors.white,
                fontSize: 14.sp,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 4.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'TSH ${_formatCurrency(receipt.amount)}',
                  style: TextStyle(
                    color: ThemeConstants.primaryOrange,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _formatDate(receipt.generatedAt),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 12.sp,
                  ),
                ),
              ],
            ),
            if (receipt.paymentChannel.isNotEmpty) ...<Widget>[
              SizedBox(height: 4.h),
              Text(
                receipt.paymentChannelDisplayName,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 12.sp,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'generated':
        return Colors.blue;
      case 'sent':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
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
    return DateFormat('dd/MM/yyyy').format(date);
  }
}
