-- =============================================================
-- ox_lib_secure
-- File: server/core/validator.lua
-- Description:
--   وحدة التحقق من المدخلات لنظام ox_lib_secure.
--   تتحقق من صحة البيانات قبل معالجتها.
--
-- Notes:
--   - مواءمة 100% مع config/main.lua النهائي.
--   - تقرأ القوائم المسموحة من Config.UI و Config.Logs.
--   - تدعم التحقق من المعرفات والإشعارات واللوجات.
--   - حماية من الحقن والتجاوز.
-- =============================================================

Config = Config or {}
OxSecure = OxSecure or {}
OxSecure.Validator = OxSecure.Validator or {}

local Validator = OxSecure.Validator
local Logger = OxSecure.Logger or {}
local Security = OxSecure.Security or {}

-- =============================================================
-- قراءة الإعدادات من الكونفق
-- متوافقة حرفيًا مع config/main.lua
-- =============================================================
local uiConfig = Config.UI or {}
local logsConfig = Config.Logs or {}
local playersConfig = Config.Players or {}
local securityConfig = Config.Security or {}
local validationConfig = securityConfig.Validation or {}

-- القوائم المسموحة من الكونفق
local ALLOWED_POSITIONS = uiConfig.AllowedPositions or {
    'left', 'right', 'center', 'top', 'bottom'
}

local ALLOWED_NOTIFICATION_TYPES = uiConfig.AllowedNotificationTypes or {
    'info', 'success', 'warning', 'error', 'critical', 'system'
}

local ALLOWED_DESIGN_STYLES = uiConfig.AllowedDesignStyles or {
    'default', 'purple_glass', 'glass', 'solid', 'gradient',
    'error', 'warning', 'success', 'info', 'critical'
}

local ALLOWED_LOG_LEVELS = logsConfig.AllowedLevels or {
    'debug', 'info', 'warn', 'error', 'critical'
}

local ALLOWED_IDENTIFIER_TYPES = playersConfig.AllowedIdentifierTypes or {
    'discord', 'license', 'license2', 'xbl', 'live', 'fivem', 'ip'
}

-- حدود الحمولة من الكونفق
local payloadLimits = securityConfig.PayloadLimits or {}
local MAX_STRING_LENGTH = payloadLimits.MaxStringLength or 2000
local MAX_TITLE_LENGTH = payloadLimits.MaxTitleLength or 200
local MAX_BODY_LENGTH = payloadLimits.MaxBodyLength or 1000
local MAX_ARRAY_SIZE = payloadLimits.MaxArraySize or 100
local MAX_OBJECT_SIZE = payloadLimits.MaxObjectSize or 50
local MAX_NESTED_DEPTH = payloadLimits.MaxNestedDepth or 5
local MAX_META_JSON_BYTES = payloadLimits.MaxMetaJsonBytes or 4096
local MAX_META_DEPTH = payloadLimits.MaxMetaDepth or 4
local MAX_NESTED_OBJECTS = payloadLimits.MaxNestedObjects or 10
local MAX_ARRAY_LENGTH = payloadLimits.MaxArrayLength or 200

-- إعدادات التحقق
local STRICT_TYPES = validationConfig.StrictTypes ~= false
local ALLOW_NIL = validationConfig.AllowNil == true
local SANITIZE_STRINGS = validationConfig.SanitizeStrings ~= false

-- =============================================================
-- الحالة الداخلية
-- =============================================================
local isInitialized = false

-- =============================================================
-- أدوات مساعدة داخلية
-- =============================================================
local function logValidator(message, level)
    level = level or 'info'
    if Logger and Logger.Log then
        Logger.Log(level, message, { category = 'validator' })
    else
        print(('[ox_lib_secure] [VALIDATOR] %s'):format(message))
    end
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
-- تهيئة وحدة التحقق
-- =============================================================
function Validator.Initialize()
    if isInitialized then
        return true
    end

    logValidator('Initializing validator module...')

    isInitialized = true
    logValidator('Validator module initialized successfully.')
    return true
end

-- =============================================================
-- التحقق من حالة التهيئة
-- =============================================================
function Validator.IsInitialized()
    return isInitialized
end

-- =============================================================
-- التحقق من نوع البيانات
-- =============================================================
function Validator.IsType(value, expectedType)
    if value == nil then
        return ALLOW_NIL
    end

    return type(value) == expectedType
end

-- =============================================================
-- التحقق من سلسلة نصية
-- =============================================================
function Validator.IsString(value, maxLength)
    if value == nil then
        return ALLOW_NIL
    end

    if type(value) ~= 'string' then
        return false
    end

    maxLength = maxLength or MAX_STRING_LENGTH

    if #value > maxLength then
        return false
    end

    return true
end

-- =============================================================
-- التحقق من رقم
-- =============================================================
function Validator.IsNumber(value, min, max)
    if value == nil then
        return ALLOW_NIL
    end

    if type(value) ~= 'number' then
        return false
    end

    if min and value < min then
        return false
    end

    if max and value > max then
        return false
    end

    return true
end

-- =============================================================
-- التحقق من عدد صحيح
-- =============================================================
function Validator.IsInteger(value, min, max)
    if not Validator.IsNumber(value, min, max) then
        return false
    end

    return value == math.floor(value)
end

-- =============================================================
-- التحقق من قيمة منطقية
-- =============================================================
function Validator.IsBoolean(value)
    if value == nil then
        return ALLOW_NIL
    end

    return type(value) == 'boolean'
end

-- =============================================================
-- التحقق من جدول
-- =============================================================
function Validator.IsTable(value, maxSize)
    if value == nil then
        return ALLOW_NIL
    end

    if type(value) ~= 'table' then
        return false
    end

    maxSize = maxSize or MAX_OBJECT_SIZE

    local count = 0
    for _ in pairs(value) do
        count = count + 1
        if count > maxSize then
            return false
        end
    end

    return true
end

-- =============================================================
-- التحقق من قائمة
-- =============================================================
function Validator.IsArray(value, maxLength)
    if value == nil then
        return ALLOW_NIL
    end

    if type(value) ~= 'table' then
        return false
    end

    maxLength = maxLength or MAX_ARRAY_LENGTH

    if #value > maxLength then
        return false
    end

    return true
end

-- =============================================================
-- التحقق من قيمة ضمن قائمة
-- =============================================================
function Validator.IsInList(value, list)
    if value == nil then
        return ALLOW_NIL
    end

    return isInList(value, list)
end

-- =============================================================
-- التحقق من عنوان إشعار
-- =============================================================
function Validator.IsValidTitle(title)
    if title == nil then
        return true -- العنوان اختياري
    end

    if type(title) ~= 'string' then
        return false
    end

    if #title > MAX_TITLE_LENGTH then
        return false
    end

    return true
end

-- =============================================================
-- التحقق من جسم إشعار
-- =============================================================
function Validator.IsValidBody(body)
    if body == nil then
        return true -- الجسم اختياري
    end

    if type(body) ~= 'string' then
        return false
    end

    if #body > MAX_BODY_LENGTH then
        return false
    end

    return true
end

-- =============================================================
-- التحقق من موقع إشعار
-- =============================================================
function Validator.IsValidPosition(position)
    if position == nil then
        return true -- الموقع اختياري
    end

    return isInList(position, ALLOWED_POSITIONS)
end

-- =============================================================
-- التحقق من نوع إشعار
-- =============================================================
function Validator.IsValidNotificationType(notificationType)
    if notificationType == nil then
        return true -- النوع اختياري
    end

    return isInList(notificationType, ALLOWED_NOTIFICATION_TYPES)
end

-- =============================================================
-- التحقق من نمط تصميم
-- =============================================================
function Validator.IsValidDesignStyle(designStyle)
    if designStyle == nil then
        return true -- النمط اختياري
    end

    return isInList(designStyle, ALLOWED_DESIGN_STYLES)
end

-- =============================================================
-- التحقق من مستوى لوج
-- =============================================================
function Validator.IsValidLogLevel(level)
    if level == nil then
        return true -- المستوى اختياري
    end

    return isInList(level, ALLOWED_LOG_LEVELS)
end

-- =============================================================
-- التحقق من نوع معرف
-- =============================================================
function Validator.IsValidIdentifierType(identifierType)
    if identifierType == nil then
        return false
    end

    return isInList(identifierType, ALLOWED_IDENTIFIER_TYPES)
end

-- =============================================================
-- التحقق من مدة (مللي ثانية)
-- =============================================================
function Validator.IsValidDuration(durationMs, minMs, maxMs)
    if durationMs == nil then
        return true -- المدة اختيارية
    end

    if type(durationMs) ~= 'number' then
        return false
    end

    minMs = minMs or 1000
    maxMs = maxMs or 60000

    if durationMs < minMs or durationMs > maxMs then
        return false
    end

    return true
end

-- =============================================================
-- التحقق من حمولة إشعار كاملة
-- =============================================================
function Validator.ValidateNotificationPayload(payload)
    if not payload then
        return ALLOW_NIL, ALLOW_NIL and nil or 'Payload is nil'
    end

    if type(payload) ~= 'table' then
        return false, 'Payload must be a table'
    end

    -- التحقق من النوع
    if payload.type and not Validator.IsValidNotificationType(payload.type) then
        return false, ('Invalid notification type: %s'):format(tostring(payload.type))
    end

    -- التحقق من العنوان
    if not Validator.IsValidTitle(payload.title) then
        return false, 'Invalid title'
    end

    -- التحقق من الجسم
    if not Validator.IsValidBody(payload.body) then
        return false, 'Invalid body'
    end

    -- التحقق من الموقع
    if payload.position and not Validator.IsValidPosition(payload.position) then
        return false, ('Invalid position: %s'):format(tostring(payload.position))
    end

    -- التحقق من نمط التصميم
    if payload.designStyle and not Validator.IsValidDesignStyle(payload.designStyle) then
        return false, ('Invalid design style: %s'):format(tostring(payload.designStyle))
    end

    -- التحقق من المدة
    if payload.durationMs and not Validator.IsValidDuration(payload.durationMs) then
        return false, 'Invalid duration'
    end

    -- التحقق من البيانات الوصفية
    if payload.meta then
        local ok, metaJson = pcall(json.encode, payload.meta)

        if ok and metaJson then
            if #metaJson > MAX_META_JSON_BYTES then
                return false, 'Meta too large'
            end
        end
    end

    return true
end

-- =============================================================
-- التحقق من حمولة لوج كاملة
-- =============================================================
function Validator.ValidateLogPayload(payload)
    if not payload then
        return ALLOW_NIL, ALLOW_NIL and nil or 'Payload is nil'
    end

    if type(payload) ~= 'table' then
        return false, 'Payload must be a table'
    end

    -- التحقق من المستوى
    if payload.level and not Validator.IsValidLogLevel(payload.level) then
        return false, ('Invalid log level: %s'):format(tostring(payload.level))
    end

    -- التحقق من الرسالة
    if payload.message then
        if type(payload.message) ~= 'string' then
            return false, 'Message must be a string'
        end

        if #payload.message > MAX_STRING_LENGTH then
            return false, 'Message too long'
        end
    end

    -- التحقق من الفئة
    if payload.category then
        if type(payload.category) ~= 'string' then
            return false, 'Category must be a string'
        end
    end

    return true
end

-- =============================================================
-- تعقيم سلسلة نصية
-- =============================================================
function Validator.SanitizeString(input)
    if not input or type(input) ~= 'string' then
        return input
    end

    if not SANITIZE_STRINGS then
        return input
    end

    -- إزالة الأحرف الخطرة
    local sanitized = input:gsub('[<>"\'\\]', '')

    -- تحديد الطول
    if #sanitized > MAX_STRING_LENGTH then
        sanitized = sanitized:sub(1, MAX_STRING_LENGTH)
    end

    return sanitized
end

-- =============================================================
-- التحقق من عمق التداخل
-- =============================================================
function Validator.ValidateNestedDepth(data, currentDepth, maxDepth)
    currentDepth = currentDepth or 0
    maxDepth = maxDepth or MAX_NESTED_DEPTH

    if currentDepth > maxDepth then
        return false, 'Maximum nested depth exceeded'
    end

    if type(data) ~= 'table' then
        return true
    end

    for _, value in pairs(data) do
        if type(value) == 'table' then
            local ok, err = Validator.ValidateNestedDepth(value, currentDepth + 1, maxDepth)
            if not ok then
                return false, err
            end
        end
    end

    return true
end

-- =============================================================
-- التحقق من معرف لاعب
-- =============================================================
function Validator.ValidateIdentifier(identifierType, identifierValue)
    if not identifierType or not identifierValue then
        return false, 'Identifier type and value are required'
    end

    if not Validator.IsValidIdentifierType(identifierType) then
        return false, ('Invalid identifier type: %s'):format(tostring(identifierType))
    end

    if type(identifierValue) ~= 'string' then
        return false, 'Identifier value must be a string'
    end

    if #identifierValue > 255 then
        return false, 'Identifier value too long'
    end

    return true
end

-- =============================================================
-- التحقق من معرف مصدر (source)
-- =============================================================
function Validator.IsValidSource(source)
    if not source then
        return false
    end

    if type(source) ~= 'number' then
        return false
    end

    if source <= 0 then
        return false
    end

    return true
end

-- =============================================================
-- إحصائيات
-- =============================================================
function Validator.GetStats()
    return {
        isInitialized = isInitialized,
        allowedPositions = ALLOWED_POSITIONS,
        allowedNotificationTypes = ALLOWED_NOTIFICATION_TYPES,
        allowedDesignStyles = ALLOWED_DESIGN_STYLES,
        allowedLogLevels = ALLOWED_LOG_LEVELS,
        allowedIdentifierTypes = ALLOWED_IDENTIFIER_TYPES,
        maxStringLength = MAX_STRING_LENGTH,
        maxTitleLength = MAX_TITLE_LENGTH,
        maxBodyLength = MAX_BODY_LENGTH,
        strictTypes = STRICT_TYPES,
        allowNil = ALLOW_NIL,
        sanitizeStrings = SANITIZE_STRINGS
    }
end

-- =============================================================
-- تهيئة عند التحميل
-- =============================================================
Validator.Initialize()

-- =============================================================
-- رسالة تحميل ناجحة
-- =============================================================
if Logger and Logger.Debug then
    Logger.Debug('server/core/validator.lua loaded')
else
    print('[ox_lib_secure] server/core/validator.lua loaded')
end
