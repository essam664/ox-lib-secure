-- =============================================================
-- ox_lib_secure
-- File: server/core/localization.lua
-- Description:
--   طبقة الترجمة والتعريب لنظام ox_lib_secure.
--
-- Notes:
--   - اللغة الافتراضية يتم تحديدها من Config.Language.
--   - الرسائل يتم جلبها من Config.Localization.
--   - يتم دعم استبدال المتغيرات عبر {placeholders}.
--   - أي رسالة مفقودة يتم استبدالها برسالة بديلة آمنة.
-- =============================================================

Config = Config or {}
OxSecure = OxSecure or {}
OxSecure.Localization = OxSecure.Localization or {}

local Localization = OxSecure.Localization
local Utils = OxSecure.Utils or {}

local currentLanguage = Config.Language or 'ar'

-- =============================================================
-- أدوات مساعدة داخلية
-- =============================================================
local function getLanguageData()
    local localization = Config.Localization or {}
    return localization[currentLanguage] or {}
end

local function getMessages()
    local langData = getLanguageData()
    return langData.messages or {}
end

local function getErrors()
    local langData = getLanguageData()
    return langData.errors or {}
end

-- =============================================================
-- التحقق من وجود اللغة قبل تغييرها.
-- =============================================================
local function languageExists(language)
    if type(language) ~= 'string' or language == '' then
        return false
    end

    local localization = Config.Localization or {}
    return localization[language] ~= nil
end

-- =============================================================
-- استبدال المتغيرات داخل نص
--
-- النمط '{([%w_]+)}' يدعم المفاتيح البسيطة فقط،
-- وهذا متوافق مع الاستخدام الحالي.
-- =============================================================
local function replacePlaceholders(template, data)
    if type(template) ~= 'string' then
        return tostring(template or '')
    end

    if type(data) ~= 'table' then
        return template
    end

    if Utils.ReplacePlaceholders then
        return Utils.ReplacePlaceholders(template, data)
    end

    -- بديل بسيط إذا لم تكن Utils متاحة
    local result = template:gsub('{([%w_]+)}', function(key)
        local value = data[key]

        if value == nil then
            return ''
        end

        return tostring(value)
    end)

    return result
end

-- =============================================================
-- تطبيع رمز الخطأ
--
-- يقبل فقط القيم النصية غير الفارغة.
-- أي نوع آخر (جدول، رقم، nil، boolean) يُعتبر غير صالح
-- ويُرجع nil حتى يتم استخدام البديل.
-- =============================================================
local function normalizeErrorCode(errorCode)
    if type(errorCode) == 'string' and errorCode ~= '' then
        return errorCode
    end

    return nil
end

-- =============================================================
-- الحصول على اللغة الحالية
-- =============================================================
function Localization.GetLanguage()
    return currentLanguage
end

-- =============================================================
-- تغيير اللغة
-- =============================================================
function Localization.SetLanguage(language)
    if type(language) ~= 'string' or language == '' then
        return false
    end

    if not languageExists(language) then
        return false
    end

    currentLanguage = language
    return true
end

-- =============================================================
-- الحصول على اللغات المتاحة
-- =============================================================
function Localization.GetAvailableLanguages()
    local localization = Config.Localization or {}
    local languages = {}

    for lang in pairs(localization) do
        languages[#languages + 1] = lang
    end

    return languages
end

-- =============================================================
-- جلب رسالة عامة
--
-- المسار يكون على شكل:
--   'generic.success'
--   'permission.denied'
--   'logs.empty'
-- =============================================================
function Localization.GetMessage(path, data)
    if type(path) ~= 'string' or path == '' then
        return ''
    end

    local messages = getMessages()

    -- تقسيم المسار
    local parts = {}

    for part in path:gmatch('[^.]+') do
        parts[#parts + 1] = part
    end

    -- البحث في الجدول
    local current = messages

    for _, part in ipairs(parts) do
        if type(current) ~= 'table' then
            return ''
        end

        current = current[part]
    end

    if type(current) ~= 'string' then
        return ''
    end

    return replacePlaceholders(current, data)
end

-- =============================================================
-- جلب رسالة عامة مع رسالة بديلة
-- =============================================================
function Localization.GetMessageOr(path, fallback, data)
    local message = Localization.GetMessage(path, data)

    if message == '' then
        if type(fallback) == 'string' then
            return replacePlaceholders(fallback, data)
        end

        return ''
    end

    return message
end

-- =============================================================
-- جلب عنوان نوع الرسالة
-- =============================================================
function Localization.GetTitle(notificationType)
    local messages = getMessages()
    local titles = messages.titles or {}

    if type(notificationType) == 'string' and titles[notificationType] then
        return titles[notificationType]
    end

    return titles.system or 'النظام'
end

-- =============================================================
-- جلب خطأ من الكتالوج
--
-- يقبل فقط رمز خطأ نصي.
-- أي نوع آخر يُعامل كخطأ غير معروف.
--
-- يُرجع جدول يحتوي على:
--   code, title, body, severity, designStyle, durationMs, category
-- =============================================================
function Localization.GetError(errorCode, data)
    local errors = getErrors()
    local catalog = errors.catalog or {}
    local fallback = errors.fallback or {}

    local normalizedCode = normalizeErrorCode(errorCode)

    local errorEntry = nil
    local resolvedCode = normalizedCode

    if normalizedCode and catalog[normalizedCode] then
        errorEntry = catalog[normalizedCode]
    else
        errorEntry = fallback

        if fallback.code then
            resolvedCode = fallback.code
        end
    end

    if type(errorEntry) ~= 'table' then
        return {
            code = 'ERR_UNKNOWN',
            title = 'خطأ غير معروف',
            body = 'حدث خطأ غير متوقع في النظام.',
            severity = 'error',
            designStyle = 'error',
            durationMs = 6000,
            category = 'general'
        }
    end

    -- استبدال المتغيرات في العنوان والجسم
    local title = errorEntry.title or 'خطأ'
    local body = errorEntry.body or 'حدث خطأ غير متوقع.'

    if data then
        title = replacePlaceholders(title, data)
        body = replacePlaceholders(body, data)
    end

    return {
        code = resolvedCode or 'ERR_UNKNOWN',
        title = title,
        body = body,
        severity = errorEntry.severity or 'error',
        designStyle = errorEntry.designStyle or 'error',
        durationMs = errorEntry.durationMs or 6000,
        category = errorEntry.category or 'general'
    }
end

-- =============================================================
-- جلب عنوان خطأ فقط
-- =============================================================
function Localization.GetErrorTitle(errorCode, data)
    local errorInfo = Localization.GetError(errorCode, data)
    return errorInfo.title
end

-- =============================================================
-- جلب جسم خطأ فقط
-- =============================================================
function Localization.GetErrorBody(errorCode, data)
    local errorInfo = Localization.GetError(errorCode, data)
    return errorInfo.body
end

-- =============================================================
-- جلب تصميم خطأ
-- =============================================================
function Localization.GetErrorDesign(errorCode)
    local errors = getErrors()
    local catalog = errors.catalog or {}
    local fallback = errors.fallback or {}

    local normalizedCode = normalizeErrorCode(errorCode)

    local errorEntry = nil

    if normalizedCode and catalog[normalizedCode] then
        errorEntry = catalog[normalizedCode]
    else
        errorEntry = fallback
    end

    if type(errorEntry) ~= 'table' then
        return 'error'
    end

    return errorEntry.designStyle or 'error'
end

-- =============================================================
-- جلب درجة خطورة خطأ
-- =============================================================
function Localization.GetErrorSeverity(errorCode)
    local errors = getErrors()
    local catalog = errors.catalog or {}
    local fallback = errors.fallback or {}

    local normalizedCode = normalizeErrorCode(errorCode)

    local errorEntry = nil

    if normalizedCode and catalog[normalizedCode] then
        errorEntry = catalog[normalizedCode]
    else
        errorEntry = fallback
    end

    if type(errorEntry) ~= 'table' then
        return 'error'
    end

    return errorEntry.severity or 'error'
end

-- =============================================================
-- جلب التصنيفات المسموحة للأخطاء
-- =============================================================
function Localization.GetAllowedErrorCategories()
    local errors = getErrors()
    return errors.allowedCategories or {}
end

-- =============================================================
-- التحقق من صحة تصنيف خطأ
-- =============================================================
function Localization.IsValidErrorCategory(category)
    if type(category) ~= 'string' then
        return false
    end

    local allowedCategories = Localization.GetAllowedErrorCategories()

    if Utils.Contains then
        return Utils.Contains(allowedCategories, category)
    end

    for _, allowedCategory in ipairs(allowedCategories) do
        if allowedCategory == category then
            return true
        end
    end

    return false
end

-- =============================================================
-- جلب نص من قسم معين
-- =============================================================
function Localization.GetSection(sectionName)
    local messages = getMessages()

    if type(sectionName) == 'string' and type(messages[sectionName]) == 'table' then
        return messages[sectionName]
    end

    return {}
end

-- =============================================================
-- جلب جميع الرسائل
-- =============================================================
function Localization.GetAllMessages()
    return getMessages()
end

-- =============================================================
-- جلب جميع الأخطاء
-- =============================================================
function Localization.GetAllErrors()
    return getErrors()
end

-- =============================================================
-- رسالة تحميل ناجحة
-- =============================================================
if OxSecure.Console and type(OxSecure.Console.debug) == 'function' then
    OxSecure.Console.debug('server/core/localization.lua loaded')
end
