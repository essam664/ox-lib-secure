-- =============================================================
-- ox_lib_secure
-- File: client/main.lua
-- Description:
--   نقطة الدخول الرئيسية للعميل.
--   يدير تهيئة الوحدات ومعالجة الأحداث العامة.
--
-- Notes:
--   - يتم تحميل الوحدات بالترتيب عبر fxmanifest.lua.
--   - هذا الملف يدير التهيئة النهائية بعد تحميل كل الوحدات.
--   - يعالج أحداث بدء وإيقاف المورد.
-- =============================================================

OxSecure = OxSecure or {}
OxSecure.Client = OxSecure.Client or {}

local Client = OxSecure.Client
local UI = OxSecure.UI or {}
local ClientNotifications = OxSecure.ClientNotifications or {}
local ClientEvents = OxSecure.ClientEvents or {}

-- حالة التهيئة
local isInitialized = false

-- =============================================================
-- أدوات مساعدة داخلية
-- =============================================================
local function logClientMain(message)
    print(('[ox_lib_secure] [CLIENT MAIN] %s'):format(message))
end

-- =============================================================
-- تهيئة النظام على العميل
-- =============================================================
local function initializeClient()
    if isInitialized then
        return
    end

    isInitialized = true

    logClientMain('Initializing client...')

    -- تهيئة الواجهة
    if UI.Initialize then
        UI.Initialize()
    end

    logClientMain('Client initialization complete.')
    logClientMain('========================================')
end

-- =============================================================
-- حدث: بدء المورد
-- =============================================================
AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    logClientMain('========================================')
    logClientMain('  ox_lib_secure Client v' .. (Config and Config.Version or '1.0.0'))
    logClientMain('========================================')

    -- انتظار قصير للتأكد من تحميل جميع الوحدات
    Wait(500)

    initializeClient()
end)

-- =============================================================
-- حدث: إيقاف المورد
-- =============================================================
AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    logClientMain('ox_lib_secure client is shutting down...')

    -- إغلاق الواجهة إذا كانت مفتوحة
    if UI.Close then
        UI.Close()
    end

    -- مسح جميع الإشعارات
    if ClientNotifications and ClientNotifications.ClearAll then
        ClientNotifications.ClearAll()
    end

    logClientMain('Client shutdown complete.')
end)

-- =============================================================
-- حدث: جاهزية اللاعب
-- =============================================================
AddEventHandler('playerSpawned', function()
    if not isInitialized then
        initializeClient()
    end

    logClientMain('Player spawned. Client is ready.')
end)

-- =============================================================
-- معالجة مفاتيح الاختصار (اختياري)
-- =============================================================
-- يمكن إضافة مفاتيح اختصار هنا لاحقًا
-- مثال: فتح/إغلاق الواجهة بمفتاح معين

-- =============================================================
-- رسالة تحميل ناجحة
-- =============================================================
logClientMain('client/main.lua loaded successfully.')
