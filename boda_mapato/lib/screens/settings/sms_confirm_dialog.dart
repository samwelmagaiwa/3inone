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

  // The app-wide field style fills fields with a light surface but writes labels and text in white, which leaves both fields blank-white
  // on this dark dialog. These fields carry their own dark look so the label and what is typed can be read.
  static const TextStyle _fieldText = TextStyle(color: Colors.white, fontSize: 16);

  static InputDecoration _field(final String label, final IconData icon) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        floatingLabelStyle: const TextStyle(color: Colors.white),
        prefixIcon: Icon(icon, color: Colors.white70),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.08),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.white38),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.white, width: 1.5),
        ),
      );

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
              style: _fieldText,
              cursorColor: Colors.white,
              decoration: _field(loc.translateWith('sms_master_type_word', <Object?>[widget.word]), Icons.keyboard),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            key: const ValueKey<String>('sms_master_password'),
            controller: _password,
            obscureText: _hide,
            style: _fieldText,
            cursorColor: Colors.white,
            decoration: _field(loc.translate('sms_master_password'), Icons.lock_outline).copyWith(
              suffixIcon: IconButton(
                icon: Icon(_hide ? Icons.visibility : Icons.visibility_off, color: Colors.white70),
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
