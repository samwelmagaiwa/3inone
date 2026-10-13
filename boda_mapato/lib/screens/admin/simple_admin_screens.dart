import "package:flutter/material.dart";

import '../../constants/theme_constants.dart';
import '../../utils/responsive_helper.dart';
import '../../services/localization_service.dart';

class SimpleDriversManagementScreen extends StatelessWidget {
  const SimpleDriversManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    ResponsiveHelper.init(context);
    return ThemeConstants.buildResponsiveScaffold(
      context,
      title: LocalizationService.instance.translate('drivers'),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people,
              size: ResponsiveHelper.iconSizeXL * 2,
              color: Colors.white,
            ),
            ResponsiveHelper.verticalSpace(2.5),
            Text(
              LocalizationService.instance.translate('drivers_management'),
              style: TextStyle(
                color: Colors.white,
                fontSize: ResponsiveHelper.h2,
                fontWeight: FontWeight.bold,
              ),
            ),
            ResponsiveHelper.verticalSpace(1.2),
            Text(
              LocalizationService.instance.translate('this_page_is_still_being_built'),
              style: TextStyle(
                color: Colors.white70,
                fontSize: ResponsiveHelper.bodyL,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SimpleVehiclesManagementScreen extends StatelessWidget {
  const SimpleVehiclesManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(LocalizationService.instance.translate('vehicles_3')),
        backgroundColor: ThemeConstants.primaryBlue,
        foregroundColor: Colors.white,
      ),
      backgroundColor: ThemeConstants.primaryBlue,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.directions_car,
              size: 80,
              color: Colors.white,
            ),
            SizedBox(height: 20),
            Text(
              LocalizationService.instance.translate('vehicle_management'),
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 10),
            Text(
              LocalizationService.instance.translate('this_page_is_still_being_built'),
              style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SimplePaymentsManagementScreen extends StatelessWidget {
  const SimplePaymentsManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(LocalizationService.instance.translate('payments_section')),
        backgroundColor: ThemeConstants.primaryBlue,
        foregroundColor: Colors.white,
      ),
      backgroundColor: ThemeConstants.primaryBlue,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.payment,
              size: 80,
              color: Colors.white,
            ),
            SizedBox(height: 20),
            Text(
              LocalizationService.instance.translate('payments_management'),
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 10),
            Text(
              LocalizationService.instance.translate('this_page_is_still_being_built'),
              style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SimpleAnalyticsScreen extends StatelessWidget {
  const SimpleAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(LocalizationService.instance.translate('analytics')),
        backgroundColor: ThemeConstants.primaryBlue,
        foregroundColor: Colors.white,
      ),
      backgroundColor: ThemeConstants.primaryBlue,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.analytics,
              size: 80,
              color: Colors.white,
            ),
            SizedBox(height: 20),
            Text(
              LocalizationService.instance.translate('analytics'),
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 10),
            Text(
              LocalizationService.instance.translate('this_page_is_still_being_built'),
              style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SimpleReportsScreen extends StatelessWidget {
  const SimpleReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(LocalizationService.instance.translate('reports')),
        backgroundColor: ThemeConstants.primaryBlue,
        foregroundColor: Colors.white,
      ),
      backgroundColor: ThemeConstants.primaryBlue,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.receipt_long,
              size: 80,
              color: Colors.white,
            ),
            SizedBox(height: 20),
            Text(
              LocalizationService.instance.translate('reports'),
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 10),
            Text(
              LocalizationService.instance.translate('this_page_is_still_being_built'),
              style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SimpleRemindersScreen extends StatelessWidget {
  const SimpleRemindersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(LocalizationService.instance.translate('reminders')),
        backgroundColor: ThemeConstants.primaryBlue,
        foregroundColor: Colors.white,
      ),
      backgroundColor: ThemeConstants.primaryBlue,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.notifications,
              size: 80,
              color: Colors.white,
            ),
            SizedBox(height: 20),
            Text(
              LocalizationService.instance.translate('reminders'),
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 10),
            Text(
              LocalizationService.instance.translate('this_page_is_still_being_built'),
              style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SimpleReportScreen extends StatelessWidget {
  const SimpleReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(LocalizationService.instance.translate('reports')),
        backgroundColor: ThemeConstants.primaryBlue,
        foregroundColor: Colors.white,
      ),
      backgroundColor: ThemeConstants.primaryBlue,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.receipt_long,
              size: 80,
              color: Colors.white,
            ),
            SizedBox(height: 20),
            Text(
              LocalizationService.instance.translate('reports'),
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 10),
            Text(
              LocalizationService.instance.translate('this_page_is_still_being_built'),
              style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
