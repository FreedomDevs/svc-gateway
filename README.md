Кароче он на сервисы передаёт заголовки такие:

Если запрос без авторизации:
- eauth-type: guest

Если запрос от пользователя:
- eauth-type: user
- eauth-user-id: 9896394e-5468-4326-9fb2-407c548f01f5
- eauth-user-roles: \["user"\]

Если запрос от сервера:
- eauth-type: server
- eauth-server-name: elysium-main
