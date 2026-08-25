-- =============================================================
-- ox_lib_secure
-- File: server/modules/error_handler.lua
-- Description:
--   وحدة معالجة الأخطاء العامة لنظام ox_lib_secure.
--
-- Notes:
--   - يوفر أغلفة آمنة لاستدعاء الدوال.
--   - يسجل الأخطاء غير المتوقعة في اللوجات.
--   - يوفر آلية تعافي من الأخطاء.
--   - يتكامل مع وحدة الأخطاء والإشعارات.
--   - إصلاح: SafeCallWithRetry تعيد المحاولة فعليًا.
--   - إصلاح: AsyncSafeCallWithRetry تستدعي الدالة مرة واحدة.
-- =============================================================

Config = Config or {}
OxSecure = OxSecure or {}
OxSecure.ErrorHandler = OxSecure.ErrorHandler or {}

local ErrorHandler = OxSecure.ErrorHandler
local Logger = OxSecure.Logger or {}
local Errors = OxSecure.Errors or {}
local Logs = OxSecure.Logs or {}
local Audit = OxSecure.Audit or {}

local errorHandlerConfig = Config.ErrorHandler or {}
local MAX_ERROR_HISTORY = errorHandlerConfig.MaxErrorHistory or 100
local ERROR_COOLDOWN_SECONDS = errorHandlerConfig.ErrorCooldownSeconds or 5

-- سجل الأخطاء الأخيرة
local recentErrors = {}
local lastErrorTimes = {}
local totalErrorsCaught = 0
local isInitialized = false

-- =============================================================
-- أدوات مساعدة داخلية
-- =============================================================
local function logErrorHandlerEvent(message, options)
    if Logger.Info then
        Logger.Info(message, options or {
            category = 'error_handler',
            eventCode = 'error_handler_event'
        })
    end
end

local function logErrorHandlerError(message, options)
    if Logger.Error then
        Logger.Error(message, options or {
            category = 'error_handler',
            eventCode = 'error_handler_error'
        })
    end
end

-- =============================================================
-- التحقق من معدل الأخطاء (لمنع الفيضان)
-- =============================================================
local function isRateLimited(errorKey)
    local now = os.time()
    local lastTime = lastErrorTimes[errorKey]

    if lastTime and (now - lastTime) < ERROR_COOLDOWN_SECONDS then
        return true
    end

    lastErrorTimes[errorKey] = now
    return false
end

-- =============================================================
-- إضافة خطأ إلى السجل المحلي
-- =============================================================
local function addToErrorHistory(errorInfo)
    recentErrors[#recentErrors + 1] = errorInfo

    while #recentErrors > MAX_ERROR_HISTORY do
        table.remove(recentErrors, 1)
    end

    totalErrorsCaught = totalErrorsCaught + 1
end

-- =============================================================
-- تهيئة معالج الأخطاء
-- =============================================================
function ErrorHandler.Initialize()
    if isInitialized then
        return
    end

    isInitialized = true

    logErrorHandlerEvent('Error handler initialized')

    AddEventHandler('onResourceStop', function(resourceName)
        if resourceName == GetCurrentResourceName() then
            logErrorHandlerEvent(('Error handler shutdown. Total errors caught: %d'):format(totalErrorsCaught))
        end
    end)
end

-- =============================================================
-- تنفيذ دالة بشكل آمن مع التقاط الأخطاء
-- =============================================================
function ErrorHandler.SafeCall(fn, context, ...)
    if type(fn) ~= 'function' then
        return false, 'Invalid function provided'
    end

    context = context or 'unknown'

    local results = { pcall(fn, ...) }
    local ok = results[1]

    if ok then
        return true, select(2, table.unpack(results))
    else
        local errorMessage = tostring(results[2])
        local errorKey = context .. ':' .. errorMessage:sub(1, 100)

        if not isRateLimited(errorKey) then
            local errorInfo = {
                context = context,
                message = errorMessage,
                timestamp = os.time(),
                stackTrace = debug.traceback('', 2)
            }

            addToErrorHistory(errorInfo)

            logErrorHandlerError(('Error caught in %s: %s'):format(context, errorMessage))

            if Logs.Error then
                Logs.Error(('SafeCall error in %s: %s'):format(context, errorMessage), {
                    category = 'error_handler',
                    eventCode = 'safe_call_error',
                    meta = {
                        context = context,
                        errorMessage = errorMessage
                    }
                })
            end
        end

        return false, errorMessage
    end
end

-- =============================================================
-- تنفيذ دالة بشكل آمن مع إعادة المحاولة (متزامن)
--
-- إصلاح: إعادة المحاولة تتم فعليًا في حلقة متزامنة.
-- لا يوجد تأخير بين المحاولات لأن البيئة المتزامنة
-- لا تدعم الانتظار غير المتزامن. إذا كان التأخير مطلوبًا،
-- استخدم AsyncSafeCallWithRetry بدلاً من ذلك.
-- =============================================================
function ErrorHandler.SafeCallWithRetry(fn, context, options, ...)
    options = options or {}

    local maxRetries = options.maxRetries or 3
    local onRetry = options.onRetry

    local attempt = 0
    local lastError = nil

    while attempt < maxRetries do
        attempt = attempt + 1

        local ok, result = ErrorHandler.SafeCall(fn, context, ...)

        if ok then
            return true, result
        end

        lastError = result

        if attempt < maxRetries and onRetry then
            pcall(onRetry, attempt, lastError)
        end

        if attempt < maxRetries then
            logErrorHandlerEvent(('Retrying %s (attempt %d/%d)'):format(context, attempt, maxRetries))
        end
    end

    return false, lastError
end

-- =============================================================
-- تنفيذ دالة بشكل آمن مع إعادة محاولة غير متزامنة
--
-- إصلاح: استدعاء الدالة مرة واحدة فقط عبر SafeCall.
-- =============================================================
function ErrorHandler.AsyncSafeCallWithRetry(fn, context, options, callback, ...)
    options = options or {}

    local maxRetries = options.maxRetries or 3
    local retryDelayMs = options.retryDelayMs or 1000
    local onRetry = options.onRetry

    local attempt = 0
    local args = { ... }

    local function tryOnce()
        attempt = attempt + 1

        -- إصلاح: استدعاء الدالة مرة واحدة فقط
        local ok, result = ErrorHandler.SafeCall(fn, context, table.unpack(args))

        if ok then
            if callback then callback(true, result) end
            return
        end

        local lastError = result

        if attempt < maxRetries then
            if onRetry then
                pcall(onRetry, attempt, lastError)
            end

            logErrorHandlerEvent(('Async retrying %s (attempt %d/%d)'):format(context, attempt, maxRetries))

            SetTimeout(retryDelayMs, tryOnce)
        else
            if callback then callback(false, lastError) end
        end
    end

    tryOnce()
end

-- =============================================================
-- حماية حدث (Event Handler) من الأخطاء
-- =============================================================
function ErrorHandler.ProtectHandler(handlerFn, eventName)
    if type(handlerFn) ~= 'function' then
        return function() end
    end

    eventName = eventName or 'unknown_event'

    return function(...)
        local ok, err = ErrorHandler.SafeCall(handlerFn, eventName, ...)

        if not ok then
            logErrorHandlerError(('Event handler error in %s: %s'):format(eventName, tostring(err)))

            if Errors.Log then
                Errors.Log({
                    errorCode = 'ERR_EVENT_HANDLER_FAILED',
                    title = 'خطأ في معالج الحدث',
                    body = ('حدث خطأ في معالج الحدث: %s'):format(eventName),
                    severity = 'error',
                    meta = {
                        eventName = eventName,
                        errorMessage = tostring(err)
                    }
                })
            end
        end
    end
end

-- =============================================================
-- حماية خيط (Thread) من الأخطاء
-- =============================================================
function ErrorHandler.ProtectThread(threadFn, threadName)
    if type(threadFn) ~= 'function' then
        return
    end

    threadName = threadName or 'unknown_thread'

    CreateThread(function()
        local ok, err = ErrorHandler.SafeCall(threadFn, threadName)

        if not ok then
            logErrorHandlerError(('Thread error in %s: %s'):format(threadName, tostring(err)))
        end
    end)
end

-- =============================================================
-- الحصول على الأخطاء الأخيرة
-- =============================================================
function ErrorHandler.GetRecentErrors(limit)
    limit = limit or 20

    local result = {}
    local startIndex = math.max(1, #recentErrors - limit + 1)

    for i = startIndex, #recentErrors do
        result[#result + 1] = recentErrors[i]
    end

    return result
end

-- =============================================================
-- الحصول على إحصائيات معالج الأخطاء
-- =============================================================
function ErrorHandler.GetStats()
    return {
        totalErrorsCaught = totalErrorsCaught,
        recentErrorsCount = #recentErrors,
        maxErrorHistory = MAX_ERROR_HISTORY,
        isInitialized = isInitialized
    }
end

-- =============================================================
-- مسح سجل الأخطاء المحلي
-- =============================================================
function ErrorHandler.ClearHistory()
    recentErrors = {}
    lastErrorTimes = {}
    logErrorHandlerEvent('Error history cleared')
end

-- =============================================================
-- الإبلاغ عن خطأ حرج
-- =============================================================
function ErrorHandler.ReportCritical(context, errorMessage, meta)
    local errorInfo = {
        context = context,
        message = errorMessage,
        timestamp = os.time(),
        severity = 'critical',
        meta = meta
    }

    addToErrorHistory(errorInfo)

    logErrorHandlerError(('CRITICAL ERROR in %s: %s'):format(context, tostring(errorMessage)))

    if Logs.Critical then
        Logs.Critical(('CRITICAL: %s - %s'):format(context, tostring(errorMessage)), {
            category = 'error_handler',
            eventCode = 'critical_error',
            meta = meta
        })
    end

    if Audit.RecordSystemAction then
        Audit.RecordSystemAction('critical_error', 'system', context, {
            errorMessage = tostring(errorMessage),
            meta = meta
        })
    end
end

-- =============================================================
-- تهيئة عند التحميل
-- =============================================================
ErrorHandler.Initialize()

-- =============================================================
-- رسالة تحميل ناجحة
-- =============================================================
if Logger.Debug then
    Logger.Debug('server/modules/error_handler.lua loaded')
elseif OxSecure.Console and type(OxSecure.Console.debug) == 'function' then
    OxSecure.Console.debug('server/modules/error_handler.lua loaded')
end
