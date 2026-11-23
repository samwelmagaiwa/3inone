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
    // Inside GlowSections the frame belongs to the whole stack: this part is only its rows.
    if (GlowSections.joined(context)) return _rows(context);
    return DecoratedBox(
      decoration: joinedCardDecoration(),
      child: DecoratedBox(
        decoration: joinedCardBorder(),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          // A transparent Material, so a ListTile or button in a row paints its touch ripple on the card instead of being hidden by it.
          child: Material(type: MaterialType.transparency, child: _rows(context)),
        ),
      ),
    );
  }

  Widget _rows(final BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int i = 0; i < children.length; i++) ...<Widget>[
            if (i > 0) SectionGlowDivider(key: dividerKey == null ? null : ValueKey<String>('${dividerKey}_$i'), lift: false),
            Padding(padding: padding, child: children[i]),
          ],
        ],
      );
}

/// Several [GlowCard]s (or [GlowListCard]s) as ONE card: one frame around all of them, no gap between, and the glowing line and each part's gold
/// title showing where one ends and the next begins. A card inside it drops its own frame and the air below it.
class GlowSections extends StatelessWidget {
  const GlowSections({super.key, required this.children, this.bottom = 10});

  final List<Widget> children;

  /// Air below the whole stack.
  final double bottom;

  /// Is this card inside a [GlowSections]?
  static bool joined(final BuildContext context) => context.dependOnInheritedWidgetOfExactType<_JoinedScope>() != null;

  @override
  Widget build(final BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: DecoratedBox(
          decoration: joinedCardDecoration(),
          child: DecoratedBox(
            decoration: joinedCardBorder(),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Material(
                type: MaterialType.transparency,
                child: _JoinedScope(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      for (int i = 0; i < children.length; i++) ...<Widget>[
                        if (i > 0) const Padding(padding: EdgeInsets.symmetric(vertical: 2), child: SectionGlowDivider(lift: false)),
                        children[i],
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class _JoinedScope extends InheritedWidget {
  const _JoinedScope({required super.child});

  @override
  bool updateShouldNotify(final _JoinedScope oldWidget) => false;
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
        padding: EdgeInsets.only(bottom: GlowSections.joined(context) ? 0 : bottom),
        child: GlowListCard(
          dividerKey: dividerKey,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          children: <Widget>[if (title != null) GlowTitle(title!), ...glowRows(children)],
        ),
      );
}

/// Marks a widget that is one section card (it builds a [GlowCard] inside), so [joinGlowCards] treats it like one.
mixin GlowSectionWidget {}

/// Turns the runs of section cards in a list of children into ONE joined card each ([GlowSections]): the cards, and the plain spacers between
/// them, become parts of a single frame told apart by the glowing line and each part's gold title. Anything else (a button, a heading, a gap
/// that is not between two cards) stays where it is and ends the run. A single card on its own is left as it is.
List<Widget> joinGlowCards(final List<Widget> children) {
  bool isCard(final Widget w) => w is GlowCard || w is GlowListCard || w is GlowSectionWidget;
  bool isSpacer(final Widget w) => w is SizedBox && w.child == null && w.width == null && (w.height ?? 0) <= 24;
  final List<Widget> out = <Widget>[];
  final List<Widget> run = <Widget>[];
  void flush() {
    if (run.length >= 2) {
      out.add(GlowSections(children: List<Widget>.of(run)));
    } else {
      out.addAll(run);
    }
    run.clear();
  }

  for (int i = 0; i < children.length; i++) {
    final Widget w = children[i];
    if (isCard(w)) {
      run.add(w);
      continue;
    }
    if (run.isNotEmpty && isSpacer(w)) {
      int j = i;
      while (j < children.length && isSpacer(children[j])) {
        j++;
      }
      if (j < children.length && isCard(children[j])) {
        i = j - 1;
        continue;
      }
    }
    flush();
    out.add(w);
  }
  flush();
  return out;
}
