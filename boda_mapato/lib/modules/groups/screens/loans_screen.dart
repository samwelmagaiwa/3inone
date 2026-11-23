import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../constants/theme_constants.dart';
import '../../../services/localization_service.dart';
import '../../../utils/server_message.dart';
import '../../inventory/screens/widgets/glow_list_card.dart';
import '../models/group_loan_models.dart';
import '../models/group_models.dart';
import '../services/groups_api.dart';
import 'groups_text.dart';
import 'loan_detail_screen.dart';
import 'my_loans_screen.dart';
import 'widgets/groups_ui.dart';

/// Loans for the officers: the portfolio (paid out, principal and interest still owed apart, overdue), what waits at each step, and the
/// loans by stage. A loan opens its file, where each officer finds their own step.
class LoansScreen extends StatefulWidget {
  const LoansScreen({required this.me, required this.api, required this.onChanged, super.key});

  final GroupMe me;
  final GroupsApi api;
  final Future<void> Function() onChanged;

  @override
  State<LoansScreen> createState() => _LoansScreenState();
}

class _LoansScreenState extends State<LoansScreen> {
  String? _status = 'open';
  GroupLoanPage? _page;
  final List<GroupLoan> _rows = <GroupLoan>[];
  int _pageNo = 1;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({final bool more = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final int page = more ? _pageNo + 1 : 1;
      final GroupLoanPage got = await widget.api.loans(status: _status, page: page);
      if (!mounted) return;
      setState(() {
        if (!more) _rows.clear();
        _rows.addAll(got.loans);
        _page = got;
        _pageNo = page;
        _loading = false;
      });
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _error = readableErrorMessage(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _open(final GroupLoan l) async {
    await Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => LoanDetailScreen(api: widget.api, me: widget.me, loanId: l.id)));
    await _load();
    await widget.onChanged();
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final Map<String, double> p = _page?.portfolio ?? const <String, double>{};
    final Map<String, int> w = _page?.waiting ?? const <String, int>{};
    final List<(String?, String)> filters = <(String?, String)>[
      ('open', sw ? 'Yanaendelea' : 'In progress'),
      ('under_review', loanStateLabel(sw: sw, state: 'under_review')),
      ('recommended', loanStateLabel(sw: sw, state: 'recommended')),
      ('approved', loanStateLabel(sw: sw, state: 'approved')),
      ('active', sw ? 'Iliyotolewa' : 'Paid out'),
      ('rejected', loanStateLabel(sw: sw, state: 'rejected')),
      (null, sw ? 'Yote' : 'All'),
    ];

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: joinGlowCards(<Widget>[
          if (_page != null)
            GlowListCard(padding: const EdgeInsets.all(16), children: <Widget>[
              Wrap(spacing: 24, runSpacing: 10, children: <Widget>[
                GroupStat(key: const Key('grp_portfolio_out'), label: sw ? 'Msingi unaodaiwa' : 'Principal owed', value: tsh(p['principal_outstanding'] ?? 0), color: ThemeConstants.invAccent),
                GroupStat(label: sw ? 'Riba inayodaiwa' : 'Interest owed', value: tsh(p['interest_outstanding'] ?? 0)),
                GroupStat(label: sw ? 'Riba iliyolipwa' : 'Interest received', value: tsh(p['interest_paid'] ?? 0), color: ThemeConstants.successGreen),
                GroupStat(
                  label: sw ? 'Imepita muda' : 'Overdue',
                  value: '${tsh(p['arrears'] ?? 0)} · ${(p['overdue'] ?? 0).toStringAsFixed(0)}',
                  color: (p['arrears'] ?? 0) > 0 ? ThemeConstants.errorText : null,
                ),
              ]),
              if ((w['to_recommend'] ?? 0) + (w['to_approve'] ?? 0) + (w['to_disburse'] ?? 0) > 0)
                Wrap(spacing: 24, runSpacing: 10, children: <Widget>[
                  GroupStat(label: sw ? 'Ya kupendekeza' : 'To recommend', value: '${w['to_recommend'] ?? 0}', color: ThemeConstants.warningAmber),
                  GroupStat(label: sw ? 'Ya kuidhinisha' : 'To approve', value: '${w['to_approve'] ?? 0}', color: ThemeConstants.warningAmber),
                  GroupStat(label: sw ? 'Ya kutoa' : 'To pay out', value: '${w['to_disburse'] ?? 0}', color: ThemeConstants.warningAmber),
                ]),
            ]),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: <Widget>[
              for (final (String?, String) f in filters)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    key: Key('grp_loan_filter_${f.$1 ?? 'all'}'),
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
          if (!_loading && _error == null && _rows.isEmpty) GroupEmpty(sw ? 'Hakuna mkopo hapa.' : 'No loans here.'),
          if (_rows.isNotEmpty)
            GlowListCard(
              dividerKey: 'grp_loans_div',
              padding: const EdgeInsets.symmetric(horizontal: 4),
              children: <Widget>[for (final GroupLoan l in _rows) LoanTile(loan: l, sw: sw, showMember: true, onTap: () => _open(l))],
            ),
          if (_loading) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
          if ((_page?.hasMore ?? false) && !_loading)
            TextButton(
              onPressed: () => _load(more: true),
              child: Text(LocalizationService.instance.translate('list_show_more'), style: const TextStyle(color: ThemeConstants.primaryOrange)),
            ),
        ]),
      ),
    );
  }
}
