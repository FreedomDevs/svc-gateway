local function is_allowed(val, list)
  if not list or type(list) ~= "table" then return false end
  for _, v in pairs(list) do
    if v == val then
      return true
    end
  end
  return false
end

local function check_cors(allowed_domains)
  if is_allowed(ngx.var.http_origin, allowed_domains) then
    ngx.header["Access-Control-Allow-Origin"] = ngx.var.http_origin
    ngx.header["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS, PUT, DELETE, PATCH"
    ngx.header["Access-Control-Allow-Headers"] =
    "DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization"
    ngx.header["Access-Control-Max-Age"] = "1800"
  end

  if ngx.req.get_method() == "OPTIONS" then
    ngx.status = 204
    ngx.send_headers()
    ngx.exit(ngx.HTTP_OK)
  end
end

return check_cors
