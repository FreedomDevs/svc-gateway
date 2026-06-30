-- lua/my_endpoint.lua
local cjson = require "cjson"
local jwt_parser = require "jwt_parser"
local user_service = require("user_service")
local sha256 = require "resty.sha256"
local str = require "resty.string"

local cache = ngx.shared.app
local config_json = cache:get("config")

local headers = ngx.req.get_headers()
local auth_header = headers["Authorization"]

local config = cjson.decode(config_json)

local auth_type = "guest"
local server_name = ""
local server_token = nil
local user_id = ""
local user_roles = ""
local roles = nil

if auth_header then
  if string.sub(auth_header, 1, 7) == "Bearer " then
    local token = string.sub(auth_header, 8)

    local user_token, err = jwt_parser.parse_user_token(token)

    if not user_token then
      ngx.log(ngx.WARN, "JWT Auth block failed: ", err)
      ngx.status = ngx.HTTP_UNAUTHORIZED
      ngx.say("Unauthorized: ", err)
      ngx.exit(ngx.HTTP_UNAUTHORIZED)
    end

    auth_type = "user"
    user_id = user_token.uuid

    roles, err = user_service.get_user_roles(config["svc-users-host"], user_id)
    if not roles then
      ngx.log(ngx.ERR, "Не удалось получить роли пользователя: ", err)
      ngx.status = 500
      ngx.say("Internal Server Error")
      ngx.exit(500)
    end

    user_roles = table.concat(roles, " ")
  elseif string.sub(auth_header, 1, 6) == "Basic " then
    local base64_str = string.sub(auth_header, 7)

    local digest = sha256:new()
    digest:update(base64_str)
    local binary_hash = digest:final()
    local hex_hash = str.to_hex(binary_hash)

    server_token = config.allowed_server_tokens[hex_hash]
    if not server_token then
      ngx.log(ngx.WARN, "Попытка входа с неизвестным хэшем: ", hex_hash)
      ngx.status = ngx.HTTP_FORBIDDEN
      ngx.say("Access denied: hash not found in config")
      ngx.exit(ngx.HTTP_FORBIDDEN)
    end

    local decoded, err = ngx.decode_base64(base64_str)
    if not decoded then
      ngx.log(ngx.ERR, "Failed to decode base64: ", err)
      ngx.exit(400)
    end

    local colon_pos = string.find(decoded, ":")

    auth_type = "server"
    server_name = string.sub(decoded, 1, colon_pos - 1)
  end
end

ngx.req.set_header("eauth-type", auth_type)
ngx.req.set_header("eauth-server-name", server_name)
ngx.req.set_header("eauth-user-id", user_id)
ngx.req.set_header("eauth-user-roles", user_roles)

local function match_url(pattern, url)
  -- 1. Экранируем ТОЛЬКО реальные спецсимволы регулярных выражений.
  -- Порядок внутри [%...] важен, минус ставим в самый конец, чтобы он не означал диапазон.
  local regex = pattern:gsub("([%.%+%*%?%^%$%(%)%[%]%{%}%|%\\])", "\\%1")

  -- 2. Заменяем именованные параметры :id, :name на регулярку [^/]+
  regex = regex:gsub(":[%a%d_]+", "[^/]+")

  -- 3. Заменяем *path (wildcard в конце) на .+
  regex = regex:gsub("\\%*[%a%d_]+", ".+")

  -- 4. Добавляем якоря начала (^) и конца ($) строки
  regex = "^" .. regex .. "$"

  -- 5. Проверяем совпадение через быстрый ngx.re.match с JIT
  local res, err = ngx.re.match(url, regex, "jo")

  if err then
    ngx.log(ngx.ERR, "Ошибка регулярного выражения: ", err)
    return false
  end

  return res ~= nil
end

for service_name, service in pairs(config.services) do
  for _, route in ipairs(service.routes) do
    if route.method ~= ngx.var.request_method then goto continue end
    if not match_url(route.path, ngx.var.uri) then goto continue end

    if route.required_role == false then
      ngx.var.backend = "http://" .. service_name .. "-backend"
      goto break_all
    end
    if auth_type == "guest" then
      ngx.exit(403)
    end

    local required_role = route.required_role
    if auth_type == "user" then
      for _, role in ipairs(roles) do
        if role == required_role then
          ngx.var.backend = "http://" .. service_name .. "-backend"
          goto break_all
        end
      end

      ngx.exit(403)
    end

    if auth_type == "server" then
      local groups = server_token.groups
      if type(groups) == "string" then
        groups = { groups }
      end

      for _, group in ipairs(groups) do
        local group_data = config.server_token_groups[group]

        if group_data and group_data[service_name] then
          local roles = group_data[service_name]

          for _, role in ipairs(roles) do
            if role == required_role then
              ngx.var.backend = "http://" .. service_name .. "-backend"
              goto break_all
            end
          end
        end
      end

      ngx.exit(403)
    end

    ::continue::
  end
end

ngx.exit(404)

::break_all::
