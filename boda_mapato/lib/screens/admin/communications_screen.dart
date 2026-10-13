import "dart:ui";

import "package:flutter/material.dart";
import 'package:flutter_screenutil/flutter_screenutil.dart';
import "package:provider/provider.dart";

import "../../constants/theme_constants.dart";
import "../../models/communication.dart";
import "../../models/driver.dart";
import '../../services/api_service.dart';
import "../../services/localization_service.dart";

// ─────────────────────────────────────────────
// Color palette (local — matches property_details_screen)
// ─────────────────────────────────────────────
const _kGradientTop = Color(0xFF04121A);
const _kGradientMid = Color(0xFF092D3A);
const _kGradientBottom = Color(0xFF0D485A);
const _kOrange = Color(0xFFF97316);
const _kGreen = Color(0xFF10B981);
const _kAmber = Color(0xFFF59E0B);
const _kRed = Color(0xFFEF4444);
const _kCyan = Color(0xFF1BA3C7);
const _kWhatsApp = Color(0xFF25D366);

class CommunicationsScreen extends StatefulWidget {
  const CommunicationsScreen({super.key});

  @override
  State<CommunicationsScreen> createState() => _CommunicationsScreenState();
}

class _CommunicationsScreenState extends State<CommunicationsScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();

  bool _isLoading = true;
  bool _apiEndpointsAvailable = false;
  String _selectedFilterMode =
      "all"; // "all", "sms", "call", "whatsapp", "system_note"
  String _selectedFilterStatus = "all"; // "all", "answered", "unanswered"

  // Communication data
  List<Communication> _communications = [];
  List<Driver> _availableDrivers = [];
  CommunicationSummary? _summary;

  // Filter controllers
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  // Animations
  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
            begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _loadCommunicationsData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCommunicationsData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Initialize API service
      await _apiService.initialize();

      // Load available drivers for form
      await _loadAvailableDrivers();

      // Load communications
      await _loadCommunications();

      // Load summary
      await _loadCommunicationSummary();
    } on Exception catch (e) {
      _showErrorSnackBar(LocalizationService.instance.translateWith('error_loading_data', <Object?>[e]));
    } finally {
      setState(() {
        _isLoading = false;
      });
      if (mounted) _animCtrl.forward();
    }
  }

  Future<void> _loadAvailableDrivers() async {
    try {
      // Check if driver endpoint exists
      bool useApiData = false;

      try {
        final bool isConnected = await _apiService.testConnectivity();
        if (!isConnected) {
          useApiData = false;
          setState(() {
            _apiEndpointsAvailable = false;
          });
        } else {
          final testResponse =
              await _apiService.get('/admin/drivers', requireAuth: false);
          useApiData = testResponse['status'] == 'success';
          setState(() {
            _apiEndpointsAvailable = useApiData;
          });
        }
      } on Exception catch (e) {
        useApiData = false;
        setState(() {
          _apiEndpointsAvailable = false;
        });
        debugPrint('Connectivity/driver endpoint check failed: $e');
      }

      if (useApiData) {
        try {
          final response = await _apiService.get('/admin/drivers');
          // Be robust to multiple response shapes
          final bool ok = (response['status'] == 'success') ||
              response.containsKey('data') ||
              response.containsKey('drivers');
          if (ok) {
            final dynamic data =
                response.containsKey('data') ? response['data'] : response;

            List<dynamic> driverData = <dynamic>[];
            if (data is List) {
              driverData = data;
            } else if (data is Map) {
              if (data['drivers'] is List) {
                driverData = data['drivers'] as List<dynamic>;
              } else if (data['data'] is List) {
                // Laravel-style pagination: { data: { data: [...] }}
                driverData = data['data'] as List<dynamic>;
              } else if (data['items'] is List) {
                driverData = data['items'] as List<dynamic>;
              } else if (data['results'] is List) {
                driverData = data['results'] as List<dynamic>;
              }
            }

            if (driverData.isNotEmpty) {
              _availableDrivers = driverData
                  .map((json) => Driver.fromJson(json as Map<String, dynamic>))
                  .toList();
            } else {
              // Could not recognize the driver list structure; fall back to mock
              debugPrint('Unexpected driver data format: '
                  '${data.runtimeType}${data is Map ? ' keys=${data.keys.toList()}' : ''}');
              _availableDrivers = _getMockDrivers();
            }
          } else {
            _availableDrivers = _getMockDrivers();
          }
        } on Exception catch (driverError) {
          debugPrint('Error parsing driver data: $driverError');
          _availableDrivers = _getMockDrivers();
        }
      } else {
        // Mock data for drivers
        _availableDrivers = _getMockDrivers();
      }
    } on Exception catch (e) {
      debugPrint(LocalizationService.instance.translateWith('failed_to_load_drivers_2', <Object?>[e]));
      _availableDrivers = _getMockDrivers();
    }
  }

  Future<void> _loadCommunications() async {
    try {
      if (_apiEndpointsAvailable) {
        try {
          final response = await _apiService.get('/admin/communications');
          if (response['status'] == 'success' && response['data'] != null) {
            final List<dynamic> commData = response['data'] as List<dynamic>;
            _communications = commData
                .map((json) =>
                    Communication.fromJson(json as Map<String, dynamic>))
                .toList();
          } else {
            _communications = [];
          }
        } on Exception catch (apiError) {
          debugPrint('Communications API endpoints failed: $apiError');
          setState(() {
            _apiEndpointsAvailable = false;
          });
          _communications = _getMockCommunications();
        }
      } else {
        _communications = _getMockCommunications();
      }
    } on Exception catch (e) {
      debugPrint('Communications loading failed: $e');
      _communications = _getMockCommunications();
    }
  }

  Future<void> _loadCommunicationSummary() async {
    try {
      if (_apiEndpointsAvailable) {
        try {
          final response =
              await _apiService.get('/admin/communications/summary');
          if (response['status'] == 'success' && response['data'] != null) {
            _summary = CommunicationSummary.fromJson(response['data']);
          } else {
            _summary = _getMockSummary();
          }
        } on Exception catch (_) {
          _summary = _getMockSummary();
        }
      } else {
        _summary = _getMockSummary();
      }
    } on Exception catch (e) {
      debugPrint('Summary load failed: $e');
      _summary = _getMockSummary();
    }
  }

  List<Driver> _getMockDrivers() {
    return [
      Driver(
        id: "1",
        name: "Juma Mwalimu",
        email: "juma@example.com",
        phone: "+255712345678",
        licenseNumber: "LIC001",
        joinedDate: DateTime.now().subtract(const Duration(days: 120)),
        status: "active",
        totalPayments: 85000,
        rating: 4.5,
        tripsCompleted: 245,
        vehicleType: "Boda Boda",
        vehicleNumber: "BB001",
      ),
      Driver(
        id: "2",
        name: "Mary Kibwana",
        email: "mary@example.com",
        phone: "+255723456789",
        licenseNumber: "LIC002",
        joinedDate: DateTime.now().subtract(const Duration(days: 90)),
        status: "active",
        totalPayments: 67000,
        rating: 4.2,
        tripsCompleted: 198,
        vehicleType: "Boda Boda",
        vehicleNumber: "BB002",
      ),
      Driver(
        id: "3",
        name: "Hassan Mwangi",
        email: "hassan@example.com",
        phone: "+255734567890",
        licenseNumber: "LIC003",
        joinedDate: DateTime.now().subtract(const Duration(days: 60)),
        status: "active",
        totalPayments: 45000,
        rating: 4.7,
        tripsCompleted: 132,
        vehicleType: "Boda Boda",
        vehicleNumber: "BB003",
      ),
    ];
  }

  List<Communication> _getMockCommunications() {
    final DateTime now = DateTime.now();
    return [
      Communication(
        id: 1,
        driverId: "1",
        driverName: "Juma Mwalimu",
        messageDate: now.subtract(const Duration(days: 2)),
        messageContent:
            LocalizationService.instance.translate('i_would_like_to_inform_you'),
        response:
            LocalizationService.instance.translate('we_received_your_message_how_many'),
        mode: CommunicationMode.sms,
        createdAt: now.subtract(const Duration(days: 2)),
        updatedAt: now.subtract(const Duration(days: 1)),
      ),
      Communication(
        id: 2,
        driverId: "2",
        driverName: "Mary Kibwana",
        messageDate: now.subtract(const Duration(days: 5)),
        messageContent:
            LocalizationService.instance.translate('the_driver_s_phone_is_off'),
        mode: CommunicationMode.systemNote,
        createdAt: now.subtract(const Duration(days: 5)),
        updatedAt: now.subtract(const Duration(days: 5)),
      ),
      Communication(
        id: 3,
        driverId: "1",
        driverName: "Juma Mwalimu",
        messageDate: now.subtract(const Duration(days: 7)),
        messageContent:
            LocalizationService.instance.translate('excuse_me_i_would_like_to'),
        response:
            LocalizationService.instance.translate('we_are_sharing_new_updates_this'),
        mode: CommunicationMode.whatsapp,
        createdAt: now.subtract(const Duration(days: 7)),
        updatedAt: now.subtract(const Duration(days: 6)),
      ),
      Communication(
        id: 4,
        driverId: "3",
        driverName: "Hassan Mwangi",
        messageDate: now.subtract(const Duration(days: 10)),
        messageContent:
            LocalizationService.instance.translate('phone_conversation_about_last_week_s'),
        response: LocalizationService.instance.translate('promised_to_pay_part_of_the'),
        mode: CommunicationMode.call,
        createdAt: now.subtract(const Duration(days: 10)),
        updatedAt: now.subtract(const Duration(days: 9)),
      ),
    ];
  }

  CommunicationSummary _getMockSummary() {
    return CommunicationSummary(
      totalCommunications: 15,
      unansweredCommunications: 3,
      recentCommunications: 8,
      communicationsByMode: {
        CommunicationMode.sms: 4,
        CommunicationMode.call: 6,
        CommunicationMode.whatsapp: 3,
        CommunicationMode.systemNote: 2,
      },
      lastCommunicationDate: DateTime.now().subtract(const Duration(days: 2)),
    );
  }

  void _showErrorSnackBar(String message) {
    ThemeConstants.showErrorSnackBar(context, message);
  }

  void _showSuccessSnackBar(String message) {
    ThemeConstants.showSuccessSnackBar(context, message);
  }

  Color _getModeColor(CommunicationMode mode) {
    switch (mode) {
      case CommunicationMode.sms:
        return _kOrange;
      case CommunicationMode.call:
        return _kGreen;
      case CommunicationMode.whatsapp:
        return _kWhatsApp;
      case CommunicationMode.systemNote:
        return _kAmber;
    }
  }

  IconData _getModeIcon(CommunicationMode mode) {
    switch (mode) {
      case CommunicationMode.sms:
        return Icons.sms_outlined;
      case CommunicationMode.call:
        return Icons.phone_outlined;
      case CommunicationMode.whatsapp:
        return Icons.chat_outlined;
      case CommunicationMode.systemNote:
        return Icons.note_alt_outlined;
    }
  }

  List<Communication> _getFilteredCommunications() {
    List<Communication> filtered = List.from(_communications);

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((comm) {
        return comm.driverName.toLowerCase().contains(_searchQuery) ||
            comm.messageContent.toLowerCase().contains(_searchQuery) ||
            (comm.response?.toLowerCase().contains(_searchQuery) ?? false);
      }).toList();
    }

    // Apply mode filter
    if (_selectedFilterMode != "all") {
      filtered = filtered.where((comm) {
        return comm.mode.value == _selectedFilterMode;
      }).toList();
    }

    // Apply status filter
    if (_selectedFilterStatus != "all") {
      if (_selectedFilterStatus == "answered") {
        filtered = filtered.where((comm) => comm.hasResponse).toList();
      } else if (_selectedFilterStatus == "unanswered") {
        filtered = filtered.where((comm) => !comm.hasResponse).toList();
      }
    }

    // Sort by message date (newest first)
    filtered.sort((a, b) => b.messageDate.compareTo(a.messageDate));

    return filtered;
  }

  // ════════════════════════════════════════════
  //  BUILD
  // ════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Consumer<LocalizationService>(
      builder: (context, localizationService, child) {
        return Scaffold(
          backgroundColor: _kGradientTop,
          extendBodyBehindAppBar: true,
          floatingActionButton: _buildFab(localizationService),
          body: Stack(
            children: [
              // ── Animated gradient background
              const _AnimatedBackground(),

              // ── Main scrollable content
              _isLoading
                  ? _buildLoadingState()
                  : _buildMainContent(localizationService),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFab(LocalizationService loc) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(16.r),
        onTap: _showAddCommunicationDialog,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 14.h),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFF97316), Color(0xFFFF6B35)],
            ),
            borderRadius: BorderRadius.circular(16.r),
            boxShadow: [
              BoxShadow(
                color: _kOrange.withOpacity(0.4),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_comment_rounded,
                  color: Colors.white, size: 18.sp),
              SizedBox(width: 8.w),
              Text(
                loc.translate("add"),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13.sp,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return CustomScrollView(
      slivers: [
        _buildSliverAppBar(null),
        SliverFillRemaining(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 32.w,
                  height: 32.w,
                  child: const CircularProgressIndicator(
                      color: _kOrange, strokeWidth: 2.5),
                ),
                SizedBox(height: 16.h),
                Text("${LocalizationService.instance.translate('loading_2')}...",
                    style: TextStyle(
                        color: Colors.white38, fontSize: 13.sp)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMainContent(LocalizationService loc) {
    final filteredCommunications = _getFilteredCommunications();

    return RefreshIndicator(
      onRefresh: _loadCommunicationsData,
      color: _kOrange,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          _buildSliverAppBar(loc),

          // ── Content
          SliverPadding(
            padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, 100.h),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                FadeTransition(
                  opacity: _fadeAnim,
                  child: SlideTransition(
                    position: _slideAnim,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(height: 16.h),

                        // ── Summary Cards
                        if (_summary != null)
                          _buildSummarySection(loc),

                        SizedBox(height: 16.h),

                        // ── Filter & Search
                        _buildFiltersSection(loc),

                        SizedBox(height: 16.h),

                        // ── Communications List Header
                        Padding(
                          padding: EdgeInsets.only(left: 4.w, bottom: 8.h),
                          child: Row(
                            children: [
                              Container(
                                padding: EdgeInsets.all(7.w),
                                decoration: BoxDecoration(
                                  color: _kOrange.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(10.r),
                                  border: Border.all(
                                      color: _kOrange.withOpacity(0.25)),
                                ),
                                child: Icon(Icons.forum_outlined,
                                    color: _kOrange, size: 14.sp),
                              ),
                              SizedBox(width: 10.w),
                              Text(
                                "${loc.translate("communications")} (${filteredCommunications.length})",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // ── Communication Cards List
                        if (filteredCommunications.isEmpty)
                          _buildEmptyState(loc)
                        else
                          ...filteredCommunications
                              .map((comm) => _buildCommunicationCard(comm)),
                      ],
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ── Sliver App Bar
  SliverAppBar _buildSliverAppBar(LocalizationService? loc) {
    return SliverAppBar(
      expandedHeight: 140.h,
      pinned: true,
      backgroundColor: _kGradientTop.withOpacity(0.85),
      elevation: 0,
      leading: IconButton(
        icon: Container(
          padding: EdgeInsets.all(6.w),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10.r),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
          ),
          child: Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 14.sp),
        ),
        onPressed: () => Navigator.pop(context),
      ),
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.parallax,
        background: Stack(
          children: [
            // Subtle radial glow
            Positioned(
              top: 50.h,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 120.w,
                  height: 120.w,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [
                      _kOrange.withOpacity(0.15),
                      Colors.transparent,
                    ]),
                  ),
                ),
              ),
            ),
            // Content
            Positioned(
              bottom: 20.h,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  // Icon
                  Container(
                    width: 56.w,
                    height: 56.w,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFFF97316), Color(0xFFFF6B35)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(
                          color: Colors.white.withOpacity(0.3), width: 2.5),
                      boxShadow: [
                        BoxShadow(
                          color: _kOrange.withOpacity(0.35),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Icon(Icons.forum_rounded,
                          color: Colors.white, size: 24.sp),
                    ),
                  ),
                  SizedBox(height: 10.h),
                  // Title
                  Text(
                    loc?.translate("communications_title") ?? "Mawasiliano",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18.sp,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.4,
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

  // ── Summary Section
  Widget _buildSummarySection(LocalizationService loc) {
    final responseRate = ((_summary!.totalCommunications -
                    _summary!.unansweredCommunications) /
                (_summary!.totalCommunications == 0
                    ? 1
                    : _summary!.totalCommunications) *
                100)
            .round();

    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(
            icon: Icons.analytics_outlined,
            label: loc.translate("communications_summary_title"),
          ),
          Divider(height: 24.h, color: Colors.white10),
          Row(
            children: [
              Expanded(
                child: _StatPill(
                  icon: Icons.chat_bubble_outline,
                  label: loc.translate("total_communications"),
                  value: '${_summary!.totalCommunications}',
                  color: _kCyan,
                ),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: _StatPill(
                  icon: Icons.help_outline,
                  label: loc.translate("unanswered"),
                  value: '${_summary!.unansweredCommunications}',
                  color: _kRed,
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          Row(
            children: [
              Expanded(
                child: _StatPill(
                  icon: Icons.access_time,
                  label: loc.translate("recent_7_days"),
                  value: '${_summary!.recentCommunications}',
                  color: _kGreen,
                ),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: _StatPill(
                  icon: Icons.trending_up,
                  label: loc.translate("response_rate"),
                  value: '$responseRate%',
                  color: _kAmber,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Filter & Search Section
  Widget _buildFiltersSection(LocalizationService loc) {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(
            icon: Icons.filter_list_rounded,
            label: loc.translate("filter_communications"),
          ),
          Divider(height: 20.h, color: Colors.white10),

          // Search field
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: Colors.white, fontSize: 13.sp),
              decoration: InputDecoration(
                hintText: loc.translate("search_driver_content"),
                hintStyle:
                    TextStyle(color: Colors.white38, fontSize: 12.sp),
                prefixIcon: Icon(Icons.search,
                    color: Colors.white38, size: 18.sp),
                filled: false,
                border: InputBorder.none,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.toLowerCase();
                });
              },
            ),
          ),
          SizedBox(height: 14.h),

          // Type filters
          Text(loc.translate("type"),
              style: TextStyle(
                  color: Colors.white54,
                  fontSize: 10.sp,
                  letterSpacing: 0.5,
                  fontWeight: FontWeight.w600)),
          SizedBox(height: 6.h),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip(loc.translate("all"), "all",
                    _selectedFilterMode, (v) {
                  setState(() => _selectedFilterMode = v);
                }),
                SizedBox(width: 6.w),
                _buildFilterChip("SMS", "sms", _selectedFilterMode, (v) {
                  setState(() => _selectedFilterMode = v);
                }),
                SizedBox(width: 6.w),
                _buildFilterChip(
                    loc.translate("call"), "call", _selectedFilterMode, (v) {
                  setState(() => _selectedFilterMode = v);
                }),
                SizedBox(width: 6.w),
                _buildFilterChip(
                    "WhatsApp", "whatsapp", _selectedFilterMode, (v) {
                  setState(() => _selectedFilterMode = v);
                }),
                SizedBox(width: 6.w),
                _buildFilterChip(
                    loc.translate("note"), "system_note", _selectedFilterMode,
                    (v) {
                  setState(() => _selectedFilterMode = v);
                }),
              ],
            ),
          ),
          SizedBox(height: 10.h),

          // Status filters
          Text(loc.translate("status"),
              style: TextStyle(
                  color: Colors.white54,
                  fontSize: 10.sp,
                  letterSpacing: 0.5,
                  fontWeight: FontWeight.w600)),
          SizedBox(height: 6.h),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip(loc.translate("all"), "all",
                    _selectedFilterStatus, (v) {
                  setState(() => _selectedFilterStatus = v);
                }),
                SizedBox(width: 6.w),
                _buildFilterChip(loc.translate("answered"), "answered",
                    _selectedFilterStatus, (v) {
                  setState(() => _selectedFilterStatus = v);
                }),
                SizedBox(width: 6.w),
                _buildFilterChip(loc.translate("unanswered"), "unanswered",
                    _selectedFilterStatus, (v) {
                  setState(() => _selectedFilterStatus = v);
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, String selectedValue,
      Function(String) onSelected) {
    final bool isSelected = selectedValue == value;
    return GestureDetector(
      onTap: () => onSelected(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 7.h),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(
                  colors: [Color(0xFFF97316), Color(0xFFFF6B35)])
              : null,
          color: isSelected ? null : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(20.r),
          border: Border.all(
            color: isSelected
                ? _kOrange.withOpacity(0.5)
                : Colors.white.withOpacity(0.12),
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: _kOrange.withOpacity(0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white60,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontSize: 11.sp,
          ),
        ),
      ),
    );
  }

  // ── Empty state
  Widget _buildEmptyState(LocalizationService loc) {
    return _GlassCard(
      child: Column(
        children: [
          SizedBox(height: 20.h),
          Icon(Icons.chat_bubble_outline,
              size: 48.sp, color: Colors.white24),
          SizedBox(height: 12.h),
          Text(
            loc.translate("no_communications"),
            style: TextStyle(color: Colors.white38, fontSize: 13.sp),
          ),
          SizedBox(height: 20.h),
        ],
      ),
    );
  }

  // ── Communication Card
  Widget _buildCommunicationCard(Communication comm) {
    final Color modeColor = _getModeColor(comm.mode);
    final IconData modeIcon = _getModeIcon(comm.mode);
    final String initial =
        comm.driverName.isNotEmpty ? comm.driverName[0].toUpperCase() : '?';

    return Padding(
      padding: EdgeInsets.only(bottom: 10.h),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16.r),
        child: InkWell(
          borderRadius: BorderRadius.circular(16.r),
          onTap: () => _showCommunicationDetails(comm),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16.r),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                padding: EdgeInsets.all(14.w),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(16.r),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Top row: avatar + name + mode badge
                    Row(
                      children: [
                        // Avatar
                        Container(
                          width: 40.w,
                          height: 40.w,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                modeColor.withOpacity(0.7),
                                modeColor.withOpacity(0.4),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            border: Border.all(
                                color: modeColor.withOpacity(0.4), width: 1.5),
                          ),
                          child: Center(
                            child: Text(
                              initial,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16.sp,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 12.w),

                        // Name
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                comm.driverName,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(height: 2.h),
                              Row(
                                children: [
                                  Icon(Icons.access_time_rounded,
                                      color: Colors.white38, size: 11.sp),
                                  SizedBox(width: 4.w),
                                  Text(
                                    comm.formattedMessageDate,
                                    style: TextStyle(
                                      color: Colors.white38,
                                      fontSize: 10.sp,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // Mode badge
                        Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 10.w, vertical: 5.h),
                          decoration: BoxDecoration(
                            color: modeColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20.r),
                            border: Border.all(
                                color: modeColor.withOpacity(0.35)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(modeIcon,
                                  color: modeColor, size: 12.sp),
                              SizedBox(width: 4.w),
                              Text(
                                comm.mode.displayName,
                                style: TextStyle(
                                  color: modeColor,
                                  fontSize: 10.sp,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: 10.h),

                    // ── Message content
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(10.w),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(10.r),
                        border:
                            Border.all(color: Colors.white.withOpacity(0.06)),
                      ),
                      child: Text(
                        comm.messageContent,
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12.sp,
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                    SizedBox(height: 8.h),

                    // ── Bottom row: response status
                    Row(
                      children: [
                        if (comm.hasResponse) ...[
                          Container(
                            padding: EdgeInsets.all(4.w),
                            decoration: BoxDecoration(
                              color: _kGreen.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6.r),
                            ),
                            child: Icon(Icons.check_circle_outline,
                                color: _kGreen, size: 13.sp),
                          ),
                          SizedBox(width: 8.w),
                          Expanded(
                            child: Text(
                              comm.response ?? "",
                              style: TextStyle(
                                color: _kGreen.withOpacity(0.8),
                                fontSize: 11.sp,
                                fontStyle: FontStyle.italic,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ] else ...[
                          Container(
                            padding: EdgeInsets.all(4.w),
                            decoration: BoxDecoration(
                              color: _kAmber.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6.r),
                            ),
                            child: Icon(Icons.schedule_rounded,
                                color: _kAmber, size: 13.sp),
                          ),
                          SizedBox(width: 8.w),
                          Text(
                            LocalizationService.instance.translate('waiting_for_a_reply'),
                            style: TextStyle(
                              color: _kAmber.withOpacity(0.8),
                              fontSize: 11.sp,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                        const Spacer(),
                        Icon(Icons.chevron_right_rounded,
                            color: Colors.white24, size: 18.sp),
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

  // ════════════════════════════════════════════
  //  DIALOGS — frosted glassmorphic style
  // ════════════════════════════════════════════

  void _showCommunicationDetails(Communication communication) {
    final Color modeColor = _getModeColor(communication.mode);
    final IconData modeIcon = _getModeIcon(communication.mode);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 24.h),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20.r),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                constraints: BoxConstraints(maxWidth: 480.w),
                decoration: BoxDecoration(
                  color: _kGradientMid.withOpacity(0.92),
                  borderRadius: BorderRadius.circular(20.r),
                  border: Border.all(color: Colors.white.withOpacity(0.12)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(20.w),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        children: [
                          Container(
                            padding: EdgeInsets.all(10.w),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  modeColor.withOpacity(0.3),
                                  modeColor.withOpacity(0.1),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(12.r),
                              border: Border.all(
                                  color: modeColor.withOpacity(0.3)),
                            ),
                            child: Icon(modeIcon,
                                color: modeColor, size: 20.sp),
                          ),
                          SizedBox(width: 12.w),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  LocalizationService.instance.translate('communication_details'),
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16.sp,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 2.h),
                                Text(
                                  communication.mode.displayName,
                                  style: TextStyle(
                                    color: modeColor,
                                    fontSize: 11.sp,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              padding: EdgeInsets.all(6.w),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8.r),
                              ),
                              child: Icon(Icons.close_rounded,
                                  color: Colors.white54, size: 16.sp),
                            ),
                          ),
                        ],
                      ),

                      SizedBox(height: 20.h),

                      // Info rows
                      _buildGlassDetailRow(
                          Icons.person_outline, LocalizationService.instance.translate('driver'), communication.driverName),
                      SizedBox(height: 8.h),
                      _buildGlassDetailRow(Icons.calendar_today_outlined,
                          LocalizationService.instance.translate('date'), communication.formattedDateTime),
                      SizedBox(height: 16.h),

                      // Message
                      Text(LocalizationService.instance.translate('reminder_message'),
                          style: TextStyle(
                              color: Colors.white54,
                              fontSize: 10.sp,
                              letterSpacing: 0.5,
                              fontWeight: FontWeight.w600)),
                      SizedBox(height: 6.h),
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(14.w),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(
                              color: Colors.white.withOpacity(0.08)),
                        ),
                        child: Text(
                          communication.messageContent,
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13.sp,
                            height: 1.5,
                          ),
                        ),
                      ),

                      SizedBox(height: 16.h),

                      // Response
                      Text(LocalizationService.instance.translate('reply'),
                          style: TextStyle(
                              color: Colors.white54,
                              fontSize: 10.sp,
                              letterSpacing: 0.5,
                              fontWeight: FontWeight.w600)),
                      SizedBox(height: 6.h),
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(14.w),
                        decoration: BoxDecoration(
                          color: communication.hasResponse
                              ? _kGreen.withOpacity(0.06)
                              : _kAmber.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(
                            color: communication.hasResponse
                                ? _kGreen.withOpacity(0.15)
                                : _kAmber.withOpacity(0.15),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              communication.hasResponse
                                  ? Icons.check_circle_outline
                                  : Icons.schedule_rounded,
                              color: communication.hasResponse
                                  ? _kGreen
                                  : _kAmber,
                              size: 16.sp,
                            ),
                            SizedBox(width: 10.w),
                            Expanded(
                              child: Text(
                                communication.response ??
                                    LocalizationService.instance.translate('no_reply_yet'),
                                style: TextStyle(
                                  color: communication.hasResponse
                                      ? Colors.white70
                                      : Colors.white38,
                                  fontSize: 13.sp,
                                  fontStyle: communication.hasResponse
                                      ? FontStyle.normal
                                      : FontStyle.italic,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      SizedBox(height: 20.h),

                      // Actions
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (!communication.hasResponse)
                            _buildGlassButton(
                              label: LocalizationService.instance.translate('add_reply'),
                              icon: Icons.reply_rounded,
                              color: _kOrange,
                              filled: true,
                              onTap: () {
                                Navigator.pop(context);
                                _showAddResponseDialog(communication);
                              },
                            ),
                          if (!communication.hasResponse)
                            SizedBox(width: 10.w),
                          _buildGlassButton(
                            label: LocalizationService.instance.translate('close'),
                            icon: Icons.close_rounded,
                            color: Colors.white54,
                            onTap: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGlassDetailRow(IconData icon, String label, String value) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 12.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(6.w),
            decoration: BoxDecoration(
              color: _kCyan.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Icon(icon, color: _kCyan, size: 14.sp),
          ),
          SizedBox(width: 10.w),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      color: Colors.white38, fontSize: 10.sp)),
              SizedBox(height: 2.h),
              Text(value,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGlassButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool filled = false,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(10.r),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
          decoration: BoxDecoration(
            gradient: filled
                ? const LinearGradient(
                    colors: [Color(0xFFF97316), Color(0xFFFF6B35)])
                : null,
            color: filled ? null : Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10.r),
            border: Border.all(
              color:
                  filled ? _kOrange.withOpacity(0.5) : Colors.white.withOpacity(0.15),
            ),
            boxShadow: filled
                ? [
                    BoxShadow(
                      color: _kOrange.withOpacity(0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  color: filled ? Colors.white : color, size: 14.sp),
              SizedBox(width: 6.w),
              Text(label,
                  style: TextStyle(
                    color: filled ? Colors.white : color,
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                  )),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddCommunicationDialog() {
    final TextEditingController messageController = TextEditingController();
    Driver? selectedDriver;
    CommunicationMode selectedMode = CommunicationMode.systemNote;

    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding:
                  EdgeInsets.symmetric(horizontal: 16.w, vertical: 24.h),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20.r),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    constraints: BoxConstraints(maxWidth: 480.w),
                    decoration: BoxDecoration(
                      color: _kGradientMid.withOpacity(0.92),
                      borderRadius: BorderRadius.circular(20.r),
                      border:
                          Border.all(color: Colors.white.withOpacity(0.12)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 30,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(20.w),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header
                          Row(
                            children: [
                              Container(
                                padding: EdgeInsets.all(10.w),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      _kOrange.withOpacity(0.3),
                                      _kOrange.withOpacity(0.1),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(12.r),
                                  border: Border.all(
                                      color: _kOrange.withOpacity(0.3)),
                                ),
                                child: Icon(Icons.add_comment_rounded,
                                    color: _kOrange, size: 20.sp),
                              ),
                              SizedBox(width: 12.w),
                              Expanded(
                                child: Text(
                                  LocalizationService.instance.translate('add_communication'),
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16.sp,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  messageController.dispose();
                                  Navigator.pop(ctx);
                                },
                                child: Container(
                                  padding: EdgeInsets.all(6.w),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8.r),
                                  ),
                                  child: Icon(Icons.close_rounded,
                                      color: Colors.white54, size: 16.sp),
                                ),
                              ),
                            ],
                          ),

                          SizedBox(height: 20.h),

                          // Driver selection
                          Text(LocalizationService.instance.translate('select_driver'),
                              style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 10.sp,
                                  letterSpacing: 0.5,
                                  fontWeight: FontWeight.w600)),
                          SizedBox(height: 6.h),
                          Container(
                            width: double.infinity,
                            padding: EdgeInsets.symmetric(
                                horizontal: 12.w, vertical: 4.h),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(12.r),
                              border: Border.all(
                                  color: Colors.white.withOpacity(0.1)),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<Driver>(
                                value: selectedDriver,
                                hint: Text(
                                  "${LocalizationService.instance.translate('select_driver')}...",
                                  style: TextStyle(
                                      color: Colors.white38,
                                      fontSize: 13.sp),
                                ),
                                dropdownColor: _kGradientMid,
                                style: TextStyle(
                                    color: Colors.white, fontSize: 13.sp),
                                items:
                                    _availableDrivers.map((Driver driver) {
                                  return DropdownMenuItem<Driver>(
                                    value: driver,
                                    child: Text(driver.name,
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 13.sp)),
                                  );
                                }).toList(),
                                onChanged: (Driver? value) {
                                  setDialogState(() {
                                    selectedDriver = value;
                                  });
                                },
                              ),
                            ),
                          ),

                          SizedBox(height: 16.h),

                          // Communication mode
                          Text(LocalizationService.instance.translate('communication_type'),
                              style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 10.sp,
                                  letterSpacing: 0.5,
                                  fontWeight: FontWeight.w600)),
                          SizedBox(height: 6.h),
                          Container(
                            width: double.infinity,
                            padding: EdgeInsets.symmetric(
                                horizontal: 12.w, vertical: 4.h),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(12.r),
                              border: Border.all(
                                  color: Colors.white.withOpacity(0.1)),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<CommunicationMode>(
                                value: selectedMode,
                                dropdownColor: _kGradientMid,
                                style: TextStyle(
                                    color: Colors.white, fontSize: 13.sp),
                                items: CommunicationMode.allModes
                                    .map((CommunicationMode mode) {
                                  return DropdownMenuItem<CommunicationMode>(
                                    value: mode,
                                    child: Row(
                                      children: [
                                        Icon(_getModeIcon(mode),
                                            color: _getModeColor(mode),
                                            size: 16.sp),
                                        SizedBox(width: 10.w),
                                        Text(mode.displayName,
                                            style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 13.sp)),
                                      ],
                                    ),
                                  );
                                }).toList(),
                                onChanged: (CommunicationMode? value) {
                                  setDialogState(() {
                                    selectedMode =
                                        value ?? CommunicationMode.systemNote;
                                  });
                                },
                              ),
                            ),
                          ),

                          SizedBox(height: 16.h),

                          // Message
                          Text(LocalizationService.instance.translate('reminder_message'),
                              style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 10.sp,
                                  letterSpacing: 0.5,
                                  fontWeight: FontWeight.w600)),
                          SizedBox(height: 6.h),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(12.r),
                              border: Border.all(
                                  color: Colors.white.withOpacity(0.1)),
                            ),
                            child: TextField(
                              controller: messageController,
                              style: TextStyle(
                                  color: Colors.white, fontSize: 13.sp),
                              maxLines: 4,
                              decoration: InputDecoration(
                                hintText: "${LocalizationService.instance.translate('write_the_message_here')}...",
                                hintStyle: TextStyle(
                                    color: Colors.white38,
                                    fontSize: 12.sp),
                                filled: false,
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.all(14.w),
                              ),
                            ),
                          ),

                          SizedBox(height: 24.h),

                          // Actions
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              _buildGlassButton(
                                label: LocalizationService.instance.translate('cancel_2'),
                                icon: Icons.close_rounded,
                                color: Colors.white54,
                                onTap: () {
                                  messageController.dispose();
                                  Navigator.pop(ctx);
                                },
                              ),
                              SizedBox(width: 10.w),
                              _buildGlassButton(
                                label: LocalizationService.instance.translate('save'),
                                icon: Icons.save_rounded,
                                color: _kOrange,
                                filled: true,
                                onTap: () {
                                  if (selectedDriver != null &&
                                      messageController.text
                                          .trim()
                                          .isNotEmpty) {
                                    _saveCommunication(
                                      selectedDriver!,
                                      messageController.text.trim(),
                                      selectedMode,
                                    );
                                    messageController.dispose();
                                    Navigator.pop(ctx);
                                  } else {
                                    _showErrorSnackBar(
                                        LocalizationService.instance.translate('please_fill_in_all_required_fields'));
                                  }
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showAddResponseDialog(Communication communication) {
    final TextEditingController responseController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              EdgeInsets.symmetric(horizontal: 16.w, vertical: 24.h),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20.r),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                constraints: BoxConstraints(maxWidth: 480.w),
                decoration: BoxDecoration(
                  color: _kGradientMid.withOpacity(0.92),
                  borderRadius: BorderRadius.circular(20.r),
                  border:
                      Border.all(color: Colors.white.withOpacity(0.12)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(20.w),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        children: [
                          Container(
                            padding: EdgeInsets.all(10.w),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  _kOrange.withOpacity(0.3),
                                  _kOrange.withOpacity(0.1),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(12.r),
                              border: Border.all(
                                  color: _kOrange.withOpacity(0.3)),
                            ),
                            child: Icon(Icons.reply_rounded,
                                color: _kOrange, size: 20.sp),
                          ),
                          SizedBox(width: 12.w),
                          Expanded(
                            child: Text(
                              LocalizationService.instance.translate('add_reply'),
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16.sp,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              responseController.dispose();
                              Navigator.pop(ctx);
                            },
                            child: Container(
                              padding: EdgeInsets.all(6.w),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8.r),
                              ),
                              child: Icon(Icons.close_rounded,
                                  color: Colors.white54, size: 16.sp),
                            ),
                          ),
                        ],
                      ),

                      SizedBox(height: 20.h),

                      // Original message
                      Text(LocalizationService.instance.translate('original_message'),
                          style: TextStyle(
                              color: Colors.white54,
                              fontSize: 10.sp,
                              letterSpacing: 0.5,
                              fontWeight: FontWeight.w600)),
                      SizedBox(height: 6.h),
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(14.w),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(
                              color: Colors.white.withOpacity(0.08)),
                        ),
                        child: Text(
                          communication.messageContent,
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12.sp,
                            height: 1.5,
                          ),
                        ),
                      ),

                      SizedBox(height: 16.h),

                      // Response
                      Text(LocalizationService.instance.translate('your_reply'),
                          style: TextStyle(
                              color: Colors.white54,
                              fontSize: 10.sp,
                              letterSpacing: 0.5,
                              fontWeight: FontWeight.w600)),
                      SizedBox(height: 6.h),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(
                              color: Colors.white.withOpacity(0.1)),
                        ),
                        child: TextField(
                          controller: responseController,
                          style: TextStyle(
                              color: Colors.white, fontSize: 13.sp),
                          maxLines: 4,
                          decoration: InputDecoration(
                            hintText: "${LocalizationService.instance.translate('write_your_reply_here')}...",
                            hintStyle: TextStyle(
                                color: Colors.white38, fontSize: 12.sp),
                            filled: false,
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.all(14.w),
                          ),
                        ),
                      ),

                      SizedBox(height: 24.h),

                      // Actions
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          _buildGlassButton(
                            label: LocalizationService.instance.translate('cancel_2'),
                            icon: Icons.close_rounded,
                            color: Colors.white54,
                            onTap: () {
                              responseController.dispose();
                              Navigator.pop(ctx);
                            },
                          ),
                          SizedBox(width: 10.w),
                          _buildGlassButton(
                            label: LocalizationService.instance.translate('send_reply'),
                            icon: Icons.send_rounded,
                            color: _kOrange,
                            filled: true,
                            onTap: () {
                              if (responseController.text
                                  .trim()
                                  .isNotEmpty) {
                                _saveResponse(communication,
                                    responseController.text.trim());
                                responseController.dispose();
                                Navigator.pop(ctx);
                              } else {
                                _showErrorSnackBar(
                                    LocalizationService.instance.translate('please_write_a_reply'));
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ════════════════════════════════════════════
  //  API SAVE METHODS (unchanged logic)
  // ════════════════════════════════════════════

  Future<void> _saveCommunication(
      Driver driver, String message, CommunicationMode mode) async {
    try {
      final DateTime now = DateTime.now();
      final Communication newCommunication = Communication(
        id: _communications.length + 1, // Mock ID
        driverId: driver.id,
        driverName: driver.name,
        messageDate: now,
        messageContent: message,
        mode: mode,
        createdAt: now,
        updatedAt: now,
      );

      if (_apiEndpointsAvailable) {
        // Try to save via API
        try {
          final response = await _apiService.post('/admin/communications', {
            'driver_id': driver.id,
            'driver_name': driver.name,
            'message_date': now.toIso8601String(),
            'message_content': message,
            'mode': mode.value,
          });

          if (response['status'] == 'success') {
            // Reload communications from API
            await _loadCommunications();
            await _loadCommunicationSummary();
            _showSuccessSnackBar("${LocalizationService.instance.translate('communication_saved_successfully')}!");
            return;
          }
        } on Exception catch (apiError) {
          debugPrint('Failed to save via API: $apiError');
        }
      }

      // Fallback: Save locally (mock)
      setState(() {
        _communications.insert(0, newCommunication);
        // Update summary
        if (_summary != null) {
          _summary = CommunicationSummary(
            totalCommunications: _summary!.totalCommunications + 1,
            unansweredCommunications: _summary!.unansweredCommunications + 1,
            recentCommunications: _summary!.recentCommunications + 1,
            communicationsByMode: {
              ..._summary!.communicationsByMode,
              mode: (_summary!.communicationsByMode[mode] ?? 0) + 1,
            },
            lastCommunicationDate: now,
          );
        }
      });

      _showSuccessSnackBar("${LocalizationService.instance.translate('communication_saved_sample')}!");
    } on Exception catch (e) {
      _showErrorSnackBar(LocalizationService.instance.translateWith('error_saving', <Object?>[e]));
    }
  }

  Future<void> _saveResponse(
      Communication communication, String response) async {
    try {
      if (_apiEndpointsAvailable) {
        // Try to save via API
        try {
          final apiResponse = await _apiService
              .put('/admin/communications/${communication.id}', {
            'response': response,
          });

          if (apiResponse['status'] == 'success') {
            // Reload communications from API
            await _loadCommunications();
            await _loadCommunicationSummary();
            _showSuccessSnackBar("${LocalizationService.instance.translate('reply_saved_successfully')}!");
            return;
          }
        } on Exception catch (apiError) {
          debugPrint('Failed to save response via API: $apiError');
        }
      }

      // Fallback: Update locally (mock)
      setState(() {
        final int index =
            _communications.indexWhere((comm) => comm.id == communication.id);
        if (index != -1) {
          _communications[index] = communication.copyWith(
            response: response,
            updatedAt: DateTime.now(),
          );

          // Update summary
          if (_summary != null) {
            _summary = CommunicationSummary(
              totalCommunications: _summary!.totalCommunications,
              unansweredCommunications: _summary!.unansweredCommunications - 1,
              recentCommunications: _summary!.recentCommunications,
              communicationsByMode: _summary!.communicationsByMode,
              lastCommunicationDate: _summary!.lastCommunicationDate,
            );
          }
        }
      });

      _showSuccessSnackBar("${LocalizationService.instance.translate('reply_saved_sample')}!");
    } on Exception catch (e) {
      _showErrorSnackBar(LocalizationService.instance.translateWith('error_saving_the_reply', <Object?>[e]));
    }
  }
}

// ─────────────────────────────────────────────
// Animated gradient background
// ─────────────────────────────────────────────
class _AnimatedBackground extends StatefulWidget {
  const _AnimatedBackground();
  @override
  State<_AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<_AnimatedBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 8))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value;
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _kGradientTop,
                Color.lerp(_kGradientMid, const Color(0xFF0A3A4A), t)!,
                _kGradientBottom,
              ],
              stops: const [0, 0.55, 1],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
// Glass card base
// ─────────────────────────────────────────────
class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child, this.padding});
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20.r),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.07),
            borderRadius: BorderRadius.circular(20.r),
            border: Border.all(color: Colors.white.withOpacity(0.13)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: padding ??
                EdgeInsets.symmetric(horizontal: 14.w, vertical: 16.h),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Section title row
// ─────────────────────────────────────────────
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.label, this.trailing});
  final IconData icon;
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(7.w),
          decoration: BoxDecoration(
            color: _kOrange.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10.r),
            border: Border.all(color: _kOrange.withOpacity(0.25)),
          ),
          child: Icon(icon, color: _kOrange, size: 14.sp),
        ),
        SizedBox(width: 10.w),
        Expanded(
          child: Text(label,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Stat pill widget
// ─────────────────────────────────────────────
class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 12.w),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(8.w),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Icon(icon, color: color, size: 16.sp),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 9.sp,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
