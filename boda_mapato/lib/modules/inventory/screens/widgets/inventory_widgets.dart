import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../models/user_permissions.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../services/localization_service.dart';

/// Formats numbers dynamically with thousand separators as typed (e.g., 20000 -> 20,000)
class ThousandsFormatter extends TextInputFormatter {
  static final RegExp _digitOnly = RegExp(r'[^\d.]');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    final String cleanText = newValue.text.replaceAll(',', '').replaceAll(_digitOnly, '');
    if (cleanText.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    // Handle decimal if any
    final parts = cleanText.split('.');
    final int integerPart = int.tryParse(parts[0]) ?? 0;
    String formatted = NumberFormat('#,###', 'en_US').format(integerPart);
    if (parts.length > 1) {
      formatted += '.${parts[1]}';
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// Helper to format a number into comma-separated string (e.g., 20000 -> 20,000)
String formatAmount(num? amount) {
  if (amount == null) return '0';
  final formatter = NumberFormat('#,###', 'en_US');
  if (amount is double && amount != amount.roundToDouble()) {
    return NumberFormat('#,##0.##', 'en_US').format(amount);
  }
  return formatter.format(amount);
}

/// Helper to parse text with potential commas into double
double parseAmount(String? text) {
  if (text == null || text.trim().isEmpty) return 0.0;
  final clean = text.replaceAll(',', '').trim();
  return double.tryParse(clean) ?? 0.0;
}

/// Shared inventory building blocks.
///
/// Every one of these follows the module's overflow rules: text in a [Row] is
/// always inside [Expanded]/[Flexible], single-line labels use [AutoSizeText]
/// with a floor, numbers that must stay on one line use [FittedBox], and
/// sheets are keyboard-aware and height-capped.

/// Small labelled figure used in summary rows.
class InvStatTile extends StatelessWidget {
  const InvStatTile({
    required this.label,
    required this.value,
    required this.icon,
    this.accent,
    super.key,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? accent;

  @override
  Widget build(BuildContext context) => Container(
        decoration: ThemeConstants.glassCardDecoration,
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              icon,
              size: 13.sp,
              color: accent ?? Colors.white70,
            ),
            SizedBox(height: 2.h),
            AutoSizeText(
              label,
              maxLines: 1,
              minFontSize: 9,
              overflow: TextOverflow.ellipsis,
              style: ThemeConstants.captionStyle,
            ),
            SizedBox(height: 1.h),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: ThemeConstants.bodyStyle.copyWith(
                  fontWeight: FontWeight.w700,
                  // the plain red is too dim to read as a number on the dark card
                  color: accent == ThemeConstants.errorRed ? ThemeConstants.errorText : (accent ?? ThemeConstants.textPrimary),
                ),
              ),
            ),
          ],
        ),
      );
}

/// Rounded status pill.
class InvBadge extends StatelessWidget {
  const InvBadge({required this.label, required this.color, super.key});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
        decoration: BoxDecoration(
          color: color.withOpacity(0.22),
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(color: color.withOpacity(0.65)),
        ),
        constraints: BoxConstraints(maxWidth: 120.w),
        child: AutoSizeText(
          label,
          maxLines: 1,
          minFontSize: 8,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Colors.white, fontSize: 10.sp),
        ),
      );
}

/// Search box in the module's input style.
class InvSearchField extends StatelessWidget {
  const InvSearchField({
    required this.hint,
    required this.onChanged,
    super.key,
  });

  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => TextField(
        onChanged: onChanged,
        style: ThemeConstants.bodyStyle,
        decoration: ThemeConstants.invInputDecoration(hint).copyWith(
          prefixIcon: const Icon(Icons.search, color: Colors.white70),
        ),
      );
}

/// Horizontally scrollable single-choice chips — never overflows, however many.
class InvFilterChips<T> extends StatelessWidget {
  const InvFilterChips({
    required this.value,
    required this.options,
    required this.onSelected,
    super.key,
  });

  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: options.entries.map((MapEntry<T, String> e) {
            final bool selected = e.key == value;
            return Padding(
              padding: EdgeInsets.only(right: 8.w),
              child: GestureDetector(
                onTap: () => onSelected(e.key),
                child: Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.h),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white.withOpacity(0.3)
                        : Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20.r),
                  ),
                  child: Text(
                    e.value,
                    style: TextStyle(
                      color: selected
                          ? ThemeConstants.textPrimary
                          : ThemeConstants.textSecondary,
                      fontSize: 13.sp,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      );
}

/// Centred placeholder for an empty list.
class InvEmptyState extends StatelessWidget {
  const InvEmptyState({
    required this.icon,
    required this.message,
    super.key,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 32.w, vertical: 48.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 44.sp, color: Colors.white24),
              SizedBox(height: 12.h),
              Text(
                message,
                textAlign: TextAlign.center,
                style: ThemeConstants.captionStyle,
              ),
            ],
          ),
        ),
      );
}

/// Keyboard-aware, height-capped bottom sheet shell.
class InvSheetShell extends StatelessWidget {
  const InvSheetShell({
    required this.title,
    required this.children,
    super.key,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: ThemeConstants.primaryBlue,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
              border: Border.all(color: Colors.white24),
            ),
            padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 16.h),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Center(
                    child: Container(
                      width: 40.w,
                      height: 4.h,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(4.r),
                      ),
                    ),
                  ),
                  SizedBox(height: 12.h),
                  AutoSizeText(
                    title,
                    maxLines: 1,
                    minFontSize: 13,
                    overflow: TextOverflow.ellipsis,
                    style: ThemeConstants.headingStyle,
                  ),
                  SizedBox(height: 12.h),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      );
}

/// Text field in the module's input style, with an optional-suffix label.
class InvTextField extends StatelessWidget {
  const InvTextField({
    required this.controller,
    required this.label,
    this.hint,
    this.keyboardType,
    this.inputFormatters,
    this.validator,
    this.isOptional = false,
    this.maxLines = 1,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final FormFieldValidator<String>? validator;
  final bool isOptional;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final String fullLabel = isOptional
        ? '$label (${LocalizationService.instance.translate('optional')})'
        : label;

    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      maxLines: maxLines,
      style: ThemeConstants.bodyStyle,
      decoration: ThemeConstants.invInputDecoration(fullLabel).copyWith(
        labelText: fullLabel,
        hintText: hint ?? fullLabel,
      ),
    );
  }
}

/// Tappable date field that opens the platform picker.
class InvDateField extends StatelessWidget {
  const InvDateField({
    required this.label,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    final String text = value == null
        ? LocalizationService.instance.translate('not_set')
        : '${value!.day}/${value!.month}/${value!.year}';

    return InkWell(
      onTap: () async {
        final DateTime? picked = await showDatePicker(
          context: context,
          initialDate: value ?? now.add(const Duration(days: 90)),
          firstDate: DateTime(now.year - 2),
          lastDate: DateTime(now.year + 10),
        );
        if (picked != null) {
          onChanged(picked);
        }
      },
      borderRadius: BorderRadius.circular(12.r),
      child: InputDecorator(
        decoration: ThemeConstants.invInputDecoration(label),
        child: Row(
          children: <Widget>[
            Expanded(
              child: AutoSizeText(
                text,
                maxLines: 1,
                minFontSize: 10,
                overflow: TextOverflow.ellipsis,
                style: ThemeConstants.bodyStyle,
              ),
            ),
            if (value != null)
              GestureDetector(
                onTap: () => onChanged(null),
                child: const Icon(Icons.clear, color: Colors.white54, size: 18),
              )
            else
              const Icon(Icons.event, color: Colors.white54, size: 18),
          ],
        ),
      ),
    );
  }
}

/// Full-width primary action with a busy state.
class InvPrimaryButton extends StatelessWidget {
  const InvPrimaryButton({
    required this.busy,
    required this.onPressed,
    this.label,
    this.color,
    super.key,
  });

  final bool busy;
  final VoidCallback onPressed;
  final String? label;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 46.h,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: color ?? ThemeConstants.primaryOrange,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14.r),
            ),
          ),
          onPressed: busy ? null : onPressed,
          child: busy
              ? SizedBox(
                  width: 20.w,
                  height: 20.w,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  label ?? LocalizationService.instance.translate('save'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      );
}

/// Tabbed page shell used by the depot screens, styled like the rest of the
/// module. Tab labels scroll horizontally so a long set never overflows.
/// When there are more tabs off-screen a right-edge fade gradient cues the
/// user to scroll; it vanishes once the last tab is selected.
///
/// [tabPermissions] is an optional parallel list of predicates — one per tab.
/// When provided, any tab whose predicate returns false for the current user's
/// [UserPermissions] is hidden. Pass null entries to always-show a tab.
class InvTabScaffold extends StatefulWidget {
  const InvTabScaffold({
    required this.title,
    required this.tabs,
    required this.views,
    this.tabPermissions,
    this.actions,
    this.floatingActionButton,
    super.key,
  }) : assert(tabPermissions == null || tabPermissions.length == tabs.length);

  final String title;
  final List<String> tabs;
  final List<Widget> views;
  /// Optional per-tab permission predicate. null entry = always visible.
  final List<bool Function(UserPermissions)?> ? tabPermissions;
  final List<Widget>? actions;
  final Widget? floatingActionButton;

  @override
  State<InvTabScaffold> createState() => _InvTabScaffoldState();
}

// TickerProviderStateMixin, not the Single one: when the number of tabs changes (a hub dropping its crates tab
// for a business without crates) a new TabController is made, and the Single mixin allows one ticker for the
// whole life of the State, even after the first controller was disposed -- debug builds then stop with
// "multiple tickers were created".
class _InvTabScaffoldState extends State<InvTabScaffold>
    with TickerProviderStateMixin {
  late TabController _ctrl;
  bool _atEnd = false;

  // Resolved after filtering by permissions.
  late List<String> _tabs;
  late List<Widget> _views;

  @override
  void initState() {
    super.initState();
    _applyPermissions();
    _ctrl = TabController(length: _tabs.length, vsync: this);
    _atEnd = _tabs.length <= 1;
    _ctrl.addListener(_onTab);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-filter when the auth/permissions context changes.
    _rebuildTabs();
  }

  @override
  void didUpdateWidget(InvTabScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A hub may add or drop a tab while it is open (the crates tab, once the business's kind is known).
    if (oldWidget.tabs.length != widget.tabs.length) {
      _rebuildTabs();
    } else {
      _applyPermissions();
    }
  }

  void _applyPermissions() {
    final perms = _readPerms();
    final List<String> tabs = [];
    final List<Widget> views = [];
    for (int i = 0; i < widget.tabs.length; i++) {
      final pred = widget.tabPermissions?[i];
      if (pred == null || pred(perms)) {
        tabs.add(widget.tabs[i]);
        views.add(widget.views[i]);
      }
    }
    // Ensure at least one tab survives.
    if (tabs.isEmpty) {
      _tabs = [widget.tabs.first];
      _views = [widget.views.first];
    } else {
      _tabs = tabs;
      _views = views;
    }
  }

  UserPermissions _readPerms() {
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final user = auth.user;
      if (user == null) return UserPermissions.empty();
      return UserPermissions.fromUser(
        userRole: user.role,
        explicitGrants: user.permissions,
      );
    } catch (_) {
      return UserPermissions.empty();
    }
  }

  void _rebuildTabs() {
    final List<String> prevTabs = _tabs;
    _applyPermissions();
    if (_tabs.length != prevTabs.length) {
      _ctrl.removeListener(_onTab);
      _ctrl.dispose();
      _ctrl = TabController(length: _tabs.length, vsync: this);
      _atEnd = _tabs.length <= 1;
      _ctrl.addListener(_onTab);
    }
  }

  void _onTab() {
    final bool nowAtEnd = _ctrl.index == _tabs.length - 1;
    if (nowAtEnd != _atEnd) setState(() => _atEnd = nowAtEnd);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onTab);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabBar = TabBar(
      controller: _ctrl,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      indicatorColor: ThemeConstants.primaryOrange,
      labelColor: ThemeConstants.textPrimary,
      unselectedLabelColor: ThemeConstants.textSecondary,
      labelStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
      tabs: _tabs.map((String t) => Tab(text: t)).toList(),
    );

    // Wrap the tab bar in a Stack so we can overlay a right-edge fade
    // that signals "more tabs this way →". The gradient covers ~48 logical
    // pixels and disappears once the last tab is active.
    final PreferredSizeWidget tabBarWithFade = PreferredSize(
      preferredSize: tabBar.preferredSize,
      child: Stack(
        children: [
          tabBar,
          if (!_atEnd)
            Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              width: 48.w,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        ThemeConstants.primaryBlue.withValues(alpha: 0),
                        ThemeConstants.primaryBlue.withValues(alpha: 0.92),
                      ],
                    ),
                  ),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: EdgeInsets.only(right: 6.w, bottom: 4.h),
                      child: Icon(
                        Icons.chevron_right,
                        color: Colors.white54,
                        size: 18.sp,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: widget.title.isEmpty ? 0 : kToolbarHeight,
        iconTheme: const IconThemeData(color: ThemeConstants.textPrimary),
        title: widget.title.isEmpty
            ? null
            : AutoSizeText(
                widget.title,
                maxLines: 1,
                minFontSize: 13,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: ThemeConstants.textPrimary,
                  fontSize: 19.sp,
                  fontWeight: FontWeight.bold,
                ),
              ),
        actions: widget.actions,
        bottom: tabBarWithFade,
      ),
      floatingActionButton: widget.floatingActionButton,
      body: SafeArea(
        child: TabBarView(controller: _ctrl, children: _views),
      ),
    );
  }
}

/// Table that scrolls in both directions, so any number of columns of any
/// width stays reachable and the page body never overflows horizontally.
class InvDataTable extends StatelessWidget {
  const InvDataTable({
    required this.columns,
    required this.rows,
    this.footer,
    super.key,
  });

  final List<String> columns;
  final List<List<String>> rows;
  final Widget? footer;

  static const TableBorder _border = TableBorder(
    top:              BorderSide(color: Colors.white24, width: 0.8),
    bottom:           BorderSide(color: Colors.white24, width: 0.8),
    left:             BorderSide(color: Colors.white24, width: 0.8),
    right:            BorderSide(color: Colors.white24, width: 0.8),
    horizontalInside: BorderSide(color: Colors.white24, width: 0.8),
    verticalInside:   BorderSide(color: Colors.white24, width: 0.8),
  );

  @override
  Widget build(BuildContext context) {
    final headerStyle = ThemeConstants.captionStyle
        .copyWith(fontWeight: FontWeight.w700, fontSize: 11.sp);
    final cellStyle = ThemeConstants.bodyStyle.copyWith(fontSize: 11.sp);
    final pad = EdgeInsets.symmetric(horizontal: 10.w, vertical: 9.h);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: IntrinsicWidth(
                child: Table(
                  border: _border,
                  // IntrinsicColumnWidth sizes each column to its widest cell.
                  // As new columns arrive the table widens; as rows arrive it
                  // grows taller — grid lines follow automatically.
                  defaultColumnWidth: const IntrinsicColumnWidth(),
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: <TableRow>[
                    // ── Header ───────────────────────────────────────────
                    TableRow(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                      ),
                      children: columns
                          .map((String c) => Padding(
                                padding: pad,
                                child: Text(c,
                                    style: headerStyle, maxLines: 1),
                              ))
                          .toList(),
                    ),
                    // ── Data rows ────────────────────────────────────────
                    ...rows.asMap().entries.map(
                      (MapEntry<int, List<String>> entry) => TableRow(
                        decoration: BoxDecoration(
                          color: entry.key.isOdd
                              ? Colors.white.withOpacity(0.04)
                              : Colors.transparent,
                        ),
                        children: entry.value
                            .map((String cell) => Padding(
                                  padding: pad,
                                  child: Text(cell,
                                      style: cellStyle,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (footer != null) footer!,
      ],
    );
  }
}

/// Row of label/value pairs that wraps instead of overflowing.
class InvKeyValueWrap extends StatelessWidget {
  const InvKeyValueWrap({required this.entries, super.key});

  final Map<String, String> entries;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 16.w,
        runSpacing: 8.h,
        children: entries.entries
            .map((MapEntry<String, String> e) => ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 160.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      AutoSizeText(
                        e.key,
                        maxLines: 1,
                        minFontSize: 9,
                        overflow: TextOverflow.ellipsis,
                        style: ThemeConstants.captionStyle,
                      ),
                      AutoSizeText(
                        e.value,
                        maxLines: 1,
                        minFontSize: 10,
                        overflow: TextOverflow.ellipsis,
                        style: ThemeConstants.bodyStyle
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ))
            .toList(),
      );
}
