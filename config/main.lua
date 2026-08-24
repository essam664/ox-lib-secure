-- =============================================================
-- ox_lib_secure
-- File: config/main.lua
-- Description:
--   الإعدادات الرئيسية لنظام ox_lib_secure.
--   هذا الملف يُحمّل من جهة السيرفر فقط.
--
-- Notes:
--   - لا تضع في هذا الملف أي مفاتيح سرية.
--   - المفاتيح الرئيسية للتشفير يجب أن تأتي من البيئة الخارجية.
--   - القيم هنا تعتبر قيمًا افتراضية، ويمكن تجاوزها لاحقًا
--     من قاعدة البيانات إذا أردنا ذلك.
--   - يتم ضبط Config.ResourceName لاحقًا داخل server/main.lua
--     حتى لا نعتمد على استدعاءات قد لا تكون جاهزة في وقت مبكر.
-- =============================================================

Config = Config or {}

-- =============================================================
-- إعدادات عامة
-- =============================================================
Config.Version = '1.0.0'
Config.Language = 'ar'
Config.Debug = false

-- =============================================================
-- إعدادات قاعدة البيانات
-- =============================================================
Config.Database = {
    UseDatabase = true,
    TablePrefix = 'oxsecure_',

    SaveLogs = true,
    SaveNotifications = true,
    SaveErrors = true,
    SaveSessions = true,
    SaveCommands = true,
    SaveAudit = true,
    SaveFailedAttempts = true,
    SaveRateLimitAudit = false
}

-- =============================================================
-- إعدادات الواجهة
-- =============================================================
Config.UI = {
    Theme = 'purple_glass',
    Position = 'left',
    RTL = true,

    MaxVisibleNotifications = 5,
    DefaultDurationMs = 6000,
    CriticalDurationMs = 8000,

    AllowedPositions = {
        'left',
        'right',
        'top',
        'bottom',
        'center'
    },

    AllowedNotificationTypes = {
        'info',
        'success',
        'warning',
        'error',
        'critical',
        'system'
    },

    AllowedDesignStyles = {
        'default',
        'purple_glass',
        'glass',
        'critical',
        'purple',
        'gold',
        'info',
        'warning',
        'success',
        'error'
    }
}

-- =============================================================
-- إعدادات الصوت
-- =============================================================
Config.Sounds = {
    Enabled = true,

    -- المسار النسبي المناسب للاستخدام داخل NUI
    Folder = 'assets/sounds',

    Volume = 0.5,

    Files = {
        notify = 'notify.ogg',
        success = 'success.ogg',
        warning = 'warning.ogg',
        error = 'error.ogg',
        critical = 'critical.ogg'
    }
}

-- =============================================================
-- إعدادات اللوجات
-- =============================================================
Config.Logs = {
    Console = true,
    PublicByDefault = false,
    MaxMessageLength = 2000,

    AllowedLevels = {
        'debug',
        'info',
        'warn',
        'error',
        'critical'
    }
}

-- =============================================================
-- إعدادات الأخطاء
-- =============================================================
Config.Errors = {
    MaxTitleLength = 120,
    MaxBodyLength = 2000,

    DefaultErrorCode = 'ERR_UNKNOWN',
    DefaultDesignStyle = 'error',
    CriticalDesignStyle = 'critical',

    AllowedSeverities = {
        'info',
        'warning',
        'error',
        'critical'
    }
}

-- =============================================================
-- إعدادات الأمان
-- =============================================================
Config.Security = {
    -- اسم متغير البيئة الذي سيحتوي على المفتاح الرئيسي.
    -- لا تخزن المفتاح نفسه داخل قاعدة البيانات أو داخل الكود.
    MasterKeyEnvName = 'OXSECURE_MASTER_KEY',

    AllowDbPrivateKeys = false,

    -- يتم استخدام القيمة بأحرف صغيرة لتكون متوافقة مع أغلب
    -- مكتبات التشفير والتوقيع عند التنفيذ.
    HmacAlgorithm = 'sha256',

    TokenTTLSeconds = 300,

    MaxPayloadLength = 4000,
    MaxTitleLength = 120,
    MaxMetaJsonBytes = 65535,

    SanitizeHtml = true,
    BlockUnknownSystems = true,

    FailedAttempts = {
        Max = 10,
        BanMinutes = 30
    }
}

-- =============================================================
-- إعدادات معدل الاستخدام / منع السبام
-- =============================================================
Config.RateLimit = {
    -- الأفضل دائمًا أن يتم الفحص الأول داخل ذاكرة Lua.
    -- قاعدة البيانات تستخدم للتدقيق فقط وليس لكل طلب.
    UseMemoryLimiter = true,
    UseDatabaseOnlyForAudit = true,

    WindowSeconds = 10,
    MaxPerWindow = 20,
    CleanupIntervalSeconds = 300
}

-- =============================================================
-- إعدادات قائمة الانتظار
-- =============================================================
Config.Queue = {
    Enabled = true,
    MaxAttempts = 3,
    RetryDelayMs = 1000,
    WorkerIntervalMs = 500,
    ExpirationSeconds = 300
}

-- =============================================================
-- إعدادات اللاعبين
-- =============================================================
Config.Players = {
    TrackLastSeen = true,
    SessionIdLength = 32,

    -- الأولوية الافتراضية للمعرف الأساسي.
    -- تم تقديم license لأنه الأكثر شيوعًا وثباتًا في FiveM.
    PrimaryIdentifierPriority = {
        'license',
        'license2',
        'discord',
        'fivem',
        'xbl',
        'steam',
        'live'
    },

    AllowedIdentifierTypes = {
        'license',
        'license2',
        'discord',
        'fivem',
        'xbl',
        'steam',
        'live'
    }
}

-- =============================================================
-- إعدادات جلسات اللاعبين
-- =============================================================
Config.Sessions = {
    TrackSessions = true,
    MaxActivePerPlayer = 1,
    CleanupIntervalSeconds = 3600
}

-- =============================================================
-- إعدادات الكلمات المفتاحية
-- =============================================================
Config.Keywords = {
    Enabled = true,
    MaxKeywords = 100,
    DefaultMatchType = 'contains'
}

-- =============================================================
-- إعدادات الأوامر
-- =============================================================
Config.Command = {
    LogsPanel = 'llogliba3mk',
    RequiredPermission = 'ui.open',
    LogUsage = true
}

-- =============================================================
-- إعدادات الأداء
-- =============================================================
Config.Performance = {
    UseBatchInserts = false,
    BatchIntervalMs = 1000,
    MaxCacheSize = 500
}

-- =============================================================
-- إعدادات التطوير
-- =============================================================
Config.Dev = {
    ShowDebugOverlay = false,
    VerboseConsole = false,
    SimulateLatencyMs = 0
}
