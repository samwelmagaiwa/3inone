import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../models/user_permissions.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../services/api_service.dart';
import '../../../../services/localization_service.dart';
import '../../services/inv_event_bus.dart';
import '../widgets/inventory_widgets.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  final ApiService _api = ApiService();

  String _period = 'today'; // today | week | month | year
  bool _loadingList = false;
  bool _loadingSummary = false;

  List<Map<String, dynamic>> _expenses = [];
  Map<String, dynamic>? _summary;
  List<String> _categories = [
    'rent', 'salaries', 'transport', 'utilities',
    'supplies', 'maintenance', 'marketing', 'other',
  ];

  static const _periodKeys = ['today', 'week', 'month', 'year'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loadingList = true;
      _loadingSummary = true;
    });
    try {
      final res = await _api.getOrNull('/inventory/expenses?period=$_period');
      final sumRes = await _api.getOrNull('/inventory/expenses/summary?period=$_period');
      if (mounted) {
        setState(() {
          _expenses = List<Map<String, dynamic>>.from(
              (res?['data'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)));
          _summary = sumRes?['data'] as Map<String, dynamic>?;
          _loadingList = false;
          _loadingSummary = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _loadingList = false; _loadingSummary = false; });
    }

    // Also fetch categories from backend (non-blocking)
    try {
      final catRes = await _api.getOrNull('/inventory/expenses/categories');
      final cats = catRes?['data'];
      if (cats is List && mounted) {
        setState(() => _categories = List<String>.from(cats));
      }
    } catch (_) {}
  }

  String _fmt(dynamic v) {
    final n = double.tryParse(v?.toString() ?? '') ?? 0;
    return NumberFormat('#,##0', 'en').format(n);
  }

  String _catLabel(LocalizationService loc, String cat) {
    const known = ['rent', 'salaries', 'transport', 'utilities', 'supplies', 'maintenance', 'marketing', 'licences', 'loan_repayment', 'drawings', 'family', 'other'];
    return known.contains(cat) ? loc.translate(cat) : cat;
  }

  String _ratio(dynamic expenses, dynamic revenue) {
    final e = double.tryParse(expenses?.toString() ?? '') ?? 0;
    final r = double.tryParse(revenue?.toString() ?? '') ?? 1;
    if (r == 0) return '0%';
    return '${(e / r * 100).toStringAsFixed(1)}%';
  }

  Color _netColor(dynamic net) {
    final n = double.tryParse(net?.toString() ?? '') ?? 0;
    return n >= 0 ? Colors.greenAccent.shade400 : ThemeConstants.errorText;
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final auth = context.read<AuthProvider>();
    final role = auth.user?.role ?? 'viewer';
    // Adding follows the permission the server enforces on POST/PUT, so it
    // works for anyone an admin granted inv_manage_expenses (and no longer
    // shows a button the server would reject for a role without it).
    // Deleting stays an admin/manager decision.
    final canAdd = context.select<AuthProvider, UserPermissions>((AuthProvider a) => a.permissions).has('inv_manage_expenses');
    final canDelete = role == 'admin' || role == 'manager';

    const textPrimary = Colors.white;
    final textSecondary = Colors.white.withOpacity(0.55);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: canAdd
          ? FloatingActionButton.small(
              heroTag: 'expenses_fab',
              backgroundColor: ThemeConstants.primaryOrange,
              onPressed: () => _showAddSheet(context),
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          backgroundColor: Colors.white,
          color: ThemeConstants.primaryBlue,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
            children: [
              // ── Period filter chips ───────────────────────────────────────
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _periodKeys.map((key) {
                    final selected = key == _period;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(loc.translate(key),
                            style: TextStyle(
                              color: selected ? Colors.black : Colors.white70,
                              fontWeight: FontWeight.w600,
                              fontSize: 12.sp,
                            )),
                        selected: selected,
                        selectedColor: ThemeConstants.primaryOrange,
                        backgroundColor: Colors.white.withOpacity(0.08),
                        side: BorderSide(color: Colors.white.withOpacity(0.15)),
                        onSelected: (_) {
                          setState(() => _period = key);
                          _load();
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
              SizedBox(height: 14.h),

              // ── Revenue vs Expenses summary ───────────────────────────────
              if (_loadingSummary)
                const Center(
                    child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(color: Colors.white54),
                ))
              else if (_summary != null) ...[
                _SummarySection(summary: _summary!, fmt: _fmt, netColor: _netColor, ratio: _ratio),
                if ((double.tryParse('${_summary!['personal_total'] ?? 0}') ?? 0) > 0)
                  Padding(
                    padding: EdgeInsets.only(top: 8.h),
                    child: Text('${loc.translate('personal_spending_note')}: TZS ${_fmt(_summary!['personal_total'])}', key: const ValueKey<String>('personal_total'), style: TextStyle(color: Colors.white54, fontSize: 11.sp)),
                  ),
                SizedBox(height: 16.h),
              ],

              // ── Expense list ──────────────────────────────────────────────
              if (_loadingList)
                const Center(
                    child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(color: Colors.white54),
                ))
              else if (_expenses.isEmpty)
                InvEmptyState(
                  icon: Icons.receipt_long_outlined,
                  message: loc.translate('no_expenses'),
                )
              else ...[
                // Header
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                          flex: 4,
                          child: Text(loc.translate('description'),
                              style: TextStyle(
                                  color: textSecondary,
                                  fontSize: 11.sp,
                                  fontWeight: FontWeight.w600))),
                      Expanded(
                          flex: 2,
                          child: Text(loc.translate('date'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: textSecondary,
                                  fontSize: 11.sp,
                                  fontWeight: FontWeight.w600))),
                      Expanded(
                          flex: 3,
                          child: Text(loc.translate('amount'),
                              textAlign: TextAlign.end,
                              style: TextStyle(
                                  color: textSecondary,
                                  fontSize: 11.sp,
                                  fontWeight: FontWeight.w600))),
                      if (canDelete) SizedBox(width: 28.w),
                    ],
                  ),
                ),
                // Rows
                ..._expenses.map((exp) {
                  final date = exp['expense_date']?.toString() ?? '';
                  final shortDate = date.length >= 10 ? date.substring(5) : date;
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                            color: Colors.white.withOpacity(0.06)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 4,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                exp['description']?.toString() ?? '',
                                style: TextStyle(
                                    color: textPrimary,
                                    fontSize: 12.sp,
                                    fontWeight: FontWeight.w500),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                _catLabel(loc, exp['category']?.toString() ?? '') + (exp['is_personal'] == true || exp['is_personal'] == 1 ? '  ·  ${loc.translate('personal_tag')}' : ''),
                                style: TextStyle(
                                    color: ThemeConstants.primaryOrange
                                        .withOpacity(0.85),
                                    fontSize: 10.sp),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            shortDate,
                            textAlign: TextAlign.center,
                            style:
                                TextStyle(color: textSecondary, fontSize: 11.sp),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            'TZS ${_fmt(exp['amount'])}',
                            textAlign: TextAlign.end,
                            style: TextStyle(
                                color: ThemeConstants.errorText,
                                fontSize: 12.sp,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (canDelete)
                          GestureDetector(
                            onTap: () => _confirmDelete(context, exp),
                            child: Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Icon(Icons.delete_outline,
                                  size: 18.sp, color: Colors.white38),
                            ),
                          ),
                      ],
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAddSheet(BuildContext context) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddExpenseSheet(
        categories: _categories,
        api: _api,
      ),
    );
    if (result == true) {
      _load();
      // Refresh dashboard KPIs so expensesToday updates immediately.
      InvEventBus.instance.emit({InvDomain.expense});
    }
  }

  Future<void> _confirmDelete(
      BuildContext context, Map<String, dynamic> exp) async {
    final loc = LocalizationService.instance;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ThemeConstants.primaryBlue,
        title: Text(loc.translate('confirm_delete_expense'),
            style: const TextStyle(color: Colors.white)),
        content: Text(
          '${loc.translate('confirm_delete_expense_body')} "${exp['description']}"?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(loc.translate('no'),
                  style: const TextStyle(color: Colors.white54))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(loc.translate('delete'),
                  style: TextStyle(color: ThemeConstants.errorText))),
        ],
      ),
    );
    if (ok == true) {
      await _api.delete('/inventory/expenses/${exp['id']}');
      _load();
      InvEventBus.instance.emit({InvDomain.expense});
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Summary widget
// ─────────────────────────────────────────────────────────────────────────────

class _SummarySection extends StatelessWidget {
  const _SummarySection({
    required this.summary,
    required this.fmt,
    required this.netColor,
    required this.ratio,
  });

  final Map<String, dynamic> summary;
  final String Function(dynamic) fmt;
  final Color Function(dynamic) netColor;
  final String Function(dynamic, dynamic) ratio;

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final textSecondary = Colors.white.withOpacity(0.55);
    const textPrimary = Colors.white;

    final byCategory = summary['by_category'] as List? ?? [];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── KPI banner ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                _KpiCell(
                  label: loc.translate('income'),
                  value: 'TZS ${fmt(summary['revenue'])}',
                  color: Colors.greenAccent.shade400,
                ),
                _vDivider(),
                _KpiCell(
                  label: loc.translate('expenses'),
                  value: 'TZS ${fmt(summary['total_expenses'])}',
                  color: ThemeConstants.errorText,
                ),
                _vDivider(),
                _KpiCell(
                  label: loc.translate('net_profit'),
                  value: 'TZS ${fmt(summary['net_profit'])}',
                  color: netColor(summary['net_profit']),
                ),
              ],
            ),
          ),

          // Expense ratio bar
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${loc.translate('expenses')}: ${ratio(summary['total_expenses'], summary['revenue'])} ${loc.isSwahili ? 'ya mapato' : 'of income'}',
                  style: TextStyle(color: textSecondary, fontSize: 10.sp),
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: () {
                      final r = double.tryParse(
                              summary['revenue']?.toString() ?? '') ??
                          0;
                      final e = double.tryParse(
                              summary['total_expenses']?.toString() ?? '') ??
                          0;
                      if (r <= 0) return 0.0;
                      return (e / r).clamp(0.0, 1.0);
                    }(),
                    backgroundColor: Colors.white12,
                    valueColor: AlwaysStoppedAnimation<Color>(
                        ThemeConstants.errorText),
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          ),

          // ── By-category breakdown ─────────────────────────────────────────
          if (byCategory.isNotEmpty) ...[
            Divider(height: 1, color: Colors.white.withOpacity(0.08)),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Text(loc.translate('expense_by_type'),
                  style: TextStyle(
                      color: textSecondary,
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w600)),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                      flex: 4,
                      child: Text(loc.translate('type'),
                          style: TextStyle(
                              color: textSecondary,
                              fontSize: 10.sp,
                              fontWeight: FontWeight.w600))),
                  Expanded(
                      flex: 1,
                      child: Text(loc.translate('count'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: textSecondary,
                              fontSize: 10.sp,
                              fontWeight: FontWeight.w600))),
                  Expanded(
                      flex: 3,
                      child: Text(loc.translate('total'),
                          textAlign: TextAlign.end,
                          style: TextStyle(
                              color: textSecondary,
                              fontSize: 10.sp,
                              fontWeight: FontWeight.w600))),
                ],
              ),
            ),
            ...byCategory.map((c) {
              final map = c as Map;
              final catKey = map['category']?.toString() ?? '';
              const _known = ['rent', 'salaries', 'transport', 'utilities', 'supplies', 'maintenance', 'marketing', 'licences', 'loan_repayment', 'drawings', 'family', 'other'];
              final catName = _known.contains(catKey) ? loc.translate(catKey) : catKey;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  border: Border(
                    bottom:
                        BorderSide(color: Colors.white.withOpacity(0.06)),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: Text(catName,
                          style: TextStyle(
                              color: textPrimary,
                              fontSize: 11.sp,
                              fontWeight: FontWeight.w500)),
                    ),
                    Expanded(
                      flex: 1,
                      child: Text(
                        map['count']?.toString() ?? '0',
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(color: textSecondary, fontSize: 11.sp),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        'TZS ${fmt(map['total'])}',
                        textAlign: TextAlign.end,
                        style: TextStyle(
                            color: ThemeConstants.errorText,
                            fontSize: 11.sp,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }

  Widget _vDivider() => Container(
        width: 1,
        height: 36,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        color: Colors.white.withOpacity(0.12),
      );
}

class _KpiCell extends StatelessWidget {
  const _KpiCell(
      {required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(label,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.55), fontSize: 10.sp)),
          const SizedBox(height: 2),
          Text(value,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: color,
                  fontSize: 11.sp,
                  fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add expense bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _AddExpenseSheet extends StatefulWidget {
  const _AddExpenseSheet({
    required this.categories,
    required this.api,
  });
  final List<String> categories;
  final ApiService api;

  @override
  State<_AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<_AddExpenseSheet> {
  final _formKey = GlobalKey<FormState>();
  String _category = 'other';
  final _descCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  DateTime _date = DateTime.now();
  bool _saving = false;

  /// The owner's own spending (family, drawings): kept in the list, never taken off the business's profit.
  bool _personal = false;

  static const List<String> _personalCategories = <String>['drawings', 'family'];

  bool get _isPersonal => _personal || _personalCategories.contains(_category);

  // Formats digits with commas while keeping a clean numeric value for saving
  void _onAmountChanged(String value) {
    final digits = value.replaceAll(',', '').replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      _amountCtrl.value = const TextEditingValue(text: '');
      return;
    }
    final formatted = NumberFormat('#,##0', 'en').format(int.parse(digits));
    _amountCtrl.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  double get _parsedAmount =>
      double.tryParse(_amountCtrl.text.replaceAll(',', '')) ?? 0;

  @override
  void initState() {
    super.initState();
    _category = widget.categories.contains('other')
        ? 'other'
        : (widget.categories.isNotEmpty ? widget.categories.first : 'other');
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    const _known = ['rent', 'salaries', 'transport', 'utilities', 'supplies', 'maintenance', 'marketing', 'licences', 'loan_repayment', 'drawings', 'family', 'other'];
    String catLabel(String c) => _known.contains(c) ? loc.translate(c) : c;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: ThemeConstants.primaryBlue,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 24.h),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40.w,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              SizedBox(height: 14.h),
              Text(loc.translate('record_expenses'),
                  style: ThemeConstants.headingStyle
                      .copyWith(fontSize: 16.sp, color: Colors.white)),
              SizedBox(height: 14.h),

              // Category dropdown
              DropdownButtonFormField<String>(
                value: _category,
                decoration: _inputDeco(loc.translate('expense_type')),
                dropdownColor: ThemeConstants.primaryBlue,
                style: const TextStyle(color: Colors.white),
                items: widget.categories
                    .map((c) => DropdownMenuItem(
                          value: c,
                          child: Text(catLabel(c),
                              style: const TextStyle(color: Colors.white)),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _category = v ?? _category),
              ),
              SizedBox(height: 10.h),

              // Description
              TextFormField(
                controller: _descCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDeco(loc.translate('description_required')),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? loc.translate('description_required_error') : null,
              ),
              SizedBox(height: 10.h),

              // Amount
              TextFormField(
                controller: _amountCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDeco(loc.translate('amount_tzs')),
                keyboardType: TextInputType.number,
                onChanged: _onAmountChanged,
                validator: (v) {
                  if (_parsedAmount <= 0) return loc.translate('amount_required_error');
                  return null;
                },
              ),
              SizedBox(height: 10.h),

              // Date picker row
              GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                    builder: (ctx, child) => Theme(
                      data: ThemeData.dark(),
                      child: child!,
                    ),
                  );
                  if (picked != null) setState(() => _date = picked);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_outlined,
                          color: Colors.white54, size: 18),
                      const SizedBox(width: 10),
                      Text(
                        DateFormat('dd/MM/yyyy').format(_date),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 8.h),
              SwitchListTile(
                key: const ValueKey<String>('expense_personal'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                activeColor: ThemeConstants.primaryOrange,
                value: _isPersonal,
                // family and drawings are always personal, so the switch cannot be turned off for them
                onChanged: _personalCategories.contains(_category) ? null : (bool v) => setState(() => _personal = v),
                title: Text(loc.translate('personal_expense'), style: const TextStyle(color: Colors.white)),
                subtitle: Text(loc.translate('personal_expense_hint'), style: const TextStyle(color: Colors.white54, fontSize: 11)),
              ),
              SizedBox(height: 10.h),

              InvPrimaryButton(
                busy: _saving,
                label: loc.translate('save'),
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDeco(String label) => InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white54, fontSize: 13.sp),
        filled: true,
        fillColor: Colors.white.withOpacity(0.07),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.white24),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: ThemeConstants.primaryOrange),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.redAccent.shade200),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.redAccent.shade200),
        ),
      );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.api.post('/inventory/expenses', {
        'category': _category,
        'description': _descCtrl.text.trim(),
        'amount': _parsedAmount,
        'expense_date': DateFormat('yyyy-MM-dd').format(_date),
        'is_personal': _isPersonal,
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(LocalizationService.instance.translateWith('failed', <Object?>[e]),
                style: const TextStyle(color: Colors.white)),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }
}
