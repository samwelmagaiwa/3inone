import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../services/localization_service.dart';
import '../../../../utils/server_message.dart';
import '../../models/salon_models.dart';
import '../../providers/inventory_provider.dart';
import '../../services/salon_api.dart';
import '../widgets/inventory_widgets.dart';
import 'salon_access.dart';
import 'salon_text.dart';

enum _Range { today, week, month, lastMonth }

/// What the salon spends: rent, salaries, products, electricity and water, transport, repairs, marketing, licences. Each
/// expense says who supplied, how it was paid and carries a photo of the receipt. What the owner or a manager records
/// counts at once; what anyone else records waits for their approval. Only approved spending is a cost in the profit.
class SalonExpensesScreen extends StatefulWidget {
  const SalonExpensesScreen({super.key, this.api, this.today, this.pickReceipt});

  /// The server calls (a fake in tests).
  final SalonApi? api;

  /// What "today" is (a test fixes it); the real clock otherwise.
  final DateTime? today;

  /// Pick a receipt photo: its bytes and file name, or null when none was chosen (a test gives its own; the phone's
  /// gallery otherwise).
  final Future<(Uint8List, String)?> Function()? pickReceipt;

  @override
  State<SalonExpensesScreen> createState() => _SalonExpensesScreenState();
}

class _SalonExpensesScreenState extends State<SalonExpensesScreen> {
  late final SalonApi _api = widget.api ?? SalonApi();

  _Range _range = _Range.month;
  List<SalonExpense> _items = <SalonExpense>[];
  String? _error;
  bool _loading = true;
  bool _busy = false;

  DateTime get _today {
    final DateTime d = widget.today ?? DateTime.now();
    return DateTime(d.year, d.month, d.day);
  }

  (DateTime, DateTime) get _dates {
    final DateTime t = _today;
    switch (_range) {
      case _Range.today:
        return (t, t);
      case _Range.week:
        return (t.subtract(Duration(days: t.weekday - 1)), t);
      case _Range.month:
        return (DateTime(t.year, t.month), t);
      case _Range.lastMonth:
        return (DateTime(t.year, t.month - 1), DateTime(t.year, t.month, 0));
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final _Range asked = _range;
    final (DateTime from, DateTime to) = _dates;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<SalonExpense> rows = await _api.expenses(from, to);
      if (!mounted || asked != _range) return;
      setState(() {
        _items = rows;
        _loading = false;
      });
    } on Exception catch (e) {
      if (!mounted || asked != _range) return;
      setState(() {
        _error = readableErrorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _openForm({final SalonExpense? expense}) async {
    final bool? saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheet) => _ExpenseSheet(api: _api, expense: expense, today: _today),
    );
    if (saved == true && mounted) _load();
  }

  Future<void> _decide(final SalonExpense e, final bool approve) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _api.decideExpense(e.id, approve: approve);
      if (!mounted) return;
      setState(() => _busy = false);
      await _load();
    } on Exception catch (err) {
      if (!mounted) return;
      setState(() => _busy = false);
      ThemeConstants.showErrorSnackBar(context, readableErrorMessage(err));
    }
  }

  Future<(Uint8List, String)?> _pick() async {
    if (widget.pickReceipt != null) return widget.pickReceipt!();
    final XFile? file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 70, maxWidth: 1600);
    if (file == null) return null;

    return (await file.readAsBytes(), file.name);
  }

  Future<void> _attach(final SalonExpense e) async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final (Uint8List, String)? picked = await _pick();
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await _api.attachReceipt(e.id, picked.$1, picked.$2);
      if (!mounted) return;
      setState(() => _busy = false);
      ThemeConstants.showSuccessSnackBar(context, sw ? 'Risiti imehifadhiwa.' : 'Receipt saved.');
      await _load();
    } on Exception catch (err) {
      if (!mounted) return;
      setState(() => _busy = false);
      ThemeConstants.showErrorSnackBar(context, readableErrorMessage(err));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final bool manager = canSeeSalonMoney(context.watch<AuthProvider>().user);

    return Material(
      color: ThemeConstants.primaryBlue,
      child: RefreshIndicator(
        onRefresh: _load,
        backgroundColor: Colors.white,
        color: ThemeConstants.primaryBlue,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 24.h),
          children: _body(sw, manager),
        ),
      ),
    );
  }

  List<Widget> _body(final bool sw, final bool manager) {
    final double total = _items.where((SalonExpense e) => e.status == 'approved').fold<double>(0, (double s, SalonExpense e) => s + e.amount);
    final int waiting = _items.where((SalonExpense e) => e.isPending).length;

    return <Widget>[
      InvFilterChips<_Range>(
        value: _range,
        options: <_Range, String>{
          _Range.today: sw ? 'Leo' : 'Today',
          _Range.week: sw ? 'Wiki hii' : 'This week',
          _Range.month: sw ? 'Mwezi huu' : 'This month',
          _Range.lastMonth: sw ? 'Mwezi uliopita' : 'Last month',
        },
        onSelected: (_Range r) {
          if (r == _range) return;
          setState(() => _range = r);
          _load();
        },
      ),
      SizedBox(height: 10.h),
      Row(
        children: <Widget>[
          Expanded(child: InvStatTile(label: sw ? 'Matumizi' : 'Spent', value: tsh(total), icon: Icons.receipt_long_outlined, accent: ThemeConstants.warningAmber)),
          SizedBox(width: 8.w),
          Expanded(child: InvStatTile(label: sw ? 'Yanasubiri idhini' : 'Waiting approval', value: '$waiting', icon: Icons.hourglass_empty_rounded)),
        ],
      ),
      SizedBox(height: 10.h),
      InvPrimaryButton(key: const ValueKey<String>('expense_add'), busy: false, label: sw ? 'Andika matumizi' : 'Record an expense', onPressed: () => _openForm()),
      SizedBox(height: 12.h),
      if (_loading && _items.isEmpty)
        Padding(padding: EdgeInsets.only(top: 60.h), child: const Center(child: CircularProgressIndicator(color: Colors.white70)))
      else if (_error != null && _items.isEmpty) ...<Widget>[
        InvEmptyState(icon: Icons.error_outline, message: _error!),
        Center(child: TextButton(key: const ValueKey<String>('expense_retry'), onPressed: _load, child: Text(sw ? 'Jaribu tena' : 'Try again', style: const TextStyle(color: Colors.white)))),
      ] else if (_items.isEmpty)
        InvEmptyState(icon: Icons.receipt_long_outlined, message: sw ? 'Hakuna matumizi kwa kipindi hiki.' : 'No expenses in this period.')
      else
        for (final SalonExpense e in _items) ...<Widget>[
          _ExpenseCard(
            expense: e,
            sw: sw,
            manager: manager,
            onEdit: () => _openForm(expense: e),
            onApprove: () => _decide(e, true),
            onReject: () => _decide(e, false),
            onReceipt: () => _attach(e),
          ),
          SizedBox(height: 8.h),
        ],
    ];
  }
}

class _ExpenseCard extends StatelessWidget {
  const _ExpenseCard({required this.expense, required this.sw, required this.manager, required this.onEdit, required this.onApprove, required this.onReject, required this.onReceipt});

  final SalonExpense expense;
  final bool sw;
  final bool manager;
  final VoidCallback onEdit;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onReceipt;

  @override
  Widget build(BuildContext context) {
    final SalonExpense e = expense;
    final Color statusColor = e.isPending ? ThemeConstants.warningAmber : ThemeConstants.errorRed;

    return Container(
      key: ValueKey<String>('expense_${e.id}'),
      decoration: ThemeConstants.glassCardDecoration,
      padding: EdgeInsets.all(12.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(e.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700))),
              SizedBox(width: 8.w),
              Text(tsh(e.amount), style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w800, color: ThemeConstants.warningAmber)),
            ],
          ),
          SizedBox(height: 4.h),
          Text(
            <String>[
              expenseCategoryLabel(sw: sw, category: e.category),
              dayLabel(e.date),
              if (e.supplier != null) e.supplier!,
              if (e.paymentMethod != null) channelLabel(sw: sw, channel: e.paymentMethod!),
              if (e.createdByName != null) e.createdByName!,
            ].join(' • '),
            style: ThemeConstants.captionStyle,
          ),
          SizedBox(height: 6.h),
          Wrap(
            spacing: 6.w,
            runSpacing: 4.h,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              if (e.status != 'approved') InvBadge(label: e.isPending ? (sw ? 'Inasubiri idhini' : 'Waiting approval') : (sw ? 'Imekataliwa' : 'Rejected'), color: statusColor),
              if (e.receiptUrl != null)
                InkWell(
                  key: ValueKey<String>('expense_receipt_${e.id}'),
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (BuildContext d) => Dialog(child: InteractiveViewer(child: Image.network(e.receiptUrl!, fit: BoxFit.contain, errorBuilder: (_, __, ___) => Padding(padding: EdgeInsets.all(24.w), child: Text(sw ? 'Picha haipatikani.' : 'The photo could not be loaded.'))))),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[Icon(Icons.image_outlined, size: 16.sp, color: ThemeConstants.primaryCyan), SizedBox(width: 4.w), Text(sw ? 'Risiti' : 'Receipt', style: ThemeConstants.captionStyle.copyWith(color: ThemeConstants.primaryCyan))]),
                )
              else
                InkWell(
                  key: ValueKey<String>('expense_attach_${e.id}'),
                  onTap: onReceipt,
                  child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[Icon(Icons.add_a_photo_outlined, size: 16.sp, color: Colors.white70), SizedBox(width: 4.w), Text(sw ? 'Ongeza picha ya risiti' : 'Add receipt photo', style: ThemeConstants.captionStyle)]),
                ),
              InkWell(
                key: ValueKey<String>('expense_edit_${e.id}'),
                onTap: onEdit,
                child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[Icon(Icons.edit_outlined, size: 16.sp, color: Colors.white70), SizedBox(width: 4.w), Text(sw ? 'Hariri' : 'Edit', style: ThemeConstants.captionStyle)]),
              ),
            ],
          ),
          if (e.isPending && manager) ...<Widget>[
            SizedBox(height: 8.h),
            Row(
              children: <Widget>[
                Expanded(child: OutlinedButton(key: ValueKey<String>('expense_reject_${e.id}'), onPressed: onReject, child: Text(sw ? 'Kataa' : 'Reject', style: const TextStyle(color: ThemeConstants.errorText, fontWeight: FontWeight.w800)))),
                SizedBox(width: 8.w),
                Expanded(child: ElevatedButton(key: ValueKey<String>('expense_approve_${e.id}'), onPressed: onApprove, style: ElevatedButton.styleFrom(backgroundColor: ThemeConstants.successGreen), child: Text(sw ? 'Idhinisha' : 'Approve', style: const TextStyle(color: Colors.white)))),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The form for one expense, in a sheet. Pops `true` when it was saved.
class _ExpenseSheet extends StatefulWidget {
  const _ExpenseSheet({required this.api, required this.today, this.expense});

  final SalonApi api;
  final SalonExpense? expense;
  final DateTime today;

  @override
  State<_ExpenseSheet> createState() => _ExpenseSheetState();
}

class _ExpenseSheetState extends State<_ExpenseSheet> {
  final TextEditingController _description = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _supplier = TextEditingController();
  String _category = 'supplies';
  String? _method;
  late DateTime _date = widget.today;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final SalonExpense? e = widget.expense;
    if (e != null) {
      _description.text = e.description;
      _amount.text = formatAmount(e.amount);
      _supplier.text = e.supplier ?? '';
      _category = expenseCategories.contains(e.category) ? e.category : 'other';
      _method = e.paymentMethod;
      _date = DateTime(e.date.year, e.date.month, e.date.day);
    }
  }

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    _supplier.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final double amount = parseAmount(_amount.text);
    if (_description.text.trim().isEmpty) {
      setState(() => _error = sw ? 'Andika matumizi ni ya nini.' : 'Say what it was for.');
      return;
    }
    if (amount <= 0) {
      setState(() => _error = sw ? 'Andika kiasi.' : 'Write the amount.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.saveExpense(
        id: widget.expense?.id,
        category: _category,
        description: _description.text.trim(),
        amount: amount,
        date: _date,
        supplier: _supplier.text.trim(),
        paymentMethod: _method,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = readableErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;

    return InvSheetShell(
      title: widget.expense == null ? (sw ? 'Andika matumizi' : 'Record an expense') : (sw ? 'Hariri matumizi' : 'Edit expense'),
      children: <Widget>[
        Wrap(
          spacing: 8.w,
          runSpacing: 4.h,
          children: <Widget>[
            for (final String c in expenseCategories)
              ChoiceChip(
                key: ValueKey<String>('expense_cat_$c'),
                label: Text(expenseCategoryLabel(sw: sw, category: c)),
                selected: _category == c,
                onSelected: (_) => setState(() => _category = c),
              ),
          ],
        ),
        SizedBox(height: 10.h),
        InvTextField(key: const ValueKey<String>('expense_description'), controller: _description, label: sw ? 'Matumizi ni ya nini' : 'What it was for'),
        SizedBox(height: 10.h),
        InvTextField(
          key: const ValueKey<String>('expense_amount'),
          controller: _amount,
          label: sw ? 'Kiasi (TZS)' : 'Amount (TZS)',
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[ThousandsFormatter()],
        ),
        SizedBox(height: 10.h),
        InvDateField(label: sw ? 'Tarehe' : 'Date', value: _date, onChanged: (DateTime? d) => setState(() => _date = d ?? _date)),
        SizedBox(height: 10.h),
        InvTextField(key: const ValueKey<String>('expense_supplier'), controller: _supplier, label: sw ? 'Muuzaji / msambazaji' : 'Supplier', isOptional: true),
        SizedBox(height: 10.h),
        Text(sw ? 'Imelipwa kwa' : 'Paid by', style: ThemeConstants.captionStyle),
        SizedBox(height: 4.h),
        Wrap(
          spacing: 8.w,
          runSpacing: 4.h,
          children: <Widget>[
            for (final String c in InventoryProvider.paymentChannels)
              ChoiceChip(
                key: ValueKey<String>('expense_method_$c'),
                label: Text(channelLabel(sw: sw, channel: c)),
                selected: _method == c,
                onSelected: (bool on) => setState(() => _method = on ? c : null),
              ),
          ],
        ),
        if (_error != null)
          Padding(padding: EdgeInsets.only(top: 10.h), child: Text(_error!, key: const ValueKey<String>('expense_error'), style: ThemeConstants.captionStyle.copyWith(color: ThemeConstants.errorText, fontSize: 12.sp))),
        SizedBox(height: 14.h),
        InvPrimaryButton(key: const ValueKey<String>('expense_save'), busy: _saving, label: sw ? 'Hifadhi' : 'Save', onPressed: _save),
      ],
    );
  }
}
