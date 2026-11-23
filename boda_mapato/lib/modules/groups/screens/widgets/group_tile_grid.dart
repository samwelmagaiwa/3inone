import 'package:flutter/material.dart';

import '../../../../constants/theme_constants.dart';
import '../../../inventory/screens/widgets/glow_list_card.dart';
import '../../../inventory/screens/widgets/joined_sections.dart';

/// One cell of a [GroupTileGrid]: either a button (an icon and its name, with a count badge when something waits) or, when [value] is given,
/// a figure (the icon, the value and what it counts).
class GroupGridTile {
  const GroupGridTile({required this.icon, required this.color, required this.label, this.value, this.badge = 0, this.badgeColor, this.onTap, this.tileKey});

  final IconData icon;
  final Color color;
  final String label;

  /// A figure to show (makes the cell a figure cell instead of a button cell).
  final String? value;

  /// A count shown on the icon (nothing when 0).
  final int badge;
  final Color? badgeColor;
  final VoidCallback? onTap;
  final Key? tileKey;
}

/// Tiles in ONE card, set out like the inventory dashboard: a thin vertical line between the tiles of a row and the glowing line between
/// the rows. The card keeps the dashboard's colours; only the lines tell the tiles apart. Inside a [GlowSections] stack it joins its
/// neighbours like any other section.
class GroupTileGrid extends StatelessWidget with GlowSectionWidget {
  const GroupTileGrid({required this.tiles, super.key, this.columns = 2, this.title, this.dividerKey, this.footer});

  final List<GroupGridTile> tiles;
  final int columns;

  /// Shown first, centred in gold, when given.
  final String? title;
  final String? dividerKey;

  /// Something under the tiles, after one more glowing line (a main button).
  final Widget? footer;

  Widget _cell(final GroupGridTile t) {
    final Widget content = t.value == null ? _button(t) : _figure(t);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(key: t.tileKey, onTap: t.onTap, child: content),
    );
  }

  Widget _icon(final GroupGridTile t, {required final double size, required final double pad}) => Stack(clipBehavior: Clip.none, children: <Widget>[
        Container(
          padding: EdgeInsets.all(pad),
          decoration: BoxDecoration(color: t.color.withValues(alpha: 0.16), shape: BoxShape.circle, border: Border.all(color: t.color.withValues(alpha: 0.45))),
          child: Icon(t.icon, color: t.color, size: size),
        ),
        if (t.badge > 0)
          Positioned(
            top: -4,
            right: -6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              constraints: const BoxConstraints(minWidth: 18),
              decoration: BoxDecoration(color: t.badgeColor ?? ThemeConstants.primaryOrange, borderRadius: BorderRadius.circular(10)),
              child: Text('${t.badge}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800)),
            ),
          ),
      ]);

  Widget _button(final GroupGridTile t) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: <Widget>[
          _icon(t, size: 22, pad: 11),
          const SizedBox(height: 7),
          Text(t.label, textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w600, height: 1.2)),
        ]),
      );

  Widget _figure(final GroupGridTile t) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(children: <Widget>[
          _icon(t, size: 18, pad: 7),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: <Widget>[
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(t.value!, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900))),
              Text(t.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w500)),
            ]),
          ),
        ]),
      );

  Widget _grid(final BuildContext context) {
    final List<Widget> rows = <Widget>[];
    for (int start = 0; start < tiles.length; start += columns) {
      final List<GroupGridTile> row = tiles.skip(start).take(columns).toList();
      if (rows.isNotEmpty) rows.add(SectionGlowDivider(key: dividerKey == null ? null : ValueKey<String>('${dividerKey}_${start ~/ columns}'), lift: false));
      rows.add(IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          for (int i = 0; i < columns; i++) ...<Widget>[
            if (i > 0) Container(width: 1, margin: const EdgeInsets.symmetric(vertical: 10), color: Colors.white.withValues(alpha: 0.15)),
            Expanded(child: i < row.length ? _cell(row[i]) : const SizedBox.shrink()),
          ],
        ]),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      if (title != null) ...<Widget>[
        Padding(padding: const EdgeInsets.only(top: 10, bottom: 4), child: GlowTitle(title!)),
        const SectionGlowDivider(lift: false),
      ],
      ...rows,
      if (footer != null) ...<Widget>[
        const SectionGlowDivider(lift: false),
        Padding(padding: const EdgeInsets.fromLTRB(14, 10, 14, 12), child: footer),
      ],
    ]);
  }

  @override
  Widget build(final BuildContext context) {
    // Inside a joined stack the frame belongs to the whole stack.
    if (GlowSections.joined(context)) return _grid(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: joinedCardDecoration(),
        child: DecoratedBox(
          decoration: joinedCardBorder(),
          child: ClipRRect(borderRadius: BorderRadius.circular(20), child: Material(type: MaterialType.transparency, child: _grid(context))),
        ),
      ),
    );
  }
}
