import 'dart:io';
import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../services/sms_service.dart';
import '../widgets/temporary_password_dialog.dart' show temporaryPasswordOf;

class MaintenanceProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();

  List<Map<String, dynamic>> _requests = [];
  List<Map<String, dynamic>> _vendors = [];
  List<Map<String, dynamic>> _marketplaceVendors = [];
  List<Map<String, dynamic>> _preventiveSchedules = [];
  bool _isLoading = false;

  List<Map<String, dynamic>> get requests => _requests;
  List<Map<String, dynamic>> get vendors => _vendors;
  List<Map<String, dynamic>> get marketplaceVendors => _marketplaceVendors;
  List<Map<String, dynamic>> get preventiveSchedules => _preventiveSchedules;
  bool get isLoading => _isLoading;

  Future<void> fetchRequests({String? status, String? propertyId}) async {
    _isLoading = true;
    notifyListeners();

    try {
      final queryParams = <String, String>{};
      if (status != null) queryParams['status'] = status;
      if (propertyId != null) queryParams['property_id'] = propertyId;

      final response = await _apiService.get("/rental/maintenance/requests", queryParams: queryParams);
      if (response['status'] == 'success') {
        _requests = List<Map<String, dynamic>>.from(response['data']);
      }
    } catch (e) {
      debugPrint("Error fetching maintenance requests: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> submitRequest({
    required String propertyId,
    required String category, required String priority, required String description, String? houseId,
    File? photo,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      final fields = {
        'property_id': propertyId,
        if (houseId != null) 'house_id': houseId,
        'category': category,
        'priority': priority,
        'description': description,
      };

      final response = photo != null
          ? await _apiService.postMultipart(
              "/rental/maintenance/requests",
              fields,
              fileField: 'photo',
              file: photo,
            )
          : await _apiService.post("/rental/maintenance/requests", fields);

      if (response['status'] == 'success') {
        await fetchRequests();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint("Error submitting maintenance request: $e");
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchVendors() async {
    try {
      final response = await _apiService.get("/rental/maintenance/vendors");
      if (response['status'] == 'success') {
        _vendors = List<Map<String, dynamic>>.from(response['data']);
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Error fetching vendors: $e");
    }
  }

  Future<void> fetchMarketplaceVendors() async {
    try {
      final response = await _apiService.get("/rental/maintenance/marketplace/vendors");
      if (response['status'] == 'success') {
        _marketplaceVendors = List<Map<String, dynamic>>.from(response['data']);
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Error fetching marketplace vendors: $e");
    }
  }

  Future<bool> saveToRoster(String vendorId) async {
    try {
      final response = await _apiService.post("/rental/maintenance/vendors/$vendorId/save", {});
      if (response['status'] == 'success') {
        await fetchVendors(); 
        return true;
      }
      return false;
    } catch (e) {
      debugPrint("Error saving to roster: $e");
      return false;
    }
  }

  Future<bool> removeFromRoster(String vendorId) async {
    try {
      final response = await _apiService.post("/rental/maintenance/vendors/$vendorId/remove", {});
      if (response['status'] == 'success') {
        await fetchVendors(); 
        return true;
      }
      return false;
    } catch (e) {
      debugPrint("Error removing from roster: $e");
      return false;
    }
  }

  /// The one-time password the server made up for the fundi the LAST addVendor created,
  /// to hand over; null when that fundi already had a sign-in.
  String? _lastTemporaryPassword;
  String? get lastTemporaryPassword => _lastTemporaryPassword;

  Future<String?> addVendor({
    required String name,
    required String phone,
    String? specialty,
    String? email,
    String? address,
    String? businessName,
    String? experience,
  }) async {
    _lastTemporaryPassword = null;
    try {
      final response = await _apiService.post("/rental/maintenance/vendors", {
        'name': name,
        'phone': phone,
        'specialty': specialty,
        'email': email,
        'address': address,
        'business_name': businessName,
        'experience': experience,
      });
      if (response['status'] == 'success' || response['status'] == 201) {
        _lastTemporaryPassword = temporaryPasswordOf(response);
        await fetchVendors();
        return null;
      }
      return response['message']?.toString() ?? "Imeshindikana kuongeza fundi";
    } catch (e) {
      debugPrint("Error adding vendor: $e");
      if (e.toString().contains("ApiException")) {
         return e.toString().replaceAll("Exception: ApiException: ", "");
      }
      return e.toString();
    }
  }

  Future<bool> assignWorkOrder({
    required String requestId,
    required String vendorId,
    required String title,
    String? instructions,
    double? estimatedCost,
    DateTime? scheduledDate,
  }) async {
    try {
      final response = await _apiService.post("/rental/maintenance/requests/$requestId/assign", {
        'vendor_id': vendorId,
        'title': title,
        'instructions': instructions,
        'estimated_cost': estimatedCost,
        'scheduled_date': scheduledDate?.toIso8601String().split('T')[0],
      });
      if (response['status'] == 'success') {
        await fetchRequests();
        // Notify vendor via SMS
        await SmsService.instance.notifyVendor(vendorId, requestId);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint("Error assigning work order: $e");
      return false;
    }
  }

  Future<bool> updateStatus({
    required String requestId,
    required String status,
    double? actualCost,
    DateTime? completionDate,
  }) async {
    try {
      final response = await _apiService.put("/rental/maintenance/requests/$requestId/status", {
        'status': status,
        if (actualCost != null) 'actual_cost': actualCost,
        if (completionDate != null) 'completion_date': completionDate.toIso8601String().split('T')[0],
      });
      if (response['status'] == 'success') {
        await fetchRequests();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint("Error updating status: $e");
      return false;
    }
  }

  Future<void> fetchPreventiveSchedules() async {
    try {
      final response = await _apiService.get("/rental/maintenance/preventive");
      if (response['status'] == 'success') {
        _preventiveSchedules = List<Map<String, dynamic>>.from(response['data']);
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Error fetching preventive schedules: $e");
    }
  }
}
