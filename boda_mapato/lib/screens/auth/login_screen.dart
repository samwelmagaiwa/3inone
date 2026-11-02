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

  static const Color _blue = Color(0xFF1565C0);
  static const Color _ink = Color(0xFF14264F);
  static const Color _soft = Color(0xFFEAF1FB);
  static const Color _green = Color(0xFF2ECC40);

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
        color: isError ? const Color(0xFFFDECEA) : const Color(0xFFE8F1FF),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: isError ? const Color(0xFFF5C2BD) : const Color(0xFFBBD3F7)),
      ),
      child: Text(text, style: TextStyle(color: isError ? const Color(0xFFB3261E) : _ink, fontSize: 13.sp, height: 1.4)),
    );
  }

  @override
  Widget build(final BuildContext context) {
    final bool signUp = _step == _Step.signUp;
    final bool confirm = _step == _Step.confirmPhone;
    return Consumer<LocalizationService>(
      builder: (final BuildContext context, final LocalizationService loc, final Widget? child) => Scaffold(
        backgroundColor: _soft,
        body: Stack(
          children: <Widget>[
            LayoutBuilder(
              builder: (final BuildContext context, final BoxConstraints box) => SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                child: ConstrainedBox(
                  // On a tall screen the footer waves sit at the very bottom; on a short one the page scrolls to them.
                  constraints: BoxConstraints(minHeight: box.maxHeight),
                  child: AnimatedOpacity(
                    opacity: _isLoading ? 0.4 : 1.0,
                    duration: const Duration(milliseconds: 300),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Column(
                          children: <Widget>[
                            _header(loc),
                            Transform.translate(
                              offset: Offset(0, -34.h),
                              child: Padding(padding: EdgeInsets.symmetric(horizontal: 22.w), child: _card(loc, signUp, confirm)),
                            ),
                          ],
                        ),
                        Column(
                          children: <Widget>[
                            _switchLine(loc),
                            SizedBox(height: 14.h),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 28.w),
                              child: Text.rich(
                                key: const ValueKey<String>('legal_links'),
                                TextSpan(
                                  style: TextStyle(color: const Color(0xFF51608A), fontSize: 12.sp, height: 1.5),
                                  children: <InlineSpan>[
                                    TextSpan(text: '${loc.translate('by_continuing_you_accept')} '),
                                    _legalLink(loc.translate('terms_of_use'), 'https://3inone.nexoryatech.com/terms', _blue),
                                    TextSpan(text: ' ${loc.translate('and_word')} '),
                                    _legalLink(loc.translate('privacy_policy'), 'https://3inone.nexoryatech.com/privacy', _blue),
                                  ],
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            SizedBox(height: 12.h),
                            SizedBox(height: 110.h, width: double.infinity, child: const CustomPaint(painter: _FooterPainter())),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            if (_isLoading)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.45),
                  child: Center(
                    child: ThemeConstants.buildResponsiveLoadingWidget(context, message: loc.translate('signing_in')),
                  ),
                ),
              ),

          ],
        ),
      ),
    );
  }

  /// The blue top of the page: a city of buildings behind, the logo, the name, the line under it and the four services of the app.
  Widget _header(final LocalizationService loc) {
    final double top = MediaQuery.of(context).padding.top;
    return SizedBox(
      height: 420.h + top,
      child: Stack(
        children: <Widget>[
          const Positioned.fill(child: CustomPaint(painter: _HeaderPainter())),
          Padding(
            padding: EdgeInsets.only(top: top + 52.h),
            child: Align(
              alignment: Alignment.topCenter,
              child: Column(
                children: <Widget>[
                  Container(
                    padding: EdgeInsets.all(4.w),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.18),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.7), width: 2),
                      boxShadow: <BoxShadow>[BoxShadow(color: const Color(0xFF4FC3F7).withValues(alpha: 0.5), blurRadius: 24, spreadRadius: 2)],
                    ),
                    child: ClipOval(child: Image.asset('assets/images/app_icon.png', width: 84.w, height: 84.w, fit: BoxFit.cover)),
                  ),
                  SizedBox(height: 8.h),
                  Text.rich(
                    key: const ValueKey<String>('brand_name'),
                    TextSpan(
                      style: TextStyle(fontSize: 42.sp, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, shadows: const <Shadow>[Shadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 3))]),
                      children: const <InlineSpan>[
                        TextSpan(text: '3 ', style: TextStyle(color: Color(0xFF39E05A))),
                        TextSpan(text: 'iN ', style: TextStyle(color: Colors.white)),
                        TextSpan(text: 'One', style: TextStyle(color: Color(0xFF4FC3F7))),
                      ],
                    ),
                  ),
                  Text(
                    'Smart Access. One Platform.',
                    style: TextStyle(color: Colors.white, fontSize: 14.sp, fontStyle: FontStyle.italic, letterSpacing: 0.4),
                  ),
                  SizedBox(height: 14.h),
                  Row(
                    key: const ValueKey<String>('service_chips'),
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      _serviceChip(Icons.apartment_rounded, loc.translate('svc_rental'), const Color(0xFF1ABC9C)),
                      _serviceChip(Icons.two_wheeler_rounded, loc.translate('svc_transport'), const Color(0xFF7B52E8)),
                      _serviceChip(Icons.storefront_rounded, loc.translate('svc_shop'), const Color(0xFFF39C12)),
                      _serviceChip(Icons.content_cut_rounded, loc.translate('svc_salon'), const Color(0xFFE91E8C)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        // Back to the landing page
          Positioned(
            top: top + 10.h,
            left: 14.w,
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
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(20.r),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 14.sp),
                    SizedBox(width: 4.w),
                    Icon(Icons.home_rounded, color: Colors.white, size: 18.sp),
                    SizedBox(width: 4.w),
                    Text('Home', style: TextStyle(color: Colors.white, fontSize: 13.sp, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _serviceChip(final IconData icon, final String label, final Color color) {
    return SizedBox(
      width: 78.w,
      child: Column(
        children: <Widget>[
          Container(
            width: 46.w,
            height: 46.w,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const <BoxShadow>[BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3))],
            ),
            child: Icon(icon, color: Colors.white, size: 24.sp),
          ),
          SizedBox(height: 4.h),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 10.sp, fontWeight: FontWeight.w600, shadows: const <Shadow>[Shadow(color: Colors.black54, blurRadius: 4)])),
        ],
      ),
    );
  }

  /// The white card with the title, the form and the Google button.
  Widget _card(final LocalizationService loc, final bool signUp, final bool confirm) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28.r),
        boxShadow: <BoxShadow>[BoxShadow(color: _blue.withValues(alpha: 0.22), blurRadius: 28, offset: const Offset(0, 10))],
      ),
      padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 22.h),
      child: Column(
        children: <Widget>[
          AnimatedSwitcher(
            duration: _anim,
            child: Text(
              loc.translate(confirm ? 'confirm_phone_title' : (signUp ? 'sign_up' : 'signin')),
              key: ValueKey<String>('login_title_${_step.name}'),
              textAlign: TextAlign.center,
              style: TextStyle(color: _ink, fontSize: 30.sp, fontWeight: FontWeight.w800),
            ),
          ),
          SizedBox(height: 6.h),
          Container(
            width: 64.w,
            height: 4.h,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(4.r), gradient: const LinearGradient(colors: <Color>[_green, _blue])),
          ),
          SizedBox(height: 18.h),
          AnimatedSize(
            duration: _anim,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: _anim,
              child: confirm ? _confirmPanel(loc) : _formPanel(loc, signUp),
            ),
          ),
          if (_step == _Step.signIn)
            TextButton(
              onPressed: _handleForgotPassword,
              child: Text(loc.translate('forgot_password'), style: TextStyle(color: _blue, fontSize: 14.sp, fontWeight: FontWeight.w600)),
            ),
          if (!confirm) ...<Widget>[
            SizedBox(height: 6.h),
            Row(
              children: <Widget>[
                const Expanded(child: Divider(color: Color(0xFFD5DFF2))),
                Container(
                  margin: EdgeInsets.symmetric(horizontal: 10.w),
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 5.h),
                  decoration: BoxDecoration(color: const Color(0xFFE3ECFA), borderRadius: BorderRadius.circular(14.r)),
                  child: Text(loc.translate('or_sign_in_with').toUpperCase(), style: TextStyle(color: const Color(0xFF51608A), fontSize: 11.sp, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
                ),
                const Expanded(child: Divider(color: Color(0xFFD5DFF2))),
              ],
            ),
            SizedBox(height: 14.h),
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
            icon: Icons.email,
            keyboardType: TextInputType.emailAddress,
            validator: _emailError,
          ),
          _reveal(
            show: signUp,
            key: const ValueKey<String>('signup_phone'),
            child: Padding(
              padding: EdgeInsets.only(top: 14.h),
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
          SizedBox(height: 14.h),
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
              icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off, color: const Color(0xFF7B8AA6), size: 20.sp),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          _reveal(
            show: signUp,
            key: const ValueKey<String>('signup_confirm'),
            child: Padding(
              padding: EdgeInsets.only(top: 14.h),
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
          SizedBox(height: 20.h),
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
          Text(_notice!, key: const ValueKey<String>('confirm_notice'), textAlign: TextAlign.center, style: TextStyle(color: const Color(0xFF334155), fontSize: 14.sp, height: 1.4)),
        SizedBox(height: 16.h),
        _pillField(
          fieldKey: const ValueKey<String>('otp_field'),
          controller: _codeController,
          hint: loc.translate('verification_code'),
          icon: Icons.sms,
          keyboardType: TextInputType.number,
          formatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
        ),
        if (_error != null) _messageBox(_error!, isError: true, key: const ValueKey<String>('login_error')),
        SizedBox(height: 20.h),
        _mainButton(loc.translate('confirm_code_button').toUpperCase(), const ValueKey<String>('confirm_code_button')),
        TextButton(
          key: const ValueKey<String>('resend_code_button'),
          onPressed: _resend,
          child: Text(loc.translate('resend_code'), style: TextStyle(color: _blue, fontSize: 14.sp, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  Widget _mainButton(final String label, final Key key) {
    return SizedBox(
      width: double.infinity,
      height: 54.h,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30.r),
          gradient: const LinearGradient(colors: <Color>[_blue, _green]),
          boxShadow: <BoxShadow>[BoxShadow(color: _blue.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 6))],
        ),
        child: ElevatedButton(
          key: key,
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30.r)),
          ),
          child: AnimatedSwitcher(
            duration: _anim,
            child: Text(label, key: ValueKey<String>(label), style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
          ),
        ),
      ),
    );
  }

  /// "No account? Sign up" / "Have an account? Sign in" under the card: switches the page between the two.
  Widget _switchLine(final LocalizationService loc) {
    final bool confirm = _step == _Step.confirmPhone;
    final bool signUp = _step == _Step.signUp;
    final String question = loc.translate(signUp ? 'have_account_question' : 'no_account_question');
    final String action = loc.translate(signUp ? 'signin' : 'sign_up');
    return Text.rich(
      TextSpan(
        style: TextStyle(color: _ink, fontSize: 15.sp),
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
                style: TextStyle(color: _blue, fontSize: 15.sp, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }

  /// A light pill with a blue icon, as in the design.
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
    return TextFormField(
      key: fieldKey,
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      inputFormatters: formatters,
      style: TextStyle(color: _ink, fontSize: 16.sp),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: const Color(0xFF7B8AA6), fontSize: 16.sp),
        errorStyle: TextStyle(color: const Color(0xFFB3261E), fontSize: 12.sp),
        prefixIcon: Icon(icon, color: _blue, size: 22.sp),
        suffixIcon: suffix,
        filled: true,
        fillColor: const Color(0xFFF4F8FF),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30.r), borderSide: const BorderSide(color: Color(0xFFB8CCF0), width: 1.2)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30.r), borderSide: const BorderSide(color: _blue, width: 1.8)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30.r), borderSide: const BorderSide(color: Color(0xFFB3261E), width: 1.2)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30.r), borderSide: const BorderSide(color: Color(0xFFB3261E), width: 1.8)),
        contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
      ),
    );
  }
}

/// The blue top of the page: the sky, a city of buildings behind (rentals, shops, offices) and the green and blue waves that carry it
/// down into the card.
class _HeaderPainter extends CustomPainter {
  const _HeaderPainter();

  @override
  void paint(final Canvas canvas, final Size size) {
    final double w = size.width;
    final double h = size.height;
    final Rect rect = Offset.zero & size;

    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF041A52), Color(0xFF0A4DB5), Color(0xFF1E88E5)],
        ).createShader(rect),
    );

    // soft light spots, like the lights of a city at dusk
    final Paint dot = Paint()..color = Colors.white.withValues(alpha: 0.10);
    for (double y = h * 0.12; y < h * 0.5; y += 16) {
      for (double x = w * 0.03; x < w * 0.22; x += 16) {
        canvas.drawCircle(Offset(x, y), 1.6, dot);
      }
    }

    final double ground = h * 0.80;
    final Paint wall = Paint()..color = Colors.white.withValues(alpha: 0.13);
    final Paint window = Paint()..color = Colors.white.withValues(alpha: 0.30);
    void building(final double x, final double bw, final double bh) {
      final double top = ground - bh;
      canvas.drawRect(Rect.fromLTWH(x, top, bw, bh), wall);
      for (double yy = top + 8; yy < ground - 8; yy += 14) {
        for (double xx = x + 6; xx < x + bw - 6; xx += 11) {
          canvas.drawRect(Rect.fromLTWH(xx, yy, 4, 6), window);
        }
      }
    }

    // left: low buildings (shops and salons); right: taller blocks (rentals and offices)
    building(w * 0.00, w * 0.10, h * 0.26);
    building(w * 0.10, w * 0.08, h * 0.18);
    building(w * 0.52, w * 0.09, h * 0.28);
    building(w * 0.62, w * 0.13, h * 0.50);
    building(w * 0.76, w * 0.10, h * 0.38);
    building(w * 0.86, w * 0.14, h * 0.58);

    // the green wave
    final Path green = Path()
      ..moveTo(0, h * 0.80)
      ..cubicTo(w * 0.25, h * 0.70, w * 0.50, h * 0.92, w, h * 0.74)
      ..lineTo(w, h * 0.81)
      ..cubicTo(w * 0.55, h * 1.00, w * 0.25, h * 0.80, 0, h * 0.90)
      ..close();
    canvas.drawPath(
      green,
      Paint()..shader = const LinearGradient(colors: <Color>[Color(0xFF2ECC40), Color(0xFF9BE45A)]).createShader(rect),
    );

    // the blue wave under it
    final Path blue = Path()
      ..moveTo(0, h * 0.90)
      ..cubicTo(w * 0.30, h * 0.80, w * 0.60, h * 1.02, w, h * 0.81)
      ..lineTo(w, h * 0.87)
      ..cubicTo(w * 0.60, h * 1.08, w * 0.30, h * 0.88, 0, h * 0.98)
      ..close();
    canvas.drawPath(blue, Paint()..color = const Color(0xFF1E88E5));

    // the page colour, so the header flows into the body
    final Path body = Path()
      ..moveTo(0, h * 0.95)
      ..cubicTo(w * 0.30, h * 0.87, w * 0.65, h * 1.06, w, h * 0.89)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(body, Paint()..color = const Color(0xFFEAF1FB));
  }

  @override
  bool shouldRepaint(covariant final CustomPainter oldDelegate) => false;
}

/// The waves at the bottom of the page.
class _FooterPainter extends CustomPainter {
  const _FooterPainter();

  @override
  void paint(final Canvas canvas, final Size size) {
    final double w = size.width;
    final double h = size.height;
    final Rect rect = Offset.zero & size;

    final Path blue = Path()
      ..moveTo(0, h * 0.45)
      ..cubicTo(w * 0.30, h * 0.20, w * 0.65, h * 0.70, w, h * 0.30)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      blue,
      Paint()..shader = const LinearGradient(colors: <Color>[Color(0xFF0A4DB5), Color(0xFF1E88E5)]).createShader(rect),
    );

    final Path green = Path()
      ..moveTo(0, h * 0.62)
      ..cubicTo(w * 0.30, h * 0.40, w * 0.65, h * 0.90, w, h * 0.50)
      ..lineTo(w, h * 0.58)
      ..cubicTo(w * 0.65, h * 1.0, w * 0.30, h * 0.52, 0, h * 0.72)
      ..close();
    canvas.drawPath(green, Paint()..color = const Color(0xFF2ECC40));
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

/// The "Sign in with Google" button: white with a light blue edge and Google's G, as in the design.
class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(final BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 2,
      shadowColor: const Color(0x331565C0),
      borderRadius: BorderRadius.circular(30.r),
      child: InkWell(
        key: const ValueKey<String>('google_signin_button'),
        borderRadius: BorderRadius.circular(30.r),
        onTap: onTap,
        child: Container(
          height: 54.h,
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 24.w),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30.r),
            border: Border.all(color: const Color(0xFFC9D6EE), width: 1.2),
          ),
          child: Row(
            children: <Widget>[
              CustomPaint(size: Size(26.w, 26.w), painter: const _GoogleGPainter()),
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: const Color(0xFF14264F), fontSize: 14.sp, fontWeight: FontWeight.w800, letterSpacing: 1.2),
                ),
              ),
              SizedBox(width: 26.w),
            ],
          ),
        ),
      ),
    );
  }
}
