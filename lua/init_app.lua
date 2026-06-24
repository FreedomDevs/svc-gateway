-- lua/init_app.lua
local cjson = require("cjson")

-- Функция для чтения файла
local function read_file(path)
  local file, err = io.open(path, "r")
  if not file then
    return nil, err
  end
  local content = file:read("*all")
  file:close()
  return content
end

-- Читаем наш конфиг
local config_json, err = read_file("config.json")
if not config_json then
  ngx.log(ngx.ERR, "ЗАВЕРШЕНИЕ: Не удалось прочитать config.json: ", err)
  os.exit(1) -- Если конфига нет, Nginx даже не запустится (это правильно)
end

-- Проверяем, что JSON валидный (опционально)
local status, config_table = pcall(cjson.decode, config_json)
if not status then
  ngx.log(ngx.ERR, "ЗАВЕРШЕНИЕ: Ошибка в синтаксисе config.json")
  os.exit(1)
end

-- Сохраняем строку в нашу разделяемую память Nginx
local cache = ngx.shared.app
cache:set("config", config_json)

ngx.log(ngx.WARN, "🚀 Конфигурация сервиса успешно загружена в память Nginx!")
