import "package:flutter/foundation.dart";
import '../services/localization_service.dart';

enum TransactionType {
  income,
  expense,
}

enum TransactionStatus {
  pending,
  completed,
  cancelled,
}

extension TransactionTypeExtension on TransactionType {
  String get name {
    switch (this) {
      case TransactionType.income:
        return LocalizationService.instance.translate('income');
      case TransactionType.expense:
        return LocalizationService.instance.translate('expenses');
    }
  }
}

extension TransactionStatusExtension on TransactionStatus {
  String get name {
    switch (this) {
      case TransactionStatus.pending:
        return LocalizationService.instance.translate('pending_2');
      case TransactionStatus.completed:
        return LocalizationService.instance.translate('status_completed');
      case TransactionStatus.cancelled:
        return LocalizationService.instance.translate('cancelled');
    }
  }
}

@immutable
class Transaction {
  const Transaction({
    required this.id,
    required this.amount,
    required this.type,
    required this.status,
    required this.description,
    required this.category,
    required this.deviceId,
    required this.driverId,
    required this.createdAt,
    required this.updatedAt,
    this.receiptNumber,
    this.customerName,
    this.notes,
  });

  factory Transaction.fromJson(final Map<String, dynamic> json) => Transaction(
        id: json["id"] ?? "",
        amount: (json["amount"] as num? ?? 0).toDouble(),
        type: _parseTransactionType(json["type"]),
        status: _parseTransactionStatus(json["status"]),
        description: json["description"] ?? "",
        category: json["category"] ?? "",
        deviceId: json["device_id"] ?? "",
        driverId: json["driver_id"] ?? "",
        createdAt: DateTime.parse(
          json["created_at"] ?? DateTime.now().toIso8601String(),
        ),
        updatedAt: DateTime.parse(
          json["updated_at"] ?? DateTime.now().toIso8601String(),
        ),
        receiptNumber: json["receipt_number"],
        customerName: json["customer_name"],
        notes: json["notes"],
      );
  final String id;
  final double amount;
  final TransactionType type;
  final TransactionStatus status;
  final String description;
  final String category;
  final String deviceId;
  final String driverId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? receiptNumber;
  final String? customerName;
  final String? notes;

  static TransactionType _parseTransactionType(final String? type) {
    switch (type?.toLowerCase()) {
      case "income":
        return TransactionType.income;
      case "expense":
        return TransactionType.expense;
      default:
        return TransactionType.income;
    }
  }

  static TransactionStatus _parseTransactionStatus(final String? status) {
    switch (status?.toLowerCase()) {
      case "pending":
        return TransactionStatus.pending;
      case "completed":
        return TransactionStatus.completed;
      case "cancelled":
        return TransactionStatus.cancelled;
      default:
        return TransactionStatus.pending;
    }
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        "id": id,
        "amount": amount,
        "type": type.name.toLowerCase(),
        "status": status.name.toLowerCase(),
        "description": description,
        "category": category,
        "device_id": deviceId,
        "driver_id": driverId,
        "created_at": createdAt.toIso8601String(),
        "updated_at": updatedAt.toIso8601String(),
        "receipt_number": receiptNumber,
        "customer_name": customerName,
        "notes": notes,
      };

  Transaction copyWith({
    final String? id,
    final double? amount,
    final TransactionType? type,
    final TransactionStatus? status,
    final String? description,
    final String? category,
    final String? deviceId,
    final String? driverId,
    final DateTime? createdAt,
    final DateTime? updatedAt,
    final String? receiptNumber,
    final String? customerName,
    final String? notes,
  }) =>
      Transaction(
        id: id ?? this.id,
        amount: amount ?? this.amount,
        type: type ?? this.type,
        status: status ?? this.status,
        description: description ?? this.description,
        category: category ?? this.category,
        deviceId: deviceId ?? this.deviceId,
        driverId: driverId ?? this.driverId,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        receiptNumber: receiptNumber ?? this.receiptNumber,
        customerName: customerName ?? this.customerName,
        notes: notes ?? this.notes,
      );

  @override
  String toString() =>
      "Transaction(id: $id, amount: $amount, type: ${type.name}, "
      "status: ${status.name}, description: $description, "
      "category: $category)";

  @override
  bool operator ==(final Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is Transaction && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
