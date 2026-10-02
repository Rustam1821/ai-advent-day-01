import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'grounded_answer.dart';
import 'retrieval_service.dart';

class TaskState {
  const TaskState({this.goal = '', this.clarifications = const [],
    this.constraints = const [], this.terms = const []});
  final String goal;
  final List<String> clarifications, constraints, terms;
  Map<String, dynamic> toJson() => {'goal': goal, 'clarifications': clarifications,
    'constraints': constraints, 'terms': terms};
  // Normalize equivalent LLM representations; persisted state stays strict.
  factory TaskState.fromModel(dynamic value) {
    if (value is! Map) throw const FormatException('taskState must be an object');
    final normalized = Map<String, dynamic>.from(value);
    String pair(dynamic key, dynamic text) {
      if (key is! String || key.trim().isEmpty || text is! String || text.trim().isEmpty) {
        throw const FormatException('Task State entries must contain non-empty strings');
      }
      return '${key.trim()} = ${text.trim()}';
    }
    for (final field in ['clarifications', 'constraints', 'terms']) {
      final raw = value[field];
      final items = <String>[];
      if (raw is Map) {
        for (final entry in raw.entries) {
          items.add(pair(entry.key, entry.value));
        }
      } else if (raw is List) {
        for (final item in raw) {
          if (item is String) {
            if (item.trim().isNotEmpty) items.add(item.trim());
          } else if (item is Map && item.length == 2 &&
              item.containsKey('term') && item.containsKey('definition')) {
            items.add(pair(item['term'], item['definition']));
          } else if (item is Map && item.length == 2 &&
              item.containsKey('key') && item.containsKey('value')) {
            items.add(pair(item['key'], item['value']));
          } else {
            throw FormatException('Task State $field: expected strings or key/value entries, got ${item.runtimeType}');
          }
        }
      } else {
        throw FormatException('Task State $field: expected array of strings, got ${raw.runtimeType}');
      }
      normalized[field] = items.toSet().toList();
    }
    return TaskState.fromJson(normalized);
  }
  factory TaskState.fromJson(dynamic value) {
    if (value is! Map || value['goal'] is! String || (value['goal'] as String).length > 500) {
      throw const FormatException('Invalid Task State goal');
    }
    List<String> items(String key) {
      final list = value[key];
      if (list is! List) throw FormatException('Task State $key: expected array');
      if (list.length > 8) throw FormatException('Task State $key: ${list.length} items, maximum 8');
      for (var i = 0; i < list.length; i++) {
        final item = list[i];
        if (item is! String || item.trim().isEmpty) {
          throw FormatException('Task State $key[$i]: expected non-empty string');
        }
        if (item.length > 250) {
          throw FormatException('Task State $key[$i]: ${item.length} chars, maximum 250');
        }
      }
      return List<String>.unmodifiable(list);
    }
    return TaskState(goal: value['goal'], clarifications: items('clarifications'),
      constraints: items('constraints'), terms: items('terms'));
  }
}

Map<String, dynamic> answerJson(GroundedAnswer answer) => {
  'answer': answer.answer, 'isInsufficientContext': answer.isInsufficientContext,
  'clarificationRequest': answer.clarificationRequest,
  'citations': [for (final c in answer.citations) {
    'source': c.source, 'section': c.section, 'chunkId': c.chunkId, 'quote': c.quote,
  }],
};

class ChatMessage {
  ChatMessage({required this.role, required this.content, this.answer,
    this.evidence = const [], this.candidates = const [], this.query, this.error = false, this.finalLlmRequested = false,
    String? id, DateTime? timestamp})
    : timestamp = timestamp ?? DateTime.now(),
      id = id ?? DateTime.now().microsecondsSinceEpoch.toString();
  final String id, role, content;
  final DateTime timestamp;
  final GroundedAnswer? answer;
  // Saved source snapshots allow old citations to survive index rebuilds.
  final List<RetrievedChunk> evidence, candidates;
  final String? query;
  final bool error, finalLlmRequested;
  Map<String, dynamic> toJson() => {
    'id': id, 'role': role, 'content': content, 'timestamp': timestamp.toIso8601String(),
    'answer': answer == null ? null : answerJson(answer!), 'query': query,
    'error': error, 'finalLlmRequested': finalLlmRequested,
    'candidates': [for (final hit in candidates) {'metadata': hit.chunk.metadata, 'score': hit.score}],
    'evidence': [for (final hit in evidence) {'metadata': hit.chunk.metadata, 'score': hit.score}],
  };
  factory ChatMessage.fromJson(dynamic value) {
    final m = Map<String, dynamic>.from(value as Map);
    if (!['user','assistant'].contains(m['role']) || m['content'] is! String ||
        m['id'] is! String || m['error'] is! bool || m['finalLlmRequested'] is! bool) {
      throw const FormatException('Invalid chat message');
    }
    final evidence = (m['evidence'] as List).map((e) => RetrievedChunk(
      IndexedChunk(Map<String, dynamic>.from(e['metadata'] as Map), []),
      (e['score'] as num).toDouble())).toList();
    final candidates = ((m['candidates'] ?? []) as List).map((e) => RetrievedChunk(
      IndexedChunk(Map<String, dynamic>.from(e['metadata'] as Map), []),
      (e['score'] as num).toDouble())).toList();
    final answer = m['answer'] == null ? null : GroundingValidator().parse(jsonEncode(m['answer']), evidence);
    if (m['role'] == 'assistant' && m['error'] == false && answer == null) {
      throw const FormatException('Assistant answer missing');
    }
    return ChatMessage(id: m['id'], role: m['role'], content: answer?.answer ?? m['content'],
      timestamp: DateTime.parse(m['timestamp']), answer: answer, evidence: evidence, candidates: candidates,
      query: m['query'] as String?, error: m['error'], finalLlmRequested: m['finalLlmRequested']);
  }
}

class ChatSession {
  TaskState state = const TaskState();
  final List<ChatMessage> messages = [];
  static const recentLimit = 6;
  List<Map<String, String>> recent() {
    final usable = messages.where((m) => !m.error).toList();
    return usable.skip(usable.length > recentLimit ? usable.length - recentLimit : 0)
      .map((m) => {'role': m.role, 'content': m.content.length > 2000 ? m.content.substring(0, 2000) : m.content}).toList();
  }
}

class ChatStore {
  Future<File> _file() async => File('${(await getApplicationDocumentsDirectory()).path}/chat_session.json');
  Future<ChatSession> load() async {
    final file = await _file();
    if (!await file.exists()) return ChatSession();
    final data = jsonDecode(await file.readAsString()) as Map;
    if (data['version'] != 1) throw const FormatException('Unsupported chat version');
    final session = ChatSession()..state = TaskState.fromJson(data['taskState']);
    session.messages.addAll((data['messages'] as List).map(ChatMessage.fromJson));
    return session;
  }
  Future<void> save(ChatSession session) async {
    final file = await _file();
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode({'version': 1, 'taskState': session.state.toJson(),
      'messages': session.messages.map((m) => m.toJson()).toList()}), flush: true);
    await temp.rename(file.path);
  }
}
