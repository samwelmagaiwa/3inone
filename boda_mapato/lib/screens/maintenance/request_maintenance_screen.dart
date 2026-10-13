import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../constants/theme_constants.dart';
import '../../providers/maintenance_provider.dart';
import '../../providers/rental_provider.dart';
import '../../services/localization_service.dart';
import '../../utils/maintenance_labels.dart';

class RequestMaintenanceScreen extends StatefulWidget {
  const RequestMaintenanceScreen({super.key});

  @override
  State<RequestMaintenanceScreen> createState() => _RequestMaintenanceScreenState();
}

class _RequestMaintenanceScreenState extends State<RequestMaintenanceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  
  String? _selectedPropertyId;
  String? _selectedHouseId;
  String _selectedCategory = 'Mengineyo';
  String _selectedPriority = 'medium';
  File? _image;

  final List<String> _categories = [
    'Mengineyo',
    'Mabomba/Plumbing',
    'Umeme',
    'Ujenzi/Structural',
    'Vifaa vya Ndani',
    'Paka Rangi',
    'Usalama',
  ];

  final Map<String, String> _priorityMap = {
    'low': LocalizationService.instance.translate('low'),
    'medium': LocalizationService.instance.translate('priority_medium'),
    'high': LocalizationService.instance.translate('high'),
    'emergency': LocalizationService.instance.translate('urgent'),
  };

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedPropertyId == null) {
      ThemeConstants.showErrorSnackBar(context, LocalizationService.instance.translate('property_not_selected'));
      return;
    }

    final success = await context.read<MaintenanceProvider>().submitRequest(
      propertyId: _selectedPropertyId!,
      houseId: _selectedHouseId,
      category: _selectedCategory,
      priority: _selectedPriority,
      description: _descriptionController.text,
      photo: _image,
    );

    if (success && mounted) {
      Navigator.pop(context);
      ThemeConstants.showSuccessSnackBar(context, LocalizationService.instance.translate('your_request_has_been_sent'));
    } else if (mounted) {
      ThemeConstants.showErrorSnackBar(context, LocalizationService.instance.translate('could_not_send_the_request'));
    }
  }

  @override
  Widget build(final BuildContext context) {
    final rentalProvider = context.watch<RentalProvider>();
    final maintenanceProvider = context.watch<MaintenanceProvider>();

    return ThemeConstants.buildScaffold(
      title: LocalizationService.instance.translate('request_maintenance'),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 20.h),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ThemeConstants.buildResponsiveGlassCardStatic(
                context,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader(LocalizationService.instance.translate('property_house'), Icons.home_work),
                    SizedBox(height: 16.h),
                    _buildDropdown(
                      label: LocalizationService.instance.translate('select_property_2'),
                      value: _selectedPropertyId,
                      items: rentalProvider.properties.map((p) {
                        return DropdownMenuItem(
                          value: p['id'].toString(),
                          child: Text(p['name']),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setState(() {
                          _selectedPropertyId = val;
                          _selectedHouseId = null;
                        });
                      },
                    ),
                    if (_selectedPropertyId != null) ...[
                      SizedBox(height: 16.h),
                      _buildDropdown(
                        label: LocalizationService.instance.translate('select_house_optional'),
                        value: _selectedHouseId,
                        items: rentalProvider.properties
                            .firstWhere((p) => p['id'].toString() == _selectedPropertyId)['houses']
                            .map<DropdownMenuItem<String>>((h) {
                          return DropdownMenuItem(
                            value: h['id'].toString(),
                            child: Text(LocalizationService.instance.translateWith('unit_2', <Object?>[h['house_number']])),
                          );
                        }).toList(),
                        onChanged: (val) => setState(() => _selectedHouseId = val),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(height: 20.h),
              ThemeConstants.buildResponsiveGlassCardStatic(
                context,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader(LocalizationService.instance.translate('problem_details'), Icons.report_problem),
                    SizedBox(height: 16.h),
                    Row(
                      children: [
                        Expanded(
                          child: _buildDropdown(
                            label: LocalizationService.instance.translate('category_2'),
                            value: _selectedCategory,
                            items: _categories.map((c) {
                              return DropdownMenuItem(value: c, child: Text(maintenanceCategoryLabel(c), overflow: TextOverflow.ellipsis));
                            }).toList(),
                            onChanged: (val) => setState(() => _selectedCategory = val!),
                          ),
                        ),
                        SizedBox(width: 8.w),
                        Expanded(
                          child: _buildDropdown(
                            label: LocalizationService.instance.translate('priority'),
                            value: _selectedPriority,
                            items: _priorityMap.entries.map((e) {
                              return DropdownMenuItem(value: e.key, child: Text(e.value));
                            }).toList(),
                            onChanged: (val) => setState(() => _selectedPriority = val!),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16.h),
                    TextFormField(
                      controller: _descriptionController,
                      maxLines: 4,
                      style: ThemeConstants.bodyStyle,
                      decoration: _inputDecoration("${LocalizationService.instance.translate('describe_the_problem_in_detail')}...", Icons.description),
                      validator: (val) => val == null || val.isEmpty ? LocalizationService.instance.translate('please_describe_the_problem') : null,
                    ),
                  ],
                ),
              ),
              SizedBox(height: 20.h),
              ThemeConstants.buildResponsiveGlassCardStatic(
                context,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader(LocalizationService.instance.translate('photos_of_the_problem'), Icons.add_a_photo),
                    SizedBox(height: 16.h),
                    GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        height: 180.h,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(16.r),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: _image != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(16.r),
                                child: Image.file(_image!, fit: BoxFit.cover),
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: EdgeInsets.all(12.r),
                                    decoration: BoxDecoration(
                                      color: ThemeConstants.footerBarColor.withOpacity(0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(Icons.camera_alt, color: ThemeConstants.footerBarColor, size: 32.sp),
                                  ),
                                  SizedBox(height: 12.h),
                                  Text(LocalizationService.instance.translate('tap_to_add_a_sample_photo'), 
                                      style: ThemeConstants.captionStyle.copyWith(fontSize: 13.sp)),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 32.h),
              SizedBox(
                width: double.infinity,
                height: 58.h,
                child: ElevatedButton(
                  onPressed: maintenanceProvider.isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ThemeConstants.footerBarColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
                    elevation: 4,
                  ),
                  child: maintenanceProvider.isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(LocalizationService.instance.translate('send_request_now').toUpperCase(), 
                          style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                ),
              ),
              SizedBox(height: 40.h),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: ThemeConstants.footerBarColor, size: 18.sp),
        SizedBox(width: 8.w),
        Text(
          title.toUpperCase(),
          style: TextStyle(
            color: ThemeConstants.footerBarColor,
            fontSize: 12.sp,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown({
    required String label,
    required dynamic value,
    required List<DropdownMenuItem<dynamic>> items,
    required void Function(dynamic) onChanged,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<dynamic>(
          value: value,
          items: items,
          onChanged: onChanged,
          dropdownColor: const Color(0xFF1E293B),
          style: ThemeConstants.bodyStyle,
          isExpanded: true,
          hint: Text(label, style: ThemeConstants.captionStyle),
          icon: Icon(Icons.arrow_drop_down, color: ThemeConstants.footerBarColor, size: 24.sp),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: ThemeConstants.captionStyle,
      prefixIcon: Icon(icon, color: Colors.grey, size: 20.sp),
      filled: true,
      fillColor: Colors.white.withOpacity(0.05),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14.r), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14.r),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14.r),
        borderSide: const BorderSide(color: ThemeConstants.footerBarColor, width: 1.5),
      ),
    );
  }
}
