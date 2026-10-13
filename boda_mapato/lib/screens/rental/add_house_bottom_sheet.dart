import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';

import '../../config/api_config.dart';
import '../../constants/theme_constants.dart';
import '../../providers/rental_provider.dart';
import '../../services/localization_service.dart';
import 'lease_agreement_wizard_screen.dart';

class AddHouseBottomSheet extends StatefulWidget {
  final String propertyId;
  final Map<String, dynamic>? existingHouse;
  final VoidCallback onSaved;

  const AddHouseBottomSheet({
    required this.propertyId,
    this.existingHouse,
    required this.onSaved,
    super.key,
  });

  @override
  State<AddHouseBottomSheet> createState() => _AddHouseBottomSheetState();
}

class _AddHouseBottomSheetState extends State<AddHouseBottomSheet> {
  final _loc = LocalizationService.instance;
  bool _attemptedSubmit = false;
  bool _isSaving = false;
  late bool _isEdit;

  final _numberCtrl = TextEditingController();
  final _rentCtrl = TextEditingController();
  final _depositCtrl = TextEditingController();
  final _meterCtrl = TextEditingController();
  final _waterCtrl = TextEditingController();
  final _distanceCtrl = TextEditingController();
  final _bedroomsCtrl = TextEditingController();
  final _bathroomsCtrl = TextEditingController();
  final _sqmCtrl = TextEditingController();
  final _floorCtrl = TextEditingController();
  final _elecCountCtrl = TextEditingController();
  final _waterCountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _unitsCountCtrl = TextEditingController();
  final List<TextEditingController> _unitNameCtrls = [];

  String _type = 'room';
  String _status = 'vacant';
  String? _blockId;
  DateTime? _maintenanceUntil;

  bool _hasFence = false;
  bool _hasTiles = false;
  bool _hasSittingRoom = false;
  bool _hasMasterBedroom = false;
  bool _hasKitchen = false;
  bool _landlordLivesHere = false;

  double _targetRent = 0;
  double _currentHousesSum = 0;
  bool _isLoadingStats = true;

  String _kitchenLocation = 'inside';
  String _elecType = 'independent';
  String _waterType = 'independent';
  String _billingCycle = 'monthly';
  String _currency = 'TZS';
  bool _utilityBillingEnabled = false;
  final _ownershipNotesCtrl = TextEditingController();

  /// Each entry: {'file': XFile, 'caption': String}
  final List<Map<String, dynamic>> _captionedImages = [];
  final ImagePicker _picker = ImagePicker();
  static const int _maxPhotos = 5;

  @override
  void initState() {
    super.initState();
    _isEdit = widget.existingHouse != null;
    
    // Load blocks for this property
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      context.read<RentalProvider>().fetchBlocks(widget.propertyId);
      final stats = await context.read<RentalProvider>().getPropertyRentStats(
        widget.propertyId,
        excludeHouseId: _isEdit ? widget.existingHouse!['id'].toString() : null
      );
      if (mounted) {
        setState(() {
          _targetRent = stats['target'] ?? 0;
          _currentHousesSum = stats['sum'] ?? 0;
          _isLoadingStats = false;
        });
      }
    });

    _rentCtrl.addListener(() {
      setState(() {});
    });

    if (_isEdit) {
      final h = widget.existingHouse!;
      _numberCtrl.text = h['house_number'] ?? '';
      _rentCtrl.text = _fmtAmt(h['rent_amount']);
      _depositCtrl.text = _fmtAmt(h['deposit_amount']);
      _meterCtrl.text = h['electricity_meter'] ?? '';
      _waterCtrl.text = h['water_meter'] ?? '';
      _distanceCtrl.text = (h['distance_from_road'] ?? '').toString().replaceAll(RegExp(r'[a-zA-Z\s]'), '');
      _bedroomsCtrl.text = h['bedrooms']?.toString() ?? '';
      _bathroomsCtrl.text = h['bathrooms']?.toString() ?? '';
      _sqmCtrl.text = h['square_meters']?.toString() ?? '';
      _floorCtrl.text = h['floor']?.toString() ?? '';
      _elecCountCtrl.text = h['electricity_sharing_count']?.toString() ?? '';
      _waterCountCtrl.text = h['water_sharing_count']?.toString() ?? '';
      _notesCtrl.text = h['description'] ?? '';
      _ownershipNotesCtrl.text = h['ownership_notes'] ?? '';
      _type = h['type'] ?? 'room';
      _status = h['status'] ?? 'vacant';
      _billingCycle = h['billing_cycle'] ?? 'monthly';
      _currency = h['currency'] ?? 'TZS';
      _utilityBillingEnabled = h['utility_billing_enabled'] == 1 || h['utility_billing_enabled'] == true;
      _blockId = h['block_id']?.toString();
      _hasFence = h['has_fence'] == true;
      _hasTiles = h['has_tiles'] == true;
      _hasSittingRoom = h['has_sitting_room'] == true;
      _hasMasterBedroom = h['has_master_bedroom'] == true;
      _hasKitchen = h['has_kitchen'] == true;
      _landlordLivesHere = h['landlord_lives_present'] == true;
      _kitchenLocation = h['kitchen_location'] ?? 'inside';
      _elecType = h['electricity_type'] ?? 'independent';
      _waterType = h['water_type'] ?? 'independent';
      if (h['maintenance_until'] != null) {
        _maintenanceUntil = DateTime.tryParse(h['maintenance_until'].toString());
      }
      final paths = (h['images'] ?? []) as List;
      final caps = (h['image_captions'] ?? []) as List;
      for (int i = 0; i < paths.length; i++) {
        _captionedImages.add({
          'file': paths[i].toString(),
          'caption': (caps.length > i) ? caps[i].toString() : '',
          'isRemote': true,
        });
      }
      
      _unitsCountCtrl.text = h['units_count']?.toString() ?? '0';
      final uNames = (h['unit_names'] ?? []) as List;
      for (final name in uNames) {
        _unitNameCtrls.add(TextEditingController(text: name.toString()));
      }
    }
  }

  String _fmtAmt(dynamic v) {
    if (v == null) return '0';
    if (v is num) return v.toInt().toString();
    if (v is String) {
      final d = double.tryParse(v);
      if (d != null) return d.toInt().toString();
    }
    return v.toString();
  }

  Future<void> _pickImages() async {
    final remaining = _maxPhotos - _captionedImages.length;
    if (remaining <= 0) return;
    final picked = await _picker.pickMultiImage();
    for (final xf in picked) {
      if (_captionedImages.length >= _maxPhotos) break;
      final caption = await _promptCaption(xf);
      if (caption != null) setState(() => _captionedImages.add({
        'file': xf, 
        'caption': caption,
        'isRemote': false,
      }));
    }
  }

  Future<void> _takePhoto() async {
    if (_captionedImages.length >= _maxPhotos) return;
    final photo = await _picker.pickImage(source: ImageSource.camera);
    if (photo != null) {
      final caption = await _promptCaption(photo);
      if (caption != null) setState(() => _captionedImages.add({
        'file': photo, 
        'caption': caption,
        'isRemote': false,
      }));
    }
  }

  Future<String?> _promptCaption(XFile file) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: ThemeConstants.bgMid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
        child: Padding(
          padding: EdgeInsets.all(20.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Icon(Icons.label_outline, color: ThemeConstants.primaryOrange, size: 22.sp),
                SizedBox(width: 8.w),
                Expanded(child: Text(_loc.translate('image_name'), style: TextStyle(color: Colors.white, fontSize: 16.sp, fontWeight: FontWeight.bold))),
                GestureDetector(
                  onTap: () => Navigator.pop(ctx, null),
                  child: Icon(Icons.close, color: Colors.white38, size: 20.sp),
                ),
              ]),
              SizedBox(height: 16.h),
              ClipRRect(
                borderRadius: BorderRadius.circular(12.r),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.file(File(file.path), fit: BoxFit.cover),
                ),
              ),
              SizedBox(height: 14.h),
              TextField(
                controller: ctrl,
                autofocus: true,
                style: TextStyle(color: Colors.white, fontSize: 14.sp),
                decoration: InputDecoration(
                  hintText: _loc.translate('image_name_hint'),
                  hintStyle: TextStyle(color: Colors.white38, fontSize: 13.sp),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.06),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide.none),
                  contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
                ),
              ),
              SizedBox(height: 18.h),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, null),
                    child: Text(_loc.translate('cancel'), style: TextStyle(color: Colors.white54, fontSize: 13.sp)),
                  ),
                  SizedBox(width: 8.w),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, ctrl.text.isEmpty ? _loc.translate('photo') : ctrl.text),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ThemeConstants.primaryOrange,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                    ),
                    child: Text(_loc.translate('save'), style: TextStyle(color: Colors.white, fontSize: 13.sp, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        color: ThemeConstants.bgMid,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24.r),
          topRight: Radius.circular(24.r),
        ),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: EdgeInsets.only(top: 12.h),
            width: 40.w,
            height: 4.h,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2.r),
            ),
          ),
          // Header
          Padding(
            padding: EdgeInsets.all(20.w),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _isEdit ? _loc.translate('edit_house') : _loc.translate('add_house'),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white54),
                ),
              ],
            ),
          ),
          // Body
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Section 1: Basic Info ──
                  _sectionHeader(_loc.translate('basic_info'), Icons.info_outline),
                  SizedBox(height: 12.h),
                  Row(children: [
                    Expanded(child: _buildTextField(_numberCtrl, _loc.translate('house_number'), Icons.door_front_door,
                        errorText: _attemptedSubmit && _numberCtrl.text.isEmpty
                            ? _loc.translate('field_required')
                            : null)),
                    Consumer<RentalProvider>(builder: (context, rental, _) {
                      if (rental.blocks.isEmpty) return const SizedBox();
                      return SizedBox(width: 12.w);
                    }),
                    Expanded(
                      child: Consumer<RentalProvider>(builder: (context, rental, _) {
                        if (rental.blocks.isEmpty) return const SizedBox();
                        return _buildDropdown(_loc.translate('blocks'), _blockId ?? 'none',
                            ['none', ...rental.blocks.map((e) => e['id'].toString())],
                            (v) => setState(() => _blockId = (v == 'none' ? null : v)),
                            displayValue: (v) {
                              if (v == 'none') return "-- ${_loc.translate('none')} --";
                              final b = rental.blocks.firstWhere((e) => e['id'].toString() == v, orElse: () => null);
                              return b != null ? b['name'] : v;
                            });
                      }),
                    ),
                  ]),
                  SizedBox(height: 16.h),
                  Row(children: [
                    Expanded(child: _buildDropdown(_loc.translate('house_type'), _type,
                        ['room', 'apartment', 'studio', 'commercial', 'bedsitter', 'one_bedroom', 'two_bedroom'],
                        (v) => setState(() => _type = v))),
                    SizedBox(width: 12.w),
                    Expanded(child: _buildDropdown(_loc.translate('house_status'), _status,
                        ['vacant', 'occupied', 'maintenance', 'reserved'],
                        (v) => setState(() => _status = v))),
                  ]),
                  if (_status == 'maintenance') ...[
                    SizedBox(height: 16.h),
                    _buildDatePicker(
                      label: _loc.translate('maintenance_end_date'),
                      value: _maintenanceUntil,
                      onChanged: (d) => setState(() => _maintenanceUntil = d),
                    ),
                  ],
                  SizedBox(height: 16.h),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildTextField(_rentCtrl, '${_loc.translate('rent_amount')} *', Icons.payments,
                              keyboard: TextInputType.number,
                              errorText: _attemptedSubmit && _rentCtrl.text.isEmpty
                                  ? _loc.translate('field_required')
                                  : (_attemptedSubmit && double.tryParse(_rentCtrl.text) == null
                                      ? _loc.translate('invalid_amount')
                                      : (_targetRent > 0 && (double.tryParse(_rentCtrl.text) ?? 0) > (_targetRent - _currentHousesSum)
                                          ? "Kiasi kinazidi lengo la mali"
                                          : null))),
                          if (!_isLoadingStats && _targetRent > 0) ...[
                            SizedBox(height: 6.h),
                            Builder(builder: (context) {
                              double entered = double.tryParse(_rentCtrl.text) ?? 0;
                              double remaining = _targetRent - _currentHousesSum - entered;
                              bool isExceeded = remaining < 0;
                              return Text(
                                isExceeded 
                                  ? LocalizationService.instance.translateWith('amount_is_above_the_target_by', <Object?>[remaining.abs().toStringAsFixed(0)])
                                  : LocalizationService.instance.translateWith('remaining_target_tzs', <Object?>[remaining.toStringAsFixed(0)]),
                                style: TextStyle(
                                  color: isExceeded ? ThemeConstants.errorRed : ThemeConstants.successGreen,
                                  fontSize: 11.sp,
                                  fontWeight: FontWeight.w600,
                                ),
                              );
                            })
                          ]
                        ]
                      )
                    ),
                    SizedBox(width: 12.w),
                    Expanded(child: _buildTextField(_depositCtrl, _loc.translate('deposit_amount'), Icons.account_balance_wallet,
                        keyboard: TextInputType.number,
                        errorText: (double.tryParse(_depositCtrl.text) ?? 0) > (double.tryParse(_rentCtrl.text) ?? 0)
                            ? _loc.translate('deposit_exceeds_rent')
                            : null)),
                  ]),
                  SizedBox(height: 16.h),
                  Row(children: [
                    Expanded(child: _buildTextField(_floorCtrl, _loc.translate('floor'), Icons.layers, keyboard: TextInputType.number)),
                    SizedBox(width: 12.w),
                    Expanded(child: _buildTextField(_sqmCtrl, _loc.translate('area_sqm'), Icons.square_foot, keyboard: TextInputType.number)),
                  ]),
                  SizedBox(height: 16.h),
                  Row(children: [
                    Expanded(child: _buildTextField(_bedroomsCtrl, _loc.translate('bedrooms'), Icons.bed, keyboard: TextInputType.number)),
                    SizedBox(width: 12.w),
                    Expanded(child: _buildTextField(_bathroomsCtrl, _loc.translate('bathrooms'), Icons.bathtub, keyboard: TextInputType.number)),
                  ]),

                  SizedBox(height: 28.h),
                  _divider(),

                  // ── Section 1.5: Multi-Unit Units ──
                  SizedBox(height: 16.h),
                  _sectionHeader(_loc.translate('units_section'), Icons.door_front_door),
                  SizedBox(height: 12.h),
                  _buildTextField(
                    _unitsCountCtrl,
                    _loc.translate('total_units_label'),
                    Icons.numbers,
                    keyboard: TextInputType.number,
                    onChanged: (v) {
                      final count = int.tryParse(v) ?? 0;
                      if (count > 20) return; // Safety limit
                      setState(() {
                        if (count > _unitNameCtrls.length) {
                          for (int i = _unitNameCtrls.length; i < count; i++) {
                            _unitNameCtrls.add(TextEditingController(text: '${_loc.translate('unit')} ${i + 1}'));
                          }
                        } else if (count < _unitNameCtrls.length) {
                          _unitNameCtrls.removeRange(count, _unitNameCtrls.length);
                        }
                      });
                    },
                  ),
                  if (_unitNameCtrls.isNotEmpty) ...[
                    SizedBox(height: 16.h),
                    Text(_loc.translate('name_units_hint'), style: TextStyle(color: Colors.white38, fontSize: 11.sp)),
                    SizedBox(height: 8.h),
                    ..._unitNameCtrls.asMap().entries.map((e) {
                      return Padding(
                        padding: EdgeInsets.only(bottom: 8.h),
                        child: _buildTextField(e.value, '${_loc.translate('unit')} ${e.key + 1}', Icons.label),
                      );
                    }),
                  ],

                  SizedBox(height: 28.h),
                  _divider(),

                  // ── Section 2: Interior Features ──
                  SizedBox(height: 16.h),
                  _sectionHeader(_loc.translate('house_features'), Icons.home_work_outlined),
                  SizedBox(height: 8.h),
                  _buildSwitch(_loc.translate('has_fence'), _hasFence, (v) => setState(() => _hasFence = v), Icons.fence),
                  _buildSwitch(_loc.translate('has_tiles'), _hasTiles, (v) => setState(() => _hasTiles = v), Icons.grid_on),
                  _buildSwitch(_loc.translate('has_master_bedroom'), _hasMasterBedroom, (v) => setState(() => _hasMasterBedroom = v), Icons.king_bed),
                  _buildSwitch(_loc.translate('has_sitting_room'), _hasSittingRoom, (v) => setState(() => _hasSittingRoom = v), Icons.weekend),
                  _buildSwitch(_loc.translate('has_kitchen'), _hasKitchen, (v) => setState(() => _hasKitchen = v), Icons.kitchen),
                  if (_hasKitchen) ...[
                    Padding(
                      padding: EdgeInsets.only(left: 40.w, bottom: 8.h),
                      child: Row(children: [
                        Text('${_loc.translate('kitchen_location')}:', style: TextStyle(color: Colors.white70, fontSize: 13.sp)),
                        SizedBox(width: 12.w),
                        _chipOption(_loc.translate('inside'), 'inside', _kitchenLocation, (v) => setState(() => _kitchenLocation = v)),
                        SizedBox(width: 8.w),
                        _chipOption(_loc.translate('outside'), 'outside', _kitchenLocation, (v) => setState(() => _kitchenLocation = v)),
                      ]),
                    ),
                  ],
                  SizedBox(height: 8.h),
                  _buildTextField(_distanceCtrl, '${_loc.translate('distance_from_road')} (km)', Icons.add_road, keyboard: TextInputType.number),

                  SizedBox(height: 28.h),
                  _divider(),

                  // ── Section 3: Utilities ──
                  SizedBox(height: 16.h),
                  _sectionHeader(_loc.translate('utilities_section'), Icons.electrical_services),
                  SizedBox(height: 12.h),
                  Row(children: [
                    Expanded(child: _buildDropdown(_loc.translate('electricity_type'), _elecType,
                        ['independent', 'shared'], (v) => setState(() => _elecType = v))),
                    SizedBox(width: 12.w),
                    if (_elecType == 'shared')
                      Expanded(child: _buildTextField(_elecCountCtrl, _loc.translate('sharing_count'), Icons.people, keyboard: TextInputType.number))
                    else
                      Expanded(child: _buildTextField(_meterCtrl, _loc.translate('electricity_meter'), Icons.bolt)),
                  ]),
                  SizedBox(height: 16.h),
                  Row(children: [
                    Expanded(child: _buildDropdown(_loc.translate('water_type'), _waterType,
                        ['independent', 'shared'], (v) => setState(() => _waterType = v))),
                    SizedBox(width: 12.w),
                    if (_waterType == 'shared')
                      Expanded(child: _buildTextField(_waterCountCtrl, _loc.translate('sharing_count'), Icons.people, keyboard: TextInputType.number))
                    else
                      Expanded(child: _buildTextField(_waterCtrl, _loc.translate('water_meter'), Icons.water_drop)),
                  ]),

                  SizedBox(height: 28.h),
                  _divider(),

                  // ── Section 4: Residence ──
                  SizedBox(height: 16.h),
                  _sectionHeader(_loc.translate('residence_ownership'), Icons.person_pin_circle),
                  SizedBox(height: 8.h),
                  _buildSwitch(_loc.translate('landlord_lives_here'), _landlordLivesHere, (v) => setState(() => _landlordLivesHere = v), Icons.home),
                  SizedBox(height: 12.h),

                  // ── Section 4.5: Configuration (Shifted from Property) ──
                  _divider(),
                  SizedBox(height: 16.h),
                  _sectionHeader(_loc.translate('configuration'), Icons.settings_outlined),
                  SizedBox(height: 14.h),
                  Row(
                    children: [
                      Expanded(
                        child: _buildDropdown(_loc.translate('billing_cycle'), _billingCycle,
                          ['monthly', 'quarterly', 'yearly'],
                          (v) => setState(() => _billingCycle = v)),
                      ),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: _buildDropdown(_loc.translate('currency'), _currency,
                          ['TZS', 'USD'],
                          (v) => setState(() => _currency = v),
                          displayValue: (v) => v),
                      ),
                    ],
                  ),
                  SizedBox(height: 16.h),
                  _buildSwitch(LocalizationService.instance.translate('utility_bills_water_electricity'), _utilityBillingEnabled, 
                    (v) => setState(() => _utilityBillingEnabled = v), Icons.electrical_services),
                  SizedBox(height: 8.h),
                  _buildTextField(_ownershipNotesCtrl, LocalizationService.instance.translate('ownership_details'), Icons.note_alt_outlined, maxLines: 3),
                  SizedBox(height: 16.h),
                  _buildTextField(_notesCtrl, _loc.translate('notes'), Icons.description, maxLines: 3),

                  SizedBox(height: 28.h),
                  _divider(),

                  // ── Section 5: Photos ──
                  SizedBox(height: 16.h),
                  _sectionHeader(_loc.translate('photos_section'), Icons.photo_library),
                  SizedBox(height: 4.h),
                  Row(children: [
                    Expanded(
                      child: Text(_loc.translate('photos_hint'), style: TextStyle(color: Colors.white38, fontSize: 11.sp)),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                      decoration: BoxDecoration(
                        color: _captionedImages.length >= _maxPhotos
                            ? ThemeConstants.primaryOrange.withOpacity(0.2)
                            : Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(12.r),
                        border: Border.all(color: _captionedImages.isEmpty && _attemptedSubmit
                            ? Colors.redAccent
                            : (_captionedImages.length >= _maxPhotos
                                ? ThemeConstants.primaryOrange
                                : Colors.white12)),
                      ),
                      child: Text(
                        '${_captionedImages.length} / $_maxPhotos',
                        style: TextStyle(
                          color: _captionedImages.isEmpty && _attemptedSubmit
                              ? Colors.redAccent
                              : (_captionedImages.length >= _maxPhotos
                                  ? ThemeConstants.primaryOrange
                                  : Colors.white54),
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ]),
                  if (_attemptedSubmit && _captionedImages.isEmpty && !_isEdit)
                    Padding(
                      padding: EdgeInsets.only(top: 6.h),
                      child: Text(
                        _loc.translate('photos_required'),
                        style: TextStyle(color: Colors.redAccent, fontSize: 12.sp),
                      ),
                    ),
                  SizedBox(height: 12.h),

                  if (_captionedImages.isNotEmpty)
                    House3DPreviewGallery(images: _captionedImages.map((e) => {
                      'source': e['file'], 
                      'caption': e['caption'],
                      'isRemote': e['isRemote'] ?? false,
                    }).toList()),
                  if (_captionedImages.isNotEmpty) ...[
                    SizedBox(height: 12.h),
                    Wrap(
                      spacing: 8.w, runSpacing: 8.h,
                      children: _captionedImages.asMap().entries.map((e) {
                        final idx = e.key;
                        final item = e.value;
                        final bool isRemote = item['isRemote'] == true;
                        
                        Widget img;
                        if (isRemote) {
                          final path = item['file'].toString();
                          final url = path.startsWith('http') ? path : "${ApiConfig.webBaseUrl}/storage/$path";
                          img = Image.network(url, width: 28.w, height: 28.w, fit: BoxFit.cover);
                        } else {
                          img = Image.file(File((item['file'] as XFile).path), width: 28.w, height: 28.w, fit: BoxFit.cover);
                        }

                        return Chip(
                          avatar: ClipRRect(borderRadius: BorderRadius.circular(10.r), child: img),
                          label: Text(item['caption'], style: TextStyle(color: Colors.white, fontSize: 11.sp)),
                          backgroundColor: Colors.white.withOpacity(0.08),
                          deleteIcon: Icon(Icons.close, size: 14.sp, color: Colors.redAccent),
                          onDeleted: () => setState(() => _captionedImages.removeAt(idx)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
                          side: BorderSide(color: Colors.white12),
                        );
                      }).toList(),
                    ),
                  ],
                  SizedBox(height: 12.h),

                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _captionedImages.length >= _maxPhotos ? null : _pickImages,
                        icon: Icon(Icons.photo_library, color: _captionedImages.length >= _maxPhotos ? Colors.white24 : ThemeConstants.primaryOrange, size: 18.sp),
                        label: Text(_loc.translate('gallery'), style: TextStyle(color: _captionedImages.length >= _maxPhotos ? Colors.white24 : ThemeConstants.primaryOrange, fontSize: 12.sp)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: ThemeConstants.primaryOrange.withOpacity(0.5)),
                          padding: EdgeInsets.symmetric(vertical: 12.h),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                        ),
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _captionedImages.length >= _maxPhotos ? null : _takePhoto,
                        icon: Icon(Icons.camera_alt, color: _captionedImages.length >= _maxPhotos ? Colors.white24 : ThemeConstants.primaryOrange, size: 18.sp),
                        label: Text(_loc.translate('camera'), style: TextStyle(color: _captionedImages.length >= _maxPhotos ? Colors.white24 : ThemeConstants.primaryOrange, fontSize: 12.sp)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: ThemeConstants.primaryOrange.withOpacity(0.5)),
                          padding: EdgeInsets.symmetric(vertical: 12.h),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                        ),
                      ),
                    ),
                  ]),

                  SizedBox(height: 36.h),
                  // ── Save Button ──
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _submitForm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ThemeConstants.primaryOrange,
                        padding: EdgeInsets.symmetric(vertical: 16.h),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                      ),
                      child: _isSaving
                          ? SizedBox(width: 20.w, height: 20.w, child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : Text(
                              _isEdit ? _loc.translate('update_house') : _loc.translate('save_house'),
                              style: TextStyle(color: Colors.white, fontSize: 16.sp, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                  SizedBox(height: 40.h),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── UI Helpers ──

  Widget _sectionHeader(String title, IconData icon) {
    return Row(children: [
      Icon(icon, color: ThemeConstants.primaryOrange, size: 20.sp),
      SizedBox(width: 8.w),
      Text(title, style: TextStyle(color: Colors.white, fontSize: 16.sp, fontWeight: FontWeight.bold)),
    ]);
  }

  Widget _divider() => Divider(color: Colors.white.withOpacity(0.08), thickness: 1);

  Widget _buildSwitch(String label, bool value, void Function(bool) onChanged, IconData icon) {
    return Container(
      margin: EdgeInsets.only(bottom: 4.h),
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        title: Row(children: [
          Icon(icon, color: Colors.white38, size: 18.sp),
          SizedBox(width: 10.w),
          Expanded(child: Text(label, style: TextStyle(color: Colors.white, fontSize: 13.sp))),
        ]),
        activeColor: ThemeConstants.primaryOrange,
        contentPadding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _chipOption(String label, String value, String groupValue, void Function(String) onSelect) {
    final selected = value == groupValue;
    return GestureDetector(
      onTap: () => onSelect(value),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.h),
        decoration: BoxDecoration(
          color: selected ? ThemeConstants.primaryOrange.withOpacity(0.2) : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20.r),
          border: Border.all(color: selected ? ThemeConstants.primaryOrange : Colors.white12),
        ),
        child: Text(label, style: TextStyle(
          color: selected ? ThemeConstants.primaryOrange : Colors.white54,
          fontSize: 12.sp,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        )),
      ),
    );
  }

  Widget _buildTextField(TextEditingController ctrl, String label, IconData icon,
      {TextInputType? keyboard, String? errorText, int maxLines = 1, ValueChanged<String>? onChanged}) {
    return TextField(
      controller: ctrl,
      onChanged: (v) {
        if (onChanged != null) onChanged(v);
        setState(() {});
      },
      keyboardType: keyboard,
      maxLines: maxLines,
      style: TextStyle(color: Colors.white, fontSize: 15.sp),
      decoration: InputDecoration(
        labelText: label,
        errorText: errorText,
        labelStyle: TextStyle(color: Colors.white70, fontSize: 13.sp),
        prefixIcon: Icon(icon, color: ThemeConstants.primaryOrange, size: 20.sp),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide(color: errorText != null ? Colors.redAccent : Colors.white12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: const BorderSide(color: ThemeConstants.primaryOrange),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
      ),
    );
  }

  Widget _buildDropdown(String label, String value, List<String> items, Function(String) onChange, {String Function(String)? displayValue}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(color: Colors.white70, fontSize: 12.sp)),
      SizedBox(height: 6.h),
      Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: Colors.white12),
        ),
        child: DropdownButton<String>(
          value: items.contains(value) ? value : (items.isNotEmpty ? items.first : null),
          isExpanded: true,
          dropdownColor: ThemeConstants.bgMid,
          underline: const SizedBox(),
          style: TextStyle(color: Colors.white, fontSize: 14.sp),
          items: items.map((i) => DropdownMenuItem(
            value: i,
            child: Text(displayValue != null ? displayValue(i) : _loc.translate(i)),
          )).toList(),
          onChanged: (v) => onChange(v ?? items.first),
        ),
      ),
    ]);
  }

  Widget _buildDatePicker({required String label, required DateTime? value, required ValueChanged<DateTime?> onChanged}) {
    return InkWell(
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now().add(const Duration(days: 7)),
          firstDate: DateTime.now().subtract(const Duration(days: 365)),
          lastDate: DateTime.now().add(const Duration(days: 3650)),
          builder: (context, child) => Theme(
            data: Theme.of(context).copyWith(
              colorScheme: ColorScheme.dark(
                primary: ThemeConstants.primaryOrange,
                onPrimary: Colors.white,
                surface: ThemeConstants.bgMid,
                onSurface: Colors.white,
              ),
            ),
            child: child!,
          ),
        );
        if (d != null) onChanged(d);
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(children: [
          Icon(Icons.calendar_today, color: ThemeConstants.primaryOrange, size: 20.sp),
          SizedBox(width: 12.w),
          Expanded(child: Text(
            value != null ? "${value.day}/${value.month}/${value.year}" : LocalizationService.instance.translateWith('tap_to_select', <Object?>[label]),
            style: TextStyle(color: value != null ? Colors.white : Colors.white38, fontSize: 14.sp),
          )),
        ]),
      ),
    );
  }

  // ── Submit ──

  Future<void> _submitForm() async {
    setState(() => _attemptedSubmit = true);
    if (_numberCtrl.text.isEmpty || _rentCtrl.text.isEmpty) return;
    if (!_isEdit && _captionedImages.isEmpty) return;
    final double rentAmt = double.tryParse(_rentCtrl.text) ?? 0;
    final double depositAmt = double.tryParse(_depositCtrl.text) ?? 0;
    if (depositAmt > rentAmt) return;

    if (_targetRent > 0) {
      final remaining = _targetRent - _currentHousesSum - rentAmt;
      if (remaining < 0) {
        if (mounted) {
          ThemeConstants.showErrorSnackBar(
              context, LocalizationService.instance.translate('the_rent_amount_is_above_the'));
        }
        setState(() => _attemptedSubmit = false);
        return;
      }
    }

    setState(() => _isSaving = true);

    final provider = context.read<RentalProvider>();
    final data = {
      'property_id': widget.propertyId,
      'house_number': _numberCtrl.text,
      'rent_amount': rentAmt,
      'deposit_amount': depositAmt,
      'type': _type,
      'status': _status,
      'block_id': _blockId,
      'has_fence': _hasFence,
      'has_tiles': _hasTiles,
      'has_sitting_room': _hasSittingRoom,
      'has_master_bedroom': _hasMasterBedroom,
      'has_kitchen': _hasKitchen,
      'landlord_lives_present': _landlordLivesHere,
      if (_hasKitchen) 'kitchen_location': _kitchenLocation,
      'distance_from_road': _distanceCtrl.text.trim().isNotEmpty ? '${_distanceCtrl.text.trim()}km' : '',
      'electricity_type': _elecType,
      if (_elecType == 'shared') 'electricity_sharing_count': _elecCountCtrl.text,
      if (_elecType == 'independent') 'electricity_meter': _meterCtrl.text,
      'water_type': _waterType,
      if (_waterType == 'shared') 'water_sharing_count': _waterCountCtrl.text,
      if (_waterType == 'independent') 'water_meter': _waterCtrl.text,
      'bedrooms': _bedroomsCtrl.text,
      'bathrooms': _bathroomsCtrl.text,
      'square_meters': _sqmCtrl.text,
      'floor': _floorCtrl.text,
      'description': _notesCtrl.text,
      'billing_cycle': _billingCycle,
      'currency': _currency,
      'utility_billing_enabled': _utilityBillingEnabled,
      'ownership_notes': _ownershipNotesCtrl.text,
      if (_status == 'maintenance' && _maintenanceUntil != null)
        'maintenance_until': "${_maintenanceUntil!.year}-${_maintenanceUntil!.month.toString().padLeft(2, '0')}-${_maintenanceUntil!.day.toString().padLeft(2, '0')}",
      'units_count': int.tryParse(_unitsCountCtrl.text) ?? 0,
      'unit_names': _unitNameCtrls.map((e) => e.text).join(','),
    };

    final Map<String, dynamic> payload = {};
    data.forEach((key, value) {
      if (value != null && value.toString().isNotEmpty) {
        payload[key] = value is bool ? (value ? 'true' : 'false') : value;
      }
    });

    // Partition images: existing (remote) and new (local)
    final existingPaths = _captionedImages.where((e) => e['isRemote'] == true).map((e) => e['file'].toString()).toList();
    final existingCaps = _captionedImages.where((e) => e['isRemote'] == true).map((e) => e['caption'].toString()).toList();
    final newItems = _captionedImages.where((e) => e['isRemote'] != true).toList();
    
    // Extract just the XFile list for the API
    final imageFiles = newItems.map((e) => e['file'] as XFile).toList();
    
    if (_isEdit) {
      payload['existing_images'] = existingPaths.join('||');
      payload['existing_captions'] = existingCaps.join('||');
    }

    // Build new captions JSON
    if (newItems.isNotEmpty) {
      payload['image_captions'] = newItems.map((e) => e['caption'] as String).toList().join('||');
    }

    String? houseId;
    bool updateSuccess = false;

    if (_isEdit) {
      updateSuccess = await provider.updateHouse(widget.existingHouse!['id'].toString(), payload, images: imageFiles);
    } else {
      houseId = await provider.createHouse(payload, images: imageFiles);
    }

    if (mounted) {
      setState(() => _isSaving = false);
      
      if (_isEdit) {
        Navigator.pop(context);
        if (updateSuccess) widget.onSaved();
      } else if (houseId != null) {
        if (houseId == 'success') {
           Navigator.pop(context);
           widget.onSaved();
           return;
        }

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: ThemeConstants.bgMid,
            title: Text(LocalizationService.instance.translate('house_created'), style: const TextStyle(color: Colors.white)),
            content: Text(LocalizationService.instance.translate('do_you_want_to_onboard_a'), style: const TextStyle(color: Colors.white70)),
            actions: [
              TextButton(
                onPressed: () {
                  final nav = Navigator.of(context);
                  nav.pop(); // dialog
                  nav.pop(); // bottom sheet
                  widget.onSaved();
                },
                child: Text(LocalizationService.instance.translate('not_now'), style: const TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                onPressed: () {
                  final nav = Navigator.of(context);
                  nav.pop(); // dialog
                  nav.pop(); // bottom sheet
                  widget.onSaved();
                  nav.push(MaterialPageRoute(
                    builder: (_) => LeaseAgreementWizardScreen(
                      preSelectedProperty: {'id': widget.propertyId},
                      preSelectedHouse: {'id': houseId},
                    )
                  ));
                },
                style: ElevatedButton.styleFrom(backgroundColor: ThemeConstants.primaryOrange),
                child: Text(LocalizationService.instance.translate('yes_onboard_tenant'), style: const TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      }
    }
  }
}

// ── 3D Preview Gallery ──

class House3DPreviewGallery extends StatefulWidget {
  /// Each entry: {'source': dynamic(XFile|String), 'caption': String}
  final List<dynamic> images;
  const House3DPreviewGallery({required this.images, super.key});
  @override
  State<House3DPreviewGallery> createState() => _House3DPreviewGalleryState();
}

class _House3DPreviewGalleryState extends State<House3DPreviewGallery> {
  final PageController _ctrl = PageController(viewportFraction: 0.78);
  double _page = 0.0;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() => setState(() => _page = _ctrl.page ?? 0.0));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.images.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 220.h,
      child: PageView.builder(
        controller: _ctrl,
        physics: const BouncingScrollPhysics(),
        itemCount: widget.images.length,
        itemBuilder: (context, i) {
          double scale = 1.0;
          if (_ctrl.position.haveDimensions) {
            scale = (1 - ((_page - i).abs() * 0.3)).clamp(0.0, 1.0);
          }
          final matrix = Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY((_page - i) * -0.5)
            ..scale(scale);

          final entry = widget.images[i];
          dynamic src;
          String caption = '';
          if (entry is Map) {
            src = entry['source'];
            caption = (entry['caption'] ?? '').toString();
          } else {
            src = entry;
          }

          Widget imgWidget;
          if (src is XFile) {
            imgWidget = Image.file(File(src.path), fit: BoxFit.cover);
          } else if (src is String && src.startsWith('http')) {
            imgWidget = Image.network(src, fit: BoxFit.cover);
          } else if (src is String) {
            imgWidget = Image.network("${ApiConfig.webBaseUrl}/storage/$src", fit: BoxFit.cover);
          } else {
            imgWidget = Container(color: Colors.white10, child: Icon(Icons.image, color: Colors.white24, size: 40.sp));
          }

          return Transform(
            alignment: Alignment.center,
            transform: matrix,
            child: Container(
              margin: EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(16.r),
                boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 5))],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(fit: StackFit.expand, children: [
                imgWidget,
                Container(decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.black87, Colors.transparent],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                  ),
                )),
                Positioned(
                  bottom: 8.h, left: 12.w, right: 12.w,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (caption.isNotEmpty)
                        Text(
                          caption,
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13.sp),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      SizedBox(height: 2.h),
                      Text(
                        "${i + 1} / ${widget.images.length}",
                        style: TextStyle(color: Colors.white60, fontSize: 10.sp),
                      ),
                    ],
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }
}
