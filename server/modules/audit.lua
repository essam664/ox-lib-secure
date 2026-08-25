-- =============================================================
-- ox_lib_secure
-- File: server/modules/audit.lua
-- Description:
--   وحدة التدقيق لنظام ox_lib_secure.
--
-- Notes:
--   - يتم تسجيل جميع إجراءات المشرفين.
--   - يتم حفظ السجلات في قاعدة البيانات.
--   - يتم دعم التكامل مع Discord للإشعارات.
--   - يتم دعم التصفية حسب نوع الإجراء والفاعل.
--   - البحث في details منفصل لأنه JSON.
--   - أخطاء Discord تُسجل في اللوجات.
-- =============================================================

Config = Config or {}
OxSecure = OxSecure or {}
OxSecure.Audit = OxSecure.Audit or {}

local Audit = OxSecure.Audit
local Database = OxSecure.Database or {}
local Logger = OxSecure.Logger or {}
local Utils = OxSecure.Utils or {}
local Discord = OxSecure.Discord or {}

local auditConfig = Config.Audit or {}
local ENABLE_DISCORD_NOTIFICATIONS = auditConfig.DiscordNotifications ~= false

-- =============================================================
-- أدوات مساعدة داخلية
-- =============================================================
local function logAuditEvent(message, options)
    if Logger.Info then
        Logger.Info(message, options or {
            category = 'audit',
            eventCode = 'audit_event'
        })
    end
end

local function logAuditError(message, options)
    if Logger.Error then
        Logger.Error(message, options or {
            category = 'audit',
            eventCode = 'audit_error'
        })
    end
end

-- =============================================================
-- حفظ سجل تدقيق في قاعدة البيانات
-- =============================================================
local function saveToDatabase(entry)
    if not Database.IsReady() then
        return
    end

    if not Config.Database.SaveAudit then
        return
    end

    local detailsJson = nil

    if entry.details ~= nil and Utils.SafeJsonEncode then
        detailsJson = Utils.SafeJsonEncode(entry.details)
    end

    local insertQuery = ('INSERT INTO %s (action_code, actor_admin_id, actor_discord_id, actor_player_id, target_type, target_id, details, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, NOW())'):format(Database.GetTableName('audit_actions'))

    Database.Execute(insertQuery, {
        entry.actionCode or 'unknown',
        entry.actorAdminId,
        entry.actorDiscordId,
        entry.actorPlayerId,
        entry.targetType,
        entry.targetId,
        detailsJson
    }, function(_, err)
        if err then
            logAuditError(('Failed to save audit record: %s'):format(tostring(err)))
        end
    end)
end

-- =============================================================
-- تسجيل إجراء تدقيق
--
-- ملاحظة مهمة:
--   إذا لم يكن اللاعب موجودًا في الكاش، سيتم استخدام
--   serverId كـ actorPlayerId. هذا ليس معرفًا دائمًا وقد
--   يتغير بين الجلسات. للتحليل الدقيق لاحقًا، يُنصح
--   بالاعتماد على actorDiscordId أو actorAdminId.
--
-- options:
--   actionCode: رمز الإجراء (مطلوب)
--   actorSource: معرف اللاعب المنفذ (اختياري)
--   targetType: نوع الهدف (اختياري)
--   targetId: معرف الهدف (اختياري)
--   details: تفاصيل إضافية (جدول)
--   notifyDiscord: إرسال إشعار Discord (افتراضي: حسب الإعداد)
-- =============================================================
function Audit.Record(options, callback)
    options = options or {}

    local actionCode = options.actionCode

    if type(actionCode) ~= 'string' or actionCode == '' then
        if callback then callback(false, { code = 'ERR_INVALID_FIELD' }) end
        return
    end

    local actorAdminId = nil
    local actorDiscordId = nil
    local actorPlayerId = nil

    -- استخراج معلومات الفاعل
    if options.actorSource then
        local serverId = tonumber(options.actorSource)

        if serverId and serverId > 0 then
            -- محاولة جلب معرف قاعدة البيانات و Discord من الكاش
            local Players = OxSecure.Players

            if Players and Players.GetPlayer then
                local playerData = Players.GetPlayer(serverId)

                if playerData then
                    -- استخدام database ID إذا وجد
                    actorPlayerId = playerData.id or serverId

                    if playerData.identifiers then
                        for _, id in ipairs(playerData.identifiers) do
                            if id.type == 'discord' then
                                actorDiscordId = id.value
                                break
                            end
                        end
                    end
                else
                    -- إذا لم يكن اللاعب في الكاش، نستخدم serverId كحل أخير
                    -- تحذير: serverId ليس معرفًا دائمًا وقد يتغير بين الجلسات
                    actorPlayerId = serverId
                    logAuditEvent(('Player not found in cache for server ID %d, using server ID as actorPlayerId'):format(serverId))
                end
            else
                actorPlayerId = serverId
            end
        end
    end

    -- استخدام القيم الممررة مباشرة إذا كانت متاحة
    if options.actorAdminId then
        actorAdminId = options.actorAdminId
    end

    if options.actorDiscordId then
        actorDiscordId = options.actorDiscordId
    end

    -- حفظ في قاعدة البيانات
    saveToDatabase({
        actionCode = actionCode,
        actorAdminId = actorAdminId,
        actorDiscordId = actorDiscordId,
        actorPlayerId = actorPlayerId,
        targetType = options.targetType,
        targetId = options.targetId,
        details = options.details
    })

    logAuditEvent(('Audit recorded: action=%s target=%s'):format(actionCode, options.targetId or 'N/A'))

    -- إرسال إشعار Discord إذا كان مفعلًا
    local shouldNotify = options.notifyDiscord

    if shouldNotify == nil then
        shouldNotify = ENABLE_DISCORD_NOTIFICATIONS
    end

    if shouldNotify and Discord.SendAuditNotification then
        local actorName = actorDiscordId or tostring(actorPlayerId or 'النظام')

        local detailsText = ''

        if options.details and type(options.details) == 'table' then
            local parts = {}

            for key, value in pairs(options.details) do
                parts[#parts + 1] = ('%s: %s'):format(key, tostring(value))
            end

            detailsText = table.concat(parts, '\n')
        end

        -- تسجيل أخطاء Discord في اللوجات
        Discord.SendAuditNotification(actionCode, actorName, detailsText, {
            callback = function(success, err)
                if not success then
                    logAuditError(('Failed to send Discord notification: %s'):format(tostring(err)))
                end
            end
        })
    end

    if callback then callback(true, nil) end
end

-- =============================================================
-- تسجيل إجراء مشرف
-- =============================================================
function Audit.RecordAdminAction(source, actionCode, targetType, targetId, details, callback)
    Audit.Record({
        actionCode = actionCode,
        actorSource = source,
        targetType = targetType,
        targetId = targetId,
        details = details,
        notifyDiscord = true
    }, callback)
end

-- =============================================================
-- تسجيل إجراء نظام (بدون فاعل بشري)
-- =============================================================
function Audit.RecordSystemAction(actionCode, targetType, targetId, details, callback)
    Audit.Record({
        actionCode = actionCode,
        targetType = targetType,
        targetId = targetId,
        details = details,
        notifyDiscord = false
    }, callback)
end

-- =============================================================
-- جلب سجلات التدقيق من قاعدة البيانات
-- =============================================================
function Audit.GetRecords(options, callback)
    options = options or {}

    local limit = options.limit or 50
    local offset = options.offset or 0

    local query = nil
    local params = {}

    if options.actionCode then
        query = ('SELECT * FROM %s WHERE action_code = ? ORDER BY created_at DESC LIMIT ? OFFSET ?'):format(Database.GetTableName('audit_actions'))
        params = { options.actionCode, limit, offset }
    elseif options.actorDiscordId then
        query = ('SELECT * FROM %s WHERE actor_discord_id = ? ORDER BY created_at DESC LIMIT ? OFFSET ?'):format(Database.GetTableName('audit_actions'))
        params = { options.actorDiscordId, limit, offset }
    elseif options.actorPlayerId then
        query = ('SELECT * FROM %s WHERE actor_player_id = ? ORDER BY created_at DESC LIMIT ? OFFSET ?'):format(Database.GetTableName('audit_actions'))
        params = { options.actorPlayerId, limit, offset }
    elseif options.targetType then
        query = ('SELECT * FROM %s WHERE target_type = ? ORDER BY created_at DESC LIMIT ? OFFSET ?'):format(Database.GetTableName('audit_actions'))
        params = { options.targetType, limit, offset }
    else
        query = ('SELECT * FROM %s ORDER BY created_at DESC LIMIT ? OFFSET ?'):format(Database.GetTableName('audit_actions'))
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
-- البحث في سجلات التدقيق
-- =============================================================
function Audit.Search(searchTerm, options, callback)
    options = options or {}

    if type(searchTerm) ~= 'string' or searchTerm == '' then
        if callback then callback({}, nil) end
        return
    end

    local limit = options.limit or 50
    local offset = options.offset or 0

    local query = nil
    local params = {}
    local pattern = '%' .. searchTerm .. '%'

    -- البحث في details منفصل لأنه JSON وقد يعطي نتائج غير دقيقة
    if options.searchInDetails then
        query = ('SELECT * FROM %s WHERE details LIKE ? ORDER BY created_at DESC LIMIT ? OFFSET ?'):format(Database.GetTableName('audit_actions'))
        params = { pattern, limit, offset }
        logAuditEvent('Searching in details field (JSON) - results may not be accurate')
    else
        -- البحث في الحقول النصية فقط
        query = ('SELECT * FROM %s WHERE action_code LIKE ? OR target_id LIKE ? ORDER BY created_at DESC LIMIT ? OFFSET ?'):format(Database.GetTableName('audit_actions'))
        params = { pattern, pattern, limit, offset }
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
-- الحصول على إحصائيات التدقيق
-- =============================================================
function Audit.GetStats(callback)
    local statsQuery = ('SELECT action_code, COUNT(*) as count FROM %s GROUP BY action_code ORDER BY count DESC LIMIT 20'):format(Database.GetTableName('audit_actions'))

    Database.Execute(statsQuery, {}, function(results, err)
        if err then
            if callback then callback({}, err) end
            return
        end

        local stats = {}

        if type(results) == 'table' then
            for _, row in ipairs(results) do
                stats[row.action_code] = row.count
            end
        end

        if callback then callback(stats, nil) end
    end)
end

-- =============================================================
-- حذف سجلات التدقيق القديمة
-- =============================================================
function Audit.CleanupOld(days, callback)
    days = days or 90

    local deleteQuery = ('DELETE FROM %s WHERE created_at < DATE_SUB(NOW(), INTERVAL ? DAY)'):format(Database.GetTableName('audit_actions'))

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
    Logger.Debug('server/modules/audit.lua loaded')
elseif OxSecure.Console and type(OxSecure.Console.debug) == 'function' then
    OxSecure.Console.debug('server/modules/audit.lua loaded')
end
