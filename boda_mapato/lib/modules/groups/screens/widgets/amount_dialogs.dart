import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../groups_text.dart';

/// An amount (never above [max]) and a note.
class AmountNoteDialog extends StatefulWidget {
  const AmountNoteDialog({required this.title, required this.amount, required this.max, super.key, this.noteLabel, this.noteRequired = false, this.allowZero = false});

  final String title;
  final double amount;
  final double max;
  final String? noteLabel;
  final bool noteRequired;

  /// 0 is an answer too (a damage charge decided as nothing).
  final bool allowZero;

  @override
  State<AmountNoteDialog> createState() => _AmountNoteDialogState();
}

class _AmountNoteDialogState extends State<AmountNoteDialog> {
  late final TextEditingController _amount = TextEditingController(text: widget.amount.toStringAsFixed(0));
  final TextEditingController _note = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  double? get _value => double.tryParse(_amount.text.trim());

  bool get _ready => (_value ?? -1) >= (widget.allowZero ? 0 : 1) && (_value ?? 0) <= widget.max + 0.001 && (!widget.noteRequired || _note.text.trim().length >= 3);

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      key: const Key('grp_amount_dialog'),
      backgroundColor: ThemeConstants.bgMid,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
      content: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        // As wide as the screen allows, not as narrow as the fields' hints.
        const SizedBox(width: double.maxFinite),
        TextField(
          key: const Key('grp_amount_field'),
          controller: _amount,
          onChanged: (_) => setState(() {}),
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          style: const TextStyle(color: Colors.white),
          decoration: ThemeConstants.darkField(sw ? 'Kiasi' : 'Amount', helper: '${sw ? 'Hadi' : 'Up to'} ${tsh(widget.max)}'),
        ),
        if (widget.noteLabel != null) ...<Widget>[
          const SizedBox(height: 10),
          TextField(
            key: const Key('grp_amount_note'),
            controller: _note,
            onChanged: (_) => setState(() {}),
            maxLength: 255,
            style: const TextStyle(color: Colors.white),
            decoration: ThemeConstants.darkField(widget.noteLabel!),
          ),
        ],
      ]),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context), child: Text(sw ? 'Ghairi' : 'Cancel', style: const TextStyle(color: Colors.white60))),
        TextButton(
          key: const Key('grp_amount_next'),
          onPressed: _ready ? () => Navigator.pop(context, (_value!, _note.text.trim())) : null,
          child: Text(sw ? 'Endelea' : 'Next', style: TextStyle(color: _ready ? ThemeConstants.successGreen : Colors.white24, fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}

/// How money is paid out: the method and, for mobile money or the bank, its reference.
class PayOutDialog extends StatefulWidget {
  const PayOutDialog({super.key});

  @override
  State<PayOutDialog> createState() => _PayOutDialogState();
}

class _PayOutDialogState extends State<PayOutDialog> {
  final TextEditingController _ref = TextEditingController();
  String _method = 'mpesa';

  @override
  void dispose() {
    _ref.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      key: const Key('grp_payout_dialog'),
      backgroundColor: ThemeConstants.bgMid,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(sw ? 'Imelipwa kwa njia gani' : 'How it is paid out', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
      content: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        // As wide as the screen allows, not as narrow as the fields' hints.
        const SizedBox(width: double.maxFinite),
        DropdownButtonFormField<String>(
          initialValue: _method,
          dropdownColor: ThemeConstants.bgMid,
          style: const TextStyle(color: Colors.white),
          decoration: ThemeConstants.darkField(sw ? 'Njia' : 'Method'),
          items: <DropdownMenuItem<String>>[for (final String m in paymentMethods) DropdownMenuItem<String>(value: m, child: Text(methodLabel(sw: sw, method: m)))],
          onChanged: (final String? v) => setState(() => _method = v ?? 'cash'),
        ),
        if (_method != 'cash') ...<Widget>[
          const SizedBox(height: 10),
          TextField(controller: _ref, maxLength: 80, style: const TextStyle(color: Colors.white), decoration: ThemeConstants.darkField(sw ? 'Namba ya muamala (hiari)' : 'Reference (optional)')),
        ],
      ]),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context), child: Text(sw ? 'Ghairi' : 'Cancel', style: const TextStyle(color: Colors.white60))),
        TextButton(
          key: const Key('grp_payout_next'),
          onPressed: () => Navigator.pop(context, (_method, _ref.text.trim())),
          child: Text(sw ? 'Endelea' : 'Next', style: const TextStyle(color: ThemeConstants.successGreen, fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}
