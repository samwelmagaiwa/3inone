import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../../constants/theme_constants.dart';
import '../../../services/api_service.dart';
import '../../../services/localization_service.dart';

/// Full-screen barcode/QR scanner.
/// Resolves any scanned code against the backend and shows:
///  - Product detail sheet  (entity_type == 'product' | 'product_unit')
///  - Sale/receipt detail sheet  (entity_type == 'sale')
class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  final ApiService _api = ApiService();
  final MobileScannerController _ctrl = MobileScannerController();
  bool _processing = false;
  String? _lastCode;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    final String? raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw == _lastCode || _processing) return;
    _lastCode = raw;

    await _ctrl.stop();
    setState(() => _processing = true);

    try {
      final Map<String, dynamic>? res =
          await _api.getOrNull('/inventory/barcodes/resolve?code=${Uri.encodeComponent(raw)}');

      if (!mounted) return;

      if (res == null) {
        _showError(raw);
        return;
      }

      final data = (res['data'] as Map<String, dynamic>?) ?? {};
      final String entityType = (data['entity_type'] ?? '').toString();
      final detail = data['detail'];

      if (entityType == 'product' || entityType == 'product_unit') {
        await _showProductSheet(raw, detail);
      } else if (entityType == 'sale') {
        await _showSaleSheet(raw, detail);
      } else {
        _showError(raw);
      }
    } catch (_) {
      if (mounted) _showError(raw);
    } finally {
      if (mounted) {
        setState(() {
          _processing = false;
          _lastCode = null;
        });
        await _ctrl.start();
      }
    }
  }

  void _showError(String code) {
    ThemeConstants.showErrorSnackBar(
      context,
      LocalizationService.instance.translateWith('code_not_found', <Object?>[code]),
    );
  }

  Future<void> _showProductSheet(String code, dynamic detail) async {
    final Map<String, dynamic> d = detail is Map
        ? Map<String, dynamic>.from(detail)
        : <String, dynamic>{};

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: ThemeConstants.primaryBlue,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20.r))),
      isScrollControlled: true,
      builder: (_) => _ProductDetailSheet(code: code, data: d),
    );
  }

  Future<void> _showSaleSheet(String code, dynamic detail) async {
    final Map<String, dynamic> d = detail is Map
        ? Map<String, dynamic>.from(detail)
        : <String, dynamic>{};

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: ThemeConstants.primaryBlue,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20.r))),
      isScrollControlled: true,
      builder: (_) => _SaleDetailSheet(code: code, data: d),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(loc.isSwahili ? 'Scan Bidhaa / Risiti' : 'Scan Product / Receipt'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _ctrl.toggleTorch(),
            tooltip: LocalizationService.instance.translate('torch'),
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_ios),
            onPressed: () => _ctrl.switchCamera(),
            tooltip: LocalizationService.instance.translate('flip_camera'),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _ctrl,
            onDetect: _onDetect,
          ),
          // Scanning overlay
          Center(
            child: Container(
              width: 260.w,
              height: 260.w,
              decoration: BoxDecoration(
                border: Border.all(
                    color: ThemeConstants.primaryOrange, width: 2.5),
                borderRadius: BorderRadius.circular(16.r),
              ),
            ),
          ),
          Positioned(
            bottom: 60.h,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20.r),
                ),
                child: Text(
                  loc.isSwahili
                      ? 'Lenga kamera kwenye barcode au QR code'
                      : 'Point camera at barcode or QR code',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          if (_processing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Product Detail Sheet ─────────────────────────────────────────────────────

class _ProductDetailSheet extends StatelessWidget {
  const _ProductDetailSheet({required this.code, required this.data});
  final String code;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final String name = _s(data['name']);
    final String sku = _s(data['sku']);
    final String barcode = _s(data['barcode']);
    final String category = _s(data['category_name']);
    final String brand = _s(data['brand_name']);
    final String unit = _s(data['unit']);
    final String status = _s(data['status']);
    final double cost = _d(data['cost_price']);
    final double price = _d(data['selling_price']);
    final int qty = _i(data['quantity']);
    final int minStock = _i(data['min_stock']);
    final String priceTier = _s(data['price_tier']);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (_, scroll) => SingleChildScrollView(
        controller: scroll,
        padding: EdgeInsets.all(20.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40.w,
                height: 4.h,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2.r),
                ),
              ),
            ),
            SizedBox(height: 16.h),
            Row(
              children: [
                Container(
                  width: 48.w,
                  height: 48.w,
                  decoration: BoxDecoration(
                    color: ThemeConstants.primaryOrange.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.inventory_2_rounded,
                      color: ThemeConstants.primaryOrange, size: 26.sp),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name.isNotEmpty ? name : LocalizationService.instance.translate('unknown_product'),
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 17.sp)),
                      Text(sku,
                          style: TextStyle(
                              color: Colors.white54, fontSize: 12.sp)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: status == 'active'
                        ? Colors.green.shade700
                        : Colors.red.shade700,
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: Text(status.toUpperCase(),
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 10.sp,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            SizedBox(height: 20.h),
            _section(loc.isSwahili ? 'Bei' : 'Pricing', [
              _row(loc.isSwahili ? 'Bei ya Kununua' : 'Cost Price',
                  'TZS ${_fmt(cost)}'),
              _row(loc.isSwahili ? 'Bei ya Kuuza' : 'Selling Price',
                  'TZS ${_fmt(price)}',
                  highlight: true),
              _row(loc.isSwahili ? 'Faida' : 'Profit per unit',
                  'TZS ${_fmt(price - cost)}'),
              _row(loc.isSwahili ? 'Aina ya Bei' : 'Price Tier',
                  priceTier.toUpperCase()),
            ]),
            SizedBox(height: 12.h),
            _section(loc.isSwahili ? 'Hifadhi' : 'Stock', [
              _row(loc.isSwahili ? 'Kiasi' : 'Quantity', '$qty $unit',
                  highlight: qty <= minStock),
              _row(loc.isSwahili ? 'Kiwango cha Chini' : 'Min Stock',
                  '$minStock $unit'),
              if (qty <= minStock)
                Padding(
                  padding: EdgeInsets.only(top: 4.h),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: Colors.orange, size: 16.sp),
                      SizedBox(width: 6.w),
                      Text(
                          loc.isSwahili
                              ? 'Hifadhi iko chini ya kiwango'
                              : 'Stock below minimum threshold',
                          style: TextStyle(
                              color: Colors.orange, fontSize: 11.sp)),
                    ],
                  ),
                ),
            ]),
            SizedBox(height: 12.h),
            _section(loc.isSwahili ? 'Maelezo' : 'Details', [
              if (category.isNotEmpty)
                _row(loc.isSwahili ? 'Kategoria' : 'Category', category),
              if (brand.isNotEmpty)
                _row(loc.isSwahili ? 'Chapa' : 'Brand', brand),
              _row(loc.isSwahili ? 'Kitengo' : 'Unit', unit),
              if (barcode.isNotEmpty)
                _row(LocalizationService.instance.translate('barcode'), barcode),
            ]),
            SizedBox(height: 20.h),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.check),
                label: Text(loc.isSwahili ? 'Sawa' : 'Done'),
                style: FilledButton.styleFrom(
                    backgroundColor: ThemeConstants.primaryOrange),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> rows) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8)),
          SizedBox(height: 6.h),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Column(children: rows),
          ),
        ],
      );

  Widget _row(String label, String value, {bool highlight = false}) => Padding(
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style:
                    TextStyle(color: Colors.white54, fontSize: 13.sp)),
            Text(value,
                style: TextStyle(
                    color: highlight ? ThemeConstants.primaryOrange : Colors.white,
                    fontWeight:
                        highlight ? FontWeight.bold : FontWeight.normal,
                    fontSize: 13.sp)),
          ],
        ),
      );

  String _s(dynamic v) => (v ?? '').toString();
  double _d(dynamic v) =>
      double.tryParse(v?.toString() ?? '') ?? 0;
  int _i(dynamic v) => int.tryParse(v?.toString() ?? '') ?? 0;
  String _fmt(double v) => v.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
}

// ─── Sale / Receipt Detail Sheet ─────────────────────────────────────────────

class _SaleDetailSheet extends StatelessWidget {
  const _SaleDetailSheet({required this.code, required this.data});
  final String code;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final Map<String, dynamic> sale = data['sale'] is Map
        ? Map<String, dynamic>.from(data['sale'] as Map)
        : <String, dynamic>{};
    final List<dynamic> items = data['items'] is List
        ? List<dynamic>.from(data['items'] as List)
        : <dynamic>[];
    final List<dynamic> payments = data['payments'] is List
        ? List<dynamic>.from(data['payments'] as List)
        : <dynamic>[];

    final String number = _s(sale['number']);
    final String customerName = _s(sale['customer_name']);
    final String customerPhone = _s(sale['customer_phone']);
    final double total = _d(sale['total']);
    final double paidTotal = _d(sale['paid_total']);
    final String status = _s(sale['payment_status']);
    final String createdAt = _s(sale['created_at']).split('T').first;
    final String cancelledAt = _s(sale['cancelled_at']);

    final Color statusColor = status == 'paid'
        ? Colors.green.shade400
        : status == 'debt'
            ? Colors.red.shade400
            : Colors.orange.shade400;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.97,
      builder: (_, scroll) => SingleChildScrollView(
        controller: scroll,
        padding: EdgeInsets.all(20.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40.w,
                height: 4.h,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2.r),
                ),
              ),
            ),
            SizedBox(height: 16.h),
            // Header
            Row(
              children: [
                Container(
                  width: 48.w,
                  height: 48.w,
                  decoration: BoxDecoration(
                    color: Colors.blue.shade800.withOpacity(0.4),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.receipt_long_rounded,
                      color: Colors.lightBlueAccent, size: 26.sp),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          loc.isSwahili ? 'Risiti ya Mauzo' : 'Sales Receipt',
                          style: TextStyle(
                              color: Colors.white54, fontSize: 11.sp)),
                      Text(number.isNotEmpty ? number : code,
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 17.sp)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(10.r),
                    border: Border.all(color: statusColor, width: 1),
                  ),
                  child: Text(status.toUpperCase(),
                      style: TextStyle(
                          color: statusColor,
                          fontSize: 10.sp,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            if (cancelledAt.isNotEmpty) ...[
              SizedBox(height: 8.h),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                decoration: BoxDecoration(
                  color: Colors.red.shade900.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Row(
                  children: [
                    Icon(Icons.cancel_outlined,
                        color: Colors.redAccent, size: 16.sp),
                    SizedBox(width: 8.w),
                    Text(
                        '${loc.isSwahili ? 'Imefutwa' : 'CANCELLED'} · $cancelledAt',
                        style: TextStyle(
                            color: Colors.redAccent, fontSize: 12.sp)),
                  ],
                ),
              ),
            ],
            SizedBox(height: 16.h),
            // Customer & Date
            if (customerName.isNotEmpty)
              _infoRow(Icons.person_outline,
                  '${loc.isSwahili ? 'Mteja' : 'Customer'}: $customerName${customerPhone.isNotEmpty ? ' · $customerPhone' : ''}'),
            _infoRow(Icons.calendar_today_outlined,
                '${loc.isSwahili ? 'Tarehe' : 'Date'}: $createdAt'),
            SizedBox(height: 16.h),
            // Items
            Text(loc.isSwahili ? 'Bidhaa Zilizoaguliwa' : 'Items Sold',
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8)),
            SizedBox(height: 6.h),
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Column(
                children: [
                  for (final raw in items) ...[
                    () {
                      final m = Map<String, dynamic>.from(raw as Map);
                      final pName = _s(m['product_name']);
                      final qty = _i(m['quantity']);
                      final unitPrice = _d(m['unit_price']);
                      final lineTotal = _d(m['total']);
                      return Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: 14.w, vertical: 10.h),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(pName,
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 13.sp)),
                                  Text(
                                      '$qty × TZS ${_fmt(unitPrice)}',
                                      style: TextStyle(
                                          color: Colors.white54,
                                          fontSize: 11.sp)),
                                ],
                              ),
                            ),
                            Text('TZS ${_fmt(lineTotal)}',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13.sp)),
                          ],
                        ),
                      );
                    }(),
                    if (raw != items.last)
                      Divider(height: 1, color: Colors.white12),
                  ],
                  if (items.isEmpty)
                    Padding(
                      padding: EdgeInsets.all(16.w),
                      child: Text(
                          loc.isSwahili ? 'Hakuna bidhaa' : 'No items',
                          style: TextStyle(
                              color: Colors.white38, fontSize: 13.sp)),
                    ),
                ],
              ),
            ),
            SizedBox(height: 12.h),
            // Totals
            Container(
              padding: EdgeInsets.all(14.w),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Column(
                children: [
                  _totRow(loc.isSwahili ? 'Jumla' : 'Total',
                      'TZS ${_fmt(total)}',
                      bold: true),
                  SizedBox(height: 6.h),
                  _totRow(loc.isSwahili ? 'Kilicholipwa' : 'Paid',
                      'TZS ${_fmt(paidTotal)}',
                      color: Colors.greenAccent),
                  if (total - paidTotal > 0) ...[
                    SizedBox(height: 6.h),
                    _totRow(loc.isSwahili ? 'Baki' : 'Balance',
                        'TZS ${_fmt(total - paidTotal)}',
                        color: Colors.redAccent),
                  ],
                ],
              ),
            ),
            // Payments
            if (payments.isNotEmpty) ...[
              SizedBox(height: 12.h),
              Text(loc.isSwahili ? 'Malipo' : 'Payments',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8)),
              SizedBox(height: 6.h),
              for (final p in payments)
                () {
                  final m = Map<String, dynamic>.from(p as Map);
                  return _infoRow(
                    Icons.payments_outlined,
                    'TZS ${_fmt(_d(m['amount']))} · ${_s(m['method'])} · ${_s(m['paid_at']).split('T').first}',
                  );
                }(),
            ],
            SizedBox(height: 20.h),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.check),
                label: Text(loc.isSwahili ? 'Sawa' : 'Done'),
                style: FilledButton.styleFrom(
                    backgroundColor: ThemeConstants.primaryOrange),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) => Padding(
        padding: EdgeInsets.only(bottom: 6.h),
        child: Row(
          children: [
            Icon(icon, color: Colors.white38, size: 16.sp),
            SizedBox(width: 8.w),
            Expanded(
                child: Text(text,
                    style: TextStyle(color: Colors.white70, fontSize: 13.sp))),
          ],
        ),
      );

  Widget _totRow(String label, String value,
          {bool bold = false, Color? color}) =>
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  color: Colors.white54,
                  fontSize: 13.sp,
                  fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          Text(value,
              style: TextStyle(
                  color: color ?? Colors.white,
                  fontSize: 13.sp,
                  fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
        ],
      );

  String _s(dynamic v) => (v ?? '').toString();
  double _d(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0;
  int _i(dynamic v) => int.tryParse(v?.toString() ?? '') ?? 0;
  String _fmt(double v) => v.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
}
