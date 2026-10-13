import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/localization_service.dart';

/// A one-time password the server generated for an account somebody else created
/// (a driver, a tenant, a fundi). Shown once to whoever created it, to hand over: the
/// person must choose their own the first time they sign in.
class TemporaryCredential {
  const TemporaryCredential({
    required this.name,
    required this.password,
    this.contact,
  });

  final String name;
  final String password;

  /// What they sign in with (email or phone), shown beside the password.
  final String? contact;

  String get asText => contact == null || contact!.isEmpty
      ? "$name: $password"
      : "$name ($contact): $password";
}

/// The generated password in an API response, or null when there is none -- because the
/// person already had an account, or the creator chose the password themselves.
String? temporaryPasswordOf(final Map<String, dynamic>? response) {
  final Object? data = response?['data'];
  if (data is! Map) return null;
  final Object? value = data['temporary_password'];
  return value is String && value.isNotEmpty ? value : null;
}

/// Shows the passwords and waits until the creator has dismissed them. It can only be
/// dismissed with the button: once closed, the password cannot be shown again.
Future<void> showTemporaryPasswords(
  final BuildContext context,
  final List<TemporaryCredential> credentials,
) =>
    showTemporaryPasswordsOn(Navigator.of(context), credentials);

/// Same, for a caller whose own context is about to go away (a sheet that closes itself
/// before this is shown): take the navigator first, while the context is still alive.
Future<void> showTemporaryPasswordsOn(
  final NavigatorState navigator,
  final List<TemporaryCredential> credentials,
) {
  if (credentials.isEmpty) return Future<void>.value();
  return navigator.push<void>(
    DialogRoute<void>(
      context: navigator.context,
      barrierDismissible: false,
      builder: (final BuildContext _) =>
          TemporaryPasswordsDialog(credentials: credentials),
    ),
  );
}

class TemporaryPasswordsDialog extends StatefulWidget {
  const TemporaryPasswordsDialog({super.key, required this.credentials});

  final List<TemporaryCredential> credentials;

  @override
  State<TemporaryPasswordsDialog> createState() =>
      _TemporaryPasswordsDialogState();
}

class _TemporaryPasswordsDialogState extends State<TemporaryPasswordsDialog> {
  bool _copied = false;

  bool get _sw => LocalizationService.instance.isSwahili;
  bool get _many => widget.credentials.length > 1;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(
      text: widget.credentials
          .map((final TemporaryCredential c) => c.asText)
          .join("\n"),
    ));
    if (mounted) setState(() => _copied = true);
  }

  @override
  Widget build(final BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final String who = widget.credentials.first.name;

    return AlertDialog(
      title: Text(_sw ? "Neno la siri la muda" : "Temporary password"),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 360),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(_message(who)),
              const SizedBox(height: 16),
              for (int i = 0; i < widget.credentials.length; i++) ...<Widget>[
                if (_many)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      widget.credentials[i].contact == null ||
                              widget.credentials[i].contact!.isEmpty
                          ? widget.credentials[i].name
                          : "${widget.credentials[i].name} · ${widget.credentials[i].contact}",
                      style: text.labelMedium,
                    ),
                  ),
                SelectableText(
                  widget.credentials[i].password,
                  key: ValueKey<String>("temp_password_$i"),
                  style: text.titleLarge?.copyWith(
                    fontFamily: "monospace",
                    letterSpacing: 2,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton.icon(
          key: const ValueKey<String>("temp_password_copy"),
          onPressed: _copy,
          icon: Icon(_copied ? Icons.check : Icons.copy, size: 18),
          label: Text(_copied
              ? (_sw ? "Imenakiliwa" : "Copied")
              : (_many
                  ? (_sw ? "Nakili zote" : "Copy all")
                  : (_sw ? "Nakili" : "Copy"))),
        ),
        FilledButton(
          key: const ValueKey<String>("temp_password_done"),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_sw ? "Nimemaliza" : "Done"),
        ),
      ],
    );
  }

  String _message(final String who) {
    if (_many) {
      return _sw
          ? "Mpe kila mtu neno lake la siri ili aingie. Wataombwa kuweka jipya wakiingia mara ya kwanza. Hayataonyeshwa tena."
          : "Give each person their password so they can sign in. They will be asked to choose a new one the first time. These will not be shown again.";
    }
    return _sw
        ? "Mpe $who neno hili la siri ili aingie. Ataombwa kuweka jipya akiingia mara ya kwanza. Halitaonyeshwa tena."
        : "Give $who this password so they can sign in. They will be asked to choose a new one the first time. It will not be shown again.";
  }
}
