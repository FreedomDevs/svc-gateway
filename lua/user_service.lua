-- lua/user_service.lua
local http = require("resty.http")
local cjson = require("cjson")

local _M = {}

function _M.get_user_roles(host, uuid)
  local httpc = http.new()
  local url = string.format("%s/users/%s", host, uuid)

  local res, err = httpc:request_uri(url, {
    method = "GET",
    headers = {
      ["Accept"] = "application/json",
    },
    keepalive_timeout = 60000,
    keepalive_pool = 10
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
