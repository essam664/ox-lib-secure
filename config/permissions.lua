-- =============================================================
-- ox_lib_secure
-- File: config/permissions.lua
-- Description:
--   إعدادات الصلاحيات الخاصة بنظام ox_lib_secure.
--   هذا الملف يُحمّل من جهة السيرفر فقط.
--
-- Notes:
--   - الصلاحيات النهائية يجب أن تُحسم من السيرفر فقط.
--   - لا يتم الاعتماد على أي صلاحية قادمة من الكلاينت.
--   - يمكن لاحقًا تجاوز أو إضافة صلاحيات من قاعدة البيانات.
-- =============================================================

Config = Config or {}

Config.Permissions = {
    Enabled = true,

    -- =============================================================
    -- إعدادات عامة للصلاحيات
    -- =============================================================
    RequireDiscordIdentifier = true,
    DiscordIdentifierPrefix = 'discord:',
    AllowWildcard = true,

    -- أصحاب صلاحية المالك
    -- يتم إعطاؤهم دور owner تلقائيًا إذا لم يكن لديهم دور آخر.
    Owners = {
        '1249662830568013825'
    },

    DefaultRoleForOwners = 'owner',
    DefaultRoleForAdmins = 'admin',
    DefaultRoleForModerators = 'moderator',

    -- =============================================================
    -- التخزين المؤقت للصلاحيات
    -- =============================================================
    Cache = {
        Enabled = true,
        TTLSeconds = 60,
        MaxEntries = 500
    },

    -- =============================================================
    -- التدقيق وتسجيل المحاولات
    -- =============================================================
    Audit = {
        LogGranted = false,
        LogDenied = true,
        LogRoleChanges = true,
        LogPermissionChanges = true
    },

    -- =============================================================
    -- سلوك رفض الوصول
    -- =============================================================
    Deny = {
        ErrorCode = 'ERR_PERMISSION_DENIED',
        NotifyPlayer = true,
        LogToDatabase = true,
        LogToConsole = true,
        RecordFailedAttempt = true
    },

    -- =============================================================
    -- قائمة الصلاحيات المتاحة
    -- =============================================================
    PermissionsList = {
        ['ui.open'] = {
            labelAr = 'فتح لوحة النظام',
            category = 'ui',
            description = 'يسمح بفتح لوحة النظام الأساسية'
        },

        ['logs.read'] = {
            labelAr = 'قراءة اللوجات',
            category = 'logs',
            description = 'يسمح بعرض اللوجات داخل اللوحة'
        },

        ['logs.delete'] = {
            labelAr = 'حذف اللوجات',
            category = 'logs',
            description = 'يسمح بحذف اللوجات'
        },

        ['logs.export'] = {
            labelAr = 'تصدير اللوجات',
            category = 'logs',
            description = 'يسمح بتصدير اللوجات'
        },

        ['players.block'] = {
            labelAr = 'حظر اللاعبين',
            category = 'players',
            description = 'يسمح بحظر اللاعبين'
        },

        ['players.unblock'] = {
            labelAr = 'فك حظر اللاعبين',
            category = 'players',
            description = 'يسمح بفك حظر اللاعبين'
        },

        ['systems.manage'] = {
            labelAr = 'إدارة الأنظمة',
            category = 'systems',
            description = 'يسمح بإدارة الأنظمة المربوطة'
        },

        ['tokens.manage'] = {
            labelAr = 'إدارة التوكنات',
            category = 'tokens',
            description = 'يسمح بإدارة توكنات الأنظمة المربوطة'
        },

        ['settings.manage'] = {
            labelAr = 'إدارة الإعدادات',
            category = 'settings',
            description = 'يسمح بتعديل إعدادات النظام'
        }
    },

    -- =============================================================
    -- الأدوار
    --
    -- يمكن استخدام '*' مع صاحب صلاحية المالك إذا كان
    -- Config.Permissions.AllowWildcard = true
    -- =============================================================
    Roles = {
        owner = {
            labelAr = 'المالك',
            priority = 100,
            isProtected = true,
            permissions = {
                '*'
            }
        },

        admin = {
            labelAr = 'مشرف',
            priority = 80,
            isProtected = false,
            permissions = {
                'ui.open',
                'logs.read',
                'logs.export',
                'players.block',
                'players.unblock'
            }
        },

        moderator = {
            labelAr = 'مراقب',
            priority = 50,
            isProtected = false,
            permissions = {
                'ui.open',
                'logs.read'
            }
        }
    },

    -- =============================================================
    -- صلاحيات الأوامر
    --
    -- مهم:
    -- اسم الأمر هنا يجب أن يبقى متطابقًا مع:
    -- Config.Command.LogsPanel في config/main.lua
    -- =============================================================
    CommandPermissions = {
        ['llogliba3mk'] = {
            'ui.open',
            'logs.read'
        }
    },

    -- =============================================================
    -- صلاحيات لوحة الإدارة
    -- =============================================================
    PanelPermissions = {
        open = 'ui.open',
        readLogs = 'logs.read',
        deleteLogs = 'logs.delete',
        exportLogs = 'logs.export',
        blockPlayers = 'players.block',
        unblockPlayers = 'players.unblock',
        manageSystems = 'systems.manage',
        manageTokens = 'tokens.manage',
        manageSettings = 'settings.manage'
    },

    -- =============================================================
    -- صلاحيات الأنظمة المربوطة
    --
    -- هذه هي الصلاحيات التي يمكن منحها لأي نظام خارجي
    -- يريد إرسال إشعارات أو أخطاء أو لوجات إلى نظامنا.
    -- =============================================================
    Scopes = {
        ['notify.send'] = {
            labelAr = 'إرسال إشعارات',
            description = 'يسمح للنظام بإرسال إشعارات إلى اللاعبين'
        },

        ['errors.report'] = {
            labelAr = 'الإبلاغ عن الأخطاء',
            description = 'يسمح للنظام بإرسال أخطاء إلى النظام المركزي'
        },

        ['logs.write'] = {
            labelAr = 'كتابة اللوجات',
            description = 'يسمح للنظام بكتابة لوجات داخل النظام المركزي'
        }
    },

    DefaultSystemScopes = {
        'notify.send',
        'errors.report',
        'logs.write'
    },

    -- =============================================================
    -- إعدادات الكونسول
    -- =============================================================
    Console = {
        AllowConsoleAdmin = true,
        ConsoleRoles = {
            'owner'
        }
    },

    -- =============================================================
    -- إعدادات إضافية للجلسات الإدارية
    -- =============================================================
    Session = {
        BindAdminSessionToDiscord = true,
        ClosePanelOnDisconnect = true
    }
}
