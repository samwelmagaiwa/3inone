import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../providers/inventory_provider.dart';

/// Is the screen being drawn part of a SALON (opened from the salon's home)? The salon shares its screens with
/// inventory, and says so through the inventory provider. Where there is no provider (some tests) it is not a salon.
bool isSalonMode(final BuildContext context, {final bool listen = true}) {
  try {
    return listen ? context.watch<InventoryProvider>().salonMode : context.read<InventoryProvider>().salonMode;
  } on ProviderNotFoundException {
    return false;
  }
}
