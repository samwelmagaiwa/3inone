import "package:flutter/material.dart";

import "../constants/theme_constants.dart";

/// A row of filter chips that is wider than the screen, made obvious:
///
///   - a fade and an arrow at an edge say "there are more chips this way" (and go away at the end of the row);
///   - tapping the arrow slides the row along;
///   - tapping a chip ([ScrollChoiceChip]) slides it towards the start of the row, so the chips after it come into
///     view; at the end of the row it stops where the last chip ends.
class ScrollingChipRow extends StatefulWidget {
  const ScrollingChipRow({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.fadeColor = ThemeConstants.primaryBlue,
  });

  final List<Widget> children;
  final EdgeInsets padding;

  /// The colour behind the row, so the fade melts into it.
  final Color fadeColor;

  /// Slide the row so the chip that [chipContext] belongs to sits near its start. The chips after it show up; the row
  /// never goes past its own end.
  static void reveal(final BuildContext chipContext) {
    Scrollable.ensureVisible(
      chipContext,
      alignment: 0.06,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  State<ScrollingChipRow> createState() => _ScrollingChipRowState();
}

class _ScrollingChipRowState extends State<ScrollingChipRow> {
  final ScrollController _controller = ScrollController();
  bool _moreBefore = false;
  bool _moreAfter = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Is there anything hidden before / after what is on screen?
  void _look(final ScrollMetrics m) {
    final bool before = m.pixels > 1;
    final bool after = m.pixels < m.maxScrollExtent - 1;
    if (before != _moreBefore || after != _moreAfter) {
      setState(() {
        _moreBefore = before;
        _moreAfter = after;
      });
    }
  }

  void _slide(final double direction) {
    if (!_controller.hasClients) return;
    final ScrollPosition p = _controller.position;
    final double target = (p.pixels + direction * p.viewportDimension * 0.6).clamp(0.0, p.maxScrollExtent);
    _controller.animateTo(target, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(final BuildContext context) {
    return Stack(
      children: <Widget>[
        NotificationListener<Notification>(
          onNotification: (final Notification n) {
            if (n is ScrollMetricsNotification) _look(n.metrics);
            if (n is ScrollNotification) _look(n.metrics);
            return false;
          },
          child: SingleChildScrollView(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            padding: widget.padding,
            child: Row(children: widget.children),
          ),
        ),
        if (_moreBefore) _edge(before: true),
        if (_moreAfter) _edge(before: false),
      ],
    );
  }

  /// The fade with an arrow, over the first or the last chips.
  Widget _edge({required final bool before}) {
    return Positioned(
      top: 0,
      bottom: 0,
      left: before ? 0 : null,
      right: before ? null : 0,
      child: GestureDetector(
        key: ValueKey<String>(before ? "chips_more_before" : "chips_more_after"),
        behavior: HitTestBehavior.opaque,
        onTap: () => _slide(before ? -1 : 1),
        child: Container(
          width: 44,
          alignment: before ? Alignment.centerLeft : Alignment.centerRight,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: before ? Alignment.centerLeft : Alignment.centerRight,
              end: before ? Alignment.centerRight : Alignment.centerLeft,
              colors: <Color>[widget.fadeColor, widget.fadeColor.withValues(alpha: 0)],
            ),
          ),
          child: Icon(before ? Icons.chevron_left : Icons.chevron_right, color: Colors.white70, size: 26),
        ),
      ),
    );
  }
}

/// A filter chip for a [ScrollingChipRow]: choosing it also slides the row so the next chips come into view.
class ScrollChoiceChip extends StatelessWidget {
  const ScrollChoiceChip({super.key, required this.label, required this.selected, required this.onSelected});

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(final BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Builder(
          builder: (final BuildContext chipContext) => ChoiceChip(
            label: Text(label),
            selected: selected,
            onSelected: (final bool value) {
              ScrollingChipRow.reveal(chipContext);
              onSelected(value);
            },
          ),
        ),
      );
}
