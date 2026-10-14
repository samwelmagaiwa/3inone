import "package:flutter/material.dart";
import "package:intl/intl.dart";

import "../../constants/theme_constants.dart";
import "../../models/business.dart";
import "../../models/plan_prices.dart";
import "../../models/subscription.dart";
import "../../services/api_service.dart";
import "../../services/localization_service.dart";
import "../../utils/plan_text.dart";
import "../../utils/server_message.dart";
import "../../widgets/dial_date_picker.dart";
import "../../widgets/scrolling_chip_row.dart";
import "../settings/subscription_screen.dart";

/// One page of businesses plus how many are expired / about to expire, and the plans on offer.
class BusinessesPage {
  const BusinessesPage({
    required this.items,
    this.total = 0,
    this.expired = 0,
    this.expiring = 0,
    this.plans = kBusinessPlans,
  });

  final List<Business> items;
  final int total;
  final int expired;
  final int expiring;
  final List<String> plans;
}

/// Where the screen gets its data. The app uses [ApiBusinessesDataSource]; tests supply a fake.
abstract class BusinessesDataSource {
  Future<BusinessesPage> load(String status, {String? query});

  /// [validUntil] null with [clearValidUntil] true means "no expiry".
  Future<void> updateBilling(String id, {String? plan, DateTime? validUntil, bool clearValidUntil = false});

  /// Every payment recorded for the business, newest first.
  Future<List<SubscriptionPayment>> payments(String id);

  /// The plans, what each covers and what it costs (set under Plans & Prices): a payment form fills the amount from it.
  Future<PlanCatalog> planCatalog();

  /// Record a payment: it moves the paid-until date on by [months] and opens a business that was held back.
  /// The owner is told by text message. Returns the subscription as it stands afterwards.
  Future<SubscriptionInfo> recordPayment(
    String id, {
    required double amount,
    String? method,
    String? reference,
    String? plan,
    int months = 1,
    DateTime? validUntil,
    String? note,
  });
}

class ApiBusinessesDataSource implements BusinessesDataSource {
  ApiBusinessesDataSource() {
    _api.initialize();
  }

  final ApiService _api = ApiService();

  @override
  Future<BusinessesPage> load(final String status, {final String? query}) async {
    final Map<String, dynamic> res = await _api.getBusinesses(status: status, query: query);
    final dynamic data = res["data"];
    final Map<dynamic, dynamic> meta = res["meta"] is Map ? res["meta"] as Map : <dynamic, dynamic>{};
    final Map<dynamic, dynamic> counts = meta["counts"] is Map ? meta["counts"] as Map : <dynamic, dynamic>{};
    return BusinessesPage(
      items: data is List
          ? data.whereType<Map>().map((final Map m) => Business.fromJson(Map<String, dynamic>.from(m))).toList()
          : <Business>[],
      total: (counts["total"] as num?)?.toInt() ?? 0,
      expired: (counts["expired"] as num?)?.toInt() ?? 0,
      expiring: (counts["expiring"] as num?)?.toInt() ?? 0,
      plans: meta["plans"] is List ? (meta["plans"] as List).map((e) => e.toString()).toList() : kBusinessPlans,
    );
  }

  @override
  Future<void> updateBilling(final String id, {final String? plan, final DateTime? validUntil, final bool clearValidUntil = false}) async {
    await _api.updateBusiness(id, plan: plan, validUntil: validUntil, clearValidUntil: clearValidUntil);
  }

  @override
  Future<PlanCatalog> planCatalog() async {
    final Map<String, dynamic> res = await _api.getPlans();
    return PlanCatalog.fromJson(Map<String, dynamic>.from(res["data"] as Map));
  }

  @override
  Future<List<SubscriptionPayment>> payments(final String id) async {
    final Map<String, dynamic> res = await _api.getBusinessPayments(id);
    final Object? data = res["data"];
    final Object? list = data is Map ? data["payments"] : data;
    return list is List
        ? list.whereType<Map>().map((final Map m) => SubscriptionPayment.fromJson(Map<String, dynamic>.from(m))).toList()
        : <SubscriptionPayment>[];
  }

  @override
  Future<SubscriptionInfo> recordPayment(
    final String id, {
    required final double amount,
    final String? method,
    final String? reference,
    final String? plan,
    final int months = 1,
    final DateTime? validUntil,
    final String? note,
  }) async {
    final Map<String, dynamic> res = await _api.recordBusinessPayment(
      id,
      amount: amount,
      method: method,
      reference: reference,
      plan: plan,
      // An exact end date says it all; otherwise the months it pays for.
      months: validUntil == null ? months : null,
      validUntil: validUntil,
      note: note,
    );
    final Object? data = res["data"];
    final Object? sub = data is Map ? data["subscription"] : null;
    return SubscriptionInfo.fromJson(sub is Map ? Map<String, dynamic>.from(sub) : <String, dynamic>{});
  }
}

/// Super admin: every business with its owner, services and plan, and the one place a plan and its
/// paid-until date are changed. An owner can never change their own.
class BusinessesScreen extends StatefulWidget {
  const BusinessesScreen({super.key, this.dataSource});

  final BusinessesDataSource? dataSource;

  @override
  State<BusinessesScreen> createState() => _BusinessesScreenState();
}

class _BusinessesScreenState extends State<BusinessesScreen> {
  final LocalizationService _loc = LocalizationService.instance;
  late final BusinessesDataSource _source = widget.dataSource ?? ApiBusinessesDataSource();
  final TextEditingController _search = TextEditingController();

  String _status = "all";
  bool _loading = true;
  String? _error;
  BusinessesPage _page = const BusinessesPage(items: <Business>[]);

  bool get _sw => _loc.isSwahili;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final BusinessesPage page = await _source.load(_status, query: _search.text);
      if (!mounted) return;
      setState(() {
        _page = page;
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

  String _serviceLabel(final String s) => switch (s) {
        "inventory" => _loc.translate("inventory_service"),
        "rental" => _loc.translate("rental_service"),
        _ => _loc.translate("transport_service"),
      };

  Future<void> _open(final Business b) async {
    bool paid = false;
    final bool? changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (final BuildContext _) => _BillingSheet(
        business: b,
        plans: _page.plans,
        source: _source,
        sw: _sw,
        onPaymentRecorded: () => paid = true,
      ),
    );
    if (((changed ?? false) || paid) && mounted) await _load();
  }

  @override
  Widget build(final BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(_sw ? "Biashara na Mipango" : "Businesses & Plans"),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                key: const ValueKey<String>("businesses_search"),
                controller: _search,
                style: const TextStyle(color: Colors.white),
                textInputAction: TextInputAction.search,
                onSubmitted: (final String _) => _load(),
                decoration: InputDecoration(
                  hintText: _sw ? "Tafuta biashara, mmiliki au TIN" : "Search business, owner or TIN",
                  hintStyle: const TextStyle(color: Colors.white38),
                  prefixIcon: const Icon(Icons.search, color: Colors.white54),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.06),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
            ),
            ScrollingChipRow(
              children: <Widget>[
                _chip("all", _sw ? "Zote" : "All", _page.total),
                _chip("expiring", _sw ? "Zinaisha karibu" : "Ending soon", _page.expiring),
                _chip("expired", _sw ? "Zilizoisha" : "Expired", _page.expired),
                _chip("no_expiry", _sw ? "Bila kikomo" : "No end date", null),
              ],
            ),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _chip(final String status, final String label, final int? count) => ScrollChoiceChip(
        key: ValueKey<String>("filter_$status"),
        label: count == null ? label : "$label ($count)",
        selected: _status == status,
        onSelected: (final bool _) {
          if (_status == status) return;
          setState(() => _status = status);
          _load();
        },
      );

  Widget _body() {
    if (_loading && _page.items.isEmpty) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
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
      );
    }
    if (_page.items.isEmpty) {
      return Center(
        child: Text(
          _sw ? "Hakuna biashara hapa." : "No businesses here.",
          key: const ValueKey<String>("businesses_empty"),
          style: const TextStyle(color: Colors.white54),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: _page.items.length,
        separatorBuilder: (final BuildContext _, final int __) => const SizedBox(height: 10),
        itemBuilder: (final BuildContext _, final int i) => _card(_page.items[i]),
      ),
    );
  }

  Widget _card(final Business b) {
    final BusinessBilling bill = b.billing;
    final Color tone = bill.isExpired ? Colors.redAccent : (bill.needsAttention() ? Colors.amberAccent : Colors.greenAccent);

    return ThemeConstants.buildGlassCard(
      onTap: () => _open(b),
      child: Padding(
        key: ValueKey<String>("business_${b.id}"),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.storefront_outlined, color: ThemeConstants.primaryOrange),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    b.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: tone.withValues(alpha: 0.5)),
                  ),
                  child: Text(businessPlanLabel(bill.plan, sw: _sw), style: TextStyle(color: tone, fontSize: 12)),
                ),
              ],
            ),
            if (b.owner != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                "${b.owner!.name}  ·  ${b.owner!.phoneNumber}${b.owner!.isActive ? "" : (_sw ? "  ·  Imesimamishwa" : "  ·  Suspended")}",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: ThemeConstants.textSecondary),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: b.services
                  .map((final String s) => Chip(
                        label: Text(_serviceLabel(s), style: const TextStyle(fontSize: 11)),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ))
                  .toList(),
            ),
            const SizedBox(height: 6),
            Text(_validity(bill), style: TextStyle(color: tone, fontSize: 12)),
            if (_planTooSmall(b)) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                _sw
                    ? "Mpango ${businessPlanLabel(bill.plan, sw: true)} unahusu huduma ${kPlanServices[bill.plan]}, biashara ina ${b.services.length}."
                    : "The ${businessPlanLabel(bill.plan, sw: false)} plan covers ${kPlanServices[bill.plan]} service${kPlanServices[bill.plan] == 1 ? "" : "s"}; this business has ${b.services.length}.",
                key: ValueKey<String>("plan_mismatch_${b.id}"),
                style: const TextStyle(color: Colors.amberAccent, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// A sold plan that holds fewer services than the business has (a trial and free have no limit).
  bool _planTooSmall(final Business b) {
    final int? limit = kPlanServices[b.billing.plan];
    return limit != null && b.services.length > limit;
  }

  String _validity(final BusinessBilling bill) {
    if (bill.validUntil == null) return _sw ? "Haina tarehe ya kuisha" : "No end date";
    final String date = DateFormat("dd MMM yyyy").format(bill.validUntil!);
    final int days = bill.daysLeft ?? 0;
    if (bill.isExpired) return _sw ? "Imeisha $date (siku ${-days} zilizopita)" : "Ended $date (${-days} day(s) ago)";
    return _sw ? "Hadi $date (siku $days)" : "Until $date ($days day(s))";
  }
}

/// Change one business's plan and paid-until date.
class _BillingSheet extends StatefulWidget {
  const _BillingSheet({
    required this.business,
    required this.plans,
    required this.source,
    required this.sw,
    required this.onPaymentRecorded,
  });

  final Business business;
  final List<String> plans;
  final BusinessesDataSource source;
  final bool sw;
  final VoidCallback onPaymentRecorded;

  @override
  State<_BillingSheet> createState() => _BillingSheetState();
}

class _BillingSheetState extends State<_BillingSheet> {
  late String _plan = widget.business.billing.plan;
  late DateTime? _validUntil = widget.business.billing.validUntil;
  bool _busy = false;
  String? _error;
  List<SubscriptionPayment>? _payments;
  String? _paymentsError;

  bool get _sw => widget.sw;

  @override
  void initState() {
    super.initState();
    _loadPayments();
  }

  Future<void> _loadPayments() async {
    try {
      final List<SubscriptionPayment> list = await widget.source.payments(widget.business.id);
      if (!mounted) return;
      setState(() {
        _payments = list;
        _paymentsError = null;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _paymentsError = readableErrorMessage(e));
    }
  }

  Future<void> _recordPayment() async {
    final SubscriptionInfo? after = await showDialog<SubscriptionInfo>(
      context: context,
      builder: (final BuildContext _) => _PaymentDialog(
        business: widget.business,
        plans: widget.plans,
        source: widget.source,
        sw: _sw,
      ),
    );
    if (after == null || !mounted) return;
    widget.onPaymentRecorded();
    setState(() {
      _validUntil = after.validUntil ?? _validUntil;
      if (after.plan.isNotEmpty) _plan = after.plan;
    });
    await _loadPayments();
  }

  /// Extend from whichever is later: today, or the current end date (so paying early loses nothing).
  void _extend(final int days) {
    final DateTime today = DateUtils.dateOnly(DateTime.now());
    final DateTime base = (_validUntil != null && _validUntil!.isAfter(today)) ? DateUtils.dateOnly(_validUntil!) : today;
    setState(() => _validUntil = base.add(Duration(days: days)));
  }

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDialDatePicker(
      context,
      initialDate: _validUntil != null && _validUntil!.isAfter(now) ? _validUntil! : now.add(const Duration(days: 30)),
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 3650)),
      sw: _sw,
    );
    if (picked != null) setState(() => _validUntil = picked);
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.source.updateBilling(
        widget.business.id,
        plan: _plan,
        validUntil: _validUntil,
        clearValidUntil: _validUntil == null,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = readableErrorMessage(e);
      });
    }
  }

  @override
  Widget build(final BuildContext context) {
    final Business b = widget.business;
    final DateFormat fmt = DateFormat("dd MMM yyyy");

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (final BuildContext _, final ScrollController controller) => DecoratedBox(
        decoration: const BoxDecoration(
          color: ThemeConstants.primaryBlue,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: <Widget>[
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text(b.name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            if (b.owner != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text("${b.owner!.name} · ${b.owner!.email}", style: const TextStyle(color: Colors.white60)),
              ),
            if (b.tin.isNotEmpty) Text("TIN ${b.tin}", style: const TextStyle(color: Colors.white54, fontSize: 13)),
            const Divider(color: Colors.white24, height: 32),
            Text(_sw ? "Mpango" : "Plan", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.plans
                  .map((final String p) => ChoiceChip(
                        key: ValueKey<String>("plan_$p"),
                        label: Text(businessPlanLabel(p, sw: _sw)),
                        selected: _plan == p,
                        onSelected: _busy ? null : (final bool _) => setState(() => _plan = p),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 20),
            Text(_sw ? "Imelipiwa hadi" : "Paid until", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              _validUntil == null ? (_sw ? "Hakuna tarehe ya kuisha" : "No end date") : fmt.format(_validUntil!),
              key: const ValueKey<String>("billing_valid_until"),
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final int d in <int>[30, 90, 365])
                  OutlinedButton(
                    key: ValueKey<String>("extend_$d"),
                    onPressed: _busy ? null : () => _extend(d),
                    child: Text(_sw ? "+ siku $d" : "+ $d days"),
                  ),
                OutlinedButton(
                  key: const ValueKey<String>("billing_pick_date"),
                  onPressed: _busy ? null : _pickDate,
                  child: Text(_sw ? "Tarehe nyingine" : "Custom date"),
                ),
                OutlinedButton(
                  key: const ValueKey<String>("billing_no_expiry"),
                  onPressed: _busy ? null : () => setState(() => _validUntil = null),
                  child: Text(_sw ? "Bila kikomo" : "No end date"),
                ),
              ],
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(_error!, key: const ValueKey<String>("billing_error"), style: const TextStyle(color: Colors.redAccent)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              key: const ValueKey<String>("billing_save"),
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(_sw ? "Hifadhi" : "Save"),
            ),
            const Divider(color: Colors.white24, height: 40),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    _sw ? "Malipo" : "Payments",
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                FilledButton.icon(
                  key: const ValueKey<String>("record_payment"),
                  onPressed: _busy ? null : _recordPayment,
                  icon: const Icon(Icons.add_card_outlined, size: 18),
                  label: Text(_sw ? "Rekodi malipo" : "Record payment"),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _sw
                  ? "Malipo yakirekodiwa, tarehe ya kuisha inasogezwa mbele, huduma inafunguka na mmiliki anatumiwa ujumbe."
                  : "Recording a payment moves the end date on, opens the service if it was on hold, and texts the owner.",
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 10),
            if (_paymentsError != null)
              Text(_paymentsError!, key: const ValueKey<String>("payments_error"), style: const TextStyle(color: Colors.redAccent))
            else if (_payments == null)
              const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
            else if (_payments!.isEmpty)
              Text(
                _sw ? "Hakuna malipo yaliyorekodiwa bado." : "No payments recorded yet.",
                key: const ValueKey<String>("payments_empty"),
                style: const TextStyle(color: Colors.white54),
              )
            else
              for (final SubscriptionPayment p in _payments!) SubscriptionPaymentTile(payment: p, sw: _sw),
          ],
        ),
      ),
    );
  }
}

/// Record one payment for a business. The server moves the end date on and texts the owner; this form shows the
/// server's answer (a wrong amount, say) in place and closes only when the payment was recorded.
class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.business, required this.plans, required this.source, required this.sw});

  final Business business;
  final List<String> plans;
  final BusinessesDataSource source;
  final bool sw;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _reference = TextEditingController();
  final TextEditingController _note = TextEditingController();
  String _method = "mobile_money";
  int _months = 1;

  /// A chosen end date instead of a number of months.
  DateTime? _until;

  /// The price list. Until the server has answered, what each plan covers is known and the prices are not.
  PlanCatalog _catalog = PlanCatalog.fallback;
  late String _plan = _initialPlan();

  /// Has the person typed the amount themselves? Then the price list no longer overwrites it.
  bool _amountEdited = false;
  bool _busy = false;
  String? _error;

  bool get _sw => widget.sw;

  /// How many services this business has: the plan has to cover them.
  int get _servicesCount => widget.business.services.length;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  /// Ask for the price list; without an answer the form simply has no prices to fill in.
  Future<void> _loadCatalog() async {
    try {
      final PlanCatalog catalog = await widget.source.planCatalog();
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _applyPrice();
      });
    } on Exception catch (_) {
      // no price list: the amount is typed
    }
  }

  /// Fill the amount from the price list for the plan and months chosen, unless the person typed their own.
  void _applyPrice() {
    if (_amountEdited || _until != null) return;
    final double? price = _catalog.priceFor(_plan, _months);
    _amount.text = price == null ? "" : (price == price.roundToDouble() ? "${price.round()}" : "$price");
  }

  /// A trial or a free plan is not something a payment buys.
  List<String> get _paidPlans => widget.plans.where((final String p) => p != "trial" && p != "free").toList();

  /// The plan the business is on when it covers its services, else the smallest one that does.
  String _initialPlan() {
    final String current = widget.business.billing.plan;
    if (_paidPlans.contains(current) && _catalog.covers(current, _servicesCount)) return current;
    final String fit = _catalog.planFor(_servicesCount);
    if (_paidPlans.contains(fit)) return fit;
    return _paidPlans.isNotEmpty ? _paidPlans.last : current;
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _chooseEndDate() async {
    final DateTime today = DateUtils.dateOnly(DateTime.now());
    final DateTime? picked = await showDialDatePicker(
      context,
      initialDate: _until ?? today.add(const Duration(days: 30)),
      firstDate: today.add(const Duration(days: 1)),
      lastDate: today.add(const Duration(days: 3650)),
      sw: _sw,
    );
    if (picked != null && mounted) setState(() => _until = picked);
  }

  String _covers() {
    if (_until != null) return _sw ? "Hadi ${dialDateLabel(_until!, sw: true)}" : "Until ${dialDateLabel(_until!, sw: false)}";
    return _months == 12 ? (_sw ? "Mwaka 1" : "1 year") : (_sw ? "Miezi $_months" : "$_months month(s)");
  }

  Future<void> _submit() async {
    final double? amount = double.tryParse(_amount.text.replaceAll(",", "").trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = _sw ? "Weka kiasi kilicholipwa." : "Enter the amount that was paid.");
      return;
    }

    // Money is being recorded and the owner is texted: ask once more, with everything in front of the person.
    final bool? sure = await showDialog<bool>(
      context: context,
      builder: (final BuildContext _) => _ConfirmPaymentDialog(
        business: widget.business.name,
        amount: "TZS ${NumberFormat("#,##0").format(amount)}",
        method: paymentMethodLabel(_method, sw: _sw),
        covers: _covers(),
        plan: businessPlanLabel(_plan, sw: _sw),
        sw: _sw,
      ),
    );
    if (sure != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final SubscriptionInfo after = await widget.source.recordPayment(
        widget.business.id,
        amount: amount,
        method: _method,
        reference: _reference.text,
        plan: _plan,
        months: _months,
        validUntil: _until,
        note: _note.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(after);
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = readableErrorMessage(e);
      });
    }
  }

  InputDecoration _decoration(final String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white60),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      );

  /// Under the amount: what the price list says for the plan and months chosen (and a way back to it after typing
  /// another), or that there is none.
  Widget _priceHint() {
    final String plan = businessPlanLabel(_plan, sw: _sw);
    if (_until != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 4, left: 4),
        child: Text(
          _sw ? "Tarehe nyingine: weka kiasi kilicholipwa." : "Custom date: enter the amount that was paid.",
          key: const ValueKey<String>("payment_price_hint"),
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      );
    }
    final double? price = _catalog.priceFor(_plan, _months);
    final String period = periodText(_months, sw: _sw).toLowerCase();
    if (price == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 4, left: 4),
        child: Text(
          _sw ? "Bei ya $plan kwa $period bado haijawekwa kwenye Mipango na Bei." : "No price is set for $plan for $period in Plans & Prices.",
          key: const ValueKey<String>("payment_price_hint"),
          style: const TextStyle(color: Colors.white38, fontSize: 12),
        ),
      );
    }
    final bool differs = (double.tryParse(_amount.text.replaceAll(",", "").trim()) ?? price) != price;
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              _sw ? "Bei ya orodha: ${moneyText(_catalog.currency, price)} ($plan, $period)" : "Price list: ${moneyText(_catalog.currency, price)} ($plan, $period)",
              key: const ValueKey<String>("payment_price_hint"),
              style: TextStyle(color: differs ? Colors.amberAccent : Colors.greenAccent, fontSize: 12),
            ),
          ),
          if (differs)
            TextButton(
              key: const ValueKey<String>("payment_use_list_price"),
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _amountEdited = false;
                        _applyPrice();
                      }),
              child: Text(_sw ? "Tumia" : "Use it"),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(final BuildContext context) {
    return AlertDialog(
      backgroundColor: ThemeConstants.primaryBlue,
      title: Text(
        _sw ? "Rekodi malipo - ${widget.business.name}" : "Record payment - ${widget.business.name}",
        style: const TextStyle(color: Colors.white, fontSize: 17),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (_paidPlans.isNotEmpty) ...<Widget>[
              Text(_sw ? "Mpango" : "Plan", style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final String p in _paidPlans)
                    ChoiceChip(
                      key: ValueKey<String>("payment_plan_$p"),
                      label: Text(
                        _catalog.servicesIncluded(p) == null
                            ? businessPlanLabel(p, sw: _sw)
                            : "${businessPlanLabel(p, sw: _sw)} · ${_catalog.servicesIncluded(p)}",
                      ),
                      selected: _plan == p,
                      // a plan that holds fewer services than the business has cannot be chosen
                      onSelected: (_busy || !_catalog.covers(p, _servicesCount))
                          ? null
                          : (final bool _) => setState(() {
                                _plan = p;
                                _applyPrice();
                              }),
                    ),
                ],
              ),
              if (_servicesCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _sw
                        ? "Biashara hii ina huduma $_servicesCount: mpango unaotosha ni ${businessPlanLabel(_catalog.planFor(_servicesCount), sw: true)} au zaidi."
                        : "This business has $_servicesCount service${_servicesCount == 1 ? "" : "s"}: the plan has to be ${businessPlanLabel(_catalog.planFor(_servicesCount), sw: false)} or bigger.",
                    key: const ValueKey<String>("payment_plan_note"),
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 14),
            ],
            Text(_sw ? "Inalipia muda gani" : "Time it pays for", style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final int m in <int>[1, 3, 6, 12])
                  ChoiceChip(
                    key: ValueKey<String>("payment_months_$m"),
                    label: Text(m == 12 ? (_sw ? "Mwaka 1" : "1 year") : (_sw ? "Miezi $m" : "$m month(s)")),
                    selected: _until == null && _months == m,
                    onSelected: _busy
                        ? null
                        : (final bool _) => setState(() {
                              _months = m;
                              _until = null;
                              _applyPrice();
                            }),
                  ),
                ChoiceChip(
                  key: const ValueKey<String>("payment_custom_date"),
                  avatar: const Icon(Icons.event_outlined, size: 18),
                  label: Text(_until == null ? (_sw ? "Tarehe nyingine" : "Custom date") : _covers()),
                  selected: _until != null,
                  onSelected: _busy ? null : (final bool _) => _chooseEndDate(),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey<String>("payment_amount"),
              controller: _amount,
              enabled: !_busy,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white),
              onChanged: (final String v) => setState(() => _amountEdited = v.trim().isNotEmpty),
              decoration: _decoration(_sw ? "Kiasi kilicholipwa (TZS)" : "Amount paid (TZS)"),
            ),
            _priceHint(),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const ValueKey<String>("payment_method"),
              initialValue: _method,
              isExpanded: true,
              dropdownColor: ThemeConstants.bgBottom,
              style: const TextStyle(color: Colors.white),
              decoration: _decoration(_sw ? "Njia ya malipo" : "How it was paid"),
              items: <DropdownMenuItem<String>>[
                for (final String m in kPaymentMethods) DropdownMenuItem<String>(value: m, child: Text(paymentMethodLabel(m, sw: _sw))),
              ],
              onChanged: _busy ? null : (final String? m) => setState(() => _method = m ?? _method),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey<String>("payment_reference"),
              controller: _reference,
              enabled: !_busy,
              style: const TextStyle(color: Colors.white),
              decoration: _decoration(_sw ? "Namba ya muamala (si lazima)" : "Transaction reference (optional)"),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey<String>("payment_note"),
              controller: _note,
              enabled: !_busy,
              style: const TextStyle(color: Colors.white),
              decoration: _decoration(_sw ? "Maelezo (si lazima)" : "Note (optional)"),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(_error!, key: const ValueKey<String>("payment_error"), style: const TextStyle(color: Colors.redAccent)),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          key: const ValueKey<String>("payment_cancel"),
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(_sw ? "Ghairi" : "Cancel"),
        ),
        FilledButton(
          key: const ValueKey<String>("payment_submit"),
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(_sw ? "Rekodi" : "Record"),
        ),
      ],
    );
  }
}

/// "Record this payment?" with what is about to be recorded, and a plain NO / YES.
class _ConfirmPaymentDialog extends StatelessWidget {
  const _ConfirmPaymentDialog({
    required this.business,
    required this.amount,
    required this.method,
    required this.covers,
    required this.plan,
    required this.sw,
  });

  final String business;
  final String amount;
  final String method;
  final String covers;
  final String plan;
  final bool sw;

  Widget _line(final String label, final String value, final String key) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(flex: 4, child: Text(label, style: const TextStyle(color: Colors.white60, fontSize: 13))),
            Expanded(flex: 6, child: Text(value, key: ValueKey<String>(key), textAlign: TextAlign.end, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
          ],
        ),
      );

  @override
  Widget build(final BuildContext context) {
    return AlertDialog(
      key: const ValueKey<String>("confirm_payment"),
      backgroundColor: ThemeConstants.primaryBlue,
      title: Text(sw ? "Thibitisha malipo" : "Confirm the payment", style: const TextStyle(color: Colors.white, fontSize: 18)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _line(sw ? "Biashara" : "Business", business, "confirm_business"),
            _line(sw ? "Kiasi" : "Amount", amount, "confirm_amount"),
            _line(sw ? "Njia" : "How", method, "confirm_method"),
            _line(sw ? "Inalipia" : "Pays for", covers, "confirm_covers"),
            _line(sw ? "Mpango" : "Plan", plan, "confirm_plan"),
            const Divider(color: Colors.white24, height: 24),
            Text(
              sw ? "Rekodi malipo haya? Mmiliki atatumiwa ujumbe wa uthibitisho." : "Record this payment? The owner is sent a text to confirm it.",
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(key: const ValueKey<String>("confirm_no"), onPressed: () => Navigator.of(context).pop(false), child: Text(sw ? "Hapana" : "No")),
        FilledButton(key: const ValueKey<String>("confirm_yes"), onPressed: () => Navigator.of(context).pop(true), child: Text(sw ? "Ndiyo" : "Yes")),
      ],
    );
  }
}
