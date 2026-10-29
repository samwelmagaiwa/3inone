import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../constants/theme_constants.dart';
import '../../models/inv_capabilities.dart';

/// Asked when the owner taps "Add product": what kind of business is this? Picking one saves it (the product
/// page and the till behave by it) and the product page opens right after; closing the card opens nothing.
///
/// Returns true when a kind was picked and is saved (or was already the current one), false when the owner
/// backed out.
Future<bool> chooseBusinessKind(
  BuildContext context, {
  required String current,
  required Future<String?> Function(String kind) onChange,
  required bool sw,
}) async {
  final bool? picked = await showDialog<bool>(
    context: context,
    builder: (BuildContext _) => BusinessKindChooser(current: current, onChange: onChange, sw: sw),
  );
  return picked ?? false;
}

class BusinessKindChooser extends StatefulWidget {
  const BusinessKindChooser({super.key, required this.current, required this.onChange, required this.sw});

  /// retail | wholesale | mixed | depot -- what the business is now.
  final String current;

  /// Saves the kind. Returns null on success, or the reason it was refused.
  final Future<String?> Function(String kind) onChange;
  final bool sw;

  @override
  State<BusinessKindChooser> createState() => _BusinessKindChooserState();
}

class _BusinessKindChooserState extends State<BusinessKindChooser> {
  /// The kind being saved right now.
  String? _saving;
  String? _error;

  bool get _sw => widget.sw;

  Future<void> _pick(String kind) async {
    if (_saving != null) return;
    if (kind == widget.current) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _saving = kind;
      _error = null;
    });
    final String? refused = await widget.onChange(kind);
    if (!mounted) return;
    if (refused == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _saving = null;
        _error = refused;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      key: const ValueKey<String>('business_kind_chooser'),
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 24.h),
      // A cyan edge and soft cyan glows, like the cards of Depot settings and the dashboard (Material's own
      // elevation shadow cannot be tinted into a glow: it comes out as a hard band).
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ThemeConstants.primaryBlue,
          borderRadius: BorderRadius.circular(20.r),
          border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.42), width: 1.6),
          boxShadow: <BoxShadow>[
            BoxShadow(color: Colors.cyanAccent.withValues(alpha: 0.30), blurRadius: 22),
            BoxShadow(color: Colors.cyanAccent.withValues(alpha: 0.14), blurRadius: 42, spreadRadius: 2),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 8.h),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: 38.w,
                      height: 38.w,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12.r),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: <Color>[ThemeConstants.primaryCyan, ThemeConstants.invAccent],
                        ),
                        boxShadow: <BoxShadow>[
                          BoxShadow(color: ThemeConstants.primaryCyan.withValues(alpha: 0.45), blurRadius: 12, offset: const Offset(0, 3)),
                        ],
                      ),
                      child: Icon(Icons.category_rounded, color: ThemeConstants.primaryBlue, size: 22.sp),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Text(
                        _sw ? 'Biashara yako ni ya aina gani?' : 'What kind of business is this?',
                        style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w800, fontSize: 17.sp),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 10.h),
                Text(
                  _sw ? 'Chagua ili uendelee kuongeza bidhaa.' : 'Pick one to carry on adding the product.',
                  style: ThemeConstants.captionStyle.copyWith(fontSize: 12.sp, color: Colors.white70),
                ),
                SizedBox(height: 14.h),
                for (int i = 0; i < kInventoryTypes.length; i++) ...<Widget>[
                  _KindTile(
                    key: ValueKey<String>('chooser_kind_${kInventoryTypes[i]}'),
                    kind: kInventoryTypes[i],
                    index: i,
                    label: inventoryTypeLabel(kInventoryTypes[i], sw: _sw),
                    hint: inventoryTypeHint(kInventoryTypes[i], sw: _sw),
                    current: kInventoryTypes[i] == widget.current,
                    currentLabel: _sw ? 'Sasa' : 'Current',
                    saving: _saving == kInventoryTypes[i],
                    dimmed: _saving != null && _saving != kInventoryTypes[i],
                    onTap: _saving == null ? () => _pick(kInventoryTypes[i]) : null,
                  ),
                  SizedBox(height: 10.h),
                ],
                if (_error != null) ...<Widget>[
                  Text(
                    _error!,
                    key: const ValueKey<String>('chooser_error'),
                    style: ThemeConstants.captionStyle.copyWith(color: ThemeConstants.errorText, fontSize: 12.sp),
                  ),
                  SizedBox(height: 6.h),
                ],
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: const ValueKey<String>('chooser_cancel'),
                    style: TextButton.styleFrom(foregroundColor: Colors.white70),
                    onPressed: _saving == null ? () => Navigator.of(context).pop(false) : null,
                    child: Text(_sw ? 'Ghairi' : 'Cancel'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// How each kind looks: its own icon and colour, so the four are told apart at a glance.
({IconData icon, Color color}) _look(String kind) => switch (kind) {
      'retail' => (icon: Icons.storefront_rounded, color: ThemeConstants.primaryCyan),
      'wholesale' => (icon: Icons.warehouse_rounded, color: ThemeConstants.warningAmber),
      'mixed' => (icon: Icons.compare_arrows_rounded, color: const Color(0xFF8B8CF5)),
      'depot' => (icon: Icons.liquor_rounded, color: ThemeConstants.successGreen),
      _ => (icon: Icons.category_rounded, color: ThemeConstants.invAccent),
    };

/// One kind of business as a card to tap: a coloured icon, its name and what it is for. The current one has a
/// glowing outline and a "Current" mark; the others an arrow. They slide in one after the other.
class _KindTile extends StatelessWidget {
  const _KindTile({
    super.key,
    required this.kind,
    required this.index,
    required this.label,
    required this.hint,
    required this.current,
    required this.currentLabel,
    required this.saving,
    required this.dimmed,
    required this.onTap,
  });

  final String kind;
  final int index;
  final String label;
  final String hint;
  final bool current;
  final String currentLabel;
  final bool saving;

  /// Another kind is being saved: this one steps back.
  final bool dimmed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ({IconData icon, Color color}) look = _look(kind);
    final Color c = look.color;
    final BorderRadius radius = BorderRadius.circular(16.r);

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 240 + 70 * index),
      curve: Curves.easeOutCubic,
      builder: (BuildContext _, double v, Widget? child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 16 * (1 - v)), child: child),
      ),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: dimmed ? 0.45 : 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[c.withValues(alpha: current ? 0.30 : 0.17), Colors.white.withValues(alpha: 0.05)],
            ),
            border: Border.all(color: current ? c : Colors.white.withValues(alpha: 0.16), width: current ? 1.6 : 1),
            boxShadow: <BoxShadow>[
              if (current) BoxShadow(color: c.withValues(alpha: 0.38), blurRadius: 16),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              borderRadius: radius,
              splashColor: c.withValues(alpha: 0.22),
              highlightColor: c.withValues(alpha: 0.10),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
                child: Row(
                  children: <Widget>[
                    // the icon badge
                    Container(
                      width: 46.w,
                      height: 46.w,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14.r),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: <Color>[c, Color.lerp(c, Colors.black, 0.40)!],
                        ),
                        boxShadow: <BoxShadow>[BoxShadow(color: c.withValues(alpha: 0.40), blurRadius: 10, offset: const Offset(0, 3))],
                      ),
                      child: Icon(look.icon, color: Colors.white, size: 26.sp),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(label, style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w800, fontSize: 15.sp)),
                          SizedBox(height: 3.h),
                          Text(hint, style: ThemeConstants.captionStyle.copyWith(fontSize: 11.5.sp, color: Colors.white70, height: 1.3)),
                        ],
                      ),
                    ),
                    SizedBox(width: 8.w),
                    if (saving)
                      SizedBox(width: 22.w, height: 22.w, child: CircularProgressIndicator(strokeWidth: 2.4, color: c))
                    else if (current)
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 9.w, vertical: 4.h),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20.r),
                          color: c.withValues(alpha: 0.22),
                          border: Border.all(color: c.withValues(alpha: 0.8)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(Icons.check_circle_rounded, color: Color.lerp(c, Colors.white, 0.4), size: 13.sp),
                            SizedBox(width: 4.w),
                            Text(
                              currentLabel,
                              style: ThemeConstants.captionStyle.copyWith(fontSize: 11.sp, fontWeight: FontWeight.w700, color: Colors.white),
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        width: 30.w,
                        height: 30.w,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.10)),
                        child: Icon(Icons.arrow_forward_rounded, color: Colors.white70, size: 17.sp),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
