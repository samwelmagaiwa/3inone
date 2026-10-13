import '../services/localization_service.dart';

/// Texts used by several screens. Each one is read when it is shown, so it follows the language chosen in the app.
class AppStrings {
  // App info
  static const String appName = "3 iN One";
  static const String appVersion = "1.0";

  // General
  static String get loading => "${LocalizationService.instance.translate('loading_2')}...";
  static String get error => LocalizationService.instance.translate('error');
  static String get success => LocalizationService.instance.translate('success');
  static String get cancel => LocalizationService.instance.translate('cancel_2');
  static String get save => LocalizationService.instance.translate('save');
  static String get delete => LocalizationService.instance.translate('delete');
  static String get edit => LocalizationService.instance.translate('edit');
  static String get add => LocalizationService.instance.translate('add');
  static String get search => LocalizationService.instance.translate('search');
  static String get filter => LocalizationService.instance.translate('filter');
  static String get refresh => LocalizationService.instance.translate('refresh');

  // Dashboard
  static String get dashboard => LocalizationService.instance.translate('dashboard');
  static String get totalRevenue => LocalizationService.instance.translate('total_revenue');
  static String get todayRevenue => LocalizationService.instance.translate('today_s_income');
  static String get weeklyRevenue => LocalizationService.instance.translate('weekly_revenue');
  static String get monthlyRevenue => LocalizationService.instance.translate('monthly_revenue');
  static String get recentTransactions => LocalizationService.instance.translate('recent_transactions');

  // Device Selection
  static String get selectDevice => LocalizationService.instance.translate('select_vehicle');
  static String get bajaji => LocalizationService.instance.translate('vehicle_type_bajaji');
  static String get pikipiki => LocalizationService.instance.translate('vehicle_type_pikipiki');
  static String get gari => LocalizationService.instance.translate('vehicle_type_gari');
  static String get deviceType => LocalizationService.instance.translate('vehicle_type');

  // Transactions
  static String get transactions => LocalizationService.instance.translate('transactions');
  static String get newTransaction => LocalizationService.instance.translate('new_transaction');
  static String get transactionDetails => LocalizationService.instance.translate('transaction_details');
  static String get amount => LocalizationService.instance.translate('amount');
  static String get date => LocalizationService.instance.translate('date');
  static String get time => LocalizationService.instance.translate('time_2');
  static String get description => LocalizationService.instance.translate('description');
  static String get category => LocalizationService.instance.translate('category');
  static String get income => LocalizationService.instance.translate('income');
  static String get expense => LocalizationService.instance.translate('expenses');
  static String get pending => LocalizationService.instance.translate('pending_2');
  static String get completed => LocalizationService.instance.translate('status_completed');

  // Receipts
  static String get receipts => LocalizationService.instance.translate('receipt');
  static String get generateReceipt => LocalizationService.instance.translate('generate_receipt');
  static String get printReceipt => LocalizationService.instance.translate('print_receipt');
  static String get receiptNumber => LocalizationService.instance.translate('receipt_number_2');
  static String get customerName => LocalizationService.instance.translate('customer_name');
  static String get serviceType => LocalizationService.instance.translate('service_type');

  // Reminders
  static String get reminders => LocalizationService.instance.translate('reminders_2');
  static String get newReminder => LocalizationService.instance.translate('new_reminder');
  static String get reminderTitle => LocalizationService.instance.translate('reminder_title_2');
  static String get reminderMessage => LocalizationService.instance.translate('reminder_message_2');
  static String get reminderTime => LocalizationService.instance.translate('reminder_time_2');
  static String get activeReminders => LocalizationService.instance.translate('current_reminders');

  // Reports
  static String get reports => LocalizationService.instance.translate('reports');
  static String get dailyReport => LocalizationService.instance.translate('daily_report_2');
  static String get weeklyReport => LocalizationService.instance.translate('weekly_report_2');
  static String get monthlyReport => LocalizationService.instance.translate('monthly_report_2');
  static String get generateReport => LocalizationService.instance.translate('generate_report');
  static String get exportReport => LocalizationService.instance.translate('export_report');

  // Validation messages
  static String get fieldRequired => LocalizationService.instance.translate('field_required');
  static String get invalidAmount => LocalizationService.instance.translate('invalid_amount');
  static String get invalidDate => LocalizationService.instance.translate('date_is_not_valid');
  static String get invalidEmail => LocalizationService.instance.translate('email_is_not_valid');
  static String get invalidPhone => LocalizationService.instance.translate('phone_number_is_not_valid_2');

  // Error messages
  static String get networkError => LocalizationService.instance.translate('network_error');
  static String get serverError => LocalizationService.instance.translate('server_error');
  static String get unknownError => LocalizationService.instance.translate('unknown_error');
  static String get noDataFound => LocalizationService.instance.translate('no_data_found');

  // Success messages
  static String get transactionSaved => LocalizationService.instance.translate('transaction_saved');
  static String get reminderSet => LocalizationService.instance.translate('reminder_set');
  static String get receiptGenerated => LocalizationService.instance.translate('receipt_created');
  static String get reportGenerated => LocalizationService.instance.translate('report_created_2');
}
