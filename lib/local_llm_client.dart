import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class LocalLlmException implements Exception {
  const LocalLlmException(this.message);
  final String message;
  @override
  String toString() => message;
}

class LocalLlmClient {
  Future<String> chat(String baseUrl, String token,
      List<Map<String, String>> messages, {bool support = false, int? ticketId}) async {
    final base = Uri.tryParse(baseUrl.trim());
    if (base == null || base.scheme != 'https' || base.host.isEmpty ||
        base.userInfo.isNotEmpty || base.hasQuery || base.hasFragment ||
        (base.path.isNotEmpty && base.path != '/')) {
      throw const LocalLlmException('Введите HTTPS-адрес Gateway без пути.');
    }
    if (token.trim().isEmpty) {
      throw const LocalLlmException('Введите Bearer-токен.');
    }
    final client = http.Client();
    try {
      final request = http.Request('POST', base.replace(path: '/v1/chat'))
        ..followRedirects = false
        ..headers.addAll({'Content-Type': 'application/json',
          'Authorization': 'Bearer ${token.trim()}'})
        ..body = jsonEncode({'messages': messages, if (support) 'mode': 'support',
          if (support) 'ticket_id': ticketId});
      final response = await (() async {
        return http.Response.fromStream(await client.send(request));
      })().timeout(const Duration(minutes: 6));
      dynamic data;
      try {
        data = jsonDecode(utf8.decode(response.bodyBytes));
      } on FormatException {
        throw LocalLlmException('HTTP ${response.statusCode}: Gateway или туннель '
            'вернул ответ вместо JSON. Проверьте Gateway и адрес туннеля.');
      }
      if (response.statusCode != 200) {
        final error = data is Map ? data['error'] : null;
        final retry = response.headers['retry-after'];
        throw LocalLlmException('HTTP ${response.statusCode}: ${error ?? "Ошибка Gateway"}'
          '${retry == null ? "" : ". Повторите через $retry с."}');
      }
      if (data is! Map || data['message'] is! Map ||
          data['message']['content'] is! String) {
        throw const FormatException();
      }
      final answer = data['message']['content'] as String;
      return data['done_reason'] == 'length'
          ? '$answer\n\n[Достигнут лимит ответа: 512 токенов]' : answer;
    } on TimeoutException {
      throw const LocalLlmException('Истекло время ожидания. Запрос мог продолжить работу на Mac.');
    } on http.ClientException {
      throw const LocalLlmException('Нет соединения с Gateway. Проверьте адрес и туннель.');
    } on FormatException {
      throw const LocalLlmException('Gateway вернул некорректный JSON.');
    } finally {
      client.close();
    }
  }
}

extension FileAssistantClient on LocalLlmClient {
  Future<Map<String, dynamic>> files(String baseUrl, String token,
      Map<String, dynamic> data) async {
    final base = Uri.tryParse(baseUrl.trim());
    if (base == null || base.host.isEmpty || base.userInfo.isNotEmpty ||
        base.hasQuery || base.hasFragment || (base.path.isNotEmpty && base.path != '/') ||
        !(base.scheme == 'https' || (base.scheme == 'http' &&
          ['localhost', '127.0.0.1', '10.0.2.2'].contains(base.host)))) {
      throw const LocalLlmException('Введите URL Gateway; HTTP доступен только локально.');
    }
    if (token.trim().isEmpty) throw const LocalLlmException('Введите Bearer-токен.');
    final client = http.Client();
    try {
      final request = http.Request('POST', base.replace(path: '/v1/files'))
        ..followRedirects = false
        ..headers.addAll({'Content-Type': 'application/json', 'Authorization': 'Bearer ${token.trim()}'})
        ..body = jsonEncode(data);
      final response = await (() async {
        return http.Response.fromStream(await client.send(request));
      })().timeout(const Duration(seconds: 45));
      final result = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (response.statusCode != 200) throw LocalLlmException('${result['error']}');
      return result;
    } on TimeoutException {
      throw LocalLlmException('Gateway не ответил за 45 секунд: ${base.origin}. '
          'Проверьте адрес Gateway и доступность туннеля. '
          'Задание на Mac могло продолжить работу; это тайм-аут HTTP, не модели.');
    } on http.ClientException catch (error) {
      throw LocalLlmException('Нет соединения с Gateway ${base.origin}: ${error.message}. '
          'На телефоне localhost/127.0.0.1 указывает на сам телефон. '
          'Используйте HTTPS-адрес туннеля Gateway.');
    } on FormatException {
      throw const LocalLlmException('Gateway или туннель вернул ответ вместо JSON. '
          'Проверьте URL и запущенный туннель.');
    } finally {
      client.close();
    }
  }
}
