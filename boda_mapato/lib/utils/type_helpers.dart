/// Type helper utilities to prevent InvalidType compilation errors
///
/// This file contains utility functions and type definitions to ensure
/// proper type inference and prevent compilation issues.
library;

import "dart:convert";
import "package:flutter/foundation.dart" show immutable;
import '../services/localization_service.dart';

class TypeHelpers {
  /// Safely cast dynamic to Map<String, dynamic>
  static Map<String, dynamic>? safeCastToMap(final value) {
    if (value is Map<String, dynamic>) {
      return value;
    } else if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return null;
  }

  /// Safely cast dynamic to List<Map<String, dynamic>>
  static List<Map<String, dynamic>>? safeCastToMapList(final value) {
    if (value is List<Map<String, dynamic>>) {
      return value;
    } else if (value is List) {
      try {
        return value
            .map((final item) => Map<String, dynamic>.from(item as Map))
            .toList();
      } on Exception {
        return null;
      }
    }
    return null;
  }

  /// Safely parse JSON string to Map
  static Map<String, dynamic>? safeJsonDecode(final String? jsonString) {
    if (jsonString == null || jsonString.isEmpty) return null;

    try {
      final decoded = jsonDecode(jsonString);
      return safeCastToMap(decoded);
    } on Exception {
      return null;
    }
  }

  /// Safely encode object to JSON string
  static String? safeJsonEncode(final object) {
    try {
      return jsonEncode(object);
    } on Exception {
      return null;
    }
  }

  /// Type-safe getter for Map values
  static T? safeGet<T>(final Map<String, dynamic>? map, final String key) {
    if (map == null || !map.containsKey(key)) return null;

    final value = map[key];
    if (value is T) {
      return value;
    }
    return null;
  }

  /// Type-safe getter with default value
  static T safeGetWithDefault<T>(
    final Map<String, dynamic>? map,
    final String key,
    final T defaultValue,
  ) =>
      safeGet<T>(map, key) ?? defaultValue;

  /// Ensure a value is of the expected type
  static T ensureType<T>(final value, final T defaultValue) {
    if (value is T) {
      return value;
    }
    return defaultValue;
  }

  /// Convert dynamic to double safely
  static double toDouble(final value, {final double defaultValue = 0}) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      return double.tryParse(value) ?? defaultValue;
    }
    return defaultValue;
  }

  /// Convert dynamic to int safely
  static int toInt(final value, {final int defaultValue = 0}) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) {
      return int.tryParse(value) ?? defaultValue;
    }
    return defaultValue;
  }

  /// Convert dynamic to string safely
  static String stringify(final value, {final String defaultValue = ""}) {
    if (value is String) return value;
    if (value != null) return value.toString();
    return defaultValue;
  }

  /// Convert dynamic to bool safely
  static bool toBool(final value, {final bool defaultValue = false}) {
    if (value is bool) return value;
    if (value is String) {
      return value.toLowerCase() == "true" || value == "1";
    }
    if (value is int) {
      return value != 0;
    }
    return defaultValue;
  }

  /// Convert dynamic to DateTime safely
  static DateTime? toDateTime(final value) {
    if (value is DateTime) return value;
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  /// Create a typed list from dynamic
  static List<T> createTypedList<T>(
    final value,
    T Function(Object?) converter,
  ) {
    if (value is List) {
      return value.map((final item) => converter(item)).toList();
    }
    return <T>[];
  }

  /// Validate that a Map has the expected structure
  static bool validateMapStructure(
    final Map<String, dynamic>? map,
    final List<String> requiredKeys,
  ) {
    if (map == null) return false;

    for (final String key in requiredKeys) {
      if (!map.containsKey(key)) return false;
    }
    return true;
  }
}

/// Type-safe filter options for UI components
@immutable
class FilterOption {
  const FilterOption({
    required this.key,
    required this.label,
    this.description,
  });

  factory FilterOption.fromJson(final Map<String, dynamic> json) =>
      FilterOption(
        key: TypeHelpers.stringify(json["key"]),
        label: TypeHelpers.stringify(json["label"]),
        description: TypeHelpers.safeGet<String>(json, "description"),
      );
  final String key;
  final String label;
  final String? description;

  Map<String, dynamic> toJson() => <String, dynamic>{
        "key": key,
        "label": label,
        if (description != null) "description": description,
      };

  @override
  bool operator ==(final Object other) =>
      identical(this, other) ||
      other is FilterOption &&
          runtimeType == other.runtimeType &&
          key == other.key;

  @override
  int get hashCode => key.hashCode;
}

/// Common filter options for the app
class CommonFilters {
  static List<FilterOption> get transactionFilters => <FilterOption>[
    FilterOption(key: "all", label: LocalizationService.instance.translate('all_3')),
    FilterOption(key: "income", label: LocalizationService.instance.translate('income')),
    FilterOption(key: "expense", label: LocalizationService.instance.translate('expenses')),
    FilterOption(key: "today", label: LocalizationService.instance.translate('today')),
    FilterOption(key: "week", label: LocalizationService.instance.translate('this_week')),
    FilterOption(key: "month", label: LocalizationService.instance.translate('this_month')),
  ];

  static List<FilterOption> get paymentStatusFilters => <FilterOption>[
    FilterOption(key: "all", label: LocalizationService.instance.translate('all_3')),
    FilterOption(key: "paid", label: LocalizationService.instance.translate('filter_paid_only')),
    FilterOption(key: "pending", label: LocalizationService.instance.translate('pending_4')),
    FilterOption(key: "overdue", label: LocalizationService.instance.translate('late_2')),
  ];

  static List<FilterOption> get driverStatusFilters => <FilterOption>[
    FilterOption(key: "all", label: LocalizationService.instance.translate('all_2')),
    FilterOption(key: "active", label: LocalizationService.instance.translate('active')),
    FilterOption(key: "inactive", label: LocalizationService.instance.translate('inactive_2')),
  ];
}
