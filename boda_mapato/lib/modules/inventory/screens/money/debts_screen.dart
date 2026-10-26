import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../../../utils/server_message.dart';
import '../../services/money_api.dart';
import 'money_style.dart';
import '../salon/salon_input.dart';
import '../salon/salon_text.dart';

/// Every debt in one place, in two tabs: what customers owe me and what I owe. Debts from before the app are written here
/// (name, amount, when it began, when it is due) and join the debtors ageing, the customer's credit balance and the monthly
/// report. Part payments are taken here; a debt that has payments stays as a record.
class DebtsScreen extends StatefulWidget {
  const DebtsScreen({super.key, this.api, this.initialTab = 0});

  final MoneyApi? api;

  /// 0 = owed to me, 1 = I owe.
  final int initialTab;

  @override
  State<DebtsScreen> createState() => _DebtsScreenState();
}

class _DebtsScreenState extends State<DebtsScreen> with SingleTickerProviderStateMixin {
  late final MoneyApi _api = widget.api ?? MoneyApi();
  late final TabController _tabs = TabController(length: 2, vsync: this, initialIndex: widget.initialTab.clamp(0, 1));
  final Map<String, Map<String, dynamic>> _data = <String, Map<String, dynamic>>{};
  final Map<String, String> _errors = <String, String>{};
  bool _loading = true;

  static const List<String> _kinds = <String>['receivable', 'payable'];

  String get _kind => _kinds[_tabs.index];

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    for (final String kind in _kinds) {
      try {
        final Map<String, dynamic> d = await _api.debts(kind);
        _data[kind] = d;
        _errors.remove(kind);
      } on Exception catch (e) {
        _errors[kind] = readableErrorMessage(e);
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  List<Map<String, dynamic>> _debts(final String kind) => <Map<String, dynamic>>[
        if (_data[kind]?['debts'] is List)
          for (final dynamic r in _data[kind]!['debts'] as List<dynamic>)
            if (r is Map) Map<String, dynamic>.from(r),
      ];

  num _num(final dynamic v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);

  Future<void> _add() async {
    final bool? saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext c) => _AddDebtSheet(api: _api, kind: _kind),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _open(final Map<String, dynamic> debt) async {
    final bool? changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext c) => _DebtSheet(api: _api, debt: debt),
    );
    if (changed == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;

    return Scaffold(
      appBar: AppBar(
        title: Text(sw ? 'Madeni' : 'Debts'),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: ThemeConstants.invAccent,
          tabs: <Widget>[
            Tab(key: const Key('tab_owed_to_me'), text: sw ? 'Ninayodai' : 'Owed to me'),
            Tab(key: const Key('tab_i_owe'), text: sw ? 'Ninayodaiwa' : 'I owe'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('debt_add'),
        backgroundColor: ThemeConstants.invAccent,
        foregroundColor: Colors.black,
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: Text(_kind == 'receivable' ? (sw ? 'Deni la zamani' : 'Add old debt') : (sw ? 'Deni ninalodaiwa' : 'Add what I owe')),
      ),
      body: _loading && _data.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(controller: _tabs, children: <Widget>[for (final String k in _kinds) _tab(k, sw)]),
    );
  }

  Widget _tab(final String kind, final bool sw) {
    final Map<String, dynamic>? d = _data[kind];
    final bool receivable = kind == 'receivable';
    if (d == null) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_errors[kind] ?? '', textAlign: TextAlign.center)));
    }
    final List<Map<String, dynamic>> list = _debts(kind);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        key: Key('debts_$kind'),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: <Widget>[
          Card(
            color: (receivable ? ThemeConstants.successGreen : ThemeConstants.warningAmber).withValues(alpha: 0.14),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text(receivable ? (sw ? 'Jumla ninayodai' : 'Total owed to me') : (sw ? 'Jumla ninayodaiwa' : 'Total I owe'), style: kMoneyCaption),
                const SizedBox(height: 4),
                Text(tsh(_num(d['total'])), key: Key('debts_total_$kind'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 6),
                Text(
                  '${sw ? 'Kabla ya mfumo' : 'From before the app'}: ${tsh(_num(d['old']))}   ·   ${receivable ? (sw ? 'Kutoka mauzo' : 'From sales') : (sw ? 'Kutoka ankara' : 'From invoices')}: ${tsh(_num(d['from_records']))}',
                  key: Key('debts_split_$kind'),
                  style: kMoneyCaption,
                ),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(children: <Widget>[
                Icon(receivable ? Icons.handshake_outlined : Icons.account_balance_outlined, size: 48, color: Colors.white38),
                const SizedBox(height: 12),
                Text(
                  receivable
                      ? (sw ? 'Hakuna deni la zamani bado.\nIngiza kila mtu anayekudai ili kila kitu kiwe sehemu moja.' : 'No old debts yet.\nAdd everyone who owes you so it is all in one place.')
                      : (sw ? 'Hakuna deni ulilokopa bado.\nIngiza ulichokopa ili mtaji uwe sahihi.' : 'Nothing owed yet.\nAdd what you owe so your capital is right.'),
                  key: Key('debts_empty_$kind'),
                  textAlign: TextAlign.center,
                  style: kMoneyCaption,
                ),
              ]),
            ),
          for (final Map<String, dynamic> debt in list) _card(debt, sw),
        ],
      ),
    );
  }

  Widget _card(final Map<String, dynamic> debt, final bool sw) {
    final num amount = _num(debt['amount']);
    final num left = _num(debt['left']);
    final int late = _num(debt['days_late']).toInt();
    final double paidShare = amount <= 0 ? 0 : ((amount - left) / amount).clamp(0.0, 1.0).toDouble();
    final String due = '${debt['due_on'] ?? ''}';

    return Card(
      key: Key('debt_${debt['id']}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _open(debt),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Row(children: <Widget>[
              CircleAvatar(radius: 18, backgroundColor: ThemeConstants.invFill, child: Text(('${debt['name']}'.isEmpty ? '?' : '${debt['name']}'[0]).toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Text('${debt['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
                  if ('${debt['phone'] ?? ''}'.isNotEmpty) Text('${debt['phone']}', style: kMoneyCaption),
                ]),
              ),
              Text(tsh(left), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.white)),
            ]),
            const SizedBox(height: 10),
            ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: paidShare, minHeight: 5, backgroundColor: Colors.white12, valueColor: const AlwaysStoppedAnimation<Color>(ThemeConstants.successGreen))),
            const SizedBox(height: 8),
            Row(children: <Widget>[
              Text('${sw ? 'Jumla' : 'Of'} ${tsh(amount)}', style: kMoneyCaption),
              const Spacer(),
              if (late > 0)
                _chip(sw ? 'Siku $late zimepita' : '$late days late', ThemeConstants.errorRed)
              else if (due.isNotEmpty)
                _chip('${sw ? 'Mwisho' : 'Due'} ${dayLabel(DateTime.parse(due))}', Colors.white70)
              else
                _chip('${sw ? 'Ilianza' : 'Since'} ${dayLabel(DateTime.parse('${debt['started_on']}'))}', Colors.white54),
            ]),
            if ('${debt['note'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('${debt['note']}', style: kMoneyCaption)),
          ]),
        ),
      ),
    );
  }

  Widget _chip(final String text, final Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(10)),
        child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      );
}

/// A sheet's chrome in the app's dark teal, with the keyboard pushing it up.
class _Sheet extends StatelessWidget {
  const _Sheet({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
          child: Container(
            decoration: BoxDecoration(color: ThemeConstants.primaryBlue, borderRadius: const BorderRadius.vertical(top: Radius.circular(20)), border: Border.all(color: Colors.white24)),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)))),
                const SizedBox(height: 12),
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 12),
                ...children,
              ]),
            ),
          ),
        ),
      );
}

class _AddDebtSheet extends StatefulWidget {
  const _AddDebtSheet({required this.api, required this.kind});

  final MoneyApi api;
  final String kind;

  @override
  State<_AddDebtSheet> createState() => _AddDebtSheetState();
}

class _AddDebtSheetState extends State<_AddDebtSheet> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _note = TextEditingController();
  DateTime _started = DateTime.now();
  DateTime? _due;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<DateTime?> _pick(final DateTime initial) => showDatePicker(context: context, initialDate: initial, firstDate: DateTime(2000), lastDate: DateTime(2100));

  Future<void> _save() async {
    final bool sw = LocalizationService.instance.isSwahili;
    final double? amount = double.tryParse(_amount.text.replaceAll(',', '').trim());
    if (_name.text.trim().isEmpty) return setState(() => _error = widget.kind == 'receivable' ? (sw ? 'Andika jina la mdaiwa.' : 'Write the debtor\'s name.') : (sw ? 'Andika unayemdai.' : 'Write who you owe.'));
    if (amount == null || amount <= 0) return setState(() => _error = sw ? 'Andika kiasi.' : 'Write the amount.');
    if (_due != null && _due!.isBefore(DateTime(_started.year, _started.month, _started.day))) return setState(() => _error = sw ? 'Tarehe ya mwisho ni kabla ya kuanza.' : 'The due date is before it began.');
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.addDebt(kind: widget.kind, name: _name.text, phone: _phone.text, amount: amount, startedOn: _started, dueOn: _due, note: _note.text);
      if (mounted) Navigator.pop(context, true);
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = readableErrorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final bool receivable = widget.kind == 'receivable';

    return _Sheet(
      title: receivable ? (sw ? 'Deni la zamani ninalodai' : 'Old debt owed to me') : (sw ? 'Deni ninalodaiwa' : 'Debt I owe'),
      children: <Widget>[
        TextField(key: const Key('debt_name'), controller: _name, style: salonInputStyle, textCapitalization: TextCapitalization.words, decoration: salonInput(labelText: receivable ? (sw ? 'Jina la mdaiwa' : 'Debtor\'s name') : (sw ? 'Ninayemdai (msambazaji au mtu)' : 'Who I owe (supplier or person)'))),
        const SizedBox(height: 10),
        TextField(key: const Key('debt_phone'), controller: _phone, style: salonInputStyle, keyboardType: TextInputType.phone, decoration: salonInput(labelText: sw ? 'Simu (si lazima)' : 'Phone (optional)')),
        const SizedBox(height: 10),
        TextField(key: const Key('debt_amount'), controller: _amount, style: salonInputStyle, keyboardType: const TextInputType.numberWithOptions(decimal: false), decoration: salonInput(labelText: sw ? 'Kiasi (TSh)' : 'Amount (TSh)')),
        const SizedBox(height: 10),
        Row(children: <Widget>[
          Expanded(
            child: OutlinedButton.icon(
              key: const Key('debt_started'),
              onPressed: () async {
                final DateTime? d = await _pick(_started);
                if (d != null) setState(() => _started = d);
              },
              icon: const Icon(Icons.event, size: 18),
              label: Text('${sw ? 'Ilianza' : 'Began'} ${dayLabel(_started)}', overflow: TextOverflow.ellipsis),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              key: const Key('debt_due'),
              onPressed: () async {
                final DateTime? d = await _pick(_due ?? DateTime.now());
                if (d != null) setState(() => _due = d);
              },
              icon: const Icon(Icons.alarm, size: 18),
              label: Text(_due == null ? (sw ? 'Mwisho (si lazima)' : 'Due (optional)') : '${sw ? 'Mwisho' : 'Due'} ${dayLabel(_due!)}', overflow: TextOverflow.ellipsis),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        TextField(key: const Key('debt_note'), controller: _note, style: salonInputStyle, decoration: salonInput(labelText: sw ? 'Maelezo (si lazima)' : 'Note (optional)')),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, key: const Key('debt_error'), style: const TextStyle(color: ThemeConstants.errorRed))),
        const SizedBox(height: 14),
        SizedBox(width: double.infinity, child: FilledButton(key: const Key('debt_save'), onPressed: _saving ? null : _save, child: Text(sw ? 'Hifadhi' : 'Save'))),
      ],
    );
  }
}

/// One debt: what is left, the payments made so far, and the buttons to take (or make) a payment or remove a wrong entry.
class _DebtSheet extends StatefulWidget {
  const _DebtSheet({required this.api, required this.debt});

  final MoneyApi api;
  final Map<String, dynamic> debt;

  @override
  State<_DebtSheet> createState() => _DebtSheetState();
}

class _DebtSheetState extends State<_DebtSheet> {
  final TextEditingController _amount = TextEditingController();
  List<Map<String, dynamic>>? _payments;
  String? _error;
  bool _busy = false;

  num get _left => widget.debt['left'] as num;

  @override
  void initState() {
    super.initState();
    _amount.text = _left.round().toString();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final List<Map<String, dynamic>> p = await widget.api.debtPayments((widget.debt['id'] as num).toInt());
        if (mounted) setState(() => _payments = p);
      } on Exception {
        if (mounted) setState(() => _payments = <Map<String, dynamic>>[]);
      }
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pay() async {
    final bool sw = LocalizationService.instance.isSwahili;
    final double? amount = double.tryParse(_amount.text.replaceAll(',', '').trim());
    if (amount == null || amount <= 0 || amount > _left + 0.001) return setState(() => _error = sw ? 'Kiasi kiwe kati ya 1 na ${tsh(_left)}.' : 'The amount must be between 1 and ${tsh(_left)}.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.payDebt((widget.debt['id'] as num).toInt(), amount: amount);
      if (mounted) Navigator.pop(context, true);
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = readableErrorMessage(e);
        });
      }
    }
  }

  Future<void> _delete() async {
    setState(() => _busy = true);
    try {
      await widget.api.deleteDebt((widget.debt['id'] as num).toInt());
      if (mounted) Navigator.pop(context, true);
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = readableErrorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final bool receivable = widget.debt['kind'] == 'receivable';
    final bool hasPayments = (widget.debt['paid'] as num) > 0;

    return _Sheet(
      title: '${widget.debt['name']}',
      children: <Widget>[
        Text('${sw ? 'Iliyobaki' : 'Left'}: ${tsh(_left)}   (${sw ? 'jumla' : 'of'} ${tsh(widget.debt['amount'] as num)})', key: const Key('debt_left'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
        if ('${widget.debt['note'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${widget.debt['note']}', style: kMoneyCaption)),
        const SizedBox(height: 14),
        Text(sw ? 'Malipo yaliyopita' : 'Payments so far', style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
        if (_payments == null) const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator()),
        if (_payments != null && _payments!.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(sw ? 'Hakuna bado.' : 'None yet.', style: kMoneyCaption)),
        for (final Map<String, dynamic> p in _payments ?? <Map<String, dynamic>>[])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: <Widget>[
              Text(dayLabel(DateTime.parse('${p['paid_on']}')), style: kMoneyCaption),
              const Spacer(),
              Text(tsh(p['amount'] as num), style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
            ]),
          ),
        const SizedBox(height: 14),
        TextField(key: const Key('pay_amount'), controller: _amount, style: salonInputStyle, keyboardType: TextInputType.number, decoration: salonInput(labelText: receivable ? (sw ? 'Kiasi kilicholipwa (TSh)' : 'Amount received (TSh)') : (sw ? 'Kiasi ninacholipa (TSh)' : 'Amount I pay (TSh)'))),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, key: const Key('pay_error'), style: const TextStyle(color: ThemeConstants.errorRed))),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: FilledButton(key: const Key('pay_save'), onPressed: _busy ? null : _pay, child: Text(receivable ? (sw ? 'Pokea malipo' : 'Receive payment') : (sw ? 'Lipa' : 'Pay')))),
        if (!hasPayments)
          Align(alignment: Alignment.centerRight, child: TextButton.icon(key: const Key('debt_delete'), onPressed: _busy ? null : _delete, icon: const Icon(Icons.delete_outline, color: ThemeConstants.errorRed), label: Text(sw ? 'Futa (liliandikwa kimakosa)' : 'Delete (entered by mistake)', style: const TextStyle(color: ThemeConstants.errorRed)))),
      ],
    );
  }
}
