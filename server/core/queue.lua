-- =============================================================
-- ox_lib_secure
-- File: server/core/queue.lua
-- Description:
--   طبقة قائمة الانتظار لنظام ox_lib_secure.
--
-- Notes:
--   - يتم تخزين العناصر في قاعدة البيانات.
--   - يتم المعالجة بالترتيب حسب الأولوية والوقت المجدول.
--   - يتم إعادة المحاولة تلقائيًا عند الفشل.
--   - يتم تنظيف العناصر المنتهية الصلاحية دوريًا.
--   - يتم حفظ نوع الرسالة داخل الـ payload.
--   - يتم استخدام نسخ عميق للـ payload عند توفره.
-- =============================================================

Config = Config or {}
OxSecure = OxSecure or {}
OxSecure.Queue = OxSecure.Queue or {}

local Queue = OxSecure.Queue
local Database = OxSecure.Database or {}
local Logger = OxSecure.Logger or {}
local Utils = OxSecure.Utils or {}

local queueConfig = Config.Queue or {}
local PROCESS_INTERVAL_MS = queueConfig.ProcessIntervalMs or 5000
local MAX_BATCH_SIZE = queueConfig.MaxBatchSize or 10
local CLEANUP_INTERVAL_MS = queueConfig.CleanupIntervalMs or 300000

-- حالة المعالجة
local isProcessing = false
local handlers = {}

-- =============================================================
-- أدوات مساعدة داخلية
-- =============================================================
local function logQueueEvent(message, options)
    if Logger.Info then
        Logger.Info(message, options or {
            category = 'queue',
            eventCode = 'queue_event'
        })
    end
end

local function logQueueError(message, options)
    if Logger.Error then
        Logger.Error(message, options or {
            category = 'queue',
            eventCode = 'queue_error'
        })
    end
end

-- =============================================================
-- إصلاح 1: نسخ عميق للـ payload إذا كان متاحًا
-- =============================================================
local function copyPayload(source)
    if type(source) ~= 'table' then
        return {}
    end

    -- استخدام Utils.TableCopy للنسخ العميق إذا كان متاحًا
    if Utils.TableCopy then
        local copied = Utils.TableCopy(source)

        if copied then
            return copied
        end
    end

    -- بديل: نسخ سطحي
    local result = {}

    for key, value in pairs(source) do
        result[key] = value
    end

    return result
end

-- =============================================================
-- إصلاح 3: تحويل DATETIME إلى طابع زمني
-- =============================================================
local function datetimeToTimestamp(value)
    if value == nil then
        return nil
    end

    if type(value) == 'number' then
        return value
    end

    -- استخدام Utils.DateTimeToTimestamp إذا كان متاحًا
    if Utils.DateTimeToTimestamp then
        local result = Utils.DateTimeToTimestamp(value)

        if result then
            return result
        end
    end

    if type(value) ~= 'string' then
        return nil
    end

    local year, month, day, hour, min, sec = value:match('(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)')

    if year then
        return os.time({
            year = tonumber(year),
            month = tonumber(month),
            day = tonumber(day),
            hour = tonumber(hour),
            min = tonumber(min),
            sec = tonumber(sec)
        })
    end

    year, month, day = value:match('(%d+)-(%d+)-(%d+)')

    if year then
        return os.time({
            year = tonumber(year),
            month = tonumber(month),
            day = tonumber(day),
            hour = 0,
            min = 0,
            sec = 0
        })
    end

    return nil
end

-- =============================================================
-- تسجيل معالج لنوع معين من الرسائل
-- =============================================================
function Queue.RegisterHandler(messageType, handler)
    if type(messageType) ~= 'string' or messageType == '' then
        return false
    end

    if type(handler) ~= 'function' then
        return false
    end

    handlers[messageType] = handler
    logQueueEvent(('Handler registered for message type: %s'):format(messageType))
    return true
end

-- =============================================================
-- إلغاء تسجيل معالج
-- =============================================================
function Queue.UnregisterHandler(messageType)
    handlers[messageType] = nil
end

-- =============================================================
-- إضافة عنصر إلى قائمة الانتظار
-- =============================================================
function Queue.Enqueue(options, callback)
    options = options or {}

    local messageType = options.messageType

    if type(messageType) ~= 'string' or messageType == '' then
        if callback then callback(false, { code = 'ERR_INVALID_FIELD' }) end
        return
    end

    if not handlers[messageType] then
        if callback then callback(false, { code = 'ERR_QUEUE_NO_HANDLER' }) end
        return
    end

    -- إصلاح 1: نسخ عميق للـ payload
    local payload = copyPayload(options.payload)

    -- إضافة نوع الرسالة إلى الـ payload
    payload._messageType = messageType

    local payloadJson = '{}'

    if Utils.SafeJsonEncode then
        local encoded = Utils.SafeJsonEncode(payload)

        if encoded then
            payloadJson = encoded
        end
    end

    local scheduledAtDatetime = nil

    if options.scheduledAt then
        scheduledAtDatetime = os.date('%Y-%m-%d %H:%M:%S', options.scheduledAt)
    end

    local expiresAtDatetime = nil

    if options.expiresAt then
        expiresAtDatetime = os.date('%Y-%m-%d %H:%M:%S', options.expiresAt)
    end

    local insertQuery = ('INSERT INTO %s (status, priority, attempts, max_attempts, payload_json, last_error, scheduled_at, expires_at, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, NOW())'):format(Database.GetTableName('message_queue'))

    Database.Insert(insertQuery, {
        'pending',
        options.priority or 0,
        0,
        options.maxAttempts or 3,
        payloadJson,
        nil,
        scheduledAtDatetime,
        expiresAtDatetime
    }, function(insertId, err)
        if err then
            logQueueError(('Failed to enqueue message: %s'):format(tostring(err)))
            if callback then callback(false, { code = 'ERR_DB_INSERT_FAILED', details = err }) end
            return
        end

        logQueueEvent(('Message enqueued: type=%s id=%d'):format(messageType, insertId))

        if callback then callback(true, { id = insertId }) end
    end)
end

-- =============================================================
-- جلب العناصر الجاهزة للمعالجة
-- =============================================================
local function fetchPendingItems(limit, callback)
    local selectQuery = ('SELECT * FROM %s WHERE status = ? AND (scheduled_at IS NULL OR scheduled_at <= NOW()) AND (expires_at IS NULL OR expires_at > NOW()) ORDER BY priority DESC, scheduled_at ASC, created_at ASC LIMIT ?'):format(Database.GetTableName('message_queue'))

    Database.Execute(selectQuery, { 'pending', limit }, function(results, err)
        if err then
            callback({}, err)
            return
        end

        callback(results or {}, nil)
    end)
end

-- =============================================================
-- تحديث حالة عنصر
-- =============================================================
local function updateItemStatus(itemId, status, lastError, callback)
    local updateQuery = ('UPDATE %s SET status = ?, last_error = ? WHERE id = ?'):format(Database.GetTableName('message_queue'))

    Database.Execute(updateQuery, { status, lastError, itemId }, function(_, err)
        if callback then callback(not err, err) end
    end)
end

-- =============================================================
-- معالجة عنصر واحد
--
-- إصلاح 3: استخدام دالة التحويل الموحدة لـ expires_at.
-- =============================================================
local function processItem(item, callback)
    local payload = nil

    if item.payload_json then
        if Utils.SafeJsonDecode then
            payload = Utils.SafeJsonDecode(item.payload_json)
        end
    end

    if not payload then
        payload = {}
    end

    -- إضافة معلومات العنصر إلى الـ payload
    payload._queueItemId = item.id
    payload._queueAttempts = item.attempts

    -- إصلاح 3: التحقق من انتهاء الصلاحية باستخدام الدالة الموحدة
    if item.expires_at then
        local expiresTimestamp = datetimeToTimestamp(item.expires_at)

        if expiresTimestamp and os.time() > expiresTimestamp then
            updateItemStatus(item.id, 'expired', 'Message expired before processing', function()
                callback(false, 'expired')
            end)
            return
        end
    end

    -- تحديد نوع الرسالة من الـ payload
    local messageType = payload._messageType or 'default'
    local handler = handlers[messageType]

    if not handler then
        handler = handlers['default']
    end

    if not handler then
        updateItemStatus(item.id, 'failed', 'No handler found for message type: ' .. tostring(messageType), function()
            callback(false, 'no_handler')
        end)
        return
    end

    -- تحديث الحالة إلى "قيد المعالجة"
    local updateQuery = ('UPDATE %s SET status = ?, attempts = attempts + 1 WHERE id = ?'):format(Database.GetTableName('message_queue'))

    Database.Execute(updateQuery, { 'processing', item.id }, function(_, err)
        if err then
            callback(false, err)
            return
        end

        -- استدعاء المعالج
        local ok, handlerErr = pcall(function()
            handler(payload, function(success, errorMessage)
                if success then
                    updateItemStatus(item.id, 'completed', nil, function()
                        callback(true, nil)
                    end)
                else
                    local newAttempts = (item.attempts or 0) + 1

                    if newAttempts >= (item.max_attempts or 3) then
                        updateItemStatus(item.id, 'failed', tostring(errorMessage), function()
                            callback(false, errorMessage)
                        end)
                    else
                        updateItemStatus(item.id, 'pending', tostring(errorMessage), function()
                            callback(false, errorMessage)
                        end)
                    end
                end
            end)
        end)

        if not ok then
            updateItemStatus(item.id, 'failed', 'Handler error: ' .. tostring(handlerErr), function()
                callback(false, handlerErr)
            end)
        end
    end)
end

-- =============================================================
-- معالجة قائمة الانتظار
-- =============================================================
function Queue.Process(callback)
    if isProcessing then
        if callback then callback(false, 'Already processing') end
        return
    end

    isProcessing = true

    fetchPendingItems(MAX_BATCH_SIZE, function(items, err)
        if err then
            isProcessing = false
            if callback then callback(false, err) end
            return
        end

        if #items == 0 then
            isProcessing = false
            if callback then callback(true, 0) end
            return
        end

        local processedCount = 0
        local pendingItems = #items

        for _, item in ipairs(items) do
            processItem(item, function(success)
                if success then
                    processedCount = processedCount + 1
                end

                pendingItems = pendingItems - 1

                if pendingItems <= 0 then
                    isProcessing = false

                    if processedCount > 0 then
                        logQueueEvent(('Queue processed: %d/%d items'):format(processedCount, #items))
                    end

                    if callback then callback(true, processedCount) end
                end
            end)
        end
    end)
end

-- =============================================================
-- تنظيف العناصر القديمة
-- =============================================================
function Queue.Cleanup(callback)
    local deleteCompletedQuery = ('DELETE FROM %s WHERE status = ? AND created_at < DATE_SUB(NOW(), INTERVAL 24 HOUR)'):format(Database.GetTableName('message_queue'))

    Database.Execute(deleteCompletedQuery, { 'completed' }, function(_, err1)
        local deleteExpiredQuery = ('DELETE FROM %s WHERE expires_at IS NOT NULL AND expires_at < NOW()'):format(Database.GetTableName('message_queue'))

        Database.Execute(deleteExpiredQuery, {}, function(_, err2)
            local deleteFailedQuery = ('DELETE FROM %s WHERE status = ? AND attempts >= max_attempts'):format(Database.GetTableName('message_queue'))

            Database.Execute(deleteFailedQuery, { 'failed' }, function(_, err3)
                if callback then callback(true) end
            end)
        end)
    end)
end

-- =============================================================
-- الحصول على إحصائيات قائمة الانتظار
-- =============================================================
function Queue.GetStats(callback)
    local statsQuery = ('SELECT status, COUNT(*) as count FROM %s GROUP BY status'):format(Database.GetTableName('message_queue'))

    Database.Execute(statsQuery, {}, function(results, err)
        if err then
            if callback then callback({}, err) end
            return
        end

        local stats = {
            pending = 0,
            processing = 0,
            completed = 0,
            failed = 0,
            cancelled = 0,
            expired = 0
        }

        if type(results) == 'table' then
            for _, row in ipairs(results) do
                stats[row.status] = row.count
            end
        end

        if callback then callback(stats, nil) end
    end)
end

-- =============================================================
-- إلغاء عنصر في قائمة الانتظار
-- =============================================================
function Queue.Cancel(itemId, callback)
    if not itemId or itemId <= 0 then
        if callback then callback(false, 'Invalid item ID') end
        return
    end

    local updateQuery = ('UPDATE %s SET status = ? WHERE id = ? AND status IN (?, ?)'):format(Database.GetTableName('message_queue'))

    Database.Execute(updateQuery, { 'cancelled', itemId, 'pending', 'processing' }, function(_, err)
        if err then
            if callback then callback(false, err) end
            return
        end

        if callback then callback(true, nil) end
    end)
end

-- =============================================================
-- إعادة محاولة عنصر فاشل
-- =============================================================
function Queue.Retry(itemId, callback)
    if not itemId or itemId <= 0 then
        if callback then callback(false, 'Invalid item ID') end
        return
    end

    local updateQuery = ('UPDATE %s SET status = ?, attempts = 0, last_error = NULL WHERE id = ? AND status = ?'):format(Database.GetTableName('message_queue'))

    Database.Execute(updateQuery, { 'pending', itemId, 'failed' }, function(_, err)
        if err then
            if callback then callback(false, err) end
            return
        end

        if callback then callback(true, nil) end
    end)
end

-- =============================================================
-- مهمة دورية لمعالجة قائمة الانتظار
-- =============================================================
CreateThread(function()
    while true do
        Wait(PROCESS_INTERVAL_MS)

        if Database.IsReady() then
            Queue.Process()
        end
    end
end)

-- =============================================================
-- مهمة دورية لتنظيف قائمة الانتظار
-- =============================================================
CreateThread(function()
    while true do
        Wait(CLEANUP_INTERVAL_MS)

        if Database.IsReady() then
            Queue.Cleanup()
        end
    end
end)

-- =============================================================
-- رسالة تحميل ناجحة
-- =============================================================
if Logger.Debug then
    Logger.Debug('server/core/queue.lua loaded')
elseif OxSecure.Console and type(OxSecure.Console.debug) == 'function' then
    OxSecure.Console.debug('server/core/queue.lua loaded')
end
