import 'package:flutter/material.dart';

import '../../../../constants/theme_constants.dart';

/// What the person is told, and must agree to, before this phone is registered for attendance. Nothing is collected before they agree.
/// Returns true only when they tapped "I agree".
Future<bool> askDeviceConsent(final BuildContext context, {required final bool sw}) async {
  final bool? agreed = await showDialog<bool>(
    context: context,
    builder: (final BuildContext ctx) => AlertDialog(
      key: const ValueKey<String>('device_consent'),
      title: Text(sw ? 'Sajili simu hii kwa mahudhurio' : 'Register this phone for attendance'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(sw ? 'Ili kuthibitisha kuwa ni wewe unayeanza kazi, mfumo utakusanya:' : 'To confirm it is you who starts work, the system will collect:', style: ThemeConstants.bodyStyle),
            const SizedBox(height: 8),
            _bullet(sw ? 'Jina na modeli ya simu, mfumo wa uendeshaji na toleo la app' : 'The phone name and model, its system and the app version'),
            _bullet(sw ? 'Kitambulisho cha simu hii kilichotengenezwa na app (si IMEI wala MAC)' : 'An identifier for this phone made by the app (not the IMEI or MAC address)'),
            _bullet(sw ? 'Anwani ya IP ya mtandao wako' : 'The network (IP) address you connect from'),
            _bullet(sw ? 'Eneo ulipo unapoanza au unapomaliza kazi' : 'Where you are when you start or finish work'),
            const SizedBox(height: 8),
            Text(
              sw
                  ? 'Hutumika kuthibitisha mahudhurio tu. Msimamizi wako anaiona, na simu nyingine ikitumika kwa akaunti yako atajulishwa. Faili, ujumbe na anwani zako hazisomwi.'
                  : 'It is used only to confirm attendance. Your administrator can see it, and is told if another phone is used on your account. Your files, messages and contacts are not read.',
              style: ThemeConstants.captionStyle,
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(key: const ValueKey<String>('consent_decline'), onPressed: () => Navigator.of(ctx).pop(false), child: Text(sw ? 'Sikubali' : 'Decline')),
        TextButton(key: const ValueKey<String>('consent_agree'), onPressed: () => Navigator.of(ctx).pop(true), child: Text(sw ? 'Nakubali' : 'I agree')),
      ],
    ),
  );

  return agreed == true;
}

Widget _bullet(final String line) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text('•  $line', style: ThemeConstants.captionStyle),
    );
