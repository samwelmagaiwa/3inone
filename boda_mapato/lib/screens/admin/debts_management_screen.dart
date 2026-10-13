import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/theme_constants.dart';
import '../../models/driver.dart';
import '../../providers/debts_provider.dart';
import '../../services/api_service.dart';
import '../../services/app_events.dart';
import '../../services/localization_service.dart';
import '../../utils/responsive_helper.dart';
import 'debt_records_list_screen.dart';

enum MonthFilter { mweziHuu, mweziUliopita, mwakaHuu, zote }

class DebtsManagementScreen extends StatefulWidget {
  const DebtsManagementScreen({super.key, this.initialDriverId});
  final String? initialDriverId;

  @override
  State<DebtsManagementScreen> createState() => _DebtsManagementScreenState();
}

class _DebtsManagementScreenState extends State<DebtsManagementScreen>
    with TickerProviderStateMixin {
  final ApiService _api = ApiService();
  final TextEditingController _search = TextEditingController();
  bool _loading = true;
  String? _error;
  List<Driver> _drivers = <Driver>[];
  List<Driver> _filtered = <Driver>[];
  int _tabIndex = 0; // 0: Wanaodaiwa, 1: Wasiodaiwa, 2: Zote

  late final TabController _tabController;

  bool _listeningProvider = false;
  DebtsProvider? _debtsProvider;
  VoidCallback? _dpListener;

  // Month/Year quick filter
  MonthFilter _monthFilter = MonthFilter.zote;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabIndex != _tabController.index) {
        setState(() => _tabIndex = _tabController.index);
        _applyFilter();
      }
    });
    _search.addListener(_applyFilter);
    _loadDrivers();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final DebtsProvider dp = Provider.of<DebtsProvider>(context, listen: false);
    if (!_listeningProvider || _debtsProvider != dp) {
      // Remove old listener if provider instance changed
      if (_debtsProvider != null && _dpListener != null) {
        _debtsProvider!.removeListener(_dpListener!);
      }
      _debtsProvider = dp;
      _dpListener = () {
        if (!mounted) return;
        if (dp.shouldRefresh) {
          _loadDrivers();
          dp.consume();
        }
      };
      dp.addListener(_dpListener!);
      _listeningProvider = true;
    }
  }

  @override
  void dispose() {
    // Remove provider listener to avoid callbacks after dispose
    if (_debtsProvider != null && _dpListener != null) {
      _debtsProvider!.removeListener(_dpListener!);
    }
    _search.dispose();
    _tabController.dispose();
    super.dispose();
  }

  bool _autoOpened = false;
  Future<void> _loadDrivers() async {
    try {
      if (!mounted) return;
      setState(() {
        _loading = true;
        _error = null;
      });
      final Map<String, dynamic> res = await _api.getDebtDrivers(limit: 200);
      if (!mounted) return;
      final Map<String, dynamic>? data = res['data'] as Map<String, dynamic>?;
      final List<dynamic> list =
          (data?['drivers'] as List<dynamic>?) ?? <dynamic>[];
      _drivers =
          list.map((j) => Driver.fromJson(j as Map<String, dynamic>)).toList();
      if (mounted) _applyFilter();

      // If an initial driver was provided, open the create form prefilled once
      if (!_autoOpened && widget.initialDriverId != null) {
        final Driver d = _drivers.firstWhere(
          (Driver x) => x.id == widget.initialDriverId,
          orElse: () => Driver(
            id: widget.initialDriverId!,
            name: '',
            email: '',
            phone: '',
            licenseNumber: '',
            status: 'inactive',
            totalPayments: 0,
            joinedDate: DateTime.now(),
            rating: 0,
            tripsCompleted: 0,
          ),
        );
        _autoOpened = true;
        // Open form with driver (if found)
        await _openDetailForm(d);
      }
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _applyFilter() {
    if (!mounted) return;
    final String q = _search.text.toLowerCase();
    List<Driver> base = _drivers;

    // Tab filters
    if (_tabIndex == 0) {
      base = base.where((Driver d) => d.totalDebt > 0).toList();
    } else if (_tabIndex == 1) {
      base = base.where((Driver d) => d.totalDebt <= 0).toList();
    }

    // Month/Year quick filter (applies to debtors)
    base = base.where((Driver d) {
      if (d.totalDebt <= 0) {
        return true; // do not exclude non-debt in non-debt tab
      }
      if (_monthFilter == MonthFilter.zote) return true;
      if (d.dueDates.isEmpty) return false;
      final String next = d.dueDates.first;
      final DateTime? nd = DateTime.tryParse(next);
      if (nd == null) return false;
      final DateTime now = DateTime.now();
      switch (_monthFilter) {
        case MonthFilter.mweziHuu:
          return nd.year == now.year && nd.month == now.month;
        case MonthFilter.mweziUliopita:
          final DateTime lastMonth = DateTime(now.year, now.month - 1);
          return nd.year == lastMonth.year && nd.month == lastMonth.month;
        case MonthFilter.mwakaHuu:
          return nd.year == now.year;
        case MonthFilter.zote:
          return true;
      }
    }).toList();

    // Search text filter
    _filtered = base.where((Driver d) {
      return d.name.toLowerCase().contains(q) ||
          d.phone.toLowerCase().contains(q) ||
          (d.vehicleNumber ?? '').toLowerCase().contains(q) ||
          d.email.toLowerCase().contains(q);
    }).toList();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    ResponsiveHelper.init(context);
    return Consumer<LocalizationService>(
      builder: (context, localizationService, child) => Scaffold(
        backgroundColor: ThemeConstants.primaryBlue,
        appBar: ThemeConstants.buildAppBar(
            localizationService.translate('debt_records'),
            actions: <Widget>[
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadDrivers,
              ),
            ]),
        body: DecoratedBox(
          decoration: const BoxDecoration(color: ThemeConstants.primaryBlue),
          child: SafeArea(
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: _search,
                          style: const TextStyle(
                              color: ThemeConstants.textPrimary),
                          decoration: InputDecoration(
                            hintText: localizationService
                                .translate('search_driver_hint'),
                            hintStyle: const TextStyle(
                                color: ThemeConstants.textSecondary),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.08),
                            prefixIcon:
                                const Icon(Icons.search, color: Colors.white70),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: _loading ? null : _openCreateForm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ThemeConstants.primaryOrange,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.add),
                        label:
                            Text(localizationService.translate('record_debt')),
                      ),
                    ],
                  ),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    indicatorColor: ThemeConstants.primaryOrange,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white70,
                    tabs: <Widget>[
                      Tab(text: localizationService.translate('with_debts')),
                      Tab(text: localizationService.translate('without_debts')),
                      Tab(text: localizationService.translate('all')),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Month/Year quick filter chips
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 8,
                    children: <Widget>[
                      _buildFilterChip(
                          localizationService.translate('this_month'),
                          MonthFilter.mweziHuu),
                      _buildFilterChip(
                          localizationService.translate('last_month'),
                          MonthFilter.mweziUliopita),
                      _buildFilterChip(
                          localizationService.translate('this_year'),
                          MonthFilter.mwakaHuu),
                      _buildFilterChip(localizationService.translate('all'),
                          MonthFilter.zote),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _loading
                      ? ThemeConstants.buildLoadingWidget()
                      : _error != null
                          ? _buildError()
                          : _buildList(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildError() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.error_outline, color: Colors.redAccent),
            const SizedBox(height: 8),
            Consumer<LocalizationService>(
              builder: (context, localizationService, child) => Column(
                children: [
                  Text(_error ?? localizationService.translate('unknown_error'),
                      style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _loadDrivers,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ThemeConstants.primaryOrange,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(localizationService.translate('try_again')),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _buildList() {
    if (_filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.search_off, color: Colors.white54, size: 40),
            const SizedBox(height: 8),
            Consumer<LocalizationService>(
              builder: (context, localizationService, child) => Text(
                  localizationService.translate('no_results'),
                  style: const TextStyle(color: Colors.white70)),
            ),
          ],
        ),
      );
    }
    // Full-width list: the previous 2-column grid squeezed each card to
    // ~half the screen width, and each card's own 2-column info-box wrap
    // then squeezed those down further (~78px each) -- nowhere near enough
    // room for an icon + text like "License: D1234ABC" without truncating
    // to "licens e: D...". A single column gives every card, and every
    // info box inside it, the full width to breathe.
    return RefreshIndicator(
      color: Colors.white,
      backgroundColor: ThemeConstants.primaryBlue,
      onRefresh: _loadDrivers,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _filtered.length,
        separatorBuilder: (BuildContext context, int i) =>
            const SizedBox(height: 12),
        itemBuilder: (BuildContext context, int i) {
          final Driver d = _filtered[i];
          return _buildDriverTile(d);
        },
      ),
    );
  }

  Widget _buildDriverTile(Driver d) {
    final bool hasDebt = d.totalDebt > 0;
    return Consumer<LocalizationService>(
      builder: (context, localizationService, child) =>
          ThemeConstants.buildGlassCard(
        onTap: () => _openDriverRecords(d),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  CircleAvatar(
                    backgroundColor: ThemeConstants.cardColor,
                    child: Text(
                        d.name.isNotEmpty ? d.name[0].toUpperCase() : '?',
                        style: const TextStyle(color: Colors.white)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          d.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: (hasDebt
                                    ? ThemeConstants.errorRed
                                    : ThemeConstants.successGreen)
                                .withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            hasDebt
                                ? localizationService.translate('has_debt')
                                : localizationService.translate('no_debt'),
                            style: TextStyle(
                              color: hasDebt
                                  ? ThemeConstants.errorRed
                                  : ThemeConstants.successGreen,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Two-column details inside the tile
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints c) {
                  final double colW = (c.maxWidth - 8) / 2; // spacing 8
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      _infoBox(
                          Icons.badge,
                          '${localizationService.translate('license')}: ${d.licenseNumber}',
                          colW),
                      _infoBox(
                          Icons.payments,
                          '${localizationService.translate('debt')}: ${d.totalDebt.toStringAsFixed(0)}',
                          colW),
                      _infoBox(
                          Icons.event_available,
                          hasDebt && d.dueDates.isNotEmpty
                              ? '${localizationService.translate('next_due_date')}: ${d.dueDates.first}'
                              : localizationService.translate('no_due_date'),
                          colW),
                      _infoBox(
                          Icons.event,
                          hasDebt
                              ? '${localizationService.translate('debt_days')}: ${d.unpaidDays}'
                              : localizationService.translate('no_debt'),
                          colW),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoBox(IconData icon, String text, double width) => SizedBox(
        width: width,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: ThemeConstants.primaryBlue,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.25)),
          ),
          child: Row(
            children: <Widget>[
              Icon(icon, color: Colors.white70, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildFilterChip(String text, MonthFilter value) => FilterChip(
        label: Text(text,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600)),
        selected: _monthFilter == value,
        onSelected: (bool v) {
          setState(() => _monthFilter = value);
          _applyFilter();
        },
        selectedColor: ThemeConstants.primaryBlue,
        backgroundColor: ThemeConstants.primaryBlue,
        checkmarkColor: Colors.white,
        shape: StadiumBorder(
            side: BorderSide(color: Colors.white.withOpacity(0.25))),
      );

  void _openCreateForm() {
    _openDetailForm(null);
  }

  Future<void> _openDriverRecords(Driver d) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            DebtRecordsListScreen(driverId: d.id, driverName: d.name),
      ),
    );
  }

  Future<void> _openDetailForm(Driver? driver) async {
    final bool? changed = await Navigator.push(
      context,
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => DebtRecordFormScreen(driver: driver),
        fullscreenDialog: true,
      ),
    );
    if (changed ?? false) {
      await _loadDrivers();
      if (!context.mounted) return;
    }
  }
}

class DebtRecordFormScreen extends StatefulWidget {
  const DebtRecordFormScreen({super.key, this.driver});
  final Driver? driver;

  @override
  State<DebtRecordFormScreen> createState() => _DebtRecordFormScreenState();
}

class _DebtRecordFormScreenState extends State<DebtRecordFormScreen> {
  final ApiService _api = ApiService();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  final List<DateTime> _selectedDates = <DateTime>[];
  final Map<DateTime, TextEditingController> _amountCtrls =
      <DateTime, TextEditingController>{};
  bool _promised = false;
  DateTime? _promiseDate;
  bool _submitting = false;

  // Driver selection state
  List<Driver> _allDrivers = <Driver>[];
  List<Driver> _filteredDrivers = <Driver>[];
  Driver? _selectedDriver;
  bool _loadingDrivers = false;
  String? _driverLoadError;
  final TextEditingController _driverSearch = TextEditingController();

  // Agreement-derived defaults
  double? _agreementDefaultAmount;
  List<String> _agreementFrequencies = <String>[];

  @override
  void initState() {
    super.initState();
    _selectedDriver = widget.driver;
    // If a driver object was injected but has an empty/unknown id, clear it
    if (_selectedDriver != null && _selectedDriver!.id.trim().isEmpty) {
      _selectedDriver = null;
    }
    if (_selectedDriver == null) {
      _fetchDrivers();
    } else {
      // Preload agreement info for provided driver
      _fetchAgreementForDriver(_selectedDriver!.id);
    }
    // Initialize search filtering
    _driverSearch.addListener(() {
      final String q = _driverSearch.text.toLowerCase().trim();
      setState(() {
        if (q.isEmpty) {
          _filteredDrivers = List<Driver>.from(_allDrivers);
        } else {
          _filteredDrivers = _allDrivers.where((Driver d) {
            final String name = d.name.toLowerCase();
            final String phone = d.phone.toLowerCase();
            final String vehicle = (d.vehicleNumber ?? '').toLowerCase();
            final String license = d.licenseNumber.toLowerCase();
            return name.contains(q) ||
                phone.contains(q) ||
                vehicle.contains(q) ||
                license.contains(q);
          }).toList();
        }
      });
    });
  }

  Future<void> _fetchAgreementForDriver(String driverId) async {
    try {
      final Map<String, dynamic> res =
          await _api.getDriverAgreementByDriverId(driverId);
      final Map<String, dynamic>? data = res['data'] as Map<String, dynamic>?;
      double defAmount = 0;
      if (data != null) {
        defAmount = (data['default_amount'] is num)
            ? (data['default_amount'] as num).toDouble()
            : 0;
        if (defAmount == 0 && data['daily_amount'] is num) {
          defAmount = (data['daily_amount'] as num).toDouble();
        }
        if (defAmount == 0 && data['amount'] is num) {
          defAmount = (data['amount'] as num).toDouble();
        }
        if (defAmount == 0 && data['agreed_amount'] is num) {
          defAmount = (data['agreed_amount'] as num).toDouble();
        }
      }
      final List<String> freqs = <String>[];
      final dynamic f = data?['payment_frequencies'];
      if (f is List) {
        for (final dynamic x in f) {
          final String s = (x ?? '').toString();
          if (s.isNotEmpty) freqs.add(s);
        }
      }
      setState(() {
        _agreementDefaultAmount = defAmount > 0 ? defAmount : null;
        _agreementFrequencies = freqs;
      });
    } on Exception {
      setState(() {
        _agreementDefaultAmount = null;
        _agreementFrequencies = <String>[];
      });
    }
  }

  Future<void> _fetchDrivers() async {
    try {
      setState(() {
        _loadingDrivers = true;
        _driverLoadError = null;
      });
      final Map<String, dynamic> res = await _api.getDebtDrivers(limit: 200);
      final Map<String, dynamic>? data = res['data'] as Map<String, dynamic>?;
      final List<dynamic> list =
          (data?['drivers'] as List<dynamic>?) ?? <dynamic>[];
      _allDrivers =
          list.map((j) => Driver.fromJson(j as Map<String, dynamic>)).toList();
      _filteredDrivers = List<Driver>.from(_allDrivers);
      // Do not auto-select to force explicit choice
    } on Exception catch (e) {
      setState(() => _driverLoadError = e.toString());
    } finally {
      setState(() => _loadingDrivers = false);
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    _driverSearch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(LocalizationService.instance.translate('record_debt')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) =>
              SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: c.maxHeight - 32),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _buildDriverSelector(),
                    const SizedBox(height: 16),
                    _sectionTitle(LocalizationService.instance.translate('debt_start_date')),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        ..._selectedDates.map(_dateChip),
                        OutlinedButton.icon(
                          onPressed: _pickDate,
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                                color: Colors.white.withOpacity(0.4)),
                            foregroundColor: Colors.white,
                            backgroundColor: Colors.white.withOpacity(0.06),
                          ),
                          icon: const Icon(Icons.add),
                          label: Text(LocalizationService.instance.translate('add_date')),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Per-date amounts
                    ..._buildPerDateAmountFields(),
                    const SizedBox(height: 12),
                    _labelValue(LocalizationService.instance.translate('month_year'), _monthYearText()),
                    const SizedBox(height: 8),
                    // Subtotal row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text('${LocalizationService.instance.translate('total_dates_x_amount')}:',
                            style: TextStyle(color: Colors.white70)),
                        Text(
                          _subtotalText(),
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _notes,
                      minLines: 2,
                      maxLines: 4,
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDecorationWithIcon(
                          LocalizationService.instance.translate('debt_details_optional'), Icons.notes),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      value: _promised,
                      onChanged: (bool v) => setState(() => _promised = v),
                      title: Text('${LocalizationService.instance.translate('did_they_promise_to_pay')}?',
                          style: TextStyle(color: Colors.white)),
                      activeColor: ThemeConstants.primaryOrange,
                      contentPadding: EdgeInsets.zero,
                    ),
                    if (_promised) ...<Widget>[
                      const SizedBox(height: 8),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: _labelValue(
                              LocalizationService.instance.translate('promised_payment_date'),
                              _promiseDate == null
                                  ? LocalizationService.instance.translate('select_a_date')
                                  : _fmt(_promiseDate!),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: _pickPromiseDate,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: ThemeConstants.primaryOrange,
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.event),
                            label: Text(LocalizationService.instance.translate('select')),
                          )
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _submitting ? null : _submit,
                        icon: _submitting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.save),
                        label: Text(
                            _submitting ? '${LocalizationService.instance.translate('saving')}...' : LocalizationService.instance.translate('save_debt')),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ThemeConstants.primaryOrange,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 48),
                        ),
                      ),
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

  Widget _labelValue(String label, String value) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 4),
            Text(value.isEmpty ? '-' : value,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(left: 2),
        child: Text(
          t,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      );

  Widget _buildDriverSelector() {
    // If a driver is already selected (e.g., launched from a driver row), show the card and a change button
    if (_selectedDriver != null) {
      final Driver d = _selectedDriver!;
      final bool invalidInjected = d.id.trim().isEmpty || (!_allDrivers.any((Driver x) => x.id == d.id) && _allDrivers.isNotEmpty);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildDriverCard(d),
          if (invalidInjected) ...<Widget>[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
              ),
              child: Text(
                LocalizationService.instance.translate('the_driver_provided_is_not_valid'),
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => setState(() => _selectedDriver = null),
              icon:
                  const Icon(Icons.swap_horiz, color: Colors.white70, size: 18),
              label: Text(LocalizationService.instance.translate('change_driver'),
                  style: TextStyle(color: Colors.white70)),
            ),
          ),
          const SizedBox(height: 8),
          if (_agreementDefaultAmount != null ||
              _agreementFrequencies.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.18)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(LocalizationService.instance.translate('active_agreement'),
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 6),
                  if (_agreementFrequencies.isNotEmpty)
                    Text(LocalizationService.instance.translateWith('cycle', <Object?>[_agreementFrequencies.join(', ')]),
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600)),
                  if (_agreementDefaultAmount != null)
                    Text(
                        LocalizationService.instance.translateWith('default_amount_tsh', <Object?>[_agreementDefaultAmount!.toStringAsFixed(0)]),
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
        ],
      );
    }

    // Otherwise, show a dropdown to pick a driver
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _sectionTitle(LocalizationService.instance.translate('select_driver')),
        const SizedBox(height: 8),
        if (_loadingDrivers)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: <Widget>[
                SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white)),
                SizedBox(width: 8),
                Text('${LocalizationService.instance.translate('loading_drivers')}...',
                    style: TextStyle(color: Colors.white70)),
              ],
            ),
          )
        else if (_driverLoadError != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: <Widget>[
                const Icon(Icons.error_outline, color: Colors.white70),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(_driverLoadError!,
                        style: const TextStyle(color: Colors.white))),
                TextButton(
                  onPressed: _fetchDrivers,
                  child: Text(LocalizationService.instance.translate('try_again'),
                      style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          )
        else ...<Widget>[
          // Search box
          TextField(
            controller: _driverSearch,
            style: const TextStyle(color: Colors.white),
            decoration: _inputDecorationWithIcon(
                    LocalizationService.instance.translate('search_driver_by_name_phone_vehicle'),
                    Icons.search)
                .copyWith(
              suffixIcon: _driverSearch.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear,
                          color: Colors.white70, size: 18),
                      onPressed: _driverSearch.clear,
                    ),
            ),
          ),
          const SizedBox(height: 8),
          if (_filteredDrivers.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12)),
              child: Text(LocalizationService.instance.translate('no_search_results'),
                  style: TextStyle(color: Colors.white70)),
            )
          else
            DropdownButtonFormField<String>(
              isExpanded: true,
              decoration:
                  _inputDecorationWithIcon(LocalizationService.instance.translate('select_driver'), Icons.person),
              dropdownColor: ThemeConstants.primaryBlue,
              iconEnabledColor: Colors.white70,
              style: const TextStyle(color: Colors.white),
              items: _filteredDrivers.map((Driver d) {
                final String label =
                    d.vehicleNumber != null && d.vehicleNumber!.isNotEmpty
                        ? '${d.name} • ${d.vehicleNumber}'
                        : d.name;
                return DropdownMenuItem<String>(
                  value: d.id,
                  child: Text(label, overflow: TextOverflow.ellipsis),
                );
              }).toList(),
              onChanged: (String? id) {
                setState(() {
                  _selectedDriver =
                      _allDrivers.firstWhere((Driver d) => d.id == id);
                });
                if (id != null && id.isNotEmpty) {
                  _fetchAgreementForDriver(id);
                }
              },
              validator: (String? v) =>
                  (_selectedDriver == null) ? LocalizationService.instance.translate('select_driver') : null,
            ),
        ],
      ],
    );
  }

  Widget _buildDriverCard(Driver d) {
    final String name = d.name.isNotEmpty ? d.name : '-';
    final String license = d.licenseNumber.isNotEmpty ? d.licenseNumber : '-';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              CircleAvatar(
                backgroundColor: Colors.white.withOpacity(0.15),
                child: Text(
                  name.isNotEmpty && name != '-'
                      ? name.substring(0, 1).toUpperCase()
                      : '?',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(name,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(LocalizationService.instance.translateWith('license_2', <Object?>[license.isNotEmpty ? license : '-']),
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          if (license.isEmpty || license == '-') ...<Widget>[
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Icon(Icons.info_outline, color: Colors.white70, size: 16),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${LocalizationService.instance.translate('no_license_is_saved_on_the')}.',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white70),
        filled: true,
        fillColor: Colors.white.withOpacity(0.10),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.25)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide:
              const BorderSide(color: ThemeConstants.primaryOrange, width: 2),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      );

  InputDecoration _inputDecorationWithIcon(String hint, IconData icon) {
    final base = _inputDecoration(hint);
    return base.copyWith(
      prefixIcon: Icon(icon, color: Colors.white70, size: 18),
      prefixIconConstraints: const BoxConstraints(minWidth: 40),
    );
  }

  String _monthYearText() {
    if (_selectedDates.isEmpty) return '-';
    final DateTime d = _selectedDates.first;
    return '${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  Widget _dateChip(DateTime d) => Chip(
        label: Text(_fmt(d), style: const TextStyle(color: Colors.white)),
        backgroundColor: ThemeConstants.primaryBlue,
        shape: StadiumBorder(
            side: BorderSide(color: Colors.white.withOpacity(0.25))),
        deleteIcon: const Icon(Icons.close, color: Colors.white70, size: 18),
        labelPadding: const EdgeInsets.symmetric(horizontal: 10),
        onDeleted: () {
          setState(() {
            _selectedDates.remove(d);
            _amountCtrls.remove(d)?.dispose();
          });
        },
      );

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
      builder: (BuildContext context, Widget? child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: ThemeConstants.primaryOrange,
            surface: ThemeConstants.primaryBlue,
            onPrimary: Colors.white,
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (!_selectedDates.contains(picked)) {
          _selectedDates.add(picked);
          _amountCtrls[picked] = TextEditingController();
          // Prefill amount from agreement default when available
          final TextEditingController c = _amountCtrls[picked]!;
          if ((_agreementDefaultAmount ?? 0) > 0 && c.text.trim().isEmpty) {
            c.text = _agreementDefaultAmount!.toStringAsFixed(0);
          }
          _selectedDates.sort((DateTime a, DateTime b) => a.compareTo(b));
        }
      });
    }
  }

  Future<void> _pickPromiseDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _promiseDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
      builder: (BuildContext context, Widget? child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: ThemeConstants.primaryOrange,
            surface: ThemeConstants.primaryBlue,
            onPrimary: Colors.white,
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _promiseDate = picked);
  }

  String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _subtotalText() {
    double total = 0;
    for (final DateTime d in _selectedDates) {
      final c = _amountCtrls[d];
      if (c == null) continue;
      final double? v = double.tryParse(c.text.trim());
      if (v != null && v > 0) total += v;
    }
    return total.toStringAsFixed(0);
  }

  List<Widget> _buildPerDateAmountFields() {
    return _selectedDates.map((DateTime d) {
      final TextEditingController ctrl =
          _amountCtrls[d] ??= TextEditingController();
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_fmt(d), style: const TextStyle(color: Colors.white)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecorationWithIcon(
                    LocalizationService.instance.translate('amount_for_this_date'), Icons.payments),
                onChanged: (_) => setState(() {}),
                validator: (String? v) {
                  final double? val = double.tryParse((v ?? '').trim());
                  if (val == null || val <= 0) return LocalizationService.instance.translate('enter_a_valid_amount');
                  return null;
                },
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  bool _isKnownDriver(String id) => _allDrivers.any((Driver d) => d.id == id);

  Future<void> _submit() async {
    if (_selectedDates.isEmpty) {
      _showSnack(LocalizationService.instance.translate('add_at_least_one_debt_date'));
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    final String driverId = _selectedDriver?.id.trim() ?? widget.driver?.id.trim() ?? '';
    if (driverId.isEmpty || !_isKnownDriver(driverId)) {
      _showSnack(LocalizationService.instance.translate('please_select_a_valid_driver_first'));
      // If drivers not loaded yet, fetch to populate dropdown
      if (_allDrivers.isEmpty) {
        await _fetchDrivers();
      }
      return;
    }

    try {
      setState(() => _submitting = true);
      // Build items payload
      final List<Map<String, dynamic>> items = <Map<String, dynamic>>[];
      for (final DateTime d in _selectedDates) {
        final TextEditingController? ctrl = _amountCtrls[d];
        final double? val =
            ctrl == null ? null : double.tryParse(ctrl.text.trim());
        if (val == null || val <= 0) {
          _showSnack(LocalizationService.instance.translateWith('enter_a_valid_amount_for_date', <Object?>[_fmt(d)]));
          setState(() => _submitting = false);
          return;
        }
        items.add(<String, dynamic>{'date': _fmt(d), 'amount': val});
      }
      await _api.createDebts(
        driverId: driverId,
        items: items,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        promisedToPay: _promised,
        promiseToPayAt: _promiseDate,
      );
      if (!mounted) return;
      // Notify other pages (e.g., Malipo and Debts list) to refresh
      try {
        Provider.of<DebtsProvider>(context, listen: false).markChanged();
      } on Exception catch (_) {
        debugPrint('Provider notification failed');
      }

      // Emit events to notify other screens of debt changes
      AppEvents.instance.emit(AppEventType.debtsUpdated);
      AppEvents.instance.emit(AppEventType.receiptsUpdated);
      AppEvents.instance.emit(AppEventType.dashboardShouldRefresh);

      _showSnack(LocalizationService.instance.translate('debts_saved_successfully'), success: true);
      Navigator.pop(context, true);
    } on Exception catch (e) {
      _showSnack(LocalizationService.instance.translateWith('error_2', <Object?>[e]));
    } finally {
      setState(() => _submitting = false);
    }
  }

  void _showSnack(String m, {bool success = false}) {
    if (success) {
      ThemeConstants.showSuccessSnackBar(context, m);
    } else {
      ThemeConstants.showErrorSnackBar(context, m);
    }
  }
}
