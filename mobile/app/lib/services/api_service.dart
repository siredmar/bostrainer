import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/scenario.dart';
import '../models/session.dart';
import '../models/evaluation.dart';

/// Result of sending a message — may include an evaluation if session ended.
class SendMessageResult {
  final String reply;
  final Evaluation? evaluation;

  SendMessageResult({required this.reply, this.evaluation});
}

/// REST client for the bridge server.
class ApiService {
  final String baseUrl;
  final http.Client _client;

  ApiService({required this.baseUrl}) : _client = http.Client();

  /// Fetch all available scenarios.
  Future<List<Scenario>> getScenarios() async {
    final response = await _client.get(Uri.parse('$baseUrl/api/scenarios'));
    if (response.statusCode != 200) {
      throw ApiException('Failed to load scenarios: ${response.statusCode}');
    }
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((j) => Scenario.fromJson(j as Map<String, dynamic>)).toList();
  }

  /// Create a new training session.
  Future<Session> createSession(String scenarioKey) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/sessions'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'scenario_key': scenarioKey}),
    );
    if (response.statusCode != 201) {
      throw ApiException('Failed to create session: ${response.statusCode}');
    }
    return Session.fromJson(jsonDecode(response.body));
  }

  /// Send a text message and get AI reply (and optional evaluation).
  Future<SendMessageResult> sendMessage(String sessionId, String text) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/sessions/$sessionId/message'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'text': text}),
    );
    if (response.statusCode != 200) {
      throw ApiException('Failed to send message: ${response.statusCode}');
    }
    final data = jsonDecode(response.body);
    Evaluation? evaluation;
    if (data['evaluation'] != null) {
      evaluation = Evaluation.fromEvalJson(data['evaluation'] as Map<String, dynamic>);
    }
    return SendMessageResult(
      reply: data['reply'] as String,
      evaluation: evaluation,
    );
  }

  /// End a session and get evaluation.
  Future<Evaluation> endSession(String sessionId) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/sessions/$sessionId/end'),
    );
    if (response.statusCode != 200) {
      throw ApiException('Failed to end session: ${response.statusCode}');
    }
    return Evaluation.fromJson(jsonDecode(response.body));
  }

  /// Delete a session without evaluation.
  Future<void> deleteSession(String sessionId) async {
    await _client.delete(Uri.parse('$baseUrl/api/sessions/$sessionId'));
  }

  void dispose() {
    _client.close();
  }
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => 'ApiException: $message';
}
