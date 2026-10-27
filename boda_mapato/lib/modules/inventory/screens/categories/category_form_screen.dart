import 'dart:io';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../models/inv_category.dart';
import '../../providers/inventory_provider.dart';
import '../../../../utils/localized_name.dart';

class CategoryFormScreen extends StatefulWidget {
  const CategoryFormScreen({super.key, this.existing, this.providerOverride});
  final InvCategory? existing;
  final InventoryProvider? providerOverride;

  @override
  State<CategoryFormScreen> createState() => _CategoryFormScreenState();
}

class _CategoryFormScreenState extends State<CategoryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  int? _parentId;
  bool _active = true;
  String? _imagePath;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    if (c != null) {
      _nameCtrl.text = c.name;
      _descCtrl.text = c.description;
      _parentId = c.parentId;
      _active = c.status == 'active' || c.status == 'Active';
      _imagePath = c.imagePath;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image);
    if (res != null && res.files.isNotEmpty) {
      setState(() => _imagePath = res.files.single.path);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final inv = widget.providerOverride ??
        Provider.of<InventoryProvider>(context, listen: false);
    final loc = LocalizationService.instance;
    final name = _nameCtrl.text.trim();
    final desc = _descCtrl.text.trim();
    final status = _active ? 'active' : 'inactive';

    bool ok = false;
    if (widget.existing == null) {
      final id = await inv.createCategory(
        name: name,
        description: desc,
        parentId: _parentId,
        imagePath: _imagePath,
        status: status,
      );
      ok = id != null;
    } else {
      ok = await inv.updateCategory(
        id: widget.existing!.id,
        name: name,
        description: desc,
        parentId: _parentId,
        imagePath: _imagePath,
        status: status,
      );
    }

    if (!mounted) return;
    if (ok) {
      ThemeConstants.showSuccessSnackBar(context, loc.translate('saved'));
      Navigator.of(context).pop(true);
    } else {
      ThemeConstants.showErrorSnackBar(context, loc.translate('operation_failed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final inv =
        widget.providerOverride ?? Provider.of<InventoryProvider>(context);
    final cats = inv.categories;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: ThemeConstants.buildAppBar(
          widget.existing == null ? loc.translate('add_category') : loc.translate('edit_category')),
      body: Stack(
        children: [
          const DecoratedBox(
            decoration: ThemeConstants.dashboardBackground,
            child: SizedBox.expand(),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(16.w),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(loc.translate('category_details'),
                        style: ThemeConstants.headingStyle),
                    SizedBox(height: 12.h),

                    // Name
                    TextFormField(
                      controller: _nameCtrl,
                      style: ThemeConstants.bodyStyle,
                      decoration:
                          ThemeConstants.invInputDecoration(loc.translate('category_name'))
                              .copyWith(
                        labelText: loc.translate('category_name'),
                        hintText: loc.isSwahili ? 'mf. Vinywaji baridi / Soft Drinks' : 'e.g. Vinywaji baridi / Soft Drinks',
                        helperText: loc.isSwahili
                            ? 'Andika "Kiswahili / English" ili jina lionekane kwa lugha ya mtumiaji.'
                            : 'Write "Kiswahili / English" so the name shows in each user\'s language.',
                        helperMaxLines: 2,
                      ),
                      validator: (v) {
                        final val = v?.trim() ?? '';
                        if (val.isEmpty) return loc.translate('category_name_required');
                        if (val.length < 2) return loc.translate('category_name_required');
                        return null;
                      },
                    ),
                    SizedBox(height: 12.h),

                    // Description
                    TextFormField(
                      controller: _descCtrl,
                      style: ThemeConstants.bodyStyle,
                      decoration:
                          ThemeConstants.invInputDecoration(loc.translate('description'))
                              .copyWith(
                        labelText: '${loc.translate('description')} (${loc.translate('optional')})',
                        hintText: loc.isSwahili
                            ? 'mf. Maelezo mafupi ya kundi hili la bidhaa au huduma'
                            : 'e.g. A short note about this group of goods or services',
                      ),
                      maxLines: 3,
                    ),
                    SizedBox(height: 12.h),

                    // Parent dropdown
                    InputDecorator(
                      decoration: ThemeConstants.invInputDecoration(
                          loc.translate('parent_category_optional')),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int?>(
                          value: _parentId,
                          isExpanded: true,
                          dropdownColor: ThemeConstants.primaryBlue,
                          items: [
                            DropdownMenuItem<int?>(
                                child: Text(loc.translate('none'),
                                    style: const TextStyle(color: Colors.white))),
                            ...cats
                                .where((c) =>
                                    widget.existing == null ||
                                    c.id != widget.existing!.id)
                                .map((c) => DropdownMenuItem<int?>(
                                      value: c.id,
                                      child: AutoSizeText(localizedName(c.name),
                                          maxLines: 1,
                                          style: const TextStyle(
                                              color: Colors.white)),
                                    )),
                          ],
                          onChanged: (v) => setState(() => _parentId = v),
                        ),
                      ),
                    ),
                    SizedBox(height: 12.h),

                    // Image picker + preview
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 24.r,
                          backgroundColor: Colors.white24,
                          backgroundImage: (_imagePath != null &&
                                  _imagePath!.isNotEmpty &&
                                  File(_imagePath!).existsSync())
                              ? FileImage(File(_imagePath!))
                              : null,
                          child: (_imagePath == null || _imagePath!.isEmpty)
                              ? const Icon(Icons.image_outlined,
                                  color: Colors.white)
                              : null,
                        ),
                        SizedBox(width: 12.w),
                        ElevatedButton.icon(
                          onPressed: _pickImage,
                          icon: const Icon(Icons.upload_file),
                          label: Text(loc.translate('upload_capture')),
                        ),
                        if (_imagePath != null) ...[
                          SizedBox(width: 8.w),
                          Expanded(
                            child: Text(
                              _imagePath!,
                              style: ThemeConstants.captionStyle,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ]
                      ],
                    ),
                    SizedBox(height: 12.h),

                    // Status
                    Row(
                      children: [
                        Text(loc.translate('status'), style: ThemeConstants.bodyStyle),
                        const Spacer(),
                        Switch(
                          value: _active,
                          onChanged: (v) => setState(() => _active = v),
                        ),
                        SizedBox(width: 6.w),
                        Text(_active ? loc.translate('active') : loc.translate('inactive'),
                            style: ThemeConstants.captionStyle),
                      ],
                    ),
                    SizedBox(height: 24.h),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _submit,
                        child: Text(loc.translate('save_category')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
