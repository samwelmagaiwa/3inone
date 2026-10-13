import 'package:auto_size_text/auto_size_text.dart';
import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "../../constants/colors.dart";
import "../../constants/strings.dart";
import "../../constants/styles.dart";
import "../../constants/theme_constants.dart";
import "../../models/transaction.dart";
import "../../providers/transaction_provider.dart";
import "../../widgets/custom_card.dart";
import "../../widgets/transaction_tile.dart";
import "transaction_detail.dart";
import '../../services/localization_service.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  String _selectedFilter = "all";
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTransactions() async {
    await Provider.of<TransactionProvider>(context, listen: false)
        .loadTransactions();
  }

  void _showAddTransactionDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (final BuildContext context) => const _AddTransactionSheet(),
    );
  }

  @override
  Widget build(final BuildContext context) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(
            AppStrings.transactions,
            style: AppStyles.heading2,
          ),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          actions: <Widget>[
            IconButton(
              icon: const Icon(Icons.filter_list),
              onPressed: _showFilterDialog,
            ),
          ],
        ),
        body: Column(
          children: <Widget>[
            // Search Bar
            Container(
              padding: const EdgeInsets.all(AppStyles.spacingM),
              color: AppColors.primary,
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: AppStrings.search,
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppStyles.radiusM(context)),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
                onChanged: (final String value) {
                  Provider.of<TransactionProvider>(context, listen: false)
                      .filterTransactions(value);
                },
              ),
            ),

            // Transactions List
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadTransactions,
                child: Consumer<TransactionProvider>(
                  builder: (
                    final BuildContext context,
                    final TransactionProvider transactionProvider,
                    final Widget? child,
                  ) {
                    final List<Transaction> transactions =
                        transactionProvider.filteredTransactions;

                    if (transactionProvider.isLoading) {
                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    }

                    if (transactions.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            const Icon(
                              Icons.receipt_long,
                              size: 64,
                              color: AppColors.textHint,
                            ),
                            const SizedBox(height: AppStyles.spacingM),
                            Text(
                              AppStrings.noDataFound,
                              style: AppStyles.bodyLarge.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(AppStyles.spacingM),
                      itemCount: transactions.length,
                      itemBuilder:
                          (final BuildContext context, final int index) {
                        final Transaction transaction = transactions[index];
                        return Padding(
                          padding:
                              const EdgeInsets.only(bottom: AppStyles.spacingM),
                          child: CustomCard(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (final BuildContext context) =>
                                      TransactionDetailScreen(
                                    transaction: transaction,
                                  ),
                                ),
                              );
                            },
                            child: TransactionTile(
                              transaction: transaction,
                              showDate: true,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _showAddTransactionDialog,
          backgroundColor: AppColors.primary,
          child: const Icon(Icons.add, color: Colors.white),
        ),
      );

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (final BuildContext context) => AlertDialog(
        title: AutoSizeText(
          LocalizationService.instance.translate('filter_transactions'),
          maxLines: 1,
          stepGranularity: 0.5,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _FilterOption(
              title: LocalizationService.instance.translate('all_3'),
              value: "all",
              selectedValue: _selectedFilter,
              onChanged: (final String? value) {
                setState(() {
                  _selectedFilter = value!;
                });
                Navigator.pop(context);
              },
            ),
            _FilterOption(
              title: LocalizationService.instance.translate('income'),
              value: "income",
              selectedValue: _selectedFilter,
              onChanged: (final String? value) {
                setState(() {
                  _selectedFilter = value!;
                });
                Navigator.pop(context);
              },
            ),
            _FilterOption(
              title: LocalizationService.instance.translate('expenses'),
              value: "expense",
              selectedValue: _selectedFilter,
              onChanged: (final String? value) {
                setState(() {
                  _selectedFilter = value!;
                });
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterOption extends StatelessWidget {
  const _FilterOption({
    required this.title,
    required this.value,
    required this.selectedValue,
    required this.onChanged,
  });
  final String title;
  final String value;
  final String selectedValue;
  final Function(String?) onChanged;

  @override
  Widget build(final BuildContext context) => RadioListTile<String>(
        title: Text(title),
        value: value,
        groupValue: selectedValue,
        onChanged: onChanged,
      );
}

class _AddTransactionSheet extends StatefulWidget {
  const _AddTransactionSheet();

  @override
  State<_AddTransactionSheet> createState() => _AddTransactionSheetState();
}

class _AddTransactionSheetState extends State<_AddTransactionSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _categoryController = TextEditingController();
  TransactionType _selectedType = TransactionType.income;
  bool _isLoading = false;

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  Future<void> _saveTransaction() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final Transaction transaction = Transaction(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        amount: double.parse(_amountController.text),
        type: _selectedType,
        status: TransactionStatus.completed,
        description: _descriptionController.text.trim(),
        category: _categoryController.text.trim(),
        deviceId: "current_device_id", // Replace with actual device ID
        driverId: "current_driver_id", // Replace with actual driver ID
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await Provider.of<TransactionProvider>(context, listen: false)
          .addTransaction(transaction);

      if (mounted) {
        Navigator.pop(context);
        ThemeConstants.showSuccessSnackBar(
            context, AppStrings.transactionSaved);
      }
    } on Exception catch (e) {
      if (mounted) {
        ThemeConstants.showErrorSnackBar(context, LocalizationService.instance.translateWith('error_2', <Object?>[e]));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(final BuildContext context) => Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          padding: const EdgeInsets.all(AppStyles.spacingM),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppStyles.radiusL(context)),
            ),
          ),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  AppStrings.newTransaction,
                  style: AppStyles.heading2,
                ),
                const SizedBox(height: AppStyles.spacingL),

                // Transaction Type
                Row(
                  children: <Widget>[
                    Expanded(
                      child: RadioListTile<TransactionType>(
                        title: Text(AppStrings.income),
                        value: TransactionType.income,
                        groupValue: _selectedType,
                        onChanged: (final TransactionType? value) {
                          setState(() {
                            _selectedType = value!;
                          });
                        },
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<TransactionType>(
                        title: Text(AppStrings.expense),
                        value: TransactionType.expense,
                        groupValue: _selectedType,
                        onChanged: (final TransactionType? value) {
                          setState(() {
                            _selectedType = value!;
                          });
                        },
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: AppStyles.spacingM),

                // Amount
                TextFormField(
                  controller: _amountController,
                  decoration: AppStyles.inputDecoration(context).copyWith(
                    labelText: AppStrings.amount,
                    prefixText: "TSh ",
                  ),
                  keyboardType: TextInputType.number,
                  validator: (final String? value) {
                    if (value == null || value.trim().isEmpty) {
                      return AppStrings.fieldRequired;
                    }
                    if (double.tryParse(value) == null) {
                      return AppStrings.invalidAmount;
                    }
                    return null;
                  },
                ),

                const SizedBox(height: AppStyles.spacingM),

                // Description
                TextFormField(
                  controller: _descriptionController,
                  decoration: AppStyles.inputDecoration(context).copyWith(
                    labelText: AppStrings.description,
                  ),
                  validator: (final String? value) {
                    if (value == null || value.trim().isEmpty) {
                      return AppStrings.fieldRequired;
                    }
                    return null;
                  },
                ),

                const SizedBox(height: AppStyles.spacingM),

                // Category
                TextFormField(
                  controller: _categoryController,
                  decoration: AppStyles.inputDecoration(context).copyWith(
                    labelText: AppStrings.category,
                  ),
                  validator: (final String? value) {
                    if (value == null || value.trim().isEmpty) {
                      return AppStrings.fieldRequired;
                    }
                    return null;
                  },
                ),

                const SizedBox(height: AppStyles.spacingL),

                // Save Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _saveTransaction,
                    style: AppStyles.primaryButton(context),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(AppStrings.save),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
