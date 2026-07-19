-- Полный GPT код
local websocket = require "resty.websocket.server"
local ffi = require "ffi"

local wb, err = websocket:new {
  timeout = 60000 * 2,
  max_payload_len = 16 * 1024 * 1024
}

if not wb then
  ngx.log(ngx.ERR, "websocket init failed: ", err)
  return ngx.exit(500)
end


local backend_url = ngx.var.backend

if not backend_url then
  ngx.log(ngx.ERR, "backend variable is not set")
  return ngx.exit(500)
end


local backend = ngx.socket.tcp()
backend:settimeouts(60000 * 2, 60000 * 2, 60000 * 2)


local ok, err

if backend_url:sub(1, 6) == "tcp://" then
  local addr = backend_url:sub(7)

  local host, port = addr:match("^([^:]+):(%d+)$")

  if not host or not port then
    ngx.log(ngx.ERR, "invalid tcp backend: ", backend_url)
    return ngx.exit(500)
  end

  ok, err = backend:connect(host, tonumber(port))
elseif backend_url:sub(1, 7) == "unix://" then
  local path = backend_url:sub(8)

  ok, err = backend:connect("unix:" .. path)
else
  ngx.log(ngx.ERR, "unknown backend scheme: ", backend_url)
  return ngx.exit(500)
end


if not ok then
  ngx.log(ngx.ERR, "backend connect failed: ", err)
  return ngx.exit(502)
end


local function pack_u32_le(n)
  local buf = ffi.new("uint32_t[1]", n)
  return ffi.string(buf, 4)
end


local function unpack_u32_le(str)
  local buf = ffi.new("uint32_t[1]")
  ffi.copy(buf, str, 4)
  return tonumber(buf[0])
end


-- WS -> Backend
local function ws_reader()
  while true do
    local data, typ, err = wb:recv_frame()

    if not data then
      break
    end

    if typ == "close" then
      backend:close()
      break
    end

    if typ == "ping" then
      wb:send_pong(data)
      goto continue
    end

    if typ == "text" then
      ngx.log(ngx.ERR, "unexpected text frame from client, expected binary")
      break
    end

    if typ ~= "binary" then
      goto continue
    end

    if #data < 4 then
      ngx.log(ngx.ERR, "invalid message")
      break
    end


    local msg_type = data:sub(1, 4)
    local payload = data:sub(5)
    local packet =
        msg_type ..
        pack_u32_le(#payload) ..
        payload


    local ok, err = backend:send(packet)

    if not ok then
      ngx.log(ngx.ERR, "backend write failed: ", err)
      break
    end

    ::continue::
  end
end


-- Backend -> WS
local function backend_reader()
  while true do
    -- type
    local type_raw, err = backend:receive(4)
    if not type_raw then
      break
    end

    -- length
    local len_raw, err = backend:receive(4)
    if not len_raw then
      break
    end

    local len = unpack_u32_le(len_raw)
    if len > 16 * 1024 * 1024 then
      ngx.log(ngx.ERR, "message too large")
      break
    end


    local data, err = backend:receive(len)
    if not data then
      break
    end

    local full_packet = type_raw .. data

    -- отправляем клиенту
    local ok, err = wb:send_binary(full_packet)
    if not ok then
      ngx.log(ngx.ERR, "websocket send failed: ", err)
      break
    end
  end
end


-- параллельно запускаем две стороны
local t1 = ngx.thread.spawn(ws_reader)
local t2 = ngx.thread.spawn(backend_reader)


local ok, thread = ngx.thread.wait(t1, t2)

if thread == t1 then
  ngx.thread.kill(t2)
else
  ngx.thread.kill(t1)
end


backend:close()
wb:send_close(1000, "Normal closure")

ngx.exit(ngx.OK)
