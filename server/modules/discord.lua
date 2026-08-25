-- =============================================================
-- ox_lib_secure
-- File: server/modules/discord.lua
-- Description:
--   وحدة تكامل Discord لنظام ox_lib_secure.
--
-- Notes:
--   - يتم إرسال الإشعارات عبر Webhooks.
--   - يتم التحقق من معدل الاستخدام لتجنب حظر Discord.
--   - يتم معالجة أخطاء الإرسال بشكل آمن.
--   - يمكن تهيئة الوحدة يدويًا حتى لو لم تكن مفعلة مسبقًا.
-- =============================================================

Config = Config or {}
OxSecure = OxSecure or {}
OxSecure.Discord = OxSecure.Discord or {}

local Discord = OxSecure.Discord
local Utils = OxSecure.Utils or {}
local Logger = OxSecure.Logger or {}
local RateLimiter = OxSecure.RateLimiter or {}
local Localization = OxSecure.Localization or {}

local discordConfig = Config.Discord or {}
local ENABLED = discordConfig.Enabled == true
local DEFAULT_WEBHOOK_URL = discordConfig.WebhookUrl or nil
local BOT_NAME = discordConfig.BotName or 'ox_lib_secure'
local BOT_AVATAR_URL = discordConfig.BotAvatarUrl or nil
local MAX_MESSAGE_LENGTH = 2000

-- حالة الوحدة
local moduleState = {
    initialized = false,
    failedSends = 0,
    successfulSends = 0,
    lastError = nil
}

-- =============================================================
-- أدوات مساعدة داخلية
-- =============================================================
local function isDiscordEnabled()
    return ENABLED and DEFAULT_WEBHOOK_URL ~= nil
end

local function logDiscordEvent(message, options)
    if Logger.Info then
        Logger.Info(message, options or {
            category = 'discord',
            eventCode = 'discord_event'
        })
    end
end

local function logDiscordError(message, options)
    if Logger.Error then
        Logger.Error(message, options or {
            category = 'discord',
            eventCode = 'discord_error'
        })
    end
end

-- =============================================================
-- التحقق من صحة رابط Webhook
-- =============================================================
local function isValidWebhookUrl(url)
    if type(url) ~= 'string' or url == '' then
        return false
    end

    -- روابط Discord Webhook تبدأ بـ:
    -- https://discord.com/api/webhooks/
    -- أو
    -- https://discordapp.com/api/webhooks/
    if url:find('^https://discord%.com/api/webhooks/') then
        return true
    end

    if url:find('^https://discordapp%.com/api/webhooks/') then
        return true
    end

    return false
end

-- =============================================================
-- تهيئة الوحدة
--
-- إصلاح: تحديث ENABLED عند استلام Webhook صالح حتى لو
-- لم تكن الوحدة مفعلة مسبقًا في الإعدادات.
-- =============================================================
function Discord.Initialize(webhookUrl)
    if webhookUrl and isValidWebhookUrl(webhookUrl) then
        DEFAULT_WEBHOOK_URL = webhookUrl
        ENABLED = true  -- تحديث الحالة لتسمح بالإرسال
    end

    if not DEFAULT_WEBHOOK_URL then
        logDiscordError('Discord module: No webhook URL configured.')
        moduleState.initialized = false
        return false
    end

    if not isValidWebhookUrl(DEFAULT_WEBHOOK_URL) then
        logDiscordError('Discord module: Invalid webhook URL format.')
        moduleState.initialized = false
        return false
    end

    moduleState.initialized = true
    logDiscordEvent('Discord module initialized successfully.')
    return true
end

-- =============================================================
-- التحقق من جاهزية الوحدة
-- =============================================================
function Discord.IsReady()
    return ENABLED and moduleState.initialized and DEFAULT_WEBHOOK_URL ~= nil
end

-- =============================================================
-- بناء payload لـ Discord
-- =============================================================
local function buildDiscordPayload(options)
    options = options or {}

    local payload = {
        content = nil,
        embeds = nil,
        username = options.botName or BOT_NAME,
        avatar_url = options.botAvatarUrl or BOT_AVATAR_URL
    }

    -- إذا كان هناك رسالة نصية بسيطة
    if options.content and type(options.content) == 'string' then
        payload.content = options.content:sub(1, MAX_MESSAGE_LENGTH)
    end

    -- إذا كان هناك رسائل مدمجة (embeds)
    if options.embeds and type(options.embeds) == 'table' then
        payload.embeds = options.embeds
    end

    return payload
end

-- =============================================================
-- إرسال طلب HTTP إلى Discord
-- =============================================================
local function sendHttpRequest(webhookUrl, payload, callback)
    PerformHttpRequest(webhookUrl, function(statusCode, responseBody, headers)
        if statusCode >= 200 and statusCode < 300 then
            callback(true, nil)
        else
            local errorMessage = ('Discord API returned status %d'):format(statusCode)

            if responseBody then
                local decoded = nil
                if Utils.SafeJsonDecode then
                    decoded = Utils.SafeJsonDecode(responseBody)
                end

                if decoded and decoded.message then
                    errorMessage = errorMessage .. ': ' .. tostring(decoded.message)
                end
            end

            callback(false, errorMessage)
        end
    end, 'POST', Utils.SafeJsonEncode and Utils.SafeJsonEncode(payload) or '{}', {
        ['Content-Type'] = 'application/json'
    })
end

-- =============================================================
-- إرسال إشعار إلى Discord
--
-- options:
--   content: نص الرسالة
--   embeds: جدول الرسائل المدمجة
--   botName: اسم البوت (اختياري)
--   botAvatarUrl: رابط الصورة الرمزية (اختياري)
--   webhookUrl: رابط Webhook مخصص (اختياري)
-- =============================================================
function Discord.Send(options, callback)
    if not ENABLED then
        if callback then callback(false, 'Discord module is disabled') end
        return
    end

    if not moduleState.initialized then
        if callback then callback(false, 'Discord module is not initialized') end
        return
    end

    -- التحقق من معدل الاستخدام
    if RateLimiter.CheckGlobal then
        local allowed, rateError = RateLimiter.CheckGlobal('discord_webhook')

        if not allowed then
            moduleState.failedSends = moduleState.failedSends + 1
            moduleState.lastError = 'Rate limit exceeded'

            if callback then callback(false, 'Rate limit exceeded') end
            return
        end
    end

    local webhookUrl = options.webhookUrl or DEFAULT_WEBHOOK_URL

    if not isValidWebhookUrl(webhookUrl) then
        moduleState.failedSends = moduleState.failedSends + 1
        moduleState.lastError = 'Invalid webhook URL'

        if callback then callback(false, 'Invalid webhook URL') end
        return
    end

    local payload = buildDiscordPayload(options)

    sendHttpRequest(webhookUrl, payload, function(success, err)
        if success then
            moduleState.successfulSends = moduleState.successfulSends + 1
            moduleState.lastError = nil

            logDiscordEvent('Discord message sent successfully.')

            if callback then callback(true, nil) end
        else
            moduleState.failedSends = moduleState.failedSends + 1
            moduleState.lastError = err

            logDiscordError(('Discord message failed: %s'):format(tostring(err)))

            if callback then callback(false, err) end
        end
    end)
end

-- =============================================================
-- إرسال إشعار نظام بسيط
-- =============================================================
function Discord.SendSystemNotification(title, body, options)
    options = options or {}

    local content = ('**%s**\n%s'):format(title or 'النظام', body or '')

    Discord.Send({
        content = content,
        botName = options.botName,
        botAvatarUrl = options.botAvatarUrl,
        webhookUrl = options.webhookUrl
    }, options.callback)
end

-- =============================================================
-- إرسال إشعار خطأ إلى Discord
-- =============================================================
function Discord.SendErrorNotification(errorCode, data, options)
    options = options or {}

    local errorInfo = nil

    if Localization.GetError then
        errorInfo = Localization.GetError(errorCode, data)
    end

    if not errorInfo then
        errorInfo = {
            code = errorCode or 'ERR_UNKNOWN',
            title = 'خطأ غير معروف',
            body = 'حدث خطأ غير متوقع في النظام.'
        }
    end

    local embed = {
        title = ('❌ %s'):format(errorInfo.title),
        description = errorInfo.body,
        color = 0xFF0000,
        fields = {
            {
                name = 'رمز الخطأ',
                value = errorInfo.code,
                inline = true
            }
        },
        timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ')
    }

    if data and data.playerName then
        embed.fields[#embed.fields + 1] = {
            name = 'اللاعب',
            value = tostring(data.playerName),
            inline = true
        }
    end

    if data and data.serverId then
        embed.fields[#embed.fields + 1] = {
            name = 'معرف السيرفر',
            value = tostring(data.serverId),
            inline = true
        }
    end

    Discord.Send({
        embeds = { embed },
        botName = options.botName,
        botAvatarUrl = options.botAvatarUrl,
        webhookUrl = options.webhookUrl
    }, options.callback)
end

-- =============================================================
-- إرسال إشعار أمان إلى Discord
-- =============================================================
function Discord.SendSecurityAlert(message, details, options)
    options = options or {}

    local embed = {
        title = '🛡️ تنبيه أمني',
        description = message,
        color = 0xFFA500,
        fields = {},
        timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ')
    }

    if details and type(details) == 'table' then
        for key, value in pairs(details) do
            embed.fields[#embed.fields + 1] = {
                name = tostring(key),
                value = tostring(value):sub(1, 1024),
                inline = true
            }
        end
    end

    Discord.Send({
        embeds = { embed },
        botName = options.botName,
        botAvatarUrl = options.botAvatarUrl,
        webhookUrl = options.webhookUrl
    }, options.callback)
end

-- =============================================================
-- إرسال إشعار تدقيق إلى Discord
-- =============================================================
function Discord.SendAuditNotification(actionCode, actorName, details, options)
    options = options or {}

    local embed = {
        title = ('📋 تدقيق: %s'):format(actionCode or 'unknown'),
        description = details or '',
        color = 0x00AAFF,
        fields = {
            {
                name = 'المنفذ',
                value = actorName or 'النظام',
                inline = true
            }
        },
        timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ')
    }

    Discord.Send({
        embeds = { embed },
        botName = options.botName,
        botAvatarUrl = options.botAvatarUrl,
        webhookUrl = options.webhookUrl
    }, options.callback)
end

-- =============================================================
-- الحصول على إحصائيات الوحدة
-- =============================================================
function Discord.GetStats()
    return {
        enabled = ENABLED,
        initialized = moduleState.initialized,
        successfulSends = moduleState.successfulSends,
        failedSends = moduleState.failedSends,
        lastError = moduleState.lastError
    }
end

-- =============================================================
-- إعادة تعيين الإحصائيات
-- =============================================================
function Discord.ResetStats()
    moduleState.successfulSends = 0
    moduleState.failedSends = 0
    moduleState.lastError = nil
end

-- =============================================================
-- تهيئة تلقائية عند التحميل
-- =============================================================
if ENABLED and DEFAULT_WEBHOOK_URL then
    Discord.Initialize()
end

-- =============================================================
-- رسالة تحميل ناجحة
-- =============================================================
if Logger.Debug then
    Logger.Debug('server/modules/discord.lua loaded')
elseif OxSecure.Console and type(OxSecure.Console.debug) == 'function' then
    OxSecure.Console.debug('server/modules/discord.lua loaded')
end
