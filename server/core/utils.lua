-- =============================================================
-- ox_lib_secure
-- File: server/core/utils.lua
-- Description:
--   أدوات مساعدة عامة لنظام ox_lib_secure.
--
-- Notes:
--   - هذا الملف لا يجب أن يحتوي على منطق أعمال ثقيل.
--   - الأدوات هنا يجب أن تكون نقية قدر الإمكان.
--   - أي أداة أمنية ثقيلة يجب أن تكون لاحقًا داخل
--     server/core/security.lua
-- =============================================================

Config = Config or {}
OxSecure = OxSecure or {}

OxSecure.Utils = OxSecure.Utils or {}

local Utils = OxSecure.Utils

-- =============================================================
-- الوقت
-- =============================================================
function Utils.NowMs()
    if type(GetGameTimer) == 'function' then
        return GetGameTimer()
    end

    return os.time() * 1000
end

-- =============================================================
-- التحقق من النصوص
-- =============================================================
function Utils.IsString(value)
    return type(value) == 'string'
end

function Utils.IsNonEmptyString(value)
    if type(value) ~= 'string' then
        return false
    end

    return value:match('%S') ~= nil
end

function Utils.Trim(text)
    if type(text) ~= 'string' then
        return ''
    end

    return text:match('^%s*(.-)%s*$') or ''
end

-- =============================================================
-- قص النصوص مع محاولة الحفاظ على UTF-8
-- =============================================================
function Utils.Truncate(text, maxChars)
    if type(text) ~= 'string' then
        return ''
    end

    if type(maxChars) ~= 'number' or maxChars <= 0 then
        return text
    end

    if utf8 and utf8.len and utf8.offset then
        local length = utf8.len(text)

        if length <= maxChars then
            return text
        end

        local offset = utf8.offset(text, maxChars + 1)

        if offset then
            return text:sub(1, offset - 1)
        end

        return text
    end

    if #text <= maxChars then
        return text
    end

    return text:sub(1, maxChars)
end

-- =============================================================
-- تنظيف النصوص
-- =============================================================
function Utils.SanitizeText(input, options)
    options = options or {}

    if type(input) ~= 'string' then
        return ''
    end

    local validation = Config.Security and Config.Security.Validation or {}
    local limits = Config.Security and Config.Security.PayloadLimits or {}

    local text = input

    if options.blockControl ~= false and validation.BlockControlCharacters ~= false then
        text = text:gsub('%c', ' ')
    end

    if options.sanitizeHtml ~= false and validation.SanitizeHtml ~= false then
        text = text:gsub('<[^>]*>', '')
    end

    if options.normalizeWhitespace ~= false and validation.NormalizeWhitespace ~= false then
        text = text:gsub('%s+', ' ')
    end

    text = Utils.Trim(text)

    local maxLength = options.maxLength or options.maxLen or limits.MaxMessageLength

    if type(maxLength) == 'number' and maxLength > 0 then
        text = Utils.Truncate(text, maxLength)
    end

    return text
end

-- =============================================================
-- استبدال المتغيرات داخل النصوص
-- مثال:
--   'حقل مطلوب مفقود: {field}.'
-- =============================================================
function Utils.ReplacePlaceholders(template, data, pattern)
    if type(template) ~= 'string' then
        return ''
    end

    data = data or {}

    local placeholderPattern = pattern or '{([%w_]+)}'

    local result = template:gsub(placeholderPattern, function(key)
        local value = data[key]

        if value == nil then
            return ''
        end

        return tostring(value)
    end)

    return result
end

-- =============================================================
-- JSON الآمن
-- =============================================================
function Utils.SafeJsonEncode(value)
    if json == nil or type(json.encode) ~= 'function' then
        return nil, 'json not available'
    end

    local ok, encoded = pcall(json.encode, value)

    if not ok then
        return nil, tostring(encoded)
    end

    return encoded, nil
end

function Utils.SafeJsonDecode(text)
    if json == nil or type(json.decode) ~= 'function' then
        return nil, 'json not available'
    end

    if type(text) ~= 'string' or text == '' then
        return nil, 'invalid json input'
    end

    local ok, decoded = pcall(json.decode, text)

    if not ok then
        return nil, tostring(decoded)
    end

    return decoded, nil
end

-- =============================================================
-- أدوات الجداول
-- =============================================================
local function deepCopy(original, seen)
    if type(original) ~= 'table' then
        return original
    end

    seen = seen or {}

    if seen[original] then
        return seen[original]
    end

    local copy = {}
    seen[original] = copy

    for key, value in pairs(original) do
        copy[deepCopy(key, seen)] = deepCopy(value, seen)
    end

    return copy
end

function Utils.TableCopy(value)
    return deepCopy(value)
end

function Utils.TableMerge(base, override, deep)
    if type(base) ~= 'table' then
        base = {}
    end

    if type(override) ~= 'table' then
        return base
    end

    for key, value in pairs(override) do
        if deep and type(base[key]) == 'table' and type(value) == 'table' then
            base[key] = Utils.TableMerge(base[key], value, true)
        else
            base[key] = value
        end
    end

    return base
end

function Utils.Count(tableToCount)
    if type(tableToCount) ~= 'table' then
        return 0
    end

    local count = 0

    for _ in pairs(tableToCount) do
        count = count + 1
    end

    return count
end

function Utils.ListToSet(list)
    local set = {}

    if type(list) ~= 'table' then
        return set
    end

    for _, value in ipairs(list) do
        set[value] = true
    end

    return set
end

function Utils.Contains(list, value)
    if type(list) ~= 'table' then
        return false
    end

    for _, item in ipairs(list) do
        if item == value then
            return true
        end
    end

    return false
end

function Utils.Split(input, separator)
    local result = {}

    if type(input) ~= 'string' or input == '' then
        return result
    end

    separator = separator or ','

    local start = 1

    while true do
        local position = input:find(separator, start, true)

        if not position then
            if start <= #input then
                result[#result + 1] = input:sub(start)
            end

            break
        end

        if position > start then
            result[#result + 1] = input:sub(start, position - 1)
        end

        start = position + #separator
    end

    return result
end

function Utils.Clamp(value, minValue, maxValue)
    if type(value) ~= 'number' then
        return minValue
    end

    if value < minValue then
        return minValue
    end

    if value > maxValue then
        return maxValue
    end

    return value
end

-- =============================================================
-- Hash سريع غير مخصص للأمان الثقيل
--
-- ملاحظة:
-- GetHashKey سريع ومناسب للاستخدامات الداخلية غير الأمنية،
-- لكنه ليس تجزئة تشفيرية قوية.
-- أي تجزئة قوية أو توقيع أمني يجب أن يكون لاحقًا داخل:
--   server/core/security.lua
-- =============================================================
function Utils.FastHash(input)
    if type(input) ~= 'string' then
        input = tostring(input)
    end

    if type(GetHashKey) == 'function' then
        local hash = GetHashKey(input)
        return string.format('%08x', hash & 0xFFFFFFFF)
    end

    -- FNV-1a 32-bit fallback
    local hash = 2166136261

    for i = 1, #input do
        hash = hash ~ input:byte(i)
        hash = (hash * 16777619) & 0xFFFFFFFF
    end

    return string.format('%08x', hash)
end

function Utils.CreateBucketKey(parts)
    if type(parts) ~= 'table' then
        parts = { tostring(parts) }
    end

    local joined = table.concat(parts, ':')

    local first = Utils.FastHash(joined)
    local second = Utils.FastHash(joined .. '|oxsecure|bucket')

    return first .. second
end

-- =============================================================
-- مولد أرقام عشوائية داخلي
--
-- ملاحظة مهمة:
-- لا نستخدم math.randomseed حتى لا نتداخل مع مولد الأرقام
-- العشوائية العام في Lua أو مع سكربتات أخرى.
--
-- هذا المولد غير تشفيري.
-- الاستخدامات الحساسة يجب أن تُدار لاحقًا عبر طبقة الأمان.
-- =============================================================
local rngState = 0

local function ensureRngState()
    if rngState ~= 0 then
        return
    end

    local seed = os.time()

    if type(GetGameTimer) == 'function' then
        seed = seed + GetGameTimer()
    end

    local resourceName = Config.ResourceName or 'oxsecure'
    local nameHash = tonumber(Utils.FastHash(resourceName), 16) or 0

    rngState = (seed ~ nameHash) & 0xFFFFFFFF

    if rngState == 0 then
        rngState = 0x9E3779B9
    end
end

local function nextRandom32()
    ensureRngState()

    local x = rngState

    x = (x ~ ((x << 13) & 0xFFFFFFFF)) & 0xFFFFFFFF
    x = (x ~ (x >> 17)) & 0xFFFFFFFF
    x = (x ~ ((x << 5) & 0xFFFFFFFF)) & 0xFFFFFFFF

    rngState = x & 0xFFFFFFFF

    return rngState
end

local function randomInt(minValue, maxValue)
    if minValue > maxValue then
        minValue, maxValue = maxValue, minValue
    end

    local range = maxValue - minValue + 1

    if range <= 0 then
        return minValue
    end

    return minValue + (nextRandom32() % range)
end

-- =============================================================
-- توليد نصوص عشوائية
-- =============================================================
function Utils.GenerateRandomString(length, alphabet)
    length = math.floor(tonumber(length) or 16)

    if length <= 0 then
        return ''
    end

    alphabet = alphabet or 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'

    local result = {}

    for i = 1, length do
        local index = randomInt(1, #alphabet)
        result[i] = alphabet:sub(index, index)
    end

    return table.concat(result)
end

function Utils.GenerateNonce(length)
    length = length or 16
    return Utils.GenerateRandomString(length)
end

function Utils.GenerateSessionId(length)
    local sessionLength = length or (Config.Players and Config.Players.SessionIdLength) or 32

    local randomPart = Utils.GenerateRandomString(math.max(16, sessionLength))
    local timePart = tostring(os.time()) .. ':' .. tostring(Utils.NowMs())

    local hashOne = Utils.FastHash(randomPart .. '|' .. timePart)
    local hashTwo = Utils.FastHash(timePart .. '|' .. randomPart)

    local sessionId = hashOne .. hashTwo

    if #sessionId >= sessionLength then
        return sessionId:sub(1, sessionLength)
    end

    return sessionId .. Utils.GenerateRandomString(sessionLength - #sessionId)
end

-- =============================================================
-- إخفاء الأسرار
-- =============================================================
local function isForbiddenKey(key)
    local secretsConfig = Config.Security and Config.Security.Secrets or {}
    local forbidden = secretsConfig.ForbiddenInLogs or {}

    local lowerKey = key:lower()

    for _, forbiddenKey in ipairs(forbidden) do
        if type(forbiddenKey) == 'string' and forbiddenKey ~= '' then
            if lowerKey:find(forbiddenKey:lower(), 1, true) then
                return true
            end
        end
    end

    return false
end

local function redactTable(target, seen)
    if type(target) ~= 'table' then
        return target
    end

    seen = seen or {}

    if seen[target] then
        return target
    end

    seen[target] = true

    local secretsConfig = Config.Security and Config.Security.Secrets or {}
    local maskValue = secretsConfig.MaskValue or '[REDACTED]'

    for key, value in pairs(target) do
        if type(key) == 'string' and isForbiddenKey(key) then
            target[key] = maskValue
        elseif type(value) == 'table' then
            redactTable(value, seen)
        end
    end

    return target
end

function Utils.RedactSecrets(value)
    if type(value) ~= 'table' then
        return value
    end

    local copy = Utils.TableCopy(value)
    redactTable(copy)

    return copy
end

-- =============================================================
-- استدعاء آمن للدوال
-- =============================================================
function Utils.SafeCallback(fn, ...)
    if type(fn) ~= 'function' then
        return false, 'invalid callback'
    end

    return pcall(fn, ...)
end

-- =============================================================
-- رسالة تحميل ناجحة
-- =============================================================
if OxSecure.Console and type(OxSecure.Console.debug) == 'function' then
    OxSecure.Console.debug('server/core/utils.lua loaded')
end
