-- =============================================================
-- ox_lib_secure
-- File: server/core/permissions.lua
-- Description:
--   وحدة الصلاحيات لنظام ox_lib_secure.
--   تدير الأدوار والصلاحيات والتحكم في الوصول.
--
-- Notes:
--   - مواءمة 100% مع config/main.lua النهائي.
--   - تعتمد على الذاكرة للأداء العالي.
--   - قاعدة البيانات للحفظ الدائم فقط (غير متزامن).
--   - إصلاح: تحميل كسول للأدوار، تعيين المالكين في الذاكرة فقط.
-- =============================================================

Config = Config or {}
OxSecure = OxSecure or {}
OxSecure.Permissions = OxSecure.Permissions or {}

local Permissions = OxSecure.Permissions
local Logger = OxSecure.Logger or {}
local Database = OxSecure.Database or {}
local Security = OxSecure.Security or {}
local Audit = OxSecure.Audit or {}

-- =============================================================
-- قراءة الإعدادات من الكونفق
-- =============================================================
local permConfig = Config.Permissions or {}

local ENABLED = permConfig.Enabled ~= false
local OWNERS = permConfig.Owners or {}
local DEFAULT_ROLE_FOR_OWNERS = permConfig.DefaultRoleForOwners or 'super_admin'
local ROLES = permConfig.Roles or {}
local PERMISSIONS_LIST = permConfig.PermissionsList or {}
local SCOPES = permConfig.Scopes or {}
local DEFAULT_SYSTEM_SCOPES = permConfig.DefaultSystemScopes or {}
local COMMAND_PERMISSIONS = permConfig.CommandPermissions or {}
local PANEL_PERMISSIONS = permConfig.PanelPermissions or {}
local CACHE_CONFIG = permConfig.Cache or {}
local AUDIT_CONFIG = permConfig.Audit or {}
local DENY_CONFIG = permConfig.Deny or {}

local CACHE_ENABLED = CACHE_CONFIG.Enabled ~= false
local CACHE_TTL_SECONDS = CACHE_CONFIG.TTLSeconds or 300
local CACHE_MAX_ENTRIES = CACHE_CONFIG.MaxEntries or 500
local CACHE_CLEANUP_SECONDS = CACHE_CONFIG.CleanupIntervalSeconds or 120

local AUDIT_LOG_CHECKS = AUDIT_CONFIG.LogPermissionChecks == true
local AUDIT_LOG_DENIED = AUDIT_CONFIG.LogDeniedAccess ~= false
local AUDIT_LOG_ROLE_CHANGES = AUDIT_CONFIG.LogRoleChanges ~= false

local DENY_MESSAGE = DENY_CONFIG.Message or 'ليس لديك صلاحية لتنفيذ هذا الإجراء.'
local DENY_LOG = DENY_CONFIG.LogDenied ~= false
local DENY_NOTIFY_ADMIN = DENY_CONFIG.NotifyAdmin == true

-- =============================================================
-- الحالة الداخلية
-- =============================================================
local playerRoles = {}
local permissionCache = {}
local systemScopes = {}
local isInitialized = false

-- =============================================================
-- أدوات مساعدة داخلية
-- =============================================================
local function logPermission(message, level)
    level = level or 'info'
    if Logger and Logger.Log then
        Logger.Log(level, message, { category = 'permissions' })
    else
        print(('[ox_lib_secure] [PERMISSIONS] %s'):format(message))
    end
end

local function getCurrentTimestamp()
    return os.time()
end

local function isInList(value, list)
    if not value or not list then
        return false
    end
    for _, item in ipairs(list) do
        if item == value then
            return true
        end
    end
    return false
end

local function tableSize(t)
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    return count
end

-- =============================================================
-- الحصول على اسم جدول أدوار اللاعبين
-- =============================================================
local function getPlayerRolesTableName()
    if Database and Database.GetTableName then
        local ok, name = pcall(Database.GetTableName, 'player_roles')
        if ok and name then
            return name
        end
    end
    return 'oxsecure_player_roles'
end

-- =============================================================
-- تهيئة وحدة الصلاحيات
-- إصلاح: إزالة التحميل الكمي، الاعتماد على التحميل الكسول
-- =============================================================
function Permissions.Initialize()
    if isInitialized then
        return true
    end

    if not ENABLED then
        logPermission('Permissions system is disabled.')
        return true
    end

    logPermission('Initializing permissions system...')
    logPermission(('Loaded %d roles, %d permissions'):format(
        tableSize(ROLES),
        tableSize(PERMISSIONS_LIST)
    ))

    -- تنظيف الكاش الدوري
    if CACHE_ENABLED then
        CreateThread(function()
            while true do
                Wait(CACHE_CLEANUP_SECONDS * 1000)
                Permissions.CleanupCache()
            end
        end)
    end

    -- ملاحظة: لا يتم تحميل الأدوار عند البدء.
    -- يتم تحميلها كسليًا عند أول طلب لكل لاعب.

    isInitialized = true
    logPermission('Permissions system initialized successfully (lazy loading enabled).')
    return true
end

-- =============================================================
-- التحقق من حالة التهيئة
-- =============================================================
function Permissions.IsInitialized()
    return isInitialized
end

-- =============================================================
-- تحميل دور لاعب واحد من قاعدة البيانات (تحميل كسول)
-- إصلاح: جلب دور لاعب واحد فقط عند الحاجة
-- =============================================================
function Permissions.LoadPlayerRoleFromDB(source, callback)
    if not source then
        if callback then callback(nil) end
        return
    end

    if not Database or not Database.Execute then
        if callback then callback(nil) end
        return
    end

    local tableName = getPlayerRolesTableName()

    Database.Execute(
        ('SELECT role FROM %s WHERE source = ? LIMIT 1'):format(tableName),
        { source },
        function(results)
            local role = nil

            if results and #results > 0 then
                local row = results[1]
                if row and row.role and ROLES[row.role] then
                    role = row.role
                    playerRoles[source] = role
                end
            end

            if callback then
                callback(role)
            end
        end
    )
end

-- =============================================================
-- الحصول على دور لاعب
-- إصلاح: المالكين يُعيَّنون في الذاكرة فقط بدون حفظ قاعدة بيانات
-- =============================================================
function Permissions.GetPlayerRole(source)
    if not source then
        return nil
    end

    -- التحقق من الذاكرة أولاً
    if playerRoles[source] then
        return playerRoles[source]
    end

    -- التحقق من الكاش
    if CACHE_ENABLED then
        local cached = Permissions.CacheGet('role:' .. tostring(source))
        if cached then
            return cached
        end
    end

    -- التحقق من المالكين
    -- إصلاح: تعيين في الذاكرة فقط بدون حفظ في قاعدة البيانات
    local identifiers = {}
    if Security and Security.GetIdentifiers then
        identifiers = Security.GetIdentifiers(source)
    end

    for _, owner in ipairs(OWNERS) do
        for _, id in ipairs(identifiers) do
            local fullId = id.type .. ':' .. id.value
            if fullId == owner or id.value == owner then
                -- تعيين في الذاكرة فقط (بدون حفظ قاعدة بيانات)
                playerRoles[source] = DEFAULT_ROLE_FOR_OWNERS

                if CACHE_ENABLED then
                    Permissions.CacheSet('role:' .. tostring(source), DEFAULT_ROLE_FOR_OWNERS)
                end

                logPermission(('Owner detected: source %d assigned role %s (memory only)'):format(
                    source, DEFAULT_ROLE_FOR_OWNERS
                ))

                return DEFAULT_ROLE_FOR_OWNERS
            end
        end
    end

    return nil
end

-- =============================================================
-- الحصول على دور لاعب مع تحميل كسول من قاعدة البيانات
-- =============================================================
function Permissions.GetPlayerRoleAsync(source, callback)
    if not source then
        if callback then callback(nil) end
        return
    end

    -- التحقق من الذاكرة أولاً
    local role = Permissions.GetPlayerRole(source)

    if role then
        if callback then callback(role) end
        return
    end

    -- تحميل من قاعدة البيانات
    Permissions.LoadPlayerRoleFromDB(source, function(loadedRole)
        if callback then
            callback(loadedRole)
        end
    end)
end

-- =============================================================
-- تعيين دور لاعب
-- ملاحظة: يتطلب القيد الفريد على عمود source في الجدول
-- =============================================================
function Permissions.SetPlayerRole(source, roleName, skipDbSave)
    if not source or not roleName then
        return false
    end

    -- التحقق من وجود الدور
    if not ROLES[roleName] then
        logPermission(('Attempt to set non-existent role: %s'):format(roleName), 'warn')
        return false
    end

    local oldRole = playerRoles[source]
    playerRoles[source] = roleName

    -- مسح جميع مفاتيح الكاش المتعلقة بالمصدر
    if CACHE_ENABLED then
        Permissions.CacheDelete('role:' .. tostring(source))

        local keysToDelete = {}
        for key in pairs(permissionCache) do
            if key:find('^perms:' .. tostring(source) .. ':') then
                keysToDelete[#keysToDelete + 1] = key
            end
        end

        for _, key in ipairs(keysToDelete) do
            permissionCache[key] = nil
        end
    end

    -- حفظ في قاعدة البيانات (غير متزامن)
    -- ملاحظة: يتطلب القيد الفريد على عمود source
    if not skipDbSave and Database and Database.Execute then
        local tableName = getPlayerRolesTableName()

        Database.Execute(
            ('INSERT INTO %s (source, role, updated_at) VALUES (?, ?, NOW()) ON DUPLICATE KEY UPDATE role = ?, updated_at = NOW()'):format(tableName),
            { source, roleName, roleName }
        )
    end

    -- تسجيل التغيير في التدقيق
    if AUDIT_LOG_ROLE_CHANGES and Audit and Audit.Record then
        Audit.Record('role_changed', 'system', 'player', source, {
            oldRole = oldRole,
            newRole = roleName
        })
    end

    logPermission(('Role set for source %d: %s -> %s'):format(source, tostring(oldRole), roleName))
    return true
end

-- =============================================================
-- إزالة دور لاعب
-- =============================================================
function Permissions.RemovePlayerRole(source)
    if not source then
        return false
    end

    local oldRole = playerRoles[source]
    playerRoles[source] = nil

    -- مسح الكاش
    if CACHE_ENABLED then
        Permissions.CacheDelete('role:' .. tostring(source))

        local keysToDelete = {}
        for key in pairs(permissionCache) do
            if key:find('^perms:' .. tostring(source) .. ':') then
                keysToDelete[#keysToDelete + 1] = key
            end
        end

        for _, key in ipairs(keysToDelete) do
            permissionCache[key] = nil
        end
    end

    -- حذف من قاعدة البيانات
    if Database and Database.Execute then
        local tableName = getPlayerRolesTableName()

        Database.Execute(
            ('DELETE FROM %s WHERE source = ?'):format(tableName),
            { source }
        )
    end

    if AUDIT_LOG_ROLE_CHANGES and Audit and Audit.Record then
        Audit.Record('role_removed', 'system', 'player', source, {
            oldRole = oldRole
        })
    end

    return true
end

-- =============================================================
-- التحقق من الصلاحيات
-- =============================================================
function Permissions.HasPermission(source, permission)
    if not ENABLED then
        return true
    end

    if not source or not permission then
        return false
    end

    -- التحقق من الكاش
    if CACHE_ENABLED then
        local cacheKey = ('perms:%s:%s'):format(tostring(source), permission)
        local cached = Permissions.CacheGet(cacheKey)
        if cached ~= nil then
            return cached
        end
    end

    -- الحصول على الدور
    local role = Permissions.GetPlayerRole(source)

    if not role then
        return false
    end

    -- التحقق من صلاحيات الدور
    local roleData = ROLES[role]

    if not roleData then
        return false
    end

    local hasPermission = isInList(permission, roleData.permissions)

    -- تسجيل في التدقيق
    if AUDIT_LOG_CHECKS and Audit and Audit.Record then
        Audit.Record('permission_check', 'system', 'player', source, {
            permission = permission,
            role = role,
            result = hasPermission
        })
    end

    -- تسجيل الرفض
    if not hasPermission and AUDIT_LOG_DENIED then
        logPermission(('Permission denied: source=%d, permission=%s, role=%s'):format(
            source, permission, tostring(role)
        ), 'warn')

        if Audit and Audit.Record then
            Audit.Record('permission_denied', 'system', 'player', source, {
                permission = permission,
                role = role
            })
        end
    end

    -- حفظ في الكاش
    if CACHE_ENABLED then
        local cacheKey = ('perms:%s:%s'):format(tostring(source), permission)
        Permissions.CacheSet(cacheKey, hasPermission)
    end

    return hasPermission
end

function Permissions.HasAnyPermission(source, permissionList)
    if not ENABLED then
        return true
    end

    if not source or not permissionList then
        return false
    end

    for _, permission in ipairs(permissionList) do
        if Permissions.HasPermission(source, permission) then
            return true
        end
    end

    return false
end

function Permissions.HasAllPermissions(source, permissionList)
    if not ENABLED then
        return true
    end

    if not source or not permissionList then
        return false
    end

    for _, permission in ipairs(permissionList) do
        if not Permissions.HasPermission(source, permission) then
            return false
        end
    end

    return true
end

-- =============================================================
-- التحقق من صلاحيات الأوامر
-- =============================================================
function Permissions.CheckCommand(source, commandName)
    if not ENABLED then
        return true
    end

    if not source or not commandName then
        return false
    end

    local requiredPermissions = COMMAND_PERMISSIONS[commandName]

    if not requiredPermissions then
        return true
    end

    return Permissions.HasAnyPermission(source, requiredPermissions)
end

-- =============================================================
-- التحقق من صلاحيات اللوحة
-- =============================================================
function Permissions.CheckPanel(source, panelKey)
    if not ENABLED then
        return true
    end

    if not source or not panelKey then
        return false
    end

    local requiredPermission = PANEL_PERMISSIONS[panelKey]

    if not requiredPermission then
        return false
    end

    return Permissions.HasPermission(source, requiredPermission)
end

-- =============================================================
-- التحقق من نطاقات الأنظمة
-- =============================================================
function Permissions.RegisterSystemScopes(systemId, scopes)
    if not systemId or not scopes then
        return false
    end

    systemScopes[systemId] = scopes
    return true
end

function Permissions.CheckScope(systemId, scope)
    if not ENABLED then
        return true
    end

    if not systemId or not scope then
        return false
    end

    -- التحقق من النطاقات الافتراضية
    if isInList(scope, DEFAULT_SYSTEM_SCOPES) then
        return true
    end

    -- التحقق من النطاقات المسجلة في الذاكرة
    local scopes = systemScopes[systemId]

    if scopes then
        return isInList(scope, scopes)
    end

    return false
end

-- =============================================================
-- الحصول على جميع صلاحيات لاعب
-- =============================================================
function Permissions.GetPlayerPermissions(source)
    if not source then
        return {}
    end

    local role = Permissions.GetPlayerRole(source)

    if not role then
        return {}
    end

    local roleData = ROLES[role]

    if not roleData then
        return {}
    end

    return roleData.permissions or {}
end

-- =============================================================
-- الحصول على معلومات دور
-- =============================================================
function Permissions.GetRoleInfo(roleName)
    if not roleName then
        return nil
    end

    local roleData = ROLES[roleName]

    if not roleData then
        return nil
    end

    return {
        name = roleData.name,
        priority = roleData.priority,
        isProtected = roleData.isProtected,
        permissions = roleData.permissions,
        permissionCount = #(roleData.permissions or {})
    }
end

-- =============================================================
-- الحصول على جميع الأدوار
-- =============================================================
function Permissions.GetAllRoles()
    local result = {}

    for roleName, roleData in pairs(ROLES) do
        result[roleName] = {
            name = roleData.name,
            priority = roleData.priority,
            isProtected = roleData.isProtected,
            permissionCount = #(roleData.permissions or {})
        }
    end

    return result
end

-- =============================================================
-- الحصول على جميع الصلاحيات المتاحة
-- =============================================================
function Permissions.GetAllPermissions()
    return PERMISSIONS_LIST
end

-- =============================================================
-- الحصول على جميع النطاقات المتاحة
-- =============================================================
function Permissions.GetAllScopes()
    return SCOPES
end

-- =============================================================
-- رفض الوصول
-- =============================================================
function Permissions.Deny(source, context)
    local message = DENY_MESSAGE

    if context then
        message = message .. ' (' .. context .. ')'
    end

    if DENY_LOG then
        logPermission(('Access denied: source=%d, context=%s'):format(
            source or 0, tostring(context)
        ), 'warn')
    end

    return false, message
end

-- =============================================================
-- الكاش
-- =============================================================
function Permissions.CacheSet(key, value, ttlSeconds)
    if not CACHE_ENABLED then
        return false
    end

    ttlSeconds = ttlSeconds or CACHE_TTL_SECONDS

    local count = 0
    for _ in pairs(permissionCache) do
        count = count + 1
    end

    if count >= CACHE_MAX_ENTRIES then
        local oldestKey = nil
        local oldestTime = math.huge

        for k, v in pairs(permissionCache) do
            if v.createdAt < oldestTime then
                oldestTime = v.createdAt
                oldestKey = k
            end
        end

        if oldestKey then
            permissionCache[oldestKey] = nil
        end
    end

    permissionCache[key] = {
        value = value,
        createdAt = getCurrentTimestamp(),
        expiresAt = getCurrentTimestamp() + ttlSeconds
    }

    return true
end

function Permissions.CacheGet(key)
    if not CACHE_ENABLED then
        return nil
    end

    local entry = permissionCache[key]
    if not entry then
        return nil
    end

    if entry.expiresAt < getCurrentTimestamp() then
        permissionCache[key] = nil
        return nil
    end

    return entry.value
end

function Permissions.CacheDelete(key)
    if permissionCache[key] then
        permissionCache[key] = nil
        return true
    end
    return false
end

function Permissions.CleanupCache()
    local now = getCurrentTimestamp()
    local cleaned = 0

    for key, entry in pairs(permissionCache) do
        if entry.expiresAt < now then
            permissionCache[key] = nil
            cleaned = cleaned + 1
        end
    end

    if cleaned > 0 then
        logPermission(('Cache cleanup: removed %d expired entries'):format(cleaned))
    end
end

-- =============================================================
-- إحصائيات
-- =============================================================
function Permissions.GetStats()
    return {
        roles = tableSize(ROLES),
        permissions = tableSize(PERMISSIONS_LIST),
        scopes = tableSize(SCOPES),
        cacheEntries = tableSize(permissionCache),
        playersWithRoles = tableSize(playerRoles),
        isEnabled = ENABLED,
        isInitialized = isInitialized
    }
end

-- =============================================================
-- تنظيف عند خروج اللاعب
-- =============================================================
AddEventHandler('playerDropped', function(reason)
    local src = source

    if not src then
        return
    end

    if playerRoles[src] then
        playerRoles[src] = nil
    end

    if CACHE_ENABLED then
        Permissions.CacheDelete('role:' .. tostring(src))

        local keysToDelete = {}
        for key in pairs(permissionCache) do
            if key:find('^perms:' .. tostring(src) .. ':') then
                keysToDelete[#keysToDelete + 1] = key
            end
        end

        for _, key in ipairs(keysToDelete) do
            permissionCache[key] = nil
        end
    end
end)

-- =============================================================
-- تهيئة عند التحميل
-- =============================================================
Permissions.Initialize()

-- =============================================================
-- رسالة تحميل ناجحة
-- =============================================================
if Logger and Logger.Debug then
    Logger.Debug('server/core/permissions.lua loaded')
else
    print('[ox_lib_secure] server/core/permissions.lua loaded')
end
