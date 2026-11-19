import 'package:flutter/material.dart';

import '../../services/localization_service.dart';

/// What was typed to confirm a change of an SMS master switch.
class SmsConfirm {
  const SmsConfirm(this.password, this.word);
  final String password;
  final String word;
}

/// Asks for the password, and (to switch OFF) the confirm word typed exactly; the button stays grey until both are there.
/// The server checks both again, so this is only the first lock.
class SmsConfirmDialog extends StatefulWidget {
  const SmsConfirmDialog({
    required this.enable,
    required this.word,
    required this.title,
    required this.body,
    super.key,
  });

  final bool enable;
  final String word;
  final String title;
  final String body;

  @override
  State<SmsConfirmDialog> createState() => _SmsConfirmDialogState();
}

class _SmsConfirmDialogState extends State<SmsConfirmDialog> {
  final TextEditingController _password = TextEditingController();
  final TextEditingController _word = TextEditingController();
  bool _hide = true;

  @override
  void dispose() {
    _password.dispose();
    _word.dispose();
    super.dispose();
  }

  bool get _ready =>
      _password.text.isNotEmpty && (widget.enable || widget.word.isEmpty || _word.text.trim().toUpperCase() == widget.word.toUpperCase());

  @override
  Widget build(final BuildContext context) {
    final LocalizationService loc = LocalizationService.instance;
    return AlertDialog(
      title: Row(children: <Widget>[
        Icon(widget.enable ? Icons.sms : Icons.warning_amber_rounded, color: widget.enable ? Colors.green : Colors.red),
        const SizedBox(width: 8),
        Expanded(child: Text(widget.title)),
      ]),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text(widget.body),
          const SizedBox(height: 16),
          if (!widget.enable && widget.word.isNotEmpty) ...<Widget>[
            TextField(
              key: const ValueKey<String>('sms_master_word'),
              controller: _word,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(labelText: loc.translateWith('sms_master_type_word', <Object?>[widget.word])),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
          ],
          TextField(
            key: const ValueKey<String>('sms_master_password'),
            controller: _password,
            obscureText: _hide,
            decoration: InputDecoration(
              labelText: loc.translate('sms_master_password'),
              suffixIcon: IconButton(
                icon: Icon(_hide ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _hide = !_hide),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ]),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(loc.translate('cancel'))),
        FilledButton(
          key: const ValueKey<String>('sms_master_confirm'),
          style: FilledButton.styleFrom(backgroundColor: widget.enable ? Colors.green : Colors.red),
          onPressed: _ready ? () => Navigator.of(context).pop(SmsConfirm(_password.text, _word.text.trim())) : null,
          child: Text(loc.translate(widget.enable ? 'sms_master_switch_on' : 'sms_master_switch_off')),
        ),
      ],
    );
  }
}
