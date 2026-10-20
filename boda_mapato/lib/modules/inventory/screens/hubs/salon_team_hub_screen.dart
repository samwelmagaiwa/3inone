import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../models/user_permissions.dart';
import '../../../../services/localization_service.dart';
import '../salon/attendance_screen.dart';
import '../salon/schedule_screen.dart';
import '../salon/shifts_screen.dart';
import '../widgets/inventory_widgets.dart';

/// The salon's people at work: who is in and for how long, when each works (the owner and managers), and each
/// shift's cash. Everyone opens it for their own day; the owner and managers see everyone's.
class SalonTeamHubScreen extends StatelessWidget {
  const SalonTeamHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;

    return InvTabScaffold(
      title: '',
      tabs: <String>[
        sw ? 'Mahudhurio' : 'Attendance',
        sw ? 'Ratiba' : 'Schedule',
        sw ? 'Pesa za zamu' : 'Shift cash',
      ],
      views: const <Widget>[
        AttendanceScreen(),
        ScheduleScreen(),
        ShiftsScreen(),
      ],
      // The schedule is the owner's and managers' to set; attendance and shifts are for everyone.
      tabPermissions: <bool Function(UserPermissions)?>[
        null,
        (UserPermissions p) => p.has('inv_view_reports'),
        null,
      ],
    );
  }
}
