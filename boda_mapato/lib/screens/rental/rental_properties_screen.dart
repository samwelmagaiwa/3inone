import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../constants/theme_constants.dart';
import '../../providers/rental_provider.dart';
import '../../widgets/backgrounds/starfield_background.dart';
import '../../widgets/location_selector.dart';
import '../../services/localization_service.dart';
import '../../utils/rental_labels.dart';

class RentalPropertiesScreen extends StatefulWidget {
  const RentalPropertiesScreen({super.key});

  @override
  State<RentalPropertiesScreen> createState() => _RentalPropertiesScreenState();
}

class _RentalPropertiesScreenState extends State<RentalPropertiesScreen> {
  final List<String> _propertyTypes = [
    'apartment',
    'rental_compound',
    'standalone_house',
    'hostel',
    'commercial_building',
    'mixed_use',
    'office_space',
    'shop_units'
  ];

  final TextEditingController _searchController = TextEditingController();
  String? _selectedStatus;
  String? _selectedType;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadProperties();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadProperties() {
    context.read<RentalProvider>().fetchPropertiesWithPagination(
          search: _searchQuery.isNotEmpty ? _searchQuery : null,
          status: _selectedStatus,
        );
  }

  void _onSearchChanged(String query) {
    setState(() => _searchQuery = query);
    context.read<RentalProvider>().resetPagination();
    _loadProperties();
  }

  void _applyFilter({String? status, String? type}) {
    setState(() {
      _selectedStatus = status;
      _selectedType = type;
    });
    context.read<RentalProvider>().resetPagination();
    _loadProperties();
  }

  void _clearFilters() {
    setState(() {
      _searchQuery = '';
      _selectedStatus = null;
      _selectedType = null;
      _searchController.clear();
    });
    context.read<RentalProvider>().resetPagination();
    _loadProperties();
  }

  @override
  Widget build(BuildContext context) {
    final rentalProvider = context.watch<RentalProvider>();
    final properties = rentalProvider.properties;
    const cyberCyan = Color(0xFF00E5FF);

    return StarfieldBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            LocalizationService.instance.translate('properties').toUpperCase(),
            style: TextStyle(
              color: Colors.white,
              fontSize: 18.sp,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.w,
            ),
          ),
          centerTitle: false,
          actions: [
            IconButton(
              icon: Icon(Icons.add_circle_outline, color: cyberCyan, size: 28.sp),
              onPressed: () => _showAddPropertyDialog(context),
            ),
            SizedBox(width: 8.w),
          ],
        ),
        body: Column(
          children: [
            _buildSearchAndFilter(cyberCyan),
            Expanded(
              child: rentalProvider.isLoading && properties.isEmpty
                  ? Center(
                      child: CircularProgressIndicator(color: cyberCyan))
                  : properties.isEmpty
                      ? _buildEmptyState(cyberCyan)
                      : _buildPropertyList(properties, cyberCyan),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchAndFilter(Color cyberCyan) {
    return Container(
      padding: EdgeInsets.all(16.w),
      child: Column(
        children: [
          // Search Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(16.r),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16.r),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: "${LocalizationService.instance.translate('search_properties')}...",
                    hintStyle: const TextStyle(color: Colors.white38),
                    prefixIcon: Icon(Icons.search, color: cyberCyan.withValues(alpha: 0.6)),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: Colors.white38),
                            onPressed: _clearFilters)
                        : null,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: 12.h),
          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip(LocalizationService.instance.translate('all'), null,
                    _selectedStatus == null && _selectedType == null),
                SizedBox(width: 8.w),
                _buildFilterChip(LocalizationService.instance.translate('active'), "active", _selectedStatus == "active"),
                SizedBox(width: 8.w),
                _buildFilterChip(
                    LocalizationService.instance.translate('inactive_2'), "inactive", _selectedStatus == "inactive"),
                SizedBox(width: 8.w),
                _buildFilterChip(LocalizationService.instance.translate('maintenance'), "under_maintenance",
                    _selectedStatus == "under_maintenance"),
                SizedBox(width: 8.w),
                _buildFilterChip(
                    LocalizationService.instance.translate('apartment'), "apartment", _selectedType == "apartment",
                    isType: true),
                SizedBox(width: 8.w),
                _buildFilterChip(LocalizationService.instance.translate('hostel'), "hostel", _selectedType == "hostel",
                    isType: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String? value, bool isSelected,
      {bool isType = false}) {
    return GestureDetector(
      onTap: () {
        if (isType) {
          _applyFilter(type: isSelected ? null : value);
        } else {
          _applyFilter(status: isSelected ? null : value);
        }
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: isSelected
              ? ThemeConstants.primaryOrange
              : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20.r),
          border: Border.all(
              color:
                  isSelected ? ThemeConstants.primaryOrange : Colors.white12),
        ),
        child: Text(label,
            style: TextStyle(
                color: Colors.white,
                fontSize: 12.sp,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
      ),
    );
  }

  Widget _buildEmptyState(Color cyberCyan) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(24.w),
            decoration: BoxDecoration(
              color: cyberCyan.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: cyberCyan.withValues(alpha: 0.1), blurRadius: 20, spreadRadius: 5)
              ],
            ),
            child: Icon(Icons.apartment, size: 64.sp, color: cyberCyan.withValues(alpha: 0.5)),
          ),
          SizedBox(height: 24.h),
          Text(
            LocalizationService.instance.translate('no_properties_found'),
            style: TextStyle(
                color: Colors.white,
                fontSize: 18.sp,
                fontWeight: FontWeight.w900,
                letterSpacing: 1),
          ),
          SizedBox(height: 8.h),
          Text(
            LocalizationService.instance.translate('click_the_button_above_to_add'),
            style: TextStyle(color: Colors.white38, fontSize: 13.sp),
          ),
        ],
      ),
    );
  }

  Widget _buildPropertyList(List properties, Color cyberCyan) {
    return ListView.builder(
      padding: EdgeInsets.all(16.w),
      itemCount: properties.length,
      itemBuilder: (context, index) {
        final property = properties[index] as Map<String, dynamic>;
        return _buildPropertyCard(property, cyberCyan);
      },
    );
  }

  Widget _buildPropertyCard(Map<String, dynamic> property, Color cyberCyan) {
    final houses = property['houses'] as List? ?? [];
    final occupiedCount = houses.where((h) => (h as Map<String, dynamic>)['status'] == 'occupied').length;
    final status = property['status'] ?? 'active';

    Color statusColor;
    switch (status) {
      case 'active':
        statusColor = ThemeConstants.successGreen;
      case 'inactive':
        statusColor = Colors.white38;
      case 'under_maintenance':
        statusColor = ThemeConstants.warningAmber;
      case 'archived':
        statusColor = Colors.white24;
      default:
        statusColor = Colors.white54;
    }

    return Container(
      margin: EdgeInsets.only(bottom: 20.h),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24.r),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: EdgeInsets.all(20.w),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(24.r),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _showPropertyDetails(property),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(12.w),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [cyberCyan.withValues(alpha: 0.2), cyberCyan.withValues(alpha: 0.05)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16.r),
                            border: Border.all(color: cyberCyan.withValues(alpha: 0.2)),
                          ),
                          child: Icon(Icons.apartment, color: cyberCyan, size: 24.sp),
                        ),
                        SizedBox(width: 16.w),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (property['name'] ?? '').toString().toUpperCase(),
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16.sp,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.w,
                                ),
                              ),
                              SizedBox(height: 4.h),
                              Row(
                                children: [
                                  Icon(Icons.location_on_outlined, size: 14.sp, color: Colors.white38),
                                  SizedBox(width: 4.w),
                                  Expanded(
                                    child: Text(
                                      "${property['district'] ?? ''}, ${property['region'] ?? ''}",
                                      style: TextStyle(color: Colors.white38, fontSize: 12.sp),
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
                          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12.r),
                            border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            status.toString().toUpperCase(),
                            style: TextStyle(color: statusColor, fontSize: 9.sp, fontWeight: FontWeight.w900, letterSpacing: 1),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 20.h),
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatItem(Icons.home_outlined, "${houses.length}", LocalizationService.instance.translate('units').toUpperCase(), cyberCyan),
                        ),
                        Container(width: 1, height: 30.h, color: Colors.white.withValues(alpha: 0.1)),
                        Expanded(
                          child: _buildStatItem(Icons.person_outline, "$occupiedCount", LocalizationService.instance.translate('occupied').toUpperCase(), cyberCyan),
                        ),
                        Container(width: 1, height: 30.h, color: Colors.white.withValues(alpha: 0.1)),
                        Expanded(
                          child: _buildStatItem(Icons.meeting_room_outlined, "${houses.length - occupiedCount}", LocalizationService.instance.translate('vacant').toUpperCase(), 
                            houses.length - occupiedCount > 0 ? ThemeConstants.successGreen : Colors.white38,
                            isMain: true),
                        ),
                      ],
                    ),
                    SizedBox(height: 20.h),
                    Row(
                      children: [
                        if (property['property_type'] != null)
                          _buildInfoChip(_formatPropertyType(property['property_type']), cyberCyan),
                        SizedBox(width: 8.w),
                        if (property['default_billing_cycle'] != null)
                          _buildInfoChip(rentalValueLabel(property['default_billing_cycle'].toString()).toUpperCase(), Colors.white38),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String value, String label, Color color, {bool isMain = false}) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: isMain ? color : Colors.white,
            fontSize: 20.sp,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: 4.h),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 12.sp, color: color.withValues(alpha: 0.6)),
            SizedBox(width: 4.w),
            Text(label, style: TextStyle(color: Colors.white38, fontSize: 9.sp, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          ],
        ),
      ],
    );
  }

  Widget _buildInfoChip(String label, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 10.sp, fontWeight: FontWeight.bold),
      ),
    );
  }

  String _formatPropertyType(String type) => rentalValueLabel(type);

  void _showAddPropertyDialog(BuildContext context) {
    final nameController = TextEditingController();
    final addressController = TextEditingController();
    final blocksController = TextEditingController(text: "1");
    final housesController = TextEditingController(text: "0");
    final rentController = TextEditingController(text: "0");

    String? selectedRegion;
    String? selectedDistrict;
    String? selectedWard;
    String? selectedStreet;
    String? selectedPlace;
    String selectedType = 'apartment';
    String selectedBillingCycle = 'monthly';
    String selectedCurrency = 'TZS';

    const cyberCyan = Color(0xFF00E5FF);
    final primaryOrange = ThemeConstants.primaryOrange;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.9,
        decoration: BoxDecoration(
          color: const Color(0xFF001219), // Deeper dark for the modal
          borderRadius: BorderRadius.only(
              topLeft: Radius.circular(32.r), topRight: Radius.circular(32.r)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Column(
          children: [
            Container(
              margin: EdgeInsets.only(top: 12.h),
              width: 40.w,
              height: 4.h,
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2.r)),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(24.w, 20.h, 24.w, 10.h),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("ADD PROPERTY",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 20.sp,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.w)),
                  IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white54)),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: StatefulBuilder(
                  builder: (context, setState) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Section 1: Basic Information
                      _buildSectionPlate(
                        icon: Icons.info_outline,
                        title: LocalizationService.instance.translate('basic_information'),
                        accentColor: primaryOrange,
                        children: [
                          _buildModernInput(
                            controller: nameController,
                            label: "${LocalizationService.instance.translate('property_name')} *",
                            icon: Icons.apartment,
                            cyberCyan: cyberCyan,
                          ),
                          SizedBox(height: 16.h),
                          _buildModernDropdown(
                            label: LocalizationService.instance.translate('property_type'),
                            value: selectedType,
                            items: _propertyTypes,
                            onChanged: (v) => setState(() => selectedType = v),
                            formatter: _formatPropertyType,
                            cyberCyan: cyberCyan,
                          ),
                          SizedBox(height: 16.h),
                          _buildModernInput(
                            controller: addressController,
                            label: LocalizationService.instance.translate('description'),
                            icon: Icons.description_outlined,
                            cyberCyan: cyberCyan,
                            maxLines: 3,
                          ),
                        ],
                      ),
                      
                      SizedBox(height: 24.h),
                      
                      // Section 2: Location
                      _buildSectionPlate(
                        icon: Icons.location_on_outlined,
                        title: LocalizationService.instance.translate('location'),
                        accentColor: primaryOrange,
                        children: [
                          LocationSelector(
                            onChanged: (region, district, ward, street, place) {
                              selectedRegion = region;
                              selectedDistrict = district;
                              selectedWard = ward;
                              selectedStreet = street;
                              selectedPlace = place;
                            },
                          ),
                          SizedBox(height: 16.h),
                          _buildModernInput(
                            controller: addressController, // Reusing address for clarity
                            label: "${LocalizationService.instance.translate('specific_address')} *",
                            icon: Icons.home_outlined,
                            cyberCyan: cyberCyan,
                          ),
                        ],
                      ),

                      SizedBox(height: 24.h),

                      // Section 3: Configuration
                      _buildSectionPlate(
                        icon: Icons.settings_outlined,
                        title: LocalizationService.instance.translate('configuration'),
                        accentColor: primaryOrange,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _buildModernInput(
                                  controller: blocksController,
                                  label: LocalizationService.instance.translate('blocks'),
                                  icon: Icons.grid_view,
                                  cyberCyan: cyberCyan,
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                              SizedBox(width: 12.w),
                              Expanded(
                                child: _buildModernInput(
                                  controller: housesController,
                                  label: LocalizationService.instance.translate('total_units'),
                                  icon: Icons.home,
                                  cyberCyan: cyberCyan,
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 16.h),
                          Row(
                            children: [
                              Expanded(
                                child: _buildModernDropdown(
                                  label: LocalizationService.instance.translate('billing_cycle'),
                                  value: selectedBillingCycle,
                                  items: ["monthly", "quarterly", "yearly"],
                                  onChanged: (v) => setState(() => selectedBillingCycle = v),
                                  formatter: (v) => rentalValueLabel(v).toUpperCase(),
                                  cyberCyan: cyberCyan,
                                ),
                              ),
                              SizedBox(width: 12.w),
                              Expanded(
                                child: _buildModernDropdown(
                                  label: LocalizationService.instance.translate('currency'),
                                  value: selectedCurrency,
                                  items: ["TZS", "USD"],
                                  onChanged: (v) => setState(() => selectedCurrency = v),
                                  formatter: (v) => v,
                                  cyberCyan: cyberCyan,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),

                      SizedBox(height: 32.h),

                      // Save Button
                      GestureDetector(
                        onTap: () async {
                          if (nameController.text.isNotEmpty) {
                            final provider = context.read<RentalProvider>();
                            await provider.addProperty({
                              'name': nameController.text,
                              'property_type': selectedType,
                              'address': addressController.text.trim(),
                              'region': selectedRegion,
                              'district': selectedDistrict,
                              'ward': selectedWard,
                              'street': selectedStreet,
                              'place': selectedPlace,
                              'total_blocks': int.tryParse(blocksController.text) ?? 1,
                              'total_units': int.tryParse(housesController.text) ?? 0,
                              'default_billing_cycle': selectedBillingCycle,
                              'currency': selectedCurrency,
                              'default_rent_amount': double.tryParse(rentController.text) ?? 0.0,
                              'default_deposit_amount': 0.0,
                            });
                            if (context.mounted) Navigator.pop(context);
                          }
                        },
                        child: Container(
                          height: 60.h,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [primaryOrange, const Color(0xFFFF9100)],
                            ),
                            borderRadius: BorderRadius.circular(16.r),
                            boxShadow: [
                              BoxShadow(color: primaryOrange.withValues(alpha: 0.3), blurRadius: 15, offset: const Offset(0, 5))
                            ],
                          ),
                          child: Center(
                            child: Text(
                              "SAVE PROPERTY",
                              style: TextStyle(color: Colors.white, fontSize: 16.sp, fontWeight: FontWeight.w900, letterSpacing: 2),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 40.h),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionPlate({
    required IconData icon,
    required String title,
    required List<Widget> children,
    required Color accentColor,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(24.r),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 8.h),
            child: Row(
              children: [
                Icon(icon, color: accentColor, size: 20.sp),
                SizedBox(width: 8.w),
                Text(
                  title,
                  style: TextStyle(color: Colors.white, fontSize: 15.sp, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  Widget _buildModernInput({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required Color cyberCyan,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.white38, fontSize: 12.sp, fontWeight: FontWeight.w600)),
        SizedBox(height: 8.h),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            maxLines: maxLines,
            style: TextStyle(color: Colors.white, fontSize: 14.sp),
            decoration: InputDecoration(
              prefixIcon: Icon(icon, color: cyberCyan.withValues(alpha: 0.4), size: 20.sp),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildModernDropdown({
    required String label,
    required String value,
    required List<String> items,
    required Function(String) onChanged,
    required String Function(String) formatter,
    required Color cyberCyan,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.white38, fontSize: 12.sp, fontWeight: FontWeight.w600)),
        SizedBox(height: 8.h),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12.w),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: (items.contains(value)) ? value : null,
              isExpanded: true,
              dropdownColor: ThemeConstants.primaryBlue,
              style: TextStyle(color: Colors.white, fontSize: 14.sp),
              icon: Icon(Icons.keyboard_arrow_down, color: cyberCyan.withValues(alpha: 0.4)),
              items: items
                  .map((item) => DropdownMenuItem(
                        value: item,
                        child: Text(formatter(item)),
                      ))
                  .toList(),
              onChanged: (v) => onChanged(v ?? items.first),
            ),
          ),
        ),
      ],
    );
  }


  void _showAddHouseDialog(BuildContext context, String propertyId) {
    final houseNumberController = TextEditingController();
    final rentController = TextEditingController();
    final depositController = TextEditingController(text: "0");
    final electricityController = TextEditingController();
    final waterController = TextEditingController();
    String selectedType = 'room';
    String selectedStatus = 'vacant';

    const cyberCyan = Color(0xFF00E5FF);
    final primaryOrange = ThemeConstants.primaryOrange;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: BoxDecoration(
          color: const Color(0xFF001219),
          borderRadius: BorderRadius.only(
              topLeft: Radius.circular(32.r), topRight: Radius.circular(32.r)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Column(
          children: [
            Container(
              margin: EdgeInsets.only(top: 12.h),
              width: 40.w,
              height: 4.h,
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2.r)),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(24.w, 20.h, 24.w, 10.h),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("ADD HOUSE/UNIT",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 20.sp,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.w)),
                  IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white54)),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: StatefulBuilder(
                  builder: (context, setState) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionPlate(
                        icon: Icons.door_front_door_outlined,
                        title: LocalizationService.instance.translate('unit_information'),
                        accentColor: primaryOrange,
                        children: [
                          _buildModernInput(
                            controller: houseNumberController,
                            label: "${LocalizationService.instance.translate('house_unit_number')} *",
                            icon: Icons.numbers,
                            cyberCyan: cyberCyan,
                          ),
                          SizedBox(height: 16.h),
                          Row(
                            children: [
                              Expanded(
                                child: _buildModernDropdown(
                                    label: LocalizationService.instance.translate('type'),
                                    value: selectedType,
                                    items: ['room', 'apartment', 'studio', 'commercial', 'bedsitter', 'one_bedroom'],
                                    onChanged: (v) => setState(() => selectedType = v),
                                    formatter: (v) => rentalValueLabel(v).toUpperCase(),
                                    cyberCyan: cyberCyan),
                              ),
                              SizedBox(width: 12.w),
                              Expanded(
                                child: _buildModernDropdown(
                                    label: LocalizationService.instance.translate('status'),
                                    value: selectedStatus,
                                    items: ['vacant', 'occupied', 'maintenance'],
                                    onChanged: (v) => setState(() => selectedStatus = v),
                                    formatter: (v) => rentalValueLabel(v).toUpperCase(),
                                    cyberCyan: cyberCyan),
                              ),
                            ],
                          ),
                        ],
                      ),
                      
                      SizedBox(height: 24.h),

                      _buildSectionPlate(
                        icon: Icons.payments_outlined,
                        title: LocalizationService.instance.translate('financials'),
                        accentColor: primaryOrange,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _buildModernInput(
                                  controller: rentController,
                                  label: "${LocalizationService.instance.translate('rent_monthly')} *",
                                  icon: Icons.price_change_outlined,
                                  cyberCyan: cyberCyan,
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                              SizedBox(width: 12.w),
                              Expanded(
                                child: _buildModernInput(
                                  controller: depositController,
                                  label: LocalizationService.instance.translate('deposit'),
                                  icon: Icons.account_balance_wallet_outlined,
                                  cyberCyan: cyberCyan,
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),

                      SizedBox(height: 24.h),

                      _buildSectionPlate(
                        icon: Icons.bolt_outlined,
                        title: LocalizationService.instance.translate('utilities'),
                        accentColor: primaryOrange,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _buildModernInput(
                                  controller: electricityController,
                                  label: LocalizationService.instance.translate('electricity_meter'),
                                  icon: Icons.electric_bolt,
                                  cyberCyan: cyberCyan,
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                              SizedBox(width: 12.w),
                              Expanded(
                                child: _buildModernInput(
                                  controller: waterController,
                                  label: LocalizationService.instance.translate('water_meter'),
                                  icon: Icons.water_drop,
                                  cyberCyan: cyberCyan,
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),

                      SizedBox(height: 32.h),

                      GestureDetector(
                        onTap: () async {
                          if (houseNumberController.text.isNotEmpty && rentController.text.isNotEmpty) {
                            final provider = context.read<RentalProvider>();
                            await provider.addHouse(propertyId, {
                              'house_number': houseNumberController.text,
                              'rent_amount': double.tryParse(rentController.text) ?? 0,
                              'deposit_amount': double.tryParse(depositController.text) ?? 0,
                              'type': selectedType,
                              'status': selectedStatus,
                            });
                            if (context.mounted) Navigator.pop(context);
                          }
                        },
                        child: Container(
                          height: 60.h,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [primaryOrange, const Color(0xFFFF9100)],
                            ),
                            borderRadius: BorderRadius.circular(16.r),
                            boxShadow: [
                              BoxShadow(color: primaryOrange.withValues(alpha: 0.3), blurRadius: 15, offset: const Offset(0, 5))
                            ],
                          ),
                          child: Center(
                            child: Text(
                              "ADD HOUSE",
                              style: TextStyle(color: Colors.white, fontSize: 16.sp, fontWeight: FontWeight.w900, letterSpacing: 2),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 40.h),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPropertyDetails(Map<String, dynamic> property) {
    final houses = property['houses'] as List? ?? [];
    const cyberCyan = Color(0xFF00E5FF);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: const Color(0xFF001219),
          borderRadius: BorderRadius.only(
              topLeft: Radius.circular(32.r), topRight: Radius.circular(32.r)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Column(
          children: [
            Container(
              margin: EdgeInsets.only(top: 12.h),
              width: 40.w,
              height: 4.h,
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2.r)),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(24.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(16.w),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [cyberCyan.withValues(alpha: 0.2), cyberCyan.withValues(alpha: 0.05)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16.r),
                            border: Border.all(color: cyberCyan.withValues(alpha: 0.2)),
                          ),
                          child: Icon(Icons.apartment, color: cyberCyan, size: 32.sp),
                        ),
                        SizedBox(width: 16.w),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text((property['name'] ?? '').toString().toUpperCase(),
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 20.sp,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.w)),
                              Text("${property['address'] ?? ''}",
                                  style: TextStyle(
                                      color: Colors.white38, fontSize: 13.sp)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 24.h),
                    
                    _buildSectionPlate(
                      icon: Icons.location_on_outlined,
                      title: LocalizationService.instance.translate('location_details'),
                      accentColor: cyberCyan,
                      children: [
                        _buildDetailRow(LocalizationService.instance.translate('region'), property['region'] ?? '-'),
                        _buildDetailRow(LocalizationService.instance.translate('district'), property['district'] ?? '-'),
                        _buildDetailRow(LocalizationService.instance.translate('ward'), property['ward'] ?? '-'),
                        _buildDetailRow(LocalizationService.instance.translate('street_2'), property['street'] ?? '-'),
                        _buildDetailRow(LocalizationService.instance.translate('place_label'), property['place'] ?? '-'),
                      ],
                    ),

                    SizedBox(height: 16.h),

                    _buildSectionPlate(
                      icon: Icons.settings_outlined,
                      title: LocalizationService.instance.translate('management'),
                      accentColor: cyberCyan,
                      children: [
                        _buildDetailRow(LocalizationService.instance.translate('type'), _formatPropertyType(property['property_type'] ?? 'N/A')),
                        _buildDetailRow(LocalizationService.instance.translate('lipisha'), (property['default_billing_cycle'] as String?) != null ? rentalValueLabel(property['default_billing_cycle'] as String?).toUpperCase() : '-'),
                        _buildDetailRow(LocalizationService.instance.translate('default_rent'), "TSh ${property['default_rent_amount'] ?? 0}"),
                        _buildDetailRow(LocalizationService.instance.translate('status'), (property['status'] as String?) != null ? rentalValueLabel(property['status'] as String?).toUpperCase() : LocalizationService.instance.translate('active').toUpperCase()),
                      ],
                    ),

                    SizedBox(height: 24.h),
                    
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(LocalizationService.instance.translateWith('units_2', <Object?>[houses.length]).toUpperCase(),
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 18.sp,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1)),
                        IconButton(
                          onPressed: () {
                            Navigator.pop(context);
                            _showAddHouseDialog(context, property['id']);
                          },
                          icon: Icon(Icons.add_circle_outline, color: cyberCyan, size: 24.sp),
                        ),
                      ],
                    ),
                    SizedBox(height: 12.h),
                    if (houses.isEmpty)
                      Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 32.h),
                          child: Column(
                            children: [
                              Icon(Icons.home_work_outlined, size: 48.sp, color: Colors.white10),
                              SizedBox(height: 12.h),
                              Text(LocalizationService.instance.translate('no_units_registered_yet'), style: TextStyle(color: Colors.white10, fontSize: 13.sp)),
                            ],
                          ),
                        ),
                      )
                    else
                      ...houses.map((h) => _buildHouseItem(h as Map<String, dynamic>, cyberCyan)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.white38, fontSize: 14.sp, fontWeight: FontWeight.w600)),
          Text(value,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _buildHouseItem(Map<String, dynamic> house, Color cyberCyan) {
    final status = house['status'] ?? 'vacant';
    Color statusColor;
    switch (status) {
      case 'occupied':
        statusColor = ThemeConstants.successGreen;
      case 'maintenance':
        statusColor = ThemeConstants.warningAmber;
      default:
        statusColor = Colors.white38;
    }

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(10.w),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: statusColor.withValues(alpha: 0.2)),
              ),
              child: Icon(Icons.door_front_door_outlined, color: statusColor, size: 20.sp),
            ),
            SizedBox(width: 16.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(house['house_number'] ?? '',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w900)),
                  Text(LocalizationService.instance.translateWith('tsh_month', <Object?>[house['rent_amount']]),
                      style: TextStyle(color: Colors.white38, fontSize: 11.sp, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: statusColor.withValues(alpha: 0.2)),
              ),
              child: Text(
                status.toString().toUpperCase(),
                style: TextStyle(
                    color: statusColor,
                    fontSize: 9.sp,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
