import 'package:flutter/material.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';

/// Pages for a long list: "21-40 of 120", how many to show on a page, and the pages themselves (first, previous, numbers with "…" where
/// some are left out, next, last). Page numbers are shown from 1; [page] counts from 0.
class PagerBar extends StatelessWidget {
  const PagerBar({
    required this.total,
    required this.page,
    required this.pageSize,
    required this.onPage,
    required this.onPageSize,
    super.key,
    this.sizes = const <int>[10, 20, 50, 100],
  });

  final int total;
  final int page;
  final int pageSize;
  final ValueChanged<int> onPage;
  final ValueChanged<int> onPageSize;
  final List<int> sizes;

  int get pages => total == 0 ? 1 : (total / pageSize).ceil();

  /// The page numbers to show (0-based), the first and last always, two either side of the current one, and -1 where some are left out.
  List<int> window() {
    final int last = pages - 1;
    final Set<int> keep = <int>{0, last, for (int i = page - 1; i <= page + 1; i++) if (i >= 0 && i <= last) i};
    final List<int> sorted = keep.toList()..sort();
    final List<int> out = <int>[];
    for (int i = 0; i < sorted.length; i++) {
      if (i > 0 && sorted[i] - sorted[i - 1] > 1) {
        // one missing page is shown rather than "…"
        if (sorted[i] - sorted[i - 1] == 2) {
          out.add(sorted[i] - 1);
        } else {
          out.add(-1);
        }
      }
      out.add(sorted[i]);
    }
    return out;
  }

  @override
  Widget build(final BuildContext context) {
    final LocalizationService loc = LocalizationService.instance;
    final int from = total == 0 ? 0 : page * pageSize + 1;
    final int to = ((page + 1) * pageSize) > total ? total : (page + 1) * pageSize;
    final int last = pages - 1;

    Widget arrow(final String key, final IconData icon, final String tip, final int? target) => IconButton(
          key: Key(key),
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          onPressed: target == null ? null : () => onPage(target),
          icon: Icon(icon, color: target == null ? Colors.white24 : Colors.white70),
        );

    Widget number(final int p) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: InkWell(
            key: Key('pager_page_$p'),
            borderRadius: BorderRadius.circular(10),
            onTap: p == page ? null : () => onPage(p),
            child: Container(
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: p == page ? ThemeConstants.invAccent.withValues(alpha: 0.28) : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: p == page ? ThemeConstants.invAccent : Colors.white24),
              ),
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: Text('${p + 1}', style: TextStyle(color: p == page ? Colors.white : Colors.white70, fontWeight: p == page ? FontWeight.w800 : FontWeight.w500, fontSize: 13)),
              ),
            ),
          ),
        );

    return Column(
      key: const Key('pager_bar'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Flexible(
              child: Text(
                loc.translateWith('pager_showing', <Object?>[from, to, total]),
                key: const Key('pager_showing'),
                style: ThemeConstants.captionStyle,
              ),
            ),
            Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
              Text(loc.translate('pager_per_page'), style: ThemeConstants.captionStyle),
              const SizedBox(width: 6),
              DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  key: const Key('pager_size'),
                  value: sizes.contains(pageSize) ? pageSize : null,
                  dropdownColor: ThemeConstants.primaryBlue,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  iconEnabledColor: Colors.white70,
                  items: <DropdownMenuItem<int>>[for (final int s in sizes) DropdownMenuItem<int>(value: s, child: Text('$s'))],
                  onChanged: (final int? v) {
                    if (v != null) onPageSize(v);
                  },
                ),
              ),
            ]),
          ],
        ),
        const SizedBox(height: 6),
        // ONE row, side by side: first, previous, the numbers (only as many as the data has pages, "…" where some are left out), next, last.
        // On a narrow phone the whole row is scaled down to fit; it never wraps.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            key: const Key('pager_row'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              arrow('pager_first', Icons.first_page_rounded, loc.translate('pager_first'), page > 0 ? 0 : null),
              arrow('pager_prev', Icons.chevron_left_rounded, loc.translate('pager_prev'), page > 0 ? page - 1 : null),
              for (final int p in window())
                if (p == -1) const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text('…', style: TextStyle(color: Colors.white54))) else number(p),
              arrow('pager_next', Icons.chevron_right_rounded, loc.translate('pager_next'), page < last ? page + 1 : null),
              arrow('pager_last', Icons.last_page_rounded, loc.translate('pager_last'), page < last ? last : null),
            ],
          ),
        ),
        Center(
          child: Text(loc.translateWith('pager_page_of', <Object?>[page + 1, pages]), key: const Key('pager_page_of'), style: ThemeConstants.captionStyle),
        ),
      ],
    );
  }
}
