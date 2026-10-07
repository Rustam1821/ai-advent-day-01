class LocalLlmConfig {
  static const baseUrl = String.fromEnvironment(
    'OLLAMA_BASE_URL',
    defaultValue: 'http://localhost:11434',
  );
  static const model = String.fromEnvironment(
    'OLLAMA_MODEL',
    defaultValue: 'qwen3:4b',
  );
  static const timeout = Duration(minutes: 3);

  static Uri get endpoint {
    final base = Uri.parse(baseUrl);
    if (base.scheme != 'http' ||
        !['localhost', '127.0.0.1', '::1'].contains(base.host) ||
        base.userInfo.isNotEmpty ||
        (base.path.isNotEmpty && base.path != '/') ||
        base.hasQuery || base.hasFragment || model != 'qwen3:4b') {
      throw const FormatException(
        'Use a local loopback HTTP endpoint and the qwen3:4b model.',
      );
    }
    return base.replace(path: '/api/generate');
  }
}
