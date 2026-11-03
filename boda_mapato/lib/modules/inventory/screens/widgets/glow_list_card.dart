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
    );
  }
}
