-- =============================================================
-- ox_lib_secure
-- File: server/core/security.lua
-- Description:
--   طبقة الأمان المركزية لنظام ox_lib_secure.
--
-- Responsibilities:
--   - SHA-256
--   - HMAC-SHA256
--   - Token hashing
--   - Payload validation
--   - Meta validation
--   - Anti-replay nonces
--   - Failed attempts tracking
--   - Secret redaction
--   - Canonical signing
--
-- Important:
--   - يجب أن يكون المفتاح الرئيسي خارج قاعدة البيانات.
--   - في الإنتاج، يُنصح بشدة بضبط OXSECURE_MASTER_KEY.
--   - إيقاف المورد عند غياب المفتاح ليس افتراضيًا.
--     يمكن تفعيله عبر:
--       Config.Security.RequireMasterKeyInProduction = true
--   - تخزين المحاولات الفاشلة حاليًا في الذاكرة فقط.
--     إذا أردت استمرارية الحظر بعد إعادة التشغيل، يجب لاحقًا
--     مزامنتها مع قاعدة البيانات عبر خطافات الاستمرارية.
-- =============================================================

Config = Config or {}
OxSecure = OxSecure or {}
OxSecure.Security = OxSecure.Security or {}

local Security = OxSecure.Security
local Utils = OxSecure.Utils or {}

local securityConfig = Config.Security or {}
local payloadLimits = securityConfig.PayloadLimits or {}
local validationConfig = securityConfig.Validation or {}
local tokenConfig = securityConfig.Token or {}
local antiReplayConfig = securityConfig.AntiReplay or {}
local failedAttemptsConfig = securityConfig.FailedAttempts or {}
local encryptionConfig = securityConfig.Encryption or {}

-- =============================================================
-- حالة داخلية
-- =============================================================
local masterKeyWarned = false
local signingKeyCache = nil
local failedAttemptsStorageWarned = false

Security.degraded = false
Security.weakSigningKey = false
Security.FailedAttemptsStorage = 'memory'

-- =============================================================
-- سياسة المفتاح الرئيسي
--
-- RequireMasterKeyInProduction:
--   إذا كانت true ولم يوجد المفتاح و BuildMode = false،
--   سيتم إيقاف المورد.
--
-- AllowDegradedMode:
--   يسمح صراحة بالعمل بدون مفتاح مع تحذير.
--
-- في وضع البناء، نسمح بالعمل المتدهور مؤقتًا.
-- =============================================================
local requireMasterKeyInProduction = securityConfig.RequireMasterKeyInProduction == true

local allowDegradedMode

if securityConfig.AllowDegradedMode == true then
    allowDegradedMode = true
elseif OxSecure.BuildMode == true then
    allowDegradedMode = true
elseif requireMasterKeyInProduction then
    allowDegradedMode = false
else
    -- إذا لم يتم تفعيل إلزام المفتاح، نسمح بالعمل المتدهور
    -- لتجنب الإيقاف القاسي أثناء التطوير أو عند نسيان المفتاح.
    allowDegradedMode = true
end

-- =============================================================
-- خطافات الاستمرارية
--
-- حاليًا المحاولات الفاشلة مخزنة في الذاكرة فقط.
-- عند الحاجة لحظر دائم بعد إعادة التشغيل، يمكن لوحدة قاعدة
-- البيانات تسجيل هذه الخطافات وحفظ البيانات في الجدول
-- المناسب.
-- =============================================================
Security.PersistenceHooks = {
    OnFailedAttempt = nil,
    OnBlocked = nil
}

-- =============================================================
-- SHA-256 constants
-- =============================================================
local SHA256_K = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
}

-- =============================================================
-- أدوات bit helpers
-- =============================================================
local function rotr32(value, bits)
    return ((value >> bits) | (value << (32 - bits))) & 0xFFFFFFFF
end

-- =============================================================
-- SHA-256 binary
-- =============================================================
local function sha256Binary(input)
    if type(input) ~= 'string' then
        input = tostring(input)
    end

    local h0 = 0x6a09e667
    local h1 = 0xbb67ae85
    local h2 = 0x3c6ef372
    local h3 = 0xa54ff53a
    local h4 = 0x510e527f
    local h5 = 0x9b05688c
    local h6 = 0x1f83d9ab
    local h7 = 0x5be0cd19

    local messageLength = #input
    local bitLength = messageLength * 8

    local paddingLength = (56 - ((messageLength + 1) % 64)) % 64
    local padded = input .. '\128' .. string.rep('\0', paddingLength)
    padded = padded .. string.pack('>I8', bitLength)

    for chunkStart = 1, #padded, 64 do
        local w = {}

        for i = 0, 15 do
            w[i] = string.unpack('>I4', padded, chunkStart + (i * 4))
        end

        for i = 16, 63 do
            local s0 = rotr32(w[i - 15], 7) ~ rotr32(w[i - 15], 18) ~ (w[i - 15] >> 3)
            local s1 = rotr32(w[i - 13], 17) ~ rotr32(w[i - 13], 19) ~ (w[i - 13] >> 10)
            w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xFFFFFFFF
        end

        local a = h0
        local b = h1
        local c = h2
        local d = h3
        local e = h4
        local f = h5
        local g = h6
        local h = h7

        for i = 0, 63 do
            local S1 = rotr32(e, 6) ~ rotr32(e, 11) ~ rotr32(e, 25)
            local ch = (e & f) ~ ((~e) & g)
            local temp1 = (h + S1 + ch + SHA256_K[i + 1] + w[i]) & 0xFFFFFFFF

            local S0 = rotr32(a, 2) ~ rotr32(a, 13) ~ rotr32(a, 22)
            local maj = (a & b) ~ (a & c) ~ (b & c)
            local temp2 = (S0 + maj) & 0xFFFFFFFF

            h = g
            g = f
            f = e
            e = (d + temp1) & 0xFFFFFFFF
            d = c
            c = b
            b = a
            a = (temp1 + temp2) & 0xFFFFFFFF
        end

        h0 = (h0 + a) & 0xFFFFFFFF
        h1 = (h1 + b) & 0xFFFFFFFF
        h2 = (h2 + c) & 0xFFFFFFFF
        h3 = (h3 + d) & 0xFFFFFFFF
        h4 = (h4 + e) & 0xFFFFFFFF
        h5 = (h5 + f) & 0xFFFFFFFF
        h6 = (h6 + g) & 0xFFFFFFFF
        h7 = (h7 + h) & 0xFFFFFFFF
    end

    return string.pack('>I4I4I4I4I4I4I4I4', h0, h1, h2, h3, h4, h5, h6, h7)
end

local function toHex(binary)
    return (binary:gsub('.', function(char)
        return string.format('%02x', string.byte(char))
    end))
end

local function xorBytes(a, b)
    local result = {}

    for i = 1, #a do
        result[i] = string.char(a:byte(i) ~ b:byte(i))
    end

    return table.concat(result)
end

-- =============================================================
-- SHA-256 hex
-- =============================================================
function Security.Hash(input)
    return toHex(sha256Binary(input))
end

-- =============================================================
-- HMAC-SHA256
-- =============================================================
function Security.Hmac(message, key)
    if type(key) ~= 'string' then
        key = tostring(key)
    end

    if type(message) ~= 'string' then
        message = tostring(message)
    end

    local blockSize = 64

    if #key > blockSize then
        key = sha256Binary(key)
    end

    if #key < blockSize then
        key = key .. string.rep('\0', blockSize - #key)
    end

    local ipad = string.rep('\x36', blockSize)
    local opad = string.rep('\x5c', blockSize)

    local innerKey = xorBytes(key, ipad)
    local outerKey = xorBytes(key, opad)

    local innerHash = sha256Binary(innerKey .. message)
    return toHex(sha256Binary(outerKey .. innerHash))
end

-- =============================================================
-- Canonical JSON
--
-- يُستخدم للتوقيع على البيانات بشكل ثابت وقابل للتكرار.
-- =============================================================
local function escapeJsonString(value)
    value = value:gsub('[%c"\\]', function(char)
        if char == '"' then
            return '\\"'
        elseif char == '\\' then
            return '\\\\'
        elseif char == '\n' then
            return '\\n'
        elseif char == '\r' then
            return '\\r'
        elseif char == '\t' then
            return '\\t'
        else
            return string.format('\\u%04x', char:byte())
        end
    end)

    return value
end

local function canonicalEncode(value, seen)
    seen = seen or {}

    local valueType = type(value)

    if valueType == 'nil' then
        return 'null'
    end

    if valueType == 'boolean' then
        return value and 'true' or 'false'
    end

    if valueType == 'number' then
        if value ~= value or value == math.huge or value == -math.huge then
            return 'null'
        end

        if math.type(value) == 'integer' then
            return string.format('%d', value)
        end

        return string.format('%.17g', value)
    end

    if valueType == 'string' then
        return '"' .. escapeJsonString(value) .. '"'
    end

    if valueType ~= 'table' then
        return 'null'
    end

    if seen[value] then
        return 'null'
    end

    seen[value] = true

    local count = 0

    for _ in pairs(value) do
        count = count + 1
    end

    local arrayLength = #value

    if arrayLength == count then
        local parts = {}

        for i = 1, arrayLength do
            parts[i] = canonicalEncode(value[i], seen)
        end

        return '[' .. table.concat(parts, ',') .. ']'
    end

    local keys = {}

    for key in pairs(value) do
        if type(key) == 'string' or type(key) == 'number' then
            keys[#keys + 1] = key
        end
    end

    -- فرز المفاتيح:
    -- إذا كان المفتاحان قابلين للتحويل إلى أرقام، تكون المقارنة رقمية.
    -- بخلاف ذلك، تكون المقارنة نصية.
    table.sort(keys, function(a, b)
        local numA = tonumber(a)
        local numB = tonumber(b)

        if numA ~= nil and numB ~= nil then
            return numA < numB
        end

        return tostring(a) < tostring(b)
    end)

    local parts = {}

    for _, key in ipairs(keys) do
        local encodedKey = '"' .. escapeJsonString(tostring(key)) .. '"'
        local encodedValue = canonicalEncode(value[key], seen)
        parts[#parts + 1] = encodedKey .. ':' .. encodedValue
    end

    return '{' .. table.concat(parts, ',') .. '}'
end

function Security.CanonicalEncode(value)
    return canonicalEncode(value)
end

-- =============================================================
-- مفتاح التوقيع
--
-- يجب أن يكون المفتاح الرئيسي خارج قاعدة البيانات.
-- إذا لم يتوفر، يعمل النظام في وضع متدهور ويُسجل تحذير.
-- إذا تم تفعيل RequireMasterKeyInProduction وتم تعطيل
-- BuildMode، سيتم إيقاف المورد.
-- =============================================================
function Security.HasMasterKey()
    local envName = encryptionConfig.MasterKeyEnvName or 'OXSECURE_MASTER_KEY'

    if type(os.getenv) ~= 'function' then
        return false
    end

    local key = os.getenv(envName)

    if Utils.IsNonEmptyString then
        return Utils.IsNonEmptyString(key)
    end

    return type(key) == 'string' and key ~= ''
end

local function handleMissingMasterKey()
    if Security.HasMasterKey() then
        Security.degraded = false
        Security.weakSigningKey = false
        return
    end

    local envName = encryptionConfig.MasterKeyEnvName or 'OXSECURE_MASTER_KEY'

    if allowDegradedMode then
        if not masterKeyWarned then
            if OxSecure.Console and type(OxSecure.Console.warn) == 'function' then
                OxSecure.Console.warn(('Master key is not set. Set %s in your server environment. Running in degraded security mode.'):format(envName))
            end

            masterKeyWarned = true
        end

        Security.degraded = true
        Security.weakSigningKey = true
        return
    end

    if OxSecure.Console and type(OxSecure.Console.error) == 'function' then
        OxSecure.Console.error(('Master key is not set. Set %s in your server environment. Resource will stop because RequireMasterKeyInProduction is enabled.'):format(envName))
    end

    StopResource(Config.ResourceName or GetCurrentResourceName())
end

handleMissingMasterKey()

function Security.GetSigningKey()
    if signingKeyCache then
        return signingKeyCache
    end

    local envName = encryptionConfig.MasterKeyEnvName or 'OXSECURE_MASTER_KEY'

    if type(os.getenv) == 'function' then
        local key = os.getenv(envName)

        if type(key) == 'string' and key ~= '' then
            signingKeyCache = key
            Security.degraded = false
            Security.weakSigningKey = false
            return signingKeyCache
        end
    end

    if not allowDegradedMode then
        if OxSecure.Console and type(OxSecure.Console.error) == 'function' then
            OxSecure.Console.error(('Signing key requested but master key is missing: %s'):format(envName))
        end

        return nil
    end

    if not masterKeyWarned then
        if OxSecure.Console and type(OxSecure.Console.warn) == 'function' then
            OxSecure.Console.warn(('Master key is not set. Falling back to degraded signing key. Set %s in your server environment.'):format(envName))
        end

        masterKeyWarned = true
    end

    Security.degraded = true
    Security.weakSigningKey = true

    signingKeyCache = (Config.ResourceName or 'oxsecure') .. ':' .. (Config.Version or '1.0.0')
    return signingKeyCache
end

function Security.IsDegraded()
    return Security.degraded == true
end

function Security.IsUsingWeakSigningKey()
    return Security.weakSigningKey == true
end

function Security.AllowSensitiveOperation()
    if Security.HasMasterKey() then
        return true
    end

    -- في وضع البناء نسمح مؤقتًا حتى نكمل تطوير الملفات.
    if OxSecure.BuildMode == true then
        return true
    end

    -- خيار صريح إذا أردت السماح بالعمليات الحساسة بدون مفتاح.
    if securityConfig.AllowSensitiveOperationsWithoutMasterKey == true then
        return true
    end

    return false
end

-- =============================================================
-- مقارنة ثابتة الزمن
-- =============================================================
function Security.ConstantTimeCompare(a, b)
    if type(a) ~= 'string' or type(b) ~= 'string' then
        return false
    end

    if #a ~= #b then
        return false
    end

    local difference = 0

    for i = 1, #a do
        difference = difference | (a:byte(i) ~ b:byte(i))
    end

    return difference == 0
end

-- =============================================================
-- التوقيع والتحقق
-- =============================================================
function Security.SignValue(value, key)
    key = key or Security.GetSigningKey()

    if key == nil then
        return nil
    end

    local payload = value

    if type(value) ~= 'string' then
        payload = canonicalEncode(value)
    end

    return Security.Hmac(payload, key)
end

function Security.SignSensitiveValue(value, key)
    if not Security.AllowSensitiveOperation() then
        if OxSecure.Console and type(OxSecure.Console.warn) == 'function' then
            OxSecure.Console.warn('Sensitive signing blocked because master key is missing.')
        end

        return nil
    end

    return Security.SignValue(value, key)
end

function Security.VerifySignature(value, signature, key)
    if type(signature) ~= 'string' or signature == '' then
        return false
    end

    key = key or Security.GetSigningKey()

    if key == nil then
        return false
    end

    local expected = Security.SignValue(value, key)

    if expected == nil then
        return false
    end

    return Security.ConstantTimeCompare(expected, signature)
end

function Security.VerifySensitiveSignature(value, signature, key)
    if not Security.AllowSensitiveOperation() then
        return false
    end

    return Security.VerifySignature(value, signature, key)
end

function Security.HashObject(value)
    local payload = value

    if type(value) ~= 'string' then
        payload = canonicalEncode(value)
    end

    return Security.Hash(payload)
end

-- =============================================================
-- التوكنات
-- =============================================================
function Security.GenerateToken(length)
    if not Security.AllowSensitiveOperation() then
        if OxSecure.Console and type(OxSecure.Console.warn) == 'function' then
            OxSecure.Console.warn('Token generation blocked because master key is missing.')
        end

        return nil, nil, nil
    end

    length = length or 64

    local randomPart = Utils.GenerateRandomString and Utils.GenerateRandomString(math.max(32, length)) or tostring(math.floor(os.time()))
    local timePart = tostring(os.time()) .. ':' .. tostring(Utils.NowMs and Utils.NowMs() or os.time())

    local partOne = Security.Hash(randomPart .. '|' .. timePart)
    local partTwo = Security.Hash(timePart .. '|' .. randomPart)

    local token = partOne .. partTwo

    if #token > length then
        token = token:sub(1, length)
    end

    local signingKey = Security.GetSigningKey()

    if signingKey == nil then
        return nil, nil, nil
    end

    local tokenHash = Security.Hmac(token, signingKey)
    local hintLength = tokenConfig.HintLength or 8
    local tokenHint = token:sub(1, hintLength)

    return token, tokenHash, tokenHint
end

function Security.HashToken(token)
    if type(token) ~= 'string' or token == '' then
        return nil
    end

    local signingKey = Security.GetSigningKey()

    if signingKey == nil then
        return nil
    end

    return Security.Hmac(token, signingKey)
end

-- =============================================================
-- تنظيف النصوص
-- =============================================================
function Security.SanitizeText(input, options)
    if Utils.SanitizeText then
        return Utils.SanitizeText(input, options)
    end

    return type(input) == 'string' and input or ''
end

-- =============================================================
-- التحقق من النصوص
-- =============================================================
function Security.ValidateRequiredString(value, maxLength, fieldName)
    fieldName = fieldName or 'field'

    if type(value) ~= 'string' then
        return false, {
            code = 'ERR_INVALID_FIELD',
            field = fieldName
        }
    end

    local sanitized = Security.SanitizeText(value, {
        maxLength = maxLength
    })

    if sanitized == '' then
        return false, {
            code = 'ERR_EMPTY_MESSAGE',
            field = fieldName
        }
    end

    return true, sanitized
end

-- =============================================================
-- قوائم القيم المسموحة
-- =============================================================
local function isAllowed(list, value)
    if type(list) ~= 'table' then
        return false
    end

    if Utils.Contains then
        return Utils.Contains(list, value)
    end

    for _, item in ipairs(list) do
        if item == value then
            return true
        end
    end

    return false
end

function Security.IsAllowedNotificationType(value)
    return isAllowed(validationConfig.AllowedNotificationTypes, value)
end

function Security.IsAllowedPosition(value)
    return isAllowed(validationConfig.AllowedPositions, value)
end

function Security.IsAllowedDesignStyle(value)
    return isAllowed(validationConfig.AllowedDesignStyles, value)
end

function Security.IsAllowedLogLevel(value)
    return isAllowed(validationConfig.AllowedLogLevels, value)
end

function Security.IsAllowedSeverity(value)
    return isAllowed(validationConfig.AllowedSeverities, value)
end

-- =============================================================
-- التحقق من meta
-- =============================================================
local function validateMetaValue(value, depth, counters)
    local maxDepth = payloadLimits.MaxMetaDepth or 5
    local maxKeys = payloadLimits.MaxMetaKeys or 30
    local maxNestedObjects = payloadLimits.MaxNestedObjects or 15
    local maxArrayLength = payloadLimits.MaxArrayLength or 50

    if depth > maxDepth then
        return false
    end

    local valueType = type(value)

    if valueType == 'function' or valueType == 'userdata' or valueType == 'thread' then
        return false
    end

    if valueType ~= 'table' then
        return true
    end

    counters.objects = counters.objects + 1

    if counters.objects > maxNestedObjects then
        return false
    end

    local count = 0

    for _ in pairs(value) do
        count = count + 1
    end

    counters.keys = counters.keys + count

    if counters.keys > maxKeys then
        return false
    end

    local arrayLength = #value

    -- يتم تطبيق حد المصفوفات فقط إذا كان الجدول مصفوفة فعلية.
    if arrayLength == count and arrayLength > maxArrayLength then
        return false
    end

    for _, childValue in pairs(value) do
        if not validateMetaValue(childValue, depth + 1, counters) then
            return false
        end
    end

    return true
end

function Security.ValidateMeta(meta)
    if meta == nil then
        return true, nil
    end

    if type(meta) ~= 'table' then
        return false, {
            code = 'ERR_INVALID_META'
        }
    end

    local encoded, encodeError = Utils.SafeJsonEncode and Utils.SafeJsonEncode(meta) or nil

    if not encoded then
        return false, {
            code = 'ERR_INVALID_META',
            details = encodeError
        }
    end

    local maxBytes = payloadLimits.MaxMetaJsonBytes or 65535

    if #encoded > maxBytes then
        return false, {
            code = 'ERR_INVALID_META'
        }
    end

    local counters = {
        keys = 0,
        objects = 0
    }

    if not validateMetaValue(meta, 1, counters) then
        return false, {
            code = 'ERR_INVALID_META'
        }
    end

    return true, meta
end

-- =============================================================
-- التحقق من حمولة إشعار
-- =============================================================
function Security.ValidateNotificationPayload(payload)
    if type(payload) ~= 'table' then
        return false, {
            code = 'ERR_INVALID_PAYLOAD'
        }
    end

    local okTitle, title = Security.ValidateRequiredString(payload.title, payloadLimits.MaxTitleLength or 120, 'title')

    if not okTitle then
        return false, title
    end

    local rawBody = payload.body or payload.message

    local okBody, body = Security.ValidateRequiredString(rawBody, payloadLimits.MaxMessageLength or 2000, 'body')

    if not okBody then
        return false, body
    end

    local notificationType = payload.type or 'info'

    if not Security.IsAllowedNotificationType(notificationType) then
        return false, {
            code = 'ERR_INVALID_TYPE',
            field = 'type'
        }
    end

    local position = payload.position or (Config.UI and Config.UI.Position) or 'left'

    if not Security.IsAllowedPosition(position) then
        return false, {
            code = 'ERR_INVALID_POSITION',
            field = 'position'
        }
    end

    local designStyle = payload.designStyle or 'glass'

    if not Security.IsAllowedDesignStyle(designStyle) then
        return false, {
            code = 'ERR_INVALID_STYLE',
            field = 'designStyle'
        }
    end

    local okMeta, metaOrError = Security.ValidateMeta(payload.meta)

    if not okMeta then
        return false, metaOrError
    end

    local durationMs = tonumber(payload.durationMs)

    if durationMs then
        durationMs = math.floor(durationMs)

        if durationMs < 1000 then
            durationMs = 1000
        elseif durationMs > 30000 then
            durationMs = 30000
        end
    end

    return true, {
        title = title,
        body = body,
        type = notificationType,
        position = position,
        designStyle = designStyle,
        durationMs = durationMs,
        meta = metaOrError
    }
end

-- =============================================================
-- التحقق من حمولة خطأ
-- =============================================================
function Security.ValidateErrorPayload(payload)
    if type(payload) ~= 'table' then
        return false, {
            code = 'ERR_INVALID_PAYLOAD'
        }
    end

    local okCode, errorCode = Security.ValidateRequiredString(payload.errorCode or payload.code, 100, 'errorCode')

    if not okCode then
        return false, errorCode
    end

    local okTitle, title = Security.ValidateRequiredString(payload.title, payloadLimits.MaxTitleLength or 120, 'title')

    if not okTitle then
        return false, title
    end

    local okBody, body = Security.ValidateRequiredString(payload.body or payload.message, payloadLimits.MaxBodyLength or 2000, 'body')

    if not okBody then
        return false, body
    end

    local severity = payload.severity or 'error'

    if not Security.IsAllowedSeverity(severity) then
        return false, {
            code = 'ERR_INVALID_SEVERITY',
            field = 'severity'
        }
    end

    local designStyle = payload.designStyle or 'error'

    if not Security.IsAllowedDesignStyle(designStyle) then
        return false, {
            code = 'ERR_INVALID_STYLE',
            field = 'designStyle'
        }
    end

    local okMeta, metaOrError = Security.ValidateMeta(payload.meta)

    if not okMeta then
        return false, metaOrError
    end

    return true, {
        errorCode = errorCode,
        title = title,
        body = body,
        severity = severity,
        designStyle = designStyle,
        meta = metaOrError
    }
end

-- =============================================================
-- Anti-replay nonces
-- =============================================================
local function cleanupNonces(stateSecurity)
    if not stateSecurity or not stateSecurity.nonces then
        return
    end

    local now = Utils.NowMs and Utils.NowMs() or os.time() * 1000

    for nonce, expiresAt in pairs(stateSecurity.nonces) do
        if type(expiresAt) == 'number' and expiresAt < now then
            stateSecurity.nonces[nonce] = nil
        end
    end
end

function Security.CheckAntiReplay(nonce, timestampMs)
    if antiReplayConfig.Enabled == false then
        return true
    end

    if type(nonce) ~= 'string' or nonce == '' then
        return false
    end

    local state = OxSecure.State and OxSecure.State.Runtime or nil
    local stateSecurity = state and state.security or nil

    if not stateSecurity then
        return false
    end

    cleanupNonces(stateSecurity)

    local now = Utils.NowMs and Utils.NowMs() or os.time() * 1000
    local ttlMs = (antiReplayConfig.NonceTTLSeconds or 60) * 1000

    if type(timestampMs) == 'number' then
        if math.abs(now - timestampMs) > ttlMs then
            return false
        end
    end

    if stateSecurity.nonces[nonce] then
        return false
    end

    stateSecurity.nonces[nonce] = now + ttlMs

    return true
end

-- =============================================================
-- مهمة دورية لتنظيف nonces
-- =============================================================
if antiReplayConfig.Enabled ~= false then
    local nonceCleanupInterval = tonumber(antiReplayConfig.CleanupIntervalSeconds) or 60

    if nonceCleanupInterval < 5 then
        nonceCleanupInterval = 5
    end

    CreateThread(function()
        while true do
            Wait(nonceCleanupInterval * 1000)

            local state = OxSecure.State and OxSecure.State.Runtime or nil
            local stateSecurity = state and state.security or nil

            if stateSecurity then
                cleanupNonces(stateSecurity)
            end
        end
    end)
end

-- =============================================================
-- مصدر تخزين المحاولات الفاشلة
-- =============================================================
function Security.GetFailedAttemptsStorage()
    return Security.FailedAttemptsStorage
end

-- =============================================================
-- المحاولات الفاشلة
--
-- التخزين الحالي في الذاكرة فقط.
-- إذا أردت استمرارية الحظر بعد إعادة التشغيل، يجب حفظها
-- لاحقًا في قاعدة البيانات عبر PersistenceHooks.
-- =============================================================
function Security.RegisterFailedAttempt(key, reasonCode)
    if type(key) ~= 'string' or key == '' then
        return 0, false
    end

    if Security.FailedAttemptsStorage ~= 'memory' and not failedAttemptsStorageWarned then
        if OxSecure.Console and type(OxSecure.Console.warn) == 'function' then
            OxSecure.Console.warn('Failed attempts storage is not supported yet. Falling back to memory storage.')
        end

        failedAttemptsStorageWarned = true
    end

    local state = OxSecure.State and OxSecure.State.Runtime or nil
    local stateSecurity = state and state.security or nil

    if not stateSecurity then
        return 0, false
    end

    local now = Utils.NowMs and Utils.NowMs() or os.time() * 1000

    stateSecurity.failedAttempts[key] = stateSecurity.failedAttempts[key] or {
        count = 0,
        firstAt = now
    }

    local entry = stateSecurity.failedAttempts[key]

    entry.count = entry.count + 1
    entry.lastAt = now
    entry.reason = reasonCode

    local maxAttempts = failedAttemptsConfig.Max or 10
    local shouldBlock = maxAttempts > 0 and entry.count >= maxAttempts

    if shouldBlock then
        local banMinutes = failedAttemptsConfig.BanMinutes or 30
        entry.blockedUntil = now + (banMinutes * 60000)
    end

    if type(Security.PersistenceHooks.OnFailedAttempt) == 'function' then
        pcall(Security.PersistenceHooks.OnFailedAttempt, key, entry, reasonCode)
    end

    if shouldBlock and type(Security.PersistenceHooks.OnBlocked) == 'function' then
        pcall(Security.PersistenceHooks.OnBlocked, key, entry, reasonCode)
    end

    return entry.count, shouldBlock
end

function Security.IsTemporarilyBlocked(key)
    if type(key) ~= 'string' or key == '' then
        return false
    end

    local state = OxSecure.State and OxSecure.State.Runtime or nil
    local stateSecurity = state and state.security or nil

    if not stateSecurity then
        return false
    end

    local entry = stateSecurity.failedAttempts[key]

    if not entry then
        return false
    end

    local now = Utils.NowMs and Utils.NowMs() or os.time() * 1000

    if entry.blockedUntil and entry.blockedUntil > now then
        return true
    end

    if entry.blockedUntil and entry.blockedUntil <= now then
        entry.blockedUntil = nil
    end

    return false
end

function Security.ClearFailedAttempts(key)
    if type(key) ~= 'string' or key == '' then
        return
    end

    local state = OxSecure.State and OxSecure.State.Runtime or nil
    local stateSecurity = state and state.security or nil

    if not stateSecurity then
        return
    end

    stateSecurity.failedAttempts[key] = nil
end

-- =============================================================
-- إخفاء الأسرار
-- =============================================================
function Security.RedactSecrets(value)
    if Utils.RedactSecrets then
        return Utils.RedactSecrets(value)
    end

    return value
end

-- =============================================================
-- رسالة تحميل ناجحة
-- =============================================================
if OxSecure.Console and type(OxSecure.Console.debug) == 'function' then
    OxSecure.Console.debug('server/core/security.lua loaded')
end
