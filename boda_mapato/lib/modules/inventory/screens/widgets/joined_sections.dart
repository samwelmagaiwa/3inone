import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../constants/theme_constants.dart';

/// The glowing line between two joined sections: the same one the inventory dashboard draws between its
/// valuation, products and chart sections.
class SectionGlowDivider extends StatelessWidget {
  const SectionGlowDivider({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Container(
          height: 2.5,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: <Color>[
                Colors.transparent,
                Colors.cyanAccent.withOpacity(0.5),
                Colors.white.withOpacity(0.7),
                Colors.cyanAccent.withOpacity(0.5),
                Colors.transparent,
              ],
            ),
            borderRadius: BorderRadius.circular(2),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.cyanAccent.withOpacity(0.6),
                blurRadius: 12,
                spreadRadius: 2,
              ),
              BoxShadow(
                color: ThemeConstants.primaryBlue,
                blurRadius: 20,
                spreadRadius: 8,
                offset: const Offset(0, 6),
              ),
            ],
          ),
        ),
      );
}

/// The same glowing line stood upright, between two fields side by side. Its glow is only the cyan one: the dark
/// lift the horizontal line has would lie over the fields on either side.
class SectionGlowVerticalDivider extends StatelessWidget {
  const SectionGlowVerticalDivider({super.key});

  /// How wide the line is; the glow spreads beyond it.
  static const double lineWidth = 2.5;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Colors.transparent,
              Colors.cyanAccent.withOpacity(0.5),
              Colors.white.withOpacity(0.7),
              Colors.cyanAccent.withOpacity(0.5),
              Colors.transparent,
            ],
          ),
          borderRadius: BorderRadius.circular(2),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.cyanAccent.withOpacity(0.45),
              blurRadius: 8,
              spreadRadius: 1,
            ),
          ],
        ),
      );
}

/// A section that goes edge to edge inside a [JoinedSectionsCard] (a tappable row whose ripple should reach the
/// card's sides); the card adds no padding around it.
class FlushSection extends StatelessWidget {
  const FlushSection({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// The fill and glow of a joined card: the glass fill of the inventory dashboard's joined sections with its
/// cyan top-edge glow and the dark lift underneath. Pair it with [joinedCardBorder].
BoxDecoration joinedCardDecoration() => BoxDecoration(
      color: ThemeConstants.cardColor,
      borderRadius: BorderRadius.circular(20),
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: Colors.cyanAccent.withOpacity(0.35),
          blurRadius: 14,
          offset: const Offset(0, -1),
        ),
        BoxShadow(
          color: Colors.cyanAccent.withOpacity(0.20),
          blurRadius: 20,
          spreadRadius: 2,
        ),
        BoxShadow(
          color: ThemeConstants.primaryBlue,
          blurRadius: 28,
          spreadRadius: 8,
          offset: const Offset(0, 18),
        ),
      ],
    );

/// The cyan edge of a joined card.
BoxDecoration joinedCardBorder() => BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.cyanAccent.withOpacity(0.42), width: 1.8),
    );

/// Sections joined into ONE card and separated by [SectionGlowDivider]s, with no gaps between them: the look of
/// the inventory dashboard's joined sections (glass fill, cyan border and glow).
class JoinedSectionsCard extends StatelessWidget {
  const JoinedSectionsCard({super.key, required this.sections});

  final List<Widget> sections;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: joinedCardDecoration(),
      child: DecoratedBox(
        decoration: joinedCardBorder(),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (int i = 0; i < sections.length; i++) ...<Widget>[
                if (i > 0) const SectionGlowDivider(),
                if (sections[i] is FlushSection)
                  sections[i]
                else
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
                    child: sections[i],
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
