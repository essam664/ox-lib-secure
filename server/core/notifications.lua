-- =============================================================
-- ox_lib_secure
-- File: server/core/notifications.lua
-- Description:
--   طبقة الإشعارات لنظام ox_lib_secure.
--
-- Notes:
--   - يتم إرسال الإشعارات عبر واجهة NUI.
--   - يتم التحقق من معدل الاستخدام قبل الإرسال.
--   - يتم حفظ الإشعارات في قاعدة البيانات مرة واحدة فقط.
--   - يتم دعم أنماط التصميم والمواقع المختلفة.
--   - يتم دعم ربط الإشعارات بالكلمات المفتاحية والأنظمة.
--   - البث الجماعي ينتظر اكتمال جميع الإرسالات.
--   - العنوان لا يبقى فارغًا حتى لو أرجعت الترجمة نصًا فارغًا.
-- =============================================================

Config = Config or {}
OxSecure = OxSecure or {}
OxSecure.Notifications = OxSecure.Notifications or {}

local Notifications = OxSecure.Notifications
local Database = OxSecure.Database or {}
local Logger = OxSecure.Logger or {}
local Utils = OxSecure.Utils or {}
local RateLimiter = OxSecure.RateLimiter or {}
local Localization = OxSecure.Localization or {}
local Keywords = OxSecure.Keywords or {}

local notificationsConfig = Config.Notifications or {}
local uiConfig = Config.UI or {}

local DEFAULT_POSITION = notificationsConfig.DefaultPosition or uiConfig.DefaultPosition or 'left'
local DEFAULT_DESIGN_STYLE = notificationsConfig.DefaultDesignStyle or uiConfig.DefaultDesignStyle or 'default'
local DEFAULT_DURATION_MS = notificationsConfig.DefaultDurationMs or uiConfig.DefaultDurationMs or 5000
local MAX_DURATION_MS = notificationsConfig.MaxDurationMs or uiConfig.MaxDurationMs or 30000

-- =============================================================
-- أدوات مساعدة داخلية
-- =============================================================
local function logNotificationEvent(message, options)
    if Logger.Info then
        Logger.Info(message, options or {
            category = 'notification',
            eventCode = 'notification_event'
        })
    end
end

local function logNotificationError(message, options)
    if Logger.Error then
        Logger.Error(message, options or {
            category = 'notification',
            eventCode = 'notification_error'
        })
    end
end

-- =============================================================
-- التحقق من صحة نوع الإشعار
-- =============================================================
local function isValidNotificationType(notificationType)
    local allowedTypes = uiConfig.AllowedNotificationTypes or {
        'info', 'success', 'warning', 'error', 'critical', 'system'
    }

    for _, validType in ipairs(allowedTypes) do
        if notificationType == validType then
            return true
        end
    end

    return false
end

-- =============================================================
-- التحقق من صحة نمط التصميم
-- =============================================================
local function isValidDesignStyle(designStyle)
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
-- التحقق من صحة الموقع
-- =============================================================
local function isValidPosition(position)
    local allowedPositions = uiConfig.AllowedPositions or {
        'top', 'top-right', 'top-left',
        'bottom', 'bottom-right', 'bottom-left',
        'center', 'left', 'right'
    }

    for _, validPos in ipairs(allowedPositions) do
        if position == validPos then
            return true
        end
    end

    return false
end

-- =============================================================
-- إرسال إشعار إلى لاعب معين عبر NUI
-- =============================================================
local function sendToClient(source, notificationData)
    if not source or source <= 0 then
        return false
    end

    TriggerClientEvent('oxsecure:client:showNotification', source, notificationData)
    return true
end

-- =============================================================
-- حفظ إشعار في قاعدة البيانات
-- =============================================================
local function saveToDatabase(entry)
    if not Database.IsReady() then
        return
    end

    if not Config.Database.SaveNotifications then
        return
    end

    local metaJson = nil

    if entry.meta ~= nil and Utils.SafeJsonEncode then
        metaJson = Utils.SafeJsonEncode(entry.meta)
    end

    local insertQuery = ('INSERT INTO %s (notification_type, title_ar, body_ar, position, design_style, player_id, server_player_id, discord_id, source_system_id, keyword_id, log_id, status, failure_reason, delivered_at, expires_at, meta_json, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())'):format(Database.GetTableName('notifications'))

    Database.Execute(insertQuery, {
        entry.type or 'info',
        entry.title or '',
        entry.body or '',
        entry.position or DEFAULT_POSITION,
        entry.designStyle or DEFAULT_DESIGN_STYLE,
        entry.playerId,
        entry.serverPlayerId,
        entry.discordId,
        entry.sourceSystemId,
        entry.keywordId,
        entry.logId,
        entry.status or 'queued',
        entry.failureReason,
        entry.deliveredAt,
        entry.expiresAt,
        metaJson
    }, function(_, err)
        if err then
            logNotificationError(('Failed to save notification to DB: %s'):format(tostring(err)))
        end
    end)
end

-- =============================================================
-- إرسال إشعار إلى لاعب
--
-- إصلاح: التحقق من أن العنوان ليس فارغًا حتى لو أرجعت
-- الترجمة نصًا فارغًا.
-- =============================================================
function Notifications.Send(source, options, callback)
    options = options or {}

    local serverId = tonumber(source)

    if not serverId or serverId <= 0 then
        if callback then callback(false, { code = 'ERR_INVALID_SOURCE' }) end
        return
    end

    -- التحقق من معدل الاستخدام
    if RateLimiter.Check then
        local allowed, rateError = RateLimiter.Check(serverId, 'notification')

        if not allowed then
            if callback then callback(false, { code = 'ERR_RATE_LIMIT' }) end
            return
        end
    end

    -- تحديد النوع
    local notificationType = options.type or 'info'

    if not isValidNotificationType(notificationType) then
        notificationType = 'info'
    end

    -- إصلاح: تحديد العنوان مع فحص النص الفارغ
    local title = options.title

    if not title or title == '' then
        local localizedTitle = nil

        if Localization.GetMessage then
            localizedTitle = Localization.GetMessage('titles.' .. notificationType)
        end

        -- التحقق من أن الترجمة ليست فارغة
        if localizedTitle and localizedTitle ~= '' then
            title = localizedTitle
        else
            title = notificationType
        end
    end

    -- تحديد النص
    local body = options.body or options.message or ''

    if body == '' then
        if callback then callback(false, { code = 'ERR_EMPTY_MESSAGE' }) end
        return
    end

    -- تحديد الموقع
    local position = options.position or DEFAULT_POSITION

    if not isValidPosition(position) then
        position = DEFAULT_POSITION
    end

    -- تحديد نمط التصميم
    local designStyle = options.designStyle or DEFAULT_DESIGN_STYLE

    if not isValidDesignStyle(designStyle) then
        designStyle = DEFAULT_DESIGN_STYLE
    end

    -- تحديد المدة
    local durationMs = options.durationMs or DEFAULT_DURATION_MS

    if durationMs > MAX_DURATION_MS then
        durationMs = MAX_DURATION_MS
    end

    if durationMs < 1000 then
        durationMs = 1000
    end

    -- بناء بيانات الإشعار
    local notificationData = {
        id = Utils.GenerateSessionId and Utils.GenerateSessionId(16) or tostring(os.time()),
        type = notificationType,
        title = title,
        body = body,
        position = position,
        designStyle = designStyle,
        durationMs = durationMs,
        sound = options.sound ~= false,
        soundName = options.soundName or (notificationsConfig.Sound and notificationsConfig.Sound.DefaultName) or 'default',
        meta = options.meta,
        createdAt = os.time()
    }

    -- إرسال إلى اللاعب
    local sent = sendToClient(serverId, notificationData)

    if sent then
        saveToDatabase({
            type = notificationType,
            title = title,
            body = body,
            position = position,
            designStyle = designStyle,
            serverPlayerId = serverId,
            playerId = options.playerId,
            discordId = options.discordId,
            sourceSystemId = options.sourceSystemId,
            keywordId = options.keywordId,
            logId = options.logId,
            status = 'delivered',
            deliveredAt = os.date('%Y-%m-%d %H:%M:%S'),
            meta = options.meta
        })

        logNotificationEvent(('Notification sent to player %d: type=%s'):format(serverId, notificationType))

        if callback then callback(true, { id = notificationData.id }) end
    else
        saveToDatabase({
            type = notificationType,
            title = title,
            body = body,
            position = position,
            designStyle = designStyle,
            serverPlayerId = serverId,
            playerId = options.playerId,
            discordId = options.discordId,
            sourceSystemId = options.sourceSystemId,
            keywordId = options.keywordId,
            logId = options.logId,
            status = 'failed',
            failureReason = 'Failed to send to client',
            meta = options.meta
        })

        if callback then callback(false, { code = 'ERR_UI_FAILED' }) end
    end
end

-- =============================================================
-- إرسال إشعار إلى جميع اللاعبين المتصلين
-- =============================================================
function Notifications.Broadcast(options, callback)
    options = options or {}

    local players = GetPlayers()

    if not players or #players == 0 then
        if callback then callback(false, { code = 'ERR_NO_PLAYERS' }) end
        return
    end

    local sentCount = 0
    local pendingSends = #players

    for _, playerId in ipairs(players) do
        local serverId = tonumber(playerId)

        if serverId and serverId > 0 then
            Notifications.Send(serverId, options, function(ok)
                if ok then
                    sentCount = sentCount + 1
                end

                pendingSends = pendingSends - 1

                if pendingSends <= 0 then
                    logNotificationEvent(('Broadcast notification sent to %d players'):format(sentCount))

                    if callback then callback(true, { sentCount = sentCount }) end
                end
            end)
        else
            pendingSends = pendingSends - 1

            if pendingSends <= 0 then
                logNotificationEvent(('Broadcast notification sent to %d players'):format(sentCount))

                if callback then callback(true, { sentCount = sentCount }) end
            end
        end
    end
end

-- =============================================================
-- إرسال إشعار خطأ إلى لاعب
-- =============================================================
function Notifications.SendError(source, errorCode, data, callback)
    local errorInfo = nil

    if Localization.GetError then
        errorInfo = Localization.GetError(errorCode, data)
    end

    if not errorInfo then
        errorInfo = {
            code = errorCode or 'ERR_UNKNOWN',
            title = 'خطأ غير معروف',
            body = 'حدث خطأ غير متوقع في النظام.',
            severity = 'error',
            designStyle = 'error',
            durationMs = 6000
        }
    end

    local notificationType = 'error'

    if errorInfo.severity == 'critical' then
        notificationType = 'critical'
    elseif errorInfo.severity == 'warning' then
        notificationType = 'warning'
    elseif errorInfo.severity == 'info' then
        notificationType = 'info'
    end

    Notifications.Send(source, {
        type = notificationType,
        title = errorInfo.title,
        body = errorInfo.body,
        designStyle = errorInfo.designStyle or 'error',
        durationMs = errorInfo.durationMs or 6000,
        meta = {
            errorCode = errorInfo.code,
            category = errorInfo.category
        }
    }, callback)
end

-- =============================================================
-- إرسال إشعار نجاح إلى لاعب
-- =============================================================
function Notifications.SendSuccess(source, title, body, callback)
    Notifications.Send(source, {
        type = 'success',
        title = title or 'نجاح',
        body = body or 'تمت العملية بنجاح.',
        designStyle = 'success',
        durationMs = 4000
    }, callback)
end

-- =============================================================
-- إرسال إشعار تحذير إلى لاعب
-- =============================================================
function Notifications.SendWarning(source, title, body, callback)
    Notifications.Send(source, {
        type = 'warning',
        title = title or 'تحذير',
        body = body or 'يرجى الانتباه.',
        designStyle = 'warning',
        durationMs = 5000
    }, callback)
end

-- =============================================================
-- إرسال إشعار نظام إلى لاعب
-- =============================================================
function Notifications.SendSystem(source, title, body, callback)
    Notifications.Send(source, {
        type = 'system',
        title = title or 'النظام',
        body = body or '',
        designStyle = 'default',
        durationMs = 5000
    }, callback)
end

-- =============================================================
-- إرسال إشعار بناءً على كلمة مفتاحية
-- =============================================================
function Notifications.SendFromKeyword(source, text, callback)
    if not Keywords.GetFirstMatch then
        if callback then callback(false, { code = 'ERR_KEYWORD_NOT_FOUND' }) end
        return
    end

    Keywords.GetFirstMatch(text, function(keywordEntry)
        if not keywordEntry then
            if callback then callback(false, { code = 'ERR_KEYWORD_NOT_FOUND' }) end
            return
        end

        local designStyle = keywordEntry.design_style or DEFAULT_DESIGN_STYLE
        local title = keywordEntry.title_ar or keywordEntry.keyword
        local body = keywordEntry.body_ar or text
        local durationMs = keywordEntry.duration_ms or DEFAULT_DURATION_MS
        local soundName = keywordEntry.sound_name or 'default'

        Notifications.Send(source, {
            type = 'info',
            title = title,
            body = body,
            designStyle = designStyle,
            durationMs = durationMs,
            soundName = soundName,
            keywordId = keywordEntry.id,
            meta = {
                keywordId = keywordEntry.id,
                keyword = keywordEntry.keyword
            }
        }, callback)
    end)
end

-- =============================================================
-- رسالة تحميل ناجحة
-- =============================================================
if Logger.Debug then
    Logger.Debug('server/core/notifications.lua loaded')
elseif OxSecure.Console and type(OxSecure.Console.debug) == 'function' then
    OxSecure.Console.debug('server/core/notifications.lua loaded')
end
