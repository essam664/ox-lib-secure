-- =============================================================
-- ox_lib_secure
-- File: fxmanifest.lua
-- Description: ملف تعريف المورد لنظام ox_lib_secure
-- =============================================================

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ox_lib_secure'
author 'ox_lib_secure Team'
version '1.0.0'
description 'Advanced security and notification system for FiveM'
repository 'https://github.com/ox-lib-secure/ox_lib_secure'

dependencies {
    'oxmysql'
}

server_scripts {
    -- الإعدادات
    'config/main.lua',

    -- النواة الأساسية
    'server/core/state.lua',
    'server/core/utils.lua',
    'server/core/security.lua',
    'server/core/validator.lua',
    'server/core/rate_limiter.lua',
    'server/core/localization.lua',
    'server/core/logger.lua',

    -- قاعدة البيانات
    'server/core/database.lua',
    'server/database/queries.lua',
    'server/database/migrations.lua',

    -- الوحدات الأساسية
    'server/core/permissions.lua',
    'server/modules/discord.lua',
    'server/core/players.lua',
    'server/core/sessions.lua',
    'server/core/systems.lua',
    'server/core/keywords.lua',
    'server/core/queue.lua',

    -- الإشعارات والأخطاء
    'server/core/notifications.lua',
    'server/core/errors.lua',
    'server/core/logs.lua',

    -- الوحدات الإضافية
    'server/modules/audit.lua',
    'server/modules/storage.lua',
    'server/modules/error_handler.lua',

    -- الأوامر
    'server/commands/admin.lua',

    -- نقطة الدخول الرئيسية
    'server/main.lua'
}

client_scripts {
    'client/core/ui.lua',
    'client/core/notifications.lua',
    'client/core/events.lua',
    'client/main.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/css/style.css',
    'html/js/app.js',
    'html/js/sounds.js'
}
