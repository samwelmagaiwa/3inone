import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import '../../constants/theme_constants.dart';
import '../../providers/rental_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/localization_service.dart';
import '../../utils/rental_flow_validator.dart';
import 'onboard_tenant_screen.dart';
import 'record_payment_screen.dart';

class LeaseAgreementWizardScreen extends StatefulWidget {
  final Map<String, dynamic>? preSelectedTenant;
  final Map<String, dynamic>? preSelectedProperty;
  final Map<String, dynamic>? preSelectedHouse;

  const LeaseAgreementWizardScreen({
    super.key,
    this.preSelectedTenant,
    this.preSelectedProperty,
    this.preSelectedHouse,
  });

  @override
  State<LeaseAgreementWizardScreen> createState() => _LeaseAgreementWizardScreenState();
}

class _LeaseAgreementWizardScreenState extends State<LeaseAgreementWizardScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  final int _totalSteps = 6;
  final _formKey = GlobalKey<FormState>();

  File? _signatureFile;
  final ImagePicker _picker = ImagePicker();

  // --- Step 1: Selection ---
  String? _selectedTenantId;
  String? _selectedPropertyId;
  String? _selectedHouseId;
  Map<String, dynamic>? _selectedHouseData;

  // --- Step 2: Terms & Financials ---
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 365));
  final _rentController = TextEditingController();
  final _depositAmountController = TextEditingController();
  final _depositPaidController = TextEditingController();
  int _advanceMonths = 1; // Default 1 month

  // --- Step 3: Billing Cycle & Fees ---
  String _billingCycle = 'monthly';
  int _dueDay = 5;
  int _gracePeriod = 0;
  String _lateFeeType = 'none';
  final _lateFeeAmountController = TextEditingController();
  bool _autoRenew = false;

  // --- Step 4: Utilities & Extra Charges ---
  final Map<String, bool> _utilities = {
    'utilities_water': false,
    'utilities_electricity': false,
    'service_charge': false,
    'parking_space': false,
  };
  final Map<String, TextEditingController> _utilityAmounts = {
    'utilities_water': TextEditingController(),
    'utilities_electricity': TextEditingController(),
    'service_charge': TextEditingController(),
    'parking_space': TextEditingController(),
  };

  // --- Step 5: Rules & Policies ---
  final _landlordObligationsController = TextEditingController();
  final _tenantObligationsController = TextEditingController();
  final _terminationPolicyController = TextEditingController();

  // --- Step 5: Beautiful 12 Clauses ---
  late final List<_LeaseClause> _leaseClauses;
  String _activeCategory = 'tenant'; // 'tenant', 'maintenance', 'legal'

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.preSelectedTenant != null) {
      _selectedTenantId = widget.preSelectedTenant!['id']?.toString();
    }
    if (widget.preSelectedProperty != null) {
      _selectedPropertyId = widget.preSelectedProperty!['id']?.toString();
    }
    if (widget.preSelectedHouse != null) {
      _selectedHouseId = widget.preSelectedHouse!['id']?.toString();
      _selectedHouseData = widget.preSelectedHouse;
      final rent = (_selectedHouseData?['rent_amount'] ?? _selectedHouseData?['rent'] ?? '').toString();
      final deposit = (_selectedHouseData?['deposit_amount'] ?? _selectedHouseData?['deposit'] ?? rent).toString();
      _rentController.text = rent;
      if (deposit.isNotEmpty) {
        _depositAmountController.text = deposit;
        _depositPaidController.text = deposit;
      }
    }

    _rentController.addListener(() {
      if (_rentController.text.isNotEmpty && _currentStep == 1) { // Only auto-fill if we are in Step 2 (VIPINDI)
        // If deposit is empty, suggest rent. If not, leave it.
        if (_depositAmountController.text.isEmpty) {
          _depositAmountController.text = _rentController.text;
        }
        if (_depositPaidController.text.isEmpty) {
          _depositPaidController.text = _rentController.text;
        }
      }
    });

    if (widget.preSelectedHouse != null) {
      context.read<RentalProvider>().fetchHouseDetails(widget.preSelectedHouse!['id'].toString()).then((details) {
        if (details != null && mounted) {
          setState(() {
            _selectedHouseData = details;
            final rent = (details['rent_amount'] ?? details['rent'] ?? _rentController.text).toString();
            final deposit = (details['deposit_amount'] ?? details['deposit'] ?? rent).toString();
            _rentController.text = rent;
            if (deposit.isNotEmpty) {
              _depositAmountController.text = deposit;
              _depositPaidController.text = deposit;
            }
          });
        }
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Validate tenants exist
      RentalFlowValidator.validateStep(
        context: context,
        fetchData: (p) => p.fetchTenants(),
        condition: (p) => p.tenants.isNotEmpty,
        title: LocalizationService.instance.translate('no_tenants'),
        message: LocalizationService.instance.translate('you_need_to_onboard_a_tenant'),
        actionLabel: LocalizationService.instance.translate('onboard_tenant'),
        onAction: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const OnboardTenantScreen())),
      ).then((_) {
        if (!mounted) return;
        // Validate houses exist
        RentalFlowValidator.validateStep(
          context: context,
          fetchData: (p) => p.fetchProperties(),
          condition: (p) => RentalFlowValidator.hasHouses(p),
          title: LocalizationService.instance.translate('no_houses_found'),
          message: LocalizationService.instance.translate('you_need_to_have_a_property'),
          actionLabel: LocalizationService.instance.translate('add_property'),
          onAction: () => Navigator.pushReplacementNamed(context, '/rental/add-property'),
        );
      });
    });

    // Initialize default obligations from our new clauses
    final isSw = LocalizationService.instance.isSwahili;
    final lang = isSw ? 'sw' : 'en';
    
    _leaseClauses = [
      _LeaseClause(
        id: 'security_deposit',
        title: _clauseDefaults[lang]!['security_deposit_title']!,
        icon: Icons.shield_outlined,
        defaultText: _clauseDefaults[lang]!['security_deposit_text']!,
        text: _clauseDefaults[lang]!['security_deposit_text']!,
        category: 'legal',
      ),
      _LeaseClause(
        id: 'late_payment',
        title: _clauseDefaults[lang]!['late_payment_title']!,
        icon: Icons.hourglass_empty_rounded,
        defaultText: _clauseDefaults[lang]!['late_payment_text']!,
        text: _clauseDefaults[lang]!['late_payment_text']!,
        category: 'tenant',
      ),
      _LeaseClause(
        id: 'maintenance',
        title: _clauseDefaults[lang]!['maintenance_title']!,
        icon: Icons.build_outlined,
        defaultText: _clauseDefaults[lang]!['maintenance_text']!,
        text: _clauseDefaults[lang]!['maintenance_text']!,
        category: 'maintenance',
      ),
      _LeaseClause(
        id: 'utilities',
        title: _clauseDefaults[lang]!['utilities_title']!,
        icon: Icons.power_outlined,
        defaultText: _clauseDefaults[lang]!['utilities_text']!,
        text: _clauseDefaults[lang]!['utilities_text']!,
        category: 'tenant',
      ),
      _LeaseClause(
        id: 'inspection',
        title: _clauseDefaults[lang]!['inspection_title']!,
        icon: Icons.visibility_outlined,
        defaultText: _clauseDefaults[lang]!['inspection_text']!,
        text: _clauseDefaults[lang]!['inspection_text']!,
        category: 'maintenance',
      ),
      _LeaseClause(
        id: 'subleasing',
        title: _clauseDefaults[lang]!['subleasing_title']!,
        icon: Icons.people_outline_rounded,
        defaultText: _clauseDefaults[lang]!['subleasing_text']!,
        text: _clauseDefaults[lang]!['subleasing_text']!,
        category: 'legal',
      ),
      _LeaseClause(
        id: 'use_of_premises',
        title: _clauseDefaults[lang]!['use_of_premises_title']!,
        icon: Icons.home_work_outlined,
        defaultText: _clauseDefaults[lang]!['use_of_premises_text']!,
        text: _clauseDefaults[lang]!['use_of_premises_text']!,
        category: 'tenant',
      ),
      _LeaseClause(
        id: 'damages_repairs',
        title: _clauseDefaults[lang]!['damages_repairs_title']!,
        icon: Icons.handyman_outlined,
        defaultText: _clauseDefaults[lang]!['damages_repairs_text']!,
        text: _clauseDefaults[lang]!['damages_repairs_text']!,
        category: 'tenant',
      ),
      _LeaseClause(
        id: 'pets_policy',
        title: _clauseDefaults[lang]!['pets_policy_title']!,
        icon: Icons.pets_outlined,
        defaultText: _clauseDefaults[lang]!['pets_policy_text']!,
        text: _clauseDefaults[lang]!['pets_policy_text']!,
        category: 'tenant',
        isEnabled: false, // Optional by default
      ),
      _LeaseClause(
        id: 'insurance',
        title: _clauseDefaults[lang]!['insurance_title']!,
        icon: Icons.admin_panel_settings_outlined,
        defaultText: _clauseDefaults[lang]!['insurance_text']!,
        text: _clauseDefaults[lang]!['insurance_text']!,
        category: 'legal',
      ),
      _LeaseClause(
        id: 'termination_conditions',
        title: _clauseDefaults[lang]!['termination_conditions_title']!,
        icon: Icons.gavel_outlined,
        defaultText: _clauseDefaults[lang]!['termination_conditions_text']!,
        text: _clauseDefaults[lang]!['termination_conditions_text']!,
        category: 'legal',
      ),
      _LeaseClause(
        id: 'governing_law',
        title: _clauseDefaults[lang]!['governing_law_title']!,
        icon: Icons.gavel_rounded,
        defaultText: _clauseDefaults[lang]!['governing_law_text']!,
        text: _clauseDefaults[lang]!['governing_law_text']!,
        category: 'legal',
      ),
    ];

    _syncLegacyObligations();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _rentController.dispose();
    _depositAmountController.dispose();
    _depositPaidController.dispose();
    _lateFeeAmountController.dispose();
    _utilityAmounts.values.forEach((c) => c.dispose());
    _landlordObligationsController.dispose();
    _tenantObligationsController.dispose();
    _terminationPolicyController.dispose();
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

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final loc = LocalizationService.instance;

    // Fail-safe: Redirect tenants who somehow reach this management wizard
    if (user?.role == 'tenant') {
       WidgetsBinding.instance.addPostFrameCallback((_) {
         Navigator.pushReplacementNamed(context, '/rental/tenant-self-service');
       });
       return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return ThemeConstants.buildResponsiveScaffold(
      context,
      title: loc.translate('lease_wizard'),
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
                  _buildStep2(),
                  _buildStep3(),
                  _buildStep4(),
                  _buildStep5(),
                  _buildStep6(),
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
      loc.translate("step_selection"),
      loc.translate("step_terms"),
      loc.translate("step_payments"),
      loc.translate("step_utilities"),
      loc.translate("step_rules"),
      loc.translate("step_review"),
    ];
    return Container(
      height: 60.h,
      padding: EdgeInsets.symmetric(horizontal: 14.w),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: steps.length,
        separatorBuilder: (context, index) => Icon(Icons.chevron_right, color: Colors.white24, size: 14.w),
        itemBuilder: (context, index) {
          final isCurrent = index == _currentStep;
          final isDone = index < _currentStep;
          return Center(
            child: Row(
              children: [
                Container(
                  width: 24.w,
                  height: 24.w,
                  decoration: BoxDecoration(
                    color: isCurrent ? ThemeConstants.primaryOrange : (isDone ? ThemeConstants.successGreen : Colors.white10),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: isDone ? Icon(Icons.check, size: 12.w, color: Colors.white) : Text("${index + 1}", style: TextStyle(fontSize: 10.sp, color: Colors.white, fontWeight: FontWeight.bold)),
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
          );
        },
      ),
    );
  }

  Widget _buildBottomActions() {
    final loc = LocalizationService.instance;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 20.h),
      decoration: BoxDecoration(
        color: ThemeConstants.bgMid,
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
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
                  padding: EdgeInsets.all(12.h),
                  child: Center(child: Text(loc.translate("previous"), style: const TextStyle(color: Colors.white))),
                ),
              ),
            if (_currentStep > 0) SizedBox(width: 12.w),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _nextStep,
                style: ElevatedButton.styleFrom(
                  backgroundColor: ThemeConstants.primaryOrange,
                  padding: EdgeInsets.symmetric(vertical: 12.h),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                ),
                child: _isSaving 
                   ? SizedBox(height: 20.h, width: 20.h, child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                   : Text(_currentStep == _totalSteps - 1 ? loc.translate("complete") : loc.translate("next_step"), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Step 1: Selection ---
  Widget _buildStep1() {
    final rentalProvider = context.watch<RentalProvider>();
    final tenants = rentalProvider.tenants;
    final properties = rentalProvider.properties;

    List<dynamic> houses = [];
    if (_selectedPropertyId != null) {
      final prop = properties.firstWhere((p) => p['id'].toString() == _selectedPropertyId, orElse: () => null);
      if (prop != null) {
        houses = (prop['houses'] as List? ?? []).where((h) => 
          h['status'] == 'vacant' || h['current_tenant_id'] == null
        ).toList();
      }
    }

    final loc = LocalizationService.instance;
    return _buildStepLayout(
      title: loc.translate("step_selection"),
      children: [
        _buildDropdownField(
          loc.translate("select_tenant"), 
          _selectedTenantId, 
          tenants.map((t) => t['id'].toString()).toList(),
          (v) => setState(() => _selectedTenantId = v),
          labels: tenants.map((t) => t['name'].toString()).toList(),
          icon: Icons.person,
        ),
        SizedBox(height: 16.h),
        _buildDropdownField(
          loc.translate("select_property"), 
          _selectedPropertyId, 
          properties.map((p) => p['id'].toString()).toList(),
          (v) => setState(() { _selectedPropertyId = v; _selectedHouseId = null; }),
          labels: properties.map((p) => p['name'].toString()).toList(),
          icon: Icons.business,
        ),
        SizedBox(height: 16.h),
        _buildDropdownField(
          loc.translate("select_house"), 
          _selectedHouseId, 
          houses.map((h) => h['id'].toString()).toList(),
          (v) => _handleHouseSelection(v, houses),
          labels: houses.map((h) => "No: ${h['house_number']} (${h['type']})").toList(),
          icon: Icons.house,
          enabled: _selectedPropertyId != null,
        ),
        if (_selectedHouseData != null) ...[
          SizedBox(height: 20.h),
          ThemeConstants.buildResponsiveGlassCardStatic(
            context,
            padding: EdgeInsets.all(16.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(loc.translate("house_details"), style: TextStyle(color: Colors.white70, fontSize: 12.sp)),
                SizedBox(height: 8.h),
                _buildInfoRow(Icons.payments, "${loc.translate('rent')}:", "${_selectedHouseData!['rent_amount'] ?? _selectedHouseData!['rent']} TZS"),
                _buildInfoRow(Icons.meeting_room, "${loc.translate('type')}:", "${_selectedHouseData!['type']}"),
                _buildInfoRow(Icons.layers, "${loc.translate('floor')}:", "${_selectedHouseData!['floor']}"),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // --- Step 2: Terms & Financials ---
  Widget _buildStep2() {
    final loc = LocalizationService.instance;
    return _buildStepLayout(
      title: loc.translate("step_terms"),
      children: [
        Row(
          children: [
            Expanded(child: _buildDatePickerField(loc.translate("start_date"), _startDate, (d) => setState(() => _startDate = d!))),
            SizedBox(width: 12.w),
            Expanded(child: _buildDatePickerField(loc.translate("end_date"), _endDate, (d) => setState(() => _endDate = d!))),
          ],
        ),
        SizedBox(height: 16.h),
        _buildInputField(loc.translate("rent_monthly"), _rentController, Icons.payments, keyboardType: TextInputType.number),
        SizedBox(height: 16.h),
        _buildInputField(loc.translate("security_deposit"), _depositAmountController,
            Icons.account_balance_wallet,
            keyboardType: TextInputType.number),
        SizedBox(height: 16.h),
        _buildInputField(loc.translate("deposit_paid"), _depositPaidController,
            Icons.check_circle_outline,
            keyboardType: TextInputType.number),
        SizedBox(height: 16.h),
        _buildDropdownField(
          loc.translate("advance_months"),
          _advanceMonths.toString(),
          List.generate(12, (i) => (i + 1).toString()),
          (v) => setState(() => _advanceMonths = int.parse(v!)),
          icon: Icons.timer,
        ),
        if (_rentController.text.isNotEmpty) ...[
          SizedBox(height: 12.h),
          ThemeConstants.buildResponsiveGlassCardStatic(
            context,
            padding: EdgeInsets.all(12.w),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(loc.translate("total_prepaid"), style: TextStyle(color: Colors.white54, fontSize: 10.sp)),
                    Text("TZS ${((double.tryParse(_rentController.text) ?? 0) * _advanceMonths).toStringAsFixed(2)}", 
                         style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(loc.translate("paid_until"), style: TextStyle(color: Colors.white54, fontSize: 10.sp)),
                    Text(DateFormat('dd/MM/yyyy').format(DateTime(_startDate.year, _startDate.month + _advanceMonths, _startDate.day)), 
                         style: const TextStyle(color: ThemeConstants.successGreen, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // --- Step 3: Billing & Fees ---
  Widget _buildStep3() {
    final loc = LocalizationService.instance;
    return _buildStepLayout(
      title: loc.translate("step_payments"),
      children: [
        _buildDropdownField(
          loc.translate("billing_cycle"),
          _billingCycle,
          ['monthly', 'quarterly', 'semi_annual', 'annual'],
          (v) => setState(() => _billingCycle = v!),
          labels: [
            loc.translate("monthly"),
            loc.translate("quarterly"),
            loc.translate("semi_annual"),
            loc.translate("annual")
          ],
          icon: Icons.refresh,
        ),
        SizedBox(height: 16.h),
        _buildDropdownField(
          loc.translate("due_day"),
          _dueDay.toString(),
          List.generate(28, (i) => (i + 1).toString()),
          (v) => setState(() => _dueDay = int.parse(v!)),
          icon: Icons.calendar_today,
        ),
        SizedBox(height: 16.h),
        _buildDropdownField(
          loc.translate("grace_period"),
          _gracePeriod.toString(),
          List.generate(15, (i) => i.toString()),
          (v) => setState(() => _gracePeriod = int.parse(v!)),
          icon: Icons.timer_outlined,
        ),
        SizedBox(height: 16.h),
        _buildDropdownField(
          loc.translate("late_fee_type"), 
          _lateFeeType, 
          ['none', 'fixed', 'percentage'],
          (v) => setState(() => _lateFeeType = v!),
          labels: [loc.translate("none"), loc.translate("fixed"), loc.translate("percentage")],
          icon: Icons.warning_amber_rounded,
        ),
        if (_lateFeeType != 'none') ...[
          SizedBox(height: 16.h),
          _buildInputField(
            _lateFeeType == 'fixed' ? loc.translate("late_fee_amount") : loc.translate("late_fee_percent"), 
            _lateFeeAmountController, 
            Icons.money_off, 
            keyboardType: TextInputType.number,
          ),
        ],
        SizedBox(height: 16.h),
        _buildCheckboxRow(loc.translate("auto_renew"), _autoRenew, (v) => setState(() => _autoRenew = v!)),
      ],
    );
  }

  // --- Step 4: Utilities ---
  Widget _buildStep4() {
    final loc = LocalizationService.instance;
    return _buildStepLayout(
      title: loc.translate("step_utilities"),
      children: [
        ..._utilities.keys.map((key) => _buildUtilityToggle(key)),
      ],
    );
  }

  Widget _buildUtilityToggle(String key) {
    final loc = LocalizationService.instance;
    bool isSelected = _utilities[key]!;
    return Column(
      children: [
        ThemeConstants.buildResponsiveGlassCard(
          context,
          onTap: () => setState(() => _utilities[key] = !isSelected),
          padding: EdgeInsets.all(12.w),
          child: Row(
            children: [
              Icon(isSelected ? Icons.check_box : Icons.check_box_outline_blank, color: isSelected ? ThemeConstants.primaryOrange : Colors.white24),
              SizedBox(width: 12.w),
              Expanded(child: Text(loc.translate(key), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
              if (isSelected) Text(loc.translate("included"), style: const TextStyle(color: ThemeConstants.successGreen, fontSize: 10)),
            ],
          ),
        ),
        if (isSelected) 
          Padding(
            padding: EdgeInsets.only(top: 8.h, bottom: 16.h, left: 32.w),
            child: _buildInputField(loc.translate("amount_per_month"), _utilityAmounts[key]!, Icons.add_card, keyboardType: TextInputType.number),
          )
        else 
          SizedBox(height: 12.h),
      ],
    );
  }

  // --- Step 5: Rules ---
  Widget _buildStep5() {
    final loc = LocalizationService.instance;
    final isSw = loc.isSwahili;
    final tenantLabel = isSw ? 'Wapangaji & Matumizi' : 'Tenant & Use';
    final maintenanceLabel = isSw ? 'Matengenezo & Ukaazi' : 'Maintenance & Access';
    final legalLabel = isSw ? 'Sheria & Dhamana' : 'Legal & Financial';

    final activeClauses = _leaseClauses.where((c) => c.category == _activeCategory).toList();

    return _buildStepLayout(
      title: loc.translate("step_rules"),
      children: [
        // Category chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              _buildCategoryTab('tenant', tenantLabel, Icons.person_outline),
              SizedBox(width: 8.w),
              _buildCategoryTab('maintenance', maintenanceLabel, Icons.build_outlined),
              SizedBox(width: 8.w),
              _buildCategoryTab('legal', legalLabel, Icons.gavel_outlined),
            ],
          ),
        ),
        SizedBox(height: 20.h),
        // Active category cards
        ...activeClauses.map((clause) => _buildClauseCard(clause)),
      ],
    );
  }

  Widget _buildCategoryTab(String category, String label, IconData icon) {
    final isActive = _activeCategory == category;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _activeCategory = category),
        borderRadius: BorderRadius.circular(30.r),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
          decoration: BoxDecoration(
            color: isActive 
                ? ThemeConstants.primaryOrange.withOpacity(0.2) 
                : Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(30.r),
            border: Border.all(
              color: isActive 
                  ? ThemeConstants.primaryOrange 
                  : Colors.white.withOpacity(0.1),
              width: isActive ? 1.5 : 1.0,
            ),
            boxShadow: isActive ? [
              BoxShadow(
                color: ThemeConstants.primaryOrange.withOpacity(0.2),
                blurRadius: 8,
                offset: const Offset(0, 2),
              )
            ] : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: isActive ? ThemeConstants.primaryOrange : Colors.white54, size: 16.w),
              SizedBox(width: 8.w),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? Colors.white : Colors.white60,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                  fontSize: 12.sp,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildClauseCard(_LeaseClause clause) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: EdgeInsets.only(bottom: 14.h),
      decoration: BoxDecoration(
        color: clause.isEnabled 
            ? Colors.white.withOpacity(0.06) 
            : Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: clause.isEnabled 
              ? ThemeConstants.primaryOrange.withOpacity(0.4) 
              : Colors.white.withOpacity(0.08),
          width: clause.isEnabled ? 1.2 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          InkWell(
            onTap: () {
              if (clause.isEnabled) {
                setState(() => clause.isExpanded = !clause.isExpanded);
              }
            },
            borderRadius: BorderRadius.circular(16.r),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
              child: Row(
                children: [
                  // Icon container
                  Container(
                    padding: EdgeInsets.all(8.w),
                    decoration: BoxDecoration(
                      color: clause.isEnabled 
                          ? ThemeConstants.primaryOrange.withOpacity(0.15) 
                          : Colors.white.withOpacity(0.05),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      clause.icon, 
                      color: clause.isEnabled ? ThemeConstants.primaryOrange : Colors.white30, 
                      size: 18.w
                    ),
                  ),
                  SizedBox(width: 12.w),
                  // Title text
                  Expanded(
                    child: Text(
                      clause.title,
                      style: TextStyle(
                        color: clause.isEnabled ? Colors.white : Colors.white30,
                        fontWeight: FontWeight.bold,
                        fontSize: 13.sp,
                        decoration: clause.isEnabled ? null : TextDecoration.lineThrough,
                      ),
                    ),
                  ),
                  // Toggle switch
                  Transform.scale(
                    scale: 0.8,
                    child: Switch(
                      value: clause.isEnabled,
                      onChanged: (val) {
                        setState(() {
                          clause.isEnabled = val;
                          if (!val) {
                            clause.isExpanded = false;
                          } else {
                            clause.isExpanded = true;
                          }
                          _syncLegacyObligations();
                        });
                      },
                      activeColor: ThemeConstants.primaryOrange,
                      activeTrackColor: ThemeConstants.primaryOrange.withOpacity(0.3),
                      inactiveThumbColor: Colors.white24,
                      inactiveTrackColor: Colors.white10,
                    ),
                  ),
                  if (clause.isEnabled) ...[
                    SizedBox(width: 4.w),
                    Icon(
                      clause.isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      color: Colors.white54,
                      size: 16.w,
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Expanded Content (Text Editor)
          if (clause.isEnabled && clause.isExpanded)
            Padding(
              padding: EdgeInsets.only(left: 14.w, right: 14.w, bottom: 16.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(color: Colors.white10, height: 1),
                  SizedBox(height: 12.h),
                  TextFormField(
                    initialValue: clause.text,
                    maxLines: null,
                    style: TextStyle(color: Colors.white, fontSize: 13.sp, height: 1.4),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.black.withOpacity(0.2),
                      contentPadding: EdgeInsets.all(12.w),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10.r),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10.r),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10.r),
                        borderSide: const BorderSide(color: ThemeConstants.primaryOrange, width: 1.2),
                      ),
                    ),
                    onChanged: (val) {
                      clause.text = val;
                      _syncLegacyObligations();
                    },
                  ),
                  SizedBox(height: 8.h),
                  // Reset button if changed
                  if (clause.text != clause.defaultText)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () {
                          setState(() {
                            clause.text = clause.defaultText;
                            _syncLegacyObligations();
                          });
                        },
                        icon: const Icon(Icons.undo, size: 12, color: ThemeConstants.primaryOrange),
                        label: Text(
                          LocalizationService.instance.isSwahili ? 'Rejesha Chaguomsingi' : 'Reset to Default',
                          style: TextStyle(color: ThemeConstants.primaryOrange, fontSize: 10.sp),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _syncLegacyObligations() {
    final tenantClauses = _leaseClauses.where((c) => c.isEnabled && (
      c.id == 'late_payment' || 
      c.id == 'maintenance' || 
      c.id == 'utilities' || 
      c.id == 'use_of_premises' || 
      c.id == 'damages_repairs' || 
      c.id == 'pets_policy' || 
      c.id == 'insurance'
    ));
    final landlordClauses = _leaseClauses.where((c) => c.isEnabled && (
      c.id == 'maintenance' || 
      c.id == 'inspection'
    ));
    final terminationClauses = _leaseClauses.where((c) => c.isEnabled && (
      c.id == 'late_payment' || 
      c.id == 'termination_conditions'
    ));

    _tenantObligationsController.text = tenantClauses.map((c) => c.text).join('\n\n');
    _landlordObligationsController.text = landlordClauses.map((c) => c.text).join('\n\n');
    _terminationPolicyController.text = terminationClauses.map((c) => c.text).join('\n\n');
  }

  // --- Step 6: Review ---
  Widget _buildStep6() {
    final rentalProvider = context.watch<RentalProvider>();
    final loc = LocalizationService.instance;
    final tenant = rentalProvider.tenants.firstWhere((t) => t['id'].toString() == _selectedTenantId, orElse: () => {'name': loc.translate('tenant_not_selected')});
    final property = rentalProvider.properties.firstWhere((p) => p['id'].toString() == _selectedPropertyId, orElse: () => {'name': loc.translate('property_not_selected')});

    return _buildStepLayout(
      title: loc.translate("review_lease"),
      children: [
        ThemeConstants.buildResponsiveGlassCardStatic(
          context,
          padding: EdgeInsets.all(16.w),
          child: Column(
            children: [
              _buildReviewSummary(loc.translate("tenant"), tenant['name'].toString()),
              _buildReviewSummary(loc.translate("house"), "${property['name']} - ${_selectedHouseData?['house_number'] ?? '-'}"),
              _buildReviewSummary(loc.translate("period"), "${DateFormat('dd/MM/yyyy').format(_startDate)} - ${DateFormat('dd/MM/yyyy').format(_endDate)}"),
              _buildReviewSummary(loc.translate("rent"), "${_rentController.text} TZS / ${loc.translate(_billingCycle)}"),
              _buildReviewSummary(loc.translate("security_deposit"), "${_depositAmountController.text} TZS"),
              const Divider(color: Colors.white10),
              _buildReviewSummary(loc.translate("advance_months"), "$_advanceMonths Months"),
              _buildReviewSummary(loc.translate("total_prepaid"), "${((double.tryParse(_rentController.text) ?? 0) * _advanceMonths).toStringAsFixed(2)} TZS"),
              _buildReviewSummary(loc.translate("paid_until"), DateFormat('dd/MM/yyyy').format(DateTime(_startDate.year, _startDate.month + _advanceMonths, _startDate.day))),
              const Divider(color: Colors.white10),
              SizedBox(height: 8.h),
              Text(loc.translate("wizard_complete_msg"), style: TextStyle(color: Colors.white54, fontSize: 11.sp)),
            ],
          ),
        ),
        SizedBox(height: 20.h),
        Text(loc.translate("signature_upload"), style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14.sp)),
        SizedBox(height: 12.h),
        ThemeConstants.buildResponsiveGlassCard(
          context,
          onTap: _showPickerOptions,
          padding: EdgeInsets.all(20.h),
          child: Center(
            child: _signatureFile != null
                ? Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8.r),
                        child: Image.file(_signatureFile!, height: 120.h, width: double.infinity, fit: BoxFit.cover),
                      ),
                      SizedBox(height: 8.h),
                      Text(loc.translate("change_image") ?? 'Change Image', style: TextStyle(color: ThemeConstants.primaryOrange, fontSize: 12.sp)),
                    ],
                  )
                : Column(
                    children: [
                      Icon(Icons.cloud_upload_outlined, color: ThemeConstants.primaryOrange, size: 32.w),
                      SizedBox(height: 8.h),
                      Text(loc.translate("upload_signed_copy"), style: TextStyle(color: Colors.white70, fontSize: 11.sp)),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickDocument(ImageSource source) async {
    try {
      final pickedFile = await _picker.pickImage(source: source, imageQuality: 80);
      if (pickedFile != null) {
        setState(() {
          _signatureFile = File(pickedFile.path);
        });
      }
    } catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, LocalizationService.instance.translateWith('error_picking_document', <Object?>[e]));
    }
  }

  void _showPickerOptions() {
    final loc = LocalizationService.instance;
    showModalBottomSheet(
      context: context,
      backgroundColor: ThemeConstants.bgMid,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20.r))),
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.white),
                title: Text(loc.translate('gallery') ?? 'Gallery', style: const TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickDocument(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera, color: Colors.white),
                title: Text(loc.translate('camera') ?? 'Camera', style: const TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickDocument(ImageSource.camera);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // --- Helpers ---

  Widget _buildStepLayout({required String title, required List<Widget> children}) {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 20.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: Colors.white, fontSize: 18.sp, fontWeight: FontWeight.bold)),
          SizedBox(height: 24.h),
          ...children,
          SizedBox(height: 100.h),
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
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: ThemeConstants.invInputDecoration(label).copyWith(
          prefixIcon: Icon(icon, color: Colors.white70, size: 18.w),
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
        ),
      ),
    );
  }

  Widget _buildMultiLineField(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        SizedBox(height: 8.h),
        ThemeConstants.buildResponsiveGlassCardStatic(
          context,
          child: TextFormField(
            controller: controller,
            maxLines: 4,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: ThemeConstants.invInputDecoration("").copyWith(
              contentPadding: EdgeInsets.all(12.w),
              hintText: label,
              hintStyle: const TextStyle(color: Colors.white54),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownField(String label, String? value, List<String> items, Function(String?) onChanged, {List<String>? labels, IconData? icon, bool enabled = true}) {
    // Ensure unique values to avoid Flutter assertion errors
    final uniqueItems = <String>[];
    final uniqueLabels = <String>[];
    final seen = <String>{};
    
    for (int i = 0; i < items.length; i++) {
      if (!seen.contains(items[i])) {
        seen.add(items[i]);
        uniqueItems.add(items[i]);
        if (labels != null && i < labels.length) {
          uniqueLabels.add(labels[i]);
        }
      }
    }

    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: ThemeConstants.buildResponsiveGlassCardStatic(
        context,
        child: DropdownButtonFormField<String>(
          value: uniqueItems.contains(value) ? value : null,
          items: List.generate(uniqueItems.length, (i) => DropdownMenuItem(
            value: uniqueItems[i],
            child: Text(uniqueLabels.isNotEmpty ? uniqueLabels[i] : uniqueItems[i], 
                 style: const TextStyle(fontSize: 13, color: Colors.white)),
          )),
          selectedItemBuilder: (BuildContext context) {
            return uniqueItems.map<Widget>((String item) {
              final index = uniqueItems.indexOf(item);
              final display = uniqueLabels.isNotEmpty ? uniqueLabels[index] : item;
              return Text(display, style: const TextStyle(color: Colors.white, fontSize: 13));
            }).toList();
          },
          hint: Text(label, style: const TextStyle(color: Colors.white60, fontSize: 13)),
          onChanged: enabled ? onChanged : null,
          isExpanded: true,
          dropdownColor: const Color(0xFF1A3B45),
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: ThemeConstants.invInputDecoration(label).copyWith(
            prefixIcon: icon != null ? Icon(icon, color: Colors.white70, size: 18.w) : null,
            labelText: label,
            labelStyle: const TextStyle(color: Colors.white70),
            hintStyle: const TextStyle(color: Colors.white30),
          ),
        ),
      ),
    );
  }

  Widget _buildDatePickerField(String label, DateTime date, Function(DateTime?) onSelected) {
    return ThemeConstants.buildResponsiveGlassCard(
      context,
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime.now().subtract(const Duration(days: 30)), // Allow slightly backdated
          lastDate: DateTime(2050),
        );
        if (picked != null) onSelected(picked);
      },
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10)),
            SizedBox(height: 4.h),
            Row(
              children: [
                Icon(Icons.calendar_today, color: ThemeConstants.primaryOrange, size: 14.w),
                SizedBox(width: 8.w),
                Text(DateFormat('dd/MM/yyyy').format(date), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: Row(
        children: [
          Icon(icon, color: ThemeConstants.primaryOrange, size: 14.w),
          SizedBox(width: 8.w),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const Spacer(),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildReviewSummary(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: Row(
        children: [
          Text("$label:", style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const Spacer(),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }

  Future<void> _handleHouseSelection(String? v, List<dynamic> houses) async {
    if (v == null) return;
    
    setState(() {
      _selectedHouseId = v;
      final house = houses.firstWhere((h) => h['id'].toString() == v);
      _selectedHouseData = house;
      
      final rent = (house['rent_amount'] ?? house['rent'] ?? '').toString();
      final deposit = (house['deposit_amount'] ?? house['deposit'] ?? rent).toString();
      
      _rentController.text = rent;
      if (deposit.isNotEmpty) {
        _depositAmountController.text = deposit;
        _depositPaidController.text = deposit;
      }
    });

    // Fetch full details to get the accurate deposit amount from house creation
    final fullDetails = await context.read<RentalProvider>().fetchHouseDetails(v);
    if (fullDetails != null && mounted) {
      setState(() {
        _selectedHouseData = fullDetails;
        final rent = (fullDetails['rent_amount'] ?? fullDetails['rent'] ?? _rentController.text).toString();
        final deposit = (fullDetails['deposit_amount'] ?? fullDetails['deposit'] ?? rent).toString();
        
        _rentController.text = rent;
        if (deposit.isNotEmpty) {
          _depositAmountController.text = deposit;
          _depositPaidController.text = deposit;
        }
      });
    }
  }

  Widget _buildCheckboxRow(String label, bool value, Function(bool?) onChanged) {
    return Row(
      children: [
        Checkbox(value: value, onChanged: onChanged, activeColor: ThemeConstants.primaryOrange),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }

  Future<void> _handleSave() async {
    final loc = LocalizationService.instance;
    if (_selectedTenantId == null || _selectedHouseId == null || _selectedPropertyId == null) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, loc.translate("please_select_tenant_house"));
      return;
    }

    setState(() => _isSaving = true);
    
    // Prepare utilities
    final List<Map<String, dynamic>> utilityCharges = [];
    _utilities.forEach((key, isSelected) {
      if (isSelected) {
        final amountText = _utilityAmounts[key]!.text;
        utilityCharges.add({
          'name': key,
          'amount': amountText.isNotEmpty ? double.parse(amountText) : 0.0,
          'billing_type': 'fixed',
        });
      }
    });

    // Prepare rules
    final Map<String, String> rules = {
      'landlord_obligations': _landlordObligationsController.text,
      'tenant_obligations': _tenantObligationsController.text,
      'termination_policy': _terminationPolicyController.text,
      // Add individual clauses
      ...Map.fromEntries(_leaseClauses.where((c) => c.isEnabled).map((c) => MapEntry(c.id, c.text))),
    };

    final payload = {
      'tenant_id': _selectedTenantId,
      'property_id': _selectedPropertyId,
      'house_id': _selectedHouseId,
      'start_date': DateFormat('yyyy-MM-dd').format(_startDate),
      'end_date': DateFormat('yyyy-MM-dd').format(_endDate),
      'rent_amount': double.parse(_rentController.text),
      'deposit_amount': _depositAmountController.text.isNotEmpty ? double.parse(_depositAmountController.text) : 0.0,
      'deposit_paid': _depositPaidController.text.isNotEmpty ? double.parse(_depositPaidController.text) : 0.0,
      'rent_cycle': _billingCycle,
      'due_day': _dueDay,
      'grace_period_days': _gracePeriod,
      'late_fee_type': _lateFeeType,
      'late_fee_amount': _lateFeeAmountController.text.isNotEmpty ? double.parse(_lateFeeAmountController.text) : 0.0,
      'utility_charges': utilityCharges,
      'rules': rules,
      'auto_renew': _autoRenew,
      'advance_months': _advanceMonths,
      'prepaid_amount': (double.tryParse(_rentController.text) ?? 0) * _advanceMonths,
      'paid_until': DateFormat('yyyy-MM-dd').format(DateTime(_startDate.year, _startDate.month + _advanceMonths, _startDate.day)),
    };

    final agreementId = await context.read<RentalProvider>().createAgreement(payload, document: _signatureFile);
    
    if (mounted) {
      setState(() => _isSaving = false);
      if (agreementId != null) {
        if (agreementId == 'success') {
          ThemeConstants.showSuccessSnackBar(context, loc.translate("lease_created_success"));
          Navigator.pop(context);
          return;
        }

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: ThemeConstants.bgMid,
            title: Text(LocalizationService.instance.translate('agreement_created'), style: const TextStyle(color: Colors.white)),
            content: Text(LocalizationService.instance.translate('do_you_want_to_record_the'), style: const TextStyle(color: Colors.white70)),
            actions: [
              TextButton(
                onPressed: () {
                  final nav = Navigator.of(context);
                  nav.pop(); // close dialog
                  nav.pop(); // close wizard
                },
                child: Text(LocalizationService.instance.translate('not_now'), style: const TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                onPressed: () {
                  final nav = Navigator.of(context);
                  nav.pop(); // close dialog
                  nav.pop(); // close wizard
                  nav.push(MaterialPageRoute(
                    builder: (_) => RecordPaymentScreen(
                      preSelectedTenant: {'id': _selectedTenantId},
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
        ThemeConstants.showErrorSnackBar(context, loc.translate("lease_creation_failed"));
      }
    }
  }
}

class _LeaseClause {
  final String id;
  final String title;
  final IconData icon;
  final String defaultText;
  final String category; // 'tenant', 'maintenance', 'legal'
  String text;
  bool isEnabled;
  bool isExpanded;

  _LeaseClause({
    required this.id,
    required this.title,
    required this.icon,
    required this.defaultText,
    required this.category,
    required this.text,
    this.isEnabled = true,
    this.isExpanded = false,
  });
}

const Map<String, Map<String, String>> _clauseDefaults = {
  'en': {
    'security_deposit_title': '1. Security Deposit',
    'security_deposit_text': 'Tenant shall pay a refundable security deposit before moving in. The deposit will be used to cover damages, unpaid rent, or cleaning costs beyond normal wear and tear. Refund will be processed within 14–30 days after lease termination.',
    
    'late_payment_title': '2. Late Payment Policy',
    'late_payment_text': 'Rent not paid within the agreed due date will incur a late fee. Continuous delay in payment may lead to termination of the agreement.',
    
    'maintenance_title': '3. Maintenance Responsibilities',
    'maintenance_text': 'Tenant is responsible for minor repairs and cleanliness inside the premises. Landlord is responsible for major structural repairs, plumbing systems, and electrical faults not caused by tenant negligence.',
    
    'utilities_title': '4. Utilities',
    'utilities_text': 'Tenant shall be responsible for payment of utilities including water, electricity, internet, and waste disposal unless otherwise stated in the agreement.',
    
    'inspection_title': '5. Property Inspection',
    'inspection_text': 'Landlord reserves the right to inspect the property after providing reasonable notice (e.g. 24–48 hours), except in emergency situations.',
    
    'subleasing_title': '6. Subleasing Policy',
    'subleasing_text': 'Tenant shall not sublease, assign, or transfer the property without prior written consent from the landlord.',
    
    'use_of_premises_title': '7. Use of Premises',
    'use_of_premises_text': 'The property shall be used strictly for residential purposes only and not for illegal or unauthorized activities.',
    
    'damages_repairs_title': '8. Damages & Repairs',
    'damages_repairs_text': 'Any damage caused by the tenant or their visitors shall be repaired at the tenant’s expense.',
    
    'pets_policy_title': '9. Pets Policy (optional)',
    'pets_policy_text': 'Pets are only allowed with prior approval from the landlord. Any damage caused by pets remains the tenant’s responsibility.',
    
    'insurance_title': '10. Insurance',
    'insurance_text': 'Tenant is encouraged to obtain personal contents insurance for protection against theft, fire, or damage.',
    
    'termination_conditions_title': '11. Termination Conditions',
    'termination_conditions_text': 'Either party may terminate the agreement with 30 days written notice. Immediate termination may occur in case of serious breach of contract.',
    
    'governing_law_title': '12. Governing Law',
    'governing_law_text': 'This agreement shall be governed by the applicable laws of the jurisdiction where the property is located.',
  },
  'sw': {
    'security_deposit_title': '1. Dhamana ya Usalama (Security Deposit)',
    'security_deposit_text': 'Mpangaji atalipa dhamana ya usalama inayorejeshwa kabla ya kuhamia. Dhamana itatumika kulipia uharibifu, kodi isiyolipwa, au gharama za usafi zinazozidi uchakavu wa kawaida. Urejeshaji utafanyika ndani ya siku 14–30 baada ya mkataba kuisha.',
    
    'late_payment_title': '2. Sera ya Malipo ya Chelewe',
    'late_payment_text': 'Kodi isiyolipwa ndani ya tarehe iliyokubaliwa itatozwa faini ya kuchelewa. Kuchelewa kwa malipo mara kwa mara kunaweza kusababisha kusitishwa kwa mkataba.',
    
    'maintenance_title': '3. Wajibu wa Matengenezo',
    'maintenance_text': 'Mpangaji anajibika kwa matengenezo madogo na usafi ndani ya eneo lake. Mwenye nyumba anajibika kwa matengenezo makubwa ya miundo, mifumo ya mabomba, na hitilafu za umeme ambazo hazijasababishwa na uzembe wa mpangaji.',
    
    'utilities_title': '4. Huduma za Pamoja (Bili)',
    'utilities_text': 'Mpangaji atawajibika kulipia huduma ikiwa ni pamoja na maji, umeme, mtandao, na uzoaji wa taka isipokuwa kama imeelezwa vinginevyo kwenye mkataba.',
    
    'inspection_title': '5. Ukaguzi wa Mali',
    'inspection_text': 'Mwenye nyumba ana haki ya kukagua mali baada ya kutoa notisi ya kuridhisha (mfano siku 1-2 au saa 24-48), isipokuwa katika dharura kubwa.',
    
    'subleasing_title': '6. Sera ya Kupangisha Mtu Mwingine',
    'subleasing_text': 'Mpangaji hataruhusiwa kupangisha mtu mwingine, kuhamisha au kupeana eneo bila idhini ya maandishi kutoka kwa mwenye nyumba.',
    
    'use_of_premises_title': '7. Matumizi ya Eneo',
    'use_of_premises_text': 'Mali hii itatumika kwa madhumuni ya makazi tu na si kwa shughuli zisizoidhinishwa au haramu.',
    
    'damages_repairs_title': '8. Uharibifu & Matengenezo',
    'damages_repairs_text': 'Uharibifu wowote uliosababishwa na mpangaji au wageni wake utarekebishwa kwa gharama ya mpangaji.',
    
    'pets_policy_title': '9. Sera ya Wanyama (Si lazima)',
    'pets_policy_text': 'Wanyama wa kufugwa wanaruhusiwa tu kwa idhini ya awali kutoka kwa mwenye nyumba. Uharibifu wowote unaosababishwa na wanyama unabaki kuwa wajibu wa mpangaji.',
    
    'insurance_title': '10. Bima ya Vyombo',
    'insurance_text': 'Mpangaji anashauriwa kukata bima ya mali zake binafsi kwa ajili ya ulinzi dhidi ya wizi, moto, au uharibifu wowote.',
    
    'termination_conditions_title': '11. Masharti ya Kusitisha',
    'termination_conditions_text': 'Upande wowote unaweza kusitisha mkataba huu kwa kutoa notisi ya maandishi ya siku 30. Kusitishwa kwa haraka kunaweza kutokea ikiwa kuna ukiukwaji mkubwa wa mkataba.',
    
    'governing_law_title': '12. Sheria Inayoongoza',
    'governing_law_text': 'Mkataba huu utaongozwa na sheria zinazohusika za eneo ambalo mali hiyo ipo.',
  }
};
