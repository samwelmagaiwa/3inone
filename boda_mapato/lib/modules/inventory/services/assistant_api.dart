import '../../../services/api_service.dart';

/// The AI assistant: ask a question about the business. The server answers only from what the signed-in person may see.
/// Screens take one of these so a test can hand them a fake with canned answers.
class AssistantApi {
  AssistantApi({final ApiService? api}) : _api = api ?? ApiService();

  final ApiService _api;

  Map<String, dynamic> _data(final Map<String, dynamic> res) => res['data'] is Map ? Map<String, dynamic>.from(res['data'] as Map) : <String, dynamic>{};

  /// `available` (the server has an AI key), `topics` (what this person may ask about) and `questions_left` today.
  Future<Map<String, dynamic>> status() async => _data(await _api.get('/inventory/assistant'));

  /// [history] is the earlier turns, oldest first, each `{role: user|model, text: ...}`.
  /// Returns `answer`, `cards` (records shown as they are in the data) and `questions_left`.
  Future<Map<String, dynamic>> ask(final String question, final String lang, final List<Map<String, String>> history) async =>
      _data(await _api.post('/inventory/assistant', <String, dynamic>{'question': question, 'lang': lang, 'history': history}));
}
