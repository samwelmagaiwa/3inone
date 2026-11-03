import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../models/existing_customer.dart';

/// What the dialog hands back: the customer to use, and whether they were already saved (so nobody is saved twice).
class CustomerChoice {
  const CustomerChoice({required this.id, required this.name, this.existed = false});

  final int id;
  final String name;
  final bool existed;
}

typedef CustomerLookup = Future<ExistingCustomer?> Function(String name, String phone);
typedef CustomerSaver = Future<CustomerChoice?> Function({required String name, required String phone, String? address});

/// A phone number has at least nine digits (0743519104, 743519104, +255743519104 all do).
bool isValidCustomerPhone(final String phone) => phone.replaceAll(RegExp(r'\D'), '').length >= 9;

/// Adds a customer at the till. A customer is saved ONLY with a phone number, and only once: while the name or the number is typed
/// the dialog asks whether that customer is already saved, and if so shows them with a button to use them instead of saving a second one.
class AddCustomerDialog extends StatefulWidget {
  const AddCustomerDialog({super.key, required this.lookup, required this.save, this.debounce = const Duration(milliseconds: 400)});

  final CustomerLookup lookup;
  final CustomerSaver save;
  final Duration debounce;

  @override
  State<AddCustomerDialog> createState() => _AddCustomerDialogState();
}

class _AddCustomerDialogState extends State<AddCustomerDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _address = TextEditingController();
  Timer? _timer;
  ExistingCustomer? _found;
  bool _saving = false;
  bool _tried = false;
  int _ask = 0;

  @override
  void dispose() {
    _timer?.cancel();
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  /// Asks, a moment after the typing stops, whether this name or number is already saved.
  void _typed() {
    setState(() {});
    _timer?.cancel();
    final String name = _name.text.trim();
    final String phone = _phone.text.trim();
    if (name.length < 2 && !isValidCustomerPhone(phone)) {
      setState(() => _found = null);

      return;
    }
    _timer = Timer(widget.debounce, () async {
      final int ask = ++_ask;
      ExistingCustomer? found;
      try {
        found = await widget.lookup(name, isValidCustomerPhone(phone) ? phone : '');
      } on Exception {
        found = null;
      }
      if (mounted && ask == _ask) setState(() => _found = found);
    });
  }

  String? get _phoneError {
    final LocalizationService loc = LocalizationService.instance;
    final String p = _phone.text.trim();
    if (p.isEmpty) return _tried ? loc.translate('customer_phone_required') : null;

    return isValidCustomerPhone(p) ? null : loc.translate('customer_phone_required');
  }

  Future<void> _submit() async {
    final LocalizationService loc = LocalizationService.instance;
    final ExistingCustomer? found = _found;
    if (found != null) {
      Navigator.of(context).pop(CustomerChoice(id: found.id, name: found.name, existed: true));

      return;
    }
    setState(() => _tried = true);
    if (_name.text.trim().isEmpty) {
      ThemeConstants.showWarningSnackBar(context, loc.translate('customer_name_required'));

      return;
    }
    if (!isValidCustomerPhone(_phone.text.trim())) return;

    setState(() => _saving = true);
    final CustomerChoice? saved = await widget.save(name: _name.text.trim(), phone: _phone.text.trim(), address: _address.text.trim());
    if (!mounted) return;
    if (saved == null) {
      setState(() => _saving = false);
      ThemeConstants.showErrorSnackBar(context, loc.translate('customer_save_failed'));

      return;
    }
    Navigator.of(context).pop(saved);
  }

  @override
  Widget build(final BuildContext context) {
    final LocalizationService loc = LocalizationService.instance;
    final ExistingCustomer? found = _found;

    return AlertDialog(
      backgroundColor: ThemeConstants.primaryBlue,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
      title: Text(loc.translate('add_customer'), style: ThemeConstants.bodyStyle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(key: const ValueKey<String>('new_customer_name'), controller: _name, onChanged: (_) => _typed(), textCapitalization: TextCapitalization.words, decoration: ThemeConstants.invInputDecoration(loc.translate('customer_name')), style: ThemeConstants.bodyStyle),
            SizedBox(height: 8.h),
            TextField(
              key: const ValueKey<String>('new_customer_phone'),
              controller: _phone,
              onChanged: (_) => _typed(),
              keyboardType: TextInputType.phone,
              inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
              decoration: ThemeConstants.invInputDecoration(loc.translate('phone_number')).copyWith(errorText: _phoneError, errorStyle: const TextStyle(color: ThemeConstants.errorText)),
              style: ThemeConstants.bodyStyle,
            ),
            SizedBox(height: 8.h),
            TextField(key: const ValueKey<String>('new_customer_address'), controller: _address, decoration: ThemeConstants.invInputDecoration(loc.translate('address')), style: ThemeConstants.bodyStyle),
            if (found != null)
              Container(
                key: const ValueKey<String>('customer_already_saved'),
                width: double.infinity,
                margin: EdgeInsets.only(top: 10.h),
                padding: EdgeInsets.all(10.w),
                decoration: BoxDecoration(color: ThemeConstants.warningAmber.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(10.r), border: Border.all(color: ThemeConstants.warningAmber)),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.info_outline_rounded, color: ThemeConstants.warningAmber, size: 20.sp),
                    SizedBox(width: 8.w),
                    Expanded(child: Text(loc.translate('customer_already_saved').replaceAll('{name}', found.name).replaceAll('{phone}', found.phone), style: ThemeConstants.captionStyle.copyWith(color: Colors.white))),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: Text(loc.translate('cancel'))),
        ElevatedButton(
          key: const ValueKey<String>('new_customer_save'),
          // Disabled while the request runs so a double-tap can't save twice.
          onPressed: _saving ? null : _submit,
          child: _saving ? SizedBox(width: 16.sp, height: 16.sp, child: const CircularProgressIndicator(strokeWidth: 2)) : Text(found != null ? loc.translate('use_this_customer') : loc.translate('save')),
        ),
      ],
    );
  }
}
