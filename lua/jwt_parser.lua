local jwt = require("resty.jwt")
local cjson = require("cjson")

local _M = {}

function _M.parse_user_token(token_str)
  local cache = ngx.shared.app_config
  local config = cjson.decode(cache:get("raw_config"))
  local public_key = config.jwt_public_key

  if not public_key then
    return nil, "JWT Public key not found in server config"
  end

  local jwt_obj = jwt:verify(public_key, token_str)

  if not jwt_obj.verified then
    return nil, "JWT verification failed: " .. (jwt_obj.reason or "unknown")
  end

  local claims = jwt_obj.payload

  local user_token = {
    iat = claims.iat,
    exp = claims.exp,
    uuid = claims.uuid,
    token_hash = claims.tokenHash
  }

  if not user_token.uuid or not user_token.token_hash then
    return nil, "JWT missing required UserToken fields (uuid or tokenHash)"
  end

  return user_token
end

return _M
