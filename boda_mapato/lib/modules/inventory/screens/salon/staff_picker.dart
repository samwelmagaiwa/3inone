import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../models/inv_sale.dart';
import '../../providers/inventory_provider.dart';
import '../widgets/inventory_widgets.dart';

/// Say who served the client for this line of the sale. The list is the salon's own active people (the owner too);
/// "Nobody" leaves it unnamed (it then shows up as "No stylist named" in the results).
Future<void> pickStylist(BuildContext context, InvSaleItem item) {
  final InventoryProvider inv = context.read<InventoryProvider>();
  // refreshed each time it opens: someone may have been added since
  inv.fetchSalonStaff();

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext _) => ChangeNotifierProvider<InventoryProvider>.value(value: inv, child: _StaffSheet(item: item)),
  );
}

class _StaffSheet extends StatelessWidget {
  const _StaffSheet({required this.item});

  final InvSaleItem item;

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final InventoryProvider inv = context.watch<InventoryProvider>();
    final List<Map<String, String>> staff = inv.salonStaff;

    void choose(String? id, String? name) {
      inv.setCartStaff(item, id, name);
      Navigator.pop(context);
    }

    return InvSheetShell(
      title: sw ? 'Nani amemhudumia mteja?' : 'Who served the client?',
      // A Material INSIDE the coloured sheet: the tiles draw their touch ripple on the nearest one, and a coloured box
      // between them and it would hide the ripple (and Flutter shows a red error for that in debug builds).
      children: <Widget>[
        Material(
          type: MaterialType.transparency,
          child: Column(children: <Widget>[
        if (staff.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 12.h),
            child: Text(
              sw ? 'Hakuna wafanyakazi bado. Ongeza wahudumu kwenye Mipangilio > Watumiaji.' : 'No staff yet. Add stylists under Settings > Users.',
              key: const ValueKey<String>('staff_picker_empty'),
              style: ThemeConstants.captionStyle,
            ),
          ),
        for (final Map<String, String> s in staff)
          ListTile(
            key: ValueKey<String>('staff_${s['id']}'),
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.person_outline, color: Colors.white70, size: 22.sp),
            title: Text(s['name'] ?? '', style: ThemeConstants.bodyStyle),
            trailing: item.staffId == s['id'] ? const Icon(Icons.check_circle, color: ThemeConstants.successGreen) : null,
            onTap: () => choose(s['id'], s['name']),
          ),
        ListTile(
          key: const ValueKey<String>('staff_nobody'),
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.person_off_outlined, color: Colors.white54, size: 22.sp),
          title: Text(sw ? 'Hakuna (usitaje mhudumu)' : 'Nobody (do not name a stylist)', style: ThemeConstants.bodyStyle.copyWith(color: Colors.white70)),
          trailing: item.staffId == null ? const Icon(Icons.check_circle, color: Colors.white38) : null,
          onTap: () => choose(null, null),
        ),
          ]),
        ),
      ],
    );
  }
}
