import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../constants/theme_constants.dart';
import '../../services/localization_service.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final LocalizationService localizationService =
        LocalizationService.instance;

    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(
        localizationService.translate('help'),
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
                          Icons.help,
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
                              localizationService.translate('help'),
                              style: const TextStyle(
                                color: ThemeConstants.textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              localizationService.translate('help_subtitle'),
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

              // FAQ Section
              ThemeConstants.buildGlassCard(
                child: Column(
                  children: [
                    _buildFAQItem(
                      localizationService.isSwahili
                          ? 'Je, ninawezaje kuongeza dereva mpya?'
                          : 'How do I add a new driver?',
                      localizationService.isSwahili
                          ? 'Nenda kwenye dashibodi, chagua "Madereva" na ubofye kitufe cha "Ongeza Dereva". Jaza taarifa zote muhimu na uhifadhi.'
                          : 'Go to the dashboard, select "Drivers" and tap the "Add Driver" button. Fill in all required information and save.',
                      Icons.person_add,
                    ),
                    const Divider(color: Colors.white24, height: 1),
                    _buildFAQItem(
                      localizationService.isSwahili
                          ? 'Ninawezeaje kurekodi malipo?'
                          : 'How do I record a payment?',
                      localizationService.isSwahili
                          ? 'Nenda kwenye sehemu ya "Malipo", chagua dereva na ingiza kiasi alicho lipa. Mfumo utaongeza malipo na kumshusha deni lake.'
                          : 'Go to the "Payments" section, select a driver and enter the amount paid. The system will add the payment and reduce their debt.',
                      Icons.payment,
                    ),
                    const Divider(color: Colors.white24, height: 1),
                    _buildFAQItem(
                      localizationService.isSwahili
                          ? 'Ninawezeaje kutengeneza risiti?'
                          : 'How do I generate receipts?',
                      localizationService.isSwahili
                          ? 'Nenda kwenye "Toa Risiti", chagua malipo yanayohitaji risiti na ubofye "Tengeneza Risiti". Unaweza kutuma risiti kwa barua pepe au WhatsApp.'
                          : 'Go to "Generate Receipts", select payments that need receipts and tap "Generate Receipt". You can send receipts via email or WhatsApp.',
                      Icons.receipt,
                    ),
                    const Divider(color: Colors.white24, height: 1),
                    _buildFAQItem(
                      localizationService.isSwahili
                          ? 'Jinsi ya kubadilisha lugha ya programu?'
                          : 'How to change app language?',
                      localizationService.isSwahili
                          ? 'Nenda kwenye "Mipangilio" > "Lugha" na uchague lugha unayotaka. Programu itabadilisha lugha moja kwa moja.'
                          : 'Go to "Settings" > "Language" and select your preferred language. The app will change language immediately.',
                      Icons.language,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Contact Support
              ThemeConstants.buildGlassCard(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.contact_support,
                            color: ThemeConstants.primaryOrange,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            localizationService.isSwahili
                                ? 'Wasiliana na Msaada'
                                : 'Contact Support',
                            style: const TextStyle(
                              color: ThemeConstants.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 4),
                      leading: const Icon(Icons.email,
                          color: ThemeConstants.textSecondary),
                      title: Text(
                        localizationService.isSwahili ? 'Barua pepe' : 'Email',
                        style:
                            const TextStyle(color: ThemeConstants.textPrimary),
                      ),
                      subtitle: const Text(
                        'support@bodamapato.com',
                        style: TextStyle(color: ThemeConstants.textSecondary),
                      ),
                      trailing: const Icon(Icons.chevron_right,
                          color: ThemeConstants.textSecondary),
                      onTap: () {
                        // Open email client
                        _showContactInfo(
                            context,
                            localizationService.isSwahili
                                ? 'Fungua programu ya barua pepe kuwasiliana nasi'
                                : 'Open email app to contact us');
                      },
                    ),
                    const Divider(color: Colors.white24, height: 1),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 4),
                      leading: const Icon(Icons.phone,
                          color: ThemeConstants.textSecondary),
                      title: Text(
                        localizationService.isSwahili ? 'Simu' : 'Phone',
                        style:
                            const TextStyle(color: ThemeConstants.textPrimary),
                      ),
                      subtitle: const Text(
                        '+255 123 456 789',
                        style: TextStyle(color: ThemeConstants.textSecondary),
                      ),
                      trailing: const Icon(Icons.chevron_right,
                          color: ThemeConstants.textSecondary),
                      onTap: () {
                        // Open phone dialer
                        _showContactInfo(
                            context,
                            localizationService.isSwahili
                                ? 'Piga simu kwa msaada'
                                : 'Call for support');
                      },
                    ),
                    const Divider(color: Colors.white24, height: 1),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 4),
                      leading: const Icon(Icons.chat,
                          color: ThemeConstants.textSecondary),
                      title: const Text(
                        'WhatsApp',
                        style: TextStyle(color: ThemeConstants.textPrimary),
                      ),
                      subtitle: const Text(
                        '+255 123 456 789',
                        style: TextStyle(color: ThemeConstants.textSecondary),
                      ),
                      trailing: const Icon(Icons.chevron_right,
                          color: ThemeConstants.textSecondary),
                      onTap: () {
                        // Open WhatsApp
                        _showContactInfo(
                            context,
                            localizationService.isSwahili
                                ? 'Tumia WhatsApp kuwasiliana nasi'
                                : 'Use WhatsApp to contact us');
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // App Version
              ThemeConstants.buildGlassCard(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: ThemeConstants.primaryOrange,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              localizationService.translate('app_name'),
                              style: const TextStyle(
                                color: ThemeConstants.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${localizationService.translate('version')}: 1.0.0',
                              style: const TextStyle(
                                color: ThemeConstants.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              localizationService.translate('copyright'),
                              style: const TextStyle(
                                color: ThemeConstants.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ],
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

  Widget _buildFAQItem(String question, String answer, IconData icon) {
    return ExpansionTile(
      leading: Icon(icon, color: ThemeConstants.textSecondary),
      title: Text(
        question,
        style: const TextStyle(
          color: ThemeConstants.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
      iconColor: ThemeConstants.primaryOrange,
      collapsedIconColor: ThemeConstants.textSecondary,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(56, 0, 20, 16),
          child: Text(
            answer,
            style: const TextStyle(
              color: ThemeConstants.textSecondary,
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  void _showContactInfo(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ThemeConstants.primaryBlue,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.info, color: ThemeConstants.primaryOrange, size: 18.sp),
            SizedBox(width: 8.w),
            Expanded(
              child: AutoSizeText(LocalizationService.instance.translate('info'),
                  style: TextStyle(color: ThemeConstants.textPrimary),
                  maxLines: 1,
                  stepGranularity: 0.5),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(color: ThemeConstants.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'OK',
              style: TextStyle(color: ThemeConstants.primaryOrange),
            ),
          ),
        ],
      ),
    );
  }
}
