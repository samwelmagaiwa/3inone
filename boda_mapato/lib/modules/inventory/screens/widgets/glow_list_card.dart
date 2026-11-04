import 'package:flutter/material.dart';

import 'joined_sections.dart';

/// A list of rows in ONE card, each row divided from the next by the glowing line of the inventory dashboard: a tight, easy-to-scan
/// data list with no gaps between the rows. The card keeps the colour of the screen; only the lines glow.
class GlowListCard extends StatelessWidget {
  const GlowListCard({super.key, required this.children, this.dividerKey, this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 10)});

  final List<Widget> children;

  /// Names the dividers (so a test can count them): each gets this name and its number.
  final String? dividerKey;

  /// Around each row.
  final EdgeInsets padding;

  @override
  Widget build(final BuildContext context) {
    return DecoratedBox(
      decoration: joinedCardDecoration(),
      child: DecoratedBox(
        decoration: joinedCardBorder(),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          // A transparent Material, so a ListTile or button in a row paints its touch ripple on the card instead of being hidden by it.
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (int i = 0; i < children.length; i++) ...<Widget>[
                  if (i > 0) SectionGlowDivider(key: dividerKey == null ? null : ValueKey<String>('${dividerKey}_$i'), lift: false),
                  Padding(padding: padding, child: children[i]),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The rows of a card as [GlowListCard] wants them: the spacers and plain dividers that separated lines in the older cards are left out, because
/// the glowing line now does that.
List<Widget> glowRows(final List<Widget> children) => <Widget>[
      for (final Widget w in children)
        if (w is! Divider && !(w is SizedBox && w.child == null)) w,
    ];

/// The title of a group of lines, centred, in the same gold as the other pages' section titles.
class GlowTitle extends StatelessWidget {
  const GlowTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(final BuildContext context) => Center(child: Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFFFFD166))));
}

/// A card of lines (a title and what belongs to it) divided by the glowing line, with a little air below, for the pages that used to stack plain
/// cards. [children] may still hold the old spacers and dividers: they are dropped.
class GlowCard extends StatelessWidget {
  const GlowCard({super.key, required this.children, this.title, this.dividerKey, this.bottom = 10});

  final List<Widget> children;

  /// Shown first, centred in gold, when given.
  final String? title;
  final String? dividerKey;
  final double bottom;

  @override
  Widget build(final BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: GlowListCard(
          dividerKey: dividerKey,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          children: <Widget>[if (title != null) GlowTitle(title!), ...glowRows(children)],
        ),
      );
}
