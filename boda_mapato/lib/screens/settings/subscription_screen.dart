import "package:flutter/material.dart";
import "package:intl/intl.dart";

import "../../constants/theme_constants.dart";
import "../../models/business.dart";
import "../../models/subscription.dart";
import "../../services/api_service.dart";
import "../../services/localization_service.dart";
import "../../utils/server_message.dart";

/// Where the screen gets the subscription. The app uses [ApiSubscriptionSource]; tests supply a fake.
abstract class SubscriptionDataSource {
  Future<SubscriptionInfo> load();
}

class ApiSubscriptionSource implements SubscriptionDataSource {
  ApiSubscriptionSource() {
    _api.initialize();
  }

  final ApiService _api = ApiService();

  @override
  Future<SubscriptionInfo> load() async {
    final Map<String, dynamic> res = await _api.getSubscription();
    final Object? data = res["data"];
    if (data is! Map) {
      throw Exception(LocalizationService.instance.translate("the_server_s_answer_is_not"));
    }
    return SubscriptionInfo.fromJson(Map<String, dynamic>.from(data));
  }
}

/// "My subscription": the plan, when it started, when it ends, how many days are left, and what was paid.
/// The owner also sees every payment (date paid, amount, the period it covers); staff see the plan and the dates.
class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key, this.dataSource});

  final SubscriptionDataSource? dataSource;

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  late final SubscriptionDataSource _source = widget.dataSource ?? ApiSubscriptionSource();
  bool _loading = true;
  String? _error;
  SubscriptionInfo? _info;

  bool get _sw => LocalizationService.instance.isSwahili;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final SubscriptionInfo info = await _source.load();
      if (!mounted) return;
      setState(() {
        _info = info;
        _loading = false;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = readableErrorMessage(e);
      });
    }
  }

  @override
  Widget build(final BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(_sw ? "Usajili Wangu" : "My Subscription"),
      body: SafeArea(
        child: _loading && _info == null
            ? const Center(child: CircularProgressIndicator())
            : _error != null && _info == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent)),
                          const SizedBox(height: 12),
                          OutlinedButton(onPressed: _load, child: Text(_sw ? "Jaribu tena" : "Retry")),
                        ],
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: <Widget>[SubscriptionDetails(info: _info!, sw: _sw)],
                    ),
                  ),
      ),
    );
  }
}

/// The status, the dates and (for the owner) the payment history of one subscription.
class SubscriptionDetails extends StatelessWidget {
  const SubscriptionDetails({super.key, required this.info, required this.sw, this.showHistory = true});

  final SubscriptionInfo info;
  final bool sw;
  final bool showHistory;

  String _date(final DateTime? d) => subscriptionDate(d);

  String _money(final SubscriptionPayment p) => subscriptionMoney(p);

  (IconData, Color, String, String) _status() {
    final int days = info.daysLeft ?? 0;
    final String until = _date(info.validUntil);
    return switch (info.status) {
      "never" => (
          Icons.all_inclusive,
          Colors.lightBlueAccent,
          sw ? "Hakuna tarehe ya kuisha" : "No end date",
          sw ? "Mpango wako hauna tarehe ya kuisha." : "Your plan has no end date.",
        ),
      "active" => (
          Icons.check_circle_outline,
          Colors.greenAccent,
          sw ? "Unatumika" : "Active",
          sw ? "Usajili wako unatumika hadi $until (siku $days zimebaki)." : "Your subscription is active until $until ($days day(s) left).",
        ),
      "expiring" => (
          Icons.schedule,
          Colors.amberAccent,
          sw ? "Unakaribia kuisha" : "Ending soon",
          days == 0
              ? (sw ? "Usajili wako unaisha leo ($until). Lipia ili huduma isisimame." : "Your subscription ends today ($until). Pay so the service does not stop.")
              : (sw
                  ? "Usajili wako unaisha baada ya siku $days ($until). Lipia kabla ya hapo ili huduma isisimame."
                  : "Your subscription ends in $days day(s) ($until). Pay before then so the service does not stop."),
        ),
      "grace" => (
          Icons.warning_amber_rounded,
          Colors.orangeAccent,
          sw ? "Umeisha - tafadhali lipia" : "Ended - please pay",
          sw
              ? "Usajili uliisha $until. Unaweza kuendelea hadi ${_date(info.graceEndsAt)}; lipia kabla ya hapo ili huduma isisimame."
              : "The subscription ended on $until. You can keep working until ${_date(info.graceEndsAt)}; pay before then so the service is not stopped.",
        ),
      _ => (
          Icons.lock_clock,
          Colors.redAccent,
          info.blocked ? (sw ? "Huduma imesimamishwa" : "Service on hold") : (sw ? "Umeisha - tafadhali lipia" : "Ended - please pay"),
          info.blocked
              ? (sw
                  ? "Usajili uliisha $until na huduma imesimamishwa. Lipia ili uendelee; itafunguka mara moja."
                  : "The subscription ended on $until and the service is on hold. Pay to continue; it opens again at once.")
              : (sw ? "Usajili uliisha $until. Tafadhali lipia ili uendelee." : "The subscription ended on $until. Please pay to continue."),
        ),
    };
  }

  @override
  Widget build(final BuildContext context) {
    final (IconData icon, Color color, String title, String message) = _status();
    final int? days = info.daysLeft;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (info.businessName.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(info.businessName, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          ),
        Container(
          key: const ValueKey<String>("subscription_status_card"),
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.55)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, color: color, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, key: const ValueKey<String>("subscription_status_title"), style: TextStyle(color: color, fontSize: 17, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(message, key: const ValueKey<String>("subscription_status_message"), style: const TextStyle(color: Colors.white, fontSize: 13.5, height: 1.35)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ThemeConstants.buildGlassCard(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: <Widget>[
                _row("subscription_plan", sw ? "Mpango" : "Plan", businessPlanLabel(info.plan, sw: sw)),
                _row("subscription_started", sw ? "Ulianza" : "Started", _date(info.startedAt)),
                _row("subscription_ends", sw ? "Unaisha" : "Ends", info.neverExpires ? (sw ? "Hakuna" : "Never") : _date(info.validUntil)),
                if (days != null)
                  _row(
                    "subscription_days",
                    sw ? "Siku zilizobaki" : "Days left",
                    days >= 0 ? "$days" : (sw ? "Imeisha siku ${-days} zilizopita" : "Ended ${-days} day(s) ago"),
                  ),
                if (info.lastPayment != null)
                  _row(
                    "subscription_last_payment",
                    sw ? "Malipo ya mwisho" : "Last payment",
                    "${_date(info.lastPayment!.paidAt)} · ${_money(info.lastPayment!)}",
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _renewBox(),
        if (showHistory && info.isOwner) ...<Widget>[
          const SizedBox(height: 20),
          Text(sw ? "Historia ya malipo" : "Payment history", style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (info.payments.isEmpty)
            Text(
              sw ? "Hakuna malipo yaliyorekodiwa bado." : "No payments recorded yet.",
              key: const ValueKey<String>("subscription_no_payments"),
              style: const TextStyle(color: Colors.white54),
            )
          else
            for (final SubscriptionPayment p in info.payments) SubscriptionPaymentTile(payment: p, sw: sw),
        ],
      ],
    );
  }

  Widget _row(final String key, final String label, final String value) => Padding(
        key: ValueKey<String>(key),
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(flex: 4, child: Text(label, style: const TextStyle(color: ThemeConstants.textSecondary))),
            Expanded(flex: 6, child: Text(value, textAlign: TextAlign.end, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
          ],
        ),
      );

  Widget _renewBox() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(sw ? "Jinsi ya kulipia" : "How to pay", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              info.isOwner
                  ? (sw
                      ? "Lipia kisha mjulishe msimamizi. Malipo yakirekodiwa, huduma yako inaendelea mara moja na utapata ujumbe mfupi."
                      : "Pay, then tell your administrator. Once the payment is recorded your service carries on at once and you get a text message.")
                  : (sw ? "Mwombe mmiliki wa biashara alipie usajili." : "Ask the owner of the business to pay for the subscription."),
              style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.35),
            ),
            if (info.contactPhone.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  const Icon(Icons.phone_outlined, color: Colors.white54, size: 16),
                  const SizedBox(width: 6),
                  Text(info.contactPhone, key: const ValueKey<String>("subscription_contact"), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ],
              ),
            ],
          ],
        ),
      );
}

final DateFormat _dayFormat = DateFormat("dd MMM yyyy");

String subscriptionDate(final DateTime? d) => d == null ? "-" : _dayFormat.format(d);

String subscriptionMoney(final SubscriptionPayment p) => "${p.currency} ${NumberFormat("#,##0").format(p.amount)}";

/// The ways a payment can be recorded (the values the server accepts).
const List<String> kPaymentMethods = <String>["cash", "mobile_money", "bank_transfer", "cheque", "other"];

String paymentMethodLabel(final String? method, {required final bool sw}) => switch (method) {
      "cash" => sw ? "Taslimu" : "Cash",
      "mobile_money" => sw ? "Pesa za simu" : "Mobile money",
      "bank_transfer" => sw ? "Benki" : "Bank transfer",
      "cheque" => sw ? "Hundi" : "Cheque",
      "other" => sw ? "Nyingine" : "Other",
      _ => "",
    };

/// One payment: the amount, the day it was paid, the period it bought, and how it was paid.
class SubscriptionPaymentTile extends StatelessWidget {
  const SubscriptionPaymentTile({super.key, required this.payment, required this.sw});

  final SubscriptionPayment payment;
  final bool sw;

  @override
  Widget build(final BuildContext context) {
    final SubscriptionPayment p = payment;
    final String how = <String>[paymentMethodLabel(p.method, sw: sw), if ((p.reference ?? "").isNotEmpty) p.reference!]
        .where((final String s) => s.isNotEmpty)
        .join(" · ");
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ThemeConstants.buildGlassCard(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            key: ValueKey<String>("payment_${p.paidAt?.millisecondsSinceEpoch}_${p.amount}"),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(child: Text(subscriptionMoney(p), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800))),
                  Text(subscriptionDate(p.paidAt), style: const TextStyle(color: Colors.white70)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                "${sw ? "Kipindi" : "Period"}: ${subscriptionDate(p.periodStart)} - ${subscriptionDate(p.periodEnd)}",
                style: const TextStyle(color: ThemeConstants.textSecondary, fontSize: 13),
              ),
              if (how.isNotEmpty) Text(how, style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
