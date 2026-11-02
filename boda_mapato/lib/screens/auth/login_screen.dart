import "dart:convert";
import "dart:ui";
import "package:flutter/material.dart";
import "package:flutter_screenutil/flutter_screenutil.dart";
import "package:provider/provider.dart";
import "package:url_launcher/url_launcher_string.dart";
import "package:shared_preferences/shared_preferences.dart";

import "../../constants/colors.dart";
import "../../constants/theme_constants.dart";
import "../../providers/auth_provider.dart";
import "../../services/localization_service.dart";
import "forgot_password_sheet.dart";
import "register_business_screen.dart";
import '../../utils/server_message.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Once a device has logged a given email in successfully with its
  // matching phone number, that phone is remembered here and the phone
  // field is skipped on later logins for the same email -- only a NEW
  // email on this device (or a manual "use a different number" tap) asks
  // for the phone again. Keyed on lower-cased email, persisted locally.
  static const String _rememberedPhonesKey = 'remembered_login_phones';

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;

  bool _forcePhoneField = false;
  Map<String, String> _rememberedPhones = <String, String>{};

  /// True once this device already knows this email's registered phone --
  /// the phone field is hidden and that remembered value is used silently.
  bool get _phoneFieldNeeded {
    if (_forcePhoneField) return true;
    final String email = _emailController.text.trim().toLowerCase();
    return email.isEmpty || !_rememberedPhones.containsKey(email);
  }

  @override
  void initState() {
    super.initState();
    _emailController.addListener(() => setState(() {}));
    _loadRememberedPhones();
  }

  Future<void> _loadRememberedPhones() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_rememberedPhonesKey);
      if (raw == null || raw.isEmpty) return;
      final dynamic decoded = jsonDecode(raw);
      if (decoded is Map && mounted) {
        setState(() {
          _rememberedPhones = decoded.map(
            (dynamic k, dynamic v) => MapEntry(k.toString(), v.toString()),
          );
        });
      }
    } on Exception {
      // First run / corrupted prefs -- just fall back to always asking.
    }
  }

  Future<void> _rememberPhone(String email, String phone) async {
    try {
      _rememberedPhones = <String, String>{
        ..._rememberedPhones,
        email.toLowerCase(): phone,
      };
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_rememberedPhonesKey, jsonEncode(_rememberedPhones));
    } on Exception {
      // Non-fatal -- the next login just asks for the phone again.
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final String email = _emailController.text.trim();
    final String phone = _phoneFieldNeeded
        ? _phoneController.text.trim()
        : _rememberedPhones[email.toLowerCase()]!;

    setState(() {
      _isLoading = true;
    });

    try {
      final AuthProvider authProvider = Provider.of<AuthProvider>(context, listen: false);
      final bool success = await authProvider.login(
        email: email,
        password: _passwordController.text,
        phoneNumber: phone,
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }

      if (success) {
        await _rememberPhone(email, phone);
        if (mounted) {
          _showSnackBar(LocalizationService.instance.translate('login_successful'), Colors.green);
          Navigator.of(context).pop();
        }
      } else {
        if (mounted) {
          // The remembered phone may be stale (number changed) -- surface
          // the field again so the user can correct it instead of being
          // stuck unable to see why login keeps failing.
          setState(() => _forcePhoneField = true);
          if (authProvider.lastErrorCode == 'registration_rejected') {
            _showRegistrationRejectedDialog(
              message: authProvider.errorMessage ?? LocalizationService.instance.translate('login_failed'),
              email: email,
              phone: phone,
            );
          } else if (authProvider.lastErrorCode == 'registration_pending') {
            _showRegistrationPendingDialog(
              message: authProvider.errorMessage ?? LocalizationService.instance.translate('login_failed'),
            );
          } else {
            _showSnackBar(authProvider.errorMessage ?? LocalizationService.instance.translate('login_failed'), Colors.red);
          }
        }
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _showSnackBar(readableErrorMessage(e), Colors.red);
      }
    }
  }

  /// Google's account chooser. An owner who is registered and approved goes straight in; someone new goes to the registration form
  /// (no password, no user name: Google is both); someone still waiting hears so.
  Future<void> _handleGoogle() async {
    final AuthProvider authProvider = Provider.of<AuthProvider>(context, listen: false);
    setState(() => _isLoading = true);
    final GoogleResult result = await authProvider.loginWithGoogle();
    if (!mounted) return;
    setState(() => _isLoading = false);

    switch (result) {
      case GoogleResult.signedIn:
        _showSnackBar(LocalizationService.instance.translate('login_successful'), Colors.green);
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
        final String message = authProvider.errorMessage ?? LocalizationService.instance.translate('login_failed');
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
    required final String phone,
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
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (final BuildContext _) => RegisterBusinessScreen(
                    initialEmail: email,
                    initialPhone: phone,
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
        initialEmail: _emailController.text.trim().isEmpty
            ? null
            : _emailController.text.trim(),
      ),
    );
    if (verifiedEmail != null && mounted) {
      setState(() {
        _emailController.text = verifiedEmail;
        // The account's phone is unchanged by a password reset, so if this
        // device already remembered it, keep skipping the phone field.
        _forcePhoneField = false;
        _passwordController.clear();
      });
    }
  }

  static const Color _navy = Color(0xFF2D3566);
  static const Color _teal = Color(0xFF008080);

  @override
  Widget build(final BuildContext context) {
    return Consumer<LocalizationService>(
      builder: (final BuildContext context, final LocalizationService loc, final Widget? child) => Scaffold(
        backgroundColor: _navy,
        body: Stack(
          children: <Widget>[
            const Positioned.fill(child: CustomPaint(painter: _BlobPainter())),
            SafeArea(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: AnimatedOpacity(
                  opacity: _isLoading ? 0.3 : 1.0,
                  duration: const Duration(milliseconds: 300),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 28.w),
                    child: Column(
                      children: <Widget>[
                        SizedBox(height: 96.h),
                        Text(
                          loc.translate('signin'),
                          key: const ValueKey<String>('login_title'),
                          style: TextStyle(color: Colors.white, fontSize: 36.sp, fontWeight: FontWeight.w800),
                        ),
                        SizedBox(height: 28.h),
                        Form(
                          key: _formKey,
                          child: Column(
                            children: <Widget>[
                              _pillField(controller: _emailController, hint: loc.translate('email'), icon: Icons.email, keyboardType: TextInputType.emailAddress),
                              if (_phoneFieldNeeded) ...<Widget>[
                                SizedBox(height: 16.h),
                                _pillField(controller: _phoneController, hint: loc.translate('phone_number'), icon: Icons.phone_android, keyboardType: TextInputType.phone),
                              ] else
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton(
                                    onPressed: () => setState(() => _forcePhoneField = true),
                                    style: TextButton.styleFrom(padding: EdgeInsets.only(left: 12.w, top: 4.h), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                                    child: Text(loc.translate('use_different_phone'), style: TextStyle(color: Colors.white54, fontSize: 11.sp)),
                                  ),
                                ),
                              SizedBox(height: 16.h),
                              _pillField(
                                controller: _passwordController,
                                hint: loc.translate('password'),
                                icon: Icons.lock,
                                obscureText: _obscurePassword,
                                suffix: IconButton(
                                  icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off, color: Colors.black38, size: 20.sp),
                                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                ),
                              ),
                              SizedBox(height: 22.h),
                              SizedBox(
                                width: double.infinity,
                                height: 56.h,
                                child: ElevatedButton(
                                  key: const ValueKey<String>('login_button'),
                                  onPressed: _handleLogin,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _teal,
                                    foregroundColor: Colors.white,
                                    elevation: 8,
                                    shadowColor: Colors.black54,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30.r)),
                                  ),
                                  child: Text(loc.translate('signin').toUpperCase(), style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.w800, letterSpacing: 1)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 10.h),
                        TextButton(
                          onPressed: _handleForgotPassword,
                          child: Text(loc.translate('forgot_password'), style: TextStyle(color: Colors.white60, fontSize: 14.sp)),
                        ),
                        SizedBox(height: 22.h),
                        Text(
                          loc.translate('or_sign_in_with').toUpperCase(),
                          style: TextStyle(color: Colors.white, fontSize: 16.sp, fontWeight: FontWeight.w800),
                        ),
                        SizedBox(height: 18.h),
                        _GoogleButton(label: loc.translate('sign_in_with_google').toUpperCase(), onTap: _handleGoogle),
                        SizedBox(height: 40.h),
                        Text.rich(
                          TextSpan(
                            style: TextStyle(color: Colors.white, fontSize: 15.sp),
                            children: <InlineSpan>[
                              TextSpan(text: '${loc.translate('no_account_question')} '),
                              WidgetSpan(
                                alignment: PlaceholderAlignment.baseline,
                                baseline: TextBaseline.alphabetic,
                                child: GestureDetector(
                                  key: const ValueKey<String>('sign_up_link'),
                                  onTap: _handleGoogle,
                                  child: Text(loc.translate('sign_up'), style: TextStyle(color: Colors.white, fontSize: 15.sp, fontWeight: FontWeight.w800)),
                                ),
                              ),
                            ],
                          ),
                          textAlign: TextAlign.center,
                        ),
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

  /// A white pill with an icon and a grey hint, as in the design.
  Widget _pillField({
    required final TextEditingController controller,
    required final String hint,
    required final IconData icon,
    final bool obscureText = false,
    final Widget? suffix,
    final TextInputType? keyboardType,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30.r),
        boxShadow: const <BoxShadow>[BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        style: TextStyle(color: Colors.black87, fontSize: 16.sp),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.black38, fontSize: 16.sp),
          prefixIcon: Icon(icon, color: Colors.black45, size: 22.sp),
          suffixIcon: suffix,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          errorBorder: InputBorder.none,
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
