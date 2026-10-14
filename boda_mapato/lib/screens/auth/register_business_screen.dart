import "package:flutter/material.dart";
import "package:flutter_screenutil/flutter_screenutil.dart";

import "../../constants/theme_constants.dart";
import "../../models/business_registration.dart";
import "../../models/plan_prices.dart";
import "../../modules/inventory/models/inv_capabilities.dart";
import "../../services/api_service.dart";
import "../../services/auth_service.dart";
import "../../services/localization_service.dart";
import "../../utils/plan_text.dart";
import "../../widgets/backgrounds/starfield_background.dart";

/// Sends a registration. [AuthService.registerBusiness] in the app; a stub in tests.
typedef RegisterBusiness = Future<Map<String, dynamic>> Function(
    BusinessRegistrationRequest request);

/// Confirms the phone number with the code that was texted. [AuthService.verifyRegistrationPhone] in the app.
typedef VerifyPhone = Future<void> Function(String email, String code);

/// Texts a new code. [AuthService.resendRegistrationCode] in the app.
typedef ResendCode = Future<void> Function(String email);

/// The plans with what they cover and cost, as the super admin set them. Read from the server in the app; a stub in tests.
typedef LoadPlans = Future<PlanCatalog> Function();

Future<PlanCatalog> _loadPlansFromServer() async {
  final Map<String, dynamic> res = await ApiService().getPlans();
  return PlanCatalog.fromJson(Map<String, dynamic>.from(res["data"] as Map));
}

/// A business owner registers themselves. Nothing is switched on yet: a super
/// admin reviews these details and assigns the services (inventory / rental /
/// transport), and only then can the owner sign in.
class RegisterBusinessScreen extends StatefulWidget {
  const RegisterBusinessScreen({
    super.key,
    this.onSubmit,
    this.onVerifyPhone,
    this.onResendCode,
    this.onLoadPlans,
    this.initialEmail,
    this.initialPhone,
  });

  /// Overridable so the screen can be tested without a network.
  final RegisterBusiness? onSubmit;
  final VerifyPhone? onVerifyPhone;
  final ResendCode? onResendCode;

  /// Where the prices come from. Without an answer the form still works: it says what each plan covers and that the
  /// price will be told.
  final LoadPlans? onLoadPlans;
  final String? initialEmail;
  final String? initialPhone;

  @override
  State<RegisterBusinessScreen> createState() => _RegisterBusinessScreenState();
}

class _RegisterBusinessScreenState extends State<RegisterBusinessScreen> {
  static final RegExp _phonePattern = RegExp(r"^(0\d{9}|\+\d{9,15})$");

  final LocalizationService _loc = LocalizationService.instance;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _name = TextEditingController();
  final TextEditingController _business = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  final TextEditingController _region = TextEditingController();
  final TextEditingController _district = TextEditingController();
  final TextEditingController _address = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  final TextEditingController _code = TextEditingController();

  final Set<String> _services = <String>{};
  bool _servicesMissing = false;
  // The package: a plan (basic = one service, standard = two, premium = all three) paid for [_months] months. It
  // follows the number of services chosen until the applicant picks one themselves.
  PlanCatalog _catalog = PlanCatalog.fallback;
  String? _plan;
  bool _planTouched = false;
  int _months = 1;
  // Asked once inventory is among the services: retail, wholesale, mixed or depot.
  String? _inventoryType;
  bool _typeMissing = false;
  bool _obscure = true;
  bool _busy = false;
  bool _done = false;
  // The server texted a code to the phone; until it is entered the super admin sees an
  // unconfirmed number. The application itself is already sent either way.
  bool _needsCode = false;
  bool _codeUnavailable = false;
  bool _phoneConfirmed = false;
  bool _codeBusy = false;
  String? _codeError;
  String? _codeNotice;
  String? _error;

  bool get _sw => _loc.isSwahili;

  @override
  void initState() {
    super.initState();
    if (widget.initialEmail != null) {
      _email.text = widget.initialEmail!;
    }
    if (widget.initialPhone != null) {
      _phone.text = widget.initialPhone!;
    }
    _loadPlans();
  }

  /// Ask for the prices. A failure changes nothing: the plans and what they cover are known without the server.
  Future<void> _loadPlans() async {
    try {
      final PlanCatalog catalog = await (widget.onLoadPlans ?? _loadPlansFromServer)();
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _syncPlan();
      });
    } on Exception catch (_) {
      // the prices are simply not shown
    }
  }

  /// Until the applicant picks a plan, the one that fits the services chosen.
  void _syncPlan() {
    if (_planTouched) return;
    _plan = _services.isEmpty ? null : _catalog.planFor(_services.length);
  }

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[
      _name, _business, _email, _phone, _password, _confirm,
      _region, _district, _address, _notes, _code, //
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String _serviceLabel(final String service) => switch (service) {
        "inventory" => _loc.translate("inventory_service"),
        "rental" => _loc.translate("rental_service"),
        _ => _loc.translate("transport_service"),
      };

  IconData _serviceIcon(final String service) => switch (service) {
        "inventory" => Icons.inventory_2_rounded,
        "rental" => Icons.apartment_rounded,
        _ => Icons.local_shipping_rounded,
      };

  Future<void> _submit() async {
    setState(() => _error = null);
    final bool formOk = _formKey.currentState?.validate() ?? false;
    final bool needsType = _services.contains("inventory") && _inventoryType == null;
    setState(() {
      _servicesMissing = _services.isEmpty;
      _typeMissing = needsType;
    });
    if (!formOk || _services.isEmpty || needsType) return;

    // The package must cover the services chosen: basic is ONE service, standard two, premium all three.
    final String plan = _plan ?? _catalog.planFor(_services.length);
    if (!_catalog.covers(plan, _services.length)) {
      setState(() => _error = _tooSmallText(plan));
      return;
    }

    setState(() => _busy = true);
    try {
      final Map<String, dynamic> result = await (widget.onSubmit ?? AuthService.registerBusiness)(
        BusinessRegistrationRequest(
          name: _name.text,
          businessName: _business.text,
          email: _email.text,
          phoneNumber: _phone.text,
          password: _password.text,
          passwordConfirmation: _confirm.text,
          requestedServices: kBusinessServices.where(_services.contains).toList(),
          requestedPlan: plan,
          requestedMonths: _months,
          inventoryType: _services.contains("inventory") ? _inventoryType : null,
          region: _region.text,
          district: _district.text,
          address: _address.text,
          notes: _notes.text,
        ),
      );
      if (!mounted) return;
      final Object? data = result["data"];
      setState(() {
        _busy = false;
        _done = true;
        // Text messages can be switched off on the server: then no code exists, and asking for one
        // would leave the person waiting for something that never comes.
        _codeUnavailable = data is Map && data["code_status"] == "unavailable";
        _needsCode = data is Map && data["phone_verification_required"] == true && !_codeUnavailable;
        _phoneConfirmed = data is Map && data["phone_verified"] == true;
      });
    } on AuthHttpException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } on Exception catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _sw
            ? "Imeshindikana kuwasiliana na seva. Hakikisha una intaneti kisha jaribu tena."
            : "Could not reach the server. Check your internet connection and try again.";
      });
    }
  }

  String _friendly(final Object e) => e is AuthHttpException
      ? e.message
      : (_sw ? "Imeshindikana kuwasiliana na seva. Jaribu tena." : "Could not reach the server. Try again.");

  Future<void> _confirmPhone() async {
    final String code = _code.text.trim();
    if (!RegExp(r"^\d{6}$").hasMatch(code)) {
      setState(() => _codeError = _loc.translate("enter_valid_code"));
      return;
    }
    setState(() {
      _codeBusy = true;
      _codeError = null;
      _codeNotice = null;
    });
    try {
      await (widget.onVerifyPhone ?? ((final String e, final String c) => AuthService.verifyRegistrationPhone(email: e, code: c)))(
        _email.text.trim(),
        code,
      );
      if (!mounted) return;
      setState(() {
        _codeBusy = false;
        _needsCode = false;
        _phoneConfirmed = true;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _codeBusy = false;
        _codeError = _friendly(e);
      });
    }
  }

  Future<void> _sendNewCode() async {
    setState(() {
      _codeBusy = true;
      _codeError = null;
      _codeNotice = null;
    });
    try {
      await (widget.onResendCode ?? ((final String e) => AuthService.resendRegistrationCode(email: e)))(_email.text.trim());
      if (!mounted) return;
      setState(() {
        _codeBusy = false;
        _codeNotice = _loc.translate("code_sent");
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _codeBusy = false;
        _codeError = _friendly(e);
      });
    }
  }

  @override
  Widget build(final BuildContext context) {
    return StarfieldBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          title: Text(
            _sw ? "Jisajili - Biashara Yako" : "Register Your Business",
            style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
          ),
        ),
        body: SafeArea(child: _done ? _buildDone() : _buildForm()),
      ),
    );
  }

  // ------------------------------------------------------------------ form

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: ListView(
        padding: EdgeInsets.fromLTRB(20.w, 4.h, 20.w, 32.h),
        children: <Widget>[
          Text(
            _sw
                ? "Jaza taarifa zako. Msimamizi mkuu atazikagua na kukupa huduma unazostahili; "
                    "baada ya hapo utaweza kuingia na kuunda wafanyakazi wako."
                : "Fill in your details. A super admin will review them and give you the services "
                    "you need; after that you can sign in and create your own staff.",
            style: TextStyle(color: Colors.white70, fontSize: 13.sp, height: 1.4),
          ),
          SizedBox(height: 18.h),
          if (_error != null) _errorBox(_error!),
          _section(_sw ? "Taarifa zako" : "About you"),
          _field(
            controller: _name,
            label: _sw ? "Jina lako kamili" : "Your full name",
            icon: Icons.person_outline,
            validator: _required,
          ),
          _field(
            controller: _email,
            label: _loc.translate("email"),
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: (final String? v) => (v == null || !v.contains("@"))
                ? _loc.translate("enter_valid_email")
                : null,
          ),
          _field(
            controller: _phone,
            label: _loc.translate("phone_number"),
            hint: "0743519100",
            icon: Icons.phone_android_outlined,
            keyboardType: TextInputType.phone,
            validator: (final String? v) =>
                _phonePattern.hasMatch((v ?? "").trim())
                    ? null
                    : (_sw
                        ? "Namba ya simu si sahihi (mfano 0743519100 au +255743519100)"
                        : "Invalid phone number (e.g. 0743519100 or +255743519100)"),
          ),
          _field(
            controller: _password,
            label: _loc.translate("password"),
            icon: Icons.lock_outline,
            obscure: _obscure,
            suffix: IconButton(
              icon: Icon(
                _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: Colors.white54,
                size: 20.sp,
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
            validator: (final String? v) => (v == null || v.length < 8)
                ? (_sw ? "Nenosiri liwe na angalau herufi 8" : "Password must be at least 8 characters")
                : null,
          ),
          _field(
            controller: _confirm,
            label: _sw ? "Thibitisha nenosiri" : "Confirm password",
            icon: Icons.lock_reset_outlined,
            obscure: _obscure,
            validator: (final String? v) => v != _password.text
                ? _loc.translate("passwords_do_not_match")
                : null,
          ),
          _section(_sw ? "Biashara yako" : "Your business"),
          _field(
            controller: _business,
            label: _sw ? "Jina la biashara" : "Business name",
            icon: Icons.storefront_outlined,
            validator: _required,
          ),
          _servicePicker(),
          if (_services.contains("inventory")) _inventoryTypePicker(),
          _packagePicker(),
          _section(_sw ? "Mahali na maelezo (hiari)" : "Location and details (optional)"),
          _field(controller: _region, label: _sw ? "Mkoa" : "Region", icon: Icons.map_outlined),
          _field(controller: _district, label: _sw ? "Wilaya" : "District", icon: Icons.location_city_outlined),
          _field(controller: _address, label: _sw ? "Anuani" : "Address", icon: Icons.place_outlined),
          _field(
            controller: _notes,
            label: _sw ? "Maelezo ya ziada" : "Anything else we should know",
            icon: Icons.notes_outlined,
            maxLines: 3,
          ),
          SizedBox(height: 8.h),
          _primaryButton(
            label: _sw ? "Tuma Ombi" : "Submit Registration",
            onPressed: _busy ? null : _submit,
          ),
        ],
      ),
    );
  }

  String? _required(final String? v) => (v == null || v.trim().isEmpty)
      ? (_sw ? "Sehemu hii inahitajika" : "This field is required")
      : null;

  Widget _servicePicker() {
    return Padding(
      padding: EdgeInsets.only(bottom: 14.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            _sw ? "Huduma unazohitaji" : "Services you need",
            style: TextStyle(color: Colors.white70, fontSize: 13.sp, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 8.h),
          Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: kBusinessServices.map((final String s) {
              final bool selected = _services.contains(s);
              return FilterChip(
                key: ValueKey<String>("service_$s"),
                avatar: Icon(_serviceIcon(s), size: 18.sp, color: selected ? Colors.black : ThemeConstants.primaryCyan),
                label: Text(_serviceLabel(s)),
                selected: selected,
                showCheckmark: false,
                labelStyle: TextStyle(color: selected ? Colors.black : Colors.white, fontSize: 13.sp),
                selectedColor: ThemeConstants.primaryCyan,
                backgroundColor: Colors.white.withValues(alpha: 0.06),
                side: BorderSide(color: selected ? ThemeConstants.primaryCyan : Colors.white24),
                onSelected: (final bool on) => setState(() {
                  on ? _services.add(s) : _services.remove(s);
                  _servicesMissing = false;
                  _error = null;
                  _syncPlan();
                }),
              );
            }).toList(),
          ),
          if (_servicesMissing)
            Padding(
              padding: EdgeInsets.only(top: 6.h),
              child: Text(
                _sw ? "Chagua angalau huduma moja" : "Choose at least one service",
                style: TextStyle(color: Colors.redAccent, fontSize: 12.sp),
              ),
            ),
          SizedBox(height: 6.h),
          Text(
            _sw
                ? "Msimamizi mkuu ndiye atakayekupa huduma ya mwisho."
                : "The super admin decides the final services you are given.",
            style: TextStyle(color: Colors.white38, fontSize: 11.sp),
          ),
        ],
      ),
    );
  }

  String _tooSmallText(final String plan) => planTooSmallText(
        plan,
        _catalog.servicesIncluded(plan) ?? 0,
        _services.length,
        _catalog.planFor(_services.length),
        sw: _sw,
      );

  /// "Your package": what each plan covers and costs, the one that fits the services chosen, and a plain word when a
  /// plan is too small. Prices are the super admin's: they show here as soon as they are saved.
  Widget _packagePicker() {
    final int count = _services.length;
    final String? plan = _plan;
    final String recommended = count == 0 ? "" : _catalog.planFor(count);
    final bool tooSmall = plan != null && count > 0 && !_catalog.covers(plan, count);
    final int included = plan == null ? 0 : (_catalog.servicesIncluded(plan) ?? 0);

    return Padding(
      padding: EdgeInsets.only(bottom: 14.h),
      child: Column(
        key: const ValueKey<String>("package_section"),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            _sw ? "Kifurushi chako na bei" : "Your package and price",
            style: TextStyle(color: Colors.white70, fontSize: 13.sp, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 4.h),
          Text(
            _sw
                ? "${planNameText("basic", sw: true)} ni huduma MOJA, ${planNameText("standard", sw: true)} ni huduma 2, Premium ni huduma ZOTE 3."
                : "Basic is ONE service, Standard is TWO, Premium is ALL THREE.",
            key: const ValueKey<String>("package_rule"),
            style: TextStyle(color: Colors.white54, fontSize: 12.sp),
          ),
          SizedBox(height: 10.h),
          Wrap(
            spacing: 8.w,
            runSpacing: 6.h,
            children: <Widget>[
              for (final int m in _catalog.periods)
                ChoiceChip(
                  key: ValueKey<String>("period_$m"),
                  label: Text(periodText(m, sw: _sw)),
                  selected: _months == m,
                  onSelected: (final bool _) => setState(() => _months = m),
                ),
            ],
          ),
          SizedBox(height: 10.h),
          for (final PlanOffer o in _catalog.offers) _planOption(o, count, recommended),
          if (count == 0)
            Padding(
              padding: EdgeInsets.only(top: 2.h),
              child: Text(
                _sw ? "Chagua huduma hapo juu ili ujue mpango unaokufaa." : "Choose your services above to see the plan that fits.",
                key: const ValueKey<String>("package_choose_services"),
                style: TextStyle(color: Colors.white38, fontSize: 12.sp),
              ),
            ),
          if (tooSmall) _planWarning(plan, included, count, recommended),
          if (plan == "basic" && !tooSmall)
            _packageNote(
              key: "basic_notice",
              color: Colors.amberAccent,
              icon: Icons.info_outline,
              text: _sw
                  ? "Kumbuka: mpango wa ${planNameText("basic", sw: true)} (Basic) ni huduma MOJA tu. Ukihitaji huduma 2 chagua ${planNameText("standard", sw: true)} (Standard), au Premium kwa huduma zote 3."
                  : "Please note: the Basic plan is ONE service only. For two services choose Standard, or Premium for all three.",
            ),
          if (plan != null && count > 0 && !tooSmall && plan != recommended && included > count)
            _packageNote(
              key: "plan_note",
              color: Colors.lightBlueAccent,
              icon: Icons.lightbulb_outline,
              text: _sw
                  ? "${planNameText(plan, sw: true)} inajumuisha huduma $included, wewe umechagua $count. ${planNameText(recommended, sw: true)} inatosha kwa huduma ulizochagua."
                  : "${planNameText(plan, sw: false)} covers $included services and you chose $count. ${planNameText(recommended, sw: false)} is enough for the services you chose.",
            ),
          if (plan != null && count > 0 && !tooSmall) _packageSummary(plan, included),
        ],
      ),
    );
  }

  /// One plan to choose: what it covers and what it costs for the period chosen.
  Widget _planOption(final PlanOffer o, final int count, final String recommended) {
    final bool selected = _plan == o.plan;
    final bool fits = count == 0 || count <= o.servicesIncluded;
    final double? price = _catalog.priceFor(o.plan, _months);

    return Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: Opacity(
        opacity: fits ? 1 : 0.55,
        child: InkWell(
          key: ValueKey<String>("plan_${o.plan}"),
          borderRadius: BorderRadius.circular(14.r),
          onTap: () => setState(() {
            _plan = o.plan;
            _planTouched = true;
            _error = null;
          }),
          child: Container(
            padding: EdgeInsets.all(12.w),
            decoration: BoxDecoration(
              color: selected ? ThemeConstants.primaryCyan.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(14.r),
              border: Border.all(color: selected ? ThemeConstants.primaryCyan : Colors.white24, width: selected ? 1.6 : 1),
            ),
            child: Row(
              children: <Widget>[
                Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? ThemeConstants.primaryCyan : Colors.white38, size: 22.sp),
                SizedBox(width: 10.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Wrap(
                        spacing: 8.w,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
                          Text(planNameText(o.plan, sw: _sw), style: TextStyle(color: Colors.white, fontSize: 15.sp, fontWeight: FontWeight.w800)),
                          if (o.plan == recommended)
                            Container(
                              key: ValueKey<String>("recommended_${o.plan}"),
                              padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 2.h),
                              decoration: BoxDecoration(color: Colors.greenAccent.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(8.r)),
                              child: Text(_sw ? "Inakufaa" : "Fits you", style: TextStyle(color: Colors.greenAccent, fontSize: 11.sp, fontWeight: FontWeight.w700)),
                            ),
                        ],
                      ),
                      Text(planCoverText(o.servicesIncluded, sw: _sw), key: ValueKey<String>("covers_${o.plan}"), style: TextStyle(color: ThemeConstants.primaryCyan, fontSize: 12.5.sp, fontWeight: FontWeight.w600)),
                      SizedBox(height: 2.h),
                      Text(
                        price == null
                            ? (_sw ? "Bei itatangazwa" : "Price to be announced")
                            : "${moneyText(_catalog.currency, price)} · ${periodText(_months, sw: _sw)}",
                        key: ValueKey<String>("price_${o.plan}"),
                        style: TextStyle(color: price == null ? Colors.white38 : Colors.white, fontSize: 13.sp, fontWeight: price == null ? FontWeight.w400 : FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _planWarning(final String plan, final int included, final int count, final String recommended) {
    return Container(
      key: const ValueKey<String>("plan_warning"),
      margin: EdgeInsets.only(top: 4.h),
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(_tooSmallText(plan), style: TextStyle(color: Colors.red[100], fontSize: 13.sp, height: 1.35)),
          SizedBox(height: 6.h),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              key: const ValueKey<String>("use_recommended_plan"),
              onPressed: () => setState(() {
                _plan = recommended;
                _planTouched = false;
                _error = null;
              }),
              child: Text(_sw ? "Tumia ${planNameText(recommended, sw: true)}" : "Use ${planNameText(recommended, sw: false)}"),
            ),
          ),
        ],
      ),
    );
  }

  Widget _packageNote({required final String key, required final Color color, required final IconData icon, required final String text}) {
    return Container(
      key: ValueKey<String>(key),
      margin: EdgeInsets.only(top: 4.h),
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: color, size: 18.sp),
          SizedBox(width: 8.w),
          Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 12.5.sp, height: 1.35))),
        ],
      ),
    );
  }

  /// What the applicant will pay, and that the first days are free.
  Widget _packageSummary(final String plan, final int included) {
    final double? price = _catalog.priceFor(plan, _months);
    final String name = planNameText(plan, sw: _sw);
    final String period = periodText(_months, sw: _sw).toLowerCase();
    final String line = price == null
        ? (_sw ? "Bei ya $name kwa $period itatangazwa na msimamizi." : "The price of $name for $period will be told by the administrator.")
        : (_sw
            ? "Utalipa ${moneyText(_catalog.currency, price)} kwa $period: $name (${planCoverText(included, sw: true).toLowerCase()})."
            : "You will pay ${moneyText(_catalog.currency, price)} for $period: $name (${planCoverText(included, sw: false).toLowerCase()}).");

    return Container(
      margin: EdgeInsets.only(top: 6.h),
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(line, key: const ValueKey<String>("package_summary"), style: TextStyle(color: Colors.white, fontSize: 13.5.sp, fontWeight: FontWeight.w700)),
          if (_catalog.trialDays > 0) ...<Widget>[
            SizedBox(height: 4.h),
            Text(
              _sw
                  ? "Ukikubaliwa unapata siku ${_catalog.trialDays} za majaribio bila malipo; malipo yanaanza baada ya hapo."
                  : "Once you are approved you get ${_catalog.trialDays} days of free trial; payment starts after that.",
              key: const ValueKey<String>("trial_note"),
              style: TextStyle(color: Colors.white60, fontSize: 12.sp),
            ),
          ],
        ],
      ),
    );
  }

  /// "What kind of stock business?": retail, wholesale, ... It sets how the product page and the till
  /// behave from day one; the owner can change it later in the business profile.
  Widget _inventoryTypePicker() {
    return Padding(
      padding: EdgeInsets.only(bottom: 14.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          DropdownButtonFormField<String>(
            key: const ValueKey<String>("inventory_type_field"),
            initialValue: _inventoryType,
            isExpanded: true,
            dropdownColor: const Color(0xFF1E2A33),
            iconEnabledColor: Colors.white54,
            style: TextStyle(color: Colors.white, fontSize: 14.sp),
            hint: Text(
              _sw ? "Jumla, Rejareja, au ..." : "Wholesale, Retail, or ...",
              style: TextStyle(color: Colors.white38, fontSize: 14.sp),
            ),
            decoration: InputDecoration(
              labelText: _sw ? "Aina ya biashara ya bidhaa" : "Kind of stock business",
              labelStyle: TextStyle(color: Colors.white54, fontSize: 13.sp),
              prefixIcon: Icon(Icons.category_outlined, color: ThemeConstants.primaryCyan, size: 20.sp),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide: BorderSide(color: _typeMissing ? Colors.redAccent : Colors.white12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide: const BorderSide(color: ThemeConstants.primaryCyan),
              ),
            ),
            items: <DropdownMenuItem<String>>[
              for (final String t in kInventoryTypes)
                DropdownMenuItem<String>(
                  value: t,
                  child: Text(inventoryTypeLabel(t, sw: _sw), overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (final String? v) => setState(() {
              _inventoryType = v;
              _typeMissing = false;
            }),
          ),
          if (_typeMissing)
            Padding(
              padding: EdgeInsets.only(top: 6.h),
              child: Text(
                _sw ? "Chagua aina ya biashara yako" : "Choose what kind of business you run",
                key: const ValueKey<String>("inventory_type_error"),
                style: TextStyle(color: Colors.redAccent, fontSize: 12.sp),
              ),
            )
          else if (_inventoryType != null)
            Padding(
              padding: EdgeInsets.only(top: 6.h),
              child: Text(
                inventoryTypeHint(_inventoryType!, sw: _sw),
                key: const ValueKey<String>("inventory_type_hint"),
                style: TextStyle(color: Colors.white38, fontSize: 11.sp),
              ),
            ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ done

  Widget _buildDone() {
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(28.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.mark_email_read_outlined, color: Colors.greenAccent, size: 64.sp),
            SizedBox(height: 18.h),
            Text(
              _sw ? "Ombi lako limepokelewa" : "Registration received",
              key: const ValueKey<String>("registration_done_title"),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 20.sp, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10.h),
            Text(
              _sw
                  ? 'Msimamizi mkuu atakagua taarifa za "${_business.text.trim()}" na kukupa huduma. '
                      '${_codeUnavailable ? "Ukikubaliwa utaweza" : "Ukikubaliwa utatumiwa ujumbe mfupi, kisha utaweza"} '
                      'kuingia kwa barua pepe na nenosiri ulilotumia hapa.'
                  : 'A super admin will review "${_business.text.trim()}" and give you your services. '
                      '${_codeUnavailable ? "Once approved you can" : "Once approved you will get a text message, and can"} '
                      'sign in with the email and password you just used.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 14.sp, height: 1.4),
            ),
            if (_plan != null) ...<Widget>[
              SizedBox(height: 12.h),
              Text(
                _sw
                    ? "Kifurushi ulichochagua: ${planNameText(_plan!, sw: true)} (${planCoverText(_catalog.servicesIncluded(_plan!) ?? 0, sw: true).toLowerCase()}) · ${periodText(_months, sw: true).toLowerCase()}"
                        "${_catalog.priceFor(_plan!, _months) == null ? "" : " · ${moneyText(_catalog.currency, _catalog.priceFor(_plan!, _months)!)}"}"
                    : "Your package: ${planNameText(_plan!, sw: false)} (${planCoverText(_catalog.servicesIncluded(_plan!) ?? 0, sw: false).toLowerCase()}) · ${periodText(_months, sw: false).toLowerCase()}"
                        "${_catalog.priceFor(_plan!, _months) == null ? "" : " · ${moneyText(_catalog.currency, _catalog.priceFor(_plan!, _months)!)}"}",
                key: const ValueKey<String>("registration_done_package"),
                textAlign: TextAlign.center,
                style: TextStyle(color: ThemeConstants.primaryCyan, fontSize: 13.sp, fontWeight: FontWeight.w700),
              ),
            ],
            SizedBox(height: 20.h),
            if (_phoneConfirmed)
              Row(
                key: const ValueKey<String>("phone_confirmed"),
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(Icons.verified_outlined, color: Colors.greenAccent, size: 18.sp),
                  SizedBox(width: 6.w),
                  Text(
                    _sw ? "Namba ya simu imethibitishwa" : "Phone number confirmed",
                    style: TextStyle(color: Colors.greenAccent, fontSize: 13.sp),
                  ),
                ],
              ),
            if (_needsCode) _buildCodeCard(),
            if (_codeUnavailable && !_phoneConfirmed) _buildNoCodeNotice(),
            SizedBox(height: 20.h),
            _primaryButton(
              label: _sw ? "Rudi kuingia" : "Back to sign in",
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ],
        ),
      ),
    );
  }

  /// Text messages are off on the server, so there is no code to enter: say so plainly, and that the
  /// application is not harmed by it (the super admin checks the number themselves before approving).
  Widget _buildNoCodeNotice() {
    return Container(
      key: const ValueKey<String>("phone_code_unavailable"),
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white12),
      ),
      child: Text(
        _sw
            ? "Huduma ya ujumbe mfupi haipatikani sasa, kwa hiyo hatukuweza kukutumia nambari ya kuthibitisha simu. "
                "Usijali: msimamizi atakuthibitisha kabla ya kukubali ombi lako."
            : "Text messages are not available right now, so we could not send you a phone confirmation code. "
                "Don't worry: the admin will check you before approving your application.",
        style: TextStyle(color: Colors.white70, fontSize: 13.sp, height: 1.4),
      ),
    );
  }

  /// "We texted a code to your phone": enter it so the super admin sees a confirmed number.
  Widget _buildCodeCard() {
    return Container(
      key: const ValueKey<String>("phone_code_card"),
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            _sw
                ? "Tumekutumia nambari ya tarakimu 6 kwa ujumbe mfupi kwenye ${_phone.text.trim()}. Iweke hapa kuthibitisha simu yako."
                : "We texted a 6-digit code to ${_phone.text.trim()}. Enter it here to confirm your phone.",
            style: TextStyle(color: Colors.white70, fontSize: 13.sp, height: 1.4),
          ),
          SizedBox(height: 12.h),
          if (_codeError != null)
            Padding(
              padding: EdgeInsets.only(bottom: 8.h),
              child: Text(_codeError!, key: const ValueKey<String>("phone_code_error"), style: TextStyle(color: Colors.red[200], fontSize: 13.sp)),
            ),
          if (_codeNotice != null)
            Padding(
              padding: EdgeInsets.only(bottom: 8.h),
              child: Text(_codeNotice!, key: const ValueKey<String>("phone_code_notice"), style: TextStyle(color: Colors.greenAccent, fontSize: 13.sp)),
            ),
          TextField(
            key: const ValueKey<String>("phone_code_field"),
            controller: _code,
            keyboardType: TextInputType.number,
            maxLength: 6,
            style: const TextStyle(color: Colors.white, letterSpacing: 4),
            decoration: InputDecoration(
              counterText: "",
              labelText: _loc.translate("verification_code"),
              labelStyle: TextStyle(color: Colors.white54, fontSize: 13.sp),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: const BorderSide(color: Colors.white12)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: const BorderSide(color: ThemeConstants.primaryCyan)),
            ),
          ),
          SizedBox(height: 10.h),
          ElevatedButton(
            key: const ValueKey<String>("registration_confirm_phone"),
            onPressed: _codeBusy ? null : _confirmPhone,
            style: ElevatedButton.styleFrom(backgroundColor: ThemeConstants.primaryCyan),
            child: Text(
              (_sw ? "Thibitisha simu" : "Confirm phone").toUpperCase(),
              style: TextStyle(color: Colors.black, fontSize: 13.sp, fontWeight: FontWeight.w800),
            ),
          ),
          TextButton(
            key: const ValueKey<String>("registration_resend_code"),
            onPressed: _codeBusy ? null : _sendNewCode,
            child: Text(_loc.translate("resend_code"), style: TextStyle(color: ThemeConstants.primaryCyan, fontSize: 13.sp)),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- widgets

  Widget _section(final String title) => Padding(
        padding: EdgeInsets.only(top: 6.h, bottom: 12.h),
        child: Text(
          title.toUpperCase(),
          style: TextStyle(
            color: ThemeConstants.primaryCyan,
            fontSize: 12.sp,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
      );

  Widget _errorBox(final String message) => Container(
        key: const ValueKey<String>("registration_error"),
        margin: EdgeInsets.only(bottom: 16.h),
        padding: EdgeInsets.all(12.w),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
        ),
        child: Text(message, style: TextStyle(color: Colors.red[200], fontSize: 13.sp)),
      );

  Widget _field({
    required final TextEditingController controller,
    required final String label,
    required final IconData icon,
    final String? hint,
    final bool obscure = false,
    final Widget? suffix,
    final int maxLines = 1,
    final TextInputType? keyboardType,
    final String? Function(String?)? validator,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: 14.h),
      child: TextFormField(
        controller: controller,
        obscureText: obscure,
        maxLines: obscure ? 1 : maxLines,
        keyboardType: keyboardType,
        validator: validator,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white24),
          labelStyle: TextStyle(color: Colors.white54, fontSize: 13.sp),
          prefixIcon: Icon(icon, color: ThemeConstants.primaryCyan, size: 20.sp),
          suffixIcon: suffix,
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.05),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.r),
            borderSide: const BorderSide(color: Colors.white12),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.r),
            borderSide: const BorderSide(color: ThemeConstants.primaryCyan),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.r),
            borderSide: const BorderSide(color: Colors.redAccent),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.r),
            borderSide: const BorderSide(color: Colors.redAccent),
          ),
        ),
      ),
    );
  }

  Widget _primaryButton({required final String label, required final VoidCallback? onPressed}) {
    return SizedBox(
      height: 52.h,
      child: ElevatedButton(
        key: const ValueKey<String>("registration_submit"),
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: ThemeConstants.primaryCyan,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.r)),
        ),
        child: _busy
            ? SizedBox(
                width: 22.w,
                height: 22.w,
                child: const CircularProgressIndicator(strokeWidth: 2.4, color: Colors.black),
              )
            : Text(
                label.toUpperCase(),
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
      ),
    );
  }
}
