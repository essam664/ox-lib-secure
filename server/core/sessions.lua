-- =============================================================
-- ox_lib_secure
-- File: server/core/sessions.lua
-- Description:
--   طبقة إدارة جلسات اللاعبين لنظام ox_lib_secure.
--
-- Notes:
--   - يتم إنشاء جلسة جديدة عند دخول اللاعب.
--   - يتم إنهاء الجلسة عند خروج اللاعب.
--   - يتم التحقق من الجلسات النشطة السابقة قبل الإنشاء.
--   - يتم توليد معرف جلسة فريد باستخدام Security.
--   - يتم تخزين الجلسات في قاعدة البيانات.
--   - التنظيف يحدّث قاعدة البيانات أيضًا.
--   - قفل بسيط يمنع التسابق عند إنشاء الجلسات.
-- =============================================================

Config = Config or {}
OxSecure = OxSecure or {}
OxSecure.Sessions = OxSecure.Sessions or {}

local Sessions = OxSecure.Sessions
local Database = OxSecure.Database or {}
local Security = OxSecure.Security or {}
local Logger = OxSecure.Logger or {}
local Utils = OxSecure.Utils or {}
local StateManager = OxSecure.StateManager or {}
local Players = OxSecure.Players or {}

local playersConfig = Config.Players or {}
local SESSION_ID_LENGTH = playersConfig.SessionIdLength or 32
local PLAYER_WAIT_TIMEOUT_MS = 10000
local PLAYER_WAIT_INTERVAL_MS = 200
local STALE_SESSION_MAX_AGE_SECONDS = 86400

-- إصلاح 3: جدول أقفال لمنع التسابق عند إنشاء الجلسات
local sessionLocks = {}

-- =============================================================
-- أدوات مساعدة داخلية
-- =============================================================
local function getSessionsCache()
    local state = StateManager.Get and StateManager.Get() or nil
    return state and state.sessions or nil
end

local function logSessionEvent(message, options)
    if Logger.Info then
        Logger.Info(message, options or {
            category = 'session',
            eventCode = 'session_event'
        })
    end
end

local function logSessionError(message, options)
    if Logger.Error then
        Logger.Error(message, options or {
            category = 'session',
            eventCode = 'session_error'
        })
    end
end

-- =============================================================
-- توليد معرف جلسة فريد
-- =============================================================
local function generateSessionId()
    if Utils.GenerateSessionId then
        return Utils.GenerateSessionId(SESSION_ID_LENGTH)
    end

    return ('session_%d_%d'):format(os.time(), math.floor(os.clock() * 1000000))
end

-- =============================================================
-- إصلاح 1: حساب تاريخ القطع في Lua بدلاً من INTERVAL
-- لضمان التوافق مع oxmysql.
-- =============================================================
local function getStaleCutoffDatetime(maxAgeSeconds)
    local cutoffTime = os.time() - maxAgeSeconds
    return os.date('%Y-%m-%d %H:%M:%S', cutoffTime)
end

-- =============================================================
-- إصلاح 3: قفل بسيط لمنع التسابق
-- =============================================================
local function acquireSessionLock(playerId)
    if sessionLocks[playerId] then
        return false
    end

    sessionLocks[playerId] = true
    return true
end

local function releaseSessionLock(playerId)
    sessionLocks[playerId] = nil
end

-- =============================================================
-- إغلاق الجلسات النشطة السابقة في قاعدة البيانات
-- =============================================================
local function closeExistingActiveSessions(playerId, callback)
    local selectQuery = ('SELECT session_id FROM %s WHERE player_id = ? AND disconnected_at IS NULL'):format(Database.GetTableName('player_sessions'))

    Database.Execute(selectQuery, { playerId }, function(results, err)
        if err then
            logSessionError(('Failed to check existing sessions: %s'):format(tostring(err)))
            if callback then callback() end
            return
        end

        if type(results) ~= 'table' or #results == 0 then
            if callback then callback() end
            return
        end

        local updateQuery = ('UPDATE %s SET disconnected_at = NOW() WHERE player_id = ? AND disconnected_at IS NULL'):format(Database.GetTableName('player_sessions'))

        Database.Execute(updateQuery, { playerId }, function(_, updateErr)
            if updateErr then
                logSessionError(('Failed to close existing sessions: %s'):format(tostring(updateErr)))
            else
                logSessionEvent(('Closed %d stale session(s) for player %d'):format(#results, playerId))
            end

            if callback then callback() end
        end)
    end)
end

-- =============================================================
-- إنشاء جلسة جديدة للاعب
--
-- إصلاح 3: قفل بسيط لمنع التسابق.
-- =============================================================
function Sessions.CreateSession(source, playerId, callback)
    local serverId = tonumber(source)

    if not serverId or serverId <= 0 then
        if callback then callback(false, { code = 'ERR_INVALID_SOURCE' }) end
        return
    end

    if not playerId or playerId <= 0 then
        if callback then callback(false, { code = 'ERR_INVALID_PLAYER_ID' }) end
        return
    end

    -- إصلاح 3: محاولة الحصول على قفل
    if not acquireSessionLock(playerId) then
        logSessionError(('Session creation already in progress for player %d, skipping'):format(playerId))
        if callback then callback(false, { code = 'ERR_SESSION_LOCKED' }) end
        return
    end

    -- التحقق من الكاش أولاً
    local existingSession = Sessions.GetActiveSession(serverId)

    if existingSession then
        releaseSessionLock(playerId)
        if callback then callback(true, existingSession.sessionId) end
        return
    end

    -- إغلاق الجلسات النشطة السابقة في قاعدة البيانات
    closeExistingActiveSessions(playerId, function()
        local sessionId = generateSessionId()

        local insertQuery = ('INSERT INTO %s (session_id, player_id, server_player_id, connected_at) VALUES (?, ?, ?, NOW())'):format(Database.GetTableName('player_sessions'))

        Database.Insert(insertQuery, {
            sessionId,
            playerId,
            serverId
        }, function(insertId, err)
            -- تحرير القلق في جميع الحالات
            releaseSessionLock(playerId)

            if err then
                logSessionError(('Failed to create session: %s'):format(tostring(err)))
                if callback then callback(false, { code = 'ERR_DB_INSERT_FAILED', details = err }) end
                return
            end

            -- حفظ في الكاش
            local cache = getSessionsCache()

            if cache then
                if not cache.bySessionId then
                    cache.bySessionId = {}
                end

                if not cache.byServerId then
                    cache.byServerId = {}
                end

                if not cache.byDbId then
                    cache.byDbId = {}
                end

                local sessionData = {
                    id = insertId,
                    sessionId = sessionId,
                    playerId = playerId,
                    serverPlayerId = serverId,
                    connectedAt = os.time()
                }

                cache.bySessionId[sessionId] = sessionData
                cache.byServerId[serverId] = sessionId
                cache.byDbId[insertId] = sessionId
                cache.activeCount = (cache.activeCount or 0) + 1
            end

            logSessionEvent(('Session created: %s for player %d'):format(sessionId:sub(1, 8), playerId))

            if callback then callback(true, sessionId) end
        end)
    end)
end

-- =============================================================
-- إنهاء جلسة لاعب
--
-- إصلاح 2: إضافة بديل للبحث في قاعدة البيانات عند غياب
-- الجلسة من الكاش.
-- =============================================================
function Sessions.EndSession(source, callback)
    local serverId = tonumber(source)

    if not serverId or serverId <= 0 then
        if callback then callback(false) end
        return
    end

    local cache = getSessionsCache()
    local sessionId = nil

    -- محاولة الحصول على معرف الجلسة من الكاش
    if cache and cache.byServerId then
        sessionId = cache.byServerId[serverId]
    end

    -- إصلاح 2: إذا لم نجد الجلسة في الكاش، نبحث في قاعدة البيانات
    if not sessionId then
        local selectQuery = ('SELECT session_id FROM %s WHERE server_player_id = ? AND disconnected_at IS NULL ORDER BY connected_at DESC LIMIT 1'):format(Database.GetTableName('player_sessions'))

        Database.Single(selectQuery, { serverId }, function(result, err)
            if err or not result or not result.session_id then
                if callback then callback(false) end
                return
            end

            -- إغلاق الجلسة في قاعدة البيانات
            local updateQuery = ('UPDATE %s SET disconnected_at = NOW() WHERE session_id = ? AND disconnected_at IS NULL'):format(Database.GetTableName('player_sessions'))

            Database.Execute(updateQuery, { result.session_id }, function(_, updateErr)
                if updateErr then
                    logSessionError(('Failed to end session from DB: %s'):format(tostring(updateErr)))
                end

                if callback then callback(true) end
            end)
        end)
        return
    end

    -- المسار العادي: الجلسة موجودة في الكاش
    local updateQuery = ('UPDATE %s SET disconnected_at = NOW() WHERE session_id = ? AND disconnected_at IS NULL'):format(Database.GetTableName('player_sessions'))

    Database.Execute(updateQuery, { sessionId }, function(_, err)
        if err then
            logSessionError(('Failed to end session: %s'):format(tostring(err)))
        end

        local sessionData = cache.bySessionId and cache.bySessionId[sessionId]

        if cache.bySessionId then
            cache.bySessionId[sessionId] = nil
        end

        if cache.byServerId then
            cache.byServerId[serverId] = nil
        end

        if sessionData and cache.byDbId then
            cache.byDbId[sessionData.id] = nil
        end

        if cache.activeCount and cache.activeCount > 0 then
            cache.activeCount = cache.activeCount - 1
        end

        logSessionEvent(('Session ended: %s'):format(sessionId:sub(1, 8)))

        if callback then callback(true) end
    end)
end

-- =============================================================
-- جلب الجلسة النشطة للاعب
-- =============================================================
function Sessions.GetActiveSession(source)
    local serverId = tonumber(source)

    if not serverId or serverId <= 0 then
        return nil
    end

    local cache = getSessionsCache()

    if not cache then
        return nil
    end

    local sessionId = cache.byServerId and cache.byServerId[serverId]

    if not sessionId then
        return nil
    end

    return cache.bySessionId and cache.bySessionId[sessionId]
end

-- =============================================================
-- جلب معرف الجلسة النشطة
-- =============================================================
function Sessions.GetSessionId(source)
    local session = Sessions.GetActiveSession(source)

    if session then
        return session.sessionId
    end

    return nil
end

-- =============================================================
-- جلب الجلسة من قاعدة البيانات
-- =============================================================
function Sessions.GetSessionFromDb(sessionId, callback)
    if type(sessionId) ~= 'string' or sessionId == '' then
        if callback then callback(nil, 'Invalid session ID') end
        return
    end

    local cache = getSessionsCache()

    if cache and cache.bySessionId and cache.bySessionId[sessionId] then
        if callback then callback(cache.bySessionId[sessionId], nil) end
        return
    end

    local selectQuery = ('SELECT * FROM %s WHERE session_id = ?'):format(Database.GetTableName('player_sessions'))

    Database.Single(selectQuery, { sessionId }, function(result, err)
        if err then
            if callback then callback(nil, err) end
            return
        end

        if callback then callback(result, nil) end
    end)
end

-- =============================================================
-- جلب جميع الجلسات النشطة
-- =============================================================
function Sessions.GetAllActiveSessions()
    local cache = getSessionsCache()

    if not cache or not cache.bySessionId then
        return {}
    end

    local sessions = {}

    for _, sessionData in pairs(cache.bySessionId) do
        sessions[#sessions + 1] = sessionData
    end

    return sessions
end

-- =============================================================
-- الحصول على عدد الجلسات النشطة
-- =============================================================
function Sessions.GetActiveCount()
    local cache = getSessionsCache()

    if not cache then
        return 0
    end

    return cache.activeCount or 0
end

-- =============================================================
-- تنظيف الجلسات القديمة
--
-- إصلاح 1: استخدام تاريخ محسوب في Lua بدلاً من INTERVAL.
-- إصلاح 2: تحديث قاعدة البيانات أيضًا.
-- =============================================================
function Sessions.CleanupStaleSessions(maxAgeSeconds)
    maxAgeSeconds = maxAgeSeconds or STALE_SESSION_MAX_AGE_SECONDS

    local cache = getSessionsCache()

    if not cache or not cache.bySessionId then
        return 0
    end

    local now = os.time()
    local removedCount = 0

    for sessionId, sessionData in pairs(cache.bySessionId) do
        if sessionData.connectedAt and (now - sessionData.connectedAt) > maxAgeSeconds then
            cache.bySessionId[sessionId] = nil

            if cache.byServerId and sessionData.serverPlayerId then
                cache.byServerId[sessionData.serverPlayerId] = nil
            end

            if cache.byDbId and sessionData.id then
                cache.byDbId[sessionData.id] = nil
            end

            removedCount = removedCount + 1
        end
    end

    if cache.activeCount then
        cache.activeCount = math.max(0, cache.activeCount - removedCount)
    end

    -- إصلاح 1 و2: تحديث قاعدة البيانات باستخدام تاريخ محسوب
    if removedCount > 0 then
        local cutoffDatetime = getStaleCutoffDatetime(maxAgeSeconds)
        local cleanupQuery = ('UPDATE %s SET disconnected_at = NOW() WHERE disconnected_at IS NULL AND connected_at < ?'):format(Database.GetTableName('player_sessions'))

        Database.Execute(cleanupQuery, { cutoffDatetime }, function(_, err)
            if err then
                logSessionError(('Failed to cleanup stale sessions in DB: %s'):format(tostring(err)))
            else
                logSessionEvent(('Cleaned up %d stale session(s)'):format(removedCount))
            end
        end)
    end

    return removedCount
end

-- =============================================================
-- ربط الجلسات بأحداث اللاعبين
-- =============================================================
AddEventHandler('playerJoin', function()
    local src = source
    local waitStartTime = os.time()

    local function tryCreateSession()
        local playerData = Players.GetPlayer(src)

        if playerData and playerData.id then
            Sessions.CreateSession(src, playerData.id, function(ok, sessionId)
                if not ok then
                    logSessionError(('Failed to create session for player %d'):format(playerData.id))
                end
            end)
            return
        end

        local elapsed = os.time() - waitStartTime

        if elapsed * 1000 >= PLAYER_WAIT_TIMEOUT_MS then
            logSessionError(('Timeout waiting for player %d to be ready for session creation'):format(src))
            return
        end

        SetTimeout(PLAYER_WAIT_INTERVAL_MS, tryCreateSession)
    end

    tryCreateSession()
end)

AddEventHandler('playerDropped', function()
    local src = source
    Sessions.EndSession(src)
end)

-- =============================================================
-- مهمة دورية لتنظيف الجلسات القديمة
-- =============================================================
CreateThread(function()
    while true do
        Wait(3600000)
        Sessions.CleanupStaleSessions()
    end
end)

-- =============================================================
-- رسالة تحميل ناجحة
-- =============================================================
if Logger.Debug then
    Logger.Debug('server/core/sessions.lua loaded')
elseif OxSecure.Console and type(OxSecure.Console.debug) == 'function' then
    OxSecure.Console.debug('server/core/sessions.lua loaded')
end
