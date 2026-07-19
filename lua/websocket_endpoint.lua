local user_service = require("user_service")
local jwt_parser = require "jwt_parser"
local cjson = require "cjson"
local sha256 = require "resty.sha256"
--[[
local headers = ngx.req.get_headers()
local auth_header = headers["Authorization"]


local cache = ngx.shared.app
local config_json = cache:get("config")
local config = cjson.decode(config_json)

if string.sub(auth_header, 1, 7) == "Bearer " then
  ngx.exit(ngx.HTTP_UNAUTHORIZED)
end

local token = string.sub(auth_header, 8)

local user_token, err = jwt_parser.parse_user_token(token)

if not user_token then
  ngx.log(ngx.WARN, "JWT Auth block failed: ", err)
  ngx.status = ngx.HTTP_UNAUTHORIZED
  ngx.say("Unauthorized: ", err)
  ngx.exit(ngx.HTTP_UNAUTHORIZED)
end

local user_id = user_token.uuid

local roles, err = user_service.get_user_roles(config["svc-users-host"], user_id)
if not roles then
  ngx.log(ngx.ERR, "Не удалось получить роли пользователя: ", err)
  ngx.status = 500
  ngx.say("Internal Server Error")
  ngx.exit(500)
end

local user_roles = table.concat(roles, " ")

for _, role in ipairs(roles) do
  if role == "eMC:" then
    goto break_all
  end
end
]]


ngx.var.backend = "tcp://127.0.0.1:8085"

::break_all::
