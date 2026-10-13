// ignore_for_file: cascade_invocations
import "package:flutter/foundation.dart";
import "../models/transaction.dart";
import "../services/api_service.dart";
import "../services/auth_service.dart";
import '../services/localization_service.dart';

class TransactionProvider extends ChangeNotifier {
  final ApiService _api = ApiService();

  List<Transaction> _transactions = <Transaction>[];
  List<Transaction> _filteredTransactions = <Transaction>[];
  bool _isLoading = false;
  String? _error;
  String _searchQuery = "";
  String _filterType = "all";

  // Getters
  List<Transaction> get transactions => _transactions;
  List<Transaction> get filteredTransactions => _filteredTransactions;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get searchQuery => _searchQuery;
  String get filterType => _filterType;

  // Load transactions from API
  Future<void> loadTransactions() async {
    _setLoading(true);
    _clearError();

    try {
      // Guard: only fetch when authenticated
      if (!await AuthService.isAuthenticated()) {
        _transactions = <Transaction>[];
        _applyFilters();
        return;
      }
      await _api.initialize();
      final Map<String, dynamic> resp = await _api.getTransactions();
      final dynamic data = resp["data"];
      List<dynamic> list = <dynamic>[];
      if (data is List) {
        list = data;
      } else if (data is Map && data["data"] is List) {
        list = data["data"];
      }
      _transactions = list
          .map<Transaction>(
            (final j) => Transaction.fromJson(j as Map<String, dynamic>),
          )
          .toList();
      _applyFilters();
    } on Exception catch (e) {
      _setError(LocalizationService.instance.translateWith('failed_to_load_transactions', <Object?>[e]));
      _transactions = <Transaction>[]; // Empty list instead of mock data
      _applyFilters();
    } finally {
      _setLoading(false);
    }
  }

  // Add new transaction
  Future<bool> addTransaction(final Transaction transaction) async {
    try {
      await _api.initialize();
      final Map<String, dynamic> resp =
          await _api.createTransaction(transaction.toJson());
      final Map<String, dynamic> createdJson =
          (resp["data"] ?? resp) as Map<String, dynamic>;
      final Transaction newTransaction = Transaction.fromJson(createdJson);
      _transactions.insert(0, newTransaction);
      _applyFilters();
      return true;
    } on Exception catch (e) {
      _setError(LocalizationService.instance.translateWith('failed_to_add_transaction', <Object?>[e]));
      return false;
    }
  }

  // Update transaction
  Future<bool> updateTransaction(final Transaction transaction) async {
    try {
      final Map<String, dynamic> resp = await _api.updateTransaction(
        transaction.id,
        transaction.toJson(),
      );
      final Map<String, dynamic> updatedJson =
          (resp["data"] ?? resp) as Map<String, dynamic>;
      final Transaction updatedTransaction = Transaction.fromJson(updatedJson);
      final int index = _transactions
          .indexWhere((final Transaction t) => t.id == transaction.id);
      if (index != -1) {
        _transactions[index] = updatedTransaction;
        _applyFilters();
      }
      return true;
    } on Exception catch (e) {
      _setError(LocalizationService.instance.translateWith('failed_to_update_transaction', <Object?>[e]));
      return false;
    }
  }

  // Delete transaction
  Future<bool> deleteTransaction(final String id) async {
    try {
      await _api.deleteTransaction(id);
      _transactions.removeWhere((final Transaction t) => t.id == id);
      _applyFilters();
      return true;
    } on Exception catch (e) {
      _setError(LocalizationService.instance.translateWith('failed_to_delete_transaction', <Object?>[e]));
      return false;
    }
  }

  // Filter transactions
  void filterTransactions(final String query) {
    _searchQuery = query;
    _applyFilters();
  }

  // Set filter type
  void setFilterType(final String type) {
    _filterType = type;
    _applyFilters();
  }

  // Apply filters and search
  void _applyFilters() {
    _filteredTransactions =
        _transactions.where((final Transaction transaction) {
      // Apply search filter
      bool matchesSearch = true;
      if (_searchQuery.isNotEmpty) {
        matchesSearch = transaction.description
                .toLowerCase()
                .contains(_searchQuery.toLowerCase()) ||
            transaction.category
                .toLowerCase()
                .contains(_searchQuery.toLowerCase()) ||
            transaction.amount.toString().contains(_searchQuery);
      }

      // Apply type filter
      bool matchesType = true;
      switch (_filterType) {
        case "income":
          matchesType = transaction.type == TransactionType.income;
        case "expense":
          matchesType = transaction.type == TransactionType.expense;
        case "today":
          final DateTime today = DateTime.now();
          matchesType = transaction.createdAt.day == today.day &&
              transaction.createdAt.month == today.month &&
              transaction.createdAt.year == today.year;
        case "week":
          final DateTime now = DateTime.now();
          final DateTime weekStart =
              now.subtract(Duration(days: now.weekday - 1));
          matchesType = transaction.createdAt.isAfter(weekStart);
        case "month":
          final DateTime now = DateTime.now();
          matchesType = transaction.createdAt.month == now.month &&
              transaction.createdAt.year == now.year;
        default:
          matchesType = true;
      }

      return matchesSearch && matchesType;
    }).toList();

    // Sort by date (newest first)
    _filteredTransactions.sort(
      (final Transaction a, final Transaction b) =>
          b.createdAt.compareTo(a.createdAt),
    );

    notifyListeners();
  }

  // Get revenue statistics
  Map<String, double> getRevenueStats() {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime weekStart = today.subtract(Duration(days: now.weekday - 1));
    final DateTime monthStart = DateTime(now.year, now.month);

    double todayRevenue = 0;
    double weekRevenue = 0;
    double monthRevenue = 0;
    double totalRevenue = 0;

    for (final Transaction transaction in _transactions) {
      if (transaction.type == TransactionType.income &&
          transaction.status == TransactionStatus.completed) {
        totalRevenue += transaction.amount;

        if (transaction.createdAt.isAfter(today)) {
          todayRevenue += transaction.amount;
        }

        if (transaction.createdAt.isAfter(weekStart)) {
          weekRevenue += transaction.amount;
        }

        if (transaction.createdAt.isAfter(monthStart)) {
          monthRevenue += transaction.amount;
        }
      }
    }

    return <String, double>{
      "today": todayRevenue,
      "week": weekRevenue,
      "month": monthRevenue,
      "total": totalRevenue,
    };
  }

  // Get recent transactions
  List<Transaction> getRecentTransactions(final int limit) {
    final List<Transaction> sortedTransactions =
        List<Transaction>.from(_transactions);
    sortedTransactions.sort(
      (final Transaction a, final Transaction b) =>
          b.createdAt.compareTo(a.createdAt),
    );
    return sortedTransactions.take(limit).toList();
  }

  // Get device revenue for today
  double getDeviceRevenueToday(final String deviceId) {
    final DateTime today = DateTime.now();
    final DateTime todayStart = DateTime(today.year, today.month, today.day);

    return _transactions
        .where(
          (final Transaction t) =>
              t.deviceId == deviceId &&
              t.type == TransactionType.income &&
              t.status == TransactionStatus.completed &&
              t.createdAt.isAfter(todayStart),
        )
        .fold(
          0,
          (final double sum, final Transaction t) => sum + t.amount,
        );
  }

  // Get transactions by date range
  List<Transaction> getTransactionsByDateRange(
    final DateTime startDate,
    final DateTime endDate,
  ) =>
      _transactions
          .where(
            (final Transaction t) =>
                t.createdAt.isAfter(startDate) && t.createdAt.isBefore(endDate),
          )
          .toList();

  // Get transactions by type
  List<Transaction> getTransactionsByType(final TransactionType type) =>
      _transactions.where((final Transaction t) => t.type == type).toList();

  // Get transactions by status
  List<Transaction> getTransactionsByStatus(final TransactionStatus status) =>
      _transactions.where((final Transaction t) => t.status == status).toList();

  // Get monthly revenue data for charts
  Map<String, double> getMonthlyRevenueData() {
    final Map<String, double> monthlyData = <String, double>{};
    final DateTime now = DateTime.now();

    for (int i = 11; i >= 0; i--) {
      final DateTime month = DateTime(now.year, now.month - i);
      final String monthKey = "${month.month}/${month.year}";
      monthlyData[monthKey] = 0;
    }

    for (final Transaction transaction in _transactions) {
      if (transaction.type == TransactionType.income &&
          transaction.status == TransactionStatus.completed) {
        final String monthKey =
            "${transaction.createdAt.month}/${transaction.createdAt.year}";
        if (monthlyData.containsKey(monthKey)) {
          monthlyData[monthKey] = monthlyData[monthKey]! + transaction.amount;
        }
      }
    }

    return monthlyData;
  }

  // Helper methods
  void _setLoading(final bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(final String error) {
    _error = error;
    notifyListeners();
  }

  void _clearError() {
    _error = null;
    notifyListeners();
  }
}
