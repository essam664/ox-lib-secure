-- =============================================================
-- ox_lib_secure
-- File: fxmanifest.lua
-- Description:
--   ملف تعريف المورد الخاص بنظام ox_lib_secure
--   يحدد ملفات السيرفر والكلاينت والواجهة واعتماديات المورد.
--
-- Notes:
--   - ملفات الأمان تُحمّل من جهة السيرفر فقط.
--   - لا يتم إرسال ملفات الإعدادات الحساسة إلى الكلاينت.
--   - الواجهة تعتمد على NUI داخل مجلد html.
--   - المورد يعتمد على oxmysql للتعامل مع قاعدة البيانات.
--   - لا تشغل المورد قبل إنشاء جميع الملفات المذكورة في files.
-- =============================================================

fx_version 'cerulean'
game 'gta5'

name 'ox_lib_secure'
author 'ESSAM'
version '1.0.0'
description 'Secure Arabic Glass UI notification and logging system for FiveM'

lua54 'yes'

-- =============================================================
-- الاعتماديات
-- =============================================================
dependencies {
    'oxmysql'
}

-- =============================================================
-- ملفات مشتركة
-- لا نضع هنا أي ملفات تحتوي على أسرار أو إعدادات حساسة.
-- =============================================================
shared_scripts {
    -- إذا أردنا لاحقًا الاعتماد على مكتبة ox_lib الرسمية، يمكن إضافة:
    -- '@ox_lib/init.lua'
}

-- =============================================================
-- ملفات السيرفر
-- ترتيب التحميل مهم.
-- =============================================================
server_scripts {
    'config/main.lua',
    'config/theme.lua',
    'config/permissions.lua',
    'config/security.lua',
    'config/messages.ar.lua',
    'config/errors.ar.lua',

    'server/main.lua'
}

-- =============================================================
-- ملفات الكلاينت
-- =============================================================
client_scripts {
    'client/main.lua'
}

-- =============================================================
-- ملفات الواجهة
-- =============================================================
files {
    'html/index.html',

    'html/css/reset.css',
    'html/css/tokens.css',
    'html/css/rtl.css',
    'html/css/glass.css',
    'html/css/animations.css',
    'html/css/notifications.css',
    'html/css/errors.css',
    'html/css/logs.css',
    'html/css/app.css',

    'html/js/main.js',
    'html/js/store.js',
    'html/js/bus.js',
    'html/js/security.js',
    'html/js/sanitizer.js',
    'html/js/i18n.js',

    'html/js/themes/purple_glass.js',

    'html/js/components/App.js',
    'html/js/components/NotificationStack.js',
    'html/js/components/GlassMessage.js',
    'html/js/components/CriticalRedMessage.js',
    'html/js/components/ErrorModal.js',
    'html/js/components/LogsPanel.js',
    'html/js/components/PermissionDenied.js',
    'html/js/components/LoadingScreen.js',
    'html/js/components/DebugOverlay.js',

    'html/js/locales/ar.js',
    'html/js/locales/en.js',

    'html/js/utils/sound.js',

    -- ملفات الصوت الحقيقية
    -- يجب وضع هذه الملفات فعليًا داخل:
    -- html/assets/sounds/
    'html/assets/sounds/notify.ogg',
    'html/assets/sounds/success.ogg',
    'html/assets/sounds/warning.ogg',
    'html/assets/sounds/error.ogg',
    'html/assets/sounds/critical.ogg'
}

-- =============================================================
-- صفحة الواجهة الرئيسية
-- =============================================================
ui_page 'html/index.html'
