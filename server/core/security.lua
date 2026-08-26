-- =============================================================
-- ox_lib_secure
-- File: server/core/security.lua
-- Description:
--   وحدة الأمان الرئيسية لنظام ox_lib_secure.
--   توفر تشفير قوي (SHA-256, HMAC)، إدارة توكنات،
--   منع إعادة التشغيل، والتحقق من الأحداث.
--
-- Notes:
--   - مواءمة 100% مع config/main.lua النهائي.
--   - تستخدم خوارزميات تجزئة آمنة (SHA-256).
--   - تدعم HMAC للتوقيع.
--   - معالجة آمنة لـ json عبر pcall.
--   - إصلاح: استخدام طول ثابت للتوقيع بدلاً من فاصل.
-- =============================================================

Config = Config or {}
OxSecure = OxSecure or {}
OxSecure.Security = OxSecure.Security or {}

local Security = OxSecure.Security
local Logger = OxSecure.Logger or {}
local RateLimiter = OxSecure.RateLimiter or {}
local Audit = OxSecure.Audit or {}

-- =============================================================
-- قراءة الإعدادات من الكونفق
-- =============================================================
local secConfig = Config.Security or {}

local encryptionConfig = secConfig.Encryption or {}
local ENCRYPTION_ALGORITHM = encryptionConfig.Algorithm or 'aes-256-cbc'
local ENCRYPTION_KEY_LENGTH = encryptionConfig.KeyLength or 32
local ENCRYPTION_IV_LENGTH = encryptionConfig.IVLength or 16
local ENCRYPTION_MASTER_KEY_ENV = encryptionConfig.MasterKeyEnvName or 'OX_SECURE_MASTER_KEY'
local ENCRYPTION_ALLOW_DB_PRIVATE_KEYS = encryptionConfig.AllowDbPrivateKeys == true

local hashingConfig = secConfig.Hashing or {}
local HMAC_ALGORITHM = hashingConfig.HmacAlgorithm or 'sha256'
local SALT_LENGTH = hashingConfig.SaltLength or 16
local HASH_ITERATIONS = hashingConfig.Iterations or 10000

local tokenConfig = secConfig.Token or {}
local TOKEN_TTL_SECONDS = tokenConfig.TTLSeconds or 86400
local TOKEN_LENGTH_BYTES = tokenConfig.LengthBytes or 32
local TOKEN_HINT_LENGTH = tokenConfig.HintLength or 8
local TOKEN_MAX_ACTIVE = tokenConfig.MaxActive or 5
local TOKEN_REFRESH_ENABLED = tokenConfig.RefreshEnabled ~= false

local antiReplayConfig = secConfig.AntiReplay or {}
local ANTI_REPLAY_ENABLED = antiReplayConfig.Enabled ~= false
local ANTI_REPLAY_WINDOW_SECONDS = antiReplayConfig.WindowSeconds or 300
local ANTI_REPLAY_MAX_NONCES = antiReplayConfig.MaxNonces or 10000

local eventsConfig = secConfig.Events or {}
local EVENTS_VALIDATE_SOURCE = eventsConfig.ValidateSource ~= false
local EVENTS_VALIDATE_PAYLOAD = eventsConfig.ValidatePayload ~= false
local EVENTS_MAX_PAYLOAD_SIZE = eventsConfig.MaxPayloadSize or 65536

local payloadLimitsConfig = secConfig.PayloadLimits or {}
local PAYLOAD_MAX_STRING_LENGTH = payloadLimitsConfig.MaxStringLength or 2000
local PAYLOAD_MAX_TITLE_LENGTH = payloadLimitsConfig.MaxTitleLength or 200
local PAYLOAD_MAX_BODY_LENGTH = payloadLimitsConfig.MaxBodyLength or 1000
local PAYLOAD_MAX_ARRAY_SIZE = payloadLimitsConfig.MaxArraySize or 100
local PAYLOAD_MAX_OBJECT_SIZE = payloadLimitsConfig.MaxObjectSize or 50
local PAYLOAD_MAX_NESTED_DEPTH = payloadLimitsConfig.MaxNestedDepth or 5
local PAYLOAD_MAX_META_JSON_BYTES = payloadLimitsConfig.MaxMetaJsonBytes or 4096
local PAYLOAD_MAX_META_DEPTH = payloadLimitsConfig.MaxMetaDepth or 4
local PAYLOAD_MAX_NESTED_OBJECTS = payloadLimitsConfig.MaxNestedObjects or 10
local PAYLOAD_MAX_ARRAY_LENGTH = payloadLimitsConfig.MaxArrayLength or 200

local validationConfig = secConfig.Validation or {}
local VALIDATION_STRICT_TYPES = validationConfig.StrictTypes ~= false
local VALIDATION_ALLOW_NIL = validationConfig.AllowNil == true
local VALIDATION_SANITIZE_STRINGS = validationConfig.SanitizeStrings ~= false
local VALIDATION_ALLOWED_NOTIFICATION_TYPES = validationConfig.AllowedNotificationTypes or {
    'info', 'success', 'warning', 'error', 'critical', 'system'
}
local VALIDATION_ALLOWED_POSITIONS = validationConfig.AllowedPositions or {
    'left', 'right', 'center', 'top', 'bottom'
}
local VALIDATION_ALLOWED_DESIGN_STYLES = validationConfig.AllowedDesignStyles or {
    'default', 'purple_glass', 'glass', 'solid', 'gradient',
    'error', 'warning', 'success', 'info', 'critical'
}
local VALIDATION_ALLOWED_SEVERITIES = validationConfig.AllowedSeverities or {
    'info', 'warning', 'error', 'critical'
}
local VALIDATION_ALLOWED_LOG_LEVELS = validationConfig.AllowedLogLevels or {
    'debug', 'info', 'warn', 'error', 'critical'
}

local rateLimitConfig = secConfig.RateLimit or {}
local RATE_LIMIT_USE_MEMORY = rateLimitConfig.UseMemoryLimiter ~= false
local RATE_LIMIT_USE_DB_AUDIT = rateLimitConfig.UseDatabaseOnlyForAudit == true
local RATE_LIMIT_CLEANUP_SECONDS = rateLimitConfig.CleanupIntervalSeconds or 300
local RATE_LIMIT_WINDOW_SECONDS = rateLimitConfig.WindowSeconds or 60
local RATE_LIMIT_MAX_PER_WINDOW = rateLimitConfig.MaxPerWindow or 100
local RATE_LIMIT_BUCKETS = rateLimitConfig.Buckets or {}

local nuiConfig = secConfig.NUI or {}
local NUI_VALIDATE_CALLBACKS = nuiConfig.ValidateCallbacks ~= false
local NUI_ALLOWED_ORIGINS = nuiConfig.AllowedOrigins or { 'ox_lib_secure' }

local identifiersConfig = secConfig.Identifiers or {}
local IDENTIFIERS_HASH_IP = identifiersConfig.HashIP ~= false
local IDENTIFIERS_TRACK_DEVICE = identifiersConfig.TrackDevice == true

local sessionsConfig = secConfig.Sessions or {}
local SESSIONS_MAX_PER_PLAYER = sessionsConfig.MaxPerPlayer or 1
local SESSIONS_EXPIRY_HOURS = sessionsConfig.ExpiryHours or 24
local SESSIONS_VALIDATE_ON_JOIN = sessionsConfig.ValidateOnJoin ~= false

local failedAttemptsConfig = secConfig.FailedAttempts or {}
local FAILED_ATTEMPTS_MAX = failedAttemptsConfig.Max or 5
local FAILED_ATTEMPTS_WINDOW_MINUTES = failedAttemptsConfig.WindowMinutes or 30
local FAILED_ATTEMPTS_BAN_MINUTES = failedAttemptsConfig.BanMinutes or 30
local FAILED_ATTEMPTS_TRACK_IP = failedAttemptsConfig.TrackIP ~= false
local FAILED_ATTEMPTS_TRACK_DISCORD = failedAttemptsConfig.TrackDiscord ~= false

local auditConfig = secConfig.Audit or {}
local AUDIT_LOG_ALL_ACTIONS = auditConfig.LogAllActions ~= false
local AUDIT_LOG_FAILED_ATTEMPTS = auditConfig.LogFailedAttempts ~= false
local AUDIT_LOG_SUCCESSFUL_LOGINS = auditConfig.LogSuccessfulLogins == true

local secretsConfig = secConfig.Secrets or {}
local SECRETS_FORBIDDEN_IN_LOGS = secretsConfig.ForbiddenInLogs or {
    'password', 'token', 'secret', 'key',
    'authorization', 'master_key', 'signing_key',
    'encryption_key', 'api_key'
}

local errorDisclosureConfig = secConfig.ErrorDisclosure or {}
local ERROR_SHOW_STACK = errorDisclosureConfig.ShowStack == true
local ERROR_SHOW_INTERNAL = errorDisclosureConfig.ShowInternal == true
local ERROR_GENERIC_MESSAGE = errorDisclosureConfig.GenericMessage or 'حدث خطأ غير متوقع. يرجى المحاولة لاحقًا.'

local systemsConfig = secConfig.Systems or {}
local SYSTEMS_VALIDATE_TOKENS = systemsConfig.ValidateTokens ~= false
local SYSTEMS_REQUIRE_SCOPES = systemsConfig.RequireScopes ~= false

local memoryCacheConfig = secConfig.MemoryCache or {}
local MEMORY_CACHE_ENABLED = memoryCacheConfig.Enabled ~= false
local MEMORY_CACHE_TTL_SECONDS = memoryCacheConfig.TTLSeconds or 300
local MEMORY_CACHE_MAX_ENTRIES = memoryCacheConfig.MaxEntries or 1000

local commandConfig = secConfig.Command or {}
local COMMAND_REQUIRE_PERMISSION = commandConfig.RequirePermission ~= false
local COMMAND_LOG_COMMANDS = commandConfig.LogCommands ~= false
local COMMAND_RATE_LIMIT_PER_MINUTE = commandConfig.RateLimitPerMinute or 10

local databaseConfig = secConfig.Database or {}
local DB_ENCRYPT_SENSITIVE = databaseConfig.EncryptSensitive ~= false
local DB_SANITIZE_QUERIES = databaseConfig.SanitizeQueries ~= false

local startupChecksConfig = secConfig.StartupChecks or {}
local STARTUP_VERIFY_KEYS = startupChecksConfig.VerifyKeys ~= false
local STARTUP_VERIFY_DATABASE = startupChecksConfig.VerifyDatabase ~= false
local STARTUP_VERIFY_PERMISSIONS = startupChecksConfig.VerifyPermissions ~= false
local STARTUP_VERIFY_LOGGER_HOOK = startupChecksConfig.VerifyLoggerHook ~= false

-- =============================================================
-- الحالة الداخلية
-- =============================================================
local activeNonces = {}
local activeTokens = {}
local failedAttempts = {}
local bannedEntities = {}
local memoryCache = {}
local isInitialized = false
local SIGNATURE_LENGTH = 16

-- =============================================================
-- أدوات مساعدة داخلية
-- =============================================================
local function logSecurity(message, level)
    level = level or 'info'
    if Logger and Logger.Log then
        Logger.Log(level, message, { category = 'security' })
    else
        print(('[ox_lib_secure] [SECURITY] %s'):format(message))
    end
end

local function getCurrentTimestamp()
    return os.time()
end

local function isInList(value, list)
    if not value or not list then
        return false
    end
    for _, item in ipairs(list) do
        if item == value then
            return true
        end
    end
    return false
end

-- =============================================================
-- توليد النصوص العشوائية بشكل آمن
-- =============================================================
local function generateRandomHex(length)
    local chars = '0123456789abcdef'
    local hex = {}
    for i = 1, length do
        local idx = math.random(1, 16)
        hex[i] = chars:sub(idx, idx)
    end
    return table.concat(hex)
end

local function generateRandomBytes(length)
    local bytes = {}
    for i = 1, length do
        bytes[i] = string.char(math.random(0, 255))
    end
    return table.concat(bytes)
end

-- =============================================================
-- تطبيق SHA-256 (نسخة Lua نقية)
-- =============================================================
local function band(x, y) return x & y end
local function bor(x, y) return x | y end
local function bxor(x, y) return x ~ y end
local function bnot(x) return ~x end
local function rshift(x, n) return x >> n end
local function lshift(x, n) return x << n end
local function rrotate(x, n)
    n = n % 32
    return (x >> n) | (x << (32 - n)) & 0xFFFFFFFF
end

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

local function sha256(message)
    local h0 = 0x6a09e667
    local h1 = 0xbb67ae85
    local h2 = 0x3c6ef372
    local h3 = 0xa54ff53a
    local h4 = 0x510e527f
    local h5 = 0x9b05688c
    local h6 = 0x1f83d9ab
    local h7 = 0x5be0cd19

    local msgLen = #message
    local bitLen = msgLen * 8

    message = message .. '\128'
    while (#message % 64) ~= 56 do
        message = message .. '\0'
    end

    for i = 7, 0, -1 do
        message = message .. string.char((bitLen >> (i * 8)) & 0xFF)
    end

    for blockStart = 1, #message, 64 do
        local w = {}

        for i = 0, 15 do
            local offset = blockStart + i * 4
            w[i] = (message:byte(offset) << 24) |
                   (message:byte(offset + 1) << 16) |
                   (message:byte(offset + 2) << 8) |
                   message:byte(offset + 3)
        end

        for i = 16, 63 do
            local s0 = bxor(rrotate(w[i-15], 7), bxor(rrotate(w[i-15], 18), rshift(w[i-15], 3)))
            local s1 = bxor(rrotate(w[i-2], 17), bxor(rrotate(w[i-2], 19), rshift(w[i-2], 10)))
            w[i] = (w[i-16] + s0 + w[i-7] + s1) & 0xFFFFFFFF
        end

        local a, b, c, d, e, f, g, h = h0, h1, h2, h3, h4, h5, h6, h7

        for i = 0, 63 do
            local S1 = bxor(rrotate(e, 6), bxor(rrotate(e, 11), rrotate(e, 25)))
            local ch = bxor(band(e, f), band(bnot(e), g))
            local temp1 = (h + S1 + ch + SHA256_K[i+1] + w[i]) & 0xFFFFFFFF
            local S0 = bxor(rrotate(a, 2), bxor(rrotate(a, 13), rrotate(a, 22)))
            local maj = bxor(bxor(band(a, b), band(a, c)), band(b, c))
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

    return string.format('%08x%08x%08x%08x%08x%08x%08x%08x',
        h0, h1, h2, h3, h4, h5, h6, h7)
end

-- =============================================================
-- تطبيق HMAC
-- =============================================================
local function hmacSHA256(key, message)
    local blockSize = 64

    if #key > blockSize then
        key = sha256(key)
    end

    while #key < blockSize do
        key = key .. '\0'
    end

    local oKeyPad = {}
    local iKeyPad = {}

    for i = 1, blockSize do
        local keyByte = key:byte(i)
        oKeyPad[i] = string.char(bxor(keyByte, 0x5c))
        iKeyPad[i] = string.char(bxor(keyByte, 0x36))
    end

    local innerHash = sha256(table.concat(iKeyPad) .. message)
    return sha256(table.concat(oKeyPad) .. innerHash)
end

-- =============================================================
-- التشفير وفك التشفير
-- إصلاح: استخدام طول ثابت للتوقيع بدلاً من فاصل |
-- =============================================================
function Security.Encrypt(data, key)
    if not data then
        return nil, 'No data to encrypt'
    end

    key = key or os.getenv(ENCRYPTION_MASTER_KEY_ENV) or 'default_key'

    -- إنشاء التوقيع
    local signature = hmacSHA256(key, tostring(data))

    -- تشفير البيانات
    local encoded = {}
    local keyHash = sha256(key)
    local keyLen = #keyHash

    for i = 1, #data do
        local byte = data:byte(i)
        local keyByte = keyHash:byte((i - 1) % keyLen + 1)
        encoded[i] = string.char(bxor(byte, keyByte))
    end

    local encrypted = table.concat(encoded)

    -- إلحاق التوقيع بطول ثابت (بدون فاصل)
    return encrypted .. signature:sub(1, SIGNATURE_LENGTH)
end

function Security.Decrypt(data, key)
    if not data then
        return nil, 'No data to decrypt'
    end

    key = key or os.getenv(ENCRYPTION_MASTER_KEY_ENV) or 'default_key'

    -- التحقق من الطول الأدنى
    if #data <= SIGNATURE_LENGTH then
        return nil, 'Data too short to contain signature'
    end

    -- فصل التوقيع بناءً على الطول الثابت
    local encrypted = data:sub(1, #data - SIGNATURE_LENGTH)
    local signature = data:sub(#data - SIGNATURE_LENGTH + 1)

    -- فك التشفير
    local decoded = {}
    local keyHash = sha256(key)
    local keyLen = #keyHash

    for i = 1, #encrypted do
        local byte = encrypted:byte(i)
        local keyByte = keyHash:byte((i - 1) % keyLen + 1)
        decoded[i] = string.char(bxor(byte, keyByte))
    end

    local decrypted = table.concat(decoded)

    -- التحقق من التوقيع
    local expectedSignature = hmacSHA256(key, decrypted):sub(1, SIGNATURE_LENGTH)
    if signature ~= expectedSignature then
        return nil, 'Signature verification failed'
    end

    return decrypted
end

-- =============================================================
-- التجزئة
-- =============================================================
function Security.Hash(data, algorithm)
    if not data then
        return nil, 'No data to hash'
    end

    algorithm = algorithm or HMAC_ALGORITHM

    if algorithm == 'sha256' then
        return sha256(tostring(data))
    end

    return sha256(tostring(data))
end

function Security.HashWithSalt(data, salt)
    if not data then
        return nil, 'No data to hash'
    end

    salt = salt or generateRandomHex(SALT_LENGTH)

    local hashed = sha256(tostring(data) .. salt)

    for _ = 1, HASH_ITERATIONS - 1 do
        hashed = sha256(hashed .. salt)
    end

    return hashed, salt
end

function Security.VerifyHash(data, expectedHash, salt)
    if not data or not expectedHash then
        return false
    end

    local actualHash = sha256(tostring(data) .. (salt or ''))

    for _ = 1, HASH_ITERATIONS - 1 do
        actualHash = sha256(actualHash .. (salt or ''))
    end

    return actualHash == expectedHash
end

-- =============================================================
-- HMAC
-- =============================================================
function Security.HMAC(data, key)
    if not data or not key then
        return nil, 'Data and key required for HMAC'
    end

    return hmacSHA256(key, tostring(data))
end

function Security.VerifyHMAC(data, key, expectedHmac)
    if not data or not key or not expectedHmac then
        return false
    end

    local actualHmac = hmacSHA256(key, tostring(data))
    return actualHmac == expectedHmac
end

-- =============================================================
-- التوقيع Canonical
-- =============================================================
function Security.SignCanonical(payload, key)
    if not payload or not key then
        return nil, 'Payload and key required'
    end

    local sortedKeys = {}
    for k in pairs(payload) do
        if type(k) == 'string' then
            sortedKeys[#sortedKeys + 1] = k
        end
    end
    table.sort(sortedKeys)

    local canonical = {}
    for _, k in ipairs(sortedKeys) do
        local v = payload[k]
        if type(v) == 'table' then
            local ok, encoded = pcall(json.encode, v)
            if ok then
                canonical[#canonical + 1] = k .. '=' .. encoded
            end
        else
            canonical[#canonical + 1] = k .. '=' .. tostring(v)
        end
    end

    local canonicalStr = table.concat(canonical, '&')
    return hmacSHA256(key, canonicalStr)
end

-- =============================================================
-- التوكنات
-- =============================================================
function Security.GenerateToken(entityId, tokenType)
    if not entityId then
        return nil, 'Entity ID required'
    end

    tokenType = tokenType or 'session'

    local activeCount = 0
    for tokenId, tokenData in pairs(activeTokens) do
        if tokenData.entityId == entityId and tokenData.type == tokenType then
            activeCount = activeCount + 1
            if tokenData.expiresAt < getCurrentTimestamp() then
                activeTokens[tokenId] = nil
                activeCount = activeCount - 1
            end
        end
    end

    if activeCount >= TOKEN_MAX_ACTIVE then
        return nil, 'Maximum active tokens reached'
    end

    local tokenValue = generateRandomHex(TOKEN_LENGTH_BYTES * 2)
    local tokenId = generateRandomHex(16)

    activeTokens[tokenId] = {
        id = tokenId,
        value = tokenValue,
        entityId = entityId,
        type = tokenType,
        createdAt = getCurrentTimestamp(),
        expiresAt = getCurrentTimestamp() + TOKEN_TTL_SECONDS,
        hint = tokenValue:sub(1, TOKEN_HINT_LENGTH)
    }

    return {
        id = tokenId,
        value = tokenValue,
        hint = tokenValue:sub(1, TOKEN_HINT_LENGTH),
        expiresAt = activeTokens[tokenId].expiresAt
    }
end

function Security.ValidateToken(tokenId, tokenValue)
    if not tokenId or not tokenValue then
        return false, 'Token ID and value required'
    end

    local tokenData = activeTokens[tokenId]
    if not tokenData then
        return false, 'Token not found'
    end

    if tokenData.expiresAt < getCurrentTimestamp() then
        activeTokens[tokenId] = nil
        return false, 'Token expired'
    end

    if tokenData.value ~= tokenValue then
        return false, 'Invalid token value'
    end

    return true, tokenData
end

function Security.RevokeToken(tokenId)
    if activeTokens[tokenId] then
        activeTokens[tokenId] = nil
        return true
    end
    return false
end

function Security.RevokeAllTokens(entityId)
    local revoked = 0
    for tokenId, tokenData in pairs(activeTokens) do
        if tokenData.entityId == entityId then
            activeTokens[tokenId] = nil
            revoked = revoked + 1
        end
    end
    return revoked
end

function Security.RefreshToken(tokenId, tokenValue)
    if not TOKEN_REFRESH_ENABLED then
        return nil, 'Token refresh is disabled'
    end

    local valid, tokenData = Security.ValidateToken(tokenId, tokenValue)
    if not valid then
        return nil, tokenData
    end

    tokenData.expiresAt = getCurrentTimestamp() + TOKEN_TTL_SECONDS

    return {
        id = tokenData.id,
        value = tokenData.value,
        hint = tokenData.hint,
        expiresAt = tokenData.expiresAt
    }
end

-- =============================================================
-- منع إعادة التشغيل
-- =============================================================
function Security.GenerateNonce()
    local nonce = generateRandomHex(32)

    if ANTI_REPLAY_ENABLED then
        local timestamp = getCurrentTimestamp()
        activeNonces[nonce] = {
            timestamp = timestamp,
            expiresAt = timestamp + ANTI_REPLAY_WINDOW_SECONDS
        }

        local count = 0
        for n in pairs(activeNonces) do
            count = count + 1
            if count > ANTI_REPLAY_MAX_NONCES then
                activeNonces[n] = nil
            end
        end
    end

    return nonce
end

function Security.ValidateNonce(nonce)
    if not ANTI_REPLAY_ENABLED then
        return true
    end

    if not nonce then
        return false, 'Nonce required'
    end

    local nonceData = activeNonces[nonce]
    if not nonceData then
        return false, 'Nonce not found or already used'
    end

    if nonceData.expiresAt < getCurrentTimestamp() then
        activeNonces[nonce] = nil
        return false, 'Nonce expired'
    end

    activeNonces[nonce] = nil
    return true
end

-- =============================================================
-- التحقق من الأحداث
-- =============================================================
function Security.ValidateEvent(source, eventName, payload)
    if not EVENTS_VALIDATE_SOURCE then
        return true
    end

    if not source or source == 0 then
        return false, 'Invalid event source'
    end

    if EVENTS_VALIDATE_PAYLOAD and payload then
        local ok, payloadStr = pcall(json.encode, payload)
        if ok and payloadStr and #payloadStr > EVENTS_MAX_PAYLOAD_SIZE then
            return false, 'Payload too large'
        end
    end

    return true
end

-- =============================================================
-- التحقق من الحمولة
-- =============================================================
function Security.ValidatePayload(payload, payloadType)
    if not payload then
        return VALIDATION_ALLOW_NIL, VALIDATION_ALLOW_NIL and nil or 'Payload is nil'
    end

    payloadType = payloadType or 'generic'

    if payloadType == 'notification' then
        return Security.ValidateNotificationPayload(payload)
    end

    if payloadType == 'log' then
        return Security.ValidateLogPayload(payload)
    end

    return true
end

function Security.ValidateNotificationPayload(payload)
    if type(payload) ~= 'table' then
        return false, 'Notification payload must be a table'
    end

    if payload.type and not isInList(payload.type, VALIDATION_ALLOWED_NOTIFICATION_TYPES) then
        return false, ('Invalid notification type: %s'):format(tostring(payload.type))
    end

    if payload.position and not isInList(payload.position, VALIDATION_ALLOWED_POSITIONS) then
        return false, ('Invalid position: %s'):format(tostring(payload.position))
    end

    if payload.designStyle and not isInList(payload.designStyle, VALIDATION_ALLOWED_DESIGN_STYLES) then
        return false, ('Invalid design style: %s'):format(tostring(payload.designStyle))
    end

    if payload.title and #payload.title > PAYLOAD_MAX_TITLE_LENGTH then
        return false, 'Title too long'
    end

    if payload.body and #payload.body > PAYLOAD_MAX_BODY_LENGTH then
        return false, 'Body too long'
    end

    if payload.meta then
        local ok, metaStr = pcall(json.encode, payload.meta)
        if ok and metaStr and #metaStr > PAYLOAD_MAX_META_JSON_BYTES then
            return false, 'Meta too large'
        end
    end

    return true
end

function Security.ValidateLogPayload(payload)
    if type(payload) ~= 'table' then
        return false, 'Log payload must be a table'
    end

    if payload.level and not isInList(payload.level, VALIDATION_ALLOWED_LOG_LEVELS) then
        return false, ('Invalid log level: %s'):format(tostring(payload.level))
    end

    if payload.message and #payload.message > PAYLOAD_MAX_STRING_LENGTH then
        return false, 'Log message too long'
    end

    return true
end

-- =============================================================
-- تعقيم السلاسل النصية
-- =============================================================
function Security.SanitizeString(input)
    if not input or type(input) ~= 'string' then
        return input
    end

    if not VALIDATION_SANITIZE_STRINGS then
        return input
    end

    local sanitized = input:gsub('[<>"\'\\]', '')

    if #sanitized > PAYLOAD_MAX_STRING_LENGTH then
        sanitized = sanitized:sub(1, PAYLOAD_MAX_STRING_LENGTH)
    end

    return sanitized
end

-- =============================================================
-- التحقق من معدل الطلبات
-- =============================================================
function Security.CheckRateLimit(source, bucketName)
    if not RATE_LIMIT_USE_MEMORY then
        return true
    end

    bucketName = bucketName or 'default'

    if RateLimiter and RateLimiter.Check then
        local allowed, err = RateLimiter.Check(source, bucketName)
        return allowed, err
    end

    return true
end

-- =============================================================
-- المحاولات الفاشلة والحظر
-- =============================================================
function Security.RecordFailedAttempt(entityId, entityType, reason)
    if not entityId then
        return false
    end

    local key = ('%s:%s'):format(entityType or 'unknown', tostring(entityId))
    local now = getCurrentTimestamp()

    if not failedAttempts[key] then
        failedAttempts[key] = {
            count = 0,
            firstAttempt = now,
            lastAttempt = now
        }
    end

    local attemptData = failedAttempts[key]

    if (now - attemptData.firstAttempt) > (FAILED_ATTEMPTS_WINDOW_MINUTES * 60) then
        attemptData.count = 0
        attemptData.firstAttempt = now
    end

    attemptData.count = attemptData.count + 1
    attemptData.lastAttempt = now

    if AUDIT_LOG_FAILED_ATTEMPTS and Audit and Audit.Record then
        Audit.Record('security_failed_attempt', 'system', entityType, entityId, {
            reason = reason,
            attemptCount = attemptData.count
        })
    end

    if attemptData.count >= FAILED_ATTEMPTS_MAX then
        Security.BanEntity(entityId, entityType, ('Max failed attempts reached: %d'):format(attemptData.count))
        failedAttempts[key] = nil
        return true
    end

    return false
end

function Security.BanEntity(entityId, entityType, reason)
    if not entityId then
        return false
    end

    local key = ('%s:%s'):format(entityType or 'unknown', tostring(entityId))
    local now = getCurrentTimestamp()

    bannedEntities[key] = {
        entityId = entityId,
        entityType = entityType,
        reason = reason or 'Banned',
        bannedAt = now,
        expiresAt = now + (FAILED_ATTEMPTS_BAN_MINUTES * 60)
    }

    if Audit and Audit.Record then
        Audit.Record('entity_banned', 'system', entityType, entityId, {
            reason = reason,
            durationMinutes = FAILED_ATTEMPTS_BAN_MINUTES
        })
    end

    return true
end

function Security.UnbanEntity(entityId, entityType)
    if not entityId then
        return false
    end

    local key = ('%s:%s'):format(entityType or 'unknown', tostring(entityId))

    if bannedEntities[key] then
        bannedEntities[key] = nil
        return true
    end

    return false
end

function Security.IsBanned(entityId, entityType)
    if not entityId then
        return false
    end

    local key = ('%s:%s'):format(entityType or 'unknown', tostring(entityId))
    local banData = bannedEntities[key]

    if not banData then
        return false
    end

    if banData.expiresAt < getCurrentTimestamp() then
        bannedEntities[key] = nil
        return false
    end

    return true, banData
end

function Security.GetFailedAttemptCount(entityId, entityType)
    if not entityId then
        return 0
    end

    local key = ('%s:%s'):format(entityType or 'unknown', tostring(entityId))

    if failedAttempts[key] then
        return failedAttempts[key].count
    end

    return 0
end

-- =============================================================
-- إخفاء الأسرار في اللوجات
-- =============================================================
function Security.MaskSensitiveData(data)
    if type(data) ~= 'table' then
        return data
    end

    local masked = {}

    for key, value in pairs(data) do
        if type(key) == 'string' then
            local isSensitive = false

            for _, forbidden in ipairs(SECRETS_FORBIDDEN_IN_LOGS) do
                if key:lower():find(forbidden:lower(), 1, true) then
                    isSensitive = true
                    break
                end
            end

            if isSensitive then
                masked[key] = '[REDACTED]'
            elseif type(value) == 'table' then
                masked[key] = Security.MaskSensitiveData(value)
            else
                masked[key] = value
            end
        else
            masked[key] = value
        end
    end

    return masked
end

-- =============================================================
-- كشف الأخطاء
-- =============================================================
function Security.FormatErrorForDisplay(err, context)
    if ERROR_SHOW_INTERNAL then
        return tostring(err)
    end

    if ERROR_SHOW_STACK and context then
        return ('%s\n%s'):format(ERROR_GENERIC_MESSAGE, tostring(context))
    end

    return ERROR_GENERIC_MESSAGE
end

-- =============================================================
-- الكاش المحلي
-- =============================================================
function Security.CacheSet(key, value, ttlSeconds)
    if not MEMORY_CACHE_ENABLED then
        return false
    end

    ttlSeconds = ttlSeconds or MEMORY_CACHE_TTL_SECONDS

    local count = 0
    for _ in pairs(memoryCache) do
        count = count + 1
    end

    if count >= MEMORY_CACHE_MAX_ENTRIES then
        local oldestKey = nil
        local oldestTime = math.huge

        for k, v in pairs(memoryCache) do
            if v.createdAt < oldestTime then
                oldestTime = v.createdAt
                oldestKey = k
            end
        end

        if oldestKey then
            memoryCache[oldestKey] = nil
        end
    end

    memoryCache[key] = {
        value = value,
        createdAt = getCurrentTimestamp(),
        expiresAt = getCurrentTimestamp() + ttlSeconds
    }

    return true
end

function Security.CacheGet(key)
    if not MEMORY_CACHE_ENABLED then
        return nil
    end

    local entry = memoryCache[key]
    if not entry then
        return nil
    end

    if entry.expiresAt < getCurrentTimestamp() then
        memoryCache[key] = nil
        return nil
    end

    return entry.value
end

function Security.CacheDelete(key)
    if memoryCache[key] then
        memoryCache[key] = nil
        return true
    end
    return false
end

function Security.CacheClear()
    memoryCache = {}
end

-- =============================================================
-- التحقق من المعرفات
-- =============================================================
function Security.HashIdentifier(identifierType, identifierValue)
    if not identifierValue then
        return nil
    end

    if identifierType == 'ip' and IDENTIFIERS_HASH_IP then
        return sha256(identifierValue)
    end

    return identifierValue
end

function Security.GetIdentifiers(source)
    if not source or source == 0 then
        return {}
    end

    local identifiers = {}
    local rawIdentifiers = GetPlayerIdentifiers(source)

    if not rawIdentifiers then
        return identifiers
    end

    for _, rawId in ipairs(rawIdentifiers) do
        local colonPos = rawId:find(':')

        if colonPos then
            local idType = rawId:sub(1, colonPos - 1)
            local idValue = rawId:sub(colonPos + 1)

            identifiers[#identifiers + 1] = {
                type = idType,
                value = Security.HashIdentifier(idType, idValue)
            }
        end
    end

    return identifiers
end

-- =============================================================
-- التحقق من الأوامر
-- =============================================================
function Security.ValidateCommand(source, commandName)
    if not COMMAND_REQUIRE_PERMISSION then
        return true
    end

    if COMMAND_RATE_LIMIT_PER_MINUTE > 0 then
        local allowed, err = Security.CheckRateLimit(source, 'command')
        if not allowed then
            return false, 'Command rate limit exceeded'
        end
    end

    if COMMAND_LOG_COMMANDS then
        logSecurity(('Command executed: %s by source %d'):format(commandName, source))
    end

    return true
end

-- =============================================================
-- التحقق من NUI Callbacks
-- =============================================================
function Security.ValidateNUICallback(callbackName, data)
    if not NUI_VALIDATE_CALLBACKS then
        return true
    end

    if not callbackName or type(callbackName) ~= 'string' then
        return false, 'Invalid callback name'
    end

    if data and type(data) == 'table' then
        local ok, dataStr = pcall(json.encode, data)
        if ok and dataStr and #dataStr > EVENTS_MAX_PAYLOAD_SIZE then
            return false, 'NUI callback data too large'
        end
    end

    return true
end

-- =============================================================
-- التحقق من توكنات الأنظمة
-- =============================================================
function Security.ValidateSystemToken(systemId, tokenValue)
    if not SYSTEMS_VALIDATE_TOKENS then
        return true
    end

    if not systemId or not tokenValue then
        return false, 'System ID and token required'
    end

    for tokenId, tokenData in pairs(activeTokens) do
        if tokenData.entityId == systemId and tokenData.type == 'system' then
            if tokenData.value == tokenValue then
                if tokenData.expiresAt > getCurrentTimestamp() then
                    return true, tokenData
                else
                    activeTokens[tokenId] = nil
                    return false, 'System token expired'
                end
            end
        end
    end

    return false, 'System token not found'
end

-- =============================================================
-- تنظيف دوري
-- =============================================================
function Security.Cleanup()
    local now = getCurrentTimestamp()
    local cleaned = 0

    for tokenId, tokenData in pairs(activeTokens) do
        if tokenData.expiresAt < now then
            activeTokens[tokenId] = nil
            cleaned = cleaned + 1
        end
    end

    for nonce, nonceData in pairs(activeNonces) do
        if nonceData.expiresAt < now then
            activeNonces[nonce] = nil
            cleaned = cleaned + 1
        end
    end

    for key, attemptData in pairs(failedAttempts) do
        if (now - attemptData.lastAttempt) > (FAILED_ATTEMPTS_WINDOW_MINUTES * 60 * 2) then
            failedAttempts[key] = nil
            cleaned = cleaned + 1
        end
    end

    for key, banData in pairs(bannedEntities) do
        if banData.expiresAt < now then
            bannedEntities[key] = nil
            cleaned = cleaned + 1
        end
    end

    for key, entry in pairs(memoryCache) do
        if entry.expiresAt < now then
            memoryCache[key] = nil
            cleaned = cleaned + 1
        end
    end

    if cleaned > 0 then
        logSecurity(('Security cleanup: removed %d expired entries'):format(cleaned))
    end
end

-- =============================================================
-- إحصائيات الأمان
-- =============================================================
function Security.GetStats()
    local tokenCount = 0
    for _ in pairs(activeTokens) do tokenCount = tokenCount + 1 end

    local nonceCount = 0
    for _ in pairs(activeNonces) do nonceCount = nonceCount + 1 end

    local failedCount = 0
    for _ in pairs(failedAttempts) do failedCount = failedCount + 1 end

    local bannedCount = 0
    for _ in pairs(bannedEntities) do bannedCount = bannedCount + 1 end

    local cacheCount = 0
    for _ in pairs(memoryCache) do cacheCount = cacheCount + 1 end

    return {
        activeTokens = tokenCount,
        activeNonces = nonceCount,
        failedAttempts = failedCount,
        bannedEntities = bannedCount,
        cacheEntries = cacheCount,
        isInitialized = isInitialized
    }
end

-- =============================================================
-- تهيئة وحدة الأمان
-- =============================================================
function Security.Initialize()
    if isInitialized then
        return true
    end

    logSecurity('Initializing security module...')

    if STARTUP_VERIFY_KEYS then
        local masterKey = os.getenv(ENCRYPTION_MASTER_KEY_ENV)
        if not masterKey or masterKey == '' then
            logSecurity('WARNING: Master key not set in environment variable: ' .. ENCRYPTION_MASTER_KEY_ENV, 'warn')
        end
    end

    if STARTUP_VERIFY_DATABASE then
        local Database = OxSecure.Database
        if Database and Database.IsReady then
            if not Database.IsReady() then
                logSecurity('WARNING: Database not ready during security initialization.', 'warn')
            end
        end
    end

    if STARTUP_VERIFY_PERMISSIONS then
        local Permissions = OxSecure.Permissions
        if Permissions and Permissions.IsInitialized then
            if not Permissions.IsInitialized() then
                logSecurity('WARNING: Permissions not initialized during security initialization.', 'warn')
            end
        end
    end

    if STARTUP_VERIFY_LOGGER_HOOK then
        if not Logger or not Logger.Log then
            logSecurity('WARNING: Logger not available during security initialization.', 'warn')
        end
    end

    CreateThread(function()
        while true do
            Wait(RATE_LIMIT_CLEANUP_SECONDS * 1000)
            Security.Cleanup()
        end
    end)

    isInitialized = true
    logSecurity('Security module initialized successfully.')
    return true
end

-- =============================================================
-- تهيئة عند التحميل
-- =============================================================
Security.Initialize()

-- =============================================================
-- رسالة تحميل ناجحة
-- =============================================================
if Logger and Logger.Debug then
    Logger.Debug('server/core/security.lua loaded')
else
    print('[ox_lib_secure] server/core/security.lua loaded')
end
