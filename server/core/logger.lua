-- =============================================================
-- ox_lib_secure
-- File: server/core/logger.lua
-- Description:
--   طبقة التسجيل المركزية لنظام ox_lib_secure.
--
-- Notes:
--   - التسجيل إلى الكونسول يتم دائمًا.
--   - التسجيل إلى قاعدة البيانات يتم عند توفرها.
--   - يتم إخفاء الأسرار قبل التسجيل.
--   - يتم تخزين اللوجات مؤقتًا قبل الحفظ.
-- =============================================================

Config = Config or {}
OxSecure = OxSecure or {}
OxSecure.Logger = OxSecure.Logger or {}

local Logger = OxSecure.Logger
local Utils = OxSecure.Utils or {}
local Security = OxSecure.Security or {}
local Localization = OxSecure.Localization or {}

local logsConfig = Config.Logs or {}

local CONSOLE_ENABLED = logsConfig.Console ~= false
local PUBLIC_BY_DEFAULT = logsConfig.PublicByDefault == true
local MAX_MESSAGE_LENGTH = logsConfig.MaxMessageLength or 2000
local MAX_BUFFER = logsConfig.MaxBuffer or 100

-- مستويات اللوجات
local LOG_LEVELS = {
    debug = 1,
    info = 2,
    warn = 3,
    error = 4,
    critical = 5
}

-- ألوان الكونسول لكل مستوى
local LOG_COLORS = {
    debug = '^7',
    info = '^2',
    warn = '^3',
    error = '^1',
    critical = '^1'
}

-- =============================================================
-- أدوات مساعدة داخلية
-- =============================================================
local function nowMs()
    if Utils.NowMs then
        return Utils.NowMs()
    end

    if type(GetGameTimer) == 'function' then
        return GetGameTimer()
    end

    return os.time() * 1000
end

local function getStateLogs()
    local state = OxSecure.State and OxSecure.State.Runtime or nil
    return state and state.logs or nil
end

local function isValidLevel(level)
    return LOG_LEVELS[level] ~= nil
end

local function truncateMessage(message)
    if type(message) ~= 'string' then
        message = tostring(message or '')
    end

    if #message > MAX_MESSAGE_LENGTH then
        return message:sub(1, MAX_MESSAGE_LENGTH)
    end

    return message
end

-- =============================================================
-- إخفاء الأسرار
--
-- هذه الدالة مطلوبة من قبل server/main.lua في فحوصات
-- الإقلاع. يجب أن تكون موجودة دائمًا.
-- =============================================================
function Logger.RedactSecrets(value)
    if Security.RedactSecrets then
        return Security.RedactSecrets(value)
    end

    if Utils.RedactSecrets then
        return Utils.RedactSecrets(value)
    end

    return value
end

-- =============================================================
-- تنسيق رسالة الكونسول
-- =============================================================
local function formatConsoleMessage(level, message)
    local color = LOG_COLORS[level] or '^7'
    local prefix = '^5[ox_lib_secure]^7'
    local levelTag = string.upper(level)

    return ('%s %s[%s]^7 %s'):format(prefix, color, levelTag, message)
end

-- =============================================================
-- الكتابة إلى الكونسول
-- =============================================================
local function writeToConsole(level, message)
    if not CONSOLE_ENABLED then
        return
    end

    if level == 'debug' and not OxSecure.Debug then
        return
    end

    local formatted = formatConsoleMessage(level, message)
    print(formatted)
end

-- =============================================================
-- إضافة لوج إلى الذاكرة المؤقتة
-- =============================================================
local function addToBuffer(entry)
    local stateLogs = getStateLogs()

    if not stateLogs then
        return
    end

    if not stateLogs.buffer then
        stateLogs.buffer = {}
    end

    table.insert(stateLogs.buffer, entry)
    stateLogs.bufferSize = #stateLogs.buffer

    -- إذا تجاوز المخزن الحد الأقصى، نحذف الأقدم
    if stateLogs.bufferSize > MAX_BUFFER then
        table.remove(stateLogs.buffer, 1)
        stateLogs.bufferSize = #stateLogs.buffer
    end
end

-- =============================================================
-- بناء مدخل لوج
--
-- إصلاح:
-- معالجة isPublic بشكل صريح لتجنب مشكلة false في Lua.
-- =============================================================
local function buildLogEntry(level, message, options)
    options = options or {}

    -- إصلاح: معالجة isPublic بشكل صريح
    local isPublic = options.isPublic

    if isPublic == nil then
        isPublic = PUBLIC_BY_DEFAULT
    end

    local entry = {
        level = level,
        message = truncateMessage(message),
        category = options.category or 'general',
        eventCode = options.eventCode or 'log',
        systemCode = options.systemCode or nil,
        serverPlayerId = options.serverPlayerId or nil,
        isPublic = isPublic,
        meta = nil,
        createdAt = nowMs(),
        createdAtUnix = os.time()
    }

    -- إخفاء الأسرار من meta إذا كانت موجودة
    if options.meta ~= nil then
        entry.meta = Logger.RedactSecrets(options.meta)
    end

    return entry
end

-- =============================================================
-- التسجيل الأساسي
-- =============================================================
local function log(level, message, options)
    if not isValidLevel(level) then
        level = 'info'
    end

    if type(message) ~= 'string' then
        message = tostring(message or '')
    end

    local cleanMessage = truncateMessage(message)

    -- الكتابة إلى الكونسول
    writeToConsole(level, cleanMessage)

    -- بناء المدخل
    local entry = buildLogEntry(level, cleanMessage, options)

    -- إضافة إلى الذاكرة المؤقتة
    addToBuffer(entry)

    -- إذا كانت قاعدة البيانات متاحة، نحفظ مباشرة
    -- سيتم تنفيذ هذا لاحقًا في وحدة قاعدة البيانات
    if OxSecure.Database and type(OxSecure.Database.SaveLog) == 'function' then
        OxSecure.Database.SaveLog(entry)
    end

    return entry
end

-- =============================================================
-- واجهات التسجيل العامة
-- =============================================================
function Logger.Debug(message, options)
    return log('debug', message, options)
end

function Logger.Info(message, options)
    return log('info', message, options)
end

function Logger.Warn(message, options)
    return log('warn', message, options)
end

function Logger.Error(message, options)
    return log('error', message, options)
end

function Logger.Critical(message, options)
    return log('critical', message, options)
end

-- =============================================================
-- تسجيل بخطأ من الكتالوج
-- =============================================================
function Logger.LogError(errorCode, data, options)
    options = options or {}

    local errorInfo = nil

    if Localization.GetError then
        errorInfo = Localization.GetError(errorCode, data)
    end

    if not errorInfo then
        errorInfo = {
            code = errorCode or 'ERR_UNKNOWN',
            title = 'خطأ غير معروف',
            body = 'حدث خطأ غير متوقع في النظام.',
            severity = 'error'
        }
    end

    local level = errorInfo.severity or 'error'

    if not isValidLevel(level) then
        level = 'error'
    end

    local message = ('[%s] %s'):format(errorInfo.code, errorInfo.body)

    return log(level, message, {
        category = options.category or errorInfo.category or 'general',
        eventCode = options.eventCode or errorInfo.code,
        systemCode = options.systemCode,
        serverPlayerId = options.serverPlayerId,
        isPublic = options.isPublic,
        meta = options.meta
    })
end

-- =============================================================
-- تسجيل حدث أمني
-- =============================================================
function Logger.SecurityEvent(message, options)
    options = options or {}
    options.category = 'security'
    options.eventCode = options.eventCode or 'security_event'

    return log('warn', message, options)
end

-- =============================================================
-- تسجيل حدث قاعدة بيانات
-- =============================================================
function Logger.DatabaseEvent(message, options)
    options = options or {}
    options.category = 'database'
    options.eventCode = options.eventCode or 'database_event'

    return log('info', message, options)
end

-- =============================================================
-- تسجيل حدث معدل استخدام
-- =============================================================
function Logger.RateLimitEvent(message, options)
    options = options or {}
    options.category = 'rate_limit'
    options.eventCode = options.eventCode or 'rate_limit_event'

    return log('warn', message, options)
end

-- =============================================================
-- تسجيل حدث صلاحيات
-- =============================================================
function Logger.PermissionEvent(message, options)
    options = options or {}
    options.category = 'permission'
    options.eventCode = options.eventCode or 'permission_event'

    return log('warn', message, options)
end

-- =============================================================
-- الحصول على اللوجات المخزنة مؤقتًا
-- =============================================================
function Logger.GetBufferedLogs()
    local stateLogs = getStateLogs()

    if not stateLogs or not stateLogs.buffer then
        return {}
    end

    return stateLogs.buffer
end

-- =============================================================
-- مسح اللوجات المخزنة مؤقتًا
-- =============================================================
function Logger.ClearBuffer()
    local stateLogs = getStateLogs()

    if not stateLogs then
        return
    end

    stateLogs.buffer = {}
    stateLogs.bufferSize = 0
    stateLogs.lastFlushMs = nowMs()
end

-- =============================================================
-- الحصول على إحصائيات المخزن
-- =============================================================
function Logger.GetBufferStats()
    local stateLogs = getStateLogs()

    if not stateLogs then
        return {
            bufferSize = 0,
            maxBuffer = MAX_BUFFER,
            lastFlushMs = 0
        }
    end

    return {
        bufferSize = stateLogs.bufferSize or 0,
        maxBuffer = MAX_BUFFER,
        lastFlushMs = stateLogs.lastFlushMs or 0
    }
end

-- =============================================================
-- التحقق من صحة مستوى اللوج
-- =============================================================
function Logger.IsValidLevel(level)
    return isValidLevel(level)
end

-- =============================================================
-- الحصول على المستويات المتاحة
-- =============================================================
function Logger.GetAvailableLevels()
    local levels = {}

    for level in pairs(LOG_LEVELS) do
        levels[#levels + 1] = level
    end

    table.sort(levels, function(a, b)
        return LOG_LEVELS[a] < LOG_LEVELS[b]
    end)

    return levels
end

-- =============================================================
-- رسالة تحميل ناجحة
-- =============================================================
if CONSOLE_ENABLED then
    print(formatConsoleMessage('debug', 'server/core/logger.lua loaded'))
end
