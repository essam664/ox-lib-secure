-- =============================================================
-- ox_lib_secure
-- File: client/core/events.lua
-- Description:
--   معالجة أحداث الخادم على العميل.
--
-- Notes:
--   - يستقبل الأحداث من الخادم عبر RegisterNetEvent.
--   - يعالج أحداث الإشعارات والتحديثات والأخطاء.
--   - يتكامل مع وحدة الواجهة والإشعارات.
--   - يستخدم TriggerEvent محليًا ليسمح لأي وحدة أخرى
--     بالتقاط الأحداث إذا لزم الأمر.
--   - ملاحظة: يمكن لاحقًا استبدال TriggerEvent باستدعاء
--     مباشر لدالة العرض لتقليل الحمل، لكن الطريقة الحالية
--     مقبولة وتسمح بالتقاط الحدث من وحدات أخرى.
-- =============================================================

OxSecure = OxSecure or {}
OxSecure.ClientEvents = OxSecure.ClientEvents or {}

local ClientEvents = OxSecure.ClientEvents
local UI = OxSecure.UI or {}
local ClientNotifications = OxSecure.ClientNotifications or {}

-- =============================================================
-- أدوات مساعدة داخلية
-- =============================================================
local function logClientEvent(message)
    print(('[ox_lib_secure] [CLIENT] %s'):format(message))
end

-- =============================================================
-- حدث: تحديث بيانات اللاعب
-- =============================================================
RegisterNetEvent('oxsecure:client:updatePlayerData', function(data)
    if not data then
        return
    end

    if UI.IsOpen and UI.IsOpen() then
        UI.Update({
            type = 'playerData',
            data = data
        })
    end

    logClientEvent('Player data updated.')
end)

-- =============================================================
-- حدث: عرض إشعار خطأ
-- =============================================================
RegisterNetEvent('oxsecure:client:showError', function(data)
    if not data then
        return
    end

    local errorNotification = {
        id = data.id or tostring(os.time()),
        type = 'error',
        title = data.title or 'خطأ',
        body = data.body or 'حدث خطأ غير متوقع.',
        position = data.position or 'center',
        designStyle = data.designStyle or 'error',
        durationMs = data.durationMs or 6000,
        sound = true,
        soundName = 'error'
    }

    -- ملاحظة: يمكن استبدال هذا بالاستدعاء المباشر:
    -- ClientNotifications.Show(errorNotification)
    -- لكن الطريقة الحالية تسمح لأي وحدة بالتقاط الحدث.
    TriggerEvent('oxsecure:client:showNotification', errorNotification)
end)

-- =============================================================
-- حدث: عرض إشعار نجاح
-- =============================================================
RegisterNetEvent('oxsecure:client:showSuccess', function(data)
    if not data then
        return
    end

    local successNotification = {
        id = data.id or tostring(os.time()),
        type = 'success',
        title = data.title or 'نجاح',
        body = data.body or 'تمت العملية بنجاح.',
        position = data.position or 'center',
        designStyle = data.designStyle or 'success',
        durationMs = data.durationMs or 4000,
        sound = true,
        soundName = 'success'
    }

    TriggerEvent('oxsecure:client:showNotification', successNotification)
end)

-- =============================================================
-- حدث: مسح جميع الإشعارات
-- =============================================================
RegisterNetEvent('oxsecure:client:clearNotifications', function()
    if ClientNotifications and ClientNotifications.ClearAll then
        ClientNotifications.ClearAll()
    end

    logClientEvent('All notifications cleared.')
end)

-- =============================================================
-- حدث: فتح الواجهة
-- =============================================================
RegisterNetEvent('oxsecure:client:openUI', function(data)
    if UI.Open then
        UI.Open()
    end

    logClientEvent('UI opened.')
end)

-- =============================================================
-- حدث: إغلاق الواجهة
-- =============================================================
RegisterNetEvent('oxsecure:client:closeUI', function()
    if UI.Close then
        UI.Close()
    end

    logClientEvent('UI closed.')
end)

-- =============================================================
-- حدث: تحديث إعدادات الواجهة
-- =============================================================
RegisterNetEvent('oxsecure:client:updateUIConfig', function(config)
    if not config then
        return
    end

    if UI.Update then
        UI.Update({
            type = 'uiConfig',
            data = config
        })
    end

    logClientEvent('UI config updated.')
end)

-- =============================================================
-- حدث: عرض إشعار نظام
-- =============================================================
RegisterNetEvent('oxsecure:client:showSystemMessage', function(data)
    if not data then
        return
    end

    local systemNotification = {
        id = data.id or tostring(os.time()),
        type = 'system',
        title = data.title or 'النظام',
        body = data.body or '',
        position = data.position or 'top',
        designStyle = data.designStyle or 'default',
        durationMs = data.durationMs or 5000,
        sound = data.sound ~= false,
        soundName = data.soundName or 'default'
    }

    TriggerEvent('oxsecure:client:showNotification', systemNotification)
end)

-- =============================================================
-- حدث: إعادة الاتصال بعد انقطاع
-- =============================================================
RegisterNetEvent('oxsecure:client:reconnected', function(data)
    logClientEvent('Reconnected to server.')

    local reconnectNotification = {
        id = tostring(os.time()),
        type = 'info',
        title = 'إعادة الاتصال',
        body = 'تم إعادة الاتصال بالخادم بنجاح.',
        position = 'center',
        designStyle = 'default',
        durationMs = 3000,
        sound = false
    }

    TriggerEvent('oxsecure:client:showNotification', reconnectNotification)
end)

-- =============================================================
-- حدث: إيقاف المورد (تنظيف)
-- =============================================================
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        if UI.Close then
            UI.Close()
        end

        logClientEvent('Resource stopped. Client state cleaned.')
    end
end)

-- =============================================================
-- رسالة تحميل ناجحة
-- =============================================================
print('[ox_lib_secure] client/core/events.lua loaded.')
