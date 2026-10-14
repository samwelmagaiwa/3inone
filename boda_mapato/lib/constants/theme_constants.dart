import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../utils/responsive_helper.dart';
import '../widgets/loading/faux_3d_loading_widget.dart';
import '../services/localization_service.dart';
import '../utils/server_message.dart';

class ThemeConstants {
  // Modern theme colors - matching admin dashboard
  static const Color primaryBlue = Color(0xFF0D3D4D); // Dark teal base
  // Background gradient to match the shared image (dark teal to deep cyan)
  static const Color bgTop = Color(0xFF04121A); // very dark blue-teal (top)
  static const Color bgMid = Color(0xFF092D3A); // mid deep teal-blue
  static const Color bgBottom = Color(0xFF0D485A); // bottom brighter teal-blue
  static const Color footerBarColor =
      Color(0xFF1BA3C7); // bright cyan-blue as in reference footer
  static const Color primaryGradientStart = Color(0xFF667eea);
  static const Color primaryGradientEnd = Color(0xFF764ba2);
  static const Color cardColor = Color(0x1AFFFFFF);
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xB3FFFFFF);
  static const Color primaryOrange = Color(0xFFF97316);
  static const Color successGreen = Color(0xFF10B981);
  static const Color warningAmber = Color(0xFFF59E0B);
  static const Color errorRed = Color(0xFFEF4444);
  static const Color primaryCyan = Color(0xFF00E5FF); // Premium Cyber-Cyan

  // Inventory teal-cyan palette (for consistent design across inventory pages)
  // 30% alpha teal fill, 25% alpha cyan border, vivid cyan accent, neutral chip ~28% alpha
  static const Color invFill = Color(0x4D0F6C7D); // rgba(15,108,125,0.30)
  static const Color invBorder = Color(0x4020B8CE); // rgba(32,184,206,0.25)
  static const Color invAccent = Color(0xFF20B8CE); // cyan accent
  static const Color invCard = Color(0xE60B5B6B); // rgba(11,91,107,0.90)
  static const Color invNeutralChip = Color(0x4720B8CE); // ~28% alpha cyan

  // App/dashboard background decoration (gradient)
  static const BoxDecoration dashboardBackground = BoxDecoration(
    gradient: LinearGradient(
      colors: [bgTop, bgMid, bgBottom],
      stops: [0.0, 0.55, 1.0],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    ),
  );

  // Glass card decoration
  static BoxDecoration glassCardDecoration = BoxDecoration(
    color: cardColor,
    borderRadius: BorderRadius.circular(20.r),
    border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
    boxShadow: const <BoxShadow>[],
  );

  // Inventory card decoration (teal tint)
  static BoxDecoration invCardDecoration = BoxDecoration(
    color: invCard,
    borderRadius: BorderRadius.circular(14.r),
    border: Border.all(color: invBorder),
  );

  // Standard app bar theme
  static AppBar buildAppBar(
    String title, {
    List<Widget>? actions,
    Widget? leading,
    bool automaticallyImplyLeading = true,
  }) =>
      AppBar(
        title: Text(
          title,
          style: TextStyle(
            color: textPrimary,
            fontSize: 20.sp,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: bgTop,
        foregroundColor: textPrimary,
        elevation: 0,
        leading: leading,
        automaticallyImplyLeading: automaticallyImplyLeading,
        actions: actions,
        iconTheme: const IconThemeData(color: textPrimary),
      );

  /// A text field drawn on one of the app's own dark surfaces (a dialog, a sheet, a card).
  ///
  /// The app theme gives every text field a WHITE fill (it was made for the light forms). A field on a dark surface that
  /// does not say otherwise is therefore drawn as a white box, and the white text typed into it cannot be read. This
  /// is the decoration to use there: a faint light fill over the surface, white text, no white box.
  static InputDecoration darkField(
    final String label, {
    final String? hint,
    final String? helper,
    final String? error,
    final Widget? suffix,
    final Widget? prefix,
  }) {
    final OutlineInputBorder none = OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none);
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      helperMaxLines: 3,
      errorText: error,
      suffixIcon: suffix,
      prefixIcon: prefix,
      labelStyle: const TextStyle(color: Colors.white60),
      hintStyle: const TextStyle(color: Colors.white30),
      helperStyle: const TextStyle(color: Colors.white54),
      counterStyle: const TextStyle(color: Colors.white54),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.08),
      border: none,
      enabledBorder: none,
      disabledBorder: none,
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: primaryCyan)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.redAccent)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.redAccent)),
    );
  }

  // Glass card widget - Fixed for proper touch events
  static Widget buildGlassCard({
    required Widget child,
    VoidCallback? onTap,
  }) =>
      Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: DecoratedBox(
            decoration: glassCardDecoration,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20.r),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                // A DecoratedBox with a background sits between the outer
                // Material and `child` above, so a ListTile (or anything
                // else that paints ink on "the nearest Material ancestor")
                // inside `child` would have its splash hidden behind that
                // background. Give it a nearer, transparent Material to
                // paint on instead.
                child: Material(
                  type: MaterialType.transparency,
                  child: child,
                ),
              ),
            ),
          ),
        ),
      );

  // Glass card widget without touch handling (for display-only cards)
  static Widget buildGlassCardStatic({required Widget child}) => DecoratedBox(
        decoration: glassCardDecoration,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20.r),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: child,
          ),
        ),
      );

  // Default text style for input fields (bright white)
  static TextStyle get inputStyle => TextStyle(
        color: textPrimary,
        fontSize: 14.sp,
        fontWeight: FontWeight.normal,
      );

  // Convenience: inventory input decoration (teal/cyan)
  static InputDecoration invInputDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: textSecondary,
          fontSize: 12.sp,
          fontWeight: FontWeight.normal,
        ),
        labelStyle: TextStyle(
          color: textPrimary,
          fontSize: 14.sp,
        ),
        filled: true,
        fillColor: invFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14.r),
          borderSide: const BorderSide(color: invBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14.r),
          borderSide: const BorderSide(color: invBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14.r),
          borderSide: const BorderSide(color: invAccent, width: 1.4),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
      );

  // Choice chips and option tiles (the kind-of-business chips, the pack-size chips): a faint white fill and a
  // hairline white border. Text fields use the teal invFill / invBorder above.
  static const Color glassFieldFill = Color(0x14FFFFFF); // white 8%
  static const Color glassFieldBorder = Color(0x2EFFFFFF); // white 18%

  // Standard scaffold with blue background
  static Widget buildScaffold({
    required String title,
    required Widget body,
    List<Widget>? actions,
    Widget? floatingActionButton,
    Widget? drawer,
  }) =>
      Scaffold(
        backgroundColor: Colors.transparent,
        appBar: buildAppBar(title, actions: actions),
        body: Stack(
          children: [
            const DecoratedBox(
              decoration: dashboardBackground,
              child: SizedBox.expand(),
            ),
            SafeArea(child: body),
          ],
        ),
        floatingActionButton: floatingActionButton,
        drawer: drawer,
      );

  // Loading widget
  static Widget buildLoadingWidget() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
            SizedBox(height: 24.h),
            Text(
              "${LocalizationService.instance.translate('loading_2')}...",
              style: TextStyle(
                color: textSecondary,
                fontSize: 16.sp,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );

  // Text styles
  static TextStyle get headingStyle => TextStyle(
        color: textPrimary,
        fontSize: 18.sp,
        fontWeight: FontWeight.bold,
      );

  static TextStyle get subHeadingStyle => TextStyle(
        color: textSecondary,
        fontSize: 16.sp,
        fontWeight: FontWeight.w600,
      );

  static TextStyle get bodyStyle => TextStyle(
        color: textPrimary,
        fontSize: 14.sp,
        fontWeight: FontWeight.normal,
      );

  static TextStyle get captionStyle => TextStyle(
        color: textSecondary,
        fontSize: 12.sp,
        fontWeight: FontWeight.normal,
      );

  // Top snackbar utility methods - truly positions at TOP of screen
  static void _showTopSnackBar(
    BuildContext context,
    String message, {
    Color? backgroundColor,
    Duration? duration,
    IconData? icon,
  }) {
    final OverlayState? overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    showTopBanner(
      overlay,
      message,
      backgroundColor: backgroundColor,
      duration: duration,
      icon: icon,
    );
  }

  /// Same top banner as [_showTopSnackBar], but takes an [OverlayState]
  /// captured before an `await` instead of a [BuildContext] — for call
  /// sites that pop a dialog (invalidating their context) before showing
  /// the result, mirroring the ScaffoldMessenger-capture pattern.
  static void showTopBanner(
    OverlayState overlay,
    String message, {
    Color? backgroundColor,
    Duration? duration,
    IconData? icon,
  }) {
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 10,
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              color: backgroundColor ?? successGreen,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    // Whatever reaches a banner is cleaned here, once: no "Exception: ..." wrapper, and a
                    // message the server wrote in both languages shows only the one that is chosen.
                    readableServerMessage(message),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    overlay.insert(overlayEntry);

    // Auto-remove after duration
    Future.delayed(duration ?? const Duration(seconds: 3), () {
      overlayEntry.remove();
    });
  }

  static void showSuccessSnackBar(BuildContext context, String message) {
    _showTopSnackBar(
      context,
      message,
      backgroundColor: successGreen,
      icon: Icons.check_circle,
    );
  }

  static void showErrorSnackBar(BuildContext context, String message) {
    _showTopSnackBar(
      context,
      message,
      backgroundColor: errorRed,
      icon: Icons.error,
    );
  }

  static void showWarningSnackBar(BuildContext context, String message) {
    _showTopSnackBar(
      context,
      message,
      backgroundColor: warningAmber,
      icon: Icons.warning,
    );
  }

  static void showInfoSnackBar(BuildContext context, String message) {
    _showTopSnackBar(
      context,
      message,
      backgroundColor: Colors.blue[600],
      icon: Icons.info_outline,
    );
  }

  // Responsive helper methods
  /// Get responsive glass card decoration with MediaQuery-based sizing
  static BoxDecoration responsiveGlassCardDecoration(BuildContext context) {
    ResponsiveHelper.init(context);
    return BoxDecoration(
      color: cardColor,
      borderRadius: BorderRadius.circular(ResponsiveHelper.radiusL),
      border: Border.all(color: Colors.white.withValues(alpha: 0.12)), // Subtler border
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.1),
          blurRadius: ResponsiveHelper.elevation * 5,
          offset: Offset(0, ResponsiveHelper.elevation * 2.5),
        ),
      ],
    );
  }

  /// Get responsive app bar with MediaQuery-based sizing
  static AppBar buildResponsiveAppBar(BuildContext context, String title,
      {List<Widget>? actions, Widget? leading, bool? showBackButton, VoidCallback? onBack}) {
    ResponsiveHelper.init(context);
    final canPop = showBackButton ?? Navigator.canPop(context);

    return AppBar(
      title: Text(
        title,
        style: TextStyle(
          color: textPrimary,
          fontSize: ResponsiveHelper.h3,
          fontWeight: FontWeight.bold,
        ),
      ),
      backgroundColor: primaryBlue,
      foregroundColor: textPrimary,
      elevation: 0,
      actions: actions,
      automaticallyImplyLeading: true,
      leading: leading ?? (canPop ? IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, size: 20),
        onPressed: onBack ?? () => Navigator.pop(context),
      ) : null),
      iconTheme: IconThemeData(
        color: textPrimary,
        size: ResponsiveHelper.iconSizeL,
      ),
      toolbarHeight: ResponsiveHelper.appBarHeight,
    );
  }

  /// Responsive glass card widget with MediaQuery-based sizing
  static Widget buildResponsiveGlassCard(BuildContext context,
      {required Widget child, required VoidCallback onTap, EdgeInsets? padding}) {
    ResponsiveHelper.init(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(ResponsiveHelper.radiusL),
      child: Container(
        constraints: BoxConstraints(
          minHeight: ResponsiveHelper.cardMinHeight,
          maxWidth: ResponsiveHelper.maxCardWidth,
        ),
        decoration: responsiveGlassCardDecoration(context),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(ResponsiveHelper.radiusL),
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: ResponsiveHelper.isMobile ? 8 : 10,
              sigmaY: ResponsiveHelper.isMobile ? 8 : 10,
            ),
            child: Padding(
              padding: padding ?? ResponsiveHelper.cardPadding,
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  /// Responsive glass card widget without touch handling (for display-only cards)
  static Widget buildResponsiveGlassCardStatic(BuildContext context,
      {required Widget child, EdgeInsets? padding}) {
    ResponsiveHelper.init(context);
    return Container(
      constraints: BoxConstraints(
        minHeight: ResponsiveHelper.cardMinHeight,
        maxWidth: ResponsiveHelper.maxCardWidth,
      ),
      decoration: responsiveGlassCardDecoration(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(ResponsiveHelper.radiusL),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: ResponsiveHelper.isMobile ? 8 : 10,
            sigmaY: ResponsiveHelper.isMobile ? 8 : 10,
          ),
          child: Padding(
            padding: padding ?? ResponsiveHelper.cardPadding,
            child: child,
          ),
        ),
      ),
    );
  }

  /// Responsive scaffold with MediaQuery-based sizing
  static Widget buildResponsiveScaffold(
    BuildContext context, {
    required String title,
    required Widget body,
    List<Widget>? actions,
    Widget? floatingActionButton,
    Widget? drawer,
    Widget? leading,
    bool? showBackButton,
    VoidCallback? onBack,
  }) {
    ResponsiveHelper.init(context);
    return Scaffold(
      backgroundColor: primaryBlue,
      appBar: buildResponsiveAppBar(context, title,
          actions: actions,
          leading: leading,
          showBackButton: showBackButton,
          onBack: onBack),
      body: DecoratedBox(
        decoration: const BoxDecoration(color: primaryBlue),
        child: SafeArea(
          child: body,
        ),
      ),
      floatingActionButton: floatingActionButton,
      drawer: drawer,
    );
  }

  /// Responsive loading widget with MediaQuery-based sizing
  static Widget buildResponsiveLoadingWidget(BuildContext context,
      {String? message}) {
    ResponsiveHelper.init(context);
    return Center(
      child: Faux3DLoadingWidget(message: message),
    );
  }

  // Responsive text styles
  /// Responsive heading style
  static TextStyle responsiveHeadingStyle(BuildContext context) {
    ResponsiveHelper.init(context);
    return TextStyle(
      color: textPrimary,
      fontSize: ResponsiveHelper.h4,
      fontWeight: FontWeight.bold,
    );
  }

  /// Responsive subheading style
  static TextStyle responsiveSubHeadingStyle(BuildContext context) {
    ResponsiveHelper.init(context);
    return TextStyle(
      color: textSecondary,
      fontSize: ResponsiveHelper.bodyL,
      fontWeight: FontWeight.w600,
    );
  }

  /// Responsive body style
  static TextStyle responsiveBodyStyle(BuildContext context) {
    ResponsiveHelper.init(context);
    return TextStyle(
      color: textPrimary,
      fontSize: ResponsiveHelper.bodyM,
      fontWeight: FontWeight.normal,
    );
  }

  /// Responsive caption style
  static TextStyle responsiveCaptionStyle(BuildContext context) {
    ResponsiveHelper.init(context);
    return TextStyle(
      color: textSecondary,
      fontSize: ResponsiveHelper.bodyS,
      fontWeight: FontWeight.normal,
    );
  }

  // Responsive button styles
  /// Responsive elevated button style
  static ButtonStyle responsiveElevatedButtonStyle(BuildContext context) {
    ResponsiveHelper.init(context);
    return ElevatedButton.styleFrom(
      backgroundColor: primaryOrange,
      foregroundColor: textPrimary,
      elevation: ResponsiveHelper.elevation,
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacingL,
        vertical: ResponsiveHelper.spacingM,
      ),
      minimumSize: Size(
        ResponsiveHelper.wp(20),
        ResponsiveHelper.buttonHeight,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ResponsiveHelper.radiusM),
      ),
      textStyle: TextStyle(
        fontSize: ResponsiveHelper.bodyL,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  /// Responsive outlined button style
  static ButtonStyle responsiveOutlinedButtonStyle(BuildContext context) {
    ResponsiveHelper.init(context);
    return OutlinedButton.styleFrom(
      foregroundColor: textPrimary,
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacingL,
        vertical: ResponsiveHelper.spacingM,
      ),
      minimumSize: Size(
        ResponsiveHelper.wp(20),
        ResponsiveHelper.buttonHeight,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ResponsiveHelper.radiusM),
      ),
      side: const BorderSide(color: textPrimary, width: 1.5),
      textStyle: TextStyle(
        fontSize: ResponsiveHelper.bodyL,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
