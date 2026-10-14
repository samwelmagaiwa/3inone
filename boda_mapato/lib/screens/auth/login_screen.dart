import "dart:convert";
import "dart:ui";
import "package:flutter/foundation.dart" show kDebugMode;
import "package:flutter/material.dart";
import "package:flutter_screenutil/flutter_screenutil.dart";
import "package:provider/provider.dart";
import "package:shared_preferences/shared_preferences.dart";

import "../../constants/colors.dart";
import "../../constants/theme_constants.dart";
import "../../providers/auth_provider.dart";
import "../../services/localization_service.dart";
import "../../widgets/backgrounds/starfield_background.dart";
import "../../widgets/flag_app_name_text.dart";
import "forgot_password_sheet.dart";
import "register_business_screen.dart";
import '../../utils/server_message.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

// ---------------------------------------------------------------------------
// Demo accounts shown in the collapsible picker — add / remove freely.
// ---------------------------------------------------------------------------
class _DemoAccount {
  const _DemoAccount({
    required this.label,
    required this.role,
    required this.email,
    required this.phone,
    required this.password,
    required this.color,
    required this.icon,
  });
  final String label;
  final String role;
  final String email;
  final String phone;
  final String password;
  final Color color;
  final IconData icon;
}

const List<_DemoAccount> _kDemoAccounts = [
  _DemoAccount(
    label: 'Samwel Magaiwa',
    role: 'Admin · E-Mauzo',
    email: 'admin@gmail.com',
    phone: '+255743519104',
    password: '12345678',
    color: Color(0xFF00E5FF),
    icon: Icons.manage_accounts_rounded,
  ),
  _DemoAccount(
    label: 'Juma Mwita',
    role: 'Sales Officer',
    email: 'juma@gmail.com',
    phone: '0743519107',
    password: '12345678',
    color: Color(0xFF69F0AE),
    icon: Icons.point_of_sale_rounded,
  ),
  _DemoAccount(
    label: 'John Mwita',
    role: 'Driver',
    email: 'john@gmail.com',
    phone: '+255743519105',
    password: '12345678',
    color: Color(0xFFFF6E40),
    icon: Icons.local_shipping_rounded,
  ),
  _DemoAccount(
    label: 'Jane Mwita',
    role: 'Driver',
    email: 'jane@gmail.com',
    phone: '+255743519107',
    password: '12345678',
    color: Color(0xFFCE93D8),
    icon: Icons.local_shipping_rounded,
  ),
];

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
  bool _demoExpanded = false;
  bool _forcePhoneField = false;
  Map<String, String> _rememberedPhones = <String, String>{};

  void _applyDemo(_DemoAccount account) {
    setState(() {
      _emailController.text = account.email;
      _phoneController.text = account.phone;
      _passwordController.text = account.password;
      _demoExpanded = false;
    });
  }

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

  @override
  Widget build(final BuildContext context) {
    final Color cyberCyan = const Color(0xFF00E5FF);

    return StarfieldBackground(
      child: Consumer<LocalizationService>(
        builder: (context, localizationService, child) => Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              // Nebula Glow
              Positioned(
                top: -100.h,
                right: -50.w,
                child: Container(
                  width: 400.w,
                  height: 400.h,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        cyberCyan.withValues(alpha: 0.12),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),

              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: AnimatedOpacity(
                        opacity: _isLoading ? 0.3 : 1.0,
                        duration: const Duration(milliseconds: 500),
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 24.w),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              SizedBox(height: 36.h),
                                  
                                  // Hero Logo Section
                                  TweenAnimationBuilder<double>(
                                    tween: Tween(begin: 0.0, end: 1.0),
                                    duration: const Duration(seconds: 2),
                                    builder: (context, val, child) {
                                      return Transform.scale(
                                        scale: 0.9 + (0.1 * val),
                                        child: Container(
                                          padding: EdgeInsets.all(4.w),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            border: Border.all(color: cyberCyan.withValues(alpha: 0.5 * val), width: 2),
                                            boxShadow: [
                                              BoxShadow(
                                                color: cyberCyan.withValues(alpha: 0.2 * val),
                                                blurRadius: 30 * val,
                                                spreadRadius: 5 * val,
                                              ),
                                            ],
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(70.r),
                                            child: Image.asset(
                                              'assets/images/app_icon.png',
                                              width: 110.w,
                                              height: 110.w,
                                              fit: BoxFit.cover,
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  
                                  SizedBox(height: 16.h),
                                  
                                  FlagAppNameText(
                                    localizationService.translate('app_name'),
                                    fontSize: 28.sp,
                                  ),
                                  
                                  SizedBox(height: 24.h),

                                  // ── Demo credentials picker ──────────────
                                  // DEBUG BUILDS ONLY. It holds real sign-in details, and anything
                                  // in a release build can be read out of the app file by anyone
                                  // who downloads it. kDebugMode is a compile-time constant, so a
                                  // release build does not even contain this picker or its list.
                                  if (kDebugMode) ...<Widget>[
                                    _DemoPicker(
                                      expanded: _demoExpanded,
                                      onToggle: () => setState(() => _demoExpanded = !_demoExpanded),
                                      onSelect: _applyDemo,
                                    ),

                                    SizedBox(height: 24.h),
                                  ],

                                  // Glass Card Form
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(24.r),
                                    child: BackdropFilter(
                                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                                      child: Container(
                                        padding: EdgeInsets.all(24.w),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.05),
                                          borderRadius: BorderRadius.circular(24.r),
                                          border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
                                        ),
                                        child: Form(
                                          key: _formKey,
                                          child: Column(
                                            children: [
                                              _buildModernField(
                                                controller: _emailController,
                                                label: localizationService.translate('email'),
                                                icon: Icons.email_outlined,
                                                cyberCyan: cyberCyan,
                                              ),
                                              if (_phoneFieldNeeded) ...<Widget>[
                                                SizedBox(height: 20.h),
                                                _buildModernField(
                                                  controller: _phoneController,
                                                  label: localizationService.translate('phone_number'),
                                                  icon: Icons.phone_android_outlined,
                                                  cyberCyan: cyberCyan,
                                                ),
                                              ] else ...<Widget>[
                                                SizedBox(height: 6.h),
                                                Align(
                                                  alignment: Alignment.centerLeft,
                                                  child: TextButton(
                                                    onPressed: () =>
                                                        setState(() => _forcePhoneField = true),
                                                    style: TextButton.styleFrom(
                                                      padding: EdgeInsets.zero,
                                                      minimumSize: Size.zero,
                                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                    ),
                                                    child: Text(
                                                      localizationService.translate('use_different_phone'),
                                                      style: TextStyle(
                                                        color: cyberCyan.withValues(alpha: 0.7),
                                                        fontSize: 11.sp,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                              SizedBox(height: 20.h),
                                              _buildModernField(
                                                controller: _passwordController,
                                                label: localizationService.translate('password'),
                                                icon: Icons.lock_outline,
                                                obscureText: _obscurePassword,
                                                cyberCyan: cyberCyan,
                                                suffix: IconButton(
                                                  icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off, color: Colors.white38, size: 20.sp),
                                                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                                ),
                                              ),
                                              SizedBox(height: 32.h),
                                              
                                              // Login Button
                                              GestureDetector(
                                                onTap: _handleLogin,
                                                child: Container(
                                                  height: 56.h,
                                                  width: double.infinity,
                                                  decoration: BoxDecoration(
                                                    borderRadius: BorderRadius.circular(16.r),
                                                    gradient: LinearGradient(
                                                      colors: [cyberCyan, const Color(0xFF00B8D4)],
                                                    ),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: cyberCyan.withValues(alpha: 0.3),
                                                        blurRadius: 15,
                                                        offset: const Offset(0, 5),
                                                      ),
                                                    ],
                                                  ),
                                                  child: Center(
                                                    child: Text(
                                                      localizationService.translate('signin').toUpperCase(),
                                                      style: TextStyle(
                                                        color: Colors.black,
                                                        fontSize: 16.sp,
                                                        fontWeight: FontWeight.w900,
                                                        letterSpacing: 2.w,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              
                                              SizedBox(height: 16.h),
                                              
                                              TextButton(
                                                onPressed: _handleForgotPassword,
                                                child: Text(
                                                  localizationService.translate('forgot_password'),
                                                  style: TextStyle(color: Colors.white38, fontSize: 13.sp),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  
                              SizedBox(height: 20.h),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Loading Overlay
              if (_isLoading)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.8),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          FlagAppNameText(
                            localizationService.translate('app_name'),
                            fontSize: 26.sp,
                          ),
                          SizedBox(height: 20.h),
                          ThemeConstants.buildResponsiveLoadingWidget(
                            context,
                            message: localizationService.translate('signing_in'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Back-to-home button — last in Stack so it sits on top and is tappable
              Positioned(
                top: MediaQuery.of(context).padding.top + 10.h,
                left: 16.w,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14.r),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: GestureDetector(
                      onTap: () {
                        if (Navigator.of(context).canPop()) {
                          Navigator.of(context).pop();
                        } else {
                          Navigator.of(context).pushNamedAndRemoveUntil(
                            '/',
                            (route) => false,
                          );
                        }
                      },
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(14.r),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.arrow_back_ios_new_rounded,
                                color: Colors.white70, size: 14.sp),
                            SizedBox(width: 5.w),
                            Text(
                              'Home',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13.sp,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
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
    );
  }

  Widget _buildModernField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    Widget? suffix,
    required Color cyberCyan,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(color: Colors.white54, fontSize: 11.sp, fontWeight: FontWeight.bold, letterSpacing: 1),
        ),
        SizedBox(height: 8.h),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(color: Colors.white12),
          ),
          child: TextFormField(
            controller: controller,
            obscureText: obscureText,
            style: const TextStyle(color: Colors.white, decoration: TextDecoration.none),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.transparent,
              prefixIcon: Icon(icon, color: cyberCyan.withValues(alpha: 0.6), size: 20.sp),
              suffixIcon: suffix,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Demo credentials picker (stateless — parent owns expanded flag) ─────────
class _DemoPicker extends StatelessWidget {
  const _DemoPicker({
    required this.expanded,
    required this.onToggle,
    required this.onSelect,
  });

  final bool expanded;
  final VoidCallback onToggle;
  final void Function(_DemoAccount) onSelect;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16.r),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(
              color: const Color(0xFFFFD700).withValues(alpha: 0.25),
              width: 1,
            ),
          ),
          child: Column(
            children: [
              // ── Header row ───────────────────────────────────────────────
              GestureDetector(
                onTap: onToggle,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                  child: Row(
                    children: [
                      Icon(
                        Icons.key_rounded,
                        color: const Color(0xFFFFD700),
                        size: 18.sp,
                      ),
                      SizedBox(width: 10.w),
                      Expanded(
                        child: Text(
                          'Demo Login Credentials',
                          style: TextStyle(
                            color: const Color(0xFFFFD700),
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      AnimatedRotation(
                        turns: expanded ? 0.5 : 0.0,
                        duration: const Duration(milliseconds: 250),
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: const Color(0xFFFFD700).withValues(alpha: 0.8),
                          size: 20.sp,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Expandable account list ──────────────────────────────────
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 250),
                crossFadeState: expanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                firstChild: const SizedBox.shrink(),
                secondChild: Column(
                  children: [
                    Divider(
                      height: 1,
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                    ...List.generate(_kDemoAccounts.length, (i) {
                      final acc = _kDemoAccounts[i];
                      return _DemoTile(
                        account: acc,
                        onTap: () => onSelect(acc),
                        isLast: i == _kDemoAccounts.length - 1,
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DemoTile extends StatelessWidget {
  const _DemoTile({
    required this.account,
    required this.onTap,
    required this.isLast,
  });

  final _DemoAccount account;
  final VoidCallback onTap;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : Border(
                  bottom: BorderSide(
                    color: Colors.white.withValues(alpha: 0.06),
                    width: 1,
                  ),
                ),
        ),
        child: Row(
          children: [
            Container(
              width: 36.w,
              height: 36.w,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: account.color.withValues(alpha: 0.12),
                border: Border.all(
                  color: account.color.withValues(alpha: 0.35),
                  width: 1,
                ),
              ),
              child: Icon(account.icon, color: account.color, size: 18.sp),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account.label,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${account.role}  ·  ${account.email}',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 11.sp,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: account.color.withValues(alpha: 0.5),
              size: 12.sp,
            ),
          ],
        ),
      ),
    );
  }
}
