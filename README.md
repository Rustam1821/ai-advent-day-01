# AI Advent Challenge — Day 4

Один prompt трижды отправляется в DeepSeek с `temperature` 0, 0.7 и 1.2.
Модель, system prompt и остальные API-параметры во всех запросах одинаковы.

## Запуск

API key хранится только в локальном `.env`, который не попадает в Git:

```env
DEEPSEEK_API_KEY=ваш_ключ
```

В VS Code достаточно запустить конфигурацию `ai_advent_day_01` через Run/F5.
Запуск из терминала:

```sh
flutter run --dart-define-from-file=.env
```
