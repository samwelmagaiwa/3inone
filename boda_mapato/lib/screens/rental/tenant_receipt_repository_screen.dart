import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import '../../constants/theme_constants.dart';
import '../../services/api_service.dart';
import 'receipt_view_screen.dart';
import '../../services/localization_service.dart';

class TenantReceiptRepositoryScreen extends StatefulWidget {
  const TenantReceiptRepositoryScreen({super.key});

  @override
  State<TenantReceiptRepositoryScreen> createState() => _TenantReceiptRepositoryScreenState();
}

class _TenantReceiptRepositoryScreenState extends State<TenantReceiptRepositoryScreen> {
  final ApiService _api = ApiService();
  List<dynamic> _receipts = [];
  List<dynamic> _filteredReceipts = [];
  bool _isLoading = true;
  String _searchQuery = "";
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchReceipts();
  }

  Future<void> _fetchReceipts() async {
    setState(() => _isLoading = true);
    try {
      final response = await _api.getTenantReceipts();
      final data = response['data'] ?? [];
      setState(() {
        _receipts = data;
        _filteredReceipts = data;
      });
    } catch (e) {
      debugPrint('Error fetching tenant receipts: $e');
      if (mounted) ThemeConstants.showErrorSnackBar(context, LocalizationService.instance.translate('failed_to_load_receipts'));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _filterReceipts(String query) {
    if (query.isEmpty) {
      setState(() => _filteredReceipts = _receipts);
      return;
    }
    
    final lowerQuery = query.toLowerCase();
    setState(() {
      _filteredReceipts = _receipts.where((receipt) {
        final paymentDate = receipt['payment']?['payment_date']?.toString() ?? '';
        final receiptNo = receipt['receipt_number']?.toString().toLowerCase() ?? '';
        
        // Allow searching by Month/Year e.g., '05' or '2026' or 'RCP-XXX'
        return paymentDate.contains(lowerQuery) || receiptNo.contains(lowerQuery);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ThemeConstants.buildResponsiveScaffold(
      context,
      title: LocalizationService.instance.translate('receipt_repository'),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(16.w),
            child: TextField(
              controller: _searchController,
              onChanged: _filterReceipts,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: LocalizationService.instance.translate('search_by_month_year_or_number'),
                hintStyle: const TextStyle(color: Colors.white54),
                prefixIcon: const Icon(Icons.search, color: Colors.white54),
                filled: true,
                fillColor: Colors.white.withOpacity(0.08),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16.r),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading 
                ? const Center(child: CircularProgressIndicator(color: ThemeConstants.primaryOrange))
                : _filteredReceipts.isEmpty 
                    ? _buildEmptyState() 
                    : _buildReceiptsList(),
          )
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 80.sp, color: Colors.white24),
          SizedBox(height: 16.h),
          Text(
            LocalizationService.instance.translate('no_receipts_found'),
            style: TextStyle(color: Colors.white54, fontSize: 18.sp, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8.h),
          Text(
            LocalizationService.instance.translate('when_landlords_dispatch_receipts_they_will'),
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 14.sp),
          ),
        ],
      ),
    );
  }

  Widget _buildReceiptsList() {
    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      itemCount: _filteredReceipts.length,
      itemBuilder: (context, index) {
        final receipt = _filteredReceipts[index];
        final payment = receipt['payment'] ?? {};
        final amount = payment['amount'] ?? 0;
        final dateStr = payment['payment_date'] ?? receipt['created_at'];
        
        String formattedDate = dateStr;
        try {
          if (dateStr != null) {
            formattedDate = DateFormat('MMMM d, yyyy').format(DateTime.parse(dateStr));
          }
        } catch (_) {}

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => ReceiptViewScreen(payment: payment))
            );
          },
          child: Container(
            margin: EdgeInsets.only(bottom: 12.h),
            padding: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16.r),
              border: Border.all(color: Colors.white.withOpacity(0.15)),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(12.w),
                  decoration: BoxDecoration(
                      color: ThemeConstants.primaryOrange.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12.r)),
                  child: Icon(Icons.receipt_long, color: ThemeConstants.primaryOrange, size: 24.sp),
                ),
                SizedBox(width: 14.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(receipt['receipt_number'] ?? 'RCP-xxx',
                          style: TextStyle(color: Colors.white, fontSize: 16.sp, fontWeight: FontWeight.w600)),
                      Text(formattedDate,
                          style: TextStyle(color: Colors.white54, fontSize: 12.sp)),
                    ],
                  ),
                ),
                Text(
                  "TSh $amount",
                  style: TextStyle(
                      color: ThemeConstants.successGreen,
                      fontSize: 16.sp,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
