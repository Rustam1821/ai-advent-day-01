# MCP и текущая Git-ветка

`server/developer_server.dart` использует mcp_dart 2.4.2 из Day 20.
StreamableMcpServer слушает `127.0.0.1:3000/mcp` с JSON-ответами.
Day 31: `get_current_branch`, без аргументов и без записи файлов.
Day 32: `get_pr_changes` получает base/head SHA и возвращает PR snapshot;
подробности и ограничения — [Code Review](../README.md#day-32--automated-code-review).

На каждом вызове инструмент выполняет `git -C <корень проекта> symbolic-ref
--quiet --short HEAD` через Process.run, без shell. Корень определяется по
расположению скрипта. Имя не хранится в настройках и не кешируется.
Возвращается structuredContent с branch и detached. Detached HEAD означает,
что текущей ветки нет; ошибка Git возвращает MCP isError.

Python Gateway выполняет MCP lifecycle: initialize, notifications/initialized,
tools/list с пагинацией, затем tools/call. Проверяются наличие инструмента,
ошибки протокола и структура результата. Сессия закрывается DELETE.
Сервер не нужно публиковать через туннель: к нему обращается только Gateway.

Результат MCP передаётся локальной qwen3:4b. Ответ должен цитировать MCP;
Gateway дополнительно выводит фактическое значение branch отдельной строкой.
Источник: `mcp://developer/get_current_branch`. Если MCP недоступен,
Gateway возвращает ошибку, документация не используется как замена живой ветки.
