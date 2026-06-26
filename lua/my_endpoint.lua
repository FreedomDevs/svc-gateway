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

local function ensure_array(val)
  if val == nil then return {} end
  return type(val) == "table" and val or { val }
end

local auth_type = "guest"
local server_name = ""
local user_id = ""
local user_roles = ""

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

    local roles, err = user_service.get_user_roles(config["svc-users-host"], user_id)
    if not roles then
      ngx.log(ngx.ERR, "Не удалось получить роли пользователя: ", err)
      ngx.status = 500
      ngx.say("Internal Server Error")
      ngx.exit(500)
    end

    user_roles = cjson.encode(roles)
  elseif string.sub(auth_header, 1, 6) == "Basic " then
    local base64_str = string.sub(auth_header, 7)

    local digest = sha256:new()
    digest:update(base64_str)
    local binary_hash = digest:final()
    local hex_hash = str.to_hex(binary_hash)

    local token_info = config.allowed_server_tokens[hex_hash]
    if not token_info then
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

-- Всё, пока мне лень писать дальше
ngx.say("Test")
ngx.exit(200)
