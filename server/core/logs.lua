-- =============================================================
-- ox_lib_secure
-- File: server/core/logs.lua
-- Description:
--   طبقة اللوجات لنظام ox_lib_secure.
--
-- Notes:
--   - يتم تسجيل الأحداث بمستويات مختلفة.
--   - يتم التخزين المؤقت للإدراج الدفعي.
--   - يتم الحفظ في قاعدة البيانات بشكل دوري.
--   - يتم دعم التصفية حسب المستوى والفئة.
--   - يتم التحقق من نوع الرسالة قبل التسجيل.
--   - البحث يدعم عدة حقول.
-- =============================================================

Config = Config or {}
OxSecure = OxSecure or {}
OxSecure.Logs = OxSecure.Logs or {}

local Logs = OxSecure.Logs
local Database = OxSecure.Database or {}
local Logger = OxSecure.Logger or {}
local Utils = OxSecure.Utils or {}
local Security = OxSecure.Security or {}

local logsConfig = Config.Logs or {}
local SAVE_LOGS = Config.Database and Config.Database.SaveLogs ~= false
local MAX_BUFFER = logsConfig.MaxBuffer or 100
local FLUSH_INTERVAL_SECONDS = logsConfig.FlushIntervalSeconds or 30
local MAX_MESSAGE_LENGTH = logsConfig.MaxMessageLength or 2000

-- مستويات اللوجات
local LOG_LEVELS = {
    debug = 0,
    info = 1,
    warn = 2,
    error = 3,
    critical = 4
}

-- المخزن المؤقت
local logBuffer = {}
local isFlushing = false
local totalLogsWritten = 0

-- =============================================================
-- أدوات مساعدة داخلية
-- =============================================================
local function isValidLevel(level)
    return LOG_LEVELS[level] ~= nil
end

-- =============================================================
-- حساب تجزئة الرسالة للتحقق من السلامة
-- =============================================================
local function hashMessage(message)
    if not message or type(message) ~= 'string' then
        return nil
    end

    if Security.Hash then
        return Security.Hash(message)
    end

    return nil
end

-- =============================================================
-- إضافة لوج إلى المخزن المؤقت
-- =============================================================
local function addToBuffer(entry)
    logBuffer[#logBuffer + 1] = entry

    if #logBuffer >= MAX_BUFFER then
        Logs.Flush()
    end
end

-- =============================================================
-- حفظ دفعة من اللوجات في قاعدة البيانات
-- =============================================================
local function flushToDatabase(callback)
    if #logBuffer == 0 then
        if callback then callback(true, 0) end
        return
    end

    if not Database.IsReady() or not SAVE_LOGS then
        logBuffer = {}
        if callback then callback(true, 0) end
        return
    end

    isFlushing = true

    local batch = logBuffer
    logBuffer = {}

    local insertQuery = ('INSERT INTO %s (level, category, event_code, message, message_hash, source_system_id, player_id, session_id, is_public, meta_json, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())'):format(Database.GetTableName('logs'))

    local pendingInserts = #batch
    local successCount = 0

    for _, entry in ipairs(batch) do
        local metaJson = nil

        if entry.meta ~= nil and Utils.SafeJsonEncode then
            metaJson = Utils.SafeJsonEncode(entry.meta)
        end

        Database.Execute(insertQuery, {
            entry.level or 'info',
            entry.category or 'general',
            entry.eventCode or 'log',
            entry.message or '',
            entry.messageHash,
            entry.sourceSystemId,
            entry.playerId,
            entry.sessionId,
            entry.isPublic and 1 or 0,
            metaJson
        }, function(_, err)
            if not err then
                successCount = successCount + 1
            end

            pendingInserts = pendingInserts - 1

            if pendingInserts <= 0 then
                isFlushing = false
                totalLogsWritten = totalLogsWritten + successCount

                if callback then callback(true, successCount) end
            end
        end)
    end
end

-- =============================================================
-- تفريغ المخزن المؤقت
-- =============================================================
function Logs.Flush(callback)
    if isFlushing then
        if callback then callback(false, 'Already flushing') end
        return
    end

    flushToDatabase(callback)
end

-- =============================================================
-- تسجيل لوج
--
-- إصلاح 1: التحقق من نوع الرسالة قبل التسجيل.
-- =============================================================
function Logs.Write(options, callback)
    options = options or {}

    local level = options.level or 'info'

    if not isValidLevel(level) then
        level = 'info'
    end

    local message = options.message

    -- إصلاح 1: التحقق من نوع الرسالة
    if type(message) ~= 'string' then
        if callback then callback(false, { code = 'ERR_INVALID_FIELD' }) end
        return
    end

    if message == '' then
        if callback then callback(false, { code = 'ERR_EMPTY_MESSAGE' }) end
        return
    end

    -- تقليم الرسالة إذا تجاوزت الحد الأقصى
    if #message > MAX_MESSAGE_LENGTH then
        message = message:sub(1, MAX_MESSAGE_LENGTH)
    end

    local category = options.category or 'general'
    local eventCode = options.eventCode or 'log'
    local isPublic = options.isPublic or false

    local messageHash = hashMessage(message)

    addToBuffer({
        level = level,
        category = category,
        eventCode = eventCode,
        message = message,
        messageHash = messageHash,
        playerId = options.playerId,
        sessionId = options.sessionId,
        sourceSystemId = options.sourceSystemId,
        isPublic = isPublic,
        meta = options.meta
    })

    if callback then callback(true, nil) end
end

-- =============================================================
-- تسجيل لوج بمستوى debug
-- =============================================================
function Logs.Debug(message, options)
    options = options or {}
    options.level = 'debug'
    options.message = message
    Logs.Write(options)
end

-- =============================================================
-- تسجيل لوج بمستوى info
-- =============================================================
function Logs.Info(message, options)
    options = options or {}
    options.level = 'info'
    options.message = message
    Logs.Write(options)
end

-- =============================================================
-- تسجيل لوج بمستوى warn
-- =============================================================
function Logs.Warn(message, options)
    options = options or {}
    options.level = 'warn'
    options.message = message
    Logs.Write(options)
end

-- =============================================================
-- تسجيل لوج بمستوى error
-- =============================================================
function Logs.Error(message, options)
    options = options or {}
    options.level = 'error'
    options.message = message
    Logs.Write(options)
end

-- =============================================================
-- تسجيل لوج بمستوى critical
-- =============================================================
function Logs.Critical(message, options)
    options = options or {}
    options.level = 'critical'
    options.message = message
    Logs.Write(options)
end

-- =============================================================
-- جلب اللوجات من قاعدة البيانات
-- =============================================================
function Logs.GetLogs(options, callback)
    options = options or {}

    local limit = options.limit or 50
    local offset = options.offset or 0

    local query = nil
    local params = {}

    if options.level then
        query = ('SELECT * FROM %s WHERE level = ? ORDER BY created_at DESC LIMIT ? OFFSET ?'):format(Database.GetTableName('logs'))
        params = { options.level, limit, offset }
    elseif options.category then
        query = ('SELECT * FROM %s WHERE category = ? ORDER BY created_at DESC LIMIT ? OFFSET ?'):format(Database.GetTableName('logs'))
        params = { options.category, limit, offset }
    elseif options.playerId then
        query = ('SELECT * FROM %s WHERE player_id = ? ORDER BY created_at DESC LIMIT ? OFFSET ?'):format(Database.GetTableName('logs'))
        params = { options.playerId, limit, offset }
    elseif options.publicOnly then
        query = ('SELECT * FROM %s WHERE is_public = 1 ORDER BY created_at DESC LIMIT ? OFFSET ?'):format(Database.GetTableName('logs'))
        params = { limit, offset }
    else
        query = ('SELECT * FROM %s ORDER BY created_at DESC LIMIT ? OFFSET ?'):format(Database.GetTableName('logs'))
        params = { limit, offset }
    end

    Database.Execute(query, params, function(results, err)
        if err then
            if callback then callback({}, err) end
            return
        end

        if callback then callback(results or {}, nil) end
    end)
end

-- =============================================================
-- البحث في اللوجات
--
-- إصلاح 4: البحث في عدة حقول (message, category, event_code).
-- =============================================================
function Logs.Search(searchTerm, options, callback)
    options = options or {}

    if type(searchTerm) ~= 'string' or searchTerm == '' then
        if callback then callback({}, nil) end
        return
    end

    local limit = options.limit or 50
    local offset = options.offset or 0

    local query = nil
    local params = {}

    if options.searchField == 'category' then
        query = ('SELECT * FROM %s WHERE category LIKE ? ORDER BY created_at DESC LIMIT ? OFFSET ?'):format(Database.GetTableName('logs'))
        params = { '%' .. searchTerm .. '%', limit, offset }
    elseif options.searchField == 'event_code' then
        query = ('SELECT * FROM %s WHERE event_code LIKE ? ORDER BY created_at DESC LIMIT ? OFFSET ?'):format(Database.GetTableName('logs'))
        params = { '%' .. searchTerm .. '%', limit, offset }
    else
        -- البحث في جميع الحقول النصية
        query = ('SELECT * FROM %s WHERE message LIKE ? OR category LIKE ? OR event_code LIKE ? ORDER BY created_at DESC LIMIT ? OFFSET ?'):format(Database.GetTableName('logs'))
        local pattern = '%' .. searchTerm .. '%'
        params = { pattern, pattern, pattern, limit, offset }
    end

    Database.Execute(query, params, function(results, err)
        if err then
            if callback then callback({}, err) end
            return
        end

        if callback then callback(results or {}, nil) end
    end)
end

-- =============================================================
-- الحصول على إحصائيات اللوجات
-- =============================================================
function Logs.GetStats(callback)
    local statsQuery = ('SELECT level, COUNT(*) as count FROM %s GROUP BY level'):format(Database.GetTableName('logs'))

    Database.Execute(statsQuery, {}, function(results, err)
        if err then
            if callback then callback({}, err) end
            return
        end

        local stats = {
            debug = 0,
            info = 0,
            warn = 0,
            error = 0,
            critical = 0,
            total = 0,
            bufferSize = #logBuffer,
            totalWritten = totalLogsWritten
        }

        if type(results) == 'table' then
            for _, row in ipairs(results) do
                stats[row.level] = row.count
                stats.total = stats.total + row.count
            end
        end

        if callback then callback(stats, nil) end
    end)
end

-- =============================================================
-- حذف اللوجات القديمة
-- =============================================================
function Logs.CleanupOld(days, callback)
    days = days or 30

    local deleteQuery = ('DELETE FROM %s WHERE created_at < DATE_SUB(NOW(), INTERVAL ? DAY)'):format(Database.GetTableName('logs'))

    Database.Execute(deleteQuery, { days }, function(_, err)
        if err then
            if callback then callback(false, err) end
            return
        end

        if callback then callback(true, nil) end
    end)
end

-- =============================================================
-- الحصول على حجم المخزن المؤقت
-- =============================================================
function Logs.GetBufferSize()
    return #logBuffer
end

-- =============================================================
-- مهمة دورية لتفريغ المخزن المؤقت
-- =============================================================
CreateThread(function()
    while true do
        Wait(FLUSH_INTERVAL_SECONDS * 1000)

        if #logBuffer > 0 then
            Logs.Flush()
        end
    end
end)

-- =============================================================
-- إصلاح 2: تفريغ المخزن عند إيقاف المورد مع معالجة
-- حالة التفريغ النشط.
-- =============================================================
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        if #logBuffer > 0 then
            -- محاولة التفريغ مع انتظار قصير
            if not isFlushing then
                Logs.Flush(function() end)
            else
                -- إذا كان هناك تفريغ نشط، ننتظر حتى ينتهي
                local waitCount = 0
                local maxWait = 10

                local function waitForFlush()
                    if not isFlushing or waitCount >= maxWait then
                        if #logBuffer > 0 and not isFlushing then
                            Logs.Flush(function() end)
                        end
                        return
                    end

                    waitCount = waitCount + 1
                    SetTimeout(100, waitForFlush)
                end

                waitForFlush()
            end
        end
    end
end)

-- =============================================================
-- رسالة تحميل ناجحة
-- =============================================================
if Logger.Debug then
    Logger.Debug('server/core/logs.lua loaded')
elseif OxSecure.Console and type(OxSecure.Console.debug) == 'function' then
    OxSecure.Console.debug('server/core/logs.lua loaded')
end
