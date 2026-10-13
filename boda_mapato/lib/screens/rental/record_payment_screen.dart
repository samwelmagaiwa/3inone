import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import '../../constants/theme_constants.dart';
import '../../providers/rental_provider.dart';
import '../../utils/rental_flow_validator.dart';
import 'lease_agreement_wizard_screen.dart';
import 'receipt_view_screen.dart';
import '../../services/localization_service.dart';

// ─────────────────────────────────────────────
// Color palette
// ─────────────────────────────────────────────
const _kGradientTop    = Color(0xFF04121A);
const _kGradientMid    = Color(0xFF092D3A);
const _kGradientBottom = Color(0xFF0D485A);
const _kOrange         = Color(0xFFF97316);
const _kGreen          = Color(0xFF10B981);
const _kAmber          = Color(0xFFF59E0B);
const _kRed            = Color(0xFFEF4444);
const _kCyan           = Color(0xFF1BA3C7);

class RecordPaymentScreen extends StatefulWidget {
  const RecordPaymentScreen({super.key, this.preSelectedTenant});
  final Map<String, dynamic>? preSelectedTenant;

  @override
  State<RecordPaymentScreen> createState() => _RecordPaymentScreenState();
}

class _RecordPaymentScreenState extends State<RecordPaymentScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _selectedTenant;
  Map<String, dynamic>? _selectedBill;
  final _amountController = TextEditingController();
  String _selectedPaymentMethod = 'cash';
  final _referenceController = TextEditingController();
  bool _isProcessing = false;

  late final AnimationController _animCtrl;
  late final Animation<double>    _fadeAnim;
  late final Animation<Offset>    _slideAnim;

  final List<Map<String, dynamic>> _paymentMethods = [
    {'value': 'cash',          'label': LocalizationService.instance.translate('method_cash'),          'icon': Icons.payments_outlined,        'color': _kGreen},
    {'value': 'bank_transfer', 'label': LocalizationService.instance.translate('method_bank'), 'icon': Icons.account_balance_outlined, 'color': _kCyan},
    {'value': 'mpesa',         'label': 'M-Pesa',        'icon': Icons.phone_android_outlined,   'color': _kGreen},
    {'value': 'airtel_money',  'label': 'Airtel Money',  'icon': Icons.phone_iphone_outlined,    'color': _kRed},
    {'value': 'tigo_pesa',     'label': 'Tigo Pesa',     'icon': Icons.smartphone_outlined,      'color': _kCyan},
  ];

  @override
  void initState() {
    super.initState();

    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim  = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
            begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));

    if (widget.preSelectedTenant != null) {
      _selectedTenant = widget.preSelectedTenant;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RentalProvider>().fetchTenants();

      RentalFlowValidator.validateStep(
        context: context,
        fetchData: (p) => p.fetchBills(),
        condition: (p) => p.bills.any((b) =>
            b['status'] == 'unpaid' ||
            b['status'] == 'partial' ||
            b['status'] == 'overdue'),
        title: LocalizationService.instance.translate('no_unpaid_bills'),
        message:
            LocalizationService.instance.translate('there_are_no_active_unpaid_bills'),
        actionLabel: LocalizationService.instance.translate('create_lease'),
        onAction: () => Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (_) => const LeaseAgreementWizardScreen())),
      );

      _animCtrl.forward();
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  String _formatCurrency(double value) {
    if (value >= 1000000) return "${(value / 1000000).toStringAsFixed(1)}M";
    if (value >= 1000) return "${(value / 1000).toStringAsFixed(0)}K";
    return value.toStringAsFixed(0);
  }

  String _formatFullCurrency(double value) {
    final s = value.toStringAsFixed(0);
    return s.replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  }

  String _formatStatus(String status) {
    return switch (status) {
      'overdue' => LocalizationService.instance.translate('overdue'),
      'partial' => LocalizationService.instance.translate('bill_partial'),
      'paid'    => LocalizationService.instance.translate('bill_paid'),
      _         => LocalizationService.instance.translate('bill_unpaid')
    };
  }

  int get _currentStep {
    if (_selectedBill != null) return 3;
    if (_selectedTenant != null) return 2;
    return 1;
  }

  // ── Build ───────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kGradientTop,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // ── Animated background
          const _AnimatedBackground(),

          // ── Main content
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // ── App bar
              SliverAppBar(
                expandedHeight: 200.h,
                pinned: true,
                backgroundColor: _kGradientTop.withOpacity(0.85),
                elevation: 0,
                leading: IconButton(
                  icon: Container(
                    padding: EdgeInsets.all(6.w),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10.r),
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                    ),
                    child: Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white, size: 14.sp),
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  collapseMode: CollapseMode.parallax,
                  background: _HeroHeader(step: _currentStep),
                ),
              ),

              // ── Body
              SliverPadding(
                padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, 100.h),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    FadeTransition(
                      opacity: _fadeAnim,
                      child: SlideTransition(
                        position: _slideAnim,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(height: 20.h),
                            _GlassCard(
                              padding: EdgeInsets.zero,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: _buildJoinedSections(),
                              ),
                            ),
                            SizedBox(height: 24.h),

                            // Submit button
                            if (_selectedBill != null) _buildSubmitButton(),
                            SizedBox(height: 40.h),
                          ],
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildJoinedSections() {
    final sections = <Widget>[];

    // 1. Tenant section (always shown)
    sections.add(_wrapSection(_buildTenantSection()));

    // 2. Bill section (shown after tenant selected)
    if (_selectedTenant != null) {
      sections.add(_wrapSection(_buildBillSection()));
    }

    // 3. Amount + payment method (shown after bill selected)
    if (_selectedBill != null) {
      sections.add(_wrapSection(_buildAmountSection()));
      sections.add(_wrapSection(_buildPaymentMethodSection()));
      sections.add(_wrapSection(_buildReferenceSection()));
    }

    // Add dividers between sections
    final joined = <Widget>[];
    for (int i = 0; i < sections.length; i++) {
      joined.add(sections[i]);
      if (i < sections.length - 1) {
        joined.add(const _SectionDivider());
      }
    }
    return joined;
  }

  Widget _wrapSection(Widget child) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 16.h),
      child: child,
    );
  }

  // ── TENANT SECTION ──
  Widget _buildTenantSection() {
    final provider = context.watch<RentalProvider>();
    final tenants = provider.tenants;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          icon: Icons.person_rounded,
          label: LocalizationService.instance.translate('select_tenant_title'),
          trailing: _selectedTenant != null
              ? Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                  decoration: BoxDecoration(
                    color: _kGreen.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.check_circle_rounded,
                        color: _kGreen, size: 10.sp),
                    SizedBox(width: 4.w),
                    Text(LocalizationService.instance.translate('selected'),
                        style: TextStyle(
                            color: _kGreen,
                            fontSize: 9.sp,
                            fontWeight: FontWeight.w600)),
                  ]),
                )
              : null,
        ),
        Divider(height: 24.h, color: Colors.white10),
        if (provider.isLoading && tenants.isEmpty)
          Center(
            child: Padding(
              padding: EdgeInsets.all(20.h),
              child: SizedBox(
                width: 24.w,
                height: 24.w,
                child: const CircularProgressIndicator(
                    color: _kOrange, strokeWidth: 2),
              ),
            ),
          )
        else if (tenants.isEmpty)
          _buildEmptyState(Icons.person_off_outlined, LocalizationService.instance.translate('no_tenants'))
        else
          ...tenants.map((dynamic t) =>
              _buildTenantItem(t as Map<String, dynamic>)),
      ],
    );
  }

  Widget _buildTenantItem(Map<String, dynamic> tenant) {
    final isSelected = _selectedTenant?['id'] == tenant['id'];
    final house = tenant['house'] is Map
        ? tenant['house'] as Map
        : <String, dynamic>{};
    final name = tenant['name'] ?? '?';
    final initial = name.isNotEmpty ? name[0].toString().toUpperCase() : '?';

    return Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() {
              _selectedTenant = tenant;
              _selectedBill = null;
            });
          },
          borderRadius: BorderRadius.circular(14.r),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
            decoration: BoxDecoration(
              color: isSelected
                  ? _kOrange.withOpacity(0.12)
                  : Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(14.r),
              border: Border.all(
                color: isSelected
                    ? _kOrange.withOpacity(0.5)
                    : Colors.white.withOpacity(0.06),
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 42.w,
                  height: 42.w,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: isSelected
                          ? [_kOrange.withOpacity(0.9), const Color(0xFFFF6B35)]
                          : [_kOrange.withOpacity(0.25), _kOrange.withOpacity(0.15)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(
                      color: isSelected
                          ? Colors.white.withOpacity(0.3)
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Text(initial,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16.sp,
                          fontWeight: FontWeight.bold,
                        )),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 14.sp,
                              fontWeight: FontWeight.w600)),
                      SizedBox(height: 2.h),
                      Row(
                        children: [
                          Icon(Icons.home_outlined,
                              color: Colors.white38, size: 12.sp),
                          SizedBox(width: 4.w),
                          Text(LocalizationService.instance.translateWith('house_3', <Object?>[house['house_number'] ?? '—']),
                              style: TextStyle(
                                  color: Colors.white38, fontSize: 11.sp)),
                        ],
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Container(
                    padding: EdgeInsets.all(4.w),
                    decoration: BoxDecoration(
                      color: _kOrange.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.check_rounded,
                        color: _kOrange, size: 16.sp),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── BILL SECTION ──
  Widget _buildBillSection() {
    final provider = context.watch<RentalProvider>();
    final bills = provider.bills.where((b) {
      final tenantId = b['agreement']?['tenant_id'];
      return tenantId == _selectedTenant?['id'] &&
          (b['status'] == 'unpaid' ||
              b['status'] == 'partial' ||
              b['status'] == 'overdue');
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          icon: Icons.receipt_long_rounded,
          label: LocalizationService.instance.translate('select_rent_period'),
          trailing: _selectedBill != null
              ? Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                  decoration: BoxDecoration(
                    color: _kGreen.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.check_circle_rounded,
                        color: _kGreen, size: 10.sp),
                    SizedBox(width: 4.w),
                    Text(LocalizationService.instance.translate('selected_item'),
                        style: TextStyle(
                            color: _kGreen,
                            fontSize: 9.sp,
                            fontWeight: FontWeight.w600)),
                  ]),
                )
              : null,
        ),
        Divider(height: 24.h, color: Colors.white10),
        if (bills.isEmpty)
          _buildEmptyState(
              Icons.receipt_long_outlined, LocalizationService.instance.translate('no_open_bills'))
        else
          ...bills.map((dynamic b) =>
              _buildBillItem(b as Map<String, dynamic>)),
      ],
    );
  }

  Widget _buildBillItem(Map<String, dynamic> bill) {
    final isSelected = _selectedBill?['id'] == bill['id'];
    final amountDue =
        double.tryParse((bill['amount_due'] ?? 0).toString()) ?? 0.0;
    final balance =
        double.tryParse((bill['balance'] ?? 0).toString()) ?? 0.0;
    final status = bill['status'] ?? 'unpaid';

    Color statusColor;
    switch (status) {
      case 'overdue':
        statusColor = _kRed;
      case 'partial':
        statusColor = _kAmber;
      default:
        statusColor = Colors.white54;
    }

    return Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() {
              _selectedBill = bill;
              _amountController.text = balance.toStringAsFixed(0);
            });
          },
          borderRadius: BorderRadius.circular(14.r),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
            decoration: BoxDecoration(
              color: isSelected
                  ? _kOrange.withOpacity(0.12)
                  : Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(14.r),
              border: Border.all(
                color: isSelected
                    ? _kOrange.withOpacity(0.5)
                    : Colors.white.withOpacity(0.06),
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                // Bill icon
                Container(
                  width: 42.w,
                  height: 42.w,
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(color: statusColor.withOpacity(0.25)),
                  ),
                  child: Center(
                    child: Icon(Icons.calendar_month_outlined,
                        color: statusColor, size: 20.sp),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(bill['month_year'] ?? '',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 14.sp,
                              fontWeight: FontWeight.w600)),
                      SizedBox(height: 4.h),
                      Row(
                        children: [
                          _MiniChip(
                              label: LocalizationService.instance.translateWith('rent_tsh', <Object?>[_formatCurrency(amountDue)]),
                              color: Colors.white38),
                          SizedBox(width: 6.w),
                          _MiniChip(
                              label: LocalizationService.instance.translateWith('balance_tsh', <Object?>[_formatCurrency(balance)]),
                              color: statusColor),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: 8.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10.r),
                    border: Border.all(color: statusColor.withOpacity(0.25)),
                  ),
                  child: Text(_formatStatus(status),
                      style: TextStyle(
                          color: statusColor,
                          fontSize: 9.sp,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── AMOUNT SECTION ──
  Widget _buildAmountSection() {
    final balance =
        double.tryParse((_selectedBill?['balance'] ?? 0).toString()) ?? 0.0;
    final amountDue =
        double.tryParse((_selectedBill?['amount_due'] ?? 0).toString()) ?? 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          icon: Icons.monetization_on_rounded,
          label: LocalizationService.instance.translate('payment_amount_2'),
        ),
        Divider(height: 24.h, color: Colors.white10),

        // Amount input hero
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(vertical: 20.h, horizontal: 16.w),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                _kOrange.withOpacity(0.12),
                _kCyan.withOpacity(0.08),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(color: _kOrange.withOpacity(0.2)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('TSh',
                      style: TextStyle(
                          color: Colors.white38,
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w500)),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: TextField(
                      controller: _amountController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 28.sp,
                          fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        hintText: '0',
                        hintStyle: TextStyle(
                            color: Colors.white12, fontSize: 28.sp),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12.h),
              // Balance info chips
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _InfoChip(
                    label: LocalizationService.instance.translate('rent_label'),
                    value: 'TSh ${_formatFullCurrency(amountDue)}',
                    color: Colors.white54,
                  ),
                  SizedBox(width: 12.w),
                  _InfoChip(
                    label: LocalizationService.instance.translate('balance_label'),
                    value: 'TSh ${_formatFullCurrency(balance)}',
                    color: _kAmber,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── PAYMENT METHOD SECTION ──
  Widget _buildPaymentMethodSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          icon: Icons.payment_rounded,
          label: LocalizationService.instance.translate('payment_method_label'),
        ),
        Divider(height: 24.h, color: Colors.white10),
        Wrap(
          spacing: 8.w,
          runSpacing: 8.h,
          children: _paymentMethods.map((method) {
            final isSelected =
                _selectedPaymentMethod == method['value'];
            final color = method['color'] as Color;
            final icon = method['icon'] as IconData;

            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => setState(
                    () => _selectedPaymentMethod = method['value'] as String),
                borderRadius: BorderRadius.circular(14.r),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: EdgeInsets.symmetric(
                      horizontal: 14.w, vertical: 10.h),
                  decoration: BoxDecoration(
                    gradient: isSelected
                        ? LinearGradient(
                            colors: [
                              _kOrange.withOpacity(0.9),
                              const Color(0xFFFF6B35),
                            ],
                          )
                        : null,
                    color: isSelected ? null : Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(14.r),
                    border: Border.all(
                      color: isSelected
                          ? _kOrange.withOpacity(0.6)
                          : Colors.white.withOpacity(0.08),
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                                color: _kOrange.withOpacity(0.25),
                                blurRadius: 8,
                                offset: const Offset(0, 3))
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: EdgeInsets.all(4.w),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.white.withOpacity(0.2)
                              : color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6.r),
                        ),
                        child: Icon(icon,
                            color: isSelected ? Colors.white : color,
                            size: 14.sp),
                      ),
                      SizedBox(width: 8.w),
                      Text(method['label'] as String,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12.sp,
                            fontWeight:
                                isSelected ? FontWeight.bold : FontWeight.w400,
                          )),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── REFERENCE SECTION ──
  Widget _buildReferenceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          icon: Icons.tag_rounded,
          label: LocalizationService.instance.translate('reference_payment_number'),
        ),
        Divider(height: 24.h, color: Colors.white10),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(14.r),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: TextField(
            controller: _referenceController,
            style: TextStyle(color: Colors.white, fontSize: 14.sp),
            decoration: InputDecoration(
              hintText: LocalizationService.instance.translate('example_trx12345_optional'),
              hintStyle: TextStyle(color: Colors.white24, fontSize: 12.sp),
              prefixIcon: Padding(
                padding: EdgeInsets.all(12.w),
                child: Icon(Icons.receipt_outlined,
                    color: Colors.white24, size: 16.sp),
              ),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                  horizontal: 14.w, vertical: 14.h),
            ),
          ),
        ),
      ],
    );
  }

  // ── SUBMIT BUTTON ──
  Widget _buildSubmitButton() {
    final amount = double.tryParse(_amountController.text) ?? 0;
    final canSubmit =
        _selectedTenant != null && _selectedBill != null && amount > 0;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16.r),
      child: InkWell(
        onTap: canSubmit && !_isProcessing ? _submitPayment : null,
        borderRadius: BorderRadius.circular(16.r),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: double.infinity,
          padding: EdgeInsets.symmetric(vertical: 16.h),
          decoration: BoxDecoration(
            gradient: canSubmit
                ? const LinearGradient(
                    colors: [Color(0xFFF97316), Color(0xFFFF6B35)],
                  )
                : null,
            color: canSubmit ? null : Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(
              color: canSubmit
                  ? _kOrange.withOpacity(0.5)
                  : Colors.white.withOpacity(0.06),
            ),
            boxShadow: canSubmit
                ? [
                    BoxShadow(
                        color: _kOrange.withOpacity(0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 6))
                  ]
                : null,
          ),
          child: _isProcessing
              ? Center(
                  child: SizedBox(
                    width: 24.w,
                    height: 24.w,
                    child: const CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5),
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle_outline_rounded,
                        color:
                            canSubmit ? Colors.white : Colors.white24,
                        size: 20.sp),
                    SizedBox(width: 10.w),
                    Text(LocalizationService.instance.translate('save_payment'),
                        style: TextStyle(
                          color:
                              canSubmit ? Colors.white : Colors.white24,
                          fontSize: 16.sp,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.3,
                        )),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(IconData icon, String message) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(24.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.white12, size: 36.sp),
          SizedBox(height: 8.h),
          Text(message,
              style: TextStyle(color: Colors.white38, fontSize: 12.sp)),
        ],
      ),
    );
  }

  // ── Submit payment ──
  Future<void> _submitPayment() async {
    setState(() => _isProcessing = true);

    try {
      final provider = context.read<RentalProvider>();
      final paymentId = await provider.recordPayment({
        'bill_id': _selectedBill!['id'],
        'amount_paid': double.parse(_amountController.text),
        'payment_method': _selectedPaymentMethod,
        'transaction_reference': _referenceController.text.isNotEmpty
            ? _referenceController.text
            : null,
      });

      if (mounted) {
        if (paymentId != null) {
          _showSuccessDialog(provider.lastPayment ?? {'id': paymentId});
        } else {
          _showErrorDialog(LocalizationService.instance.translate('the_payment_did_not_go_through'));
        }
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog(LocalizationService.instance.translateWith('error_2', <Object?>[e]));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showSuccessDialog(dynamic payment) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: _kGradientMid,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20.r)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(20.w),
              decoration: BoxDecoration(
                gradient: RadialGradient(colors: [
                  _kGreen.withOpacity(0.25),
                  Colors.transparent,
                ]),
                shape: BoxShape.circle,
              ),
              child: Container(
                padding: EdgeInsets.all(12.w),
                decoration: BoxDecoration(
                  color: _kGreen.withOpacity(0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: _kGreen.withOpacity(0.3)),
                ),
                child: Icon(Icons.check_rounded,
                    color: _kGreen, size: 36.sp),
              ),
            ),
            SizedBox(height: 16.h),
            Text("${LocalizationService.instance.translate('payment_saved')}!",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18.sp,
                    fontWeight: FontWeight.bold)),
            SizedBox(height: 8.h),
            Text(
                LocalizationService.instance.translate('would_you_like_to_view_and'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white54, fontSize: 13.sp)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: Text(LocalizationService.instance.translate('later'),
                style: TextStyle(
                    color: Colors.white54, fontSize: 13.sp)),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFF97316), Color(0xFFFF6B35)],
              ),
              borderRadius: BorderRadius.circular(10.r),
              boxShadow: [
                BoxShadow(
                    color: _kOrange.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3))
              ],
            ),
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        ReceiptViewScreen(payment: payment),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10.r)),
              ),
              child: Text(LocalizationService.instance.translate('yes_receipt'),
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    ThemeConstants.showErrorSnackBar(context, message);
  }
}

// ─────────────────────────────────────────────
// Animated gradient background
// ─────────────────────────────────────────────
class _AnimatedBackground extends StatefulWidget {
  const _AnimatedBackground();
  @override
  State<_AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<_AnimatedBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 8))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value;
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _kGradientTop,
                Color.lerp(
                    _kGradientMid, const Color(0xFF0A3A4A), t)!,
                _kGradientBottom,
              ],
              stops: const [0, 0.55, 1],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
// Hero header with step indicator
// ─────────────────────────────────────────────
class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.step});
  final int step;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(painter: _ArcPainter()),
        ),
        Positioned(
          top: 60.h,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              width: 120.w,
              height: 120.w,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  _kOrange.withOpacity(0.18),
                  Colors.transparent,
                ]),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 24.h,
          left: 0,
          right: 0,
          child: Column(
            children: [
              // Payment icon
              Container(
                width: 64.w,
                height: 64.w,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      _kOrange.withOpacity(0.9),
                      const Color(0xFFFF6B35),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                      color: Colors.white.withOpacity(0.3), width: 2.5),
                  boxShadow: [
                    BoxShadow(
                      color: _kOrange.withOpacity(0.4),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(Icons.payments_rounded,
                      color: Colors.white, size: 28.sp),
                ),
              ),
              SizedBox(height: 10.h),
              Text(LocalizationService.instance.translate('record_payment'),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18.sp,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.4,
                  )),
              SizedBox(height: 16.h),

              // Step indicator
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 48.w),
                child: Row(
                  children: [
                    _StepDot(
                        num: 1,
                        label: LocalizationService.instance.translate('agreement_step_tenant'),
                        isActive: step >= 1,
                        isCurrent: step == 1),
                    _StepLine(isActive: step >= 2),
                    _StepDot(
                        num: 2,
                        label: LocalizationService.instance.translate('bill'),
                        isActive: step >= 2,
                        isCurrent: step == 2),
                    _StepLine(isActive: step >= 3),
                    _StepDot(
                        num: 3,
                        label: LocalizationService.instance.translate('payment_label'),
                        isActive: step >= 3,
                        isCurrent: step == 3),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Step dot
// ─────────────────────────────────────────────
class _StepDot extends StatelessWidget {
  const _StepDot({
    required this.num,
    required this.label,
    required this.isActive,
    required this.isCurrent,
  });
  final int num;
  final String label;
  final bool isActive;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 28.w,
            height: 28.w,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: isActive
                  ? const LinearGradient(
                      colors: [_kOrange, Color(0xFFFF6B35)],
                    )
                  : null,
              color: isActive ? null : Colors.white.withOpacity(0.08),
              border: Border.all(
                color: isActive
                    ? _kOrange.withOpacity(0.6)
                    : Colors.white.withOpacity(0.15),
                width: isCurrent ? 2 : 1,
              ),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                          color: _kOrange.withOpacity(0.3),
                          blurRadius: 8)
                    ]
                  : null,
            ),
            child: Center(
              child: isActive && !isCurrent
                  ? Icon(Icons.check_rounded,
                      color: Colors.white, size: 14.sp)
                  : Text('$num',
                      style: TextStyle(
                        color: isActive ? Colors.white : Colors.white24,
                        fontSize: 11.sp,
                        fontWeight: FontWeight.bold,
                      )),
            ),
          ),
          SizedBox(height: 4.h),
          Text(label,
              style: TextStyle(
                color: isActive ? Colors.white70 : Colors.white24,
                fontSize: 9.sp,
                fontWeight: isCurrent ? FontWeight.bold : FontWeight.w400,
              )),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Step line
// ─────────────────────────────────────────────
class _StepLine extends StatelessWidget {
  const _StepLine({required this.isActive});
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32.w,
      height: 2.h,
      margin: EdgeInsets.only(bottom: 16.h),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(1.r),
        gradient: isActive
            ? const LinearGradient(
                colors: [_kOrange, Color(0xFFFF6B35)],
              )
            : null,
        color: isActive ? null : Colors.white.withOpacity(0.08),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Arc painter
// ─────────────────────────────────────────────
class _ArcPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [
          _kOrange.withOpacity(0.08),
          _kCyan.withOpacity(0.10),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Offset.zero & size)
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, size.height * 0.6)
      ..quadraticBezierTo(size.width * 0.5, size.height * 0.3,
          size.width, size.height * 0.55)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);

    final circlePaint = Paint()
      ..color = _kOrange.withOpacity(0.06)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(size.width * 0.85, size.height * 0.15),
        size.width * 0.18, circlePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─────────────────────────────────────────────
// Glass card
// ─────────────────────────────────────────────
class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child, this.padding});
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20.r),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.07),
            borderRadius: BorderRadius.circular(20.r),
            border: Border.all(color: Colors.white.withOpacity(0.13)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: padding ??
                EdgeInsets.symmetric(horizontal: 12.w, vertical: 16.h),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Section divider
// ─────────────────────────────────────────────
class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12.r),
        child: Container(
          height: 2.h,
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white.withOpacity(0.0),
                Colors.white.withOpacity(0.08),
                _kOrange.withOpacity(0.45),
                Colors.white.withOpacity(0.08),
                Colors.white.withOpacity(0.0),
              ],
              stops: const [0.0, 0.2, 0.5, 0.8, 1.0],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Section title
// ─────────────────────────────────────────────
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.label, this.trailing});
  final IconData icon;
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(7.w),
          decoration: BoxDecoration(
            color: _kOrange.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10.r),
            border: Border.all(color: _kOrange.withOpacity(0.25)),
          ),
          child: Icon(icon, color: _kOrange, size: 14.sp),
        ),
        SizedBox(width: 10.w),
        Expanded(
          child: Text(label,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.bold)),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Mini chip
// ─────────────────────────────────────────────
class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6.r),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 9.sp, fontWeight: FontWeight.w500)),
    );
  }
}

// ─────────────────────────────────────────────
// Info chip
// ─────────────────────────────────────────────
class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Column(
        children: [
          Text(label,
              style: TextStyle(
                  color: color.withOpacity(0.7),
                  fontSize: 9.sp,
                  letterSpacing: 0.3)),
          SizedBox(height: 2.h),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
