import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../services/reminder_voice.dart';
import '../../services/voice_settings.dart';

/// The sheet where the owner chooses the voice that reads the debts, and how fast: every voice the phone has for the language is listed and
/// can be listened to before it is kept. What is kept is used every time a reminder is read, and "automatic" goes back to the clearest voice
/// the phone has (Tanzania's Kiswahili first).
class VoicePickerSheet extends StatefulWidget {
  const VoicePickerSheet({super.key, required this.voice});

  final ReminderVoice voice;

  @override
  State<VoicePickerSheet> createState() => _VoicePickerSheetState();
}

class _VoicePickerSheetState extends State<VoicePickerSheet> {
  List<VoiceOption>? _options;
  String? _chosen;
  String _speed = 'normal';
  bool get _sw => LocalizationService.instance.isSwahili;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final List<VoiceOption> options = await widget.voice.voices(sw: _sw);
    final String? chosen = await VoiceSettings.voiceName(swahili: _sw);
    final String speed = await VoiceSettings.speed();
    if (!mounted) return;
    setState(() {
      _options = options;
      _chosen = options.any((VoiceOption o) => o.name == chosen) ? chosen : null;
      _speed = speed;
    });
  }

  /// Plays the sample sentence with the given choice, so it is heard before it is kept.
  Future<void> _hear({final String? name, final String? speed}) async {
    final double rate = VoiceSettings.speeds[speed ?? _speed]!;
    final bool ok = await widget.voice.preview(LocalizationService.instance.translate('voice_sample'), sw: _sw, voiceName: name ?? _chosen, rate: rate);
    if (!ok && mounted) ThemeConstants.showWarningSnackBar(context, LocalizationService.instance.translate('voice_missing'));
  }

  Future<void> _choose(final String? name) async {
    setState(() => _chosen = name);
    await VoiceSettings.setVoiceName(name, swahili: _sw);
    await _hear(name: name);
  }

  Future<void> _setSpeed(final String speed) async {
    setState(() => _speed = speed);
    await VoiceSettings.setSpeed(speed);
    await _hear(speed: speed);
  }

  /// "Kiswahili (Tanzania) 2", or "English (US) 1": a name a person can read, in the order of the list.
  String _label(final VoiceOption o, final int number) {
    final String l = o.locale.toLowerCase().replaceAll('_', '-');
    final String place = switch (l) {
      'sw-tz' => 'Tanzania',
      'sw-ke' => 'Kenya',
      'en-us' => 'US',
      'en-gb' => 'UK',
      _ => o.locale,
    };
    final String language = l.startsWith('sw') ? 'Kiswahili' : 'English';

    return '$language ($place) $number';
  }

  @override
  Widget build(final BuildContext context) {
    final LocalizationService loc = LocalizationService.instance;
    final List<VoiceOption>? options = _options;

    return SafeArea(
      child: Container(
        decoration: BoxDecoration(color: ThemeConstants.primaryBlue, borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)), border: Border.all(color: Colors.white24)),
        padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 16.h),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(child: Container(width: 40.w, height: 4.h, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4.r)))),
              SizedBox(height: 12.h),
              Text(loc.translate('voice_pick_title'), style: TextStyle(color: Colors.white, fontSize: 18.sp, fontWeight: FontWeight.w800)),
              SizedBox(height: 4.h),
              Text(loc.translate('voice_pick_hint'), style: ThemeConstants.captionStyle),
              SizedBox(height: 14.h),
              Text(loc.translate('voice_speed'), style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700)),
              SizedBox(height: 6.h),
              Wrap(
                spacing: 8.w,
                children: <Widget>[
                  for (final String s in VoiceSettings.speeds.keys)
                    ChoiceChip(key: ValueKey<String>('voice_speed_$s'), label: Text(loc.translate('voice_speed_$s')), selected: _speed == s, onSelected: (_) => _setSpeed(s)),
                ],
              ),
              SizedBox(height: 14.h),
              Text(loc.translate('voice_list'), style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700)),
              SizedBox(height: 4.h),
              if (options == null)
                Padding(padding: EdgeInsets.all(16.w), child: const Center(child: CircularProgressIndicator()))
              else ...<Widget>[
                _row(key: const ValueKey<String>('voice_auto'), title: loc.translate('voice_auto_best'), subtitle: loc.translate('voice_auto_best_hint'), selected: _chosen == null, onTap: () => _choose(null), onPlay: () => _hear(name: null)),
                for (int i = 0; i < options.length; i++)
                  _row(
                    key: ValueKey<String>('voice_${options[i].name}'),
                    title: _label(options[i], i + 1),
                    subtitle: '${options[i].network ? '${loc.translate('voice_clear')} · ' : ''}${options[i].name}',
                    selected: _chosen == options[i].name,
                    onTap: () => _choose(options[i].name),
                    onPlay: () => _hear(name: options[i].name),
                  ),
                if (options.isEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: 8.h),
                    child: Text(loc.translate('voice_none_installed'), key: const ValueKey<String>('voice_none'), style: ThemeConstants.captionStyle.copyWith(color: ThemeConstants.warningAmber)),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _row({required final Key key, required final String title, required final String subtitle, required final bool selected, required final VoidCallback onTap, required final VoidCallback onPlay}) {
    return InkWell(
      key: key,
      borderRadius: BorderRadius.circular(12.r),
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 6.h),
        child: Row(
          children: <Widget>[
            Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? ThemeConstants.successGreen : Colors.white54, size: 22.sp),
            SizedBox(width: 10.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700)),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: ThemeConstants.captionStyle),
                ],
              ),
            ),
            IconButton(tooltip: LocalizationService.instance.translate('voice_listen'), icon: Icon(Icons.play_circle_fill_rounded, color: const Color(0xFF3B82F6), size: 28.sp), onPressed: onPlay),
          ],
        ),
      ),
    );
  }
}
