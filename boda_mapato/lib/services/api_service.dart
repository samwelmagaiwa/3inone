import 'dart:convert';
import 'dart:io';
// ignore_for_file: avoid_dynamic_calls, avoid_positional_boolean_parameters, cascade_invocations, avoid_catches_without_on_clauses
import 'package:flutter/foundation.dart';
import 'http_client.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../models/dashboard_report.dart';
import '../models/revenue_report.dart';
import 'auth_events.dart';
import 'localization_service.dart';
import '../utils/server_message.dart';

class ApiService {
  // API Configuration - Updated for Laravel backend
  // For development on localhost (when running flutter on same machine)
  // Use centralized API configuration
  // See lib/config/api_config.dart
  static String get baseUrl => ApiConfig.baseUrl;
  static String get webBaseUrl => ApiConfig.webBaseUrl;

  // Alternative URLs for different environments:
  // For real device testing: "http://192.168.1.124:8000/api";
  // For Android emulator: "http://10.0.2.2:8000/api";
  // For iOS simulator: "http://127.0.1:8000/api";

  // Timeout duration
  static Duration get timeoutDuration => ApiConfig.timeoutDuration;
  static const Duration connectionTimeout = Duration(seconds: 10);

  // Headers
  Map<String, String> get _headers => <String, String>{
        "Content-Type": "application/json",
        "Accept": "application/json",
      };

  /// Which service the screens in front of the person belong to: 'salon' while the salon is open, else null (the shop).
  /// Sent with every request so the server keeps the salon's books apart from the shop's.
  static String? activeService;

  /// The branch (of a salon, a shop or a depot) being looked at / worked in (its id), or null for all branches. Sent as `X-Branch`.
  static int? activeBranch;

  /// The chosen branch's name, for showing where figures come from.
  static String? activeBranchName;

  /// Which service the chosen branch belongs to ('inventory', 'salon', 'transport', 'rental'). Each service has its own
  /// list of branches, so the server ignores a branch chosen in another one; null = the service now open.
  static String? activeBranchService;

  /// Look at one branch of [service] (or all of them when [id] is null).
  static void chooseBranch(final int? id, final String? name, {final String? service}) {
    activeBranch = id;
    activeBranchName = id == null ? null : name;
    activeBranchService = id == null ? null : service;
  }

  /// Back to "all branches": a branch of one service must never follow the person into another.
  static void clearBranch() => chooseBranch(null, null);

  Future<Map<String, String>> get _authHeaders async {
    final String? token = await _getStoredToken();
    return <String, String>{
      ..._headers,
      if (token != null) "Authorization": "Bearer $token",
      if (activeService != null) "X-Service": activeService!,
      if (activeBranch != null) "X-Branch": '$activeBranch',
      if (activeBranch != null) "X-Branch-Service": activeBranchService ?? activeService ?? 'inventory',
    };
  }

  // Get token from SharedPreferences (same key as AuthService)
  Future<String?> _getStoredToken() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString("auth_token");
  }

  // Initialize with stored token (for backward compatibility)
  Future<void> initialize() async {
    // Token is now fetched dynamically from SharedPreferences
    // No need to store it in instance variable
  }

  // Quick connectivity test with shorter timeout
  Future<bool> testConnectivity() async {
    try {
      final http.Response response = await http
          .get(
            Uri.parse("$baseUrl/health"),
            headers: _headers,
          )
          .timeout(connectionTimeout);
      return response.statusCode == 200;
    } on Exception {
      return false;
    }
  }

  // Set auth token
  Future<void> setAuthToken(final String token) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString("auth_token", token);
  }

  // Clear auth token
  Future<void> clearAuthToken() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove("auth_token");
  }

  // Generic HTTP methods
  Future<Map<String, dynamic>> get(
    final String endpoint, {
    final bool requireAuth = true,
    final Map<String, dynamic>? queryParams,
  }) async {
    return _get(endpoint, requireAuth: requireAuth, queryParams: queryParams);
  }

  // Safe GET that returns null instead of throwing on API errors (e.g., 404)
  Future<Map<String, dynamic>?> getOrNull(
    final String endpoint, {
    final bool requireAuth = true,
  }) async {
    try {
      return await _get(endpoint, requireAuth: requireAuth);
    } on ApiException catch (e) {
      if (kDebugMode && ApiConfig.enableHttpLogs) {
        debugPrint('HTTP GET getOrNull failed -> $endpoint :: ${e.message}');
      }
      return null;
    } on Exception catch (e) {
      if (kDebugMode && ApiConfig.enableHttpLogs) {
        debugPrint('HTTP GET getOrNull failed -> $endpoint :: $e');
      }
      return null;
    }
  }

  // Tolerant GET: returns null on 404 without throwing (prevents debugger breaks).
  Future<Map<String, dynamic>?> getMaybe(
    final String endpoint, {
    final bool requireAuth = true,
  }) async {
    try {
      final Map<String, String> headers =
          requireAuth ? await _authHeaders : _headers;
      if (requireAuth && !headers.containsKey('Authorization')) {
        return null;
      }
      final http.Response response = await http
          .get(
            Uri.parse("$baseUrl$endpoint"),
            headers: headers,
          )
          .timeout(timeoutDuration);
      if (response.statusCode == 404) {
        return null;
      }
      return _handleResponse(response);
    } on Exception {
      return null;
    }
  }

  // Helper: try multiple endpoints sequentially (useful when backend routes differ)
  Future<Map<String, dynamic>> _getFirst(List<String> endpoints,
      {bool requireAuth = true}) async {
    ApiException? last404;
    for (final String e in endpoints) {
      try {
        return await _get(e, requireAuth: requireAuth);
      } on ApiException catch (err) {
        final String m = err.message.toLowerCase();
        if (m.contains('404') ||
            m.contains('haipatikani') ||
            m.contains('not found')) {
          last404 = err;
          continue;
        }
        rethrow;
      }
    }
    throw last404 ?? ApiException('Rasilimali haipatikani');
  }

  Future<Map<String, dynamic>> _postFirst(
      List<String> endpoints, Map<String, dynamic> data,
      {bool requireAuth = true}) async {
    ApiException? last404;
    for (final String e in endpoints) {
      try {
        if (kDebugMode && ApiConfig.enableHttpLogs) {
          debugPrint('HTTP POST try -> $e');
        }
        return await _post(e, data, requireAuth: requireAuth);
      } on ApiException catch (err) {
        final String m = err.message.toLowerCase();
        if (m.contains('404') ||
            m.contains('haipatikani') ||
            m.contains('not found')) {
          last404 = err;
          continue;
        }
        rethrow;
      }
    }
    throw last404 ?? ApiException('Rasilimali haipatikani');
  }

  Future<Map<String, dynamic>> _putFirst(
      List<String> endpoints, Map<String, dynamic> data) async {
    ApiException? last404;
    for (final String e in endpoints) {
      try {
        return await _put(e, data);
      } on ApiException catch (err) {
        final String m = err.message.toLowerCase();
        if (m.contains('404') ||
            m.contains('haipatikani') ||
            m.contains('not found')) {
          last404 = err;
          continue;
        }
        rethrow;
      }
    }
    throw last404 ?? ApiException('Rasilimali haipatikani');
  }

  Future<Map<String, dynamic>> _deleteFirst(List<String> endpoints) async {
    ApiException? last404;
    for (final String e in endpoints) {
      try {
        return await _delete(e);
      } on ApiException catch (err) {
        final String m = err.message.toLowerCase();
        if (m.contains('404') ||
            m.contains('haipatikani') ||
            m.contains('not found')) {
          last404 = err;
          continue;
        }
        rethrow;
      }
    }
    throw last404 ?? ApiException('Rasilimali haipatikani');
  }

  /// Any file the server sends back (a CSV or PDF export), as bytes. A refusal throws the server's own words.
  Future<Uint8List> getFileBytes(final String endpoint) async {
    try {
      final http.Response response = await http.get(Uri.parse("$baseUrl$endpoint"), headers: await _authHeaders).timeout(timeoutDuration);
      if (response.statusCode == 200) return response.bodyBytes;
      String message = "Server returned status ${response.statusCode}";
      try {
        final dynamic body = jsonDecode(response.body);
        if (body is Map && body['message'] != null) message = '${body['message']}';
      } on FormatException {
        // not JSON: keep the status text
      }
      throw ApiException(message);
    } on SocketException catch (e) {
      throw ApiException(LocalizationService.instance.translateWith('no_network_connection', <Object?>[e.message]));
    }
  }

  // Fetch raw PDF bytes from API (application/pdf)
  Future<Uint8List> getPdf(
    final String endpoint, {
    final bool requireAuth = true,
  }) async {
    try {
      final Map<String, String> headers =
          requireAuth ? await _authHeaders : _headers;
      final http.Response response = await http.get(
        Uri.parse("$baseUrl$endpoint"),
        headers: {
          ...headers,
          "Accept": "application/pdf",
        },
      ).timeout(timeoutDuration);

      if (response.statusCode == 200 &&
          (response.headers['content-type']?.contains('application/pdf') ??
              false)) {
        return response.bodyBytes;
      }
      throw ApiException("Server returned status ${response.statusCode}");
    } on SocketException catch (e) {
      throw ApiException(LocalizationService.instance.translateWith('no_network_connection', <Object?>[e.message]));
    } on Exception catch (e) {
      throw ApiException(LocalizationService.instance.translateWith('error_getting_the_pdf', <Object?>[e]));
    }
  }

  Future<Map<String, dynamic>> post(
    final String endpoint,
    final Map<String, dynamic> data, {
    final bool requireAuth = true,
  }) async {
    return _post(endpoint, data, requireAuth: requireAuth);
  }

  Future<Map<String, dynamic>> put(
    final String endpoint,
    final Map<String, dynamic> data,
  ) async {
    return _put(endpoint, data);
  }

  Future<Map<String, dynamic>> delete(final String endpoint) async {
    return _delete(endpoint);
  }

  Future<Map<String, dynamic>> _get(
    final String endpoint, {
    final bool requireAuth = true,
    final Map<String, dynamic>? queryParams,
  }) async {
    try {
      final Map<String, String> headers =
          requireAuth ? await _authHeaders : _headers;

      // If auth is required but no token present, avoid hitting the server at all
      if (requireAuth && !headers.containsKey("Authorization")) {
        throw ApiException(LocalizationService.instance.translate('not_allowed_please_log_in_again'));
      }

      final Uri uri = Uri.parse("$baseUrl$endpoint").replace(
        queryParameters:
            queryParams?.map((key, value) => MapEntry(key, value.toString())),
      );

      final http.Response response = await _sharedGet(uri, headers);

      return _handleResponse(response);
    } on SocketException catch (e) {
      throw ApiException(LocalizationService.instance.translateWith('no_network_connection', <Object?>[e.message]));
    } on HttpException catch (e) {
      throw ApiException(LocalizationService.instance.translateWith('server_error_2', <Object?>[e.message]));
    } on FormatException catch (e) {
      throw ApiException(LocalizationService.instance.translateWith('server_answer_unreadable', <Object?>[e.message]));
    } on ApiException {
      rethrow;
    } on Exception catch (e) {
      throw ApiException(LocalizationService.instance.translateWith('unknown_error_2', <Object?>[e]));
    }
  }

  /// GETs that are on their way right now, by who is asking and what for. Opening a screen makes several
  /// providers ask for the same thing in the same moment (the business settings, the crate types, the sales
  /// officers ...): they now share one request. Only while it is in flight: the moment it answers it is forgotten,
  /// so nobody ever receives an old answer. Each caller decodes the response for itself.
  static final Map<String, Future<http.Response>> _inFlight = <String, Future<http.Response>>{};

  Future<http.Response> _sharedGet(final Uri uri, final Map<String, String> headers) {
    final String key = '${headers["Authorization"] ?? ""} ${headers["X-Service"] ?? ""} $uri';
    final Future<http.Response>? running = _inFlight[key];
    if (running != null) return running;

    final Future<http.Response> request = http.get(uri, headers: headers).timeout(timeoutDuration);
    _inFlight[key] = request;
    // Block bodies, not arrows: `remove` hands back the request itself, and returning a FAILED request from the
    // error handler made this derived future fail too, with nobody listening (an uncaught error on every timeout).
    request.then<void>(
      (_) {
        _inFlight.remove(key);
      },
      onError: (final Object _) {
        _inFlight.remove(key);
      },
    );
    return request;
  }

  Future<Map<String, dynamic>> _post(
    final String endpoint,
    final Map<String, dynamic> data, {
    final bool requireAuth = true,
  }) async {
    try {
      final Map<String, String> headers =
          requireAuth ? await _authHeaders : _headers;
      if (requireAuth && !headers.containsKey("Authorization")) {
        throw ApiException(LocalizationService.instance.translate('not_allowed_please_log_in_again'));
      }

      final String fullUrl = "$baseUrl$endpoint";
      if (kDebugMode && ApiConfig.enableHttpLogs) {
        debugPrint('HTTP POST -> $fullUrl');
        debugPrint('Body: ${json.encode(data)}');
      }
      final http.Response response = await http
          .post(
            Uri.parse(fullUrl),
            headers: headers,
            body: json.encode(data),
          )
          .timeout(timeoutDuration);

      return _handleResponse(response);
    } on SocketException catch (e) {
      throw ApiException(LocalizationService.instance.translateWith('no_network_connection', <Object?>[e.message]));
    } on HttpException catch (e) {
      throw ApiException(LocalizationService.instance.translateWith('server_error_2', <Object?>[e.message]));
    } on FormatException catch (e) {
      throw ApiException(LocalizationService.instance.translateWith('server_answer_unreadable', <Object?>[e.message]));
    } on ApiException {
      rethrow;
    } on Exception catch (e) {
      throw ApiException(LocalizationService.instance.translateWith('unknown_error_2', <Object?>[e]));
    }
  }

  Future<Map<String, dynamic>> _put(
    final String endpoint,
    final Map<String, dynamic> data,
  ) async {
    try {
      final Map<String, String> headers = await _authHeaders;
      if (!headers.containsKey("Authorization")) {
        throw ApiException(LocalizationService.instance.translate('not_allowed_please_log_in_again'));
      }
      final http.Response response = await http
          .put(
            Uri.parse("$baseUrl$endpoint"),
            headers: headers,
            body: json.encode(data),
          )
          .timeout(timeoutDuration);

      return _handleResponse(response);
    } on SocketException catch (e) {
      throw ApiException(LocalizationService.instance.translateWith('no_network_connection', <Object?>[e.message]));
    } on HttpException catch (e) {
      throw ApiException(LocalizationService.instance.translateWith('server_error_2', <Object?>[e.message]));
    } on FormatException catch (e) {
      throw ApiException(LocalizationService.instance.translateWith('server_answer_unreadable', <Object?>[e.message]));
    } on ApiException {
      rethrow;
    } on Exception catch (e) {
      throw ApiException(LocalizationService.instance.translateWith('unknown_error_2', <Object?>[e]));
    }
  }

  Future<Map<String, dynamic>> _delete(final String endpoint) async {
    try {
      final Map<String, String> headers = await _authHeaders;
      if (!headers.containsKey("Authorization")) {
        throw ApiException(LocalizationService.instance.translate('not_allowed_please_log_in_again'));
      }
      final http.Response response = await http
          .delete(
            Uri.parse("$baseUrl$endpoint"),
            headers: headers,
          )
          .timeout(timeoutDuration);

      return _handleResponse(response);
    } on SocketException catch (e) {
      throw ApiException(LocalizationService.instance.translateWith('no_network_connection', <Object?>[e.message]));
    } on HttpException catch (e) {
      throw ApiException(LocalizationService.instance.translateWith('server_error_2', <Object?>[e.message]));
    } on FormatException catch (e) {
      throw ApiException(LocalizationService.instance.translateWith('server_answer_unreadable', <Object?>[e.message]));
    } on ApiException {
      rethrow;
    } on Exception catch (e) {
      throw ApiException(LocalizationService.instance.translateWith('unknown_error_2', <Object?>[e]));
    }
  }

  // Payments APIs
  Future<void> markPaymentAsPaid(final String paymentId) async {
    await _post("/admin/payments/$paymentId/mark-paid", <String, dynamic>{});
  }

  // Drivers APIs for import/create

  // Vehicles APIs for import/create

  // Driver payment requests (driver app)
  Future<void> createPaymentRequest(final Map<String, dynamic> data) async {
    await _post("/driver/payment-requests", data);
  }

  Map<String, dynamic> _handleResponse(final http.Response response) {
    Map<String, dynamic> data;

    try {
      data = json.decode(response.body);
    } on Exception {
      throw ApiException(LocalizationService.instance.translate('the_server_s_answer_is_not'));
    }

    // Debug logging in debug mode only
    assert(() {
      if (ApiConfig.enableHttpLogs) {
        debugPrint(
            '[API] ${response.request?.method} ${response.request?.url} -> ${response.statusCode}');
        if (response.statusCode >= 400) {
          debugPrint('[API] body: ${response.body}');
        }
      }
      return true;
    }(), 'API debug logging');

    switch (response.statusCode) {
      case 200:
      case 201:
        return data;
      case 400:
        throw ApiException(data["message"] ?? LocalizationService.instance.translate('invalid_request'));
      case 401:
        // Broadcast unauthorized — AuthProvider will verify the token before
        // actually logging the user out (prevents false logouts from transient
        // 401s on polling or non-critical endpoints).
        AuthEvents.instance.emit(AuthEvent.unauthorized);
        throw ApiException(LocalizationService.instance.translate('not_allowed_please_log_in_again'));
      case 402:
        // The business's plan ended and the server holds it back until it pays. Tell the app, so it shows
        // "pay to continue" once instead of a string of errors, and opens again by itself after payment.
        final Object? errors402 = data["errors"];
        final String? code402 = errors402 is Map ? errors402["code"]?.toString() : data["code"]?.toString();
        if (code402 == "subscription_expired") {
          AuthEvents.instance.emit(AuthEvent.subscriptionExpired);
        }
        throw ApiException(data["message"] ?? LocalizationService.instance.translate('subscription_ended_pay'));
      case 403:
        // A service this business was never given deserves its own message, not
        // a generic "not allowed" that looks like a bug.
        if (data["code"] == "service_not_assigned") {
          throw ApiException(data["message"] ??
              LocalizationService.instance.translate('your_account_has_not_been_given'));
        }
        throw ApiException(LocalizationService.instance.translate('you_are_not_allowed_to_access'));
      case 404:
        throw ApiException("Rasilimali haipatikani");
      case 409:
        // e.g. "already approved" / "inventory is held by another business":
        // the server's explanation is what the user needs.
        throw ApiException(
            data["message"] ?? LocalizationService.instance.translate('the_request_conflicts_with_the_current'));
      case 422:
        final Map<String, dynamic>? errors =
            data["errors"] as Map<String, dynamic>?;
        if (errors != null && errors.isNotEmpty) {
          final firstError = errors.values.first;
          // Only a SENTENCE is a message. `errors` can also carry data (the products a sale ran short of, as maps):
          // printing that would put "{product_id: 7, ...}" on the screen, so the server's own `message` is used then.
          if (firstError is List && firstError.isNotEmpty && firstError.first is String) {
            throw ApiException(firstError.first as String);
          }
        }
        throw ApiException(data["message"] ?? LocalizationService.instance.translate('invalid_data'));
      case 500:
        throw ApiException(data["message"] ?? LocalizationService.instance.translate('internal_server_error'));
      default:
        throw ApiException(data["message"] ??
            LocalizationService.instance.translateWith('unknown_error_2', <Object?>[response.statusCode]));
    }
  }

  // Authentication endpoints
  Future<Map<String, dynamic>> login({
    required final String email,
    required final String password,
    final String? phoneNumber,
  }) async {
    final Map<String, dynamic> requestData = <String, dynamic>{
      if (email.isNotEmpty) "email": email,
      "password": password,
    };

    // Add phone_number if provided (drivers often login via phone)
    if (phoneNumber != null && phoneNumber.isNotEmpty) {
      requestData["phone_number"] = phoneNumber;
    }

    // Try multiple possible auth endpoints (admin and driver guards)
    final List<String> endpoints = <String>[
      "/auth/login", // default (admin/user)
      "/driver/login", // driver guard variant A
      "/driver/auth/login", // driver guard variant B
      "/auth/driver/login", // driver under auth namespace
    ];

    final Map<String, dynamic> response =
        await _postFirst(endpoints, requestData, requireAuth: false);

    // Handle nested response structure: response.data.token or response.token
    String? token;
    if (response["data"] is Map && response["data"]["token"] != null) {
      token = response["data"]["token"];
    } else if (response["token"] != null) {
      token = response["token"];
    }

    if (token != null) {
      await setAuthToken(token);
    }

    return response;
  }

  Future<Map<String, dynamic>> logout() async {
    try {
      final Map<String, dynamic> response =
          await _post("/auth/logout", <String, dynamic>{});
      await clearAuthToken();
      return response;
    } on Exception {
      // Clear token even if logout fails
      await clearAuthToken();
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getCurrentUser() async => _get("/auth/user");

  // Business registrations -- super admin only. A business owner registers
  // themselves (AuthService.registerBusiness); the super admin reviews the
  // details here and assigns the services, which switches the owner's login on.
  Future<Map<String, dynamic>> getBusinessRegistrations({
    final String status = "pending",
    final String? query,
  }) async =>
      _get(
        "/admin/registrations",
        queryParams: <String, dynamic>{
          "status": status,
          "per_page": 100,
          if (query != null && query.trim().isNotEmpty) "q": query.trim(),
        },
      );

  /// [allowUnverified]: approve even though the applicant never confirmed their phone number
  /// (the server refuses that unless it is asked for on purpose).
  ///
  /// [plan] and [validUntil] set the business's plan from day one; left out, the server starts a trial.
  Future<Map<String, dynamic>> approveBusinessRegistration(
    final String id,
    final List<String> serviceTypes, {
    final bool allowUnverified = false,
    final String? plan,
    final DateTime? validUntil,
    final String? inventoryType,
  }) async =>
      _post("/admin/registrations/$id/approve", <String, dynamic>{
        "service_types": serviceTypes,
        if (inventoryType != null) "inventory_type": inventoryType,
        if (allowUnverified) "allow_unverified": true,
        if (plan != null) "plan": plan,
        if (validUntil != null) "valid_until": _dateOnly(validUntil),
      });

  static String _dateOnly(final DateTime d) =>
      "${d.year.toString().padLeft(4, "0")}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}";

  // The business itself: name, address, TIN, logo (what receipts and texts say) and its plan.
  // Anyone who works for the business reads it; only its owner edits the profile. Billing is
  // read-only here and changed only by a super admin (updateBusiness).
  Future<Map<String, dynamic>> getMyBusiness() async => _get("/business");

  Future<Map<String, dynamic>> updateMyBusiness(final Map<String, dynamic> fields) async =>
      _put("/business", fields);

  Future<Map<String, dynamic>> removeBusinessLogo() async => _delete("/business/logo");

  Future<Map<String, dynamic>> uploadBusinessLogo({
    required final Uint8List bytes,
    required final String filename,
  }) async {
    final Map<String, String> headers = await _authHeaders;
    if (!headers.containsKey("Authorization")) {
      throw ApiException(LocalizationService.instance.translate('not_allowed_please_log_in_again'));
    }
    final http.MultipartRequest request = http.MultipartRequest("POST", Uri.parse("$baseUrl/business/logo"));
    final Map<String, String> h = Map<String, String>.of(headers)..remove("Content-Type");
    request.headers.addAll(h);
    request.files.add(http.MultipartFile.fromBytes("logo", bytes, filename: filename));
    final http.StreamedResponse streamed = await request.send().timeout(timeoutDuration);
    return _handleResponse(await http.Response.fromStream(streamed));
  }

  // Super admin: every business with its owner, services and plan.
  Future<Map<String, dynamic>> getBusinesses({
    final String status = "all",
    final String? plan,
    final String? query,
  }) async =>
      _get(
        "/admin/businesses",
        queryParams: <String, dynamic>{
          "status": status,
          "per_page": 100,
          if (plan != null && plan.isNotEmpty) "plan": plan,
          if (query != null && query.trim().isNotEmpty) "q": query.trim(),
        },
      );

  /// [validUntil] null with [clearValidUntil] true means "no expiry".
  Future<Map<String, dynamic>> updateBusiness(
    final String id, {
    final String? plan,
    final DateTime? validUntil,
    final bool clearValidUntil = false,
  }) async =>
      _put("/admin/businesses/$id", <String, dynamic>{
        if (plan != null) "plan": plan,
        if (validUntil != null) "valid_until": _dateOnly(validUntil),
        if (clearValidUntil) "valid_until": null,
      });

  /// The signed-in business's subscription: plan, start, end, status, and (owner only) what it paid.
  Future<Map<String, dynamic>> getSubscription() async => _get("/business/subscription");

  /// The plans, how many services each covers and what they cost. Public: the registration form reads it before sign-in.
  Future<Map<String, dynamic>> getPlans() async => _get("/plans", requireAuth: false);

  /// Super admin: the same list, for the page where the prices are set.
  Future<Map<String, dynamic>> getPlanPrices() async => _get("/admin/plan-prices");

  /// Super admin: set or clear prices. `{plan: {months: amount}}`; an amount of null clears that price. What is not
  /// mentioned stays as it is.
  Future<Map<String, dynamic>> savePlanPrices(final Map<String, Map<String, double?>> prices) async =>
      _put("/admin/plan-prices", <String, dynamic>{"prices": prices});

  /// Super admin: every business with the SMS sender name it texts under, filtered and counted.
  Future<Map<String, dynamic>> getSmsSenders({
    final String status = "all",
    final String? query,
    final int page = 1,
    final int perPage = 50,
  }) async =>
      _get(
        "/admin/sms-senders",
        queryParams: <String, dynamic>{
          "status": status,
          "page": page,
          "per_page": perPage,
          if (query != null && query.trim().isNotEmpty) "q": query.trim(),
        },
      );

  /// Super admin: set a business's sender name, key and status. Only what [body] holds is changed.
  Future<Map<String, dynamic>> saveSmsSender(final String businessId, final Map<String, dynamic> body) async =>
      _put("/admin/sms-senders/$businessId", body);

  /// Super admin: one real text under the name (and the key typed or saved), to see if the provider accepts it.
  Future<Map<String, dynamic>> testSmsSender(
    final String businessId, {
    final String? phone,
    final String? senderId,
    final String? apiKey,
    final String? apiSecret,
  }) async =>
      _post("/admin/sms-senders/$businessId/test", <String, dynamic>{
        if (phone != null && phone.trim().isNotEmpty) "phone": phone.trim(),
        if (senderId != null && senderId.trim().isNotEmpty) "sender_id": senderId.trim(),
        if (apiKey != null && apiKey.trim().isNotEmpty) "api_key": apiKey.trim(),
        if (apiSecret != null && apiSecret.trim().isNotEmpty) "api_secret": apiSecret.trim(),
      });

  /// Owner: ask for the name customers' phones should show. It waits for the super admin.
  Future<Map<String, dynamic>> requestSmsSender({required final String senderId, final String? displayName}) async =>
      _post("/business/sms-sender", <String, dynamic>{
        "sender_id": senderId.trim(),
        if (displayName != null && displayName.trim().isNotEmpty) "display_name": displayName.trim(),
      });

  /// Owner: take a request that is still waiting back.
  Future<Map<String, dynamic>> withdrawSmsSender() async => _delete("/business/sms-sender");

  /// Super admin: the subscription of one business with every payment recorded for it.
  Future<Map<String, dynamic>> getBusinessPayments(final String id) async => _get("/admin/businesses/$id/payments");

  /// Super admin: record a payment. It moves the paid-until date on (by [months], or to [validUntil]) and opens
  /// a held-back business again at once; the owner is told by text message.
  Future<Map<String, dynamic>> recordBusinessPayment(
    final String id, {
    required final double amount,
    final String? method,
    final String? reference,
    final String? plan,
    final int? months,
    final DateTime? validUntil,
    final String? note,
  }) async =>
      _post("/admin/businesses/$id/payments", <String, dynamic>{
        "amount": amount,
        if (method != null && method.isNotEmpty) "method": method,
        if (reference != null && reference.trim().isNotEmpty) "reference": reference.trim(),
        if (plan != null && plan.isNotEmpty) "plan": plan,
        if (months != null) "months": months,
        if (validUntil != null) "valid_until": _dateOnly(validUntil),
        if (note != null && note.trim().isNotEmpty) "note": note.trim(),
      });

  Future<Map<String, dynamic>> rejectBusinessRegistration(
    final String id,
    final String reason,
  ) async =>
      _post("/admin/registrations/$id/reject", <String, dynamic>{"reason": reason});

  Future<Map<String, dynamic>> refreshToken() async {
    final Map<String, dynamic> response =
        await _post("/auth/refresh", <String, dynamic>{});

    if (response["token"] != null) {
      await setAuthToken(response["token"]);
    }

    return response;
  }

  // Security endpoints
  Future<Map<String, dynamic>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async =>
      _post("/auth/change-password", <String, dynamic>{
        "current_password": currentPassword,
        "new_password": newPassword,
      });

  Future<Map<String, dynamic>> getSecuritySettings() async =>
      _get("/auth/security");

  Future<Map<String, dynamic>> setTwoFactor(bool enabled) async =>
      _post("/auth/two-factor", <String, dynamic>{"enabled": enabled});

  Future<Map<String, dynamic>> getLoginHistory(
          {int page = 1, int limit = 20}) async =>
      _get("/auth/login-history?page=$page&limit=$limit");

  // Dashboard endpoints
  // Summary dashboard (AdminController::dashboard)
  Future<Map<String, dynamic>> getDashboardData() async =>
      _get("/admin/dashboard");
  // Detailed dashboard data (DashboardController::index)
  Future<Map<String, dynamic>> getDashboardDataDetailed() async =>
      _get("/admin/dashboard-data");

  // Driver dashboard (read-only for driver role)
  Future<Map<String, dynamic>> getDriverDashboard() async =>
      _get("/driver/dashboard");

  // Driver self resources
  Future<Map<String, dynamic>> getDriverReceipts(
          {int page = 1, int limit = 20}) async =>
      _get("/driver/receipts?per_page=$limit&page=$page");

  Future<Map<String, dynamic>> getDriverPayments(
      {int page = 1,
      int limit = 50,
      DateTime? startDate,
      DateTime? endDate}) async {
    final List<String> params = <String>["per_page=$limit", "page=$page"];
    if (startDate != null) {
      params.add("start_date=${startDate.toIso8601String().split('T')[0]}");
    }
    if (endDate != null) {
      params.add("end_date=${endDate.toIso8601String().split('T')[0]}");
    }
    final String qs = params.join("&");
    return _get("/driver/payments?$qs");
  }

  Future<Map<String, dynamic>> getDriverDebtRecordsSelf(
      {int page = 1,
      int limit = 50,
      bool onlyPaid = false,
      bool onlyUnpaid = false,
      DateTime? startDate,
      DateTime? endDate}) async {
    final List<String> params = <String>["per_page=$limit", "page=$page"];
    if (onlyPaid) {
      params.add("only_paid=true");
    }
    if (onlyUnpaid) {
      params.add("only_unpaid=true");
    }
    if (startDate != null) {
      params.add("start_date=${startDate.toIso8601String().split('T')[0]}");
    }
    if (endDate != null) {
      params.add("end_date=${endDate.toIso8601String().split('T')[0]}");
    }
    final String qs = params.join("&");
    return _get("/driver/debts/records?$qs");
  }

  Future<Map<String, dynamic>> getDriverPaymentHistory(
      {int page = 1,
      int limit = 200,
      DateTime? startDate,
      DateTime? endDate}) async {
    final List<String> params = <String>["per_page=$limit", "page=$page"];
    if (startDate != null) {
      params.add("start_date=${startDate.toIso8601String().split('T')[0]}");
    }
    if (endDate != null) {
      params.add("end_date=${endDate.toIso8601String().split('T')[0]}");
    }
    final String qs = params.join("&");
    return _get("/driver/payment-history?$qs");
  }

  Future<Map<String, dynamic>> getDriverPaymentsSummary(
      {DateTime? startDate, DateTime? endDate}) async {
    final List<String> params = <String>[];
    if (startDate != null) {
      params.add("start_date=${startDate.toIso8601String().split('T')[0]}");
    }
    if (endDate != null) {
      params.add("end_date=${endDate.toIso8601String().split('T')[0]}");
    }
    final String qs = params.isEmpty ? '' : '?${params.join('&')}';
    return _get("/driver/payments/summary$qs");
  }

  // Aggregated stats (DashboardController::getStats)
  Future<Map<String, dynamic>> getDashboardStats() async =>
      _get("/admin/dashboard-stats");

  // Token verification helper (wraps /auth/user)
  Future<bool> verifyToken() async {
    try {
      await _get("/auth/user");
      return true;
    } catch (_) {
      return false;
    }
  }

  // Specific dashboard counts from database tables with exact column filtering

  /// Get unpaid debts count from debt_records table WHERE is_paid = 0
  Future<Map<String, dynamic>> getUnpaidDebtsCount() async =>
      _get("/admin/dashboard/unpaid-debts-count");

  /// Get active devices count from devices table WHERE is_active = 1
  Future<Map<String, dynamic>> getActiveDevicesCount() async =>
      _get("/admin/dashboard/active-devices-count");

  /// Get active drivers count from drivers table WHERE is_active = 1
  Future<Map<String, dynamic>> getActiveDriversCount() async =>
      _get("/admin/dashboard/active-drivers-count");

  /// Get generated receipts count from payment_receipts table WHERE receipt_status = 'generated'
  Future<Map<String, dynamic>> getGeneratedReceiptsCount() async =>
      _get("/admin/dashboard/generated-receipts-count");

  /// Get pending receipts count from payments table WHERE receipt_status = 'pending'
  Future<Map<String, dynamic>> getPendingReceiptsCount() async =>
      _get("/admin/dashboard/pending-receipts-count");

  /// Get daily revenue from debt_records (is_paid=1) + payments tables for today
  Future<Map<String, dynamic>> getDailyRevenue() async =>
      _get("/admin/dashboard/daily-revenue");

  /// Get weekly revenue from debt_records (is_paid=1) + payments tables for current week
  Future<Map<String, dynamic>> getWeeklyRevenue() async =>
      _get("/admin/dashboard/weekly-revenue");

  /// Get monthly revenue from debt_records (is_paid=1) + payments tables for current month
  Future<Map<String, dynamic>> getMonthlyRevenue() async =>
      _get("/admin/dashboard/monthly-revenue");

  /// Get comprehensive dashboard data with all database table counts and exact column filtering
  Future<Map<String, dynamic>> getComprehensiveDashboardData() async =>
      _get("/admin/dashboard/comprehensive");

  Future<List<dynamic>> getRevenueChart(
      {final int days = 30, DateTime? startDate, DateTime? endDate}) async {
    // Build date window (defaults to last N days)
    final DateTime end = endDate ?? DateTime.now();
    final DateTime start = startDate ?? end.subtract(Duration(days: days - 1));
    final String startStr = start.toIso8601String().split('T')[0];
    final String endStr = end.toIso8601String().split('T')[0];

    // Try multiple parameter conventions
    final List<String> endpoints = <String>[
      "/admin/reports/revenue?start_date=$startStr&end_date=$endStr",
      "/admin/reports/revenue?date_from=$startStr&date_to=$endStr",
    ];

    final Map<String, dynamic> response = await _getFirst(endpoints);

    // Expected shape: { data: { daily_data: [ {date, amount|total|total_amount|paid}, ... ] } }
    final dynamic data = response["data"];
    if (data is Map<String, dynamic>) {
      final dynamic daily =
          data["daily_data"] ?? data["daily"] ?? data["series"];
      if (daily is List) return daily.cast<dynamic>();
    }

    if (response["daily_data"] is List) {
      return (response["daily_data"] as List).cast<dynamic>();
    }

    return <dynamic>[];
  }

  // Upload profile image (avatar)
  Future<Map<String, dynamic>> uploadProfileImage({
    required Uint8List bytes,
    required String filename,
  }) async {
    final Map<String, String> headers = await _authHeaders;
    if (!headers.containsKey("Authorization")) {
      throw ApiException(LocalizationService.instance.translate('not_allowed_please_log_in_again'));
    }

    Future<Map<String, dynamic>> send(String endpoint, String fieldName) async {
      final uri = Uri.parse("$baseUrl$endpoint");
      final request = http.MultipartRequest('POST', uri);
      final Map<String, String> h = Map.of(headers);
      // Let MultipartRequest set the correct boundary header
      h.remove('Content-Type');
      request.headers.addAll(h);
      request.files.add(
          http.MultipartFile.fromBytes(fieldName, bytes, filename: filename));
      final streamed = await request.send().timeout(timeoutDuration);
      final response = await http.Response.fromStream(streamed);
      return _handleResponse(response);
    }

    // Try common endpoints/field names
    try {
      return await send('/auth/profile/avatar', 'avatar');
    } on Exception {
      try {
        return await send('/auth/profile/photo', 'photo');
      } on Exception {
        return send('/auth/profile/image', 'image');
      }
    }
  }

  /// Upload one file (a photo) to [endpoint] as the multipart field [field]. The answer is the server's JSON.
  Future<Map<String, dynamic>> uploadFile(
    final String endpoint,
    final String field,
    final Uint8List bytes,
    final String filename, {
    final Map<String, String>? fields,
  }) async {
    final Map<String, String> headers = await _authHeaders;
    if (!headers.containsKey("Authorization")) {
      throw ApiException(LocalizationService.instance.translate('not_allowed_please_log_in_again'));
    }

    final http.MultipartRequest request = http.MultipartRequest('POST', Uri.parse("$baseUrl$endpoint"));
    final Map<String, String> h = Map.of(headers);
    // Let MultipartRequest set the correct boundary header
    h.remove('Content-Type');
    request.headers.addAll(h);
    request.files.add(http.MultipartFile.fromBytes(field, bytes, filename: filename));
    if (fields != null) request.fields.addAll(fields);
    final http.StreamedResponse streamed = await request.send().timeout(timeoutDuration);
    return _handleResponse(await http.Response.fromStream(streamed));
  }

  // Users management endpoints
  Future<Map<String, dynamic>> getUsers(
      {int page = 1,
      int limit = 50,
      String? query,
      String? role,
      String? serviceType}) async {
    String q = (query != null && query.isNotEmpty)
        ? "&q=${Uri.encodeComponent(query)}"
        : "";
    if (role != null && role.isNotEmpty) {
      q += "&role=${Uri.encodeComponent(role)}";
    }
    if (serviceType != null && serviceType.isNotEmpty) {
      q += "&service_type=${Uri.encodeComponent(serviceType)}";
    }
    final List<String> endpoints = <String>[
      "/admin/users?page=$page&limit=$limit$q",
      "/users?page=$page&limit=$limit$q",
      "/admin/user-management/users?page=$page&limit=$limit$q",
    ];
    return _getFirst(endpoints);
  }

  /// Get the first user with 'super_admin' role for support contact
  Future<Map<String, dynamic>?> getSuperAdminUser() async {
    try {
      // Use the new role parameter supported by our backend update
      final response = await getUsers(role: 'super_admin');
      final dynamic data = response['data'] ?? response['users'] ?? [];
      final List<dynamic> users = data is List ? data : (data['users'] as List? ?? []);
      
      if (users.isEmpty) return null;
      
      // Look for exact role match
      final admin = users.firstWhere(
        (u) => (u['role']?.toString().toLowerCase() == 'super_admin'),
        orElse: () => users.first, // Fallback to first search result if no exact role match but search returned results
      );
      return admin as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('ApiService.getSuperAdminUser failed: $e');
      return null;
    }
  }

  /// Get users created by the currently authenticated admin
  Future<Map<String, dynamic>> getMyUsers(
      {int page = 1, int limit = 50, String? query, String? serviceType}) async {
    String q = (query != null && query.isNotEmpty)
        ? "&q=${Uri.encodeComponent(query)}"
        : "";
    if (serviceType != null && serviceType.isNotEmpty) {
      q += "&service_type=${Uri.encodeComponent(serviceType)}";
    }
    final List<String> endpoints = <String>[
      "/admin/users?created_by=me&page=$page&limit=$limit$q",
      "/admin/users/mine?page=$page&limit=$limit$q",
      "/users?created_by=me&page=$page&limit=$limit$q",
      "/admin/user-management/users/mine?page=$page&limit=$limit$q",
    ];
    return _getFirst(endpoints);
  }

  /// Super admin only: every user grouped by service, then by the admin who
  /// manages them within that service.
  Future<Map<String, dynamic>> getUsersByService() async {
    final List<String> endpoints = <String>[
      "/admin/users/by-service",
    ];
    return _getFirst(endpoints);
  }

  Future<Map<String, dynamic>> createUser(Map<String, dynamic> userData) async {
    if (kDebugMode) {
      debugPrint(
          'DEBUG ApiService.createUser: Trying endpoints for user creation');
    }
    return _postFirst(
        <String>["/admin/users", "/users", "/admin/user-management/users"],
        userData);
  }

  Future<Map<String, dynamic>> updateUser(
          String userId, Map<String, dynamic> userData) async =>
      _putFirst(<String>[
        "/admin/users/$userId",
        "/users/$userId",
        "/admin/user-management/users/$userId"
      ], userData);

  /// Super admin: place a staff member under a business admin (they join that business). [service] limits them to one service.
  Future<Map<String, dynamic>> assignUserToAdmin({
    required final String userId,
    required final String adminId,
    final String? service,
  }) async =>
      _put('/admin/users/$userId/assign-admin', <String, dynamic>{
        'admin_id': adminId,
        if (service != null) 'service': service,
      });

  Future<Map<String, dynamic>> updateUserPermissions(
          String userId, List<String> permissions) async =>
      updateUser(userId, {'permissions': permissions});

  // Rental Module APIs
  Future<Map<String, dynamic>> getRentalProperties() async =>
      _get("/rental/properties");

  Future<Map<String, dynamic>> getRentalPropertiesPaginated({
    int page = 1,
    String? search,
    String? status,
    int perPage = 15,
  }) async {
    final queryParams = {
      'page': page.toString(),
      'per_page': perPage.toString(),
      if (search != null && search.isNotEmpty) 'search': search,
      if (status != null) 'status': status,
    };
    return _get("/rental/properties", queryParams: queryParams);
  }

  Future<Map<String, dynamic>> getRentalPropertyDetails(
          String propertyId) async =>
      _get("/rental/properties/$propertyId");

  Future<Map<String, dynamic>> getRentalPropertyStats() async =>
      _get("/rental/properties/stats");

  Future<Map<String, dynamic>> addRentalProperty(Map<String, dynamic> data,
      {File? image}) async {
    final Map<String, String> fields = {};
    data.forEach((key, value) {
      // EXCLUDE cover_image from regular fields if we have a file, 
      // or if it's already a File object in the map
      if (key == 'cover_image' && (image != null || value is File)) return;
      if (value != null) fields[key] = value.toString();
    });

    if (image != null) {
      debugPrint('Adding property with Multipart image. Fields: $fields');
      debugPrint('Image field name: cover_image, Path: ${image.path}');
      return postMultipart("/rental/properties", fields,
          fileField: 'cover_image', file: image);
    }

    debugPrint('Adding property WITHOUT image (JSON). Data: $data');
    return _post("/rental/properties", data);
  }

  Future<Map<String, dynamic>> addRentalPropertyWithImage(
    Map<String, dynamic> fields, {
    required String imagePath,
  }) async {
    final headers = await _authHeaders;
    final uri = Uri.parse("$baseUrl/rental/properties");
    final request = http.MultipartRequest('POST', uri);
    final h = Map<String, String>.of(headers);
    h.remove('Content-Type');
    request.headers.addAll(h);

    request.files.add(await http.MultipartFile.fromPath('image', imagePath));
    fields.forEach((key, value) {
      if (value != null) request.fields[key] = value.toString();
    });

    final response = await http.Response.fromStream(await request.send());
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> updateRentalProperty(
      String propertyId, Map<String, dynamic> data,
      {File? image}) async {
    final Map<String, String> fields = {};
    data.forEach((key, value) {
      if (key == 'cover_image' && (image != null || value is File)) return;
      if (value != null) fields[key] = value.toString();
    });
    fields['_method'] = 'PUT';

    if (image != null) {
      debugPrint('Updating property with Multipart image. Fields: $fields');
      return postMultipart("/rental/properties/$propertyId", fields,
          fileField: 'cover_image', file: image);
    }

    debugPrint('Updating property WITHOUT image (JSON). Data: $data');
    return _put("/rental/properties/$propertyId", data);
  }

  Future<Map<String, dynamic>> deleteRentalProperty(String propertyId) async =>
      _delete("/rental/properties/$propertyId");

  Future<Map<String, dynamic>> addHouseToProperty(
          String propertyId, Map<String, dynamic> data) async =>
      _post("/rental/properties/$propertyId/houses", data);

  Future<Map<String, dynamic>> getRentalDashboard() async =>
      _get("/rental/dashboard");

  Future<Map<String, dynamic>> getRentalTenants() async =>
      _get("/rental/tenants");

  Future<Map<String, dynamic>> getRentalTenantDetails(String tenantId) async =>
      _get("/rental/tenants/$tenantId");

  Future<Map<String, dynamic>> onboardTenant(Map<String, dynamic> data) async {
    final Map<String, String> headers = await _authHeaders;
    final uri = Uri.parse("$baseUrl/rental/tenants/onboard");
    final request = http.MultipartRequest('POST', uri);

    // Add auth headers (remove Content-Type to let MultipartRequest set it)
    final Map<String, String> h = Map.of(headers);
    h.remove('Content-Type');
    request.headers.addAll(h);

    // Filter fields & map complex structures to strings or individual fields
    final String? photoPath = data.remove('tenant_photo');
    final String? idDocPath = data.remove('id_document');

    // Add all remaining data as fields
    // For nested maps (emergency_contact, id_details, etc.), flatten them for Laravel multipart support
    data.forEach((key, value) {
      if (value != null) {
        if (value is Map) {
          value.forEach((subKey, subValue) {
            if (subValue != null) {
              request.fields['$key[$subKey]'] = subValue.toString();
            }
          });
        } else if (value is List) {
          request.fields[key] = json.encode(value);
        } else {
          request.fields[key] = value.toString();
        }
      }
    });

    // Add Tenant Photo if present
    if (photoPath != null && photoPath.isNotEmpty) {
      final file = File(photoPath);
      if (await file.exists()) {
        request.files.add(await http.MultipartFile.fromPath('tenant_photo', photoPath));
      }
    }

    // Add ID Document if present
    if (idDocPath != null && idDocPath.isNotEmpty) {
      final file = File(idDocPath);
      if (await file.exists()) {
        request.files.add(await http.MultipartFile.fromPath('id_document', idDocPath));
      }
    }

    final streamed = await request.send().timeout(timeoutDuration);
    final response = await http.Response.fromStream(streamed);
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> getRentalBills() async =>
      _get("/rental/billing/bills");

  Future<Map<String, dynamic>> recordRentalPayment(
          Map<String, dynamic> data) async =>
      _post("/rental/payments/record", data);

  Future<Map<String, dynamic>> getRentalPayments() async =>
      _get("/rental/payments");

  Future<Map<String, dynamic>> getRentalReceipts() async =>
      _get("/rental/receipts");

  Future<Map<String, dynamic>> getRentalArrears() async =>
      _get("/rental/reports/arrears");

  /// Send multipart request with file upload for maintenance requests
  Future<Map<String, dynamic>> postMultipart(
    String endpoint,
    Map<String, dynamic> fields, {
    required String fileField,
    required file,
  }) async {
    final headers = await _authHeaders;
    final uri = Uri.parse("$baseUrl$endpoint");
    final request = http.MultipartRequest('POST', uri);
    final h = Map<String, String>.of(headers);
    h.remove('Content-Type');
    request.headers.addAll(h);

    request.files.add(await http.MultipartFile.fromPath(fileField, file.path));
    fields.forEach((key, value) {
      if (value != null) request.fields[key] = value.toString();
    });

    final response = await http.Response.fromStream(await request.send());
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> postMultipartMultiFiles(
      String endpoint, Map<String, dynamic> data,
      {required String fileField, required List<dynamic> files}) async {
    final headers = await _authHeaders;

    final url = Uri.parse("$baseUrl$endpoint");
    final request = http.MultipartRequest("POST", url);

    final h = Map<String, String>.of(headers);
    h.remove('Content-Type');
    request.headers.addAll(h);

    for (var file in files) {
       final path = file is String ? file : file.path;
       request.files.add(await http.MultipartFile.fromPath(fileField, path));
    }

    data.forEach((key, value) {
      if (value != null) request.fields[key] = value.toString();
    });

    final response = await http.Response.fromStream(await request.send());
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> sendSmsReminder(String billId) async =>
      _post("/rental/billing/$billId/reminder", {'type': 'sms'});

  // Tenant management
  Future<Map<String, dynamic>> updateTenantStatus(
          String tenantId, String status) async =>
      _put("/rental/tenants/$tenantId/status", {'status': status});

  Future<Map<String, dynamic>> terminateTenant(String tenantId) async =>
      _delete("/rental/tenants/$tenantId");

  Future<Map<String, dynamic>> getRentalSearchTenants(String query) async =>
      _get("/rental/tenants", queryParams: {'search': query});

  // Agreement APIs
  Future<Map<String, dynamic>> getAgreements(
      {String? status, String? search}) async {
    final params = <String, dynamic>{};
    if (status != null) params['status'] = status;
    if (search != null) params['search'] = search;
    return _get("/rental/agreements", queryParams: params);
  }

  Future<Map<String, dynamic>> createAgreement(
          Map<String, dynamic> data) async =>
      _post("/rental/agreements", data);

  Future<Map<String, dynamic>> uploadAgreementDocument(
          String agreementId, dynamic file, String documentType) async =>
      postMultipart("/rental/agreements/$agreementId/documents", {'document_type': documentType}, fileField: 'document', file: file);

  Future<Map<String, dynamic>> dispatchTenantReceipt(String id) async =>
      _post("/rental/receipts/$id/dispatch", {});

  Future<Map<String, dynamic>> getTenantReceipts() async =>
      _get("/rental/tenant/receipts");

  Future<Map<String, dynamic>> getTenantBills() async =>
      _get("/rental/tenant/bills");

  Future<Map<String, dynamic>> getTenantPayments() async =>
      _get("/rental/tenant/payments");

  Future<List<dynamic>> getSystemTenants({String? query}) async {
    final params = <String, dynamic>{};
    if (query != null && query.isNotEmpty) params['query'] = query;
    final res = await _get("/rental/tenants/system", queryParams: params);
    return (res['data'] as List?) ?? [];
  }

  Future<Map<String, dynamic>> renewAgreement(
          String id, Map<String, dynamic> data) async =>
      _post("/rental/agreements/$id/renew", data);

  Future<Map<String, dynamic>> terminateAgreement(
          String id, String reason) async =>
      _post("/rental/agreements/$id/terminate", {'termination_reason': reason});

  Future<Map<String, dynamic>> getExpiringAgreements() async =>
      _get("/rental/agreements/expiring");

  // Blocks
  Future<Map<String, dynamic>> getRentalBlocks(String propertyId) async =>
      _get("/rental/blocks/$propertyId");

  Future<Map<String, dynamic>> addRentalBlock(
          String propertyId, Map<String, dynamic> data) async =>
      _post("/rental/blocks/$propertyId", data);

  // Houses
  Future<Map<String, dynamic>> getPropertyHouses(String propertyId) async =>
      _get("/rental/properties/$propertyId/houses");
  Future<Map<String, dynamic>> getHouseDetails(String houseId) async =>
      _get("/rental/houses/$houseId");

  Future<Map<String, dynamic>> createHouse(Map<String, dynamic> data, {List<dynamic>? images}) async {
    if (images != null && images.isNotEmpty) {
      return postMultipartMultiFiles("/rental/houses", data, fileField: 'images[]', files: images);
    }
    return _post("/rental/houses", data);
  }

  Future<Map<String, dynamic>> updateHouse(String houseId, Map<String, dynamic> data, {List<dynamic>? images}) async {
    if (images != null && images.isNotEmpty) {
      data['_method'] = 'PUT';
      return postMultipartMultiFiles("/rental/houses/$houseId", data, fileField: 'images[]', files: images);
    }
    return _put("/rental/houses/$houseId", data);
  }

  Future<Map<String, dynamic>> deleteHouse(String houseId) async =>
      _delete("/rental/houses/$houseId");

  // Reports
  Future<Map<String, dynamic>> getOccupancyReport() async =>
      _get("/rental/reports/occupancy");

  Future<Map<String, dynamic>> getRevenueReport(
      {String? period, DateTime? startDate, DateTime? endDate}) async {
    final queryParams = <String, String>{};
    if (period != null) queryParams['period'] = period;
    if (startDate != null) {
      queryParams['start_date'] = startDate.toIso8601String().split('T')[0];
    }
    if (endDate != null) {
      queryParams['end_date'] = endDate.toIso8601String().split('T')[0];
    }
    if (queryParams.isEmpty) return _get("/rental/reports/revenue");
    return _get("/rental/reports/revenue", queryParams: queryParams);
  }

  Future<Map<String, dynamic>> deleteUser(String userId) async =>
      _deleteFirst(<String>[
        "/admin/users/$userId",
        "/users/$userId",
        "/admin/user-management/users/$userId"
      ]);

  Future<Map<String, dynamic>> resetUserPassword({
    required String userId,
    required String newPassword,
  }) async =>
      _postFirst(<String>[
        "/admin/users/$userId/reset-password",
        "/admin/users/$userId/password/reset",
        "/users/$userId/reset-password",
        "/users/$userId/password/reset",
      ], {
        "password": newPassword,
        "password_confirmation": newPassword,
      });

  // Driver management endpoints
  Future<Map<String, dynamic>> getDrivers({
    final int page = 1,
    final int limit = 20,
  }) async =>
      _get("/admin/drivers?page=$page&limit=$limit");

  /// Get a single driver by ID
  Future<Map<String, dynamic>> getDriverById(final String driverId) async =>
      _get("/admin/drivers/$driverId");

  Future<Map<String, dynamic>> createDriver(
    final Map<String, dynamic> driverData,
  ) async =>
      // Signed in like every other admin call. This used to be sent with no token, which
      // the server (rightly) refuses: POST /admin/drivers is an admin-only route.
      _post("/admin/drivers", driverData);

  Future<Map<String, dynamic>> updateDriver(
    final String driverId,
    final Map<String, dynamic> driverData,
  ) async =>
      _put("/admin/drivers/$driverId", driverData);

  Future<Map<String, dynamic>> deleteDriver(final String driverId) async =>
      _delete("/admin/drivers/$driverId");

  // Driver History endpoints
  Future<Map<String, dynamic>> getDriverHistory({
    required final String driverId,
    final DateTime? startDate,
    final DateTime? endDate,
  }) async {
    String endpoint = "/admin/drivers/$driverId/history";
    final List<String> params = <String>[];

    if (startDate != null) {
      params.add("start_date=${startDate.toIso8601String().split('T')[0]}");
    }
    if (endDate != null) {
      params.add("end_date=${endDate.toIso8601String().split('T')[0]}");
    }

    if (params.isNotEmpty) {
      endpoint += "?${params.join("&")}";
    }

    return _get(endpoint);
  }

  Future<Map<String, dynamic>> getDriverFinancialSummary(
    final String driverId, {
    final DateTime? startDate,
    final DateTime? endDate,
  }) async {
    String endpoint = "/admin/drivers/$driverId/financial-summary";
    final List<String> params = <String>[];

    if (startDate != null) {
      params.add("start_date=${startDate.toIso8601String().split('T')[0]}");
    }
    if (endDate != null) {
      params.add("end_date=${endDate.toIso8601String().split('T')[0]}");
    }

    if (params.isNotEmpty) {
      endpoint += "?${params.join("&")}";
    }

    return _get(endpoint);
  }

  Future<Map<String, dynamic>> getDriverPerformanceMetrics(
    final String driverId,
  ) async =>
      _get("/admin/drivers/$driverId/performance-metrics");

  Future<Map<String, dynamic>> getDriverTripsHistory({
    required final String driverId,
    final int page = 1,
    final int limit = 50,
    final DateTime? startDate,
    final DateTime? endDate,
    final String? status,
  }) async {
    String endpoint = "/admin/drivers/$driverId/trips?page=$page&limit=$limit";

    if (startDate != null) {
      endpoint += "&start_date=${startDate.toIso8601String().split('T')[0]}";
    }
    if (endDate != null) {
      endpoint += "&end_date=${endDate.toIso8601String().split('T')[0]}";
    }
    if (status != null) {
      endpoint += "&status=$status";
    }

    return _get(endpoint);
  }

  Future<Map<String, dynamic>> getDriverStatusHistory({
    required final String driverId,
    final int page = 1,
    final int limit = 20,
  }) async =>
      _get("/admin/drivers/$driverId/status-history?page=$page&limit=$limit");

  Future<Map<String, dynamic>> getDriverPaymentTrends({
    required final String driverId,
    final String period = "monthly", // daily, weekly, monthly, yearly
    final int months = 12,
  }) async =>
      _get(
          "/admin/drivers/$driverId/payment-trends?period=$period&months=$months");

  // Driver prediction analytics (server-side)
  Future<Map<String, dynamic>> getDriverPrediction(
          final String driverId) async =>
      _get("/admin/drivers/$driverId/prediction");

  Future<Map<String, dynamic>> getDriverDebtTrends({
    required final String driverId,
    final String period = "monthly",
    final int months = 12,
  }) async =>
      _get(
          "/admin/drivers/$driverId/debt-trends?period=$period&months=$months");

  Future<Map<String, dynamic>> updateDriverPerformanceMetrics(
    final String driverId,
  ) async =>
      _put("/admin/drivers/$driverId/recalculate-metrics", <String, dynamic>{});

  // Driver Agreement endpoints
  Future<Map<String, dynamic>> getDriverAgreements({
    final int page = 1,
    final int limit = 20,
    final String? status,
    final String? agreementType,
  }) async {
    String endpoint = "/admin/driver-agreements?page=$page&limit=$limit";
    if (status != null) endpoint += "&status=$status";
    if (agreementType != null) endpoint += "&agreement_type=$agreementType";
    return _get(endpoint);
  }

  Future<Map<String, dynamic>> createDriverAgreement(
    final Map<String, dynamic> agreementData,
  ) async =>
      _post("/admin/driver-agreements", agreementData);

  Future<Map<String, dynamic>> getDriverAgreement(
          final String agreementId) async =>
      _get("/admin/driver-agreements/$agreementId");

  Future<Map<String, dynamic>> updateDriverAgreement(
    final String agreementId,
    final Map<String, dynamic> agreementData,
  ) async =>
      _put("/admin/driver-agreements/$agreementId", agreementData);

  Future<Map<String, dynamic>> deleteDriverAgreement(
    final String agreementId,
  ) async =>
      _delete("/admin/driver-agreements/$agreementId");

  Future<Map<String, dynamic>> getDriverAgreementByDriverId(
    final String driverId,
  ) async =>
      _get("/admin/driver-agreements/driver/$driverId");

  Future<Map<String, dynamic>> terminateDriverAgreement(
    final String agreementId,
    final Map<String, dynamic> terminationData,
  ) async =>
      _put("/admin/driver-agreements/$agreementId/terminate", terminationData);

  Future<Map<String, dynamic>> previewDriverAgreementCalculation(
    final Map<String, dynamic> calculationData,
  ) async =>
      _post("/admin/driver-agreements/calculate-preview", calculationData);

  /// Check if a driver has completed their agreement
  /// Returns true if driver has an active/completed agreement, false otherwise
  Future<bool> hasDriverCompletedAgreement(final String driverId) async {
    try {
      final Map<String, dynamic> response =
          await getDriverAgreementByDriverId(driverId);

      final Map<String, dynamic>? data = response['data'] is Map
          ? Map<String, dynamic>.from(response['data'])
          : null;
      final String? status = data?['status']?.toString();
      return status == 'active' || status == 'completed';
    } on Exception {
      // If no agreement found or error occurred, consider as not completed
      return false;
    }
  }

  // Vehicle management endpoints
  Future<Map<String, dynamic>> getVehicles({
    final int page = 1,
    final int limit = 20,
  }) async =>
      _get("/admin/vehicles?page=$page&limit=$limit");

  Future<Map<String, dynamic>> createVehicle(
    final Map<String, dynamic> vehicleData,
  ) async =>
      _post("/admin/vehicles", vehicleData);

  Future<Map<String, dynamic>> updateVehicle(
    final String vehicleId,
    final Map<String, dynamic> vehicleData,
  ) async =>
      _put("/admin/vehicles/$vehicleId", vehicleData);

  Future<Map<String, dynamic>> unassignDriverFromVehicle(
          final String vehicleId) async =>
      _post("/admin/vehicles/$vehicleId/unassign", <String, dynamic>{});

  Future<Map<String, dynamic>> deleteVehicle(final String vehicleId) async =>
      _delete("/admin/vehicles/$vehicleId");

  Future<Map<String, dynamic>> assignDriverToVehicle({
    required final String vehicleId,
    required final String driverId,
  }) async =>
      _post("/admin/assign-driver", <String, dynamic>{
        "vehicle_id": vehicleId,
        "driver_id": driverId,
      });

  // Payment management endpoints
  Future<Map<String, dynamic>> getPayments({
    final int page = 1,
    final int limit = 20,
  }) async =>
      _get("/admin/payment-history?page=$page&limit=$limit");

  // Receipt management endpoints
  Future<Map<String, dynamic>> generateReceipt(
    final Map<String, dynamic> receiptData,
  ) async =>
      _post("/admin/generate-receipt", receiptData);

  // Reports endpoints
  Future<Map<String, dynamic>> getDashboardReport() async =>
      _get("/admin/reports/dashboard");

  Future<Map<String, dynamic>> getAdminRevenueReport({
    final DateTime? startDate,
    final DateTime? endDate,
  }) async {
    String endpoint = "/admin/reports/revenue";
    final List<String> params = <String>[];

    String d(DateTime d) {
      String two(int n) => n < 10 ? '0$n' : '$n';
      return "${d.year}-${two(d.month)}-${two(d.day)}"; // send date-only to avoid TZ issues
    }

    if (startDate != null) {
      params.add("start_date=${d(startDate)}");
    }
    if (endDate != null) {
      params.add("end_date=${d(endDate)}");
    }

    if (params.isNotEmpty) {
      endpoint += "?${params.join("&")}";
    }

    return _get(endpoint);
  }

  // Typed helpers (non-breaking): parse API maps into DTOs
  // Consumers can migrate to these methods incrementally for type safety.
  Future<DashboardReport> getDashboardReportTyped() async {
    final Map<String, dynamic> map = await getDashboardReport();
    return DashboardReport.fromApi(map);
  }

  Future<DashboardReport> getDashboardDataTyped() async {
    final Map<String, dynamic> map = await getDashboardData();
    return DashboardReport.fromApi(map);
  }

  Future<RevenueReport> getRevenueReportTyped({
    final DateTime? startDate,
    final DateTime? endDate,
  }) async {
    final Map<String, dynamic> map = await getRevenueReport(
      startDate: startDate,
      endDate: endDate,
    );
    return RevenueReport.fromApi(map);
  }

  Future<Map<String, dynamic>> getExpenseReport({
    final DateTime? startDate,
    final DateTime? endDate,
  }) async {
    String endpoint = "/admin/reports/expenses";
    final List<String> params = <String>[];

    String d(DateTime d) {
      String two(int n) => n < 10 ? '0$n' : '$n';
      return "${d.year}-${two(d.month)}-${two(d.day)}";
    }

    if (startDate != null) {
      params.add("start_date=${d(startDate)}");
    }
    if (endDate != null) {
      params.add("end_date=${d(endDate)}");
    }

    if (params.isNotEmpty) {
      endpoint += "?${params.join("&")}";
    }

    return _get(endpoint);
  }

  Future<Map<String, dynamic>> getProfitLossReport({
    final DateTime? startDate,
    final DateTime? endDate,
  }) async {
    String endpoint = "/admin/reports/profit-loss";
    final List<String> params = <String>[];

    String d(DateTime d) {
      String two(int n) => n < 10 ? '0$n' : '$n';
      return "${d.year}-${two(d.month)}-${two(d.day)}";
    }

    if (startDate != null) {
      params.add("start_date=${d(startDate)}");
    }
    if (endDate != null) {
      params.add("end_date=${d(endDate)}");
    }

    if (params.isNotEmpty) {
      endpoint += "?${params.join("&")}";
    }

    return _get(endpoint);
  }

  Future<Map<String, dynamic>> getDevicePerformanceReport() async =>
      _get("/admin/reports/device-performance");

  Future<Map<String, dynamic>> exportReportToPdf(
    final Map<String, dynamic> reportData,
  ) async =>
      _post("/admin/reports/export-pdf", reportData);

  // Reminder endpoints
  Future<Map<String, dynamic>> addReminder(
    final Map<String, dynamic> reminderData,
  ) async =>
      _post("/admin/reminders", reminderData);

  Future<Map<String, dynamic>> getReminders({
    final int page = 1,
    final int limit = 20,
  }) async =>
      _get("/admin/reminders?page=$page&limit=$limit");

  // Driver reminders (read-only)
  Future<Map<String, dynamic>> getDriverReminders(
          {int page = 1, int limit = 50}) async =>
      _get("/driver/reminders?page=$page&limit=$limit");

  Future<Map<String, dynamic>> updateReminder(
    final String reminderId,
    final Map<String, dynamic> reminderData,
  ) async =>
      _put("/admin/reminders/$reminderId", reminderData);

  Future<Map<String, dynamic>> deleteReminder(final String reminderId) async =>
      _delete("/admin/reminders/$reminderId");

  // Device management endpoints
  Future<Map<String, dynamic>> getDevices({
    final int page = 1,
    final int limit = 20,
  }) async =>
      _get("/admin/devices?page=$page&limit=$limit");

  Future<Map<String, dynamic>> createDevice(
    final Map<String, dynamic> deviceData,
  ) async =>
      _post("/admin/devices", deviceData);

  Future<Map<String, dynamic>> updateDevice(
    final String deviceId,
    final Map<String, dynamic> deviceData,
  ) async =>
      _put("/admin/devices/$deviceId", deviceData);

  Future<Map<String, dynamic>> deleteDevice(final String deviceId) async =>
      _delete("/admin/devices/$deviceId");

  // Transaction endpoints
  Future<Map<String, dynamic>> getTransactions({
    final int page = 1,
    final int limit = 20,
    final String? status,
    final String? type,
    final DateTime? startDate,
    final DateTime? endDate,
  }) async {
    String endpoint = "/admin/transactions?page=$page&limit=$limit";

    if (status != null) {
      endpoint += "&status=$status";
    }
    if (type != null) {
      endpoint += "&type=$type";
    }
    if (startDate != null) {
      endpoint += "&start_date=${startDate.toIso8601String()}";
    }
    if (endDate != null) {
      endpoint += "&end_date=${endDate.toIso8601String()}";
    }

    return _get(endpoint);
  }

  Future<Map<String, dynamic>> createTransaction(
    final Map<String, dynamic> transactionData,
  ) async =>
      _post("/admin/transactions", transactionData);

  Future<Map<String, dynamic>> updateTransaction(
    final String transactionId,
    final Map<String, dynamic> transactionData,
  ) async =>
      _put("/admin/transactions/$transactionId", transactionData);

  Future<Map<String, dynamic>> deleteTransaction(
    final String transactionId,
  ) async =>
      _delete("/admin/transactions/$transactionId");

  // Payment management endpoints
  Future<Map<String, dynamic>> getDriversWithDebts({
    final int page = 1,
    final int limit = 50,
  }) async =>
      // Updated to new debts route (payments routes removed on backend)
      _get("/admin/debts/drivers?page=$page&limit=$limit");

  // Debts management endpoints
  Future<Map<String, dynamic>> getDebtDrivers({
    final int page = 1,
    final int limit = 50,
    final String? query,
  }) async {
    String endpoint = "/admin/debts/drivers?page=$page&limit=$limit";
    if (query != null && query.isNotEmpty) {
      endpoint += "&q=${Uri.encodeComponent(query)}";
    }
    return _get(endpoint);
  }

  Future<Map<String, dynamic>> createDebts({
    required String driverId,
    List<String>? dates, // YYYY-MM-DD (legacy mode)
    double? amount, // legacy mode
    List<Map<String, dynamic>>? items, // [{date: YYYY-MM-DD, amount: 10000}]
    String? notes,
    bool promisedToPay = false,
    DateTime? promiseToPayAt,
  }) async {
    final Map<String, dynamic> payload = <String, dynamic>{
      "driver_id": driverId,
      if (items != null) "items": items,
      if (dates != null) "dates": dates,
      if (amount != null) "amount": amount,
      if (notes != null && notes.isNotEmpty) "notes": notes,
      if (promisedToPay) "promised_to_pay": true,
      if (promiseToPayAt != null)
        "promise_to_pay_at": promiseToPayAt.toIso8601String(),
    };
    return _post("/admin/debts/bulk-create", payload);
  }

  Future<Map<String, dynamic>> updateDebtRecord({
    required String debtId,
    String? earningDate,
    double? expectedAmount,
    String? notes,
    bool? promisedToPay,
    DateTime? promiseToPayAt,
  }) async {
    final Map<String, dynamic> payload = <String, dynamic>{
      if (earningDate != null) "earning_date": earningDate,
      if (expectedAmount != null) "expected_amount": expectedAmount,
      if (notes != null) "notes": notes,
      if (promisedToPay != null) "promised_to_pay": promisedToPay,
      if (promiseToPayAt != null)
        "promise_to_pay_at": promiseToPayAt.toIso8601String(),
    };
    return _put("/admin/debts/records/$debtId", payload);
  }

  Future<Map<String, dynamic>> deleteDebtRecord(String debtId) async =>
      _delete("/admin/debts/records/$debtId");

  Future<Map<String, dynamic>> getDriverDebtSummary(
    final String driverId,
  ) async {
    // Backend no longer exposes /admin/payments/driver-debt-summary.
    // Fetch records and compute a summary compatible with existing UI models.
    final Map<String, dynamic> resp =
        await _get("/admin/debts/driver/$driverId/records");

    final dynamic data = resp["data"];
    final List<dynamic> records = (data is Map && data["debt_records"] is List)
        ? (data["debt_records"] as List).cast<dynamic>()
        : (resp["debt_records"] is List)
            ? (resp["debt_records"] as List).cast<dynamic>()
            : <dynamic>[];

    double toDouble(Object? v) {
      if (v == null) return 0;
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? 0;
      return 0;
    }

    double totalDebt = 0;
    int unpaidDays = 0;
    DateTime? lastPaidAt;
    String driverName = "";

    for (final dynamic r in records) {
      final Map<String, dynamic> m = (r as Map).cast<String, dynamic>();
      driverName = driverName.isEmpty
          ? (m['driver_name']?.toString() ?? driverName)
          : driverName;
      final bool isPaid = m['is_paid'] == true || m['is_paid'] == 1;
      if (!isPaid) {
        unpaidDays += 1;
        totalDebt += toDouble(m['remaining_amount']);
      } else {
        final String? paidAtStr = m['paid_at']?.toString();
        final DateTime? dt =
            paidAtStr != null ? DateTime.tryParse(paidAtStr) : null;
        if (dt != null) {
          if (lastPaidAt == null || dt.isAfter(lastPaidAt)) {
            lastPaidAt = dt;
          }
        }
      }
    }

    return <String, dynamic>{
      'success': true,
      'message': 'Driver debt summary computed',
      'data': <String, dynamic>{
        'driver_id': driverId,
        'driver_name': driverName,
        'total_debt': totalDebt,
        'unpaid_days': unpaidDays,
        'debt_records': records,
        'last_payment_date': lastPaidAt?.toIso8601String(),
      },
    };
  }

  Future<Map<String, dynamic>> getDriverDebtRecords(
    final String driverId, {
    final bool unpaidOnly = true,
    final int limit = 100,
  }) async {
    String endpoint = "/admin/payments/driver-debts/$driverId?limit=$limit";
    if (unpaidOnly) {
      endpoint += "&unpaid_only=true";
    }
    return _get(endpoint);
  }

  Future<Map<String, dynamic>> recordPayment(
    final Map<String, dynamic> paymentData,
  ) async =>
      _post("/admin/payments/record", paymentData);

  // Store new monthly payment (not tied to debt clearance)
  Future<Map<String, dynamic>> storeNewPayment(
    final Map<String, dynamic> paymentData,
  ) async =>
      _post("/admin/payments/new", paymentData);

  Future<Map<String, dynamic>> getNewPaymentsMap({String? month}) async {
    String endpoint = "/admin/payments/new-payments-map";
    if (month != null && month.isNotEmpty) {
      endpoint += "?month=$month";
    }
    return _get(endpoint);
  }

  Future<Map<String, dynamic>> getPaymentHistory({
    final int page = 1,
    final int limit = 20,
    final String? driverId,
    final DateTime? startDate,
    final DateTime? endDate,
  }) async {
    String endpoint = "/admin/payments/history?page=$page&limit=$limit";

    String d(DateTime d) {
      String two(int n) => n < 10 ? '0$n' : '$n';
      return "${d.year}-${two(d.month)}-${two(d.day)}";
    }

    if (driverId != null) {
      endpoint += "&driver_id=$driverId";
    }
    if (startDate != null) {
      endpoint += "&start_date=${d(startDate)}";
    }
    if (endDate != null) {
      endpoint += "&end_date=${d(endDate)}";
    }

    return _get(endpoint);
  }

  Future<Map<String, dynamic>> updatePayment(
    final String paymentId,
    final Map<String, dynamic> paymentData,
  ) async =>
      _put("/admin/payments/$paymentId", paymentData);

  Future<Map<String, dynamic>> deletePayment(
    final String paymentId,
  ) async =>
      _delete("/admin/payments/$paymentId");

  Future<Map<String, dynamic>> getPaymentSummary({
    final DateTime? startDate,
    final DateTime? endDate,
  }) async {
    String endpoint = "/admin/payments/summary";
    final List<String> params = <String>[];

    if (startDate != null) {
      params.add("start_date=${startDate.toIso8601String()}");
    }
    if (endDate != null) {
      params.add("end_date=${endDate.toIso8601String()}");
    }

    if (params.isNotEmpty) {
      endpoint += "?${params.join("&")}";
    }

    return _get(endpoint);
  }

  Future<Map<String, dynamic>> markDebtAsPaid(
    final String debtId,
    final String paymentId,
  ) async =>
      _put("/admin/payments/mark-debt-paid/$debtId", {
        "payment_id": paymentId,
        "paid_at": DateTime.now().toIso8601String(),
      });

  // Receipt Management Methods

  /// Get pending receipts (payments without receipts generated)
  Future<Map<String, dynamic>> getPendingReceipts() async =>
      _get("/admin/receipts/pending");

  /// Generate receipt for a payment
  Future<Map<String, dynamic>> generatePaymentReceipt(String paymentId) async =>
      _post("/admin/receipts/generate", {
        "payment_id": paymentId,
      });

  /// Generate bulk receipts for multiple payments
  Future<Map<String, dynamic>> generateBulkReceipts(
    List<String> paymentIds,
  ) async =>
      _post("/admin/receipts/bulk-generate", {
        "payment_ids": paymentIds,
      });

  /// Get receipt by ID
  Future<Map<String, dynamic>> getReceipt(String receiptId) async =>
      _get("/admin/receipts/$receiptId");

  /// Get all receipts with optional filtering and pagination
  Future<Map<String, dynamic>> getReceipts({
    int page = 1,
    int limit = 20,
    String? status,
    String? driverId,
    String? query,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    String endpoint = "/admin/receipts?page=$page&limit=$limit";
    final List<String> params = <String>[];

    if (status != null && status.isNotEmpty) {
      params.add("status=$status");
    }
    if (driverId != null && driverId.isNotEmpty) {
      params.add("driver_id=$driverId");
    }
    if (query != null && query.isNotEmpty) {
      params.add("q=${Uri.encodeComponent(query)}");
    }
    if (dateFrom != null) {
      params.add("date_from=${dateFrom.toIso8601String().split('T')[0]}");
    }
    if (dateTo != null) {
      params.add("date_to=${dateTo.toIso8601String().split('T')[0]}");
    }

    if (params.isNotEmpty) {
      endpoint += "&${params.join("&")}";
    }

    return _get(endpoint);
  }

  /// Search receipts
  Future<Map<String, dynamic>> searchReceipts({
    required String query,
    int page = 1,
    int limit = 20,
  }) async =>
      _get(
          "/admin/receipts/search?q=${Uri.encodeComponent(query)}&page=$page&limit=$limit");

  /// Get payment receipt preview by receipt ID
  Future<Map<String, dynamic>> getPaymentReceiptPreview(
          String receiptId) async =>
      _get("/admin/receipts/$receiptId/preview");

  /// Send payment receipt to driver via specified method
  Future<Map<String, dynamic>> sendPaymentReceipt({
    required String receiptId,
    required String sendVia, // 'whatsapp', 'email', 'sms'
    required String
        contactInfo, // phone number for WhatsApp/SMS, email for email
    String? message,
  }) async =>
      _post("/admin/receipts/send", {
        "receipt_id": receiptId,
        "send_via": sendVia,
        "contact_info": contactInfo,
        if (message != null && message.isNotEmpty) "message": message,
      });

  /// Update receipt status
  Future<Map<String, dynamic>> updateReceiptStatus(
    String receiptId,
    String status,
  ) async =>
      _put("/admin/receipts/$receiptId/status", {
        "status": status,
      });

  /// Cancel receipt
  Future<Map<String, dynamic>> cancelReceipt(String receiptId) async =>
      _put("/admin/receipts/$receiptId/cancel", <String, dynamic>{});

  /// Delete receipt
  Future<Map<String, dynamic>> deleteReceipt(String receiptId) async =>
      _delete("/admin/receipts/$receiptId");

  /// Get receipt statistics
  Future<Map<String, dynamic>> getReceiptStats({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    String endpoint = "/admin/receipts/stats";
    final List<String> params = <String>[];

    if (startDate != null) {
      params.add("start_date=${startDate.toIso8601String().split('T')[0]}");
    }
    if (endDate != null) {
      params.add("end_date=${endDate.toIso8601String().split('T')[0]}");
    }

    if (params.isNotEmpty) {
      endpoint += "?${params.join("&")}";
    }

    return _get(endpoint);
  }

  /// Export receipts to PDF or Excel
  Future<Map<String, dynamic>> exportReceipts({
    required String format, // 'pdf' or 'excel'
    String? status,
    String? driverId,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final Map<String, dynamic> data = <String, dynamic>{
      "format": format,
    };

    if (status != null) data["status"] = status;
    if (driverId != null) data["driver_id"] = driverId;
    if (dateFrom != null) {
      data["date_from"] = dateFrom.toIso8601String().split('T')[0];
    }
    if (dateTo != null) {
      data["date_to"] = dateTo.toIso8601String().split('T')[0];
    }

    return _post("/admin/receipts/export", data);
  }

  /// Get payment receipt by ID (alias for getReceipt)
  Future<Map<String, dynamic>> getPaymentReceiptById(String receiptId) async =>
      getReceipt(receiptId);

  /// Get all payment receipts (alias for getReceipts)
  Future<Map<String, dynamic>> getPaymentReceipts({
    String? status,
    String? driverId,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async =>
      getReceipts(
        status: status,
        driverId: driverId,
        dateFrom: dateFrom,
        dateTo: dateTo,
      );

  // Location endpoints
  Future<Map<String, dynamic>> getLocationsRegions() async =>
      _get("/locations/regions", requireAuth: false);

  Future<Map<String, dynamic>> getLocationsDistricts(String regionId) async =>
      _get("/locations/districts?region_id=$regionId", requireAuth: false);

  Future<Map<String, dynamic>> getLocationsWards(String districtId) async =>
      _get("/locations/wards?district_id=$districtId", requireAuth: false);

  Future<Map<String, dynamic>> getLocationsStreets(String wardId) async =>
      _get("/locations/streets?ward_id=$wardId", requireAuth: false);

  Future<Map<String, dynamic>> getLocationsPlaces(String streetId) async =>
      _get("/locations/places?village_id=$streetId", requireAuth: false);

  // Health check
  Future<Map<String, dynamic>> healthCheck() async =>
      _get("/health", requireAuth: false);

  // Test endpoints
  Future<Map<String, dynamic>> testConnection() async =>
      _get("/test", requireAuth: false);

  Future<Map<String, dynamic>> getSystemStatus() async =>
      _get("/test/system-status", requireAuth: false);

  // ── Public House Listings (no auth) ──

  Future<Map<String, dynamic>> getPublicHouses({
    int page = 1,
    String? search,
    String? type,
    String? status,
    int? bedrooms,
    int? bathrooms,
    int? maxDistance,
    bool? hasFence,
    bool? hasTiles,
    bool? hasKitchen,
    bool? hasMasterBedroom,
    bool? hasSittingRoom,
  }) async {
    final params = <String, String>{
      'page': page.toString(),
      'per_page': '20',
      if (search != null && search.isNotEmpty) 'search': search,
      if (type != null) 'type': type,
      if (status != null) 'status': status,
      if (bedrooms != null) 'bedrooms': bedrooms.toString(),
      if (bathrooms != null) 'bathrooms': bathrooms.toString(),
      if (maxDistance != null) 'max_distance': maxDistance.toString(),
      if (hasFence != null) 'has_fence': hasFence.toString(),
      if (hasTiles != null) 'has_tiles': hasTiles.toString(),
      if (hasKitchen != null) 'has_kitchen': hasKitchen.toString(),
      if (hasMasterBedroom != null) 'has_master_bedroom': hasMasterBedroom.toString(),
      if (hasSittingRoom != null) 'has_sitting_room': hasSittingRoom.toString(),
    };
    final uri = Uri.parse('$baseUrl/public/houses').replace(queryParameters: params);
    try {
      final response = await http.get(uri, headers: _headers).timeout(timeoutDuration);
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return {'success': false, 'data': []};
  }
}

// Custom exception class for API errors
class ApiException implements Exception {
  /// The message is kept as plain words in the chosen language: a server text written in both languages is
  /// cut to the one that is read, and no "Exception:" wrapper is left on it.
  ApiException(final String message) : message = readableServerMessage(message);
  final String message;

  @override
  String toString() => message;
}

// Response wrapper class
class ApiResponse<T> {
  ApiResponse({
    required this.success,
    this.data,
    this.message,
    this.errors,
  });

  factory ApiResponse.fromJson(
    final Map<String, dynamic> json,
    final T Function()? fromJson,
  ) =>
      ApiResponse<T>(
        success: json["success"] ?? true,
        data: json["data"] != null && fromJson != null
            ? fromJson()
            : json["data"],
        message: json["message"],
        errors: json["errors"],
      );
  final bool success;
  final T? data;
  final String? message;
  final Map<String, dynamic>? errors;
}

// Network connectivity helper
class NetworkHelper {
  static Future<bool> isConnected() async {
    try {
      final List<InternetAddress> result =
          await InternetAddress.lookup("google.com");
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      return false;
    }
  }
}
