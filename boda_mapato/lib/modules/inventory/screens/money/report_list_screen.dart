import 'package:flutter/material.dart';

import '../widgets/joined_sections.dart';
import 'money_style.dart';

/// One line of a [ReportListScreen]: a name, a small note under it, an amount.
class ReportListRow {
  const ReportListRow({required this.label, required this.value, this.sub, this.onTap});

  final String label;
  final String value;
  final String? sub;
  final VoidCallback? onTap;
}

/// The whole of a list the monthly report cuts short (every sleeping product, everyone who owes): a line on what the list adds up to,
/// then every row, divided by the glowing line.
class ReportListScreen extends StatelessWidget {
  const ReportListScreen({super.key, required this.title, required this.summary, required this.rows});

  final String title;
  final String summary;
  final List<ReportListRow> rows;

  @override
  Widget build(final BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        key: const Key('report_full_list'),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
        children: <Widget>[
          DecoratedBox(
            decoration: joinedCardDecoration(),
            child: DecoratedBox(
              decoration: joinedCardBorder(),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                  Padding(padding: const EdgeInsets.all(14), child: Text(summary, key: const Key('report_list_summary'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
                  for (int i = 0; i < rows.length; i++) ...<Widget>[
                    const SectionGlowDivider(lift: false),
                    _row(rows[i], i),
                  ],
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(final ReportListRow r, final int i) {
    final Widget content = Padding(
      key: Key('report_row_$i'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(children: <Widget>[
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(r.label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            if (r.sub != null) Text(r.sub!, style: kMoneyCaption),
          ]),
        ),
        const SizedBox(width: 8),
        Text(r.value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        if (r.onTap != null) const Icon(Icons.chevron_right, size: 18, color: Colors.white38),
      ]),
    );

    return r.onTap == null ? content : InkWell(onTap: r.onTap, child: content);
  }
}
