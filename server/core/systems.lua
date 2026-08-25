-- =============================================================
-- ox_lib_secure
-- File: server/core/systems.lua
-- Description:
--   طبقة إدارة الأنظمة المربوطة لنظام ox_lib_secure.
--
-- Notes:
--   - يتم تسجيل الأنظمة الخارجية برمز فريد وسر.
--   - يتم توليد توكنات وصول مشفرة للأنظمة.
--   - يتم التحقق من التوكنات عند كل طلب.
--   - يتم إدارة نطاقات الصلاحيات لكل نظام.
--   - يتم تحديث آخر استخدام تلقائيًا.
--   - يتم التعامل مع الوضع المتدهور بشكل آمن.
--   - الكاش يدعم انتهاء الصلاحية (TTL) اختياريًا.
--   - فترة التنظيف قابلة للتخصيص بشكل منفصل عن TTL.
-- =============================================================

Config = Config or {}
OxSecure = OxSecure or {}
OxSecure.Systems = OxSecure.Systems or {}

local Systems = OxSecure.Systems
local Database = OxSecure.Database or {}
local Security = OxSecure.Security or {}
local Logger = OxSecure.Logger or {}
local Utils = OxSecure.Utils or {}
local StateManager = OxSecure.StateManager or {}

local systemsConfig = Config.Systems or {}
local CACHE_TTL_SECONDS = systemsConfig.CacheTTLSeconds or 300
local CACHE_CLEANUP_INTERVAL_SECONDS = systemsConfig.CacheCleanupIntervalSeconds or 120

-- =============================================================
-- أدوات مساعدة داخلية
-- =============================================================
local function getSystemsCache()
    local state = StateManager.Get and StateManager.Get() or nil
    return state and state.systems or nil
end

local function logSystemEvent(message, options)
    if Logger.Info then
        Logger.Info(message, options or {
            category = 'system',
            eventCode = 'system_event'
        })
    end
end

local function logSystemError(message, options)
    if Logger.Error then
        Logger.Error(message, options or {
            category = 'system',
            eventCode = 'system_error'
        })
    end
end

local function logSystemWarn(message)
    if Logger.Warn then
        Logger.Warn(message, {
            category = 'system',
            eventCode = 'system_warning'
        })
    end
end

-- =============================================================
-- دالة موحدة لتوليد توكن مع بديل للوضع المتدهور
--
-- الأولوية:
--   1. Security.GenerateToken (HMAC + مفتاح رئيسي)
--   2. Utils.GenerateRandomString (مولد داخلي)
--   3. بديل الطابع الزمني (آخر ملاذ - غير تشفيري القوة)
-- =============================================================
local function generateSecureToken(length)
    length = length or 64

    -- الأولوية 1: استخدام Security.GenerateToken
    if Security.GenerateToken then
        local token, tokenHash, tokenHint = Security.GenerateToken(length)

        if token and tokenHash then
            return token, tokenHash, tokenHint
        end
    end

    -- الأولوية 2: استخدام Utils.GenerateRandomString
    if Utils.GenerateRandomString then
        local fallbackToken = Utils.GenerateRandomString(length)
        local fallbackHash = Security.Hash and Security.Hash(fallbackToken) or fallbackToken
        local fallbackHint = fallbackToken:sub(1, 8)

        return fallbackToken, fallbackHash, fallbackHint
    end

    -- الأولوية 3: بديل الطابع الزمني (آخر ملاذ)
    logSystemWarn('generateSecureToken: falling back to timestamp-based token. This is not recommended for production.')

    local lastResortToken = ('token_%d_%d_%d'):format(
        os.time(),
        math.floor(os.clock() * 1000000),
        math.random(100000, 999999)
    )

    if Utils.GenerateSessionId then
        lastResortToken = lastResortToken .. '_' .. Utils.GenerateSessionId(16)
    end

    local lastResortHash = Security.Hash and Security.Hash(lastResortToken) or lastResortToken
    local lastResortHint = lastResortToken:sub(1, 8)

    return lastResortToken, lastResortHash, lastResortHint
end

-- =============================================================
-- دالة موحدة لتجزئة توكن للتحقق
-- =============================================================
local function hashTokenForValidation(token)
    if Security.HashToken then
        local hash = Security.HashToken(token)

        if hash then
            return hash
        end
    end

    if Security.Hash then
        return Security.Hash(token)
    end

    return token
end

-- =============================================================
-- كاش مع انتهاء صلاحية (TTL)
-- =============================================================
local function getCachedSystem(systemCode)
    local cache = getSystemsCache()

    if not cache or not cache.byCode then
        return nil
    end

    local entry = cache.byCode[systemCode]

    if not entry then
        return nil
    end

    if CACHE_TTL_SECONDS > 0 and entry.cachedAt then
        local elapsed = os.time() - entry.cachedAt

        if elapsed > CACHE_TTL_SECONDS then
            cache.byCode[systemCode] = nil

            if cache.byId and entry.data and entry.data.id then
                cache.byId[entry.data.id] = nil
            end

            return nil
        end
    end

    return entry.data or entry
end

local function cacheSystem(systemData)
    local cache = getSystemsCache()

    if not cache then
        return
    end

    if not cache.byCode then
        cache.byCode = {}
    end

    if not cache.byId then
        cache.byId = {}
    end

    local now = os.time()

    local entry = {
        data = systemData,
        cachedAt = now
    }

    cache.byCode[systemData.system_code] = entry
    cache.byId[systemData.id] = entry
end

-- =============================================================
-- حذف نظام من كلا جدولي الكاش
-- =============================================================
local function removeFromCache(systemCode, systemId)
    local cache = getSystemsCache()

    if not cache then
        return
    end

    if cache.byCode and systemCode then
        cache.byCode[systemCode] = nil
    end

    if cache.byId and systemId then
        cache.byId[systemId] = nil
    end
end

-- =============================================================
-- تنظيف الكاش المنتهي الصلاحية
-- =============================================================
function Systems.CleanupCache()
    local cache = getSystemsCache()

    if not cache or not cache.byCode or CACHE_TTL_SECONDS <= 0 then
        return 0
    end

    local now = os.time()
    local removedCount = 0

    for code, entry in pairs(cache.byCode) do
        if entry.cachedAt and (now - entry.cachedAt) > CACHE_TTL_SECONDS then
            local systemId = entry.data and entry.data.id or nil

            cache.byCode[code] = nil

            if cache.byId and systemId then
                cache.byId[systemId] = nil
            end

            removedCount = removedCount + 1
        end
    end

    if removedCount > 0 then
        logSystemEvent(('Cleaned up %d expired system cache entries'):format(removedCount))
    end

    return removedCount
end

-- =============================================================
-- تسجيل نظام جديد
-- =============================================================
function Systems.RegisterSystem(systemCode, displayName, notes, callback)
    if type(systemCode) ~= 'string' or systemCode == '' then
        if callback then callback(false, { code = 'ERR_INVALID_SYSTEM_CODE' }) end
        return
    end

    if type(displayName) ~= 'string' or displayName == '' then
        displayName = systemCode
    end

    local selectQuery = ('SELECT id FROM %s WHERE system_code = ?'):format(Database.GetTableName('systems'))

    Database.Single(selectQuery, { systemCode }, function(existing, err)
        if err then
            logSystemError(('Failed to check system existence: %s'):format(tostring(err)))
            if callback then callback(false, { code = 'ERR_DB_QUERY_FAILED', details = err }) end
            return
        end

        if existing then
            if callback then callback(false, { code = 'ERR_SYSTEM_ALREADY_EXISTS' }) end
            return
        end

        local secret, secretHash = generateSecureToken(64)

        local signingKeyHash = nil
        if Security.GetSigningKey then
            local signingKey = Security.GetSigningKey()
            if signingKey and Security.Hash then
                signingKeyHash = Security.Hash(signingKey .. ':' .. systemCode)
            end
        end

        local insertQuery = ('INSERT INTO %s (system_code, display_name, notes, secret_hash, signing_key_hash, is_active, created_at) VALUES (?, ?, ?, ?, ?, 1, NOW())'):format(Database.GetTableName('systems'))

        Database.Insert(insertQuery, {
            systemCode,
            displayName,
            notes,
            secretHash,
            signingKeyHash
        }, function(insertId, insertErr)
            if insertErr then
                logSystemError(('Failed to register system: %s'):format(tostring(insertErr)))
                if callback then callback(false, { code = 'ERR_DB_INSERT_FAILED', details = insertErr }) end
                return
            end

            local systemData = {
                id = insertId,
                system_code = systemCode,
                display_name = displayName,
                notes = notes,
                secret_hash = secretHash,
                signing_key_hash = signingKeyHash,
                is_active = true,
                last_used_at = nil
            }

            cacheSystem(systemData)

            logSystemEvent(('System registered: %s (ID: %d)'):format(systemCode, insertId))

            if callback then
                callback(true, {
                    id = insertId,
                    systemCode = systemCode,
                    displayName = displayName,
                    secret = secret
                })
            end
        end)
    end)
end

-- =============================================================
-- جلب نظام من قاعدة البيانات
-- =============================================================
function Systems.GetSystem(systemCode, callback)
    if type(systemCode) ~= 'string' or systemCode == '' then
        if callback then callback(nil, 'Invalid system code') end
        return
    end

    local cached = getCachedSystem(systemCode)

    if cached then
        if callback then callback(cached, nil) end
        return
    end

    local selectQuery = ('SELECT * FROM %s WHERE system_code = ?'):format(Database.GetTableName('systems'))

    Database.Single(selectQuery, { systemCode }, function(result, err)
        if err then
            if callback then callback(nil, err) end
            return
        end

        if result then
            cacheSystem(result)
        end

        if callback then callback(result, nil) end
    end)
end

-- =============================================================
-- التحقق من توكن نظام
-- =============================================================
function Systems.ValidateToken(token, callback)
    if type(token) ~= 'string' or token == '' then
        if callback then callback(false, { code = 'ERR_INVALID_TOKEN' }) end
        return
    end

    local tokenHash = hashTokenForValidation(token)

    if not tokenHash then
        if callback then callback(false, { code = 'ERR_TOKEN_HASH_FAILED' }) end
        return
    end

    local selectQuery = ('SELECT st.*, s.system_code, s.display_name, s.is_active as system_active FROM %s st INNER JOIN %s s ON st.system_id = s.id WHERE st.token_hash = ? AND st.revoked_at IS NULL AND (st.expires_at IS NULL OR st.expires_at > NOW())'):format(Database.GetTableName('system_tokens'), Database.GetTableName('systems'))

    Database.Single(selectQuery, { tokenHash }, function(result, err)
        if err then
            if callback then callback(false, { code = 'ERR_DB_QUERY_FAILED', details = err }) end
            return
        end

        if not result then
            if callback then callback(false, { code = 'ERR_TOKEN_NOT_FOUND' }) end
            return
        end

        if result.system_active ~= 1 then
            if callback then callback(false, { code = 'ERR_SYSTEM_DISABLED' }) end
            return
        end

        local updateTokenQuery = ('UPDATE %s SET last_used_at = NOW() WHERE token_hash = ?'):format(Database.GetTableName('system_tokens'))
        Database.Execute(updateTokenQuery, { tokenHash }, function() end)

        local updateSystemQuery = ('UPDATE %s SET last_used_at = NOW() WHERE id = ?'):format(Database.GetTableName('systems'))
        Database.Execute(updateSystemQuery, { result.system_id }, function() end)

        Systems.GetSystemScopes(result.system_id, function(scopes)
            if callback then
                callback(true, {
                    tokenId = result.id,
                    systemId = result.system_id,
                    systemCode = result.system_code,
                    displayName = result.display_name,
                    scopes = scopes or {}
                })
            end
        end)
    end)
end

-- =============================================================
-- توليد توكن لنظام
-- =============================================================
function Systems.GenerateToken(systemId, expiresAt, callback)
    if not systemId or systemId <= 0 then
        if callback then callback(false, { code = 'ERR_INVALID_SYSTEM_ID' }) end
        return
    end

    local selectQuery = ('SELECT id, system_code FROM %s WHERE id = ? AND is_active = 1'):format(Database.GetTableName('systems'))

    Database.Single(selectQuery, { systemId }, function(system, err)
        if err or not system then
            if callback then callback(false, { code = 'ERR_SYSTEM_NOT_FOUND' }) end
            return
        end

        local token, tokenHash, tokenHint = generateSecureToken(64)

        local insertQuery = ('INSERT INTO %s (system_id, token_hash, token_hint, expires_at, created_at) VALUES (?, ?, ?, ?, NOW())'):format(Database.GetTableName('system_tokens'))

        Database.Insert(insertQuery, {
            systemId,
            tokenHash,
            tokenHint,
            expiresAt
        }, function(insertId, insertErr)
            if insertErr then
                logSystemError(('Failed to generate token: %s'):format(tostring(insertErr)))
                if callback then callback(false, { code = 'ERR_DB_INSERT_FAILED', details = insertErr }) end
                return
            end

            logSystemEvent(('Token generated for system %s'):format(system.system_code))

            if callback then
                callback(true, {
                    tokenId = insertId,
                    token = token,
                    tokenHint = tokenHint,
                    expiresAt = expiresAt
                })
            end
        end)
    end)
end

-- =============================================================
-- إبطال توكن
-- =============================================================
function Systems.RevokeToken(tokenHash, callback)
    if type(tokenHash) ~= 'string' or tokenHash == '' then
        if callback then callback(false, 'Invalid token hash') end
        return
    end

    local updateQuery = ('UPDATE %s SET revoked_at = NOW() WHERE token_hash = ?'):format(Database.GetTableName('system_tokens'))

    Database.Execute(updateQuery, { tokenHash }, function(_, err)
        if err then
            if callback then callback(false, err) end
            return
        end

        if callback then callback(true, nil) end
    end)
end

-- =============================================================
-- جلب نطاقات نظام
-- =============================================================
function Systems.GetSystemScopes(systemId, callback)
    if not systemId or systemId <= 0 then
        if callback then callback({}) end
        return
    end

    local selectQuery = ('SELECT scope_code FROM %s WHERE system_id = ?'):format(Database.GetTableName('system_scopes'))

    Database.Execute(selectQuery, { systemId }, function(results, err)
        if err then
            if callback then callback({}) end
            return
        end

        local scopes = {}

        if type(results) == 'table' then
            for _, row in ipairs(results) do
                scopes[#scopes + 1] = row.scope_code
            end
        end

        if callback then callback(scopes) end
    end)
end

-- =============================================================
-- إضافة نطاق لنظام
-- =============================================================
function Systems.AddScope(systemId, scopeCode, callback)
    if not systemId or systemId <= 0 then
        if callback then callback(false, 'Invalid system ID') end
        return
    end

    if type(scopeCode) ~= 'string' or scopeCode == '' then
        if callback then callback(false, 'Invalid scope code') end
        return
    end

    local insertQuery = ('INSERT INTO %s (system_id, scope_code) VALUES (?, ?) ON DUPLICATE KEY UPDATE scope_code = scope_code'):format(Database.GetTableName('system_scopes'))

    Database.Execute(insertQuery, { systemId, scopeCode }, function(_, err)
        if err then
            if callback then callback(false, err) end
            return
        end

        if callback then callback(true, nil) end
    end)
end

-- =============================================================
-- إزالة نطاق من نظام
-- =============================================================
function Systems.RemoveScope(systemId, scopeCode, callback)
    if not systemId or systemId <= 0 then
        if callback then callback(false, 'Invalid system ID') end
        return
    end

    if type(scopeCode) ~= 'string' or scopeCode == '' then
        if callback then callback(false, 'Invalid scope code') end
        return
    end

    local deleteQuery = ('DELETE FROM %s WHERE system_id = ? AND scope_code = ?'):format(Database.GetTableName('system_scopes'))

    Database.Execute(deleteQuery, { systemId, scopeCode }, function(_, err)
        if err then
            if callback then callback(false, err) end
            return
        end

        if callback then callback(true, nil) end
    end)
end

-- =============================================================
-- التحقق من امتلاك نظام لنطاق معين
-- =============================================================
function Systems.HasScope(systemId, scopeCode, callback)
    if not systemId or systemId <= 0 then
        if callback then callback(false) end
        return
    end

    if type(scopeCode) ~= 'string' or scopeCode == '' then
        if callback then callback(false) end
        return
    end

    local selectQuery = ('SELECT COUNT(*) as total FROM %s WHERE system_id = ? AND scope_code = ?'):format(Database.GetTableName('system_scopes'))

    Database.Single(selectQuery, { systemId, scopeCode }, function(result, err)
        if err then
            if callback then callback(false) end
            return
        end

        local hasScope = result and result.total and result.total > 0

        if callback then callback(hasScope) end
    end)
end

-- =============================================================
-- تفعيل / تعطيل نظام
-- =============================================================
function Systems.SetActive(systemCode, isActive, callback)
    if type(systemCode) ~= 'string' or systemCode == '' then
        if callback then callback(false, 'Invalid system code') end
        return
    end

    local updateQuery = ('UPDATE %s SET is_active = ? WHERE system_code = ?'):format(Database.GetTableName('systems'))

    Database.Execute(updateQuery, { isActive and 1 or 0, systemCode }, function(_, err)
        if err then
            if callback then callback(false, err) end
            return
        end

        -- حذف من كلا الجدولين
        local cache = getSystemsCache()
        local systemId = nil

        if cache and cache.byCode then
            local entry = cache.byCode[systemCode]

            if entry and entry.data then
                systemId = entry.data.id
            end
        end

        removeFromCache(systemCode, systemId)

        logSystemEvent(('System %s set to %s'):format(systemCode, isActive and 'active' or 'inactive'))

        if callback then callback(true, nil) end
    end)
end

-- =============================================================
-- جلب جميع الأنظمة النشطة
-- =============================================================
function Systems.GetActiveSystems(callback)
    local selectQuery = ('SELECT * FROM %s WHERE is_active = 1'):format(Database.GetTableName('systems'))

    Database.Execute(selectQuery, {}, function(results, err)
        if err then
            if callback then callback({}, err) end
            return
        end

        if type(results) == 'table' then
            for _, system in ipairs(results) do
                cacheSystem(system)
            end
        end

        if callback then callback(results or {}, nil) end
    end)
end

-- =============================================================
-- جلب جميع الأنظمة
-- =============================================================
function Systems.GetAllSystems(callback)
    local selectQuery = ('SELECT * FROM %s ORDER BY created_at DESC'):format(Database.GetTableName('systems'))

    Database.Execute(selectQuery, {}, function(results, err)
        if err then
            if callback then callback({}, err) end
            return
        end

        if callback then callback(results or {}, nil) end
    end)
end

-- =============================================================
-- مهمة دورية لتنظيف الكاش المنتهي الصلاحية
--
-- إصلاح: استخدام CacheCleanupIntervalSeconds بشكل منفصل
-- عن CacheTTLSeconds مع حد أدنى 30 ثانية.
-- =============================================================
if CACHE_TTL_SECONDS > 0 then
    CreateThread(function()
        while true do
            local cleanupInterval = math.max(CACHE_CLEANUP_INTERVAL_SECONDS, 30)
            Wait(cleanupInterval * 1000)
            Systems.CleanupCache()
        end
    end)
end

-- =============================================================
-- رسالة تحميل ناجحة
-- =============================================================
if Logger.Debug then
    Logger.Debug('server/core/systems.lua loaded')
elseif OxSecure.Console and type(OxSecure.Console.debug) == 'function' then
    OxSecure.Console.debug('server/core/systems.lua loaded')
end
