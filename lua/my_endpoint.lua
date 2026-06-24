-- lua/my_endpoint.lua
local cjson = require("cjson")

-- 1. Достаем сырой JSON из памяти Nginx
local cache = ngx.shared.app
local config_json = cache:get("config")

-- 2. Парсим его в Lua-таблицу
local config = cjson.decode(config_json)

local auth_type = "guest"
local server_name = ""
local user_id = ""
local user_roles = ""

-- 3. Имитируем проверку прав (например, к нам пришел юзер с ролью "user")
local user_role = "user"
local required_permission = "delete"

-- Достаем права для этой роли из нашего конфига
local permissions = config.roles_permissions[user_role] or {}

-- Проверяем, есть ли нужное право
local has_permission = false
for _, perm in ipairs(permissions) do
  if perm == required_permission then
    has_permission = true
    break
  end
end

ngx.req.set_header("eauth-type", auth_type)
ngx.req.set_header("eauth-server-name", server_name)
ngx.req.set_header("eauth-user-id", user_id)
ngx.req.set_header("eauth-user-roles", user_roles)

ngx.say(config_json)
