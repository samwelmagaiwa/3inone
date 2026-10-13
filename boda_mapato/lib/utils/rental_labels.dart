import '../services/localization_service.dart';

/// The server (and the app's own dropdowns) keep values like `rental_compound`, `quarterly` or
/// `under_maintenance`. This is the name a person reads, in the language chosen in the app.
/// A value this app does not know is shown tidied up ("some_value" becomes "Some value").
String rentalValueLabel(final String? stored) {
  final String value = (stored ?? '').trim();
  if (value.isEmpty) {
    return '';
  }
  final LocalizationService loc = LocalizationService.instance;
  switch (value.toLowerCase()) {
    case 'monthly':
      return loc.translate('cycle_monthly');
    case 'quarterly':
      return loc.translate('cycle_quarterly');
    case 'yearly':
      return loc.translate('cycle_yearly');
    case 'active':
      return loc.translate('active');
    case 'inactive':
      return loc.translate('inactive_2');
    case 'under_maintenance':
    case 'maintenance':
      return loc.translate('maintenance');
    case 'vacant':
      return loc.translate('house_vacant');
    case 'occupied':
      return loc.translate('house_occupied');
    case 'reserved':
      return loc.translate('house_reserved');
    case 'apartment':
    case 'rental_compound':
    case 'standalone_house':
    case 'hostel':
    case 'commercial_building':
    case 'mixed_use':
    case 'office_space':
    case 'shop_units':
    case 'room':
    case 'studio':
    case 'commercial':
    case 'bedsitter':
    case 'one_bedroom':
      return loc.translate('ptype_${value.toLowerCase()}');
    default:
      final String spaced = value.replaceAll('_', ' ');
      return spaced[0].toUpperCase() + spaced.substring(1);
  }
}
