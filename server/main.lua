-- =============================================================
-- ox_lib_secure
-- File: server/main.lua
-- Description:
--   نقطة التشغيل الرئيسية لجهة السيرفر.
--
-- Responsibilities:
--   - تجهيز مساحة العمل OxSecure
--   - تحميل ملفات السيرفر بالترتيب
--   - انتظار جاهزية قاعدة البيانات
--   - اختبار اتصال قاعدة البيانات
--   - تنفيذ فحوصات الإقلاع
--   - تشغيل النظام بطريقة آمنة
--
-- Important:
--   - الملفات المحمّلة هنا يتم قراءتها عبر LoadResourceFile.
--   - لا يجب إضافتها إلى قسم files في fxmanifest.lua
--     لأن files مخصص للملفات التي تصل إلى الكلاينت.
--   - أي وحدة تريد مشاركة وظائفها مع بقية الملفات يجب أن
--     تُسجَّل داخل OxSecure، وليس كمتغير عام.
-- =============================================================

Config = Config or {}
Config.ResourceName = GetCurrentResourceName()

-- =============================================================
-- مساحة العمل الرئيسية
-- =============================================================
OxSecure = OxSecure or {}
OxSecure.ResourceName = Config.ResourceName
OxSecure.Version = Config.Version or '1.0.0'
OxSecure.Debug = Config.Debug == true

-- =============================================================
-- وضع البناء
--
-- أثناء بناء الملفات واحدة تلو الأخرى، نسمح للمورد أن يعمل
-- حتى لو بعض الملفات غير موجودة بعد.
-- عند اكتمال المشروع، يجب تحويلها إلى:
-- OxSecure.BuildMode = false
-- =============================================================
OxSecure.BuildMode = true

OxSecure.State = {
    booted = false,
    booting = false,
    dbReady = false,
    loadedFiles = {},
    missingFiles = {},
    errors = {}
}

-- =============================================================
-- أدوات التسجيل المبكرة
-- =============================================================
local function formatConsole(level, message)
    return ('^5[ox_lib_secure]^7 ^6[%s]^7 %s'):format(level, message)
end

local function logInfo(message)
    print(formatConsole('INFO', message))
end

local function logWarn(message)
    print(formatConsole('^3WARN^7', message))
end

local function logError(message)
    print(formatConsole('^1ERROR^7', message))
end

local function logDebug(message)
    if OxSecure.Debug then
        print(formatConsole('DEBUG', message))
    end
end

OxSecure.Console = {
    info = logInfo,
    warn = logWarn,
    error = logError,
    debug = logDebug
}

local function addStartupError(message)
    table.insert(OxSecure.State.errors, message)
    logError(message)
end

-- =============================================================
-- إيقاف آمن
-- =============================================================
local function fatal(message)
    addStartupError(message)

    if not OxSecure.BuildMode then
        logError('Stopping resource because BuildMode is disabled.')
        StopResource(OxSecure.ResourceName)
    else
        logWarn('BuildMode is enabled. Resource will not stop, but this must be fixed before production.')
    end
end

-- =============================================================
-- إعادة تهيئة حالة التشغيل
-- =============================================================
local function resetRuntimeState()
    OxSecure.State.loadedFiles = {}
    OxSecure.State.missingFiles = {}
    OxSecure.State.errors = {}
    OxSecure.State.booting = false
    OxSecure.State.booted = false
    OxSecure.State.dbReady = false
end

-- =============================================================
-- مشاركة الوحدات بين الملفات
--
-- تدعم هذه الدالة المفاتيح البسيطة:
--   OxSecure.Export('Logger', loggerTable)
--
-- وتدعم أيضًا المفاتيح المتداخلة:
--   OxSecure.Export('Logger.RedactSecrets', redactFunction)
--
-- مهم:
-- إذا كان جزء من المسار موجودًا لكنه ليس جدولًا،
-- فلن يتم استبداله بجدول فارغ، وسيتم تسجيل تحذير.
--
-- التزام الوحدات:
-- لأن بيئة التحميل معزولة نسبيًا، يجب على كل ملف
-- ألا يعتمد على إنشاء متغيرات عامة جديدة، بل يجب أن
-- يستخدم OxSecure.Export أو يضيف مباشرة إلى OxSecure.
-- =============================================================
function OxSecure.Export(name, value)
    if type(name) ~= 'string' or name == '' then
        return false
    end

    local parts = {}

    for part in string.gmatch(name, '[^.]+') do
        parts[#parts + 1] = part
    end

    if #parts == 0 then
        return false
    end

    if #parts == 1 then
        OxSecure[parts[1]] = value
        return true
    end

    local target = OxSecure

    for i = 1, #parts - 1 do
        local key = parts[i]
        local existing = target[key]

        if existing == nil then
            target[key] = {}
        elseif type(existing) ~= 'table' then
            logWarn(('OxSecure.Export: cannot create path "%s" because "%s" is not a table.'):format(name, key))
            return false
        end

        target = target[key]
    end

    target[parts[#parts]] = value
    return true
end

-- =============================================================
-- تحميل ملف Lua واحد
-- =============================================================
local function loadLuaFile(path, required)
    local content = LoadResourceFile(OxSecure.ResourceName, path)

    if not content then
        if required then
            table.insert(OxSecure.State.missingFiles, path)

            if OxSecure.BuildMode then
                logWarn(('Missing required file (BuildMode): %s'):format(path))
                return false
            else
                fatal(('Missing required file: %s'):format(path))
                return false
            end
        end

        logDebug(('Optional file not found: %s'):format(path))
        return false
    end

    -- بيئة معزولة نسبيًا:
    -- تسمح بالوصول إلى Config وOxSecure ودوال FiveM العامة،
    -- لكنها تمنع تلويث المتغيرات العامة الجديدة.
    --
    -- مهم:
    -- إذا أراد ملف مشاركة شيء مع ملفات أخرى، يجب أن يستخدم:
    -- OxSecure.Export('Name', value)
    -- أو يضيفه مباشرة إلى OxSecure.
    local moduleEnvironment = setmetatable({
        Config = Config,
        OxSecure = OxSecure
    }, {
        __index = _G
    })

    local chunk, compileError = load(content, '@' .. path, 't', moduleEnvironment)

    if not chunk then
        local message = ('Compile error in file %s: %s'):format(path, tostring(compileError))
        addStartupError(message)

        if required and not OxSecure.BuildMode then
            fatal(message)
        end

        return false
    end

    local ok, runError = pcall(chunk)

    if not ok then
        local message = ('Runtime error in file %s: %s'):format(path, tostring(runError))
        addStartupError(message)

        if required and not OxSecure.BuildMode then
            fatal(message)
        end

        return false
    end

    table.insert(OxSecure.State.loadedFiles, path)
    logDebug(('Loaded file: %s'):format(path))
    return true
end

-- =============================================================
-- ترتيب ملفات السيرفر
-- =============================================================
local SERVER_FILES = {
    -- الأساسيات
    { path = 'server/core/state.lua', required = true },
    { path = 'server/core/utils.lua', required = true },

    -- الأمان والتحقق
    { path = 'server/core/security.lua', required = true },
    { path = 'server/core/validator.lua', required = true },
    { path = 'server/core/rate_limiter.lua', required = true },

    -- الترجمة والتسجيل
    { path = 'server/core/localization.lua', required = true },
    { path = 'server/core/logger.lua', required = true },

    -- قاعدة البيانات
    { path = 'server/core/database.lua', required = true },
    { path = 'server/database/queries.lua', required = true },
    { path = 'server/database/migrations.lua', required = true },

    -- الصلاحيات واللاعبون
    { path = 'server/core/permissions.lua', required = true },
    { path = 'server/modules/discord.lua', required = true },
    { path = 'server/core/players.lua', required = true },
    { path = 'server/core/sessions.lua', required = true },

    -- الأنظمة والرسائل
    { path = 'server/core/systems.lua', required = true },
    { path = 'server/core/keywords.lua', required = true },
    { path = 'server/core/queue.lua', required = true },
    { path = 'server/core/notifications.lua', required = true },
    { path = 'server/core/errors.lua', required = true },
    { path = 'server/core/logs.lua', required = true },

    -- وحدات مساعدة
    { path = 'server/modules/audit.lua', required = true },
    { path = 'server/modules/storage.lua', required = true },
    { path = 'server/modules/error_handler.lua', required = true },

    -- الأوامر والأحداث والتصدير
    { path = 'server/core/commands.lua', required = true },
    { path = 'server/core/events.lua', required = true },
    { path = 'server/core/exports.lua', required = true },
    { path = 'server/core/api.lua', required = true },

    -- الفريموركات
    { path = 'server/adapters/standalone.lua', required = false },
    { path = 'server/adapters/esx.lua', required = false },
    { path = 'server/adapters/qbcore.lua', required = false }
}

local function loadServerFiles()
    logInfo('Loading server files...')

    for _, file in ipairs(SERVER_FILES) do
        loadLuaFile(file.path, file.required ~= false)
    end

    logInfo(('Loaded %d files.'):format(#OxSecure.State.loadedFiles))

    if #OxSecure.State.missingFiles > 0 then
        logWarn(('Missing files count: %d'):format(#OxSecure.State.missingFiles))
    end

    if #OxSecure.State.errors > 0 then
        logWarn(('Startup errors count: %d'):format(#OxSecure.State.errors))
    end
end

-- =============================================================
-- فحوصات الإقلاع
-- =============================================================
local function performStartupChecks()
    local checks = Config.Security and Config.Security.StartupChecks or {}

    if checks.VerifyLoggerHook then
        local hasLoggerHook = OxSecure.Logger and type(OxSecure.Logger.RedactSecrets) == 'function'

        if not hasLoggerHook then
            local message = 'Logger secret redaction hook is missing.'

            if checks.FailOnMissingLoggerHook and not OxSecure.BuildMode then
                fatal(message)
            else
                logWarn(message)
            end
        end
    end

    if checks.VerifyActionPermissionHandler then
        local hasActionHandler = OxSecure.NUI and type(OxSecure.NUI.CheckActionPermission) == 'function'

        if not hasActionHandler then
            local message = 'NUI action permission handler is missing.'

            if checks.FailOnMissingActionPermissionHandler and not OxSecure.BuildMode then
                fatal(message)
            else
                logWarn(message)
            end
        end
    end
end

-- =============================================================
-- بدء النظام
-- =============================================================
function OxSecure.Start(options)
    options = options or {}

    if OxSecure.State.booted or OxSecure.State.booting then
        return
    end

    resetRuntimeState()

    OxSecure.State.booting = true
    OxSecure.State.dbReady = options.dbReady == true

    logInfo(('Starting ox_lib_secure v%s'):format(OxSecure.Version))

    loadServerFiles()
    performStartupChecks()

    if OxSecure.Bootstrap and type(OxSecure.Bootstrap.Start) == 'function' then
        local ok, err = pcall(OxSecure.Bootstrap.Start)

        if not ok then
            addStartupError(('Bootstrap.Start failed: %s'):format(tostring(err)))
        end
    else
        if OxSecure.BuildMode then
            logWarn('Bootstrap module is not loaded yet. This is expected during file-by-file development.')
        else
            fatal('Bootstrap module is missing.')
        end
    end

    OxSecure.State.booting = false
    OxSecure.State.booted = true

    logInfo('ox_lib_secure start sequence completed.')
end

-- =============================================================
-- اختبار فعلي بسيط لقاعدة البيانات
--
-- نحاول دعم أكثر من طريقة استدعاء لـ oxmysql:
--   MySQL.query('SELECT 1', callback)
--   MySQL.query('SELECT 1', {}, callback)
--   MySQL.scalar('SELECT 1', callback)
--   MySQL.scalar('SELECT 1', {}, callback)
-- =============================================================
local function runMySQLTestQuery(callback)
    local invoked = false

    local function tryCall(fn)
        if invoked then
            return true
        end

        local ok = pcall(fn)

        if ok then
            invoked = true
        end

        return ok
    end

    if type(MySQL.query) == 'function' then
        if tryCall(function()
            MySQL.query('SELECT 1', function(result)
                callback(result ~= nil)
            end)
        end) then
            return
        end

        if tryCall(function()
            MySQL.query('SELECT 1', {}, function(result)
                callback(result ~= nil)
            end)
        end) then
            return
        end
    end

    if type(MySQL.scalar) == 'function' then
        if tryCall(function()
            MySQL.scalar('SELECT 1', function(result)
                callback(result ~= nil)
            end)
        end) then
            return
        end

        if tryCall(function()
            MySQL.scalar('SELECT 1', {}, function(result)
                callback(result ~= nil)
            end)
        end) then
            return
        end
    end

    callback(false)
end

local function verifyMySQLConnection(callback)
    local finished = false

    local function finish(success)
        if finished then
            return
        end

        finished = true
        callback(success)
    end

    local queryTimeout = Config.Database and Config.Database.QueryTestTimeoutMs or 5000
    local elapsed = 0

    runMySQLTestQuery(function(success)
        finish(success)
    end)

    CreateThread(function()
        while not finished and elapsed < queryTimeout do
            Wait(100)
            elapsed = elapsed + 100
        end

        if not finished then
            finish(false)
        end
    end)
end

-- =============================================================
-- حالة فحص قاعدة البيانات
-- =============================================================
local mysqlCheckDone = false
local mysqlCheckResult = false
local mysqlWaiting = false
local mysqlCallbacks = {}
local mysqlCheckGeneration = 0

local function resetMySQLCheckState(force)
    if mysqlWaiting and not force then
        return false
    end

    mysqlCheckGeneration = mysqlCheckGeneration + 1
    mysqlCheckDone = false
    mysqlCheckResult = false
    mysqlWaiting = false
    mysqlCallbacks = {}

    return true
end

OxSecure.ResetMySQLCheck = function(force)
    return resetMySQLCheckState(force == true)
end

local function notifyMySQLWaiters(result, generation)
    if generation ~= nil and generation ~= mysqlCheckGeneration then
        return
    end

    if mysqlCheckDone then
        return
    end

    mysqlCheckDone = true
    mysqlCheckResult = result
    mysqlWaiting = false

    for _, callback in ipairs(mysqlCallbacks) do
        local ok, err = pcall(callback, result)

        if not ok then
            logError(('MySQL wait callback error: %s'):format(tostring(err)))
        end
    end

    mysqlCallbacks = {}
end

-- =============================================================
-- انتظار قاعدة البيانات
-- =============================================================
local function hasMySQLApi()
    return MySQL ~= nil and (
        type(MySQL.ready) == 'function'
        or type(MySQL.query) == 'function'
        or type(MySQL.scalar) == 'function'
    )
end

local function waitForMySQL(callback)
    if type(callback) == 'function' then
        if mysqlCheckDone then
            callback(mysqlCheckResult)
            return
        end

        table.insert(mysqlCallbacks, callback)
    end

    if mysqlWaiting then
        return
    end

    mysqlWaiting = true

    local generation = mysqlCheckGeneration

    CreateThread(function()
        local elapsed = 0
        local timeout = Config.Database and Config.Database.ReadyTimeoutMs or 30000

        while not hasMySQLApi() and elapsed < timeout do
            Wait(100)
            elapsed = elapsed + 100

            if generation ~= mysqlCheckGeneration then
                return
            end
        end

        if generation ~= mysqlCheckGeneration then
            return
        end

        if not hasMySQLApi() then
            notifyMySQLWaiters(false, generation)
            return
        end

        if type(MySQL.ready) == 'function' then
            MySQL.ready(function()
                if generation ~= mysqlCheckGeneration then
                    return
                end

                verifyMySQLConnection(function(isQueryWorking)
                    notifyMySQLWaiters(isQueryWorking, generation)
                end)
            end)
        else
            verifyMySQLConnection(function(isQueryWorking)
                notifyMySQLWaiters(isQueryWorking, generation)
            end)
        end
    end)
end

-- =============================================================
-- إعادة فحص قاعدة البيانات
-- =============================================================
function OxSecure.RecheckDatabase(callback)
    resetMySQLCheckState(true)

    waitForMySQL(function(isReady)
        if type(callback) == 'function' then
            callback(isReady)
        end
    end)
end

-- =============================================================
-- التشغيل الفعلي
-- =============================================================
CreateThread(function()
    Wait(100)

    local useDatabase = Config.Database and Config.Database.UseDatabase ~= false

    if useDatabase then
        waitForMySQL(function(isReady)
            if not isReady then
                logWarn('MySQL/oxmysql was not detected or failed the connection test. Continuing in degraded mode.')
            else
                logInfo('Database is ready and connection test passed.')
            end

            OxSecure.Start({
                dbReady = isReady
            })
        end)
    else
        OxSecure.Start({
            dbReady = false
        })
    end
end)

-- =============================================================
-- إيقاف المورد
-- =============================================================
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= OxSecure.ResourceName then
        return
    end

    OxSecure.State.booted = false
    OxSecure.State.booting = false
    OxSecure.State.dbReady = false

    resetMySQLCheckState(true)

    logInfo('ox_lib_secure stopped.')
end)
