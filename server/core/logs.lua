-- =============================================================
-- ox_lib_secure
-- File: server/core/logs.lua
-- Description:
--   وحدة إدارة اللوجات لنظام ox_lib_secure.
--   تدير تسجيل وعرض وحذف اللوجات.
--
-- Notes:
--   - مواءمة 100% مع config/main.lua النهائي.
--   - جدول الترحيلات: oxsecure_logs.
--   - أعمدة الجدول: level, category, event_code, message,
--     message_hash, source_system_id, player_id, server_player_id,
--     player_name, discord_id, session_id, route_name, ip_hash,
--     is_public, is_resolved, resolved_at, resolved_by_admin_id,
--     meta_json, created_at.
--   - تقرأ AllowedLevels من Config.Logs.
--   - حماية json.encode بـ pcall.
--   - تنظيف دوري للوجات القديمة.
-- =============================================================

Config = Config or {}
OxSecure = OxSecure or {}
OxSecure.Logs = OxSecure.Logs or {}

local Logs = OxSecure.Logs
local Logger = OxSecure.Logger or {}
local Database = OxSecure.Database or {}
local Security = OxSecure.Security or {}
local Validator = OxSecure.Validator or {}

-- =============================================================
-- قراءة الإعدادات من الكونفق
-- متوافقة حرفيًا مع config/main.lua
-- =============================================================
local logsConfig = Config.Logs or {}

local CONSOLE_ENABLED = logsConfig.Console ~= false
local PUBLIC_BY_DEFAULT = logsConfig.PublicByDefault == true
local MAX_MESSAGE_LENGTH = logsConfig.MaxMessageLength or 2000
local MAX_BUFFER = logsConfig.MaxBuffer or 100
local FLUSH_INTERVAL_SECONDS = logsConfig.FlushIntervalSeconds or 30
local MAX_DB_LOGS = logsConfig.MaxDbLogs or 10000
local CLEANUP_AFTER_DAYS = logsConfig.CleanupAfterDays or 90
local DEFAULT_LEVEL = logsConfig.Level or 'info'
local SAVE_TO_FILE = logsConfig.SaveToFile == true
local LOG_FILE_PATH = logsConfig.LogFilePath or 'logs/ox_lib_secure.log'

-- إصلاح: قراءة المستويات المسموحة من الكونفق
local ALLOWED_LEVELS = logsConfig.AllowedLevels or {
    'debug', 'info', 'warn', 'error', 'critical'
}

-- ترتيب المستويات للأولوية
local LEVEL_PRIORITY = {
    debug = 1,
    info = 2,
    warn = 3,
    error = 4,
    critical = 5
}

-- =============================================================
-- الحالة الداخلية
-- =============================================================
local logBuffer = {}
local isInitialized = false
local totalLogged = 0
local totalFlushed = 0

-- =============================================================
-- أدوات مساعدة داخلية
-- =============================================================
local function logInternal(message, level)
    level = level or 'info'
    if Logger and Logger.Log then
        Logger.Log(level, message, { category = 'logs_module' })
    else
        print(('[ox_lib_secure] [LOGS] %s'):format(message))
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
-- الحصول على اسم جدول اللوجات
-- =============================================================
local function getLogsTableName()
    if Database and Database.GetTableName then
        local ok, name = pcall(Database.GetTableName, 'logs')
        if ok and name then
            return name
        end
    end
    return 'oxsecure_logs'
end

-- =============================================================
-- تهيئة وحدة اللوجات
-- =============================================================
function Logs.Initialize()
    if isInitialized then
        return true
    end

    logInternal('Initializing logs module...')
    logInternal(('Default level: %s'):format(DEFAULT_LEVEL))
    logInternal(('Allowed levels: %s'):format(table.concat(ALLOWED_LEVELS, ', ')))
    logInternal(('Max buffer: %d'):format(MAX_BUFFER))
    logInternal(('Flush interval: %d seconds'):format(FLUSH_INTERVAL_SECONDS))
    logInternal(('Cleanup after: %d days'):format(CLEANUP_AFTER_DAYS))

    -- بدء حلقة التفريغ الدوري
    CreateThread(function()
        while true do
            Wait(FLUSH_INTERVAL_SECONDS * 1000)
            Logs.Flush()
        end
    end)

    -- بدء التنظيف الدوري (كل 6 ساعات)
    CreateThread(function()
        while true do
            Wait(6 * 3600 * 1000)
            Logs.Cleanup()
        end
    end)

    isInitialized = true
    logInternal('Logs module initialized successfully.')
    return true
end

-- =============================================================
-- التحقق من حالة التهيئة
-- =============================================================
function Logs.IsInitialized()
    return isInitialized
end

-- =============================================================
-- التحقق من صحة مستوى اللوج
-- =============================================================
function Logs.IsValidLevel(level)
    if not level then
        return false
    end

    return isInList(level, ALLOWED_LEVELS)
end

-- =============================================================
-- تسجيل لوج جديد
-- =============================================================
function Logs.Add(options)
    if not options then
        return false, 'Options are required'
    end

    local level = options.level or DEFAULT_LEVEL
    local message = options.message or ''
    local category = options.category
    local eventCode = options.eventCode
    local meta = options.meta

    -- التحقق من المستوى
    if not Logs.IsValidLevel(level) then
        return false, ('Invalid log level: %s'):format(tostring(level))
    end

    -- التحقق من الرسالة
    if type(message) ~= 'string' then
        return false, 'Message must be a string'
    end

    if #message > MAX_MESSAGE_LENGTH then
        message = message:sub(1, MAX_MESSAGE_LENGTH)
    end

    -- التحقق من الفئة
    if category and type(category) ~= 'string' then
        category = tostring(category)
    end

    -- إنشاء اللوج
    local logEntry = {
        level = level,
        category = category,
        eventCode = eventCode,
        message = message,
        sourceSystemId = options.sourceSystemId,
        playerId = options.playerId,
        serverPlayerId = options.serverPlayerId,
        playerName = options.playerName,
        discordId = options.discordId,
        sessionId = options.sessionId,
        routeName = options.routeName,
        ipHash = options.ipHash,
        isPublic = options.isPublic ~= nil and options.isPublic or PUBLIC_BY_DEFAULT,
        meta = meta,
        createdAt = getCurrentTimestamp()
    }

    -- توليد بصمة الرسالة (إذا كانت وحدة الأمان متاحة)
    if Security and Security.Hash then
        local hash = Security.Hash(message .. tostring(logEntry.createdAt))
        if hash then
            logEntry.messageHash = hash
        end
    end

    -- إضافة إلى المخزن المؤقت
    logBuffer[#logBuffer + 1] = logEntry
    totalLogged = totalLogged + 1

    -- عرض في الكونسول إذا كان مفعلًا
    if CONSOLE_ENABLED then
        local prefix = ('[%s]'):format(level:upper())
        local categoryStr = category and ('[%s]'):format(category) or ''
        print(('[ox_lib_secure] %s %s %s'):format(prefix, categoryStr, message))
    end

    -- حفظ في ملف إذا كان مفعلًا
    if SAVE_TO_FILE then
        Logs.WriteToFile(logEntry)
    end

    -- تفريغ إذا وصل المخزن للحد الأقصى
    if #logBuffer >= MAX_BUFFER then
        Logs.Flush()
    end

    return true
end

-- =============================================================
-- دوال مساعدة لكل مستوى
-- =============================================================
function Logs.Debug(message, options)
    options = options or {}
    options.level = 'debug'
    options.message = message
    return Logs.Add(options)
end

function Logs.Info(message, options)
    options = options or {}
    options.level = 'info'
    options.message = message
    return Logs.Add(options)
end

function Logs.Warn(message, options)
    options = options or {}
    options.level = 'warn'
    options.message = message
    return Logs.Add(options)
end

function Logs.Error(message, options)
    options = options or {}
    options.level = 'error'
    options.message = message
    return Logs.Add(options)
end

function Logs.Critical(message, options)
    options = options or {}
    options.level = 'critical'
    options.message = message
    return Logs.Add(options)
end

-- =============================================================
-- تفريغ المخزن المؤقت إلى قاعدة البيانات
-- =============================================================
function Logs.Flush()
    if #logBuffer == 0 then
        return 0
    end

    if not Database or not Database.Execute then
        -- إذا لم تكن قاعدة البيانات متاحة، امسح المخزن فقط
        local count = #logBuffer
        logBuffer = {}
        return count
    end

    local tableName = getLogsTableName()
    local flushed = 0
    local batch = logBuffer
    logBuffer = {}

    for _, logEntry in ipairs(batch) do
        -- ترميز البيانات الوصفية بأمان
        local metaJson = nil
        if logEntry.meta then
            local ok, encoded = pcall(json.encode, logEntry.meta)
            if ok and encoded then
                metaJson = encoded
            end
        end

        Database.Execute(
            ([[INSERT INTO %s (
                level, category, event_code, message, message_hash,
                source_system_id, player_id, server_player_id, player_name,
                discord_id, session_id, route_name, ip_hash,
                is_public, meta_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]]):format(tableName),
            {
                logEntry.level,
                logEntry.category,
                logEntry.eventCode,
                logEntry.message,
                logEntry.messageHash,
                logEntry.sourceSystemId,
                logEntry.playerId,
                logEntry.serverPlayerId,
                logEntry.playerName,
                logEntry.discordId,
                logEntry.sessionId,
                logEntry.routeName,
                logEntry.ipHash,
                logEntry.isPublic and 1 or 0,
                metaJson
            }
        )

        flushed = flushed + 1
    end

    totalFlushed = totalFlushed + flushed

    if flushed > 0 then
        logInternal(('Flushed %d logs to database.'):format(flushed))
    end

    return flushed
end

-- =============================================================
-- كتابة لوج إلى ملف
-- =============================================================
function Logs.WriteToFile(logEntry)
    if not SAVE_TO_FILE then
        return
    end

    local ok, err = pcall(function()
        local file = io.open(LOG_FILE_PATH, 'a')
        if file then
            local timestamp = os.date('%Y-%m-%d %H:%M:%S', logEntry.createdAt)
            local line = ('[%s] [%s] %s %s\n'):format(
                timestamp,
                logEntry.level:upper(),
                logEntry.category and ('[' .. logEntry.category .. ']') or '',
                logEntry.message
            )
            file:write(line)
            file:close()
        end
    end)

    if not ok then
        -- تجاهل أخطاء الكتابة للملف لتجنب التعطل
    end
end

-- =============================================================
-- جلب اللوجات من قاعدة البيانات
-- =============================================================
function Logs.Get(options, callback)
    options = options or {}

    if not Database or not Database.Execute then
        if callback then callback({}) end
        return
    end

    local tableName = getLogsTableName()
    local limit = options.limit or 50
    local offset = options.offset or 0
    local level = options.level
    local category = options.category
    local isPublic = options.isPublic

    local whereClauses = {}
    local params = {}

    if level and Logs.IsValidLevel(level) then
        whereClauses[#whereClauses + 1] = 'level = ?'
        params[#params + 1] = level
    end

    if category then
        whereClauses[#whereClauses + 1] = 'category = ?'
        params[#params + 1] = category
    end

    if isPublic ~= nil then
        whereClauses[#whereClauses + 1] = 'is_public = ?'
        params[#params + 1] = isPublic and 1 or 0
    end

    local whereStr = #whereClauses > 0 and ('WHERE ' .. table.concat(whereClauses, ' AND ')) or ''

    -- إضافة الحدود
    params[#params + 1] = limit
    params[#params + 1] = offset

    Database.Execute(
        ('SELECT * FROM %s %s ORDER BY created_at DESC LIMIT ? OFFSET ?'):format(tableName, whereStr),
        params,
        function(results)
            if callback then
                callback(results or {})
            end
        end
    )
end

-- =============================================================
-- جلب لوج واحد
-- =============================================================
function Logs.GetById(logId, callback)
    if not logId then
        if callback then callback(nil) end
        return
    end

    if not Database or not Database.Single then
        if callback then callback(nil) end
        return
    end

    local tableName = getLogsTableName()

    Database.Single(
        ('SELECT * FROM %s WHERE id = ? LIMIT 1'):format(tableName),
        { logId },
        function(result)
            if callback then
                callback(result)
            end
        end
    )
end

-- =============================================================
-- حذف لوج
-- =============================================================
function Logs.Delete(logId, callback)
    if not logId then
        if callback then callback(false) end
        return
    end

    if not Database or not Database.Execute then
        if callback then callback(false) end
        return
    end

    local tableName = getLogsTableName()

    Database.Execute(
        ('DELETE FROM %s WHERE id = ?'):format(tableName),
        { logId },
        function()
            if callback then callback(true) end
        end
    )
end

-- =============================================================
-- حذف لوجات حسب الفئة
-- =============================================================
function Logs.DeleteByCategory(category, callback)
    if not category then
        if callback then callback(0) end
        return
    end

    if not Database or not Database.Execute then
        if callback then callback(0) end
        return
    end

    local tableName = getLogsTableName()

    Database.Execute(
        ('DELETE FROM %s WHERE category = ?'):format(tableName),
        { category },
        function(result)
            if callback then callback(result and result.affectedRows or 0) end
        end
    )
end

-- =============================================================
-- وضع علامة كمحلولة
-- =============================================================
function Logs.MarkResolved(logId, adminId, callback)
    if not logId then
        if callback then callback(false) end
        return
    end

    if not Database or not Database.Execute then
        if callback then callback(false) end
        return
    end

    local tableName = getLogsTableName()

    Database.Execute(
        ('UPDATE %s SET is_resolved = 1, resolved_at = NOW(), resolved_by_admin_id = ? WHERE id = ?'):format(tableName),
        { adminId, logId },
        function()
            if callback then callback(true) end
        end
    )
end

-- =============================================================
-- تنظيف دوري
-- =============================================================
function Logs.Cleanup()
    if not Database or not Database.Execute then
        return
    end

    local tableName = getLogsTableName()
    local cutoffDate = os.date('%Y-%m-%d %H:%M:%S', getCurrentTimestamp() - (CLEANUP_AFTER_DAYS * 86400))

    Database.Execute(
        ('DELETE FROM %s WHERE created_at < ?'):format(tableName),
        { cutoffDate }
    )

    -- أيضًا، التحقق من الحد الأقصى للسجلات
    Database.Execute(
        ([[DELETE FROM %s WHERE id NOT IN (
            SELECT id FROM (
                SELECT id FROM %s ORDER BY created_at DESC LIMIT ?
            ) AS recent_logs
        )]]):format(tableName, tableName),
        { MAX_DB_LOGS }
    )

    logInternal('Log cleanup completed.')
end

-- =============================================================
-- إحصائيات
-- =============================================================
function Logs.GetStats()
    return {
        bufferCount = #logBuffer,
        totalLogged = totalLogged,
        totalFlushed = totalFlushed,
        maxBuffer = MAX_BUFFER,
        maxMessageLength = MAX_MESSAGE_LENGTH,
        flushIntervalSeconds = FLUSH_INTERVAL_SECONDS,
        cleanupAfterDays = CLEANUP_AFTER_DAYS,
        maxDbLogs = MAX_DB_LOGS,
        allowedLevels = ALLOWED_LEVELS,
        defaultLevel = DEFAULT_LEVEL,
        consoleEnabled = CONSOLE_ENABLED,
        saveToFile = SAVE_TO_FILE,
        isInitialized = isInitialized
    }
end

-- =============================================================
-- معالجة إيقاف المورد
-- تفريغ المخزن قبل الإيقاف
-- =============================================================
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    if #logBuffer > 0 then
        logInternal(('Resource stopping. Flushing %d buffered logs...'):format(#logBuffer))
        Logs.Flush()
    end
end)

-- =============================================================
-- تهيئة عند التحميل
-- =============================================================
Logs.Initialize()

-- =============================================================
-- رسالة تحميل ناجحة
-- =============================================================
if Logger and Logger.Debug then
    Logger.Debug('server/core/logs.lua loaded')
else
    print('[ox_lib_secure] server/core/logs.lua loaded')
end
