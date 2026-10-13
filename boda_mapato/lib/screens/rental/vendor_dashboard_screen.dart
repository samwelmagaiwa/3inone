import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../constants/theme_constants.dart';
import '../../providers/auth_provider.dart';
import '../../providers/maintenance_provider.dart';
import '../../services/localization_service.dart';

class VendorDashboardScreen extends StatefulWidget {
  const VendorDashboardScreen({super.key});

  @override
  State<VendorDashboardScreen> createState() => _VendorDashboardScreenState();
}

class _VendorDashboardScreenState extends State<VendorDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MaintenanceProvider>().fetchRequests();
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final loc = LocalizationService.instance;

    return ThemeConstants.buildScaffold(
      title: LocalizationService.instance.translate('my_jobs'), // "My Jobs"
      actions: [
        IconButton(
          icon: const Icon(Icons.logout, color: Colors.white),
          onPressed: () async {
            await context.read<AuthProvider>().logout();
            if (context.mounted) Navigator.pushReplacementNamed(context, "/");
          },
        )
      ],
      body: Consumer<MaintenanceProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && provider.requests.isEmpty) {
            return ThemeConstants.buildLoadingWidget();
          }

          if (provider.requests.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.assignment_turned_in_outlined,
                      size: 64.sp, color: Colors.grey.withOpacity(0.4)),
                  SizedBox(height: 16.h),
                  Text(LocalizationService.instance.translate('you_have_no_new_jobs'),
                      style: ThemeConstants.subHeadingStyle),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: EdgeInsets.all(14.w),
            physics: const BouncingScrollPhysics(),
            itemCount: provider.requests.length,
            itemBuilder: (context, index) {
              final request = provider.requests[index];
              return _buildWorkOrderCard(context, request);
            },
          );
        },
      ),
    );
  }

  Widget _buildWorkOrderCard(BuildContext context, Map<String, dynamic> request) {
    final id = request['id'] ?? '';
    final title = request['title'] ?? LocalizationService.instance.translate('new_jobs');
    final status = request['status'] ?? 'pending';
    final createdAt = request['created_at'] != null
        ? request['created_at'].toString().split('T').first
        : '';

    final isResolved = status == 'resolved';

    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: ThemeConstants.buildResponsiveGlassCard(
        context,
        onTap: () {
          Navigator.pushNamed(context, "/rental/maintenance-details",
              arguments: request);
        },
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.all(12.r),
              decoration: BoxDecoration(
                color: isResolved
                    ? ThemeConstants.successGreen.withOpacity(0.12)
                    : ThemeConstants.warningAmber.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isResolved ? Icons.check_circle_outline : Icons.build_circle_outlined,
                color: isResolved
                    ? ThemeConstants.successGreen
                    : ThemeConstants.warningAmber,
                size: 24.sp,
              ),
            ),
            SizedBox(width: 16.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: ThemeConstants.bodyStyle.copyWith(
                          fontWeight: FontWeight.bold, fontSize: 16.sp)),
                  SizedBox(height: 4.h),
                  Text(LocalizationService.instance.translateWith('date_2', <Object?>[createdAt]), style: ThemeConstants.captionStyle),
                  SizedBox(height: 8.h),
                  _buildStatusChip(status),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios,
                color: Colors.white24, size: 16.sp),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    Color bg;
    String label;
    switch (status) {
      case 'open':
        bg = ThemeConstants.primaryBlue;
        label = LocalizationService.instance.translate('new_sent');
        break;
      case 'pending':
        bg = ThemeConstants.warningAmber;
        label = LocalizationService.instance.translate('receipt_status_pending');
        break;
      case 'in_progress':
        bg = ThemeConstants.primaryOrange;
        label = LocalizationService.instance.translate('in_progress');
        break;
      case 'resolved':
        bg = ThemeConstants.successGreen;
        label = LocalizationService.instance.translate('status_completed');
        break;
      default:
        bg = Colors.grey;
        label = status;
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: bg.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: bg.withOpacity(0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: bg, fontSize: 12.sp, fontWeight: FontWeight.bold),
      ),
    );
  }
}
