import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import '../../constants/theme_constants.dart';
import '../../services/app_messenger.dart';
import '../../services/localization_service.dart';
import '../../providers/auth_provider.dart';

class HelpdeskScreen extends StatefulWidget {
  const HelpdeskScreen({super.key});

  @override
  State<HelpdeskScreen> createState() => _HelpdeskScreenState();
}

class _HelpdeskScreenState extends State<HelpdeskScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthProvider>().fetchSuperAdminContact();
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = LocalizationService.instance;
    return ThemeConstants.buildResponsiveScaffold(
      context,
      title: LocalizationService.instance.translate('helpdesk'),
      body: Stack(
        children: [
          _buildBackground(),
          SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: 20.h),
                  _buildHeader(loc),
                  SizedBox(height: 30.h),
                  _buildFlowSection(loc),
                  SizedBox(height: 30.h),
                  _buildSupportSection(loc),
                  SizedBox(height: 100.h),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackground() {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              ThemeConstants.bgTop,
              ThemeConstants.bgMid,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(LocalizationService loc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          loc.isSwahili ? "Msaada na Mwongozo" : "Help & Guidance",
          style: TextStyle(
            color: Colors.white,
            fontSize: 28.sp,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
          ),
        ),
        SizedBox(height: 4.h),
        Text(
          loc.isSwahili 
              ? "Jifunze jinsi ya kutumia huduma ya upangishaji"
              : "Learn how to master the rental service flow",
          style: TextStyle(
            color: Colors.white60,
            fontSize: 14.sp,
          ),
        ),
      ],
    );
  }

  Widget _buildFlowSection(LocalizationService loc) {
    final steps = [
      {
        "title": loc.isSwahili ? "Sajili Mali" : "Register Property",
        "desc": loc.isSwahili 
            ? "Anza kwa kusajili jengo au eneo lako la upangishaji."
            : "Start by registering your building or rental area.",
        "icon": Icons.business,
      },
      {
        "title": loc.isSwahili ? "Ongeza Nyumba" : "Add Houses",
        "desc": loc.isSwahili
            ? "Gawa mali yako katika vyumba au nyumba maalum."
            : "Divide your property into specific units or houses.",
        "icon": Icons.grid_view,
      },
      {
        "title": loc.isSwahili ? "Sajili Mpangaji" : "Onboard Tenant",
        "desc": loc.isSwahili
            ? "Ingiza taarifa za mpangaji mpya kwenye mfumo."
            : "Enter new tenant details into the system.",
        "icon": Icons.person_add,
      },
      {
        "title": loc.isSwahili ? "Tengeneza Mkataba" : "Create Agreement",
        "desc": loc.isSwahili
            ? "Unganisha mpangaji na nyumba kwa mkataba rasmi."
            : "Link the tenant and house with a formal lease.",
        "icon": Icons.description,
      },
      {
        "title": loc.isSwahili ? "Rekodi Malipo" : "Record Payment",
        "desc": loc.isSwahili
            ? "Pokea kodi na toa risiti za kielektroniki papo hapo."
            : "Receive rent and issue instant electronic receipts.",
        "icon": Icons.payments,
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          loc.isSwahili ? "Mtiririko wa Huduma" : "Service Workflow",
          style: TextStyle(
            color: ThemeConstants.primaryOrange,
            fontSize: 18.sp,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 16.h),
        ...List.generate(steps.length, (index) => _buildFlowStep(
          index + 1,
          steps[index]["title"] as String,
          steps[index]["desc"] as String,
          steps[index]["icon"] as IconData,
          index == steps.length - 1,
        )),
      ],
    );
  }

  Widget _buildFlowStep(int stepNum, String title, String desc, IconData icon, bool isLast) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 32.w,
                height: 32.w,
                decoration: BoxDecoration(
                  color: ThemeConstants.primaryOrange,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: ThemeConstants.primaryOrange.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    "$stepNum",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14.sp),
                  ),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2.w,
                    color: ThemeConstants.primaryOrange.withOpacity(0.2),
                  ),
                ),
            ],
          ),
          SizedBox(width: 16.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStepCard(title, desc, icon),
                if (!isLast) SizedBox(height: 16.h),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepCard(String title, String desc, IconData icon) {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(10.w),
            decoration: BoxDecoration(
              color: ThemeConstants.primaryOrange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Icon(icon, color: ThemeConstants.primaryOrange, size: 24.sp),
          ),
          SizedBox(width: 16.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: Colors.white, fontSize: 16.sp, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 4.h),
                Text(
                  desc,
                  style: TextStyle(color: Colors.white54, fontSize: 12.sp),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSupportSection(LocalizationService loc) {
    return Container(
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            ThemeConstants.primaryBlue.withOpacity(0.4),
            ThemeConstants.primaryBlue.withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(24.r),
        border: Border.all(color: ThemeConstants.primaryBlue.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(Icons.contact_support, color: Colors.white, size: 40.sp),
          SizedBox(height: 16.h),
          Text(
            loc.isSwahili ? "Unahitaji msaada zaidi?" : "Need more help?",
            style: TextStyle(color: Colors.white, fontSize: 20.sp, fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 8.h),
          Text(
            loc.isSwahili 
                ? "Wasiliana na timu yetu ya msaada kwa maswali yoyote."
                : "Contact our support team for any questions or issues.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 13.sp),
          ),
          SizedBox(height: 20.h),
          Consumer<AuthProvider>(
            builder: (context, auth, _) {
              final hasPhone = auth.supportPhone.isNotEmpty;
              final hasEmail = auth.supportEmail.isNotEmpty;
              
              if (!hasPhone && !hasEmail) {
                return const SizedBox.shrink();
              }
              
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (hasPhone)
                    _buildSupportButton(
                      icon: Icons.phone,
                      label: LocalizationService.instance.translate('call_2'),
                      onTap: () async {
                        final Uri url = Uri.parse("tel:${auth.supportPhone}");
                        if (await canLaunchUrl(url)) {
                          await launchUrl(url);
                        } else {
                          AppMessenger.showError(LocalizationService.instance.translate('could_not_launch_dialer'));
                        }
                      },
                      color: ThemeConstants.primaryOrange,
                    ),
                  if (hasPhone && hasEmail) SizedBox(width: 16.w),
                  if (hasEmail)
                    _buildSupportButton(
                      icon: Icons.email,
                      label: LocalizationService.instance.translate('email_message'),
                      onTap: () async {
                        final Uri url = Uri.parse("mailto:${auth.supportEmail}");
                        if (await canLaunchUrl(url)) {
                          await launchUrl(url);
                        } else {
                          AppMessenger.showError(LocalizationService.instance.translate('could_not_launch_email_client'));
                        }
                      },
                      color: Colors.white24,
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSupportButton({required IconData icon, required String label, required VoidCallback onTap, required Color color}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12.r),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 18.sp),
            SizedBox(width: 8.w),
            Text(
              label,
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14.sp),
            ),
          ],
        ),
      ),
    );
  }
}

