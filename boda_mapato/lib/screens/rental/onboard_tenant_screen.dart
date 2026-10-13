import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../constants/theme_constants.dart';
import '../../providers/rental_provider.dart';
import '../../services/localization_service.dart';
import '../../services/api_service.dart';
import '../../utils/rental_flow_validator.dart';
import '../../widgets/temporary_password_dialog.dart';
import 'record_payment_screen.dart';

class OnboardTenantScreen extends StatefulWidget {
  const OnboardTenantScreen({super.key, this.preSelectedProperty, this.preSelectedHouse});
  final Map<String, dynamic>? preSelectedProperty;
  final Map<String, dynamic>? preSelectedHouse;

  @override
  State<OnboardTenantScreen> createState() => _OnboardTenantScreenState();
}

class _OnboardTenantScreenState extends State<OnboardTenantScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  final int _totalSteps = 4;
  final _formKey = GlobalKey<FormState>();

  // Step 1: Personal Information
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  DateTime? _dob;
  final _nidaController = TextEditingController();
  String _gender = "Male";

  // Step 2: Emergency Contact
  final _emergencyNameController = TextEditingController();
  final _relationshipController = TextEditingController();
  final _emergencyPhoneController = TextEditingController();
  final _emergencyEmailController = TextEditingController();

  // Step 3: Identification
  final _idNumberController = TextEditingController();
  final _idStateController = TextEditingController();
  DateTime? _idExpiration;
  String? _idDocPath;
  String? _idDocName;

  // Step 4: Employment
  final _employerController = TextEditingController();
  final _jobTitleController = TextEditingController();
  final _employmentLengthController = TextEditingController();
  final _workPhoneController = TextEditingController();
  bool _isEmployed = true;

  // Step 5: Rental History
  final _prevAddressController = TextEditingController();
  final _stayDurationController = TextEditingController();
  final _reasonForLeavingController = TextEditingController();
  final _prevLandlordNameController = TextEditingController();
  final _prevLandlordPhoneController = TextEditingController();

  // Step 6: Occupants & Pets
  int _adultsCount = 1;
  int _childrenCount = 0;
  bool _willOthersLive = false;
  String _petType = "None";
  final _petBreedController = TextEditingController();
  final _petAgeController = TextEditingController();
  final _petWeightController = TextEditingController();

  // Step 7: Assignment & Terms
  String? _selectedPropertyId;
  String? _selectedHouseId;
  DateTime _startDate = DateTime.now();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  String? _tenantPhotoPath;
  bool _acceptedTerms = false;
  bool _acceptedPrivacy = false;
  
  bool _rentWholeHouse = true;
  List<String> _selectedUnits = [];

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.preSelectedProperty != null) {
        _selectedPropertyId = widget.preSelectedProperty!['id']?.toString();
      }
      if (widget.preSelectedHouse != null) {
        _selectedHouseId = widget.preSelectedHouse!['id']?.toString();
        final rent = (widget.preSelectedHouse!['rent_amount'] ?? widget.preSelectedHouse!['rent'] ?? '').toString();
        _amountController.text = rent;
      }
      
      // Enforce wizard flow: Must have at least one property with houses
      RentalFlowValidator.validateStep(
        context: context,
        fetchData: (p) => p.fetchProperties(),
        condition: (p) => RentalFlowValidator.hasHouses(p),
        title: LocalizationService.instance.translate('no_houses_found'),
        message: LocalizationService.instance.translate('you_need_a_property_and_a'),
        actionLabel: LocalizationService.instance.translate('add_property_2'),
        actionRoute: "/rental/add-property",
      );
      context.read<RentalProvider>().fetchTenants();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _nidaController.dispose();
    _emergencyNameController.dispose();
    _relationshipController.dispose();
    _emergencyPhoneController.dispose();
    _emergencyEmailController.dispose();
    _idNumberController.dispose();
    _idStateController.dispose();
    _employerController.dispose();
    _jobTitleController.dispose();
    _employmentLengthController.dispose();
    _workPhoneController.dispose();
    _prevAddressController.dispose();
    _stayDurationController.dispose();
    _reasonForLeavingController.dispose();
    _prevLandlordNameController.dispose();
    _prevLandlordPhoneController.dispose();
    _petBreedController.dispose();
    _petAgeController.dispose();
    _petWeightController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep < _totalSteps - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _handleSave();
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _pickTenantPhoto() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
      );
      if (result != null && result.files.single.path != null) {
        setState(() => _tenantPhotoPath = result.files.single.path);
      }
    } catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, LocalizationService.instance.translate("image_pick_error"));
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = LocalizationService.instance;
    return ThemeConstants.buildResponsiveScaffold(
      context,
      title: loc.translate("register_tenant"),
      body: Column(
        children: [
          _buildStepper(),
          Expanded(
            child: Form(
              key: _formKey,
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _currentStep = i),
                children: [
                  _buildStep1(),
                  _buildMergedStep2(), // Contact & Identity
                  _buildMergedStep3(), // Employment & History
                  _buildMergedStep4(), // Living & Property
                ],
              ),
            ),
          ),
          _buildBottomActions(),
        ],
      ),
    );
  }

  Widget _buildStepper() {
    final loc = LocalizationService.instance;
    final steps = [
      loc.translate("personal"),
      loc.translate("contact_identity"),
      loc.translate("employment_history"),
      loc.translate("living_property"),
    ];
    return Container(
      height: 64.h,
      padding: EdgeInsets.symmetric(horizontal: 14.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.08))),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: steps.length,
        separatorBuilder: (context, index) => Icon(Icons.chevron_right, color: Colors.white24, size: 14.w),
        itemBuilder: (context, index) {
          final bool isCompleted = index < _currentStep;
          final bool isCurrent = index == _currentStep;
          return Center(
            child: AnimatedScale(
              duration: const Duration(milliseconds: 200),
              scale: isCurrent ? 1.05 : 1.0,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 26.w,
                    height: 26.w,
                    decoration: BoxDecoration(
                      color: isCurrent ? ThemeConstants.primaryOrange : (isCompleted ? ThemeConstants.successGreen : Colors.white10),
                      shape: BoxShape.circle,
                      boxShadow: isCurrent ? [BoxShadow(color: ThemeConstants.primaryOrange.withOpacity(0.3), blurRadius: 6)] : null,
                    ),
                    child: Center(
                      child: isCompleted 
                        ? Icon(Icons.check, color: Colors.white, size: 14.w)
                        : Text("${index + 1}", style: TextStyle(color: Colors.white, fontSize: 10.sp, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Text(
                    steps[index],
                    style: TextStyle(
                      color: isCurrent ? Colors.white : Colors.white54,
                      fontSize: 11.sp,
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBottomActions() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 20.h),
      decoration: BoxDecoration(
        color: ThemeConstants.bgMid,
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.08))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (_currentStep > 0)
              Expanded(
                child: ThemeConstants.buildResponsiveGlassCard(
                  context,
                  onTap: _prevStep,
                  padding: EdgeInsets.symmetric(vertical: 14.h),
                  child: Center(
                    child: Text(
                      LocalizationService.instance.translate("previous"),
                      style: TextStyle(color: Colors.white, fontSize: 14.sp, fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
              ),
            if (_currentStep > 0) SizedBox(width: 12.w),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _nextStep,
                style: ElevatedButton.styleFrom(
                  backgroundColor: ThemeConstants.primaryOrange,
                  padding: EdgeInsets.symmetric(vertical: 14.h),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
                  elevation: 6,
                  shadowColor: ThemeConstants.primaryOrange.withOpacity(0.4),
                ),
                child: _isSaving 
                  ? SizedBox(height: 20.h, width: 20.h, child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(
                      _currentStep == _totalSteps - 1 
                        ? LocalizationService.instance.translate("submit") 
                        : LocalizationService.instance.translate("next_step"), 
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15.sp),
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Step Content Builders ---

  Widget _buildStep1() {
    final loc = LocalizationService.instance;
    return _buildStepLayout(
      title: "${loc.translate('step')} 1: ${loc.translate('personal_info')}",
      children: [
        ThemeConstants.buildResponsiveGlassCardStatic(
          context,
          padding: EdgeInsets.all(12.w),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  LocalizationService.instance.translate('is_this_user_already_registered'),
                  style: TextStyle(color: Colors.white70, fontSize: 12.sp),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _showExistingTenantSearch,
                icon: const Icon(Icons.search, size: 16),
                label: Text(LocalizationService.instance.translate('select_user')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: ThemeConstants.primaryBlue,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 16.h),
        Row(
          children: [
            Expanded(child: _buildInputField(loc.translate("first_name"), _firstNameController, Icons.person)),
            SizedBox(width: 8.w),
            Expanded(child: _buildInputField(loc.translate("last_name"), _lastNameController, Icons.person)),
          ],
        ),
        SizedBox(height: 12.h),
        Row(
          children: [
            Expanded(child: _buildDropdownField(loc.translate("gender"), _gender, ["Male", "Female", "Other"], (v) => setState(() => _gender = v!), labels: [loc.translate("male"), loc.translate("female"), loc.translate("other")])),
            SizedBox(width: 8.w),
            Expanded(child: _buildDatePickerField(loc.translate("birth_date"), _dob, (d) => setState(() => _dob = d))),
          ],
        ),
        SizedBox(height: 12.h),
        Row(
          children: [
            Expanded(child: _buildInputField(loc.translate("nida_id"), _nidaController, Icons.badge)),
            SizedBox(width: 8.w),
            Expanded(child: _buildInputField(loc.translate("phone_no"), _phoneController, Icons.phone, keyboardType: TextInputType.phone)),
          ],
        ),
        SizedBox(height: 12.h),
          _buildInputField(loc.translate("email_address"), _emailController, Icons.email, keyboardType: TextInputType.emailAddress),
      ],
    );
  }

  Widget _buildMergedStep2() {
    final loc = LocalizationService.instance;
    return _buildStepLayout(
      title: "${loc.translate('step')} 2: ${loc.translate('contact_identity')}",
      children: [
        // Section: Emergency Contact
        _buildSectionHeader(loc.translate("emergency_contact")),
        Row(
          children: [
            Expanded(child: _buildInputField(loc.translate("contact_name"), _emergencyNameController, Icons.person_outline)),
            SizedBox(width: 8.w),
            Expanded(child: _buildInputField(loc.translate("relationship"), _relationshipController, Icons.family_restroom)),
          ],
        ),
        SizedBox(height: 12.h),
        Row(
          children: [
            Expanded(child: _buildInputField(loc.translate("phone_no"), _emergencyPhoneController, Icons.phone_android, keyboardType: TextInputType.phone)),
            SizedBox(width: 8.w),
            Expanded(child: _buildInputField(loc.translate("email_address"), _emergencyEmailController, Icons.alternate_email, keyboardType: TextInputType.emailAddress)),
          ],
        ),
        SizedBox(height: 24.h),

        // Section: Identity
        _buildSectionHeader(loc.translate("identification")),
        Row(
          children: [
            Expanded(child: _buildInputField(loc.translate("id_number"), _idNumberController, Icons.fingerprint)),
            SizedBox(width: 8.w),
            Expanded(child: _buildInputField(loc.translate("state_issued"), _idStateController, Icons.map)),
          ],
        ),
        SizedBox(height: 12.h),
        Row(
          children: [
            Expanded(child: _buildDatePickerField(loc.translate("exp_date"), _idExpiration, (d) => setState(() => _idExpiration = d))),
            SizedBox(width: 8.w),
            Expanded(child: _buildUploadField(loc.translate("upload_id"))),
          ],
        ),
      ],
    );
  }

  Widget _buildMergedStep3() {
    final loc = LocalizationService.instance;
    return _buildStepLayout(
      title: "${loc.translate('step')} 3: ${loc.translate('employment_history')}",
      children: [
        // Section: Employment
        _buildSectionHeader(loc.translate("employment")),
        Row(
          children: [
            Expanded(child: _buildInputField(loc.translate("employer"), _employerController, Icons.business)),
            SizedBox(width: 8.w),
            Expanded(child: _buildInputField(loc.translate("job_title"), _jobTitleController, Icons.work_outline)),
          ],
        ),
        SizedBox(height: 12.h),
        Row(
          children: [
            Expanded(child: _buildInputField(loc.translate("employment_duration"), _employmentLengthController, Icons.timer)),
            SizedBox(width: 8.w),
            Expanded(child: _buildInputField(loc.translate("work_no"), _workPhoneController, Icons.phone, keyboardType: TextInputType.phone)),
          ],
        ),
        SizedBox(height: 8.h),
        _buildCheckboxRow(loc.translate("currently_employed"), _isEmployed, (v) => setState(() => _isEmployed = v!)),
        SizedBox(height: 24.h),

        // Section: Rental History
        _buildSectionHeader(loc.translate("history")),
        Row(
          children: [
            Expanded(child: _buildInputField(loc.translate("prev_address"), _prevAddressController, Icons.home_work)),
            SizedBox(width: 8.w),
            Expanded(child: _buildInputField(loc.translate("stay_duration"), _stayDurationController, Icons.history)),
          ],
        ),
        SizedBox(height: 12.h),
        Row(
          children: [
            Expanded(child: _buildInputField(loc.translate("reason_leaving"), _reasonForLeavingController, Icons.exit_to_app)),
            SizedBox(width: 8.w),
            Expanded(child: _buildInputField(loc.translate("landlord_name"), _prevLandlordNameController, Icons.person_pin)),
          ],
        ),
        SizedBox(height: 12.h),
        _buildInputField(loc.translate("landlord_phone"), _prevLandlordPhoneController, Icons.phone, keyboardType: TextInputType.phone),
      ],
    );
  }

  Widget _buildMergedStep4() {
    final loc = LocalizationService.instance;
    final rentalProvider = context.watch<RentalProvider>();
    final properties = rentalProvider.properties;

    List<dynamic> houses = [];
    if (_selectedPropertyId != null) {
      final prop = properties.firstWhere((p) => p['id'].toString() == _selectedPropertyId, orElse: () => null);
      if (prop != null) {
        houses = (prop['houses'] as List? ?? []).where((h) => 
          h['status'] == 'vacant' || 
          h['is_occupied'] == 0 || 
          h['is_occupied'] == false
        ).toList();
      }
    }

    return _buildStepLayout(
      title: "${loc.translate('step')} 4: ${loc.translate('living_property')}",
      children: [
        // Section: Occupants & Pets
        _buildSectionHeader(loc.translate("peeps")),
        Row(
          children: [
            Expanded(child: _buildNumberField(loc.translate("adults_count"), _adultsCount, (v) => setState(() => _adultsCount = v))),
            SizedBox(width: 8.w),
            Expanded(child: _buildNumberField(loc.translate("children_count"), _childrenCount, (v) => setState(() => _childrenCount = v))),
          ],
        ),
        SizedBox(height: 12.h),
        Row(
          children: [
            Expanded(child: _buildDropdownField(loc.translate("others_stay"), _willOthersLive ? "Yes" : "No", ["Yes", "No"], (v) => setState(() => _willOthersLive = v == "Yes"), labels: [loc.translate("yes"), loc.translate("no")])),
            SizedBox(width: 8.w),
            Expanded(child: _buildDropdownField(loc.translate("pet_type"), _petType, ["None", "Dog", "Cat", "Other"], (v) => setState(() => _petType = v!), labels: [loc.translate("none"), loc.translate("dog"), loc.translate("cat"), loc.translate("other")])),
          ],
        ),
        if (_petType != "None") ...[
          SizedBox(height: 12.h),
          Row(
            children: [
              Expanded(child: _buildInputField(loc.translate("breed"), _petBreedController, Icons.pets)),
              SizedBox(width: 8.w),
              Expanded(child: _buildInputField(loc.translate("pet_age"), _petAgeController, Icons.cake, keyboardType: TextInputType.number)),
            ],
          ),
          SizedBox(height: 12.h),
          _buildInputField(loc.translate("pet_weight"), _petWeightController, Icons.scale, keyboardType: TextInputType.number),
        ],
        SizedBox(height: 24.h),

        // Section: Property & House Selection
        _buildSectionHeader(loc.translate("terms")),
        Row(
          children: [
            Expanded(
              child: _buildDropdownField(
                loc.translate("property"), 
                _selectedPropertyId, 
                properties.map((p) => p['id'].toString()).toList(),
                (v) => setState(() { _selectedPropertyId = v; _selectedHouseId = null; }),
                labels: properties.map((p) => p['name'].toString()).toList(),
              ),
            ),
            SizedBox(width: 8.w),
            Expanded(
              child: _buildDropdownField(
                loc.translate("house"), 
                _selectedHouseId, 
                houses.map((h) => h['id'].toString()).toList(),
                (v) => setState(() { 
                  _selectedHouseId = v; 
                  final house = houses.firstWhere((h) => h['id'].toString() == v, orElse: () => null);
                  if (house != null) {
                    final rent = house['rent'] ?? house['rent_amount'];
                    if (rent != null) {
                      _amountController.text = num.parse(rent.toString()).toStringAsFixed(0);
                    }
                  }
                }),
                labels: houses.map((h) => h['house_number'].toString()).toList(),
              ),
            ),
          ],
        ),
        if (_selectedHouseId != null) ...[
          Builder(builder: (context) {
            final house = houses.firstWhere((h) => h['id'].toString() == _selectedHouseId, orElse: () => null);
            if (house == null || (house['units_count'] ?? 0) == 0) return const SizedBox();
            
            final List<String> allUnits = (house['unit_names'] as List? ?? []).map((e) => e.toString()).toList();
            if (allUnits.isEmpty) return const SizedBox();

            // Calculate occupied units from active agreements if available
            // For now, we'll assume the house object might have 'occupied_units' if we updated the backend to return it
            // or we'll just show all and handle busy units on the backend response
            final occupiedUnits = (house['occupied_units'] as List? ?? []).map((e) => e.toString()).toList();
            final availableUnits = allUnits.where((u) => !occupiedUnits.contains(u)).toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 12.h),
                _buildCheckboxRow(loc.translate("rent_whole_house"), _rentWholeHouse, (v) {
                  setState(() {
                    _rentWholeHouse = v ?? true;
                    if (_rentWholeHouse) {
                      _selectedUnits = List.from(allUnits);
                    } else {
                      _selectedUnits = [];
                    }
                  });
                }),
                if (!_rentWholeHouse) ...[
                  SizedBox(height: 8.h),
                  Text(loc.translate("select_units_prompt"), style: TextStyle(color: Colors.white70, fontSize: 11.sp)),
                  SizedBox(height: 8.h),
                  Wrap(
                    spacing: 8.w,
                    runSpacing: 8.h,
                    children: availableUnits.map((u) {
                      final isSelected = _selectedUnits.contains(u);
                      return FilterChip(
                        label: Text(u, style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 12.sp)),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              _selectedUnits.add(u);
                            } else {
                              _selectedUnits.remove(u);
                            }
                            if (_selectedUnits.length == allUnits.length) {
                              _rentWholeHouse = true;
                            } else {
                              _rentWholeHouse = false;
                            }
                          });
                        },
                        selectedColor: ThemeConstants.primaryOrange,
                        backgroundColor: Colors.white.withOpacity(0.05),
                        checkmarkColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
                      );
                    }).toList(),
                  ),
                ],
              ],
            );
          }),
        ],
        SizedBox(height: 12.h),
        Row(
          children: [
            Expanded(child: _buildInputField(loc.translate("rent_amount"), _amountController, Icons.payments, keyboardType: TextInputType.number)),
            SizedBox(width: 8.w),
            Expanded(child: _buildDatePickerField(loc.translate("start_date"), _startDate, (d) => setState(() { if (d != null) _startDate = d; }))),
          ],
        ),
        SizedBox(height: 16.h),
        _buildPhotoUploadField(loc.translate("capture_tenant_photo"), _tenantPhotoPath, _pickTenantPhoto),
        SizedBox(height: 12.h),
        _buildInputField(loc.translate("additional_notes"), _notesController, Icons.note_alt),
        SizedBox(height: 16.h),
        
        ThemeConstants.buildResponsiveGlassCardStatic(
          context,
          padding: EdgeInsets.all(12.w),
          child: Column(
            children: [
              _buildCheckboxRow(loc.translate("accept_terms"), _acceptedTerms, (v) => setState(() => _acceptedTerms = v!)),
              _buildCheckboxRow(loc.translate("agree_privacy"), _acceptedPrivacy, (v) => setState(() => _acceptedPrivacy = v!)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12.h, top: 4.h),
      child: Row(
        children: [
          Container(
            width: 4.w,
            height: 16.h,
            decoration: BoxDecoration(
              color: ThemeConstants.primaryBlue,
              borderRadius: BorderRadius.circular(2.r),
            ),
          ),
          SizedBox(width: 8.w),
          Text(
            title.toUpperCase(),
            style: TextStyle(
              color: Colors.white70,
              fontSize: 11.sp,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  // --- Helper Widgets ---

  Widget _buildStepLayout({required String title, required List<Widget> children}) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 20.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(left: 4.w, bottom: 20.h),
            child: Text(
              title,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18.sp,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
          ...children,
          SizedBox(height: 120.h), // Extra space for bottom actions
        ],
      ),
    );
  }

  Widget _buildInputField(String label, TextEditingController controller, IconData icon, {TextInputType? keyboardType}) {
    return ThemeConstants.buildResponsiveGlassCardStatic(
      context,
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(color: Colors.white, fontSize: 12),
        decoration: ThemeConstants.invInputDecoration(label).copyWith(
          prefixIcon: Icon(icon, color: Colors.white70, size: 14.w),
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
          contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
        ),
      ),
    );
  }

  Widget _buildDropdownField(String label, String? value, List<String> items, Function(String?) onChanged, {List<String>? labels}) {
    return ThemeConstants.buildResponsiveGlassCardStatic(
      context,
      child: DropdownButtonFormField<String>(
        initialValue: items.contains(value) ? value : null,
        isExpanded: true,
        items: List.generate(items.length, (i) => DropdownMenuItem(
          value: items[i],
          child: Text(labels != null ? labels[i] : items[i], style: const TextStyle(fontSize: 12)),
        )),
        onChanged: onChanged,
        dropdownColor: ThemeConstants.bgMid,
        style: const TextStyle(color: Colors.white),
        decoration: ThemeConstants.invInputDecoration(label).copyWith(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
          contentPadding: EdgeInsets.only(left: 12.w, right: 8.w, top: 4.h, bottom: 4.h),
        ),
      ),
    );
  }

  Widget _buildDatePickerField(String label, DateTime? date, Function(DateTime?) onSelected) {
    final loc = LocalizationService.instance;
    return ThemeConstants.buildResponsiveGlassCard(
      context,
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date ?? DateTime.now(),
          firstDate: DateTime(1920),
          lastDate: DateTime(2100),
        );
        if (picked != null) onSelected(picked);
      },
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 10.h),
        child: Row(
          children: [
            Icon(Icons.calendar_today, color: Colors.white70, size: 14.w),
            SizedBox(width: 8.w),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10)),
                Text(
                  date != null ? "${date.day}/${date.month}/${date.year}" : loc.translate("select"),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNumberField(String label, int value, Function(int) onChanged) {
    return ThemeConstants.buildResponsiveGlassCardStatic(
      context,
      padding: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10), overflow: TextOverflow.ellipsis)),
            IconButton(
              constraints: const BoxConstraints(),
              padding: EdgeInsets.all(4.w),
              iconSize: 16.w,
              icon: const Icon(Icons.remove, color: Colors.white70),
              onPressed: () => value > 0 ? onChanged(value - 1) : null,
            ),
            Text("$value", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
            IconButton(
              constraints: const BoxConstraints(),
              padding: EdgeInsets.all(4.w),
              iconSize: 16.w,
              icon: const Icon(Icons.add, color: Colors.white70),
              onPressed: () => onChanged(value + 1),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadField(String label) {
    final loc = LocalizationService.instance;
    return ThemeConstants.buildResponsiveGlassCard(
      context,
      padding: EdgeInsets.zero,
      onTap: () async {
        final result = await FilePicker.platform.pickFiles();
        if (result != null && result.files.single.path != null) {
          setState(() {
            _idDocPath = result.files.single.path;
            _idDocName = result.files.single.name;
          });
          if (mounted) ThemeConstants.showSuccessSnackBar(context, "${LocalizationService.instance.translate('photo_attached')}: $_idDocName");
        }
      },
      child: Container(
        height: 48.h,
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(horizontal: 12.w),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _idDocPath != null ? Icons.check_circle : Icons.upload_file, 
              color: _idDocPath != null ? ThemeConstants.successGreen : ThemeConstants.primaryOrange, 
              size: 18.w
            ),
            SizedBox(width: 4.w),
            Expanded(
              child: Text(
                _idDocName ?? LocalizationService.instance.translate("attach"), 
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoUploadField(String label, String? path, VoidCallback onTap) {
    final loc = LocalizationService.instance;
    return ThemeConstants.buildResponsiveGlassCard(
      context,
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(12.w),
        width: double.infinity,
        height: 80.h,
        child: Row(
          children: [
            Container(
              width: 56.h,
              height: 56.h,
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(12.r),
                image: path != null ? DecorationImage(image: FileImage(File(path)), fit: BoxFit.cover) : null,
              ),
              child: path == null ? Icon(Icons.add_a_photo, color: Colors.white38, size: 20.w) : null,
            ),
            SizedBox(width: 16.w),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  Text(
                    path != null ? LocalizationService.instance.translate("photo_attached") : LocalizationService.instance.translate("tap_to_upload"),
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (path != null) Icon(Icons.check_circle, color: ThemeConstants.successGreen, size: 20.w),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckboxRow(String label, bool value, Function(bool?) onChanged) {
    return Row(
      children: [
        SizedBox(
          width: 24.w,
          child: Checkbox(
            value: value,
            onChanged: onChanged,
            activeColor: ThemeConstants.primaryOrange,
            side: const BorderSide(color: Colors.white54),
          ),
        ),
        SizedBox(width: 8.w),
        Expanded(child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11))),
      ],
    );
  }



  void _showExistingTenantSearch() {
    final apiService = context.read<ApiService>();
    String searchQuery = '';
    List<dynamic> results = [];
    bool isSearching = false;

    bool didInitialSearch = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateSheet) {
            void performSearch() async {
              setStateSheet(() => isSearching = true);
              try {
                final data = await apiService.getSystemTenants(query: searchQuery);
                setStateSheet(() {
                  results = data;
                  isSearching = false;
                });
              } catch (e) {
                setStateSheet(() => isSearching = false);
              }
            }

            // Trigger initial search on open if not already searching/searched
            if (!isSearching && !didInitialSearch && searchQuery.isEmpty) {
              didInitialSearch = true;
              Future.microtask(() => performSearch());
            }

            return Container(
              height: MediaQuery.of(context).size.height * 0.7,
              decoration: BoxDecoration(
                color: ThemeConstants.bgMid,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
              ),
              child: Column(
                children: [
                  Container(
                    margin: EdgeInsets.only(top: 12.h, bottom: 16.h),
                    width: 40.w,
                    height: 4.h,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2.r),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20.w),
                    child: Text(
                      LocalizationService.instance.translate('search_existing_users'),
                      style: ThemeConstants.subHeadingStyle,
                    ),
                  ),
                  SizedBox(height: 16.h),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20.w),
                    child: TextField(
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: LocalizationService.instance.translate('search_name_email_or_phone'),
                        hintStyle: const TextStyle(color: Colors.white38),
                        prefixIcon: const Icon(Icons.search, color: Colors.white54),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.05),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide.none),
                      ),
                      onChanged: (val) {
                        searchQuery = val.trim();
                      },
                      onSubmitted: (_) => performSearch(),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: ThemeConstants.primaryOrange),
                        onPressed: performSearch,
                        child: Text(LocalizationService.instance.translate('search'), style: TextStyle(color: Colors.white)),
                      ),
                    ),
                  ),
                  Expanded(
                    child: isSearching
                        ? const Center(child: CircularProgressIndicator())
                        : results.isEmpty
                            ? Center(
                                child: Text(LocalizationService.instance.translate('no_users_found'), style: TextStyle(color: Colors.white54, fontSize: 14.sp)),
                              )
                            : ListView.builder(
                                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                                itemCount: results.length,
                                itemBuilder: (context, index) {
                                  final user = results[index];
                                  return ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: ThemeConstants.primaryOrange.withOpacity(0.2),
                                      child: const Icon(Icons.person, color: ThemeConstants.primaryOrange),
                                    ),
                                    title: Text(user['name'] ?? '', style: const TextStyle(color: Colors.white)),
                                    subtitle: Text("${user['email']} • ${user['phone_number'] ?? ''}", style: const TextStyle(color: Colors.white54)),
                                    onTap: () {
                                      final nameParts = (user['name'] ?? '').toString().split(' ');
                                      _firstNameController.text = nameParts.first;
                                      if (nameParts.length > 1) {
                                        _lastNameController.text = nameParts.sublist(1).join(' ');
                                      }
                                      _emailController.text = user['email'] ?? '';
                                      _phoneController.text = user['phone_number'] ?? '';
                                      Navigator.pop(ctx);
                                    },
                                  );
                                },
                              ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _handleSave() async {
    final loc = LocalizationService.instance;
    if (!_formKey.currentState!.validate()) return;
    if (_selectedHouseId == null) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, loc.translate("select_house_error"));
      return;
    }
    if (!_acceptedTerms || !_acceptedPrivacy) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, loc.translate("accept_terms_error"));
      return;
    }

    setState(() => _isSaving = true);
    
    final data = {
      "first_name": _firstNameController.text,
      "last_name": _lastNameController.text,
      "email": _emailController.text,
      "phone": _phoneController.text,
      "dob": _dob?.toIso8601String().split('T')[0],
      "nida": _nidaController.text,
      "gender": _gender,
      "occupation": _jobTitleController.text,
      "emergency_contact_name": _emergencyNameController.text,
      "emergency_contact_phone": _emergencyPhoneController.text,
      "emergency_contact_relationship": _relationshipController.text,
      "notes": _notesController.text,
      "emergency_contact": {
        "name": _emergencyNameController.text,
        "relationship": _relationshipController.text,
        "phone": _emergencyPhoneController.text,
        "email": _emergencyEmailController.text,
      },
      "id_details": {
        "number": _idNumberController.text,
        "state": _idStateController.text,
        "expiration": _idExpiration?.toIso8601String().split('T')[0],
      },
      "id_number": _idNumberController.text,
      "employment": {
        "employer": _employerController.text,
        "title": _jobTitleController.text,
        "length": _employmentLengthController.text,
        "work_phone": _workPhoneController.text,
        "status": _isEmployed ? "Employed" : "Unemployed",
      },
      "history": {
        "prev_address": _prevAddressController.text,
        "duration": _stayDurationController.text,
        "reason": _reasonForLeavingController.text,
        "landlord_name": _prevLandlordNameController.text,
        "landlord_phone": _prevLandlordPhoneController.text,
      },
      "occupants": {
        "adults": _adultsCount,
        "children": _childrenCount,
        "others_will_live": _willOthersLive,
      },
      "pets": {
          "type": _petType,
          "breed": _petBreedController.text,
          "age": _petAgeController.text,
          "weight": _petWeightController.text,
      },
      "rental_house_id": _selectedHouseId,
      "house_id": _selectedHouseId,
      "property_id": _selectedPropertyId,
      "rent_amount": _amountController.text,
      "start_date": _startDate.toIso8601String().split('T')[0],
      "tenant_photo": _tenantPhotoPath,
      "id_document": _idDocPath,
      "selected_units": _selectedUnits,
    };

    final success = await context.read<RentalProvider>().onboardTenant(data);

    if (mounted) {
      setState(() => _isSaving = false);
      if (success != null) {
        // A brand-new tenant gets a one-time password from the server. It is shown once,
        // here, for the landlord to hand over; the tenant replaces it at first sign-in.
        final String? temporaryPassword = context.read<RentalProvider>().lastTemporaryPassword;
        if (temporaryPassword != null) {
          await showTemporaryPasswords(context, <TemporaryCredential>[
            TemporaryCredential(
              name: "${_firstNameController.text} ${_lastNameController.text}".trim(),
              contact: "${_emailController.text} · ${_phoneController.text}",
              password: temporaryPassword,
            ),
          ]);
          if (!mounted) return;
        }

        ThemeConstants.showSuccessSnackBar(context, loc.translate("tenant_onboarded_success"));

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: ThemeConstants.bgMid,
            title: Text(LocalizationService.instance.translate('tenant_onboarded'), style: const TextStyle(color: Colors.white)),
            content: Text(LocalizationService.instance.translate('do_you_want_to_record_the'), style: const TextStyle(color: Colors.white70)),
            actions: [
              TextButton(
                onPressed: () {
                  final nav = Navigator.of(context);
                  nav.pop(); // close dialog
                  nav.pop(); // close onboard screen
                },
                child: Text(LocalizationService.instance.translate('not_now'), style: const TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                onPressed: () {
                  final nav = Navigator.of(context);
                  nav.pop(); // close dialog
                  nav.pop(); // close onboard screen
                  nav.push(MaterialPageRoute(
                    builder: (_) => RecordPaymentScreen(
                      preSelectedTenant: {'id': success == 'success' ? null : success},
                    )
                  ));
                },
                style: ElevatedButton.styleFrom(backgroundColor: ThemeConstants.primaryOrange),
                child: Text(LocalizationService.instance.translate('yes_record_payment'), style: const TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      } else {
        ThemeConstants.showErrorSnackBar(context, loc.translate("failed_to_onboard"));
      }
    }
  }
}
