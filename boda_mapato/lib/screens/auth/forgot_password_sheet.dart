import "package:flutter/material.dart";
import "package:flutter_screenutil/flutter_screenutil.dart";

import "../../services/auth_service.dart";
import "../../services/localization_service.dart";

/// Two-step "forgot password" flow. Step 1: give the email AND the phone number
/// registered on the account (the same two factors login itself checks) and the
/// server TEXTS a one-time code to that phone. Step 2: enter that code and choose
/// a new password. The code only ever reaches whoever really holds the phone, so
/// knowing someone's email and number is not enough to take over their account.
/// Asks the server to text a code to the phone. [AuthService.forgotPassword] in the app.
typedef RequestResetCode = Future<void> Function(String email, String phoneNumber);

/// Sets the new password with the texted code. [AuthService.resetPassword] in the app.
typedef ResetPassword = Future<void> Function(String email, String code, String password);

class ForgotPasswordSheet extends StatefulWidget {
  const ForgotPasswordSheet({
    super.key,
    this.initialEmail,
    this.onRequestCode,
    this.onReset,
  });

  final String? initialEmail;

  /// Overridable so the sheet can be tested without a network.
  final RequestResetCode? onRequestCode;
  final ResetPassword? onReset;

  @override
  State<ForgotPasswordSheet> createState() => _ForgotPasswordSheetState();
}

class _ForgotPasswordSheetState extends State<ForgotPasswordSheet> {
  final GlobalKey<FormState> _identityFormKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _passwordFormKey = GlobalKey<FormState>();
  late final TextEditingController _email =
      TextEditingController(text: widget.initialEmail ?? '');
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _code = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirmPassword = TextEditingController();

  static const int _stepVerify = 0;
  static const int _stepNewPassword = 1;
  static const int _stepDone = 2;

  int _step = _stepVerify;
  bool _busy = false;
  String? _error;
  String? _notice;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _phone.dispose();
    _code.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _verifyIdentity() async {
    if (!(_identityFormKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await _requestCode();
      if (!mounted) return;
      setState(() {
        _step = _stepNewPassword;
        _busy = false;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _busy = false;
      });
    }
  }

  Future<void> _requestCode() =>
      (widget.onRequestCode ??
          ((final String e, final String p) =>
              AuthService.forgotPassword(email: e, phoneNumber: p)))(
        _email.text.trim(),
        _phone.text.trim(),
      );

  /// Asks for another code. The server sends one at most once a minute and answers the same
  /// way either way, so this says "sent" without promising a new text arrived.
  Future<void> _resendCode() async {
    final LocalizationService loc = LocalizationService.instance;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await _requestCode();
      if (!mounted) return;
      setState(() {
        _notice = loc.translate('code_sent');
        _busy = false;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _busy = false;
      });
    }
  }

  Future<void> _submitNewPassword() async {
    final LocalizationService loc = LocalizationService.instance;
    if (!(_passwordFormKey.currentState?.validate() ?? false)) return;
    if (_password.text != _confirmPassword.text) {
      setState(() => _error = loc.translate('passwords_do_not_match'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await (widget.onReset ??
          ((final String e, final String c, final String pw) =>
              AuthService.resetPassword(email: e, code: c, password: pw)))(
        _email.text.trim(),
        _code.text.trim(),
        _password.text,
      );
      if (!mounted) return;
      setState(() {
        _step = _stepDone;
        _busy = false;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = LocalizationService.instance;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF001D3D),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
        ),
        padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 24.h),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Container(
                  width: 40.w,
                  height: 4.h,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2.r),
                  ),
                ),
              ),
              SizedBox(height: 20.h),
              Text(
                loc.translate('forgot_password'),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20.sp,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 6.h),
              Text(
                switch (_step) {
                  _stepVerify => loc.translate('forgot_password_step1_hint'),
                  _stepNewPassword => loc.translate('forgot_password_step2_hint'),
                  _ => loc.translate('forgot_password_done_hint'),
                },
                style: TextStyle(color: Colors.white54, fontSize: 13.sp),
              ),
              SizedBox(height: 20.h),
              if (_error != null) ...<Widget>[
                Container(
                  padding: EdgeInsets.all(12.w),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Colors.red[200], fontSize: 13.sp),
                  ),
                ),
                SizedBox(height: 16.h),
              ],
              if (_notice != null) ...<Widget>[
                Text(
                  _notice!,
                  key: const ValueKey<String>('reset_notice'),
                  style: TextStyle(color: Colors.greenAccent, fontSize: 13.sp),
                ),
                SizedBox(height: 12.h),
              ],
              if (_step == _stepVerify) _buildVerifyStep(loc),
              if (_step == _stepNewPassword) _buildNewPasswordStep(loc),
              if (_step == _stepDone) _buildDoneStep(loc),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVerifyStep(LocalizationService loc) {
    return Form(
      key: _identityFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _field(
            controller: _email,
            label: loc.translate('email'),
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: (String? v) => (v == null || !v.contains('@'))
                ? loc.translate('enter_valid_email')
                : null,
          ),
          SizedBox(height: 16.h),
          _field(
            controller: _phone,
            label: loc.translate('phone_number'),
            icon: Icons.phone_android_outlined,
            keyboardType: TextInputType.phone,
            validator: (String? v) => (v == null || v.trim().length < 9)
                ? loc.translate('enter_valid_phone')
                : null,
          ),
          SizedBox(height: 24.h),
          _primaryButton(
            label: loc.translate('send_code'),
            onPressed: _busy ? null : _verifyIdentity,
          ),
        ],
      ),
    );
  }

  Widget _buildNewPasswordStep(LocalizationService loc) {
    return Form(
      key: _passwordFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _field(
            controller: _code,
            label: loc.translate('verification_code'),
            icon: Icons.sms_outlined,
            keyboardType: TextInputType.number,
            validator: (String? v) =>
                (v == null || !RegExp(r'^\d{6}$').hasMatch(v.trim()))
                    ? loc.translate('enter_valid_code')
                    : null,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const ValueKey<String>('reset_resend'),
              onPressed: _busy ? null : _resendCode,
              child: Text(
                loc.translate('resend_code'),
                style: TextStyle(color: const Color(0xFF00E5FF), fontSize: 13.sp),
              ),
            ),
          ),
          SizedBox(height: 4.h),
          _field(
            controller: _password,
            label: loc.translate('new_password'),
            icon: Icons.lock_outline,
            obscureText: _obscure,
            suffix: IconButton(
              icon: Icon(
                _obscure ? Icons.visibility : Icons.visibility_off,
                color: Colors.white38,
                size: 20.sp,
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
            validator: (String? v) => (v == null || v.length < 8)
                ? loc.translate('password_min_length')
                : null,
          ),
          SizedBox(height: 16.h),
          _field(
            controller: _confirmPassword,
            label: loc.translate('confirm_password'),
            icon: Icons.lock_outline,
            obscureText: _obscure,
            validator: (String? v) => (v == null || v.length < 8)
                ? loc.translate('password_min_length')
                : null,
          ),
          SizedBox(height: 24.h),
          _primaryButton(
            label: loc.translate('reset_password'),
            onPressed: _busy ? null : _submitNewPassword,
          ),
        ],
      ),
    );
  }

  Widget _buildDoneStep(LocalizationService loc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Icon(Icons.check_circle, color: Colors.greenAccent, size: 48.sp),
        SizedBox(height: 12.h),
        Center(
          child: Text(
            loc.translate('password_reset_successfully'),
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 14.sp),
          ),
        ),
        SizedBox(height: 24.h),
        _primaryButton(
          label: loc.translate('sawa'),
          onPressed: () => Navigator.of(context).pop(_email.text.trim()),
        ),
      ],
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    Widget? suffix,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white54, fontSize: 13.sp),
        prefixIcon: Icon(icon, color: const Color(0xFF00E5FF), size: 20.sp),
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: const BorderSide(color: Color(0xFF00E5FF)),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
      ),
    );
  }

  Widget _primaryButton({required String label, required VoidCallback? onPressed}) {
    return SizedBox(
      height: 52.h,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF00E5FF),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14.r),
          ),
        ),
        child: _busy
            ? SizedBox(
                width: 22.w,
                height: 22.w,
                child: const CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Colors.black,
                ),
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
