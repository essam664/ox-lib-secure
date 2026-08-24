-- =============================================================
-- ox_lib_secure
-- File: server/core/database.lua
-- Description:
--   طبقة قاعدة البيانات المركزية لنظام ox_lib_secure.
--
-- Notes:
--   - تستخدم هذه الطبقة oxmysql كواجهة للاتصال.
--   - يتم تنفيذ الاستعلامات بأمان مع إعادة المحاولة.
--   - الوضع الآمن يحمي النظام عند فشل الاتصال.
--   - جميع الاستعلامات تُسجل عبر طبقة التسجيل.
--   - أسماء الجداول والأعمدة متوافقة مع schema.sql المعتمد.
-- =============================================================

Config = Config or {}
OxSecure = OxSecure or {}
OxSecure.Database = OxSecure.Database or {}

local Database = OxSecure.Database
local Utils = OxSecure.Utils or {}
local Logger = OxSecure.Logger or {}

local databaseConfig = Config.Database or {}
local securityDatabaseConfig = Config.Security and Config.Security.Database or {}

local USE_DATABASE = databaseConfig.UseDatabase ~= false
local TABLE_PREFIX = databaseConfig.TablePrefix or 'oxsecure_'
local SAFE_MODE = securityDatabaseConfig.SafeMode ~= false
local RETRY_ATTEMPTS = securityDatabaseConfig.RetryAttempts or 2
local RETRY_DELAY_MS = securityDatabaseConfig.RetryDelayMs or 250
local LOG_QUERY_ERRORS = securityDatabaseConfig.LogQueryErrors ~= false

-- حالة الاتصال
local connectionState = {
    ready = false,
    failed = false,
    lastError = nil,
    lastConnectedAt = nil,
    queryCount = 0,
    errorCount = 0
}

-- =============================================================
-- أدوات مساعدة داخلية
-- =============================================================
local function nowMs()
    if Utils.NowMs then
        return Utils.NowMs()
    end

    if type(GetGameTimer) == 'function' then
        return GetGameTimer()
    end

    return os.time() * 1000
end

local function isMySQLAvailable()
    return MySQL ~= nil and type(MySQL.query) == 'function'
end

local function logDatabaseError(message, query)
    if not LOG_QUERY_ERRORS then
        return
    end

    if Logger.DatabaseEvent then
        Logger.DatabaseEvent(message, {
            meta = {
                query = query
            }
        })
    elseif Logger.Error then
        Logger.Error(message)
    end
end

local function encodeMeta(meta)
    if meta == nil then
        return nil
    end

    if Utils.SafeJsonEncode then
        local encoded, err = Utils.SafeJsonEncode(meta)

        if encoded then
            return encoded
        end
    end

    return nil
end

-- =============================================================
-- الحصول على اسم الجدول مع البادئة
-- =============================================================
function Database.GetTableName(tableName)
    return TABLE_PREFIX .. tostring(tableName or '')
end

-- =============================================================
-- الحصول على حالة الاتصال
-- =============================================================
function Database.GetConnectionState()
    return {
        ready = connectionState.ready,
        failed = connectionState.failed,
        lastError = connectionState.lastError,
        lastConnectedAt = connectionState.lastConnectedAt,
        queryCount = connectionState.queryCount,
        errorCount = connectionState.errorCount
    }
end

-- =============================================================
-- التحقق من جاهزية قاعدة البيانات
-- =============================================================
function Database.IsReady()
    return USE_DATABASE and connectionState.ready and isMySQLAvailable()
end

-- =============================================================
-- تحديد حالة الاتصال كجاهزة
-- =============================================================
function Database.SetReady()
    connectionState.ready = true
    connectionState.failed = false
    connectionState.lastError = nil
    connectionState.lastConnectedAt = nowMs()

    if OxSecure.StateManager and type(OxSecure.StateManager.SetDatabaseAvailable) == 'function' then
        OxSecure.StateManager.SetDatabaseAvailable(true)
    end

    if Logger.DatabaseEvent then
        Logger.DatabaseEvent('Database connection established.')
    end
end

-- =============================================================
-- تحديد حالة الاتصال كفاشلة
-- =============================================================
function Database.SetFailed(errorMessage)
    connectionState.ready = false
    connectionState.failed = true
    connectionState.lastError = errorMessage

    if OxSecure.StateManager and type(OxSecure.StateManager.SetDatabaseAvailable) == 'function' then
        OxSecure.StateManager.SetDatabaseAvailable(false)
    end

    logDatabaseError(('Database connection failed: %s'):format(tostring(errorMessage)), nil)
end

-- =============================================================
-- تنفيذ استعلام مع إعادة المحاولة
-- =============================================================
function Database.Execute(query, parameters, callback)
    if not USE_DATABASE then
        if callback then
            callback(nil, 'Database is disabled')
        end
        return
    end

    if not isMySQLAvailable() then
        if callback then
            callback(nil, 'MySQL is not available')
        end
        return
    end

    if SAFE_MODE and connectionState.failed then
        if callback then
            callback(nil, 'Database is in safe mode due to previous failure')
        end
        return
    end

    parameters = parameters or {}

    local function attemptQuery(attemptNumber)
        connectionState.queryCount = connectionState.queryCount + 1

        local ok, err = pcall(function()
            MySQL.query(query, parameters, function(result)
                if callback then
                    callback(result, nil)
                end
            end)
        end)

        if not ok then
            connectionState.errorCount = connectionState.errorCount + 1
            logDatabaseError(('Query execution error (attempt %d): %s'):format(attemptNumber, tostring(err)), query)

            if attemptNumber < RETRY_ATTEMPTS then
                SetTimeout(RETRY_DELAY_MS, function()
                    attemptQuery(attemptNumber + 1)
                end)
            else
                if SAFE_MODE then
                    Database.SetFailed(tostring(err))
                end

                if callback then
                    callback(nil, tostring(err))
                end
            end
        end
    end

    attemptQuery(1)
end

-- =============================================================
-- تنفيذ استعلام بشكل متزامن
-- =============================================================
function Database.ExecuteSync(query, parameters)
    if not USE_DATABASE then
        return nil, 'Database is disabled'
    end

    if not isMySQLAvailable() then
        return nil, 'MySQL is not available'
    end

    if SAFE_MODE and connectionState.failed then
        return nil, 'Database is in safe mode due to previous failure'
    end

    parameters = parameters or {}

    connectionState.queryCount = connectionState.queryCount + 1

    local ok, result = pcall(function()
        return MySQL.query.await(query, parameters)
    end)

    if not ok then
        connectionState.errorCount = connectionState.errorCount + 1
        logDatabaseError(('Sync query execution error: %s'):format(tostring(result)), query)

        if SAFE_MODE then
            Database.SetFailed(tostring(result))
        end

        return nil, tostring(result)
    end

    return result, nil
end

-- =============================================================
-- تنفيذ استعلام إدخال
-- =============================================================
function Database.Insert(query, parameters, callback)
    if not USE_DATABASE then
        if callback then
            callback(nil, 'Database is disabled')
        end
        return
    end

    if not isMySQLAvailable() then
        if callback then
            callback(nil, 'MySQL is not available')
        end
        return
    end

    parameters = parameters or {}

    local ok, err = pcall(function()
        MySQL.insert(query, parameters, function(insertId)
            if callback then
                callback(insertId, nil)
            end
        end)
    end)

    if not ok then
        connectionState.errorCount = connectionState.errorCount + 1
        logDatabaseError(('Insert error: %s'):format(tostring(err)), query)

        if callback then
            callback(nil, tostring(err))
        end
    end
end

-- =============================================================
-- تنفيذ استعلام تحديث
-- =============================================================
function Database.Update(query, parameters, callback)
    if not USE_DATABASE then
        if callback then
            callback(nil, 'Database is disabled')
        end
        return
    end

    if not isMySQLAvailable() then
        if callback then
            callback(nil, 'MySQL is not available')
        end
        return
    end

    parameters = parameters or {}

    local ok, err = pcall(function()
        MySQL.update(query, parameters, function(affectedRows)
            if callback then
                callback(affectedRows, nil)
            end
        end)
    end)

    if not ok then
        connectionState.errorCount = connectionState.errorCount + 1
        logDatabaseError(('Update error: %s'):format(tostring(err)), query)

        if callback then
            callback(nil, tostring(err))
        end
    end
end

-- =============================================================
-- تنفيذ استعلام حذف
-- =============================================================
function Database.Delete(query, parameters, callback)
    Database.Update(query, parameters, callback)
end

-- =============================================================
-- جلب صف واحد
-- =============================================================
function Database.Single(query, parameters, callback)
    if not USE_DATABASE then
        if callback then
            callback(nil, 'Database is disabled')
        end
        return
    end

    if not isMySQLAvailable() then
        if callback then
            callback(nil, 'MySQL is not available')
        end
        return
    end

    parameters = parameters or {}

    local ok, err = pcall(function()
        MySQL.single(query, parameters, function(result)
            if callback then
                callback(result, nil)
            end
        end)
    end)

    if not ok then
        connectionState.errorCount = connectionState.errorCount + 1
        logDatabaseError(('Single query error: %s'):format(tostring(err)), query)

        if callback then
            callback(nil, tostring(err))
        end
    end
end

-- =============================================================
-- جلب قيمة واحدة
-- =============================================================
function Database.Scalar(query, parameters, callback)
    if not USE_DATABASE then
        if callback then
            callback(nil, 'Database is disabled')
        end
        return
    end

    if not isMySQLAvailable() then
        if callback then
            callback(nil, 'MySQL is not available')
        end
        return
    end

    parameters = parameters or {}

    local ok, err = pcall(function()
        MySQL.scalar(query, parameters, function(result)
            if callback then
                callback(result, nil)
            end
        end)
    end)

    if not ok then
        connectionState.errorCount = connectionState.errorCount + 1
        logDatabaseError(('Scalar query error: %s'):format(tostring(err)), query)

        if callback then
            callback(nil, tostring(err))
        end
    end
end

-- =============================================================
-- حفظ لوج في قاعدة البيانات
-- متوافق مع جدول: oxsecure_logs
-- =============================================================
function Database.SaveLog(entry)
    if not USE_DATABASE or not databaseConfig.SaveLogs then
        return
    end

    if not Database.IsReady() then
        return
    end

    local tableName = Database.GetTableName('logs')
    local metaJson = encodeMeta(entry.meta)

    local query = ('INSERT INTO %s (level, category, event_code, message, message_hash, source_system_id, player_id, session_id, is_public, meta_json, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'):format(tableName)

    local parameters = {
        entry.level or 'info',
        entry.category or 'general',
        entry.eventCode or 'log',
        entry.message or '',
        entry.messageHash,
        entry.sourceSystemId,
        entry.playerId,
        entry.sessionId,
        entry.isPublic and 1 or 0,
        metaJson,
        entry.createdAtUnix or os.time()
    }

    Database.Execute(query, parameters, function(result, err)
        if err then
            logDatabaseError(('Failed to save log: %s'):format(tostring(err)), query)
        end
    end)
end

-- =============================================================
-- حفظ إشعار في قاعدة البيانات
-- متوافق مع جدول: oxsecure_notifications
-- =============================================================
function Database.SaveNotification(entry)
    if not USE_DATABASE or not databaseConfig.SaveNotifications then
        return
    end

    if not Database.IsReady() then
        return
    end

    local tableName = Database.GetTableName('notifications')
    local metaJson = encodeMeta(entry.meta)

    local query = ('INSERT INTO %s (notification_type, title_ar, body_ar, position, design_style, duration_ms, meta_json, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)'):format(tableName)

    local parameters = {
        entry.type or 'info',
        entry.title or '',
        entry.message or '',
        entry.position or 'left',
        entry.designStyle or 'default',
        entry.durationMs or 5000,
        metaJson,
        entry.createdAtUnix or os.time()
    }

    Database.Execute(query, parameters, function(result, err)
        if err then
            logDatabaseError(('Failed to save notification: %s'):format(tostring(err)), query)
        end
    end)
end

-- =============================================================
-- حفظ جلسة في قاعدة البيانات
-- متوافق مع جدول: oxsecure_player_sessions
-- =============================================================
function Database.SaveSession(entry)
    if not USE_DATABASE or not databaseConfig.SaveSessions then
        return
    end

    if not Database.IsReady() then
        return
    end

    local tableName = Database.GetTableName('player_sessions')

    local query = ('INSERT INTO %s (session_id, player_id, server_player_id, connected_at) VALUES (?, ?, ?, ?)'):format(tableName)

    local parameters = {
        entry.sessionId,
        entry.playerId,
        entry.serverPlayerId,
        entry.connectedAtUnix or os.time()
    }

    Database.Execute(query, parameters, function(result, err)
        if err then
            logDatabaseError(('Failed to save session: %s'):format(tostring(err)), query)
        end
    end)
end

-- =============================================================
-- حفظ أمر في قاعدة البيانات
-- متوافق مع جدول: oxsecure_command_history
-- =============================================================
function Database.SaveCommand(entry)
    if not USE_DATABASE or not databaseConfig.SaveCommands then
        return
    end

    if not Database.IsReady() then
        return
    end

    local tableName = Database.GetTableName('command_history')
    local argsJson = encodeMeta(entry.args)

    local query = ('INSERT INTO %s (command_name, server_player_id, player_id, args_json, created_at) VALUES (?, ?, ?, ?, ?)'):format(tableName)

    local parameters = {
        entry.commandName,
        entry.serverPlayerId,
        entry.playerId,
        argsJson,
        entry.createdAtUnix or os.time()
    }

    Database.Execute(query, parameters, function(result, err)
        if err then
            logDatabaseError(('Failed to save command: %s'):format(tostring(err)), query)
        end
    end)
end

-- =============================================================
-- حفظ تدقيق في قاعدة البيانات
-- متوافق مع جدول: oxsecure_audit_actions
--
-- إصلاح 1: استخدام العمود details بدلاً من details_json
-- =============================================================
function Database.SaveAudit(entry)
    if not USE_DATABASE or not databaseConfig.SaveAudit then
        return
    end

    if not Database.IsReady() then
        return
    end

    local tableName = Database.GetTableName('audit_actions')
    local detailsJson = encodeMeta(entry.details)

    local query = ('INSERT INTO %s (action_code, actor_admin_id, actor_discord_id, actor_player_id, target_type, target_id, details, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)'):format(tableName)

    local parameters = {
        entry.actionCode,
        entry.actorAdminId,
        entry.actorDiscordId,
        entry.actorPlayerId,
        entry.targetType,
        entry.targetId,
        detailsJson,
        entry.createdAtUnix or os.time()
    }

    Database.Execute(query, parameters, function(result, err)
        if err then
            logDatabaseError(('Failed to save audit: %s'):format(tostring(err)), query)
        end
    end)
end

-- =============================================================
-- حفظ محاولة فاشلة في قاعدة البيانات
-- متوافق مع جدول: oxsecure_failed_attempts
-- =============================================================
function Database.SaveFailedAttempt(entry)
    if not USE_DATABASE or not databaseConfig.SaveFailedAttempts then
        return
    end

    if not Database.IsReady() then
        return
    end

    local tableName = Database.GetTableName('failed_attempts')

    local query = ('INSERT INTO %s (player_id, server_player_id, discord_id, reason_code, ip_hash, created_at) VALUES (?, ?, ?, ?, ?, ?)'):format(tableName)

    local parameters = {
        entry.playerId,
        entry.serverPlayerId,
        entry.discordId,
        entry.reasonCode or 'ERR_UNKNOWN',
        entry.ipHash,
        entry.createdAtUnix or os.time()
    }

    Database.Execute(query, parameters, function(result, err)
        if err then
            logDatabaseError(('Failed to save failed attempt: %s'):format(tostring(err)), query)
        end
    end)
end

-- =============================================================
-- حفظ خطأ في قاعدة البيانات
-- متوافق مع جدول: oxsecure_errors
--
-- إصلاح 2: استخدام اسم الجدول errors بدلاً من error_logs
-- =============================================================
function Database.SaveError(entry)
    if not USE_DATABASE or not databaseConfig.SaveErrors then
        return
    end

    if not Database.IsReady() then
        return
    end

    local tableName = Database.GetTableName('errors')
    local metaJson = encodeMeta(entry.meta)

    local query = ('INSERT INTO %s (error_code, title_ar, body_ar, severity, design_style, source_system_id, player_id, meta_json, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)'):format(tableName)

    local parameters = {
        entry.errorCode or 'ERR_UNKNOWN',
        entry.title or '',
        entry.body or '',
        entry.severity or 'error',
        entry.designStyle or 'error',
        entry.sourceSystemId,
        entry.playerId,
        metaJson,
        entry.createdAtUnix or os.time()
    }

    Database.Execute(query, parameters, function(result, err)
        if err then
            logDatabaseError(('Failed to save error: %s'):format(tostring(err)), query)
        end
    end)
end

-- =============================================================
-- الحصول على إحصائيات قاعدة البيانات
-- =============================================================
function Database.GetStats()
    return {
        ready = connectionState.ready,
        failed = connectionState.failed,
        queryCount = connectionState.queryCount,
        errorCount = connectionState.errorCount,
        lastConnectedAt = connectionState.lastConnectedAt
    }
end

-- =============================================================
-- رسالة تحميل ناجحة
-- =============================================================
if Logger.Debug then
    Logger.Debug('server/core/database.lua loaded')
elseif OxSecure.Console and type(OxSecure.Console.debug) == 'function' then
    OxSecure.Console.debug('server/core/database.lua loaded')
end
