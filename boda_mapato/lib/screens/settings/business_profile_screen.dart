import "dart:typed_data";

import "package:file_picker/file_picker.dart";
import "package:flutter/material.dart";
import "package:intl/intl.dart";

import "../../constants/theme_constants.dart";
import "../../models/business.dart";
import "../../modules/inventory/models/inv_capabilities.dart";
import "../../modules/inventory/services/inv_event_bus.dart";
import "../../services/api_service.dart";
import "../../services/localization_service.dart";
import "../../widgets/subscription_banner.dart";

/// A picture the user chose: its bytes and the file name it came with.
typedef PickedLogo = ({Uint8List bytes, String name});

/// Where the screen gets and saves the business. The app uses [ApiBusinessProfileDataSource];
/// tests supply a fake so no network is needed.
abstract class BusinessProfileDataSource {
  Future<Business> load();
  Future<Business> save({
    required String name,
    required String address,
    required String tin,
    required String phone,
    required String email,
    String? inventoryType,
  });
  Future<Business> uploadLogo(Uint8List bytes, String filename);
  Future<Business> removeLogo();
}

class ApiBusinessProfileDataSource implements BusinessProfileDataSource {
  ApiBusinessProfileDataSource() {
    _api.initialize();
  }

  final ApiService _api = ApiService();

  Business _business(final Map<String, dynamic> res) =>
      Business.fromJson(Map<String, dynamic>.from(res["data"] as Map));

  @override
  Future<Business> load() async => _business(await _api.getMyBusiness());

  @override
  Future<Business> save({
    required final String name,
    required final String address,
    required final String tin,
    required final String phone,
    required final String email,
    final String? inventoryType,
  }) async {
    // Empty strings clear a field on the server; the name is never sent empty (the form requires it).
    return _business(await _api.updateMyBusiness(<String, dynamic>{
      "name": name.trim(),
      "address": address.trim(),
      "tin": tin.trim(),
      "phone": phone.trim(),
      "email": email.trim(),
      if (inventoryType != null) "inventory_type": inventoryType,
    }));
  }

  @override
  Future<Business> uploadLogo(final Uint8List bytes, final String filename) async =>
      _business(await _api.uploadBusinessLogo(bytes: bytes, filename: filename));

  @override
  Future<Business> removeLogo() async => _business(await _api.removeBusinessLogo());
}

Future<PickedLogo?> _pickLogoFromDevice() async {
  final FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
  final PlatformFile? file = (result == null || result.files.isEmpty) ? null : result.files.first;
  if (file == null || file.bytes == null) return null;
  return (bytes: file.bytes!, name: file.name);
}

/// The business as its people see it: name, address, TIN, logo and contact (what receipts and text
/// messages say) and the plan it is on. The owner edits the details; everyone else only reads them.
/// The plan is read-only here: only a super admin changes it.
class BusinessProfileScreen extends StatefulWidget {
  const BusinessProfileScreen({
    super.key,
    this.canEdit = false,
    this.showInventoryType = false,
    this.dataSource,
    this.pickLogo,
    this.onChanged,
  });

  /// Is the signed-in person the owner of the business?
  final bool canEdit;

  /// Does the business have inventory? Then its kind (retail, wholesale, ...) is shown, and the owner can change it.
  final bool showInventoryType;
  final BusinessProfileDataSource? dataSource;

  /// How a logo is chosen. The app opens the device's picker; tests supply a fake.
  final Future<PickedLogo?> Function()? pickLogo;

  /// Called after something was saved, so the rest of the app can refresh the business it shows.
  final VoidCallback? onChanged;

  @override
  State<BusinessProfileScreen> createState() => _BusinessProfileScreenState();
}

class _BusinessProfileScreenState extends State<BusinessProfileScreen> {
  final LocalizationService _loc = LocalizationService.instance;
  late final BusinessProfileDataSource _source = widget.dataSource ?? ApiBusinessProfileDataSource();
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _tin = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _address = TextEditingController();

  Business? _business;
  // The kind of stock business as chosen on this screen; only sent once the owner has actually picked one.
  String? _inventoryType;
  bool _typeTouched = false;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  bool get _sw => _loc.isSwahili;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[_name, _tin, _phone, _email, _address]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill(final Business b) {
    _business = b;
    _name.text = b.name;
    _tin.text = b.tin;
    _phone.text = b.phone;
    _email.text = b.email;
    _address.text = b.address;
    _inventoryType = b.inventoryType;
    _typeTouched = false;
  }

  String _message(final Object e) => e.toString().replaceFirst(RegExp(r"^(Api)?Exception: "), "");

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Business b = await _source.load();
      if (!mounted) return;
      setState(() {
        _fill(b);
        _loading = false;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _message(e);
      });
    }
  }

  Future<void> _run(final Future<Business> Function() action, final String done) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final Business b = await action();
      if (!mounted) return;
      setState(() {
        _fill(b);
        _busy = false;
      });
      widget.onChanged?.call();
      ThemeConstants.showSuccessSnackBar(context, done);
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _message(e);
      });
    }
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final bool changesType = widget.showInventoryType && _typeTouched && _inventoryType != null;
    await _run(
      () => _source.save(
        name: _name.text,
        address: _address.text,
        tin: _tin.text,
        phone: _phone.text,
        email: _email.text,
        inventoryType: changesType ? _inventoryType : null,
      ),
      _sw ? "Taarifa zimehifadhiwa" : "Details saved",
    );
    // The till, the product page and the menus read the kind of business: tell them to look again.
    if (changesType && _error == null) InvEventBus.instance.emit(<InvDomain>{InvDomain.settings});
  }

  Future<void> _changeLogo() async {
    final PickedLogo? picked = await (widget.pickLogo ?? _pickLogoFromDevice)();
    if (picked == null) return;
    await _run(() => _source.uploadLogo(picked.bytes, picked.name), _sw ? "Nembo imehifadhiwa" : "Logo saved");
  }

  String? _validateName(final String? v) =>
      (v == null || v.trim().isEmpty) ? (_sw ? "Jina la biashara linahitajika" : "The business name is required") : null;

  String? _validateTin(final String? v) {
    final String t = (v ?? "").trim();
    if (t.isEmpty) return null;
    return RegExp(r"^\d{3}[-\s]?\d{3}[-\s]?\d{3}$").hasMatch(t)
        ? null
        : (_sw ? "TIN lazima iwe na tarakimu 9 (mfano 123-456-789)" : "A TIN has 9 digits (e.g. 123-456-789)");
  }

  String? _validatePhone(final String? v) {
    final String t = (v ?? "").trim();
    if (t.isEmpty) return null;
    return RegExp(r"^(0\d{9}|\+\d{9,15})$").hasMatch(t)
        ? null
        : (_sw ? "Namba ya simu si sahihi (mfano 0743519100)" : "Not a valid phone number (e.g. 0743519100)");
  }

  String? _validateEmail(final String? v) {
    final String t = (v ?? "").trim();
    if (t.isEmpty) return null;
    return RegExp(r"^[^@\s]+@[^@\s]+\.[^@\s]+$").hasMatch(t) ? null : (_sw ? "Barua pepe si sahihi" : "Not a valid email");
  }

  @override
  Widget build(final BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(_sw ? "Taarifa za Biashara" : "Business Profile"),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final Business? b = _business;
    if (b == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                _error ?? (_sw ? "Hakuna biashara kwenye akaunti hii." : "This account has no business."),
                key: const ValueKey<String>("business_error"),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent),
              ),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _load, child: Text(_sw ? "Jaribu tena" : "Retry")),
            ],
          ),
        ),
      );
    }

    final bool edit = widget.canEdit;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _logoBlock(b, edit),
        const SizedBox(height: 16),
        SubscriptionBanner(billing: b.billing, sw: _sw),
        if (b.billing.needsAttention()) const SizedBox(height: 12),
        _planCard(b.billing),
        const SizedBox(height: 16),
        ThemeConstants.buildGlassCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _form,
              child: Column(
                children: <Widget>[
                  _field(_name, _sw ? "Jina la biashara" : "Business name", Icons.storefront_outlined, "business_name_field",
                      enabled: edit, validator: _validateName),
                  _field(_tin, "TIN", Icons.badge_outlined, "business_tin_field",
                      enabled: edit, validator: _validateTin, keyboard: TextInputType.number),
                  _field(_phone, _sw ? "Simu ya biashara" : "Business phone", Icons.phone_outlined, "business_phone_field",
                      enabled: edit, validator: _validatePhone, keyboard: TextInputType.phone),
                  _field(_email, _sw ? "Barua pepe ya biashara" : "Business email", Icons.email_outlined, "business_email_field",
                      enabled: edit, validator: _validateEmail, keyboard: TextInputType.emailAddress),
                  _field(_address, _sw ? "Anwani" : "Address", Icons.place_outlined, "business_address_field",
                      enabled: edit, lines: 3),
                ],
              ),
            ),
          ),
        ),
        if (widget.showInventoryType) ...<Widget>[
          const SizedBox(height: 16),
          _inventoryTypeCard(edit),
        ],
        if (_error != null) ...<Widget>[
          const SizedBox(height: 12),
          Text(_error!, key: const ValueKey<String>("business_error"), style: const TextStyle(color: Colors.redAccent)),
        ],
        const SizedBox(height: 16),
        if (edit)
          FilledButton(
            key: const ValueKey<String>("business_save"),
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(_sw ? "Hifadhi" : "Save"),
          )
        else
          Text(
            _sw
                ? "Mmiliki wa biashara tu ndiye anayeweza kubadilisha taarifa hizi."
                : "Only the owner of the business can change these details.",
            key: const ValueKey<String>("business_read_only_note"),
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
        const SizedBox(height: 8),
        Text(
          _sw
              ? "Jina, TIN, simu na anwani hapa ndivyo vinavyochapishwa kwenye risiti na ujumbe wa simu."
              : "The name, TIN, phone and address here are what receipts and text messages say.",
          style: const TextStyle(color: Colors.white38, fontSize: 12),
        ),
      ],
    );
  }

  Widget _logoBlock(final Business b, final bool edit) {
    return Column(
      children: <Widget>[
        Container(
          key: const ValueKey<String>("business_logo"),
          width: 96,
          height: 96,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white24),
          ),
          child: b.logoUrl == null
              ? const Icon(Icons.storefront_outlined, color: Colors.white54, size: 44)
              : Image.network(
                  b.logoUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (final BuildContext _, final Object __, final StackTrace? ___) =>
                      const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 36),
                ),
        ),
        if (edit) ...<Widget>[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: <Widget>[
              TextButton.icon(
                key: const ValueKey<String>("business_logo_change"),
                onPressed: _busy ? null : _changeLogo,
                icon: const Icon(Icons.image_outlined, size: 18),
                label: Text(b.logoUrl == null ? (_sw ? "Weka nembo" : "Add logo") : (_sw ? "Badilisha nembo" : "Change logo")),
              ),
              if (b.logoUrl != null)
                TextButton.icon(
                  key: const ValueKey<String>("business_logo_remove"),
                  onPressed: _busy ? null : () => _run(_source.removeLogo, _sw ? "Nembo imeondolewa" : "Logo removed"),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: Text(_sw ? "Ondoa" : "Remove"),
                ),
            ],
          ),
        ],
      ],
    );
  }

  /// What kind of stock business this is. It decides how the product page and the till behave (crates, which
  /// price the till uses, sizes and packs), so it is shown to everyone but only the owner changes it.
  Widget _inventoryTypeCard(final bool edit) {
    final String current = _inventoryType ?? "depot";
    return ThemeConstants.buildGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              _sw ? "Aina ya biashara ya bidhaa" : "Kind of stock business",
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: kInventoryTypes
                  .map((final String t) => ChoiceChip(
                        key: ValueKey<String>("business_type_$t"),
                        label: Text(inventoryTypeLabel(t, sw: _sw)),
                        selected: current == t,
                        onSelected: (edit && !_busy)
                            ? (final bool _) => setState(() {
                                  _inventoryType = t;
                                  _typeTouched = true;
                                })
                            : null,
                      ))
                  .toList(),
            ),
            const SizedBox(height: 8),
            Text(
              inventoryTypeHint(current, sw: _sw),
              key: const ValueKey<String>("business_type_hint"),
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            if (edit) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                _sw
                    ? "Kubadilisha hakubadilishi bidhaa, bei wala mauzo yako; kunabadilisha tu mipangilio uliyokuwa hujaibadilisha mwenyewe."
                    : "Changing this does not touch your products, prices or sales; it only moves the settings you have not changed yourself.",
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _planCard(final BusinessBilling billing) {
    final String until = billing.validUntil == null
        ? (_sw ? "Haina tarehe ya kuisha" : "No end date")
        : "${_sw ? "Hadi" : "Until"} ${DateFormat("dd MMM yyyy").format(billing.validUntil!)}"
            "${billing.daysLeft == null ? "" : billing.daysLeft! >= 0 ? " (${_sw ? "siku" : "days"} ${billing.daysLeft})" : ""}";

    return ThemeConstants.buildGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            const Icon(Icons.workspace_premium_outlined, color: ThemeConstants.primaryOrange),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    "${_sw ? "Mpango" : "Plan"}: ${businessPlanLabel(billing.plan, sw: _sw)}",
                    key: const ValueKey<String>("business_plan"),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(until, key: const ValueKey<String>("business_valid_until"), style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    final TextEditingController controller,
    final String label,
    final IconData icon,
    final String key, {
    required final bool enabled,
    final String? Function(String?)? validator,
    final TextInputType? keyboard,
    final int lines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        key: ValueKey<String>(key),
        controller: controller,
        enabled: enabled && !_busy,
        validator: validator,
        keyboardType: keyboard,
        minLines: lines,
        maxLines: lines,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white60),
          prefixIcon: Icon(icon, color: Colors.white54),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.06),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
      ),
    );
  }
}
