local secret_token = "Bearer test"
local client_token = ngx.req.get_headers()["Authorization"]

if client_token ~= secret_token then
  ngx.status = ngx.HTTP_UNAUTHORIZED
  ngx.say("Forbidden: Invalid token")
  ngx.exit(ngx.HTTP_UNAUTHORIZED)
end

package.loaded["lua.init_app"] = nil
require "lua.init_app"
