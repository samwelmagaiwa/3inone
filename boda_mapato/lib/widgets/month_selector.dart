import 'package:flutter/material.dart';

/// The row of month chips above a monthly chart.
///
/// It is a horizontal scroller, so on a phone only about five months fit. It always scrolls
/// so the SELECTED month is in view -- when the screen opens (the chart starts on the current
/// month, which would otherwise be hidden off to the right for most of the year) and whenever
/// a month is picked. In between it scrolls freely, so earlier months are a swipe away.
class MonthSelector extends StatefulWidget {
  const MonthSelector({
    super.key,
    required this.months,
    required this.selectedMonth,
    required this.onSelected,
    required this.selectedColor,
    required this.unselectedColor,
  });

  /// Labels, January first.
  final List<String> months;

  /// 1 = January ... 12 = December.
  final int selectedMonth;

  /// Called with the month number (1-12) the user tapped.
  final ValueChanged<int> onSelected;

  final Color selectedColor;
  final Color unselectedColor;

  @override
  State<MonthSelector> createState() => _MonthSelectorState();
}

class _MonthSelectorState extends State<MonthSelector> {
  // One stable key per chip, so the selected chip can be found and scrolled to.
  late final List<GlobalKey> _chipKeys =
      List<GlobalKey>.generate(widget.months.length, (_) => GlobalKey());

  @override
  void initState() {
    super.initState();
    _revealSelected(animate: false);
  }

  @override
  void didUpdateWidget(final MonthSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedMonth != widget.selectedMonth) {
      _revealSelected(animate: true);
    }
  }

  void _revealSelected({required final bool animate}) {
    // After layout: the chips (and their positions) do not exist yet in initState.
    WidgetsBinding.instance.addPostFrameCallback((final Duration _) {
      final int index = widget.selectedMonth - 1;
      if (!mounted || index < 0 || index >= _chipKeys.length) return;
      final BuildContext? chip = _chipKeys[index].currentContext;
      if (chip == null) return;
      Scrollable.ensureVisible(
        chip,
        alignment: 0.5,
        duration: animate ? const Duration(milliseconds: 250) : Duration.zero,
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(final BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            for (int i = 0; i < widget.months.length; i++) _chip(i),
          ],
        ),
      );

  Widget _chip(final int index) {
    final bool isSelected = index + 1 == widget.selectedMonth;

    return GestureDetector(
      key: _chipKeys[index],
      onTap: () => widget.onSelected(index + 1),
      child: Container(
        margin: const EdgeInsets.only(right: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withValues(alpha: 0.3)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          widget.months[index],
          style: TextStyle(
            color: isSelected ? widget.selectedColor : widget.unselectedColor,
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
