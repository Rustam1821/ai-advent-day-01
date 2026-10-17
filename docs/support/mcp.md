# MCP

## Подключение
Gateway подключается к MCP на Mac по http://127.0.0.1:3000/mcp. При connection refused проверьте, запущен ли `dart run server/developer_server.dart`, свободен ли порт 3000 и работает ли Gateway на том же Mac. Ошибка соединения сама по себе не доказывает причину остановки процесса. MCP нельзя проверять обычным GET как REST API: требуется initialize и tools/call.

Инструменты get_ticket и get_user читают data/tickets.json и data/users.json при каждом вызове. Они доступны только для чтения. Неизвестный id, повреждённый JSON или недоступный MCP дают ошибку; ассистент не подменяет их придуманными данными.
