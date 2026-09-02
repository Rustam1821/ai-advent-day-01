# AI Advent Challenge — Day 3

Одна логическая задача решается через DeepSeek четырьмя prompting strategies:
Direct, Step-by-step, Self-prompting и Experts.

Self-prompting использует два последовательных API-вызова: сначала создаётся
улучшенный prompt, затем новый вызов решает задачу по этому prompt. Один запуск
эксперимента выполняет пять API-вызовов.

## Запуск

API key хранится только в локальном `.env`, который не попадает в Git:

```env
DEEPSEEK_API_KEY=ваш_ключ
```

```sh
flutter run --dart-define-from-file=.env
```
