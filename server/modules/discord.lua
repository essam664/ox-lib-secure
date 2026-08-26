-- =============================================================
-- ox_lib_secure
-- File: server/modules/discord.lua
-- Description:
--   وحدة تكامل Discord لنظام ox_lib_secure.
--   ترسل إشعارات عبر Webhooks.
--
-- Notes:
--   - مواءمة 100% مع config/main.lua النهائي.
--   - تستخدم BotAvatarUrl وليس BotAvatar.
--   - تدعم ألوان مخصصة لكل نوع إشعار.
--   - إصلاح: حماية json.encode بـ pcall.
--   - إصلاح: إضافة callback اختياري لمعرفة نتيجة الإرسال.
-- =============================================================

Config = Config or {}
OxSecure = OxSecure or {}
OxSecure.Discord = OxSecure.Discord or {}

local Discord = OxSecure.Discord
local Logger = OxSecure.Logger or {}

-- =============================================================
-- قراءة الإعدادات من الكونفق
-- متوافقة حرفيًا مع config/main.lua
-- =============================================================
local discordConfig = Config.Discord or {}

local ENABLED = discordConfig.Enabled == true
local WEBHOOK_URL = discordConfig.WebhookUrl or ''
local BOT_NAME = discordConfig.BotName or 'ox_lib_secure'
local BOT_AVATAR_URL = discordConfig.BotAvatarUrl or ''
local DEFAULT_COLOR = discordConfig.DefaultColor or 0x6366f1
local SUCCESS_COLOR = discordConfig.SuccessColor or 0x10b981
local ERROR_COLOR = discordConfig.ErrorColor or 0xef4444
local WARNING_COLOR = discordConfig.WarningColor or 0xf59e0b
local INFO_COLOR = discordConfig.InfoColor or 0x3b82f6
local NOTIFY_ON_JOIN = discordConfig.NotifyOnJoin == true
local NOTIFY_ON_LEAVE = discordConfig.NotifyOnLeave == true
local NOTIFY_ON_BAN = discordConfig.NotifyOnBan ~= false
local NOTIFY_ON_UNBAN = discordConfig.NotifyOnUnban ~= false
local NOTIFY_ON_CRITICAL = discordConfig.NotifyOnCritical ~= false

-- =============================================================
-- الحالة الداخلية
-- =============================================================
local isInitialized = false
local totalSent = 0
local totalFailed = 0

-- =============================================================
-- أدوات مساعدة داخلية
-- =============================================================
local function logDiscord(message, level)
    level = level or 'info'
    if Logger and Logger.Log then
        Logger.Log(level, message, { category = 'discord' })
    else
        print(('[ox_lib_secure] [DISCORD] %s'):format(message))
    end
end

-- =============================================================
-- تهيئة وحدة Discord
-- =============================================================
function Discord.Initialize()
    if isInitialized then
        return true
    end

    if not ENABLED then
        logDiscord('Discord integration is disabled.')
        return true
    end

    if WEBHOOK_URL == '' then
        logDiscord('Discord Webhook URL is not configured.', 'warn')
        return false
    end

    logDiscord('Initializing Discord integration...')
    logDiscord(('Bot name: %s'):format(BOT_NAME))

    isInitialized = true
    logDiscord('Discord integration initialized successfully.')
    return true
end

-- =============================================================
-- التحقق من حالة التهيئة
-- =============================================================
function Discord.IsInitialized()
    return isInitialized
end

-- =============================================================
-- التحقق من التفعيل
-- =============================================================
function Discord.IsEnabled()
    return ENABLED and isInitialized and WEBHOOK_URL ~= ''
end

-- =============================================================
-- الحصول على اللون حسب النوع
-- =============================================================
local function getColor(notificationType)
    if notificationType == 'success' then
        return SUCCESS_COLOR
    elseif notificationType == 'error' or notificationType == 'critical' then
        return ERROR_COLOR
    elseif notificationType == 'warning' then
        return WARNING_COLOR
    elseif notificationType == 'info' then
        return INFO_COLOR
    else
        return DEFAULT_COLOR
    end
end

-- =============================================================
-- إرسال رسالة إلى Discord
-- إصلاح 1: حماية json.encode بـ pcall
-- إصلاح 2: إضافة callback اختياري لمعرفة نتيجة الإرسال
-- =============================================================
function Discord.Send(options, callback)
    if not Discord.IsEnabled() then
        if callback then callback(false, 'Discord integration is not enabled') end
        return false, 'Discord integration is not enabled'
    end

    if not options then
        if callback then callback(false, 'Options are required') end
        return false, 'Options are required'
    end

    local title = options.title or 'ox_lib_secure'
    local description = options.description or ''
    local color = options.color or getColor(options.type)
    local fields = options.fields or {}
    local footer = options.footer
    local timestamp = options.timestamp ~= false

    -- بناء الحمولة
    local payload = {
        username = BOT_NAME,
        embeds = {
            {
                title = title,
                description = description,
                color = color,
                fields = fields,
                timestamp = timestamp and os.date('!%Y-%m-%dT%H:%M:%SZ') or nil
            }
        }
    }

    -- إضافة الصورة الرمزية إذا كانت موجودة
    if BOT_AVATAR_URL ~= '' then
        payload.avatar_url = BOT_AVATAR_URL
    end

    -- إضافة التذييل إذا كان موجودًا
    if footer then
        payload.embeds[1].footer = {
            text = footer
        }
    end

    -- إصلاح 1: حماية الترميز بـ pcall
    local ok, payloadJson = pcall(json.encode, payload)

    if not ok or not payloadJson then
        logDiscord(('Failed to encode Discord payload: %s'):format(tostring(payloadJson)), 'error')
        totalFailed = totalFailed + 1
        if callback then callback(false, 'Failed to encode payload') end
        return false, 'Failed to encode payload'
    end

    -- إرسال الطلب
    PerformHttpRequest(WEBHOOK_URL, function(statusCode, response, headers)
        if statusCode == 200 or statusCode == 204 then
            totalSent = totalSent + 1
            if callback then callback(true) end
        else
            totalFailed = totalFailed + 1
            logDiscord(('Failed to send Discord message: HTTP %d'):format(statusCode), 'error')
            if callback then callback(false, ('HTTP %d'):format(statusCode)) end
        end
    end, 'POST', payloadJson, {
        ['Content-Type'] = 'application/json'
    })

    return true
end

-- =============================================================
-- إرسال إشعار بسيط
-- =============================================================
function Discord.Notify(notificationType, title, description, callback)
    return Discord.Send({
        type = notificationType,
        title = title,
        description = description
    }, callback)
end

-- =============================================================
-- إرسال إشعار نجاح
-- =============================================================
function Discord.NotifySuccess(title, description, callback)
    return Discord.Notify('success', title, description, callback)
end

-- =============================================================
-- إرسال إشعار خطأ
-- =============================================================
function Discord.NotifyError(title, description, callback)
    return Discord.Notify('error', title, description, callback)
end

-- =============================================================
-- إرسال إشعار تحذير
-- =============================================================
function Discord.NotifyWarning(title, description, callback)
    return Discord.Notify('warning', title, description, callback)
end

-- =============================================================
-- إرسال إشعار معلومات
-- =============================================================
function Discord.NotifyInfo(title, description, callback)
    return Discord.Notify('info', title, description, callback)
end

-- =============================================================
-- إرسال إشعار حرج
-- =============================================================
function Discord.NotifyCritical(title, description, callback)
    if not NOTIFY_ON_CRITICAL then
        if callback then callback(false, 'Critical notifications are disabled') end
        return false
    end

    return Discord.Send({
        type = 'critical',
        title = '🚨 ' .. (title or 'تنبيه حرج'),
        description = description,
        color = ERROR_COLOR
    }, callback)
end

-- =============================================================
-- إرسال إشعار حظر لاعب
-- =============================================================
function Discord.NotifyBan(playerName, reason, duration, callback)
    if not NOTIFY_ON_BAN then
        if callback then callback(false, 'Ban notifications are disabled') end
        return false
    end

    return Discord.Send({
        type = 'error',
        title = '🔨 حظر لاعب',
        description = ('تم حظر اللاعب **%s**'):format(playerName or 'غير معروف'),
        fields = {
            { name = 'السبب', value = reason or 'غير محدد', inline = true },
            { name = 'المدة', value = duration or 'دائم', inline = true }
        },
        color = ERROR_COLOR
    }, callback)
end

-- =============================================================
-- إرسال إشعار فك حظر لاعب
-- =============================================================
function Discord.NotifyUnban(playerName, adminName, callback)
    if not NOTIFY_ON_UNBAN then
        if callback then callback(false, 'Unban notifications are disabled') end
        return false
    end

    return Discord.Send({
        type = 'success',
        title = '✅ فك حظر لاعب',
        description = ('تم فك حظر اللاعب **%s**'):format(playerName or 'غير معروف'),
        fields = {
            { name = 'بواسطة', value = adminName or 'النظام', inline = true }
        },
        color = SUCCESS_COLOR
    }, callback)
end

-- =============================================================
-- إرسال إشعار انضمام لاعب
-- =============================================================
function Discord.NotifyJoin(playerName, playerId, callback)
    if not NOTIFY_ON_JOIN then
        if callback then callback(false, 'Join notifications are disabled') end
        return false
    end

    return Discord.Send({
        type = 'info',
        title = '👋 انضمام لاعب',
        description = ('انضم اللاعب **%s** (ID: %d)'):format(playerName or 'غير معروف', playerId or 0),
        color = INFO_COLOR
    }, callback)
end

-- =============================================================
-- إرسال إشعار مغادرة لاعب
-- =============================================================
function Discord.NotifyLeave(playerName, playerId, reason, callback)
    if not NOTIFY_ON_LEAVE then
        if callback then callback(false, 'Leave notifications are disabled') end
        return false
    end

    return Discord.Send({
        type = 'info',
        title = '👋 مغادرة لاعب',
        description = ('غادر اللاعب **%s** (ID: %d)'):format(playerName or 'غير معروف', playerId or 0),
        fields = {
            { name = 'السبب', value = reason or 'غير محدد', inline = true }
        },
        color = INFO_COLOR
    }, callback)
end

-- =============================================================
-- إرسال إشعار تدقيق
-- =============================================================
function Discord.NotifyAudit(action, actor, target, details, callback)
    return Discord.Send({
        type = 'info',
        title = '📋 تدقيق',
        description = ('إجراء: **%s**'):format(action or 'غير محدد'),
        fields = {
            { name = 'المنفذ', value = actor or 'النظام', inline = true },
            { name = 'الهدف', value = target or 'غير محدد', inline = true },
            { name = 'التفاصيل', value = details or '-', inline = false }
        },
        color = DEFAULT_COLOR
    }, callback)
end

-- =============================================================
-- إرسال إشعار خطأ نظام
-- =============================================================
function Discord.NotifySystemError(errorMessage, context, callback)
    return Discord.Send({
        type = 'error',
        title = '⚠️ خطأ في النظام',
        description = errorMessage or 'حدث خطأ غير متوقع',
        fields = context and {
            { name = 'السياق', value = context, inline = false }
        } or {},
        color = ERROR_COLOR
    }, callback)
end

-- =============================================================
-- إحصائيات
-- =============================================================
function Discord.GetStats()
    return {
        isEnabled = ENABLED,
        isInitialized = isInitialized,
        webhookConfigured = WEBHOOK_URL ~= '',
        totalSent = totalSent,
        totalFailed = totalFailed,
        botName = BOT_NAME,
        notifyOnJoin = NOTIFY_ON_JOIN,
        notifyOnLeave = NOTIFY_ON_LEAVE,
        notifyOnBan = NOTIFY_ON_BAN,
        notifyOnUnban = NOTIFY_ON_UNBAN,
        notifyOnCritical = NOTIFY_ON_CRITICAL
    }
end

-- =============================================================
-- تهيئة عند التحميل
-- =============================================================
Discord.Initialize()

-- =============================================================
-- رسالة تحميل ناجحة
-- =============================================================
if Logger and Logger.Debug then
    Logger.Debug('server/modules/discord.lua loaded')
else
    print('[ox_lib_secure] server/modules/discord.lua loaded')
end
