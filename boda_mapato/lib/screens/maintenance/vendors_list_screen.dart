import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher_string.dart';
import '../../constants/theme_constants.dart';
import '../../providers/auth_provider.dart';
import '../../providers/maintenance_provider.dart';
import '../../widgets/temporary_password_dialog.dart';

class VendorsListScreen extends StatefulWidget {
  const VendorsListScreen({super.key});

  @override
  _VendorsListScreenState createState() => _VendorsListScreenState();
}

class _VendorsListScreenState extends State<VendorsListScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _specialtyController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _experienceController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MaintenanceProvider>().fetchVendors();
      final canManage = context.read<AuthProvider>().user?.hasPermission('manage_vendors') == true;
      if (canManage) {
        context.read<MaintenanceProvider>().fetchMarketplaceVendors();
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _specialtyController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _experienceController.dispose();
    super.dispose();
  }

  Future<void> _callVendor(String? phone) async {
    if (phone == null || phone.isEmpty) {
      ThemeConstants.showErrorSnackBar(context, "Namba ya simu haipatikani");
      return;
    }
    final String urlString = "tel:$phone";
    if (await canLaunchUrlString(urlString)) {
      await launchUrlString(urlString, mode: LaunchMode.externalApplication);
    } else {
      ThemeConstants.showErrorSnackBar(context, "Imeshindikana kupiga simu");
    }
  }

  void _showAddVendorSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
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
            Text("Ongeza Fundi Mpya", style: ThemeConstants.headingStyle.copyWith(fontSize: 18.sp)),
            SizedBox(height: 24.h),
            _buildTextField(_nameController, "Jina kamili", Icons.person),
            SizedBox(height: 16.h),
            Row(
              children: [
                Expanded(child: _buildTextField(_phoneController, "Namba ya simu", Icons.phone, keyboardType: TextInputType.phone)),
                SizedBox(width: 8.w),
                Expanded(child: _buildTextField(_specialtyController, "Utaalamu", Icons.category)),
              ],
            ),
            SizedBox(height: 16.h),
            Row(
              children: [
                 Expanded(child: _buildTextField(_emailController, "Barua pepe (Email)", Icons.email, keyboardType: TextInputType.emailAddress)),
                 SizedBox(width: 8.w),
                 Expanded(child: _buildTextField(_experienceController, "Uzoefu (Mf. Miezi 6)", Icons.history)),
              ],
            ),
            SizedBox(height: 16.h),
            _buildTextField(_addressController, "Anwani (Mtaa/Eneo)", Icons.location_on),
            SizedBox(height: 32.h),
            SizedBox(
              width: double.infinity,
              height: 58.h,
              child: ElevatedButton(
                onPressed: () async {
                  if (_nameController.text.isEmpty || _phoneController.text.isEmpty) {
                    ThemeConstants.showErrorSnackBar(context, "Tafadhali jaza jina na namba ya simu");
                    return;
                  }
                  final MaintenanceProvider provider = context.read<MaintenanceProvider>();
                  final String vendorName = _nameController.text;
                  final String vendorPhone = _phoneController.text;
                  final errorMsg = await provider.addVendor(
                    name: _nameController.text,
                    phone: _phoneController.text,
                    specialty: _specialtyController.text,
                    email: _emailController.text,
                    address: _addressController.text,
                    experience: _experienceController.text,
                  );
                  if (errorMsg == null && mounted) {
                    // A brand-new fundi gets a one-time password from the server, shown once
                    // for the landlord to hand over (null if the fundi already had a sign-in).
                    final String? temporaryPassword = provider.lastTemporaryPassword;
                    Navigator.pop(context);
                    _nameController.clear();
                    _phoneController.clear();
                    _specialtyController.clear();
                    _emailController.clear();
                    _addressController.clear();
                    _experienceController.clear();
                    ThemeConstants.showSuccessSnackBar(context, "Fundi ameongezwa kikamilifu");
                    if (temporaryPassword != null) {
                      // The list screen's own context: the sheet's is gone once it has closed.
                      await showTemporaryPasswords(this.context, <TemporaryCredential>[
                        TemporaryCredential(
                          name: vendorName,
                          contact: vendorPhone,
                          password: temporaryPassword,
                        ),
                      ]);
                    }
                  } else if (errorMsg != null && mounted) {
                    ThemeConstants.showErrorSnackBar(context, errorMsg);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: ThemeConstants.footerBarColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
                ),
                child: Text("HIFADHI TAARIFA", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16.sp)),
              ),
            ),
            SizedBox(height: 30.h),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(final BuildContext context) {
    final bool canManage = context.watch<AuthProvider>().user?.hasPermission('manage_vendors') == true;

    return ThemeConstants.buildScaffold(
      title: canManage ? "Usimamizi wa Mafundi" : "Watoa Huduma & Mafundi",
      body: Consumer<MaintenanceProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && provider.vendors.isEmpty) {
            return ThemeConstants.buildLoadingWidget();
          }

          if (!canManage) {
            return _buildListView(provider.vendors, false, provider);
          }

          return DefaultTabController(
            length: 2,
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
                  ),
                  child: TabBar(
                    indicatorColor: ThemeConstants.footerBarColor,
                    labelColor: ThemeConstants.footerBarColor,
                    unselectedLabelColor: Colors.grey,
                    labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.sp),
                    tabs: const [
                      Tab(text: "Mafundi Wangu"),
                      Tab(text: "Soko la Mafundi"),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildListView(provider.vendors, false, provider),
                      _buildListView(provider.marketplaceVendors, true, provider),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: canManage
          ? Padding(
              padding: EdgeInsets.only(bottom: 20.h),
              child: FloatingActionButton(
                onPressed: _showAddVendorSheet,
                backgroundColor: ThemeConstants.footerBarColor,
                elevation: 6,
                child: Icon(Icons.person_add_alt_1, color: Colors.white, size: 24.sp),
              ),
            )
          : null,
    );
  }

  Widget _buildListView(List<Map<String, dynamic>> list, bool isMarketplace, MaintenanceProvider provider) {
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_search_outlined, size: 64.sp, color: Colors.grey.withOpacity(0.4)),
            SizedBox(height: 16.h),
            Text(isMarketplace ? "Hakuna mafundi kwenye soko" : "Hakuna mafundi kwenye orodha yako", style: ThemeConstants.subHeadingStyle),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(14.w, 12.h, 14.w, 100.h),
      itemCount: list.length,
      physics: const BouncingScrollPhysics(),
      itemBuilder: (context, index) {
        final vendor = list[index];
        final bool isAlreadySaved = provider.vendors.any((v) => v['id'] == vendor['id']);

        return Padding(
          padding: EdgeInsets.only(bottom: 12.h),
          child: ThemeConstants.buildResponsiveGlassCard(
            context,
            onTap: () => _callVendor(vendor['phone']),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(12.r),
                  decoration: BoxDecoration(
                    color: ThemeConstants.footerBarColor.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.handyman_outlined, color: ThemeConstants.footerBarColor, size: 24.sp),
                ),
                SizedBox(width: 16.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(vendor['name'] ?? 'N/A',
                          style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.bold, fontSize: 16.sp)),
                      SizedBox(height: 4.h),
                      Row(
                        children: [
                          Text(vendor['specialty'] ?? 'Fundi',
                              style: TextStyle(color: ThemeConstants.footerBarColor, fontSize: 12.sp, fontWeight: FontWeight.w500)),
                          if (vendor['experience'] != null && vendor['experience'].toString().isNotEmpty) ...[
                             SizedBox(width: 8.w),
                             Container(
                               padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                               decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(4.r)),
                               child: Text('${vendor['experience']} ya Uzoefu', style: TextStyle(color: Colors.orange, fontSize: 10.sp)),
                             ),
                          ]
                        ]
                      ),
                    ],
                  ),
                ),
                if (isMarketplace && !isAlreadySaved)
                  IconButton(
                    icon: Container(
                      padding: EdgeInsets.all(8.r),
                      decoration: BoxDecoration(color: ThemeConstants.footerBarColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8.r)),
                      child: Icon(Icons.bookmark_add_outlined, color: ThemeConstants.footerBarColor, size: 20.sp),
                    ),
                    onPressed: () async {
                      final success = await provider.saveToRoster(vendor['id'].toString());
                      if (success && mounted) {
                        ThemeConstants.showSuccessSnackBar(context, "Fundi amehifadhiwa!");
                      } else if (mounted) {
                        ThemeConstants.showErrorSnackBar(context, "Imeshindikana kuhifadhi fundi");
                      }
                    },
                  )
                else
                  IconButton(
                    icon: Container(
                      padding: EdgeInsets.all(8.r),
                      decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(8.r)),
                      child: Icon(Icons.phone_forwarded, color: Colors.green, size: 20.sp),
                    ),
                    onPressed: () => _callVendor(vendor['phone']),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTextField(TextEditingController controller, String hint, IconData icon, {TextInputType? keyboardType}) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: ThemeConstants.bodyStyle,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: ThemeConstants.captionStyle,
        prefixIcon: Icon(icon, color: Colors.grey, size: 18.sp),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14.r), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14.r),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14.r),
          borderSide: const BorderSide(color: ThemeConstants.footerBarColor, width: 1.2),
        ),
      ),
    );
  }
}
