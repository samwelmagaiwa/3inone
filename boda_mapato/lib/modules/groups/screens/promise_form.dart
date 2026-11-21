import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../constants/theme_constants.dart';
import '../../../services/localization_service.dart';
import '../../../utils/server_message.dart';
import '../models/group_models.dart';
import '../services/groups_api.dart';
import 'groups_text.dart';
import 'widgets/groups_ui.dart';

/// "I will pay ... on ...": by a member for themself ([memberId] null) or by an officer for a member. A promise never lowers what is owed.
/// [owing] lets it name the contribution it is for. Returns true when one was made.
Future<bool> showPromiseForm(
  final BuildContext context, {
  required final GroupsApi api,
  required final List<GroupObligation> owing,
  final int? memberId,
  final String? memberName,
  final GroupObligation? obligation,
}) async {
  final bool? made = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: ThemeConstants.bgMid,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (final BuildContext c) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
      child: _PromiseForm(api: api, owing: owing, memberId: memberId, memberName: memberName, obligation: obligation),
    ),
  );
  return made ?? false;
}

class _PromiseForm extends StatefulWidget {
  const _PromiseForm({required this.api, required this.owing, this.memberId, this.memberName, this.obligation});

  final GroupsApi api;
  final List<GroupObligation> owing;
  final int? memberId;
  final String? memberName;
  final GroupObligation? obligation;

  @override
  State<_PromiseForm> createState() => _PromiseFormState();
}

class _PromiseFormState extends State<_PromiseForm> {
  late final TextEditingController _amount = TextEditingController(text: widget.obligation == null ? '' : widget.obligation!.remaining.toStringAsFixed(0));
  final TextEditingController _note = TextEditingController();
  late int? _obligationId = widget.obligation?.id;
  DateTime _on = DateTime.now().add(const Duration(days: 7));
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  String _iso(final DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final double? amount = double.tryParse(_amount.text.replaceAll(',', '').trim());
    if (amount == null || amount < 1) {
      setState(() => _error = sw ? 'Weka kiasi sahihi.' : 'Enter a valid amount.');
      return;
    }
    final bool ok = await groupConfirm(
      context,
      title: sw ? 'Weka ahadi?' : 'Make this promise?',
      message: '${widget.memberName == null ? '' : '${widget.memberName}: '}${tsh(amount)} · ${dateLabel(_iso(_on))}.\n'
          '${sw ? 'Ahadi haipunguzi deni; malipo yaliyothibitishwa tu ndiyo yanapunguza.' : 'A promise does not lower the debt; only a verified payment does.'}',
      yes: sw ? 'Weka' : 'Make it',
      tone: GroupTone.positive,
    );
    if (!ok || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.makePromise(<String, dynamic>{
        'amount': amount,
        'promised_on': _iso(_on),
        if (_obligationId != null) 'obligation_id': _obligationId,
        if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
      }, memberId: widget.memberId);
      if (!mounted) return;
      ThemeConstants.showSuccessSnackBar(context, sw ? 'Ahadi imewekwa.' : 'Promise made.');
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

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final List<GroupObligation> open = widget.owing.where((final GroupObligation o) => o.owing).toList();
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              widget.memberName == null ? (sw ? 'Ahadi ya kulipa' : 'Promise to pay') : '${sw ? 'Ahadi ya' : 'Promise by'} ${widget.memberName}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const Divider(color: Colors.white12, height: 24),
            if (open.isNotEmpty) ...<Widget>[
              DropdownButtonFormField<int?>(
                key: const Key('grp_promise_obligation'),
                initialValue: _obligationId,
                isExpanded: true,
                dropdownColor: ThemeConstants.bgMid,
                style: const TextStyle(color: Colors.white),
                decoration: ThemeConstants.darkField(sw ? 'Ni kwa ajili ya' : 'It is for'),
                items: <DropdownMenuItem<int?>>[
                  DropdownMenuItem<int?>(child: Text(sw ? 'Deni kwa ujumla' : 'What I owe in general')),
                  for (final GroupObligation o in open) DropdownMenuItem<int?>(value: o.id, child: Text('${o.title} · ${tsh(o.remaining)}', overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (final int? id) => setState(() {
                  _obligationId = id;
                  final GroupObligation? o = open.where((final GroupObligation x) => x.id == id).firstOrNull;
                  if (o != null) _amount.text = o.remaining.toStringAsFixed(0);
                }),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              key: const Key('grp_promise_amount'),
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              style: const TextStyle(color: Colors.white),
              decoration: ThemeConstants.darkField(sw ? 'Kiasi (TSH)' : 'Amount (TSH)'),
            ),
            ListTile(
              key: const Key('grp_promise_date'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined, color: Colors.white54),
              title: Text(sw ? 'Nitalipa tarehe' : 'I will pay on', style: const TextStyle(color: Colors.white70)),
              trailing: Text(dateLabel(_iso(_on)), style: const TextStyle(color: Colors.white)),
              onTap: () async {
                final DateTime now = DateTime.now();
                final DateTime? d = await showDatePicker(context: context, initialDate: _on, firstDate: DateTime(now.year, now.month, now.day), lastDate: now.add(const Duration(days: 365)));
                if (d != null) setState(() => _on = d);
              },
            ),
            TextField(controller: _note, maxLength: 255, style: const TextStyle(color: Colors.white), decoration: ThemeConstants.darkField(sw ? 'Maelezo (hiari)' : 'Note (optional)')),
            if (_error != null) Text(_error!, key: const Key('grp_promise_error'), style: const TextStyle(color: ThemeConstants.errorText)),
            const SizedBox(height: 14),
            FilledButton.icon(
              key: const Key('grp_promise_save'),
              style: FilledButton.styleFrom(backgroundColor: ThemeConstants.successGreen, padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.handshake_outlined),
              label: Text(sw ? 'Weka ahadi' : 'Make the promise'),
            ),
          ],
        ),
      ),
    );
  }
}
