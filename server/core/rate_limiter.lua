-- =============================================================
-- ox_lib_secure
-- File: server/core/rate_limiter.lua
-- Description:
--   طبقة معدل الاستخدام لنظام ox_lib_secure.
--
-- Notes:
--   - الفحص الأول يتم دائمًا في الذاكرة لأداء أفضل.
--   - قاعدة البيانات تُستخدم للتدقيق فقط وليس لكل طلب.
--   - يتم تنظيف الدلاء المنتهية دوريًا.
--   - عند تجاوز الحد، يتم تسجيل محاولة فاشلة عبر طبقة الأمان.
--   - إذا كان USE_MEMORY_LIMITER = false، فإن Check ترجع
--     true دائمًا. يجب أن يتعامل الكود المستدعي مع هذا.
-- =============================================================

Config = Config or {}
OxSecure = OxSecure or {}
OxSecure.RateLimiter = OxSecure.RateLimiter or {}

local RateLimiter = OxSecure.RateLimiter
local Security = OxSecure.Security or {}
local Utils = OxSecure.Utils or {}

local rateLimitConfig = Config.RateLimit or {}
local securityConfig = Config.Security or {}
local rateLimitBucketsConfig = securityConfig.RateLimit and securityConfig.RateLimit.Buckets or {}
local rateLimitExceedAction = securityConfig.RateLimit and securityConfig.RateLimit.ExceedAction or {}

local USE_MEMORY_LIMITER = rateLimitConfig.UseMemoryLimiter ~= false
local CLEANUP_INTERVAL_SECONDS = rateLimitConfig.CleanupIntervalSeconds or 300
local DEFAULT_WINDOW_SECONDS = rateLimitConfig.WindowSeconds or 10
local DEFAULT_MAX_PER_WINDOW = rateLimitConfig.MaxPerWindow or 20

-- إصلاح 3: حد أقصى لعدد الدلاء في الذاكرة
local MAX_TOTAL_BUCKETS = rateLimitConfig.MaxTotalBuckets or 10000

-- إصلاح 2: حد أقصى لطول مفتاح المحاولة الفاشلة
local MAX_FAIL_KEY_LENGTH = 128

-- =============================================================
-- أدوات مساعدة داخلية
-- =============================================================
local function getStateRateLimit()
    local state = OxSecure.State and OxSecure.State.Runtime or nil
    return state and state.rateLimit or nil
end

local function nowMs()
    if Utils.NowMs then
        return Utils.NowMs()
    end

    if type(GetGameTimer) == 'function' then
        return GetGameTimer()
    end

    return os.time() * 1000
end

local function getBucketConfig(bucketName)
    local bucketConfig = rateLimitBucketsConfig[bucketName]

    if bucketConfig then
        return {
            windowSeconds = bucketConfig.windowSeconds or DEFAULT_WINDOW_SECONDS,
            max = bucketConfig.max or DEFAULT_MAX_PER_WINDOW
        }
    end

    local defaultBucket = rateLimitBucketsConfig['default']

    if defaultBucket then
        return {
            windowSeconds = defaultBucket.windowSeconds or DEFAULT_WINDOW_SECONDS,
            max = defaultBucket.max or DEFAULT_MAX_PER_WINDOW
        }
    end

    return {
        windowSeconds = DEFAULT_WINDOW_SECONDS,
        max = DEFAULT_MAX_PER_WINDOW
    }
end

-- إصلاح 2: تقصير مفتاح المحاولة الفاشلة إذا كان طويلاً
local function buildFailKey(identifier)
    local rawKey = 'rate_limit:' .. tostring(identifier or 'unknown')

    if #rawKey > MAX_FAIL_KEY_LENGTH then
        rawKey = rawKey:sub(1, MAX_FAIL_KEY_LENGTH)
    end

    return rawKey
end

-- =============================================================
-- إنشاء مفتاح الدلو
-- =============================================================
function RateLimiter.CreateBucketKey(identifier, bucketName)
    if Utils.CreateBucketKey then
        return Utils.CreateBucketKey({ identifier or 'global', bucketName or 'default' })
    end

    return tostring(identifier or 'global') .. ':' .. tostring(bucketName or 'default')
end

-- =============================================================
-- إصلاح 3:
-- فرض حد أقصى لعدد الدلاء.
-- إذا تجاوز العدد الحد، يتم حذف أقدم الدلاء.
-- =============================================================
local function enforceMaxBuckets(rateLimitState)
    if not rateLimitState or not rateLimitState.buckets then
        return
    end

    local count = 0

    for _ in pairs(rateLimitState.buckets) do
        count = count + 1
    end

    if count <= MAX_TOTAL_BUCKETS then
        return
    end

    -- جمع الدلاء مع أوقات إنشائها
    local bucketList = {}

    for key, bucket in pairs(rateLimitState.buckets) do
        if type(bucket) == 'table' then
            bucketList[#bucketList + 1] = {
                key = key,
                createdAt = bucket.createdAt or 0
            end
        else
            -- حذف القيم غير الصالحة فورًا
            rateLimitState.buckets[key] = nil
            count = count - 1
        end
    end

    -- ترتيب من الأقدم إلى الأحدث
    table.sort(bucketList, function(a, b)
        return a.createdAt < b.createdAt
    end)

    -- حذف الأقدم حتى نصل تحت الحد
    local toRemove = count - MAX_TOTAL_BUCKETS

    for i = 1, math.min(toRemove, #bucketList) do
        rateLimitState.buckets[bucketList[i].key] = nil
    end
end

-- =============================================================
-- تنظيف الدلاء المنتهية
-- =============================================================
function RateLimiter.CleanupExpiredBuckets()
    local rateLimitState = getStateRateLimit()

    if not rateLimitState or not rateLimitState.buckets then
        return 0
    end

    local now = nowMs()
    local removedCount = 0

    for key, bucket in pairs(rateLimitState.buckets) do
        if type(bucket) == 'table' then
            local windowMs = (bucket.windowSeconds or DEFAULT_WINDOW_SECONDS) * 1000
            local expiresAt = (bucket.createdAt or 0) + windowMs

            if expiresAt < now then
                rateLimitState.buckets[key] = nil
                removedCount = removedCount + 1
            end
        else
            rateLimitState.buckets[key] = nil
            removedCount = removedCount + 1
        end
    end

    -- إصلاح 3: فرض الحد الأقصى بعد التنظيف
    enforceMaxBuckets(rateLimitState)

    rateLimitState.lastCleanupMs = now

    return removedCount
end

-- =============================================================
-- التحقق من معدل الاستخدام
--
-- ملاحظة:
-- إذا كان USE_MEMORY_LIMITER = false، ترجع هذه الدالة
-- true دائمًا. يجب أن يتعامل الكود المستدعي مع هذا
-- السيناريو إذا أراد تعطيل الفحص كليًا.
--
-- يُرجع:
--   true  = مسموح
--   false, errorTable = مرفوض
-- =============================================================
function RateLimiter.Check(identifier, bucketName)
    if not USE_MEMORY_LIMITER then
        return true
    end

    local rateLimitState = getStateRateLimit()

    if not rateLimitState then
        -- إذا لم تكن الحالة جاهزة، نسمح بالطلب لتجنب تعطيل النظام
        return true
    end

    if not rateLimitState.buckets then
        rateLimitState.buckets = {}
    end

    local bucketConfig = getBucketConfig(bucketName)
    local bucketKey = RateLimiter.CreateBucketKey(identifier, bucketName)
    local now = nowMs()
    local windowMs = bucketConfig.windowSeconds * 1000

    local bucket = rateLimitState.buckets[bucketKey]

    -- إذا لا يوجد دلو أو انتهى وقته، ننشئ دلوًا جديدًا
    if not bucket or (bucket.createdAt + windowMs) <= now then
        rateLimitState.buckets[bucketKey] = {
            count = 1,
            createdAt = now,
            windowSeconds = bucketConfig.windowSeconds,
            max = bucketConfig.max
        }

        -- إصلاح 3: فرض الحد الأقصى عند إضافة دلو جديد
        enforceMaxBuckets(rateLimitState)

        return true
    end

    -- زيادة العدد
    bucket.count = bucket.count + 1

    -- فحص الحد الأقصى
    if bucket.count > bucketConfig.max then
        -- تسجيل محاولة فاشلة إذا كانت طبقة الأمان متاحة
        if rateLimitExceedAction.RecordFailedAttempt ~= false then
            if type(Security.RegisterFailedAttempt) == 'function' then
                local failKey = buildFailKey(identifier)
                Security.RegisterFailedAttempt(failKey, 'ERR_RATE_LIMIT')
            end
        end

        return false, {
            code = 'ERR_RATE_LIMIT',
            bucket = bucketName,
            count = bucket.count,
            max = bucketConfig.max,
            retryAfterMs = (bucket.createdAt + windowMs) - now
        }
    end

    return true
end

-- =============================================================
-- التحقق من معدل الاستخدام للاعب
-- =============================================================
function RateLimiter.CheckPlayer(serverId, bucketName)
    local identifier = 'player:' .. tostring(serverId or 0)
    return RateLimiter.Check(identifier, bucketName)
end

-- =============================================================
-- التحقق من معدل الاستخدام لنظام مربوط
-- =============================================================
function RateLimiter.CheckSystem(systemCode, bucketName)
    local identifier = 'system:' .. tostring(systemCode or 'unknown')
    return RateLimiter.Check(identifier, bucketName)
end

-- =============================================================
-- التحقق من معدل الاستخدام العام
-- =============================================================
function RateLimiter.CheckGlobal(bucketName)
    return RateLimiter.Check('global', bucketName)
end

-- =============================================================
-- الحصول على معلومات دلو
-- =============================================================
function RateLimiter.GetBucketInfo(identifier, bucketName)
    local rateLimitState = getStateRateLimit()

    if not rateLimitState or not rateLimitState.buckets then
        return nil
    end

    local bucketKey = RateLimiter.CreateBucketKey(identifier, bucketName)
    local bucket = rateLimitState.buckets[bucketKey]

    if not bucket then
        return nil
    end

    local now = nowMs()
    local windowMs = (bucket.windowSeconds or DEFAULT_WINDOW_SECONDS) * 1000
    local expiresAt = bucket.createdAt + windowMs
    local remainingMs = expiresAt - now

    if remainingMs <= 0 then
        return nil
    end

    return {
        count = bucket.count,
        max = bucket.max or DEFAULT_MAX_PER_WINDOW,
        remaining = math.max(0, (bucket.max or DEFAULT_MAX_PER_WINDOW) - bucket.count),
        remainingMs = remainingMs,
        createdAt = bucket.createdAt,
        expiresAt = expiresAt
    }
end

-- =============================================================
-- إعادة تعيين دلو
-- =============================================================
function RateLimiter.ResetBucket(identifier, bucketName)
    local rateLimitState = getStateRateLimit()

    if not rateLimitState or not rateLimitState.buckets then
        return false
    end

    local bucketKey = RateLimiter.CreateBucketKey(identifier, bucketName)

    if rateLimitState.buckets[bucketKey] then
        rateLimitState.buckets[bucketKey] = nil
        return true
    end

    return false
end

-- =============================================================
-- إعادة تعيين جميع الدلاء
-- =============================================================
function RateLimiter.ResetAllBuckets()
    local rateLimitState = getStateRateLimit()

    if not rateLimitState then
        return
    end

    rateLimitState.buckets = {}
    rateLimitState.lastCleanupMs = nowMs()
end

-- =============================================================
-- الحصول على إحصائيات
-- =============================================================
function RateLimiter.GetStats()
    local rateLimitState = getStateRateLimit()

    if not rateLimitState then
        return {
            totalBuckets = 0,
            lastCleanupMs = 0,
            maxTotalBuckets = MAX_TOTAL_BUCKETS
        }
    end

    local totalBuckets = 0

    if rateLimitState.buckets then
        for _ in pairs(rateLimitState.buckets) do
            totalBuckets = totalBuckets + 1
        end
    end

    return {
        totalBuckets = totalBuckets,
        lastCleanupMs = rateLimitState.lastCleanupMs or 0,
        maxTotalBuckets = MAX_TOTAL_BUCKETS
    }
end

-- =============================================================
-- مهمة دورية لتنظيف الدلاء المنتهية
-- =============================================================
if USE_MEMORY_LIMITER then
    local cleanupInterval = CLEANUP_INTERVAL_SECONDS

    if cleanupInterval < 10 then
        cleanupInterval = 10
    end

    CreateThread(function()
        while true do
            Wait(cleanupInterval * 1000)

            local removed = RateLimiter.CleanupExpiredBuckets()

            if removed > 0 and OxSecure.Console and type(OxSecure.Console.debug) == 'function' then
                OxSecure.Console.debug(('Rate limiter cleanup: removed %d expired buckets.'):format(removed))
            end
        end
    end)
end

-- =============================================================
-- رسالة تحميل ناجحة
-- =============================================================
if OxSecure.Console and type(OxSecure.Console.debug) == 'function' then
    OxSecure.Console.debug('server/core/rate_limiter.lua loaded')
end
