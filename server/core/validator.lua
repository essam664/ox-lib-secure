-- =============================================================
-- ox_lib_secure
-- File: server/core/validator.lua
-- Description:
--   طبقة التحقق من المدخلات لنظام ox_lib_secure.
--
-- Notes:
--   - هذه الطبقة تستخدم Security وUtils.
--   - لا يتم هنا تنفيذ الصلاحيات النهائية.
--   - الصلاحيات يتم فحصها لاحقًا في طبقة Permissions.
--   - أي مدخل قادم من الكلاينت يجب أن يمر من هنا.
-- =============================================================

Config = Config or {}
OxSecure = OxSecure or {}
OxSecure.Validator = OxSecure.Validator or {}

local Validator = OxSecure.Validator
local Security = OxSecure.Security or {}
local Utils = OxSecure.Utils or {}

local playersConfig = Config.Players or {}
local logsConfig = Config.Logs or {}
local securityConfig = Config.Security or {}
local payloadLimits = securityConfig.PayloadLimits or {}

local MAX_SERVER_ID = 65535
local MAX_RAW_INPUT_LENGTH = 10000

-- =============================================================
-- أدوات مساعدة داخلية
-- =============================================================
local function invalid(field, code)
    return false, {
        code = code or 'ERR_VALIDATION_FAILED',
        field = field
    }
end

-- =============================================================
-- إصلاح 1:
-- فحص نوع القيمة قبل تمريرها إلى Security.SanitizeText.
-- إذا كانت القيمة غير نصية، يتم تحويلها إلى نص أو إرجاع فارغ.
-- =============================================================
local function cleanText(value, maxLength)
    if type(value) ~= 'string' then
        if value == nil then
            return ''
        end

        value = tostring(value)
    end

    if Security.SanitizeText then
        return Security.SanitizeText(value, {
            maxLength = maxLength
        })
    end

    return value:sub(1, maxLength or 500)
end

-- التحقق من وجود دالة في Security قبل استدعائها
local function securityFunctionExists(fnName)
    return type(Security[fnName]) == 'function'
end

-- =============================================================
-- التحقق من القيم الأساسية
-- =============================================================
function Validator.IsPositiveInteger(value)
    local numberValue = tonumber(value)

    if not numberValue then
        return false
    end

    if numberValue <= 0 then
        return false
    end

    -- إصلاح 3: استخدام % 1 بدلاً من math.type
    if numberValue % 1 ~= 0 then
        return false
    end

    return true
end

-- =============================================================
-- إصلاح 3:
-- استخدام serverId % 1 == 0 بدلاً من math.type
-- لقبول الأرقام الصحيحة حتى لو كانت مخزنة كـ float.
-- =============================================================
function Validator.IsServerIdValid(source)
    local serverId = tonumber(source)

    if not serverId then
        return false
    end

    if serverId <= 0 then
        return false
    end

    if serverId > MAX_SERVER_ID then
        return false
    end

    -- التحقق من أنها عدد صحيح بدون كسور
    if serverId % 1 ~= 0 then
        return false
    end

    return true, math.floor(serverId)
end

function Validator.ValidateDiscordId(value)
    if type(value) == 'number' then
        value = tostring(math.floor(value))
    end

    if type(value) ~= 'string' then
        return false, nil
    end

    local discordId = value:match('^%s*(%d+)%s*$')

    if not discordId then
        return false, nil
    end

    if #discordId < 15 or #discordId > 25 then
        return false, nil
    end

    return true, discordId
end

function Validator.IsAllowedIdentifierType(identifierType)
    if type(identifierType) ~= 'string' then
        return false
    end

    local allowedTypes = playersConfig.AllowedIdentifierTypes or {}

    if Utils.Contains then
        return Utils.Contains(allowedTypes, identifierType)
    end

    for _, allowedType in ipairs(allowedTypes) do
        if allowedType == identifierType then
            return true
        end
    end

    return false
end

function Validator.ValidateIdentifierValue(value)
    if type(value) ~= 'string' then
        return false, nil
    end

    local cleaned = cleanText(value, 255)

    if cleaned == '' then
        return false, nil
    end

    return true, cleaned
end

-- =============================================================
-- استخراج معرفات اللاعب
-- =============================================================
function Validator.GetPlayerIdentifiers(serverId)
    local result = {}

    if not Validator.IsServerIdValid(serverId) then
        return result
    end

    if type(GetPlayerIdentifiers) ~= 'function' then
        return result
    end

    local rawIdentifiers = GetPlayerIdentifiers(tostring(serverId))

    if type(rawIdentifiers) ~= 'table' then
        return result
    end

    for _, rawIdentifier in ipairs(rawIdentifiers) do
        if type(rawIdentifier) == 'string' then
            local identifierType, identifierValue = rawIdentifier:match('^([^:]+):(.+)$')

            if identifierType and identifierValue then
                identifierType = identifierType:lower()

                if Validator.IsAllowedIdentifierType(identifierType) then
                    local ok, cleanValue = Validator.ValidateIdentifierValue(identifierValue)

                    if ok then
                        result[#result + 1] = {
                            type = identifierType,
                            value = cleanValue
                        }
                    end
                end
            end
        end
    end

    return result
end

-- =============================================================
-- اختيار المعرف الأساسي
-- =============================================================
function Validator.ChoosePrimaryIdentifier(identifiers)
    if type(identifiers) ~= 'table' or #identifiers == 0 then
        return nil, nil
    end

    local priority = playersConfig.PrimaryIdentifierPriority or {}
    local byType = {}

    for _, identifier in ipairs(identifiers) do
        if identifier.type and identifier.value then
            byType[identifier.type] = identifier.value
        end
    end

    for _, preferredType in ipairs(priority) do
        if byType[preferredType] then
            return preferredType, byType[preferredType]
        end
    end

    -- إذا لم يوجد نوع مفضل، نأخذ أول معرف صالح.
    local first = identifiers[1]

    if first and first.type and first.value then
        return first.type, first.value
    end

    return nil, nil
end

-- =============================================================
-- التحقق من مصدر اللاعب
-- =============================================================
function Validator.ValidatePlayerSource(source, options)
    options = options or {}

    local okServerId, serverId = Validator.IsServerIdValid(source)

    if not okServerId then
        return invalid('source', 'ERR_PLAYER_NOT_FOUND')
    end

    local playerName = nil

    if options.requireOnline ~= false then
        if type(GetPlayerName) ~= 'function' then
            return invalid('source', 'ERR_PLAYER_NOT_FOUND')
        end

        playerName = GetPlayerName(tostring(serverId))

        if not playerName then
            return invalid('source', 'ERR_PLAYER_NOT_FOUND')
        end
    end

    local identifiers = Validator.GetPlayerIdentifiers(serverId)

    if options.requireIdentifiers ~= false and #identifiers == 0 then
        return invalid('identifiers', 'ERR_PLAYER_NOT_FOUND')
    end

    local primaryType, primaryValue = Validator.ChoosePrimaryIdentifier(identifiers)

    if options.requireIdentifiers ~= false and not primaryType then
        return invalid('primaryIdentifier', 'ERR_PLAYER_NOT_FOUND')
    end

    local sanitizedPlayerName = cleanText(playerName or '', 100)

    return true, {
        serverId = serverId,
        name = sanitizedPlayerName,
        identifiers = identifiers,
        primaryIdentifierType = primaryType,
        primaryIdentifierValue = primaryValue
    }
end

-- =============================================================
-- التحقق من مدة الظهور
-- =============================================================
function Validator.ValidateDurationMs(value, minValue, maxValue)
    minValue = minValue or 1000
    maxValue = maxValue or 30000

    local numberValue = tonumber(value)

    if not numberValue then
        return false, nil
    end

    numberValue = math.floor(numberValue)

    if numberValue < minValue then
        numberValue = minValue
    end

    if numberValue > maxValue then
        numberValue = maxValue
    end

    return true, numberValue
end

-- =============================================================
-- التحقق من طلب إشعار
-- =============================================================
function Validator.ValidateNotificationRequest(payload)
    if type(payload) ~= 'table' then
        return invalid('payload', 'ERR_INVALID_PAYLOAD')
    end

    if not securityFunctionExists('ValidateNotificationPayload') then
        return invalid('internal', 'ERR_INTERNAL_VALIDATOR_MISSING')
    end

    local ok, normalized = Security.ValidateNotificationPayload(payload)

    if not ok then
        return false, normalized
    end

    local rawSource = payload.source or payload.serverId or payload.playerServerId
    local isBroadcast = payload.broadcast == true

    -- رفض الطلب إذا اجتمع broadcast مع source
    if isBroadcast and rawSource ~= nil then
        return invalid('broadcast', 'ERR_INVALID_PAYLOAD')
    end

    if isBroadcast then
        normalized.broadcast = true
        return true, normalized
    end

    if rawSource == nil then
        return invalid('source', 'ERR_MISSING_FIELD')
    end

    local okPlayer, player = Validator.ValidatePlayerSource(rawSource, {
        requireOnline = true,
        requireIdentifiers = true
    })

    if not okPlayer then
        return false, player
    end

    normalized.serverId = player.serverId
    normalized.playerName = player.name
    normalized.primaryIdentifierType = player.primaryIdentifierType
    normalized.primaryIdentifierValue = player.primaryIdentifierValue
    normalized.broadcast = false

    return true, normalized
end

-- =============================================================
-- التحقق من طلب خطأ
-- =============================================================
function Validator.ValidateErrorRequest(payload)
    if type(payload) ~= 'table' then
        return invalid('payload', 'ERR_INVALID_PAYLOAD')
    end

    if not securityFunctionExists('ValidateErrorPayload') then
        return invalid('internal', 'ERR_INTERNAL_VALIDATOR_MISSING')
    end

    local ok, normalized = Security.ValidateErrorPayload(payload)

    if not ok then
        return false, normalized
    end

    normalized.serverId = nil
    normalized.playerName = nil
    normalized.primaryIdentifierType = nil
    normalized.primaryIdentifierValue = nil

    local rawSource = payload.source or payload.serverId or payload.playerServerId

    if rawSource ~= nil then
        local okPlayer, player = Validator.ValidatePlayerSource(rawSource, {
            requireOnline = false,
            requireIdentifiers = false
        })

        if not okPlayer then
            return false, player
        end

        normalized.serverId = player.serverId
        normalized.playerName = player.name
        normalized.primaryIdentifierType = player.primaryIdentifierType
        normalized.primaryIdentifierValue = player.primaryIdentifierValue
    end

    return true, normalized
end

-- =============================================================
-- التحقق من طلب لوج
--
-- إصلاح 2:
-- التحقق من أن payload.message نصي قبل تمريره إلى cleanText.
-- =============================================================
function Validator.ValidateLogRequest(payload)
    if type(payload) ~= 'table' then
        return invalid('payload', 'ERR_INVALID_PAYLOAD')
    end

    local level = payload.level or 'info'

    if type(level) ~= 'string' then
        return invalid('level', 'ERR_INVALID_LEVEL')
    end

    if securityFunctionExists('IsAllowedLogLevel') and not Security.IsAllowedLogLevel(level) then
        return invalid('level', 'ERR_INVALID_LEVEL')
    end

    local category = cleanText(payload.category or 'general', 50)

    if category == '' then
        category = 'general'
    end

    local eventCode = cleanText(payload.eventCode or payload.event or 'general', 100)

    if eventCode == '' then
        eventCode = 'general'
    end

    -- إصلاح 2: التحقق من أن message موجود ونصي
    if payload.message == nil then
        return invalid('message', 'ERR_MISSING_FIELD')
    end

    if type(payload.message) ~= 'string' then
        return invalid('message', 'ERR_INVALID_FIELD')
    end

    local maxMessageLength = logsConfig.MaxMessageLength or payloadLimits.MaxMessageLength or 2000
    local message = cleanText(payload.message, maxMessageLength)

    if message == '' then
        return invalid('message', 'ERR_EMPTY_MESSAGE')
    end

    local systemCode = nil

    if payload.systemCode ~= nil then
        systemCode = cleanText(payload.systemCode, 64)

        if systemCode == '' then
            systemCode = nil
        end
    end

    local serverPlayerId = nil

    if payload.source ~= nil or payload.serverPlayerId ~= nil then
        local rawSource = payload.source or payload.serverPlayerId
        local okServerId, serverId = Validator.IsServerIdValid(rawSource)

        if okServerId then
            serverPlayerId = serverId
        end
    end

    -- التحقق من meta إذا كانت موجودة
    local validatedMeta = nil

    if payload.meta ~= nil then
        if not securityFunctionExists('ValidateMeta') then
            return invalid('internal', 'ERR_INTERNAL_VALIDATOR_MISSING')
        end

        local okMeta, metaOrError = Security.ValidateMeta(payload.meta)

        if not okMeta then
            return false, metaOrError
        end

        validatedMeta = metaOrError
    end

    -- بناء الجدول النهائي في مكان واحد
    return true, {
        level = level,
        category = category,
        eventCode = eventCode,
        message = message,
        systemCode = systemCode,
        serverPlayerId = serverPlayerId,
        meta = validatedMeta,
        isPublic = payload.isPublic == true
    }
end

-- =============================================================
-- التحقق من طلب نظام مربوط
--
-- إصلاح 4:
-- التحقق من نوع القيمة قبل فحص الطول الخام.
-- =============================================================
function Validator.ValidateSystemCall(payload)
    if type(payload) ~= 'table' then
        return invalid('payload', 'ERR_INVALID_PAYLOAD')
    end

    -- إصلاح 4: التحقق من النوع والطول الخام لـ systemCode
    if payload.systemCode == nil then
        return invalid('systemCode', 'ERR_MISSING_FIELD')
    end

    if type(payload.systemCode) ~= 'string' and type(payload.systemCode) ~= 'number' then
        return invalid('systemCode', 'ERR_INVALID_FIELD')
    end

    local rawSystemCode = tostring(payload.systemCode)

    if #rawSystemCode > MAX_RAW_INPUT_LENGTH then
        return invalid('systemCode', 'ERR_FIELD_TOO_LONG')
    end

    local systemCode = cleanText(rawSystemCode, 64)

    if systemCode == '' then
        return invalid('systemCode', 'ERR_MISSING_FIELD')
    end

    -- إصلاح 4: التحقق من النوع والطول الخام لـ scope
    if payload.scope == nil then
        return invalid('scope', 'ERR_MISSING_FIELD')
    end

    if type(payload.scope) ~= 'string' and type(payload.scope) ~= 'number' then
        return invalid('scope', 'ERR_INVALID_FIELD')
    end

    local rawScope = tostring(payload.scope)

    if #rawScope > MAX_RAW_INPUT_LENGTH then
        return invalid('scope', 'ERR_FIELD_TOO_LONG')
    end

    local scope = cleanText(rawScope, 100)

    if scope == '' then
        return invalid('scope', 'ERR_MISSING_FIELD')
    end

    local nonce = nil

    if payload.nonce ~= nil then
        if type(payload.nonce) ~= 'string' or payload.nonce == '' then
            return invalid('nonce', 'ERR_INVALID_FIELD')
        end

        if #payload.nonce > MAX_RAW_INPUT_LENGTH then
            return invalid('nonce', 'ERR_FIELD_TOO_LONG')
        end

        nonce = cleanText(payload.nonce, 64)
    end

    local timestamp = nil

    if payload.timestamp ~= nil then
        local timestampNumber = tonumber(payload.timestamp)

        if not timestampNumber then
            return invalid('timestamp', 'ERR_INVALID_FIELD')
        end

        timestamp = math.floor(timestampNumber)
    end

    local data = nil

    if payload.data ~= nil then
        if type(payload.data) ~= 'table' then
            return invalid('data', 'ERR_INVALID_PAYLOAD')
        end

        if not securityFunctionExists('ValidateMeta') then
            return invalid('internal', 'ERR_INTERNAL_VALIDATOR_MISSING')
        end

        local okMeta, metaOrError = Security.ValidateMeta(payload.data)

        if not okMeta then
            return false, metaOrError
        end

        data = metaOrError
    end

    return true, {
        systemCode = systemCode,
        scope = scope,
        nonce = nonce,
        timestamp = timestamp,
        data = data
    }
end

-- =============================================================
-- التحقق من طلب فتح اللوحة
-- =============================================================
function Validator.ValidatePanelRequest(source)
    local okPlayer, player = Validator.ValidatePlayerSource(source, {
        requireOnline = true,
        requireIdentifiers = true
    })

    if not okPlayer then
        return false, player
    end

    return true, player
end

-- =============================================================
-- التحقق من مصدر أمر
-- =============================================================
function Validator.ValidateCommandSource(source)
    local okPlayer, player = Validator.ValidatePlayerSource(source, {
        requireOnline = true,
        requireIdentifiers = true
    })

    if not okPlayer then
        return false, player
    end

    return true, player
end

-- =============================================================
-- رسالة تحميل ناجحة
-- =============================================================
if OxSecure.Console and type(OxSecure.Console.debug) == 'function' then
    OxSecure.Console.debug('server/core/validator.lua loaded')
end
