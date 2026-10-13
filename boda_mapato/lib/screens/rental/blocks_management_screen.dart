import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import '../../constants/theme_constants.dart';
import '../../providers/rental_provider.dart';
import '../../services/localization_service.dart';

class BlocksManagementScreen extends StatefulWidget {
  const BlocksManagementScreen(
      {required this.propertyId, required this.propertyName, super.key});
  final String propertyId;
  final String propertyName;

  @override
  State<BlocksManagementScreen> createState() => _BlocksManagementScreenState();
}

class _BlocksManagementScreenState extends State<BlocksManagementScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RentalProvider>().fetchBlocks(widget.propertyId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RentalProvider>();
    final blocks = provider.blocks;

    return ThemeConstants.buildResponsiveScaffold(
      context,
      title: LocalizationService.instance.translateWith('blocks_2', <Object?>[widget.propertyName]),
      actions: [
        IconButton(
          icon: const Icon(Icons.add, color: Colors.white),
          onPressed: _showAddBlockDialog,
        ),
      ],
      body: provider.isLoading && blocks.isEmpty
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : blocks.isEmpty
              ? _buildEmptyState()
              : _buildBlocksList(blocks),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(24.w),
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(Icons.view_module, size: 64.sp, color: Colors.white38),
          ),
          SizedBox(height: 24.h),
          Text(LocalizationService.instance.translate('no_blocks_yet'),
              style: TextStyle(color: Colors.white54, fontSize: 18.sp)),
          SizedBox(height: 8.h),
          Text(LocalizationService.instance.translate('add_a_block_for_renting'),
              style: TextStyle(color: Colors.white38, fontSize: 14.sp)),
          SizedBox(height: 24.h),
          ElevatedButton.icon(
            onPressed: _showAddBlockDialog,
            style: ElevatedButton.styleFrom(
              backgroundColor: ThemeConstants.primaryOrange,
              padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 14.h),
            ),
            icon: const Icon(Icons.add, color: Colors.white),
            label: Text(LocalizationService.instance.translate('add_block'), style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildBlocksList(List blocks) {
    return ListView.builder(
      padding: EdgeInsets.all(16.w),
      itemCount: blocks.length,
      itemBuilder: (context, index) {
        final block = blocks[index] as Map<String, dynamic>;
        return _buildBlockCard(block);
      },
    );
  }

  Widget _buildBlockCard(Map<String, dynamic> block) {
    final houses = block['houses'] as List? ?? [];
    final occupied = houses.where((h) => h['status'] == 'occupied').length;

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showBlockDetails(block),
          borderRadius: BorderRadius.circular(20.r),
          child: Padding(
            padding: EdgeInsets.all(16.w),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(14.w),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        ThemeConstants.invAccent.withOpacity(0.3),
                        ThemeConstants.invAccent.withOpacity(0.1)
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14.r),
                  ),
                  child: Icon(Icons.view_module,
                      color: ThemeConstants.invAccent, size: 24.sp),
                ),
                SizedBox(width: 14.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(block['name'] ?? '',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16.sp,
                              fontWeight: FontWeight.w600)),
                      if (block['description'] != null)
                        Text(block['description'],
                            style: TextStyle(
                                color: Colors.white54, fontSize: 12.sp),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                  decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12.r)),
                  child: Text(LocalizationService.instance.translateWith('houses_3', <Object?>[houses.length]),
                      style: TextStyle(color: Colors.white70, fontSize: 12.sp)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAddBlockDialog() {
    final nameController = TextEditingController();
    final descController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.5,
        decoration: BoxDecoration(
          color: ThemeConstants.primaryBlue,
          borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24.r), topRight: Radius.circular(24.r)),
        ),
        child: Column(
          children: [
            Container(
                margin: EdgeInsets.only(top: 12.h),
                width: 40.w,
                height: 4.h,
                decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2.r))),
            Padding(
              padding: EdgeInsets.all(20.w),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(LocalizationService.instance.translate('add_block'),
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 20.sp,
                          fontWeight: FontWeight.bold)),
                  IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white54)),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: Column(
                  children: [
                    TextField(
                      controller: nameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: "${LocalizationService.instance.translate('block_name')} *",
                        labelStyle: const TextStyle(color: Colors.white70),
                        prefixIcon:
                            const Icon(Icons.view_module, color: Colors.white38),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.05),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.r),
                            borderSide: const BorderSide(color: Colors.white12)),
                      ),
                    ),
                    SizedBox(height: 16.h),
                    TextField(
                      controller: descController,
                      maxLines: 3,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: LocalizationService.instance.translate('description_optional'),
                        labelStyle: const TextStyle(color: Colors.white70),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.05),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.r),
                            borderSide: const BorderSide(color: Colors.white12)),
                      ),
                    ),
                    SizedBox(height: 32.h),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          if (nameController.text.isNotEmpty) {
                            final provider = context.read<RentalProvider>();
                            await provider.addBlock(widget.propertyId, {
                              'name': nameController.text,
                              'description': descController.text
                            });
                            if (context.mounted) Navigator.pop(context);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                            backgroundColor: ThemeConstants.primaryOrange,
                            padding: EdgeInsets.symmetric(vertical: 16.h),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12.r))),
                        child: Text(LocalizationService.instance.translate('save'),
                            style: TextStyle(
                                color: Colors.white, fontSize: 16.sp)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showBlockDetails(Map<String, dynamic> block) {
    final houses = block['houses'] as List? ?? [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: ThemeConstants.primaryBlue,
          borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24.r), topRight: Radius.circular(24.r)),
        ),
        child: Column(
          children: [
            Container(
                margin: EdgeInsets.only(top: 12.h),
                width: 40.w,
                height: 4.h,
                decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2.r))),
            Padding(
              padding: EdgeInsets.all(20.w),
              child: Row(
                children: [
                  Icon(Icons.view_module,
                      color: ThemeConstants.invAccent, size: 24.sp),
                  SizedBox(width: 12.w),
                  Text(block['name'] ?? '',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 20.sp,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Expanded(
              child: houses.isEmpty
                  ? Center(
                      child: Text(LocalizationService.instance.translate('no_houses_in_this_block'),
                          style: TextStyle(color: Colors.white54)))
                  : ListView.builder(
                      padding: EdgeInsets.symmetric(horizontal: 20.w),
                      itemCount: houses.length,
                      itemBuilder: (context, index) {
                        final house = houses[index];
                        final status = house['status'] ?? 'vacant';
                        final color = status == 'occupied'
                            ? ThemeConstants.successGreen
                            : Colors.white54;

                        return Container(
                          margin: EdgeInsets.only(bottom: 8.h),
                          padding: EdgeInsets.all(12.w),
                          decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(12.r)),
                          child: Row(
                            children: [
                              Icon(Icons.door_front_door,
                                  color: color, size: 20.sp),
                              SizedBox(width: 12.w),
                              Expanded(
                                  child: Text(house['house_number'] ?? '',
                                      style: const TextStyle(color: Colors.white))),
                              Text(
                                  "TSh ${_formatCurrency(house['rent_amount'])}",
                                  style: TextStyle(
                                      color: Colors.white54, fontSize: 12.sp)),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatCurrency(num value) {
    if (value >= 1000000) return "${(value / 1000000).toStringAsFixed(1)}M";
    if (value >= 1000) return "${(value / 1000).toStringAsFixed(0)}K";
    return value.toString();
  }
}
