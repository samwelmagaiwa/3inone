import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../constants/theme_constants.dart';
import '../../models/receipt.dart';
import '../../services/api_service.dart';
import '../../services/localization_service.dart';

class DriverReceiptsScreen extends StatefulWidget {
  const DriverReceiptsScreen({super.key});

  @override
  State<DriverReceiptsScreen> createState() => _DriverReceiptsScreenState();
}

class _DriverReceiptsScreenState extends State<DriverReceiptsScreen> {
  final ApiService _api = ApiService();
  bool _isLoading = true;
  String? _error;
  List<Receipt> _receipts = <Receipt>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> res = await _api.getDriverReceipts(limit: 100);
      final dynamic data = res['data'] ?? res;
      final List<dynamic> list = (data is Map && data['data'] is List)
          ? (data['data'] as List)
          : (data is Map && data['receipts'] is List)
              ? (data['receipts'] as List)
              : <dynamic>[];
      setState(() {
        _receipts = list
            .map((e) => Receipt.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
        _isLoading = false;
      });
    } on Exception catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ThemeConstants.buildScaffold(
      title: LocalizationService.instance.translate('my_receipts'),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 12),
            ElevatedButton(
                onPressed: _load,
                child:
                    Text(LocalizationService.instance.translate('try_again'))),
          ],
        ),
      );
    }
    if (_receipts.isEmpty) {
      return Center(
        child: Text(LocalizationService.instance.translate('no_receipts'),
            style: TextStyle(color: Colors.white.withOpacity(0.8))),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: ThemeConstants.primaryBlue,
      backgroundColor: Colors.white,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemBuilder: (context, i) {
          final r = _receipts[i];
          return ListTile(
            tileColor: Colors.white.withOpacity(0.06),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.white.withOpacity(0.1))),
            leading: const Icon(Icons.receipt_long, color: Colors.white),
            title: Text(r.receiptNumber,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600)),
            subtitle: Text(
                'TSH ${r.amount.toStringAsFixed(0)} • ${DateFormat('dd/MM/yyyy').format(r.generatedAt)}',
                style: TextStyle(color: Colors.white.withOpacity(0.8))),
            trailing: const Icon(Icons.chevron_right, color: Colors.white70),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => _DriverReceiptViewer(receipt: r))),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemCount: _receipts.length,
      ),
    );
  }
}

class _DriverReceiptViewer extends StatelessWidget {
  const _DriverReceiptViewer({required this.receipt});
  final Receipt receipt;

  @override
  Widget build(BuildContext context) {
    return ThemeConstants.buildScaffold(
      title: LocalizationService.instance.translate('receipt'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ThemeConstants.buildGlassCardStatic(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.receipt_long, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(receipt.receiptNumber,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold))),
                  ],
                ),
                const SizedBox(height: 12),
                _row(LocalizationService.instance.translate('amount'),
                    'TSH ${receipt.amount.toStringAsFixed(0)}'),
                _row(LocalizationService.instance.translate('driver'),
                    receipt.driverName),
                if (receipt.vehicleNumber != null &&
                    receipt.vehicleNumber!.isNotEmpty)
                  _row(LocalizationService.instance.translate('vehicle'),
                      receipt.vehicleNumber!),
                _row(LocalizationService.instance.translate('date'),
                    DateFormat('dd/MM/yyyy').format(receipt.generatedAt)),
                if (receipt.paidDates.isNotEmpty)
                  _row(LocalizationService.instance.translate('covered_days'),
                      receipt.paidDates.join(', ')),
                if (receipt.remarks?.isNotEmpty ?? false)
                  _row(LocalizationService.instance.translate('remarks'),
                      receipt.remarks!),
                _row(
                    LocalizationService.instance.translate('driver_trips'),
                    receipt.paidDates.isNotEmpty
                        ? receipt.paidDates.length.toString()
                        : ''),
                _row(LocalizationService.instance.translate('outstanding_balance'), _formatOutstanding(receipt)),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12)),
                    child: Text(receipt.statusDisplayName,
                        style: const TextStyle(color: Colors.white)),
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
                width: 150,
                child: Text(k,
                    style: TextStyle(color: Colors.white.withOpacity(0.8)))),
            Expanded(
                child: Text(v, style: const TextStyle(color: Colors.white))),
          ],
        ),
      );
  String _formatOutstanding(Receipt r) {
    // r doesn't carry outstanding fields; keep placeholder text instructive
    return LocalizationService.instance.translate('see_the_receipt_message_for_debt');
  }
}
