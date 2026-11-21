import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';

/// What an action does decides its colour, as everywhere in the app: going ahead or approving is green, removing or refusing is red, the
/// rest (saving, giving) the app's orange.
enum GroupTone { positive, danger, neutral }

Color toneColor(final GroupTone tone) => switch (tone) {
      GroupTone.positive => ThemeConstants.successGreen,
      GroupTone.danger => ThemeConstants.errorRed,
      GroupTone.neutral => ThemeConstants.primaryOrange,
    };

bool _sw(final BuildContext context) => context.read<LocalizationService>().isSwahili;

/// The Yes / No card before anything that changes the group's records. True only when Yes was pressed.
Future<bool> groupConfirm(
  final BuildContext context, {
  required final String title,
  required final String message,
  final String? yes,
  final GroupTone tone = GroupTone.neutral,
}) async {
  final bool sw = _sw(context);
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (final BuildContext ctx) => AlertDialog(
      key: const Key('grp_confirm'),
      backgroundColor: ThemeConstants.bgMid,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
      content: Text(message, style: const TextStyle(color: Colors.white70)),
      actions: <Widget>[
        TextButton(
          key: const Key('grp_confirm_no'),
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(sw ? 'Hapana' : 'No', style: const TextStyle(color: Colors.white60)),
        ),
        TextButton(
          key: const Key('grp_confirm_yes'),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(yes ?? (sw ? 'Ndiyo' : 'Yes'), style: TextStyle(color: toneColor(tone), fontWeight: FontWeight.w800)),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// A card asking why (rejecting, reversing, suspending ...): returns the reason, or null when cancelled. The button stays off until at
/// least three letters are written.
Future<String?> groupReason(
  final BuildContext context, {
  required final String title,
  required final String yes,
  final String? message,
  final GroupTone tone = GroupTone.danger,
}) {
  return showDialog<String>(context: context, builder: (final BuildContext ctx) => _ReasonDialog(title: title, message: message, yes: yes, tone: tone));
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.title, required this.yes, required this.tone, this.message});

  final String title;
  final String? message;
  final String yes;
  final GroupTone tone;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final TextEditingController _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final bool ready = _reason.text.trim().length >= 3;
    return AlertDialog(
      key: const Key('grp_reason'),
      backgroundColor: ThemeConstants.bgMid,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (widget.message != null) ...<Widget>[
            Text(widget.message!, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
          ],
          TextField(
            key: const Key('grp_reason_field'),
            controller: _reason,
            autofocus: true,
            maxLength: 255,
            maxLines: 3,
            minLines: 1,
            style: const TextStyle(color: Colors.white),
            decoration: ThemeConstants.darkField(sw ? 'Sababu' : 'Reason'),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context), child: Text(sw ? 'Ghairi' : 'Cancel', style: const TextStyle(color: Colors.white60))),
        TextButton(
          key: const Key('grp_reason_yes'),
          onPressed: ready ? () => Navigator.pop(context, _reason.text.trim()) : null,
          child: Text(widget.yes, style: TextStyle(color: ready ? toneColor(widget.tone) : Colors.white24, fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}

/// A small coloured label (a status).
class GroupPill extends StatelessWidget {
  const GroupPill(this.text, {required this.color, super.key});

  final String text;
  final Color color;

  @override
  Widget build(final BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.55)),
        ),
        child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      );
}

/// A figure with its label under it, for the rows of numbers at the head of a card.
class GroupStat extends StatelessWidget {
  const GroupStat({required this.label, required this.value, super.key, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(final BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(value, style: TextStyle(color: color ?? Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
        ],
      );
}

/// The quiet line a list shows when it has nothing.
class GroupEmpty extends StatelessWidget {
  const GroupEmpty(this.text, {super.key});

  final String text;

  @override
  Widget build(final BuildContext context) =>
      Padding(padding: const EdgeInsets.all(24), child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60)));
}

/// A line in a details card: what it is on the left, the value on the right.
class GroupDetailRow extends StatelessWidget {
  const GroupDetailRow(this.label, this.value, {super.key, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(final BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(flex: 2, child: Text(label, style: const TextStyle(color: Colors.white60, fontSize: 13))),
            const SizedBox(width: 12),
            Expanded(
              flex: 3,
              child: Text(value, textAlign: TextAlign.end, style: TextStyle(color: valueColor ?? Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}

/// An action in a bottom sheet, its icon in the colour of what it does.
class GroupSheetAction extends StatelessWidget {
  const GroupSheetAction({required this.icon, required this.label, required this.value, super.key, this.tone = GroupTone.neutral});

  final IconData icon;
  final String label;
  final String value;
  final GroupTone tone;

  @override
  Widget build(final BuildContext context) => ListTile(
        key: Key('grp_act_$value'),
        leading: Icon(icon, color: tone == GroupTone.neutral ? Colors.white : toneColor(tone)),
        title: Text(label, style: TextStyle(color: tone == GroupTone.danger ? ThemeConstants.errorText : Colors.white)),
        onTap: () => Navigator.pop(context, value),
      );
}

/// Opens the sheet of [actions] and gives back the value of the one chosen.
/// Nothing is opened when there is nothing this person may do.
Future<String?> groupActions(final BuildContext context, {required final String title, required final List<GroupSheetAction> actions}) async =>
    actions.isEmpty
        ? null
        : showModalBottomSheet<String>(
      context: context,
      backgroundColor: ThemeConstants.bgMid,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (final BuildContext c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
            ),
            const Divider(color: Colors.white12),
            ...actions,
          ],
        ),
      ),
    );
