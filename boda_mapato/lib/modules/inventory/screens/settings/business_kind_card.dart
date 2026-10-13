import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../constants/theme_constants.dart';
import '../../models/inv_capabilities.dart';
import '../products/product_form_sections.dart' show glassChoiceChip;

/// "What kind of stock business is this?" -- retail, wholesale, both, or a depot -- where an inventory owner
/// looks for it: at the top of Depot settings.
///
/// It decides how the product page and the till behave (crates, which price the till uses, sizes and packs).
/// Changing it only moves the settings that are still at the old kind's starting values; no product, price
/// or sale is touched.
///
/// The card never hides: when the server is too old to know about kinds it says so, instead of leaving the
/// owner searching for a setting that is not there.
class BusinessKindCard extends StatefulWidget {
  const BusinessKindCard({
    super.key,
    required this.serverKnowsKinds,
    required this.current,
    required this.canChange,
    required this.onChange,
    required this.sw,
  });

  /// Did the server report a kind at all? (An older server does not.)
  final bool serverKnowsKinds;

  /// retail | wholesale | mixed | depot -- what the business is now.
  final String current;

  /// Only the owner of the business may change it.
  final bool canChange;

  /// Saves the new kind. Returns null on success, or the reason it was refused.
  final Future<String?> Function(String kind) onChange;
  final bool sw;

  @override
  State<BusinessKindCard> createState() => _BusinessKindCardState();
}

class _BusinessKindCardState extends State<BusinessKindCard> {
  late String _selected = widget.current;
  bool _saving = false;
  String? _error;

  @override
  void didUpdateWidget(BusinessKindCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // After a save the new kind arrives from the server: show it as the chosen one.
    if (oldWidget.current != widget.current) _selected = widget.current;
  }

  bool get _sw => widget.sw;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final String? refused = await widget.onChange(_selected);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = refused;
    });
    if (refused == null) {
      ThemeConstants.showSuccessSnackBar(context, _sw ? 'Imehifadhiwa' : 'Saved');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool changed = _selected != widget.current;

    return Container(
      key: const ValueKey<String>('business_kind_card'),
      width: double.infinity,
      decoration: ThemeConstants.glassCardDecoration,
      padding: EdgeInsets.all(12.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.category_outlined, color: Colors.white70, size: 18.sp),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  _sw ? 'Aina ya biashara' : 'Kind of business',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          SizedBox(height: 10.h),
          if (!widget.serverKnowsKinds)
            Container(
              key: const ValueKey<String>('business_kind_server_old'),
              padding: EdgeInsets.all(10.w),
              decoration: BoxDecoration(
                color: ThemeConstants.warningAmber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: ThemeConstants.warningAmber.withValues(alpha: 0.4)),
              ),
              child: Text(
                _sw
                    ? 'Seva yako haijasasishwa bado, kwa hiyo aina ya biashara haiwezi kuonyeshwa wala kubadilishwa hapa. '
                        'Sasisha seva na uendeshe migration zake kwanza.'
                    : 'Your server has not been updated yet, so the kind of business cannot be shown or changed here. '
                        'Update the server and run its migrations first.',
                style: ThemeConstants.captionStyle.copyWith(fontSize: 12.sp, color: Colors.white),
              ),
            )
          else ...<Widget>[
            Wrap(
              spacing: 8.w,
              runSpacing: 6.h,
              children: <Widget>[
                for (final String t in kInventoryTypes)
                  glassChoiceChip(
                    key: ValueKey<String>('business_kind_$t'),
                    label: inventoryTypeLabel(t, sw: _sw),
                    selected: _selected == t,
                    onSelected: (widget.canChange && !_saving) ? (_) => setState(() => _selected = t) : null,
                  ),
              ],
            ),
            SizedBox(height: 8.h),
            Text(
              inventoryTypeHint(_selected, sw: _sw),
              key: const ValueKey<String>('business_kind_hint'),
              style: ThemeConstants.captionStyle.copyWith(fontSize: 12.sp, color: Colors.white70),
            ),
            SizedBox(height: 6.h),
            Text(
              widget.canChange
                  ? (_sw
                      ? 'Kubadilisha hakubadilishi bidhaa, bei wala mauzo yako; kunabadilisha tu mipangilio uliyokuwa hujaibadilisha mwenyewe.'
                      : 'Changing this does not touch your products, prices or sales; it only moves the settings you have not changed yourself.')
                  : (_sw
                      ? 'Mmiliki wa biashara tu ndiye anayeweza kubadilisha hili.'
                      : 'Only the owner of the business can change this.'),
              key: widget.canChange ? null : const ValueKey<String>('business_kind_read_only'),
              style: ThemeConstants.captionStyle.copyWith(fontSize: 11.sp, color: Colors.white38),
            ),
            if (_error != null) ...<Widget>[
              SizedBox(height: 8.h),
              Text(
                _error!,
                key: const ValueKey<String>('business_kind_error'),
                style: ThemeConstants.captionStyle.copyWith(color: ThemeConstants.errorRed, fontSize: 12.sp),
              ),
            ],
            if (widget.canChange && changed) ...<Widget>[
              SizedBox(height: 10.h),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey<String>('business_kind_save'),
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? SizedBox(
                          width: 18.w,
                          height: 18.w,
                          child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(_sw ? 'Hifadhi aina ya biashara' : 'Save kind of business'),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
