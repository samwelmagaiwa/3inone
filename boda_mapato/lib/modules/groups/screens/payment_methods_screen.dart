import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../constants/theme_constants.dart';
import '../../../services/localization_service.dart';
import '../../../utils/server_message.dart';
import '../../inventory/screens/widgets/glow_list_card.dart';
import '../models/group_models.dart';
import '../services/groups_api.dart';
import 'groups_text.dart';
import 'widgets/groups_ui.dart';

/// The methods a group can authorise, in the order they are offered.
const List<String> payMethodChoices = <String>['bank_transfer', 'mpesa', 'mixx', 'halopesa', 'airtel_money', 'cash'];

/// Each method keeps its own colour wherever it shows, so a member knows at a glance which one they are paying by.
Color payMethodColor(final String method) => switch (method) {
      'mpesa' => ThemeConstants.successGreen,
      'mixx' => ThemeConstants.invAccent,
      'halopesa' => ThemeConstants.primaryOrange,
      'airtel_money' => ThemeConstants.errorRed,
      'bank_transfer' => ThemeConstants.warningAmber,
      _ => Colors.white54,
    };

IconData payMethodIcon(final String method) => switch (method) {
      'bank_transfer' => Icons.account_balance_rounded,
      'cash' => Icons.payments_rounded,
      _ => Icons.phone_android_rounded,
    };

Future<void> _copy(final BuildContext context, final String text, final bool sw) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) ThemeConstants.showSuccessSnackBar(context, sw ? 'Imenakiliwa.' : 'Copied.');
}

/// Where to pay for one method: the number (to copy), who it is paid to, and for a bank its name. Shown under the payment form and in the list.
class PayToCard extends StatelessWidget {
  const PayToCard({required this.method, super.key});

  final GroupPayMethod method;

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final Color c = payMethodColor(method.method);
    return Container(
      key: Key('grp_payto_${method.method}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: c.withValues(alpha: 0.12), border: Border.all(color: c.withValues(alpha: 0.7))),
      child: Row(children: <Widget>[
        CircleAvatar(radius: 20, backgroundColor: c.withValues(alpha: 0.25), child: Icon(payMethodIcon(method.method), color: GroupPill.readable(c), size: 20)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text('${sw ? 'Lipa kwa' : 'Pay by'} ${methodLabel(sw: sw, method: method.method)}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 2),
            Text(method.number ?? '', key: Key('grp_payto_number_${method.method}'), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
            if (method.bankName != null) Text(method.bankName!, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            if (method.accountName != null) Text(method.accountName!, style: const TextStyle(color: Colors.white60, fontSize: 12)),
          ]),
        ),
        if (method.number != null) IconButton(key: Key('grp_payto_copy_${method.method}'), tooltip: sw ? 'Nakili namba' : 'Copy the number', onPressed: () => _copy(context, method.number!, sw), icon: const Icon(Icons.copy_rounded, color: Colors.white70)),
      ]),
    );
  }
}

/// How to pay, by method: every method the group authorises as a part of one joined card, each with its number to copy. Whoever reads the
/// finances also sees the month's verified money by each method; the Mwenyekiti and the Makamu can choose the methods.
class PaymentMethodsScreen extends StatefulWidget {
  const PaymentMethodsScreen({required this.api, super.key, this.me});

  final GroupsApi api;

  /// The signed-in person, when the caller has them (the screen reads what it needs from the server).
  final GroupMe? me;

  @override
  State<PaymentMethodsScreen> createState() => _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends State<PaymentMethodsScreen> {
  ({bool configured, bool canManage, List<GroupPayMethod> methods})? _r;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final ({bool configured, bool canManage, List<GroupPayMethod> methods}) r = await widget.api.paymentMethods();
      if (mounted) setState(() => _r = r);
    } on Exception catch (e) {
      if (mounted) setState(() => _error = readableErrorMessage(e));
    }
  }

  Future<void> _edit() async {
    final bool? saved = await Navigator.push<bool>(context, MaterialPageRoute<bool>(builder: (_) => PaymentMethodsEditor(api: widget.api, current: _r?.methods ?? const <GroupPayMethod>[])));
    if (saved == true) await _load();
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final ({bool configured, bool canManage, List<GroupPayMethod> methods})? r = _r;
    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(sw ? 'Njia za malipo' : 'Payment methods', flat: true),
      body: SafeArea(
        child: r == null
            ? Center(child: _error == null ? const CircularProgressIndicator() : GroupEmpty(_error!))
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: <Widget>[
                    // The button first, then the methods.
                    if (r.canManage)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            key: const Key('grp_pm_edit'),
                            style: FilledButton.styleFrom(backgroundColor: ThemeConstants.primaryOrange, padding: const EdgeInsets.symmetric(vertical: 12)),
                            onPressed: _edit,
                            icon: const Icon(Icons.tune_rounded),
                            label: Text(sw ? 'Chagua njia za malipo' : 'Choose the payment methods'),
                          ),
                        ),
                      ),
                    if (!r.configured)
                      GlowCard(
                        title: sw ? 'Bado hazijachaguliwa' : 'Not chosen yet',
                        children: <Widget>[
                          Text(
                            sw ? 'Kikundi bado hakijachagua njia za malipo; kila njia inakubaliwa kwa sasa. Mwenyekiti huchagua njia na namba za kulipia.' : 'The group has not chosen its payment methods yet, so every method is accepted for now. The Mwenyekiti chooses the methods and the numbers to pay to.',
                            key: const Key('grp_pm_none'),
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
                      )
                    else
                      ...joinGlowCards(<Widget>[
                        for (final GroupPayMethod m in r.methods)
                          GlowCard(
                            title: methodLabel(sw: sw, method: m.method),
                            dividerKey: 'grp_pm_div',
                            children: <Widget>[
                              PayToCard(method: m),
                              if (m.monthCount != null)
                                GroupDetailRow(
                                  sw ? 'Mwezi huu (zilizothibitishwa)' : 'This month (verified)',
                                  '${m.monthCount} · ${tsh(m.monthIn ?? 0)}${(m.monthOut ?? 0) > 0 ? ' / −${tsh(m.monthOut!)}' : ''}',
                                  valueColor: payMethodColor(m.method),
                                ),
                            ],
                          ),
                      ]),
                  ],
                ),
              ),
      ),
    );
  }
}

class _Choice {
  _Choice({required this.method, GroupPayMethod? current})
      : on = current != null,
        number = TextEditingController(text: current?.number),
        name = TextEditingController(text: current?.accountName),
        bank = TextEditingController(text: current?.bankName);

  final String method;
  bool on;
  final TextEditingController number;
  final TextEditingController name;
  final TextEditingController bank;

  void dispose() {
    number.dispose();
    name.dispose();
    bank.dispose();
  }
}

/// The Mwenyekiti's choice: switch on each method the group authorises and say where it is paid (the number, who it is paid to, the bank).
/// Saving asks for the reason (it goes to the activity log) and replaces the list.
class PaymentMethodsEditor extends StatefulWidget {
  const PaymentMethodsEditor({required this.api, required this.current, super.key});

  final GroupsApi api;
  final List<GroupPayMethod> current;

  @override
  State<PaymentMethodsEditor> createState() => _PaymentMethodsEditorState();
}

class _PaymentMethodsEditorState extends State<PaymentMethodsEditor> {
  late final List<_Choice> _choices = <_Choice>[
    for (final String m in payMethodChoices) _Choice(method: m, current: widget.current.where((final GroupPayMethod p) => p.method == m).firstOrNull),
  ];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final _Choice c in _choices) {
      c.dispose();
    }
    super.dispose();
  }

  String? _problem(final bool sw) {
    final List<_Choice> on = _choices.where((final _Choice c) => c.on).toList();
    if (on.isEmpty) return sw ? 'Chagua angalau njia moja ya malipo.' : 'Choose at least one payment method.';
    for (final _Choice c in on) {
      if (c.method == 'cash') continue;
      final String label = methodLabel(sw: sw, method: c.method);
      if (c.number.text.trim().length < 3) return sw ? 'Weka namba ya kulipia ya $label.' : 'Give the number to pay to for $label.';
      if (c.name.text.trim().length < 2) return sw ? 'Weka jina la mwenye namba ya $label.' : 'Give the name the money is paid to for $label.';
      if (c.method == 'bank_transfer' && c.bank.text.trim().length < 2) return sw ? 'Weka jina la benki.' : 'Give the name of the bank.';
    }
    return null;
  }

  Future<void> _save() async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final String? problem = _problem(sw);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final String? reason = await groupReason(
      context,
      title: sw ? 'Hifadhi njia za malipo?' : 'Save the payment methods?',
      message: _choices.where((final _Choice c) => c.on).map((final _Choice c) => methodLabel(sw: sw, method: c.method)).join(', '),
      yes: sw ? 'Hifadhi' : 'Save',
      tone: GroupTone.positive,
    );
    if (reason == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.savePaymentMethods(<Map<String, dynamic>>[
        for (final _Choice c in _choices)
          if (c.on)
            <String, dynamic>{
              'method': c.method,
              if (c.method != 'cash') 'number': c.number.text.trim(),
              if (c.method != 'cash') 'account_name': c.name.text.trim(),
              if (c.method == 'bank_transfer') 'bank_name': c.bank.text.trim(),
            },
      ], reason: reason);
      if (!mounted) return;
      ThemeConstants.showSuccessSnackBar(context, sw ? 'Njia za malipo zimehifadhiwa.' : 'The payment methods are saved.');
      Navigator.pop(context, true);
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = readableErrorMessage(e);
        });
      }
    }
  }

  Widget _field(final TextEditingController c, final String label, final Key key, {final TextInputType? keyboard}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: TextField(key: key, controller: c, keyboardType: keyboard, style: const TextStyle(color: Colors.white), decoration: ThemeConstants.darkField(label)),
      );

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(sw ? 'Chagua njia za malipo' : 'Choose the payment methods', flat: true),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: <Widget>[
            ...joinGlowCards(<Widget>[
              for (final _Choice c in _choices)
                GlowCard(
                  title: methodLabel(sw: sw, method: c.method),
                  dividerKey: 'grp_pme_div',
                  children: <Widget>[
                    SwitchListTile(
                      key: Key('grp_pme_on_${c.method}'),
                      contentPadding: EdgeInsets.zero,
                      secondary: CircleAvatar(radius: 18, backgroundColor: payMethodColor(c.method).withValues(alpha: 0.25), child: Icon(payMethodIcon(c.method), color: GroupPill.readable(payMethodColor(c.method)), size: 18)),
                      title: Text(c.on ? (sw ? 'Imeidhinishwa' : 'Authorised') : (sw ? 'Haijaidhinishwa' : 'Not authorised'), style: TextStyle(color: c.on ? Colors.white : Colors.white54, fontWeight: FontWeight.w700)),
                      subtitle: c.method == 'cash' ? Text(sw ? 'Hakuna namba inayohitajika.' : 'No number needed.', style: const TextStyle(color: Colors.white54, fontSize: 12)) : null,
                      value: c.on,
                      onChanged: (final bool v) => setState(() {
                        c.on = v;
                        _error = null;
                      }),
                    ),
                    if (c.on && c.method != 'cash') ...<Widget>[
                      if (c.method == 'bank_transfer') _field(c.bank, sw ? 'Jina la benki (mf. NMB, CRDB)' : 'Name of the bank (e.g. NMB, CRDB)', Key('grp_pme_bank_${c.method}')),
                      _field(c.number, c.method == 'bank_transfer' ? (sw ? 'Namba ya akaunti' : 'Account number') : (sw ? 'Namba ya kulipia (simu au lipa namba)' : 'Number to pay to (phone or lipa number)'), Key('grp_pme_number_${c.method}'), keyboard: TextInputType.text),
                      _field(c.name, sw ? 'Jina la mwenye namba (linaonekana wakati wa kulipa)' : 'Name it is paid to (shown when paying)', Key('grp_pme_name_${c.method}')),
                    ],
                  ],
                ),
            ]),
            if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(_error!, key: const Key('grp_pme_error'), style: const TextStyle(color: ThemeConstants.errorText))),
            FilledButton.icon(
              key: const Key('grp_pme_save'),
              style: FilledButton.styleFrom(backgroundColor: ThemeConstants.successGreen, padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.save_rounded),
              label: Text(sw ? 'Hifadhi' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}
