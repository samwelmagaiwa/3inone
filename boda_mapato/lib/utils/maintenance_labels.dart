import '../services/localization_service.dart';

/// A maintenance request keeps the category exactly as it was picked ("Mabomba/Plumbing"), so what is stored
/// never changes with the language. This is the name a person reads, in the language chosen in the app.
/// A category this app does not know is shown as it was stored.
String maintenanceCategoryLabel(final String? stored) {
  final String category = (stored ?? '').trim();
  final LocalizationService loc = LocalizationService.instance;
  switch (category) {
    case '':
    case 'General':
      return loc.translate('category_general');
    case 'Mengineyo':
      return loc.translate('category_other');
    case 'Mabomba/Plumbing':
      return loc.translate('category_plumbing');
    case 'Umeme':
      return loc.translate('category_electrical');
    case 'Ujenzi/Structural':
      return loc.translate('category_structural');
    case 'Vifaa vya Ndani':
      return loc.translate('category_interior');
    case 'Paka Rangi':
      return loc.translate('category_painting');
    case 'Usalama':
      return loc.translate('category_security');
    default:
      return category;
  }
}
