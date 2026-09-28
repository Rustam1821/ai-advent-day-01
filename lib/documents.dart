import 'dart:convert';
import 'package:flutter/services.dart';

class Document {
  const Document(this.file, this.title, this.content);
  final String file, title, content;
  String get source => 'documents/$file';
}

class DocumentLoader {
  Future<List<Document>> load() async {
    final manifest = jsonDecode(await rootBundle.loadString('documents/manifest.json')) as Map;
    final files = List<String>.from(manifest['documents'] as List)..sort();
    if (files.isEmpty) throw StateError('Corpus пуст: documents/manifest.json.');
    final documents = <Document>[];
    for (final file in files) {
      try {
        final text = await rootBundle.loadString('documents/$file', cache: false);
        if (text.trim().isEmpty || text.contains('\u0000')) throw const FormatException('Пустой/некорректный текст');
        final heading = RegExp(r'^#\s+(.+)$', multiLine: true).firstMatch(text);
        documents.add(Document(file, heading?.group(1) ?? file, text));
      } catch (error) {
        throw StateError('Не удалось прочитать $file: $error');
      }
    }
    return documents;
  }
}

class Chunk {
  Chunk(Document doc, String strategy, int sequence, this.section, this.text)
      : id = '${doc.file.replaceAll('.md', '')}_${strategy}_${sequence.toString().padLeft(3, '0')}',
        source = doc.source, file = doc.file, title = doc.title, strategy = strategy;
  final String id, source, file, title, strategy, text;
  final String? section;
  Map<String, dynamic> toJson(List<double> embedding) => {
    'chunk_id': id, 'source': source, 'file': file, 'title': title,
    'strategy': strategy, 'section': section, 'text': text, 'embedding': embedding,
  };
}

abstract class Chunker {
  String get name;
  List<Chunk> split(Document doc);
}

class FixedSizeChunker implements Chunker {
  static const size = 1200, overlap = 150;
  @override
  String get name => 'fixed';
  @override
  List<Chunk> split(Document doc) {
    final chunks = <Chunk>[];
    for (var start = 0; start < doc.content.length; start += size - overlap) {
      final end = (start + size).clamp(0, doc.content.length);
      final text = doc.content.substring(start, end);
      if (text.trim().isNotEmpty) chunks.add(Chunk(doc, name, chunks.length + 1, null, text));
      if (end == doc.content.length) break;
    }
    return chunks;
  }
}

class StructureAwareChunker implements Chunker {
  static const size = 1200;
  @override
  String get name => 'structure';
  @override
  List<Chunk> split(Document doc) {
    final chunks = <Chunk>[];
    final headings = <int, String>{};
    var section = 'Preamble';
    var lines = <String>[];
    String? fence;
    void flush() {
      var packed = '';
      void emit() {
        if (packed.trim().isNotEmpty) chunks.add(Chunk(doc, name, chunks.length + 1, section, packed.trim()));
        packed = '';
      }
      // Prefer paragraph boundaries within each heading-defined section.
      for (final paragraph in lines.join('\n').split(RegExp(r'\n\s*\n'))) {
        var rest = paragraph.trim();
        if (rest.isEmpty) continue;
        if (packed.length + rest.length + 2 > size) emit();
        while (rest.length > size) {
          var boundary = rest.lastIndexOf(RegExp(r'\s'), size);
          if (boundary < size ~/ 2) boundary = size;
          packed = rest.substring(0, boundary);
          emit();
          rest = rest.substring(boundary).trimLeft();
        }
        if (rest.isNotEmpty) packed = packed.isEmpty ? rest : '$packed\n\n$rest';
      }
      emit();
      lines = [];
    }
    for (final line in const LineSplitter().convert(doc.content)) {
      final fenceMatch = RegExp(r'^\s*(`{3,}|~{3,})').firstMatch(line);
      if (fenceMatch != null) {
        final marker = fenceMatch.group(1)!;
        if (fence == null) {
          fence = marker;
        } else if (marker[0] == fence[0] && marker.length >= fence.length) {
          fence = null;
        }
      }
      final heading = fence == null ? RegExp(r'^(#{1,6})\s+(.+)$').firstMatch(line) : null;
      if (heading != null) {
        flush();
        final depth = heading.group(1)!.length;
        headings.removeWhere((level, _) => level >= depth);
        headings[depth] = heading.group(2)!.replaceFirst(RegExp(r'\s+#+\s*$'), '');
        section = headings.values.join(' > ');
      }
      lines.add(line);
    }
    flush();
    return chunks;
  }
}
