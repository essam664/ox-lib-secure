-- =============================================================
-- ox_lib_secure
-- File: server/modules/storage.lua
-- Description:
--   وحدة التخزين العام لنظام ox_lib_secure.
--
-- Notes:
--   - يوفر تخزين بنظام مفتاح/قيمة.
--   - يتم التخزين في قاعدة البيانات مع كاش محلي.
--   - يتم دعم انتهاء الصلاحية (TTL).
--   - يتم تنظيف القيم المنتهية دوريًا.
--   - إصلاح: استخدام INSERT ON DUPLICATE KEY UPDATE
--     بدلاً من الحذف ثم الإدراج لضمان سلامة البيانات.
-- =============================================================

Config = Config or {}
OxSecure = OxSecure or {}
OxSecure.Storage = OxSecure.Storage or {}

local Storage = OxSecure.Storage
local Database = OxSecure.Database or {}
local Logger = OxSecure.Logger or {}
local Utils = OxSecure.Utils or {}

local storageConfig = Config.Storage or {}
local DEFAULT_TTL_SECONDS = storageConfig.DefaultTTLSeconds or 3600
local CLEANUP_INTERVAL_SECONDS = storageConfig.CleanupIntervalSeconds or 300
local CACHE_TTL_SECONDS = storageConfig.CacheTTLSeconds or 60

-- الكاش المحلي
local localCache = {}
local cacheTimestamps = {}

-- =============================================================
-- أدوات مساعدة داخلية
-- =============================================================
local function logStorageEvent(message, options)
    if Logger.Info then
        Logger.Info(message, options or {
            category = 'storage',
            eventCode = 'storage_event'
        })
    end
end

local function logStorageError(message, options)
    if Logger.Error then
        Logger.Error(message, options or {
            category = 'storage',
            eventCode = 'storage_error'
        })
    end
end

-- =============================================================
-- التحقق من صلاحية الكاش المحلي
-- =============================================================
local function isCacheValid(key)
    if not localCache[key] then
        return false
    end

    if not cacheTimestamps[key] then
        return false
    end

    local elapsed = os.time() - cacheTimestamps[key]

    if elapsed > CACHE_TTL_SECONDS then
        localCache[key] = nil
        cacheTimestamps[key] = nil
        return false
    end

    return true
end

-- =============================================================
-- تحديث الكاش المحلي
-- =============================================================
local function updateLocalCache(key, value)
    localCache[key] = value
    cacheTimestamps[key] = os.time()
end

-- =============================================================
-- إزالة من الكاش المحلي
-- =============================================================
local function removeFromLocalCache(key)
    localCache[key] = nil
    cacheTimestamps[key] = nil
end

-- =============================================================
-- تخزين قيمة
--
-- إصلاح: استخدام INSERT ON DUPLICATE KEY UPDATE بدلاً من
-- الحذف ثم الإدراج لضمان عدم فقدان البيانات عند الفشل.
-- =============================================================
function Storage.Set(key, value, ttl, callback)
    if type(key) ~= 'string' or key == '' then
        if callback then callback(false, { code = 'ERR_INVALID_FIELD' }) end
        return
    end

    if value == nil then
        if callback then callback(false, { code = 'ERR_INVALID_FIELD' }) end
        return
    end

    ttl = ttl or DEFAULT_TTL_SECONDS

    -- تحويل القيمة إلى JSON للتخزين
    local valueJson = nil

    if Utils.SafeJsonEncode then
        valueJson = Utils.SafeJsonEncode(value)
    else
        valueJson = tostring(value)
    end

    -- حساب وقت انتهاء الصلاحية
    local expiresAtDatetime = nil

    if ttl > 0 then
        local expiresTimestamp = os.time() + ttl
        expiresAtDatetime = os.date('%Y-%m-%d %H:%M:%S', expiresTimestamp)
    end

    -- إصلاح: استخدام INSERT ON DUPLICATE KEY UPDATE
    local upsertQuery = ('INSERT INTO %s (storage_key, value_json, expires_at, created_at, updated_at) VALUES (?, ?, ?, NOW(), NOW()) ON DUPLICATE KEY UPDATE value_json = VALUES(value_json), expires_at = VALUES(expires_at), updated_at = NOW()'):format(Database.GetTableName('storage'))

    Database.Execute(upsertQuery, { key, valueJson, expiresAtDatetime }, function(_, err)
        if err then
            logStorageError(('Failed to set storage key %s: %s'):format(key, tostring(err)))
            if callback then callback(false, { code = 'ERR_DB_INSERT_FAILED', details = err }) end
            return
        end

        -- تحديث الكاش المحلي
        updateLocalCache(key, value)

        logStorageEvent(('Storage set: key=%s ttl=%d'):format(key, ttl))

        if callback then callback(true, nil) end
    end)
end

-- =============================================================
-- جلب قيمة
-- =============================================================
function Storage.Get(key, callback)
    if type(key) ~= 'string' or key == '' then
        if callback then callback(nil, { code = 'ERR_INVALID_FIELD' }) end
        return
    end

    -- التحقق من الكاش المحلي أولاً
    if isCacheValid(key) then
        if callback then callback(localCache[key], nil) end
        return
    end

    -- الجلب من قاعدة البيانات
    local selectQuery = ('SELECT value_json, expires_at FROM %s WHERE storage_key = ? AND (expires_at IS NULL OR expires_at > NOW())'):format(Database.GetTableName('storage'))

    Database.Single(selectQuery, { key }, function(result, err)
        if err then
            if callback then callback(nil, err) end
            return
        end

        if not result then
            if callback then callback(nil, nil) end
            return
        end

        -- فك ترميز القيمة
        local value = nil

        if result.value_json then
            if Utils.SafeJsonDecode then
                value = Utils.SafeJsonDecode(result.value_json)
            else
                value = result.value_json
            end
        end

        -- تحديث الكاش المحلي
        updateLocalCache(key, value)

        if callback then callback(value, nil) end
    end)
end

-- =============================================================
-- التحقق من وجود مفتاح
-- =============================================================
function Storage.Exists(key, callback)
    Storage.Get(key, function(value, err)
        if callback then callback(value ~= nil, err) end
    end)
end

-- =============================================================
-- حذف قيمة
-- =============================================================
function Storage.Delete(key, callback)
    if type(key) ~= 'string' or key == '' then
        if callback then callback(false, { code = 'ERR_INVALID_FIELD' }) end
        return
    end

    local deleteQuery = ('DELETE FROM %s WHERE storage_key = ?'):format(Database.GetTableName('storage'))

    Database.Execute(deleteQuery, { key }, function(_, err)
        if err then
            logStorageError(('Failed to delete storage key %s: %s'):format(key, tostring(err)))
            if callback then callback(false, err) end
            return
        end

        -- إزالة من الكاش المحلي
        removeFromLocalCache(key)

        logStorageEvent(('Storage deleted: key=%s'):format(key))

        if callback then callback(true, nil) end
    end)
end

-- =============================================================
-- جلب جميع المفاتيح التي تبدأ ببادئة معينة
-- =============================================================
function Storage.GetByPrefix(prefix, callback)
    if type(prefix) ~= 'string' or prefix == '' then
        if callback then callback({}, nil) end
        return
    end

    local selectQuery = ('SELECT storage_key, value_json FROM %s WHERE storage_key LIKE ? AND (expires_at IS NULL OR expires_at > NOW())'):format(Database.GetTableName('storage'))

    Database.Execute(selectQuery, { prefix .. '%' }, function(results, err)
        if err then
            if callback then callback({}, err) end
            return
        end

        local items = {}

        if type(results) == 'table' then
            for _, row in ipairs(results) do
                local value = nil

                if row.value_json then
                    if Utils.SafeJsonDecode then
                        value = Utils.SafeJsonDecode(row.value_json)
                    else
                        value = row.value_json
                    end
                end

                items[row.storage_key] = value
            end
        end

        if callback then callback(items, nil) end
    end)
end

-- =============================================================
-- حذف جميع المفاتيح التي تبدأ ببادئة معينة
-- =============================================================
function Storage.DeleteByPrefix(prefix, callback)
    if type(prefix) ~= 'string' or prefix == '' then
        if callback then callback(false, { code = 'ERR_INVALID_FIELD' }) end
        return
    end

    local deleteQuery = ('DELETE FROM %s WHERE storage_key LIKE ?'):format(Database.GetTableName('storage'))

    Database.Execute(deleteQuery, { prefix .. '%' }, function(_, err)
        if err then
            if callback then callback(false, err) end
            return
        end

        -- تنظيف الكاش المحلي من المفاتيح المطابقة
        for key in pairs(localCache) do
            if key:sub(1, #prefix) == prefix then
                removeFromLocalCache(key)
            end
        end

        logStorageEvent(('Storage deleted by prefix: %s'):format(prefix))

        if callback then callback(true, nil) end
    end)
end

-- =============================================================
-- زيادة قيمة رقمية
--
-- ملاحظة: هذه العملية غير ذرية. إذا كانت الدقة مهمة
-- في بيئة متعددة الخيوط، يُنصح باستخدام قفل أو استعلام
-- UPDATE ذري مع عمود رقمي منفصل.
-- =============================================================
function Storage.Increment(key, amount, callback)
    amount = amount or 1

    Storage.Get(key, function(currentValue, err)
        if err then
            if callback then callback(false, err) end
            return
        end

        local newValue = 0

        if type(currentValue) == 'number' then
            newValue = currentValue + amount
        else
            newValue = amount
        end

        Storage.Set(key, newValue, DEFAULT_TTL_SECONDS, function(ok, setErr)
            if not ok then
                if callback then callback(false, setErr) end
                return
            end

            if callback then callback(true, newValue) end
        end)
    end)
end

-- =============================================================
-- تنظيف القيم المنتهية الصلاحية
-- =============================================================
function Storage.CleanupExpired(callback)
    local deleteQuery = ('DELETE FROM %s WHERE expires_at IS NOT NULL AND expires_at < NOW()'):format(Database.GetTableName('storage'))

    Database.Execute(deleteQuery, {}, function(_, err)
        if err then
            logStorageError(('Failed to cleanup expired storage: %s'):format(tostring(err)))
            if callback then callback(false, err) end
            return
        end

        if callback then callback(true, nil) end
    end)
end

-- =============================================================
-- مسح الكاش المحلي بالكامل
-- =============================================================
function Storage.ClearLocalCache()
    localCache = {}
    cacheTimestamps = {}
end

-- =============================================================
-- الحصول على إحصائيات التخزين
-- =============================================================
function Storage.GetStats(callback)
    local statsQuery = ('SELECT COUNT(*) as total FROM %s WHERE expires_at IS NULL OR expires_at > NOW()'):format(Database.GetTableName('storage'))

    Database.Single(statsQuery, {}, function(result, err)
        if err then
            if callback then callback({}, err) end
            return
        end

        local cacheCount = 0

        for _ in pairs(localCache) do
            cacheCount = cacheCount + 1
        end

        local stats = {
            totalKeys = result and result.total or 0,
            localCacheSize = cacheCount
        }

        if callback then callback(stats, nil) end
    end)
end

-- =============================================================
-- مهمة دورية لتنظيف القيم المنتهية الصلاحية
-- =============================================================
CreateThread(function()
    while true do
        Wait(CLEANUP_INTERVAL_SECONDS * 1000)

        if Database.IsReady() then
            Storage.CleanupExpired()
        end
    end
end)

-- =============================================================
-- رسالة تحميل ناجحة
-- =============================================================
if Logger.Debug then
    Logger.Debug('server/modules/storage.lua loaded')
elseif OxSecure.Console and type(OxSecure.Console.debug) == 'function' then
    OxSecure.Console.debug('server/modules/storage.lua loaded')
end
