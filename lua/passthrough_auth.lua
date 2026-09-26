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

local check_cors = require "cors_check"
check_cors(config.cors_allow)

local auth_type = "guest"
local server_name = ""
local server_token = nil
local user_id = ""
local roles = {}

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

    roles, err = user_service.get_user_roles(config["svc-users-host"], user_id, ngx.var.service_name)
    if not roles then
      ngx.log(ngx.ERR, "Не удалось получить роли пользователя: ", err)
      ngx.status = 500
      ngx.say("Internal Server Error")
      ngx.exit(500)
    end
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

ngx.ctx.eauth_type = auth_type
ngx.ctx.eauth_server_name = server_name
ngx.ctx.eauth_user_id = user_id
ngx.ctx.eauth_user_roles = roles
