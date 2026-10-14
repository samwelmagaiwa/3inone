import "dart:math" as math;

import "package:flutter/material.dart";
import "../constants/theme_constants.dart";

const List<String> _monthsEn = <String>[
  "January",
  "February",
  "March",
  "April",
  "May",
  "June",
  "July",
  "August",
  "September",
  "October",
  "November",
  "December"
];
const List<String> _monthsSw = <String>[
  "Januari",
  "Februari",
  "Machi",
  "Aprili",
  "Mei",
  "Juni",
  "Julai",
  "Agosti",
  "Septemba",
  "Oktoba",
  "Novemba",
  "Desemba"
];
const List<String> _shortMonthsEn = <String>[
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Oct",
  "Nov",
  "Dec"
];
const List<String> _shortMonthsSw = <String>[
  "Jan",
  "Feb",
  "Mac",
  "Apr",
  "Mei",
  "Jun",
  "Jul",
  "Ago",
  "Sep",
  "Okt",
  "Nov",
  "Des"
];
// DateTime.weekday: Monday is 1.
const List<String> _weekdaysEn = <String>[
  "Mon",
  "Tue",
  "Wed",
  "Thu",
  "Fri",
  "Sat",
  "Sun"
];
const List<String> _weekdaysSw = <String>[
  "Jtt",
  "Jnn",
  "Jtn",
  "Alh",
  "Ijm",
  "Jms",
  "Jpl"
];

/// "14 Oct 2026" / "14 Okt 2026": a date as people read it, in the language of the app.
String dialDateLabel(final DateTime d, {required final bool sw}) =>
    "${d.day} ${(sw ? _shortMonthsSw : _shortMonthsEn)[d.month - 1]} ${d.year}";

/// Lets a person choose a date on a round dial, like the face of a watch: the days of the month sit around the
/// circle (1 to 16 on the outer ring, 17 to 31 on the inner one), a hand points at the chosen day, and it can be
/// tapped or dragged to. The arrows (or the month and year names) change the month.
///
/// Returns the date (without a time), or null when it was cancelled. Days outside [firstDate]..[lastDate] are dimmed
/// and cannot be chosen.
Future<DateTime?> showDialDatePicker(
  final BuildContext context, {
  required final DateTime initialDate,
  required final DateTime firstDate,
  required final DateTime lastDate,
  required final bool sw,
}) =>
    showDialog<DateTime>(
      context: context,
      builder: (final BuildContext _) => DialDatePickerDialog(
          initialDate: initialDate,
          firstDate: firstDate,
          lastDate: lastDate,
          sw: sw),
    );

class DialDatePickerDialog extends StatefulWidget {
  const DialDatePickerDialog(
      {super.key,
      required this.initialDate,
      required this.firstDate,
      required this.lastDate,
      required this.sw});

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final bool sw;

  @override
  State<DialDatePickerDialog> createState() => _DialDatePickerDialogState();
}

class _DialDatePickerDialogState extends State<DialDatePickerDialog> {
  late final DateTime _first = DateUtils.dateOnly(widget.firstDate);
  late final DateTime _last = DateUtils.dateOnly(widget.lastDate);
  final DateTime _today = DateUtils.dateOnly(DateTime.now());

  late DateTime _selected = _clamp(DateUtils.dateOnly(widget.initialDate));
  late DateTime _month = DateTime(_selected.year, _selected.month);

  bool get _sw => widget.sw;

  DateTime _clamp(final DateTime d) =>
      d.isBefore(_first) ? _first : (d.isAfter(_last) ? _last : d);

  bool _enabled(final DateTime d) => !d.isBefore(_first) && !d.isAfter(_last);

  int get _daysInMonth => DateUtils.getDaysInMonth(_month.year, _month.month);

  bool _monthInRange(final int year, final int month) {
    final DateTime m = DateTime(year, month);
    return !m.isBefore(DateTime(_first.year, _first.month)) &&
        !m.isAfter(DateTime(_last.year, _last.month));
  }

  /// Show another month (the nearest allowed one when that one is outside the dates on offer), keeping the chosen day
  /// number where the month has it.
  void _goTo(final int year, final int month) {
    DateTime m = DateTime(year, month);
    final DateTime lowest = DateTime(_first.year, _first.month);
    final DateTime highest = DateTime(_last.year, _last.month);
    if (m.isBefore(lowest)) m = lowest;
    if (m.isAfter(highest)) m = highest;
    final int day =
        math.min(_selected.day, DateUtils.getDaysInMonth(m.year, m.month));
    setState(() {
      _month = m;
      _selected = _clamp(DateTime(m.year, m.month, day));
    });
  }

  void _step(final int months) {
    final DateTime m = DateTime(_month.year, _month.month + months);
    _goTo(m.year, m.month);
  }

  void _pick(final int? day) {
    if (day == null || day < 1 || day > _daysInMonth) return;
    final DateTime d = DateTime(_month.year, _month.month, day);
    if (!_enabled(d)) return;
    setState(() => _selected = d);
  }

  @override
  Widget build(final BuildContext context) {
    final Color accent = Theme.of(context).colorScheme.primary;
    final List<String> months = _sw ? _monthsSw : _monthsEn;
    final DateTime previous = DateTime(_month.year, _month.month - 1);
    final DateTime next = DateTime(_month.year, _month.month + 1);

    return Dialog(
      backgroundColor: ThemeConstants.primaryBlue,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(_sw ? "Chagua tarehe" : "Select a date",
                  style: const TextStyle(color: Colors.white60, fontSize: 13)),
              const SizedBox(height: 4),
              Text(
                "${(_sw ? _weekdaysSw : _weekdaysEn)[_selected.weekday - 1]}, ${dialDateLabel(_selected, sw: _sw)}",
                key: const ValueKey<String>("dial_selected"),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  IconButton(
                    key: const ValueKey<String>("dial_prev_month"),
                    tooltip: _sw ? "Mwezi uliopita" : "Previous month",
                    onPressed: _monthInRange(previous.year, previous.month)
                        ? () => _step(-1)
                        : null,
                    icon: const Icon(Icons.chevron_left),
                    color: Colors.white,
                  ),
                  Expanded(
                    // scales down instead of overflowing on a narrow screen or with large text
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          PopupMenuButton<int>(
                            key: const ValueKey<String>("dial_month_menu"),
                            tooltip: _sw ? "Chagua mwezi" : "Choose the month",
                            onSelected: (final int m) => _goTo(_month.year, m),
                            itemBuilder: (final BuildContext _) =>
                                <PopupMenuEntry<int>>[
                              for (int m = 1; m <= 12; m++)
                                PopupMenuItem<int>(
                                  key: ValueKey<String>("dial_month_$m"),
                                  value: m,
                                  enabled: _monthInRange(_month.year, m),
                                  child: Text(months[m - 1]),
                                ),
                            ],
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Text(months[_month.month - 1],
                                      key: const ValueKey<String>("dial_month"),
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700)),
                                  const Icon(Icons.arrow_drop_down,
                                      color: Colors.white54),
                                ],
                              ),
                            ),
                          ),
                          PopupMenuButton<int>(
                            key: const ValueKey<String>("dial_year_menu"),
                            tooltip: _sw ? "Chagua mwaka" : "Choose the year",
                            onSelected: (final int y) => _goTo(y, _month.month),
                            itemBuilder: (final BuildContext _) =>
                                <PopupMenuEntry<int>>[
                              for (int y = _first.year; y <= _last.year; y++)
                                PopupMenuItem<int>(
                                    key: ValueKey<String>("dial_year_$y"),
                                    value: y,
                                    child: Text("$y")),
                            ],
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Text("${_month.year}",
                                      key: const ValueKey<String>("dial_year"),
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700)),
                                  const Icon(Icons.arrow_drop_down,
                                      color: Colors.white54),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey<String>("dial_next_month"),
                    tooltip: _sw ? "Mwezi ujao" : "Next month",
                    onPressed: _monthInRange(next.year, next.month)
                        ? () => _step(1)
                        : null,
                    icon: const Icon(Icons.chevron_right),
                    color: Colors.white,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _dial(accent),
              const SizedBox(height: 6),
              // a Wrap: with large text the two buttons go on two lines instead of overflowing
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  children: <Widget>[
                    TextButton(
                        key: const ValueKey<String>("dial_cancel"),
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(_sw ? "Ghairi" : "Cancel")),
                    FilledButton(
                        key: const ValueKey<String>("dial_ok"),
                        onPressed: () => Navigator.of(context).pop(_selected),
                        child: Text(_sw ? "Chagua" : "Select")),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The face of the watch: the days around the circle, the hand to the chosen one.
  Widget _dial(final Color accent) {
    return LayoutBuilder(
      builder: (final BuildContext context, final BoxConstraints box) {
        final double size = math.min(box.maxWidth, 300);
        return Center(
          child: SizedBox(
            key: const ValueKey<String>("dial_face"),
            width: size,
            height: size,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (final TapUpDetails d) =>
                  _pick(_Face.dayAt(d.localPosition, size)),
              onPanDown: (final DragDownDetails d) =>
                  _pick(_Face.dayAt(d.localPosition, size)),
              onPanUpdate: (final DragUpdateDetails d) =>
                  _pick(_Face.dayAt(d.localPosition, size)),
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                      child: CustomPaint(
                          painter: _FacePainter(
                              selected: _selected.day,
                              size: size,
                              accent: accent))),
                  for (int day = 1; day <= _daysInMonth; day++)
                    _number(day, size, accent),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _number(final int day, final double size, final Color accent) {
    final DateTime date = DateTime(_month.year, _month.month, day);
    final bool selected = date == _selected;
    final bool enabled = _enabled(date);
    final bool today = date == _today;
    final Offset at = _Face.position(day, size);

    return Positioned(
      left: at.dx - 17,
      top: at.dy - 17,
      width: 34,
      height: 34,
      child: Semantics(
        label: "$day",
        button: true,
        selected: selected,
        enabled: enabled,
        onTap: () => _pick(day),
        child: ExcludeSemantics(
          child: IgnorePointer(
            child: Container(
              key: ValueKey<String>("dial_day_$day"),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: today && !selected
                    ? Border.all(color: accent, width: 1.5)
                    : null,
              ),
              child: Text(
                "$day",
                style: TextStyle(
                  color: !enabled
                      ? Colors.white24
                      : (selected ? Colors.white : Colors.white70),
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Where each day sits on the face, and which day a touch means. Days 1 to 16 are on the outer ring and 17 to 31 on the
/// inner one, so a day is always in the same place whatever the month.
class _Face {
  static const int _outerSlots = 16;
  static const int _innerSlots = 15;

  static double _outerRadius(final double size) => size / 2 - 26;

  static double _innerRadius(final double size) => _outerRadius(size) * 0.6;

  static Offset position(final int day, final double size) {
    final bool outer = day <= _outerSlots;
    final int slots = outer ? _outerSlots : _innerSlots;
    final int k = outer ? day - 1 : day - _outerSlots - 1;
    final double angle = -math.pi / 2 + 2 * math.pi * k / slots;
    final double radius = outer ? _outerRadius(size) : _innerRadius(size);
    return Offset(size / 2 + radius * math.cos(angle),
        size / 2 + radius * math.sin(angle));
  }

  /// The day a touch at [p] means, or null near the centre or outside the face.
  static int? dayAt(final Offset p, final double size) {
    final Offset d = p - Offset(size / 2, size / 2);
    final double r = d.distance;
    if (r < _innerRadius(size) * 0.35 || r > size / 2) return null;

    final bool outer = r > (_outerRadius(size) + _innerRadius(size)) / 2;
    final int slots = outer ? _outerSlots : _innerSlots;
    double a = math.atan2(d.dy, d.dx) + math.pi / 2;
    if (a < 0) a += 2 * math.pi;
    final int k = (a / (2 * math.pi / slots)).round() % slots;
    return outer ? k + 1 : k + _outerSlots + 1;
  }
}

class _FacePainter extends CustomPainter {
  const _FacePainter(
      {required this.selected, required this.size, required this.accent});

  final int selected;
  final double size;
  final Color accent;

  @override
  void paint(final Canvas canvas, final Size _) {
    final Offset c = Offset(size / 2, size / 2);
    final Offset end = _Face.position(selected, size);

    canvas.drawCircle(
        c, size / 2, Paint()..color = Colors.white.withValues(alpha: 0.06));
    canvas.drawCircle(
      c,
      size / 2 - 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.14),
    );
    canvas.drawLine(
      c,
      end,
      Paint()
        ..color = accent
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(c, 4, Paint()..color = accent);
    canvas.drawCircle(end, 17, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(final _FacePainter old) =>
      old.selected != selected || old.size != size || old.accent != accent;
}
