-- =============================================================
-- ox_lib_secure
-- File: config/main.lua
-- Description:
--   ملف الإعدادات الرئيسي لنظام ox_lib_secure.
--   مواءمة حرفية 100% مع جميع الوحدات المطورة.
-- =============================================================

Config = Config or {}

-- =============================================================
-- إعدادات عامة
-- =============================================================
Config.Version = '1.0.0'
Config.Debug = false
Config.Language = 'ar'

-- =============================================================
-- إعدادات قاعدة البيانات
-- =============================================================
Config.Database = {
    SaveAudit = true,
    SaveLogs = true,
    SaveNotifications = true,
    SaveErrors = true,
    PoolSize = 5,
    ConnectionTimeout = 30,
    MaxRetries = 3,
    RetryDelayMs = 2000
}

-- =============================================================
-- إعدادات الأمان
-- متوافقة حرفيًا مع server/core/security.lua
-- =============================================================
Config.Security = {
    Encryption = {
        Algorithm = 'aes-256-cbc',
        KeyLength = 32,
        IVLength = 16,
        MasterKeyEnvName = 'OX_SECURE_MASTER_KEY',
        AllowDbPrivateKeys = false
    },

    Hashing = {
        HmacAlgorithm = 'sha256',
        SaltLength = 16,
        Iterations = 10000
    },

    Token = {
        TTLSeconds = 86400,
        LengthBytes = 32,
        HintLength = 8,
        MaxActive = 5,
        RefreshEnabled = true
    },

    AntiReplay = {
        Enabled = true,
        WindowSeconds = 300,
        MaxNonces = 10000
    },

    Events = {
        ValidateSource = true,
        ValidatePayload = true,
        MaxPayloadSize = 65536
    },

    PayloadLimits = {
        MaxStringLength = 2000,
        MaxTitleLength = 200,
        MaxBodyLength = 1000,
        MaxArraySize = 100,
        MaxObjectSize = 50,
        MaxNestedDepth = 5,
        MaxMetaJsonBytes = 4096,
        MaxMetaDepth = 4,
        MaxNestedObjects = 10,
        MaxArrayLength = 200
    },

    Validation = {
        StrictTypes = true,
        AllowNil = false,
        SanitizeStrings = true,
        AllowedNotificationTypes = {
            'info', 'success', 'warning', 'error', 'critical', 'system'
        },
        AllowedPositions = {
            'left', 'right', 'center', 'top', 'bottom'
        },
        AllowedDesignStyles = {
            'default', 'purple_glass', 'glass', 'solid', 'gradient',
            'error', 'warning', 'success', 'info', 'critical'
        },
        AllowedSeverities = {
            'info', 'warning', 'error', 'critical'
        },
        AllowedLogLevels = {
            'debug', 'info', 'warn', 'error', 'critical'
        }
    },

    RateLimit = {
        UseMemoryLimiter = true,
        UseDatabaseOnlyForAudit = false,
        CleanupIntervalSeconds = 300,
        WindowSeconds = 60,
        MaxPerWindow = 100,
        Buckets = {
            command = { max = 10, windowSeconds = 30 },
            login = { max = 5, windowSeconds = 60 },
            api = { max = 100, windowSeconds = 60 },
            notification = { max = 20, windowSeconds = 60 },
            default = { max = 60, windowSeconds = 60 }
        }
    },

    NUI = {
        ValidateCallbacks = true,
        AllowedOrigins = { 'ox_lib_secure' }
    },

    Identifiers = {
        HashIP = true,
        TrackDevice = false
    },

    Sessions = {
        MaxPerPlayer = 1,
        ExpiryHours = 24,
        ValidateOnJoin = true
    },

    FailedAttempts = {
        Max = 5,
        WindowMinutes = 30,
        BanMinutes = 30,
        TrackIP = true,
        TrackDiscord = true
    },

    Audit = {
        LogAllActions = true,
        LogFailedAttempts = true,
        LogSuccessfulLogins = false
    },

    Secrets = {
        ForbiddenInLogs = {
            'password', 'token', 'secret', 'key',
            'authorization', 'master_key', 'signing_key',
            'encryption_key', 'api_key'
        }
    },

    ErrorDisclosure = {
        ShowStack = false,
        ShowInternal = false,
        GenericMessage = 'حدث خطأ غير متوقع. يرجى المحاولة لاحقًا.'
    },

    Systems = {
        ValidateTokens = true,
        RequireScopes = true
    },

    MemoryCache = {
        Enabled = true,
        TTLSeconds = 300,
        MaxEntries = 1000
    },

    Command = {
        RequirePermission = true,
        LogCommands = true,
        RateLimitPerMinute = 10
    },

    Database = {
        EncryptSensitive = true,
        SanitizeQueries = true
    },

    StartupChecks = {
        VerifyKeys = true,
        VerifyDatabase = true,
        VerifyPermissions = true,
        VerifyLoggerHook = true
    }
}

-- =============================================================
-- إعدادات معدل الطلبات
-- متوافقة حرفيًا مع server/core/rate_limiter.lua
-- =============================================================
Config.RateLimit = {
    UseMemoryLimiter = true,
    UseDatabaseOnlyForAudit = false,
    CleanupIntervalSeconds = 300,
    MaxTotalBuckets = 10000,
    WindowSeconds = 60,
    MaxPerWindow = 60,

    Buckets = {
        command = { max = 10, windowSeconds = 30 },
        login = { max = 5, windowSeconds = 60 },
        api = { max = 100, windowSeconds = 60 },
        notification = { max = 20, windowSeconds = 60 },
        default = { max = 60, windowSeconds = 60 }
    },

    MaxTrackedSources = 1000
}

-- =============================================================
-- إعدادات اللوجات
-- متوافقة مع server/core/logger.lua و server/core/logs.lua
-- =============================================================
Config.Logs = {
    Console = true,
    PublicByDefault = false,
    MaxMessageLength = 2000,
    MaxBuffer = 100,
    FlushIntervalSeconds = 30,
    MaxDbLogs = 10000,
    CleanupAfterDays = 90,
    Level = 'info',
    SaveToFile = false,
    LogFilePath = 'logs/ox_lib_secure.log',

    AllowedLevels = {
        'debug', 'info', 'warn', 'error', 'critical'
    }
}

-- =============================================================
-- إعدادات الإشعارات
-- متوافقة مع server/core/notifications.lua
-- =============================================================
Config.Notifications = {
    Enabled = true,
    DefaultDurationMs = 5000,
    MaxVisibleNotifications = 5,
    EnableSounds = true,
    DefaultPosition = 'left',
    DefaultDesignStyle = 'default',
    CriticalDurationMs = 10000,
    SuccessDurationMs = 4000,
    ErrorDurationMs = 6000,
    WarningDurationMs = 5000,
    InfoDurationMs = 5000,
    CleanupAfterDays = 30
}

-- =============================================================
-- إعدادات الواجهة
-- متوافقة مع client/core/notifications.lua
-- و server/core/validator.lua
-- =============================================================
Config.UI = {
    MaxVisibleNotifications = 5,
    DefaultPosition = 'left',
    DefaultDesignStyle = 'default',
    EnableAnimations = true,
    AnimationDurationMs = 300,
    EnableSounds = true,

    AllowedPositions = {
        'left', 'right', 'center', 'top', 'bottom'
    },

    AllowedNotificationTypes = {
        'info', 'success', 'warning', 'error', 'critical', 'system'
    },

    AllowedDesignStyles = {
        'default', 'purple_glass', 'glass', 'solid', 'gradient',
        'error', 'warning', 'success', 'info', 'critical'
    }
}

-- =============================================================
-- إعدادات الكلمات المفتاحية
-- متوافقة مع server/core/keywords.lua
-- =============================================================
Config.Keywords = {
    Enabled = true,
    MaxCacheSize = 100,
    CacheRefreshSeconds = 300,
    CaseSensitive = false,
    AllowedMatchTypes = {
        'contains', 'exact', 'starts_with', 'ends_with'
    }
}

-- =============================================================
-- إعدادات قائمة الانتظار
-- متوافقة حرفيًا مع server/core/queue.lua
-- =============================================================
Config.Queue = {
    Enabled = true,
    MaxQueueSize = 1000,
    ProcessIntervalMs = 1000,
    MaxAttempts = 3,
    RetryDelayMs = 5000,
    MaxBatchSize = 10,
    CleanupIntervalMs = 60000,
    CleanupAfterDays = 7
}

-- =============================================================
-- إعدادات التخزين العام
-- متوافقة مع server/modules/storage.lua
-- =============================================================
Config.Storage = {
    DefaultTTLSeconds = 3600,
    CleanupIntervalSeconds = 300,
    CacheTTLSeconds = 60
}

-- =============================================================
-- إعدادات معالج الأخطاء
-- متوافقة مع server/modules/error_handler.lua
-- =============================================================
Config.ErrorHandler = {
    MaxErrorHistory = 100,
    ErrorCooldownSeconds = 5
}

-- =============================================================
-- إعدادات التدقيق
-- متوافقة مع server/modules/audit.lua
-- =============================================================
Config.Audit = {
    DiscordNotifications = true,
    DefaultLimit = 50
}

-- =============================================================
-- إعدادات Discord
-- متوافقة حرفيًا مع server/modules/discord.lua
-- =============================================================
Config.Discord = {
    Enabled = false,
    WebhookUrl = '',
    BotName = 'ox_lib_secure',
    BotAvatarUrl = '',
    DefaultColor = 0x6366f1,
    SuccessColor = 0x10b981,
    ErrorColor = 0xef4444,
    WarningColor = 0xf59e0b,
    InfoColor = 0x3b82f6,
    NotifyOnJoin = false,
    NotifyOnLeave = false,
    NotifyOnBan = true,
    NotifyOnUnban = true,
    NotifyOnCritical = true
}

-- =============================================================
-- إعدادات الصلاحيات
-- متوافقة حرفيًا مع server/core/permissions.lua
-- =============================================================
Config.Permissions = {
    Enabled = true,

    Owners = {
        -- أضف معرفات المالكين هنا
         'discord:1249662830568013825',
        -- 'license:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
    },

    DefaultRoleForOwners = 'super_admin',

    Roles = {
        super_admin = {
            name = 'Super Admin',
            priority = 100,
            isProtected = true,
            permissions = {
                'ui.open', 'logs.read', 'logs.delete', 'logs.export',
                'players.block', 'players.unblock', 'players.kick', 'players.ban',
                'systems.manage', 'tokens.manage', 'settings.manage',
                'audit.view', 'audit.export',
                'storage.manage', 'queue.manage', 'migrations.view'
            }
        },
        admin = {
            name = 'Admin',
            priority = 80,
            isProtected = false,
            permissions = {
                'ui.open', 'logs.read', 'logs.export',
                'players.block', 'players.unblock', 'players.kick',
                'audit.view', 'storage.manage', 'queue.manage'
            }
        },
        moderator = {
            name = 'Moderator',
            priority = 50,
            isProtected = false,
            permissions = {
                'ui.open', 'logs.read', 'players.kick', 'audit.view'
            }
        },
        support = {
            name = 'Support',
            priority = 30,
            isProtected = false,
            permissions = {
                'ui.open', 'logs.read'
            }
        }
    },

    PermissionsList = {
        ['ui.open'] = { labelAr = 'فتح الواجهة', category = 'ui' },
        ['logs.read'] = { labelAr = 'قراءة اللوجات', category = 'logs' },
        ['logs.delete'] = { labelAr = 'حذف اللوجات', category = 'logs' },
        ['logs.export'] = { labelAr = 'تصدير اللوجات', category = 'logs' },
        ['players.block'] = { labelAr = 'حظر اللاعبين', category = 'players' },
        ['players.unblock'] = { labelAr = 'فك حظر اللاعبين', category = 'players' },
        ['players.kick'] = { labelAr = 'طرد اللاعبين', category = 'players' },
        ['players.ban'] = { labelAr = 'حظر دائم للاعبين', category = 'players' },
        ['systems.manage'] = { labelAr = 'إدارة الأنظمة', category = 'systems' },
        ['tokens.manage'] = { labelAr = 'إدارة التوكنات', category = 'systems' },
        ['settings.manage'] = { labelAr = 'إدارة الإعدادات', category = 'settings' },
        ['audit.view'] = { labelAr = 'عرض التدقيق', category = 'audit' },
        ['audit.export'] = { labelAr = 'تصدير التدقيق', category = 'audit' },
        ['storage.manage'] = { labelAr = 'إدارة التخزين', category = 'storage' },
        ['queue.manage'] = { labelAr = 'إدارة قائمة الانتظار', category = 'queue' },
        ['migrations.view'] = { labelAr = 'عرض الترحيلات', category = 'database' }
    },

    Scopes = {
        ['notifications:send'] = { labelAr = 'إرسال إشعارات', category = 'notifications' },
        ['logs:write'] = { labelAr = 'كتابة لوجات', category = 'logs' },
        ['logs:read'] = { labelAr = 'قراءة لوجات', category = 'logs' },
        ['players:read'] = { labelAr = 'قراءة بيانات اللاعبين', category = 'players' },
        ['players:block'] = { labelAr = 'حظر اللاعبين', category = 'players' },
        ['audit:read'] = { labelAr = 'قراءة التدقيق', category = 'audit' },
        ['storage:read'] = { labelAr = 'قراءة التخزين', category = 'storage' },
        ['storage:write'] = { labelAr = 'كتابة في التخزين', category = 'storage' },
        ['keywords:read'] = { labelAr = 'قراءة الكلمات المفتاحية', category = 'keywords' },
        ['keywords:write'] = { labelAr = 'كتابة الكلمات المفتاحية', category = 'keywords' }
    },

    DefaultSystemScopes = {
        'notifications:send',
        'logs:write'
    },

    CommandPermissions = {
        ['oxsecure'] = { 'settings.manage' },
        ['oxsecurelogs'] = { 'logs.read' },
        ['oxsecureerrors'] = { 'logs.read' },
        ['oxsecureplayer'] = { 'players.block', 'players.unblock' },
        ['oxsecuresessions'] = { 'logs.read' },
        ['oxsecurestorage'] = { 'storage.manage' },
        ['oxsecurequeue'] = { 'queue.manage' },
        ['oxsecuremigrations'] = { 'migrations.view' }
    },

    PanelPermissions = {
        open = 'ui.open',
        view_logs = 'logs.read',
        delete_logs = 'logs.delete',
        export_logs = 'logs.export',
        manage_players = 'players.block',
        manage_systems = 'systems.manage',
        manage_tokens = 'tokens.manage',
        manage_settings = 'settings.manage',
        view_audit = 'audit.view',
        export_audit = 'audit.export'
    },

    Cache = {
        Enabled = true,
        TTLSeconds = 300,
        MaxEntries = 500,
        CleanupIntervalSeconds = 120
    },

    Audit = {
        LogPermissionChecks = false,
        LogDeniedAccess = true,
        LogRoleChanges = true
    },

    Deny = {
        Message = 'ليس لديك صلاحية لتنفيذ هذا الإجراء.',
        LogDenied = true,
        NotifyAdmin = false
    }
}

-- =============================================================
-- إعدادات الأنظمة المربوطة
-- متوافقة مع server/core/systems.lua
-- =============================================================
Config.Systems = {
    CacheTTLSeconds = 300,
    CacheCleanupIntervalSeconds = 120,
    Enabled = true,
    TokenExpiryHours = 24,
    MaxSystems = 10
}

-- =============================================================
-- إعدادات الجلسات
-- متوافقة حرفيًا مع server/core/sessions.lua
-- =============================================================
Config.Sessions = {
    TrackSessions = true,
    MaxActivePerPlayer = 1,
    CleanupIntervalSeconds = 1800,
    SessionExpiryHours = 24,
    SessionIdLength = 32,
    ValidateOnJoin = true,
    LogSessionEnd = true,

    -- إعدادات جديدة (اختيارية)
    LoadSessionsOnStart = false,
    SessionCleanupDelayMs = 5000
}

-- =============================================================
-- إعدادات اللاعبين
-- متوافقة مع server/core/players.lua و server/core/validator.lua
-- =============================================================
Config.Players = {
    Enabled = true,

    PrimaryIdentifierPriority = {
        'discord', 'license', 'license2',
        'xbl', 'live', 'fivem', 'ip'
    },

    AllowedIdentifierTypes = {
        'discord', 'license', 'license2',
        'xbl', 'live', 'fivem', 'ip'
    },

    TrackLastSeen = true,
    SessionIdLength = 32,
    DefaultBanDurationHours = 24,
    CleanupInactiveAfterDays = 180
}

-- =============================================================
-- إعدادات الترحيلات
-- =============================================================
Config.Migrations = {
    AutoRun = true,
    StopOnFailure = false
}

-- =============================================================
-- إعدادات الترجمة
-- متوافقة مع server/core/localization.lua
-- =============================================================
Config.Localization = {
    DefaultLanguage = 'ar',
    AvailableLanguages = { 'ar', 'en' },
    AutoTranslate = false
}

-- =============================================================
-- رسالة تحميل ناجحة
-- =============================================================
print(('[ox_lib_secure] config/main.lua loaded (v%s)'):format(Config.Version))
