// ignore_for_file: avoid_dynamic_calls
import "package:flutter/material.dart";

import "../../constants/theme_constants.dart";
import "../../services/api_service.dart";
import "../../services/app_events.dart";
import "../../widgets/custom_button.dart";
import "../../widgets/custom_card.dart";
import '../../services/localization_service.dart';

class RecordPaymentScreen extends StatefulWidget {
  const RecordPaymentScreen({super.key});

  @override
  State<RecordPaymentScreen> createState() => _RecordPaymentScreenState();
}

class _RecordPaymentScreenState extends State<RecordPaymentScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _customerNameController = TextEditingController();
  final TextEditingController _customerPhoneController =
      TextEditingController();

  final ApiService _apiService = ApiService();

  bool _isLoading = false;
  bool _isLoadingDrivers = false;
  bool _isLoadingVehicles = false;

  List<Map<String, dynamic>> _drivers = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _vehicles = <Map<String, dynamic>>[];

  String? _selectedDriverId;
  String? _selectedVehicleId;
  String _selectedCategory = "daily_payment";
  String _selectedPaymentMethod = "cash";

  // Enhanced color scheme (aligned with ThemeConstants)
  static const Color primaryBlue = ThemeConstants.primaryBlue;
  static const Color successGreen = ThemeConstants.successGreen;
  static const Color errorRed = ThemeConstants.errorRed;
  static const Color grayBackground = Color(0xFFF8FAFC);

  // Payment categories
  final Map<String, String> _paymentCategories = <String, String>{
    "daily_payment": LocalizationService.instance.translate('daily_payment'),
    "weekly_payment": LocalizationService.instance.translate('weekly_payment'),
    "trip_payment": LocalizationService.instance.translate('trip_payment'),
    "delivery_payment": LocalizationService.instance.translate('delivery_payment'),
    "rental_payment": LocalizationService.instance.translate('rental_payment'),
    "fuel_contribution": LocalizationService.instance.translate('fuel_contribution'),
    "maintenance_fee": LocalizationService.instance.translate('maintenance_fee'),
    "other_payment": LocalizationService.instance.translate('other_payments'),
  };

  // Payment methods
  final Map<String, String> _paymentMethods = <String, String>{
    "cash": LocalizationService.instance.translate('cash'),
    "mobile_money": LocalizationService.instance.translate('mobile_money'),
    "bank_transfer": LocalizationService.instance.translate('bank_transfer'),
    "card": LocalizationService.instance.translate('card'),
  };

  @override
  void initState() {
    super.initState();
    _loadDrivers();
    _loadVehicles();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _notesController.dispose();
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    super.dispose();
  }

  Future<void> _loadDrivers() async {
    if (mounted) {
      setState(() {
        _isLoadingDrivers = true;
      });
    }

    try {
      await _apiService.initialize();
      final Map<String, dynamic> response = await _apiService.getDrivers();

      if (mounted) {
        setState(() {
          // Handle the actual response structure: {status, message, data}
          try {
            // Debug logging
            debugPrint("Drivers response type: ${response.runtimeType}");
            debugPrint("Drivers response keys: ${response.keys}");
            debugPrint("Drivers data type: ${response["data"]?.runtimeType}");
            debugPrint("Drivers data: ${response["data"]}");

            // Check if data is a Map (paginated response) or List (direct response)
            final data = response["data"];
            if (data is Map<String, dynamic>) {
              // Paginated response: data contains another object with "data" key
              if (data["data"] is List) {
                _drivers = List<Map<String, dynamic>>.from(data["data"]);
              } else {
                debugPrint("No list found in nested data object");
                _drivers = <Map<String, dynamic>>[];
              }
            } else if (data is List) {
              // Direct list response
              _drivers = List<Map<String, dynamic>>.from(data);
            } else {
              debugPrint("Data is neither Map nor List: ${data?.runtimeType}");
              _drivers = <Map<String, dynamic>>[];
            }
          } on Exception catch (e) {
            debugPrint("Error parsing drivers response: $e");
            _drivers = <Map<String, dynamic>>[];
          }
        });
      }
    } on Exception catch (e) {
      if (mounted) {
        _showErrorSnackBar(LocalizationService.instance.translateWith('error_loading_drivers', <Object?>[e]));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingDrivers = false;
        });
      }
    }
  }

  Future<void> _loadVehicles() async {
    if (mounted) {
      setState(() {
        _isLoadingVehicles = true;
      });
    }

    try {
      await _apiService.initialize();
      final Map<String, dynamic> response = await _apiService.getVehicles();

      if (mounted) {
        setState(() {
          // Handle the actual response structure: {status, message, data}
          try {
            // Debug logging
            debugPrint("Vehicles response type: ${response.runtimeType}");
            debugPrint("Vehicles response keys: ${response.keys}");
            debugPrint("Vehicles data type: ${response["data"]?.runtimeType}");
            debugPrint("Vehicles data: ${response["data"]}");

            // Check if data is a Map (paginated response) or List (direct response)
            final data = response["data"];
            if (data is Map<String, dynamic>) {
              // Paginated response: data contains another object with "data" key
              if (data["data"] is List) {
                _vehicles = List<Map<String, dynamic>>.from(data["data"]);
              } else {
                debugPrint("No list found in nested data object");
                _vehicles = <Map<String, dynamic>>[];
              }
            } else if (data is List) {
              // Direct list response
              _vehicles = List<Map<String, dynamic>>.from(data);
            } else {
              debugPrint("Data is neither Map nor List: ${data?.runtimeType}");
              _vehicles = <Map<String, dynamic>>[];
            }
          } on Exception catch (e) {
            debugPrint("Error parsing vehicles response: $e");
            _vehicles = <Map<String, dynamic>>[];
          }
        });
      }
    } on Exception catch (e) {
      if (mounted) {
        _showErrorSnackBar(LocalizationService.instance.translateWith('error_loading_vehicles', <Object?>[e]));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingVehicles = false;
        });
      }
    }
  }

  Future<void> _recordPayment() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedDriverId == null) {
      _showErrorSnackBar(LocalizationService.instance.translate('please_select_a_driver'));
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      await _apiService.initialize();

      final Map<String, Object?> paymentData = <String, Object?>{
        "driver_id": _selectedDriverId,
        "device_id": _selectedVehicleId,
        "amount": double.parse(_amountController.text),
        "category": _selectedCategory,
        "description": _descriptionController.text,
        "payment_method": _selectedPaymentMethod,
        "notes":
            _notesController.text.isNotEmpty ? _notesController.text : null,
        "customer_name": _customerNameController.text.isNotEmpty
            ? _customerNameController.text
            : null,
        "customer_phone": _customerPhoneController.text.isNotEmpty
            ? _customerPhoneController.text
            : null,
      };

      await _apiService.recordPayment(paymentData);

      if (mounted) {
        _showSuccessSnackBar("${LocalizationService.instance.translate('payment_recorded_successfully')}!");
        _clearForm();

        // Emit events to notify other screens about payment updates
        AppEvents.instance.emit(AppEventType.paymentsUpdated);
        AppEvents.instance.emit(AppEventType.receiptsUpdated);
        AppEvents.instance.emit(AppEventType.dashboardShouldRefresh);
      }
    } on Exception catch (e) {
      if (mounted) {
        _showErrorSnackBar(LocalizationService.instance.translateWith('error_recording_the_payment', <Object?>[e]));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _clearForm() {
    _amountController.clear();
    _descriptionController.clear();
    _notesController.clear();
    _customerNameController.clear();
    _customerPhoneController.clear();
    setState(() {
      _selectedDriverId = null;
      _selectedVehicleId = null;
      _selectedCategory = "daily_payment";
      _selectedPaymentMethod = "cash";
    });
  }

  void _showErrorSnackBar(final String message) {
    if (mounted) {
      ThemeConstants.showErrorSnackBar(context, message);
    }
  }

  void _showSuccessSnackBar(final String message) {
    if (mounted) {
      ThemeConstants.showSuccessSnackBar(context, message);
    }
  }

  @override
  Widget build(final BuildContext context) => Scaffold(
        backgroundColor: grayBackground,
        appBar: AppBar(
          title: Text(
            LocalizationService.instance.translate('record_payment'),
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // Header Card
                  CustomCard(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 20,
                      ),
                      decoration: BoxDecoration(
                        color: ThemeConstants.primaryBlue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: <Widget>[
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: ThemeConstants.primaryBlue,
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: const Icon(
                              Icons.payment,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  LocalizationService.instance.translate('record_driver_payment'),
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF616161),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 2,
                                ),
                                SizedBox(height: 8),
                                Text(
                                  LocalizationService.instance.translate('enter_the_driver_s_payment_details'),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.black54,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 2,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Driver Selection
                  CustomCard(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            LocalizationService.instance.translate('select_driver'),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF616161),
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (_isLoadingDrivers)
                            const Center(child: CircularProgressIndicator())
                          else
                            DropdownButtonFormField<String>(
                              isExpanded: true,
                              initialValue: _selectedDriverId,
                              decoration: InputDecoration(
                                labelText: LocalizationService.instance.translate('driver'),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                prefixIcon: const Icon(Icons.person),
                              ),
                              items: _drivers
                                  .map(
                                    (final Map<String, dynamic> driver) =>
                                        DropdownMenuItem<String>(
                                      value: driver["id"].toString(),
                                      child: Text(
                                        "${driver["name"]} - ${driver["phone"]}",
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                        softWrap: false,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (final String? value) {
                                setState(() {
                                  _selectedDriverId = value;
                                  // Filter vehicles for selected driver
                                  _selectedVehicleId = null;
                                });
                              },
                              validator: (final String? value) {
                                if (value == null || value.isEmpty) {
                                  return LocalizationService.instance.translate('please_select_a_driver');
                                }
                                return null;
                              },
                            ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Vehicle Selection (Optional)
                  CustomCard(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            LocalizationService.instance.translate('select_vehicle_optional'),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF616161),
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (_isLoadingVehicles)
                            const Center(child: CircularProgressIndicator())
                          else
                            DropdownButtonFormField<String>(
                              isExpanded: true,
                              initialValue: _selectedVehicleId,
                              decoration: InputDecoration(
                                labelText: LocalizationService.instance.translate('vehicle_2'),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                prefixIcon: const Icon(Icons.directions_car),
                              ),
                              items: <DropdownMenuItem<String>>[
                                DropdownMenuItem<String>(
                                  child: Text(LocalizationService.instance.translate('no_vehicle')),
                                ),
                                ..._vehicles.map(
                                  (final Map<String, dynamic> vehicle) =>
                                      DropdownMenuItem<String>(
                                    value: vehicle["id"].toString(),
                                    child: Text(
                                      "${vehicle["plate_number"]} - ${vehicle["type"]}",
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                      softWrap: false,
                                    ),
                                  ),
                                ),
                              ],
                              onChanged: (final String? value) {
                                setState(() {
                                  _selectedVehicleId = value;
                                });
                              },
                            ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Payment Details
                  CustomCard(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            LocalizationService.instance.translate('payment_information'),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF616161),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Amount
                          TextFormField(
                            controller: _amountController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: LocalizationService.instance.translate('amount_tsh'),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              prefixIcon: const Icon(Icons.money),
                              prefixText: "TSH ",
                            ),
                            validator: (final String? value) {
                              if (value == null || value.isEmpty) {
                                return LocalizationService.instance.translate('please_enter_the_amount');
                              }
                              if (double.tryParse(value) == null) {
                                return LocalizationService.instance.translate('enter_a_valid_amount_3');
                              }
                              if (double.parse(value) <= 0) {
                                return LocalizationService.instance.translate('the_amount_must_be_greater_than');
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 16),

                          // Category
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: _selectedCategory,
                            decoration: InputDecoration(
                              labelText: LocalizationService.instance.translate('payment_mode'),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              prefixIcon: const Icon(Icons.category),
                            ),
                            items: _paymentCategories.entries
                                .map(
                                  (final MapEntry<String, String> entry) =>
                                      DropdownMenuItem<String>(
                                    value: entry.key,
                                    child: Text(
                                      entry.value,
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                      softWrap: false,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (final String? value) {
                              setState(() {
                                _selectedCategory = value!;
                              });
                            },
                          ),

                          const SizedBox(height: 16),

                          // Payment Method
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: _selectedPaymentMethod,
                            decoration: InputDecoration(
                              labelText: LocalizationService.instance.translate('payment_method_label'),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              prefixIcon: const Icon(Icons.payment),
                            ),
                            items: _paymentMethods.entries
                                .map(
                                  (final MapEntry<String, String> entry) =>
                                      DropdownMenuItem<String>(
                                    value: entry.key,
                                    child: Text(
                                      entry.value,
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                      softWrap: false,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (final String? value) {
                              setState(() {
                                _selectedPaymentMethod = value!;
                              });
                            },
                          ),

                          const SizedBox(height: 16),

                          // Description
                          TextFormField(
                            controller: _descriptionController,
                            maxLines: 3,
                            decoration: InputDecoration(
                              labelText: LocalizationService.instance.translate('description'),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              prefixIcon: const Icon(Icons.description),
                            ),
                            validator: (final String? value) {
                              if (value == null || value.isEmpty) {
                                return LocalizationService.instance.translate('please_enter_a_description');
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Customer Details (Optional)
                  CustomCard(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            LocalizationService.instance.translate('customer_information_optional'),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF616161),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Customer Name
                          TextFormField(
                            controller: _customerNameController,
                            decoration: InputDecoration(
                              labelText: LocalizationService.instance.translate('customer_name'),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              prefixIcon: const Icon(Icons.person_outline),
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Customer Phone
                          TextFormField(
                            controller: _customerPhoneController,
                            keyboardType: TextInputType.phone,
                            decoration: InputDecoration(
                              labelText: LocalizationService.instance.translate('customer_phone_number'),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              prefixIcon: const Icon(Icons.phone),
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Notes
                          TextFormField(
                            controller: _notesController,
                            maxLines: 2,
                            decoration: InputDecoration(
                              labelText: LocalizationService.instance.translate('extra_details_optional'),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              prefixIcon: const Icon(Icons.note),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Submit Button
                  CustomButton(
                    text: LocalizationService.instance.translate('record_payment'),
                    onPressed: _isLoading ? null : _recordPayment,
                    isLoading: _isLoading,
                    backgroundColor: successGreen,
                    height: 56,
                  ),

                  const SizedBox(height: 16),

                  // Clear Button
                  CustomButton(
                    text: LocalizationService.instance.translate('clear_form'),
                    onPressed: _isLoading ? null : _clearForm,
                    backgroundColor: Colors.grey,
                    height: 48,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
