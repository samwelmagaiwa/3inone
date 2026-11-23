import 'package:flutter/material.dart';

import '../../../../constants/theme_constants.dart';

/// A member's profile picture in a frame made for it: a ring in the colour of their status with a soft glow, a dark gap, then the photo
/// (or their initials when there is none yet). A small camera badge shows to whoever may change it. Tapping opens what the screen decides.
class MemberAvatar extends StatelessWidget {
  const MemberAvatar({required this.name, required this.ringColor, super.key, this.photoUrl, this.size = 84, this.onTap, this.editable = false});

  final String name;
  final String? photoUrl;
  final Color ringColor;
  final double size;
  final VoidCallback? onTap;

  /// Shows the camera badge (the person may add or change the photo).
  final bool editable;

  /// "AJ" from "Asha Mussa Juma": the first letter of the first and the last name.
  static String initials(final String name) {
    final List<String> parts = name.trim().split(RegExp(r'\s+')).where((final String p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(final BuildContext context) {
    final double inner = size - 14;
    final Widget fallback = Container(
      width: inner,
      height: inner,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: <Color>[ThemeConstants.invAccent.withValues(alpha: 0.55), ThemeConstants.primaryBlue]),
      ),
      child: Text(initials(name), key: const Key('grp_member_initials'), style: TextStyle(color: Colors.white, fontSize: size * 0.32, fontWeight: FontWeight.w800, letterSpacing: 1)),
    );
    return Semantics(
      button: onTap != null,
      label: name,
      child: GestureDetector(
        key: const Key('grp_member_avatar'),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(clipBehavior: Clip.none, children: <Widget>[
            // The ring, with its glow.
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(colors: <Color>[ringColor, Colors.white.withValues(alpha: 0.85), ringColor]),
                boxShadow: <BoxShadow>[BoxShadow(color: ringColor.withValues(alpha: 0.4), blurRadius: 14, spreadRadius: 1)],
              ),
            ),
            // A dark gap between the ring and the picture.
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle, color: ThemeConstants.primaryBlue)),
              ),
            ),
            Center(
              child: ClipOval(
                child: photoUrl == null
                    ? fallback
                    : Image.network(photoUrl!, key: const Key('grp_member_photo'), width: inner, height: inner, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback),
              ),
            ),
            if (editable)
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  key: const Key('grp_member_avatar_edit'),
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(shape: BoxShape.circle, color: ThemeConstants.primaryOrange, border: Border.all(color: ThemeConstants.primaryBlue, width: 2)),
                  child: const Icon(Icons.photo_camera_rounded, color: Colors.white, size: 14),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
