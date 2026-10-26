import '../../../services/api_service.dart';

/// The AI assistant: ask a question about the business. The server answers only from what the signed-in person may see.
/// Screens take one of these so a test can hand them a fake with canned answers.
class AssistantApi {
  AssistantApi({final ApiService? api}) : _api = api ?? ApiService();

  final ApiService _api;

  Map<String, dynamic> _data(final Map<String, dynamic> res) => res['data'] is Map ? Map<String, dynamic>.from(res['data'] as Map) : <String, dynamic>{};

  /// `available` (the server has an AI key), `topics`, `suggestions` (one-tap questions for this person: `id`, `en`, `sw`, `tool`),
  /// `services` and `questions_left` today.
  Future<Map<String, dynamic>> status() async => _data(await _api.get('/assistant'));

  /// [history] is the earlier turns, oldest first, each `{role: user|model, text: ...}`.
  /// Returns `answer`, `cards` (records shown as they are in the data) and `questions_left`.
  /// [topic] is the id of a one-tap suggestion: the server then reads the data first and needs just one AI call, so it is faster.
  Future<Map<String, dynamic>> ask(final String question, final String lang, final List<Map<String, String>> history, {final String? topic}) async =>
      _data(await _api.post('/assistant', <String, dynamic>{'question': question, 'lang': lang, 'history': history, if (topic != null) 'topic': topic}));
}
