import 'dart:io';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/sms_service.dart';
import '../widgets/temporary_password_dialog.dart' show temporaryPasswordOf;

class RentalProvider extends ChangeNotifier {
  final ApiService _api = ApiService();

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  // Dashboard
  Map<String, dynamic> _dashboardData = {};
  Map<String, dynamic> get dashboardData => _dashboardData;

  // Properties
  List<dynamic> _properties = [];
  List<dynamic> get properties => _properties;

  // Blocks
  List<dynamic> _blocks = [];
  List<dynamic> get blocks => _blocks;

  // Tenants
  List<dynamic> _tenants = [];
  List<dynamic> get tenants => _tenants;

  // Bills
  List<dynamic> _bills = [];
  List<dynamic> get bills => _bills;

  // Payments
  List<dynamic> _payments = [];
  List<dynamic> get payments => _payments;

  // Receipts
  List<dynamic> _receipts = [];
  List<dynamic> get receipts => _receipts;

  // Arrears
  List<dynamic> _arrears = [];
  List<dynamic> get arrears => _arrears;

  // Selected Property for details
  Map<String, dynamic>? _selectedProperty;
  Map<String, dynamic>? get selectedProperty => _selectedProperty;

  // Property Stats
  Map<String, dynamic>? _propertyStats;
  Map<String, dynamic>? get propertyStats => _propertyStats;

  // Pagination
  int _currentPage = 1;
  int _totalPages = 1;
  bool _hasMore = true;
  int get currentPage => _currentPage;
  int get totalPages => _totalPages;
  bool get hasMore => _hasMore;

  // Last payment for showing receipt
  dynamic _lastPayment;
  dynamic get lastPayment => _lastPayment;

  Future<void> fetchDashboard() async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await _api.getRentalDashboard();
      _dashboardData = response['data'] ?? {};
    } catch (e) {
      debugPrint('Error fetching dashboard: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchProperties() async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await _api.getRentalProperties();
      debugPrint('Fetch properties RAW keys: ${response.keys}');
      debugPrint('Fetch properties RAW response: $response');
      
      List<dynamic> items = [];
      
      // Greedy extraction: Collect ALL lists that look like they contain property-like objects
      void collectLists(obj) {
        if (obj is List) {
          if (obj.isNotEmpty && obj.first is Map && 
              (obj.first.containsKey('name') || obj.first.containsKey('house_number'))) {
            items.addAll(obj);
          }
        } else if (obj is Map) {
          for (final v in obj.values) {
            collectLists(v);
          }
        }
      }
      
      collectLists(response);
      
      // If nothing found via greedy collection, fallback to standard locations
      if (items.isEmpty) {
        final dynamic data = response['data'] ?? response['properties'] ?? response['result'];
        if (data is List) {
          items = data;
        } else if (data is Map && data.containsKey('data') && data['data'] is List) {
          items = data['data'];
        }
      }
      
      // Deduplicate by ID if needed
      final seenIds = <String>{};
      _properties = items.where((item) {
        final id = item['id']?.toString();
        if (id == null) return true;
        if (seenIds.contains(id)) return false;
        seenIds.add(id);
        return true;
      }).toList();

      debugPrint('Loaded ${_properties.length} properties via deep greedy fetch');
    } catch (e) {
      debugPrint('Error fetching properties: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchTenants() async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await _api.getRentalTenants();
      _tenants = response['data'] ?? [];
    } catch (e) {
      debugPrint('Error fetching tenants: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>?> fetchTenantDetails(String tenantId) async {
    try {
      final response = await _api.getRentalTenantDetails(tenantId);
      return response['data'] as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('Error fetching tenant details: $e');
      return null;
    }
  }

  Future<void> fetchBills() async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await _api.getRentalBills();
      final List<dynamic> items = response['data'] ?? [];
      
      // Deduplicate by ID
      final seenIds = <String>{};
      _bills = items.where((item) {
        final id = item['id']?.toString();
        if (id == null) return true;
        if (seenIds.contains(id)) return false;
        seenIds.add(id);
        return true;
      }).toList();
    } catch (e) {
      debugPrint('Error fetching bills: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchPayments() async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await _api.getRentalPayments();
      _payments = response['data'] ?? [];
    } catch (e) {
      debugPrint('Error fetching payments: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchReceipts() async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await _api.getRentalReceipts();
      _receipts = response['data'] ?? [];
    } catch (e) {
      debugPrint('Error fetching receipts: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> dispatchTenantReceipt(String receiptId) async {
    _isLoading = true;
    notifyListeners();
    try {
      await _api.dispatchTenantReceipt(receiptId);
      return true;
    } catch (e) {
      debugPrint('Error dispatching receipt: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchBlocks(String propertyId) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await _api.getRentalBlocks(propertyId);
      _blocks = response['data'] ?? [];
    } catch (e) {
      debugPrint('Error fetching blocks: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, double>> getPropertyRentStats(String propertyId, {String? excludeHouseId}) async {
    try {
      double target = 0;
      if (_selectedProperty != null && _selectedProperty!['id'] == propertyId) {
        target = double.tryParse(_selectedProperty!['default_rent_amount']?.toString() ?? '0') ?? 0;
      } else {
        final propResponse = await _api.getRentalPropertyDetails(propertyId);
        target = double.tryParse(propResponse['data']?['default_rent_amount']?.toString() ?? '0') ?? 0;
      }

      final houses = await fetchPropertyHouses(propertyId);
      double sum = 0;
      for (var h in houses) {
        if (excludeHouseId != null && h['id'] == excludeHouseId) continue;
        sum += double.tryParse(h['rent_amount']?.toString() ?? '0') ?? 0;
      }
      return {'target': target, 'sum': sum};
    } catch (e) {
      debugPrint('Error getting rent stats: $e');
      return {'target': 0, 'sum': 0};
    }
  }

  Future<bool> addBlock(String propertyId, Map<String, dynamic> data) async {
    _isLoading = true;
    notifyListeners();
    try {
      await _api.addRentalBlock(propertyId, data);
      await fetchBlocks(propertyId);
      return true;
    } catch (e) {
      debugPrint('Error adding block: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchArrears() async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await _api.getRentalArrears();
      _arrears = (response['data']?['arrears'] as List?) ?? [];
    } catch (e) {
      debugPrint('Error fetching arrears: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// The one-time password the server made up for the tenant the LAST onboarding created,
  /// to hand over; null when that tenant already had an account (they keep their own).
  String? _lastTemporaryPassword;
  String? get lastTemporaryPassword => _lastTemporaryPassword;

  Future<String?> onboardTenant(Map<String, dynamic> data) async {
    _isLoading = true;
    _lastTemporaryPassword = null;
    notifyListeners();
    try {
      final response = await _api.onboardTenant(data);
      _lastTemporaryPassword = temporaryPasswordOf(response);
      await fetchProperties();
      await fetchTenants();
      await fetchBills();
      final dataObj = response['data'];
      return dataObj?['tenant']?['id']?.toString() ?? dataObj?['id']?.toString() ?? 'success';
    } catch (e) {
      debugPrint('Error onboarding tenant: $e');
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> addHouse(String propertyId, Map<String, dynamic> data) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await _api.addHouseToProperty(propertyId, data);
      await fetchProperties(); // Refresh to show new house
      final dataObj = response['data'];
      return dataObj?['id']?.toString() ?? dataObj?['house']?['id']?.toString() ?? 'success';
    } catch (e) {
      debugPrint('Error adding house: $e');
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> terminateTenantAgreement(String tenantId) async {
    _isLoading = true;
    notifyListeners();
    try {
      await _api.terminateTenant(tenantId);
      await fetchTenants();
      return true;
    } catch (e) {
      debugPrint('Error terminating agreement: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> sendSmsReminder(String billId) async {
    return SmsService.instance.sendBillReminder(billId);
  }

  Future<String?> recordPayment(Map<String, dynamic> data) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await _api.recordRentalPayment(data);
      _lastPayment = response['data'];
      await fetchBills();
      await fetchPayments();
      await fetchDashboard();
      return response['data']?['id']?.toString() ?? 'success';
    } catch (e) {
      debugPrint('Error recording payment: $e');
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> addProperty(Map<String, dynamic> data, {File? image}) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await _api.addRentalProperty(data, image: image);
      await fetchProperties();
      final dataObj = response['data'];
      return dataObj?['id']?.toString() ?? dataObj?['property']?['id']?.toString() ?? 'success';
    } catch (e) {
      debugPrint('Error adding property: $e');
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchPropertyDetails(String propertyId) async {
    if (propertyId.isEmpty) return; // Prevention
    _isLoading = true;
    notifyListeners();
    try {
      final response = await _api.getRentalPropertyDetails(propertyId);
      if (response['data'] is Map<String, dynamic>) {
        _selectedProperty = response['data'];
      } else {
        debugPrint('fetchPropertyDetails: Expected Map but got ${response['data'].runtimeType}');
      }
    } catch (e) {
      debugPrint('Error fetching property details: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchPropertyStats() async {
    try {
      final response = await _api.getRentalPropertyStats();
      _propertyStats = response['data'];
      notifyListeners();
    } catch (e) {
      debugPrint('Error fetching property stats: $e');
    }
  }

  Future<void> fetchPropertiesWithPagination(
      {String? search, String? status, int page = 1}) async {
    if (page > 1 && !_hasMore) return;

    _isLoading = true;
    notifyListeners();
    try {
      final response = await _api.getRentalPropertiesPaginated(
          page: page, search: search, status: status);
      debugPrint('Fetch properties paginated (page $page) RAW keys: ${response.keys}');
      
      List<dynamic> items = [];
      Map<String, dynamic>? paginationMap;

      // Check for standard Laravel pagination structure first (root level 'data' and sibling 'pagination')
      if (response.containsKey('pagination') && response['pagination'] is Map &&
          response.containsKey('data') && response['data'] is List) {
        final pagination = response['pagination'] as Map<String, dynamic>;
        items = List<dynamic>.from(response['data'] as List);
        _currentPage = pagination['current_page'] ?? page;
        _totalPages = pagination['last_page'] ?? _currentPage;
        _hasMore = _currentPage < _totalPages;
        paginationMap = response; // Mark as resolved so greedy parser doesn't collect it again
      } else {
        // 1. Deeply look for pagination metadata with verification (Legacy/fallback)
        void findPagination(obj) {
          if (obj is Map) {
            if (obj.containsKey('data') && obj['data'] is List && obj.containsKey('current_page')) {
              // Verify this list contains property-like objects
              final list = obj['data'] as List;
              if (list.isEmpty || (list.first is Map && 
                  (list.first.containsKey('name') || list.first.containsKey('house_number')))) {
                paginationMap = obj as Map<String, dynamic>;
                return;
              }
            }
            for (final v in obj.values) {
              if (v is Map || v is List) findPagination(v);
              if (paginationMap != null) return;
            }
          } else if (obj is List) {
            for (final v in obj) {
              findPagination(v);
              if (paginationMap != null) return;
            }
          }
        }

        findPagination(response);

        if (paginationMap != null) {
          items = List<dynamic>.from(paginationMap!['data'] as List);
          _currentPage = paginationMap!['current_page'] ?? page;
          _totalPages = paginationMap!['last_page'] ?? _currentPage;
          _hasMore = _currentPage < _totalPages;
        } else {
          _hasMore = false;
        }
      }

      // 2. Deeply look for ANY other lists and merge them (Greedy Collection)
      void collectMoreItems(obj) {
        if (obj is List) {
          if (obj.isNotEmpty && obj.first is Map && 
              (obj.first.containsKey('name') || obj.first.containsKey('house_number'))) {
            for (final item in obj) {
              if (!items.contains(item)) {
                items.add(item);
              }
            }
          }
        } else if (obj is Map && obj != paginationMap) {
          for (final v in obj.values) {
            collectMoreItems(v);
          }
        }
      }

      collectMoreItems(response);

      // 3. Safeguard: if items is empty, stop paging
      if (items.isEmpty) {
        _hasMore = false;
        if (page == 1) _properties = [];
        return;
      }

      // 4. Deduplicate by ID
      final seenIds = <String>{};
      final uniqueItems = items.where((item) {
        final id = (item is Map) ? (item['id']?.toString() ?? item['name']?.toString() ?? '') : '';
        if (id == '') return true;
        if (seenIds.contains(id)) return false;
        seenIds.add(id);
        return true;
      }).toList();

      if (page == 1) {
        _properties = uniqueItems;
      } else {
        final existingIds = _properties.map((p) => (p is Map) ? (p['id']?.toString() ?? p['name']?.toString() ?? '') : '').toSet();
        int addedCount = 0;
        for (final item in uniqueItems) {
          final id = (item is Map) ? (item['id']?.toString() ?? item['name']?.toString() ?? '') : '';
          if (!existingIds.contains(id)) {
            _properties.add(item);
            addedCount++;
          }
        }
        if (addedCount == 0) _hasMore = false;
      }
      debugPrint('Loaded ${_properties.length} properties. More: $_hasMore');
    } catch (e) {
      debugPrint('Error fetching properties: $e');
      _hasMore = false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void resetPagination() {
    _currentPage = 1;
    _totalPages = 1;
    _hasMore = true;
    _properties = [];
  }

  Future<String?> updateProperty(String propertyId, Map<String, dynamic> data,
      {File? image}) async {
    _isLoading = true;
    notifyListeners();
    try {
      await _api.updateRentalProperty(propertyId, data, image: image);
      await fetchProperties();
      return null;
    } catch (e) {
      debugPrint('Error updating property: $e');
      if (e is ApiException) {
        return e.message;
      }
      return e.toString().replaceAll('ApiException: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> deleteProperty(String propertyId) async {
    _isLoading = true;
    notifyListeners();
    try {
      await _api.deleteRentalProperty(propertyId);
      _properties.removeWhere((p) => p['id'] == propertyId);
      return true;
    } catch (e) {
      debugPrint('Error deleting property: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>?> fetchHouseDetails(String houseId) async {
    try {
      final response = await _api.getHouseDetails(houseId);
      return response['data'];
    } catch (e) {
      debugPrint('Error fetching house details: $e');
      return null;
    }
  }

  Future<String?> createHouse(Map<String, dynamic> data, {List<dynamic>? images}) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await _api.createHouse(data, images: images);
      await fetchProperties();
      final dataObj = response['data'];
      return dataObj?['id']?.toString() ?? dataObj?['house']?['id']?.toString() ?? 'success';
    } catch (e) {
      debugPrint('Error creating house: $e');
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> updateHouse(String houseId, Map<String, dynamic> data, {List<dynamic>? images}) async {
    _isLoading = true;
    notifyListeners();
    try {
      await _api.updateHouse(houseId, data, images: images);
      return true;
    } catch (e) {
      debugPrint('Error updating house: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> deleteHouse(String houseId) async {
    _isLoading = true;
    notifyListeners();
    try {
      await _api.deleteHouse(houseId);
      await fetchProperties();
      return true;
    } catch (e) {
      debugPrint('Error deleting house: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<List<dynamic>> fetchPropertyHouses(String propertyId) async {
    try {
      final response = await _api.getPropertyHouses(propertyId);
      return response['data'] ?? [];
    } catch (e) {
      debugPrint('Error fetching property houses: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> fetchOccupancyReport() async {
    try {
      final response = await _api.getOccupancyReport();
      return response['data'];
    } catch (e) {
      debugPrint('Error fetching occupancy: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> fetchRevenueReport(String period) async {
    try {
      final response = await _api.getRevenueReport(period: period);
      return response['data'];
    } catch (e) {
      debugPrint('Error fetching revenue report: $e');
      return null;
    }
  }

  Future<bool> updateTenantStatus(String tenantId, String status) async {
    _isLoading = true;
    notifyListeners();
    try {
      await _api.updateTenantStatus(tenantId, status);
      await fetchTenants();
      return true;
    } catch (e) {
      debugPrint('Error updating tenant status: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> terminateTenant(String tenantId) async {
    _isLoading = true;
    notifyListeners();
    try {
      await _api.terminateTenant(tenantId);
      await fetchTenants();
      return true;
    } catch (e) {
      debugPrint('Error terminating tenant: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  List<dynamic> searchTenants(String query) {
    if (query.isEmpty) return _tenants;
    return _tenants.where((tenant) {
      final name = (tenant['name'] ?? '').toString().toLowerCase();
      final phone = (tenant['phone_number'] ?? '').toString().toLowerCase();
      final search = query.toLowerCase();
      return name.contains(search) || phone.contains(search);
    }).toList();
  }

  // Agreement methods
  List<dynamic> _agreements = [];
  List<dynamic> get agreements => _agreements;

  Future<void> fetchAgreements({String? status, String? search}) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await _api.getAgreements(status: status, search: search);
      final List<dynamic> items = response['data'] ?? [];
      
      // Deduplicate by ID
      final seenIds = <String>{};
      _agreements = items.where((item) {
        final id = item['id']?.toString();
        if (id == null) return true;
        if (seenIds.contains(id)) return false;
        seenIds.add(id);
        return true;
      }).toList();
    } catch (e) {
      debugPrint('Error fetching agreements: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> createAgreement(Map<String, dynamic> data, {File? document}) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await _api.createAgreement(data);
      
      // Attempt to upload document if provided and agreement created
      String? agreementId;
      if (response['data'] != null) {
          agreementId = response['data']['id']?.toString();
      }
      agreementId ??= response['id']?.toString();

      if (document != null && agreementId != null) {
        try {
          await _api.uploadAgreementDocument(agreementId, document, 'signed_contract');
        } catch (e) {
          debugPrint('Error uploading agreement document: $e');
          // We don't fail the entire process if upload fails, but warn ideally
        }
      }
      
      await fetchAgreements();
      return agreementId ?? 'success';
    } catch (e) {
      debugPrint('Error creating agreement: $e');
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> renewAgreement(String id, Map<String, dynamic> data) async {
    try {
      await _api.renewAgreement(id, data);
      await fetchAgreements();
      return true;
    } catch (e) {
      debugPrint('Error renewing agreement: $e');
      return false;
    }
  }

  Future<bool> terminateAgreement(String id, String reason) async {
    try {
      await _api.terminateAgreement(id, reason);
      await fetchAgreements();
      return true;
    } catch (e) {
      debugPrint('Error terminating agreement: $e');
      return false;
    }
  }

  List<dynamic> getExpiringAgreements() {
    return _agreements.where((a) {
      return a['status'] == 'active' && a['end_date'] != null;
    }).toList();
  }
// Tenant House Details
  Map<String, dynamic>? _currentTenantHouse;
  Map<String, dynamic>? get currentTenantHouse => _currentTenantHouse;

  Future<void> fetchCurrentTenantHouse() async {
    _isLoading = true;
    notifyListeners();
    try {
      // Prefer house info from dashboard data if present
      if (_dashboardData.isNotEmpty && _dashboardData['house'] != null) {
        _currentTenantHouse = _dashboardData['house'] as Map<String, dynamic>;
      } else if (_tenants.isNotEmpty) {
        final firstTenant = _tenants.first;
        if (firstTenant['house'] != null) {
          _currentTenantHouse = firstTenant['house'] as Map<String, dynamic>;
        }
      }
    } catch (e) {
      debugPrint('Error fetching tenant house: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

}
