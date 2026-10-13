import '../services/localization_service.dart';
class Communication {
  Communication({
    required this.driverId,
    required this.driverName,
    required this.messageDate,
    required this.messageContent,
    required this.mode,
    required this.createdAt,
    required this.updatedAt,
    this.id,
    this.response,
  });

  // Factory constructor from JSON
  factory Communication.fromJson(Map<String, dynamic> json) {
    return Communication(
      id: json["id"],
      driverId: json["driver_id"],
      driverName: json["driver_name"] ?? "",
      messageDate: DateTime.parse(json["message_date"]),
      messageContent: json["message_content"] ?? "",
      response: json["response"],
      mode: CommunicationMode.fromString(json["mode"] ?? "system_note"),
      createdAt: DateTime.parse(json["created_at"]),
      updatedAt: DateTime.parse(json["updated_at"]),
    );
  }
  final int? id;
  final String driverId;
  final String driverName; // Denormalized for easier display
  final DateTime messageDate;
  final String messageContent;
  final String? response;
  final CommunicationMode mode;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      "id": id,
      "driver_id": driverId,
      "driver_name": driverName,
      "message_date": messageDate.toIso8601String(),
      "message_content": messageContent,
      "response": response,
      "mode": mode.value,
      "created_at": createdAt.toIso8601String(),
      "updated_at": updatedAt.toIso8601String(),
    };
  }

  // Create copy with updated fields
  Communication copyWith({
    int? id,
    String? driverId,
    String? driverName,
    DateTime? messageDate,
    String? messageContent,
    String? response,
    CommunicationMode? mode,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Communication(
      id: id ?? this.id,
      driverId: driverId ?? this.driverId,
      driverName: driverName ?? this.driverName,
      messageDate: messageDate ?? this.messageDate,
      messageContent: messageContent ?? this.messageContent,
      response: response ?? this.response,
      mode: mode ?? this.mode,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // Formatted date string for display
  String get formattedMessageDate {
    return "${messageDate.day.toString().padLeft(2, '0')}/"
        "${messageDate.month.toString().padLeft(2, '0')}/"
        "${messageDate.year}";
  }

  // Formatted time string for display
  String get formattedMessageTime {
    return "${messageDate.hour.toString().padLeft(2, '0')}:"
        "${messageDate.minute.toString().padLeft(2, '0')}";
  }

  // Full formatted datetime for display
  String get formattedDateTime {
    return "$formattedMessageDate $formattedMessageTime";
  }

  // Check if communication has response
  bool get hasResponse {
    return response != null && response!.isNotEmpty;
  }

  // Get truncated content for table display
  String get truncatedContent {
    if (messageContent.length <= 50) return messageContent;
    return "${messageContent.substring(0, 47)}...";
  }

  // Get truncated response for table display
  String get truncatedResponse {
    if (!hasResponse) return LocalizationService.instance.translate('no_reply');
    if (response!.length <= 30) return response!;
    return "${response!.substring(0, 27)}...";
  }

  @override
  String toString() {
    return 'Communication{id: $id, driverId: $driverId, driverName: $driverName, messageDate: $messageDate, mode: ${mode.displayName}}';
  }
}

// Enum for communication modes
enum CommunicationMode {
  sms("sms", "📱"),
  call("call", "📞"),
  whatsapp("whatsapp", "💬"),
  systemNote("system_note", "📝");

  const CommunicationMode(this.value, this.icon);

  final String value;
  final String icon;

  /// The name shown for the mode, in the language chosen in the app.
  String get displayName {
    switch (this) {
      case CommunicationMode.sms:
        return "SMS";
      case CommunicationMode.call:
        return LocalizationService.instance.translate('call');
      case CommunicationMode.whatsapp:
        return "WhatsApp";
      case CommunicationMode.systemNote:
        return LocalizationService.instance.translate('system_notes');
    }
  }

  // Create from string value
  static CommunicationMode fromString(String value) {
    switch (value.toLowerCase()) {
      case "sms":
        return CommunicationMode.sms;
      case "call":
        return CommunicationMode.call;
      case "whatsapp":
        return CommunicationMode.whatsapp;
      case "system_note":
      default:
        return CommunicationMode.systemNote;
    }
  }

  // Get all modes as a list
  static List<CommunicationMode> get allModes => CommunicationMode.values;
}

// Communication summary for dashboard/overview
class CommunicationSummary {
  CommunicationSummary({
    required this.totalCommunications,
    required this.unansweredCommunications,
    required this.recentCommunications,
    required this.communicationsByMode,
    this.lastCommunicationDate,
  });

  factory CommunicationSummary.fromJson(Map<String, dynamic> json) {
    // Parse communications by mode
    final Map<CommunicationMode, int> modeMap = {};
    if (json["communications_by_mode"] != null) {
      final Map<String, dynamic> modeData = json["communications_by_mode"];
      for (final String key in modeData.keys) {
        final CommunicationMode mode = CommunicationMode.fromString(key);
        modeMap[mode] = modeData[key] ?? 0;
      }
    }

    return CommunicationSummary(
      totalCommunications: json["total_communications"] ?? 0,
      unansweredCommunications: json["unanswered_communications"] ?? 0,
      recentCommunications: json["recent_communications"] ?? 0,
      communicationsByMode: modeMap,
      lastCommunicationDate: json["last_communication_date"] != null
          ? DateTime.parse(json["last_communication_date"])
          : null,
    );
  }
  final int totalCommunications;
  final int unansweredCommunications;
  final int recentCommunications; // Last 7 days
  final Map<CommunicationMode, int> communicationsByMode;
  final DateTime? lastCommunicationDate;

  Map<String, dynamic> toJson() {
    final Map<String, int> modeMap = {};
    communicationsByMode.forEach((mode, count) {
      modeMap[mode.value] = count;
    });

    return {
      "total_communications": totalCommunications,
      "unanswered_communications": unansweredCommunications,
      "recent_communications": recentCommunications,
      "communications_by_mode": modeMap,
      "last_communication_date": lastCommunicationDate?.toIso8601String(),
    };
  }

  // Get percentage of unanswered communications
  double get unansweredPercentage {
    if (totalCommunications == 0) return 0;
    return (unansweredCommunications / totalCommunications) * 100;
  }
}
