import '../services/localization_service.dart';
class ValidationUtils {
  // Email validation
  static bool isValidEmail(final String email) {
    if (email.isEmpty) return false;

    final RegExp emailRegex = RegExp(
      r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$",
    );
    return emailRegex.hasMatch(email);
  }

  // Phone number validation (Tanzanian format)
  static bool isValidPhoneNumber(final String phone) {
    if (phone.isEmpty) return false;

    // Remove spaces and special characters
    final String cleanPhone = phone.replaceAll(RegExp(r"[\s\-\(\)]"), "");

    // Tanzanian phone number patterns
    final RegExp phoneRegex = RegExp(
      r"^(\+255|0)(6[0-9]|7[0-9])[0-9]{7}$",
    );
    return phoneRegex.hasMatch(cleanPhone);
  }

  // Password validation
  static bool isValidPassword(final String password) {
    if (password.isEmpty) return false;

    // At least 8 characters, contains uppercase, lowercase, and number
    final RegExp passwordRegex = RegExp(
      r"^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)[a-zA-Z\d@$!%*?&]{8,}$",
    );
    return passwordRegex.hasMatch(password);
  }

  // Simple password validation (less strict)
  static bool isValidSimplePassword(final String password) =>
      password.length >= 6;

  // Amount validation
  static bool isValidAmount(final String amount) {
    if (amount.isEmpty) return false;

    final RegExp amountRegex = RegExp(r"^\d+(\.\d{1,2})?$");
    return amountRegex.hasMatch(amount) && double.parse(amount) > 0;
  }

  // Plate number validation (Tanzanian format)
  static bool isValidPlateNumber(final String plateNumber) {
    if (plateNumber.isEmpty) return false;

    // Tanzanian plate number format: T123ABC or similar
    final RegExp plateRegex = RegExp(
      r"^[A-Z]{1,2}\s?\d{3}\s?[A-Z]{3}$",
      caseSensitive: false,
    );
    return plateRegex.hasMatch(plateNumber.toUpperCase());
  }

  // Name validation
  static bool isValidName(final String name) {
    if (name.isEmpty) return false;

    // At least 2 characters, only letters and spaces
    final RegExp nameRegex = RegExp(r"^[a-zA-Z\s]{2,}$");
    return nameRegex.hasMatch(name.trim());
  }

  // License number validation
  static bool isValidLicenseNumber(final String licenseNumber) {
    if (licenseNumber.isEmpty) return false;

    // Basic format: letters and numbers, at least 5 characters
    final RegExp licenseRegex = RegExp(r"^[A-Z0-9]{5,}$", caseSensitive: false);
    return licenseRegex.hasMatch(licenseNumber);
  }

  // Receipt number validation
  static bool isValidReceiptNumber(final String receiptNumber) {
    if (receiptNumber.isEmpty) return false;

    // Format: R followed by numbers
    final RegExp receiptRegex = RegExp(r"^R\d+$", caseSensitive: false);
    return receiptRegex.hasMatch(receiptNumber);
  }

  // Date validation
  static bool isValidDate(final String date) {
    if (date.isEmpty) return false;

    try {
      final List<String> parts = date.split("/");
      if (parts.length != 3) return false;

      final int day = int.parse(parts[0]);
      final int month = int.parse(parts[1]);
      final int year = int.parse(parts[2]);

      if (day < 1 || day > 31) return false;
      if (month < 1 || month > 12) return false;
      if (year < 1900 || year > DateTime.now().year + 10) return false;

      // Try to create a valid date
      DateTime(year, month, day);
      return true;
    } on Exception {
      return false;
    }
  }

  // Time validation (HH:MM format)
  static bool isValidTime(final String time) {
    if (time.isEmpty) return false;

    final RegExp timeRegex = RegExp(r"^([01]?[0-9]|2[0-3]):[0-5][0-9]$");
    return timeRegex.hasMatch(time);
  }

  // URL validation
  static bool isValidUrl(final String url) {
    if (url.isEmpty) return false;

    try {
      final Uri uri = Uri.parse(url);
      return uri.hasScheme && (uri.scheme == "http" || uri.scheme == "https");
    } on Exception {
      return false;
    }
  }

  // Numeric validation
  static bool isNumeric(final String value) {
    if (value.isEmpty) return false;
    return double.tryParse(value) != null;
  }

  // Integer validation
  static bool isInteger(final String value) {
    if (value.isEmpty) return false;
    return int.tryParse(value) != null;
  }

  // Positive number validation
  static bool isPositiveNumber(final String value) {
    if (!isNumeric(value)) return false;
    return double.parse(value) > 0;
  }

  // Range validation for numbers
  static bool isInRange(
    final String value,
    final double min,
    final double max,
  ) {
    if (!isNumeric(value)) return false;
    final double number = double.parse(value);
    return number >= min && number <= max;
  }

  // Length validation
  static bool hasValidLength(
    final String value,
    final int minLength, [
    final int? maxLength,
  ]) {
    if (value.length < minLength) return false;
    if (maxLength != null && value.length > maxLength) return false;
    return true;
  }

  // Contains only letters
  static bool isAlphabetic(final String value) {
    if (value.isEmpty) return false;
    final RegExp alphabeticRegex = RegExp(r"^[a-zA-Z]+$");
    return alphabeticRegex.hasMatch(value);
  }

  // Contains only letters and spaces
  static bool isAlphabeticWithSpaces(final String value) {
    if (value.isEmpty) return false;
    final RegExp alphabeticRegex = RegExp(r"^[a-zA-Z\s]+$");
    return alphabeticRegex.hasMatch(value);
  }

  // Contains only alphanumeric characters
  static bool isAlphanumeric(final String value) {
    if (value.isEmpty) return false;
    final RegExp alphanumericRegex = RegExp(r"^[a-zA-Z0-9]+$");
    return alphanumericRegex.hasMatch(value);
  }

  // Custom validation with regex
  static bool matchesPattern(final String value, final String pattern) {
    if (value.isEmpty) return false;
    final RegExp regex = RegExp(pattern);
    return regex.hasMatch(value);
  }

  // Validation error messages
  static String? getEmailError(final String email) {
    if (email.isEmpty) return LocalizationService.instance.translate('email_is_required_2');
    if (!isValidEmail(email)) return LocalizationService.instance.translate('email_is_not_valid');
    return null;
  }

  static String? getPhoneError(final String phone) {
    if (phone.isEmpty) return LocalizationService.instance.translate('phone_number_is_required_2');
    if (!isValidPhoneNumber(phone)) return LocalizationService.instance.translate('phone_number_is_not_valid_2');
    return null;
  }

  static String? getPasswordError(final String password) {
    if (password.isEmpty) return LocalizationService.instance.translate('password_is_required');
    if (!isValidSimplePassword(password)) {
      return LocalizationService.instance.translate('password_must_have_at_least_6');
    }
    return null;
  }

  static String? getStrongPasswordError(final String password) {
    if (password.isEmpty) return LocalizationService.instance.translate('password_is_required');
    if (!isValidPassword(password)) {
      return LocalizationService.instance.translate('password_must_have_at_least_8');
    }
    return null;
  }

  static String? getAmountError(final String amount) {
    if (amount.isEmpty) return LocalizationService.instance.translate('amount_is_required');
    if (!isValidAmount(amount)) return LocalizationService.instance.translate('invalid_amount');
    return null;
  }

  static String? getNameError(final String name) {
    if (name.isEmpty) return LocalizationService.instance.translate('name_is_required_2');
    if (!isValidName(name)) return LocalizationService.instance.translate('name_is_not_valid');
    return null;
  }

  static String? getPlateNumberError(final String plateNumber) {
    if (plateNumber.isEmpty) return LocalizationService.instance.translate('plate_number_is_required');
    if (!isValidPlateNumber(plateNumber)) return LocalizationService.instance.translate('plate_number_is_not_valid');
    return null;
  }

  static String? getRequiredFieldError(
    final String value,
    final String fieldName,
  ) {
    if (value.trim().isEmpty) return "$fieldName inahitajika";
    return null;
  }

  static String? getLengthError(
    final String value,
    final String fieldName,
    final int minLength, [
    final int? maxLength,
  ]) {
    if (value.length < minLength) {
      return LocalizationService.instance.translateWith('must_have_at_least_characters', <Object?>[fieldName, minLength]);
    }
    if (maxLength != null && value.length > maxLength) {
      return LocalizationService.instance.translateWith('cannot_have_more_than_characters', <Object?>[fieldName, maxLength]);
    }
    return null;
  }

  // Confirm password validation
  static String? getConfirmPasswordError(
    final String password,
    final String confirmPassword,
  ) {
    if (confirmPassword.isEmpty) return LocalizationService.instance.translate('confirm_the_password');
    if (password != confirmPassword) return LocalizationService.instance.translate('passwords_do_not_match_2');
    return null;
  }

  // Date range validation
  static String? getDateRangeError(
    final DateTime? startDate,
    final DateTime? endDate,
  ) {
    if (startDate == null) return LocalizationService.instance.translate('start_date_is_required');
    if (endDate == null) return LocalizationService.instance.translate('end_date_is_required');
    if (startDate.isAfter(endDate)) {
      return LocalizationService.instance.translate('the_start_date_cannot_be_after');
    }
    return null;
  }

  // Future date validation
  static String? getFutureDateError(final DateTime? date) {
    if (date == null) return LocalizationService.instance.translate('date_is_required');
    if (date.isBefore(DateTime.now())) return LocalizationService.instance.translate('the_date_must_be_in_the');
    return null;
  }

  // Past date validation
  static String? getPastDateError(final DateTime? date) {
    if (date == null) return LocalizationService.instance.translate('date_is_required');
    if (date.isAfter(DateTime.now())) return LocalizationService.instance.translate('the_date_must_be_in_the_2');
    return null;
  }
}
