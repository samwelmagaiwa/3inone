import "package:flutter/material.dart";
import "package:intl/intl.dart";

import "../../constants/theme_constants.dart";
import "../../models/business.dart";
import "../../models/business_registration.dart";
import "../../models/plan_prices.dart";
import "../../modules/inventory/models/inv_capabilities.dart";
import "../../services/api_service.dart";
import "../../services/localization_service.dart";
import "../../utils/plan_text.dart";
import "../../utils/server_message.dart";
import "../../widgets/dial_date_picker.dart";
import "../../widgets/scrolling_chip_row.dart";

/// One page of registrations plus how many exist in each state.
class RegistrationsPage {
  const RegistrationsPage({required this.items, required this.counts});

  final List<BusinessRegistration> items;
  final Map<String, int> counts;
}

/// Where the screen gets its data. The app uses [ApiRegistrationsDataSource];
/// tests supply a fake so no network is needed.
abstract class RegistrationsDataSource {
  Future<RegistrationsPage> load(String status, {String? query});
  Future<void> approve(
    String id,
    List<String> services, {
    bool allowUnverified = false,
    String? plan,
    DateTime? validUntil,
    String? inventoryType,
  });
  Future<void> reject(String id, String reason);
}

class ApiRegistrationsDataSource implements RegistrationsDataSource {
  ApiRegistrationsDataSource() {
    _api.initialize();
  }

  final ApiService _api = ApiService();

  @override
  Future<RegistrationsPage> load(final String status, {final String? query}) async {
    final Map<String, dynamic> res =
        await _api.getBusinessRegistrations(status: status, query: query);
    final dynamic data = res["data"];
    final List<BusinessRegistration> items = data is List
        ? data
            .whereType<Map>()
            .map((final Map m) => BusinessRegistration.fromJson(Map<String, dynamic>.from(m)))
            .toList()
        : <BusinessRegistration>[];
    final dynamic rawCounts = (res["meta"] is Map) ? (res["meta"] as Map)["counts"] : null;
    final Map<String, int> counts = <String, int>{
      for (final String s in <String>["pending", "approved", "rejected"])
        s: rawCounts is Map ? ((rawCounts[s] as num?)?.toInt() ?? 0) : 0,
    };
    return RegistrationsPage(items: items, counts: counts);
  }

  @override
  Future<void> approve(
    final String id,
    final List<String> services, {
    final bool allowUnverified = false,
    final String? plan,
    final DateTime? validUntil,
    final String? inventoryType,
  }) async {
    await _api.approveBusinessRegistration(id, services,
        allowUnverified: allowUnverified, plan: plan, validUntil: validUntil, inventoryType: inventoryType);
  }

  @override
  Future<void> reject(final String id, final String reason) async {
    await _api.rejectBusinessRegistration(id, reason);
  }
}

/// Super admin: see who has registered, read their details, and give them the
/// services (or turn them down). Approving switches the owner's login on with
/// exactly the services chosen here.
class RegistrationsScreen extends StatefulWidget {
  const RegistrationsScreen({super.key, this.dataSource});

  final RegistrationsDataSource? dataSource;

  @override
  State<RegistrationsScreen> createState() => _RegistrationsScreenState();
}

class _RegistrationsScreenState extends State<RegistrationsScreen> {
  final LocalizationService _loc = LocalizationService.instance;
  late final RegistrationsDataSource _source = widget.dataSource ?? ApiRegistrationsDataSource();
  final TextEditingController _search = TextEditingController();

  String _status = BusinessRegistration.pending;
  bool _loading = true;
  String? _error;
  RegistrationsPage _page = const RegistrationsPage(items: <BusinessRegistration>[], counts: <String, int>{});

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
      final RegistrationsPage page = await _source.load(_status, query: _search.text);
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

  Future<void> _open(final BusinessRegistration r) async {
    final bool? changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (final BuildContext _) => _RegistrationSheet(
        registration: r,
        source: _source,
        serviceLabel: _serviceLabel,
        sw: _sw,
      ),
    );
    if ((changed ?? false) && mounted) {
      await _load();
    }
  }

  /// Gives the applicant exactly the services they asked for, on the default trial plan, after one question.
  /// (Opening the request instead lets the super admin change the services or the plan first.)
  Future<void> _approveAsRequested(final BusinessRegistration r) async {
    final List<String> services = kBusinessServices.where(r.requestedServices.contains).toList();
    if (services.isEmpty) return;
    final String names = services.map(_serviceLabel).join(", ");

    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (final BuildContext ctx) => AlertDialog(
        key: const ValueKey<String>("approve_as_requested_dialog"),
        title: Text(_sw ? "Idhinisha ${r.businessName}?" : "Approve ${r.businessName}?"),
        content: Text(
          _sw
              ? "Akaunti ya ${r.ownerName} itawashwa na atapewa: $names. Itaanza na kipindi cha majaribio. Atatumiwa ujumbe aingie."
              : "${r.ownerName}'s account will be switched on with: $names. It starts on a free trial, and they are told to sign in.",
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_sw ? "Ghairi" : "Cancel")),
          FilledButton(
            key: const ValueKey<String>("approve_as_requested_confirm"),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_sw ? "Idhinisha" : "Approve"),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;

    bool allowUnverified = false;
    if (!r.ownerPhoneVerified) {
      if (!await _askApproveUnverified(context, r, _sw) || !mounted) return;
      allowUnverified = true;
    }

    try {
      await _source.approve(
        r.id,
        services,
        allowUnverified: allowUnverified,
        plan: "trial",
        inventoryType: services.contains("inventory") ? r.inventoryType : null,
      );
      if (!mounted) return;
      ThemeConstants.showSuccessSnackBar(
        context,
        _sw ? "${r.businessName} imeidhinishwa." : "${r.businessName} is approved.",
      );
      await _load();
    } on Exception catch (e) {
      if (!mounted) return;
      ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  @override
  Widget build(final BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(_sw ? "Usajili wa Biashara" : "Business Registrations"),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                controller: _search,
                style: const TextStyle(color: Colors.white),
                textInputAction: TextInputAction.search,
                onSubmitted: (final String _) => _load(),
                decoration: InputDecoration(
                  hintText: _sw ? "Tafuta jina, simu au biashara" : "Search name, phone or business",
                  hintStyle: const TextStyle(color: Colors.white38),
                  prefixIcon: const Icon(Icons.search, color: Colors.white54),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.06),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            ScrollingChipRow(
              children: <Widget>[
                _chip(BusinessRegistration.pending, _sw ? "Zinazosubiri" : "Pending"),
                _chip(BusinessRegistration.approved, _sw ? "Zilizokubaliwa" : "Approved"),
                _chip(BusinessRegistration.rejected, _sw ? "Zilizokataliwa" : "Rejected"),
              ],
            ),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _chip(final String status, final String label) {
    final int? count = _page.counts[status];
    return ScrollChoiceChip(
      key: ValueKey<String>("status_$status"),
      label: count == null ? label : "$label ($count)",
      selected: _status == status,
      onSelected: (final bool _) {
        if (_status == status) return;
        setState(() => _status = status);
        _load();
      },
    );
  }

  Widget _body() {
    if (_loading && _page.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
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
          key: const ValueKey<String>("registrations_empty"),
          _status == BusinessRegistration.pending
              ? (_sw ? "Hakuna usajili unaosubiri." : "No registrations waiting.")
              : (_sw ? "Hakuna usajili hapa." : "Nothing here."),
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

  Widget _card(final BusinessRegistration r) {
    final DateFormat fmt = DateFormat("dd MMM yyyy, HH:mm");
    return ThemeConstants.buildGlassCard(
      onTap: () => _open(r),
      child: Padding(
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
                    r.businessName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                _statusBadge(r.status),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              "${r.ownerName}  ·  ${r.ownerPhone}",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: ThemeConstants.textSecondary),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: (r.isPending || r.status == BusinessRegistration.rejected
                      ? r.requestedServices
                      : r.assignedServices)
                  .map((final String s) => Chip(
                        label: Text(_serviceLabel(s), style: const TextStyle(fontSize: 11)),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ))
                  .toList(),
            ),
            if (r.submittedAt != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                (_sw ? "Imetumwa " : "Submitted ") + fmt.format(r.submittedAt!),
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
            if (r.isPending && r.requestedServices.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton.icon(
                      key: ValueKey<String>("approve_as_requested_${r.id}"),
                      onPressed: () => _approveAsRequested(r),
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      label: Text(_sw ? "Idhinisha kama alivyoomba" : "Approve as requested"),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    key: ValueKey<String>("review_${r.id}"),
                    onPressed: () => _open(r),
                    child: Text(_sw ? "Kagua" : "Review"),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(final String status) {
    final (String, Color) v = switch (status) {
      BusinessRegistration.approved => (_sw ? "Imekubaliwa" : "Approved", Colors.greenAccent),
      BusinessRegistration.rejected => (_sw ? "Imekataliwa" : "Rejected", Colors.redAccent),
      _ => (_sw ? "Inasubiri" : "Pending", Colors.amberAccent),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: v.$2.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: v.$2.withValues(alpha: 0.5)),
      ),
      child: Text(v.$1, style: TextStyle(color: v.$2, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

/// Anyone can type any email into the form. If the applicant never confirmed the phone number with the texted
/// code, the super admin must decide that on purpose. True means "approve anyway".
Future<bool> _askApproveUnverified(final BuildContext context, final BusinessRegistration r, final bool sw) async {
  final bool? anyway = await showDialog<bool>(
    context: context,
    builder: (final BuildContext ctx) => AlertDialog(
      key: const ValueKey<String>("unverified_dialog"),
      title: Text(sw ? "Simu haijathibitishwa" : "Phone not confirmed"),
      content: Text(
        sw
            ? "${r.ownerName} hajathibitisha namba ${r.ownerPhone} kwa nambari iliyotumwa. Idhinisha tu kama umemthibitisha mwenyewe (mfano kwa kumpigia simu)."
            : "${r.ownerName} has not confirmed ${r.ownerPhone} with the texted code. Approve only if you have checked them yourself (for example by phoning them).",
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(sw ? "Ghairi" : "Cancel")),
        FilledButton(
          key: const ValueKey<String>("approve_unverified_confirm"),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(sw ? "Idhinisha hata hivyo" : "Approve anyway"),
        ),
      ],
    ),
  );
  return anyway == true;
}

/// Full details of one registration, with the approve / reject actions.
class _RegistrationSheet extends StatefulWidget {
  const _RegistrationSheet({
    required this.registration,
    required this.source,
    required this.serviceLabel,
    required this.sw,
  });

  final BusinessRegistration registration;
  final RegistrationsDataSource source;
  final String Function(String) serviceLabel;
  final bool sw;

  @override
  State<_RegistrationSheet> createState() => _RegistrationSheetState();
}

class _RegistrationSheetState extends State<_RegistrationSheet> {
  late final Set<String> _grant = <String>{...widget.registration.requestedServices};
  // What the business starts on. A trial (the server sets its length) unless chosen otherwise.
  String _plan = "trial";
  DateTime? _validUntil;
  // The kind of stock business (retail, wholesale, ...): what the applicant chose, which the super admin may correct.
  late String? _inventoryType = widget.registration.inventoryType;
  // Owned by the sheet, not the dialog: the dialog is still animating out when
  // showDialog returns, so disposing a controller there crashes its text field.
  final TextEditingController _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  BusinessRegistration get _r => widget.registration;
  bool get _sw => widget.sw;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  /// The smallest sold plan that holds the services being given.
  String _betterPlan() => PlanCatalog.fallback.planFor(_grant.length);

  Future<void> _approve() async {
    if (_grant.isEmpty) {
      setState(() => _error = _sw ? "Chagua angalau huduma moja ya kumpa." : "Choose at least one service to give.");
      return;
    }
    if (_planTooSmall) {
      setState(() => _error = planTooSmallText(_plan, kPlanServices[_plan]!, _grant.length, _betterPlan(), sw: _sw));
      return;
    }
    final List<String> services = kBusinessServices.where(_grant.contains).toList();

    // Anyone can type any email into the form. If the applicant never confirmed the phone
    // number with the texted code, the super admin must decide that on purpose.
    bool allowUnverified = false;
    if (!_r.ownerPhoneVerified) {
      if (!await _askApproveUnverified(context, _r, _sw)) return;
      allowUnverified = true;
    }

    await _run(() => widget.source.approve(
          _r.id,
          services,
          allowUnverified: allowUnverified,
          plan: _plan,
          validUntil: _validUntil,
          inventoryType: _grant.contains("inventory") ? _inventoryType : null,
        ));
  }

  Future<void> _pickValidUntil() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDialDatePicker(
      context,
      initialDate: _validUntil ?? now.add(const Duration(days: 30)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 3650)),
      sw: _sw,
    );
    if (picked != null) setState(() => _validUntil = picked);
  }

  Future<void> _reject() async {
    _reason.clear();
    final String? text = await showDialog<String>(
      context: context,
      builder: (final BuildContext ctx) => AlertDialog(
        title: Text(_sw ? "Kataa usajili" : "Reject registration"),
        content: TextField(
          key: const ValueKey<String>("reject_reason"),
          controller: _reason,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: _sw ? "Sababu (itaonekana kwa mwombaji)" : "Reason (the applicant will see it)",
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_sw ? "Ghairi" : "Cancel")),
          FilledButton(
            key: const ValueKey<String>("reject_confirm"),
            onPressed: () => Navigator.pop(ctx, _reason.text.trim()),
            child: Text(_sw ? "Kataa" : "Reject"),
          ),
        ],
      ),
    );
    if (text == null) return;
    if (text.isEmpty) {
      setState(() => _error = _sw ? "Andika sababu ya kukataa." : "Please give a reason for rejecting.");
      return;
    }
    await _run(() => widget.source.reject(_r.id, text));
  }

  Future<void> _run(final Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
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
    final DateFormat fmt = DateFormat("dd MMM yyyy, HH:mm");
    final bool actionable = _r.status != BusinessRegistration.approved;

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
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
            Text(_r.businessName, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _row(Icons.person_outline, _sw ? "Mmiliki" : "Owner", _r.ownerName),
            _row(Icons.email_outlined, _sw ? "Barua pepe" : "Email", _r.ownerEmail),
            _row(Icons.phone_android_outlined, _sw ? "Simu" : "Phone", _r.ownerPhone),
            _row(
              _r.ownerPhoneVerified ? Icons.verified_outlined : Icons.warning_amber_rounded,
              _sw ? "Uthibitisho wa simu" : "Phone check",
              _r.ownerPhoneVerified
                  ? (_sw ? "Imethibitishwa kwa nambari" : "Confirmed with the texted code")
                  : (_sw ? "Haijathibitishwa" : "Not confirmed"),
            ),
            if (_r.location.isNotEmpty) _row(Icons.place_outlined, _sw ? "Mahali" : "Location", _r.location),
            if ((_r.idNumber ?? "").isNotEmpty) _row(Icons.badge_outlined, _sw ? "Kitambulisho" : "ID number", _r.idNumber!),
            if ((_r.notes ?? "").isNotEmpty) _row(Icons.notes_outlined, _sw ? "Maelezo" : "Notes", _r.notes!),
            if (_r.submittedAt != null) _row(Icons.schedule, _sw ? "Imetumwa" : "Submitted", fmt.format(_r.submittedAt!)),
            _row(
              Icons.checklist_rtl,
              _sw ? "Huduma alizoomba" : "Services requested",
              _r.requestedServices.map(widget.serviceLabel).join(", "),
            ),
            if ((_r.requestedPlan ?? "").isNotEmpty)
              _row(Icons.sell_outlined, _sw ? "Kifurushi alichochagua" : "Package chosen", _packageText(), valueKey: "requested_package"),
            if ((_r.inventoryType ?? "").isNotEmpty)
              _row(Icons.category_outlined, _sw ? "Aina ya biashara" : "Kind of business", inventoryTypeLabel(_r.inventoryType!, sw: _sw)),
            if (_r.status == BusinessRegistration.approved) ...<Widget>[
              _row(Icons.verified_outlined, _sw ? "Huduma alizopewa" : "Services given", _r.assignedServices.map(widget.serviceLabel).join(", ")),
              if (_r.reviewedBy != null) _row(Icons.how_to_reg_outlined, _sw ? "Aliyekubali" : "Approved by", _r.reviewedBy!),
            ],
            if (_r.status == BusinessRegistration.rejected && (_r.rejectionReason ?? "").isNotEmpty)
              _row(Icons.block, _sw ? "Sababu ya kukataa" : "Rejection reason", _r.rejectionReason!),
            if (actionable) ...<Widget>[
              const Divider(color: Colors.white24, height: 32),
              Text(
                _sw ? "Mpe huduma hizi" : "Give these services",
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: kBusinessServices
                    .map((final String s) => FilterChip(
                          key: ValueKey<String>("grant_$s"),
                          label: Text(widget.serviceLabel(s)),
                          selected: _grant.contains(s),
                          onSelected: _busy
                              ? null
                              : (final bool on) => setState(() {
                                    on ? _grant.add(s) : _grant.remove(s);
                                    _error = null;
                                  }),
                        ))
                    .toList(),
              ),
              if (_grant.contains("inventory")) ...<Widget>[
                const SizedBox(height: 16),
                Text(
                  _sw ? "Aina ya biashara ya bidhaa" : "Kind of stock business",
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: kInventoryTypes
                      .map((final String t) => ChoiceChip(
                            key: ValueKey<String>("inv_type_$t"),
                            label: Text(inventoryTypeLabel(t, sw: _sw)),
                            selected: _inventoryType == t,
                            onSelected: _busy ? null : (final bool _) => setState(() => _inventoryType = t),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 6),
                Text(
                  _inventoryType == null
                      ? (_sw ? "Haijachaguliwa: itatumika hali ya ghala (depo)." : "Not chosen: the depot way of working is used.")
                      : inventoryTypeHint(_inventoryType!, sw: _sw),
                  key: const ValueKey<String>("inv_type_hint"),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                _sw ? "Mpango wa malipo" : "Plan",
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: kBusinessPlans
                    .map((final String p) => ChoiceChip(
                          key: ValueKey<String>("plan_$p"),
                          label: Text(businessPlanLabel(p, sw: _sw)),
                          selected: _plan == p,
                          onSelected: _busy ? null : (final bool _) => setState(() => _plan = p),
                        ))
                    .toList(),
              ),
              if (_planTooSmall)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    planTooSmallText(_plan, kPlanServices[_plan]!, _grant.length, _betterPlan(), sw: _sw),
                    key: const ValueKey<String>("plan_too_small_note"),
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12.5),
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      _validUntil != null
                          ? (_sw ? "Hadi ${DateFormat("dd MMM yyyy").format(_validUntil!)}" : "Until ${DateFormat("dd MMM yyyy").format(_validUntil!)}")
                          : _plan == "trial"
                              ? (_sw ? "Jaribio huanza leo (muda unawekwa na mfumo)" : "The trial starts today (the server sets its length)")
                              : (_sw ? "Hakuna tarehe ya kuisha" : "No end date"),
                      key: const ValueKey<String>("plan_valid_until_text"),
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ),
                  TextButton(
                    key: const ValueKey<String>("plan_pick_date"),
                    onPressed: _busy ? null : _pickValidUntil,
                    child: Text(_sw ? "Chagua tarehe" : "Pick date"),
                  ),
                  if (_validUntil != null)
                    IconButton(
                      key: const ValueKey<String>("plan_clear_date"),
                      tooltip: _sw ? "Futa tarehe" : "Clear date",
                      onPressed: _busy ? null : () => setState(() => _validUntil = null),
                      icon: const Icon(Icons.close, color: Colors.white54, size: 18),
                    ),
                ],
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(_error!, key: const ValueKey<String>("registration_action_error"), style: const TextStyle(color: Colors.redAccent)),
              ],
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  if (_r.isPending) ...<Widget>[
                    Expanded(
                      child: OutlinedButton(
                        key: const ValueKey<String>("reject_button"),
                        onPressed: _busy ? null : _reject,
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
                        child: Text(_sw ? "Kataa" : "Reject"),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      key: const ValueKey<String>("approve_button"),
                      onPressed: _busy ? null : _approve,
                      style: FilledButton.styleFrom(backgroundColor: Colors.green),
                      child: _busy
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(_sw ? "Kubali na Mpe Huduma" : "Approve and Assign"),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(final IconData icon, final String label, final String value, {final String? valueKey}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: 18, color: ThemeConstants.primaryCyan),
            const SizedBox(width: 10),
            SizedBox(width: 110, child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13))),
            Expanded(child: Text(value, key: valueKey == null ? null : ValueKey<String>(valueKey), style: const TextStyle(color: Colors.white, fontSize: 14))),
          ],
        ),
      );

  /// "Standard · TWO services · 3 months · TZS 140,000": what they chose to buy and what it is priced at.
  String _packageText() {
    final String plan = _r.requestedPlan!;
    final int months = _r.requestedMonths ?? 1;
    final int included = kPlanServices[plan] ?? 0;
    return <String>[
      planNameText(plan, sw: _sw),
      if (included > 0) planCoverText(included, sw: _sw),
      periodText(months, sw: _sw),
      _r.requestedPrice == null ? (_sw ? "bei haijawekwa" : "no price set") : moneyText("TZS", _r.requestedPrice!),
    ].join(" · ");
  }

  /// The plan chosen above holds fewer services than are being given (a trial and free have no limit).
  bool get _planTooSmall {
    final int? limit = kPlanServices[_plan];
    return limit != null && _grant.length > limit;
  }
}
