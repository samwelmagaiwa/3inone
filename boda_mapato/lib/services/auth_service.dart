import "dart:convert";
import "dart:developer" as developer;

import "package:flutter/foundation.dart"; // for kDebugMode, debugPrint
import "package:http/http.dart" as http;
import "package:shared_preferences/shared_preferences.dart";
import "../config/api_config.dart";
import "../models/business_registration.dart";

/// A non-2xx answer from the server. Keeps the status code so callers can tell
/// "your session is no longer valid" (401) from a server hiccup (5xx), and
/// prints exactly like the plain `Exception` it replaces.
class AuthHttpException implements Exception {
  AuthHttpException(this.statusCode, this.message, {this.code});

  final int statusCode;
  final String message;
  final String? code;

  @override
  String toString() => "Exception: $message";
}

mixin AuthService {
  // API Configuration - Updated for Laravel backend
  // For mobile device testing via USB debugging on this PC (192.168.1.124)
  // Use centralized API configuration for consistency with ApiService
  static String get baseUrl => ApiConfig.baseUrl;

  // Alternative URLs for different environments:
  // For development on localhost: "http://127.0.1:8000/api"
  // For Android emulator: "http://10.0.2.2:8000/api"
  // For iOS simulator: "http://127.0.1:8000/api"

  static Duration get timeoutDuration => ApiConfig.timeoutDuration;
  static const String tokenKey = "auth_token";
  static const String userKey = "user_data";

  // Headers for API requests
  static Map<String, String> get _headers => <String, String>{
        "Content-Type": "application/json",
        "Accept": "application/json",
      };

  // Headers with authentication token
  static Future<Map<String, String>> get _authHeaders async {
    final String? token = await getToken();
    return <String, String>{
      ..._headers,
      if (token != null) "Authorization": "Bearer $token",
    };
  }

  // Handle HTTP response
  static Map<String, dynamic> _handleResponse(final http.Response response) {
    final Map<String, dynamic> data = jsonDecode(response.body);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    } else {
      if (kDebugMode && ApiConfig.enableHttpLogs) {
        debugPrint(
            'HTTP ERROR ${response.request?.url} status=${response.statusCode}');
        final String b = response.body;
        debugPrint(
            'Body (first 1000): ${b.length > 1000 ? '${b.substring(0, 1000)}...' : b}');
      }
      final Object? errorsObj = data["errors"];
      String? code;
      if (errorsObj is Map) {
        final Object? codeObj = errorsObj["code"];
        code = codeObj?.toString();
      }
      code ??= data["code"]?.toString();
      throw AuthHttpException(
        response.statusCode,
        (data["message"] ?? "Server error: ${response.statusCode}").toString(),
        code: code,
      );
    }
  }

  // Login method (direct authentication)
  static Future<Map<String, dynamic>> login({
    required final String email,
    required final String password,
    required final String phoneNumber,
  }) async {
    try {
      final String url = "$baseUrl/auth/login";
      if (kDebugMode && ApiConfig.enableHttpLogs) {
        debugPrint('HTTP POST $url');
        debugPrint(
            'Request: {email: $email, phone_number: $phoneNumber, password: ***}');
      }
      final http.Response response = await http
          .post(
            Uri.parse(url),
            headers: _headers,
            body: jsonEncode(<String, String>{
              "email": email,
              "password": password,
              "phone_number": phoneNumber,
            }),
          )
          .timeout(timeoutDuration);
      if (kDebugMode && ApiConfig.enableHttpLogs) {
        debugPrint('HTTP <- $url status=${response.statusCode}');
        final String b = response.body;
        debugPrint(
            'Body (first 1000): ${b.length > 1000 ? '${b.substring(0, 1000)}...' : b}');
      }

      final Map<String, dynamic> data = _handleResponse(response);

      // Normalize response structure and persist
      final Map<String, dynamic>? dataMap =
          data["data"] is Map ? Map<String, dynamic>.from(data["data"]) : null;
      final String? token = (dataMap?['token'] ?? data['token']) as String?;
      final Map<String, dynamic>? user =
          (dataMap?['user'] ?? data['user']) is Map
              ? Map<String, dynamic>.from(dataMap?['user'] ?? data['user'])
              : null;

      if (token != null) {
        await saveToken(token);
      }
      if (user != null) {
        await saveUserData(user);
      }

      return data;
    } on Exception catch (e) {
      if (kDebugMode && ApiConfig.enableHttpLogs) {
        debugPrint('HTTP EXCEPTION $baseUrl/auth/login -> $e');
      }
      throw Exception("Login failed: $e");
    }
  }

  /// Step 1 of password recovery: asks the server to TEXT a one-time code to the phone
  /// registered on the account (it needs the email AND that phone number). Nothing that
  /// proves identity comes back in the answer, and the answer is the same whether or not
  /// the details matched, so only the real owner of the phone ever gets the code.
  static Future<void> forgotPassword({
    required final String email,
    required final String phoneNumber,
  }) async {
    final http.Response response = await http
        .post(
          Uri.parse("$baseUrl/auth/forgot-password"),
          headers: _headers,
          body: jsonEncode(<String, String>{
            "email": email,
            "phone_number": phoneNumber,
          }),
        )
        .timeout(timeoutDuration);

    _handleResponse(response);
  }

  /// Step 2: the code that was texted, plus the new password.
  static Future<void> resetPassword({
    required final String email,
    required final String code,
    required final String password,
  }) async {
    final http.Response response = await http
        .post(
          Uri.parse("$baseUrl/auth/reset-password"),
          headers: _headers,
          body: jsonEncode(<String, String>{
            "email": email,
            "code": code,
            "password": password,
            "password_confirmation": password,
          }),
        )
        .timeout(timeoutDuration);

    _handleResponse(response);
  }

  /// Confirms the phone number of a registration with the code that was texted to it.
  static Future<void> verifyRegistrationPhone({
    required final String email,
    required final String code,
  }) async {
    final http.Response response = await http
        .post(
          Uri.parse("$baseUrl/auth/register/verify-phone"),
          headers: _headers,
          body: jsonEncode(<String, String>{"email": email, "code": code}),
        )
        .timeout(timeoutDuration);

    _handleResponse(response);
  }

  /// Texts a new phone-confirmation code for a registration.
  static Future<void> resendRegistrationCode({required final String email}) async {
    final http.Response response = await http
        .post(
          Uri.parse("$baseUrl/auth/register/resend-code"),
          headers: _headers,
          body: jsonEncode(<String, String>{"email": email}),
        )
        .timeout(timeoutDuration);

    _handleResponse(response);
  }

  /// Registers a business owner. Unlike an ordinary sign-up this does NOT sign
  /// anyone in: the account stays inactive until a super admin reviews the
  /// registration and assigns the services, so there is no token in the answer.
  ///
  /// A validation failure (422) is reported with every problem the server found,
  /// one per line, instead of Laravel's "(and 2 more errors)" summary.
  static Future<Map<String, dynamic>> registerBusiness(
    final BusinessRegistrationRequest request,
  ) async {
    final http.Response response = await http
        .post(
          Uri.parse("$baseUrl/auth/register"),
          headers: _headers,
          body: jsonEncode(request.toJson()),
        )
        .timeout(timeoutDuration);

    Map<String, dynamic> data;
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException {
      throw AuthHttpException(
          response.statusCode, "Jibu la seva halieleweki (${response.statusCode})");
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }

    final dynamic errors = data["errors"];
    if (response.statusCode == 422 && errors is Map && errors.isNotEmpty) {
      final List<String> lines = errors.values
          .expand((final v) => v is List ? v : <dynamic>[v])
          .map((final e) => e.toString())
          .toList();
      throw AuthHttpException(422, lines.join("\n"));
    }
    throw AuthHttpException(
      response.statusCode,
      (data["message"] ?? "Server error: ${response.statusCode}").toString(),
    );
  }

  // Logout method
  static Future<void> logout() async {
    try {
      final Map<String, String> headers = await _authHeaders;
      await http
          .post(
            Uri.parse("$baseUrl/auth/logout"),
            headers: headers,
          )
          .timeout(timeoutDuration);
    } on Exception catch (e) {
      // Continue with local logout even if server request fails
      developer.log("Logout request failed: $e");
    } finally {
      // Clear local storage
      await clearAuthData();
    }
  }

  // Get current user
  static Future<Map<String, dynamic>?> getCurrentUser() async {
    try {
      final Map<String, String> headers = await _authHeaders;
      final String url = "$baseUrl/auth/user";
      if (kDebugMode && ApiConfig.enableHttpLogs) {
        debugPrint('HTTP GET $url');
      }
      final http.Response response = await http
          .get(
            Uri.parse(url),
            headers: headers,
          )
          .timeout(timeoutDuration);
      if (kDebugMode && ApiConfig.enableHttpLogs) {
        debugPrint('HTTP <- $url status=${response.statusCode}');
        final String b = response.body;
        debugPrint(
            'Body (first 1000): ${b.length > 1000 ? '${b.substring(0, 1000)}...' : b}');
      }

      final Map<String, dynamic> raw = _handleResponse(response);
      // Normalize ResponseHelper structure: { success, message, data: { user, ... } }
      final Map<String, dynamic> payload = raw['data'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(raw['data'] as Map)
          : raw;

      // Update stored user data
      final Map<String, dynamic>? user = payload['user'] is Map
          ? Map<String, dynamic>.from(payload['user'] as Map)
          : null;
      if (user != null) {
        await saveUserData(user);
      }

      return user;
    } on AuthHttpException {
      rethrow; // keep the status code for the caller
    } on Exception catch (e) {
      throw Exception("Failed to get user data: $e");
    }
  }

  /// True only when the server itself says this token is no longer valid (401).
  /// A timeout, no signal or a 5xx says nothing about the session, so those must
  /// never be treated as "signed out".
  static bool isSessionInvalid(final Object error) =>
      error is AuthHttpException && error.statusCode == 401;

  /// The server wraps the new token as `{data: {token: ...}}`; older/other
  /// responses put it at the top level, so accept both.
  @visibleForTesting
  static String? tokenFromRefreshResponse(final Map<String, dynamic> body) {
    final Object? wrapped = body["data"];
    final Object? token =
        (wrapped is Map<String, dynamic> ? wrapped["token"] : null) ??
            body["token"];
    return token is String && token.isNotEmpty ? token : null;
  }

  // Refresh token
  static Future<String?> refreshToken() async {
    try {
      final Map<String, String> headers = await _authHeaders;
      final http.Response response = await http
          .post(
            Uri.parse("$baseUrl/auth/refresh"),
            headers: headers,
          )
          .timeout(timeoutDuration);

      final String? token = tokenFromRefreshResponse(_handleResponse(response));
      if (token == null) {
        return null;
      }

      await saveToken(token);
      return token;
    } on Exception catch (e) {
      throw Exception("Token refresh failed: $e");
    }
  }

  // Update profile
  static Future<Map<String, dynamic>> updateProfile({
    final String? name,
    final String? email,
    final String? phone,
  }) async {
    try {
      final Map<String, String> headers = await _authHeaders;
      final http.Response response = await http
          .put(
            Uri.parse("$baseUrl/auth/profile"),
            headers: headers,
            body: jsonEncode(<String, String?>{
              if (name != null) "name": name,
              if (email != null) "email": email,
              if (phone != null) "phone_number": phone,
            }),
          )
          .timeout(timeoutDuration);

      final Map<String, dynamic> data = _handleResponse(response);

      final Map<String, dynamic>? user =
          data['user'] is Map ? Map<String, dynamic>.from(data['user']) : null;
      if (user != null) {
        await saveUserData(user);
      }

      return data;
    } on Exception catch (e) {
      throw Exception("Profile update failed: $e");
    }
  }

  // Change password
  static Future<void> changePassword({
    required final String currentPassword,
    required final String newPassword,
    required final String confirmPassword,
  }) async {
    try {
      final Map<String, String> headers = await _authHeaders;
      final http.Response response = await http
          .post(
            Uri.parse("$baseUrl/auth/change-password"),
            headers: headers,
            body: jsonEncode(<String, String>{
              "current_password": currentPassword,
              "new_password": newPassword,
              "new_password_confirmation": confirmPassword,
            }),
          )
          .timeout(timeoutDuration);

      _handleResponse(response);
    } on Exception catch (e) {
      throw Exception("Change password failed: $e");
    }
  }

  // Token management
  static Future<void> saveToken(final String token) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(tokenKey, token);
  }

  static Future<String?> getToken() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString(tokenKey);
  }

  static Future<void> clearToken() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(tokenKey);
  }

  // User data management
  static Future<void> saveUserData(final Map<String, dynamic> userData) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(userKey, jsonEncode(userData));
  }

  static Future<Map<String, dynamic>?> getUserData() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? userDataString = prefs.getString(userKey);
    if (userDataString != null) {
      return jsonDecode(userDataString);
    }
    return null;
  }

  static Future<void> clearUserData() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(userKey);
  }

  // Clear all auth data
  static Future<void> clearAuthData() async {
    await clearToken();
    await clearUserData();
  }

  // Check if user is authenticated
  static Future<bool> isAuthenticated() async {
    final String? token = await getToken();
    return token != null && token.isNotEmpty;
  }

  // Validate token (check if it's still valid)
  static Future<bool> validateToken() async {
    try {
      await getCurrentUser();
      return true;
    } on Exception {
      return false;
    }
  }
}
