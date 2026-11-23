import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../../inventory/screens/widgets/glow_list_card.dart';
import '../../models/group_models.dart';
import '../groups_text.dart';

/// The member's account on Home: what the group holds for them (savings and shares), with the account number beside it. The amount is hidden
/// until the eye is tapped (and hidden again on the next tap), so it is not on show to anyone looking over a shoulder. Tapping the card opens
/// the statement.
class GroupAccountCard extends StatefulWidget {
  const GroupAccountCard({required this.me, required this.onStatement, super.key});

  final GroupMe me;
  final VoidCallback onStatement;

  @override
  State<GroupAccountCard> createState() => _GroupAccountCardState();
}

class _GroupAccountCardState extends State<GroupAccountCard> {
  bool _shown = false;

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final GroupMe me = widget.me;
    final double account = (me.balances?['savings'] ?? 0) + (me.balances?['shares'] ?? 0);
    final String? number = me.member?.memberNumber ?? me.member?.applicationRef;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: const Key('grp_my_account'),
        borderRadius: BorderRadius.circular(20),
        onTap: widget.onStatement,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
          // Inside the joined card the card's own frame is dropped: the glowing lines and the gold title tell it apart.
          decoration: GlowSections.joined(context) ? null : BoxDecoration(borderRadius: BorderRadius.circular(20), color: Colors.white.withValues(alpha: 0.03), border: Border.all(color: Colors.white.withValues(alpha: 0.06))),
          child: Row(children: <Widget>[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: ThemeConstants.invAccent.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: const Icon(Icons.account_balance_wallet_rounded, color: ThemeConstants.invAccent, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: <Widget>[
                Row(children: <Widget>[
                  Flexible(child: Text(sw ? 'Akaunti yangu' : 'My account', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w500))),
                  if (number != null) ...<Widget>[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: ThemeConstants.invAccent.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
                        child: Text('${sw ? 'Na.' : 'No.'} $number', key: const Key('grp_my_account_number'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: ThemeConstants.invAccent, fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ]),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(_shown ? tsh(account) : 'TSh ••••••', key: const Key('grp_my_account_total'), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                ),
              ]),
            ),
            IconButton(
              key: const Key('grp_my_account_eye'),
              tooltip: _shown ? (sw ? 'Ficha salio' : 'Hide the balance') : (sw ? 'Onyesha salio' : 'Show the balance'),
              icon: Icon(_shown ? Icons.visibility_rounded : Icons.visibility_off_rounded, color: Colors.white70),
              onPressed: () => setState(() => _shown = !_shown),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The account as a titled section, so it joins the sections under it into one card.
class GroupAccountSection extends StatelessWidget with GlowSectionWidget {
  const GroupAccountSection({required this.me, required this.onStatement, super.key});

  final GroupMe me;
  final VoidCallback onStatement;

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    return GlowCard(title: sw ? 'Akaunti' : 'Account', children: <Widget>[GroupAccountCard(me: me, onStatement: onStatement)]);
  }
}
