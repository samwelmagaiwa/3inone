import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../constants/theme_constants.dart';
import '../../services/api_service.dart';
import '../../utils/responsive_helper.dart';
import '../../services/localization_service.dart';

enum PredictionMode { auto, average, regression }

class DriverPredictionScreen extends StatefulWidget {
  const DriverPredictionScreen(
      {required this.driverId, required this.driverName, super.key});
  final String driverId;
  final String driverName;

  @override
  State<DriverPredictionScreen> createState() => _DriverPredictionScreenState();
}

class _DriverPredictionScreenState extends State<DriverPredictionScreen> {
  final ApiService _api = ApiService();
  bool _loading = true;
  String? _error;
  bool _serverUsed = false;

  // Data
  double _totalPaid = 0;
  double _totalAmount =
      0; // from agreement.total_amount|total_profit|expected_total
  DateTime? _startDate;
  DateTime? _endDate; // may be null for Dei Waka
  bool _weekendsCountable = true;
  bool _satIncluded = true;
  bool _sunIncluded = true;

  // Chart points
  final List<FlSpot> _spots = <FlSpot>[];
  final List<String> _labels = <String>[];
  Map<DateTime, double> _perDay = <DateTime, double>{};

  // Prediction
  bool _onTrack = false;
  DateTime? _predictedDate;
  int _estimatedDelayDays = 0;
  int? _confidenceDays;
  PredictionMode _mode = PredictionMode.auto;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _serverUsed = false;
    });
    try {
      await _api.initialize();

      // Try server-side prediction first
      try {
        final Map<String, dynamic> pred =
            await _api.getDriverPrediction(widget.driverId);
        final dynamic pdata = pred['data'] ?? pred;
        if (pdata is Map<String, dynamic>) {
          _totalPaid = _num(pdata['total_paid']);
          _totalAmount = _num(pdata['total_amount']);
          _startDate = _parseDate(pdata['start_date'] ??
              pdata['contract_start'] ??
              pdata['agreement_start']);
          _endDate = _parseDate(pdata['predicted_end'] ??
              pdata['contract_end'] ??
              pdata['agreement_end']);
          final List<dynamic> ph =
              List<dynamic>.from(pdata['payment_history'] ?? <dynamic>[]);
          // Build per-day map and chart from server history
          _perDay.clear();
          _spots.clear();
          _labels.clear();
          ph.sort((a, b) => ((a as Map<String, dynamic>)['date'] ?? '')
              .toString()
              .compareTo(
                  ((b as Map<String, dynamic>)['date'] ?? '').toString()));
          double running = 0;
          for (int i = 0; i < ph.length; i++) {
            final Map<String, dynamic> item = ph[i] as Map<String, dynamic>;
            final DateTime? d = _parseDate(item['date']);
            final double amt = _parseNum(item['amount']) ?? 0;
            if (d != null) {
              final DateTime day = DateTime(d.year, d.month, d.day);
              _perDay.update(day, (v) => v + amt, ifAbsent: () => amt);
              running += amt;
              _spots.add(FlSpot(i.toDouble(), running));
              _labels.add(DateFormat('dd/MM').format(day));
            }
          }
          // Prediction results from server if provided
          _onTrack = (pdata['on_track'] ?? false) == true;
          _predictedDate = _parseDate(pdata['predicted_date']);
          _estimatedDelayDays =
              int.tryParse((pdata['estimated_delay_days'] ?? 0).toString()) ??
                  0;
          _confidenceDays =
              int.tryParse((pdata['confidence_days'] ?? '').toString());
          _weekendsCountable = (pdata['weekends_countable'] ?? true) == true;
          _satIncluded = (pdata['saturday_included'] ?? true) == true;
          _sunIncluded = (pdata['sunday_included'] ?? true) == true;

          // If server provided prediction fields, keep them; otherwise compute locally
          if (pdata['predicted_date'] == null) {
            _recomputePrediction();
          }
          _serverUsed = true;
        }
      } on Exception catch (_) {
        _serverUsed = false; // fall back to local compute below
      }

      if (_serverUsed) {
        setState(() => _loading = false);
        return;
      }

      final agreementResp =
          await _api.getDriverAgreementByDriverId(widget.driverId);
      final dynamic aData = agreementResp['data'] ?? agreementResp;
      if (aData is! Map<String, dynamic>) {
        throw Exception(LocalizationService.instance.translate('agreement_not_found'));
      }

      _totalAmount = _parseNum(aData['total_amount']) ??
          _parseNum(aData['total_profit']) ??
          _parseNum(aData['grand_total']) ??
          _parseNum(aData['expected_total']) ??
          0.0;
      _startDate = _parseDate(aData['start_date']);
      _endDate = _parseDate(aData['end_date']);
      _weekendsCountable = (aData['weekends_countable'] ?? true) == true;
      _satIncluded = (aData['saturday_included'] ?? true) == true;
      _sunIncluded = (aData['sunday_included'] ?? true) == true;

      // Payment history
      final Map<String, dynamic> history = await _api.getPaymentHistory(
        driverId: widget.driverId,
        limit: 500, // fetch enough points
      );

      final List<dynamic> rows = (history['data'] is Map)
          ? List<dynamic>.from(
              (history['data'] as Map<String, dynamic>)['data'] ?? <dynamic>[])
          : (history['data'] is List)
              ? List<dynamic>.from(history['data'])
              : <dynamic>[];

      // Build daily series (date->sum)
      final Map<DateTime, double> perDay = <DateTime, double>{};
      for (final dynamic r in rows) {
        if (r is! Map) continue;
        final DateTime? d =
            _parseDate(r['date'] ?? r['paid_at'] ?? r['created_at']);
        final double amt =
            _parseNum(r['amount'] ?? r['total'] ?? r['paid_amount']) ?? 0;
        if (d == null) continue;
        final DateTime day = DateTime(d.year, d.month, d.day);
        perDay.update(day, (v) => v + amt, ifAbsent: () => amt);
      }

      // Accumulate total paid and produce chart points
      _perDay = perDay;
      final List<DateTime> sortedDays = perDay.keys.toList()..sort();
      double running = 0;
      _spots.clear();
      _labels.clear();
      for (int i = 0; i < sortedDays.length; i++) {
        running += perDay[sortedDays[i]] ?? 0;
        _spots.add(FlSpot(i.toDouble(), running));
        _labels.add(DateFormat('dd/MM').format(sortedDays[i]));
      }
      _totalPaid = running;

      // Prediction based on selected mode
      _recomputePrediction();

      setState(() => _loading = false);
    } on Exception catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _recomputePrediction() {
    switch (_mode) {
      case PredictionMode.auto:
        _computePredictionAuto(_perDay);
      case PredictionMode.regression:
        _computePredictionRegression(_perDay);
      case PredictionMode.average:
        _computePredictionAverage(_perDay);
    }
  }

  void _computePredictionAuto(Map<DateTime, double> perDay) {
    // Choose the best among regression and EWMA/average using simple criteria
    if (_startDate == null) {
      _computePredictionAverage(perDay);
      return;
    }
    // Prefer regression when trend is stable and positive
    final _RegResult reg = _fitRegression(perDay);
    if (reg.valid && reg.r2 >= 0.6 && reg.a > 0) {
      _applyPredictionFromIncludedDays(
          (reg.xStarCeil - reg.xNow).clamp(0, 36500));
      return;
    }
    // Else use recency-weighted average (EWMA). If that yields zero, fallback to average
    final double ewma = _computeEwmaDailyRate(perDay);
    if (ewma > 0) {
      _applyPredictionFromRate(ewma);
      return;
    }
    _computePredictionAverage(perDay);
  }

  void _applyPredictionFromIncludedDays(int neededIncludedDays) {
    final DateTime t = DateTime.now();
    DateTime pd = t;
    int added = 0;
    while (added < neededIncludedDays) {
      pd = pd.add(const Duration(days: 1));
      if (_isIncluded(pd)) added++;
    }
    _predictedDate = pd;
    if (_endDate != null) {
      final DateTime end =
          DateTime(_endDate!.year, _endDate!.month, _endDate!.day);
      _onTrack = !pd.isAfter(end);
      _estimatedDelayDays = _onTrack ? 0 : pd.difference(end).inDays;
    } else {
      _onTrack = true;
      _estimatedDelayDays = 0;
    }
  }

  void _applyPredictionFromRate(double ratePerIncludedDay) {
    final double remaining = max(_totalAmount - _totalPaid, 0);
    if (ratePerIncludedDay <= 0 || remaining <= 0) {
      _onTrack = true;
      _predictedDate = DateTime.now();
      _estimatedDelayDays = 0;
      return;
    }
    final int need = (remaining / ratePerIncludedDay).ceil();
    _applyPredictionFromIncludedDays(need);
  }

  double _computeEwmaDailyRate(Map<DateTime, double> perDay,
      {int windowDays = 60, double alpha = 0.3}) {
    if (_startDate == null || perDay.isEmpty) return 0;
    final DateTime startWindow =
        DateTime.now().subtract(Duration(days: windowDays));
    double ewma = 0;
    bool initialized = false;
    // iterate chronologically
    final List<DateTime> days = perDay.keys.toList()..sort();
    for (final DateTime d in days) {
      if (d.isBefore(startWindow)) continue;
      final double x = perDay[d] ?? 0;
      if (!initialized) {
        ewma = x;
        initialized = true;
      } else {
        ewma = alpha * x + (1 - alpha) * ewma;
      }
    }
    if (!initialized) return 0;
    // Convert per-day payment amount to average per included day by dividing by 1 included day per entry
    // Since each entry represents a day, ewma already stands for average per included day in window
    return ewma;
  }

  _RegResult _fitRegression(Map<DateTime, double> perDay) {
    if (_startDate == null || perDay.length < 2) {
      return _RegResult.invalid();
    }
    final List<DateTime> days = perDay.keys.toList()..sort();
    double running = 0;
    final List<double> xs = <double>[];
    final List<double> ys = <double>[];
    for (final DateTime d in days) {
      running += perDay[d] ?? 0;
      final int xIndex = _countIncludedDays(_startDate!, d);
      xs.add(xIndex.toDouble());
      ys.add(running);
    }
    final int n = xs.length;
    double sumx = 0;
    double sumy = 0;
    double sumxy = 0;
    double sumx2 = 0;
    for (int i = 0; i < n; i++) {
      final double x = xs[i];
      final double y = ys[i];
      sumx += x;
      sumy += y;
      sumxy += x * y;
      sumx2 += x * x;
    }
    final double denom = (n * sumx2) - (sumx * sumx);
    if (denom.abs() < 1e-6) return _RegResult.invalid();
    final double a = ((n * sumxy) - (sumx * sumy)) / denom;
    final double b = (sumy / n) - a * (sumx / n);
    // R^2
    double ssTot = 0;
    double ssRes = 0;
    final double yMean = sumy / n;
    for (int i = 0; i < n; i++) {
      final double yHat = a * xs[i] + b;
      ssRes += pow(ys[i] - yHat, 2) as double;
      ssTot += pow(ys[i] - yMean, 2) as double;
    }
    final double r2 = ssTot.abs() < 1e-6 ? 0 : 1 - (ssRes / ssTot);
    final int xNow = _countIncludedDays(_startDate!, DateTime.now());
    final double xStar = (_totalAmount - b) / (a == 0 ? 1e-6 : a);
    final int xStarCeil = xStar.isNaN || xStar.isInfinite ? xNow : xStar.ceil();
    return _RegResult(
        valid: true, a: a, b: b, r2: r2, xNow: xNow, xStarCeil: xStarCeil);
  }

  void _computePredictionAverage(Map<DateTime, double> perDay) {
    if (_startDate == null) {
      _onTrack = false;
      _predictedDate = null;
      _estimatedDelayDays = 0;
      return;
    }

    final DateTime today = DateTime.now();
    final DateTime s =
        DateTime(_startDate!.year, _startDate!.month, _startDate!.day);
    final DateTime t = DateTime(today.year, today.month, today.day);

    int includedDays = 0;
    DateTime d = s;
    while (!d.isAfter(t)) {
      if (_isIncluded(d)) includedDays++;
      d = d.add(const Duration(days: 1));
    }
    includedDays = max(includedDays, 1);

    final double rate = _totalPaid / includedDays; // average per included day

    if (_totalAmount <= 0 || rate <= 0) {
      _onTrack = false;
      _predictedDate = null;
      _estimatedDelayDays = 0;
      return;
    }

    final double remaining = max(_totalAmount - _totalPaid, 0);
    final int neededIncludedDays = (remaining / rate).ceil();

    // Convert needed included days to a calendar date respecting inclusion rules
    DateTime pd = t;
    int added = 0;
    while (added < neededIncludedDays) {
      pd = pd.add(const Duration(days: 1));
      if (_isIncluded(pd)) added++;
    }
    _predictedDate = pd;

    if (_endDate != null) {
      final DateTime end =
          DateTime(_endDate!.year, _endDate!.month, _endDate!.day);
      _onTrack = !pd.isAfter(end);
      _estimatedDelayDays = _onTrack ? 0 : pd.difference(end).inDays;
    } else {
      _onTrack = true; // open-ended contract
      _estimatedDelayDays = 0;
    }
  }

  void _computePredictionRegression(Map<DateTime, double> perDay) {
    if (_startDate == null || _totalAmount <= 0 || perDay.isEmpty) {
      _computePredictionAverage(perDay);
      return;
    }
    final List<DateTime> days = perDay.keys.toList()..sort();
    if (days.length < 2) {
      _computePredictionAverage(perDay);
      return;
    }
    // Build regression points: x = included day index since start (inclusive), y = cumulative paid
    double running = 0;
    final List<double> xs = <double>[];
    final List<double> ys = <double>[];
    for (final DateTime d in days) {
      running += perDay[d] ?? 0;
      final int xIndex = _countIncludedDays(_startDate!, d); // inclusive index
      xs.add(xIndex.toDouble());
      ys.add(running);
    }
    final int n = xs.length;
    double sumx = 0;
    double sumy = 0;
    double sumxy = 0;
    double sumx2 = 0;
    for (int i = 0; i < n; i++) {
      final double x = xs[i];
      final double y = ys[i];
      sumx += x;
      sumy += y;
      sumxy += x * y;
      sumx2 += x * x;
    }
    final double denom = (n * sumx2) - (sumx * sumx);
    if (denom.abs() < 1e-6) {
      _computePredictionAverage(perDay);
      return;
    }
    final double a =
        ((n * sumxy) - (sumx * sumy)) / denom; // slope per included day
    final double b = (sumy / n) - a * (sumx / n);
    if (a <= 0) {
      _computePredictionAverage(perDay);
      return;
    }
    final int xNow = _countIncludedDays(_startDate!, DateTime.now());
    double xStar = (_totalAmount - b) / a;
    if (xStar.isNaN || xStar.isInfinite) {
      _computePredictionAverage(perDay);
      return;
    }
    if (xStar < xNow) xStar = xNow.toDouble();
    final int need = (xStar.ceil() - xNow).clamp(0, 36500);
    DateTime pd = DateTime.now();
    int added = 0;
    while (added < need) {
      pd = pd.add(const Duration(days: 1));
      if (_isIncluded(pd)) added++;
    }
    _predictedDate = pd;
    if (_endDate != null) {
      final DateTime end =
          DateTime(_endDate!.year, _endDate!.month, _endDate!.day);
      _onTrack = !pd.isAfter(end);
      _estimatedDelayDays = _onTrack ? 0 : pd.difference(end).inDays;
    } else {
      _onTrack = true;
      _estimatedDelayDays = 0;
    }
  }

  bool _isIncluded(DateTime d) {
    final int wd = d.weekday; // 1=Mon..7=Sun
    if (!_weekendsCountable) {
      return !(wd == DateTime.saturday || wd == DateTime.sunday);
    }
    if (wd == DateTime.saturday && !_satIncluded) return false;
    if (wd == DateTime.sunday && !_sunIncluded) return false;
    return true;
  }

  DateTime? _parseDate(Object? v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
    return null;
  }

  double? _parseNum(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  double _num(Object? v) => _parseNum(v) ?? 0.0;

  String _ts(num x) => NumberFormat('#,##0', 'sw_TZ').format(x);

  @override
  Widget build(BuildContext context) {
    ResponsiveHelper.init(context);
    return ThemeConstants.buildResponsiveScaffold(
      context,
      title: LocalizationService.instance.translateWith('prediction_2', <Object?>[widget.driverName]),
      body: _loading
          ? ThemeConstants.buildResponsiveLoadingWidget(context)
          : _error != null
              ? _buildError(_error!)
              : _buildBody(),
    );
  }

  Widget _buildError(String message) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            message,
            style: const TextStyle(color: Colors.white),
            textAlign: TextAlign.center,
          ),
        ),
      );

  Widget _buildBody() {
    final double balance = max(_totalAmount - _totalPaid, 0);
    final int daysPassed = _startDate == null
        ? 0
        : _countIncludedDays(_startDate!, DateTime.now());
    final int totalDays = (_startDate != null && _endDate != null)
        ? _countIncludedDays(_startDate!, _endDate!)
        : 0;

    return SingleChildScrollView(
      padding: ResponsiveHelper.defaultPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Mode toggle (wrap to avoid horizontal overflow on small screens)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: Text(LocalizationService.instance.translate('auto_best')),
                selected: _mode == PredictionMode.auto,
                onSelected: (sel) {
                  if (sel) {
                    setState(() {
                      _mode = PredictionMode.auto;
                      _recomputePrediction();
                    });
                  }
                },
              ),
              ChoiceChip(
                label: Text(LocalizationService.instance.translate('daily_average_2')),
                selected: _mode == PredictionMode.average,
                onSelected: (sel) {
                  if (sel) {
                    setState(() {
                      _mode = PredictionMode.average;
                      _recomputePrediction();
                    });
                  }
                },
              ),
              ChoiceChip(
                label: Text(LocalizationService.instance.translate('regression_linear')),
                selected: _mode == PredictionMode.regression,
                onSelected: (sel) {
                  if (sel) {
                    setState(() {
                      _mode = PredictionMode.regression;
                      _recomputePrediction();
                    });
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Summary cards
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              _summaryCard(
                  LocalizationService.instance.translate('payments_total_label'),
                  LocalizationService.instance.translateWith('tsh_of', <Object?>[_ts(_totalPaid), _ts(_totalAmount)]),
                  Icons.payments,
                  ThemeConstants.primaryOrange),
              _summaryCard(LocalizationService.instance.translate('remaining_debt_2'), 'TSH ${_ts(balance)}',
                  Icons.account_balance_wallet, ThemeConstants.warningAmber),
              _summaryCard(
                  LocalizationService.instance.translate('agreement_progress'),
                  _endDate == null
                      ? LocalizationService.instance.translateWith('days_3', <Object?>[daysPassed])
                      : LocalizationService.instance.translateWith('of_days', <Object?>[daysPassed, totalDays]),
                  Icons.calendar_today,
                  Colors.lightBlueAccent),
            ],
          ),
          const SizedBox(height: 16),

          // Chart
          ThemeConstants.buildGlassCardStatic(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                height: 260,
                width: double.infinity,
                child: _spots.isEmpty
                    ? Center(
                        child: Text(
                          LocalizationService.instance.translate('no_payment_history_to_show'),
                          style: TextStyle(color: Colors.white70),
                        ),
                      )
                    : LineChart(
                        LineChartData(
                          backgroundColor: Colors.transparent,
                          titlesData: FlTitlesData(
                            rightTitles: const AxisTitles(),
                            topTitles: const AxisTitles(),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 42,
                                getTitlesWidget: (value, meta) => Text(
                                  _ts(value),
                                  style: const TextStyle(
                                      color: Colors.white60, fontSize: 10),
                                ),
                              ),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                interval: max(
                                    1, (_labels.length / 6).floorToDouble()),
                                getTitlesWidget: (value, meta) {
                                  final int i = value.toInt();
                                  if (i >= 0 && i < _labels.length) {
                                    return Text(_labels[i],
                                        style: const TextStyle(
                                            color: Colors.white60,
                                            fontSize: 10));
                                  }
                                  return const SizedBox.shrink();
                                },
                              ),
                            ),
                          ),
                          gridData: FlGridData(
                              drawVerticalLine: false,
                              getDrawingHorizontalLine: (v) => const FlLine(
                                  color: Colors.white12, strokeWidth: 1)),
                          borderData: FlBorderData(show: false),
                          lineBarsData: [
                            LineChartBarData(
                              spots: _spots,
                              isCurved: true,
                              color: ThemeConstants.primaryOrange,
                              barWidth: 3,
                              belowBarData: BarAreaData(
                                  show: true,
                                  color: ThemeConstants.primaryOrange
                                      .withOpacity(0.15)),
                              dotData: const FlDotData(show: false),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Prediction result
          ThemeConstants.buildGlassCardStatic(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _buildPredictionWidget(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(String title, String value, IconData icon, Color color) =>
      ThemeConstants.buildGlassCardStatic(
        child: Container(
          constraints: const BoxConstraints(minWidth: 260),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: <Widget>[
              Icon(icon, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(title,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildPredictionWidget() {
    if (_predictedDate == null) {
      return Text(
        LocalizationService.instance.translate('a_prediction_is_not_possible_there'),
        style: TextStyle(color: Colors.white70),
      );
    }

    final String dateStr = DateFormat('dd/MM/yyyy').format(_predictedDate!);
    final String message = _onTrack
        ? LocalizationService.instance.translateWith('the_driver_is_on_track_expected', <Object?>[dateStr])
        : LocalizationService.instance.translateWith('may_not_finish_on_time_estimated', <Object?>[_estimatedDelayDays, dateStr]);

    final String modeLabel = () {
      switch (_mode) {
        case PredictionMode.auto:
          return LocalizationService.instance.translate('method_auto');
        case PredictionMode.regression:
          return LocalizationService.instance.translate('method_regression');
        case PredictionMode.average:
          return LocalizationService.instance.translate('method_average');
      }
    }();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_onTrack ? Icons.check_circle : Icons.warning_amber,
                color: _onTrack ? Colors.greenAccent : Colors.amber),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            Text(
              modeLabel,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
            if (_confidenceDays != null)
              Text(
                LocalizationService.instance.translateWith('confidence_days', <Object?>[_confidenceDays]),
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          LocalizationService.instance.translate('explanation_this_prediction_is_an_estimate'),
          style: TextStyle(color: Colors.white60, fontSize: 12),
        ),
      ],
    );
  }

  int _countIncludedDays(DateTime start, DateTime end) {
    DateTime s = DateTime(start.year, start.month, start.day);
    DateTime e = DateTime(end.year, end.month, end.day);
    if (e.isBefore(s)) {
      final tmp = s;
      s = e;
      e = tmp;
    }
    int count = 0;
    DateTime d = s;
    while (!d.isAfter(e)) {
      if (_isIncluded(d)) count++;
      d = d.add(const Duration(days: 1));
    }
    return count == 0
        ? 1
        : count; // at least 1 if inclusive start=end day is included
  }
}

class _RegResult {
  const _RegResult(
      {required this.valid,
      required this.a,
      required this.b,
      required this.r2,
      required this.xNow,
      required this.xStarCeil});
  factory _RegResult.invalid() =>
      const _RegResult(valid: false, a: 0, b: 0, r2: 0, xNow: 0, xStarCeil: 0);

  final bool valid;
  final double a;
  final double b;
  final double r2;
  final int xNow;
  final int xStarCeil;
}
