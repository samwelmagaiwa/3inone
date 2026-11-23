import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../constants/theme_constants.dart';
import '../../../services/localization_service.dart';
import '../../../widgets/scrolling_chip_row.dart';
import '../../../utils/server_message.dart';
import '../../inventory/screens/widgets/glow_list_card.dart';
import '../models/group_models.dart';
import '../services/group_documents.dart';
import '../services/groups_api.dart';
import 'group_dashboard_screen.dart';
import 'groups_text.dart';
import 'payment_form.dart';
import 'widgets/groups_ui.dart';
import 'widgets/member_picker.dart';

/// The group's payments as the treasurer works them: the queue waiting for verification (oldest first), what was verified or turned down,
/// and the group's totals. Verifying, turning down and reversing each ask first; nobody acts on their own payment (the server refuses it too).
class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({required this.me, required this.api, required this.onChanged, super.key});

  final GroupMe me;
  final GroupsApi api;
  final Future<void> Function() onChanged;

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  String? _status = 'pending';
  final List<GroupTransaction> _rows = <GroupTransaction>[];
  Map<String, dynamic> _summary = const <String, dynamic>{};
  int _page = 1;
  bool _hasMore = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({final bool more = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final int page = more ? _page + 1 : 1;
      final GroupTransactionPage got = await widget.api.transactions(status: _status, query: _search.text, page: page);
      final Map<String, dynamic> summary = more ? _summary : await widget.api.moneySummary();
      if (!mounted) return;
      setState(() {
        if (!more) _rows.clear();
        _rows.addAll(got.transactions);
        _summary = summary;
        _page = page;
        _hasMore = got.hasMore;
        _loading = false;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _error = readableErrorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _afterChange(final String done) async {
    if (!mounted) return;
    ThemeConstants.showSuccessSnackBar(context, done);
    await _load();
    await widget.onChanged();
  }

  Future<void> _act(final GroupTransaction t) async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final GroupMe me = widget.me;
    final bool mine = me.member != null && me.member!.id == t.memberId;
    final String? picked = await groupActions(
      context,
      title: '${categoryLabel(sw: sw, category: t.category)} · ${t.memberName ?? ''} · ${tsh(t.amount)}',
      actions: <GroupSheetAction>[
        if (t.isVerified && t.receiptNumber != null) GroupSheetAction(icon: Icons.receipt_long_rounded, label: sw ? 'Risiti (PDF)' : 'Receipt (PDF)', value: 'receipt'),
        if (t.isPending && me.can('verify_payments') && !mine) ...<GroupSheetAction>[
          GroupSheetAction(icon: Icons.verified_rounded, label: sw ? 'Thibitisha' : 'Verify', value: 'verify', tone: GroupTone.positive),
          GroupSheetAction(icon: Icons.block_rounded, label: sw ? 'Kataa' : 'Turn down', value: 'reject', tone: GroupTone.danger),
        ],
        if (t.isVerified && !t.isReversal && !t.isReversed && me.can('reverse_payments') && !mine)
          GroupSheetAction(icon: Icons.undo_rounded, label: sw ? 'Rekebisha (rudisha)' : 'Reverse', value: 'reverse', tone: GroupTone.danger),
      ],
    );
    if (picked == null || !mounted) return;
    try {
      switch (picked) {
        case 'receipt':
          await GroupDocuments.shareReceipt(context, widget.api, t.id, sw: sw);
        case 'verify':
          final bool ok = await groupConfirm(
            context,
            title: sw ? 'Thibitisha malipo?' : 'Verify this payment?',
            message: '${t.memberName ?? ''}: ${tsh(t.amount)} · ${methodLabel(sw: sw, method: t.method)}${t.externalRef == null ? '' : ' · ${t.externalRef}'}.\n'
                '${sw ? 'Hakikisha pesa zimeingia kweli kabla ya kuthibitisha.' : 'Make sure the money really arrived before verifying.'}',
            yes: sw ? 'Thibitisha' : 'Verify',
            tone: GroupTone.positive,
          );
          if (!ok) return;
          final GroupTransaction done = await widget.api.verify(t.id);
          await _afterChange('${sw ? 'Imethibitishwa' : 'Verified'} · ${done.receiptNumber ?? ''}');
        case 'reject':
          final String? reason = await groupReason(
            context,
            title: sw ? 'Kataa malipo' : 'Turn down the payment',
            message: sw ? 'Andika kwa nini; mwanachama ataiona.' : 'Write why; the member sees it.',
            yes: sw ? 'Kataa' : 'Turn down',
          );
          if (reason == null) return;
          await widget.api.reject(t.id, reason);
          await _afterChange(sw ? 'Malipo yamekataliwa.' : 'Payment turned down.');
        case 'reverse':
          final String? reason = await groupReason(
            context,
            title: sw ? 'Rekebisha malipo yaliyothibitishwa' : 'Reverse a verified payment',
            message: sw
                ? 'Malipo ya awali hayafutwi: yanaandikwa malipo ya kurudisha ${tsh(t.amount)} yanayohusishwa nayo.'
                : 'The original is never deleted: a reversal of ${tsh(t.amount)} is recorded and linked to it.',
            yes: sw ? 'Rekebisha' : 'Reverse',
          );
          if (reason == null) return;
          await widget.api.reverse(t.id, reason);
          await _afterChange(sw ? 'Marekebisho yamerekodiwa.' : 'Reversal recorded.');
      }
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  /// The button: a payment for a member, or -- for whoever records payouts -- a group expense.
  Future<void> _add() async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    if (!widget.me.can('record_payouts')) return _record();
    final String? picked = await groupActions(context, title: sw ? 'Rekodi' : 'Record', actions: <GroupSheetAction>[
      if (widget.me.can('record_payments')) GroupSheetAction(icon: Icons.add_card_rounded, label: sw ? 'Malipo ya mwanachama' : "A member's payment", value: 'payment', tone: GroupTone.positive),
      GroupSheetAction(icon: Icons.receipt_long_rounded, label: sw ? 'Matumizi ya kikundi' : 'A group expense', value: 'expense', tone: GroupTone.danger),
    ]);
    if (!mounted) return;
    if (picked == 'payment') {
      await _record();
      return;
    }
    if (picked == 'expense' && await showExpenseForm(context, api: widget.api)) {
      await _load();
      await widget.onChanged();
    }
  }

  Future<void> _record() async {
    final GroupMember? member = await pickGroupMember(context, api: widget.api, statuses: const <String>{'submitted', 'active', 'suspended'});
    if (member == null || !mounted) return;
    Map<String, double> paid = const <String, double>{};
    List<GroupObligation> owing = const <GroupObligation>[];
    try {
      final GroupStatementData? s = await widget.api.statement(memberId: member.id);
      paid = s?.balances ?? const <String, double>{};
      owing = s?.owing ?? const <GroupObligation>[];
    } on Exception {
      paid = const <String, double>{};
    }
    if (!mounted) return;
    if (await showPaymentForm(context, api: widget.api, me: widget.me, member: member, paid: paid, owing: owing)) {
      await _load();
      await widget.onChanged();
    }
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final Map<String, dynamic> verified = _summary['verified'] is Map ? Map<String, dynamic>.from(_summary['verified'] as Map) : <String, dynamic>{};
    final Map<String, dynamic> month = _summary['contributions'] is Map ? Map<String, dynamic>.from(_summary['contributions'] as Map) : <String, dynamic>{};
    final List<(String?, String)> filters = <(String?, String)>[
      ('pending', sw ? 'Zinasubiri' : 'Waiting'),
      ('verified', sw ? 'Zimethibitishwa' : 'Verified'),
      ('rejected', sw ? 'Zimekataliwa' : 'Turned down'),
      (null, sw ? 'Zote' : 'All'),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: widget.me.can('record_payments') || widget.me.can('record_payouts')
          ? FloatingActionButton.extended(
              key: const Key('grp_payment_record'),
              backgroundColor: ThemeConstants.primaryOrange,
              foregroundColor: Colors.white,
              onPressed: _add,
              icon: const Icon(Icons.add_card_rounded),
              label: Text(sw ? 'Rekodi malipo' : 'Record a payment'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: joinGlowCards(<Widget>[
            TextField(
              key: const Key('grp_pay_search'),
              controller: _search,
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 400), _load);
              },
              style: const TextStyle(color: Colors.white),
              decoration: ThemeConstants.darkField(sw ? 'Tafuta jina, namba au reference' : 'Search name, number or reference', prefix: const Icon(Icons.search, color: Colors.white54)),
            ),
            const SizedBox(height: 8),
            ScrollingChipRow(padding: EdgeInsets.zero, children: <Widget>[
                for (final (String?, String) f in filters)
                  ScrollChoiceChip(chipKey: Key('grp_pay_filter_${f.$1 ?? 'all'}'),
                      label: f.$2,
                      selected: _status == f.$1,
                      onSelected: (_) {
                        setState(() => _status = f.$1);
                        _load();
                      },
                    ),
              ]),
            const SizedBox(height: 10),
            if (widget.me.can('view_finance') && _summary.isNotEmpty)
              GlowListCard(
                padding: const EdgeInsets.all(16),
                children: <Widget>[
                  Wrap(spacing: 24, runSpacing: 10, children: <Widget>[
                    GroupStat(
                      key: const Key('grp_cash_stat'),
                      label: sw ? 'Fedha kwenye kumbukumbu' : 'Cash on record',
                      value: tsh((_summary['cash_on_record'] as num?) ?? 0),
                      color: ThemeConstants.invAccent,
                    ),
                    for (final MapEntry<String, dynamic> e in verified.entries)
                      if (e.key != 'expense' || ((e.value as num?) ?? 0) != 0)
                        GroupStat(label: categoryLabel(sw: sw, category: e.key), value: tsh(((e.value as num?) ?? 0).abs())),
                    GroupStat(
                      key: const Key('grp_pay_pending_stat'),
                      label: sw ? 'Zinasubiri' : 'Waiting',
                      value: '${_summary['pending_count'] ?? 0} · ${tsh((_summary['pending_amount'] as num?) ?? 0)}',
                      color: ((_summary['pending_count'] as num?) ?? 0) > 0 ? ThemeConstants.warningAmber : null,
                    ),
                  ]),
                  if (month.isNotEmpty)
                    Wrap(spacing: 24, runSpacing: 10, children: <Widget>[
                      GroupStat(
                        key: const Key('grp_month_stat'),
                        label: '${sw ? 'Michango' : 'Contributions'} ${_summary['month'] ?? ''}',
                        value: '${tsh((month['collected'] as num?) ?? 0)} / ${tsh((month['expected'] as num?) ?? 0)}',
                      ),
                      GroupStat(
                        label: sw ? 'Imepita muda' : 'Overdue',
                        value: '${tsh((month['overdue_amount'] as num?) ?? 0)} · ${month['overdue_members'] ?? 0} ${sw ? 'wanachama' : 'members'}',
                        color: ((month['overdue_amount'] as num?) ?? 0) > 0 ? ThemeConstants.errorText : null,
                      ),
                      GroupStat(label: sw ? 'Matumizi mwezi huu' : 'Spent this month', value: tsh((_summary['expenses_in_month'] as num?) ?? 0)),
                    ]),
                ],
              ),
            if (_error != null) GroupEmpty(_error!),
            if (!_loading && _error == null && _rows.isEmpty)
              GroupEmpty(_status == 'pending' ? (sw ? 'Hakuna malipo yanayosubiri.' : 'Nothing waits for verification.') : (sw ? 'Hakuna malipo hapa.' : 'No payments here.')),
            if (_rows.isNotEmpty)
              GlowListCard(
                dividerKey: 'grp_pay_div',
                padding: const EdgeInsets.symmetric(horizontal: 4),
                children: <Widget>[for (final GroupTransaction t in _rows) GroupTransactionTile(t: t, sw: sw, showMember: true, onTap: () => _act(t))],
              ),
            if (_loading) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
            if (_hasMore && !_loading)
              TextButton(
                onPressed: () => _load(more: true),
                child: Text(LocalizationService.instance.translate('list_show_more'), style: const TextStyle(color: ThemeConstants.primaryOrange)),
              ),
          ]),
        ),
      ),
    );
  }
}
