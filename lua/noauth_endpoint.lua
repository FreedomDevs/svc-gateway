local cjson = require "cjson"

local cache = ngx.shared.app
local config_json = cache:get("config")

local config = cjson.decode(config_json)

local uri = ngx.var.uri

-- Функция для проверки, начинается ли строка со специфичного префикса
local function starts_with(str, start)
    return string.sub(str, 1, string.len(start)) == start
end

-- Флаг, нашли ли мы совпадение
local matched = false

-- Итерируемся по сервисам
for service_name, service in pairs(config.services) do
    local routes = service.base_routes
    if type(routes) == "string" then
        routes = { routes }
    end

    -- Проверяем маршруты
    for _, route in ipairs(routes) do
        if starts_with(uri, route) then
            -- Записываем целевой upstream
            ngx.var.backend = "http://" .. service_name .. "-backend"
            matched = true
            break
        end
    end

    if matched then break end
end

-- Если ни один роут не подошел, отдаем 404
if not matched then
    ngx.status = ngx.HTTP_NOT_FOUND
    ngx.say("Service not found")
    ngx.exit(ngx.HTTP_NOT_FOUND)
end
