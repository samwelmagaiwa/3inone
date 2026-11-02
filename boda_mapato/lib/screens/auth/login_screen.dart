import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_screenutil/flutter_screenutil.dart";
import "package:provider/provider.dart";
import "package:url_launcher/url_launcher_string.dart";

import "../../constants/colors.dart";
import "../../constants/theme_constants.dart";
import "../../providers/auth_provider.dart";
import "../../services/auth_service.dart";
import "../../services/localization_service.dart";
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
  static const Color _navy = Color(0xFF2D3566);
  static const Color _teal = Color(0xFF008080);
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
  late _Step _step;
  String? _error;
  String? _notice;

  LocalizationService get _loc => LocalizationService.instance;

  @override
  void initState() {
    super.initState();
    _step = widget.startInSignup ? _Step.signUp : _Step.signIn;
  }

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
        child: Text(text, style: TextStyle(color: color, fontSize: 13.sp, height: 1.5)),
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
      margin: EdgeInsets.only(top: 14.h),
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: isError ? const Color(0xFF5A1D1D) : Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: isError ? const Color(0xFFFFB4AB) : Colors.white24),
      ),
      child: Text(text, style: TextStyle(color: isError ? const Color(0xFFFFDAD6) : Colors.white, fontSize: 13.sp, height: 1.4)),
    );
  }

  @override
  Widget build(final BuildContext context) {
    final bool signUp = _step == _Step.signUp;
    final bool confirm = _step == _Step.confirmPhone;
    return Consumer<LocalizationService>(
      builder: (final BuildContext context, final LocalizationService loc, final Widget? child) => Scaffold(
        backgroundColor: _navy,
        body: Stack(
          children: <Widget>[
            const Positioned.fill(child: CustomPaint(painter: _BlobPainter())),
            SafeArea(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                child: AnimatedOpacity(
                  opacity: _isLoading ? 0.3 : 1.0,
                  duration: const Duration(milliseconds: 300),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 28.w),
                    child: Column(
                      children: <Widget>[
                        SizedBox(height: 96.h),
                        AnimatedSwitcher(
                          duration: _anim,
                          child: Text(
                            loc.translate(confirm ? 'confirm_phone_title' : (signUp ? 'sign_up' : 'signin')),
                            key: ValueKey<String>('login_title_${_step.name}'),
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white, fontSize: 36.sp, fontWeight: FontWeight.w800),
                          ),
                        ),
                        SizedBox(height: 28.h),
                        AnimatedSize(
                          duration: _anim,
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.topCenter,
                          child: AnimatedSwitcher(
                            duration: _anim,
                            child: confirm ? _confirmPanel(loc) : _formPanel(loc, signUp),
                          ),
                        ),
                        if (_step == _Step.signIn) ...<Widget>[
                          SizedBox(height: 10.h),
                          TextButton(
                            onPressed: _handleForgotPassword,
                            child: Text(loc.translate('forgot_password'), style: TextStyle(color: Colors.white60, fontSize: 14.sp)),
                          ),
                        ],
                        if (!confirm) ...<Widget>[
                          SizedBox(height: 22.h),
                          Text(
                            loc.translate('or_sign_in_with').toUpperCase(),
                            style: TextStyle(color: Colors.white, fontSize: 16.sp, fontWeight: FontWeight.w800),
                          ),
                          SizedBox(height: 18.h),
                          _GoogleButton(label: loc.translate('sign_in_with_google').toUpperCase(), onTap: _handleGoogle),
                        ],
                        SizedBox(height: 36.h),
                        _switchLine(loc),
                        SizedBox(height: 14.h),
                        Text.rich(
                          key: const ValueKey<String>('legal_links'),
                          TextSpan(
                            style: TextStyle(color: Colors.white54, fontSize: 12.sp, height: 1.5),
                            children: <InlineSpan>[
                              TextSpan(text: '${loc.translate('by_continuing_you_accept')} '),
                              _legalLink(loc.translate('terms_of_use'), 'https://3inone.nexoryatech.com/terms', Colors.white),
                              TextSpan(text: ' ${loc.translate('and_word')} '),
                              _legalLink(loc.translate('privacy_policy'), 'https://3inone.nexoryatech.com/privacy', Colors.white),
                            ],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 28.h),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            if (_isLoading)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.6),
                  child: Center(
                    child: ThemeConstants.buildResponsiveLoadingWidget(context, message: loc.translate('signing_in')),
                  ),
                ),
              ),

            // Back to the landing page: last in the Stack so it sits on top and is tappable
            Positioned(
              top: MediaQuery.of(context).padding.top + 10.h,
              left: 16.w,
              child: GestureDetector(
                onTap: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  } else {
                    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
                  }
                },
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(14.r)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 14.sp),
                      SizedBox(width: 5.w),
                      Text('Home', style: TextStyle(color: Colors.white, fontSize: 13.sp, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
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
            icon: Icons.email,
            keyboardType: TextInputType.emailAddress,
            validator: _emailError,
          ),
          _reveal(
            show: signUp,
            key: const ValueKey<String>('signup_phone'),
            child: Padding(
              padding: EdgeInsets.only(top: 16.h),
              child: _pillField(
                fieldKey: const ValueKey<String>('phone_field'),
                controller: _phoneController,
                hint: loc.translate('phone_number'),
                icon: Icons.phone_android,
                keyboardType: TextInputType.phone,
                validator: (final String? v) => _phonePattern.hasMatch((v ?? '').trim()) ? null : loc.translate('invalid_phone_number'),
              ),
            ),
          ),
          SizedBox(height: 16.h),
          _pillField(
            fieldKey: const ValueKey<String>('password_field'),
            controller: _passwordController,
            hint: loc.translate('password'),
            icon: Icons.lock,
            obscureText: _obscurePassword,
            validator: (final String? v) {
              if (v == null || v.isEmpty) return loc.translate('enter_password_hint');
              if (signUp && v.length < 8) return loc.translate('password_min_8');
              return null;
            },
            suffix: IconButton(
              icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off, color: Colors.black38, size: 20.sp),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          _reveal(
            show: signUp,
            key: const ValueKey<String>('signup_confirm'),
            child: Padding(
              padding: EdgeInsets.only(top: 16.h),
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
          if (_notice != null) _messageBox(_notice!, isError: false, key: const ValueKey<String>('login_notice')),
          if (_error != null) _messageBox(_error!, isError: true, key: const ValueKey<String>('login_error')),
          SizedBox(height: 22.h),
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
          Text(_notice!, key: const ValueKey<String>('confirm_notice'), textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 14.sp, height: 1.4)),
        SizedBox(height: 18.h),
        _pillField(
          fieldKey: const ValueKey<String>('otp_field'),
          controller: _codeController,
          hint: loc.translate('verification_code'),
          icon: Icons.sms,
          keyboardType: TextInputType.number,
          formatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
        ),
        if (_error != null) _messageBox(_error!, isError: true, key: const ValueKey<String>('login_error')),
        SizedBox(height: 22.h),
        _mainButton(loc.translate('confirm_code_button').toUpperCase(), const ValueKey<String>('confirm_code_button')),
        TextButton(
          key: const ValueKey<String>('resend_code_button'),
          onPressed: _resend,
          child: Text(loc.translate('resend_code'), style: TextStyle(color: Colors.white70, fontSize: 14.sp)),
        ),
      ],
    );
  }

  Widget _mainButton(final String label, final Key key) {
    return SizedBox(
      width: double.infinity,
      height: 56.h,
      child: ElevatedButton(
        key: key,
        onPressed: _submit,
        style: ElevatedButton.styleFrom(
          backgroundColor: _teal,
          foregroundColor: Colors.white,
          elevation: 8,
          shadowColor: Colors.black54,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30.r)),
        ),
        child: AnimatedSwitcher(
          duration: _anim,
          child: Text(label, key: ValueKey<String>(label), style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.w800, letterSpacing: 1)),
        ),
      ),
    );
  }

  /// "No account? Sign up" / "Have an account? Sign in" under the buttons: switches the page between the two.
  Widget _switchLine(final LocalizationService loc) {
    final bool confirm = _step == _Step.confirmPhone;
    final bool signUp = _step == _Step.signUp;
    final String question = loc.translate(signUp ? 'have_account_question' : 'no_account_question');
    final String action = loc.translate(signUp ? 'signin' : 'sign_up');
    return Text.rich(
      TextSpan(
        style: TextStyle(color: Colors.white, fontSize: 15.sp),
        children: <InlineSpan>[
          if (!confirm) TextSpan(text: '$question '),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: GestureDetector(
              key: ValueKey<String>(confirm || signUp ? 'sign_in_link' : 'sign_up_link'),
              onTap: () => _goTo(confirm || signUp ? _Step.signIn : _Step.signUp),
              child: Text(
                confirm ? loc.translate('back') : action,
                style: TextStyle(color: Colors.white, fontSize: 15.sp, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }

  /// A white pill with an icon and a grey hint, as in the design.
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
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30.r),
        boxShadow: const <BoxShadow>[BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: TextFormField(
        key: fieldKey,
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        validator: validator,
        inputFormatters: formatters,
        style: TextStyle(color: Colors.black87, fontSize: 16.sp),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.black38, fontSize: 16.sp),
          errorStyle: TextStyle(color: const Color(0xFFB3261E), fontSize: 12.sp),
          prefixIcon: Icon(icon, color: Colors.black45, size: 22.sp),
          suffixIcon: suffix,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 18.h),
        ),
      ),
    );
  }
}

/// The background of the page: the navy ground with teal shapes at the top left and the bottom right.
class _BlobPainter extends CustomPainter {
  const _BlobPainter();

  @override
  void paint(final Canvas canvas, final Size size) {
    final double w = size.width;
    final double h = size.height;

    final Path back = Path()
      ..moveTo(w * 0.35, 0)
      ..lineTo(w * 0.85, 0)
      ..cubicTo(w * 0.78, h * 0.05, w * 0.55, h * 0.04, w * 0.5, h * 0.1)
      ..cubicTo(w * 0.45, h * 0.17, w * 0.3, h * 0.12, w * 0.35, 0)
      ..close();
    canvas.drawPath(back, Paint()..color = const Color(0xFF2A7F94).withValues(alpha: 0.85));

    final Path top = Path()
      ..moveTo(0, 0)
      ..lineTo(w * 0.62, 0)
      ..cubicTo(w * 0.5, h * 0.07, w * 0.58, h * 0.15, w * 0.3, h * 0.17)
      ..cubicTo(w * 0.1, h * 0.18, w * 0.04, h * 0.22, 0, h * 0.3)
      ..close();
    canvas.drawPath(top, Paint()..color = const Color(0xFF008080));

    final Path bottomLeft = Path()
      ..moveTo(0, h * 0.88)
      ..cubicTo(w * 0.12, h * 0.9, w * 0.22, h * 0.96, w * 0.2, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(bottomLeft, Paint()..color = const Color(0xFF2A7F94).withValues(alpha: 0.85));

    final Path bottomRight = Path()
      ..moveTo(w, h)
      ..lineTo(w * 0.62, h)
      ..cubicTo(w * 0.6, h * 0.94, w * 0.75, h * 0.9, w * 0.9, h * 0.9)
      ..cubicTo(w * 0.97, h * 0.9, w, h * 0.87, w, h * 0.83)
      ..close();
    canvas.drawPath(bottomRight, Paint()..color = const Color(0xFF008080));
  }

  @override
  bool shouldRepaint(covariant final CustomPainter oldDelegate) => false;
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

/// The "Sign in with Google" button: a white pill with Google's G, as in the design.
class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(final BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 6,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(30.r),
      child: InkWell(
        key: const ValueKey<String>('google_signin_button'),
        borderRadius: BorderRadius.circular(30.r),
        onTap: onTap,
        child: Container(
          height: 56.h,
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 28.w),
          child: Row(
            children: <Widget>[
              CustomPaint(size: Size(28.w, 28.w), painter: const _GoogleGPainter()),
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: const Color(0xFF111111), fontSize: 14.sp, fontWeight: FontWeight.w800, letterSpacing: 1.4),
                ),
              ),
              SizedBox(width: 28.w),
            ],
          ),
        ),
      ),
    );
  }
}
