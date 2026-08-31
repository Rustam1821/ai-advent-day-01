# AI Advent Challenge — Day 1

Минимальный Flutter-клиент для отправки prompt в DeepSeek и отображения ответа.

## Запуск

Передайте API key при запуске через compile-time переменную (ключ не хранится в
репозитории):

```sh
flutter run --dart-define=DEEPSEEK_API_KEY=ваш_ключ
```

Для сборки используйте тот же параметр, например:

```sh
flutter build apk --dart-define=DEEPSEEK_API_KEY=ваш_ключ
```

Не добавляйте настоящий ключ в скрипты или конфигурационные файлы проекта.

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
