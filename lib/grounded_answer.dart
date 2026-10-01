import 'dart:convert';
import 'retrieval_service.dart';

class Citation {
  const Citation(this.source, this.section, this.chunkId, this.quote);
  final String source, chunkId, quote;
  final String? section;
}

class GroundedAnswer {
  const GroundedAnswer(this.answer, this.citations,
      {this.isInsufficientContext = false, this.clarificationRequest});
  final String answer;
  final List<Citation> citations;
  final bool isInsufficientContext;
  final String? clarificationRequest;

  static const insufficient = GroundedAnswer(
    'Я не знаю ответа на основании доступной базы знаний.', [],
    isInsufficientContext: true,
    clarificationRequest: 'Пожалуйста, уточните вопрос или укажите компонент/проект.',
  );
}

class GroundingValidator {
  String _normalize(String text) => text.trim().replaceAll(RegExp(r'\s+'), ' ');

  GroundedAnswer parse(String raw, List<RetrievedChunk> context) {
    try {
      final data = jsonDecode(raw);
      if (data is! Map || data['answer'] is! String ||
          (data['answer'] as String).trim().isEmpty ||
          data['isInsufficientContext'] is! bool || data['citations'] is! List ||
          !data.containsKey('clarificationRequest') ||
          (data['clarificationRequest'] != null && data['clarificationRequest'] is! String)) {
        throw const FormatException('Некорректные обязательные поля JSON');
      }
      final rawCitations = data['citations'] as List;
      if (data['isInsufficientContext'] == true) {
        if (rawCitations.isNotEmpty || data['clarificationRequest'] is! String ||
            (data['clarificationRequest'] as String).trim().isEmpty) {
          throw const FormatException('Для недостаточного контекста нужны пустые citations и уточнение');
        }
        // Do not expose potentially factual text disguised as an abstention.
        return GroundedAnswer.insufficient;
      }
      if (rawCitations.isEmpty) throw const FormatException('Нет citations');
      final chunks = {for (final hit in context) hit.chunk.metadata['chunk_id']: hit.chunk.metadata};
      final citations = <Citation>[];
      final seen = <String>{};
      for (final c in rawCitations) {
        if (c is! Map || ['source', 'chunkId', 'quote'].any((key) =>
            c[key] is! String || (c[key] as String).trim().isEmpty) ||
            !c.containsKey('section') || (c['section'] != null && c['section'] is! String)) {
          throw const FormatException('Некорректные поля citation');
        }
        final chunk = chunks[c['chunkId']];
        if (chunk == null) throw FormatException('Unknown chunkId: ${c['chunkId']}');
        if (c['source'] != chunk['source']) throw const FormatException('Source mismatch');
        if (c['section'] != chunk['section']) throw const FormatException('Section mismatch');
        final quote = _normalize(c['quote'] as String);
        if (quote.isEmpty || !_normalize(chunk['text'] as String).contains(quote)) {
          throw const FormatException('Quote not present in cited chunk');
        }
        if (seen.add(jsonEncode([c['chunkId'], quote]))) {
          citations.add(Citation(c['source'], c['section'], c['chunkId'], c['quote']));
        }
      }
      return GroundedAnswer((data['answer'] as String).trim(), List.unmodifiable(citations));
    } catch (error) {
      throw FormatException('Ответ модели не прошёл проверку источников. Причина: $error');
    }
  }
}
