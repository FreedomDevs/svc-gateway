-- lua/my_endpoint.lua
local cjson = require "cjson"
local ffi = require("ffi")

local cache = ngx.shared.app
local config_json = cache:get("config")
local config = cjson.decode(config_json)

local check_cors = require "cors_check"
check_cors(config.cors_allow)

ffi.cdef [[
    int fileno(void *stream);
    int flock(int fd, int operation);
]]
-- Константы flock (Linux)
local LOCK_EX = 2 -- Исключительная блокировка (на запись)
local LOCK_UN = 8 -- Снятие блокировки
local function starts_with(str, start)
  return string.sub(str, 1, string.len(start)) == start
end
local function send_error(status_code, response)
  ngx.status = status_code
  ngx.header.content_type = "application/json; charset=utf-8"

  ngx.say(cjson.encode(response))
  return ngx.exit(status_code)
end

local function json_merge_patch(target, patch)
  -- Если patch не является таблицей, он полностью заменяет target
  if type(patch) ~= "table" then
    return patch
  end

  -- Если target не был таблицей (например, был nil или числом), создаем новую
  if type(target) ~= "table" then
    target = {}
  end

  for k, v in pairs(patch) do
    -- В cjson значение null выражается через cjson.null
    if v == cjson.null then
      target[k] = nil -- Удаляем ключ
    elseif type(v) == "table" then
      -- Если ключ — вложенный объект, уходим в рекурсию
      target[k] = json_merge_patch(target[k], v)
    else
      -- Для простых типов (строки, числа, boolean) просто перезаписываем
      target[k] = v
    end
  end

  return target
end

local function has_value(tab, val)
  for _, item in ipairs(tab) do
    if item == val then
      return true
    end
  end
  return false
end

local function check_errors(data)

end

if ngx.ctx.eauth_type ~= "user" then
  ngx.exit(403)
end
local roles = ngx.ctx.eauth_user_roles

local path = ngx.var.uri

if path == "/server.json" then
  local method = ngx.req.get_method()
  if method ~= "POST" and method ~= "PATCH" then
    ngx.exit(405)
  end

  local id = ngx.req.get_uri_args().id
  if id == nil then
    send_error(400, { error = { message = "Query parameter id not provided", code = "ID_NOT_PROVIDED" } })
  end

  if ! has_value(roles, id) then
    ngx.exit(403)
  end

  ngx.req.read_body()
  local body_raw = ngx.req.get_body_data()
  if not body_raw or #body_raw == 0 then
    send_error(400, { error = { message = "Empty request body", code = "INVALID_JSON" } })
  end

  local ok, json_data = pcall(cjson.decode, body_raw)
  if not ok then
    send_error(400, { error = { message = "Invalid json", code = "INVALID_JSON" } })
  end

  local file, err = io.open(ngx.var.document_root .. "/server.json", "r+")
  if not file then
    send_error(500, { error = { message = "Не удалось открыть файл", code = "INTERNAL_SERVER_ERROR" } })
  end

  local fd = ffi.C.fileno(file)
  local lock_res = ffi.C.flock(fd, LOCK_EX)
  if lock_res ~= 0 then
    file:close()
    send_error(500, { error = { message = "Не удалось заблокировать файл", code = "INTERNAL_SERVER_ERROR" } })
  end

  local content = file:read("*a")
  local data = cjson.decode(content)

  if method == "POST" then
    data[id] = json_data
  elseif method == "PATCH" then
    data[id] = json_merge_patch(data[id], json_data)
  end

  check_errors(data[id])

  local new_content = cjson.encode(data)

  file:seek("set", 0)
  file:write(new_content)
  file:flush()
  file:setvbuf("no")

  -- 6. РАЗБЛОКИРУЕМ И ЗАКРЫВАЕМ
  ffi.C.flock(fd, LOCK_UN)
  file:close()

  if not success then
    return nil, "Ошибка в обработчике данных: " .. tostring(new_content)
  end

  send_error(200, { meta = { code = "UPDATED_OK" } })
end
