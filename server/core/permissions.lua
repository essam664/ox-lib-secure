-- =============================================================
-- ox_lib_secure
-- File: server/core/permissions.lua
-- Description:
--   طبقة إدارة الصلاحيات (RBAC) لنظام ox_lib_secure.
--
-- Notes:
--   - يعتمد النظام على الأدوار (Roles) والصلاحيات (Permissions).
--   - يتم جلب الصلاحيات من قاعدة البيانات وتخزينها في الكاش.
--   - يدعم التكامل مع معرفات Discord و FiveM.
--   - يوفر واجهة موحدة للتحقق من الصلاحيات.
--   - تم إضافة حماية من التحميل المتكرر للصلاحيات.
-- =============================================================

Config = Config or {}
OxSecure = OxSecure or {}
OxSecure.Permissions = OxSecure.Permissions or {}

local Permissions = OxSecure.Permissions
local Database = OxSecure.Database or {}
local Validator = OxSecure.Validator or {}
local Logger = OxSecure.Logger or {}
local StateManager = OxSecure.StateManager or {}

-- =============================================================
-- أدوات مساعدة داخلية
-- =============================================================
local function getPermissionsCache()
    local state = StateManager.Get and StateManager.Get() or nil
    return state and state.permissions or nil
end

local function logPermissionEvent(message, options)
    if Logger.PermissionEvent then
        Logger.PermissionEvent(message, options)
    elseif Logger.Debug then
        Logger.Debug(message, options)
    end
end

-- إصلاح 2: جدول لتتبع اللاعبين الذين يتم تحميل صلاحياتهم حاليًا
local loadingPlayers = {}

-- إصلاح 5: استخراج معرف Discord من قائمة المعرفات
local function extractDiscordId(identifiers)
    if type(identifiers) ~= 'table' then
        return nil
    end

    for _, id in ipairs(identifiers) do
        if id.type == 'discord' then
            return id.value
        end
    end

    return nil
end

-- =============================================================
-- إصلاح 1: استخدام Database.GetTableName بدلاً من بناء
-- اسم الجدول يدويًا.
-- =============================================================

-- =============================================================
-- جلب بيانات المشرف من قاعدة البيانات
-- =============================================================
local function fetchAdminByDiscordId(discordId, callback)
    if not Database.IsReady() then
        callback(nil, 'Database is not ready')
        return
    end

    local query = ('SELECT * FROM %s WHERE discord_id = ? AND is_active = 1'):format(Database.GetTableName('admins'))

    Database.Single(query, { discordId }, function(result, err)
        if err then
            callback(nil, err)
            return
        end
        callback(result, nil)
    end)
end

-- =============================================================
-- جلب أدوار المشرف من قاعدة البيانات
-- =============================================================
local function fetchAdminRoles(adminId, callback)
    if not Database.IsReady() then
        callback({}, 'Database is not ready')
        return
    end

    local query = ('SELECT role_code FROM %s WHERE admin_id = ?'):format(Database.GetTableName('admin_roles'))

    Database.Execute(query, { adminId }, function(results, err)
        if err then
            callback({}, err)
            return
        end

        local roles = {}
        if type(results) == 'table' then
            for _, row in ipairs(results) do
                roles[#roles + 1] = row.role_code
            end
        end

        callback(roles, nil)
    end)
end

-- =============================================================
-- جلب صلاحيات الدور من قاعدة البيانات
-- =============================================================
local function fetchRolePermissions(roleCode, callback)
    if not Database.IsReady() then
        callback({}, 'Database is not ready')
        return
    end

    local query = ('SELECT permission_code FROM %s WHERE role_code = ? AND granted = 1'):format(Database.GetTableName('role_permissions'))

    Database.Execute(query, { roleCode }, function(results, err)
        if err then
            callback({}, err)
            return
        end

        local permissions = {}
        if type(results) == 'table' then
            for _, row in ipairs(results) do
                permissions[#permissions + 1] = row.permission_code
            end
        end

        callback(permissions, nil)
    end)
end

-- =============================================================
-- حفظ الصلاحيات في الكاش
-- =============================================================
local function saveToCache(discordId, data)
    local cache = getPermissionsCache()

    if cache and cache.resolvedPermissions then
        cache.resolvedPermissions[discordId] = data
    end
end

-- =============================================================
-- تحميل صلاحيات اللاعب وتحديث الكاش
--
-- إصلاح 2: إضافة حماية من التحميل المتكرر.
-- إصلاح 3: تسجيل خطأ واضح عند فشل جلب الأدوار.
-- =============================================================
function Permissions.LoadPlayerPermissions(source, callback)
    local serverId = tonumber(source)

    if not serverId or serverId <= 0 then
        if callback then callback(false, { code = 'ERR_INVALID_SOURCE' }) end
        return
    end

    -- إصلاح 2: منع التحميل المتكرر
    if loadingPlayers[serverId] then
        if callback then callback(false, { code = 'ERR_ALREADY_LOADING' }) end
        return
    end

    loadingPlayers[serverId] = true

    local function cleanup()
        loadingPlayers[serverId] = nil
    end

    local okPlayer, player = Validator.ValidatePlayerSource(serverId, {
        requireOnline = true,
        requireIdentifiers = true
    })

    if not okPlayer then
        cleanup()
        if callback then callback(false, player) end
        return
    end

    local discordId = extractDiscordId(player.identifiers)

    if not discordId then
        -- اللاعب ليس لديه Discord مرتبط، لا توجد صلاحيات مشرف
        cleanup()
        if callback then callback(true, { isAdmin = false, roles = {}, permissions = {} }) end
        return
    end

    fetchAdminByDiscordId(discordId, function(admin, err)
        if err then
            -- إصلاح 3: تسجيل الخطأ بدلاً من التجاهل
            if Logger.Error then
                Logger.Error(('Failed to fetch admin by discord ID: %s'):format(tostring(err)), {
                    category = 'permission',
                    serverPlayerId = serverId
                })
            end
            cleanup()
            if callback then callback(false, { code = 'ERR_DB_QUERY_FAILED', details = err }) end
            return
        end

        if not admin then
            cleanup()
            if callback then callback(true, { isAdmin = false, roles = {}, permissions = {} }) end
            return
        end

        fetchAdminRoles(admin.id, function(roles, rolesErr)
            if rolesErr then
                -- إصلاح 3: تسجيل خطأ واضح وإرجاع حالة خطأ للمستدعي
                if Logger.Error then
                    Logger.Error(('Failed to fetch admin roles for admin ID %d: %s'):format(admin.id, tostring(rolesErr)), {
                        category = 'permission',
                        serverPlayerId = serverId
                    })
                end
                cleanup()
                if callback then callback(false, { code = 'ERR_DB_QUERY_FAILED', details = rolesErr }) end
                return
            end

            local allPermissions = {}
            local pendingRoles = #roles

            if pendingRoles == 0 then
                -- مشرف بدون أدوار
                saveToCache(discordId, {
                    isAdmin = true,
                    adminId = admin.id,
                    roles = roles,
                    permissions = allPermissions
                })

                cleanup()
                if callback then callback(true, { isAdmin = true, adminId = admin.id, roles = roles, permissions = {} }) end
                return
            end

            for _, roleCode in ipairs(roles) do
                fetchRolePermissions(roleCode, function(perms, permsErr)
                    if permsErr then
                        logPermissionEvent(('Failed to fetch permissions for role %s: %s'):format(roleCode, tostring(permsErr)))
                    else
                        for _, perm in ipairs(perms) do
                            allPermissions[perm] = true
                        end
                    end

                    pendingRoles = pendingRoles - 1

                    if pendingRoles <= 0 then
                        -- تحويل الجدول إلى قائمة
                        local permissionsList = {}
                        for perm, _ in pairs(allPermissions) do
                            permissionsList[#permissionsList + 1] = perm
                        end

                        saveToCache(discordId, {
                            isAdmin = true,
                            adminId = admin.id,
                            roles = roles,
                            permissions = allPermissions
                        })

                        cleanup()
                        if callback then
                            callback(true, {
                                isAdmin = true,
                                adminId = admin.id,
                                roles = roles,
                                permissions = permissionsList
                            })
                        end
                    end
                end)
            end
        end)
    end)
end

-- =============================================================
-- التحقق من امتلاك اللاعب لصلاحية معينة
-- =============================================================
function Permissions.HasPermission(source, permissionCode)
    if type(permissionCode) ~= 'string' or permissionCode == '' then
        return false
    end

    local serverId = tonumber(source)

    if not serverId or serverId <= 0 then
        return false
    end

    local okPlayer, player = Validator.ValidatePlayerSource(serverId, {
        requireOnline = true,
        requireIdentifiers = false
    })

    if not okPlayer then
        return false
    end

    local discordId = extractDiscordId(player.identifiers)

    if not discordId then
        return false
    end

    local cache = getPermissionsCache()

    if cache and cache.resolvedPermissions and cache.resolvedPermissions[discordId] then
        local resolved = cache.resolvedPermissions[discordId]

        -- إذا كان يمتلك صلاحية '*' (Super Admin)
        if resolved.permissions['*'] then
            return true
        end

        return resolved.permissions[permissionCode] == true
    end

    -- إذا لم تكن الصلاحيات محملة في الكاش، نرفض الطلب
    -- يجب تحميل الصلاحيات عند تسجيل دخول اللاعب
    logPermissionEvent(('Permissions not cached for player %d. Request denied.'):format(serverId), {
        meta = { permission = permissionCode }
    })

    return false
end

-- =============================================================
-- التحقق مما إذا كان اللاعب مشرفًا
-- =============================================================
function Permissions.IsAdmin(source)
    local serverId = tonumber(source)

    if not serverId or serverId <= 0 then
        return false
    end

    local okPlayer, player = Validator.ValidatePlayerSource(serverId, {
        requireOnline = true,
        requireIdentifiers = false
    })

    if not okPlayer then
        return false
    end

    local discordId = extractDiscordId(player.identifiers)

    if not discordId then
        return false
    end

    local cache = getPermissionsCache()

    if cache and cache.resolvedPermissions and cache.resolvedPermissions[discordId] then
        return cache.resolvedPermissions[discordId].isAdmin == true
    end

    return false
end

-- =============================================================
-- الحصول على جميع صلاحيات اللاعب
-- =============================================================
function Permissions.GetPlayerPermissions(source)
    local serverId = tonumber(source)

    if not serverId or serverId <= 0 then
        return {}
    end

    local okPlayer, player = Validator.ValidatePlayerSource(serverId, {
        requireOnline = true,
        requireIdentifiers = false
    })

    if not okPlayer then
        return {}
    end

    local discordId = extractDiscordId(player.identifiers)

    if not discordId then
        return {}
    end

    local cache = getPermissionsCache()

    if cache and cache.resolvedPermissions and cache.resolvedPermissions[discordId] then
        local resolved = cache.resolvedPermissions[discordId]
        local permissionsList = {}

        for perm, _ in pairs(resolved.permissions) do
            permissionsList[#permissionsList + 1] = perm
        end

        return permissionsList
    end

    return {}
end

-- =============================================================
-- إعادة تحميل الكاش لمشرف معين
-- =============================================================
function Permissions.ReloadAdminPermissions(discordId, callback)
    if type(discordId) ~= 'string' or discordId == '' then
        if callback then callback(false, 'Invalid discord ID') end
        return
    end

    -- مسح الكاش القديم
    local cache = getPermissionsCache()
    if cache and cache.resolvedPermissions then
        cache.resolvedPermissions[discordId] = nil
    end

    fetchAdminByDiscordId(discordId, function(admin, err)
        if err then
            if Logger.Error then
                Logger.Error(('Failed to fetch admin for reload: %s'):format(tostring(err)))
            end
            if callback then callback(false, err) end
            return
        end

        if not admin then
            saveToCache(discordId, { isAdmin = false, roles = {}, permissions = {} })
            if callback then callback(true, { isAdmin = false }) end
            return
        end

        fetchAdminRoles(admin.id, function(roles, rolesErr)
            if rolesErr then
                if Logger.Error then
                    Logger.Error(('Failed to fetch admin roles for reload: %s'):format(tostring(rolesErr)))
                end
                if callback then callback(false, rolesErr) end
                return
            end

            local allPermissions = {}
            local pendingRoles = #roles

            if pendingRoles == 0 then
                saveToCache(discordId, {
                    isAdmin = true,
                    adminId = admin.id,
                    roles = roles,
                    permissions = allPermissions
                })
                if callback then callback(true, { isAdmin = true, roles = roles }) end
                return
            end

            for _, roleCode in ipairs(roles) do
                fetchRolePermissions(roleCode, function(perms, permsErr)
                    if not permsErr then
                        for _, perm in ipairs(perms) do
                            allPermissions[perm] = true
                        end
                    end

                    pendingRoles = pendingRoles - 1

                    if pendingRoles <= 0 then
                        saveToCache(discordId, {
                            isAdmin = true,
                            adminId = admin.id,
                            roles = roles,
                            permissions = allPermissions
                        })
                        if callback then callback(true, { isAdmin = true, roles = roles }) end
                    end
                end)
            end
        end)
    end)
end

-- =============================================================
-- مسح كاش الصلاحيات بالكامل
-- =============================================================
function Permissions.ClearCache()
    if StateManager.ResetPermissions then
        StateManager.ResetPermissions()
        logPermissionEvent('Permissions cache cleared.')
    end
end

-- =============================================================
-- رسالة تحميل ناجحة
-- =============================================================
if Logger.Debug then
    Logger.Debug('server/core/permissions.lua loaded')
elseif OxSecure.Console and type(OxSecure.Console.debug) == 'function' then
    OxSecure.Console.debug('server/core/permissions.lua loaded')
end
