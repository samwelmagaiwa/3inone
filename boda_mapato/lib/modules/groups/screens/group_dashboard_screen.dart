import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../constants/theme_constants.dart';
import '../../../services/localization_service.dart';
import '../../../utils/server_message.dart';
import '../../inventory/screens/widgets/glow_list_card.dart';
import '../models/group_models.dart';
import '../services/groups_api.dart';
import 'groups_text.dart';
import 'payment_form.dart';
import 'widgets/groups_ui.dart';

/// Home: the person's own membership and money, and -- for officers -- what waits for them. Everyone has it; a member sees nothing of anyone else.
class GroupDashboardScreen extends StatefulWidget {
  const GroupDashboardScreen({required this.me, required this.api, required this.onChanged, required this.onOpen, super.key});

  final GroupMe me;
  final GroupsApi api;
  final Future<void> Function() onChanged;
  final void Function(String section) onOpen;

  @override
  State<GroupDashboardScreen> createState() => _GroupDashboardScreenState();
}

class _GroupDashboardScreenState extends State<GroupDashboardScreen> {
  List<GroupTransaction> _mine = const <GroupTransaction>[];
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMine());
  }

  Future<void> _loadMine() async {
    if (widget.me.member == null) return;
    try {
      final List<GroupTransaction> mine = await widget.api.myTransactions();
      if (mounted) setState(() => _mine = mine);
    } on Exception catch (e) {
      if (mounted) setState(() => _error = readableErrorMessage(e));
    }
  }

  Future<void> _refresh() async {
    await widget.onChanged();
    await _loadMine();
  }

  Future<void> _pay() async {
    if (await showPaymentForm(context, api: widget.api, me: widget.me)) await _refresh();
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final GroupMe me = widget.me;
    final GroupMember? m = me.member;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: <Widget>[
          // Who I am in the group.
          GlowListCard(
            dividerKey: 'grp_me_div',
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: <Widget>[
              Row(
                children: <Widget>[
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: ThemeConstants.invAccent.withValues(alpha: 0.25),
                    child: const Icon(Icons.person_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          m?.fullName ?? (me.groupName ?? (sw ? 'Kikundi' : 'Group')),
                          key: const Key('grp_me_name'),
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          m == null
                              ? (sw ? 'Msimamizi wa kikundi' : 'Group administrator')
                              : '${officeLabel(sw: sw, office: m.office)} · ${m.memberNumber ?? m.applicationRef ?? ''}',
                          style: const TextStyle(color: Colors.white60, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (m != null) GroupPill(statusLabel(sw: sw, status: m.status), color: statusColor(m.status)),
                ],
              ),
              if (m?.statusReason != null && m!.status != 'active')
                Text(m.statusReason!, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
          if (m != null) ...<Widget>[
            const SizedBox(height: 12),
            GlowCard(
              title: sw ? 'Malipo yangu' : 'My payments',
              dividerKey: 'grp_mypay_div',
              children: <Widget>[
                _DueLine(label: categoryLabel(sw: sw, category: 'joining_fee'), paid: me.balances?['joining_fee'] ?? 0, due: me.joiningFee, sw: sw),
                _DueLine(label: categoryLabel(sw: sw, category: 'shares'), paid: me.balances?['shares'] ?? 0, due: me.shareAmount, sw: sw),
                if (me.pending > 0)
                  GroupDetailRow(sw ? 'Yanasubiri uthibitisho' : 'Waiting for verification', '${me.pending}', valueColor: ThemeConstants.warningAmber),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: FilledButton.icon(
                    key: const Key('grp_pay_open'),
                    style: FilledButton.styleFrom(backgroundColor: ThemeConstants.primaryOrange),
                    onPressed: _pay,
                    icon: const Icon(Icons.payments_rounded),
                    label: Text(sw ? 'Lipa' : 'Pay'),
                  ),
                ),
              ],
            ),
          ],
          if (me.waiting.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            GlowCard(
              title: sw ? 'Yanayokusubiri' : 'Waiting for you',
              dividerKey: 'grp_wait_div',
              children: <Widget>[
                if (me.waiting.containsKey('payments_to_verify'))
                  _WaitLine(
                    key: const Key('grp_wait_payments'),
                    icon: Icons.fact_check_rounded,
                    label: sw ? 'Malipo ya kuthibitisha' : 'Payments to verify',
                    count: me.waiting['payments_to_verify']!,
                    onTap: () => widget.onOpen('payments'),
                  ),
                if (me.waiting.containsKey('applications'))
                  _WaitLine(
                    key: const Key('grp_wait_applications'),
                    icon: Icons.how_to_reg_rounded,
                    label: sw ? 'Maombi ya uanachama' : 'Membership applications',
                    count: me.waiting['applications']!,
                    onTap: () => widget.onOpen('members'),
                  ),
              ],
            ),
          ],
          if (m != null) ...<Widget>[
            const SizedBox(height: 12),
            if (_error != null) GroupEmpty(_error!),
            if (_mine.isEmpty && _error == null) GroupEmpty(sw ? 'Bado hujatuma malipo.' : 'No payments sent yet.'),
            if (_mine.isNotEmpty)
              GlowListCard(
                dividerKey: 'grp_mine_div',
                padding: const EdgeInsets.symmetric(horizontal: 4),
                children: <Widget>[
                  for (final GroupTransaction t in _mine.take(20)) GroupTransactionTile(t: t, sw: sw),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

/// "Joining fee · 80,000 of 80,000", green once all is paid.
class _DueLine extends StatelessWidget {
  const _DueLine({required this.label, required this.paid, required this.due, required this.sw});

  final String label;
  final double paid;
  final double due;
  final bool sw;

  @override
  Widget build(final BuildContext context) {
    final bool done = due <= 0 || paid + 0.001 >= due;
    return GroupDetailRow(
      label,
      due > 0 ? '${tsh(paid)} / ${tsh(due)}' : tsh(paid),
      valueColor: done ? ThemeConstants.successGreen : ThemeConstants.warningAmber,
    );
  }
}

class _WaitLine extends StatelessWidget {
  const _WaitLine({required this.icon, required this.label, required this.count, required this.onTap, super.key});

  final IconData icon;
  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(final BuildContext context) => ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: count > 0 ? ThemeConstants.warningAmber : Colors.white54),
        title: Text(label, style: const TextStyle(color: Colors.white)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Text('$count', style: TextStyle(color: count > 0 ? ThemeConstants.warningAmber : Colors.white54, fontWeight: FontWeight.w800, fontSize: 16)),
          const Icon(Icons.chevron_right, color: Colors.white38),
        ]),
        onTap: onTap,
      );
}

/// A payment in a list: what it was for, who, how much, and where it stands.
class GroupTransactionTile extends StatelessWidget {
  const GroupTransactionTile({required this.t, required this.sw, super.key, this.showMember = false, this.onTap});

  final GroupTransaction t;
  final bool sw;
  final bool showMember;
  final VoidCallback? onTap;

  @override
  Widget build(final BuildContext context) => ListTile(
        key: Key('grp_tx_${t.id}'),
        onTap: onTap,
        title: Text(
          '${t.isReversal ? (sw ? 'Marekebisho: ' : 'Reversal: ') : ''}${categoryLabel(sw: sw, category: t.category)}'
          '${showMember && t.memberName != null ? ' · ${t.memberName}' : ''}',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          <String>[
            dateLabel(t.paidOn),
            methodLabel(sw: sw, method: t.method),
            if (t.externalRef != null) t.externalRef!,
            if (t.receiptNumber != null) t.receiptNumber!,
            if (t.rejectReason != null) t.rejectReason!,
            if (t.isReversed) (sw ? 'Imerekebishwa' : 'Reversed'),
          ].join(' · '),
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Text(
              tsh(t.signedAmount),
              style: TextStyle(color: t.signedAmount < 0 ? ThemeConstants.errorText : Colors.white, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            GroupPill(paymentStatusLabel(sw: sw, status: t.status), color: paymentStatusColor(t.status)),
          ],
        ),
      );
}
