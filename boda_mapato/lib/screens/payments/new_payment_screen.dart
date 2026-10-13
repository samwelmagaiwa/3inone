import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../constants/theme_constants.dart';
import '../../models/driver.dart';
import '../../providers/debts_provider.dart';
import '../../services/api_service.dart';
import '../../services/localization_service.dart';

class NewPaymentScreen extends StatefulWidget {
  const NewPaymentScreen({super.key, this.initialDriver});
  final Driver? initialDriver;

  @override
  State<NewPaymentScreen> createState() => _NewPaymentScreenState();
}

class _NewPaymentScreenState extends State<NewPaymentScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final ApiService _api = ApiService();

  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _dateCtrl = TextEditingController();
  final TextEditingController _monthForCtrl = TextEditingController();
  final TextEditingController _notesCtrl = TextEditingController();

  late DateTime _paymentDate;
  String? _driverId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _paymentDate = DateTime.now();
    _dateCtrl.text = DateFormat('yyyy-MM-dd').format(_paymentDate);
    _monthForCtrl.text = DateFormat('yyyy-MM')
        .format(DateTime(_paymentDate.year, _paymentDate.month));
    _driverId = widget.initialDriver?.id;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _dateCtrl.dispose();
    _monthForCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDate: _paymentDate,
      builder: (BuildContext context, Widget? child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: ThemeConstants.primaryOrange,
            surface: ThemeConstants.primaryBlue,
            onPrimary: Colors.white,
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
            ),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _paymentDate = picked;
        _dateCtrl.text = DateFormat('yyyy-MM-dd').format(picked);
        // Default month_for to selected date's month
        _monthForCtrl.text =
            DateFormat('yyyy-MM').format(DateTime(picked.year, picked.month));
      });
    }
  }

  InputDecoration _inputDecoration({String? hintText, Widget? suffixIcon}) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(
        color: Colors.white70,
        fontSize: 14,
      ),
      filled: true,
      fillColor: Colors.white.withOpacity(0.10),
      suffixIcon: suffixIcon,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: Colors.white.withOpacity(0.3),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: Colors.white.withOpacity(0.3),
        ),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(
          color: ThemeConstants.primaryOrange,
          width: 2,
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if ((_driverId ?? '').isEmpty) return;

    setState(() => _saving = true);
    try {
      final Map<String, dynamic> payload = <String, dynamic>{
        'driver_id': _driverId,
        'amount': double.parse(_amountCtrl.text.trim()),
        'payment_date': _dateCtrl.text.trim(),
        if (_monthForCtrl.text.trim().isNotEmpty)
          'month_for': _monthForCtrl.text.trim(),
        if (_notesCtrl.text.trim().isNotEmpty) 'notes': _notesCtrl.text.trim(),
      };
      await _api.storeNewPayment(payload);
      if (!mounted) return;
      // notify debts-related views to refresh state
      try {
        Provider.of<DebtsProvider>(context, listen: false).markChanged();
      } on Exception catch (_) {}
      ThemeConstants.showSuccessSnackBar(context, LocalizationService.instance.translate('payment_recorded'));
      Navigator.pop(context);
    } on ApiException catch (e) {
      ThemeConstants.showErrorSnackBar(
          context, LocalizationService.instance.translateWith('could_not_save', <Object?>[e.message]));
    } on Exception catch (e) {
      ThemeConstants.showErrorSnackBar(context, LocalizationService.instance.translateWith('error_2', <Object?>[e]));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ThemeConstants.buildScaffold(
      title: LocalizationService.instance.translate('record_new_payment'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Driver (read-only or input)
              ThemeConstants.buildGlassCardStatic(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.person, color: Colors.white70, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.initialDriver?.name ??
                              LocalizationService.instance.translateWith('driver_id', <Object?>[_driverId ?? '']),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Amount
              Text(LocalizationService.instance.translate('amount_tsh'),
                  style: TextStyle(color: Colors.white, fontSize: 13)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration(hintText: LocalizationService.instance.translate('enter_the_amount')),
                validator: (v) {
                  final a = double.tryParse(v ?? '');
                  if (a == null || a <= 0) return LocalizationService.instance.translate('enter_a_valid_amount');
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Payment date
              Text(LocalizationService.instance.translate('payment_date'),
                  style: TextStyle(color: Colors.white, fontSize: 13)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _dateCtrl,
                readOnly: true,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration(
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.date_range, color: Colors.white70),
                    onPressed: _pickDate,
                  ),
                ),
                onTap: _pickDate,
              ),
              const SizedBox(height: 12),

              // Month for
              Text(LocalizationService.instance.translate('related_month_optional'),
                  style: TextStyle(color: Colors.white, fontSize: 13)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _monthForCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration(hintText: LocalizationService.instance.translate('example_2025_10')),
              ),
              const SizedBox(height: 12),

              // Notes
              Text(LocalizationService.instance.translate('note_optional'),
                  style: TextStyle(color: Colors.white, fontSize: 13)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _notesCtrl,
                maxLines: 3,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration(),
              ),
              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ThemeConstants.primaryOrange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      if (_saving) ...[
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white)),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(LocalizationService.instance.translate('save_payment')),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
