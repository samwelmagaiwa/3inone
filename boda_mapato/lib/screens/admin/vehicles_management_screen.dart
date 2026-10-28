// ignore_for_file: avoid_dynamic_calls, unused_element
import "package:flutter/material.dart";
import "package:flutter_screenutil/flutter_screenutil.dart";
import "package:provider/provider.dart";

import "../../constants/theme_constants.dart";
import "../../models/vehicle.dart";
import "../../services/api_service.dart";
import "../../services/localization_service.dart";
import "../../utils/responsive_helper.dart";
import "../../widgets/branch_picker_field.dart";

class VehiclesManagementScreen extends StatefulWidget {
  const VehiclesManagementScreen({super.key});

  @override
  State<VehiclesManagementScreen> createState() =>
      _VehiclesManagementScreenState();
}

class _VehiclesManagementScreenState extends State<VehiclesManagementScreen>
    with TickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  List<Vehicle> _vehicles = <Vehicle>[];
  List<Vehicle> _filteredVehicles = <Vehicle>[];
  String _searchQuery = "";
  String _selectedFilter = "all"; // all, active, inactive, assigned, unassigned
  int _currentPage = 1;
  bool _hasMoreData = true;
  bool _isLoadingMore = false;

  // Using theme constants for colors

  @override
  void initState() {
    super.initState();
    _initializeAndLoadVehicles();
  }

  Future<void> _initializeAndLoadVehicles() async {
    // Initialize API service with stored token
    await _apiService.initialize();
    // Load vehicles
    await _loadVehicles();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadVehicles({final bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _isLoading = true;
        _currentPage = 1;
        _hasMoreData = true;
        _vehicles.clear();
        _filteredVehicles.clear();
      });
    } else if (!_hasMoreData || _isLoadingMore) {
      return;
    }

    setState(() {
      if (_currentPage == 1) {
        _isLoading = true;
      } else {
        _isLoadingMore = true;
      }
    });

    try {
      final Map<String, dynamic> response = await _apiService.getVehicles(
        page: _currentPage,
      );

      // Handle the actual response structure: {status, message, data: {data: [...], pagination: {...}}}
      List<dynamic> vehiclesData;
      if (response["data"] is Map<String, dynamic>) {
        // Paginated response: data contains another object with "data" key
        vehiclesData = response["data"]["data"] ?? <Map<String, dynamic>>[];
      } else if (response["data"] is List) {
        // Direct list response
        vehiclesData = response["data"];
      } else {
        vehiclesData = <Map<String, dynamic>>[];
      }
      final List<Vehicle> newVehicles = vehiclesData
          .map((final json) => Vehicle.fromJson(json as Map<String, dynamic>))
          .toList();

      if (!mounted) return;
      setState(() {
        if (_currentPage == 1) {
          _vehicles = newVehicles;
        } else {
          _vehicles.addAll(newVehicles);
        }

        // Check if there"s more data
        _hasMoreData = newVehicles.length >= 20;
        _currentPage++;
      });

      _filterVehicles();
    } on Exception catch (e) {
      if (mounted) {
        _showErrorSnackBar(LocalizationService.instance.translateWith('error_loading_vehicles', <Object?>[e]));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  void _filterVehicles() {
    setState(() {
      _filteredVehicles = _vehicles.where((final Vehicle vehicle) {
        final bool matchesSearch = _searchQuery.isEmpty ||
            vehicle.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            vehicle.plateNumber
                .toLowerCase()
                .contains(_searchQuery.toLowerCase()) ||
            vehicle.type.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            (vehicle.driverName
                    ?.toLowerCase()
                    .contains(_searchQuery.toLowerCase()) ??
                false);

        final bool matchesFilter = _selectedFilter == "all" ||
            (_selectedFilter == "active" && vehicle.isActive) ||
            (_selectedFilter == "inactive" && !vehicle.isActive) ||
            (_selectedFilter == "assigned" && vehicle.driverName != null) ||
            (_selectedFilter == "unassigned" && vehicle.driverName == null);

        return matchesSearch && matchesFilter;
      }).toList();
    });
  }

  void _onSearchChanged(final String query) {
    setState(() {
      _searchQuery = query;
    });
    _filterVehicles();
  }

  void _onFilterChanged(final String filter) {
    setState(() {
      _selectedFilter = filter;
    });
    _filterVehicles();
  }

  void _showErrorSnackBar(final String message) {
    ThemeConstants.showErrorSnackBar(context, message);
  }

  void _showSuccessSnackBar(final String message) {
    ThemeConstants.showSuccessSnackBar(context, message);
  }

  @override
  Widget build(final BuildContext context) {
    ResponsiveHelper.init(context);
    return Consumer<LocalizationService>(
      builder: (context, localizationService, child) => Scaffold(
        backgroundColor: ThemeConstants
            .primaryBlue, // Solid blue background like drivers page
        appBar: ThemeConstants.buildResponsiveAppBar(
            context, localizationService.translate('manage_vehicles'),
            actions: <Widget>[
              IconButton(
                onPressed: () => _loadVehicles(refresh: true),
                icon: const Icon(Icons.refresh),
              ),
              PopupMenuButton<String>(
                onSelected: (final String value) {
                  switch (value) {
                    case "export":
                      _exportVehicles();
                    case "import":
                      _importVehicles();
                  }
                },
                itemBuilder: (final BuildContext context) =>
                    <PopupMenuEntry<String>>[
                  PopupMenuItem(
                    value: "export",
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.download,
                            color: ThemeConstants.primaryBlue),
                        const SizedBox(width: 8),
                        Text(localizationService.translate('export_data')),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: "import",
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.upload, color: Colors.orange),
                        const SizedBox(width: 8),
                        Text(localizationService.translate('import_data')),
                      ],
                    ),
                  ),
                ],
              ),
            ]),
        body: DecoratedBox(
          decoration: const BoxDecoration(color: ThemeConstants.primaryBlue),
          child: SafeArea(
            child: _isLoading
                ? ThemeConstants.buildResponsiveLoadingWidget(context)
                : _buildMainContent(),
          ),
        ),
        floatingActionButton: _buildFloatingActionButton(),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() => AppBar(
        title: Text(
          LocalizationService.instance.translate('manage_vehicles'),
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: ThemeConstants.primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            color: ThemeConstants.primaryBlue, // Solid blue background
          ),
        ),
        actions: <Widget>[
          IconButton(
            onPressed: () => _loadVehicles(refresh: true),
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            onSelected: (final String value) {
              switch (value) {
                case "export":
                  _exportVehicles();
                case "import":
                  _importVehicles();
              }
            },
            itemBuilder: (final BuildContext context) =>
                <PopupMenuEntry<String>>[
              PopupMenuItem(
                value: "export",
                child: Row(
                  children: <Widget>[
                    Icon(Icons.download, color: ThemeConstants.primaryBlue),
                    SizedBox(width: 8),
                    Text(LocalizationService.instance.translate('export_data')),
                  ],
                ),
              ),
              PopupMenuItem(
                value: "import",
                child: Row(
                  children: <Widget>[
                    Icon(Icons.upload, color: Colors.orange),
                    SizedBox(width: 8),
                    Text(LocalizationService.instance.translate('import_data')),
                  ],
                ),
              ),
            ],
          ),
        ],
      );

  Widget _buildLoadingScreen() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const CircularProgressIndicator(),
            SizedBox(height: 16.h),
            Text(
              "${LocalizationService.instance.translate('loading_vehicles')}...",
              style: TextStyle(
                fontSize: 16,
                color: Colors.black54,
              ),
            ),
          ],
        ),
      );

  Widget _buildMainContent() => Column(
        children: <Widget>[
          _buildSearchAndFilter(),
          _buildStatsCards(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _loadVehicles(refresh: true),
              color: ThemeConstants.textPrimary, // White refresh indicator
              backgroundColor: ThemeConstants.primaryBlue, // Blue background
              child: _filteredVehicles.isEmpty
                  ? _buildEmptyState()
                  : _buildVehiclesList(),
            ),
          ),
        ],
      );

  Widget _buildSearchAndFilter() => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            // Search bar - Glass styled like drivers page
            DecoratedBox(
              decoration: BoxDecoration(
                color: ThemeConstants.primaryBlue
                    .withOpacity(0.3), // Glass effect like drivers page
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                ),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                style: ThemeConstants.bodyStyle, // White text
                decoration: InputDecoration(
                  hintText: "${LocalizationService.instance.translate('search_vehicle_number_type_or_driver')}...",
                  hintStyle: ThemeConstants.captionStyle.copyWith(
                    color: ThemeConstants.textSecondary,
                  ),
                  prefixIcon: const Icon(
                    Icons.search,
                    color: Colors.white,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          onPressed: () {
                            _searchController.clear();
                            _onSearchChanged("");
                          },
                          icon: const Icon(
                            Icons.clear,
                            color: Colors.white,
                          ),
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  filled: true,
                  fillColor: Colors.transparent,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Filter chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: <Widget>[
                  _buildFilterChip("all", LocalizationService.instance.translate('all_3'), _vehicles.length),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    "active",
                    LocalizationService.instance.translate('active'),
                    _vehicles.where((final Vehicle v) => v.isActive).length,
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    "inactive",
                    LocalizationService.instance.translate('inactive_driver'),
                    _vehicles.where((final Vehicle v) => !v.isActive).length,
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    "assigned",
                    LocalizationService.instance.translate('assigned'),
                    _vehicles
                        .where((final Vehicle v) => v.driverName != null)
                        .length,
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    "unassigned",
                    LocalizationService.instance.translate('unassigned'),
                    _vehicles
                        .where((final Vehicle v) => v.driverName == null)
                        .length,
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _buildFilterChip(
    final String value,
    final String label,
    final int count,
  ) {
    final bool isSelected = _selectedFilter == value;
    return FilterChip(
      selected: isSelected,
      label: Text(
        "$label ($count)",
        style: const TextStyle(
          color: Colors
              .white, // Always white text for visibility like drivers page
          fontWeight: FontWeight.w500,
        ),
      ),
      backgroundColor: ThemeConstants.primaryBlue
          .withOpacity(0.3), // Glass effect like drivers page
      selectedColor:
          ThemeConstants.primaryOrange, // Orange selection like drivers page
      checkmarkColor: Colors.white,
      side: BorderSide(
        color: isSelected
            ? ThemeConstants.primaryOrange
            : Colors.white.withOpacity(0.5),
      ),
      onSelected: (final bool selected) {
        if (selected) {
          _onFilterChanged(value);
        }
      },
    );
  }

  Widget _buildStatsCards() {
    final int activeVehicles =
        _vehicles.where((final Vehicle v) => v.isActive).length;
    final int assignedVehicles =
        _vehicles.where((final Vehicle v) => v.driverName != null).length;
    final double utilizationRate =
        _vehicles.isNotEmpty ? (assignedVehicles / _vehicles.length * 100) : 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _buildStatCard(
              title: LocalizationService.instance.translate('active_vehicles_2'),
              value: "$activeVehicles/${_vehicles.length}",
              icon: Icons.directions_car,
              color: ThemeConstants.successGreen,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              title: LocalizationService.instance.translate('assigned_to_drivers'),
              value: "$assignedVehicles/${_vehicles.length}",
              icon: Icons.assignment_ind,
              color: Colors.orange,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              title: LocalizationService.instance.translate('utilization_rate'),
              value: "${utilizationRate.toStringAsFixed(1)}%",
              icon: Icons.trending_up,
              color: Colors.amber,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required final String title,
    required final String value,
    required final IconData icon,
    required final Color color,
  }) =>
      ThemeConstants.buildGlassCardStatic(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: <Widget>[
              Icon(
                icon,
                color: color,
                size: 24,
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: ThemeConstants.bodyStyle.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: ThemeConstants.captionStyle.copyWith(
                  fontSize: 10,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );

  Widget _buildEmptyState() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(
              Icons.directions_car_outlined,
              size: 80,
              color: ThemeConstants
                  .textSecondary, // Light text for blue background
            ),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty
                  ? LocalizationService.instance.translate('no_vehicle_found')
                  : LocalizationService.instance.translate('no_vehicles_yet'),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color:
                    ThemeConstants.textPrimary, // White text on blue background
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isNotEmpty
                  ? LocalizationService.instance.translate('try_searching_with_another_name')
                  : LocalizationService.instance.translate('register_your_first_vehicle'),
              style: const TextStyle(
                fontSize: 14,
                color: ThemeConstants
                    .textSecondary, // Light text on blue background
              ),
            ),
            const SizedBox(height: 24),
            if (_searchQuery.isEmpty)
              ElevatedButton.icon(
                onPressed: _showAddVehicleDialog,
                icon: const Icon(Icons.add, color: Colors.white),
                label: Text(
                  LocalizationService.instance.translate('register_vehicle'),
                  style: TextStyle(color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: ThemeConstants.primaryOrange,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
          ],
        ),
      );

  Widget _buildVehiclesList() => ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _filteredVehicles.length + (_hasMoreData ? 1 : 0),
        itemBuilder: (final BuildContext context, final int index) {
          if (index == _filteredVehicles.length) {
            // Load more indicator
            if (!_isLoadingMore) {
              // Schedule loading after this frame to avoid setState during build
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _loadVehicles();
              });
            }
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }

          final Vehicle vehicle = _filteredVehicles[index];
          return _buildVehicleCard(vehicle);
        },
      );

  Widget _buildVehicleCard(final Vehicle vehicle) {
    final bool isActive = vehicle.isActive;
    final bool isAssigned = vehicle.driverName != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ThemeConstants.buildGlassCardStatic(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  // Vehicle icon
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color:
                          isActive ? ThemeConstants.successGreen : Colors.grey,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Icon(
                      _getVehicleIcon(vehicle.type),
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Vehicle info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                vehicle.name,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: ThemeConstants
                                      .textPrimary, // White text on blue background
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isActive
                                    ? ThemeConstants.successGreen
                                        .withOpacity(0.3)
                                    : Colors.grey.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isActive
                                      ? ThemeConstants.successGreen
                                      : Colors.grey.shade400,
                                ),
                              ),
                              child: Text(
                                isActive ? LocalizationService.instance.translate('active').toUpperCase() : LocalizationService.instance.translate('inactive_driver').toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors
                                      .white, // White text for better contrast
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          vehicle.plateNumber,
                          style: const TextStyle(
                            fontSize: 14,
                            color: ThemeConstants
                                .textSecondary, // Light text on blue background
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: <Widget>[
                            Icon(
                              _getVehicleIcon(vehicle.type),
                              size: 16,
                              color: Colors.white, // White icon for contrast
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _getVehicleTypeDisplay(vehicle.type),
                              style: const TextStyle(
                                fontSize: 12,
                                color: ThemeConstants
                                    .textSecondary, // Light text on blue background
                              ),
                            ),
                            if (isAssigned) ...<Widget>[
                              const SizedBox(width: 16),
                              const Icon(
                                Icons.person,
                                size: 16,
                                color: Colors.white, // White icon for contrast
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  vehicle.driverName!,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: ThemeConstants
                                        .textSecondary, // Light text on blue background
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Actions
                  PopupMenuButton<String>(
                    icon: const Icon(
                      Icons.more_vert,
                      color: ThemeConstants.textPrimary, // White icon
                    ),
                    onSelected: (final String value) =>
                        _handleVehicleAction(value, vehicle),
                    itemBuilder: (final BuildContext context) =>
                        <PopupMenuEntry<String>>[
                      PopupMenuItem(
                        value: "view",
                        child: Row(
                          children: <Widget>[
                            Icon(Icons.visibility,
                                color: ThemeConstants.primaryBlue),
                            SizedBox(width: 8),
                            Text(LocalizationService.instance.translate('view')),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: "edit",
                        child: Row(
                          children: <Widget>[
                            Icon(Icons.edit, color: Colors.orange),
                            SizedBox(width: 8),
                            Text(LocalizationService.instance.translate('edit')),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: isAssigned ? "unassign" : "assign",
                        child: Row(
                          children: <Widget>[
                            Icon(
                              isAssigned
                                  ? Icons.person_remove
                                  : Icons.person_add,
                              color: isAssigned
                                  ? Colors.amber
                                  : ThemeConstants.successGreen,
                            ),
                            const SizedBox(width: 8),
                            Text(isAssigned ? LocalizationService.instance.translate('remove_driver') : LocalizationService.instance.translate('assign_driver')),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: isActive ? "deactivate" : "activate",
                        child: Row(
                          children: <Widget>[
                            Icon(
                              isActive ? Icons.block : Icons.check_circle,
                              color: isActive
                                  ? ThemeConstants.errorRed
                                  : ThemeConstants.successGreen,
                            ),
                            const SizedBox(width: 8),
                            Text(isActive ? LocalizationService.instance.translate('deactivate') : LocalizationService.instance.translate('activate')),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: "delete",
                        child: Row(
                          children: <Widget>[
                            Icon(Icons.delete, color: ThemeConstants.errorRed),
                            SizedBox(width: 8),
                            Text(LocalizationService.instance.translate('delete')),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (vehicle.description != null &&
                  vehicle.description!.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1), // Glass effect
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.2),
                    ),
                  ),
                  child: Text(
                    vehicle.description!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: ThemeConstants
                          .textSecondary, // Light text for consistency
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingActionButton() => FloatingActionButton.extended(
        onPressed: _showAddVehicleDialog,
        backgroundColor:
            ThemeConstants.primaryOrange, // Use theme orange like drivers page
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text(
          LocalizationService.instance.translate('register_vehicle'),
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      );

  IconData _getVehicleIcon(final String vehicleType) {
    switch (vehicleType.toLowerCase()) {
      case "bajaji":
        return Icons
            .directions_car; // three_wheeler not available, using car icon
      case "pikipiki":
        return Icons.motorcycle;
      case "gari":
        return Icons.directions_car;
      default:
        return Icons.directions_car;
    }
  }

  String _getVehicleTypeDisplay(final String vehicleType) {
    switch (vehicleType.toLowerCase()) {
      case "bajaji":
        return LocalizationService.instance.translate('vehicle_type_bajaji');
      case "pikipiki":
        return LocalizationService.instance.translate('vehicle_type_pikipiki');
      case "gari":
        return LocalizationService.instance.translate('vehicle_type_gari');
      default:
        return vehicleType;
    }
  }

  void _handleVehicleAction(final String action, final Vehicle vehicle) {
    switch (action) {
      case "view":
        _showVehicleDetails(vehicle);
      case "edit":
        _showEditVehicleDialog(vehicle);
      case "assign":
        _showAssignDriverDialog(vehicle);
      case "unassign":
        _confirmUnassignDriver(vehicle);
      case "activate":
      case "deactivate":
        _toggleVehicleStatus(vehicle);
      case "delete":
        _confirmDeleteVehicle(vehicle);
    }
  }

  void _showVehicleDetails(final Vehicle vehicle) {
    showDialog(
      context: context,
      builder: (final BuildContext context) => AlertDialog(
        backgroundColor:
            ThemeConstants.primaryBlue, // Blue background like other cards
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          LocalizationService.instance.translateWith('details_of', <Object?>[vehicle.name]),
          style: const TextStyle(
            color: ThemeConstants.textPrimary, // White text on blue background
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _buildDetailRow("${LocalizationService.instance.translate('name')}:", vehicle.name),
              _buildDetailRow("${LocalizationService.instance.translate('vehicle_number')}:", vehicle.plateNumber),
              _buildDetailRow("${LocalizationService.instance.translate('type')}:", _getVehicleTypeDisplay(vehicle.type)),
              _buildDetailRow("${LocalizationService.instance.translate('status')}:", vehicle.isActive ? LocalizationService.instance.translate('active') : LocalizationService.instance.translate('inactive_driver')),
              _buildDetailRow(
                "${LocalizationService.instance.translate('driver')}:",
                vehicle.driverName ?? LocalizationService.instance.translate('no_driver_assigned'),
              ),
              if (vehicle.description != null &&
                  vehicle.description!.isNotEmpty)
                _buildDetailRow("${LocalizationService.instance.translate('description')}:", vehicle.description!),
              _buildDetailRow("${LocalizationService.instance.translate('registered_on')}:", _formatDate(vehicle.createdAt)),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              LocalizationService.instance.translate('close'),
              style: TextStyle(
                color:
                    ThemeConstants.textPrimary, // White text on blue background
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(final String label, final String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 100,
              child: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  color: ThemeConstants
                      .textSecondary, // Light text on blue background
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: ThemeConstants
                      .textPrimary, // White text on blue background
                ),
              ),
            ),
          ],
        ),
      );

  String _formatDate(final DateTime date) =>
      "${date.day}/${date.month}/${date.year}";

  void _showAddVehicleDialog() {
    showDialog(
      context: context,
      builder: (final BuildContext context) => _AddVehicleDialog(
        onVehicleAdded: () {
          // Refresh the vehicles list after adding a new vehicle
          _loadVehicles(refresh: true);
        },
      ),
    );
  }

  void _showEditVehicleDialog(final Vehicle vehicle) {
    showDialog(
      context: context,
      builder: (final BuildContext context) => _EditVehicleDialog(
        vehicle: vehicle,
        onVehicleUpdated: (final Vehicle updated) {
          final int idx = _vehicles.indexWhere((final v) => v.id == updated.id);
          if (idx != -1) {
            setState(() => _vehicles[idx] = updated);
            _filterVehicles();
          } else {
            _loadVehicles(refresh: true);
          }
        },
      ),
    );
  }

  void _showAssignDriverDialog(final Vehicle vehicle) {
    showDialog(
      context: context,
      builder: (final BuildContext context) => _AssignDriverDialog(
        vehicle: vehicle,
        onAssigned: (final Vehicle updated) {
          final int idx = _vehicles.indexWhere((final v) => v.id == updated.id);
          if (idx != -1) {
            setState(() => _vehicles[idx] = updated);
            _filterVehicles();
          }
        },
      ),
    );
  }

  void _confirmUnassignDriver(final Vehicle vehicle) {
    showDialog(
      context: context,
      builder: (final BuildContext context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(LocalizationService.instance.translate('remove_driver')),
        content: Text(
          "${LocalizationService.instance.translateWith('are_you_sure_you_want_to', <Object?>[vehicle.driverName, vehicle.plateNumber])}?",
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(LocalizationService.instance.translate('no')),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await _apiService.unassignDriverFromVehicle(vehicle.id);
                if (!mounted) return;
                setState(() {
                  final int idx =
                      _vehicles.indexWhere((final v) => v.id == vehicle.id);
                  if (idx != -1) {
                    _vehicles[idx] = _vehicles[idx].copyWith();
                  }
                });
                _filterVehicles();
                _showSuccessSnackBar(
                    LocalizationService.instance.translateWith('driver_removed_from', <Object?>[vehicle.plateNumber]));
              } on Exception catch (e) {
                if (mounted) {
                  _showErrorSnackBar(LocalizationService.instance.translateWith('could_not_remove_the_driver', <Object?>[e]));
                }
              }
            },
            child: Text(
              LocalizationService.instance.translate('remove'),
              style: TextStyle(color: Colors.amber),
            ),
          ),
        ],
      ),
    );
  }

  void _toggleVehicleStatus(final Vehicle vehicle) {
    final bool isActive = vehicle.isActive;

    showDialog(
      context: context,
      builder: (final BuildContext context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(isActive ? LocalizationService.instance.translate('deactivate_vehicle') : LocalizationService.instance.translate('activate_vehicle')),
        content: Text(
          isActive
              ? "${LocalizationService.instance.translateWith('are_you_sure_you_want_to_2', <Object?>[vehicle.plateNumber])}?"
              : "${LocalizationService.instance.translateWith('are_you_sure_you_want_to_3', <Object?>[vehicle.plateNumber])}?",
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(LocalizationService.instance.translate('no')),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                final newActive = !isActive;
                await _apiService.updateVehicle(vehicle.id, <String, dynamic>{
                  "is_active": newActive,
                });
                if (!mounted) return;
                setState(() {
                  final int idx =
                      _vehicles.indexWhere((final v) => v.id == vehicle.id);
                  if (idx != -1) {
                    _vehicles[idx] =
                        _vehicles[idx].copyWith(isActive: newActive);
                  }
                });
                _filterVehicles();
                _showSuccessSnackBar(
                    newActive ? LocalizationService.instance.translate('vehicle_activated') : LocalizationService.instance.translate('vehicle_deactivated'));
              } on Exception catch (e) {
                if (mounted) {
                  _showErrorSnackBar(
                      LocalizationService.instance.translateWith('could_not_change_the_vehicle_status', <Object?>[e]));
                }
              }
            },
            child: Text(
              isActive ? LocalizationService.instance.translate('deactivate') : LocalizationService.instance.translate('activate'),
              style: TextStyle(
                color: isActive
                    ? ThemeConstants.errorRed
                    : ThemeConstants.successGreen,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteVehicle(final Vehicle vehicle) {
    showDialog(
      context: context,
      builder: (final BuildContext context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(LocalizationService.instance.translate('delete_vehicle')),
        content: Text(
          LocalizationService.instance.translateWith('are_you_sure_you_want_to_4', <Object?>[vehicle.plateNumber]),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(LocalizationService.instance.translate('no')),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await _apiService.deleteVehicle(vehicle.id);
                if (!mounted) return;
                setState(() =>
                    _vehicles.removeWhere((final v) => v.id == vehicle.id));
                _filterVehicles();
                _showSuccessSnackBar(LocalizationService.instance.translate('vehicle_deleted'));
              } on Exception catch (e) {
                if (mounted) {
                  _showErrorSnackBar(LocalizationService.instance.translateWith('could_not_delete_the_vehicle', <Object?>[e]));
                }
              }
            },
            child: Text(
              LocalizationService.instance.translate('delete'),
              style: TextStyle(color: ThemeConstants.errorRed),
            ),
          ),
        ],
      ),
    );
  }

  void _exportVehicles() {
    // TODO(dev): Implement export functionality
    ThemeConstants.showInfoSnackBar(context, LocalizationService.instance.translate('export_in_development'));
  }

  void _importVehicles() {
    // TODO(dev): Implement import functionality
    ThemeConstants.showInfoSnackBar(context, LocalizationService.instance.translate('import_in_development'));
  }
}

// Edit Vehicle Dialog
class _EditVehicleDialog extends StatefulWidget {
  const _EditVehicleDialog(
      {required this.vehicle, required this.onVehicleUpdated});
  final Vehicle vehicle;
  final void Function(Vehicle) onVehicleUpdated;

  @override
  State<_EditVehicleDialog> createState() => _EditVehicleDialogState();
}

class _EditVehicleDialogState extends State<_EditVehicleDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final ApiService _apiService = ApiService();

  late final TextEditingController _nameController;
  late final TextEditingController _plateController;
  late final TextEditingController _descController;
  late String _vehicleType;
  late bool _isActive;
  int? _branchId;
  bool _saving = false;

  final Map<String, String> _vehicleTypes = {
    'bajaji': LocalizationService.instance.translate('vehicle_type_bajaji'),
    'pikipiki': LocalizationService.instance.translate('vehicle_type_pikipiki'),
    'gari': LocalizationService.instance.translate('vehicle_type_gari'),
  };

  InputDecoration _inputDecoration(String label, {IconData? icon}) {
    final OutlineInputBorder border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.white.withOpacity(0.25)),
    );
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: ThemeConstants.textSecondary),
      prefixIcon:
          icon != null ? Icon(icon, color: ThemeConstants.textSecondary) : null,
      filled: true,
      fillColor: ThemeConstants.primaryBlue.withOpacity(0.35),
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide:
            const BorderSide(color: ThemeConstants.primaryOrange, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  @override
  void initState() {
    super.initState();
    final v = widget.vehicle;
    _nameController = TextEditingController(text: v.name);
    _plateController = TextEditingController(text: v.plateNumber);
    _descController = TextEditingController(text: v.description ?? '');
    _vehicleType = v.type;
    _isActive = v.isActive;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _plateController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final payload = <String, dynamic>{
        'name': _nameController.text.trim(),
        'plate_number': _plateController.text.trim().toUpperCase(),
        'type': _vehicleType,
        'description': _descController.text.trim().isEmpty
            ? null
            : _descController.text.trim(),
        'is_active': _isActive,
        'branch_id': _branchId,
      };
      await _apiService.updateVehicle(widget.vehicle.id, payload);
      final updated = widget.vehicle.copyWith(
        name: payload['name'] as String?,
        plateNumber: payload['plate_number'] as String?,
        type: payload['type'] as String?,
        description: payload['description'] as String?,
        branchId: _branchId,
        isActive: payload['is_active'] as bool?,
      );
      if (!mounted) return;
      Navigator.pop(context);
      widget.onVehicleUpdated(updated);
      ThemeConstants.showSuccessSnackBar(context, '${LocalizationService.instance.translate('vehicle_details_saved')}.');
    } on Exception catch (e) {
      if (!mounted) return;
      ThemeConstants.showErrorSnackBar(context, LocalizationService.instance.translateWith('error_2', <Object?>[e]));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: ThemeConstants.primaryBlue,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(LocalizationService.instance.translateWith('edit_2', <Object?>[widget.vehicle.name]),
          style: ThemeConstants.headingStyle),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                style: const TextStyle(color: ThemeConstants.textPrimary),
                decoration: _inputDecoration(LocalizationService.instance.translate('name'),
                    icon: Icons.drive_file_rename_outline),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? LocalizationService.instance.translate('enter_a_name') : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _plateController,
                style: const TextStyle(color: ThemeConstants.textPrimary),
                decoration: _inputDecoration(LocalizationService.instance.translate('vehicle_number'),
                    icon: Icons.confirmation_number),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? LocalizationService.instance.translate('enter_the_vehicle_number')
                    : null,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _vehicleType,
                dropdownColor: ThemeConstants.primaryBlue,
                style: const TextStyle(color: ThemeConstants.textPrimary),
                items: _vehicleTypes.entries
                    .map((e) =>
                        DropdownMenuItem(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (val) =>
                    setState(() => _vehicleType = val ?? _vehicleType),
                decoration:
                    _inputDecoration(LocalizationService.instance.translate('vehicle_type'), icon: Icons.category),
              ),
              const SizedBox(height: 8),
              BranchPickerField(service: 'transport', initialId: widget.vehicle.branchId, decoration: _inputDecoration(''), onChanged: (int? id) => _branchId = id),
              TextFormField(
                controller: _descController,
                style: const TextStyle(color: ThemeConstants.textPrimary),
                decoration:
                    _inputDecoration(LocalizationService.instance.translate('note_optional'), icon: Icons.notes),
                maxLines: 2,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                value: _isActive,
                title: Text(
                  '${LocalizationService.instance.translate('status')}: ${_isActive ? LocalizationService.instance.translate('active') : LocalizationService.instance.translate('inactive_driver')}',
                  style: const TextStyle(color: ThemeConstants.textPrimary),
                ),
                onChanged: (val) => setState(() => _isActive = val),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(LocalizationService.instance.translate('cancel_2'), style: TextStyle(color: Colors.white)),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(
              backgroundColor: ThemeConstants.primaryOrange,
              foregroundColor: Colors.white),
          child: _saving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(LocalizationService.instance.translate('save')),
        ),
      ],
    );
  }
}

// Assign Driver Dialog
class _AssignDriverDialog extends StatefulWidget {
  const _AssignDriverDialog({required this.vehicle, required this.onAssigned});
  final Vehicle vehicle;
  final void Function(Vehicle) onAssigned;

  @override
  State<_AssignDriverDialog> createState() => _AssignDriverDialogState();
}

class _AssignDriverDialogState extends State<_AssignDriverDialog> {
  final ApiService _apiService = ApiService();
  String? _selectedDriverId;
  String? _selectedDriverName;
  bool _loading = true;
  List<Map<String, String>> _drivers = <Map<String, String>>[];

  @override
  void initState() {
    super.initState();
    _loadDrivers();
  }

  Future<void> _loadDrivers() async {
    try {
      final res = await _apiService.getDrivers(limit: 50);
      final data = res['data'] ?? res;
      final List<dynamic> list = data is Map<String, dynamic>
          ? (data['data'] ?? data['drivers'] ?? [])
          : (data as List<dynamic>? ?? []);
      _drivers = list.map<Map<String, String>>((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return {
          'id': (m['id'] ?? '').toString(),
          'name': (m['name'] ?? '').toString(),
        };
      }).toList();
    } on Exception {
      _drivers = <Map<String, String>>[];
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _assign() async {
    if (_selectedDriverId == null) return;
    try {
      await _apiService.assignDriverToVehicle(
          vehicleId: widget.vehicle.id, driverId: _selectedDriverId!);
      final updated = widget.vehicle.copyWith(
        driverId: _selectedDriverId,
        driverName: _selectedDriverName,
      );
      if (!mounted) return;
      Navigator.pop(context);
      widget.onAssigned(updated);
      ThemeConstants.showSuccessSnackBar(context, '${LocalizationService.instance.translate('driver_assigned_to_the_vehicle')}.');
    } on Exception catch (e) {
      if (!mounted) return;
      ThemeConstants.showErrorSnackBar(context, LocalizationService.instance.translateWith('error_2', <Object?>[e]));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: ThemeConstants.primaryBlue,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(LocalizationService.instance.translateWith('assign_driver_to', <Object?>[widget.vehicle.name]),
          style: ThemeConstants.headingStyle),
      content: _loading
          ? const SizedBox(
              height: 64, child: Center(child: CircularProgressIndicator()))
          : DropdownButtonFormField<String>(
              initialValue: _selectedDriverId,
              dropdownColor: ThemeConstants.primaryBlue,
              style: const TextStyle(color: Colors.white),
              items: _drivers
                  .map((d) => DropdownMenuItem<String>(
                        value: d['id'],
                        child: Text(
                          d['name'] ?? '',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ))
                  .toList(),
              onChanged: (val) {
                setState(() {
                  _selectedDriverId = val;
                  _selectedDriverName =
                      _drivers.firstWhere((e) => e['id'] == val)['name'];
                });
              },
              decoration: InputDecoration(
                labelText: LocalizationService.instance.translate('select_driver'),
                labelStyle:
                    const TextStyle(color: ThemeConstants.textSecondary),
                filled: true,
                fillColor: ThemeConstants.primaryBlue.withOpacity(0.35),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.25)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                      color: ThemeConstants.primaryOrange, width: 1.5),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(LocalizationService.instance.translate('cancel_2'), style: TextStyle(color: Colors.white)),
        ),
        ElevatedButton(
          onPressed: _selectedDriverId == null ? null : _assign,
          style: ElevatedButton.styleFrom(
              backgroundColor: ThemeConstants.primaryOrange,
              foregroundColor: Colors.white),
          child: Text(LocalizationService.instance.translate('assign')),
        ),
      ],
    );
  }
}

// Add Vehicle Dialog Widget
class _AddVehicleDialog extends StatefulWidget {
  const _AddVehicleDialog({required this.onVehicleAdded});
  final VoidCallback onVehicleAdded;

  @override
  State<_AddVehicleDialog> createState() => _AddVehicleDialogState();
}

class _AddVehicleDialogState extends State<_AddVehicleDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final ApiService _apiService = ApiService();

  // Form controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _plateNumberController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  // Form state
  bool _isLoading = false;
  String _selectedVehicleType = "bajaji";
  bool _isActive = true;
  int? _branchId;

  // Vehicle types
  final Map<String, String> _vehicleTypes = <String, String>{
    "bajaji": LocalizationService.instance.translate('vehicle_type_bajaji'),
    "pikipiki": LocalizationService.instance.translate('vehicle_type_pikipiki'),
    "gari": LocalizationService.instance.translate('vehicle_type_gari'),
  };

  // Colors (aligned with ThemeConstants)
  static const Color primaryBlue = ThemeConstants.primaryBlue;
  static const Color successGreen = ThemeConstants.successGreen;
  static const Color errorRed = ThemeConstants.errorRed;

  InputDecoration _inputDecoration(String label,
      {IconData? icon, String? hint}) {
    final OutlineInputBorder border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.white.withOpacity(0.25)),
    );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: ThemeConstants.textSecondary),
      hintStyle: const TextStyle(color: ThemeConstants.textSecondary),
      prefixIcon:
          icon != null ? Icon(icon, color: ThemeConstants.textSecondary) : null,
      filled: true,
      fillColor: ThemeConstants.primaryBlue.withOpacity(0.35),
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide:
            const BorderSide(color: ThemeConstants.primaryOrange, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _plateNumberController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await _apiService.initialize();

      final Map<String, dynamic> vehicleData = <String, dynamic>{
        "name": _nameController.text.trim(),
        "type": _selectedVehicleType,
        "plate_number": _plateNumberController.text.trim().toUpperCase(),
        "description": _descriptionController.text.trim().isNotEmpty
            ? _descriptionController.text.trim()
            : null,
        "is_active": _isActive,
        "branch_id": _branchId,
      };

      await _apiService.createVehicle(vehicleData);

      if (mounted) {
        Navigator.pop(context);
        widget.onVehicleAdded();

        ThemeConstants.showSuccessSnackBar(context, LocalizationService.instance.translateWith('vehicle_was_registered_successfully', <Object?>[_plateNumberController.text]));
      }
    } on Exception catch (e) {
      if (mounted) {
        ThemeConstants.showErrorSnackBar(context, LocalizationService.instance.translateWith('error_registering_vehicle', <Object?>[e]));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(final BuildContext context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          color: ThemeConstants.primaryBlue,
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: primaryBlue,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(
                      Icons.directions_car,
                      color: Colors.white,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        LocalizationService.instance.translate('register_new_vehicle'),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),

              // Form content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        // Vehicle name field
                        TextFormField(
                          controller: _nameController,
                          style: const TextStyle(
                              color: ThemeConstants.textPrimary),
                          decoration: _inputDecoration(
                            '${LocalizationService.instance.translate('vehicle_name')} *',
                            hint: LocalizationService.instance.translate('example_first_tuk_tuk'),
                            icon: Icons.label,
                          ),
                          validator: (final String? value) {
                            if (value == null || value.trim().isEmpty) {
                              return LocalizationService.instance.translate('vehicle_name_is_required');
                            }
                            if (value.trim().length < 2) {
                              return LocalizationService.instance.translate('name_must_have_at_least_2');
                            }
                            return null;
                          },
                        ),

                        SizedBox(height: 16.h),

                        // Vehicle type dropdown
                        DropdownButtonFormField<String>(
                          initialValue: _selectedVehicleType,
                          dropdownColor: ThemeConstants.primaryBlue,
                          style: const TextStyle(
                              color: ThemeConstants.textPrimary),
                          decoration: _inputDecoration('${LocalizationService.instance.translate('vehicle_type')} *',
                              icon: Icons.category),
                          items: _vehicleTypes.entries
                              .map(
                                (final MapEntry<String, String> entry) =>
                                    DropdownMenuItem<String>(
                                  value: entry.key,
                                  child: Text(
                                    entry.value,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (final String? value) {
                            setState(() {
                              _selectedVehicleType = value!;
                            });
                          },
                        ),

                        const SizedBox(height: 16),

                        BranchPickerField(service: 'transport', decoration: _inputDecoration(''), onChanged: (int? id) => _branchId = id),

                        const SizedBox(height: 16),

                        // Plate number field
                        TextFormField(
                          controller: _plateNumberController,
                          style: const TextStyle(
                              color: ThemeConstants.textPrimary),
                          decoration: _inputDecoration('${LocalizationService.instance.translate('vehicle_number')} *',
                              hint: 'T123ABC', icon: Icons.confirmation_number),
                          textCapitalization: TextCapitalization.characters,
                          validator: (final String? value) {
                            if (value == null || value.trim().isEmpty) {
                              return LocalizationService.instance.translate('vehicle_number_is_required');
                            }
                            if (value.trim().length < 3) {
                              return LocalizationService.instance.translate('vehicle_number_is_not_valid');
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 16),

                        // Description field
                        TextFormField(
                          controller: _descriptionController,
                          style: const TextStyle(
                              color: ThemeConstants.textPrimary),
                          decoration: _inputDecoration(LocalizationService.instance.translate('note_optional'),
                              hint: LocalizationService.instance.translate('extra_details_about_the_vehicle'),
                              icon: Icons.description),
                          maxLines: 3,
                        ),

                        const SizedBox(height: 8),

                        // Status switch (Hali)
                        // The row sits on a coloured box, so it gets its own Material to paint on.
                        Material(
                          type: MaterialType.transparency,
                          child: SwitchListTile(
                            value: _isActive,
                            title: Text(
                              '${LocalizationService.instance.translate('status')}: ${_isActive ? LocalizationService.instance.translate('active') : LocalizationService.instance.translate('inactive_driver')}',
                              style: const TextStyle(
                                  color: ThemeConstants.textPrimary),
                            ),
                            onChanged: (val) => setState(() => _isActive = val),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Action buttons
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: ThemeConstants.primaryBlue,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: TextButton(
                        onPressed:
                            _isLoading ? null : () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(color: Colors.white),
                          ),
                          foregroundColor: Colors.white,
                        ),
                        child: Text(
                          LocalizationService.instance.translate('cancel_2'),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _submitForm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ThemeConstants.primaryOrange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : Text(
                                LocalizationService.instance.translate('register_vehicle'),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}
