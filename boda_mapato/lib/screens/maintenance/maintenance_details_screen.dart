import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../constants/theme_constants.dart';
import '../../providers/auth_provider.dart';
import '../../providers/maintenance_provider.dart';
import '../../services/localization_service.dart';
import '../../utils/maintenance_labels.dart';

class MaintenanceDetailsScreen extends StatefulWidget {
  const MaintenanceDetailsScreen({required this.request, super.key});
  final Map<String, dynamic> request;

  @override
  _MaintenanceDetailsScreenState createState() => _MaintenanceDetailsScreenState();
}

class _MaintenanceDetailsScreenState extends State<MaintenanceDetailsScreen> {
  final _costController = TextEditingController();
  String? _selectedVendorId;

  @override
  void dispose() {
    _costController.dispose();
    super.dispose();
  }

  Future<void> _callVendor(String? phone) async {
    if (phone == null || phone.isEmpty) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, LocalizationService.instance.translate('phone_number_not_found'));
      return;
    }
    final String urlString = "tel:$phone";
    if (await canLaunchUrlString(urlString)) {
      await launchUrlString(urlString, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) ThemeConstants.showErrorSnackBar(context, LocalizationService.instance.translate('could_not_make_the_call'));
    }
  }

  Future<void> _assignVendor() async {
    final provider = context.read<MaintenanceProvider>();
    await provider.fetchVendors();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 14.w, right: 14.w, top: 20.h
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40.w,
                  height: 4.h,
                  margin: EdgeInsets.only(bottom: 24.h),
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10.r)),
                ),
              ),
              Text(LocalizationService.instance.translate('assign_a_maintenance_technician'), 
                  style: ThemeConstants.headingStyle.copyWith(fontSize: 18.sp)),
              SizedBox(height: 12.h),
              ThemeConstants.buildResponsiveGlassCardStatic(
                context,
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("${LocalizationService.instance.translate('request_details')}:", style: TextStyle(color: ThemeConstants.footerBarColor, fontSize: 11.sp, fontWeight: FontWeight.bold)),
                    SizedBox(height: 4.h),
                    Text("${maintenanceCategoryLabel(widget.request['category']?.toString())} - ${widget.request['property']?['name'] ?? ''}", style: TextStyle(color: Colors.white, fontSize: 13.sp, fontWeight: FontWeight.bold)),
                    SizedBox(height: 2.h),
                    Text(widget.request['description'] ?? '', style: TextStyle(color: Colors.white70, fontSize: 12.sp)),
                  ],
                ),
              ),
              SizedBox(height: 20.h),
              DropdownButtonFormField<String>(
                dropdownColor: const Color(0xFF1E293B),
                style: ThemeConstants.bodyStyle,
                decoration: _inputDecoration(LocalizationService.instance.translate('select_technician')),
                items: provider.vendors.map((v) {
                  return DropdownMenuItem(value: v['id'].toString(), child: Text(v['name']));
                }).toList(),
                onChanged: (val) => setState(() => _selectedVendorId = val),
              ),
              SizedBox(height: 16.h),
              TextField(
                controller: _costController,
                keyboardType: TextInputType.number,
                style: ThemeConstants.bodyStyle,
                decoration: _inputDecoration(LocalizationService.instance.translate('estimated_cost_tzs')),
              ),
              SizedBox(height: 32.h),
              SizedBox(
                width: double.infinity,
                height: 58.h,
                child: ElevatedButton(
                  onPressed: () async {
                    if (_selectedVendorId == null) {
                      ThemeConstants.showErrorSnackBar(context, LocalizationService.instance.translate('please_select_a_technician'));
                      return;
                    }
                    final success = await provider.assignWorkOrder(
                      requestId: widget.request['id'].toString(),
                      vendorId: _selectedVendorId!,
                      title: LocalizationService.instance.translateWith('maintenance_for', <Object?>[maintenanceCategoryLabel(widget.request['category']?.toString())]),
                      estimatedCost: double.tryParse(_costController.text),
                    );
                    if (success && mounted) {
                      Navigator.pop(context);
                      Navigator.pop(context);
                      ThemeConstants.showSuccessSnackBar(context, LocalizationService.instance.translate('technician_assigned_successfully'));
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ThemeConstants.footerBarColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
                  ),
                  child: Text(LocalizationService.instance.translate('save_plan').toUpperCase(), style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16.sp)),
                ),
              ),
              SizedBox(height: 30.h),
            ],
          ),
        );
      },
    );
  }

  Future<void> _updateStatus(String status) async {
    final success = await context.read<MaintenanceProvider>().updateStatus(
      requestId: widget.request['id'].toString(),
      status: status,
    );
    if (success && mounted) {
      if (Navigator.canPop(context)) Navigator.pop(context);
      ThemeConstants.showSuccessSnackBar(context, LocalizationService.instance.translate('request_status_updated'));
    }
  }

  @override
  Widget build(final BuildContext context) {
    final request = widget.request;
    final user = context.read<AuthProvider>().user;
    final isLandlord = user?.role == 'admin' || user?.role == 'landlord' || user?.role == 'super_admin';
    final isVendor = user?.role == 'vendor';
    final workOrder = request['work_order'];

    return ThemeConstants.buildScaffold(
      title: LocalizationService.instance.translate('request_details_2'),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 20.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ThemeConstants.buildResponsiveGlassCardStatic(
                    context,
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        if (request['photo_url'] != null)
                          ClipRRect(
                            borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
                            child: Image.network(
                              request['photo_url'],
                              height: 220.h,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _buildPlaceholderImage(),
                            ),
                          )
                        else
                          _buildPlaceholderImage(),
                        Padding(
                          padding: EdgeInsets.all(16.r),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  _StatusBadge(status: request['status'] ?? 'open'),
                                  Text(request['created_at'].toString().split('T')[0], 
                                      style: ThemeConstants.captionStyle),
                                ],
                              ),
                              SizedBox(height: 16.h),
                              Text(maintenanceCategoryLabel(request['category']?.toString()),
                                  style: TextStyle(color: ThemeConstants.footerBarColor, fontSize: 13.sp, fontWeight: FontWeight.bold)),
                              SizedBox(height: 8.h),
                              Text(request['description'] ?? '',
                                  style: ThemeConstants.bodyStyle.copyWith(fontSize: 16.sp, height: 1.5)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 20.h),
                  _buildSectionTitle(LocalizationService.instance.translate('location_and_property')),
                  ThemeConstants.buildResponsiveGlassCardStatic(
                    context,
                    child: Row(
                      children: [
                        Expanded(child: _buildInfoColumn(Icons.home, LocalizationService.instance.translate('property_label'), request['property']?['name'] ?? 'N/A')),
                        if (request['house'] != null)
                          Expanded(child: _buildInfoColumn(Icons.door_front_door, LocalizationService.instance.translate('house_label'), LocalizationService.instance.translateWith('unit_2', <Object?>[request['house']['house_number']]))),
                      ],
                    ),
                  ),
                  SizedBox(height: 20.h),
                  if (workOrder != null) ...[
                    _buildSectionTitle(LocalizationService.instance.translate('maintenance_job_work_order')),
                    ThemeConstants.buildResponsiveGlassCardStatic(
                      context,
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildInfoRow(Icons.person_outline, LocalizationService.instance.translate('technician'), workOrder['vendor']?['name'] ?? 'N/A'),
                              if (workOrder['vendor']?['phone'] != null)
                                IconButton(
                                  onPressed: () => _callVendor(workOrder['vendor']['phone'].toString()),
                                  icon: Container(
                                    padding: EdgeInsets.all(8.r),
                                    decoration: BoxDecoration(
                                      color: ThemeConstants.successGreen.withOpacity(0.12),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(Icons.phone_outlined, color: ThemeConstants.successGreen, size: 18.sp),
                                  ),
                                ),
                            ],
                          ),
                          Divider(color: Colors.white.withOpacity(0.08), height: 24.h),
                          Row(
                            children: [
                              Expanded(child: _buildInfoColumn(Icons.payments_outlined, LocalizationService.instance.translate('estimate'), "TZS ${workOrder['estimated_cost']}")),
                              Expanded(child: _buildInfoColumn(Icons.calendar_month_outlined, LocalizationService.instance.translate('date'), workOrder['scheduled_date'] ?? LocalizationService.instance.translate('receipt_status_pending'))),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                  SizedBox(height: 40.h),
                  if (isLandlord && request['status'] == 'open')
                    _buildActionButton(LocalizationService.instance.translate('assign_technician_now').toUpperCase(), Icons.assignment_ind, _assignVendor),
                  if (isLandlord && request['status'] == 'pending')
                    _buildActionButton(LocalizationService.instance.translate('start_maintenance_landlord').toUpperCase(), Icons.play_circle_fill, () => _updateStatus('in_progress')),
                  if (isLandlord && request['status'] == 'in_progress')
                    _buildActionButton(LocalizationService.instance.translate('resolve_complete_landlord').toUpperCase(), Icons.check_circle, () => _updateStatus('resolved'), color: ThemeConstants.successGreen),
                    
                  if (isVendor && request['status'] == 'pending')
                    _buildActionButton(LocalizationService.instance.translate('start_this_job').toUpperCase(), Icons.play_circle_fill, () => _updateStatus('in_progress')),
                  if (isVendor && request['status'] == 'in_progress')
                    _buildActionButton(LocalizationService.instance.translate('complete_job_resolve').toUpperCase(), Icons.check_circle, () => _updateStatus('resolved'), color: ThemeConstants.successGreen),
                  SizedBox(height: 40.h),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholderImage() {
    return Container(
      height: 150.h,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      child: Center(
        child: Icon(Icons.build_circle, size: 64.sp, color: ThemeConstants.footerBarColor.withOpacity(0.3)),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12.h, left: 4.w),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(color: Colors.white60, fontSize: 11.sp, fontWeight: FontWeight.bold, letterSpacing: 1.1),
      ),
    );
  }

  Widget _buildInfoColumn(IconData icon, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14.sp, color: ThemeConstants.footerBarColor),
            SizedBox(width: 6.w),
            Text(label, style: ThemeConstants.captionStyle.copyWith(fontSize: 11.sp)),
          ],
        ),
        SizedBox(height: 4.h),
        Text(value, style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.bold, fontSize: 14.sp)),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18.sp, color: ThemeConstants.footerBarColor),
        SizedBox(width: 12.w),
        Text("$label: ", style: ThemeConstants.captionStyle),
        Text(value, style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildActionButton(String label, IconData icon, VoidCallback onPressed, {Color? color}) {
    return Padding(
      padding: EdgeInsets.only(bottom: 16.h),
      child: SizedBox(
        width: double.infinity,
        height: 55.h,
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: color ?? ThemeConstants.footerBarColor,
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 22.sp),
              SizedBox(width: 12.w),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14.sp,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: ThemeConstants.captionStyle,
      filled: true,
      fillColor: Colors.white.withOpacity(0.05),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14.r), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14.r),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (status) {
      case 'open': color = Colors.lightBlueAccent;
      case 'pending': color = Colors.orangeAccent;
      case 'in_progress': color = Colors.purpleAccent;
      case 'resolved': color = Colors.greenAccent;
      case 'cancelled': color = Colors.redAccent;
      default: color = Colors.grey;
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 5.h),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(color: color, fontSize: 9.sp, fontWeight: FontWeight.bold, letterSpacing: 0.8),
      ),
    );
  }
}
