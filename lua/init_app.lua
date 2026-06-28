local cjson = require("cjson")

-- Функция для чтения файла
local function read_file(path)
  local file, err = io.open(path, "r")
  if not file then
    return nil, err
  end
  local content = file:read("*all")
  file:close()

  -- 1. Удаляем многострочные комментарии /* ... */
  -- Режим `.-` означает "ленивый поиск", чтобы не бахнуть лишнего между разными комментами
  content = string.gsub(content, "/%*.-%*/", "")

  -- 2. Удаляем однострочные комментарии // ...
  -- Ищем // и всё до конца строки [^\n]*
  content = string.gsub(content, "%s+//[^\n]*", "")

  return content
end

-- Читаем наш конфиг
local config_json, err = read_file("config.jsonc")
if not config_json then
  ngx.log(ngx.ERR, "ЗАВЕРШЕНИЕ: Не удалось прочитать config.jsonc: ", err)
  os.exit(1) -- Если конфига нет, Nginx даже не запустится (это правильно)
end

-- Проверяем, что JSON валидный (опционально)
local status, config = pcall(cjson.decode, config_json)
if not status then
  ngx.log(ngx.ERR, "ЗАВЕРШЕНИЕ: Ошибка в синтаксисе config.jsonc, ", config)
  os.exit(1)
end

cjson.encode_escape_forward_slash(false)

-- Сохраняем строку в нашу разделяемую память Nginx
local cache = ngx.shared.app
local minified = cjson.encode(config)
-- ngx.log(ngx.WARN, minified)

local success, err = cache:safe_set("config", minified)

if not success then
  ngx.log(ngx.ERR, "Критическая ошибка: не удалось записать конфиг в память: ", err)
end

ngx.log(ngx.WARN, "🚀 Конфигурация сервиса успешно загружена в память Nginx!")
