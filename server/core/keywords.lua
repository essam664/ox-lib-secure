-- =============================================================
-- ox_lib_secure
-- File: server/core/keywords.lua
-- Description:
--   طبقة إدارة الكلمات المفتاحية لنظام ox_lib_secure.
--
-- Notes:
--   - يتم تخزين الكلمات المفتاحية في قاعدة البيانات.
--   - يتم مطابقة الكلمات في الرسائل بأنماط مختلفة.
--   - يتم ترتيب الكلمات حسب الأولوية.
--   - يتم استخدام الكاش لتسريع المطابقة.
--   - قفل بسيط يمنع التحميل المتزامن للكاش.
-- =============================================================

Config = Config or {}
OxSecure = OxSecure or {}
OxSecure.Keywords = OxSecure.Keywords or {}

local Keywords = OxSecure.Keywords
local Database = OxSecure.Database or {}
local Logger = OxSecure.Logger or {}
local Utils = OxSecure.Utils or {}
local StateManager = OxSecure.StateManager or {}

-- إصلاح 2: علم لمنع التحميل المتزامن
local isLoadingCache = false

-- إصلاح 3: إعدادات إعادة المحاولة
local CACHE_RETRY_INTERVAL_MS = 10000
local CACHE_MAX_RETRIES = 10

-- =============================================================
-- أدوات مساعدة داخلية
-- =============================================================
local function getKeywordsCache()
    local state = StateManager.Get and StateManager.Get() or nil
    return state and state.keywords or nil
end

local function logKeywordEvent(message, options)
    if Logger.Info then
        Logger.Info(message, options or {
            category = 'keyword',
            eventCode = 'keyword_event'
        })
    end
end

local function logKeywordError(message, options)
    if Logger.Error then
        Logger.Error(message, options or {
            category = 'keyword',
            eventCode = 'keyword_error'
        })
    end
end

-- =============================================================
-- تحميل الكلمات المفتاحية النشطة في الكاش
--
-- إصلاح 2: قفل بسيط يمنع التحميل المتزامن.
-- =============================================================
function Keywords.LoadCache(callback)
    -- إصلاح 2: منع التحميل المتزامن
    if isLoadingCache then
        if callback then callback(false, 'Cache is already loading') end
        return
    end

    isLoadingCache = true

    local selectQuery = ('SELECT * FROM %s WHERE is_active = 1 ORDER BY priority DESC'):format(Database.GetTableName('keywords'))

    Database.Execute(selectQuery, {}, function(results, err)
        isLoadingCache = false

        if err then
            logKeywordError(('Failed to load keywords cache: %s'):format(tostring(err)))
            if callback then callback(false, err) end
            return
        end

        local cache = getKeywordsCache()

        if cache then
            cache.activeKeywords = {}

            if type(results) == 'table' then
                for _, keyword in ipairs(results) do
                    cache.activeKeywords[#cache.activeKeywords + 1] = keyword
                end
            end

            cache.lastLoadedAt = os.time()
        end

        logKeywordEvent(('Keywords cache loaded: %d active keywords'):format(#(cache and cache.activeKeywords or {})))

        if callback then callback(true, nil) end
    end)
end

-- =============================================================
-- إضافة كلمة مفتاحية
-- =============================================================
function Keywords.AddKeyword(keyword, options, callback)
    options = options or {}

    if type(keyword) ~= 'string' or keyword == '' then
        if callback then callback(false, { code = 'ERR_INVALID_FIELD' }) end
        return
    end

    local matchType = options.matchType or 'contains'
    local validMatchTypes = { 'contains', 'exact', 'starts_with', 'ends_with' }
    local isValidMatchType = false

    for _, validType in ipairs(validMatchTypes) do
        if matchType == validType then
            isValidMatchType = true
            break
        end
    end

    if not isValidMatchType then
        matchType = 'contains'
    end

    local insertQuery = ('INSERT INTO %s (keyword, match_type, design_style, title_ar, body_ar, sound_name, duration_ms, priority, is_active, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, NOW())'):format(Database.GetTableName('keywords'))

    Database.Insert(insertQuery, {
        keyword,
        matchType,
        options.designStyle,
        options.titleAr,
        options.bodyAr,
        options.soundName,
        options.durationMs,
        options.priority or 0
    }, function(insertId, err)
        if err then
            logKeywordError(('Failed to add keyword: %s'):format(tostring(err)))
            if callback then callback(false, { code = 'ERR_DB_INSERT_FAILED', details = err }) end
            return
        end

        Keywords.LoadCache()

        logKeywordEvent(('Keyword added: %s (ID: %d)'):format(keyword, insertId))

        if callback then callback(true, { id = insertId, keyword = keyword }) end
    end)
end

-- =============================================================
-- تحديث كلمة مفتاحية
-- =============================================================
function Keywords.UpdateKeyword(keywordId, updates, callback)
    if not keywordId or keywordId <= 0 then
        if callback then callback(false, { code = 'ERR_INVALID_FIELD' }) end
        return
    end

    if type(updates) ~= 'table' then
        if callback then callback(false, { code = 'ERR_INVALID_PAYLOAD' }) end
        return
    end

    local setClauses = {}
    local params = {}

    if updates.keyword ~= nil then
        setClauses[#setClauses + 1] = 'keyword = ?'
        params[#params + 1] = updates.keyword
    end

    if updates.matchType ~= nil then
        setClauses[#setClauses + 1] = 'match_type = ?'
        params[#params + 1] = updates.matchType
    end

    if updates.designStyle ~= nil then
        setClauses[#setClauses + 1] = 'design_style = ?'
        params[#params + 1] = updates.designStyle
    end

    if updates.titleAr ~= nil then
        setClauses[#setClauses + 1] = 'title_ar = ?'
        params[#params + 1] = updates.titleAr
    end

    if updates.bodyAr ~= nil then
        setClauses[#setClauses + 1] = 'body_ar = ?'
        params[#params + 1] = updates.bodyAr
    end

    if updates.soundName ~= nil then
        setClauses[#setClauses + 1] = 'sound_name = ?'
        params[#params + 1] = updates.soundName
    end

    if updates.durationMs ~= nil then
        setClauses[#setClauses + 1] = 'duration_ms = ?'
        params[#params + 1] = updates.durationMs
    end

    if updates.priority ~= nil then
        setClauses[#setClauses + 1] = 'priority = ?'
        params[#params + 1] = updates.priority
    end

    if updates.isActive ~= nil then
        setClauses[#setClauses + 1] = 'is_active = ?'
        params[#params + 1] = updates.isActive and 1 or 0
    end

    if #setClauses == 0 then
        if callback then callback(false, { code = 'ERR_MISSING_FIELD' }) end
        return
    end

    params[#params + 1] = keywordId

    local updateQuery = ('UPDATE %s SET %s WHERE id = ?'):format(Database.GetTableName('keywords'), table.concat(setClauses, ', '))

    Database.Execute(updateQuery, params, function(_, err)
        if err then
            logKeywordError(('Failed to update keyword %d: %s'):format(keywordId, tostring(err)))
            if callback then callback(false, { code = 'ERR_DB_QUERY_FAILED', details = err }) end
            return
        end

        Keywords.LoadCache()

        if callback then callback(true, nil) end
    end)
end

-- =============================================================
-- حذف كلمة مفتاحية
-- =============================================================
function Keywords.DeleteKeyword(keywordId, callback)
    if not keywordId or keywordId <= 0 then
        if callback then callback(false, { code = 'ERR_INVALID_FIELD' }) end
        return
    end

    local deleteQuery = ('DELETE FROM %s WHERE id = ?'):format(Database.GetTableName('keywords'))

    Database.Execute(deleteQuery, { keywordId }, function(_, err)
        if err then
            logKeywordError(('Failed to delete keyword %d: %s'):format(keywordId, tostring(err)))
            if callback then callback(false, { code = 'ERR_DB_QUERY_FAILED', details = err }) end
            return
        end

        Keywords.LoadCache()

        logKeywordEvent(('Keyword deleted: ID %d'):format(keywordId))

        if callback then callback(true, nil) end
    end)
end

-- =============================================================
-- تفعيل / تعطيل كلمة مفتاحية
-- =============================================================
function Keywords.SetActive(keywordId, isActive, callback)
    Keywords.UpdateKeyword(keywordId, { isActive = isActive }, callback)
end

-- =============================================================
-- جلب كلمة مفتاحية
-- =============================================================
function Keywords.GetKeyword(keywordId, callback)
    if not keywordId or keywordId <= 0 then
        if callback then callback(nil, 'Invalid keyword ID') end
        return
    end

    local selectQuery = ('SELECT * FROM %s WHERE id = ?'):format(Database.GetTableName('keywords'))

    Database.Single(selectQuery, { keywordId }, function(result, err)
        if err then
            if callback then callback(nil, err) end
            return
        end

        if callback then callback(result, nil) end
    end)
end

-- =============================================================
-- جلب جميع الكلمات المفتاحية
-- =============================================================
function Keywords.GetAllKeywords(callback)
    local selectQuery = ('SELECT * FROM %s ORDER BY priority DESC, created_at DESC'):format(Database.GetTableName('keywords'))

    Database.Execute(selectQuery, {}, function(results, err)
        if err then
            if callback then callback({}, err) end
            return
        end

        if callback then callback(results or {}, nil) end
    end)
end

-- =============================================================
-- جلب الكلمات المفتاحية النشطة
--
-- إصلاح 2: التحقق من علم التحميل قبل البدء.
-- =============================================================
function Keywords.GetActiveKeywords(callback)
    local cache = getKeywordsCache()

    if cache and cache.activeKeywords and cache.lastLoadedAt then
        if os.time() - cache.lastLoadedAt < 60 then
            if callback then callback(cache.activeKeywords, nil) end
            return
        end
    end

    -- إصلاح 2: التحقق من عدم وجود تحميل جارٍ
    if isLoadingCache then
        -- نعيد الكاش الحالي حتى لو كان قديمًا
        if cache and cache.activeKeywords then
            if callback then callback(cache.activeKeywords, nil) end
        else
            if callback then callback({}, nil) end
        end
        return
    end

    Keywords.LoadCache(function(ok)
        if ok then
            local updatedCache = getKeywordsCache()
            if callback then callback(updatedCache and updatedCache.activeKeywords or {}, nil) end
        else
            if callback then callback({}, nil) end
        end
    end)
end

-- =============================================================
-- مطابقة كلمة مفتاحية مع نص
-- =============================================================
local function matchKeyword(keywordEntry, text)
    if not keywordEntry or not text then
        return false
    end

    local keyword = keywordEntry.keyword
    local matchType = keywordEntry.match_type or 'contains'

    if type(keyword) ~= 'string' or type(text) ~= 'string' then
        return false
    end

    local lowerKeyword = keyword:lower()
    local lowerText = text:lower()

    if matchType == 'contains' then
        return lowerText:find(lowerKeyword, 1, true) ~= nil
    elseif matchType == 'exact' then
        return lowerText == lowerKeyword
    elseif matchType == 'starts_with' then
        return lowerText:sub(1, #lowerKeyword) == lowerKeyword
    elseif matchType == 'ends_with' then
        return lowerText:sub(-#lowerKeyword) == lowerKeyword
    end

    return false
end

-- =============================================================
-- البحث عن كلمات مفتاحية مطابقة في نص
-- =============================================================
function Keywords.MatchText(text, callback)
    if type(text) ~= 'string' or text == '' then
        if callback then callback({}) end
        return
    end

    Keywords.GetActiveKeywords(function(activeKeywords)
        local matches = {}

        for _, keywordEntry in ipairs(activeKeywords) do
            if matchKeyword(keywordEntry, text) then
                matches[#matches + 1] = keywordEntry
            end
        end

        table.sort(matches, function(a, b)
            return (a.priority or 0) > (b.priority or 0)
        end)

        if callback then callback(matches) end
    end)
end

-- =============================================================
-- التحقق من وجود كلمة مفتاحية في نص
-- =============================================================
function Keywords.HasMatch(text, callback)
    Keywords.MatchText(text, function(matches)
        if callback then callback(#matches > 0, matches) end
    end)
end

-- =============================================================
-- الحصول على أول كلمة مفتاحية مطابقة
-- =============================================================
function Keywords.GetFirstMatch(text, callback)
    Keywords.MatchText(text, function(matches)
        if #matches > 0 then
            if callback then callback(matches[1]) end
        else
            if callback then callback(nil) end
        end
    end)
end

-- =============================================================
-- إصلاح 3: تحميل الكاش عند بدء المورد مع إعادة محاولة
-- دورية بدلاً من محاولة واحدة.
-- =============================================================
local function tryLoadCacheWithRetry(attemptNumber)
    if Database.IsReady() then
        Keywords.LoadCache(function(ok, err)
            if not ok then
                logKeywordError(('Initial cache load failed (attempt %d): %s'):format(attemptNumber, tostring(err)))
            end
        end)
        return
    end

    if attemptNumber >= CACHE_MAX_RETRIES then
        logKeywordError(('Giving up on loading keywords cache after %d attempts'):format(CACHE_MAX_RETRIES))
        return
    end

    SetTimeout(CACHE_RETRY_INTERVAL_MS, function()
        tryLoadCacheWithRetry(attemptNumber + 1)
    end)
end

tryLoadCacheWithRetry(1)

-- =============================================================
-- رسالة تحميل ناجحة
-- =============================================================
if Logger.Debug then
    Logger.Debug('server/core/keywords.lua loaded')
elseif OxSecure.Console and type(OxSecure.Console.debug) == 'function' then
    OxSecure.Console.debug('server/core/keywords.lua loaded')
end
