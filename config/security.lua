-- =============================================================
-- ox_lib_secure
-- File: config/security.lua
-- Description:
--   إعدادات الأمان الخاصة بنظام ox_lib_secure.
--   هذا الملف يُحمّل من جهة السيرفر فقط.
--
-- Notes:
--   - لا تخزن أي مفاتيح سرية داخل هذا الملف.
--   - المفتاح الرئيسي يجب أن يكون خارج قاعدة البيانات.
--   - كل التحقق النهائي يجب أن يتم من جهة السيرفر.
-- =============================================================

Config = Config or {}

local previousSecurity = Config.Security or {}
local previousFailed = previousSecurity.FailedAttempts or {}

local rateDefaults = Config.RateLimit or {}
local uiDefaults = Config.UI or {}
local logsDefaults = Config.Logs or {}
local errorsDefaults = Config.Errors or {}
local playersDefaults = Config.Players or {}
local sessionsDefaults = Config.Sessions or {}

local eventPrefix = previousSecurity.EventPrefix or 'oxsecure'

local defaultWindowSeconds = rateDefaults.WindowSeconds or 10
local defaultMaxPerWindow = rateDefaults.MaxPerWindow or 20

-- =============================================================
-- إعادة بناء جدول الأمان بشكل نظيف
-- =============================================================
Config.Security = {
    Enabled = true,
    EventPrefix = eventPrefix,
    NeverTrustClient = true,
    RequireServerSideChecks = true,

    -- =============================================================
    -- فحوصات الإقلاع
    -- =============================================================
    StartupChecks = {
        -- يجب أن يتحقق السيرفر عند الإقلاع من وجود خطاف
        -- إخفاء الأسرار داخل دالة التسجيل المركزية.
        VerifyLoggerHook = true,
        FailOnMissingLoggerHook = true,

        -- يجب أن يتحقق السيرفر من وجود معالج فعلي
        -- لصلاحيات إجراءات الواجهة.
        VerifyActionPermissionHandler = true,
        FailOnMissingActionPermissionHandler = true
    },

    -- =============================================================
    -- التشفير
    -- =============================================================
    Encryption = {
        MasterKeyEnvName = previousSecurity.MasterKeyEnvName or 'OXSECURE_MASTER_KEY',
        Algorithm = 'aes-256-gcm',
        NeverStoreMasterKey = true,
        KeyRotationDays = 90,
        EncryptedFieldPrefix = 'enc:v1:',
        AllowDbPrivateKeys = previousSecurity.AllowDbPrivateKeys or false
    },

    -- =============================================================
    -- التجزئة والتوقيع
    -- =============================================================
    Hashing = {
        HmacAlgorithm = previousSecurity.HmacAlgorithm or 'sha256',
        SecretHashAlgorithm = 'sha256',
        UseHmacForEvents = true,
        UseHmacForTokens = true,
        HashLengthHex = 64
    },

    -- =============================================================
    -- التوكنات
    -- =============================================================
    Token = {
        LengthBytes = 32,
        HintLength = 8,
        TTLSeconds = previousSecurity.TokenTTLSeconds or 300,
        AllowReuse = false,
        RotationDays = 30,
        RevocationCheck = true
    },

    -- =============================================================
    -- منع إعادة الإرسال
    -- =============================================================
    AntiReplay = {
        Enabled = true,
        NonceLength = 16,
        NonceTTLSeconds = 60,
        RejectDuplicateNonce = true
    },

    -- =============================================================
    -- أسماء الأحداث الداخلية
    -- =============================================================
    Events = {
        Server = {
            Notify = eventPrefix .. ':server:notify',
            Error = eventPrefix .. ':server:error',
            Log = eventPrefix .. ':server:log',
            SystemCall = eventPrefix .. ':server:systemCall',
            RequestPanel = eventPrefix .. ':server:requestPanel',
            ClosePanel = eventPrefix .. ':server:closePanel',
            RefreshLogs = eventPrefix .. ':server:refreshLogs',
            ExportLogs = eventPrefix .. ':server:exportLogs'
        },

        Client = {
            Notify = eventPrefix .. ':client:notify',
            Error = eventPrefix .. ':client:error',
            OpenPanel = eventPrefix .. ':client:openPanel',
            ClosePanel = eventPrefix .. ':client:closePanel',
            PanelData = eventPrefix .. ':client:panelData',
            Theme = eventPrefix .. ':client:theme'
        },

        NUI = {
            Ready = eventPrefix .. ':nui:ready',
            Close = eventPrefix .. ':nui:close',
            Action = eventPrefix .. ':nui:action',
            Error = eventPrefix .. ':nui:error'
        }
    },

    -- =============================================================
    -- حدود الحمولة
    -- =============================================================
    PayloadLimits = {
        -- يُلزم كود التحقق باستخدام الحد المناسب حسب نوع الحقل.
        EnforceFieldSpecificLimits = true,

        -- توضيح مكان استخدام كل حد.
        -- هذا الجدول توثيقي، لكنه يصبح ملزمًا عندما يكون
        -- EnforceFieldSpecificLimits = true
        Usage = {
            MaxPayloadLength = 'full_external_payload',
            MaxMessageLength = 'notification_or_log_message',
            MaxBodyLength = 'error_body',
            MaxTitleLength = 'notification_or_error_title'
        },

        MaxTitleLength = previousSecurity.MaxTitleLength or 120,
        MaxMessageLength = logsDefaults.MaxMessageLength or 2000,
        MaxBodyLength = errorsDefaults.MaxBodyLength or 2000,
        MaxPayloadLength = previousSecurity.MaxPayloadLength or 4000,
        MaxMetaJsonBytes = previousSecurity.MaxMetaJsonBytes or 65535,

        MaxMetaKeys = 30,

        -- تم رفع العمق قليلًا لدعم الكائنات الأكثر تعقيدًا
        MaxMetaDepth = 5,
        MaxNestedObjects = 15,

        MaxArrayLength = 50
    },

    -- =============================================================
    -- التحقق من المدخلات
    -- =============================================================
    Validation = {
        SanitizeHtml = previousSecurity.SanitizeHtml ~= false,
        BlockControlCharacters = true,
        NormalizeWhitespace = true,
        RejectEmptyMessages = true,

        DefaultLogLevel = 'info',

        AllowedNotificationTypes = uiDefaults.AllowedNotificationTypes or {
            'info',
            'success',
            'warning',
            'error',
            'critical',
            'system'
        },

        AllowedPositions = uiDefaults.AllowedPositions or {
            'left',
            'right',
            'top',
            'bottom',
            'center'
        },

        AllowedDesignStyles = uiDefaults.AllowedDesignStyles or {
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
        },

        AllowedSeverities = errorsDefaults.AllowedSeverities or {
            'info',
            'warning',
            'error',
            'critical'
        },

        AllowedLogLevels = logsDefaults.AllowedLevels or {
            'debug',
            'info',
            'warn',
            'error',
            'critical'
        }
    },

    -- =============================================================
    -- معدل الاستخدام
    -- =============================================================
    RateLimit = {
        UseMemoryLimiter = rateDefaults.UseMemoryLimiter ~= false,
        UseDatabaseOnlyForAudit = rateDefaults.UseDatabaseOnlyForAudit ~= false,
        CleanupIntervalSeconds = rateDefaults.CleanupIntervalSeconds or 300,

        Default = {
            windowSeconds = defaultWindowSeconds,
            max = defaultMaxPerWindow
        },

        Buckets = {
            default = {
                windowSeconds = defaultWindowSeconds,
                max = defaultMaxPerWindow
            },

            notification = {
                windowSeconds = 10,
                max = 15
            },

            error = {
                windowSeconds = 10,
                max = 15
            },

            log = {
                windowSeconds = 10,
                max = 30
            },

            panelOpen = {
                windowSeconds = 30,
                max = 5
            },

            command = {
                windowSeconds = 10,
                max = 5
            },

            nuiCallback = {
                windowSeconds = 1,
                max = 20
            }
        },

        ExceedAction = {
            Log = true,
            Block = true,
            NotifyPlayer = true,
            RecordFailedAttempt = true
        }
    },

    -- =============================================================
    -- حماية الواجهة
    -- =============================================================
    NUI = {
        AllowOnlyRegisteredCallbacks = true,
        ValidateCallbacks = true,
        BlockRawHtml = true,
        SanitizeText = true,

        MaxActionsPerSecond = 20,
        CallbackTimeoutMs = 5000,

        -- يجب على السيرفر تطبيق هذا الشرط فعليًا.
        EnforceActionPermissions = true,

        -- رفض أي إجراء غير موجود في AllowedActions.
        RejectUnknownActions = true,

        -- رفض أي إجراء مصرح به إذا لم تتوفر الجلسة أو الصلاحية.
        RejectUnauthorizedActions = true,

        -- المتطلبات الافتراضية لأي إجراء غير موجود في
        -- ActionPermissions هي وجود جلسة صالحة فقط.
        DefaultActionRequirement = 'valid_session',

        -- الإجراءات المسموح بها من الواجهة.
        -- يجب أن يتم تنفيذ هذه الإجراءات فعليًا في الواجهة
        -- واستقبالها في السيرفر مع التصريح المناسب.
        AllowedActions = {
            'ready',
            'close',
            'closePanel',
            'refreshLogs',
            'filterLogs',
            'searchLogs',
            'openLogDetails',
            'exportLogs',
            'copyLog',
            'acknowledgeError'
        },

        -- بعض الإجراءات تحتاج إلى صلاحية إضافية.
        -- الإجراءات غير الموجودة هنا يكفي أن تكون الجلسة صالحة.
        ActionPermissions = {
            refreshLogs = 'logs.read',
            filterLogs = 'logs.read',
            searchLogs = 'logs.read',
            openLogDetails = 'logs.read',
            copyLog = 'logs.read',
            exportLogs = 'logs.export'
        }
    },

    -- =============================================================
    -- حماية المعرفات
    -- =============================================================
    Identifiers = {
        TrustServerIdentifiersOnly = true,
        NeverTrustClientDiscordId = true,
        RequireAtLeastOneIdentifier = true,

        PreferredIdentifierOrder = playersDefaults.PrimaryIdentifierPriority or {
            'license',
            'license2',
            'discord',
            'fivem',
            'xbl',
            'steam',
            'live'
        },

        AllowedIdentifierTypes = playersDefaults.AllowedIdentifierTypes or {
            'license',
            'license2',
            'discord',
            'fivem',
            'xbl',
            'steam',
            'live'
        }
    },

    -- =============================================================
    -- الجلسات
    -- =============================================================
    Sessions = {
        TrackSessions = sessionsDefaults.TrackSessions ~= false,
        MaxActivePerPlayer = sessionsDefaults.MaxActivePerPlayer or 1,
        BindToPlayer = true,
        CloseOnDisconnect = true
    },

    -- =============================================================
    -- المحاولات الفاشلة
    -- =============================================================
    FailedAttempts = {
        Max = previousFailed.Max or 10,
        BanMinutes = previousFailed.BanMinutes or 30,

        Actions = {
            'log',
            'block',
            'notify_player'
        },

        NotifyAdmins = false,

        ReasonCodes = {
            'ERR_PERMISSION_DENIED',
            'ERR_UNAUTHORIZED_SYSTEM',
            'ERR_TOKEN_INVALID',
            'ERR_TOKEN_EXPIRED',
            'ERR_RATE_LIMIT',
            'ERR_SPAM_BLOCKED'
        }
    },

    -- =============================================================
    -- التدقيق
    -- =============================================================
    Audit = {
        LogSecurityEvents = true,
        LogTokenUsage = false,
        LogPayloadHashes = true,
        LogDeniedEvents = true,
        MaskSecrets = true
    },

    -- =============================================================
    -- إخفاء الأسرار
    -- =============================================================
    Secrets = {
        -- يجب أن يلتزم نظام التسجيل الفعلي بهذه القيمة
        -- قبل كتابة أي لوج إلى الكونسول أو قاعدة البيانات.
        EnforceInLogger = true,

        -- يؤكد أن دالة التسجيل المركزية يجب أن تحتوي على
        -- خطاف فعلي لإخفاء الأسرار، وإلا يعتبر النظام غير آمن.
        LoggerHookRequired = true,

        RedactRecursive = true,

        ForbiddenInLogs = {
            'token',
            'secret',
            'password',
            'authorization',
            'api_key',
            'apikey',
            'master_key',
            'private_key',
            'signing_key'
        },

        MaskValue = '[REDACTED]'
    },

    -- =============================================================
    -- الإفصاح عن الأخطاء
    -- =============================================================
    ErrorDisclosure = {
        ShowDetailsToPlayer = false,
        ShowErrorCode = true,
        LogDetails = true,
        LogStackTrace = false
    },

    -- =============================================================
    -- أمان الأنظمة المربوطة
    -- =============================================================
    Systems = {
        BlockUnknownSystems = previousSecurity.BlockUnknownSystems ~= false,
        RequireScopes = true,
        RequireActiveSystem = true,

        -- يتم تعطيل إلزام التوقيع افتراضيًا في مرحلة الربط الأولى
        -- حتى لا نرفض طلبات الأنظمة التي لا تدعم التوقيع بعد.
        -- يُنصح بتفعيله لاحقًا بعد دعم جميع الأنظمة للتوقيع.
        RequireSignature = false,

        -- إذا كان النظام يمتلك مفتاح توقيع أو بيانات توقيع،
        -- فسيتم التحقق منها حتى لو كان RequireSignature = false.
        RequireSignatureWhenAvailable = true,

        -- يساعد السيرفر على جلب مفتاح التوقيع الخاص بالنظام
        -- تلقائيًا من قاعدة البيانات عند الحاجة.
        AutoDetectSigningKey = true,
        SigningKeySource = 'database',
        CacheSigningKeys = true,
        SigningKeyCacheTTLSeconds = 300,

        SignatureHeader = 'x-oxsecure-signature',
        SignatureTimestampTTLSeconds = 60,
        MaxClockSkewSeconds = 30,

        MaxInactiveDays = 90
    },

    -- =============================================================
    -- التخزين المؤقت الأمني في الذاكرة
    -- =============================================================
    MemoryCache = {
        Enabled = true,
        MaxEntries = 1000,
        CleanupSeconds = 60
    },

    -- =============================================================
    -- أمان الأوامر
    -- =============================================================
    Command = {
        RateLimitBucket = 'command',
        LogUsage = true,
        RequirePlayer = true,
        RequirePermissionCheck = true
    },

    -- =============================================================
    -- أمان قاعدة البيانات
    -- =============================================================
    Database = {
        SafeMode = true,
        RetryAttempts = 2,
        RetryDelayMs = 250,
        LogQueryErrors = true,

        -- إعادة المحاولة عند أخطاء الاتصال المؤقتة
        RetryOnConnectionErrors = true,

        -- أنماط الأخطاء القابلة لإعادة المحاولة
        -- يتم فحصها بنصوص صغيرة غير حساسة لحالة الأحرف.
        RetryableErrorPatterns = {
            'connection refused',
            'lost connection',
            'deadlock found',
            'lock wait timeout'
        }
    }
}
