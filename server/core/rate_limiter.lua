-- =============================================================
-- ox_lib_secure
-- File: server/core/rate_limiter.lua
-- Description:
--   وحدة معدل الطلبات لنظام ox_lib_secure.
--   تحمي من الإغراق والطلب المتكرر.
--
-- Notes:
--   - مواءمة 100% مع config/main.lua النهائي.
--   - تستخدم مفاتيح: max و windowSeconds في الباكيتات.
--   - تدعم الذاكرة وقاعدة البيانات.
--   - تنظيف دوري للبيانات المنتهية.
--   - إصلاح: استعلام التدقيق يتطابق مع جدول الترحيلات.
-- =============================================================

Config = Config or {}
OxSecure = OxSecure or {}
OxSecure.RateLimiter = OxSecure.RateLimiter or {}

local RateLimiter = OxSecure.RateLimiter
local Logger = OxSecure.Logger or {}
local Database = OxSecure.Database or {}

-- =============================================================
-- قراءة الإعدادات من الكونفق
-- متوافقة حرفيًا مع config/main.lua
-- =============================================================
local rateLimitConfig = Config.RateLimit or {}

local USE_MEMORY_LIMITER = rateLimitConfig.UseMemoryLimiter ~= false
local USE_DB_AUDIT = rateLimitConfig.UseDatabaseOnlyForAudit == true
local CLEANUP_INTERVAL_SECONDS = rateLimitConfig.CleanupIntervalSeconds or 300
local MAX_TOTAL_BUCKETS = rateLimitConfig.MaxTotalBuckets or 10000
local DEFAULT_WINDOW_SECONDS = rateLimitConfig.WindowSeconds or 60
local DEFAULT_MAX_PER_WINDOW = rateLimitConfig.MaxPerWindow or 60
local BUCKETS = rateLimitConfig.Buckets or {}
local MAX_TRACKED_SOURCES = rateLimitConfig.MaxTrackedSources or 1000

-- =============================================================
-- الحالة الداخلية
-- =============================================================
local trackedSources = {}
local isInitialized = false

-- =============================================================
-- أدوات مساعدة داخلية
-- =============================================================
local function logRateLimit(message, level)
    level = level or 'info'
    if Logger and Logger.Log then
        Logger.Log(level, message, { category = 'rate_limiter' })
    else
        print(('[ox_lib_secure] [RATE_LIMITER] %s'):format(message))
    end
end

local function getCurrentTimestamp()
    return os.time()
end

-- =============================================================
-- تهيئة معدل الطلبات
-- =============================================================
function RateLimiter.Initialize()
    if isInitialized then
        return true
    end

    if not USE_MEMORY_LIMITER then
        logRateLimit('Memory limiter is disabled.')
        return true
    end

    logRateLimit('Initializing rate limiter...')
    logRateLimit(('Default: %d requests per %d seconds'):format(DEFAULT_MAX_PER_WINDOW, DEFAULT_WINDOW_SECONDS))

    -- بدء التنظيف الدوري
    CreateThread(function()
        while true do
            Wait(CLEANUP_INTERVAL_SECONDS * 1000)
            RateLimiter.Cleanup()
        end
    end)

    isInitialized = true
    logRateLimit('Rate limiter initialized successfully.')
    return true
end

-- =============================================================
-- الحصول على إعدادات الباكيت
-- =============================================================
local function getBucketConfig(bucketName)
    if not bucketName then
        bucketName = 'default'
    end

    local bucket = BUCKETS[bucketName]

    if not bucket then
        return {
            max = DEFAULT_MAX_PER_WINDOW,
            windowSeconds = DEFAULT_WINDOW_SECONDS
        }
    end

    return {
        max = bucket.max or DEFAULT_MAX_PER_WINDOW,
        windowSeconds = bucket.windowSeconds or DEFAULT_WINDOW_SECONDS
    }
end

-- =============================================================
-- التحقق من معدل الطلبات
-- إصلاح: استعلام التدقيق يتطابق مع جدول الترحيلات الفعلي
-- =============================================================
function RateLimiter.Check(source, bucketName)
    if not USE_MEMORY_LIMITER then
        return true
    end

    if not source then
        return false, 'Source is required'
    end

    bucketName = bucketName or 'default'

    local bucketConfig = getBucketConfig(bucketName)
    local maxRequests = bucketConfig.max
    local windowSeconds = bucketConfig.windowSeconds

    local now = getCurrentTimestamp()
    local key = ('%s:%s'):format(tostring(source), bucketName)

    -- إنشاء أو تحديث البيانات
    if not trackedSources[key] then
        trackedSources[key] = {
            count = 0,
            windowStart = now,
            source = source,
            bucket = bucketName
        }
    end

    local data = trackedSources[key]

    -- التحقق من انتهاء النافذة
    if (now - data.windowStart) >= windowSeconds then
        data.count = 0
        data.windowStart = now
    end

    -- زيادة العدد
    data.count = data.count + 1

    -- التحقق من الحد
    if data.count > maxRequests then
        logRateLimit(('Rate limit exceeded: source=%s, bucket=%s, count=%d/%d'):format(
            tostring(source), bucketName, data.count, maxRequests
        ), 'warn')

        -- تسجيل في قاعدة البيانات إذا كان مفعلًا
        -- إصلاح: استخدام الجدول والأعمدة الفعلية من الترحيلات
        if USE_DB_AUDIT and Database and Database.Execute then
            local ok, tableName = pcall(function()
                if Database.GetTableName then
                    return Database.GetTableName('rate_limit_audit')
                end
                return 'oxsecure_rate_limit_audit'
            end)

            if ok and tableName then
                local metaJson = json.encode({
                    maxAllowed = maxRequests,
                    windowSeconds = windowSeconds,
                    exceededBy = data.count - maxRequests
                })

                Database.Execute(
                    ('INSERT INTO %s (source_type, source_id, bucket_name, window_count, meta_json, created_at) VALUES (?, ?, ?, ?, ?, NOW())'):format(tableName),
                    { 'player', tostring(source), bucketName, data.count, metaJson }
                )
            end
        end

        return false, ('Rate limit exceeded. Max %d requests per %d seconds.'):format(maxRequests, windowSeconds)
    end

    return true
end

-- =============================================================
-- التحقق مع معلومات إضافية
-- =============================================================
function RateLimiter.CheckWithInfo(source, bucketName)
    local allowed, err = RateLimiter.Check(source, bucketName)

    if not allowed then
        return false, err
    end

    local key = ('%s:%s'):format(tostring(source), bucketName or 'default')
    local data = trackedSources[key]

    if data then
        return true, nil, {
            currentCount = data.count,
            windowStart = data.windowStart,
            bucket = bucketName or 'default'
        }
    end

    return true
end

-- =============================================================
-- إعادة تعيين معدل مصدر معين
-- =============================================================
function RateLimiter.Reset(source, bucketName)
    if not source then
        return false
    end

    bucketName = bucketName or 'default'
    local key = ('%s:%s'):format(tostring(source), bucketName)

    if trackedSources[key] then
        trackedSources[key] = nil
        return true
    end

    return false
end

-- =============================================================
-- إعادة تعيين جميع المعدلات لمصدر معين
-- =============================================================
function RateLimiter.ResetAll(source)
    if not source then
        return 0
    end

    local reset = 0

    for key, data in pairs(trackedSources) do
        if data.source == source then
            trackedSources[key] = nil
            reset = reset + 1
        end
    end

    return reset
end

-- =============================================================
-- الحصول على معلومات معدل مصدر معين
-- =============================================================
function RateLimiter.GetInfo(source, bucketName)
    if not source then
        return nil
    end

    bucketName = bucketName or 'default'
    local key = ('%s:%s'):format(tostring(source), bucketName)
    local data = trackedSources[key]

    if not data then
        return nil
    end

    local bucketConfig = getBucketConfig(bucketName)

    return {
        source = source,
        bucket = bucketName,
        currentCount = data.count,
        maxAllowed = bucketConfig.max,
        windowSeconds = bucketConfig.windowSeconds,
        windowStart = data.windowStart,
        remaining = math.max(0, bucketConfig.max - data.count),
        resetAt = data.windowStart + bucketConfig.windowSeconds
    }
end

-- =============================================================
-- الحصول على جميع المصادر المتعقبة
-- =============================================================
function RateLimiter.GetAllTracked()
    local result = {}

    for key, data in pairs(trackedSources) do
        local bucketConfig = getBucketConfig(data.bucket)

        result[#result + 1] = {
            key = key,
            source = data.source,
            bucket = data.bucket,
            currentCount = data.count,
            maxAllowed = bucketConfig.max,
            windowStart = data.windowStart
        }
    end

    return result
end

-- =============================================================
-- الحصول على الإحصائيات
-- =============================================================
function RateLimiter.GetStats()
    local totalTracked = 0
    local totalRequests = 0
    local buckets = {}

    for key, data in pairs(trackedSources) do
        totalTracked = totalTracked + 1
        totalRequests = totalRequests + data.count

        if not buckets[data.bucket] then
            buckets[data.bucket] = 0
        end
        buckets[data.bucket] = buckets[data.bucket] + 1
    end

    return {
        totalTracked = totalTracked,
        totalRequests = totalRequests,
        buckets = buckets,
        isInitialized = isInitialized,
        useMemoryLimiter = USE_MEMORY_LIMITER,
        useDbAudit = USE_DB_AUDIT,
        maxTotalBuckets = MAX_TOTAL_BUCKETS,
        maxTrackedSources = MAX_TRACKED_SOURCES
    }
end

-- =============================================================
-- تنظيف دوري
-- =============================================================
function RateLimiter.Cleanup()
    local now = getCurrentTimestamp()
    local cleaned = 0

    for key, data in pairs(trackedSources) do
        local bucketConfig = getBucketConfig(data.bucket)

        -- إزالة المصادر التي انتهت نافذتها
        if (now - data.windowStart) >= (bucketConfig.windowSeconds * 2) then
            trackedSources[key] = nil
            cleaned = cleaned + 1
        end
    end

    -- التحقق من الحد الأقصى للمصادر المتعقبة
    local count = 0
    for _ in pairs(trackedSources) do
        count = count + 1
    end

    if count > MAX_TRACKED_SOURCES then
        -- إزالة أقدم المصادر
        local sorted = {}
        for key, data in pairs(trackedSources) do
            sorted[#sorted + 1] = { key = key, windowStart = data.windowStart }
        end

        table.sort(sorted, function(a, b)
            return a.windowStart < b.windowStart
        end)

        local toRemove = count - MAX_TRACKED_SOURCES
        for i = 1, toRemove do
            if sorted[i] then
                trackedSources[sorted[i].key] = nil
                cleaned = cleaned + 1
            end
        end
    end

    if cleaned > 0 then
        logRateLimit(('Cleanup: removed %d expired entries'):format(cleaned))
    end
end

-- =============================================================
-- الحصول على إعدادات الباكيتات (للعرض)
-- =============================================================
function RateLimiter.GetBucketConfigs()
    local result = {}

    for name, bucket in pairs(BUCKETS) do
        result[name] = {
            max = bucket.max or DEFAULT_MAX_PER_WINDOW,
            windowSeconds = bucket.windowSeconds or DEFAULT_WINDOW_SECONDS
        }
    end

    result['default'] = {
        max = DEFAULT_MAX_PER_WINDOW,
        windowSeconds = DEFAULT_WINDOW_SECONDS
    }

    return result
end

-- =============================================================
-- تهيئة عند التحميل
-- =============================================================
RateLimiter.Initialize()

-- =============================================================
-- رسالة تحميل ناجحة
-- =============================================================
if Logger and Logger.Debug then
    Logger.Debug('server/core/rate_limiter.lua loaded')
else
    print('[ox_lib_secure] server/core/rate_limiter.lua loaded')
end
