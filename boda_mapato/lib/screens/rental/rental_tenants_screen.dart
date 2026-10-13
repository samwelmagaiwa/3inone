import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import '../../constants/theme_constants.dart';
import '../../providers/rental_provider.dart';
import '../../services/localization_service.dart';

class RentalTenantsScreen extends StatefulWidget {
  const RentalTenantsScreen({super.key});

  @override
  State<RentalTenantsScreen> createState() => _RentalTenantsScreenState();
}

class _RentalTenantsScreenState extends State<RentalTenantsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String? _selectedStatus;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RentalProvider>().fetchTenants();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    setState(() => _searchQuery = query);
  }

  List<dynamic> _filterTenants(List tenants) {
    return tenants.where((tenant) {
      final name = (tenant['name'] ?? '').toString().toLowerCase();
      final phone = (tenant['phone_number'] ?? '').toString().toLowerCase();
      final house =
          (tenant['house']?['house_number'] ?? '').toString().toLowerCase();

      final matchesSearch = _searchQuery.isEmpty ||
          name.contains(_searchQuery.toLowerCase()) ||
          phone.contains(_searchQuery.toLowerCase()) ||
          house.contains(_searchQuery.toLowerCase());

      final status = tenant['agreement']?['status'] ?? 'active';
      final matchesStatus =
          _selectedStatus == null || status == _selectedStatus;

      return matchesSearch && matchesStatus;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final rentalProvider = context.watch<RentalProvider>();
    final tenants = rentalProvider.tenants;
    final filteredTenants = _filterTenants(tenants);

    return ThemeConstants.buildResponsiveScaffold(
      context,
      title: LocalizationService.instance.translate('rental_tenants_title'),
      actions: [
        IconButton(
            icon: const Icon(Icons.person_add, color: Colors.white),
            onPressed: () =>
                Navigator.pushNamed(context, "/rental/onboard-tenant")),
      ],
      body: Column(
        children: [
          _buildSearchAndFilter(),
          Expanded(
            child: rentalProvider.isLoading && tenants.isEmpty
                ? Center(
                    child: ThemeConstants.buildResponsiveLoadingWidget(context))
                : tenants.isEmpty
                    ? _buildEmptyState()
                    : _buildTenantList(filteredTenants),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilter() {
    return Container(
      padding: EdgeInsets.all(16.w),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: LocalizationService.instance.translate('search_tenant'),
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon: const Icon(Icons.search, color: Colors.white38),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: Colors.white38),
                      onPressed: () {
                        setState(() {
                          _searchQuery = '';
                          _searchController.clear();
                        });
                      })
                  : null,
              filled: true,
              fillColor: Colors.white.withOpacity(0.1),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.r),
                  borderSide: BorderSide.none),
            ),
          ),
          SizedBox(height: 12.h),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip(LocalizationService.instance.translate('all'), null, _selectedStatus == null),
                SizedBox(width: 8.w),
                _buildFilterChip(
                    LocalizationService.instance.translate('tenant_status_active'), "active", _selectedStatus == "active"),
                SizedBox(width: 8.w),
                _buildFilterChip(
                    LocalizationService.instance.translate('tenant_status_notice'), "notice", _selectedStatus == "notice"),
                SizedBox(width: 8.w),
                _buildFilterChip(
                    LocalizationService.instance.translate('tenant_status_defaulter'), "defaulter", _selectedStatus == "defaulter"),
                SizedBox(width: 8.w),
                _buildFilterChip(
                    LocalizationService.instance.translate('tenant_status_left'), "terminated", _selectedStatus == "terminated"),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String? value, bool isSelected) {
    return GestureDetector(
      onTap: () => setState(() => _selectedStatus = isSelected ? null : value),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
        decoration: BoxDecoration(
            color: isSelected
                ? ThemeConstants.primaryOrange
                : Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20.r)),
        child:
            Text(label, style: TextStyle(color: Colors.white, fontSize: 12.sp)),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(24.w),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child:
                Icon(Icons.people_outline, size: 64.sp, color: Colors.white38),
          ),
          SizedBox(height: 24.h),
          Text(LocalizationService.instance.translate('no_tenants'),
              style: TextStyle(
                  color: Colors.white54,
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w500)),
          SizedBox(height: 8.h),
          Text(LocalizationService.instance.translate('registered_tenants_will_appear_here'),
              style: TextStyle(color: Colors.white38, fontSize: 14.sp)),
          SizedBox(height: 24.h),
          ElevatedButton.icon(
            onPressed: () =>
                Navigator.pushNamed(context, "/rental/onboard-tenant"),
            style: ElevatedButton.styleFrom(
              backgroundColor: ThemeConstants.primaryOrange,
              padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 14.h),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r)),
            ),
            icon: const Icon(Icons.person_add, color: Colors.white),
            label: Text(LocalizationService.instance.translate('add_tenant_2'),
                style: TextStyle(color: Colors.white, fontSize: 16.sp)),
          ),
        ],
      ),
    );
  }

  Widget _buildTenantList(List tenants) {
    return ListView.builder(
      padding: EdgeInsets.all(16.w),
      itemCount: tenants.length,
      itemBuilder: (context, index) {
        final tenant = tenants[index] as Map<String, dynamic>;
        return _buildTenantCard(tenant);
      },
    );
  }

  Widget _buildTenantCard(Map<String, dynamic> tenant) {
    final house = tenant['house'] ?? {};
    final agreement = tenant['agreement'] ?? {};
    final status = agreement['status'] ?? 'active';

    Color statusColor;
    String statusLabel;
    switch (status) {
      case 'active':
        statusColor = ThemeConstants.successGreen;
        statusLabel = LocalizationService.instance.translate('tenant_status_active');
      case 'notice':
        statusColor = ThemeConstants.warningAmber;
        statusLabel = LocalizationService.instance.translate('tenant_status_notice');
      case 'defaulter':
        statusColor = ThemeConstants.errorRed;
        statusLabel = LocalizationService.instance.translate('tenant_status_defaulter');
      case 'terminated':
        statusColor = Colors.white38;
        statusLabel = LocalizationService.instance.translate('tenant_status_left');
      default:
        statusColor = Colors.white54;
        statusLabel = status.toString();
    }

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.pushNamed(context, '/rental/tenant-details',
              arguments: tenant),
          borderRadius: BorderRadius.circular(20.r),
          child: Padding(
            padding: EdgeInsets.all(16.w),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(12.w),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        ThemeConstants.primaryOrange.withOpacity(0.3),
                        ThemeConstants.primaryOrange.withOpacity(0.1)
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14.r),
                  ),
                  child: Text(
                    (tenant['name'] ?? '?').substring(0, 1).toUpperCase(),
                    style: TextStyle(
                        color: ThemeConstants.primaryOrange,
                        fontWeight: FontWeight.bold,
                        fontSize: 20.sp),
                  ),
                ),
                SizedBox(width: 14.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tenant['name'] ?? '',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 4.h),
                      Row(
                        children: [
                          Icon(Icons.phone, size: 12.sp, color: Colors.white54),
                          SizedBox(width: 4.w),
                          Text(tenant['phone_number'] ?? '',
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 12.sp)),
                        ],
                      ),
                      SizedBox(height: 2.h),
                      Row(
                        children: [
                          Icon(Icons.home, size: 12.sp, color: Colors.white38),
                          SizedBox(width: 4.w),
                          Flexible(
                            child: Text(
                              "${house['house_number'] ?? ''} - ${house['property_name'] ?? ''}",
                              style: TextStyle(
                                  color: Colors.white38, fontSize: 11.sp),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20.r),
                  ),
                  child: Text(statusLabel,
                      style: TextStyle(
                          color: statusColor,
                          fontSize: 11.sp,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
