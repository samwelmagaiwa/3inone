import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_screenutil/flutter_screenutil.dart";
import "package:provider/provider.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:url_launcher/url_launcher_string.dart";

import "../../constants/colors.dart";
import "../../constants/theme_constants.dart";
import "../../providers/auth_provider.dart";
import "../../services/auth_service.dart";
import "../../modules/inventory/screens/widgets/joined_sections.dart";
import "../../services/localization_service.dart";
import "../../widgets/service_art.dart";
import "forgot_password_sheet.dart";
import "register_business_screen.dart";
import '../../utils/server_message.dart';

/// Which part of the page is showing: signing in (email + password), signing up (email, phone, password, confirm) or confirming the
/// phone with the code that was texted after signing up.
enum _Step { signIn, signUp, confirmPhone }

typedef SignupCall = Future<Map<String, dynamic>> Function({
  required String email,
  required String phone,
  required String password,
  required String confirm,
});

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.startInSignup = false, this.onSignup, this.onVerifyCode, this.onResendCode});

  /// Opens with the sign-up fields showing (the landing page's "register" button).
  final bool startInSignup;

  /// Replaceable so the page can be tested without a network.
  final SignupCall? onSignup;
  final Future<void> Function(String email, String code)? onVerifyCode;
  final Future<void> Function(String email)? onResendCode;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static final RegExp _phonePattern = RegExp(r"^(0\d{9}|\+\d{9,15})$");
  static const Duration _anim = Duration(milliseconds: 320);

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;
  // Set where it is declared (not in initState) so a hot reload of a page that is already open cannot leave it unset.
  late _Step _step = widget.startInSignup ? _Step.signUp : _Step.signIn;
  String? _error;
  String? _notice;

  LocalizationService get _loc => LocalizationService.instance;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _confirmController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _goTo(final _Step step, {final String? notice}) {
    setState(() {
      _step = step;
      _error = null;
      _notice = notice;
    });
  }

  String? _emailError(final String? v) => (v == null || !v.contains('@') || v.trim().length < 5) ? _loc.translate('enter_valid_email') : null;

  Future<void> _submit() => switch (_step) {
        _Step.signIn => _handleLogin(),
        _Step.signUp => _handleSignup(),
        _Step.confirmPhone => _handleVerify(),
      };

  // ------------------------------------------------------------------ sign in (email + password only)

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final String email = _emailController.text.trim();
    final String password = _passwordController.text;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final AuthProvider authProvider = Provider.of<AuthProvider>(context, listen: false);
    bool success;
    try {
      success = await authProvider.login(email: email, password: password);
    } on Exception catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackBar(readableErrorMessage(e), Colors.red);
      }
      return;
    }
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      await _saveRemembered(email);
      if (!mounted) return;
      _showSnackBar(_loc.translate('login_successful'), Colors.green);
      Navigator.of(context).pop();
      return;
    }

    final String message = authProvider.errorMessage ?? _loc.translate('login_failed');
    switch (authProvider.lastErrorCode) {
      case 'needs_business_details':
        // Signed up and confirmed the phone: now the business details (the phone and password are already known).
        final ApplicantCredentials? who = authProvider.applicant;
        if (who != null) {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (final BuildContext _) => RegisterBusinessScreen(applicant: who)),
          );
        }
      case 'phone_not_verified':
        // They signed up but never entered the code: ask for it, and text a fresh one.
        _goTo(_Step.confirmPhone, notice: _loc.translate('confirm_phone_hint'));
        await _resend(silent: true);
      case 'registration_rejected':
        _showRegistrationRejectedDialog(message: message, email: email, password: password);
      case 'registration_pending':
        _showRegistrationPendingDialog(message: message);
      default:
        _showSnackBar(message, Colors.red);
    }
  }

  // ------------------------------------------------------------------ sign up (email, phone, password, confirm) + the code

  Future<void> _handleSignup() async {
    if (!_formKey.currentState!.validate()) return;

    final String email = _emailController.text.trim();
    final String phone = _phoneController.text.trim();
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final SignupCall call = widget.onSignup ??
          ({required final String email, required final String phone, required final String password, required final String confirm}) =>
              AuthService.signup(email: email, phoneNumber: phone, password: password, passwordConfirmation: confirm);
      final Map<String, dynamic> result = await call(email: email, phone: phone, password: _passwordController.text, confirm: _confirmController.text);
      if (!mounted) return;
      final Object? data = result['data'];
      final bool unavailable = data is Map && data['code_status'] == 'unavailable';
      final bool alreadyConfirmed = data is Map && data['phone_verified'] == true;
      setState(() => _isLoading = false);
      if (unavailable) {
        setState(() => _error = _loc.translate('sms_unavailable_try_later'));
      } else if (alreadyConfirmed) {
        _passwordController.clear();
        _confirmController.clear();
        _goTo(_Step.signIn, notice: _loc.translate('phone_confirmed_sign_in'));
      } else {
        _codeController.clear();
        _goTo(_Step.confirmPhone, notice: _loc.translateWith('code_sent_to', <Object?>[phone]));
      }
    } on AuthHttpException catch (e) {
      if (mounted) setState(() {
        _isLoading = false;
        _error = e.message;
      });
    } on Exception catch (e) {
      if (mounted) setState(() {
        _isLoading = false;
        _error = readableErrorMessage(e);
      });
    }
  }

  Future<void> _handleVerify() async {
    final String code = _codeController.text.trim();
    if (!RegExp(r"^\d{6}$").hasMatch(code)) {
      setState(() => _error = _loc.translate('enter_valid_code'));
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final Future<void> Function(String, String) verify =
          widget.onVerifyCode ?? (final String e, final String c) => AuthService.verifyRegistrationPhone(email: e, code: c);
      await verify(_emailController.text.trim(), code);
      if (!mounted) return;
      setState(() => _isLoading = false);
      // The phone is confirmed. Signing in again is with email and password only.
      _passwordController.clear();
      _confirmController.clear();
      _goTo(_Step.signIn, notice: _loc.translate('phone_confirmed_sign_in'));
    } on Exception catch (e) {
      if (mounted) setState(() {
        _isLoading = false;
        _error = e is AuthHttpException ? e.message : readableErrorMessage(e);
      });
    }
  }

  Future<void> _resend({final bool silent = false}) async {
    try {
      final Future<void> Function(String) resend = widget.onResendCode ?? (final String e) => AuthService.resendRegistrationCode(email: e);
      await resend(_emailController.text.trim());
      if (mounted && !silent) setState(() => _notice = _loc.translate('code_resent'));
    } on Exception catch (e) {
      if (mounted) setState(() => _error = e is AuthHttpException ? e.message : readableErrorMessage(e));
    }
  }

  // ------------------------------------------------------------------ Google

  /// Google's account chooser. An owner who is registered and approved goes straight in; someone new goes to the registration form
  /// (their phone is asked there, no password: Google is the sign-in); someone still waiting hears so.
  Future<void> _handleGoogle() async {
    final AuthProvider authProvider = Provider.of<AuthProvider>(context, listen: false);
    setState(() => _isLoading = true);
    final GoogleResult result = await authProvider.loginWithGoogle();
    if (!mounted) return;
    setState(() => _isLoading = false);

    switch (result) {
      case GoogleResult.signedIn:
        _showSnackBar(_loc.translate('login_successful'), Colors.green);
        Navigator.of(context).pop();
      case GoogleResult.cancelled:
        break;
      case GoogleResult.newUser:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (final BuildContext _) => RegisterBusinessScreen(googleSignup: authProvider.googleSignup),
          ),
        );
      case GoogleResult.failed:
        final String message = authProvider.errorMessage ?? _loc.translate('login_failed');
        if (authProvider.lastErrorCode == 'registration_pending') {
          _showRegistrationPendingDialog(message: message);
        } else {
          _showSnackBar(message, Colors.red);
        }
    }
  }

  /// A link in the small print under the buttons: opens the public page in the browser.
  InlineSpan _legalLink(final String text, final String url, final Color color) {
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: GestureDetector(
        onTap: () => launchUrlString(url, mode: LaunchMode.externalApplication),
        child: Text(text, style: TextStyle(color: color, fontSize: 10.sp, height: 1.4, decoration: TextDecoration.underline, decorationColor: color)),
      ),
    );
  }

  void _showSnackBar(final String message, final Color backgroundColor) {
    if (mounted) {
      if (backgroundColor == Colors.green) {
        ThemeConstants.showSuccessSnackBar(context, message);
      } else {
        ThemeConstants.showErrorSnackBar(context, message);
      }
    }
  }

  void _showRegistrationRejectedDialog({
    required final String message,
    required final String email,
    required final String password,
  }) {
    final bool isSwahili = LocalizationService.instance.isSwahili;
    showDialog<void>(
      context: context,
      builder: (final BuildContext ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161F30),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
          side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.4)),
        ),
        icon: Icon(Icons.cancel_outlined, color: Colors.redAccent, size: 40.sp),
        title: Text(
          isSwahili ? 'Usajili Haukukubaliwa' : 'Registration Not Approved',
          style: TextStyle(color: Colors.white, fontSize: 17.sp, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        content: Text(
          message,
          style: TextStyle(color: Colors.white70, fontSize: 13.sp),
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              isSwahili ? 'Funga' : 'Close',
              style: const TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
            ),
            icon: const Icon(Icons.edit_note, size: 18),
            label: Text(isSwahili ? 'Rekebisha Maombi' : 'Re-apply'),
            onPressed: () {
              Navigator.of(ctx).pop();
              // The email and password they just signed in with prove who they are; the phone on the registration is kept.
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (final BuildContext _) => RegisterBusinessScreen(
                    applicant: ApplicantCredentials(email: email, password: password),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showRegistrationPendingDialog({required final String message}) {
    final bool isSwahili = LocalizationService.instance.isSwahili;
    showDialog<void>(
      context: context,
      builder: (final BuildContext ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161F30),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
          side: BorderSide(color: Colors.amber.withValues(alpha: 0.4)),
        ),
        icon: Icon(Icons.hourglass_top_rounded, color: Colors.amber, size: 40.sp),
        title: Text(
          isSwahili ? 'Usajili Unasubiri Idhini' : 'Registration Pending Approval',
          style: TextStyle(color: Colors.white, fontSize: 17.sp, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              message,
              key: const ValueKey<String>('registration_pending_message'),
              style: TextStyle(color: Colors.white70, fontSize: 13.sp),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 12.h),
            Text(
              isSwahili
                  ? 'Likikubaliwa utatumiwa ujumbe mfupi kwenye simu yako, kisha uingie.'
                  : 'When it is approved you will get a text message on your phone, then you can sign in.',
              style: TextStyle(color: Colors.white54, fontSize: 12.sp),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: <Widget>[
          Center(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
              ),
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(isSwahili ? 'Nimeelewa' : 'Understood'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleForgotPassword() async {
    final String? verifiedEmail = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ForgotPasswordSheet(
        initialEmail: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
      ),
    );
    if (verifiedEmail != null && mounted) {
      setState(() {
        _emailController.text = verifiedEmail;
        _passwordController.clear();
      });
    }
  }

  // ------------------------------------------------------------------ the page

  static const Color _navy = Color(0xFF0A2E8A);
  static const Color _blue = Color(0xFF1450D6);
  static const Color _gold = Color(0xFFFFC21A);
  static const Color _ink = Color(0xFF14264F);

  static const String _rememberedKey = 'login_remembered_email';

  bool _remember = true;

  @override
  void initState() {
    super.initState();
    _loadRemembered();
  }

  /// "Remember me": the email last used on this phone is filled in again.
  Future<void> _loadRemembered() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? saved = prefs.getString(_rememberedKey);
      if (mounted && saved != null && saved.isNotEmpty && _emailController.text.isEmpty) {
        setState(() => _emailController.text = saved);
      }
    } on Exception {
      // nothing remembered: the person types it
    }
  }

  Future<void> _saveRemembered(final String email) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      if (_remember) {
        await prefs.setString(_rememberedKey, email);
      } else {
        await prefs.remove(_rememberedKey);
      }
    } on Exception {
      // not remembered this time
    }
  }

  /// Shows [child] under a fold-out animation when [show], nothing otherwise: how the phone and confirm-password fields appear when
  /// "Sign up" is chosen on the same page.
  Widget _reveal({required final bool show, required final Key key, required final Widget child}) {
    return AnimatedSwitcher(
      duration: _anim,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (final Widget c, final Animation<double> a) => SizeTransition(
        sizeFactor: a,
        axisAlignment: -1,
        child: FadeTransition(opacity: a, child: c),
      ),
      layoutBuilder: (final Widget? current, final List<Widget> previous) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[...previous, if (current != null) current],
      ),
      child: show ? KeyedSubtree(key: key, child: child) : SizedBox(key: ValueKey<String>('hidden_${key.toString()}'), width: double.infinity),
    );
  }

  Widget _messageBox(final String text, {required final bool isError, final Key? key}) {
    return Container(
      key: key,
      width: double.infinity,
      margin: EdgeInsets.only(top: 8.h),
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: isError ? const Color(0xFFFDECEA) : const Color(0xFFE8F1FF),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: isError ? const Color(0xFFF5C2BD) : const Color(0xFFBBD3F7)),
      ),
      child: Text(text, style: TextStyle(color: isError ? const Color(0xFFB3261E) : _ink, fontSize: 12.sp, height: 1.3)),
    );
  }

  @override
  Widget build(final BuildContext context) {
    final bool signUp = _step == _Step.signUp;
    final bool confirm = _step == _Step.confirmPhone;
    return Consumer<LocalizationService>(
      builder: (final BuildContext context, final LocalizationService loc, final Widget? child) => Scaffold(
        backgroundColor: _navy,
        resizeToAvoidBottomInset: true,
        body: Stack(
          children: <Widget>[
            const Positioned.fill(child: CustomPaint(painter: _BackdropPainter())),
            SafeArea(
              top: false,
              bottom: false,
              child: Column(
                children: <Widget>[
                  Expanded(
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: <Color>[Color(0xFFF4F9FF), Color(0xFFDCE9FF), Color(0xFFC4D8FF)]),
                      ),
                      child: Column(
                        children: <Widget>[
                  _hero(),
                  const SectionGlowDivider(key: ValueKey<String>('divider_hero'), lift: false),
                  _services(loc),
                  const SectionGlowDivider(key: ValueKey<String>('divider_services'), lift: false),
                  // The card takes what is left. Signing in fits without scrolling; the longer sign-up form scrolls inside it, between
                  // the fixed top and bottom.
                  Expanded(
                    child: LayoutBuilder(
                      builder: (final BuildContext context, final BoxConstraints box) => SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: box.maxHeight),
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: AnimatedOpacity(
                              opacity: _isLoading ? 0.4 : 1.0,
                              duration: const Duration(milliseconds: 300),
                              child: Padding(
                                padding: EdgeInsets.zero,
                                child: _card(loc, signUp, confirm, box.maxHeight),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                        ],
                      ),
                    ),
                  ),
                  _footer(loc),
                ],
              ),
            ),
            if (_isLoading)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.45),
                  child: Center(child: ThemeConstants.buildResponsiveLoadingWidget(context, message: loc.translate('signing_in'))),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The back button, then the name written in the colours of the flag of Tanzania with the line under it.
  Widget _hero() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: <Color>[Color(0xFF061F66), Color(0xFF0B3AA8), Color(0xFF1450D6)])),
      padding: EdgeInsets.fromLTRB(14.w, 6.h + MediaQuery.of(context).padding.top, 14.w, 6.h),
      child: Column(
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: () {
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                } else {
                  Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
                }
              },
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 5.h),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18.r),
                  border: Border.all(color: _blue, width: 1.4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.arrow_back_ios_new_rounded, color: _navy, size: 12.sp),
                    SizedBox(width: 4.w),
                    Text('Home', style: TextStyle(color: _navy, fontSize: 12.sp, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            height: 84.h,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                const Positioned.fill(child: CustomPaint(painter: _BrandArcsPainter())),
                const Padding(padding: EdgeInsets.only(top: 0), child: _FlagText(key: ValueKey<String>('brand_name'))),
              ],
            ),
          ),
          Text('Smart Access. One Platform.', style: TextStyle(color: Colors.white, fontSize: 13.sp, fontStyle: FontStyle.italic, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  /// The four services as pictures in a white strip, with the dashboard's glowing line standing between them.
  Widget _services(final LocalizationService loc) {
    return Container(
      key: const ValueKey<String>('service_art'),
      padding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 8.w),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(flex: 4, child: _tile(const BoxesArtPainter(), loc.translate('svc_shop'))),
            Padding(padding: EdgeInsets.symmetric(vertical: 8.h), child: const SizedBox(width: SectionGlowVerticalDivider.lineWidth, child: SectionGlowVerticalDivider(core: Color(0xFF1450D6)))),
            Expanded(flex: 4, child: _tile(const HouseArtPainter(), loc.translate('svc_rental'))),
            Padding(padding: EdgeInsets.symmetric(vertical: 8.h), child: const SizedBox(width: SectionGlowVerticalDivider.lineWidth, child: SectionGlowVerticalDivider(core: Color(0xFF1450D6)))),
            Expanded(flex: 4, child: _tile(const SalonArtPainter(), loc.translate('svc_salon'))),
            Padding(padding: EdgeInsets.symmetric(vertical: 8.h), child: const SizedBox(width: SectionGlowVerticalDivider.lineWidth, child: SectionGlowVerticalDivider(core: Color(0xFF1450D6)))),
            Expanded(flex: 5, child: _tile(null, loc.translate('svc_transport'))),
          ],
        ),
      ),
    );
  }

  /// One service: its picture ([painter], or the transport picture when null), its name and the gold stroke under it.
  Widget _tile(final CustomPainter? painter, final String label) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        SizedBox(height: 58.h, width: double.infinity, child: painter == null ? const Padding(padding: EdgeInsets.symmetric(horizontal: 2), child: TransportArt()) : CustomPaint(painter: painter)),
        SizedBox(height: 2.h),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: _navy, fontSize: 11.sp, fontWeight: FontWeight.w800)),
        SizedBox(height: 2.h),
        Container(width: 34.w, height: 3.h, decoration: BoxDecoration(color: _gold, borderRadius: BorderRadius.circular(2.r))),
      ],
    );
  }

  /// [text] in the middle with a line running out from each side of it: how the title, what it is for, and "or sign in with" are set.
  Widget _lined({required final String text, required final TextStyle style, required final double gap, final Key? key}) {
    final Widget line = Expanded(child: Divider(color: _navy.withValues(alpha: 0.5), height: 1));
    return Row(
      key: key,
      children: <Widget>[
        line,
        Flexible(flex: 4, child: Padding(padding: EdgeInsets.symmetric(horizontal: gap), child: Text(text, textAlign: TextAlign.center, style: style))),
        line,
      ],
    );
  }

  /// The white card: the title and what it is for, the fields, the buttons.
  Widget _card(final LocalizationService loc, final bool signUp, final bool confirm, final double minHeight) {
    return Container(
      constraints: BoxConstraints(minHeight: minHeight),
      alignment: Alignment.center,
      padding: EdgeInsets.fromLTRB(24.w, 12.h, 24.w, 14.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AnimatedSwitcher(
            duration: _anim,
            child: _lined(
              key: ValueKey<String>('login_title_${_step.name}'),
              text: loc.translate(confirm ? 'confirm_phone_title' : (signUp ? 'sign_up' : 'signin')),
              style: TextStyle(color: _navy, fontSize: 24.sp, fontWeight: FontWeight.w900),
              gap: 12.w,
            ),
          ),
          SizedBox(height: 10.h),
          AnimatedSize(
            duration: _anim,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: _anim,
              child: confirm ? _confirmPanel(loc) : _formPanel(loc, signUp),
            ),
          ),
          if (!confirm) ...<Widget>[
            SizedBox(height: 10.h),
            _lined(text: loc.translate('or_sign_in_with').toUpperCase(), style: TextStyle(color: _navy, fontSize: 10.sp, fontWeight: FontWeight.w800, letterSpacing: 0.6), gap: 10.w),
            SizedBox(height: 10.h),
            _GoogleButton(label: loc.translate('sign_in_with_google').toUpperCase(), onTap: _handleGoogle),
          ],
        ],
      ),
    );
  }

  /// The email and password fields, with the phone and confirm-password fields folding out under "Sign up".
  Widget _formPanel(final LocalizationService loc, final bool signUp) {
    return Form(
      key: _formKey,
      child: Column(
        key: const ValueKey<String>('form_panel'),
        children: <Widget>[
          _pillField(
            fieldKey: const ValueKey<String>('email_field'),
            controller: _emailController,
            hint: loc.translate('email'),
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: _emailError,
          ),
          _reveal(
            show: signUp,
            key: const ValueKey<String>('signup_phone'),
            child: Padding(
              padding: EdgeInsets.only(top: 8.h),
              child: _pillField(
                fieldKey: const ValueKey<String>('phone_field'),
                controller: _phoneController,
                hint: loc.translate('phone_number'),
                icon: Icons.phone_android_outlined,
                keyboardType: TextInputType.phone,
                validator: (final String? v) => _phonePattern.hasMatch((v ?? '').trim()) ? null : loc.translate('invalid_phone_number'),
              ),
            ),
          ),
          SizedBox(height: 8.h),
          _pillField(
            fieldKey: const ValueKey<String>('password_field'),
            controller: _passwordController,
            hint: loc.translate('password'),
            icon: Icons.lock_outline,
            obscureText: _obscurePassword,
            validator: (final String? v) {
              if (v == null || v.isEmpty) return loc.translate('enter_password_hint');
              if (signUp && v.length < 8) return loc.translate('password_min_8');
              return null;
            },
            suffix: IconButton(
              padding: EdgeInsets.zero,
              constraints: BoxConstraints(minWidth: 36.w, minHeight: 36.h),
              icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: _navy, size: 19.sp),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          _reveal(
            show: signUp,
            key: const ValueKey<String>('signup_confirm'),
            child: Padding(
              padding: EdgeInsets.only(top: 8.h),
              child: _pillField(
                fieldKey: const ValueKey<String>('confirm_field'),
                controller: _confirmController,
                hint: loc.translate('confirm_password'),
                icon: Icons.lock_reset,
                obscureText: _obscurePassword,
                validator: (final String? v) => v != _passwordController.text ? loc.translate('passwords_do_not_match') : null,
              ),
            ),
          ),
          if (_step == _Step.signIn)
            Padding(
              padding: EdgeInsets.only(top: 4.h),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 26.w,
                    height: 26.h,
                    child: Checkbox(
                      key: const ValueKey<String>('remember_me'),
                      value: _remember,
                      activeColor: _blue,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onChanged: (final bool? v) => setState(() => _remember = v ?? true),
                    ),
                  ),
                  SizedBox(width: 4.w),
                  Flexible(child: Text(loc.translate('remember_me'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: _ink, fontSize: 12.sp))),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: GestureDetector(
                      key: const ValueKey<String>('forgot_password'),
                      onTap: _handleForgotPassword,
                      child: Text(loc.translate('forgot_password'), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right, style: TextStyle(color: _blue, fontSize: 12.sp, fontWeight: FontWeight.w700, decoration: TextDecoration.underline)),
                    ),
                  ),
                ],
              ),
            )
          else
            SizedBox(height: 4.h),
          if (_notice != null) _messageBox(_notice!, isError: false, key: const ValueKey<String>('login_notice')),
          if (_error != null) _messageBox(_error!, isError: true, key: const ValueKey<String>('login_error')),
          SizedBox(height: 8.h),
          _mainButton(signUp ? loc.translate('sign_up').toUpperCase() : loc.translate('signin').toUpperCase(), const ValueKey<String>('login_button')),
        ],
      ),
    );
  }

  /// After signing up: the code that was texted to the phone.
  Widget _confirmPanel(final LocalizationService loc) {
    return Column(
      key: const ValueKey<String>('confirm_panel'),
      children: <Widget>[
        if (_notice != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(_notice!, key: const ValueKey<String>('confirm_notice'), style: TextStyle(color: _ink, fontSize: 13.sp, height: 1.35)),
          ),
        SizedBox(height: 10.h),
        _pillField(
          fieldKey: const ValueKey<String>('otp_field'),
          controller: _codeController,
          hint: loc.translate('verification_code'),
          icon: Icons.sms_outlined,
          keyboardType: TextInputType.number,
          formatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
        ),
        if (_error != null) _messageBox(_error!, isError: true, key: const ValueKey<String>('login_error')),
        SizedBox(height: 12.h),
        _mainButton(loc.translate('confirm_code_button').toUpperCase(), const ValueKey<String>('confirm_code_button')),
        Align(
          alignment: Alignment.center,
          child: TextButton(
            key: const ValueKey<String>('resend_code_button'),
            onPressed: _resend,
            child: Text(loc.translate('resend_code'), style: TextStyle(color: _blue, fontSize: 13.sp, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  /// The one strong button on the page.
  Widget _mainButton(final String label, final Key key) {
    return SizedBox(
      width: double.infinity,
      height: 48.h,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26.r),
          gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: <Color>[Color(0xFF2563EB), _navy]),
          boxShadow: <BoxShadow>[BoxShadow(color: _blue.withValues(alpha: 0.4), blurRadius: 14, offset: const Offset(0, 6))],
        ),
        child: ElevatedButton(
          key: key,
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26.r)),
          ),
          child: AnimatedSwitcher(
            duration: _anim,
            child: Row(
              key: ValueKey<String>(label),
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(Icons.login_rounded, size: 20.sp),
                SizedBox(width: 8.w),
                Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w900, letterSpacing: 1.4))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The dark blue foot of the page: "No account? Sign up" on a gold button, the small print and the line "Manage, Operate, Grow".
  Widget _footer(final LocalizationService loc) {
    final bool confirm = _step == _Step.confirmPhone;
    final bool signUp = _step == _Step.signUp;
    final bool toSignIn = confirm || signUp;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16.w, 2.h, 16.w, 22.h + MediaQuery.of(context).padding.bottom * 0.6),
      color: const Color(0xFFC4D8FF),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (!confirm) Flexible(child: Text(loc.translate(signUp ? 'have_account_question' : 'no_account_question'), style: TextStyle(color: _navy, fontSize: 13.sp, fontWeight: FontWeight.w700))),
              SizedBox(width: 8.w),
              GestureDetector(
                key: ValueKey<String>(toSignIn ? 'sign_in_link' : 'sign_up_link'),
                onTap: () => _goTo(toSignIn ? _Step.signIn : _Step.signUp),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 7.h),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: <Color>[Color(0xFFFFD84D), _gold]),
                    borderRadius: BorderRadius.circular(22.r),
                    boxShadow: <BoxShadow>[BoxShadow(color: _gold.withValues(alpha: 0.55), blurRadius: 14, spreadRadius: 1)],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(confirm ? loc.translate('back') : loc.translate(signUp ? 'signin' : 'sign_up'), style: TextStyle(color: _ink, fontSize: 13.sp, fontWeight: FontWeight.w900)),
                      Icon(Icons.chevron_right_rounded, color: _ink, size: 18.sp),
                    ],
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 6.h),
          Container(height: 1, margin: EdgeInsets.symmetric(horizontal: 30.w), decoration: BoxDecoration(gradient: LinearGradient(colors: <Color>[Colors.transparent, _navy.withValues(alpha: 0.35), Colors.transparent]))),
          SizedBox(height: 5.h),
          Text.rich(
            key: const ValueKey<String>('legal_links'),
            TextSpan(
              style: TextStyle(color: _ink, fontSize: 10.sp, height: 1.4),
              children: <InlineSpan>[
                TextSpan(text: '${loc.translate('by_continuing_you_accept')} '),
                _legalLink(loc.translate('terms_of_use'), 'https://3inone.nexoryatech.com/terms', _blue),
                TextSpan(text: ' ${loc.translate('and_word')} '),
                _legalLink(loc.translate('privacy_policy'), 'https://3inone.nexoryatech.com/privacy', _blue),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// A white field with a blue block for its icon at the left end, as in the design.
  Widget _pillField({
    required final TextEditingController controller,
    required final String hint,
    required final IconData icon,
    final Key? fieldKey,
    final bool obscureText = false,
    final Widget? suffix,
    final TextInputType? keyboardType,
    final String? Function(String?)? validator,
    final List<TextInputFormatter>? formatters,
  }) {
    final OutlineInputBorder edge = OutlineInputBorder(borderRadius: BorderRadius.circular(24.r), borderSide: const BorderSide(color: Color(0xFF9DBBF5), width: 1.2));
    return TextFormField(
      key: fieldKey,
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      inputFormatters: formatters,
      style: TextStyle(color: _ink, fontSize: 14.sp),
      cursorColor: _blue,
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: TextStyle(color: const Color(0xFF6B7FAE), fontSize: 14.sp),
        errorStyle: TextStyle(color: const Color(0xFFB3261E), fontSize: 11.sp, height: 1.1),
        prefixIcon: Container(
          width: 44.w,
          decoration: BoxDecoration(
            gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: <Color>[Color(0xFF2563EB), _navy]),
            borderRadius: BorderRadius.horizontal(left: Radius.circular(24.r)),
          ),
          child: Icon(icon, color: Colors.white, size: 19.sp),
        ),
        prefixIconConstraints: BoxConstraints.tightFor(width: 44.w, height: 44.h),
        suffixIcon: suffix,
        suffixIconConstraints: BoxConstraints(minWidth: 38.w, minHeight: 36.h),
        filled: true,
        fillColor: Colors.white,
        enabledBorder: edge,
        focusedBorder: edge.copyWith(borderSide: const BorderSide(color: _blue, width: 1.8)),
        errorBorder: edge.copyWith(borderSide: const BorderSide(color: Color(0xFFB3261E), width: 1.2)),
        focusedErrorBorder: edge.copyWith(borderSide: const BorderSide(color: Color(0xFFB3261E), width: 1.8)),
        contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 13.h),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------------- the flag of Tanzania

const Color _tzGold = Color(0xFFFCD116);
const Color _tzBlack = Color(0xFF000000);
const Color _tzGreen = Color(0xFF1EB53A);
const Color _tzBlue = Color(0xFF00A3DD);

/// The name, written in the colours of the flag of Tanzania: the 3 and the One are each a little flag (green above, blue below, the black
/// band edged in gold running across), with "iN" in gold between them. Each letter has a light edge and a soft shadow so it stands off the page.
class _FlagText extends StatelessWidget {
  const _FlagText({super.key});

  Widget _word(final String text, {final List<Color>? gradient, final bool italic = false}) {
    final TextStyle base = TextStyle(fontSize: 46.sp, fontWeight: FontWeight.w900, height: 1.0, fontStyle: italic ? FontStyle.italic : FontStyle.normal);
    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        Text(
          text,
          style: base.copyWith(
            shadows: const <Shadow>[Shadow(color: Color(0x730A2E8A), blurRadius: 10, offset: Offset(0, 5))],
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 7
              ..strokeJoin = StrokeJoin.round
              ..color = Colors.white,
          ),
        ),
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (final Rect r) => gradient != null
              ? LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: gradient).createShader(r)
              : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[_tzGreen, _tzGreen, _tzGold, _tzGold, _tzBlack, _tzBlack, _tzGold, _tzGold, _tzBlue, _tzBlue],
            stops: <double>[0, 0.36, 0.36, 0.43, 0.43, 0.57, 0.57, 0.64, 0.64, 1],
          ).createShader(r),
          child: Text(text, style: base.copyWith(color: Colors.white)),
        ),
      ],
    );
  }

  @override
  Widget build(final BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          _word('3'),
          SizedBox(width: 8.w),
          _word('iN', gradient: const <Color>[Color(0xFFFFE680), _tzGold, Color(0xFFE5A800)], italic: true),
          SizedBox(width: 8.w),
          _word('One'),
        ],
      ),
    );
  }
}

/// The arcs over and under the name: three tapering bands in the flag's green, gold and blue with a soft glow, sparks at their ends, and
/// a gold swoosh with a blue trail below.
class _BrandArcsPainter extends CustomPainter {
  const _BrandArcsPainter();

  /// A band that is thick in the middle and comes to a point at both ends, from [a] to [b] bowing through [control].
  static Path _band(final Offset a, final Offset control, final Offset b, final double thick) {
    final Offset bow = Offset(control.dx, control.dy + thick * 2);
    return Path()
      ..moveTo(a.dx, a.dy)
      ..quadraticBezierTo(control.dx, control.dy, b.dx, b.dy)
      ..quadraticBezierTo(bow.dx, bow.dy, a.dx, a.dy)
      ..close();
  }

  void _glowBand(final Canvas canvas, final Path path, final Color color) {
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.55)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    canvas.drawPath(path, Paint()..color = color);
  }

  void _spark(final Canvas canvas, final Offset c, final double r, final Color color) {
    canvas.drawCircle(c, r * 2.2, Paint()..color = color.withValues(alpha: 0.35)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    canvas.drawCircle(c, r, Paint()..color = color);
    canvas.drawCircle(c, r * 0.4, Paint()..color = Colors.white);
  }

  @override
  void paint(final Canvas canvas, final Size size) {
    final double w = size.width;
    final double h = size.height;

    // three bands over the name, the longest outside: gold, green and blue
    _glowBand(canvas, _band(Offset(w * 0.22, h * 0.20), Offset(w * 0.5, -h * 0.20), Offset(w * 0.78, h * 0.20), 3), const Color(0xFFFFC21A));
    _glowBand(canvas, _band(Offset(w * 0.29, h * 0.21), Offset(w * 0.5, -h * 0.06), Offset(w * 0.71, h * 0.21), 2.6), _tzGreen);
    _glowBand(canvas, _band(Offset(w * 0.36, h * 0.22), Offset(w * 0.5, h * 0.06), Offset(w * 0.64, h * 0.22), 2.2), const Color(0xFF1450D6));
    _spark(canvas, Offset(w * 0.22, h * 0.20), 2.6, const Color(0xFFFFC21A));
    _spark(canvas, Offset(w * 0.78, h * 0.20), 2.6, const Color(0xFFFFC21A));
    _spark(canvas, Offset(w * 0.5, h * 0.015), 2.2, Colors.white);

    // a swoosh under the name: gold, with a thinner blue trail and a spark at each end
    _glowBand(canvas, _band(Offset(w * 0.16, h * 0.93), Offset(w * 0.5, h * 0.70), Offset(w * 0.84, h * 0.93), 3.4), const Color(0xFFFFC21A));
    _glowBand(canvas, _band(Offset(w * 0.30, h * 0.96), Offset(w * 0.5, h * 0.84), Offset(w * 0.70, h * 0.96), 2.4), const Color(0xFF1450D6));
    _spark(canvas, Offset(w * 0.16, h * 0.93), 2.6, _tzGreen);
    _spark(canvas, Offset(w * 0.84, h * 0.93), 2.6, _tzBlue);
  }

  @override
  bool shouldRepaint(covariant final CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------------------------------- the background

/// The page: white at the top, flowing into blue, with gold sweeps at the corners.
class _BackdropPainter extends CustomPainter {
  const _BackdropPainter();

  @override
  void paint(final Canvas canvas, final Size size) {
    final double w = size.width;
    final double h = size.height;
    final Rect rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0xFFF4F9FF), Color(0xFFBFD8FF), Color(0xFF3B82F6), Color(0xFF0B3AA8)],
          stops: <double>[0.0, 0.3, 0.62, 1.0],
        ).createShader(rect),
    );
    // flowing white light across the middle
    canvas.drawPath(
      Path()
        ..moveTo(0, h * 0.30)
        ..cubicTo(w * 0.3, h * 0.22, w * 0.6, h * 0.42, w, h * 0.30)
        ..lineTo(w, h * 0.46)
        ..cubicTo(w * 0.6, h * 0.58, w * 0.3, h * 0.38, 0, h * 0.50)
        ..close(),
      Paint()..color = Colors.white.withValues(alpha: 0.22),
    );
    // a gold sweep at the right edge
    canvas.drawPath(
      Path()
        ..moveTo(w, h * 0.62)
        ..quadraticBezierTo(w * 0.94, h * 0.70, w, h * 0.80)
        ..lineTo(w, h * 0.76)
        ..quadraticBezierTo(w * 0.965, h * 0.70, w, h * 0.66)
        ..close(),
      Paint()..color = const Color(0xFFFFC21A),
    );
  }

  @override
  bool shouldRepaint(covariant final CustomPainter oldDelegate) => false;
}

/// The "Sign in with Google" button: white with a blue edge and Google's multicolour G, as in the design.
class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(final BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(26.r),
      child: InkWell(
        key: const ValueKey<String>('google_signin_button'),
        borderRadius: BorderRadius.circular(26.r),
        onTap: onTap,
        child: Container(
          height: 46.h,
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 18.w),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26.r),
            border: Border.all(color: const Color(0xFF1450D6), width: 1.4),
          ),
          child: Row(
            children: <Widget>[
              CustomPaint(size: Size(24.w, 24.w), painter: const _GoogleGPainter()),
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: const Color(0xFF0A2E8A), fontSize: 14.sp, fontWeight: FontWeight.w900, letterSpacing: 0.8),
                ),
              ),
              SizedBox(width: 24.w),
            ],
          ),
        ),
      ),
    );
  }
}

/// Google's multicolour "G", drawn from four arcs and a bar (no image file needed).
class _GoogleGPainter extends CustomPainter {
  const _GoogleGPainter();

  @override
  void paint(final Canvas canvas, final Size size) {
    final double w = size.width;
    final double stroke = w * 0.22;
    final Rect rect = Rect.fromLTWH(stroke / 2, stroke / 2, w - stroke, w - stroke);
    Paint arc(final Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    const double deg = 3.1415926535 / 180;
    canvas.drawArc(rect, -45 * deg, -95 * deg, false, arc(const Color(0xFFEA4335))); // red, top
    canvas.drawArc(rect, 135 * deg, 90 * deg, false, arc(const Color(0xFFFBBC05))); // yellow, left
    canvas.drawArc(rect, 45 * deg, 90 * deg, false, arc(const Color(0xFF34A853))); // green, bottom
    canvas.drawArc(rect, -45 * deg, 45 * deg, false, arc(const Color(0xFF4285F4))); // blue, right
    canvas.drawRect(Rect.fromLTWH(w * 0.5, w * 0.4, w * 0.47, stroke), Paint()..color = const Color(0xFF4285F4)); // the bar
  }

  @override
  bool shouldRepaint(covariant final CustomPainter oldDelegate) => false;
}
