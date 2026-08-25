-- =============================================================
-- ox_lib_secure
-- File: server/core/errors.lua
-- Description:
--   طبقة الأخطاء لنظام ox_lib_secure.
--
-- Notes:
--   - يتم إرسال الأخطاء إلى اللاعبين عبر الإشعارات.
--   - يتم حفظ الأخطاء في قاعدة البيانات.
--   - يتم تصنيف الأخطاء حسب الخطورة والفئة.
--   - يتم التكامل مع نظام الترجمة.
--   - الفلترة حسب رمز الخطأ بدلاً من الفئة.
--   - يتم التحقق من نتيجة الإرسال قبل الحفظ.
--   - يتم دمج بيانات الـ meta المخصصة مع بيانات النظام.
-- =============================================================

Config = Config or {}
OxSecure = OxSecure or {}
OxSecure.Errors = OxSecure.Errors or {}

local Errors = OxSecure.Errors
local Database = OxSecure.Database or {}
local Logger = OxSecure.Logger or {}
local Utils = OxSecure.Utils or {}
local Localization = OxSecure.Localization or {}
local Notifications = OxSecure.Notifications or {}
local RateLimiter = OxSecure.RateLimiter or {}

local errorsConfig = Config.Errors or {}
local ALLOWED_SEVERITIES = errorsConfig.AllowedSeverities or { 'info', 'warning', 'error', 'critical' }
local ALLOWED_CATEGORIES = errorsConfig.AllowedCategories or {
    'general', 'database', 'security', 'notification',
    'permission', 'rate_limit', 'system', 'player', 'session'
}

-- =============================================================
-- أدوات مساعدة داخلية
-- =============================================================
local function logErrorEvent(message, options)
    if Logger.Info then
        Logger.Info(message, options or {
            category = 'error',
            eventCode = 'error_event'
        })
    end
end

local function logErrorError(message, options)
    if Logger.Error then
        Logger.Error(message, options or {
            category = 'error',
            eventCode = 'error_handler_error'
        })
    end
end

-- =============================================================
-- التحقق من صحة الخطورة
-- =============================================================
local function isValidSeverity(severity)
    for _, validSeverity in ipairs(ALLOWED_SEVERITIES) do
        if severity == validSeverity then
            return true
        end
    end

    return false
end

-- =============================================================
-- التحقق من صحة الفئة
-- =============================================================
local function isValidCategory(category)
    for _, validCategory in ipairs(ALLOWED_CATEGORIES) do
        if category == validCategory then
            return true
        end
    end

    return false
end

-- =============================================================
-- التحقق من صحة نمط التصميم
-- =============================================================
local function isValidDesignStyle(designStyle)
    local uiConfig = Config.UI or {}
    local allowedStyles = uiConfig.AllowedDesignStyles or {
        'default', 'purple_glass', 'glass', 'critical',
        'purple', 'gold', 'info', 'warning', 'success', 'error'
    }

    for _, validStyle in ipairs(allowedStyles) do
        if designStyle == validStyle then
            return true
        end
    end

    return false
end

-- =============================================================
-- إصلاح: دمج بيانات الـ meta المخصصة مع بيانات النظام
-- =============================================================
local function buildSavedMeta(userMeta, systemMeta)
    local savedMeta = {}

    -- نسخ بيانات المستخدم المخصصة أولاً
    if type(userMeta) == 'table' then
        for key, value in pairs(userMeta) do
            savedMeta[key] = value
        end
    end

    -- إضافة بيانات النظام (تتجاوز أي مفاتيح متشابهة)
    if type(systemMeta) == 'table' then
        for key, value in pairs(systemMeta) do
            savedMeta[key] = value
        end
    end

    return savedMeta
end

-- =============================================================
-- حفظ خطأ في قاعدة البيانات
-- =============================================================
local function saveToDatabase(entry)
    if not Database.IsReady() then
        return
    end

    if not Config.Database.SaveErrors then
        return
    end

    local metaJson = nil

    if entry.meta ~= nil and Utils.SafeJsonEncode then
        metaJson = Utils.SafeJsonEncode(entry.meta)
    end

    local insertQuery = ('INSERT INTO %s (error_code, title_ar, body_ar, severity, design_style, source_system_id, player_id, server_player_id, discord_id, log_id, stack_ref, is_handled, meta_json, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())'):format(Database.GetTableName('errors'))

    Database.Execute(insertQuery, {
        entry.errorCode or 'ERR_UNKNOWN',
        entry.title or '',
        entry.body or '',
        entry.severity or 'error',
        entry.designStyle or 'error',
        entry.sourceSystemId,
        entry.playerId,
        entry.serverPlayerId,
        entry.discordId,
        entry.logId,
        entry.stackRef,
        entry.isHandled and 1 or 0,
        metaJson
    }, function(_, err)
        if err then
            logErrorError(('Failed to save error to DB: %s'):format(tostring(err)))
        end
    end)
end

-- =============================================================
-- إرسال خطأ إلى لاعب
-- =============================================================
function Errors.Send(source, options, callback)
    options = options or {}

    local serverId = tonumber(source)

    if not serverId or serverId <= 0 then
        if callback then callback(false, { code = 'ERR_INVALID_SOURCE' }) end
        return
    end

    local errorCode = options.errorCode or 'ERR_UNKNOWN'

    -- التحقق من معدل الاستخدام
    if RateLimiter.Check then
        local allowed, rateError = RateLimiter.Check(serverId, 'error')

        if not allowed then
            if callback then callback(false, { code = 'ERR_RATE_LIMIT' }) end
            return
        end
    end

    -- جلب معلومات الخطأ من الترجمة
    local errorInfo = nil

    if Localization.GetError then
        errorInfo = Localization.GetError(errorCode, options.data)
    end

    if not errorInfo then
        errorInfo = {
            code = errorCode,
            title = options.title or 'خطأ غير معروف',
            body = options.body or 'حدث خطأ غير متوقع في النظام.',
            severity = options.severity or 'error',
            designStyle = options.designStyle or 'error',
            durationMs = options.durationMs or 6000,
            category = options.category or 'general'
        }
    end

    -- تحديد الخطورة
    local severity = options.severity or errorInfo.severity or 'error'

    if not isValidSeverity(severity) then
        severity = 'error'
    end

    -- تحديد الفئة
    local category = options.category or errorInfo.category or 'general'

    if not isValidCategory(category) then
        category = 'general'
    end

    -- تحديد نمط التصميم مع التحقق من صحته
    local designStyle = options.designStyle or errorInfo.designStyle or 'error'

    if not isValidDesignStyle(designStyle) then
        designStyle = 'error'
    end

    -- تحديد المدة
    local durationMs = options.durationMs or errorInfo.durationMs or 6000

    -- تحديد نوع الإشعار بناءً على الخطورة
    local notificationType = 'error'

    if severity == 'critical' then
        notificationType = 'critical'
    elseif severity == 'warning' then
        notificationType = 'warning'
    elseif severity == 'info' then
        notificationType = 'info'
    end

    -- إرسال الإشعار
    if Notifications.Send then
        Notifications.Send(serverId, {
            type = notificationType,
            title = errorInfo.title,
            body = errorInfo.body,
            designStyle = designStyle,
            durationMs = durationMs,
            meta = {
                errorCode = errorCode,
                category = category,
                severity = severity
            }
        }, function(sent, sendResult)
            local deliveryStatus = sent and 'delivered' or 'failed'

            -- إصلاح: دمج بيانات المستخدم المخصصة مع بيانات النظام
            local savedMeta = buildSavedMeta(options.meta, {
                category = category,
                deliveryStatus = deliveryStatus
            })

            saveToDatabase({
                errorCode = errorCode,
                title = errorInfo.title,
                body = errorInfo.body,
                severity = severity,
                designStyle = designStyle,
                serverPlayerId = serverId,
                playerId = options.playerId,
                discordId = options.discordId,
                sourceSystemId = options.sourceSystemId,
                logId = options.logId,
                stackRef = options.stackRef,
                isHandled = options.isHandled ~= false,
                meta = savedMeta
            })

            if sent then
                logErrorEvent(('Error sent to player %d: code=%s severity=%s'):format(serverId, errorCode, severity))
            else
                logErrorError(('Error delivery failed for player %d: code=%s'):format(serverId, errorCode))
            end

            if callback then callback(sent, { errorCode = errorCode, severity = severity }) end
        end)
    else
        -- إذا لم يكن نظام الإشعارات متاحًا، نحفظ فقط
        local savedMeta = buildSavedMeta(options.meta, {
            category = category,
            deliveryStatus = 'skipped'
        })

        saveToDatabase({
            errorCode = errorCode,
            title = errorInfo.title,
            body = errorInfo.body,
            severity = severity,
            designStyle = designStyle,
            serverPlayerId = serverId,
            playerId = options.playerId,
            discordId = options.discordId,
            sourceSystemId = options.sourceSystemId,
            logId = options.logId,
            stackRef = options.stackRef,
            isHandled = options.isHandled ~= false,
            meta = savedMeta
        })

        if callback then callback(true, { errorCode = errorCode, severity = severity }) end
    end
end

-- =============================================================
-- إرسال خطأ حرج إلى لاعب
-- =============================================================
function Errors.SendCritical(source, errorCode, options, callback)
    options = options or {}
    options.errorCode = errorCode
    options.severity = 'critical'
    options.designStyle = options.designStyle or 'critical'

    Errors.Send(source, options, callback)
end

-- =============================================================
-- إرسال خطأ أمان إلى لاعب
-- =============================================================
function Errors.SendSecurityError(source, errorCode, options, callback)
    options = options or {}
    options.errorCode = errorCode
    options.severity = options.severity or 'warning'
    options.category = 'security'

    Errors.Send(source, options, callback)
end

-- =============================================================
-- إرسال خطأ قاعدة بيانات إلى لاعب
-- =============================================================
function Errors.SendDatabaseError(source, options, callback)
    options = options or {}
    options.errorCode = options.errorCode or 'ERR_DB_QUERY_FAILED'
    options.severity = options.severity or 'error'
    options.category = 'database'

    Errors.Send(source, options, callback)
end

-- =============================================================
-- إرسال خطأ صلاحيات إلى لاعب
-- =============================================================
function Errors.SendPermissionError(source, options, callback)
    options = options or {}
    options.errorCode = options.errorCode or 'ERR_PERMISSION_DENIED'
    options.severity = options.severity or 'warning'
    options.category = 'permission'

    Errors.Send(source, options, callback)
end

-- =============================================================
-- إرسال خطأ معدل استخدام إلى لاعب
-- =============================================================
function Errors.SendRateLimitError(source, options, callback)
    options = options or {}
    options.errorCode = options.errorCode or 'ERR_RATE_LIMIT'
    options.severity = options.severity or 'warning'
    options.category = 'rate_limit'

    Errors.Send(source, options, callback)
end

-- =============================================================
-- تسجيل خطأ بدون إرسال إشعار (للتسجيل فقط)
-- =============================================================
function Errors.Log(entry)
    entry = entry or {}

    saveToDatabase({
        errorCode = entry.errorCode or 'ERR_UNKNOWN',
        title = entry.title or '',
        body = entry.body or '',
        severity = entry.severity or 'error',
        designStyle = entry.designStyle or 'error',
        serverPlayerId = entry.serverPlayerId,
        playerId = entry.playerId,
        discordId = entry.discordId,
        sourceSystemId = entry.sourceSystemId,
        logId = entry.logId,
        stackRef = entry.stackRef,
        isHandled = entry.isHandled ~= false,
        meta = entry.meta
    })
end

-- =============================================================
-- جلب الأخطاء من قاعدة البيانات
-- =============================================================
function Errors.GetErrors(options, callback)
    options = options or {}

    local limit = options.limit or 50
    local offset = options.offset or 0

    local query = nil
    local params = {}

    if options.severity then
        query = ('SELECT * FROM %s WHERE severity = ? ORDER BY created_at DESC LIMIT ? OFFSET ?'):format(Database.GetTableName('errors'))
        params = { options.severity, limit, offset }
    elseif options.errorCode then
        query = ('SELECT * FROM %s WHERE error_code = ? ORDER BY created_at DESC LIMIT ? OFFSET ?'):format(Database.GetTableName('errors'))
        params = { options.errorCode, limit, offset }
    elseif options.errorCodePattern then
        query = ('SELECT * FROM %s WHERE error_code LIKE ? ORDER BY created_at DESC LIMIT ? OFFSET ?'):format(Database.GetTableName('errors'))
        params = { '%' .. options.errorCodePattern .. '%', limit, offset }
    elseif options.playerId then
        query = ('SELECT * FROM %s WHERE player_id = ? ORDER BY created_at DESC LIMIT ? OFFSET ?'):format(Database.GetTableName('errors'))
        params = { options.playerId, limit, offset }
    else
        query = ('SELECT * FROM %s ORDER BY created_at DESC LIMIT ? OFFSET ?'):format(Database.GetTableName('errors'))
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
-- الحصول على إحصائيات الأخطاء
-- =============================================================
function Errors.GetStats(callback)
    local statsQuery = ('SELECT severity, COUNT(*) as count FROM %s GROUP BY severity'):format(Database.GetTableName('errors'))

    Database.Execute(statsQuery, {}, function(results, err)
        if err then
            if callback then callback({}, err) end
            return
        end

        local stats = {
            info = 0,
            warning = 0,
            error = 0,
            critical = 0,
            total = 0
        }

        if type(results) == 'table' then
            for _, row in ipairs(results) do
                stats[row.severity] = row.count
                stats.total = stats.total + row.count
            end
        end

        if callback then callback(stats, nil) end
    end)
end

-- =============================================================
-- حذف الأخطاء القديمة
-- =============================================================
function Errors.CleanupOld(days, callback)
    days = days or 30

    local deleteQuery = ('DELETE FROM %s WHERE created_at < DATE_SUB(NOW(), INTERVAL ? DAY)'):format(Database.GetTableName('errors'))

    Database.Execute(deleteQuery, { days }, function(_, err)
        if err then
            if callback then callback(false, err) end
            return
        end

        if callback then callback(true, nil) end
    end)
end

-- =============================================================
-- رسالة تحميل ناجحة
-- =============================================================
if Logger.Debug then
    Logger.Debug('server/core/errors.lua loaded')
elseif OxSecure.Console and type(OxSecure.Console.debug) == 'function' then
    OxSecure.Console.debug('server/core/errors.lua loaded')
end
