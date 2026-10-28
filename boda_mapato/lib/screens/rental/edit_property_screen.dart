import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../constants/theme_constants.dart';
import '../../widgets/branch_picker_field.dart';
import '../../providers/rental_provider.dart';
import '../../services/localization_service.dart';
import '../../widgets/location_selector.dart';
import '../../utils/rental_labels.dart';

class EditPropertyScreen extends StatefulWidget {
  const EditPropertyScreen({required this.property, super.key});
  final Map<String, dynamic> property;

  @override
  State<EditPropertyScreen> createState() => _EditPropertyScreenState();
}

class _EditPropertyScreenState extends State<EditPropertyScreen> {
  int? _branchId;
  final _formKey = GlobalKey<FormState>();
  final _loc = LocalizationService.instance;

  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _addressController;


  late String _propertyType;
  late String? _region;
  late String? _district;
  late String? _ward;
  late String? _street;
  late String? _place;
  late String _status;
  File? _newCoverImage;
  String? _currentImageUrl;

  bool _isSubmitting = false;

  static const List<String> _propertyTypes = [
    'apartment', 'rental_compound', 'standalone_house', 'hostel',
    'commercial_building', 'mixed_use', 'office_space', 'shop_units',
  ];

  static const List<String> _regions = [
    'Dar es Salaam', 'Arusha', 'Mwanza', 'Dodoma', 'Mbeya',
    'Morogoro', 'Tanga', 'Kilimanjaro', 'Pwani', 'Kigoma',
    'Kagera', 'Mara', 'Shinyanga', 'Tabora', 'Rukwa',
    'Iringa', 'Lindi', 'Mtwara', 'Ruvuma', 'Singida',
    'Geita', 'Simiyu', 'Njombe', 'Katavi', 'Songwe',
  ];

  @override
  void initState() {
    super.initState();
    final p = widget.property;
    _nameController = TextEditingController(text: p['name'] ?? '');
    _descriptionController = TextEditingController(text: p['description'] ?? '');
    _addressController = TextEditingController(text: p['address'] ?? '');
    _propertyType = p['property_type'] ?? 'apartment';
    _region = p['region'];
    _district = p['district'];
    _ward = p['ward'];
    _street = p['street'];
    _place = p['place'];
    _status = p['status'] ?? 'active';
    _currentImageUrl = p['cover_image'];
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked =
        await picker.pickImage(source: ImageSource.gallery, maxWidth: 1200);
    if (picked != null) {
      setState(() => _newCoverImage = File(picked.path));
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSubmitting = true);

    final data = <String, dynamic>{
      'name': _nameController.text.trim(),
      'property_type': _propertyType,
      'description': _descriptionController.text.trim(),
      'region': _region ?? '',
      'district': _district ?? '',
      'ward': _ward,
      'street': _street,
      'place': _place,
      'address': _addressController.text.trim(),

      'address': _addressController.text.trim(),
      'status': _status,
      // '' clears it: null fields are left out of a form upload
      'branch_id': _branchId ?? '',
    };

    final error = await context
        .read<RentalProvider>()
        .updateProperty(widget.property['id'], data, image: _newCoverImage);

    setState(() => _isSubmitting = false);

    if (error == null && mounted) {
      ThemeConstants.showSuccessSnackBar(context, _loc.translate('property_updated'));
      Navigator.pop(context);
    } else if (mounted) {
      ThemeConstants.showErrorSnackBar(context, error ?? _loc.translate('error_occurred'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ThemeConstants.buildResponsiveScaffold(
      context,
      title: _loc.translate('edit_property'),
      showBackButton: true,
      onBack: () {
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        } else {
          Navigator.pushReplacementNamed(context, '/rental/dashboard');
        }
      },
      body: Container(
        color: ThemeConstants.bgMid,
        child: SafeArea(
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 20.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSection(
                    _loc.translate('basic_information'),
                    Icons.info_outline,
                    [
                      _buildTextInput(
                        controller: _nameController,
                        label: _loc.translate('property_name'),
                        icon: Icons.apartment,
                        required: true,
                      ),
                      SizedBox(height: 14.h),
                      _buildDropdownField(
                        label: _loc.translate('property_type'),
                        value: _propertyType,
                        items: _propertyTypes,
                        formatter: _formatType,
                        onChanged: (v) => setState(() => _propertyType = v!),
                      ),
                      SizedBox(height: 14.h),
                      _buildTextInput(
                        controller: _descriptionController,
                        label: _loc.translate('description'),
                        icon: Icons.description,
                        maxLines: 3,
                      ),
                    ],
                  ),
                  SizedBox(height: 20.h),
                  _buildSection(
                    _loc.translate('location'),
                    Icons.location_on_outlined,
                    [
                      LocationSelector(
                        onChanged: (region, district, ward, street, place) {
                          _region = region;
                          _district = district;
                          _ward = ward;
                          _street = street;
                          _place = place;
                        },
                      ),
                      SizedBox(height: 14.h),
                      _buildTextInput(
                        controller: _addressController,
                        label: _loc.translate('address'),
                        icon: Icons.home_outlined,
                        required: true,
                        maxLines: 2,
                      ),
                      SizedBox(height: 14.h),
                      BranchPickerField(service: 'rental', initialId: (widget.property['branch_id'] as num?)?.toInt(), onChanged: (int? id) => _branchId = id),
                    ],
                  ),
                  SizedBox(height: 20.h),
                  SizedBox(height: 20.h),
                  _buildSection(
                    _loc.translate('media'),
                    Icons.image_outlined,
                    [
                      GestureDetector(
                        onTap: _pickImage,
                        child: Container(
                          height: 180.h,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(18.r),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.12),
                            ),
                          ),
                          child: _newCoverImage != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(18.r),
                                  child: Image.file(_newCoverImage!,
                                      width: double.infinity,
                                      height: 180.h,
                                      fit: BoxFit.cover),
                                )
                              : (_currentImageUrl != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(18.r),
                                      child: Image.network(_currentImageUrl!,
                                          width: double.infinity,
                                          height: 180.h,
                                          fit: BoxFit.cover,
                                          errorBuilder: (c, e, s) => Center(
                                              child: Icon(Icons.broken_image_outlined,
                                                  color: Colors.white24,
                                                  size: 40.sp))),
                                    )
                                  : Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.cloud_upload_outlined,
                                            size: 40.sp, color: Colors.white38),
                                        SizedBox(height: 8.h),
                                        Text(_loc.translate('tap_to_upload'),
                                            style: ThemeConstants.captionStyle),
                                      ],
                                    )),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 32.h),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ThemeConstants.primaryOrange,
                        disabledBackgroundColor: ThemeConstants.primaryOrange.withOpacity(0.5),
                        padding: EdgeInsets.symmetric(vertical: 16.h),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.r)),
                        elevation: 8,
                        shadowColor: ThemeConstants.primaryOrange.withOpacity(0.4),
                      ),
                      child: _isSubmitting
                          ? SizedBox(
                              height: 20.h,
                              width: 20.h,
                              child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : Text(_loc.translate('update_property'),
                              style: TextStyle(color: Colors.white, fontSize: 16.sp, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  SizedBox(height: 40.h),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSection(String title, IconData icon, List<Widget> children) {
    return ThemeConstants.buildResponsiveGlassCardStatic(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: ThemeConstants.primaryOrange, size: 20.sp),
              SizedBox(width: 10.w),
              Text(title, style: ThemeConstants.headingStyle.copyWith(fontSize: 15.sp)),
            ],
          ),
          SizedBox(height: 20.h),
          ...children,
        ],
      ),
    );
  }

  Widget _buildTextInput({
    required String label, TextEditingController? controller,
    IconData? icon,
    bool required = false,
    int maxLines = 1,
    String? initialValue,
    Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      initialValue: controller == null ? initialValue : null,
      maxLines: maxLines,
      style: TextStyle(color: Colors.white, fontSize: 14.sp),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: required ? "$label *" : label,
        labelStyle: TextStyle(color: Colors.white54, fontSize: 12.sp),
        prefixIcon: icon != null ? Icon(icon, color: Colors.white38, size: 18.sp) : null,
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: const BorderSide(color: ThemeConstants.primaryOrange),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
      ),
      validator: required
          ? (v) => (v == null || v.trim().isEmpty) ? _loc.translate('field_required') : null
          : null,
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String? value,
    required List<String> items,
    required String Function(String) formatter,
    required Function(String?) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.white54, fontSize: 12.sp)),
        SizedBox(height: 6.h),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12.w),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(color: Colors.white12),
          ),
          child: DropdownButton<String>(
            value: (value != null && items.contains(value)) ? value : null,
            isExpanded: true,
            dropdownColor: ThemeConstants.primaryBlue,
            underline: const SizedBox(),
            style: TextStyle(color: Colors.white, fontSize: 14.sp),
            hint: Text(_loc.translate('select'), style: const TextStyle(color: Colors.white38)),
            items: items
                .map((item) => DropdownMenuItem(value: item, child: Text(formatter(item))))
                .toList(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  String _formatType(String type) => rentalValueLabel(type);
}
