import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../services/api_service.dart';
import '../models/inv_capabilities.dart';
import '../models/inv_depot_models.dart';
import '../services/inv_event_bus.dart';
import '../../../services/localization_service.dart';
import '../../../utils/server_message.dart';

/// State for Areas 4–13: purchasing, credit, cash, crates, POS extras,
/// dispatch, barcodes, reports, alerts, audit and settings.
///
/// Kept separate from [InventoryProvider] so neither class becomes a
/// dumping ground; screens read whichever one owns their data.
class DepotProvider extends ChangeNotifier {
  DepotProvider({ApiService? api}) : _api = api ?? ApiService() {
    _busSub = InvEventBus.instance.stream.listen(_onBusEvent);
  }

  final ApiService _api;
  late final StreamSubscription<Set<InvDomain>> _busSub;

  @override
  void dispose() {
    _busSub.cancel();
    super.dispose();
  }

  /// Re-fetches depot-owned data when relevant events arrive from other
  /// providers (e.g. a goods receipt emitted by InventoryProvider triggers
  /// crate and purchasing refreshes here).
  void _onBusEvent(Set<InvDomain> domains) {
    final futures = <Future<void>>[];
    if (domains.contains(InvDomain.purchase)) {
      futures.addAll([fetchPurchaseOrders(), fetchSupplierInvoices(), fetchSuppliers()]);
    }
    if (domains.contains(InvDomain.crate)) {
      futures.addAll([fetchCratePosition(), fetchCrateBalances()]);
    }
    if (domains.contains(InvDomain.credit)) {
      futures.addAll([fetchCreditCustomers(), fetchDebtorsAgeing()]);
    }
    if (domains.contains(InvDomain.settings)) {
      futures.add(fetchSettings());
    }
    if (futures.isNotEmpty) {
      Future.wait(futures).ignore();
    }
  }

  // ---- state -------------------------------------------------------------
  final List<InvSupplier> _suppliers = <InvSupplier>[];
  final List<InvPurchaseOrder> _purchaseOrders = <InvPurchaseOrder>[];
  final List<InvSupplierInvoice> _supplierInvoices = <InvSupplierInvoice>[];
  final List<InvCreditCustomer> _creditCustomers = <InvCreditCustomer>[];
  final List<InvDebtorAgeing> _debtors = <InvDebtorAgeing>[];
  Map<String, double> _debtorTotals = const <String, double>{};
  final List<InvCashSession> _cashSessions = <InvCashSession>[];
  InvCashSession? _activeSession;
  final List<InvCrateType> _crateTypes = <InvCrateType>[];
  final List<InvCrateBalance> _crateBalances = <InvCrateBalance>[];
  final List<InvCrateBalance> _cratePosition = <InvCrateBalance>[];
  final List<InvParkedSale> _parkedSales = <InvParkedSale>[];
  final List<InvSaleReturn> _returns = <InvSaleReturn>[];
  final List<InvDispatch> _dispatches = <InvDispatch>[];
  final List<InvReportMeta> _reports = <InvReportMeta>[];
  final List<InvAlert> _alerts = <InvAlert>[];
  final List<InvAuditEntry> _auditLog = <InvAuditEntry>[];
  Map<String, String> _settings = <String, String>{};
  bool _loading = false;

  /// Forget everything held for the previous service or account: another business's name, settings and figures
  /// must never be drawn while this one's are still on their way.
  void resetForNewContext() {
    _suppliers.clear();
    _purchaseOrders.clear();
    _supplierInvoices.clear();
    _creditCustomers.clear();
    _debtors.clear();
    _debtorTotals = const <String, double>{};
    _cashSessions.clear();
    _activeSession = null;
    _crateTypes.clear();
    _crateBalances.clear();
    _cratePosition.clear();
    _parkedSales.clear();
    _returns.clear();
    _dispatches.clear();
    _reports.clear();
    _alerts.clear();
    _auditLog.clear();
    _settings = <String, String>{};
    notifyListeners();
  }

  // ---- reads -------------------------------------------------------------
  List<InvSupplier> get suppliers => List.unmodifiable(_suppliers);
  List<InvPurchaseOrder> get purchaseOrders =>
      List.unmodifiable(_purchaseOrders);
  List<InvSupplierInvoice> get supplierInvoices =>
      List.unmodifiable(_supplierInvoices);
  List<InvCreditCustomer> get creditCustomers =>
      List.unmodifiable(_creditCustomers);
  List<InvDebtorAgeing> get debtors => List.unmodifiable(_debtors);
  Map<String, double> get debtorTotals => Map.unmodifiable(_debtorTotals);
  List<InvCashSession> get cashSessions => List.unmodifiable(_cashSessions);
  InvCashSession? get activeSession => _activeSession;
  List<InvCrateType> get crateTypes => List.unmodifiable(_crateTypes);

  /// The types that may be chosen for a new sale or movement.
  List<InvCrateType> get activeCrateTypes => List.unmodifiable(
      _crateTypes.where((InvCrateType t) => t.isActive));
  List<InvCrateBalance> get crateBalances => List.unmodifiable(_crateBalances);
  List<InvCrateBalance> get cratePosition => List.unmodifiable(_cratePosition);
  List<InvParkedSale> get parkedSales => List.unmodifiable(_parkedSales);
  List<InvSaleReturn> get returns => List.unmodifiable(_returns);
  List<InvDispatch> get dispatches => List.unmodifiable(_dispatches);
  List<InvReportMeta> get reports => List.unmodifiable(_reports);
  List<InvAlert> get alerts => List.unmodifiable(_alerts);
  List<InvAuditEntry> get auditLog => List.unmodifiable(_auditLog);
  Map<String, String> get settings => Map.unmodifiable(_settings);
  bool get isLoading => _loading;

  int get openAlertCount => _alerts.where((InvAlert a) => a.isOpen).length;
  int get criticalAlertCount =>
      _alerts.where((InvAlert a) => a.isOpen && a.isCritical).length;
  int get pendingReturnCount =>
      _returns.where((InvSaleReturn r) => r.isPending).length;
  double get totalCratesOut => _cratePosition.fold<double>(
      0, (double s, InvCrateBalance c) => s + c.outWithCustomers);
  double get totalDebt =>
      _debtors.fold<double>(0, (double s, InvDebtorAgeing d) => s + d.total);

  double settingAsDouble(String key, double fallback) =>
      double.tryParse(_settings[key] ?? '') ?? fallback;

  /// What this business's inventory is set up to do (crates or not, which price the till uses, VAT ...).
  /// Anything the server did not send reads as the depot's behaviour, which is what it always was.
  InvCapabilities get capabilities => InvCapabilities.fromSettings(_settings);

  /// Crates exist only for a business that sells returnable packaging. Until the settings have arrived nobody knows
  /// yet, so the depot's behaviour (crates) is assumed, as everywhere else.
  bool get _cratesWanted => _settings.isEmpty || capabilities.useCrates;

  /// Fetch everything the depot dashboard and menus need, in parallel.
  Future<void> bootstrap() async {
    _loading = true;
    notifyListeners();
    await Future.wait<void>(<Future<void>>[
      fetchSuppliers(),
      fetchCreditCustomers(),
      fetchCrateTypes(),
      fetchCratePosition(),
      fetchAlerts(),
      fetchSettings(),
      fetchReports(),
    ]);
    _loading = false;
    notifyListeners();
  }

  // ---- generic helpers ---------------------------------------------------

  /// GET a list endpoint and map it, swallowing transport errors so a screen
  /// keeps whatever it already had rather than blanking out.
  Future<List<T>> _getList<T>(
    String path,
    T Function(Map<String, dynamic>) parse,
  ) async {
    try {
      final Map<String, dynamic>? res = await _api.getOrNull(path);
      final dynamic data = res?['data'];
      if (data is! List) {
        return <T>[];
      }
      return data
          .map((e) => parse(Map<String, dynamic>.from(e as Map)))
          .toList();
    } on Exception {
      return <T>[];
    }
  }

  Future<bool> _post(String path, Map<String, dynamic> body) async {
    try {
      await _api.post(path, body);
      return true;
    } on Exception {
      return false;
    }
  }

  String _query(Map<String, String?> params) {
    final Iterable<String> parts = params.entries
        .where((MapEntry<String, String?> e) =>
            e.value != null && e.value!.isNotEmpty)
        .map((MapEntry<String, String?> e) =>
            '${e.key}=${Uri.encodeComponent(e.value!)}');
    return parts.isEmpty ? '' : '?${parts.join('&')}';
  }

  /// Inject rows without touching the network. Tests use this to render every
  /// screen with realistic content, which is where layout bugs actually show.
  @visibleForTesting
  void seedForTest({
    List<InvSupplier>? suppliers,
    List<InvPurchaseOrder>? purchaseOrders,
    List<InvSupplierInvoice>? supplierInvoices,
    List<InvCreditCustomer>? creditCustomers,
    List<InvDebtorAgeing>? debtors,
    List<InvCashSession>? cashSessions,
    InvCashSession? activeSession,
    List<InvCrateType>? crateTypes,
    List<InvCrateBalance>? crateBalances,
    List<InvCrateBalance>? cratePosition,
    List<InvParkedSale>? parkedSales,
    List<InvSaleReturn>? returns,
    List<InvDispatch>? dispatches,
    List<InvReportMeta>? reports,
    List<InvAlert>? alerts,
    List<InvAuditEntry>? auditLog,
    Map<String, String>? settings,
  }) {
    void fill<T>(List<T> target, List<T>? source) {
      if (source == null) return;
      target
        ..clear()
        ..addAll(source);
    }

    fill(_suppliers, suppliers);
    fill(_purchaseOrders, purchaseOrders);
    fill(_supplierInvoices, supplierInvoices);
    fill(_creditCustomers, creditCustomers);
    fill(_debtors, debtors);
    fill(_cashSessions, cashSessions);
    fill(_crateTypes, crateTypes);
    fill(_crateBalances, crateBalances);
    fill(_cratePosition, cratePosition);
    fill(_parkedSales, parkedSales);
    fill(_returns, returns);
    fill(_dispatches, dispatches);
    fill(_reports, reports);
    fill(_alerts, alerts);
    fill(_auditLog, auditLog);
    if (activeSession != null) _activeSession = activeSession;
    if (settings != null) _settings = settings;
    notifyListeners();
  }

  // ---- Area 4: purchasing ------------------------------------------------

  Future<void> fetchSuppliers({String? q}) async {
    final List<InvSupplier> rows = await _getList(
      '/inventory/suppliers${_query(<String, String?>{'q': q})}',
      InvSupplier.fromJson,
    );
    _suppliers
      ..clear()
      ..addAll(rows);
    notifyListeners();
  }

  Future<bool> saveSupplier({
    int? id,
    required String name,
    String? phone,
    String? email,
    String? address,
    String? contactPerson,
    int? paymentTermsDays,
    String? status,
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{
      'name': name,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
      if (email != null && email.isNotEmpty) 'email': email,
      if (address != null && address.isNotEmpty) 'address': address,
      if (contactPerson != null && contactPerson.isNotEmpty)
        'contact_person': contactPerson,
      if (paymentTermsDays != null) 'payment_terms_days': paymentTermsDays,
      if (status != null) 'status': status,
    };

    try {
      if (id == null) {
        await _api.post('/inventory/suppliers', body);
      } else {
        await _api.put('/inventory/suppliers/$id', body);
      }
      await fetchSuppliers();
      return true;
    } on Exception {
      return false;
    }
  }

  Future<void> fetchPurchaseOrders({String? status}) async {
    final List<InvPurchaseOrder> rows = await _getList(
      '/inventory/purchase-orders${_query(<String, String?>{
            'status': status
          })}',
      InvPurchaseOrder.fromJson,
    );
    _purchaseOrders
      ..clear()
      ..addAll(rows);
    notifyListeners();
  }

  Future<InvPurchaseOrder?> fetchPurchaseOrder(int id) async {
    try {
      final Map<String, dynamic>? res =
          await _api.getOrNull('/inventory/purchase-orders/$id');
      final dynamic data = res?['data'];
      return data is Map
          ? InvPurchaseOrder.fromJson(Map<String, dynamic>.from(data))
          : null;
    } on Exception {
      return null;
    }
  }

  Future<bool> createPurchaseOrder({
    required int supplierId,
    required List<Map<String, dynamic>> lines,
    DateTime? expectedAt,
    String? note,
  }) async {
    final bool ok = await _post('/inventory/purchase-orders', <String, dynamic>{
      'supplier_id': supplierId,
      'lines': lines,
      if (expectedAt != null)
        'expected_at': expectedAt.toIso8601String().split('T').first,
      if (note != null && note.isNotEmpty) 'note': note,
    });
    if (ok) {
      await fetchPurchaseOrders();
    }
    return ok;
  }

  Future<bool> setPurchaseOrderStatus(int id, String status) async {
    final bool ok = await _post(
      '/inventory/purchase-orders/$id/status',
      <String, dynamic>{'status': status},
    );
    if (ok) {
      await fetchPurchaseOrders();
    }
    return ok;
  }

  /// Receive goods, capturing batch, expiry and buying cost per line.
  Future<bool> receiveGoods({
    required int supplierId,
    required List<Map<String, dynamic>> lines,
    int? purchaseOrderId,
    String? invoiceNumber,
    DateTime? invoiceDueDate,
    String? note,
  }) async {
    final bool ok = await _post('/inventory/goods-receipts', <String, dynamic>{
      'supplier_id': supplierId,
      'lines': lines,
      if (purchaseOrderId != null) 'purchase_order_id': purchaseOrderId,
      if (invoiceNumber != null && invoiceNumber.isNotEmpty)
        'invoice_number': invoiceNumber,
      if (invoiceDueDate != null)
        'invoice_due_date': invoiceDueDate.toIso8601String().split('T').first,
      if (note != null && note.isNotEmpty) 'note': note,
    });
    if (ok) {
      await Future.wait<void>(<Future<void>>[
        fetchPurchaseOrders(),
        fetchSupplierInvoices(),
        fetchSuppliers(),
      ]);
      // Notify InventoryProvider to refresh products + KPIs (stock changed).
      InvEventBus.instance.emit({InvDomain.purchase, InvDomain.stock});
    }
    return ok;
  }

  Future<void> fetchSupplierInvoices({String? status}) async {
    final List<InvSupplierInvoice> rows = await _getList(
      '/inventory/supplier-invoices${_query(<String, String?>{
            'status': status
          })}',
      InvSupplierInvoice.fromJson,
    );
    _supplierInvoices
      ..clear()
      ..addAll(rows);
    notifyListeners();
  }

  Future<bool> paySupplier({
    required int supplierId,
    required double amount,
    required String method,
    int? invoiceId,
    String? reference,
  }) async {
    final bool ok =
        await _post('/inventory/supplier-payments', <String, dynamic>{
      'supplier_id': supplierId,
      'amount': amount,
      'method': method,
      if (invoiceId != null) 'supplier_invoice_id': invoiceId,
      if (reference != null && reference.isNotEmpty) 'reference': reference,
    });
    if (ok) {
      await Future.wait<void>(<Future<void>>[
        fetchSupplierInvoices(),
        fetchSuppliers(),
      ]);
    }
    return ok;
  }

  // ---- Area 6: credit ----------------------------------------------------

  Future<void> fetchCreditCustomers(
      {String? q, bool overLimitOnly = false}) async {
    final List<InvCreditCustomer> rows = await _getList(
      '/inventory/credit/customers${_query(<String, String?>{
            'q': q,
            'over_limit': overLimitOnly ? '1' : null,
          })}',
      InvCreditCustomer.fromJson,
    );
    _creditCustomers
      ..clear()
      ..addAll(rows);
    notifyListeners();
  }

  /// Returns the unpaid sales for a customer (debt + partial), newest first.
  Future<List<Map<String, dynamic>>> fetchCustomerDebtSales(int customerId) async {
    try {
      final Map<String, dynamic> res =
          await _api.get('/inventory/credit/customers/$customerId/statement');
      final dynamic salesRaw = (res['data'] as Map?)?['sales'];
      if (salesRaw is! List) return [];
      return salesRaw
          .whereType<Map>()
          .where((s) => s['payment_status'] == 'debt' || s['payment_status'] == 'partial')
          .map((s) => Map<String, dynamic>.from(s))
          .toList();
    } on Exception {
      return [];
    }
  }

  Future<bool> updateCredit(
    int customerId, {
    double? creditLimit,
    int? paymentTermsDays,
    bool? isBlocked,
    String? blockReason,
  }) async {
    try {
      await _api
          .put('/inventory/credit/customers/$customerId', <String, dynamic>{
        if (creditLimit != null) 'credit_limit': creditLimit,
        if (paymentTermsDays != null) 'payment_terms_days': paymentTermsDays,
        if (isBlocked != null) 'is_blocked': isBlocked,
        if (blockReason != null) 'block_reason': blockReason,
      });
      await fetchCreditCustomers();
      return true;
    } on Exception {
      return false;
    }
  }

  /// Ask whether this customer may take on `amount` more credit.
  Future<Map<String, dynamic>?> creditCheck(
      int customerId, double amount) async {
    try {
      final Map<String, dynamic>? res = await _api.getOrNull(
          '/inventory/credit/customers/$customerId/check?amount=$amount');
      final dynamic data = res?['data'];
      return data is Map ? Map<String, dynamic>.from(data) : null;
    } on Exception {
      return null;
    }
  }

  Future<InvStatement?> fetchStatement(
    int customerId, {
    DateTime? from,
    DateTime? to,
  }) async {
    final String qs = _query(<String, String?>{
      'from': from?.toIso8601String().split('T').first,
      'to': to?.toIso8601String().split('T').first,
    });
    try {
      final Map<String, dynamic>? res = await _api
          .getOrNull('/inventory/credit/customers/$customerId/statement$qs');
      final dynamic data = res?['data'];
      return data is Map
          ? InvStatement.fromJson(Map<String, dynamic>.from(data))
          : null;
    } on Exception {
      return null;
    }
  }

  Future<void> fetchDebtorsAgeing() async {
    try {
      final Map<String, dynamic>? res =
          await _api.getOrNull('/inventory/credit/debtors-ageing');
      if (res == null) {
        return;
      }
      final List<dynamic> rows =
          (res['data'] is List) ? res['data'] as List<dynamic> : <dynamic>[];
      _debtors
        ..clear()
        ..addAll(rows.map((r) =>
            InvDebtorAgeing.fromJson(Map<String, dynamic>.from(r as Map))));

      final dynamic meta = res['meta'];
      if (meta is Map) {
        _debtorTotals = meta.map((key, value) => MapEntry(
              key.toString(),
              value is num
                  ? value.toDouble()
                  : double.tryParse(value.toString()) ?? 0,
            ));
      }
      notifyListeners();
    } on Exception {
      // keep the last good list
    }
  }

  // ---- Area 7: payments & cash -------------------------------------------

  /// Take a payment; the server allocates it oldest-invoice-first unless
  /// explicit allocations are given.
  Future<Map<String, dynamic>?> receivePayment({
    required int customerId,
    required double amount,
    required String method,
    String? reference,
    List<Map<String, dynamic>>? allocations,
  }) async {
    try {
      final Map<String, dynamic> res =
          await _api.post('/inventory/payments', <String, dynamic>{
        'customer_id': customerId,
        'amount': amount,
        'method': method,
        if (reference != null && reference.isNotEmpty) 'reference': reference,
        if (allocations != null && allocations.isNotEmpty)
          'allocations': allocations,
      });
      await Future.wait<void>(<Future<void>>[
        fetchCreditCustomers(),
        fetchDebtorsAgeing(),
      ]);
      final dynamic data = res['data'];
      return data is Map
          ? Map<String, dynamic>.from(data)
          : <String, dynamic>{};
    } on Exception {
      return null;
    }
  }

  Future<void> fetchCashSessions(
      {String? status, bool mineOnly = false}) async {
    final List<InvCashSession> rows = await _getList(
      '/inventory/cash-sessions${_query(<String, String?>{
            'status': status,
            'mine': mineOnly ? '1' : null,
          })}',
      InvCashSession.fromJson,
    );
    _cashSessions
      ..clear()
      ..addAll(rows);
    notifyListeners();
  }

  Future<InvCashSession?> fetchCashSession(int id) async {
    try {
      final Map<String, dynamic>? res =
          await _api.getOrNull('/inventory/cash-sessions/$id');
      final dynamic data = res?['data'];
      if (data is! Map) {
        return null;
      }
      _activeSession = InvCashSession.fromJson(Map<String, dynamic>.from(data));
      notifyListeners();
      return _activeSession;
    } on Exception {
      return null;
    }
  }

  Future<int?> openCashSession({double openingFloat = 0}) async {
    try {
      final Map<String, dynamic> res = await _api.post(
        '/inventory/cash-sessions',
        <String, dynamic>{'opening_float': openingFloat},
      );
      await fetchCashSessions();
      final dynamic data = res['data'];
      return (data is Map && data['id'] is num)
          ? (data['id'] as num).toInt()
          : null;
    } on Exception {
      return null;
    }
  }

  Future<bool> addCashExpense(
    int sessionId, {
    required String description,
    required double amount,
  }) async {
    final bool ok = await _post(
      '/inventory/cash-sessions/$sessionId/expenses',
      <String, dynamic>{'description': description, 'amount': amount},
    );
    if (ok) {
      await fetchCashSession(sessionId);
    }
    return ok;
  }

  /// Close the shift. Returns the server's message when it refuses — an
  /// unexplained shortage or surplus is rejected, and the UI shows why.
  Future<String?> closeCashSession(
    int sessionId, {
    required double countedCash,
    String? reason,
  }) async {
    try {
      await _api.post(
        '/inventory/cash-sessions/$sessionId/close',
        <String, dynamic>{
          'counted_cash': countedCash,
          if (reason != null && reason.isNotEmpty) 'difference_reason': reason,
        },
      );
      await Future.wait<void>(<Future<void>>[
        fetchCashSessions(),
        fetchCashSession(sessionId).then((_) {}),
      ]);
      return null;
    } on Exception catch (e) {
      return readableErrorMessage(e);
    }
  }

  // ---- Area 8: crates ----------------------------------------------------

  Future<void> fetchCrateTypes() async {
    if (!_cratesWanted) return;
    final List<InvCrateType> rows =
        await _getList('/inventory/crate-types', InvCrateType.fromJson);
    _crateTypes
      ..clear()
      ..addAll(rows);
    notifyListeners();
  }

  // Crate types and the security deposit per crate (Depot Settings). Each call
  // returns null on success, or the server's reason when it refuses -- for example
  // customers still holding crates of a type being switched off.

  Future<String?> createCrateType(
          {required String name, required double deposit}) =>
      _crateTypeCall(() => _api.post('/inventory/crate-types',
          <String, dynamic>{'name': name, 'deposit_value': deposit}));

  Future<String?> updateCrateType(int id,
          {required String name,
          required double deposit,
          required bool active}) =>
      _crateTypeCall(() => _api.put('/inventory/crate-types/$id',
          <String, dynamic>{
            'name': name,
            'deposit_value': deposit,
            'status': active ? 'active' : 'inactive',
          }));

  Future<String?> deleteCrateType(int id) =>
      _crateTypeCall(() => _api.delete('/inventory/crate-types/$id'));

  Future<String?> _crateTypeCall(Future<Object?> Function() call) async {
    try {
      await call();
      await fetchCrateTypes();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } on Exception catch (e) {
      return readableErrorMessage(e);
    }
  }

  Future<void> fetchCrateBalances({int? customerId}) async {
    if (!_cratesWanted) return;
    final List<InvCrateBalance> rows = await _getList(
      '/inventory/crate-balances${_query(<String, String?>{
            'customer_id': customerId?.toString(),
          })}',
      InvCrateBalance.fromJson,
    );
    _crateBalances
      ..clear()
      ..addAll(rows);
    notifyListeners();
  }

  Future<void> fetchCratePosition() async {
    if (!_cratesWanted) return;
    final List<InvCrateBalance> rows =
        await _getList('/inventory/crate-position', InvCrateBalance.fromJson);
    _cratePosition
      ..clear()
      ..addAll(rows);
    notifyListeners();
  }

  Future<bool> recordCrateMovement({
    required int crateTypeId,
    required String direction,
    required int quantity,
    int? customerId,
    String? note,
  }) async {
    final bool ok = await _post('/inventory/crate-movements', <String, dynamic>{
      'crate_type_id': crateTypeId,
      'direction': direction,
      'quantity': quantity,
      if (customerId != null) 'customer_id': customerId,
      if (note != null && note.isNotEmpty) 'note': note,
    });
    if (ok) {
      await Future.wait<void>(<Future<void>>[
        fetchCrateBalances(),
        fetchCratePosition(),
      ]);
      InvEventBus.instance.emit({InvDomain.crate});
    }
    return ok;
  }

  // ---- Area 5: POS extras ------------------------------------------------

  Future<void> fetchParkedSales() async {
    final List<InvParkedSale> rows =
        await _getList('/inventory/parked-sales', InvParkedSale.fromJson);
    _parkedSales
      ..clear()
      ..addAll(rows);
    notifyListeners();
  }

  Future<bool> parkSale({
    required List<Map<String, dynamic>> cart,
    required double total,
    int? customerId,
    String? note,
  }) async {
    final bool ok = await _post('/inventory/parked-sales', <String, dynamic>{
      'cart': cart,
      'total': total,
      if (customerId != null) 'customer_id': customerId,
      if (note != null && note.isNotEmpty) 'note': note,
    });
    if (ok) {
      await fetchParkedSales();
    }
    return ok;
  }

  Future<Map<String, dynamic>?> resumeParkedSale(int id) async {
    try {
      final Map<String, dynamic> res = await _api.post(
          '/inventory/parked-sales/$id/resume', const <String, dynamic>{});
      await fetchParkedSales();
      final dynamic data = res['data'];
      return data is Map ? Map<String, dynamic>.from(data) : null;
    } on Exception {
      return null;
    }
  }

  Future<bool> discardParkedSale(int id) async {
    try {
      await _api.delete('/inventory/parked-sales/$id');
      await fetchParkedSales();
      return true;
    } on Exception {
      return false;
    }
  }

  Future<void> fetchReturns({String? status}) async {
    final List<InvSaleReturn> rows = await _getList(
      '/inventory/returns${_query(<String, String?>{'status': status})}',
      InvSaleReturn.fromJson,
    );
    _returns
      ..clear()
      ..addAll(rows);
    notifyListeners();
  }

  Future<bool> createReturn({
    required int saleId,
    required String type,
    required List<Map<String, dynamic>> lines,
    String? reason,
  }) async {
    final bool ok = await _post('/inventory/returns', <String, dynamic>{
      'sale_id': saleId,
      'type': type,
      'lines': lines,
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    });
    if (ok) {
      await fetchReturns();
    }
    return ok;
  }

  Future<bool> decideReturn(int id, {required bool approve}) async {
    final bool ok = await _post(
      '/inventory/returns/$id/decide',
      <String, dynamic>{'decision': approve ? 'approved' : 'rejected'},
    );
    if (ok) {
      await fetchReturns();
    }
    return ok;
  }

  /// Is this discount inside the configured limit?
  Future<Map<String, dynamic>?> checkDiscount({
    required double subtotal,
    required double discount,
  }) async {
    try {
      final Map<String, dynamic>? res = await _api.getOrNull(
        '/inventory/discount-check?subtotal=$subtotal&discount=$discount',
      );
      final dynamic data = res?['data'];
      return data is Map ? Map<String, dynamic>.from(data) : null;
    } on Exception {
      return null;
    }
  }

  // ---- Area 9: dispatch --------------------------------------------------

  Future<void> fetchDispatches({String? status}) async {
    final List<InvDispatch> rows = await _getList(
      '/inventory/dispatches${_query(<String, String?>{'status': status})}',
      InvDispatch.fromJson,
    );
    _dispatches
      ..clear()
      ..addAll(rows);
    notifyListeners();
  }

  Future<InvDispatch?> fetchDispatch(int id) async {
    try {
      final Map<String, dynamic>? res =
          await _api.getOrNull('/inventory/dispatches/$id');
      final dynamic data = res?['data'];
      return data is Map
          ? InvDispatch.fromJson(Map<String, dynamic>.from(data))
          : null;
    } on Exception {
      return null;
    }
  }

  Future<bool> createDispatch({
    required List<Map<String, dynamic>> lines,
    String? vehicle,
    String? route,
    String? note,
  }) async {
    final bool ok = await _post('/inventory/dispatches', <String, dynamic>{
      'lines': lines,
      if (vehicle != null && vehicle.isNotEmpty) 'vehicle': vehicle,
      if (route != null && route.isNotEmpty) 'route': route,
      if (note != null && note.isNotEmpty) 'note': note,
    });
    if (ok) {
      await fetchDispatches();
    }
    return ok;
  }

  Future<Map<String, dynamic>?> reconcileDispatch(
    int id, {
    required double cashReturned,
    required List<Map<String, dynamic>> lines,
    String? note,
  }) async {
    try {
      final Map<String, dynamic> res = await _api.post(
        '/inventory/dispatches/$id/reconcile',
        <String, dynamic>{
          'cash_returned': cashReturned,
          'lines': lines,
          if (note != null && note.isNotEmpty) 'note': note,
        },
      );
      await fetchDispatches();
      final dynamic data = res['data'];
      return data is Map
          ? Map<String, dynamic>.from(data)
          : <String, dynamic>{};
    } on Exception {
      return null;
    }
  }

  // ---- Area 10: barcodes -------------------------------------------------

  Future<String?> generateBarcode({
    required String entityType,
    required int entityId,
  }) async {
    try {
      final Map<String, dynamic> res =
          await _api.post('/inventory/barcodes', <String, dynamic>{
        'entity_type': entityType,
        'entity_id': entityId,
      });
      final dynamic data = res['data'];
      return (data is Map) ? data['code']?.toString() : null;
    } on Exception {
      return null;
    }
  }

  /// Resolve a scanned code to the product, unit, batch or crate it names.
  Future<InvScanResult?> resolveBarcode(String code) async {
    try {
      final Map<String, dynamic>? res = await _api.getOrNull(
        '/inventory/barcodes/resolve?code=${Uri.encodeComponent(code)}',
      );
      final dynamic data = res?['data'];
      return data is Map
          ? InvScanResult.fromJson(Map<String, dynamic>.from(data))
          : null;
    } on Exception {
      return null;
    }
  }

  // ---- Area 11: reports --------------------------------------------------

  Future<void> fetchReports() async {
    final List<InvReportMeta> rows =
        await _getList('/inventory/reports', InvReportMeta.fromJson);
    _reports
      ..clear()
      ..addAll(rows);
    notifyListeners();
  }

  Future<InvReport?> runReport(
    String key, {
    DateTime? from,
    DateTime? to,
  }) async {
    final String qs = _query(<String, String?>{
      'from': from?.toIso8601String().split('T').first,
      'to': to?.toIso8601String().split('T').first,
    });
    try {
      final Map<String, dynamic>? res =
          await _api.getOrNull('/inventory/reports/$key$qs');
      final dynamic data = res?['data'];
      return data is Map
          ? InvReport.fromJson(Map<String, dynamic>.from(data))
          : null;
    } on Exception {
      return null;
    }
  }

  // ---- Areas 12 & 13: alerts, audit, settings ----------------------------

  Future<void> fetchAlerts({String status = 'open'}) async {
    final List<InvAlert> rows = await _getList(
      '/inventory/alerts?status=$status',
      InvAlert.fromJson,
    );
    _alerts
      ..clear()
      ..addAll(rows);
    notifyListeners();
  }

  Future<bool> acknowledgeAlert(int id) async {
    final bool ok = await _post(
      '/inventory/alerts/$id/acknowledge',
      const <String, dynamic>{},
    );
    if (ok) {
      await fetchAlerts();
    }
    return ok;
  }

  Future<void> fetchAuditLog({
    String? entityType,
    DateTime? from,
    DateTime? to,
  }) async {
    final List<InvAuditEntry> rows = await _getList(
      '/inventory/audit-log${_query(<String, String?>{
            'entity_type': entityType,
            'from': from?.toIso8601String().split('T').first,
            'to': to?.toIso8601String().split('T').first,
          })}',
      InvAuditEntry.fromJson,
    );
    _auditLog
      ..clear()
      ..addAll(rows);
    notifyListeners();
  }

  Future<void> fetchSettings() async {
    try {
      final Map<String, dynamic>? res =
          await _api.getOrNull('/inventory/settings');
      final dynamic data = res?['data'];
      if (data is! Map) {
        return;
      }
      _settings = data.map(
        (key, value) => MapEntry(key.toString(), (value ?? '').toString()),
      );
      notifyListeners();
    } on Exception {
      // keep the previous settings
    }
  }

  /// Change the kind of stock business (retail, wholesale, mixed, depot). Only the business owner may; the
  /// server says so otherwise. Returns null on success, or the reason it was refused.
  Future<String?> changeBusinessKind(String kind) async {
    try {
      await _api.put('/business', <String, dynamic>{'inventory_type': kind});
      // The till, the product page and the menus read the kind from the settings: read them again, and tell
      // the other providers to do the same.
      await fetchSettings();
      InvEventBus.instance.emit({InvDomain.settings});
      return null;
    } on ApiException catch (e) {
      return e.message;
    } on Exception {
      return LocalizationService.instance.translate('could_not_reach_the_server_check');
    }
  }

  Future<bool> saveSettings(Map<String, String> values) async {
    try {
      await _api.put('/inventory/settings', values);
      await fetchSettings();
      InvEventBus.instance.emit({InvDomain.settings});
      return true;
    } on Exception {
      return false;
    }
  }
}
