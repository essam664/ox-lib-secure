-- =============================================================
-- ox_lib_secure
-- File: client/core/ui.lua
-- Description:
--   إدارة واجهة المستخدم على العميل.
--   يتحكم في فتح وإغلاق الواجهة وإرسال البيانات.
--
-- Notes:
--   - يتم التواصل مع الواجهة عبر SendNUIMessage.
--   - يتم استقبال الأوامر من الواجهة عبر RegisterNUICallback.
--   - يتم التحقق من جاهزية الواجهة قبل الإرسال.
--   - يتم تأجيل SetNuiFocus حتى يتم إرسال الرسالة فعليًا.
--   - يتم تحديد حد أقصى لطابور الرسائل المعلقة.
--   - عند تجاوز الحد الأقصى، تُحذف أقدم رسالة بدون
--     تنفيذ onSent الخاص بها. هذا سلوك مقصود لمنع
--     تنفيذ إجراءات قديمة (مثل SetNuiFocus لواجهة
--     لم تعد ذات صلة).
-- =============================================================

OxSecure = OxSecure or {}
OxSecure.UI = OxSecure.UI or {}

local UI = OxSecure.UI

-- حالة الواجهة
local isUIOpen = false
local isReady = false

-- طابور الرسائل المعلقة مع إجراءات ما بعد الإرسال
local pendingMessages = {}
local MAX_PENDING_MESSAGES = 50

-- =============================================================
-- أدوات مساعدة داخلية
-- =============================================================
local function sendToNUI(data, onSent)
    if not isReady then
        -- التحقق من حجم الطابور
        if #pendingMessages >= MAX_PENDING_MESSAGES then
            -- ملاحظة: تُحذف أقدم رسالة بدون تنفيذ onSent.
            -- هذا مقصود لمنع تنفيذ إجراءات قديمة.
            table.remove(pendingMessages, 1)
        end

        -- تخزين الرسالة مع الإجراء المؤجل
        pendingMessages[#pendingMessages + 1] = {
            data = data,
            onSent = onSent
        }
        return
    end

    SendNUIMessage(data)

    -- تنفيذ الإجراء المؤجل بعد الإرسال الفعلي
    if onSent then
        onSent()
    end
end

-- تفريغ الرسائل المعلقة عند جاهزية الواجهة
local function flushPendingMessages()
    for _, entry in ipairs(pendingMessages) do
        SendNUIMessage(entry.data)

        -- تنفيذ الإجراء المؤجل بعد الإرسال الفعلي
        if entry.onSent then
            entry.onSent()
        end
    end

    pendingMessages = {}
end

-- =============================================================
-- تهيئة الواجهة
-- =============================================================
function UI.Initialize()
    print('[ox_lib_secure] Client UI initialized.')
end

-- =============================================================
-- التحقق من أن الواجهة مفتوحة
-- =============================================================
function UI.IsOpen()
    return isUIOpen
end

-- =============================================================
-- التحقق من أن الواجهة جاهزة
-- =============================================================
function UI.IsReady()
    return isReady
end

-- =============================================================
-- فتح الواجهة الرئيسية
-- =============================================================
function UI.Open()
    if isUIOpen then
        return
    end

    isUIOpen = true

    sendToNUI({
        action = 'openUI',
        timestamp = os.time()
    }, function()
        SetNuiFocus(true, true)
    end)
end

-- =============================================================
-- إغلاق الواجهة الرئيسية
-- =============================================================
function UI.Close()
    if not isUIOpen then
        return
    end

    isUIOpen = false

    sendToNUI({
        action = 'closeUI',
        timestamp = os.time()
    }, function()
        SetNuiFocus(false, false)
    end)
end

-- =============================================================
-- تحديث بيانات الواجهة
-- =============================================================
function UI.Update(data)
    if not data then
        return
    end

    sendToNUI({
        action = 'updateData',
        data = data
    })
end

-- =============================================================
-- إخفاء الواجهة مؤقتًا (بدون إغلاق)
-- =============================================================
function UI.Hide()
    sendToNUI({
        action = 'hideUI'
    })
end

-- =============================================================
-- إظهار الواجهة بعد الإخفاء
-- =============================================================
function UI.Show()
    sendToNUI({
        action = 'showUI'
    })
end

-- =============================================================
-- استقبال أوامر من الواجهة (NUI Callbacks)
-- =============================================================
RegisterNUICallback('uiReady', function(data, cb)
    isReady = true

    -- تفريغ الرسائل المعلقة
    flushPendingMessages()

    print('[ox_lib_secure] NUI is ready.')
    cb('ok')
end)

RegisterNUICallback('closeUI', function(data, cb)
    UI.Close()
    cb('ok')
end)

RegisterNUICallback('uiAction', function(data, cb)
    local action = data.action

    if action == 'close' then
        UI.Close()
    end

    cb('ok')
end)

-- =============================================================
-- تهيئة عند تحميل المورد
-- =============================================================
CreateThread(function()
    Wait(500)
    UI.Initialize()
end)
