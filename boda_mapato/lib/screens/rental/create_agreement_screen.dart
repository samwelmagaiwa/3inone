import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import '../../constants/theme_constants.dart';
import '../../providers/rental_provider.dart';
import '../../services/localization_service.dart';
import '../../utils/rental_flow_validator.dart';

class CreateAgreementScreen extends StatefulWidget {
  const CreateAgreementScreen({super.key});

  @override
  State<CreateAgreementScreen> createState() => _CreateAgreementScreenState();
}

class _CreateAgreementScreenState extends State<CreateAgreementScreen> {
  int _currentStep = 0;
  bool _attemptedSubmit = false;
  bool _isSaving = false;

  // Step 1 - Tenant & Property
  String? _selectedTenant;
  String? _selectedHouse;
  List tenants = [];
  List houses = [];

  // Step 2 - Terms
  final _rentCtrl = TextEditingController();
  final _depositCtrl = TextEditingController(text: "0");
  final _noticePeriodCtrl = TextEditingController(text: "30");
  final _penaltyCtrl = TextEditingController(text: "0");
  final _notesCtrl = TextEditingController();
  bool _autoRenew = false;
  String _cycle = 'monthly';
  String _status = 'active';
  DateTime? _startDate;
  DateTime? _endDate;

  // Step 3 - Documents
  bool _hasSignedContract = false;
  bool _hasIdCopy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<RentalProvider>();
      await provider.fetchTenants();
      await provider.fetchProperties();
      if (!context.mounted) return;

      // Stage 1: Must have at least one tenant onboarded
      if (!RentalFlowValidator.hasTenants(provider)) {
        await RentalFlowValidator.validateStep(
          context: context,
          fetchData: (_) async {},
          condition: RentalFlowValidator.hasTenants,
          title: LocalizationService.instance.translate('add_a_tenant_first'),
          message: LocalizationService.instance.translate('you_have_no_tenants_yet_add'),
          actionLabel: LocalizationService.instance.translate('add_tenant'),
          actionRoute: '/rental/onboard-tenant',
        );
        return;
      }

      // Stage 2: Must have at least one vacant house
      if (!RentalFlowValidator.hasVacantHouses(provider)) {
        await RentalFlowValidator.validateStep(
          context: context,
          fetchData: (_) async {},
          condition: RentalFlowValidator.hasVacantHouses,
          title: LocalizationService.instance.translate('no_vacant_houses'),
          message: LocalizationService.instance.translate('all_houses_are_occupied_add_a'),
          actionLabel: LocalizationService.instance.translate('view_properties'),
          actionRoute: '/rental/properties',
        );
        return;
      }
    });
  }

  @override
  void dispose() {
    _rentCtrl.dispose();
    _depositCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ThemeConstants.buildResponsiveScaffold(
      context,
      title: LocalizationService.instance.translate('new_agreement'),
      body: Column(
        children: [
          _buildStepper(),
          Expanded(
            child: IndexedStack(
              index: _currentStep,
              children: [
                _buildTenantStep(),
                _buildTermsStep(),
                _buildReviewStep(),
              ],
            ),
          ),
          _buildBottomNav(),
        ],
      ),
    );
  }

  Widget _buildStepper() {
    return Container(
      margin: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 0),
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16.r)),
      child: Row(children: [
        _step(1, LocalizationService.instance.translate('agreement_step_tenant'), _currentStep >= 0),
        _stepLine(_currentStep >= 1),
        _step(2, LocalizationService.instance.translate('payment_terms'), _currentStep >= 1),
        _stepLine(_currentStep >= 2),
        _step(3, LocalizationService.instance.translate('review'), _currentStep >= 2),
      ]),
    );
  }

  Widget _step(int n, String l, bool active) => Expanded(
          child: Column(children: [
        Container(
            width: 28.w,
            height: 28.w,
            decoration: BoxDecoration(
                color: active ? ThemeConstants.primaryOrange : Colors.white24,
                shape: BoxShape.circle),
            child: Center(
                child: Icon(Icons.check,
                    color: Colors.white,
                    size: 16.sp,
                    weight: active ? 700 : 300))),
        SizedBox(height: 4.h),
        Text(l,
            style: TextStyle(
                color: active ? Colors.white : Colors.white38,
                fontSize: 10.sp)),
      ]));

  Widget _stepLine(bool active) => Container(
      width: 30.w,
      height: 2.h,
      decoration: BoxDecoration(
          color: active ? ThemeConstants.primaryOrange : Colors.white12));

  Widget _buildTenantStep() {
    final provider = context.watch<RentalProvider>();
    tenants = provider.tenants;
    houses = provider.properties
        .expand((p) => p['houses'] as List? ?? [])
        .toList();

    return SingleChildScrollView(
      padding: EdgeInsets.all(16.w),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionTitle(LocalizationService.instance.translate('select_tenant_property')),
        SizedBox(height: 16.h),
        Text(LocalizationService.instance.translate('agreement_step_tenant'), style: TextStyle(color: Colors.white70, fontSize: 12.sp)),
        SizedBox(height: 8.h),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12.w),
          decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: Colors.white12)),
          child: DropdownButton<String>(
            value: tenants.any((t) => t['id'].toString() == _selectedTenant) ? _selectedTenant : null,
            isExpanded: true,
            dropdownColor: ThemeConstants.primaryBlue,
            underline: const SizedBox(),
            style: TextStyle(color: Colors.white, fontSize: 14.sp),
            hint: Text(LocalizationService.instance.translate('select_tenant'), style: TextStyle(color: Colors.white38)),
            items: tenants
                .map<DropdownMenuItem<String>>((t) => DropdownMenuItem<String>(
                    value: t['id'].toString(), child: Text(t['name'] ?? '')))
                .toList(),
            onChanged: (v) => setState(() => _selectedTenant = v),
          ),
        ),
        if (_attemptedSubmit && _selectedTenant == null)
          Padding(
            padding: EdgeInsets.only(top: 8.h, left: 4.w),
            child: Text(LocalizationService.instance.translate('field_required'), style: TextStyle(color: Colors.redAccent, fontSize: 12.sp)),
          ),
        SizedBox(height: 16.h),
        Text(LocalizationService.instance.translate('house_label'),
            style: TextStyle(color: Colors.white70, fontSize: 12.sp)),
        SizedBox(height: 8.h),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12.w),
          decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: Colors.white12)),
          child: DropdownButton<String>(
            value: houses.any((h) => h['id'].toString() == _selectedHouse && h['status'] == 'vacant') ? _selectedHouse : null,
            isExpanded: true,
            dropdownColor: ThemeConstants.primaryBlue,
            underline: const SizedBox(),
            style: TextStyle(color: Colors.white, fontSize: 14.sp),
            hint:
                Text(LocalizationService.instance.translate('select_house_2'), style: TextStyle(color: Colors.white38)),
            items: houses
                .where((h) => h['status'] == 'vacant')
                .map<DropdownMenuItem<String>>((h) => DropdownMenuItem<String>(
                    value: h['id'].toString(),
                    child: Row(children: [
                      Icon(Icons.door_front_door,
                          size: 16.sp, color: Colors.white54),
                      SizedBox(width: 8.w),
                      Text(
                          "${h['house_number']} - TSh ${_fmt(h['rent_amount'])}"),
                    ])))
                .toList(),
            onChanged: (v) => setState(() => _selectedHouse = v),
          ),
        ),
        if (_attemptedSubmit && _selectedHouse == null)
          Padding(
            padding: EdgeInsets.only(top: 8.h, left: 4.w),
            child: Text(LocalizationService.instance.translate('field_required'), style: TextStyle(color: Colors.redAccent, fontSize: 12.sp)),
          ),
      ]),
    );
  }

  Widget _buildTermsStep() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16.w),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionTitle(LocalizationService.instance.translate('lease_terms')),
        SizedBox(height: 16.h),
        Row(children: [
          Expanded(
              child: _field(
                  _rentCtrl, LocalizationService.instance.translate('monthly_rent_tsh'), Icons.monetization_on, onChanged: (v) => setState(() {}),
                  errorText: _attemptedSubmit && _rentCtrl.text.isEmpty
                      ? LocalizationService.instance.translate('field_required')
                      : (_attemptedSubmit && double.tryParse(_rentCtrl.text) == null
                          ? LocalizationService.instance.translate('invalid_amount')
                          : null))),
          SizedBox(width: 12.w),
          Expanded(
              child: _field(_depositCtrl, "${LocalizationService.instance.translate('deposit_amount')} (TSh)", Icons.savings,
                  onChanged: (v) => setState(() {}),
                  errorText: (double.tryParse(_depositCtrl.text) ?? 0) > (double.tryParse(_rentCtrl.text) ?? 0)
                      ? LocalizationService.instance.translate('deposit_exceeds_rent')
                      : null)),
        ]),
        SizedBox(height: 16.h),
        Text(LocalizationService.instance.translate('payment_period_2'),
            style: TextStyle(color: Colors.white70, fontSize: 12.sp)),
        SizedBox(height: 8.h),
        _cycleChip(LocalizationService.instance.translate('cycle_monthly'), "monthly"),
        SizedBox(width: 8.w),
        _cycleChip(LocalizationService.instance.translate('cycle_quarterly'), "quarterly"),
        SizedBox(width: 8.w),
        _cycleChip(LocalizationService.instance.translate('cycle_yearly'), "yearly"),
        SizedBox(height: 16.h),
        Text(LocalizationService.instance.translate('agreement_status'),
            style: TextStyle(color: Colors.white70, fontSize: 12.sp)),
        SizedBox(height: 8.h),
        _dropdown(LocalizationService.instance.translate('status'), _status, ["active", "notice", "terminated", "defaulter"], (v) => setState(() => _status = v)),
        SizedBox(height: 16.h),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: _dateField(
                  LocalizationService.instance.translate('start_date'), _startDate, () => _pickDate(true),
                  isError: _attemptedSubmit && _startDate == null)),
          SizedBox(width: 12.w),
          Expanded(
              child: _dateField(
                  LocalizationService.instance.translate('agreement_end_date'), _endDate, () => _pickDate(false),
                  isError: _attemptedSubmit && (_endDate == null || (_startDate != null && _endDate!.isBefore(_startDate!))))),
        ]),
        SizedBox(height: 24.h),
        _sectionTitle(LocalizationService.instance.translate('policy_extra_details')),
        SizedBox(height: 16.h),
        Row(children: [
          Expanded(
            child: _field(_noticePeriodCtrl, LocalizationService.instance.translate('notice_days'), Icons.timer),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: _field(_penaltyCtrl, LocalizationService.instance.translate('penalty_day_tsh'), Icons.gavel),
          ),
        ]),
        SizedBox(height: 16.h),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(LocalizationService.instance.translate('auto_renew_agreement'),
              style: TextStyle(color: Colors.white70, fontSize: 13.sp)),
          Switch(
            value: _autoRenew,
            onChanged: (v) => setState(() => _autoRenew = v),
            activeThumbColor: ThemeConstants.primaryOrange,
          ),
        ]),
        SizedBox(height: 16.h),
        _field(_notesCtrl, LocalizationService.instance.translate('extra_details'), Icons.note_alt),
        SizedBox(height: 24.h),
        _sectionTitle(LocalizationService.instance.translate('documents')),
        SizedBox(height: 12.h),
        _checkItem(LocalizationService.instance.translate('signed_agreement'), _hasSignedContract,
            (v) => setState(() => _hasSignedContract = v)),
        SizedBox(height: 8.h),
        _checkItem(LocalizationService.instance.translate('id_copy'), _hasIdCopy,
            (v) => setState(() => _hasIdCopy = v)),
      ]),
    );
  }

  Widget _buildReviewStep() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16.w),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionTitle(LocalizationService.instance.translate('review_agreement')),
        SizedBox(height: 20.h),
        Container(
          padding: EdgeInsets.all(20.w),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20.r),
            border: Border.all(color: Colors.white.withOpacity(0.15)),
          ),
          child: Column(children: [
            Icon(Icons.description,
                color: ThemeConstants.primaryOrange, size: 48.sp),
            SizedBox(height: 12.h),
            Text(LocalizationService.instance.translate('lease_agreement_2').toUpperCase(),
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18.sp,
                    fontWeight: FontWeight.bold)),
            SizedBox(height: 4.h),
            Text(
                LocalizationService.instance.translateWith('house_2', <Object?>[houses.firstWhere((h) => h['id'] == _selectedHouse, orElse: () => {
                      'house_number': ''
                    })['house_number']]),
                style: const TextStyle(color: Colors.white54)),
            Divider(color: Colors.white12, height: 24.h),
            _rw(
                LocalizationService.instance.translate('agreement_step_tenant'),
                tenants.firstWhere((t) => t['id'] == _selectedTenant,
                        orElse: () => {'name': ''})['name'] ??
                    ''),
            _rw(LocalizationService.instance.translate('rent_label'), "TSh ${_fmt(double.tryParse(_rentCtrl.text) ?? 0)}"),
            _rw(LocalizationService.instance.translate('deposit'),
                "TSh ${_fmt(double.tryParse(_depositCtrl.text) ?? 0)}"),
            _rw(
                LocalizationService.instance.translate('period'),
                _cycle == 'monthly'
                    ? 'Mwezi'
                    : _cycle == 'quarterly'
                        ? LocalizationService.instance.translate('cycle_quarterly')
                        : LocalizationService.instance.translate('cycle_yearly')),
            _rw(LocalizationService.instance.translate('from'), _startDate?.toString().split(' ')[0] ?? '-'),
            _rw(LocalizationService.instance.translate('to'), _endDate?.toString().split(' ')[0] ?? '-'),
            SizedBox(height: 16.h),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving
                    ? null
                    : () async {
                        setState(() => _isSaving = true);
                        try {
                          final data = {
                            'tenant_id': _selectedTenant,
                            'house_id': _selectedHouse,
                            'rent_amount': double.tryParse(_rentCtrl.text) ?? 0,
                            'deposit_amount':
                                double.tryParse(_depositCtrl.text) ?? 0,
                            'billing_cycle': _cycle,
                            'start_date':
                                _startDate?.toIso8601String().split('T')[0],
                            'end_date':
                                _endDate?.toIso8601String().split('T')[0],
                            'notice_period_days':
                                int.tryParse(_noticePeriodCtrl.text) ?? 30,
                            'penalty_per_day':
                                double.tryParse(_penaltyCtrl.text) ?? 0,
                            'auto_renew': _autoRenew ? 1 : 0,
                            'notes': _notesCtrl.text,
                            'status': _status,
                          };

                          final success = await context
                              .read<RentalProvider>()
                              .createAgreement(data);

                          if (success != null && mounted) {
                            ThemeConstants.showSuccessSnackBar(
                                context, "${LocalizationService.instance.translate('agreement_created')}!");
                            Navigator.pop(context);
                          }
                        } finally {
                          if (mounted) setState(() => _isSaving = false);
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: ThemeConstants.successGreen,
                  padding: EdgeInsets.symmetric(vertical: 16.h),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.r)),
                ),
                child: _isSaving
                    ? SizedBox(
                        height: 20.w,
                        width: 20.w,
                        child: const CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : Text(LocalizationService.instance.translate('save_agreement_2'),
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _rw(String l, String v) => Padding(
        padding: EdgeInsets.only(bottom: 8.h),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(l, style: TextStyle(color: Colors.white54, fontSize: 14.sp)),
          Text(v,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w500)),
        ]),
      );

  Widget _sectionTitle(String t) => Text(t,
      style: TextStyle(
          color: Colors.white, fontSize: 16.sp, fontWeight: FontWeight.bold));

  Widget _field(TextEditingController c, String l, IconData ic, {String? errorText, void Function(String)? onChanged}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(l, style: TextStyle(color: errorText != null ? Colors.redAccent : Colors.white70, fontSize: 12.sp)),
      SizedBox(height: 6.h),
      TextField(
        controller: c,
        onChanged: onChanged,
        keyboardType: TextInputType.number,
        style: TextStyle(color: Colors.white, fontSize: 14.sp),
        decoration: InputDecoration(
          prefixIcon: Icon(ic, color: Colors.white38, size: 20.sp),
          filled: true,
          errorText: errorText,
          fillColor: Colors.white.withOpacity(0.05),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.r),
              borderSide: BorderSide(color: errorText != null ? Colors.redAccent : Colors.white12)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.r),
              borderSide: BorderSide(color: errorText != null ? Colors.redAccent : Colors.white12)),
        ),
      ),
    ]);
  }

  Widget _cycleChip(String l, String v) {
    final s = _cycle == v;
    return GestureDetector(
      onTap: () => setState(() => _cycle = v),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
        decoration: BoxDecoration(
            color: s
                ? ThemeConstants.primaryOrange
                : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(
                color: s ? ThemeConstants.primaryOrange : Colors.white12)),
        child: Text(l, style: TextStyle(color: Colors.white, fontSize: 13.sp)),
      ),
    );
  }

  Widget _dateField(String l, DateTime? d, VoidCallback onTap, {bool isError = false}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(l, style: TextStyle(color: isError ? Colors.redAccent : Colors.white70, fontSize: 12.sp)),
      SizedBox(height: 6.h),
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.all(12.w),
          decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: isError ? Colors.redAccent : Colors.white12)),
          child: Row(children: [
            Icon(Icons.calendar_today, color: Colors.white38, size: 16.sp),
            SizedBox(width: 8.w),
            Text(d?.toString().split(' ')[0] ?? LocalizationService.instance.translate('select_a_date'),
                style: TextStyle(
                    color: d != null ? Colors.white : Colors.white38,
                    fontSize: 14.sp)),
          ]),
        ),
      ),
    ]);
  }

  Widget _dropdown(String label, String value, List<String> items, Function(String) onChange) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w),
      decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: Colors.white12)),
      child: DropdownButton<String>(
        value: items.contains(value) ? value : items.first,
        isExpanded: true,
        dropdownColor: ThemeConstants.primaryBlue,
        underline: const SizedBox(),
        style: TextStyle(color: Colors.white, fontSize: 14.sp),
        items: items
            .map((i) => DropdownMenuItem(
                value: i, child: Text(i.toUpperCase(), style: TextStyle(fontSize: 12.sp))))
            .toList(),
        onChanged: (v) => onChange(v ?? items.first),
      ),
    );
  }

  Widget _checkItem(String l, bool v, Function(bool) onChange) {
    return GestureDetector(
      onTap: () => onChange(!v),
      child: Container(
        padding: EdgeInsets.all(12.w),
        decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12.r)),
        child: Row(children: [
          Icon(v ? Icons.check_box : Icons.check_box_outline_blank,
              color: v ? ThemeConstants.successGreen : Colors.white38,
              size: 20.sp),
          SizedBox(width: 12.w),
          Text(l, style: TextStyle(color: Colors.white, fontSize: 14.sp)),
        ]),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: const BoxDecoration(
          color: ThemeConstants.primaryBlue,
          border: Border(top: BorderSide(color: Colors.white12))),
      child: Row(children: [
        if (_currentStep > 0)
          Expanded(
            child: OutlinedButton(
              onPressed: () => setState(() => _currentStep--),
              style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white24),
                  padding: EdgeInsets.symmetric(vertical: 14.h)),
              child: Text(LocalizationService.instance.translate('previous'), style: TextStyle(color: Colors.white)),
            ),
          ),
        if (_currentStep > 0) SizedBox(width: 12.w),
        Expanded(
          child: ElevatedButton(
            onPressed: () {
              setState(() => _attemptedSubmit = true);
              if (_currentStep == 0) {
                if (_selectedTenant == null || _selectedHouse == null) return;
              } else if (_currentStep == 1) {
                if (_rentCtrl.text.isEmpty) return;
                final double r = double.tryParse(_rentCtrl.text) ?? 0;
                final double d = double.tryParse(_depositCtrl.text) ?? 0;
                if (d > r) return;
                if (_startDate == null || _endDate == null || _endDate!.isBefore(_startDate!)) return;
              }
              if (_currentStep < 2) {
                setState(() {
                  _currentStep++;
                  _attemptedSubmit = false;
                });
              } else {
                ThemeConstants.showSuccessSnackBar(context, "${LocalizationService.instance.translate('agreement_created')}!");
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: ThemeConstants.primaryOrange,
              padding: EdgeInsets.symmetric(vertical: 14.h),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r)),
            ),
            child: Text(_currentStep == 2 ? LocalizationService.instance.translate('finish') : LocalizationService.instance.translate('next'),
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    );
  }

  Future<void> _pickDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      builder: (c, child) => Theme(
          data: Theme.of(c)
              .copyWith(dialogTheme: const DialogThemeData(backgroundColor: ThemeConstants.primaryBlue)),
          child: child!),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  String _fmt(num v) {
    if (v >= 1000000) return "${(v / 1000000).toStringAsFixed(0)}M";
    if (v >= 1000) return "${(v / 1000).toStringAsFixed(0)}K";
    return v.toInt().toString();
  }
}
