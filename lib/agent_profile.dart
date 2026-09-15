import 'json_file_storage.dart';

/// User-authored interaction settings, separate from learned facts and history.
class AgentProfile {
  const AgentProfile({
    required this.id,
    required this.name,
    required this.userName,
    required this.style,
    required this.format,
    required this.constraints,
  });

  final String id, name, userName, style, format, constraints;

  String get instructions =>
      'ACTIVE AGENT PROFILE — настройки взаимодействия пользователя. '
      'Применяй к каждому ответу. Стиль старых ответов не задаёт текущий стиль. '
      'При конфликте настроек стиля используй этот активный профиль.\n'
      'Обращение к пользователю: $userName\n'
      'Стиль: $style\nФормат: $format\nОграничения: $constraints';

  Map<String, String> toJson() => {
    'id': id, 'name': name, 'userName': userName,
    'style': style, 'format': format, 'constraints': constraints,
  };

  factory AgentProfile.fromJson(dynamic value) {
    final data = Map<String, dynamic>.from(value as Map);
    for (final key in ['id', 'name', 'userName', 'style', 'format', 'constraints']) {
      if (data[key] is! String || (data[key] as String).trim().isEmpty) {
        throw const FormatException('Invalid profile');
      }
    }
    return AgentProfile(
      id: data['id'], name: data['name'], userName: data['userName'],
      style: data['style'], format: data['format'], constraints: data['constraints'],
    );
  }
}

class AgentProfiles {
  AgentProfiles(this.storage);
  final JsonFileStorage storage;
  List<AgentProfile> _profiles = const [
    AgentProfile(
      id: 'concise', name: 'Concise', userName: 'Rustam',
      style: 'Кратко и прямо, минимум объяснений.',
      format: 'Только маркированный список. Обращение включи в первый пункт.',
      constraints: 'Максимум 3 пункта, максимум 15 слов в каждом. Без подпунктов и примеров.',
    ),
    AgentProfile(
      id: 'teacher', name: 'Teacher', userName: 'Rustam',
      style: 'Объясняй подробно и простыми словами, раскрывай причины.',
      format: 'Начни с обращения. Далее разделы: Что это, Зачем нужно, Пример, Итог.',
      constraints: 'Обязательно один конкретный бытовой пример. От 180 до 250 слов.',
    ),
  ];
  String _activeId = 'concise';
  String? warning;
  Future<void>? _initialization;
  List<AgentProfile> get profiles => List.unmodifiable(_profiles);
  AgentProfile get active => _profiles.firstWhere((p) => p.id == _activeId);

  Future<void> initialize() => _initialization ??= _load();

  Future<void> _load() async {
    try {
      final data = await storage.read();
      if (data == null) {
        await _persist(_profiles, _activeId);
        return;
      }
      final loaded = (data['profiles'] as List)
          .map(AgentProfile.fromJson).toList();
      final id = data['activeId'] as String;
      if (loaded.length < 2 ||
          loaded.map((p) => p.id).toSet().length != loaded.length ||
          !loaded.any((p) => p.id == id)) {
        throw const FormatException('Invalid profiles');
      }
      _profiles = loaded;
      _activeId = id;
    } catch (_) {
      warning = 'Профили не загружены/не сохранены. Используются стандартные настройки.';
    }
  }

  Future<void> _persist(List<AgentProfile> profiles, String id) => storage.write({
    'profiles': profiles.map((p) => p.toJson()).toList(),
    'activeId': id,
  });

  Future<String?> select(String id) async {
    await initialize();
    if (!_profiles.any((p) => p.id == id)) return 'Профиль не найден.';
    return _commit(_profiles, id);
  }

  Future<String?> update(AgentProfile profile) async {
    await initialize();
    return _commit([
      for (final current in _profiles)
        if (current.id == profile.id) profile else current,
    ], _activeId);
  }

  Future<String?> _commit(List<AgentProfile> profiles, String id) async {
    try {
      await _persist(profiles, id);
      _profiles = profiles;
      _activeId = id;
      warning = null;
      return null;
    } catch (_) {
      return 'Не удалось сохранить профили. Изменения не применены.';
    }
  }
}
