// ignore_for_file: avoid_dynamic_calls
import "dart:async";

import 'package:auto_size_text/auto_size_text.dart';
import "package:flutter/material.dart";
import 'package:flutter_screenutil/flutter_screenutil.dart';
import "package:provider/provider.dart";

import "../../constants/colors.dart";
import "../../constants/strings.dart";
import "../../constants/styles.dart";
import "../../constants/theme_constants.dart";
import "../../providers/auth_provider.dart";
import "../../services/api_service.dart";
import "../../widgets/custom_button.dart";
import "../../widgets/custom_card.dart";

class ReceiptScreen extends StatefulWidget {
  const ReceiptScreen({super.key});

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _customerNameController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _serviceTypeController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final ApiService _apiService = ApiService();
  bool _isGenerating = false;
  List<Map<String, dynamic>> _recentReceipts = <Map<String, dynamic>>[];
  bool _isLoadingReceipts = true;

  @override
  void initState() {
    super.initState();
    _initializeAndLoadData();
  }

  Future<void> _initializeAndLoadData() async {
    await _apiService.initialize();
    await _loadRecentReceipts();
  }

  @override
  void dispose() {
    _customerNameController.dispose();
    _amountController.dispose();
    _serviceTypeController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadRecentReceipts() async {
    try {
      final Map<String, dynamic> response = await _apiService.getReceipts();

      if (mounted) {
        setState(() {
          if (response["data"] is Map<String, dynamic>) {
            _recentReceipts = List<Map<String, dynamic>>.from(
                response["data"]["data"] ?? <Map<String, dynamic>>[]);
          } else if (response["data"] is List) {
            _recentReceipts = List<Map<String, dynamic>>.from(response["data"]);
          } else {
            _recentReceipts = <Map<String, dynamic>>[];
          }
          _isLoadingReceipts = false;
        });
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingReceipts = false;
        });
        ThemeConstants.showErrorSnackBar(
            context, "Hitilafu katika kupakia risiti: $e");
      }
    }
  }

  Future<void> _generateReceipt() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isGenerating = true;
    });

    try {
      final Map<String, dynamic> receiptData = <String, dynamic>{
        "customer_name": _customerNameController.text.trim(),
        "amount": double.parse(_amountController.text),
        "service_type": _serviceTypeController.text.trim(),
        "notes": _notesController.text.trim(),
        "date": DateTime.now().toIso8601String(),
      };

      final Map<String, dynamic> response =
          await _apiService.generateReceipt(receiptData);

      if (mounted) {
        _showReceiptPreview(response["data"]);
        _clearForm();
        unawaited(_loadRecentReceipts()); // Reload to show new receipt
      }
    } on Exception catch (e) {
      if (mounted) {
        ThemeConstants.showErrorSnackBar(
            context, "Hitilafu katika kutengeneza risiti: $e");
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  void _clearForm() {
    _customerNameController.clear();
    _amountController.clear();
    _serviceTypeController.clear();
    _notesController.clear();
  }

  void _showReceiptPreview([Map<String, dynamic>? receiptData]) {
    showDialog(
      context: context,
      builder: (final BuildContext context) => _ReceiptPreviewDialog(
        receiptData: receiptData ??
            <String, dynamic>{
              "customer_name": _customerNameController.text,
              "amount": double.parse(_amountController.text),
              "service_type": _serviceTypeController.text,
              "notes": _notesController.text,
              "receipt_number": "TEMP-${DateTime.now().millisecondsSinceEpoch}",
              "date": DateTime.now().toIso8601String(),
            },
      ),
    );
  }

  @override
  Widget build(final BuildContext context) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text(
            AppStrings.receipts,
            style: AppStyles.heading2,
          ),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(AppStyles.spacingM),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // Header
                CustomCard(
                  child: Padding(
                    padding: const EdgeInsets.all(AppStyles.spacingM),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          Icons.receipt_long,
                          size: 32.sp,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: AppStyles.spacingM),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const Text(
                                AppStrings.generateReceipt,
                                style: AppStyles.heading3,
                              ),
                              const SizedBox(height: AppStyles.spacingXS),
                              Text(
                                "Tengeneza risiti kwa ajili ya huduma uliyotoa",
                                style: AppStyles.bodySmall.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: AppStyles.spacingL),

                // Form Fields
                const Text(
                  "Taarifa za Risiti",
                  style: AppStyles.heading3,
                ),
                const SizedBox(height: AppStyles.spacingM),

                // Customer Name
                TextFormField(
                  controller: _customerNameController,
                  decoration: AppStyles.inputDecoration(context).copyWith(
                    labelText: AppStrings.customerName,
                    hintText: "Jina la mteja",
                    prefixIcon: const Icon(Icons.person),
                  ),
                  validator: (final String? value) {
                    if (value == null || value.trim().isEmpty) {
                      return AppStrings.fieldRequired;
                    }
                    return null;
                  },
                ),

                const SizedBox(height: AppStyles.spacingM),

                // Amount
                TextFormField(
                  controller: _amountController,
                  decoration: AppStyles.inputDecoration(context).copyWith(
                    labelText: AppStrings.amount,
                    hintText: "0",
                    prefixText: "TSh ",
                    prefixIcon: const Icon(Icons.money),
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

                // Service Type
                TextFormField(
                  controller: _serviceTypeController,
                  decoration: AppStyles.inputDecoration(context).copyWith(
                    labelText: AppStrings.serviceType,
                    hintText: "Mfano: Safari ya Boda",
                    prefixIcon: const Icon(Icons.work),
                  ),
                  validator: (final String? value) {
                    if (value == null || value.trim().isEmpty) {
                      return AppStrings.fieldRequired;
                    }
                    return null;
                  },
                ),

                const SizedBox(height: AppStyles.spacingM),

                // Notes (Optional)
                TextFormField(
                  controller: _notesController,
                  decoration: AppStyles.inputDecoration(context).copyWith(
                    labelText: "Maelezo ya Ziada (Si lazima)",
                    hintText: "Maelezo mengine...",
                    prefixIcon: const Icon(Icons.note),
                  ),
                  maxLines: 3,
                ),

                const SizedBox(height: AppStyles.spacingXL),

                // Generate Button
                SizedBox(
                  width: double.infinity,
                  child: CustomButton(
                    text: _isGenerating
                        ? "Inatengeneza..."
                        : AppStrings.generateReceipt,
                    onPressed: _isGenerating ? null : _generateReceipt,
                    isLoading: _isGenerating,
                  ),
                ),

                const SizedBox(height: AppStyles.spacingL),

                // Recent Receipts Section
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    const Text(
                      "Risiti za Hivi Karibuni",
                      style: AppStyles.heading3,
                    ),
                    if (!_isLoadingReceipts && _recentReceipts.isNotEmpty)
                      TextButton(
                        onPressed: _loadRecentReceipts,
                        child: const Text("Onyesha Zote"),
                      ),
                  ],
                ),
                const SizedBox(height: AppStyles.spacingM),

                // Recent receipts list
                if (_isLoadingReceipts)
                  const Center(child: CircularProgressIndicator())
                else if (_recentReceipts.isEmpty)
                  CustomCard(
                    child: Padding(
                      padding: const EdgeInsets.all(AppStyles.spacingL),
                      child: Column(
                        children: <Widget>[
                          Icon(
                            Icons.receipt,
                            size: 48.sp,
                            color: AppColors.textHint,
                          ),
                          const SizedBox(height: AppStyles.spacingM),
                          Text(
                            "Hakuna risiti za hivi karibuni",
                            style: AppStyles.bodyMedium.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ..._recentReceipts.take(3).map(
                        (Map<String, dynamic> receipt) => Padding(
                          padding:
                              const EdgeInsets.only(bottom: AppStyles.spacingM),
                          child: CustomCard(
                            onTap: () => _showReceiptPreview(receipt),
                            child: Padding(
                              padding: const EdgeInsets.all(AppStyles.spacingM),
                              child: Row(
                                children: <Widget>[
                                  const Icon(
                                    Icons.receipt_long,
                                    color: AppColors.primary,
                                  ),
                                  const SizedBox(width: AppStyles.spacingM),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(
                                          receipt["customer_name"] ?? "N/A",
                                          style: AppStyles.bodyMedium.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          receipt["service_type"] ?? "N/A",
                                          style: AppStyles.bodySmall.copyWith(
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: <Widget>[
                                      Text(
                                        "TSh ${receipt["amount"] ?? 0}",
                                        style: AppStyles.bodyMedium.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                      Text(
                                        receipt["receipt_number"] ?? "N/A",
                                        style: AppStyles.bodySmall.copyWith(
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
              ],
            ),
          ),
        ),
      );
}

class _ReceiptPreviewDialog extends StatelessWidget {
  const _ReceiptPreviewDialog({
    required this.receiptData,
  });
  final Map<String, dynamic> receiptData;

  @override
  Widget build(final BuildContext context) {
    final String receiptNumber = receiptData["receipt_number"] ??
        "R${DateTime.now().millisecondsSinceEpoch}";
    final DateTime currentDate = receiptData["date"] != null
        ? DateTime.tryParse(receiptData["date"]) ?? DateTime.now()
        : DateTime.now();
    final String customerName = receiptData["customer_name"] ?? "N/A";
    final double amount = (receiptData["amount"] ?? 0).toDouble();
    final String serviceType = receiptData["service_type"] ?? "N/A";
    final String notes = receiptData["notes"] ?? "";
    // Whose receipt it is: the signed-in person's own business, not the platform's name.
    final business = context.read<AuthProvider>().user?.business;

    return Dialog(
      child: Container(
        padding: const EdgeInsets.all(AppStyles.spacingM),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Header
            Row(
              children: <Widget>[
                const Expanded(
                  child: AutoSizeText(
                    "Muhtasari wa Risiti",
                    style: AppStyles.heading3,
                    maxLines: 1,
                    stepGranularity: 0.5,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close, size: 18.sp),
                ),
              ],
            ),

            const Divider(),

            // Receipt Content
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppStyles.spacingM),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.textHint),
                borderRadius: BorderRadius.circular(AppStyles.radiusM(context)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // Business Header
                  Center(
                    child: Text(
                      business?.name.toUpperCase() ?? "3 IN ONE",
                      key: const ValueKey<String>("receipt_business_name"),
                      textAlign: TextAlign.center,
                      style: AppStyles.heading2,
                    ),
                  ),
                  if (business == null)
                    const Center(
                      child: Text(
                        "Mfumo wa Usimamizi wa Mapato",
                        style: AppStyles.bodySmall,
                      ),
                    )
                  else ...<Widget>[
                    if (business.address.isNotEmpty)
                      Center(child: Text(business.address, textAlign: TextAlign.center, style: AppStyles.bodySmall)),
                    if (business.phone.isNotEmpty)
                      Center(child: Text("Simu: ${business.phone}", style: AppStyles.bodySmall)),
                    if (business.tin.isNotEmpty)
                      Center(child: Text("TIN: ${business.tin}", style: AppStyles.bodySmall)),
                  ],

                  const SizedBox(height: AppStyles.spacingM),
                  const Divider(),

                  // Receipt Details
                  _ReceiptRow("Nambari ya Risiti:", receiptNumber),
                  _ReceiptRow(
                    "Tarehe:",
                    "${currentDate.day}/${currentDate.month}/${currentDate.year}",
                  ),
                  _ReceiptRow(
                    "Muda:",
                    "${currentDate.hour}:${currentDate.minute.toString().padLeft(2, "0")}",
                  ),

                  const SizedBox(height: AppStyles.spacingM),
                  const Divider(),

                  // Customer & Service Details
                  _ReceiptRow("Mteja:", customerName),
                  _ReceiptRow("Huduma:", serviceType),
                  if (notes.isNotEmpty) _ReceiptRow("Maelezo:", notes),

                  const SizedBox(height: AppStyles.spacingM),
                  const Divider(),

                  // Amount
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      const Text(
                        "JUMLA:",
                        style: AppStyles.heading3,
                      ),
                      Text(
                        "TSh ${amount.toStringAsFixed(0)}",
                        style: AppStyles.heading3.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: AppStyles.spacingM),
                  const Divider(),

                  // Footer
                  const Center(
                    child: Text(
                      "Asante kwa kutumia huduma zetu!",
                      style: AppStyles.bodySmall,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppStyles.spacingL),

            // Action Buttons
            Row(
              children: <Widget>[
                Expanded(
                  child: CustomButton(
                    text: AppStrings.printReceipt,
                    onPressed: () {
                      Navigator.pop(context);
                      ThemeConstants.showSuccessSnackBar(
                          context, AppStrings.receiptGenerated);
                    },
                    backgroundColor: AppColors.primary,
                  ),
                ),
                const SizedBox(width: AppStyles.spacingM),
                Expanded(
                  child: CustomButton(
                    text: "Hifadhi",
                    onPressed: () {
                      Navigator.pop(context);
                      ThemeConstants.showSuccessSnackBar(
                          context, "Risiti imehifadhiwa");
                    },
                    backgroundColor: AppColors.success,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(final BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppStyles.spacingS),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 100,
              child: Text(
                label,
                style: AppStyles.bodySmall.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: AppStyles.bodySmall,
              ),
            ),
          ],
        ),
      );
}
