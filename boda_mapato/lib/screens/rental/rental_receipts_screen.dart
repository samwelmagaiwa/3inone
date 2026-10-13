import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../constants/theme_constants.dart';
import '../../providers/rental_provider.dart';
import '../../services/localization_service.dart';
import '../../utils/type_helpers.dart';
import 'receipt_view_screen.dart';

class RentalReceiptsScreen extends StatefulWidget {
  final bool isSubView;

  const RentalReceiptsScreen({super.key, this.isSubView = false});

  @override
  State<RentalReceiptsScreen> createState() => _RentalReceiptsScreenState();
}

class _RentalReceiptsScreenState extends State<RentalReceiptsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  String _selectedPaymentMethod = "All";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RentalProvider>().fetchReceipts();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _formatCurrency(double value) {
    final formatter = NumberFormat("#,###");
    return formatter.format(value);
  }

  String _formatCompact(double value) {
    if (value >= 1000000) {
      return "${(value / 1000000).toStringAsFixed(1)}M";
    } else if (value >= 1000) {
      return "${(value / 1000).toStringAsFixed(0)}K";
    }
    return value.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final rentalProvider = context.watch<RentalProvider>();
    final receipts = rentalProvider.receipts;
    final loc = LocalizationService.instance;

    // Filter receipts based on search query and payment method
    final filteredReceipts = receipts.where((receipt) {
      final payment = receipt['payment'] ?? {};
      final tenant = payment['tenant'] ?? {};
      final details = receipt['details'] ?? {};
      
      final receiptNumber = (details['receipt_number'] ?? receipt['receipt_number'] ?? '').toString().toLowerCase();
      final tenantName = (tenant['name'] ?? LocalizationService.instance.translate('agreement_step_tenant')).toString().toLowerCase();
      final propertyName = (details['property_name'] ?? '').toString().toLowerCase();
      final houseNumber = (details['house_number'] ?? '').toString().toLowerCase();
      final paymentMethod = (details['payment_method'] ?? 'Cash').toString().toLowerCase();

      final matchesQuery = receiptNumber.contains(_searchQuery) ||
          tenantName.contains(_searchQuery) ||
          propertyName.contains(_searchQuery) ||
          houseNumber.contains(_searchQuery);

      final matchesMethod = _selectedPaymentMethod == "All" ||
          paymentMethod == _selectedPaymentMethod.toLowerCase();

      return matchesQuery && matchesMethod;
    }).toList();

    int totalReceipts = filteredReceipts.length;
    double totalCollected = filteredReceipts.fold(0.0, (sum, item) {
      final payment = item['payment'] ?? {};
      final details = item['details'] ?? {};
      return sum + TypeHelpers.toDouble(details['amount_paid'] ?? payment['amount_paid']);
    });

    Widget content = Column(
      children: [
        _buildStatsDashboard(totalReceipts, totalCollected, loc),
        _buildSearchAndFilters(loc),
        Expanded(
          child: rentalProvider.isLoading && receipts.isEmpty
              ? ThemeConstants.buildResponsiveLoadingWidget(context)
              : filteredReceipts.isEmpty
                  ? _buildEmptyState(loc)
                  : _buildReceiptsList(filteredReceipts, loc),
        ),
      ],
    );

    if (widget.isSubView) {
      return content;
    }

    return ThemeConstants.buildResponsiveScaffold(
      context,
      title: loc.translate("digital_receipt"),
      body: content,
    );
  }

  Widget _buildStatsDashboard(int count, double total, LocalizationService loc) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 8.h),
      child: Row(
        children: [
          Expanded(
            child: _buildStatCard(
              title: LocalizationService.instance.translate('total_receipts'),
              value: count.toString(),
              icon: Icons.receipt_long,
              gradient: const LinearGradient(
                colors: [ThemeConstants.primaryOrange, Color(0xFFFB923C)],
              ),
            ),
          ),
          SizedBox(width: 14.w),
          Expanded(
            child: _buildStatCard(
              title: LocalizationService.instance.translate('paid_amount'),
              value: "TZS ${_formatCompact(total)}",
              icon: Icons.account_balance_wallet,
              gradient: const LinearGradient(
                colors: [ThemeConstants.successGreen, Color(0xFF34D399)],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Gradient gradient,
  }) {
    return Container(
      decoration: ThemeConstants.responsiveGlassCardDecoration(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20.r),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.02),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
              borderRadius: BorderRadius.circular(20.r),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(10.w),
                  decoration: BoxDecoration(
                    gradient: gradient,
                    borderRadius: BorderRadius.circular(14.r),
                    boxShadow: [
                      BoxShadow(
                        color: gradient.colors.first.withOpacity(0.3),
                        blurRadius: 8,
                        spreadRadius: 1,
                      )
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: 22.sp),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: 11.sp,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        value,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16.sp,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchAndFilters(LocalizationService loc) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
      child: Column(
        children: [
          // Search Bar
          Container(
            decoration: ThemeConstants.responsiveGlassCardDecoration(context),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16.r),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val.trim().toLowerCase();
                    });
                  },
                  style: TextStyle(color: Colors.white, fontSize: 14.sp),
                  decoration: InputDecoration(
                    hintText: LocalizationService.instance.translate('search_by_tenant_house_receipt'),
                    hintStyle: TextStyle(color: Colors.white38, fontSize: 13.sp),
                    prefixIcon: Icon(Icons.search, color: ThemeConstants.primaryOrange, size: 20.sp),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? GestureDetector(
                            onTap: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = "";
                              });
                            },
                            child: Icon(Icons.clear, color: Colors.white60, size: 18.sp),
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.01),
                    contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16.r),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16.r),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16.r),
                      borderSide: const BorderSide(color: ThemeConstants.footerBarColor, width: 1.2),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: 10.h),
          // Filter Chips
          SizedBox(
            height: 34.h,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _buildFilterChip("All", shown: LocalizationService.instance.translate('all')),
                SizedBox(width: 8.w),
                _buildFilterChip("Cash", shown: LocalizationService.instance.translate('cash')),
                SizedBox(width: 8.w),
                _buildFilterChip("Bank", shown: LocalizationService.instance.translate('payment_channel_bank')),
                SizedBox(width: 8.w),
                _buildFilterChip("M-Pesa"),
                SizedBox(width: 8.w),
                _buildFilterChip("Airtel Money"),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// [label] is the value the list is filtered by; [shown] is what the chip reads in the chosen language.
  Widget _buildFilterChip(String label, {String? shown}) {
    final isSelected = _selectedPaymentMethod == label;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedPaymentMethod = label;
        });
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.h),
        decoration: BoxDecoration(
          color: isSelected
              ? ThemeConstants.primaryOrange.withOpacity(0.85)
              : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20.r),
          border: Border.all(
            color: isSelected
                ? ThemeConstants.primaryOrange
                : Colors.white.withOpacity(0.1),
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: ThemeConstants.primaryOrange.withOpacity(0.3),
                    blurRadius: 6,
                    spreadRadius: 1,
                  )
                ]
              : null,
        ),
        child: Text(
          shown ?? label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white70,
            fontSize: 12.sp,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(LocalizationService loc) {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(24.r),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.02),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: Icon(Icons.receipt_long_outlined, size: 70.sp, color: Colors.white30),
            ),
            SizedBox(height: 20.h),
            Text(
              LocalizationService.instance.translate('no_receipts_found'),
              style: TextStyle(color: Colors.white, fontSize: 18.sp, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8.h),
            Text(
              LocalizationService.instance.translate('no_payments_with_receipts_have_been'),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 13.sp),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReceiptsList(List<dynamic> list, LocalizationService loc) {
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, widget.isSubView ? 100.h : 20.h),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final receipt = list[index];
        return _buildReceiptCard(receipt, loc);
      },
    );
  }

  Widget _buildReceiptCard(Map<String, dynamic> receipt, LocalizationService loc) {
    final payment = receipt['payment'] ?? {};
    final tenant = payment['tenant'] ?? {};
    final details = receipt['details'] ?? {};
    final amount = TypeHelpers.toDouble(details['amount_paid'] ?? payment['amount_paid']);
    final paymentMethod = (details['payment_method'] ?? 'Cash').toString();
    final receiptNumber = (details['receipt_number'] ?? receipt['receipt_number'] ?? 'RCP-xxx').toString();
    final tenantName = (tenant['name'] ?? LocalizationService.instance.translate('agreement_step_tenant')).toString();
    final property = (details['property_name'] ?? LocalizationService.instance.translate('property_label')).toString();
    final house = (details['house_number'] ?? '').toString();

    String dateStr = receipt['created_at'] ?? payment['payment_date'] ?? '';
    String formattedDate = LocalizationService.instance.translate('today');
    if (dateStr.isNotEmpty) {
      try {
        formattedDate = DateFormat('dd MMM yyyy, HH:mm').format(DateTime.parse(dateStr));
      } catch (_) {
        formattedDate = dateStr;
      }
    }

    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(color: Colors.white.withOpacity(0.15)),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              // Construct synthetic compatible payment map for ReceiptViewScreen
              final syntheticPayment = {
                'id': receipt['id']?.toString() ?? details['id']?.toString() ?? payment['id']?.toString() ?? 'N/A',
                'created_at': receipt['created_at'] ?? payment['payment_date'] ?? '',
                'amount_paid': details['amount_paid'] ?? payment['amount_paid'] ?? payment['amount'] ?? '0',
                'payment_method': details['payment_method'] ?? payment['payment_method'] ?? 'Cash',
                'tenant': {
                  'name': tenantName,
                },
                'bill': {
                  'balance': details['balance_remaining'] ?? payment['balance_remaining'] ?? '0',
                  'due_date': payment['bill']?['due_date'] ?? details['due_date'] ?? '',
                  'house': {
                    'house_number': house,
                    'property': {
                      'name': property,
                    }
                  },
                  'agreement': {
                    'rent_amount': payment['bill']?['agreement']?['rent_amount'] ?? '1',
                  }
                },
                'receipt': {
                  'id': receipt['id']?.toString() ?? details['id']?.toString() ?? '',
                  'receipt_number': receiptNumber,
                }
              };

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ReceiptViewScreen(payment: syntheticPayment),
                ),
              );
            },
            borderRadius: BorderRadius.circular(16.r),
            child: Padding(
              padding: EdgeInsets.all(16.w),
              child: Row(
                children: [
                  // Receipt Icon container with standard orange style
                  Container(
                    padding: EdgeInsets.all(12.w),
                    decoration: BoxDecoration(
                      color: ThemeConstants.primaryOrange.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Icon(
                      Icons.receipt_long,
                      color: ThemeConstants.primaryOrange,
                      size: 24.sp,
                    ),
                  ),
                  SizedBox(width: 14.w),
                  // Details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                receiptNumber,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                              decoration: BoxDecoration(
                                color: ThemeConstants.primaryOrange.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6.r),
                              ),
                              child: Text(
                                paymentMethod,
                                style: TextStyle(
                                  color: ThemeConstants.primaryOrange,
                                  fontSize: 10.sp,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 5.h),
                        Text(
                          tenantName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(height: 2.h),
                        Text(
                          "$property ${house.isNotEmpty ? '- ${LocalizationService.instance.translate('house_label')} $house' : ''}",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 11.sp,
                          ),
                        ),
                        SizedBox(height: 6.h),
                        Text(
                          formattedDate,
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 10.sp,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 12.w),
                  // Amount with standard success green color
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        "TZS",
                        style: TextStyle(
                          color: ThemeConstants.successGreen,
                          fontSize: 10.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _formatCurrency(amount),
                        style: TextStyle(
                          color: ThemeConstants.successGreen,
                          fontSize: 16.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
