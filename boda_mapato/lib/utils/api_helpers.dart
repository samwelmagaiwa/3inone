import "dart:convert";
import "dart:io";

import "package:flutter/foundation.dart";
import "package:http/http.dart" as http;

import "../config/api_config.dart";
import 'server_message.dart';

class ApiHelpers {
  // Default timeout duration
  static Duration get defaultTimeout => ApiConfig.timeoutDuration;

  // Common headers
  static Map<String, String> get defaultHeaders => <String, String>{
        "Content-Type": "application/json",
        "Accept": "application/json",
      };

  // Handle HTTP response
  static Map<String, dynamic> handleResponse(final http.Response response) {
    try {
      final Map<String, dynamic> data = jsonDecode(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return data;
      } else {
        throw ApiException(
          message: data["message"] ?? "Server error",
          statusCode: response.statusCode,
          errors: data["errors"],
        );
      }
    } on Exception catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        message: "Failed to parse response: ${readableErrorMessage(e)}",
        statusCode: response.statusCode,
      );
    }
  }

  // Handle network errors
  static Exception handleNetworkError(final error) {
    if (error is SocketException) {
      return const NetworkException("No internet connection");
    } else if (error is HttpException) {
      return NetworkException("HTTP error: ${error.message}");
    } else if (error is FormatException) {
      return const NetworkException("Invalid response format");
    } else {
      return NetworkException("Network error: ${readableErrorMessage(error)}");
    }
  }

  // Build query string from parameters
  static String buildQueryString(final Map<String, dynamic> params) {
    if (params.isEmpty) return "";

    final String queryParams = params.entries
        .where((final MapEntry<String, dynamic> entry) => entry.value != null)
        .map(
          (final MapEntry<String, dynamic> entry) =>
              "${entry.key}=${Uri.encodeComponent(entry.value.toString())}",
        )
        .join("&");

    return queryParams.isNotEmpty ? "?$queryParams" : "";
  }

  // Build URL with query parameters
  static String buildUrl(
    final String baseUrl,
    final String endpoint, [
    final Map<String, dynamic>? params,
  ]) {
    final String url = baseUrl.endsWith("/") ? baseUrl : "$baseUrl/";
    final String cleanEndpoint =
        endpoint.startsWith("/") ? endpoint.substring(1) : endpoint;
    final String queryString = params != null ? buildQueryString(params) : "";

    return "$url$cleanEndpoint$queryString";
  }

  // Retry mechanism for API calls
  static Future<T> retryApiCall<T>(
    final Future<T> Function() apiCall, {
    final int maxRetries = 3,
    final Duration delay = const Duration(seconds: 1),
  }) async {
    int attempts = 0;

    while (attempts < maxRetries) {
      try {
        return await apiCall();
      } on Exception catch (e) {
        attempts++;

        if (attempts >= maxRetries) {
          rethrow;
        }

        // Don"t retry on client errors (4xx)
        if (e is ApiException && e.statusCode >= 400 && e.statusCode < 500) {
          rethrow;
        }

        await Future.delayed(delay * attempts);
      }
    }

    throw Exception("Max retries exceeded");
  }

  // Check if response is successful
  static bool isSuccessResponse(final int statusCode) =>
      statusCode >= 200 && statusCode < 300;

  // Check if response is client error
  static bool isClientError(final int statusCode) =>
      statusCode >= 400 && statusCode < 500;

  // Check if response is server error
  static bool isServerError(final int statusCode) => statusCode >= 500;

  // Format error message from API response
  static String formatErrorMessage(final Map<String, dynamic>? errors) {
    if (errors == null || errors.isEmpty) {
      return "An unknown error occurred";
    }

    final List<String> errorMessages = <String>[];

    errors.forEach((final String field, final messages) {
      if (messages is List) {
        errorMessages.addAll(messages.cast<String>());
      } else if (messages is String) {
        errorMessages.add(messages);
      }
    });

    return errorMessages.join("\n");
  }

  // Validate JSON structure
  static bool isValidJson(final String jsonString) {
    try {
      jsonDecode(jsonString);
      return true;
    } on Exception {
      return false;
    }
  }

  // Safe JSON decode
  static Map<String, dynamic>? safeJsonDecode(final String jsonString) {
    try {
      final decoded = jsonDecode(jsonString);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on Exception {
      return null;
    }
  }

  // Convert object to JSON safely
  static String? safeJsonEncode(final object) {
    try {
      return jsonEncode(object);
    } on Exception {
      return null;
    }
  }

  // Clean and validate URL
  static String? validateUrl(final String url) {
    try {
      final Uri uri = Uri.parse(url);
      if (uri.hasScheme && (uri.scheme == "http" || uri.scheme == "https")) {
        return uri.toString();
      }
      return null;
    } on Exception {
      return null;
    }
  }

  // Get error message from exception
  static String getErrorMessage(final error) {
    if (error is ApiException) {
      return error.message;
    } else if (error is NetworkException) {
      return error.message;
    } else if (error is SocketException) {
      return "No internet connection";
    } else if (error is HttpException) {
      return "HTTP error: ${error.message}";
    } else if (error is FormatException) {
      return "Invalid data format";
    } else {
      return error.toString();
    }
  }

  // Log API request (for debugging)
  static void logRequest(
    final String method,
    final String url, [
    final Map<String, dynamic>? data,
  ]) {
    debugPrint("API Request: $method $url");
    if (data != null) {
      debugPrint("Data: ${jsonEncode(data)}");
    }
  }

  // Log API response (for debugging)
  static void logResponse(final http.Response response) {
    debugPrint("API Response: ${response.statusCode}");
    debugPrint("Body: ${response.body}");
  }

  // Create multipart request for file uploads
  static http.MultipartRequest createMultipartRequest(
    final String method,
    final String url, {
    final Map<String, String>? headers,
    final Map<String, String>? fields,
  }) {
    final http.MultipartRequest request =
        http.MultipartRequest(method, Uri.parse(url));

    if (headers != null) {
      request.headers.addAll(headers);
    }

    if (fields != null) {
      request.fields.addAll(fields);
    }

    return request;
  }

  // Add file to multipart request
  static Future<void> addFileToRequest(
    final http.MultipartRequest request,
    final String fieldName,
    final String filePath,
  ) async {
    try {
      request.files.add(await http.MultipartFile.fromPath(fieldName, filePath));
    } on Exception {
      // Ignore if file cannot be added
    }
  }

  // Parse pagination info from response
  static PaginationInfo? parsePaginationInfo(
    final Map<String, dynamic> response,
  ) {
    final Map<String, dynamic>? meta = response["meta"] is Map
        ? Map<String, dynamic>.from(response["meta"])
        : null;
    if (meta == null) return null;

    return PaginationInfo(
      currentPage: meta["current_page"] as int? ?? 1,
      lastPage: meta["last_page"] as int? ?? 1,
      perPage: meta["per_page"] as int? ?? 10,
      total: meta["total"] as int? ?? 0,
      from: meta["from"] as int? ?? 0,
      to: meta["to"] as int? ?? 0,
    );
  }

  // Build pagination query parameters
  static Map<String, dynamic> buildPaginationParams({
    final int page = 1,
    final int perPage = 10,
    final String? sortBy,
    final String? sortOrder,
  }) =>
      <String, dynamic>{
        "page": page,
        "per_page": perPage,
        if (sortBy != null) "sort_by": sortBy,
        if (sortOrder != null) "sort_order": sortOrder,
      };
}

// Custom exception classes
class ApiException implements Exception {
  const ApiException({
    required this.message,
    required this.statusCode,
    this.errors,
  });
  final String message;
  final int statusCode;
  final Map<String, dynamic>? errors;

  @override
  String toString() => message;
}

class NetworkException implements Exception {
  const NetworkException(this.message);
  final String message;

  @override
  String toString() => "NetworkException: $message";
}

// Pagination info class
class PaginationInfo {
  const PaginationInfo({
    required this.currentPage,
    required this.lastPage,
    required this.perPage,
    required this.total,
    required this.from,
    required this.to,
  });
  final int currentPage;
  final int lastPage;
  final int perPage;
  final int total;
  final int from;
  final int to;

  bool get hasNextPage => currentPage < lastPage;
  bool get hasPreviousPage => currentPage > 1;
  int get totalPages => lastPage;

  @override
  String toString() =>
      "Page $currentPage of $lastPage ($from-$to of $total items)";
}

// API response wrapper
class ApiResponse<T> {
  const ApiResponse({
    required this.data,
    this.message,
    this.success = true,
    this.pagination,
  });

  factory ApiResponse.fromJson(
    final Map<String, dynamic> json,
    final T Function(Map<String, dynamic>) fromJsonT,
  ) =>
      ApiResponse<T>(
        data: fromJsonT(json["data"]),
        message: json["message"],
        success: json["success"] ?? true,
        pagination: ApiHelpers.parsePaginationInfo(json),
      );
  final T data;
  final String? message;
  final bool success;
  final PaginationInfo? pagination;
}
