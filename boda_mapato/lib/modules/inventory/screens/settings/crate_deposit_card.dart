import 'package:flutter/services.dart';
import '../widgets/inventory_widgets.dart' show ThousandsFormatter;
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../constants/theme_constants.dart';
import '../../models/inv_depot_models.dart';

/// Depot Settings card: the security deposit charged per crate, one row per crate
/// type. Customers holding crates are shown owing `crates held × deposit`.
///
/// The actions return `null` on success or the server's reason on failure, which is
/// shown inside the dialog so a refusal ("customers still hold this type") is never
/// lost behind a closed dialog.
class CrateDepositCard extends StatelessWidget {
  const CrateDepositCard({
    super.key,
    required this.types,
    required this.onCreate,
    required this.onUpdate,
    required this.onDelete,
    required this.swahili,
    this.joined = false,
  });

  /// Drawn as a section of a joined card: no box of its own.
  final bool joined;
  final List<InvCrateType> types;
  final Future<String?> Function(String name, double deposit) onCreate;
  final Future<String?> Function(
      InvCrateType type, String name, double deposit, bool active) onUpdate;
  final Future<String?> Function(InvCrateType type) onDelete;
  final bool swahili;

  Future<void> _openEditor(BuildContext context, {InvCrateType? type}) =>
      showDialog<void>(
        context: context,
        builder: (BuildContext ctx) => _CrateTypeDialog(
          type: type,
          swahili: swahili,
          onCreate: onCreate,
          onUpdate: onUpdate,
          onDelete: onDelete,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: joined ? null : ThemeConstants.glassCardDecoration,
      padding: joined ? null : EdgeInsets.all(12.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.inventory_2_outlined,
                  color: ThemeConstants.invAccent, size: 20.sp),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  swahili ? 'Dhamana ya makreti' : 'Crate security deposit',
                  style: ThemeConstants.bodyStyle
                      .copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          SizedBox(height: 4.h),
          Text(
            swahili
                ? 'Kiasi kinachodaiwa kwa kila kreti. Mteja aliyeshika makreti anaonekana akidaiwa makreti × dhamana.'
                : 'Amount charged per crate. A customer holding crates shows owing crates × deposit.',
            style: ThemeConstants.captionStyle,
          ),
          SizedBox(height: 10.h),
          if (types.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 8.h),
              child: Text(
                swahili ? 'Hakuna aina ya crate bado.' : 'No crate types yet.',
                key: const ValueKey<String>('crate_types_empty'),
                style: ThemeConstants.captionStyle
                    .copyWith(color: ThemeConstants.warningAmber),
              ),
            ),
          for (final InvCrateType t in types)
            InkWell(
              key: ValueKey<String>('crate_type_row_${t.id}'),
              borderRadius: BorderRadius.circular(10.r),
              onTap: () => _openEditor(context, type: t),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 4.w),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Row(
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              t.name,
                              overflow: TextOverflow.ellipsis,
                              style: ThemeConstants.bodyStyle.copyWith(
                                color: t.isActive ? null : Colors.white54,
                              ),
                            ),
                          ),
                          if (!t.isActive) ...<Widget>[
                            SizedBox(width: 8.w),
                            Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 6.w, vertical: 2.h),
                              decoration: BoxDecoration(
                                color: Colors.white12,
                                borderRadius: BorderRadius.circular(6.r),
                              ),
                              child: Text(swahili ? 'Imezimwa' : 'Off',
                                  style: ThemeConstants.captionStyle),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Text(
                      'TZS ${t.depositValue.toStringAsFixed(0)}',
                      style: ThemeConstants.bodyStyle.copyWith(
                          color: ThemeConstants.invAccent,
                          fontWeight: FontWeight.w700),
                    ),
                    SizedBox(width: 6.w),
                    Icon(Icons.edit_outlined,
                        color: Colors.white54, size: 18.sp),
                  ],
                ),
              ),
            ),
          SizedBox(height: 6.h),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const ValueKey<String>('crate_type_add'),
              style: OutlinedButton.styleFrom(
                foregroundColor: ThemeConstants.invAccent,
                side: const BorderSide(color: ThemeConstants.invBorder),
                padding: EdgeInsets.symmetric(vertical: 10.h),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.r)),
              ),
              onPressed: () => _openEditor(context),
              icon: const Icon(Icons.add),
              label: Text(swahili ? 'Ongeza aina ya crate' : 'Add crate type'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CrateTypeDialog extends StatefulWidget {
  const _CrateTypeDialog({
    required this.type,
    required this.swahili,
    required this.onCreate,
    required this.onUpdate,
    required this.onDelete,
  });

  /// Null when adding a new type.
  final InvCrateType? type;
  final bool swahili;
  final Future<String?> Function(String name, double deposit) onCreate;
  final Future<String?> Function(
      InvCrateType type, String name, double deposit, bool active) onUpdate;
  final Future<String?> Function(InvCrateType type) onDelete;

  @override
  State<_CrateTypeDialog> createState() => _CrateTypeDialogState();
}

class _CrateTypeDialogState extends State<_CrateTypeDialog> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  late final TextEditingController _name =
      TextEditingController(text: widget.type?.name ?? '');
  late final TextEditingController _deposit = TextEditingController(
      text: widget.type == null
          ? ''
          : widget.type!.depositValue.toStringAsFixed(0));
  late bool _active = widget.type?.isActive ?? true;
  bool _busy = false;
  String? _error;

  bool get _isNew => widget.type == null;
  bool get _sw => widget.swahili;

  @override
  void dispose() {
    _name.dispose();
    _deposit.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final String name = _name.text.trim();
    final double deposit = double.parse(_deposit.text.replaceAll(',', '').trim());
    final String? problem = _isNew
        ? await widget.onCreate(name, deposit)
        : await widget.onUpdate(widget.type!, name, deposit, _active);

    if (!mounted) return;
    if (problem == null) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _busy = false;
      _error = problem;
    });
  }

  Future<void> _delete() async {
    final bool? sure = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: ThemeConstants.primaryBlue,
        title: Text(_sw ? 'Futa aina hii?' : 'Delete this crate type?',
            style:
                ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.bold)),
        content: Text(
          _sw
              ? 'Futa "${widget.type!.name}"? Inawezekana tu kama haijawahi kutumika.'
              : 'Delete "${widget.type!.name}"? This only works if it has never been used.',
          style: ThemeConstants.captionStyle,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_sw ? 'Ghairi' : 'Cancel',
                style: const TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: ThemeConstants.errorRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_sw ? 'Futa' : 'Delete'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    final String? problem = await widget.onDelete(widget.type!);
    if (!mounted) return;
    if (problem == null) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _busy = false;
      _error = problem;
    });
  }

  String? _validateDeposit(String? v) {
    final double? n = double.tryParse((v ?? '').replaceAll(',', '').trim());
    if (n == null || n < 0) {
      return _sw ? 'Ingiza kiasi sahihi' : 'Enter a valid amount';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: ThemeConstants.primaryBlue,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.r)),
      title: Text(
        _isNew
            ? (_sw ? 'Aina mpya ya crate' : 'New crate type')
            : (_sw ? 'Hariri aina ya crate' : 'Edit crate type'),
        style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextFormField(
                key: const ValueKey<String>('crate_type_name'),
                controller: _name,
                enabled: !_busy,
                style: ThemeConstants.bodyStyle,
                decoration:
                    ThemeConstants.invInputDecoration(_sw ? 'Jina' : 'Name'),
                validator: (String? v) => (v ?? '').trim().isEmpty
                    ? (_sw ? 'Jina linahitajika' : 'A name is required')
                    : null,
              ),
              SizedBox(height: 10.h),
              TextFormField(
                key: const ValueKey<String>('crate_type_deposit'),
                controller: _deposit,
                enabled: !_busy,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: <TextInputFormatter>[ThousandsFormatter()],
                style: ThemeConstants.bodyStyle,
                decoration: ThemeConstants.invInputDecoration(_sw
                    ? 'Dhamana kwa kila kreti (TZS)'
                    : 'Deposit per crate (TZS)'),
                validator: _validateDeposit,
              ),
              if (!_isNew) ...<Widget>[
                SizedBox(height: 6.h),
                SwitchListTile(
                  key: const ValueKey<String>('crate_type_active'),
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: ThemeConstants.invAccent,
                  title: Text(_sw ? 'Inatumika' : 'In use',
                      style: ThemeConstants.bodyStyle),
                  subtitle: Text(
                    _sw
                        ? 'Ikizimwa haionekani kwenye mauzo mapya.'
                        : 'When off, it no longer appears for new sales.',
                    style: ThemeConstants.captionStyle,
                  ),
                  value: _active,
                  onChanged:
                      _busy ? null : (bool v) => setState(() => _active = v),
                ),
              ],
              if (_error != null) ...<Widget>[
                SizedBox(height: 8.h),
                Text(
                  _error!,
                  key: const ValueKey<String>('crate_type_error'),
                  style: TextStyle(
                      color: ThemeConstants.warningAmber, fontSize: 13.sp),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        if (!_isNew)
          TextButton(
            key: const ValueKey<String>('crate_type_delete'),
            onPressed: _busy ? null : _delete,
            child: Text(_sw ? 'Futa' : 'Delete',
                style: const TextStyle(color: ThemeConstants.errorText)),
          ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(_sw ? 'Ghairi' : 'Cancel',
              style: const TextStyle(color: Colors.white70)),
        ),
        ElevatedButton(
          key: const ValueKey<String>('crate_type_save'),
          style: ElevatedButton.styleFrom(
            backgroundColor: ThemeConstants.invAccent,
            foregroundColor: Colors.black,
          ),
          onPressed: _busy ? null : _save,
          child: _busy
              ? SizedBox(
                  width: 16.sp,
                  height: 16.sp,
                  child: const CircularProgressIndicator(strokeWidth: 2))
              : Text(_sw ? 'Hifadhi' : 'Save'),
        ),
      ],
    );
  }
}
