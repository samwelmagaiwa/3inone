import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../constants/theme_constants.dart';
import '../../../services/localization_service.dart';
import '../../../utils/server_message.dart';
import '../../inventory/screens/widgets/glow_list_card.dart';
import '../models/group_expense_models.dart';
import '../models/group_models.dart';
import '../models/group_project_models.dart';
import '../services/groups_api.dart';
import 'groups_text.dart';
import 'widgets/amount_dialogs.dart';
import 'widgets/groups_ui.dart';

/// Expenses (matumizi): officials ask for money to be spent; the treasurer (or the chair) approves or turns down; the treasurer pays it out
/// and someone else verifies. Nobody decides or pays their own request (the server refuses it too). A request for a project is held to its budget.
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({required this.me, required this.api, required this.onChanged, super.key});

  final GroupMe me;
  final GroupsApi api;
  final Future<void> Function() onChanged;

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  String? _status;
  List<GroupExpense> _rows = const <GroupExpense>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    if ((widget.me.waiting['expenses_to_approve'] ?? 0) > 0) {
      _status = 'requested';
    } else if ((widget.me.waiting['expenses_to_pay'] ?? 0) > 0) {
      _status = 'approved';
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<GroupExpense> rows = await widget.api.expenses(status: _status);
      if (mounted) {
        setState(() {
          _rows = rows;
          _loading = false;
        });
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _error = readableErrorMessage(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _done(final String text) async {
    if (!mounted) return;
    ThemeConstants.showSuccessSnackBar(context, text);
    await _load();
    await widget.onChanged();
  }

  Future<void> _act(final GroupExpense r) async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final GroupMe me = widget.me;
    final String? picked = await groupActions(context, title: '${r.payee} · ${tsh(r.amount)}', actions: <GroupSheetAction>[
      if (!r.mine && r.state == 'requested' && me.can('approve_expenses')) ...<GroupSheetAction>[
        GroupSheetAction(icon: Icons.verified_rounded, label: sw ? 'Idhinisha' : 'Approve', value: 'approve', tone: GroupTone.positive),
        GroupSheetAction(icon: Icons.block_rounded, label: sw ? 'Kataa' : 'Turn down', value: 'reject', tone: GroupTone.danger),
      ],
      if (!r.mine && r.state == 'approved' && me.can('record_payouts')) GroupSheetAction(icon: Icons.payments_rounded, label: sw ? 'Lipa' : 'Pay out', value: 'pay', tone: GroupTone.positive),
      if (r.mine && r.state == 'requested') GroupSheetAction(icon: Icons.undo_rounded, label: sw ? 'Ondoa ombi' : 'Withdraw', value: 'cancel', tone: GroupTone.danger),
    ]);
    if (picked == null || !mounted) return;
    try {
      switch (picked) {
        case 'approve':
          final (double, String)? got = await showDialog<(double, String)>(
            context: context,
            builder: (_) => AmountNoteDialog(title: sw ? 'Kiasi cha kuidhinisha' : 'Amount to approve', amount: r.amount, max: r.amount),
          );
          if (got == null || !mounted) return;
          final bool ok = await groupConfirm(context, title: sw ? 'Idhinisha matumizi?' : 'Approve the expense?', message: '${r.payee} · ${r.purpose}: ${tsh(got.$1)}', yes: sw ? 'Idhinisha' : 'Approve', tone: GroupTone.positive);
          if (!ok) return;
          await widget.api.decideExpense(r.id, approve: true, amount: got.$1);
          await _done(sw ? 'Matumizi yameidhinishwa.' : 'Expense approved.');
        case 'reject':
          final String? reason = await groupReason(context, title: sw ? 'Kataa ombi la matumizi' : 'Turn the request down', message: '${r.payee} · ${r.purpose}', yes: sw ? 'Kataa' : 'Turn down');
          if (reason == null) return;
          await widget.api.decideExpense(r.id, approve: false, note: reason);
          await _done(sw ? 'Ombi limekataliwa.' : 'Request turned down.');
        case 'pay':
          final (String, String)? how = await showDialog<(String, String)>(context: context, builder: (_) => const PayOutDialog());
          if (how == null || !mounted) return;
          final bool ok = await groupConfirm(
            context,
            title: sw ? 'Lipa matumizi?' : 'Pay the expense out?',
            message: '${r.payee}: ${tsh(r.amountApproved ?? r.amount)} · ${methodLabel(sw: sw, method: how.$1)}.\n'
                '${sw ? 'Yatahesabiwa kulipwa baada ya mtu mwingine kuthibitisha.' : 'It counts as paid once someone else verifies it.'}',
            yes: sw ? 'Lipa' : 'Pay out',
            tone: GroupTone.danger,
          );
          if (!ok) return;
          await widget.api.payExpense(r.id, method: how.$1, reference: how.$2);
          await _done(sw ? 'Imerekodiwa; inasubiri uthibitisho.' : 'Recorded; waiting for verification.');
        case 'cancel':
          if (!await groupConfirm(context, title: sw ? 'Ondoa ombi?' : 'Withdraw the request?', message: '${r.payee} · ${r.purpose}', yes: sw ? 'Ondoa' : 'Withdraw', tone: GroupTone.danger)) return;
          await widget.api.cancelExpense(r.id);
          await _done(sw ? 'Ombi limeondolewa.' : 'Request withdrawn.');
      }
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  Future<void> _ask() async {
    final bool? sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ThemeConstants.bgMid,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (final BuildContext c) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom), child: ExpenseForm(api: widget.api)),
    );
    if (sent ?? false) await _done(context.read<LocalizationService>().isSwahili ? 'Ombi limetumwa.' : 'Request sent.');
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final List<(String?, String)> filters = <(String?, String)>[
      (null, sw ? 'Yote' : 'All'),
      ('requested', expenseStateLabel(sw: sw, state: 'requested')),
      ('approved', expenseStateLabel(sw: sw, state: 'approved')),
      ('rejected', expenseStateLabel(sw: sw, state: 'rejected')),
    ];
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: widget.me.can('request_expenses')
          ? FloatingActionButton.extended(
              key: const Key('grp_expense_ask'),
              backgroundColor: ThemeConstants.primaryOrange,
              foregroundColor: Colors.white,
              onPressed: _ask,
              icon: const Icon(Icons.add_rounded),
              label: Text(sw ? 'Omba matumizi' : 'Ask to spend'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: <Widget>[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: <Widget>[
                for (final (String?, String) f in filters)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      key: Key('grp_expense_filter_${f.$1 ?? 'all'}'),
                      label: Text(f.$2),
                      selected: _status == f.$1,
                      onSelected: (_) {
                        setState(() => _status = f.$1);
                        _load();
                      },
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 10),
            if (_error != null) GroupEmpty(_error!),
            if (!_loading && _error == null && _rows.isEmpty) GroupEmpty(sw ? 'Hakuna ombi hapa.' : 'No requests here.'),
            if (_rows.isNotEmpty)
              GlowListCard(
                dividerKey: 'grp_expense_div',
                padding: const EdgeInsets.symmetric(horizontal: 4),
                children: <Widget>[for (final GroupExpense r in _rows) ExpenseTile(r: r, sw: sw, onTap: () => _act(r))],
              ),
            if (_loading) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
          ],
        ),
      ),
    );
  }
}

/// A request in a list: who is to be paid and why, the amount, who asked and for which project, and where it stands.
class ExpenseTile extends StatelessWidget {
  const ExpenseTile({required this.r, required this.sw, super.key, this.onTap});

  final GroupExpense r;
  final bool sw;
  final VoidCallback? onTap;

  @override
  Widget build(final BuildContext context) => ListTile(
        key: Key('grp_expense_${r.id}'),
        onTap: onTap,
        title: Text('${r.payee} · ${tsh(r.amountApproved ?? r.amount)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        subtitle: Text(
          <String>[
            r.purpose,
            expenseCategoryLabel(sw: sw, category: r.category),
            if (r.projectTitle != null) r.projectTitle!,
            if (r.requestedByName != null) '${sw ? 'Ameomba' : 'Asked by'} ${r.requestedByName}',
            if (r.amountApproved != null && r.amountApproved != r.amount) '${sw ? 'Aliomba' : 'Asked'} ${tsh(r.amount)}',
            if (r.decisionNote != null) r.decisionNote!,
          ].join(' · '),
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
        trailing: GroupPill(expenseStateLabel(sw: sw, state: r.state), color: expenseStateColor(r.state)),
      );
}

/// The form to ask for money to be spent.
class ExpenseForm extends StatefulWidget {
  const ExpenseForm({required this.api, super.key});

  final GroupsApi api;

  @override
  State<ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends State<ExpenseForm> {
  final TextEditingController _purpose = TextEditingController();
  final TextEditingController _payee = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  String _category = 'office';
  int? _project;
  List<GroupProject> _projects = const <GroupProject>[];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadProjects());
  }

  Future<void> _loadProjects() async {
    try {
      final List<GroupProject> p = await widget.api.projects(status: 'active');
      if (mounted) setState(() => _projects = p);
    } on Exception {
      // Without the list the request is simply not tied to a project.
    }
  }

  @override
  void dispose() {
    _purpose.dispose();
    _payee.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final double? amount = double.tryParse(_amount.text.trim());
    if (_purpose.text.trim().length < 3 || _payee.text.trim().length < 2 || amount == null || amount < 1) {
      setState(() => _error = sw ? 'Jaza kusudi, anayelipwa na kiasi.' : 'Fill in the purpose, who is paid and the amount.');
      return;
    }
    final bool ok = await groupConfirm(
      context,
      title: sw ? 'Tuma ombi la matumizi?' : 'Send the expense request?',
      message: '${_payee.text.trim()} · ${tsh(amount)} · ${_purpose.text.trim()}',
      yes: sw ? 'Tuma' : 'Send',
      tone: GroupTone.positive,
    );
    if (!ok || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.requestExpense(<String, dynamic>{
        'purpose': _purpose.text.trim(),
        'category': _category,
        'payee': _payee.text.trim(),
        'amount': amount,
        if (_project != null) 'project_id': _project,
      });
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
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: <Widget>[
          Text(sw ? 'Omba matumizi' : 'Ask to spend', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
          const Divider(color: Colors.white12, height: 24),
          TextField(key: const Key('grp_expense_purpose'), controller: _purpose, maxLength: 255, style: const TextStyle(color: Colors.white), decoration: ThemeConstants.darkField(sw ? 'Kusudi (kinanunuliwa nini)' : 'Purpose (what it is for)')),
          TextField(key: const Key('grp_expense_payee'), controller: _payee, maxLength: 150, style: const TextStyle(color: Colors.white), decoration: ThemeConstants.darkField(sw ? 'Anayelipwa' : 'Who is paid')),
          TextField(
            key: const Key('grp_expense_amount'),
            controller: _amount,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            style: const TextStyle(color: Colors.white),
            decoration: ThemeConstants.darkField(sw ? 'Kiasi (TSh)' : 'Amount (TSh)'),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _category,
            dropdownColor: ThemeConstants.bgMid,
            style: const TextStyle(color: Colors.white),
            decoration: ThemeConstants.darkField(sw ? 'Aina' : 'Kind'),
            items: <DropdownMenuItem<String>>[for (final String c in groupExpenseCategories) DropdownMenuItem<String>(value: c, child: Text(expenseCategoryLabel(sw: sw, category: c)))],
            onChanged: (final String? v) => setState(() => _category = v ?? 'other'),
          ),
          if (_projects.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            DropdownButtonFormField<int?>(
              key: const Key('grp_expense_project'),
              initialValue: _project,
              dropdownColor: ThemeConstants.bgMid,
              style: const TextStyle(color: Colors.white),
              decoration: ThemeConstants.darkField(sw ? 'Mradi (hiari)' : 'Project (optional)'),
              items: <DropdownMenuItem<int?>>[
                DropdownMenuItem<int?>(child: Text(sw ? 'Hakuna' : 'None')),
                for (final GroupProject p in _projects) DropdownMenuItem<int?>(value: p.id, child: Text(p.title)),
              ],
              onChanged: (final int? v) => setState(() => _project = v),
            ),
          ],
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, key: const Key('grp_expense_error'), style: const TextStyle(color: ThemeConstants.errorText))),
          const SizedBox(height: 14),
          FilledButton.icon(
            key: const Key('grp_expense_send'),
            style: FilledButton.styleFrom(backgroundColor: ThemeConstants.successGreen, padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: _busy ? null : _send,
            icon: const Icon(Icons.send_rounded),
            label: Text(sw ? 'Tuma ombi' : 'Send the request'),
          ),
        ]),
      ),
    );
  }
}
