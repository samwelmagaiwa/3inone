import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../models/user_permissions.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../services/localization_service.dart';
import '../../models/crates_owed.dart';
import '../../models/inv_product.dart';
import '../../models/inv_product_unit.dart';
import '../../models/inv_sale.dart';
import '../../providers/depot_provider.dart';
import '../../providers/inventory_provider.dart';
import '../../services/inventory_export_service.dart';
import '../scanning/barcode_scanner_screen.dart';
import '../widgets/crates_owed_note.dart';
import '../widgets/inv_units_ui.dart';
import '../widgets/inventory_widgets.dart';
import 'crate_checkout_rules.dart';
import 'sale_confirmation_dialog.dart';
import 'sale_receipt_screen.dart';
import '../salon/price_option_picker.dart';
import '../salon/salon_perks_card.dart';
import '../salon/salon_mode.dart';
import '../salon/goods_used_sheet.dart';
import '../salon/staff_picker.dart';

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _custName = TextEditingController();
  final TextEditingController _custPhone = TextEditingController();
  final TextEditingController _custAddress = TextEditingController();
  final TextEditingController _posPhone = TextEditingController(); // inline POS phone
  final TextEditingController _posName  = TextEditingController(); // inline POS name
  String _status = 'all'; // all | paid | debt | partial
  DateTime? _from;
  DateTime? _to;
  bool _checkingOut = false;
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  bool _loadingMore = false;

  // Toggle ON (default) = customer brought their own empty crates/bottles —
  // clean exchange, nothing to record in the ledger.
  // Toggle OFF = customer did NOT bring empties — they owe us crates back;
  // record an 'issued' movement so the debt appears in the crate ledger.
  bool _customerBroughtCrates = true;
  int? _oweCrateTypeId;
  final TextEditingController _oweCrateQty = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Default history to today
    final today = DateTime.now();
    _from = DateTime(today.year, today.month, today.day);
    _to = DateTime(today.year, today.month, today.day);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final inv = context.read<InventoryProvider>();
      inv.fetchSales(status: _status, from: _from, to: _to);
      inv.fetchSalesSummary(status: _status, from: _from, to: _to);
      final depot = context.read<DepotProvider>();
      if (depot.crateTypes.isEmpty) {
        depot.fetchCrateTypes();
      }
      // Who already holds our crates, so picking them below can say so.
      depot.fetchCrateBalances();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _custName.dispose();
    _custPhone.dispose();
    _custAddress.dispose();
    _posPhone.dispose();
    _posName.dispose();
    _oweCrateQty.dispose();
    _searchCtrl.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  /// Salon: a discount (with why) and how the client paid. Only a salon sees this; the shop's sale screen is as it was.
  Widget _salonMoneyCard(InventoryProvider inv, bool sw) {
    final bool pays = inv.paymentMode != 'debt';
    final String chosen = inv.paymentMode == 'partial' ? inv.partialPaymentMethod : inv.cashChannel;
    String label(String c) {
      switch (c) {
        case 'cash':
          return sw ? 'Taslimu' : 'Cash';
        case 'mpesa':
          return 'M-Pesa';
        case 'mixx':
          return 'Mixx by Yas';
        case 'airtel_money':
          return 'Airtel Money';
        case 'halopesa':
          return 'HaloPesa';
        default:
          return sw ? 'Benki' : 'Bank';
      }
    }

    return Container(
      key: const ValueKey<String>('salon_money_card'),
      decoration: ThemeConstants.invCardDecoration,
      padding: EdgeInsets.all(12.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(sw ? 'Punguzo' : 'Discount', style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700)),
          SizedBox(height: 6.h),
          TextField(
            key: const ValueKey<String>('salon_discount'),
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[ThousandsFormatter()],
            onChanged: (String v) => inv.setCartDiscount(parseAmount(v)),
            decoration: ThemeConstants.invInputDecoration(sw ? 'Kiasi cha punguzo (TZS)' : 'Discount amount (TZS)'),
            style: ThemeConstants.bodyStyle,
          ),
          if (inv.cartDiscount > 0) ...<Widget>[
            SizedBox(height: 8.h),
            TextField(
              key: const ValueKey<String>('salon_discount_reason'),
              onChanged: inv.setDiscountReason,
              decoration: ThemeConstants.invInputDecoration(sw ? 'Sababu ya punguzo' : 'Reason for the discount'),
              style: ThemeConstants.bodyStyle,
            ),
          ],
          if (pays) ...<Widget>[
            SizedBox(height: 12.h),
            Text(sw ? 'Amelipa kwa' : 'Paid by', style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700)),
            SizedBox(height: 6.h),
            Wrap(
              spacing: 8.w,
              runSpacing: 4.h,
              children: <Widget>[
                for (final String c in InventoryProvider.paymentChannels)
                  ChoiceChip(
                    key: ValueKey<String>('channel_$c'),
                    label: Text(label(c)),
                    selected: chosen == c,
                    onSelected: (_) => inv.paymentMode == 'partial' ? inv.setPartialPaymentMethod(c) : inv.setCashChannel(c),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Crate exchange toggle: ON (default) = customer brought their own empty
  /// crates back, normal exchange, nothing to track. OFF = customer did NOT
  /// bring empties, so we issue them crates on credit -- that debt is
  /// tracked in the crate ledger (separate from money owed) and must be
  /// returned later.
  Widget _crateExchangeCard(BuildContext context, InventoryProvider inv) {
    final loc = LocalizationService.instance;
    final depot = context.watch<DepotProvider>();

    return Container(
      decoration: ThemeConstants.invCardDecoration,
      padding: EdgeInsets.all(12.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  loc.isSwahili
                      ? 'Mteja amerudisha makreti/chupa zake tupu?'
                      : 'Did the customer bring back their empty crates?',
                  style: ThemeConstants.bodyStyle,
                ),
              ),
              Switch(
                value: _customerBroughtCrates,
                activeThumbColor: ThemeConstants.invAccent,
                onChanged: (bool v) => setState(() {
                  _customerBroughtCrates = v;
                  if (v) {
                    _oweCrateTypeId = null;
                    _oweCrateQty.clear();
                  }
                }),
              ),
            ],
          ),
          // OFF — customer did NOT bring empties; record crate debt
          if (!_customerBroughtCrates) ...<Widget>[
            SizedBox(height: 4.h),
            Text(
              loc.isSwahili
                  ? 'Mteja anadaiwa makreti — atarudisha baadaye.'
                  : 'Customer owes crates — to be returned later.',
              style: ThemeConstants.captionStyle.copyWith(
                color: ThemeConstants.warningAmber,
              ),
            ),
            SizedBox(height: 8.h),
            DropdownButtonFormField<int>(
              initialValue: _oweCrateTypeId,
              isExpanded: true,
              dropdownColor: ThemeConstants.primaryBlue,
              style: ThemeConstants.bodyStyle,
              decoration: ThemeConstants.invInputDecoration(
                  loc.isSwahili ? 'Aina ya crate' : 'Crate type'),
              items: depot.activeCrateTypes
                  .map((c) => DropdownMenuItem<int>(
                        value: c.id,
                        child: Text(c.name, style: ThemeConstants.bodyStyle),
                      ))
                  .toList(),
              onChanged: (int? v) => setState(() => _oweCrateTypeId = v),
            ),
            SizedBox(height: 8.h),
            InvTextField(
              controller: _oweCrateQty,
              label: loc.isSwahili ? 'Idadi ya makreti' : 'Number of crates',
              hint: 'e.g. 5',
              keyboardType: TextInputType.number,
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final inv = context.watch<InventoryProvider>();
    final perms = context.select<AuthProvider, UserPermissions>((AuthProvider a) => a.permissions);
    final canCreateSales = perms.has('inv_create_sales');

    return SafeArea(
      child: Column(
        children: [
          // Top Segment / Tab Switcher (POS vs History)
          Container(
            margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
            decoration: BoxDecoration(
              color: ThemeConstants.invFill,
              borderRadius: BorderRadius.circular(14.r),
              border: Border.all(color: ThemeConstants.invBorder),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: ThemeConstants.invAccent,
                borderRadius: BorderRadius.circular(10.r),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: Colors.black,
              unselectedLabelColor: Colors.white70,
              labelStyle: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13.sp,
              ),
              tabs: [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.point_of_sale, size: 18.sp),
                      SizedBox(width: 6.w),
                      Flexible(
                        child: Text(
                          loc.translate('create_sale_pos'),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.receipt_long, size: 18.sp),
                      SizedBox(width: 6.w),
                      Flexible(
                        child: Text(
                          loc.translate('sales_history'),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Tab Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // TAB 1: POS Creation
                if (canCreateSales)
                  _buildPosTab(context, inv, loc)
                else
                  Center(
                    child: Text(
                      loc.translate('no_permission'),
                      style: ThemeConstants.bodyStyle,
                    ),
                  ),

                // TAB 2: Sales History & Ledger
                _buildHistoryTab(context, inv, loc),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 1: POS CREATION TAB
  // ==========================================
  Widget _buildPosTab(
      BuildContext context, InventoryProvider inv, LocalizationService loc) {
    final auth = context.read<AuthProvider>();
    // Customer edit/delete is gated server-side by inv_manage_products.
    final canManageCustomers = context.select<AuthProvider, UserPermissions>((AuthProvider a) => a.permissions).has('inv_manage_products');
    final userId = int.tryParse(auth.user?.id ?? '') ?? 1;

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Action Toolbar: Add Products + Scan + Clear Cart
          Container(
            padding: EdgeInsets.all(12.w),
            decoration: ThemeConstants.invCardDecoration,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ThemeConstants.invAccent,
                          foregroundColor: Colors.black,
                          padding: EdgeInsets.symmetric(vertical: 12.h),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10.r),
                          ),
                        ),
                        onPressed: () => _openProductPicker(context),
                        icon: Icon(Icons.add_shopping_cart, size: 20.sp),
                        label: Text(
                          inv.cart.isEmpty
                              ? (isSalonMode(context) ? (loc.isSwahili ? 'Ongeza huduma au bidhaa' : 'Add services or goods') : loc.translate('add_products'))
                              : '${isSalonMode(context) ? (loc.isSwahili ? 'Ongeza huduma au bidhaa' : 'Add services or goods') : loc.translate('add_products')} (${inv.cart.length})',
                          style: TextStyle(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 8.w),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: ThemeConstants.invBorder),
                          padding: EdgeInsets.symmetric(vertical: 12.h),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10.r),
                          ),
                        ),
                        onPressed: () => _scanToCart(context),
                        icon: Icon(Icons.qr_code_scanner,
                            size: 18.sp, color: Colors.white),
                        label: Text(
                          loc.translate('scan'),
                          style: ThemeConstants.bodyStyle,
                        ),
                      ),
                    ),
                    if (inv.cart.isNotEmpty) ...[
                      SizedBox(width: 6.w),
                      IconButton(
                        tooltip: LocalizationService.instance.translate('clear_cart'),
                        icon: const Icon(Icons.delete_outline,
                            color: ThemeConstants.errorRed),
                        onPressed: () => inv.clearCart(),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: 12.h),

          // Cart Items List / Empty Placeholder
          if (inv.cart.isEmpty)
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: 24.h, horizontal: 16.w),
              decoration: ThemeConstants.invCardDecoration,
              child: Column(
                children: [
                  Icon(Icons.shopping_bag_outlined,
                      size: 44.sp, color: Colors.white38),
                  SizedBox(height: 8.h),
                  Text(
                    isSalonMode(context) ? (loc.isSwahili ? 'Ongeza huduma au bidhaa, chagua aliyehudumia, kisha njia ya malipo.' : 'Add services or goods, choose who served, then the payment mode.') : loc.translate('create_sale_hint'),
                    style: ThemeConstants.bodyStyle
                        .copyWith(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            Container(
              decoration: ThemeConstants.invCardDecoration,
              padding: EdgeInsets.all(12.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        LocalizationService.instance.translateWith('cart_items', <Object?>[inv.cart.length]),
                        style: ThemeConstants.headingStyle,
                      ),
                      Text(
                        'Total: TZS ${inv.cartTotal.toStringAsFixed(0)}',
                        style: TextStyle(
                          color: ThemeConstants.invAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 14.sp,
                        ),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white24, height: 16),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: inv.cart.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: Colors.white12, height: 12),
                    itemBuilder: (_, i) => _CartRow(item: inv.cart[i]),
                  ),
                ],
              ),
            ),
          SizedBox(height: 12.h),

          // Payment & Customer Configuration
          Container(
            decoration: ThemeConstants.invCardDecoration,
            padding: EdgeInsets.all(12.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  LocalizationService.instance.translate('payment_customer'),
                  style: ThemeConstants.headingStyle,
                ),
                SizedBox(height: 10.h),

                // Payment Mode Segment Pills
                Row(
                  children: [
                    Text(
                      '${loc.translate('payment_mode')}:',
                      style: ThemeConstants.captionStyle,
                    ),
                    SizedBox(width: 8.w),
                    Expanded(
                      child: Row(
                        children: [
                          _buildModeChip(inv, 'cash', loc.translate('cash')),
                          SizedBox(width: 6.w),
                          _buildModeChip(inv, 'debt', loc.translate('debt')),
                          SizedBox(width: 6.w),
                          _buildModeChip(
                              inv, 'partial', loc.translate('partial')),
                        ],
                      ),
                    ),
                  ],
                ),

                // Customer Selector (if Debt or Partial)
                if (inv.paymentMode != 'cash') ...[
                  SizedBox(height: 12.h),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int?>(
                          key: ValueKey<String>('customer_${inv.selectedCustomerId}'),
                          initialValue: inv.selectedCustomerId,
                          // Fill the space left beside the add/delete buttons and
                          // cut long names short instead of overflowing.
                          isExpanded: true,
                          dropdownColor: ThemeConstants.primaryBlue,
                          decoration: ThemeConstants.invInputDecoration(
                              loc.translate('select_customer')),
                          style: ThemeConstants.bodyStyle,
                          items: [
                            DropdownMenuItem<int?>(
                              child: Text(
                                loc.translate('select_customer'),
                                style: ThemeConstants.bodyStyle,
                              ),
                            ),
                            ...inv.customers.map(
                              (c) => DropdownMenuItem<int?>(
                                value: c.id,
                                child: Text(c.name,
                                    overflow: TextOverflow.ellipsis,
                                    style: ThemeConstants.bodyStyle),
                              ),
                            ),
                          ],
                          onChanged: (id) {
                            inv.setCustomer(id);
                            // Auto-fill name & phone from saved customer record
                            final c = id == null
                                ? null
                                : inv.customers.where((c) => c.id == id).firstOrNull;
                            _posName.text  = c?.name  ?? '';
                            _posPhone.text = c?.phone ?? '';
                            inv.setManualName(_posName.text);
                          },
                        ),
                      ),
                      if (canManageCustomers) ...[
                        SizedBox(width: 8.w),
                        IconButton(
                          style: IconButton.styleFrom(
                            backgroundColor: ThemeConstants.invFill,
                            side:
                                const BorderSide(color: ThemeConstants.invBorder),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10.r),
                            ),
                          ),
                          tooltip: loc.translate('add_customer'),
                          icon: const Icon(Icons.person_add,
                              color: Colors.white),
                          onPressed: () => _openCreateCustomerDialog(context),
                        ),
                        if (inv.selectedCustomerId != null) ...[
                          SizedBox(width: 6.w),
                          IconButton(
                            style: IconButton.styleFrom(
                              backgroundColor: ThemeConstants.invFill,
                              side: const BorderSide(
                                  color: ThemeConstants.invBorder),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10.r),
                              ),
                            ),
                            tooltip: loc.isSwahili
                                ? 'Futa mteja'
                                : 'Delete customer',
                            icon: const Icon(Icons.person_remove,
                                color: ThemeConstants.errorRed),
                            onPressed: () => _confirmDeleteCustomer(context, inv),
                          ),
                        ],
                      ],
                    ],
                  ),
                ],

                // If the picked customer is still holding our crates, say so before
                // another sale is made to them.
                if (!isSalonMode(context) && inv.paymentMode != 'cash' && inv.selectedCustomerId != null)
                  CratesOwedNote(
                    owed: CratesOwed.forCustomer(
                      context.watch<DepotProvider>().crateBalances,
                      inv.selectedCustomerId!,
                    ),
                    swahili: loc.isSwahili,
                    isDepot: inv.capabilities.isDepot,
                  ),

                // Customer name + phone (always shown, optional)
                SizedBox(height: 10.h),
                TextField(
                  controller: _posName,
                  onChanged: inv.setManualName,
                  decoration: ThemeConstants.invInputDecoration(
                    loc.translate('customer_name'),
                  ).copyWith(
                    hintText: loc.isSwahili ? 'Jina la mteja (hiari)' : 'Customer name (optional)',
                    prefixIcon: const Icon(Icons.person_outline, color: Colors.white54, size: 18),
                  ),
                  style: ThemeConstants.bodyStyle,
                ),
                SizedBox(height: 8.h),
                TextField(
                  controller: _posPhone,
                  keyboardType: TextInputType.phone,
                  onChanged: inv.setManualPhone,
                  decoration: ThemeConstants.invInputDecoration(
                    loc.translate('phone_number'),
                  ).copyWith(
                    hintText: loc.isSwahili ? 'Nambari ya simu (hiari)' : 'Phone number (optional)',
                    prefixIcon: const Icon(Icons.phone_outlined, color: Colors.white54, size: 18),
                  ),
                  style: ThemeConstants.bodyStyle,
                ),

                // Paid Amount + method (if Partial)
                if (inv.paymentMode == 'partial') ...[
                  SizedBox(height: 10.h),
                  TextField(
                    onChanged: (v) => inv.setPaidAmount(parseAmount(v)),
                    keyboardType: TextInputType.number,
                    inputFormatters: [ThousandsFormatter()],
                    decoration: ThemeConstants.invInputDecoration(
                        loc.translate('paid_amount')),
                    style: ThemeConstants.bodyStyle,
                  ),
                  if (!isSalonMode(context)) ...[
                  SizedBox(height: 8.h),
                  DropdownButtonFormField<String>(
                    initialValue: inv.partialPaymentMethod,
                    isExpanded: true,
                    dropdownColor: ThemeConstants.primaryBlue,
                    style: ThemeConstants.bodyStyle,
                    decoration: ThemeConstants.invInputDecoration(
                        loc.translate('method')),
                    items: const ['cash', 'mobile_money', 'bank_transfer']
                        .map((m) => DropdownMenuItem(
                              value: m,
                              child: Text(loc.translate(m),
                                  style: ThemeConstants.bodyStyle),
                            ))
                        .toList(),
                    onChanged: (v) =>
                        inv.setPartialPaymentMethod(v ?? 'cash'),
                  ),
                  ],
                ],
              ],
            ),
          ),
          SizedBox(height: 10.h),
          if (isSalonMode(context)) ...[
            _salonMoneyCard(inv, loc.isSwahili),
            SizedBox(height: 10.h),
            const SalonPerksCard(),
            SizedBox(height: 10.h),
          ],
          // Crates and empties: only for businesses that deal in returnable packaging (a depot).
          // (Never in a salon, whatever the settings say: it has no returnable packaging.)
          if (!isSalonMode(context) && context.watch<DepotProvider>().capabilities.useCrates) _crateExchangeCard(context, inv),
          SizedBox(height: 16.h),

          // Retail or wholesale prices: for businesses that sell at both (a depot prices by product).
          if (inv.capabilities.usesPriceLevels) ...[
            _priceLevelRow(inv, loc),
            SizedBox(height: 10.h),
          ],

          // Grand Total Breakdown & Checkout Button
          Container(
            decoration: ThemeConstants.invCardDecoration.copyWith(
              border: Border.all(color: ThemeConstants.invAccent, width: 1.2),
            ),
            padding: EdgeInsets.all(14.w),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      loc.translate('subtotal'),
                      style: ThemeConstants.bodyStyle,
                    ),
                    Text(
                      'TZS ${inv.cartSubtotal.toStringAsFixed(0)}',
                      style: ThemeConstants.bodyStyle,
                    ),
                  ],
                ),
                if (inv.cartDiscount > 0) ...[
                  SizedBox(height: 4.h),
                  Row(
                    key: const ValueKey<String>('cart_discount_row'),
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(loc.isSwahili ? 'Punguzo' : 'Discount', style: ThemeConstants.captionStyle),
                      Text('- TZS ${inv.cartDiscount.toStringAsFixed(0)}', style: ThemeConstants.captionStyle.copyWith(color: ThemeConstants.warningAmber)),
                    ],
                  ),
                ],
                if (inv.cartTax > 0) ...[
                  SizedBox(height: 4.h),
                  Row(
                    key: const ValueKey<String>('cart_vat_row'),
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        inv.capabilities.pricesIncludeVat
                            ? (loc.isSwahili ? 'VAT (ndani ya bei)' : 'VAT (included)')
                            : 'VAT',
                        style: ThemeConstants.captionStyle,
                      ),
                      Text(
                        'TZS ${inv.cartTax.toStringAsFixed(0)}',
                        style: ThemeConstants.captionStyle,
                      ),
                    ],
                  ),
                ],
                SizedBox(height: 4.h),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      loc.translate('total'),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'TZS ${inv.cartTotal.toStringAsFixed(0)}',
                      style: TextStyle(
                        color: ThemeConstants.invAccent,
                        fontSize: 20.sp,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12.h),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ThemeConstants.invAccent,
                      foregroundColor: Colors.black,
                      padding: EdgeInsets.symmetric(vertical: 14.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                    ),
                    onPressed: (inv.cart.isEmpty || _checkingOut)
                        ? null
                        : () async {
                            // A salon says why a discount was given.
                            if (isSalonMode(context, listen: false) && inv.cartDiscount > 0 && inv.discountReason.trim().isEmpty) {
                              ThemeConstants.showErrorSnackBar(context, loc.isSwahili ? 'Andika sababu ya punguzo.' : 'Write the reason for the discount.');
                              return;
                            }
                            // A salon names who served the client on every service: a complaint then says who it is about.
                            if (isSalonMode(context, listen: false)) {
                              final InvSaleItem? unnamed = inv.cart.where((InvSaleItem i) => i.isService && (i.staffId ?? '').isEmpty).firstOrNull;
                              if (unnamed != null) {
                                ThemeConstants.showErrorSnackBar(context, loc.isSwahili ? 'Chagua mhudumu aliyemhudumia mteja.' : 'Choose the stylist who served the client.');
                                await pickStylist(context, unnamed);
                                return;
                              }
                            }
                            // If the customer did not bring empties, the crates they
                            // owe MUST be recorded with the sale -- never skipped.
                            final depot = context.read<DepotProvider>();
                            final CrateCheckoutProblem? crateProblem =
                                crateCheckoutProblem(
                              customerBroughtCrates: _customerBroughtCrates,
                              hasCrateTypes: depot.activeCrateTypes.isNotEmpty,
                              crateTypeId: _oweCrateTypeId,
                              quantityText: _oweCrateQty.text,
                            );
                            if (crateProblem != null) {
                              ThemeConstants.showWarningSnackBar(
                                context,
                                crateCheckoutMessage(crateProblem,
                                    swahili: loc.isSwahili),
                              );
                              return;
                            }

                            // Toggle OFF = customer didn't bring empties →
                            // pass crate debt fields so the backend records
                            // an 'issued' movement inside the same transaction.
                            // Toggle ON = clean exchange, nothing to record.
                            final int? crateTypeId =
                                _customerBroughtCrates ? null : _oweCrateTypeId;
                            final int? crateQty = _customerBroughtCrates
                                ? null
                                : int.tryParse(_oweCrateQty.text.trim());

                            // Show what is about to be sold, and its amount, and
                            // only go on when the user says yes.
                            final String? pickedName = inv.selectedCustomerId == null
                                ? null
                                : inv.customers
                                    .where((c) => c.id == inv.selectedCustomerId)
                                    .firstOrNull
                                    ?.name;
                            final bool confirmed = await showSaleConfirmation(
                              context,
                              SaleConfirmation(
                                items: inv.cart,
                                subtotal: inv.cartSubtotal,
                                discount: inv.cartDiscount,
                                total: inv.cartTotal,
                                tax: inv.cartTax,
                                taxIncluded: inv.capabilities.pricesIncludeVat,
                                paymentMode: inv.paymentMode,
                                customerName: pickedName ?? _posName.text,
                                paidNow: inv.paidAmount,
                                crateTypeName: crateTypeId == null
                                    ? null
                                    : depot.crateTypes
                                        .where((c) => c.id == crateTypeId)
                                        .firstOrNull
                                        ?.name,
                                crateQty: crateQty,
                              ),
                              swahili: loc.isSwahili,
                            );
                            if (!confirmed || !context.mounted) return;

                            setState(() => _checkingOut = true);
                            final result = await inv.checkout(
                              createdBy: userId,
                              crateTypeId: crateTypeId,
                              crateQty: crateQty,
                              crateDirection: crateTypeId != null ? 'issued' : null,
                            );
                            if (!context.mounted) return;
                            final ok = result.$1;
                            final msgKey = result.$2;
                            if (!context.mounted) return;
                            setState(() => _checkingOut = false);
                            if (!ok) {
                              // A server sentence is shown as it is; a short key is translated.
                              ThemeConstants.showErrorSnackBar(
                                  context, msgKey.contains(' ') ? msgKey : loc.translate(msgKey));
                            } else {
                              _posPhone.clear();
                              _posName.clear();
                              setState(() {
                                _customerBroughtCrates = true;
                                _oweCrateTypeId = null;
                                _oweCrateQty.clear();
                              });
                              // Refresh crate data so the Crates & Empties
                              // screen reflects any movement recorded in this sale.
                              if (crateTypeId != null && context.mounted) {
                                final depot = context.read<DepotProvider>();
                                unawaited(Future.wait<void>(<Future<void>>[
                                  depot.fetchCratePosition(),
                                  depot.fetchCrateBalances(),
                                ]));
                              }
                              ThemeConstants.showSuccessSnackBar(
                                  context, loc.translate('success'));
                            }
                          },
                    icon: _checkingOut
                        ? SizedBox(
                            width: 18.sp,
                            height: 18.sp,
                            child: const CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : Icon(Icons.payments_outlined, size: 22.sp),
                    label: Text(
                      _checkingOut
                          ? '${LocalizationService.instance.translate('sending_2')}...'
                          : '${loc.translate('checkout')} • TZS ${inv.cartTotal.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 16.h),
        ],
      ),
    );
  }

  /// Retail | Wholesale: re-prices the whole cart from the catalogue.
  Widget _priceLevelRow(InventoryProvider inv, LocalizationService loc) {
    return Row(
      children: [
        Text(loc.isSwahili ? 'Bei:' : 'Price level:', style: ThemeConstants.captionStyle),
        SizedBox(width: 8.w),
        for (final (String tier, String label) in <(String, String)>[
          ('retail', loc.isSwahili ? 'Rejareja' : 'Retail'),
          ('wholesale', loc.isSwahili ? 'Jumla' : 'Wholesale'),
        ])
          Padding(
            padding: EdgeInsets.only(right: 6.w),
            child: ChoiceChip(
              key: ValueKey<String>('tier_$tier'),
              label: Text(label, style: TextStyle(fontSize: 12.sp)),
              selected: inv.cartTier == tier,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => inv.setCartTier(tier),
            ),
          ),
      ],
    );
  }

  Widget _buildModeChip(InventoryProvider inv, String mode, String label) {
    final bool selected = inv.paymentMode == mode;
    return Expanded(
      child: InkWell(
        onTap: () => inv.setPaymentMode(mode),
        borderRadius: BorderRadius.circular(10.r),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(vertical: 8.h),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? ThemeConstants.invAccent : ThemeConstants.invFill,
            borderRadius: BorderRadius.circular(10.r),
            border: Border.all(
              color: selected
                  ? ThemeConstants.invAccent
                  : ThemeConstants.invBorder,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.black : Colors.white,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              fontSize: 12.sp,
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // TAB 2: SALES HISTORY & LEDGER TAB
  // ==========================================
  Widget _buildHistoryTab(
      BuildContext context, InventoryProvider inv, LocalizationService loc) {
    // Cancelling a sale is gated server-side by inv_manage_sales.
    final isManager = context.select<AuthProvider, UserPermissions>((AuthProvider a) => a.permissions).has('inv_manage_sales');
    final summary = inv.salesSummary;

    void _applyFilters() {
      final q = _searchCtrl.text.trim();
      inv.fetchSales(status: _status, from: _from, to: _to, q: q.isEmpty ? null : q);
      inv.fetchSalesSummary(status: _status, from: _from, to: _to, q: q.isEmpty ? null : q);
    }

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Search bar ──────────────────────────────────────────────────
          Container(
            decoration: ThemeConstants.glassCardDecoration,
            child: TextField(
              controller: _searchCtrl,
              style: ThemeConstants.bodyStyle,
              decoration: InputDecoration(
                hintText: '${LocalizationService.instance.translate('search_receipt_number_customer')}...',
                hintStyle: ThemeConstants.captionStyle,
                prefixIcon: const Icon(Icons.search, color: Colors.white54),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white54),
                        onPressed: () {
                          _searchCtrl.clear();
                          _applyFilters();
                          setState(() {});
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.transparent,
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 14.h),
              ),
              onChanged: (_) {
                setState(() {});
                _searchDebounce?.cancel();
                _searchDebounce = Timer(const Duration(milliseconds: 500), _applyFilters);
              },
            ),
          ),
          SizedBox(height: 8.h),

          // ── Filter row ──────────────────────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                DropdownButton<String>(
                  value: _status,
                  dropdownColor: ThemeConstants.primaryBlue,
                  items: ['all', 'paid', 'debt', 'partial']
                      .map((v) => DropdownMenuItem(
                            value: v,
                            child: Text(loc.translate(v), style: ThemeConstants.bodyStyle),
                          ))
                      .toList(),
                  onChanged: (v) {
                    setState(() => _status = v ?? 'all');
                    _applyFilters();
                  },
                ),
                SizedBox(width: 8.w),
                TextButton.icon(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _from ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (d != null && context.mounted) {
                      setState(() => _from = d);
                      _applyFilters();
                    }
                  },
                  icon: const Icon(Icons.date_range, color: Colors.white70),
                  label: Text(
                    _from != null ? _from!.toLocal().toString().split(' ').first : LocalizationService.instance.translate('from_2'),
                    style: ThemeConstants.captionStyle,
                  ),
                ),
                if (_from != null)
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.white38, size: 14.sp),
                    onPressed: () {
                      setState(() => _from = null);
                      _applyFilters();
                    },
                  ),
                SizedBox(width: 4.w),
                TextButton.icon(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _to ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (d != null && context.mounted) {
                      setState(() => _to = d);
                      _applyFilters();
                    }
                  },
                  icon: const Icon(Icons.date_range, color: Colors.white70),
                  label: Text(
                    _to != null ? _to!.toLocal().toString().split(' ').first : LocalizationService.instance.translate('to_2'),
                    style: ThemeConstants.captionStyle,
                  ),
                ),
                if (_to != null)
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.white38, size: 14.sp),
                    onPressed: () {
                      setState(() => _to = null);
                      _applyFilters();
                    },
                  ),
              ],
            ),
          ),
          SizedBox(height: 8.h),

          // ── Summary stats bar ──────────────────────────────────────────
          if (summary.isNotEmpty)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
              decoration: ThemeConstants.glassCardDecoration,
              child: Row(
                children: [
                  _StatChip(
                    label: loc.translate('sales'),
                    value: '${(summary['count'] as num? ?? 0).toInt()}',
                    icon: Icons.receipt_long_rounded,
                    color: Colors.white70,
                  ),
                  _StatChip(
                    label: loc.translate('total'),
                    value: 'TZS ${_fmt(summary['total'])}',
                    icon: Icons.attach_money_rounded,
                    color: ThemeConstants.primaryBlue,
                  ),
                  _StatChip(
                    label: loc.translate('paid'),
                    value: 'TZS ${_fmt(summary['paid'])}',
                    icon: Icons.check_circle_outline,
                    color: ThemeConstants.successGreen,
                  ),
                  _StatChip(
                    label: loc.translate('debt'),
                    value: 'TZS ${_fmt(summary['debt'])}',
                    icon: Icons.warning_amber_rounded,
                    color: ThemeConstants.errorRed,
                  ),
                ],
              ),
            ),
          if (summary.isNotEmpty) SizedBox(height: 10.h),

          // ── Sales list ─────────────────────────────────────────────────
          if (inv.sales.isEmpty)
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(24.w),
              decoration: ThemeConstants.invCardDecoration,
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.receipt_long_outlined, color: Colors.white24, size: 40.sp),
                    SizedBox(height: 8.h),
                    Text(loc.translate('no_sales_found'), style: ThemeConstants.captionStyle),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              itemCount: inv.sales.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              separatorBuilder: (_, __) => SizedBox(height: 8.h),
              itemBuilder: (context, index) {
                final s = inv.sales[index];
                final custName = s.customerName?.isNotEmpty == true
                    ? s.customerName!
                    : (inv.customers
                            .where((c) => s.customerId != null && c.id == s.customerId)
                            .map((c) => c.name)
                            .firstOrNull ??
                        '-');
                final balance = (s.total - s.paidTotal).clamp(0.0, s.total);

                Color statusColor;
                if (s.isCancelled) {
                  statusColor = Colors.white38;
                } else if (s.paymentStatus == 'paid') {
                  statusColor = ThemeConstants.successGreen;
                } else if (s.paymentStatus == 'debt') {
                  statusColor = ThemeConstants.errorRed;
                } else {
                  statusColor = ThemeConstants.warningAmber;
                }

                final statusLabel = s.isCancelled
                    ? LocalizationService.instance.translate('cancelled').toUpperCase()
                    : s.paymentStatus.toUpperCase();

                return Container(
                  decoration: ThemeConstants.invCardDecoration,
                  padding: EdgeInsets.all(10.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: EdgeInsets.all(8.w),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.receipt_long, color: statusColor, size: 18.sp),
                          ),
                          SizedBox(width: 10.w),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('#${s.number}',
                                        style: ThemeConstants.bodyStyle
                                            .copyWith(fontWeight: FontWeight.bold)),
                                    Container(
                                      padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 2.h),
                                      decoration: BoxDecoration(
                                        color: statusColor.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(6.r),
                                      ),
                                      child: Text(statusLabel,
                                          style: TextStyle(
                                              color: statusColor,
                                              fontSize: 9.sp,
                                              fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 2.h),
                                Text(
                                  '$custName  •  ${s.createdAt.day}/${s.createdAt.month}/${s.createdAt.year}',
                                  style: ThemeConstants.captionStyle,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 6.h),
                      Padding(
                        padding: EdgeInsets.only(left: 44.w),
                        child: Row(
                          children: [
                            _AmountBadge(label: loc.translate('total'), amount: s.total, color: Colors.white70),
                            SizedBox(width: 6.w),
                            _AmountBadge(label: loc.translate('paid'), amount: s.paidTotal, color: ThemeConstants.successGreen),
                            if (!s.isCancelled && s.paymentStatus != 'paid') ...[
                              SizedBox(width: 6.w),
                              _AmountBadge(label: loc.translate('debt'), amount: balance, color: ThemeConstants.errorRed),
                            ],
                          ],
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            tooltip: loc.translate('view_receipt'),
                            onPressed: () => Navigator.of(context).push(SaleReceiptScreen.route(s)),
                            icon: Icon(Icons.receipt_long_outlined, color: Colors.white70, size: 19.sp),
                          ),
                          IconButton(
                            tooltip: loc.translate('print_share'),
                            onPressed: () => _shareReceipt(context, s),
                            icon: Icon(Icons.print_outlined, color: Colors.white70, size: 19.sp),
                          ),
                          if (!s.isCancelled && s.paymentStatus != 'paid')
                            IconButton(
                              tooltip: loc.translate('pay_debt'),
                              onPressed: () => _showPayDebtSheet(context, s),
                              icon: Icon(Icons.payments_outlined, color: ThemeConstants.warningAmber, size: 19.sp),
                            ),
                          if (isManager && !s.isCancelled)
                            IconButton(
                              tooltip: loc.translate('cancel_sale'),
                              onPressed: () => _showCancelSheet(context, s),
                              icon: Icon(Icons.cancel_outlined, color: ThemeConstants.errorRed, size: 19.sp),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),

          // ── Load more ──────────────────────────────────────────────────
          if (inv.salesHasMore)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 12.h),
              child: Center(
                child: _loadingMore
                    ? const CircularProgressIndicator(color: Colors.white54)
                    : OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Colors.white24),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10.r),
                          ),
                        ),
                        onPressed: () async {
                          setState(() => _loadingMore = true);
                          await context.read<InventoryProvider>().loadMoreSales(
                                status: _status,
                                from: _from,
                                to: _to,
                                q: _searchCtrl.text.trim().isEmpty
                                    ? null
                                    : _searchCtrl.text.trim(),
                              );
                          if (mounted) setState(() => _loadingMore = false);
                        },
                        icon: const Icon(Icons.expand_more),
                        label: Text(loc.translate('load_more')),
                      ),
              ),
            ),

          SizedBox(height: 24.h),
        ],
      ),
    );
  }

  void _showPayDebtSheet(BuildContext context, InvSale sale) {
    final balance = (sale.total - sale.paidTotal).clamp(0.0, sale.total);
    final amountCtrl = TextEditingController(text: balance.toStringAsFixed(0));
    String method = 'cash';
    bool busy = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: ThemeConstants.primaryBlue,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setBS) {
        final loc = LocalizationService.instance;
        return Padding(
          padding: EdgeInsets.fromLTRB(
              20.w, 20.h, 20.w, MediaQuery.of(ctx).viewInsets.bottom + 20.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${loc.translate('pay_debt')} — #${sale.number}',
                  style: ThemeConstants.bodyStyle.copyWith(
                      fontWeight: FontWeight.bold, fontSize: 15.sp)),
              SizedBox(height: 4.h),
              Text('${loc.translate('balance')}: TZS ${balance.toStringAsFixed(0)}',
                  style: ThemeConstants.captionStyle),
              SizedBox(height: 14.h),
              InvTextField(
                controller: amountCtrl,
                label: loc.translate('amount_tzs'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              SizedBox(height: 10.h),
              DropdownButtonFormField<String>(
                value: method,
                isExpanded: true,
                dropdownColor: ThemeConstants.primaryBlue,
                // Same dark field as the Amount above. A bare InputDecoration here
                // inherits the app-wide white fill, giving a white box with white text.
                decoration: ThemeConstants.invInputDecoration(
                        loc.translate('payment_method'))
                    .copyWith(labelText: loc.translate('payment_method')),
                style: ThemeConstants.bodyStyle,
                items: [
                  DropdownMenuItem(value: 'cash', child: Text(loc.translate('cash'))),
                  DropdownMenuItem(value: 'mobile_money', child: Text(loc.translate('mobile_money'))),
                  DropdownMenuItem(value: 'bank_transfer', child: Text(loc.translate('bank_transfer'))),
                ],
                onChanged: (v) => setBS(() => method = v ?? 'cash'),
              ),
              SizedBox(height: 16.h),
              InvPrimaryButton(
                busy: busy,
                label: loc.translate('record_payment'),
                onPressed: () async {
                  final amt = double.tryParse(amountCtrl.text.trim()) ?? 0;
                  if (amt <= 0) return;
                  setBS(() => busy = true);
                  final inv = context.read<InventoryProvider>();
                  final (ok, _) = await inv.recordSalePayment(sale.id, amt, method);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    ok
                        ? ThemeConstants.showInfoSnackBar(context, loc.translate('payment_recorded'))
                        : ThemeConstants.showErrorSnackBar(context, loc.translate('failed_to_record_payment'));
                  }
                },
              ),
            ],
          ),
        );
      }),
    );
  }

  void _showCancelSheet(BuildContext context, InvSale sale) {
    final reasonCtrl = TextEditingController();
    bool busy = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: ThemeConstants.primaryBlue,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setBS) {
        final loc = LocalizationService.instance;
        return Padding(
          padding: EdgeInsets.fromLTRB(
              20.w, 20.h, 20.w, MediaQuery.of(ctx).viewInsets.bottom + 20.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${loc.translate('cancel_sale')} — #${sale.number}',
                  style: ThemeConstants.bodyStyle.copyWith(
                      fontWeight: FontWeight.bold, fontSize: 15.sp,
                      color: ThemeConstants.errorRed)),
              SizedBox(height: 4.h),
              Text(loc.translate('stock_auto_restored'),
                  style: ThemeConstants.captionStyle),
              SizedBox(height: 14.h),
              InvTextField(
                controller: reasonCtrl,
                label: loc.translate('cancel_reason'),
                hint: loc.translate('cancel_reason_hint'),
              ),
              SizedBox(height: 16.h),
              InvPrimaryButton(
                busy: busy,
                label: loc.translate('confirm_cancel'),
                onPressed: () async {
                  final reason = reasonCtrl.text.trim();
                  if (reason.isEmpty) return;
                  setBS(() => busy = true);
                  final inv = context.read<InventoryProvider>();
                  final (ok, _) = await inv.cancelSale(sale.id, reason);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    ok
                        ? ThemeConstants.showInfoSnackBar(context, loc.translate('sale_cancelled_stock_restored'))
                        : ThemeConstants.showErrorSnackBar(context, loc.translate('failed_to_cancel_sale'));
                  }
                },
              ),
            ],
          ),
        );
      }),
    );
  }

  String _fmt(dynamic v) {
    final n = v is num ? v.toDouble() : double.tryParse('$v') ?? 0.0;
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}K';
    return n.toStringAsFixed(0);
  }

  static const InventoryExportService _exportService =
      InventoryExportService();

  Future<void> _shareReceipt(BuildContext context, InvSale sale) async {
    final loc = LocalizationService.instance;
    final inv = context.read<InventoryProvider>();
    final matches = inv.customers
        .where((c) => sale.customerId != null && c.id == sale.customerId)
        .toList();

    final String? action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: ThemeConstants.primaryBlue,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.print_outlined, color: Colors.white70),
              title: Text(loc.translate('print_receipt'),
                  style: ThemeConstants.bodyStyle),
              onTap: () => Navigator.pop(ctx, 'print'),
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined, color: Colors.white70),
              title: Text(loc.translate('share_receipt'),
                  style: ThemeConstants.bodyStyle),
              onTap: () => Navigator.pop(ctx, 'share'),
            ),
          ],
        ),
      ),
    );

    if (action == null || !context.mounted) return;

    try {
      // The receipt carries the business's own name, phone and address (set in Settings).
      final Map<String, String> shop = context.read<DepotProvider>().settings;
      final File file = await _exportService.saleReceiptToPdf(
        sale,
        customer: matches.isEmpty ? null : matches.first,
        depotName: shop['depot_name'] ?? '',
        depotPhone: shop['depot_phone'] ?? '',
        depotAddress: shop['depot_address'] ?? '',
      );
      if (!context.mounted) return;
      if (action == 'print') {
        await _exportService.printPdf(file);
      } else {
        await _exportService.shareFile(file,
            subject: '${loc.translate('receipt')} ${sale.number}');
      }
    } on Exception {
      if (context.mounted) {
        ThemeConstants.showErrorSnackBar(
            context, loc.translate('export_failed'));
      }
    }
  }

  Future<void> _scanToCart(BuildContext context) async {
    final loc = LocalizationService.instance;
    final String? code =
        await scanBarcode(context, title: loc.translate('scan_to_add'));
    if (code == null || code.isEmpty || !context.mounted) return;

    final depot = context.read<DepotProvider>();
    final inv = context.read<InventoryProvider>();
    final result = await depot.resolveBarcode(code);

    if (result == null || result.productId == null) {
      if (context.mounted) {
        ThemeConstants.showErrorSnackBar(
            context, loc.translate('barcode_not_found'));
      }
      return;
    }

    final matches =
        inv.products.where((p) => p.id == result.productId).toList();
    if (matches.isEmpty) {
      if (context.mounted) {
        ThemeConstants.showErrorSnackBar(
            context, loc.translate('barcode_not_found'));
      }
      return;
    }

    if (!await addToCartAskingPrice(context, inv, matches.first)) return;
    if (context.mounted) {
      ThemeConstants.showSuccessSnackBar(
        context,
        '${matches.first.name} ${loc.translate('added_to_cart')}',
      );
    }
  }

  Future<void> _openProductPicker(BuildContext context) async {
    final loc = LocalizationService.instance;
    final inv = context.read<InventoryProvider>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ThemeConstants.primaryBlue,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 12.w,
            right: 12.w,
            top: 12.h,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 12.h,
          ),
          child: SizedBox(
            height: 0.7.sh,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        loc.translate('add_to_cart'),
                        style: ThemeConstants.headingStyle,
                      ),
                    ),
                    IconButton(
                      icon:
                          Icon(Icons.close, color: Colors.white70, size: 18.sp),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                SizedBox(height: 8.h),
                Expanded(
                  child: ListView.separated(
                    physics: const BouncingScrollPhysics(),
                    itemCount: inv.products.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: Colors.white12, height: 1),
                    itemBuilder: (_, i) =>
                        _ProductPickTile(product: inv.products[i]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openCreateCustomerDialog(BuildContext context) async {
    final loc = LocalizationService.instance;
    final inv = context.read<InventoryProvider>();
    _custName.clear();
    _custPhone.clear();
    _custAddress.clear();
    bool saving = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
        backgroundColor: ThemeConstants.primaryBlue,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
        title: Text(loc.translate('add_customer'),
            style: ThemeConstants.bodyStyle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: _custName,
                  decoration: ThemeConstants.invInputDecoration(
                      loc.translate('customer_name')),
                  style: ThemeConstants.bodyStyle),
              SizedBox(height: 8.h),
              TextField(
                  controller: _custPhone,
                  keyboardType: TextInputType.phone,
                  decoration: ThemeConstants.invInputDecoration(
                      loc.translate('phone_number')),
                  style: ThemeConstants.bodyStyle),
              SizedBox(height: 8.h),
              TextField(
                  controller: _custAddress,
                  decoration: ThemeConstants.invInputDecoration(
                      loc.translate('address')),
                  style: ThemeConstants.bodyStyle),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(loc.translate('cancel'))),
          ElevatedButton(
            // Disabled while the request runs so a double-tap can't save twice.
            onPressed: saving
                ? null
                : () async {
                    if (_custName.text.trim().isEmpty ||
                        _custPhone.text.trim().isEmpty) {
                      ThemeConstants.showWarningSnackBar(
                        context,
                        loc.isSwahili
                            ? 'Ingiza jina na namba ya simu ya mteja'
                            : 'Enter the customer name and phone number',
                      );
                      return;
                    }
                    setDialogState(() => saving = true);
                    final id = await inv.createCustomer(
                      name: _custName.text.trim(),
                      phone: _custPhone.text.trim(),
                      address: _custAddress.text.trim(),
                    );
                    if (id != null) {
                      inv.setCustomer(id);
                      if (context.mounted) Navigator.pop(ctx);
                      return;
                    }
                    setDialogState(() => saving = false);
                    if (context.mounted) {
                      ThemeConstants.showErrorSnackBar(
                        context,
                        loc.isSwahili
                            ? 'Imeshindikana kuhifadhi mteja. Jaribu tena.'
                            : 'Could not save the customer. Please try again.',
                      );
                    }
                  },
            child: saving
                ? SizedBox(
                    width: 16.sp,
                    height: 16.sp,
                    child: const CircularProgressIndicator(strokeWidth: 2))
                : Text(loc.translate('save')),
          ),
        ],
      ),
      ),
    );
  }

  /// Asks before removing the selected customer; the server refuses (and says
  /// why) when they still owe money or hold crates.
  Future<void> _confirmDeleteCustomer(
      BuildContext context, InventoryProvider inv) async {
    final loc = LocalizationService.instance;
    final int? id = inv.selectedCustomerId;
    if (id == null) return;
    final String name =
        inv.customers.where((c) => c.id == id).firstOrNull?.name ?? '';

    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: ThemeConstants.primaryBlue,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
        title: Text(loc.isSwahili ? 'Futa mteja?' : 'Delete customer?',
            style: ThemeConstants.bodyStyle
                .copyWith(fontWeight: FontWeight.bold)),
        content: Text(
          loc.isSwahili
              ? 'Futa "$name"? Historia ya mauzo yake itabaki.'
              : 'Delete "$name"? Their past sales stay in your records.',
          style: ThemeConstants.captionStyle,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: Text(loc.translate('cancel'),
                style: const TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: ThemeConstants.errorRed),
            onPressed: () => Navigator.pop(dCtx, true),
            child: Text(loc.translate('delete')),
          ),
        ],
      ),
    );
    if (yes != true || !context.mounted) return;

    final String? problem = await inv.deleteCustomer(id);
    if (!context.mounted) return;
    if (problem != null) {
      ThemeConstants.showWarningSnackBar(context, problem);
      return;
    }
    _posName.clear();
    _posPhone.clear();
    inv.setManualName('');
    ThemeConstants.showSuccessSnackBar(
        context, loc.isSwahili ? 'Mteja amefutwa' : 'Customer deleted');
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 16.sp),
          SizedBox(height: 2.h),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 10.sp, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          Text(label, style: TextStyle(color: Colors.white38, fontSize: 9.sp)),
        ],
      ),
    );
  }
}

class _AmountBadge extends StatelessWidget {
  const _AmountBadge({
    required this.label,
    required this.amount,
    required this.color,
  });

  final String label;
  final double amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 3.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6.r),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 8.sp)),
          Text('TZS ${amount.toStringAsFixed(0)}',
              style: TextStyle(
                  color: color, fontSize: 10.sp, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ProductPickTile extends StatelessWidget {
  const _ProductPickTile({required this.product});
  final InvProduct product;

  @override
  Widget build(BuildContext context) {
    final inv = context.read<InventoryProvider>();
    // The price it will be rung up at (for a depot: the product's own price, as always) and the stock
    // as a person says it ("4 crate 4 bottle", "12 kg 500 g" -- a depot keeps its plain number).
    final InvProductUnit? unit = inv.defaultUnitFor(product);
    final double price = inv.unitPriceFor(product, unit);
    final String per = unit == null || unit.isBase ? '' : ' / ${unit.name}';
    final String stock = stockLabel(product, inv.unitsOf(product.id), inv.capabilities);
    return ListTile(
      leading: Container(
        padding: EdgeInsets.all(8.w),
        decoration: BoxDecoration(
          color: ThemeConstants.invFill,
          borderRadius: BorderRadius.circular(8.r),
        ),
        child: Icon(product.isService ? Icons.content_cut_rounded : Icons.inventory_2_outlined,
            color: ThemeConstants.invAccent, size: 20.sp),
      ),
      title: Text(product.name, style: ThemeConstants.bodyStyle),
      subtitle: Text(
        // A service has no stock to show: its price and how long it takes.
        product.isService
            ? '${LocalizationService.instance.isSwahili ? 'Huduma' : 'Service'} • TZS ${price.toStringAsFixed(0)}$per${product.durationMinutes == null ? '' : ' • ${product.durationMinutes} min'}'
            : 'SKU: ${product.sku} • TZS ${price.toStringAsFixed(0)}$per • $stock in stock',
        style: ThemeConstants.captionStyle,
      ),
      trailing: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: ThemeConstants.invAccent,
          foregroundColor: Colors.black,
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8.r),
          ),
        ),
        onPressed: () async {
          final bool added = await addToCartAskingPrice(context, inv, product);
          if (added && context.mounted) ThemeConstants.showSuccessSnackBar(context, LocalizationService.instance.translate('added_to_cart'));
        },
        child: Text(LocalizationService.instance.translate('add_2'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.sp)),
      ),
    );
  }
}

class _CartRow extends StatelessWidget {
  const _CartRow({required this.item});
  final InvSaleItem item;

  @override
  Widget build(BuildContext context) {
    final inv = context.read<InventoryProvider>();
    final loc = LocalizationService.instance;
    final InvProduct? product = inv.products.where((InvProduct p) => p.id == item.productId).firstOrNull;
    final List<InvProductUnit> units = inv.activeUnitsOf(item.productId);
    // What one of this line is called: its unit, else the product's own ("bottle", "pcs"), else "unit".
    final String per = item.unitName ?? product?.unit ?? 'unit';

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.name,
                  style: ThemeConstants.bodyStyle
                      .copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                'TZS ${item.total.toStringAsFixed(0)}',
                style: TextStyle(
                  color: ThemeConstants.invAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 14.sp,
                ),
              ),
              SizedBox(width: 4.w),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => inv.removeFromCart(item),
                icon: const Icon(Icons.delete_outline,
                    color: ThemeConstants.errorRed, size: 20),
              ),
            ],
          ),
          // More than one way to sell it (a crate or a bottle, a kg or a g): pick what the customer asks for.
          if (units.length > 1) ...[
            SizedBox(height: 4.h),
            UnitChips(
              units: units,
              selectedUnitId: item.unitId,
              baseLabel: product?.unit ?? 'unit',
              onSelected: (InvProductUnit u) => inv.changeCartUnit(item, u),
            ),
          ],
          // Salon: who serves this service. The person picked for the line before is offered again, and shown here.
          if (item.isService && inv.salonMode) ...[
            SizedBox(height: 4.h),
            Align(
              alignment: Alignment.centerLeft,
              child: ActionChip(
                key: ValueKey<String>('cart_staff_${item.key}'),
                avatar: Icon(Icons.person_outline, size: 16.sp, color: Colors.white70),
                label: Text(
                  (item.staffName ?? '').isEmpty
                      ? (loc.isSwahili ? 'Mhudumu: chagua' : 'Stylist: choose')
                      : (loc.isSwahili ? 'Mhudumu: ${item.staffName}' : 'Stylist: ${item.staffName}'),
                  style: TextStyle(color: Colors.white, fontSize: 12.sp),
                ),
                backgroundColor: ThemeConstants.invFill,
                side: const BorderSide(color: ThemeConstants.invBorder),
                onPressed: () => pickStylist(context, item),
              ),
            ),
          ],
          // Salon: the goods this visit used, shown on the line and changeable.
          if (item.isService && inv.salonMode) ...[
            SizedBox(height: 4.h),
            Align(
              alignment: Alignment.centerLeft,
              child: ActionChip(
                key: ValueKey<String>('cart_goods_${item.key}'),
                avatar: Icon(Icons.inventory_2_outlined, size: 16.sp, color: Colors.white70),
                label: Text(usedGoodsSummary(item.usedGoods, sw: loc.isSwahili), style: TextStyle(color: Colors.white, fontSize: 12.sp)),
                backgroundColor: ThemeConstants.invFill,
                side: const BorderSide(color: ThemeConstants.invBorder),
                onPressed: () => pickGoodsUsed(context, inv, item),
              ),
            ),
          ],
          SizedBox(height: 6.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Quantity Controls
              DecoratedBox(
                decoration: BoxDecoration(
                  color: ThemeConstants.invFill,
                  borderRadius: BorderRadius.circular(8.r),
                  border: Border.all(color: ThemeConstants.invBorder),
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => inv.setCartQty(item, item.qty - 1),
                      icon: const Icon(Icons.remove, color: Colors.white),
                      padding: EdgeInsets.zero,
                      constraints: BoxConstraints.tightFor(
                        width: 28.w,
                        height: 28.w,
                      ),
                      iconSize: 16.sp,
                    ),
                    // Tap the number to type it: 2,500 g is not 2,500 taps. Whole numbers only.
                    InkWell(
                      key: ValueKey<String>('cart_qty_${item.key}'),
                      onTap: () async {
                        final int? typed = await askWholeNumber(
                          context,
                          title: loc.isSwahili ? 'Idadi ya $per' : 'How many $per',
                          initial: item.qty,
                          okLabel: loc.translate('save'),
                          cancelLabel: loc.translate('cancel'),
                        );
                        if (typed != null && typed > 0) inv.setCartQty(item, typed);
                      },
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 4.h),
                        child: Text(
                          '${item.qty}',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14.sp,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => inv.setCartQty(item, item.qty + 1),
                      icon: const Icon(Icons.add, color: Colors.white),
                      padding: EdgeInsets.zero,
                      constraints: BoxConstraints.tightFor(
                        width: 28.w,
                        height: 28.w,
                      ),
                      iconSize: 16.sp,
                    ),
                  ],
                ),
              ),

              // Automatic Selling Price Badge
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                decoration: BoxDecoration(
                  color: ThemeConstants.invFill,
                  borderRadius: BorderRadius.circular(8.r),
                  border: Border.all(color: ThemeConstants.invBorder),
                ),
                child: Text(
                  '@ TZS ${item.unitPrice.toStringAsFixed(item.unitPrice == item.unitPrice.roundToDouble() ? 0 : 2)} / $per',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (item.taxAmount > 0)
            Padding(
              padding: EdgeInsets.only(top: 2.h),
              child: Text(
                'VAT ${(item.taxPercent ?? 0).toStringAsFixed((item.taxPercent ?? 0) % 1 == 0 ? 0 : 1)}%  •  TZS ${item.taxAmount.toStringAsFixed(0)}',
                key: ValueKey<String>('cart_vat_${item.key}'),
                style: ThemeConstants.captionStyle.copyWith(fontSize: 10.sp),
              ),
            ),
        ],
      ),
    );
  }
}
