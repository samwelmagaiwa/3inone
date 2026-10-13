import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import "../../constants/colors.dart";
import "../../constants/strings.dart";
import "../../constants/styles.dart";
import "../../constants/theme_constants.dart";
import "../../models/device.dart";
import "../../providers/device_provider.dart";
import "../../widgets/custom_button.dart";
import "../../widgets/custom_card.dart";
import '../../services/localization_service.dart';

class DeviceSelectionScreen extends StatefulWidget {
  const DeviceSelectionScreen({super.key});

  @override
  State<DeviceSelectionScreen> createState() => _DeviceSelectionScreenState();
}

class _DeviceSelectionScreenState extends State<DeviceSelectionScreen> {
  DeviceType? selectedDeviceType;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _plateNumberController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _plateNumberController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _saveDevice() async {
    if (!_formKey.currentState!.validate() || selectedDeviceType == null) {
      ThemeConstants.showErrorSnackBar(context, LocalizationService.instance.translate('please_fill_in_all_required_information'));
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final Device device = Device(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: _nameController.text.trim(),
        type: selectedDeviceType!,
        plateNumber: _plateNumberController.text.trim(),
        driverId: "current_driver_id", // Replace with actual driver ID
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
      );

      await Provider.of<DeviceProvider>(context, listen: false)
          .addDevice(device);

      if (mounted) {
        ThemeConstants.showSuccessSnackBar(context, LocalizationService.instance.translate('vehicle_registered_successfully'));
        Navigator.pop(context);
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
  Widget build(final BuildContext context) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(
            AppStrings.selectDevice,
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
                // Device Type Selection
                Text(
                  AppStrings.deviceType,
                  style: AppStyles.heading3,
                ),
                const SizedBox(height: AppStyles.spacingM),
                _DeviceTypeSelector(
                  selectedType: selectedDeviceType,
                  onTypeSelected: (final DeviceType type) {
                    setState(() {
                      selectedDeviceType = type;
                    });
                  },
                ),

                const SizedBox(height: AppStyles.spacingL),

                // Device Details Form
                Text(
                  LocalizationService.instance.translate('vehicle_information'),
                  style: AppStyles.heading3,
                ),
                const SizedBox(height: AppStyles.spacingM),

                // Device Name
                TextFormField(
                  controller: _nameController,
                  decoration: AppStyles.inputDecoration(context).copyWith(
                    labelText: LocalizationService.instance.translate('vehicle_name'),
                    hintText: LocalizationService.instance.translate('example_first_tuk_tuk'),
                  ),
                  validator: (final String? value) {
                    if (value == null || value.trim().isEmpty) {
                      return AppStrings.fieldRequired;
                    }
                    return null;
                  },
                ),

                const SizedBox(height: AppStyles.spacingM),

                // Plate Number
                TextFormField(
                  controller: _plateNumberController,
                  decoration: AppStyles.inputDecoration(context).copyWith(
                    labelText: LocalizationService.instance.translate('plate_number_2'),
                    hintText: LocalizationService.instance.translate('example_t123abc'),
                  ),
                  textCapitalization: TextCapitalization.characters,
                  validator: (final String? value) {
                    if (value == null || value.trim().isEmpty) {
                      return AppStrings.fieldRequired;
                    }
                    return null;
                  },
                ),

                const SizedBox(height: AppStyles.spacingM),

                // Description (Optional)
                TextFormField(
                  controller: _descriptionController,
                  decoration: AppStyles.inputDecoration(context).copyWith(
                    labelText: LocalizationService.instance.translate('description_not_required'),
                    hintText: LocalizationService.instance.translate('extra_details_about_the_vehicle_2'),
                  ),
                  maxLines: 3,
                ),

                const SizedBox(height: AppStyles.spacingXL),

                // Save Button
                SizedBox(
                  width: double.infinity,
                  child: CustomButton(
                    text: _isLoading ? AppStrings.loading : AppStrings.save,
                    onPressed: _isLoading ? null : _saveDevice,
                    isLoading: _isLoading,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _DeviceTypeSelector extends StatelessWidget {
  const _DeviceTypeSelector({
    required this.selectedType,
    required this.onTypeSelected,
  });
  final DeviceType? selectedType;
  final Function(DeviceType) onTypeSelected;

  @override
  Widget build(final BuildContext context) => Column(
        children: DeviceType.values.map((final DeviceType type) {
          final bool isSelected = selectedType == type;

          return Padding(
            padding: const EdgeInsets.only(bottom: AppStyles.spacingM),
            child: CustomCard(
              onTap: () => onTypeSelected(type),
              child: Container(
                padding: const EdgeInsets.all(AppStyles.spacingM),
                decoration: BoxDecoration(
                  borderRadius:
                      BorderRadius.circular(AppStyles.radiusL(context)),
                  border: isSelected
                      ? Border.all(color: AppColors.primary, width: 2)
                      : null,
                  color: isSelected
                      ? AppColors.primary.withOpacity(0.1)
                      : AppColors.surface,
                ),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: _getDeviceColor(type).withOpacity(0.2),
                        borderRadius:
                            BorderRadius.circular(AppStyles.radiusM(context)),
                      ),
                      child: Center(
                        child: Text(
                          type.icon,
                          style: const TextStyle(fontSize: 24),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppStyles.spacingM),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            type.name,
                            style: AppStyles.heading3.copyWith(
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: AppStyles.spacingXS),
                          Text(
                            _getDeviceDescription(type),
                            style: AppStyles.bodySmall.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isSelected)
                      const Icon(
                        Icons.check_circle,
                        color: AppColors.primary,
                        size: 24,
                      ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      );

  Color _getDeviceColor(final DeviceType type) {
    switch (type) {
      case DeviceType.bajaji:
        return AppColors.bajaji;
      case DeviceType.pikipiki:
        return AppColors.pikipiki;
      case DeviceType.gari:
        return AppColors.gari;
    }
  }

  String _getDeviceDescription(final DeviceType type) {
    switch (type) {
      case DeviceType.bajaji:
        return LocalizationService.instance.translate('passenger_tuk_tuk_or_rickshaw');
      case DeviceType.pikipiki:
        return LocalizationService.instance.translate('passenger_motorcycle_boda_boda');
      case DeviceType.gari:
        return LocalizationService.instance.translate('passenger_or_cargo_car');
    }
  }
}
