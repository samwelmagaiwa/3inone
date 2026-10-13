import "package:flutter/material.dart";
import "package:intl/intl.dart";

import "../../constants/theme_constants.dart";
import "../../models/business.dart";
import "../../services/api_service.dart";
import "../../services/localization_service.dart";

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
        _error = e.toString().replaceFirst(RegExp(r"^(Api)?Exception: "), "");
      });
    }
  }

  String _serviceLabel(final String s) => switch (s) {
        "inventory" => _loc.translate("inventory_service"),
        "rental" => _loc.translate("rental_service"),
        _ => _loc.translate("transport_service"),
      };

  Future<void> _open(final Business b) async {
    final bool? changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (final BuildContext _) => _BillingSheet(business: b, plans: _page.plans, source: _source, sw: _sw),
    );
    if ((changed ?? false) && mounted) await _load();
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
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: <Widget>[
                  _chip("all", _sw ? "Zote" : "All", _page.total),
                  _chip("expiring", _sw ? "Zinaisha karibu" : "Ending soon", _page.expiring),
                  _chip("expired", _sw ? "Zilizoisha" : "Expired", _page.expired),
                  _chip("no_expiry", _sw ? "Bila kikomo" : "No end date", null),
                ],
              ),
            ),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _chip(final String status, final String label, final int? count) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          key: ValueKey<String>("filter_$status"),
          label: Text(count == null ? label : "$label ($count)"),
          selected: _status == status,
          onSelected: (final bool _) {
            if (_status == status) return;
            setState(() => _status = status);
            _load();
          },
        ),
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
          ],
        ),
      ),
    );
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
  const _BillingSheet({required this.business, required this.plans, required this.source, required this.sw});

  final Business business;
  final List<String> plans;
  final BusinessesDataSource source;
  final bool sw;

  @override
  State<_BillingSheet> createState() => _BillingSheetState();
}

class _BillingSheetState extends State<_BillingSheet> {
  late String _plan = widget.business.billing.plan;
  late DateTime? _validUntil = widget.business.billing.validUntil;
  bool _busy = false;
  String? _error;

  bool get _sw => widget.sw;

  /// Extend from whichever is later: today, or the current end date (so paying early loses nothing).
  void _extend(final int days) {
    final DateTime today = DateUtils.dateOnly(DateTime.now());
    final DateTime base = (_validUntil != null && _validUntil!.isAfter(today)) ? DateUtils.dateOnly(_validUntil!) : today;
    setState(() => _validUntil = base.add(Duration(days: days)));
  }

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _validUntil != null && _validUntil!.isAfter(now) ? _validUntil! : now.add(const Duration(days: 30)),
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 3650)),
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
        _error = e.toString().replaceFirst(RegExp(r"^(Api)?Exception: "), "");
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
          color: Color(0xFF001D3D),
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
                  child: Text(_sw ? "Chagua tarehe" : "Pick a date"),
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
          ],
        ),
      ),
    );
  }
}
