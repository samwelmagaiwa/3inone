import "package:flutter/material.dart";
import "package:flutter_screenutil/flutter_screenutil.dart";

import "../../constants/theme_constants.dart";
import "../../models/business_registration.dart";
import "../../modules/inventory/models/inv_capabilities.dart";
import "../../services/auth_service.dart";
import "../../services/localization_service.dart";
import "../../widgets/backgrounds/starfield_background.dart";

/// Sends a registration. [AuthService.registerBusiness] in the app; a stub in tests.
typedef RegisterBusiness = Future<Map<String, dynamic>> Function(
    BusinessRegistrationRequest request);

/// Confirms the phone number with the code that was texted. [AuthService.verifyRegistrationPhone] in the app.
typedef VerifyPhone = Future<void> Function(String email, String code);

/// Texts a new code. [AuthService.resendRegistrationCode] in the app.
typedef ResendCode = Future<void> Function(String email);

/// A business owner registers themselves. Nothing is switched on yet: a super
/// admin reviews these details and assigns the services (inventory / rental /
/// transport), and only then can the owner sign in.
class RegisterBusinessScreen extends StatefulWidget {
  const RegisterBusinessScreen({
    super.key,
    this.onSubmit,
    this.onVerifyPhone,
    this.onResendCode,
    this.initialEmail,
    this.initialPhone,
  });

  /// Overridable so the screen can be tested without a network.
  final RegisterBusiness? onSubmit;
  final VerifyPhone? onVerifyPhone;
  final ResendCode? onResendCode;
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
