-- =============================================================
-- ox_lib_secure
-- File: server/core/state.lua
-- Description:
--   الحالة المركزية لنظام ox_lib_secure.
--
-- Notes:
--   - هذه الحالة خاصة بوقت التشغيل فقط.
--   - لا يجب تخزين بيانات حساسة دائمة هنا.
--   - أي بيانات مهمة يجب أن تُحفظ في قاعدة البيانات
--     عبر الطبقات المختصة.
-- =============================================================

Config = Config or {}
OxSecure = OxSecure or {}
OxSecure.State = OxSecure.State or {}

-- =============================================================
-- أدوات الوقت
-- =============================================================
local function nowMs()
    if type(GetGameTimer) == 'function' then
        return GetGameTimer()
    end

    return os.time() * 1000
end

-- =============================================================
-- قيم مساعدة من الإعدادات
-- =============================================================
local securityConfig = Config.Security or {}
local memoryCacheConfig = securityConfig.MemoryCache or {}
local performanceConfig = Config.Performance or {}
local logsConfig = Config.Logs or {}

local maxCacheEntries = memoryCacheConfig.MaxEntries or performanceConfig.MaxCacheSize or 500
local maxLogBuffer = logsConfig.MaxBuffer or 100

-- =============================================================
-- إنشاء حالة التشغيل
-- =============================================================
local runtime = {
    meta = {
        resourceName = Config.ResourceName or GetCurrentResourceName(),
        version = Config.Version or '1.0.0',
        language = Config.Language or 'ar',
        startedAt = os.time(),
        startedAtMs = nowMs()
    },

    flags = {
        databaseAvailable = OxSecure.State.dbReady == true,
        buildMode = OxSecure.BuildMode == true,
        debug = Config.Debug == true
    },

    limits = {
        maxCacheEntries = maxCacheEntries,
        maxLogBuffer = maxLogBuffer
    },

    -- =============================================================
    -- الكاشات المؤقتة
    -- =============================================================
    cache = {
        generic = {},
        permissions = {},
        players = {},
        systems = {},
        settings = {},
        locales = {},
        keywords = {},
        signingKeys = {},
        dbQueries = {}
    },

    -- =============================================================
    -- حالة الأمان
    -- =============================================================
    security = {
        nonces = {},
        failedAttempts = {},
        blockedPlayers = {},
        blockedSystems = {},
        recentEvents = {}
    },

    -- =============================================================
    -- معدل الاستخدام في الذاكرة
    -- =============================================================
    rateLimit = {
        buckets = {},
        lastCleanupMs = nowMs()
    },

    -- =============================================================
    -- حالة اللاعبين
    -- =============================================================
    players = {
        byServerId = {},
        byDbId = {},
        byPrimaryIdentifier = {},
        count = 0
    },

    -- =============================================================
    -- حالة الجلسات
    -- =============================================================
    sessions = {
        bySessionId = {},
        byDbId = {},
        byServerId = {},
        activeCount = 0
    },

    -- =============================================================
    -- حالة الأنظمة المربوطة
    -- =============================================================
    systems = {
        byId = {},
        byCode = {},
        tokenHints = {},
        scopesBySystem = {}
    },

    -- =============================================================
    -- حالة الصلاحيات
    -- =============================================================
    permissions = {
        adminsByDiscord = {},
        roles = {},
        rolePermissions = {},
        adminRoles = {},
        resolvedPermissions = {}
    },

    -- =============================================================
    -- اللوجات المؤقتة
    -- =============================================================
    logs = {
        buffer = {},
        bufferSize = 0,
        lastFlushMs = 0
    },

    -- =============================================================
    -- قائمة الانتظار
    -- =============================================================
    queue = {
        pending = {},
        processing = {},
        failed = {},
        lastWorkerMs = 0,
        totalQueued = 0
    },

    -- =============================================================
    -- الإشعارات
    -- =============================================================
    notifications = {
        activeByPlayer = {},
        lastSentAtByPlayer = {}
    },

    -- =============================================================
    -- حالة الواجهة
    -- =============================================================
    ui = {
        openPanelsByPlayer = {},
        lastPanelActionAt = {}
    },

    -- =============================================================
    -- الأقفال
    -- =============================================================
    locks = {
        db = false,
        queue = false,
        logsFlush = false,
        permissions = false,
        systems = false
    },

    -- =============================================================
    -- أخطاء التشغيل
    -- =============================================================
    errors = {
        runtime = {}
    }
}

OxSecure.State.Runtime = runtime

-- =============================================================
-- مدير الحالة
-- =============================================================
OxSecure.StateManager = OxSecure.StateManager or {}

local function getRuntime()
    return OxSecure.State.Runtime
end

OxSecure.StateManager.Get = function()
    return getRuntime()
end

OxSecure.StateManager.NowMs = function()
    return nowMs()
end

OxSecure.StateManager.ClearTable = function(target)
    if type(target) ~= 'table' then
        return
    end

    for key in pairs(target) do
        target[key] = nil
    end
end

-- =============================================================
-- مسح الكاشات
-- =============================================================
OxSecure.StateManager.ResetCaches = function()
    local state = getRuntime()

    if not state then
        return
    end

    for _, cacheTable in pairs(state.cache) do
        OxSecure.StateManager.ClearTable(cacheTable)
    end
end

-- =============================================================
-- مسح حالة الأمان المؤقتة
-- =============================================================
OxSecure.StateManager.ResetSecurityTemporaryState = function()
    local state = getRuntime()

    if not state then
        return
    end

    OxSecure.StateManager.ClearTable(state.security.nonces)
    OxSecure.StateManager.ClearTable(state.security.failedAttempts)
    OxSecure.StateManager.ClearTable(state.security.recentEvents)
end

-- =============================================================
-- الأقفال
-- =============================================================
OxSecure.StateManager.IsLocked = function(name)
    local state = getRuntime()

    if not state then
        return false
    end

    return state.locks[name] == true
end

OxSecure.StateManager.SetLock = function(name, value)
    local state = getRuntime()

    if not state then
        return
    end

    state.locks[name] = value == true
end

-- =============================================================
-- تسجيل أخطاء التشغيل
-- =============================================================
OxSecure.StateManager.AddRuntimeError = function(message)
    local state = getRuntime()

    if not state then
        return
    end

    table.insert(state.errors.runtime, {
        message = tostring(message),
        at = nowMs()
    })
end

-- =============================================================
-- تحديث علم قاعدة البيانات
-- =============================================================
OxSecure.StateManager.SetDatabaseAvailable = function(isAvailable)
    local state = getRuntime()

    if not state then
        return
    end

    state.flags.databaseAvailable = isAvailable == true
end

-- =============================================================
-- مسح حالة اللاعبين والجلسات
--
-- يُستخدم عند الحاجة لإعادة تحميل بيانات اللاعبين أو
-- عند تنظيف عام للحالة.
-- =============================================================
OxSecure.StateManager.ResetPlayersAndSessions = function()
    local state = getRuntime()

    if not state then
        return
    end

    OxSecure.StateManager.ClearTable(state.players.byServerId)
    OxSecure.StateManager.ClearTable(state.players.byDbId)
    OxSecure.StateManager.ClearTable(state.players.byPrimaryIdentifier)
    state.players.count = 0

    OxSecure.StateManager.ClearTable(state.sessions.bySessionId)
    OxSecure.StateManager.ClearTable(state.sessions.byDbId)
    OxSecure.StateManager.ClearTable(state.sessions.byServerId)
    state.sessions.activeCount = 0
end

-- =============================================================
-- مسح حالة الأنظمة المربوطة
-- =============================================================
OxSecure.StateManager.ResetSystems = function()
    local state = getRuntime()

    if not state then
        return
    end

    OxSecure.StateManager.ClearTable(state.systems.byId)
    OxSecure.StateManager.ClearTable(state.systems.byCode)
    OxSecure.StateManager.ClearTable(state.systems.tokenHints)
    OxSecure.StateManager.ClearTable(state.systems.scopesBySystem)
end

-- =============================================================
-- مسح حالة الصلاحيات
-- =============================================================
OxSecure.StateManager.ResetPermissions = function()
    local state = getRuntime()

    if not state then
        return
    end

    OxSecure.StateManager.ClearTable(state.permissions.adminsByDiscord)
    OxSecure.StateManager.ClearTable(state.permissions.roles)
    OxSecure.StateManager.ClearTable(state.permissions.rolePermissions)
    OxSecure.StateManager.ClearTable(state.permissions.adminRoles)
    OxSecure.StateManager.ClearTable(state.permissions.resolvedPermissions)
end

-- =============================================================
-- مسح اللوجات المؤقتة
-- =============================================================
OxSecure.StateManager.ResetLogBuffer = function()
    local state = getRuntime()

    if not state then
        return
    end

    OxSecure.StateManager.ClearTable(state.logs.buffer)
    state.logs.bufferSize = 0
    state.logs.lastFlushMs = nowMs()
end

-- =============================================================
-- مسح قائمة الانتظار
-- =============================================================
OxSecure.StateManager.ResetQueue = function()
    local state = getRuntime()

    if not state then
        return
    end

    OxSecure.StateManager.ClearTable(state.queue.pending)
    OxSecure.StateManager.ClearTable(state.queue.processing)
    OxSecure.StateManager.ClearTable(state.queue.failed)
    state.queue.lastWorkerMs = nowMs()
    state.queue.totalQueued = 0
end

-- =============================================================
-- رسالة تحميل ناجحة
-- =============================================================
if OxSecure.Console and type(OxSecure.Console.debug) == 'function' then
    OxSecure.Console.debug('server/core/state.lua loaded')
end
