-- =============================================================
-- ox_lib_secure
-- File: server/core/sessions.lua
-- Description:
--   وحدة إدارة الجلسات لنظام ox_lib_secure.
--   تتبع جلسات اللاعبين وتدير دورة حياتها.
--
-- Notes:
--   - مواءمة 100% مع config/main.lua النهائي.
--   - جدول الترحيلات: oxsecure_player_sessions.
--   - أعمدة الجدول: session_id, player_id, server_player_id,
--     connected_at, disconnected_at.
--   - تنظيف دوري للجلسات المنتهية.
--   - تحميل اختياري للجلسات عند البدء.
--   - مدة إزالة الجلسة من الذاكرة قابلة للإعداد.
--   - معالجة onResourceStop باستخدام EndSession.
-- =============================================================

Config = Config or {}
OxSecure = OxSecure or {}
OxSecure.Sessions = OxSecure.Sessions or {}

local Sessions = OxSecure.Sessions
local Logger = OxSecure.Logger or {}
local Database = OxSecure.Database or {}
local Security = OxSecure.Security or {}
local Audit = OxSecure.Audit or {}

-- =============================================================
-- قراءة الإعدادات من الكونفق
-- متوافقة حرفيًا مع config/main.lua
-- =============================================================
local sessionsConfig = Config.Sessions or {}

local TRACK_SESSIONS = sessionsConfig.TrackSessions ~= false
local MAX_ACTIVE_PER_PLAYER = sessionsConfig.MaxActivePerPlayer or 1
local CLEANUP_INTERVAL_SECONDS = sessionsConfig.CleanupIntervalSeconds or 1800
local SESSION_EXPIRY_HOURS = sessionsConfig.SessionExpiryHours or 24
local SESSION_ID_LENGTH = sessionsConfig.SessionIdLength or 32
local VALIDATE_ON_JOIN = sessionsConfig.ValidateOnJoin ~= false
local LOG_SESSION_END = sessionsConfig.LogSessionEnd ~= false

-- إعدادات اختيارية (لها قيم افتراضية)
local LOAD_SESSIONS_ON_START = sessionsConfig.LoadSessionsOnStart == true
local SESSION_CLEANUP_DELAY_MS = sessionsConfig.SessionCleanupDelayMs or 5000

-- =============================================================
-- الحالة الداخلية
-- =============================================================
local activeSessions = {}
local isInitialized = false

-- =============================================================
-- أدوات مساعدة داخلية
-- =============================================================
local function logSession(message, level)
    level = level or 'info'
    if Logger and Logger.Log then
        Logger.Log(level, message, { category = 'sessions' })
    else
        print(('[ox_lib_secure] [SESSIONS] %s'):format(message))
    end
end

local function getCurrentTimestamp()
    return os.time()
end

local function getSessionExpirySeconds()
    return SESSION_EXPIRY_HOURS * 3600
end

-- =============================================================
-- توليد معرف جلسة فريد
-- =============================================================
local function generateSessionId()
    local chars = '0123456789abcdef'
    local id = {}
    for i = 1, SESSION_ID_LENGTH do
        local idx = math.random(1, 16)
        id[i] = chars:sub(idx, idx)
    end
    return table.concat(id)
end

-- =============================================================
-- الحصول على اسم جدول الجلسات
-- =============================================================
local function getSessionsTableName()
    if Database and Database.GetTableName then
        local ok, name = pcall(Database.GetTableName, 'player_sessions')
        if ok and name then
            return name
        end
    end
    return 'oxsecure_player_sessions'
end

-- =============================================================
-- تهيئة وحدة الجلسات
-- =============================================================
function Sessions.Initialize()
    if isInitialized then
        return true
    end

    if not TRACK_SESSIONS then
        logSession('Session tracking is disabled.')
        return true
    end

    logSession('Initializing sessions module...')
    logSession(('Max active sessions per player: %d'):format(MAX_ACTIVE_PER_PLAYER))
    logSession(('Session expiry: %d hours'):format(SESSION_EXPIRY_HOURS))
    logSession(('Cleanup interval: %d seconds'):format(CLEANUP_INTERVAL_SECONDS))
    logSession(('Session cleanup delay: %d ms'):format(SESSION_CLEANUP_DELAY_MS))
    logSession(('Load sessions on start: %s'):format(tostring(LOAD_SESSIONS_ON_START)))

    -- بدء التنظيف الدوري
    CreateThread(function()
        while true do
            Wait(CLEANUP_INTERVAL_SECONDS * 1000)
            Sessions.Cleanup()
        end
    end)

    -- تحميل اختياري للجلسات من قاعدة البيانات عند البدء
    if LOAD_SESSIONS_ON_START then
        Sessions.LoadActiveSessionsFromDB()
    end

    isInitialized = true
    logSession('Sessions module initialized successfully.')
    return true
end

-- =============================================================
-- التحقق من حالة التهيئة
-- =============================================================
function Sessions.IsInitialized()
    return isInitialized
end

-- =============================================================
-- تحميل الجلسات النشطة من قاعدة البيانات عند البدء
-- =============================================================
function Sessions.LoadActiveSessionsFromDB()
    if not Database or not Database.Execute then
        logSession('Database not available, skipping session loading.', 'warn')
        return
    end

    local tableName = getSessionsTableName()
    local expirySeconds = getSessionExpirySeconds()

    Database.Execute(
        ('SELECT session_id, player_id, server_player_id, connected_at FROM %s WHERE disconnected_at IS NULL'):format(tableName),
        {},
        function(results)
            if results and #results > 0 then
                local now = getCurrentTimestamp()
                local loaded = 0
                local expired = 0

                for _, row in ipairs(results) do
                    if row.session_id and row.server_player_id then
                        -- حساب وقت الاتصال
                        local connectedAt = now
                        if row.connected_at then
                            local ok, parsedTime = pcall(function()
                                return os.time({
                                    year = tonumber(row.connected_at:sub(1, 4)),
                                    month = tonumber(row.connected_at:sub(6, 7)),
                                    day = tonumber(row.connected_at:sub(9, 10)),
                                    hour = tonumber(row.connected_at:sub(12, 13)),
                                    min = tonumber(row.connected_at:sub(15, 16)),
                                    sec = tonumber(row.connected_at:sub(18, 19))
                                })
                            end)

                            if ok and parsedTime then
                                connectedAt = parsedTime
                            end
                        end

                        -- التحقق من انتهاء الصلاحية
                        local expiresAt = connectedAt + expirySeconds

                        if expiresAt > now then
                            activeSessions[row.session_id] = {
                                sessionId = row.session_id,
                                serverPlayerId = row.server_player_id,
                                playerId = row.player_id,
                                connectedAt = connectedAt,
                                lastActivity = now,
                                expiresAt = expiresAt,
                                isActive = true
                            }
                            loaded = loaded + 1
                        else
                            -- الجلسة منتهية الصلاحية، تحديث قاعدة البيانات
                            Database.Execute(
                                ('UPDATE %s SET disconnected_at = NOW() WHERE session_id = ? AND disconnected_at IS NULL'):format(tableName),
                                { row.session_id }
                            )
                            expired = expired + 1
                        end
                    end
                end

                if loaded > 0 or expired > 0 then
                    logSession(('Loaded sessions from DB: %d active, %d expired'):format(loaded, expired))
                end
            end
        end
    )
end

-- =============================================================
-- إنشاء جلسة جديدة
-- =============================================================
function Sessions.CreateSession(serverPlayerId, playerId)
    if not TRACK_SESSIONS then
        return nil
    end

    if not serverPlayerId then
        return nil, 'Server player ID is required'
    end

    -- التحقق من الحد الأقصى للجلسات النشطة
    local activeCount = 0
    for _, session in pairs(activeSessions) do
        if session.serverPlayerId == serverPlayerId and session.isActive then
            activeCount = activeCount + 1
        end
    end

    if activeCount >= MAX_ACTIVE_PER_PLAYER then
        -- إنهاء أقدم جلسة نشطة
        local oldestSession = nil
        local oldestTime = math.huge

        for sessionId, session in pairs(activeSessions) do
            if session.serverPlayerId == serverPlayerId and session.isActive then
                if session.connectedAt < oldestTime then
                    oldestTime = session.connectedAt
                    oldestSession = sessionId
                end
            end
        end

        if oldestSession then
            Sessions.EndSession(oldestSession, 'Replaced by new session')
        end
    end

    -- إنشاء الجلسة الجديدة
    local sessionId = generateSessionId()
    local now = getCurrentTimestamp()

    activeSessions[sessionId] = {
        sessionId = sessionId,
        serverPlayerId = serverPlayerId,
        playerId = playerId,
        connectedAt = now,
        lastActivity = now,
        expiresAt = now + getSessionExpirySeconds(),
        isActive = true
    }

    -- حفظ في قاعدة البيانات (غير متزامن)
    if Database and Database.Execute then
        local tableName = getSessionsTableName()

        Database.Execute(
            ('INSERT INTO %s (session_id, player_id, server_player_id, connected_at) VALUES (?, ?, ?, NOW())'):format(tableName),
            { sessionId, playerId, serverPlayerId }
        )
    end

    logSession(('Session created: %s for player %d'):format(sessionId:sub(1, 8) .. '...', serverPlayerId))

    return sessionId
end

-- =============================================================
-- إنهاء جلسة
-- =============================================================
function Sessions.EndSession(sessionId, reason)
    if not sessionId then
        return false
    end

    local session = activeSessions[sessionId]

    if not session then
        return false
    end

    session.isActive = false
    session.disconnectedAt = getCurrentTimestamp()
    session.endReason = reason or 'Unknown'

    -- تحديث قاعدة البيانات
    if Database and Database.Execute then
        local tableName = getSessionsTableName()

        Database.Execute(
            ('UPDATE %s SET disconnected_at = NOW() WHERE session_id = ? AND disconnected_at IS NULL'):format(tableName),
            { sessionId }
        )
    end

    -- تسجيل في اللوجات
    if LOG_SESSION_END then
        logSession(('Session ended: %s for player %d (reason: %s)'):format(
            sessionId:sub(1, 8) .. '...',
            session.serverPlayerId,
            reason or 'Unknown'
        ))
    end

    -- تسجيل في التدقيق
    if Audit and Audit.Record then
        Audit.Record('session_ended', 'system', 'player', session.serverPlayerId, {
            sessionId = sessionId,
            reason = reason,
            duration = session.disconnectedAt - session.connectedAt
        })
    end

    -- إزالة من الذاكرة بعد مدة قابلة للإعداد
    SetTimeout(SESSION_CLEANUP_DELAY_MS, function()
        activeSessions[sessionId] = nil
    end)

    return true
end

-- =============================================================
-- إنهاء جميع جلسات لاعب
-- =============================================================
function Sessions.EndAllSessions(serverPlayerId)
    if not serverPlayerId then
        return 0
    end

    local ended = 0

    for sessionId, session in pairs(activeSessions) do
        if session.serverPlayerId == serverPlayerId and session.isActive then
            Sessions.EndSession(sessionId, 'Player disconnected')
            ended = ended + 1
        end
    end

    return ended
end

-- =============================================================
-- الحصول على جلسة نشطة
-- =============================================================
function Sessions.GetActiveSession(serverPlayerId)
    if not serverPlayerId then
        return nil
    end

    for sessionId, session in pairs(activeSessions) do
        if session.serverPlayerId == serverPlayerId and session.isActive then
            return session
        end
    end

    return nil
end

-- =============================================================
-- الحصول على جلسة بواسطة المعرف
-- =============================================================
function Sessions.GetSession(sessionId)
    if not sessionId then
        return nil
    end

    return activeSessions[sessionId]
end

-- =============================================================
-- التحقق من صلاحية جلسة
-- =============================================================
function Sessions.IsSessionValid(sessionId)
    if not sessionId then
        return false
    end

    local session = activeSessions[sessionId]

    if not session then
        return false
    end

    if not session.isActive then
        return false
    end

    if session.expiresAt < getCurrentTimestamp() then
        Sessions.EndSession(sessionId, 'Session expired')
        return false
    end

    return true
end

-- =============================================================
-- تحديث نشاط الجلسة
-- =============================================================
function Sessions.UpdateActivity(sessionId)
    if not sessionId then
        return false
    end

    local session = activeSessions[sessionId]

    if not session then
        return false
    end

    session.lastActivity = getCurrentTimestamp()
    session.expiresAt = session.lastActivity + getSessionExpirySeconds()

    return true
end

-- =============================================================
-- التحقق عند الانضمام
-- =============================================================
function Sessions.ValidateOnJoin(serverPlayerId, playerId)
    if not VALIDATE_ON_JOIN then
        return true
    end

    if not serverPlayerId then
        return false, 'Server player ID is required'
    end

    -- التحقق من جلسات نشطة موجودة
    local activeSession = Sessions.GetActiveSession(serverPlayerId)

    if activeSession then
        if MAX_ACTIVE_PER_PLAYER <= 1 then
            Sessions.EndSession(activeSession.sessionId, 'Reconnected')
        end
    end

    -- إنشاء جلسة جديدة
    local sessionId = Sessions.CreateSession(serverPlayerId, playerId)

    if sessionId then
        return true, sessionId
    end

    return false, 'Failed to create session'
end

-- =============================================================
-- الحصول على جميع الجلسات النشطة
-- =============================================================
function Sessions.GetAllActiveSessions()
    local result = {}

    for sessionId, session in pairs(activeSessions) do
        if session.isActive then
            result[#result + 1] = {
                sessionId = sessionId,
                serverPlayerId = session.serverPlayerId,
                playerId = session.playerId,
                connectedAt = session.connectedAt,
                lastActivity = session.lastActivity,
                expiresAt = session.expiresAt
            }
        end
    end

    return result
end

-- =============================================================
-- الحصول على عدد الجلسات النشطة
-- =============================================================
function Sessions.GetActiveCount()
    local count = 0

    for _, session in pairs(activeSessions) do
        if session.isActive then
            count = count + 1
        end
    end

    return count
end

-- =============================================================
-- تنظيف دوري
-- =============================================================
function Sessions.Cleanup()
    local now = getCurrentTimestamp()
    local cleaned = 0

    for sessionId, session in pairs(activeSessions) do
        -- إزالة الجلسات المنتهية
        if not session.isActive and session.disconnectedAt then
            if (now - session.disconnectedAt) > 300 then
                activeSessions[sessionId] = nil
                cleaned = cleaned + 1
            end
        end

        -- إنهاء الجلسات المنتهية الصلاحية
        if session.isActive and session.expiresAt < now then
            Sessions.EndSession(sessionId, 'Session expired during cleanup')
            cleaned = cleaned + 1
        end
    end

    if cleaned > 0 then
        logSession(('Cleanup: processed %d sessions'):format(cleaned))
    end
end

-- =============================================================
-- إحصائيات
-- =============================================================
function Sessions.GetStats()
    local activeCount = 0
    local totalInMemory = 0

    for _, session in pairs(activeSessions) do
        totalInMemory = totalInMemory + 1
        if session.isActive then
            activeCount = activeCount + 1
        end
    end

    return {
        activeSessions = activeCount,
        totalInMemory = totalInMemory,
        maxActivePerPlayer = MAX_ACTIVE_PER_PLAYER,
        sessionExpiryHours = SESSION_EXPIRY_HOURS,
        cleanupIntervalSeconds = CLEANUP_INTERVAL_SECONDS,
        cleanupDelayMs = SESSION_CLEANUP_DELAY_MS,
        loadSessionsOnStart = LOAD_SESSIONS_ON_START,
        trackSessions = TRACK_SESSIONS,
        isInitialized = isInitialized
    }
end

-- =============================================================
-- معالجة أحداث اللاعبين
-- =============================================================
AddEventHandler('playerDropped', function(reason)
    local src = source

    if not src then
        return
    end

    if TRACK_SESSIONS then
        Sessions.EndAllSessions(src)
    end
end)

-- =============================================================
-- معالجة إيقاف المورد
-- استخدام EndSession بدلاً من تكرار المنطق
-- =============================================================
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    if not TRACK_SESSIONS then
        return
    end

    logSession('Resource stopping. Ending all active sessions...')

    -- جمع معرفات الجلسات النشطة أولاً (لتجنب التعديل أثناء التكرار)
    local activeIds = {}
    for sessionId, session in pairs(activeSessions) do
        if session.isActive then
            activeIds[#activeIds + 1] = sessionId
        end
    end

    -- إنهاء كل جلسة باستخدام الدالة الموحدة
    local ended = 0
    for _, sessionId in ipairs(activeIds) do
        if Sessions.EndSession(sessionId, 'Resource stopped') then
            ended = ended + 1
        end
    end

    if ended > 0 then
        logSession(('Resource stop: ended %d active sessions.'):format(ended))
    end
end)

-- =============================================================
-- تهيئة عند التحميل
-- =============================================================
Sessions.Initialize()

-- =============================================================
-- رسالة تحميل ناجحة
-- =============================================================
if Logger and Logger.Debug then
    Logger.Debug('server/core/sessions.lua loaded')
else
    print('[ox_lib_secure] server/core/sessions.lua loaded')
end
