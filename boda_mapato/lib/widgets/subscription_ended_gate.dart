import "dart:async";

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:provider/provider.dart";
import "package:url_launcher/url_launcher.dart";

import "../constants/theme_constants.dart";
import "../models/subscription.dart";
import "../providers/auth_provider.dart";
import "../screens/settings/subscription_screen.dart";
import "../services/localization_service.dart";

/// Covers the whole app with "pay to continue" while the server holds the signed-in business back for an unpaid
/// plan, and takes the cover away by itself once a payment is recorded.
///
/// The cover is the only thing on screen: a polite message, the number to pay through, and a way to check again.
/// The app underneath stays where it was (it is only hidden), so after the payment the person is back in the app
/// without signing in again. The server is asked every [pollEvery] while the cover is up; "I have paid" asks at once.
class SubscriptionEndedGate extends StatelessWidget {
  const SubscriptionEndedGate({super.key, required this.child, this.pollEvery = const Duration(seconds: 30)});

  final Widget child;
  final Duration pollEvery;

  @override
  Widget build(final BuildContext context) {
    final bool held = context.select<AuthProvider, bool>((final AuthProvider auth) => auth.subscriptionBlocked);
    if (!held) return child;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        TickerMode(enabled: false, child: ExcludeSemantics(child: child)),
        _Cover(pollEvery: pollEvery),
      ],
    );
  }
}

class _Cover extends StatefulWidget {
  const _Cover({required this.pollEvery});

  final Duration pollEvery;

  @override
  State<_Cover> createState() => _CoverState();
}

class _CoverState extends State<_Cover> {
  Timer? _timer;
  Timer? _copiedTimer;
  bool _checking = false;
  bool _stillUnpaid = false;
  bool _copied = false;

  bool get _sw => LocalizationService.instance.isSwahili;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.pollEvery, (final Timer _) => _check(manual: false));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _copiedTimer?.cancel();
    super.dispose();
  }

  Future<void> _check({required final bool manual}) async {
    if (_checking) return;
    final AuthProvider auth = context.read<AuthProvider>();
    if (manual) setState(() => _checking = true);
    await auth.recheckSubscription();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _stillUnpaid = manual && auth.subscriptionBlocked;
    });
  }

  Future<void> _call(final String phone) async {
    try {
      await launchUrl(Uri(scheme: "tel", path: phone));
    } on Exception catch (_) {
      // no dialer: the number is on the screen
    }
  }

  Future<void> _copy(final String phone) async {
    await Clipboard.setData(ClipboardData(text: phone));
    if (!mounted) return;
    setState(() => _copied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  /// The polite words, in the language the app is in. The number is part of the sentence, so it is read
  /// even by someone who never looks at the card below.
  String _message({required final String name, required final String phone}) {
    final LocalizationService loc = LocalizationService.instance;
    if (name.isEmpty) {
      return phone.isEmpty
          ? loc.translate('subscription_cover_plain_nophone')
          : loc.translateWith('subscription_cover_plain_phone', <Object?>[phone]);
    }
    return phone.isEmpty
        ? loc.translateWith('subscription_cover_named_nophone', <Object?>[name])
        : loc.translateWith('subscription_cover_named_phone', <Object?>[name, phone]);
  }

  @override
  Widget build(final BuildContext context) {
    final AuthProvider auth = context.watch<AuthProvider>();
    final SubscriptionInfo? info = auth.subscription;
    final bool sw = _sw;
    final String phone = (info?.contactPhone ?? "").trim();
    final String name = (info?.businessName ?? "").trim();

    return Material(
      color: ThemeConstants.primaryBlue,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (final BuildContext context, final BoxConstraints box) => SingleChildScrollView(
            key: const ValueKey<String>("subscription_cover"),
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight - 48),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          color: Colors.amberAccent.withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.5), width: 2),
                        ),
                        child: const Icon(Icons.lock_clock, color: Colors.amberAccent, size: 42),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        sw ? "Lipia ili uendelee" : "Pay to continue",
                        key: const ValueKey<String>("subscription_cover_title"),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _message(name: name, phone: phone),
                        key: const ValueKey<String>("subscription_cover_message"),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.5),
                      ),
                      if (phone.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 22),
                        _phoneCard(phone, sw),
                      ],
                      if (info != null && !info.isOwner) ...<Widget>[
                        const SizedBox(height: 14),
                        Text(
                          sw ? "Tafadhali mjulishe mmiliki wa biashara alipie." : "Please let the owner of the business know so they can pay.",
                          key: const ValueKey<String>("subscription_cover_staff"),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ],
                      if (info?.validUntil != null) ...<Widget>[
                        const SizedBox(height: 14),
                        Text(
                          sw
                              ? "Usajili uliisha tarehe ${subscriptionDate(info!.validUntil)}."
                              : "The subscription ended on ${subscriptionDate(info!.validUntil)}.",
                          key: const ValueKey<String>("subscription_cover_ended"),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white54, fontSize: 13),
                        ),
                      ],
                      const SizedBox(height: 26),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          key: const ValueKey<String>("subscription_check"),
                          onPressed: _checking ? null : () => _check(manual: true),
                          icon: _checking
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.refresh),
                          label: Text(sw ? "Nimelipa - angalia tena" : "I have paid - check again"),
                        ),
                      ),
                      if (_stillUnpaid)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            sw ? "Malipo bado hayajarekodiwa. Jaribu tena baada ya muda mfupi." : "No payment has been recorded yet. Try again in a moment.",
                            key: const ValueKey<String>("subscription_still_unpaid"),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.amberAccent),
                          ),
                        ),
                      const SizedBox(height: 6),
                      TextButton(
                        key: const ValueKey<String>("subscription_sign_out"),
                        onPressed: () => context.read<AuthProvider>().logout(),
                        child: Text(sw ? "Toka" : "Sign out", style: const TextStyle(color: Colors.white54)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The number to pay through, large, with one tap to call it and one to copy it.
  Widget _phoneCard(final String phone, final bool sw) => Container(
        key: const ValueKey<String>("subscription_phone_card"),
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          children: <Widget>[
            Text(sw ? "Lipia kupitia namba hii" : "Pay through this number", style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 6),
            SelectableText(
              phone,
              key: const ValueKey<String>("subscription_phone"),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 1.5),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.icon(
                    key: const ValueKey<String>("subscription_call"),
                    onPressed: () => _call(phone),
                    icon: const Icon(Icons.phone_outlined, size: 18),
                    label: Text(sw ? "Piga simu" : "Call now"),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey<String>("subscription_copy"),
                    onPressed: () => _copy(phone),
                    icon: Icon(_copied ? Icons.check : Icons.copy_outlined, size: 18),
                    label: Text(_copied ? (sw ? "Imenakiliwa" : "Copied") : (sw ? "Nakili namba" : "Copy number")),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}
