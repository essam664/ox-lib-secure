-- =============================================================
-- ox_lib_secure
-- File: server/core/queue.lua
-- Description:
--   وحدة قائمة الانتظار لنظام ox_lib_secure.
--   تدير المهام المؤجلة والمعالجة غير المتزامنة.
--
-- Notes:
--   - مواءمة 100% مع config/main.lua النهائي.
--   - جدول الترحيلات: oxsecure_message_queue.
--   - أعمدة الجدول: status, priority, attempts, max_attempts,
--     payload_json, last_error, scheduled_at, expires_at, created_at.
--   - معالجة دفعات (batch) مع إعادة محاولة.
--   - تنظيف دوري للمهام المنتهية.
--   - إصلاح: إحصائية totalFailed متسقة في جميع الحالات.
--   - إصلاح: حماية json.encode بـ pcall في Enqueue.
-- =============================================================

Config = Config or {}
OxSecure = OxSecure or {}
OxSecure.Queue = OxSecure.Queue or {}

local Queue = OxSecure.Queue
local Logger = OxSecure.Logger or {}
local Database = OxSecure.Database or {}
local Audit = OxSecure.Audit or {}

-- =============================================================
-- قراءة الإعدادات من الكونفق
-- متوافقة حرفيًا مع config/main.lua
-- =============================================================
local queueConfig = Config.Queue or {}

local ENABLED = queueConfig.Enabled ~= false
local MAX_QUEUE_SIZE = queueConfig.MaxQueueSize or 1000
local PROCESS_INTERVAL_MS = queueConfig.ProcessIntervalMs or 1000
local MAX_ATTEMPTS = queueConfig.MaxAttempts or 3
local RETRY_DELAY_MS = queueConfig.RetryDelayMs or 5000
local MAX_BATCH_SIZE = queueConfig.MaxBatchSize or 10
local CLEANUP_INTERVAL_MS = queueConfig.CleanupIntervalMs or 60000
local CLEANUP_AFTER_DAYS = queueConfig.CleanupAfterDays or 7

-- =============================================================
-- الحالة الداخلية
-- =============================================================
local memoryQueue = {}
local queueHandlers = {}
local isInitialized = false
local isProcessing = false
local totalProcessed = 0
local totalFailed = 0

-- =============================================================
-- أدوات مساعدة داخلية
-- =============================================================
local function logQueue(message, level)
    level = level or 'info'
    if Logger and Logger.Log then
        Logger.Log(level, message, { category = 'queue' })
    else
        print(('[ox_lib_secure] [QUEUE] %s'):format(message))
    end
end

local function getCurrentTimestamp()
    return os.time()
end

-- =============================================================
-- الحصول على اسم جدول قائمة الانتظار
-- =============================================================
local function getQueueTableName()
    if Database and Database.GetTableName then
        local ok, name = pcall(Database.GetTableName, 'message_queue')
        if ok and name then
            return name
        end
    end
    return 'oxsecure_message_queue'
end

-- =============================================================
-- تهيئة وحدة قائمة الانتظار
-- =============================================================
function Queue.Initialize()
    if isInitialized then
        return true
    end

    if not ENABLED then
        logQueue('Queue system is disabled.')
        return true
    end

    logQueue('Initializing queue system...')
    logQueue(('Max queue size: %d'):format(MAX_QUEUE_SIZE))
    logQueue(('Process interval: %d ms'):format(PROCESS_INTERVAL_MS))
    logQueue(('Max attempts: %d'):format(MAX_ATTEMPTS))
    logQueue(('Max batch size: %d'):format(MAX_BATCH_SIZE))
    logQueue(('Cleanup interval: %d ms'):format(CLEANUP_INTERVAL_MS))

    -- بدء حلقة المعالجة
    CreateThread(function()
        while true do
            Wait(PROCESS_INTERVAL_MS)
            Queue.ProcessBatch()
        end
    end)

    -- بدء التنظيف الدوري
    CreateThread(function()
        while true do
            Wait(CLEANUP_INTERVAL_MS)
            Queue.Cleanup()
        end
    end)

    isInitialized = true
    logQueue('Queue system initialized successfully.')
    return true
end

-- =============================================================
-- التحقق من حالة التهيئة
-- =============================================================
function Queue.IsInitialized()
    return isInitialized
end

-- =============================================================
-- تسجيل معالج نوع مهمة
-- =============================================================
function Queue.RegisterHandler(queueType, handler)
    if not queueType or not handler then
        return false, 'Queue type and handler are required'
    end

    if type(handler) ~= 'function' then
        return false, 'Handler must be a function'
    end

    queueHandlers[queueType] = handler
    logQueue(('Registered handler for queue type: %s'):format(queueType))
    return true
end

-- =============================================================
-- إلغاء تسجيل معالج
-- =============================================================
function Queue.UnregisterHandler(queueType)
    if queueHandlers[queueType] then
        queueHandlers[queueType] = nil
        return true
    end
    return false
end

-- =============================================================
-- إضافة مهمة إلى قائمة الانتظار (الذاكرة)
-- إصلاح: حماية json.encode بـ pcall
-- =============================================================
function Queue.Enqueue(payload, options)
    if not ENABLED then
        return nil, 'Queue system is disabled'
    end

    if not payload then
        return nil, 'Payload is required'
    end

    options = options or {}

    -- التحقق من حجم قائمة الانتظار
    local currentSize = #memoryQueue
    if currentSize >= MAX_QUEUE_SIZE then
        return nil, 'Queue is full'
    end

    -- إنشاء المهمة
    local task = {
        id = ('task_%d_%d'):format(getCurrentTimestamp(), math.random(10000, 99999)),
        queueType = options.queueType or 'default',
        payload = payload,
        status = 'pending',
        priority = options.priority or 0,
        attempts = 0,
        maxAttempts = options.maxAttempts or MAX_ATTEMPTS,
        scheduledAt = options.scheduledAt,
        expiresAt = options.expiresAt,
        createdAt = getCurrentTimestamp(),
        lastError = nil
    }

    -- إضافة إلى قائمة الذاكرة
    memoryQueue[#memoryQueue + 1] = task

    -- حفظ في قاعدة البيانات (غير متزامن)
    -- إصلاح: استخدام pcall لحماية من أخطاء الترميز
    if Database and Database.Execute then
        local tableName = getQueueTableName()

        local ok, payloadJson = pcall(json.encode, payload)

        if ok and payloadJson then
            Database.Execute(
                ('INSERT INTO %s (status, priority, attempts, max_attempts, payload_json, scheduled_at, expires_at) VALUES (?, ?, ?, ?, ?, ?, ?)'):format(tableName),
                {
                    task.status,
                    task.priority,
                    task.attempts,
                    task.maxAttempts,
                    payloadJson,
                    task.scheduledAt and os.date('%Y-%m-%d %H:%M:%S', task.scheduledAt) or nil,
                    task.expiresAt and os.date('%Y-%m-%d %H:%M:%S', task.expiresAt) or nil
                }
            )
        else
            logQueue(('Failed to encode payload for task %s: %s'):format(task.id, tostring(payloadJson)), 'warn')
        end
    end

    return task.id
end

-- =============================================================
-- معالجة دفعة من المهام
-- إصلاح: إحصائية totalFailed متسقة في جميع الحالات
-- =============================================================
function Queue.ProcessBatch()
    if not ENABLED then
        return
    end

    if isProcessing then
        return
    end

    if #memoryQueue == 0 then
        return
    end

    isProcessing = true

    local now = getCurrentTimestamp()
    local processed = 0
    local failed = 0
    local batchCount = 0

    -- ترتيب حسب الأولوية
    table.sort(memoryQueue, function(a, b)
        return a.priority > b.priority
    end)

    -- معالجة المهام
    local i = 1
    while i <= #memoryQueue and batchCount < MAX_BATCH_SIZE do
        local task = memoryQueue[i]

        -- التحقق من الجدولة
        if task.scheduledAt and task.scheduledAt > now then
            i = i + 1
            goto continue
        end

        -- التحقق من انتهاء الصلاحية
        if task.expiresAt and task.expiresAt < now then
            task.status = 'expired'
            table.remove(memoryQueue, i)
            goto continue
        end

        -- البحث عن المعالج
        local handler = queueHandlers[task.queueType]

        if not handler then
            task.status = 'failed'
            task.lastError = 'No handler registered for type: ' .. tostring(task.queueType)
            table.remove(memoryQueue, i)
            failed = failed + 1
            totalFailed = totalFailed + 1
            logQueue(('Task failed: no handler for type: %s'):format(task.queueType), 'warn')
            goto continue
        end

        -- محاولة تنفيذ المهمة
        local ok, err = pcall(handler, task.payload)

        if ok then
            task.status = 'completed'
            table.remove(memoryQueue, i)
            processed = processed + 1
            totalProcessed = totalProcessed + 1
        else
            task.attempts = task.attempts + 1
            task.lastError = tostring(err)

            if task.attempts >= task.maxAttempts then
                task.status = 'failed'
                table.remove(memoryQueue, i)
                failed = failed + 1
                totalFailed = totalFailed + 1

                logQueue(('Task failed permanently: %s (type: %s)'):format(task.id, task.queueType), 'warn')
            else
                -- إعادة المحاولة لاحقًا
                task.scheduledAt = now + math.floor(RETRY_DELAY_MS / 1000)
                i = i + 1
            end
        end

        batchCount = batchCount + 1

        ::continue::
    end

    if processed > 0 or failed > 0 then
        logQueue(('Batch processed: %d completed, %d failed'):format(processed, failed))
    end

    isProcessing = false
end

-- =============================================================
-- إزالة مهمة من قائمة الانتظار
-- =============================================================
function Queue.RemoveTask(taskId)
    if not taskId then
        return false
    end

    for i, task in ipairs(memoryQueue) do
        if task.id == taskId then
            table.remove(memoryQueue, i)
            return true
        end
    end

    return false
end

-- =============================================================
-- إلغاء جميع المهام من نوع معين
-- =============================================================
function Queue.CancelByType(queueType)
    if not queueType then
        return 0
    end

    local cancelled = 0
    local i = 1

    while i <= #memoryQueue do
        if memoryQueue[i].queueType == queueType then
            table.remove(memoryQueue, i)
            cancelled = cancelled + 1
        else
            i = i + 1
        end
    end

    return cancelled
end

-- =============================================================
-- الحصول على مهمة
-- =============================================================
function Queue.GetTask(taskId)
    if not taskId then
        return nil
    end

    for _, task in ipairs(memoryQueue) do
        if task.id == taskId then
            return task
        end
    end

    return nil
end

-- =============================================================
-- الحصول على جميع المهام
-- =============================================================
function Queue.GetAllTasks()
    return memoryQueue
end

-- =============================================================
-- الحصول على عدد المهام المعلقة
-- =============================================================
function Queue.GetPendingCount()
    local count = 0
    for _, task in ipairs(memoryQueue) do
        if task.status == 'pending' then
            count = count + 1
        end
    end
    return count
end

-- =============================================================
-- تنظيف دوري
-- =============================================================
function Queue.Cleanup()
    local now = getCurrentTimestamp()
    local cleaned = 0

    -- إزالة المهام المنتهية من الذاكرة
    local i = 1
    while i <= #memoryQueue do
        local task = memoryQueue[i]

        if task.expiresAt and task.expiresAt < now then
            table.remove(memoryQueue, i)
            cleaned = cleaned + 1
        elseif task.status == 'completed' or task.status == 'failed' then
            table.remove(memoryQueue, i)
            cleaned = cleaned + 1
        else
            i = i + 1
        end
    end

    -- تنظيف قاعدة البيانات
    if Database and Database.Execute then
        local tableName = getQueueTableName()
        local cutoffDate = os.date('%Y-%m-%d %H:%M:%S', now - (CLEANUP_AFTER_DAYS * 86400))

        Database.Execute(
            ('DELETE FROM %s WHERE status IN (?, ?, ?) AND created_at < ?'):format(tableName),
            { 'completed', 'failed', 'expired', cutoffDate }
        )
    end

    if cleaned > 0 then
        logQueue(('Cleanup: removed %d tasks'):format(cleaned))
    end
end

-- =============================================================
-- إحصائيات
-- =============================================================
function Queue.GetStats()
    local pendingCount = 0
    local typeCounts = {}

    for _, task in ipairs(memoryQueue) do
        if task.status == 'pending' then
            pendingCount = pendingCount + 1
        end

        if not typeCounts[task.queueType] then
            typeCounts[task.queueType] = 0
        end
        typeCounts[task.queueType] = typeCounts[task.queueType] + 1
    end

    return {
        totalInMemory = #memoryQueue,
        pending = pendingCount,
        totalProcessed = totalProcessed,
        totalFailed = totalFailed,
        maxQueueSize = MAX_QUEUE_SIZE,
        maxBatchSize = MAX_BATCH_SIZE,
        maxAttempts = MAX_ATTEMPTS,
        processIntervalMs = PROCESS_INTERVAL_MS,
        cleanupIntervalMs = CLEANUP_INTERVAL_MS,
        typeCounts = typeCounts,
        isEnabled = ENABLED,
        isInitialized = isInitialized,
        isProcessing = isProcessing
    }
end

-- =============================================================
-- تهيئة عند التحميل
-- =============================================================
Queue.Initialize()

-- =============================================================
-- رسالة تحميل ناجحة
-- =============================================================
if Logger and Logger.Debug then
    Logger.Debug('server/core/queue.lua loaded')
else
    print('[ox_lib_secure] server/core/queue.lua loaded')
end
