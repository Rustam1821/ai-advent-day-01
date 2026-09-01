# AI Advent Challenge — Day 2

Flutter-клиент отправляет один prompt в DeepSeek в двух режимах: обычном и с
контролем JSON-формата, длины и завершения ответа.

## Запуск

API key хранится только в локальном `.env`, который не попадает в Git:

```env
DEEPSEEK_API_KEY=ваш_ключ
```

Запуск приложения:

```sh
flutter run --dart-define-from-file=.env
```

Сборка Android:

```sh
flutter build apk --dart-define-from-file=.env
```
