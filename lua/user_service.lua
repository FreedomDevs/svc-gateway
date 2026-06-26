-- lua/user_service.lua
local http = require("resty.http")
local cjson = require("cjson")
local ngx_base64 = require "ngx.base64"

local _M = {}

function _M.get_user_roles(host, uuid)
  local httpc = http.new()

  -- Регулярное выражение для поиска схемы, кредов (user:pass) и самого хоста
  -- Ищет паттерн: http(s)://user:password@host...
  local m, err = ngx.re.match(host, [[^(https?://)([^:]+):([^@]+)@(.+)$]], "jo")

  local auth_header = nil

  if m then
    local scheme = m[1]
    local user = m[2]
    local pass = m[3]
    local rest_of_url = m[4]

    -- Собираем чистый URL без конфиденциальных данных для отправки
    host = scheme .. rest_of_url

    -- Формируем Base64 для Basic Auth
    local credentials = user .. ":" .. pass
    -- Используем encode_base64, если версия старая, или encode_base64url для новых
    auth_header = "Basic " .. ngx_base64.encode_base64url(credentials)
  end

  -- Формируем итоговый путь к эндпоинту
  local full_url = string.format("%s/users/%s", host, uuid)

  -- Таблица заголовков
  local req_headers = {
    ["Accept"] = "application/json",
  }

  -- Если в URL была авторизация, добавляем её в заголовки
  if auth_header then
    req_headers["Authorization"] = auth_header
  end

  local res, err = httpc:request_uri(full_url, {
    method = "GET",
    headers = req_headers,
    keepalive_timeout = 60000,
    keepalive_pool = 10,
  })

  if not res then
    return nil, "HTTP request failed: " .. (err or "unknown error")
  end

  if res.status ~= 200 then
    return nil, "Server returned status: " .. res.status
  end

  local status, response_data = pcall(cjson.decode, res.body)
  if not status then
    return nil, "Failed to parse JSON response: " .. tostring(response_data)
  end

  if not response_data.data or not response_data.data.roles then
    return nil, "Invalid API response structure: missing data.roles"
  end

  -- Собираем массив ролей в нижнем регистре
  local lower_roles = {}
  for i, role in ipairs(response_data.data.roles) do
    lower_roles[i] = string.lower(role) -- Используем чистый Lua метод string.lower
  end

  return lower_roles, nil
end

return _M
