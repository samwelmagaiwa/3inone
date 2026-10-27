import '../services/localization_service.dart';

/// A name written "Kiswahili / English" shows the half of the language the person uses; a name without that shape (one the user typed
/// in a single language) shows as it is. The ready-made salon categories are named this way, and so can any a user adds.
String localizedName(final String name, {final bool? sw}) {
  final List<String> parts = name.split(' / ');
  if (parts.length != 2) return name;
  final String first = parts[0].trim();
  final String second = parts[1].trim();
  if (first.isEmpty || second.isEmpty) return name;

  return (sw ?? LocalizationService.instance.isSwahili) ? first : second;
}
