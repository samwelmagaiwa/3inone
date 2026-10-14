import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../constants/theme_constants.dart';
import '../../services/api_service.dart';
import '../../services/localization_service.dart';
import '../../utils/server_message.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

// ignore_for_file: control_flow_in_finally, avoid_catches_without_on_clauses, unnecessary_brace_in_string_interps
class _BackupScreenState extends State<BackupScreen> {
  final LocalizationService _localizationService = LocalizationService.instance;
  final ApiService _apiService = ApiService();

  bool _autoBackupEnabled = false;
  bool _isBackingUp = false;
  bool _isRestoring = false;
  String? _lastBackupDate;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _autoBackupEnabled = prefs.getBool('auto_backup') ?? false;
      _lastBackupDate = prefs.getString('last_backup_date');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(
        _localizationService.translate('backup'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Header
              ThemeConstants.buildGlassCard(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: ThemeConstants.primaryOrange.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.backup,
                          color: ThemeConstants.primaryOrange,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _localizationService.translate('backup'),
                              style: const TextStyle(
                                color: ThemeConstants.textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _localizationService.translate('backup_subtitle'),
                              style: const TextStyle(
                                color: ThemeConstants.textSecondary,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Backup Settings
              ThemeConstants.buildGlassCard(
                child: Column(
                  children: [
                    // Auto Backup Toggle
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 8),
                      leading: const Icon(Icons.schedule,
                          color: ThemeConstants.textSecondary),
                      title: Text(
                        _localizationService.translate('auto_backup'),
                        style: const TextStyle(
                            color: ThemeConstants.textPrimary, fontSize: 16),
                      ),
                      subtitle: Text(
                        _localizationService.isSwahili
                            ? 'Hifadhi data kiotomatiki kila siku'
                            : 'Automatically backup data daily',
                        style: const TextStyle(
                            color: ThemeConstants.textSecondary, fontSize: 13),
                      ),
                      trailing: Switch.adaptive(
                        value: _autoBackupEnabled,
                        onChanged: (value) async {
                          setState(() => _autoBackupEnabled = value);
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setBool('auto_backup', value);
                        },
                        activeColor: ThemeConstants.primaryOrange,
                      ),
                    ),

                    const Divider(color: Colors.white24, height: 1),

                    // Manual Backup
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 8),
                      leading: _isBackingUp
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: ThemeConstants.primaryOrange,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.backup,
                              color: ThemeConstants.textSecondary),
                      title: Text(
                        _localizationService.translate('backup_now'),
                        style: const TextStyle(
                            color: ThemeConstants.textPrimary, fontSize: 16),
                      ),
                      subtitle: Text(
                        _lastBackupDate != null
                            ? '${_localizationService.translate('last_backup')}: $_lastBackupDate'
                            : _localizationService.isSwahili
                                ? 'Hakuna hifadhi ya hivi karibuni'
                                : 'No recent backup',
                        style: const TextStyle(
                            color: ThemeConstants.textSecondary, fontSize: 13),
                      ),
                      trailing: const Icon(Icons.chevron_right,
                          color: ThemeConstants.textSecondary),
                      onTap: _isBackingUp ? null : _performBackup,
                    ),

                    const Divider(color: Colors.white24, height: 1),

                    // Restore Data
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 8),
                      leading: _isRestoring
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: ThemeConstants.primaryOrange,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.restore,
                              color: ThemeConstants.textSecondary),
                      title: Text(
                        _localizationService.translate('restore_data'),
                        style: const TextStyle(
                            color: ThemeConstants.textPrimary, fontSize: 16),
                      ),
                      subtitle: Text(
                        _localizationService.isSwahili
                            ? 'Rejesha data kutoka hifadhi iliyopo'
                            : 'Restore data from existing backup',
                        style: const TextStyle(
                            color: ThemeConstants.textSecondary, fontSize: 13),
                      ),
                      trailing: const Icon(Icons.chevron_right,
                          color: ThemeConstants.textSecondary),
                      onTap: _isRestoring ? null : _showRestoreDialog,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Backup Info
              ThemeConstants.buildGlassCard(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.info_outline,
                            color: ThemeConstants.primaryOrange,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _localizationService.isSwahili
                                ? 'Maelezo ya Hifadhi'
                                : 'Backup Information',
                            style: const TextStyle(
                              color: ThemeConstants.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _localizationService.isSwahili
                            ? '• Data yote ya madereva, malipo, na risiti itahifadhiwa\n'
                                '• Hifadhi zinazohifadhiwa kwenye cloud kwa usalama\n'
                                '• Unaweza kurejesha data wakati wowote\n'
                                '• Hifadhi ya kiotomatiki inafanywa kila siku saa 2:00 usiku'
                            : '• All driver, payment, and receipt data will be backed up\n'
                                '• Backups are stored securely in the cloud\n'
                                '• You can restore data at any time\n'
                                '• Auto backup runs daily at 2:00 AM',
                        style: const TextStyle(
                          color: ThemeConstants.textSecondary,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
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

  Future<void> _performBackup() async {
    setState(() => _isBackingUp = true);

    try {
      // The route is /auth/admin/backup. The app used to call /admin/backup, which does not exist.
      final response = await _apiService.post('/auth/admin/backup', <String, dynamic>{});

      if (response['success'] == true) {
        // Save backup date
        final prefs = await SharedPreferences.getInstance();
        final now = DateTime.now();
        final dateStr = '${now.day}/${now.month}/${now.year}';
        await prefs.setString('last_backup_date', dateStr);
        if (!mounted) return;
        setState(() => _lastBackupDate = dateStr);

        ThemeConstants.showSuccessSnackBar(
          context,
          _localizationService.translate('backup_successful'),
        );
      } else {
        throw Exception(response['message'] ?? LocalizationService.instance.translate('backup_failed'));
      }
    } catch (e) {
      if (!mounted) return;
      ThemeConstants.showErrorSnackBar(
        context,
        _localizationService.isSwahili
            ? 'Imeshindikana kuhifadhi: ${readableErrorMessage(e)}'
            : 'Backup failed: ${readableErrorMessage(e)}',
      );
    } finally {
      if (!mounted) return;
      setState(() => _isBackingUp = false);
    }
  }

  /// Restore: choose one of the backups stored on the server, then type RESTORE to confirm.
  /// (The app used to send a restore with no backup named, which the server could not act on.)
  Future<void> _showRestoreDialog() async {
    final bool sw = _localizationService.isSwahili;
    setState(() => _isRestoring = true);

    List<Map<String, dynamic>> backups = <Map<String, dynamic>>[];
    try {
      final res = await _apiService.get('/auth/admin/backup');
      final data = res['data'];
      if (data is Map && data['backups'] is List) {
        backups = (data['backups'] as List)
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isRestoring = false);
      ThemeConstants.showErrorSnackBar(context, sw ? 'Imeshindikana kupata orodha: ${readableErrorMessage(e)}' : 'Could not load the backups: ${readableErrorMessage(e)}');
      return;
    }

    if (!mounted) return;
    setState(() => _isRestoring = false);

    if (backups.isEmpty) {
      ThemeConstants.showErrorSnackBar(
        context,
        sw ? 'Hakuna nakala za akiba kwenye seva bado.' : 'There are no backups on the server yet.',
      );
      return;
    }

    final String? filename = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: ThemeConstants.primaryBlue,
        title: Text(
          sw ? 'Chagua nakala ya kurejesha' : 'Choose a backup to restore',
          style: const TextStyle(color: ThemeConstants.textPrimary),
        ),
        children: [
          for (final b in backups)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, b['filename'].toString()),
              child: Text(
                '${b['created_at'] ?? ''}  ·  ${_size(b['size_bytes'])}'
                '${b['kind'] == 'pre_restore' ? (sw ? '  (kabla ya urejeshaji)' : '  (before a restore)') : ''}',
                style: const TextStyle(color: ThemeConstants.textPrimary),
              ),
            ),
        ],
      ),
    );
    if (filename == null || !mounted) return;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => const TypeToConfirmDialog(word: 'RESTORE'),
    );
    if (confirmed != true || !mounted) return;

    await _performRestore(filename);
  }

  String _size(Object? bytes) {
    final int b = bytes is num ? bytes.toInt() : 0;
    if (b >= 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (b >= 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '$b B';
  }

  Future<void> _performRestore(String filename) async {
    setState(() => _isRestoring = true);

    try {
      final response = await _apiService.post('/auth/admin/restore', <String, dynamic>{
        'filename': filename,
        'confirm': 'RESTORE',
      });

      if (response['success'] == true) {
        if (!mounted) return;
        ThemeConstants.showSuccessSnackBar(
          context,
          _localizationService.translate('restore_successful'),
        );
      } else {
        throw Exception(response['message'] ?? LocalizationService.instance.translate('restore_failed'));
      }
    } catch (e) {
      if (!mounted) return;
      ThemeConstants.showErrorSnackBar(
        context,
        _localizationService.isSwahili
            ? 'Imeshindikana kurejesha: ${readableErrorMessage(e)}'
            : 'Restore failed: ${readableErrorMessage(e)}',
      );
    } finally {
      if (!mounted) return;
      setState(() => _isRestoring = false);
    }
  }
}

/// "Type RESTORE to continue": a restore overwrites data, so a tap is not enough.
/// Owns its text controller, so nothing is disposed while the dialog is still animating out.
class TypeToConfirmDialog extends StatefulWidget {
  const TypeToConfirmDialog({super.key, required this.word});

  final String word;

  @override
  State<TypeToConfirmDialog> createState() => TypeToConfirmDialogState();
}

class TypeToConfirmDialogState extends State<TypeToConfirmDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = LocalizationService.instance;
    final bool sw = loc.isSwahili;
    final bool ready = _controller.text.trim() == widget.word;

    return AlertDialog(
      backgroundColor: ThemeConstants.primaryBlue,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.warning, color: Colors.orange),
          const SizedBox(width: 8),
          Text(loc.translate('confirm'), style: const TextStyle(color: ThemeConstants.textPrimary)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            sw
                ? 'Hii inaandika data ya nakala juu ya data ya sasa (hakuna kinachofutwa). Kabla ya hapo, nakala ya data ya sasa itahifadhiwa. Andika ${widget.word} kuendelea.'
                : 'This writes the backup\'s data over the current data (nothing is deleted). A copy of the current data is saved first. Type ${widget.word} to continue.',
            style: const TextStyle(color: ThemeConstants.textSecondary),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey<String>('restore_confirm_field'),
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(color: ThemeConstants.textPrimary, letterSpacing: 2),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(loc.translate('cancel'), style: const TextStyle(color: ThemeConstants.textSecondary)),
        ),
        TextButton(
          key: const ValueKey<String>('restore_confirm_button'),
          onPressed: ready ? () => Navigator.pop(context, true) : null,
          child: Text(loc.translate('restore_data'), style: TextStyle(color: ready ? Colors.orange : Colors.white24)),
        ),
      ],
    );
  }
}
