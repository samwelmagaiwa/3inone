import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// The action buttons of the inventory screens: a raised, rounded button with an icon in a lighter tile, the label, and an arrow, so it
/// reads as something to press. [filled] buttons are a colour gradient with white text (the main actions); the others are a tinted glass
/// with a coloured edge (the quieter ones). Pressing shows a ripple and the button sinks a little.
class InvActionButton extends StatefulWidget {
  const InvActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
    this.filled = true,
    this.arrow = true,
  });

  final String label;
  final IconData icon;
  final Color color;

  /// Null shows the button disabled.
  final VoidCallback? onPressed;
  final bool filled;

  /// The arrow at the end that says "this opens something". Off for a button that acts on the spot.
  final bool arrow;

  @override
  State<InvActionButton> createState() => _InvActionButtonState();
}

class _InvActionButtonState extends State<InvActionButton> {
  bool _down = false;

  @override
  Widget build(final BuildContext context) {
    final bool enabled = widget.onPressed != null;
    final Color base = enabled ? widget.color : Colors.grey;
    final Color dark = HSLColor.fromColor(base).withLightness((HSLColor.fromColor(base).lightness * 0.72).clamp(0.0, 1.0)).toColor();
    final BorderRadius radius = BorderRadius.circular(14.r);

    return AnimatedScale(
      scale: _down ? 0.98 : 1,
      duration: const Duration(milliseconds: 90),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: widget.filled ? LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: <Color>[base, dark]) : null,
          color: widget.filled ? null : base.withValues(alpha: 0.14),
          border: widget.filled ? null : Border.all(color: base.withValues(alpha: 0.75), width: 1.2),
          boxShadow: widget.filled && enabled && !_down ? <BoxShadow>[BoxShadow(color: base.withValues(alpha: 0.38), blurRadius: 10, offset: const Offset(0, 4))] : const <BoxShadow>[],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: radius,
            onTap: widget.onPressed,
            onHighlightChanged: (bool v) => setState(() => _down = v),
            splashColor: Colors.white24,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 9.h),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 32.w,
                    height: 32.w,
                    decoration: BoxDecoration(color: widget.filled ? Colors.white.withValues(alpha: 0.22) : base.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(10.r)),
                    child: Icon(widget.icon, size: 18.sp, color: widget.filled ? Colors.white : base),
                  ),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: AutoSizeText(
                      widget.label,
                      maxLines: 1,
                      minFontSize: 9,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white, fontSize: 13.sp, fontWeight: FontWeight.w800, letterSpacing: 0.2),
                    ),
                  ),
                  if (widget.arrow) Icon(Icons.chevron_right_rounded, size: 22.sp, color: widget.filled ? Colors.white70 : base),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
