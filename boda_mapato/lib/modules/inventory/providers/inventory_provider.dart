// ignore_for_file: cascade_invocations
import '../../../utils/server_time.dart';
import 'dart:async';
import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../services/api_service.dart';
import '../models/inv_batch.dart';
import '../models/inv_brand.dart';
import '../models/inv_capabilities.dart';
import '../models/inv_category.dart';
import '../models/inv_customer.dart';
import '../models/inv_product.dart';
import '../models/inv_product_unit.dart';
import '../models/inv_reminder.dart';
import '../models/inv_sale.dart';
import '../services/inv_event_bus.dart';
import '../../../services/localization_service.dart';
import '../../../utils/server_message.dart';

class InventoryProvider extends ChangeNotifier {
  /// [api] lets tests supply canned answers; the app uses the real client.
  InventoryProvider({ApiService? api}) : _api = api ?? ApiService() {
    _busSub = InvEventBus.instance.stream.listen(_onBusEvent);
  }

  final ApiService _api;
  late final StreamSubscription<Set<InvDomain>> _busSub;

  @override
  void dispose() {
    _busSub.cancel();
    super.dispose();
  }

  /// Reacts to domain events emitted by any mutation in the app and
  /// refreshes whichever slices of data this provider owns.
  void _onBusEvent(Set<InvDomain> domains) {
    final futures = <Future<void>>[];

    if (domains.contains(InvDomain.sale) ||
        domains.contains(InvDomain.credit)) {
      futures.addAll([fetchSales(), fetchKpis()]);
    }
    if (domains.contains(InvDomain.product) ||
        domains.contains(InvDomain.stock)) {
      futures.add(fetchProducts());
    }
    if (domains.contains(InvDomain.stock)) {
      futures.add(fetchBatches());
    }
    if (domains.contains(InvDomain.expense)) {
      futures.add(fetchKpis());
    }
    if (domains.contains(InvDomain.settings)) {
      futures.add(fetchCapabilities());
    }
    // Always refresh KPIs after a sale (covers debt total, cash, profit).
    if (domains.contains(InvDomain.sale)) {
      // already added above — no-op duplicate guard
    }

    Future.wait(futures).then((_) {
      _refreshLowStockReminders();
      _refreshPaymentDueReminders();
      notifyListeners();
    }).ignore();
  }

  // Data
  final List<InvProduct> _products = <InvProduct>[];
  final List<InvCustomer> _customers = <InvCustomer>[];
  final List<InvSale> _sales = <InvSale>[];
  final List<InvReminder> _reminders = <InvReminder>[];
  final List<InvCategory> _categories = <InvCategory>[];
  final List<InvBrand> _brands = <InvBrand>[];
  // Selling units keyed by product id (Area 2 - products, units & pricing).
  final Map<int, List<InvProductUnit>> _unitsByProduct =
      <int, List<InvProductUnit>>{};
  // Area 3 - stock control.
  final List<InvBatch> _batches = <InvBatch>[];
  final List<InvWriteOff> _writeOffs = <InvWriteOff>[];
  final List<InvStockCount> _stockCounts = <InvStockCount>[];
  final List<InvStockMovement> _stockMovements = <InvStockMovement>[];
  int _expiredCount = 0;
  int _expiringSoonCount = 0;

  // What the business's inventory is set up to do (see InvCapabilities). Until the settings arrive it is the
  // depot's behaviour -- exactly what the app did before kinds of business existed.
  InvCapabilities _capabilities = const InvCapabilities();
  // The price level the cashier picked for this cart (retail / wholesale); null = the business's own.
  String? _tierOverride;
  // Why the last create / update was refused (the server's own words), for the screen to show.
  String? _lastError;

  // POS cart state
  final List<InvSaleItem> _cart = <InvSaleItem>[];
  String _paymentMode = 'cash'; // cash | debt | partial
  int? _selectedCustomerId;
  String _selectedCustomerPhone = '';
  String _manualPhone = '';  // optional phone for walk-in sales
  String _manualName = '';   // optional name  for walk-in sales
  double _paidAmount = 0;
  String _partialPaymentMethod = 'cash'; // method for the deposit on a partial sale

  // Sales history pagination + summary
  int _salesPage = 1;
  bool _salesHasMore = false;
  Map<String, dynamic> _salesSummary = {};

  // KPIs — fetched from GET /inventory/kpis
  double _kpiTodayTotal    = 0;
  double _kpiTodayProfit   = 0;
  double _kpiCashToday     = 0;
  double _kpiDebtTotal     = 0;
  double _kpiExpensesToday = 0;

  // Monthly chart — fetched from GET /inventory/sales/monthly-chart
  // Keyed by "year-month" → list of daily totals (index 0 = day 1)
  final Map<String, List<double>> _monthlyChartCache = {};

  // Dashboard sales-officer filter (admin/super_admin/manager only). When
  // set, every dashboard/sales query is scoped to this one officer's data;
  // sales_officer viewers never set this -- the backend already locks them
  // to their own data regardless.
  // User ids are UUID strings (see users.id), not integers.
  String? _selectedOfficerId;
  List<Map<String, dynamic>> _salesOfficers = [];

  String? get selectedOfficerId => _selectedOfficerId;
  List<Map<String, dynamic>> get salesOfficers => _salesOfficers;

  void setSelectedOfficer(String? officerId) {
    if (_selectedOfficerId == officerId) return;
    _selectedOfficerId = officerId;
    notifyListeners();
    bootstrap();
  }

  /// Users a privileged viewer can filter the dashboard down to. Returns an
  /// empty list for a sales_officer viewer (backend enforces this too).
  Future<void> fetchSalesOfficers() async {
    try {
      final res = await _api.getOrNull('/inventory/sales-officers');
      if (res == null) return;
      final List<dynamic> list = (res['data'] is List)
          ? List<dynamic>.from(res['data'] as List)
          : <dynamic>[];
      _salesOfficers = list
          .map((j) => Map<String, dynamic>.from(j as Map))
          .toList();
      notifyListeners();
    } on Exception {
      // leave cached list intact
    }
  }

  // Accessors
  List<InvProduct> get products => List.unmodifiable(_products);
  List<InvCustomer> get customers => List.unmodifiable(_customers);
  List<InvSale> get sales => List.unmodifiable(_sales);
  bool get salesHasMore => _salesHasMore;
  Map<String, dynamic> get salesSummary => Map.unmodifiable(_salesSummary);
  List<InvReminder> get reminders => List.unmodifiable(_reminders);
  List<InvCategory> get categories => List.unmodifiable(_categories);
  List<InvBrand> get brands => List.unmodifiable(_brands);

  List<InvBatch> get batches => List.unmodifiable(_batches);
  List<InvWriteOff> get writeOffs => List.unmodifiable(_writeOffs);
  List<InvStockCount> get stockCounts => List.unmodifiable(_stockCounts);
  List<InvStockMovement> get stockMovements => List.unmodifiable(_stockMovements);
  int get expiredBatchCount => _expiredCount;
  int get expiringSoonCount => _expiringSoonCount;
  int get pendingWriteOffCount =>
      _writeOffs.where((InvWriteOff w) => w.isPending).length;

  /// Batches of one product with stock left, first-expiring first.
  List<InvBatch> batchesOf(int productId) {
    final List<InvBatch> rows = _batches
        .where((InvBatch b) => b.productId == productId && b.quantity > 0)
        .toList()
      ..sort((InvBatch a, InvBatch b) {
        final DateTime? ea = a.expiryDate;
        final DateTime? eb = b.expiryDate;
        if (ea == null && eb == null) return a.id.compareTo(b.id);
        if (ea == null) return 1;
        if (eb == null) return -1;
        return ea.compareTo(eb);
      });
    return List.unmodifiable(rows);
  }

  /// Total value of stock on hand, costed from batches.
  double get stockValuation =>
      _batches.fold<double>(0, (double sum, InvBatch b) => sum + b.stockValue);

  /// Total purchasing cost across all products in stock
  double get totalInventoryCost => _products.fold<double>(
      0, (double sum, InvProduct p) => sum + p.totalCostPrice);

  /// Total expected selling revenue across all products in stock
  double get totalInventoryRevenue => _products.fold<double>(
      0, (double sum, InvProduct p) => sum + p.totalSellingPrice);

  /// Total expected profit margin across all products in stock
  double get totalInventoryExpectedProfit => _products.fold<double>(
      0, (double sum, InvProduct p) => sum + p.totalExpectedProfit);

  /// Selling units already loaded for a product; empty until [fetchUnits].
  List<InvProductUnit> unitsOf(int productId) =>
      List.unmodifiable(_unitsByProduct[productId] ?? const <InvProductUnit>[]);
  List<InvSaleItem> get cart => List.unmodifiable(_cart);
  String get paymentMode => _paymentMode;
  int? get selectedCustomerId => _selectedCustomerId;
  String get selectedCustomerPhone => _selectedCustomerPhone;
  String get manualPhone => _manualPhone;
  String get manualName => _manualName;
  double get paidAmount => _paidAmount;
  String get partialPaymentMethod => _partialPaymentMethod;

  double get cartSubtotal => _cart.fold(0, (sum, it) => sum + it.total);
  // Salon: a discount on the whole sale, why it was given, and how the client paid. (The shop has none of these:
  // its cart discount stays zero and a full payment is cash.)
  double _salonDiscount = 0;
  String _discountReason = '';
  String _cashChannel = 'cash';

  /// The code of a payment made by mobile money or the bank (asked for, and required, whenever it was not cash).
  String _paymentReference = '';
  String _partialReference = '';

  /// The ways a salon client may pay: cash, the mobile money networks, the bank.
  static const List<String> paymentChannels = <String>['cash', 'mpesa', 'mixx', 'airtel_money', 'halopesa', 'bank_transfer'];

  double get cartDiscount => !_salonMode ? 0 : (_salonDiscount > cartSubtotal ? cartSubtotal : _salonDiscount);

  // Salon perks at the till: a voucher code, loyalty points spent, packages used on lines. Their discount is part of
  // the sale's discount (the server checks the two agree).
  String _voucherCode = '';
  double _voucherOff = 0;
  int _pointsUsed = 0;
  int _pointValue = 0;

  String get voucherCode => _voucherCode;
  double get voucherOff => !_salonMode ? 0 : (_voucherOff > cartSubtotal ? cartSubtotal : _voucherOff);
  int get pointsUsed => _pointsUsed;
  double get pointsOff {
    if (!_salonMode || _pointsUsed <= 0) return 0;
    final double room = cartSubtotal - voucherOff;
    final double worth = _pointsUsed * _pointValue.toDouble();

    return worth > room ? (room < 0 ? 0 : room) : worth;
  }

  /// Everything taken off the sale: the typed discount, the voucher and the points (never more than the lines).
  double get totalDiscount {
    final double d = cartDiscount + voucherOff + pointsOff;

    return d > cartSubtotal ? cartSubtotal : d;
  }

  void setVoucher(String code, double off) {
    _voucherCode = code.trim().toUpperCase();
    _voucherOff = off < 0 ? 0 : off;
    notifyListeners();
  }

  void clearVoucher() {
    _voucherCode = '';
    _voucherOff = 0;
    notifyListeners();
  }

  void setRedeemPoints(int points, int valuePerPoint) {
    _pointsUsed = points < 0 ? 0 : points;
    _pointValue = valuePerPoint < 0 ? 0 : valuePerPoint;
    notifyListeners();
  }

  /// Take this line from one of the client's packages (it becomes free), or put it back to its price.
  void setLinePackage(InvSaleItem item, int? packageId) {
    if (packageId != null && item.packageId == null) {
      item.priceBeforePackage = item.unitPrice;
      item.unitPrice = 0;
    } else if (packageId == null && item.packageId != null) {
      item.unitPrice = item.priceBeforePackage ?? item.unitPrice;
      item.priceBeforePackage = null;
    }
    item.packageId = packageId;
    _retax(item);
    notifyListeners();
  }

  void _clearPerks({bool keepVoucher = false}) {
    if (!keepVoucher) {
      _voucherCode = '';
      _voucherOff = 0;
    }
    _pointsUsed = 0;
    for (final InvSaleItem it in _cart) {
      if (it.packageId != null) {
        it.unitPrice = it.priceBeforePackage ?? it.unitPrice;
        it.priceBeforePackage = null;
        it.packageId = null;
        _retax(it);
      }
    }
  }
  String get discountReason => _discountReason;
  String get cashChannel => _cashChannel;
  String get paymentReference => _paymentReference;

  /// Money that did not come as cash is traced by its reference number: the sale cannot be saved without it.
  bool get missingReference =>
      (_paymentMode == 'cash' && _salonMode && _cashChannel != 'cash' && _paymentReference.trim().isEmpty) ||
      (_paymentMode == 'partial' && _paidAmount > 0 && _partialPaymentMethod != 'cash' && _partialReference.trim().isEmpty);
  String get partialReference => _partialReference;

  void setCartDiscount(double amount) {
    _salonDiscount = amount < 0 ? 0 : amount;
    notifyListeners();
  }

  void setDiscountReason(String reason) {
    _discountReason = reason;
    notifyListeners();
  }

  void setCashChannel(String channel) {
    _cashChannel = channel;
    notifyListeners();
  }

  void setPaymentReference(String reference) {
    _paymentReference = reference;
    notifyListeners();
  }

  void setPartialReference(String reference) {
    _partialReference = reference;
    notifyListeners();
  }

  /// The VAT the cart carries: each line's, from its product's rate (or the business's default).
  double get cartTax => _cart.fold(0, (double sum, InvSaleItem it) => sum + it.taxAmount);

  /// When prices already include VAT the total is just the lines; otherwise VAT is added on top.
  double get cartTotal =>
      cartSubtotal - totalDiscount + (_capabilities.pricesIncludeVat ? 0 : cartTax);
  double get cartProfit => _cart.fold(0, (sum, it) => sum + it.profit);

  InvCapabilities get capabilities => _capabilities;
  String? get lastError => _lastError;

  /// The price level in use: what the cashier picked, else the business's own (retail for a depot).
  String get cartTier => _tierOverride ?? _capabilities.startingTier;

  List<InvProduct> get lowStockTop5 {
    final list = _products.where((p) => p.quantity < p.minStock).toList()
      ..sort((a, b) =>
          (a.quantity - a.minStock).compareTo(b.quantity - b.minStock));
    return list.take(5).toList();
  }

  // Sales KPIs — backed by GET /inventory/kpis (real DB aggregates)
  double get totalSalesToday     => _kpiTodayTotal;
  double get profitToday         => _kpiTodayProfit;
  double get cashToday           => _kpiCashToday;
  double get creditOutstanding   => _kpiDebtTotal;
  double get expensesToday       => _kpiExpensesToday;
  String get totalSalesTodayFormatted =>
      'TZS ${_kpiTodayTotal.toStringAsFixed(0)}';
  String get profitTodayFormatted =>
      'TZS ${_kpiTodayProfit.toStringAsFixed(0)}';

  // Monthly chart cache accessor
  List<double>? cachedMonthlyChart(int year, int month) =>
      _monthlyChartCache['$year-$month'];

  // Trend (derived): last 12 days totals (fallbacks to mock if no data)
  List<FlSpot> get salesTrend {
    final now = DateTime.now();
    final Map<int, double> dayTotals = {};
    for (int i = 11; i >= 0; i--) {
      final d =
          DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
      final key = d.millisecondsSinceEpoch;
      dayTotals[key] = 0;
    }
    for (final s in _sales) {
      final d = DateTime(s.createdAt.year, s.createdAt.month, s.createdAt.day)
          .millisecondsSinceEpoch;
      if (dayTotals.containsKey(d)) {
        dayTotals[d] = (dayTotals[d] ?? 0) + s.total;
      }
    }
    final bool empty = _sales.isEmpty;
    int x = 0;
    final List<FlSpot> spots = <FlSpot>[];
    for (final v in dayTotals.values) {
      final double y = (v as num).toDouble();
      spots
          .add(FlSpot(x.toDouble(), empty ? (2000 + (x * 700)).toDouble() : y));
      x++;
    }
    return spots;
  }

  // Build a secondary series from a base for mock dual-line chart
  List<FlSpot> _seriesFromBase(List<FlSpot> base,
          {double factor = 0.8, double offset = 1200}) =>
      base.map((e) => FlSpot(e.x, (e.y * factor) + offset)).toList();

  // Weekly trend: last 12 weeks
  List<FlSpot> get salesTrendWeekly {
    final now = DateTime.now();
    final DateTime mondayThisWeek =
        now.subtract(Duration(days: now.weekday - 1));
    final List<DateTime> weeks = List<DateTime>.generate(
        12, (i) => mondayThisWeek.subtract(Duration(days: (11 - i) * 7)));
    final Map<int, double> totals = {
      for (final d in weeks) d.millisecondsSinceEpoch: 0
    };
    for (final s in _sales) {
      final d = s.createdAt;
      final DateTime monday = d.subtract(Duration(days: d.weekday - 1));
      final key = DateTime(monday.year, monday.month, monday.day)
          .millisecondsSinceEpoch;
      if (totals.containsKey(key)) totals[key] = (totals[key] ?? 0) + s.total;
    }
    final bool empty = _sales.isEmpty;
    int x = 0;
    final List<FlSpot> spots = [];
    for (final v in totals.values) {
      final double y = (v as num).toDouble();
      spots.add(FlSpot(x.toDouble(), empty ? (5000 + x * 1500).toDouble() : y));
      x++;
    }
    return spots;
  }

  // Monthly trend: last 12 months
  List<FlSpot> get salesTrendMonthly {
    final now = DateTime.now();
    final List<DateTime> months = List<DateTime>.generate(12, (i) {
      final DateTime d = DateTime(now.year, now.month - (11 - i));
      return DateTime(d.year, d.month);
    });
    final Map<int, double> totals = {
      for (final d in months) d.millisecondsSinceEpoch: 0
    };
    for (final s in _sales) {
      final DateTime m = DateTime(s.createdAt.year, s.createdAt.month);
      final key = m.millisecondsSinceEpoch;
      if (totals.containsKey(key)) totals[key] = (totals[key] ?? 0) + s.total;
    }
    final bool empty = _sales.isEmpty;
    int x = 0;
    final List<FlSpot> spots = [];
    for (final v in totals.values) {
      final double y = (v as num).toDouble();
      spots
          .add(FlSpot(x.toDouble(), empty ? (12000 + x * 2500).toDouble() : y));
      x++;
    }
    return spots;
  }

  int get lowStockCount =>
      _products.where((p) => p.quantity < p.minStock).length;

  // Dual-series for chart (mocked from base series)
  List<FlSpot> get onlineTrendDaily =>
      _seriesFromBase(salesTrend, factor: 1.1, offset: 800);
  List<FlSpot> get posTrendDaily =>
      _seriesFromBase(salesTrend, factor: 0.9, offset: 500);
  List<FlSpot> get onlineTrendWeekly =>
      _seriesFromBase(salesTrendWeekly, factor: 1.05);
  List<FlSpot> get posTrendWeekly =>
      _seriesFromBase(salesTrendWeekly, factor: 0.85, offset: 900);
  List<FlSpot> get onlineTrendMonthly =>
      _seriesFromBase(salesTrendMonthly, factor: 1.08, offset: 2500);
  List<FlSpot> get posTrendMonthly =>
      _seriesFromBase(salesTrendMonthly, factor: 0.88, offset: 1800);

  String get topSellingProductName {
    final Map<int, double> totals = <int, double>{};
    for (final s in _sales) {
      for (final it in s.items) {
        totals[it.productId] = (totals[it.productId] ?? 0) + it.qty.toDouble();
      }
    }
    if (totals.isEmpty) {
      return _products.isNotEmpty ? _products.first.name : 'â€”';
    }
    int bestId = totals.keys.first;
    double best = totals[bestId] ?? 0;
    totals.forEach((id, v) {
      if (v > best) {
        best = v;
        bestId = id;
      }
    });
    final p = _products.firstWhere((e) => e.id == bestId,
        orElse: () => _products.isNotEmpty
            ? _products.first
            : InvProduct(
                id: 0,
                name: 'â€”',
                sku: '',
                category: '',
                costPrice: 0,
                sellingPrice: 0,
                unit: 'pcs',
                quantity: 0,
                minStock: 0,
                status: 'active',
                barcode: '',
                createdBy: 0));
    return p.name;
  }

  Future<void> bootstrap() async {
    await Future.wait([
      fetchProducts(),
      fetchCustomers(),
      fetchSales(),
      fetchCategories(),
      fetchKpis(),
      fetchSalesOfficers(),
    ]);
    _recomputeCategoryProductTotals();
    _refreshLowStockReminders();
    _refreshPaymentDueReminders();
    notifyListeners();
  }

  /// Appends `officer_id` to a query string when a privileged viewer has
  /// picked one sales officer to filter the dashboard down to.
  String _withOfficerFilter(String qs) => _selectedOfficerId == null
      ? qs
      : '$qs${qs.isEmpty ? '' : '&'}officer_id=$_selectedOfficerId';

  /// Fetches today's KPIs (sales total, profit, cash, credit, expenses)
  /// from the backend and stores them for the dashboard cards.
  Future<void> fetchKpis() async {
    try {
      final path = _selectedOfficerId == null
          ? '/inventory/kpis'
          : '/inventory/kpis?officer_id=$_selectedOfficerId';
      final res = await _api.getOrNull(path);
      if (res == null) return;
      final data = res['data'] as Map<String, dynamic>? ?? {};
      final today = data['today'] as Map<String, dynamic>? ?? {};
      _kpiTodayTotal    = _toDouble(today['total']);
      _kpiTodayProfit   = _toDouble(today['profit']);
      _kpiCashToday     = _toDouble(today['cash']);
      _kpiExpensesToday = _toDouble(today['expenses']);
      _kpiDebtTotal     = _toDouble(data['outstanding_debt']);
      notifyListeners();
    } on Exception {
      // leave previous cached values intact
    }
  }

  /// Fetches daily sales totals for [year]/[month] from the backend and
  /// caches them. The dashboard chart calls this when the user switches months
  /// so it always shows complete data rather than filtering the in-memory list.
  Future<List<double>> fetchMonthlyChart(int year, int month) async {
    final key = '$year-$month${_selectedOfficerId == null ? '' : '-o$_selectedOfficerId'}';
    try {
      final res = await _api.getOrNull(_withOfficerFilter(
          '/inventory/sales/monthly-chart?year=$year&month=$month'));
      if (res == null) return _monthlyChartCache[key] ?? [];
      final data = res['data'] as Map<String, dynamic>? ?? {};
      final days = data['days'] as List<dynamic>? ?? [];
      final totals = days.map((d) {
        final m = d as Map<String, dynamic>;
        return _toDouble(m['total']);
      }).toList();
      _monthlyChartCache[key] = totals;
      notifyListeners();
      return totals;
    } on Exception {
      return _monthlyChartCache[key] ?? [];
    }
  }

  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse('$v') ?? 0;
  }

  // Stock operations (call backend, then refresh)
  Future<bool> stockIn(
    int productId,
    int qty, {
    String? reference,
    String? batchNumber,
    DateTime? expiryDate,
    double? costPrice,
  }) async {
    try {
      await _api.post('/stock-movements', {
        'product_id': productId,
        'type': 'in',
        'quantity': qty,
        if (reference != null) 'reference': reference,
        if (batchNumber != null && batchNumber.isNotEmpty)
          'batch_number': batchNumber,
        if (expiryDate != null)
          'expiry_date': expiryDate.toIso8601String().split('T').first,
        if (costPrice != null) 'cost_price': costPrice,
      });
      await Future.wait<void>(<Future<void>>[
        fetchProducts(),
        fetchBatches(),
      ]);
      _refreshLowStockReminders();
      InvEventBus.instance.emit({InvDomain.stock});
      return true;
    } on Exception {
      return false;
    }
  }

  Future<bool> stockOut(
    int productId,
    int qty, {
    String? reason,
    String? reference,
    int? batchId,
  }) async {
    try {
      await _api.post('/stock-movements', {
        'product_id': productId,
        'type': 'out',
        'quantity': qty,
        if (reason != null) 'reason': reason,
        if (reference != null) 'reference': reference,
        if (batchId != null) 'batch_id': batchId,
      });
      await Future.wait<void>(<Future<void>>[
        fetchProducts(),
        fetchBatches(),
      ]);
      _refreshLowStockReminders();
      InvEventBus.instance.emit({InvDomain.stock});
      return true;
    } on Exception {
      return false;
    }
  }

  // POS: cart operations
  Future<void> fetchProducts(
      {int page = 1, String? q, String? status, bool? lowStock}) async {
    final List<String> endpoints = [
      '/inventory/products',
      '/products',
    ];
    for (final e in endpoints) {
      try {
        final res = await _api.getOrNull(
            '$e?page=$page&with_units=1${q != null ? '&q=$q' : ''}${status != null ? '&status=$status' : ''}${(lowStock ?? false) ? '&low_stock=1' : ''}');
        if (res == null) continue;
        final List<dynamic> list = (res['data'] is List)
            ? List<dynamic>.from(res['data'] as List)
            : (res['products'] is List)
                ? List<dynamic>.from(res['products'] as List)
                : (res is List)
                    ? List<dynamic>.from(res as List)
                    : <dynamic>[];
        _products
          ..clear()
          ..addAll(
              list.map((j) => _fromProductJson(j as Map<String, dynamic>)));
        // The selling units (crate / bottle, kg / g ...) and their prices arrive with the list.
        for (final dynamic j in list) {
          if (j is Map<String, dynamic> && j['units'] is List) {
            final int id = int.tryParse((j['id'] ?? 0).toString()) ?? 0;
            _unitsByProduct[id] = (j['units'] as List)
                .map((u) => InvProductUnit.fromJson(<String, dynamic>{...(u as Map<String, dynamic>), 'product_id': id}))
                .toList();
          }
        }
        notifyListeners();
        return;
      } on Exception {
        // try next endpoint, then fall back to mock below
      }
    }
  }

  Future<bool> createProduct({
    required String name,
    required String sku,
    required double costPrice,
    required double sellingPrice,
    required int quantity,
    required int minStock,
    String? description,
    String? category,
    int? categoryId,
    int? brandId,
    String unit = 'pcs',
    int unitFactor = 1,
    String status = 'active',
    String? barcode,
    String priceTier = 'retail',
    double? taxPercent,
    String measure = 'count',
    double? otherPrice,
    List<Map<String, dynamic>> units = const <Map<String, dynamic>>[],
    List<Map<String, dynamic>> variants = const <Map<String, dynamic>>[],
    bool isService = false,
    int? durationMinutes,
    int? rebookAfterWeeks,
    double? commissionPercent,
    double? commissionFixed,
    int? packageSessions,
    int? packageServiceId,
    int? packageValidDays,
    List<String>? staffIds,
    List<PriceOption>? priceOptions,
  }) async {
    _lastError = null;
    try {
      await _api.post('/inventory/products', {
        'name': name,
        'description': description,
        'sku': sku,
        if (taxPercent != null) 'tax_percent': taxPercent,
        if (measure != 'count') 'measure': measure,
        // The same unit's price at the other level (retail <-> wholesale).
        if (otherPrice != null) 'other_price': otherPrice,
        if (units.isNotEmpty) 'units': units,
        if (variants.isNotEmpty) 'variants': variants,
        if (isService) 'is_service': true,
        if (durationMinutes != null) 'duration_minutes': durationMinutes,
        if (rebookAfterWeeks != null) 'rebook_after_weeks': rebookAfterWeeks,
        if (commissionPercent != null) 'commission_percent': commissionPercent,
        if (commissionFixed != null) 'commission_fixed': commissionFixed,
        if (isService && packageSessions != null && packageServiceId != null) ...{
          'package_sessions': packageSessions,
          'package_service_id': packageServiceId,
          if (packageValidDays != null) 'package_valid_days': packageValidDays,
        },
        if (staffIds != null && staffIds.isNotEmpty) 'staff_ids': staffIds,
        if (priceOptions != null && priceOptions.isNotEmpty) 'price_options': <Map<String, dynamic>>[for (final PriceOption o in priceOptions) o.toJson()],
        'category': category,
        if (categoryId != null) 'category_id': categoryId,
        if (brandId != null) 'brand_id': brandId,
        'cost_price': costPrice,
        'selling_price': sellingPrice,
        'unit': unit,
        'unit_factor': unitFactor,
        'quantity': quantity,
        'min_stock': minStock,
        'status': status,
        'barcode': barcode,
        'price_tier': priceTier,
      });
      await fetchProducts();
      _refreshLowStockReminders();
      InvEventBus.instance.emit({InvDomain.product});
      return true;
    } on ApiException catch (e) {
      _lastError = e.message;
      return false;
    } on Exception {
      return false;
    }
  }

  /// Add more sizes / colours to an existing product (each its own stock item). Returns true on success.
  Future<bool> addVariants(int productId, List<Map<String, dynamic>> variants) async {
    _lastError = null;
    try {
      await _api.post('/inventory/products/$productId/variants', <String, dynamic>{'variants': variants});
      await fetchProducts();
      InvEventBus.instance.emit({InvDomain.product});
      return true;
    } on ApiException catch (e) {
      _lastError = e.message;
      return false;
    } on Exception {
      return false;
    }
  }

  /// The sizes / colours of one product (including itself), straight from the server.
  Future<List<InvProduct>> fetchFamily(int familyId) async {
    try {
      final Map<String, dynamic>? res = await _api.getOrNull('/inventory/products?family_id=$familyId');
      final List<dynamic> list = (res?['data'] is List) ? res!['data'] as List<dynamic> : <dynamic>[];
      return list.map((j) => _fromProductJson(j as Map<String, dynamic>)).toList();
    } on Exception {
      return const <InvProduct>[];
    }
  }

  /// Read what the business's inventory is set up to do (kind of business, crates, price level, VAT).
  Future<void> fetchCapabilities() async {
    try {
      final Map<String, dynamic>? res = await _api.getOrNull('/inventory/settings');
      final dynamic data = res?['data'];
      if (data is! Map) return;
      final InvCapabilities next = InvCapabilities.fromSettings(
        data.map((k, v) => MapEntry(k.toString(), (v ?? '').toString())),
      );
      if (next != _capabilities) {
        _capabilities = next;
        notifyListeners();
      }
    } on Exception {
      // keep what we had
    }
  }

  Future<bool> updateProduct({
    required int id,
    required String name,
    required double costPrice,
    required double sellingPrice,
    required int quantity,
    required int minStock,
    String? description,
    String? category,
    int? categoryId,
    int? brandId,
    String? unit,
    int? unitFactor,
    String status = 'active',
    String? barcode,
    String priceTier = 'retail',
    double? taxPercent,
    bool clearTax = false,
    String? variantLabel,
    bool? isService,
    int? durationMinutes,
    int? rebookAfterWeeks,
    double? commissionPercent,
    double? commissionFixed,
    int? packageSessions,
    int? packageServiceId,
    int? packageValidDays,
    List<String>? staffIds,
    List<PriceOption>? priceOptions,
  }) async {
    _lastError = null;
    try {
      await _api.put('/inventory/products/$id', {
        'name': name,
        'description': description,
        'category': category,
        // The VAT rate: a number sets it, "clear" puts it back to the business's default, nothing leaves it.
        if (taxPercent != null) 'tax_percent': taxPercent,
        if (clearTax) 'tax_percent': null,
        if (variantLabel != null) 'variant_label': variantLabel,
        // A service says how long it takes and when to bring the client back; nothing there clears it.
        if (isService != null) 'is_service': isService,
        if (isService == true) 'duration_minutes': durationMinutes,
        if (isService == true) 'rebook_after_weeks': rebookAfterWeeks,
        if (isService == true) 'commission_percent': commissionPercent,
        if (isService == true) 'commission_fixed': commissionFixed,
        // Nothing here turns a package back into an ordinary service.
        if (isService == true) 'package_sessions': packageSessions,
        if (isService == true) 'package_service_id': packageServiceId,
        if (isService == true) 'package_valid_days': packageValidDays,
        // An empty list clears it on the server (anyone may do it again; one price).
        if (isService == true && staffIds != null) 'staff_ids': staffIds,
        if (isService == true && priceOptions != null) 'price_options': <Map<String, dynamic>>[for (final PriceOption o in priceOptions) o.toJson()],
        if (categoryId != null) 'category_id': categoryId,
        if (brandId != null) 'brand_id': brandId,
        'cost_price': costPrice,
        'selling_price': sellingPrice,
        if (unit != null) 'unit': unit,
        if (unitFactor != null) 'unit_factor': unitFactor,
        'quantity': quantity,
        'min_stock': minStock,
        'status': status,
        'barcode': barcode,
        'price_tier': priceTier,
      });
      await fetchProducts();
      _refreshLowStockReminders();
      InvEventBus.instance.emit({InvDomain.product});
      return true;
    } on ApiException catch (e) {
      _lastError = e.message;
      return false;
    } on Exception {
      return false;
    }
  }

  /// Returns null on success, or an error message string on failure.
  Future<String?> deleteProduct(int id, {bool force = false}) async {
    try {
      final url = '/inventory/products/$id${force ? '?force=1' : ''}';
      await _api.delete(url);
      _products.removeWhere((InvProduct p) => p.id == id);
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } on Exception catch (e) {
      return readableErrorMessage(e);
    }
  }

  /// Removes a customer. Returns null on success, or the server's reason when it
  /// refuses (open debt, or crates still held) so the screen can show it.
  Future<String?> deleteCustomer(int id) async {
    try {
      await _api.delete('/inventory/customers/$id');
      _customers.removeWhere((InvCustomer c) => c.id == id);
      if (_selectedCustomerId == id) {
        _selectedCustomerId = null;
      }
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } on Exception catch (e) {
      return readableErrorMessage(e);
    }
  }

  Future<void> fetchCustomers({String? q}) async {
    final List<String> endpoints = [
      '/inventory/customers',
      '/customers',
    ];
    for (final e in endpoints) {
      try {
        final res = await _api.getOrNull('$e${q != null ? '?q=$q' : ''}');
        if (res == null) continue;
        final List<dynamic> list = (res['data'] is List)
            ? List<dynamic>.from(res['data'] as List)
            : (res['customers'] is List)
                ? List<dynamic>.from(res['customers'] as List)
                : (res is List)
                    ? List<dynamic>.from(res as List)
                    : <dynamic>[];
        _customers
          ..clear()
          ..addAll(
              list.map((j) => _fromCustomerJson(j as Map<String, dynamic>)));
        notifyListeners();
        return;
      } on Exception {
        // try next endpoint, then fall back to mock below
      }
    }
  }

  Future<void> fetchSales(
      {String? status, DateTime? from, DateTime? to, String? q}) async {
    _salesPage = 1;
    final params = <String, String>{
      if (status != null && status != 'all') 'status': status,
      if (from != null) 'from': from.toIso8601String().split('T').first,
      if (to != null) 'to': to.toIso8601String().split('T').first,
      if (q != null && q.isNotEmpty) 'q': q,
      if (_selectedOfficerId != null) 'officer_id': '$_selectedOfficerId',
      'page': '1',
    };
    final qs = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    for (final e in ['/inventory/sales', '/sales']) {
      try {
        final res = await _api.getOrNull('$e?$qs');
        if (res == null) continue;
        final List<dynamic> list = (res['data'] is List)
            ? List<dynamic>.from(res['data'] as List)
            : (res['sales'] is List)
                ? List<dynamic>.from(res['sales'] as List)
                : (res is List)
                    ? List<dynamic>.from(res as List)
                    : <dynamic>[];
        _sales
          ..clear()
          ..addAll(list.map((j) => _fromSaleJson(j as Map<String, dynamic>)));
        final meta = res['meta'] as Map<String, dynamic>?;
        _salesHasMore = meta != null &&
            (meta['current_page'] as int? ?? 1) < (meta['last_page'] as int? ?? 1);
        notifyListeners();
        return;
      } on Exception {
        // try next endpoint, then fall back to mock below
      }
    }
  }

  Future<void> loadMoreSales(
      {String? status, DateTime? from, DateTime? to, String? q}) async {
    if (!_salesHasMore) return;
    _salesPage++;
    final params = <String, String>{
      if (status != null && status != 'all') 'status': status,
      if (from != null) 'from': from.toIso8601String().split('T').first,
      if (to != null) 'to': to.toIso8601String().split('T').first,
      if (q != null && q.isNotEmpty) 'q': q,
      if (_selectedOfficerId != null) 'officer_id': '$_selectedOfficerId',
      'page': '$_salesPage',
    };
    final qs = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    try {
      final res = await _api.getOrNull('/inventory/sales?$qs');
      if (res == null) return;
      final List<dynamic> list = (res['data'] is List)
          ? List<dynamic>.from(res['data'] as List)
          : <dynamic>[];
      _sales.addAll(list.map((j) => _fromSaleJson(j as Map<String, dynamic>)));
      final meta = res['meta'] as Map<String, dynamic>?;
      _salesHasMore = meta != null &&
          (meta['current_page'] as int? ?? 1) < (meta['last_page'] as int? ?? 1);
      notifyListeners();
    } on Exception {
      _salesPage--;
    }
  }

  Future<void> fetchSalesSummary(
      {String? status, DateTime? from, DateTime? to, String? q}) async {
    final params = <String, String>{
      if (status != null && status != 'all') 'status': status,
      if (from != null) 'from': from.toIso8601String().split('T').first,
      if (to != null) 'to': to.toIso8601String().split('T').first,
      if (q != null && q.isNotEmpty) 'q': q,
      if (_selectedOfficerId != null) 'officer_id': '$_selectedOfficerId',
    };
    final qs = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    try {
      final res = await _api.getOrNull('/inventory/sales/summary?$qs');
      if (res != null && res['data'] is Map) {
        _salesSummary = Map<String, dynamic>.from(res['data'] as Map);
        notifyListeners();
      }
    } on Exception {
      // leave cached summary
    }
  }

  Future<(bool, String)> cancelSale(int id, String reason) async {
    try {
      await _api.post('/inventory/sales/$id/cancel', {'reason': reason});
      await fetchSales();
      return (true, 'cancelled');
    } on Exception catch (_) {
      return (false, 'cancel_failed');
    }
  }

  Future<(bool, String)> recordSalePayment(
      int id, double amount, String method, {String? reference}) async {
    try {
      await _api.post('/inventory/sales/$id/payments', {
        'amount': amount,
        'method': method,
        if (reference != null && reference.trim().isNotEmpty) 'reference': reference.trim(),
      });
      await fetchSales();
      InvEventBus.instance.emit({InvDomain.credit});
      return (true, 'payment_recorded');
    } on Exception catch (_) {
      return (false, 'payment_failed');
    }
  }

  Future<int?> createCustomer({
    required String name,
    required String phone,
    String? address,
  }) async {
    try {
      final res = await _api.post('/inventory/customers', {
        'name': name,
        'phone': phone,
        if (address != null && address.isNotEmpty) 'address': address,
      });
      await fetchCustomers();
      final int? id = (res['data'] is Map<String, dynamic>)
          ? (res['data'] as Map<String, dynamic>)['id'] as int?
          : null;
      return id;
    } on Exception {
      return null;
    }
  }

  Future<void> fetchReminders({String? type, String? status}) async {
    final params = <String, String>{
      if (type != null) 'type': type,
      if (status != null) 'status': status,
    };
    final qs = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    try {
      final res = await _api.getOrNull(
          qs.isNotEmpty ? '/inventory/reminders?$qs' : '/inventory/reminders');
      if (res == null) return;
      final List<dynamic> list = (res['data'] is List)
          ? List<dynamic>.from(res['data'] as List)
          : (res is List)
              ? List<dynamic>.from(res as List)
              : <dynamic>[];
      _reminders
        ..clear()
        ..addAll(list.map((j) => _fromReminderJson(j as Map<String, dynamic>)));
      notifyListeners();
    } on Exception {
      // silently keep existing reminders
    }
  }

  /// The selling units of a product that can be sold now (the base unit is always among them).
  List<InvProductUnit> activeUnitsOf(int productId) =>
      unitsOf(productId).where((InvProductUnit u) => u.isActive).toList(growable: false);

  /// Does this product have more than one way to be sold (a crate AND a bottle, a kg AND a gram)?
  bool hasChoiceOfUnits(int productId) => activeUnitsOf(productId).length > 1;

  /// The unit a product is rung up in when the cashier has not chosen: its own base unit -- except goods
  /// by weight or volume, which start on the biggest unit (a kilogram, a litre).
  InvProductUnit? defaultUnitFor(InvProduct product) {
    if (!product.isWeighed) return null;
    final List<InvProductUnit> units = activeUnitsOf(product.id)..sort((a, b) => b.factor.compareTo(a.factor));
    return units.isEmpty || units.first.isBase ? null : units.first;
  }

  /// The price of ONE [unit] of [product] for a price level: a customer's special price, else the level's
  /// price, else the other level's, else -- for a unit with no price yet -- the base price times what the unit
  /// holds. A depot (which prices by product) just uses the product's own price for its own unit.
  double unitPriceFor(InvProduct product, InvProductUnit? unit, {String? tier, int? customerId}) {
    final bool base = unit == null || unit.isBase;
    final String level = tier ?? cartTier;

    if (!_capabilities.usesPriceLevels && base) return product.sellingPrice;

    double? fromRows(InvProductUnit u) {
      final InvPriceTier t = level == 'wholesale' ? InvPriceTier.wholesale : InvPriceTier.retail;
      final InvPriceTier other = t == InvPriceTier.wholesale ? InvPriceTier.retail : InvPriceTier.wholesale;
      return (customerId != null ? u.priceFor(InvPriceTier.special, customerId: customerId) : null) ??
          u.priceFor(t) ??
          u.priceFor(other);
    }

    if (unit != null) {
      final double? own = fromRows(unit);
      if (own != null) return own;
    }
    return product.sellingPrice * (unit == null || unit.isBase ? 1 : unit.factor);
  }

  /// The VAT rate a product is sold at: its own, else the business's default.
  double taxRateFor(InvProduct product) => product.taxPercent ?? _capabilities.defaultTaxPercent;

  /// The VAT on one line (prices include VAT: the share inside the price; otherwise: added on top).
  double _lineTax(InvSaleItem it) {
    final double rate = it.taxPercent ?? 0;
    if (rate <= 0) return 0;
    final double base = it.total;
    final double tax = _capabilities.pricesIncludeVat ? base * rate / (100 + rate) : base * rate / 100;
    return (tax * 100).roundToDouble() / 100;
  }

  void _retax(InvSaleItem it) => it.taxAmount = _lineTax(it);

  InvProduct? _productOf(int id) => _products.where((InvProduct p) => p.id == id).firstOrNull;

  /// Add one of a product to the cart, in [unit] (null = the product's own base unit). The same product in
  /// another unit is its own line: 1 crate and 3 bottles are two lines.
  void addProductToCart(InvProduct product, {InvProductUnit? unit, PriceOption? option}) {
    final InvProductUnit? chosen = unit ?? defaultUnitFor(product);
    final InvProductUnit? u = (chosen != null && !chosen.isBase) ? chosen : null;
    final String key = '${product.id}:${u?.id ?? 0}${option == null ? '' : ':${option.label}'}';

    final idx = _cart.indexWhere((it) => it.key == key);
    if (idx >= 0) {
      _cart[idx].qty += 1;
      _retax(_cart[idx]);
    } else {
      final InvSaleItem line = InvSaleItem(
        productId: product.id,
        name: option == null ? product.name : '${product.name} (${option.label})',
        optionLabel: option?.label,
        qty: 1,
        unitPrice: option?.price ?? unitPriceFor(product, u, customerId: _selectedCustomerId),
        unitCostSnapshot: product.isService ? 0 : product.costPrice,
        unitId: u?.id,
        unitName: u?.name,
        unitFactor: u?.factor ?? 1,
        taxPercent: taxRateFor(product),
        isService: product.isService,
        // The stylist chosen for the line before this one is offered again (and is shown on the line, so it can
        // be changed): a client is usually served by one person.
        staffId: product.isService ? _defaultStaffId : null,
        staffName: product.isService ? _defaultStaffName : null,
      );
      _retax(line);
      _cart.add(line);
    }
    notifyListeners();
  }

  /// Sell this line in another unit (a kg instead of a g, a bottle instead of a crate). Merges into the
  /// line that already has that unit, and re-prices it for the unit.
  void changeCartUnit(InvSaleItem item, InvProductUnit? unit) {
    final InvProduct? product = _productOf(item.productId);
    if (product == null) return;
    final InvProductUnit? u = (unit != null && !unit.isBase) ? unit : null;
    final String key = '${item.productId}:${u?.id ?? 0}';
    if (key == item.key) return;

    final int clash = _cart.indexWhere((it) => it.key == key);
    if (clash >= 0) {
      _cart[clash].qty += item.qty;
      _retax(_cart[clash]);
      _cart.remove(item);
    } else {
      item.unitId = u?.id;
      item.unitName = u?.name;
      item.unitFactor = u?.factor ?? 1;
      item.unitPrice = unitPriceFor(product, u, customerId: _selectedCustomerId);
      // Another unit is another price: a price written for the old unit does not carry over.
      item.priceWritten = false;
      _retax(item);
    }
    notifyListeners();
  }

  // ---- Salon ----
  /// True while the salon's own home is open (a salon runs on this same engine). Screens that are opened on top of
  /// the home (the product form) read it to offer what a salon needs: services, and who served the client.
  bool _salonMode = false;
  bool get salonMode => _salonMode;
  void setSalonMode(bool value) {
    // Every request now says which service's books it is about (the server keeps them apart).
    ApiService.activeService = value ? 'salon' : null;
    // A branch of the shop is not a branch of the salon: forget the choice whenever the books change.
    if (!value || _salonMode != value) ApiService.clearBranch();
    if (_salonMode == value) return;
    _salonMode = value;
    notifyListeners();
  }

  // ---- Salon: who serves the client ----
  List<Map<String, String>> _salonStaff = <Map<String, String>>[];
  String? _defaultStaffId;
  String? _defaultStaffName;

  /// The people of this salon who can serve a client: {id, name, role}.
  List<Map<String, String>> get salonStaff => List.unmodifiable(_salonStaff);

  Future<void> fetchSalonStaff() async {
    try {
      final Map<String, dynamic>? res = await _api.getOrNull('/inventory/salon/staff');
      final dynamic data = res?['data'];
      if (data is! List) return;
      _salonStaff = <Map<String, String>>[
        for (final dynamic row in data)
          if (row is Map) <String, String>{'id': '${row['id']}', 'name': '${row['name'] ?? ''}', 'role': '${row['role'] ?? ''}'},
      ];
      notifyListeners();
    } on Exception {
      // keep what we had
    }
  }

  /// Say who serves this line (null = nobody named). That person is offered for the next service added.
  void setCartStaff(InvSaleItem item, String? staffId, String? staffName) {
    item.staffId = staffId;
    item.staffName = staffName;
    _defaultStaffId = staffId;
    _defaultStaffName = staffName;
    notifyListeners();
  }

  void setCartQty(InvSaleItem item, int qty) {
    item.qty = qty < 1 ? 1 : qty;
    _retax(item);
    notifyListeners();
  }

  /// Write the price of one unit of this line (business prices are not always fixed). It is kept when the price level or the
  /// customer changes; [useListPrice] takes the catalogue price back.
  void setCartUnitPrice(InvSaleItem item, double price) {
    item.unitPrice = price < 0 ? 0 : price;
    item.priceWritten = true;
    _retax(item);
    notifyListeners();
  }

  /// What the catalogue says one unit of this line costs now (for the price level and customer chosen), or null if the product is gone.
  double? listPriceOf(InvSaleItem item) {
    final InvProduct? p = _productOf(item.productId);
    if (p == null) return null;
    final InvProductUnit? u = item.unitId == null ? null : unitsOf(item.productId).where((x) => x.id == item.unitId).firstOrNull;

    return unitPriceFor(p, u, customerId: _selectedCustomerId);
  }

  /// Take the catalogue price back for a line whose price was written.
  void useListPrice(InvSaleItem item) {
    final double? list = listPriceOf(item);
    if (list == null) return;
    item.unitPrice = list;
    item.priceWritten = false;
    _retax(item);
    notifyListeners();
  }

  void removeFromCart(InvSaleItem item) {
    _cart.remove(item);
    notifyListeners();
  }

  /// Switch the whole cart between retail and wholesale prices. Every line is priced again from the catalogue,
  /// except a line whose price the cashier wrote: that one keeps it.
  void setCartTier(String tier) {
    _tierOverride = tier == 'wholesale' ? 'wholesale' : 'retail';
    for (final InvSaleItem it in _cart) {
      if (it.priceWritten) continue;
      final InvProduct? p = _productOf(it.productId);
      if (p == null) continue;
      final InvProductUnit? u = it.unitId == null ? null : unitsOf(it.productId).where((x) => x.id == it.unitId).firstOrNull;
      it.unitPrice = unitPriceFor(p, u, customerId: _selectedCustomerId);
      _retax(it);
    }
    notifyListeners();
  }

  void clearCart() {
    _cart.clear();
    _defaultStaffId = null;
    _defaultStaffName = null;
    _tierOverride = null;
    _salonDiscount = 0;
    _discountReason = '';
    _paymentReference = '';
    _partialReference = '';
    _clearPerks();
    notifyListeners();
  }

  void setPaymentMode(String mode) {
    _paymentMode = mode; // cash | debt | partial
    notifyListeners();
  }

  void setCustomer(int? customerId) {
    // Points and packages belong to one client.
    if (customerId != _selectedCustomerId) _clearPerks(keepVoucher: true);
    _selectedCustomerId = customerId;
    _selectedCustomerPhone = customerId == null
        ? ''
        : (_customers.where((c) => c.id == customerId).firstOrNull?.phone ?? '');
    notifyListeners();
  }

  void setManualPhone(String phone) {
    _manualPhone = phone;
    notifyListeners();
  }

  void setManualName(String name) {
    _manualName = name;
    notifyListeners();
  }

  void setPartialPaymentMethod(String method) {
    _partialPaymentMethod = method;
    notifyListeners();
  }

  void setPaidAmount(double amount) {
    _paidAmount = amount < 0 ? 0 : amount;
    notifyListeners();
  }

  // Checkout with business rules
  // Returns (success, message)
  Future<(bool, String)> checkout({
    required int createdBy,
    int? crateTypeId,
    int? crateQty,
    String? crateDirection, // 'issued' or 'returned'
  }) async {
    if (_cart.isEmpty) return (false, LocalizationService.instance.translate('cart_is_empty'));

    if ((_paymentMode == 'debt' || _paymentMode == 'partial') &&
        _selectedCustomerId == null) {
      return (false, 'customer_required');
    }

    // Money that did not come as cash is traced by its reference number: the owner reads them in Money > References.
    if (missingReference) return (false, 'reference_required');

    final subtotal = cartSubtotal;
    final total = cartTotal;
    double paidTotal = 0;
    String status = 'paid';
    List<Map<String, dynamic>> payments = [];

    if (_paymentMode == 'cash') {
      paidTotal = total;
      payments = [
        {
          'amount': total,
          'method': _salonMode ? _cashChannel : 'cash',
          'reference': _salonMode && _cashChannel != 'cash' ? _paymentReference.trim() : null,
          'paid_at': DateTime.now().toIso8601String(),
        }
      ];
      status = 'paid';
    } else if (_paymentMode == 'partial') {
      paidTotal = _paidAmount.clamp(0, total);
      status =
          paidTotal <= 0 ? 'debt' : (paidTotal < total ? 'partial' : 'paid');
      if (paidTotal > 0) {
        payments = [
          {
            'amount': paidTotal,
            'method': _partialPaymentMethod,
            'reference': _partialPaymentMethod == 'cash' ? null : _partialReference.trim(),
            'paid_at': DateTime.now().toIso8601String(),
          }
        ];
      }
    } else if (_paymentMode == 'debt') {
      status = 'debt';
      paidTotal = 0;
    }

    final payload = {
      'customer_id': _selectedCustomerId,
      // Walk-in overrides: only sent when no linked customer
      if (_selectedCustomerId == null && _manualName.trim().isNotEmpty)
        'customer_name_override': _manualName.trim(),
      'customer_phone': _selectedCustomerId != null
          ? (_selectedCustomerPhone.isNotEmpty ? _selectedCustomerPhone : null)
          : (_manualPhone.trim().isNotEmpty ? _manualPhone.trim() : null),
      'payment_status': status,
      'subtotal': subtotal,
      'discount': totalDiscount,
      if (totalDiscount > 0)
        'discount_reason': _discountReason.trim().isNotEmpty
            ? _discountReason.trim()
            : <String>[if (_voucherCode.isNotEmpty) 'Voucher $_voucherCode', if (pointsOff > 0) 'Loyalty points'].join(' + '),
      if (_voucherCode.isNotEmpty) 'voucher_code': _voucherCode,
      if (_pointsUsed > 0) 'redeem_points': _pointsUsed,
      'tax': cartTax,
      'total': total,
      'paid_total': paidTotal,
      'due_date': status == 'paid'
          ? null
          : DateTime.now().add(const Duration(days: 7)).toIso8601String(),
      'items': _cart
          .map((e) => {
                'product_id': e.productId,
                'quantity': e.qty,
                if (e.unitId != null) 'unit_id': e.unitId,
                'unit_price': e.unitPrice,
                'unit_cost_snapshot': e.unitCostSnapshot,
                if (e.taxPercent != null) 'tax_percent': e.taxPercent,
                if (e.staffId != null) 'staff_id': e.staffId,
                if (e.isService && e.usedGoods != null)
                  'materials': <Map<String, dynamic>>[
                    for (final InvUsedGood g in e.usedGoods!)
                      if (g.qty > 0) <String, dynamic>{'product_id': g.productId, 'quantity': g.qty},
                  ],
                if (e.packageId != null) 'package_id': e.packageId,
              })
          .toList(),
      if (payments.isNotEmpty) 'payments': payments,
      if (crateTypeId != null && crateQty != null && crateDirection != null) ...{
        'crate_type_id': crateTypeId,
        'crate_qty': crateQty,
        'crate_direction': crateDirection,
      },
    };

    try {
      // 15s is enough â€” fail fast rather than hanging the UI.
      await _api.post('/inventory/sales', payload);

      // Clear cart immediately so the UI feels instant.
      _cart.clear();
      _defaultStaffId = null;
      _defaultStaffName = null;
      _paymentMode = 'cash';
      _selectedCustomerId = null;
      _selectedCustomerPhone = '';
      _manualPhone = '';
      _manualName = '';
      _paidAmount = 0;
      _partialPaymentMethod = 'cash';
      _cashChannel = 'cash';
      _paymentReference = '';
      _partialReference = '';
      _salonDiscount = 0;
      _discountReason = '';
      _voucherCode = '';
      _voucherOff = 0;
      _pointsUsed = 0;
      notifyListeners();

      // Emit events — the bus listener re-fetches sales, products,
      // KPIs, and reminders in the background.
      InvEventBus.instance.emit({InvDomain.sale, InvDomain.product});

      return (true, 'success');
    } on ApiException catch (e) {
      // The server refused the sale (e.g. not enough stock): show its own words, so the seller knows what
      // to fix. The cart is kept as it is.
      return (false, e.message.trim().isEmpty ? 'checkout_failed' : e.message);
    } on Exception catch (_) {
      // Never fall back to mock on checkout â€” a fake-success loses real sales.
      return (false, 'checkout_failed');
    }
  }

  void _refreshLowStockReminders() {
    // Remove existing low_stock reminders and regenerate
    _reminders.removeWhere((r) => r.type == 'low_stock');
    int id = _reminders.length + 1;
    for (final p in _products.where((p) => p.quantity < p.minStock)) {
      _reminders.add(InvReminder(
        id: id++,
        type: 'low_stock',
        title: LocalizationService.instance.translate('low_stock'),
        description: LocalizationService.instance.translateWith('is_below_minimum_stock', <Object?>[p.name]),
        dueAt: DateTime.now(),
        relatedId: p.id,
      ));
    }
  }

  void _refreshPaymentDueReminders() {
    _reminders.removeWhere((r) => r.type == 'payment_due');
    int id =
        _reminders.isEmpty ? 1 : (_reminders.map((e) => e.id).reduce(max) + 1);
    for (final s in _sales.where((s) => s.paymentStatus != 'paid')) {
      _reminders.add(InvReminder(
        id: id++,
        type: 'payment_due',
        title: LocalizationService.instance.translate('payment_due'),
        description: LocalizationService.instance.translateWith('sale_has_outstanding_balance', <Object?>[s.number]),
        dueAt: s.dueDate ?? DateTime.now().add(const Duration(days: 3)),
        relatedId: s.id,
      ));
    }
  }

  Future<void> markReminderDone(int reminderId) async {
    try {
      await _api.put('/inventory/reminders/$reminderId/done', {});
      await fetchReminders();
    } on Exception {
      // fallback local change (no null gymnastics)
      final int idx = _reminders.indexWhere((e) => e.id == reminderId);
      if (idx != -1) {
        _reminders[idx].status = InvReminderStatus.done;
        notifyListeners();
      }
    }
  }

  Future<void> snoozeReminder(int reminderId, {int minutes = 60}) async {
    try {
      await _api
          .put('/inventory/reminders/$reminderId/snooze', {'minutes': minutes});
      await fetchReminders();
    } on Exception {
      final int idx = _reminders.indexWhere((e) => e.id == reminderId);
      if (idx != -1) {
        _reminders[idx].status = InvReminderStatus.snoozed;
        _reminders[idx].snoozeUntil =
            DateTime.now().add(Duration(minutes: minutes));
        notifyListeners();
      }
    }
  }

  // Categories API
  Future<void> fetchCategories({String? q, String? status}) async {
    final params = <String, String>{
      if (q != null && q.isNotEmpty) 'q': q,
      if (status != null && status.isNotEmpty && status != 'all')
        'status': status,
    };
    final qs = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    final List<String> endpoints = <String>[
      '/inventory/categories',
      '/categories',
    ];
    for (final e in endpoints) {
      try {
        final res = await _api.getOrNull(qs.isNotEmpty ? '$e?$qs' : e);
        if (res == null) continue;
        final List<dynamic> list = (res['data'] is List)
            ? List<dynamic>.from(res['data'] as List)
            : (res['categories'] is List)
                ? List<dynamic>.from(res['categories'] as List)
                : (res is List)
                    ? List<dynamic>.from(res as List)
                    : <dynamic>[];
        _categories
          ..clear()
          ..addAll(
              list.map((j) => _fromCategoryJson(j as Map<String, dynamic>)));
        _recomputeCategoryProductTotals();
        _ensureCategoryCodes();
        notifyListeners();
        return;
      } on Exception {
        // try next endpoint, then fall back to mock below
      }
    }
  }

  Future<int?> createCategory({
    required String name,
    String code = '',
    String description = '',
    int? parentId,
    String? imagePath,
    String status = 'active',
    int createdBy = 1,
  }) async {
    final String newCode = code.isNotEmpty ? code : _genCategoryCode(name);
    final payload = {
      'name': name,
      'code': newCode,
      if (description.isNotEmpty) 'description': description,
      'parent_id': parentId,
      'status': status,
      if (imagePath != null) 'image': imagePath,
    };
    try {
      final res = await _api.post('/inventory/categories', payload);
      await fetchCategories();
      final int? id = (res['data'] is Map<String, dynamic>)
          ? int.tryParse((res['data'] as Map<String, dynamic>)['id']?.toString() ?? '')
          : null;
      return id;
    } on Exception {
      return null;
    }
  }

  Future<bool> updateCategory({
    required int id,
    String? name,
    String? code,
    String? description,
    int? parentId,
    String? imagePath,
    String? status,
  }) async {
    final payload = <String, dynamic>{
      if (name != null) 'name': name,
      if (code != null) 'code': code,
      if (description != null) 'description': description,
      'parent_id': parentId,
      if (status != null) 'status': status,
      if (imagePath != null) 'image': imagePath,
    };
    try {
      await _api.put('/inventory/categories/$id', payload);
      await fetchCategories();
      return true;
    } on Exception {
      return false;
    }
  }

  Future<bool> deleteCategory(int id) async {
    try {
      await _api.delete('/inventory/categories/$id');
      _categories.removeWhere((c) => c.id == id);
      _recomputeCategoryProductTotals();
      notifyListeners();
      return true;
    } on Exception {
      return false;
    }
  }

  Future<void> toggleCategoryStatus(int id) async {
    final idx = _categories.indexWhere((c) => c.id == id);
    if (idx == -1) return;
    final newStatus =
        _categories[idx].status == 'active' ? 'inactive' : 'active';
    await updateCategory(id: id, status: newStatus);
  }

  void _recomputeCategoryProductTotals() {
    // crude mapping by category name (since product has only name category)
    final Map<String, int> countByName = <String, int>{};
    for (final p in _products) {
      final key = p.category.trim();
      countByName[key] = (countByName[key] ?? 0) + 1;
    }
    for (int i = 0; i < _categories.length; i++) {
      final c = _categories[i];
      final count = countByName[c.name.trim()] ?? 0;
      _categories[i] = c.copyWith(totalProducts: count);
    }
  }

  // Generate category code like ABC001 from name
  String _genCategoryCode(String name) {
    String prefix = name
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w[0])
        .take(3)
        .join()
        .toUpperCase();
    if (prefix.isEmpty) prefix = 'CAT';
    final int seq = (_categories.isEmpty
        ? 1
        : (_categories.map((c) => c.id).fold<int>(0, (p, e) => e > p ? e : p) +
            1));
    final String num = seq.toString().padLeft(3, '0');
    return '$prefix$num';
  }

  // Ensure every category has a code; auto-generate if missing
  void _ensureCategoryCodes() {
    final Set<String> used =
        _categories.map((c) => c.code).where((c) => c.isNotEmpty).toSet();
    for (int i = 0; i < _categories.length; i++) {
      final c = _categories[i];
      if (c.code.isEmpty) {
        final String base = _genCategoryCode(c.name);
        String candidate = base;
        // Appending to `c.name` doesn't change the generated code (the
        // prefix only looks at each word's first letter, and `seq` doesn't
        // depend on the name at all), so retries must vary the candidate
        // itself. The 999-attempt cap is a hard stop against ever looping
        // forever again, even if this generator changes later.
        int k = 1;
        while (used.contains(candidate) && k < 999) {
          candidate = '$base-$k';
          k++;
        }
        used.add(candidate);
        _categories[i] = c.copyWith(code: candidate);
      }
    }
  }

  // ---------------------------------------------------------------------
  // Area 2 - brands, selling units & tiered pricing
  // ---------------------------------------------------------------------

  Future<void> fetchBrands({String? q, String? status}) async {
    final Map<String, String> params = <String, String>{
      if (q != null && q.isNotEmpty) 'q': q,
      if (status != null && status.isNotEmpty && status != 'all')
        'status': status,
    };
    final String qs = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');

    try {
      final Map<String, dynamic>? res = await _api.getOrNull(
        qs.isNotEmpty ? '/inventory/brands?$qs' : '/inventory/brands',
      );
      if (res == null) return;
      final List<dynamic> list =
          (res['data'] is List) ? res['data'] as List<dynamic> : <dynamic>[];
      _brands
        ..clear()
        ..addAll(list.map((j) => InvBrand.fromJson(j as Map<String, dynamic>)));
      notifyListeners();
    } on Exception {
      // leave whatever was loaded before; the UI treats brands as optional
    }
  }

  Future<int?> createBrand({
    required String name,
    String description = '',
    String status = 'active',
  }) async {
    try {
      final Map<String, dynamic> res =
          await _api.post('/inventory/brands', <String, dynamic>{
        'name': name,
        if (description.isNotEmpty) 'description': description,
        'status': status,
      });
      await fetchBrands();
      final dynamic data = res['data'];
      return (data is Map)
          ? int.tryParse(data['id']?.toString() ?? '')
          : null;
    } on Exception {
      return null;
    }
  }

  Future<bool> updateBrand(
    int id, {
    String? name,
    String? description,
    String? status,
  }) async {
    try {
      await _api.put('/inventory/brands/$id', <String, dynamic>{
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        if (status != null) 'status': status,
      });
      await fetchBrands();
      return true;
    } on Exception {
      return false;
    }
  }

  Future<bool> deleteBrand(int id) async {
    try {
      await _api.delete('/inventory/brands/$id');
      _brands.removeWhere((b) => b.id == id);
      notifyListeners();
      return true;
    } on Exception {
      return false;
    }
  }

  Future<List<InvProductUnit>> fetchUnits(int productId) async {
    try {
      final Map<String, dynamic>? res =
          await _api.getOrNull('/inventory/products/$productId/units');
      if (res == null) return unitsOf(productId);
      final List<dynamic> list =
          (res['data'] is List) ? res['data'] as List<dynamic> : <dynamic>[];
      final List<InvProductUnit> units = list
          .map((j) => InvProductUnit.fromJson(j as Map<String, dynamic>))
          .toList();
      _unitsByProduct[productId] = units;
      notifyListeners();
      return units;
    } on Exception {
      return unitsOf(productId);
    }
  }

  Future<bool> createUnit(
    int productId, {
    required String name,
    required int factor,
    String? barcode,
    double? retailPrice,
    double? wholesalePrice,
  }) async {
    try {
      await _api.post('/inventory/products/$productId/units', <String, dynamic>{
        'name': name,
        'factor': factor,
        if (barcode != null && barcode.isNotEmpty) 'barcode': barcode,
        if (retailPrice != null) 'retail_price': retailPrice,
        if (wholesalePrice != null) 'wholesale_price': wholesalePrice,
      });
      await fetchUnits(productId);
      return true;
    } on Exception {
      return false;
    }
  }

  Future<bool> updateUnit(
    int productId,
    int unitId, {
    String? name,
    int? factor,
    String? barcode,
    String? status,
  }) async {
    try {
      await _api.put(
          '/inventory/products/$productId/units/$unitId', <String, dynamic>{
        if (name != null) 'name': name,
        if (factor != null) 'factor': factor,
        if (barcode != null) 'barcode': barcode,
        if (status != null) 'status': status,
      });
      await fetchUnits(productId);
      return true;
    } on Exception {
      return false;
    }
  }

  Future<bool> deleteUnit(int productId, int unitId) async {
    try {
      await _api.delete('/inventory/products/$productId/units/$unitId');
      await fetchUnits(productId);
      return true;
    } on Exception {
      return false;
    }
  }

  /// Set one tier's price. The backend logs the change automatically.
  Future<bool> setUnitPrice(
    int productId,
    int unitId, {
    required InvPriceTier tier,
    required double price,
    int? customerId,
    String? reason,
  }) async {
    try {
      await _api.post(
        '/inventory/products/$productId/units/$unitId/price',
        <String, dynamic>{
          'tier': tier.wire,
          'price': price,
          if (customerId != null) 'customer_id': customerId,
          if (reason != null && reason.isNotEmpty) 'reason': reason,
        },
      );
      await fetchUnits(productId);
      return true;
    } on Exception {
      return false;
    }
  }

  Future<List<InvPriceChange>> fetchPriceHistory(
    int productId,
    int unitId, {
    int limit = 50,
  }) async {
    try {
      final Map<String, dynamic>? res = await _api.getOrNull(
        '/inventory/products/$productId/units/$unitId/price-history?limit=$limit',
      );
      if (res == null) return const <InvPriceChange>[];
      final List<dynamic> list =
          (res['data'] is List) ? res['data'] as List<dynamic> : <dynamic>[];
      return list
          .map((j) => InvPriceChange.fromJson(j as Map<String, dynamic>))
          .toList();
    } on Exception {
      return const <InvPriceChange>[];
    }
  }

  Future<List<InvStockMovement>> fetchStockMovements({int? productId}) async {
    final path = productId != null
        ? '/inventory/stock-movements?product_id=$productId'
        : '/inventory/stock-movements';
    try {
      final Map<String, dynamic>? res = await _api.getOrNull(path);
      if (res != null && res['data'] is List) {
        final List<dynamic> list = res['data'] as List<dynamic>;
        final items = list.map((j) => _fromStockMovementJson(j as Map<String, dynamic>)).toList();
        _stockMovements
          ..clear()
          ..addAll(items);
        notifyListeners();
        return items;
      }
    } on Exception {
      // return empty if failed
    }
    return _stockMovements;
  }

  Future<bool> recordStockIn({
    required int productId,
    required int quantity,
    String? reference,
    String? batchNumber,
    String? expiryDate,
    double? costPrice,
  }) async {
    final payload = <String, dynamic>{
      'product_id': productId,
      'type': 'in',
      'quantity': quantity,
      if (reference != null && reference.isNotEmpty) 'reference': reference,
      if (batchNumber != null && batchNumber.isNotEmpty) 'batch_number': batchNumber,
      if (expiryDate != null && expiryDate.isNotEmpty) 'expiry_date': expiryDate,
      if (costPrice != null) 'cost_price': costPrice,
    };

    try {
      final res = await _api.post('/inventory/stock-movements', payload);
      await fetchProducts();
      await fetchStockMovements(productId: productId);
      return res != null;
    } on Exception {
      return false;
    }
  }

  // ---------------------------------------------------------------------
  // Area 3 - batches, expiry, stock counts & write-offs
  // ---------------------------------------------------------------------

  Future<void> fetchBatches({
    int? productId,
    bool inStockOnly = true,
    int? expiringInDays,
    bool expiredOnly = false,
    String? q,
  }) async {
    final Map<String, String> params = <String, String>{
      if (productId != null) 'product_id': '$productId',
      if (inStockOnly) 'in_stock': '1',
      if (expiringInDays != null) 'expiring_in_days': '$expiringInDays',
      if (expiredOnly) 'expired': '1',
      if (q != null && q.isNotEmpty) 'q': q,
      'per_page': '100',
    };
    final String qs = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');

    try {
      final Map<String, dynamic>? res =
          await _api.getOrNull('/inventory/batches?$qs');
      if (res == null) return;
      final List<dynamic> list =
          (res['data'] is List) ? res['data'] as List<dynamic> : <dynamic>[];
      _batches
        ..clear()
        ..addAll(list.map((j) => InvBatch.fromJson(j as Map<String, dynamic>)));
      notifyListeners();
    } on Exception {
      // keep the last good list
    }
  }

  /// Receive stock into a batch. Creates the batch when the number is new.
  Future<bool> receiveBatch({
    required int productId,
    required int quantity,
    String? batchNumber,
    DateTime? expiryDate,
    double? costPrice,
    String? reference,
  }) async {
    try {
      await _api.post('/inventory/batches', <String, dynamic>{
        'product_id': productId,
        if (batchNumber != null && batchNumber.isNotEmpty)
          'batch_number': batchNumber,
        'quantity': quantity,
        if (expiryDate != null)
          'expiry_date': expiryDate.toIso8601String().split('T').first,
        if (costPrice != null) 'cost_price': costPrice,
        if (reference != null && reference.isNotEmpty) 'reference': reference,
      });
      await Future.wait<void>(<Future<void>>[
        fetchBatches(),
        fetchProducts(),
        fetchExpirySummary(),
      ]);
      _refreshLowStockReminders();
      return true;
    } on Exception {
      return false;
    }
  }

  Future<bool> updateBatch(
    int batchId, {
    DateTime? expiryDate,
    String? status,
  }) async {
    try {
      await _api.put('/inventory/batches/$batchId', <String, dynamic>{
        if (expiryDate != null)
          'expiry_date': expiryDate.toIso8601String().split('T').first,
        if (status != null) 'status': status,
      });
      await fetchBatches();
      return true;
    } on Exception {
      return false;
    }
  }

  Future<void> fetchExpirySummary({int days = 30}) async {
    try {
      final Map<String, dynamic>? res =
          await _api.getOrNull('/inventory/expiry-summary?days=$days');
      final dynamic data = res?['data'];
      if (data is! Map) return;
      _expiredCount = data['expired'] is num
          ? (data['expired'] as num).toInt()
          : int.tryParse('${data['expired']}') ?? 0;
      _expiringSoonCount = data['expiring_soon'] is num
          ? (data['expiring_soon'] as num).toInt()
          : int.tryParse('${data['expiring_soon']}') ?? 0;
      notifyListeners();
    } on Exception {
      // leave the previous counts
    }
  }

  Future<void> fetchWriteOffs({String? status}) async {
    try {
      final Map<String, dynamic>? res = await _api.getOrNull(
        status == null || status.isEmpty || status == 'all'
            ? '/inventory/write-offs'
            : '/inventory/write-offs?status=$status',
      );
      if (res == null) return;
      final List<dynamic> list =
          (res['data'] is List) ? res['data'] as List<dynamic> : <dynamic>[];
      _writeOffs
        ..clear()
        ..addAll(
            list.map((j) => InvWriteOff.fromJson(j as Map<String, dynamic>)));
      notifyListeners();
    } on Exception {
      // keep the last good list
    }
  }

  Future<bool> createWriteOff({
    required int productId,
    required String reason,
    required int quantity,
    int? batchId,
    String? note,
  }) async {
    try {
      await _api.post('/inventory/write-offs', <String, dynamic>{
        'product_id': productId,
        'reason': reason,
        'quantity': quantity,
        if (batchId != null) 'batch_id': batchId,
        if (note != null && note.isNotEmpty) 'note': note,
      });
      await fetchWriteOffs();
      return true;
    } on Exception {
      return false;
    }
  }

  /// Approve or reject. Approving is what actually removes the stock.
  Future<bool> decideWriteOff(
    int id, {
    required bool approve,
    String? note,
  }) async {
    try {
      await _api.post('/inventory/write-offs/$id/decide', <String, dynamic>{
        'decision': approve ? 'approved' : 'rejected',
        if (note != null && note.isNotEmpty) 'decision_note': note,
      });
      await fetchWriteOffs();
      if (approve) {
        await Future.wait<void>(<Future<void>>[
          fetchProducts(),
          fetchBatches(),
        ]);
        _refreshLowStockReminders();
        InvEventBus.instance.emit({InvDomain.stock});
      }
      return true;
    } on Exception {
      return false;
    }
  }

  Future<void> fetchStockCounts({String? status}) async {
    try {
      final Map<String, dynamic>? res = await _api.getOrNull(
        status == null || status.isEmpty || status == 'all'
            ? '/inventory/stock-counts'
            : '/inventory/stock-counts?status=$status',
      );
      if (res == null) return;
      final List<dynamic> list =
          (res['data'] is List) ? res['data'] as List<dynamic> : <dynamic>[];
      _stockCounts
        ..clear()
        ..addAll(
            list.map((j) => InvStockCount.fromJson(j as Map<String, dynamic>)));
      notifyListeners();
    } on Exception {
      // keep the last good list
    }
  }

  Future<InvStockCount?> fetchStockCount(int id) async {
    try {
      final Map<String, dynamic>? res =
          await _api.getOrNull('/inventory/stock-counts/$id');
      final dynamic data = res?['data'];
      if (data is! Map) return null;
      return InvStockCount.fromJson(Map<String, dynamic>.from(data));
    } on Exception {
      return null;
    }
  }

  Future<int?> openStockCount({String? note}) async {
    try {
      final Map<String, dynamic> res =
          await _api.post('/inventory/stock-counts', <String, dynamic>{
        if (note != null && note.isNotEmpty) 'note': note,
      });
      await fetchStockCounts();
      final dynamic data = res['data'];
      return (data is Map && data['id'] is num)
          ? (data['id'] as num).toInt()
          : null;
    } on Exception {
      return null;
    }
  }

  String? _lastStockCountError;
  String? get lastStockCountError => _lastStockCountError;

  Future<bool> saveStockCountLine(
    int countId, {
    required int productId,
    required int countedQuantity,
    int? batchId,
    String? note,
  }) async {
    _lastStockCountError = null;
    try {
      await _api.post(
        '/inventory/stock-counts/$countId/lines',
        <String, dynamic>{
          'product_id': productId,
          'counted_quantity': countedQuantity,
          if (batchId != null) 'batch_id': batchId,
          if (note != null && note.isNotEmpty) 'note': note,
        },
      );
      return true;
    } on ApiException catch (e) {
      _lastStockCountError = e.message;
      return false;
    } on Exception {
      return false;
    }
  }

  Future<bool> deleteStockCountLine(int countId, int lineId) async {
    try {
      await _api.delete('/inventory/stock-counts/$countId/lines/$lineId');
      return true;
    } on Exception {
      return false;
    }
  }

  /// Apply every variance to stock and freeze the count.
  Future<bool> postStockCount(int countId) async {
    _lastStockCountError = null;
    try {
      await _api.post(
          '/inventory/stock-counts/$countId/post', const <String, dynamic>{});
      await Future.wait<void>(<Future<void>>[
        fetchStockCounts(),
        fetchProducts(),
        fetchBatches(),
      ]);
      _refreshLowStockReminders();
      InvEventBus.instance.emit({InvDomain.stock});
      return true;
    } on ApiException catch (e) {
      _lastStockCountError = e.message;
      return false;
    } on Exception {
      return false;
    }
  }

  Future<bool> cancelStockCount(int countId) async {
    try {
      await _api.post(
          '/inventory/stock-counts/$countId/cancel', const <String, dynamic>{});
      await fetchStockCounts();
      return true;
    } on Exception {
      return false;
    }
  }
}

// JSON mappers (minimal, defensive)
InvProduct _fromProductJson(Map<String, dynamic> j) => InvProduct(
      id: int.tryParse((j['id'] ?? j['product_id'] ?? 0).toString()) ?? 0,
      name: (j['name'] ?? j['product_name'] ?? '') as String,
      sku: (j['SKU'] ?? j['sku'] ?? j['code'] ?? '') as String,
      category: (j['category'] ?? '') as String,
      costPrice: double.tryParse((j['cost_price'] ?? j['cost'] ?? 0).toString()) ?? 0.0,
      sellingPrice: double.tryParse((j['selling_price'] ?? j['price'] ?? 0).toString()) ?? 0.0,
      unit: (j['unit'] ?? 'pcs') as String,
      unitFactor: int.tryParse((j['unit_factor'] ?? 1).toString()) ?? 1,
      quantity: int.tryParse((j['quantity'] ?? j['qty'] ?? 0).toString()) ?? 0,
      minStock: int.tryParse((j['min_stock'] ?? j['min'] ?? 0).toString()) ?? 0,
      status: (j['status'] ?? 'active') as String,
      barcode: (j['barcode'] ?? j['bar_code'] ?? '') as String,
      createdBy: int.tryParse((j['created_by'] ?? 0).toString()) ?? 0,
      description: j['description'] as String?,
      categoryId: int.tryParse((j['category_id'] ?? '').toString()),
      brandId: int.tryParse((j['brand_id'] ?? '').toString()),
      categoryName: j['category_name'] as String?,
      brandName: j['brand_name'] as String?,
      priceTier: (j['price_tier'] ?? 'retail') as String,
      taxPercent: j['tax_percent'] == null ? null : double.tryParse(j['tax_percent'].toString()),
      familyId: j['family_id'] == null ? null : int.tryParse(j['family_id'].toString()),
      variantLabel: j['variant_label'] as String?,
      measure: (j['measure'] ?? 'count') as String,
      isService: j['is_service'] == true || j['is_service'] == 1 || j['is_service'] == '1',
      durationMinutes: j['duration_minutes'] == null ? null : int.tryParse(j['duration_minutes'].toString()),
      rebookAfterWeeks: j['rebook_after_weeks'] == null ? null : int.tryParse(j['rebook_after_weeks'].toString()),
      commissionPercent: j['commission_percent'] == null ? null : double.tryParse(j['commission_percent'].toString()),
      commissionFixed: j['commission_fixed'] == null ? null : double.tryParse(j['commission_fixed'].toString()),
      packageSessions: j['package_sessions'] == null ? null : int.tryParse(j['package_sessions'].toString()),
      packageServiceId: j['package_service_id'] == null ? null : int.tryParse(j['package_service_id'].toString()),
      packageValidDays: j['package_valid_days'] == null ? null : int.tryParse(j['package_valid_days'].toString()),
      staffIds: j['staff_ids'] is List ? <String>[for (final dynamic s in j['staff_ids'] as List) '$s'] : const <String>[],
      priceOptions: j['price_options'] is List
          ? <PriceOption>[
              for (final dynamic o in j['price_options'] as List)
                if (o is Map) PriceOption(label: '${o['label'] ?? ''}', price: double.tryParse('${o['price'] ?? ''}') ?? 0),
            ]
          : const <PriceOption>[],
    );

InvCustomer _fromCustomerJson(Map<String, dynamic> j) => InvCustomer(
      id: int.tryParse((j['id'] ?? j['customer_id'] ?? 0).toString()) ?? 0,
      name: (j['name'] ?? j['customer_name'] ?? '') as String,
      phone: (j['phone'] ?? j['phone_number'] ?? '') as String,
    );

InvSale _fromSaleJson(Map<String, dynamic> j) {
  final items = (j['items'] is List)
      ? (j['items'] as List)
          .map((it) => it is Map<String, dynamic>
              ? InvSaleItem(
                  productId: int.tryParse((it['product_id'] ?? 0).toString()) ?? 0,
                  name: (it['product_name'] ?? '') as String,
                  qty: int.tryParse((it['quantity'] ?? it['qty'] ?? 0).toString()) ?? 0,
                  unitPrice: double.tryParse((it['unit_price'] ?? 0).toString()) ?? 0.0,
                  unitCostSnapshot: (() {
                    final v = it['unit_cost_snapshot'] ?? it['unit_cost'] ?? 0;
                    return v is num ? v.toDouble() : double.tryParse('$v') ?? 0.0;
                  })(),
                  unitId: it['unit_id'] == null ? null : int.tryParse(it['unit_id'].toString()),
                  unitName: it['unit_name'] as String?,
                  unitFactor: int.tryParse((it['unit_factor'] ?? 1).toString()) ?? 1,
                  taxPercent: it['tax_percent'] == null ? null : double.tryParse(it['tax_percent'].toString()),
                  taxAmount: double.tryParse((it['tax_amount'] ?? 0).toString()) ?? 0.0,
                  staffId: it['staff_id']?.toString(),
                  staffName: it['staff_name']?.toString(),
                  isService: it['is_service'] == true || it['is_service'] == 1,
                )
              : null)
          .whereType<InvSaleItem>()
          .toList()
      : <InvSaleItem>[];
  double _n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0.0;
  final double subtotal = _n(j['subtotal']);
  final double total = _n(j['total']);
  final double discount = _n(j['discount']);
  final double tax = _n(j['tax']);
  final double paidTotal = _n(j['paid_total']);
  final createdAtStr = j['created_at']?.toString();
  // The server's times are UTC; a sale and its receipt show Tanzania time.
  final createdAt = parseServerTime(createdAtStr) ?? DateTime.now();
  final cancelledAtStr = j['cancelled_at']?.toString();
  return InvSale(
    id: int.tryParse((j['id'] ?? 0).toString()) ?? 0,
    number: (j['number'] ?? j['sale_number'] ?? '') as String,
    customerId: j['customer_id'] != null ? int.tryParse(j['customer_id'].toString()) : null,
    customerName: j['customer_name']?.toString(),
    customerPhone: j['customer_phone']?.toString(),
    paymentStatus: (j['payment_status'] ?? j['status'] ?? '') as String,
    items: items,
    subtotal: subtotal,
    discount: discount,
    tax: tax,
    total: total,
    paidTotal: paidTotal,
    dueDate: j['due_date'] != null
        ? DateTime.tryParse(j['due_date'].toString())
        : null,
    cancelledAt: cancelledAtStr != null ? DateTime.tryParse(cancelledAtStr) : null,
    cancellationReason: j['cancellation_reason']?.toString(),
    createdBy: int.tryParse((j['created_by'] ?? 0).toString()) ?? 0,
    createdAt: createdAt,
    payments: j['payments'] is List
        ? (j['payments'] as List).whereType<Map>().map((p) {
            final paidAtStr = p['paid_at']?.toString();
            return InvPayment(
              amount: _n(p['amount']),
              method: (p['method'] ?? 'cash').toString(),
              reference: (p['reference'] ?? '').toString(),
              paidAt: parseServerTime(paidAtStr) ?? DateTime.now(),
            );
          }).toList()
        : [],
  );
}

InvReminder _fromReminderJson(Map<String, dynamic> j) {
  InvReminderStatus statusFrom(s) {
    final v = (s ?? 'open').toString();
    switch (v) {
      case 'done':
        return InvReminderStatus.done;
      case 'snoozed':
        return InvReminderStatus.snoozed;
      default:
        return InvReminderStatus.open;
    }
  }

  return InvReminder(
    id: int.tryParse((j['id'] ?? 0).toString()) ?? 0,
    type: (j['type'] ?? 'payment_due') as String,
    title: (j['title'] ?? '') as String,
    description: (j['description'] ?? '') as String,
    dueAt: j['due_at'] != null
        ? (DateTime.tryParse(j['due_at'].toString()) ?? DateTime.now())
        : DateTime.now(),
    status: statusFrom(j['status']),
    snoozeUntil: j['snooze_until'] != null
        ? DateTime.tryParse(j['snooze_until'].toString())
        : null,
    relatedId: j['related_id'] != null 
        ? int.tryParse(j['related_id'].toString()) 
        : (j['sale_id'] != null ? int.tryParse(j['sale_id'].toString()) : null),
  );
}

InvCategory _fromCategoryJson(Map<String, dynamic> j) {
  final createdAtStr = j['created_at']?.toString();
  final updatedAtStr = j['updated_at']?.toString();
  final DateTime createdAt = createdAtStr != null
      ? (DateTime.tryParse(createdAtStr) ?? DateTime.now())
      : DateTime.now();
  final DateTime updatedAt = updatedAtStr != null
      ? (DateTime.tryParse(updatedAtStr) ?? createdAt)
      : createdAt;
  return InvCategory(
    id: int.tryParse((j['id'] ?? j['category_id'] ?? 0).toString()) ?? 0,
    name: (j['name'] ?? j['category_name'] ?? '') as String,
    code: (j['code'] ?? j['category_code'] ?? '') as String,
    description: (j['description'] ?? '') as String,
    parentId: j['parent_id'] != null ? int.tryParse(j['parent_id'].toString()) : null,
    imagePath: (j['image'] ?? j['icon'] ?? j['image_url']) as String?,
    status: (j['status'] ?? 'active') as String,
    totalProducts: int.tryParse((j['total_products'] ?? 0).toString()) ?? 0,
    createdBy: int.tryParse((j['created_by'] ?? 0).toString()) ?? 0,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

class InvStockMovement {
  final int id;
  final int productId;
  final String productName;
  final String productSku;
  final String type; // 'in' | 'out'
  final int quantity;
  final int previousQuantity;
  final int newQuantity;
  final String reason;
  final String reference;
  final String userName;
  final DateTime createdAt;
  final String batchNumber;

  InvStockMovement({
    required this.id,
    required this.productId,
    required this.productName,
    required this.productSku,
    required this.type,
    required this.quantity,
    required this.previousQuantity,
    required this.newQuantity,
    required this.reason,
    required this.reference,
    required this.userName,
    required this.createdAt,
    this.batchNumber = '',
  });

  bool get isStockIn => type.toLowerCase() == 'in';
}

InvStockMovement _fromStockMovementJson(Map<String, dynamic> j) {
  final DateTime createdAt = parseServerTime(j['created_at']) ?? DateTime.now();

  return InvStockMovement(
    id: int.tryParse((j['id'] ?? 0).toString()) ?? 0,
    productId: int.tryParse((j['product_id'] ?? 0).toString()) ?? 0,
    productName: (j['product_name'] ?? j['name'] ?? '') as String,
    productSku: (j['product_sku'] ?? j['sku'] ?? '') as String,
    type: (j['type'] ?? 'in') as String,
    quantity: int.tryParse((j['quantity'] ?? 0).toString()) ?? 0,
    previousQuantity: int.tryParse((j['previous_quantity'] ?? 0).toString()) ?? 0,
    newQuantity: int.tryParse((j['new_quantity'] ?? 0).toString()) ?? 0,
    reason: (j['reason'] ?? '') as String,
    reference: (j['reference'] ?? '') as String,
    userName: (j['user_name'] ?? '') as String,
    createdAt: createdAt,
    batchNumber: (j['batch_number'] ?? '').toString(),
  );
}

