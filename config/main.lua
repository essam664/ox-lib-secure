Config = {}

-- =============================================================
-- الإصدار
-- =============================================================
Config.Version = '1.0.0'

-- =============================================================
-- اللغة الافتراضية
-- =============================================================
Config.Language = 'ar'

-- =============================================================
-- وضع التصحيح
-- =============================================================
Config.Debug = false

-- =============================================================
-- إعدادات الأمان
-- متوافق مع بنية server/core/security.lua
-- =============================================================
Config.Security = {
    -- ملاحظة: في بيئة الإنتاج، يُفضَّل ضبط MasterKey و
    -- SigningKey عبر متغيرات البيئة بدلاً من كتابتها هنا.
    -- إذا تُركت فارغة، سيعمل النظام في وضع متدهور.
    MasterKey = '',
    MasterKeyEnv = 'OXSECURE_MASTER_KEY',

    SigningKey = '',
    SigningKeyEnv = 'OXSECURE_SIGNING_KEY',

    -- بنية Encryption المتوافقة مع security.lua
    Encryption = {
        MasterKeyEnvName = 'OXSECURE_MASTER_KEY',
        SigningKeyEnvName = 'OXSECURE_SIGNING_KEY'
    },

    -- أسماء الحقول متوافقة مع security.lua
    FailedAttempts = {
        WindowSeconds = 300,
        Max = 5,
        BanMinutes = 15
    },

    PayloadLimits = {
        MaxTitleLength = 120,
        MaxBodyLength = 2000,
        MaxMessageLength = 2000,
        MaxCategoryLength = 50,
        MaxEventCodeLength = 100,
        MaxKeywordLength = 255,
        MaxMetaKeys = 10,
        MaxMetaKeyLength = 64,
        MaxMetaValueLength = 255,
        MaxMetaJsonBytes = 65535,
        MaxMetaDepth = 5,
        MaxNestedObjects = 15,
        MaxArrayLength = 50
    },

    RateLimit = {
        Buckets = {
            notification = { windowSeconds = 10, max = 20 },
            error = { windowSeconds = 10, max = 20 },
            log = { windowSeconds = 10, max = 50 },
            panelOpen = { windowSeconds = 10, max = 5 },
            command = { windowSeconds = 10, max = 10 },
            nuiCallback = { windowSeconds = 10, max = 30 },
            default = { windowSeconds = 10, max = 20 }
        },
        ExceedAction = {
            BlockRequest = true,
            RecordFailedAttempt = true
        }
    },

    Database = {
        SafeMode = true,
        RetryAttempts = 2,
        RetryDelayMs = 250,
        LogQueryErrors = true
    }
}

-- =============================================================
-- إعدادات واجهة المستخدم
-- =============================================================
Config.UI = {
    AllowedPositions = {
        'top', 'top-right', 'top-left',
        'bottom', 'bottom-right', 'bottom-left',
        'center', 'left', 'right'
    },
    AllowedNotificationTypes = {
        'info', 'success', 'warning', 'error', 'critical', 'system'
    },
    AllowedDesignStyles = {
        'default', 'purple_glass', 'glass', 'critical',
        'purple', 'gold', 'info', 'warning', 'success', 'error'
    },
    DefaultPosition = 'left',
    DefaultDesignStyle = 'default',
    DefaultDurationMs = 5000,
    MaxDurationMs = 30000
}

-- =============================================================
-- إعدادات قاعدة البيانات
-- =============================================================
Config.Database = {
    UseDatabase = true,
    TablePrefix = 'oxsecure_',
    SaveLogs = true,
    SaveErrors = true,
    SaveNotifications = true,
    SaveSessions = true,
    SaveCommands = true,
    SaveAudit = true,
    SaveFailedAttempts = true,
    SaveRateLimitAudit = true
}

-- =============================================================
-- إعدادات اللوجات
-- =============================================================
Config.Logs = {
    Console = true,
    PublicByDefault = false,
    MaxMessageLength = 2000,
    MaxBuffer = 100,
    FlushIntervalSeconds = 30
}

-- =============================================================
-- إعدادات معدل الاستخدام
-- =============================================================
Config.RateLimit = {
    UseMemoryLimiter = true,
    WindowSeconds = 10,
    MaxPerWindow = 20,
    CleanupIntervalSeconds = 300,
    MaxTotalBuckets = 10000
}

-- =============================================================
-- إعدادات Discord
-- =============================================================
Config.Discord = {
    Enabled = false,
    WebhookUrl = nil,
    BotName = 'ox_lib_secure',
    BotAvatarUrl = nil
}

-- =============================================================
-- إعدادات الإشعارات
-- =============================================================
Config.Notifications = {
    DefaultPosition = 'left',
    DefaultDesignStyle = 'default',
    DefaultDurationMs = 5000,
    MaxDurationMs = 30000,
    Sound = {
        Enabled = true,
        DefaultName = 'default'
    }
}

-- =============================================================
-- إعدادات الأخطاء
-- =============================================================
Config.Errors = {
    AllowedSeverities = { 'info', 'warning', 'error', 'critical' },
    AllowedCategories = {
        'general', 'database', 'security', 'notification',
        'permission', 'rate_limit', 'system', 'player', 'session'
    }
}

-- =============================================================
-- إعدادات اللاعبين
-- =============================================================
Config.Players = {
    PrimaryIdentifierPriority = { 'discord', 'license2', 'license', 'fivem' },
    AllowedIdentifierTypes = { 'license', 'license2', 'discord', 'fivem', 'xbl', 'steam', 'live' },
    TrackLastSeen = true,
    SessionIdLength = 32
}

-- =============================================================
-- إعدادات الأنظمة المربوطة
--
-- ملاحظة 1: CacheCleanupIntervalSeconds يُستخدم في
-- systems.lua لتحديد فترة التنظيف بشكل منفصل عن TTL.
-- =============================================================
Config.Systems = {
    CacheTTLSeconds = 300,
    CacheCleanupIntervalSeconds = 120
}

-- =============================================================
-- إعدادات الترجمة
--
-- ملاحظة 3: تمت إضافة الأكواد الناقصة إلى الكتالوج.
-- =============================================================
Config.Localization = {
    ar = {
        messages = {
            generic = {
                success = 'تمت العملية بنجاح.',
                failed = 'فشلت العملية.',
                notFound = 'لم يتم العثور على المطلوب.',
                unauthorized = 'غير مصرح لك بتنفيذ هذه العملية.',
                rateLimited = 'تم تجاوز الحد المسموح. حاول لاحقًا.'
            },
            permission = {
                denied = 'ليس لديك صلاحية كافية.',
                granted = 'تم منح الصلاحية بنجاح.',
                revoked = 'تم سحب الصلاحية بنجاح.'
            },
            player = {
                joined = 'انضم اللاعب {name} إلى السيرفر.',
                left = 'غادر اللاعب {name} السيرفر.',
                blocked = 'تم حظر اللاعب {name}.',
                unblocked = 'تم فك حظر اللاعب {name}.'
            },
            logs = {
                empty = 'لا توجد سجلات لعرضها.',
                saved = 'تم حفظ السجل بنجاح.',
                deleted = 'تم حذف السجل بنجاح.'
            },
            titles = {
                info = 'معلومة',
                success = 'نجاح',
                warning = 'تحذير',
                error = 'خطأ',
                critical = 'حرج',
                system = 'النظام'
            }
        },
        errors = {
            fallback = {
                code = 'ERR_UNKNOWN',
                title = 'خطأ غير معروف',
                body = 'حدث خطأ غير متوقع في النظام.',
                severity = 'error',
                designStyle = 'error',
                durationMs = 6000,
                category = 'general'
            },
            catalog = {
                ERR_PLAYER_NOT_FOUND = {
                    title = 'لاعب غير موجود',
                    body = 'لم يتم العثور على اللاعب المطلوب.',
                    severity = 'warning',
                    designStyle = 'warning',
                    durationMs = 5000,
                    category = 'player'
                },
                ERR_INVALID_PAYLOAD = {
                    title = 'بيانات غير صالحة',
                    body = 'البيانات المرسلة غير صالحة أو ناقصة.',
                    severity = 'warning',
                    designStyle = 'warning',
                    durationMs = 5000,
                    category = 'general'
                },
                ERR_MISSING_FIELD = {
                    title = 'حقل مفقود',
                    body = 'حقل مطلوب غير موجود في البيانات المرسلة.',
                    severity = 'warning',
                    designStyle = 'warning',
                    durationMs = 5000,
                    category = 'general'
                },
                ERR_VALIDATION_FAILED = {
                    title = 'فشل التحقق',
                    body = 'فشل التحقق من صحة البيانات المرسلة.',
                    severity = 'warning',
                    designStyle = 'warning',
                    durationMs = 5000,
                    category = 'general'
                },
                ERR_UI_FAILED = {
                    title = 'خطأ في الواجهة',
                    body = 'حدث خطأ أثناء عرض الواجهة.',
                    severity = 'error',
                    designStyle = 'error',
                    durationMs = 6000,
                    category = 'general'
                },
                ERR_RATE_LIMIT = {
                    title = 'تجاوز الحد المسموح',
                    body = 'تم تجاوز عدد الطلبات المسموح بها. يرجى المحاولة لاحقًا.',
                    severity = 'warning',
                    designStyle = 'warning',
                    durationMs = 5000,
                    category = 'rate_limit'
                },
                ERR_PERMISSION_DENIED = {
                    title = 'صلاحيات غير كافية',
                    body = 'ليس لديك الصلاحيات الكافية لتنفيذ هذه العملية.',
                    severity = 'warning',
                    designStyle = 'warning',
                    durationMs = 5000,
                    category = 'permission'
                },
                ERR_DB_QUERY_FAILED = {
                    title = 'خطأ في قاعدة البيانات',
                    body = 'حدث خطأ أثناء تنفيذ استعلام قاعدة البيانات.',
                    severity = 'error',
                    designStyle = 'error',
                    durationMs = 6000,
                    category = 'database'
                },
                ERR_DB_INSERT_FAILED = {
                    title = 'خطأ في الإدراج',
                    body = 'حدث خطأ أثناء إدراج البيانات في قاعدة البيانات.',
                    severity = 'error',
                    designStyle = 'error',
                    durationMs = 6000,
                    category = 'database'
                },
                ERR_DB_CONNECTION_FAILED = {
                    title = 'فشل الاتصال بقاعدة البيانات',
                    body = 'تعذر الاتصال بقاعدة البيانات.',
                    severity = 'critical',
                    designStyle = 'error',
                    durationMs = 8000,
                    category = 'database'
                },
                ERR_TOKEN_NOT_FOUND = {
                    title = 'توكن غير موجود',
                    body = 'لم يتم العثور على التوكن المطلوب.',
                    severity = 'warning',
                    designStyle = 'warning',
                    durationMs = 5000,
                    category = 'security'
                },
                ERR_TOKEN_EXPIRED = {
                    title = 'توكن منتهي الصلاحية',
                    body = 'التوكن المقدم انتهت صلاحيته.',
                    severity = 'warning',
                    designStyle = 'warning',
                    durationMs = 5000,
                    category = 'security'
                },
                ERR_TOKEN_REVOKED = {
                    title = 'توكن مُبطل',
                    body = 'التوكن المقدم تم إبطاله.',
                    severity = 'warning',
                    designStyle = 'warning',
                    durationMs = 5000,
                    category = 'security'
                },
                ERR_SYSTEM_DISABLED = {
                    title = 'نظام معطل',
                    body = 'النظام المطلوب معطل حاليًا.',
                    severity = 'warning',
                    designStyle = 'warning',
                    durationMs = 5000,
                    category = 'system'
                },
                ERR_INVALID_TOKEN = {
                    title = 'توكن غير صالح',
                    body = 'التوكن المقدم غير صالح.',
                    severity = 'warning',
                    designStyle = 'warning',
                    durationMs = 5000,
                    category = 'security'
                },
                ERR_INVALID_LEVEL = {
                    title = 'مستوى غير صالح',
                    body = 'مستوى اللوج المقدم غير صالح.',
                    severity = 'warning',
                    designStyle = 'warning',
                    durationMs = 5000,
                    category = 'general'
                },
                ERR_EMPTY_MESSAGE = {
                    title = 'رسالة فارغة',
                    body = 'لا يمكن إرسال رسالة فارغة.',
                    severity = 'warning',
                    designStyle = 'warning',
                    durationMs = 5000,
                    category = 'general'
                },
                ERR_FIELD_TOO_LONG = {
                    title = 'حقل طويل جدًا',
                    body = 'أحد الحقول يتجاوز الحد الأقصى المسموح به.',
                    severity = 'warning',
                    designStyle = 'warning',
                    durationMs = 5000,
                    category = 'general'
                },
                ERR_INVALID_FIELD = {
                    title = 'حقل غير صالح',
                    body = 'أحد الحقول يحتوي على قيمة غير صالحة.',
                    severity = 'warning',
                    designStyle = 'warning',
                    durationMs = 5000,
                    category = 'general'
                },
                ERR_INVALID_SOURCE = {
                    title = 'مصدر غير صالح',
                    body = 'معرف اللاعب المقدم غير صالح.',
                    severity = 'warning',
                    designStyle = 'warning',
                    durationMs = 5000,
                    category = 'player'
                },
                ERR_INVALID_PLAYER_ID = {
                    title = 'معرف لاعب غير صالح',
                    body = 'معرف اللاعب المقدم غير صالح.',
                    severity = 'warning',
                    designStyle = 'warning',
                    durationMs = 5000,
                    category = 'player'
                },
                ERR_SESSION_LOCKED = {
                    title = 'جلسة قيد الإنشاء',
                    body = 'يتم إنشاء جلسة بالفعل لهذا اللاعب.',
                    severity = 'info',
                    designStyle = 'info',
                    durationMs = 3000,
                    category = 'session'
                },
                ERR_SESSION_NOT_FOUND = {
                    title = 'جلسة غير موجودة',
                    body = 'لم يتم العثور على الجلسة المطلوبة.',
                    severity = 'warning',
                    designStyle = 'warning',
                    durationMs = 5000,
                    category = 'session'
                },
                ERR_SYSTEM_ALREADY_EXISTS = {
                    title = 'نظام موجود بالفعل',
                    body = 'النظام المطلوب تسجيله موجود بالفعل.',
                    severity = 'warning',
                    designStyle = 'warning',
                    durationMs = 5000,
                    category = 'system'
                },
                ERR_INVALID_SYSTEM_CODE = {
                    title = 'رمز نظام غير صالح',
                    body = 'رمز النظام المقدم غير صالح.',
                    severity = 'warning',
                    designStyle = 'warning',
                    durationMs = 5000,
                    category = 'system'
                },
                ERR_INVALID_SYSTEM_ID = {
                    title = 'معرف نظام غير صالح',
                    body = 'معرف النظام المقدم غير صالح.',
                    severity = 'warning',
                    designStyle = 'warning',
                    durationMs = 5000,
                    category = 'system'
                },
                ERR_SYSTEM_NOT_FOUND = {
                    title = 'نظام غير موجود',
                    body = 'لم يتم العثور على النظام المطلوب.',
                    severity = 'warning',
                    designStyle = 'warning',
                    durationMs = 5000,
                    category = 'system'
                },
                ERR_TOKEN_HASH_FAILED = {
                    title = 'فشل تجزئة التوكن',
                    body = 'حدث خطأ أثناء تجزئة التوكن.',
                    severity = 'error',
                    designStyle = 'error',
                    durationMs = 6000,
                    category = 'security'
                },
                ERR_INTERNAL_VALIDATOR_MISSING = {
                    title = 'خطأ داخلي',
                    body = 'دالة تحقق مطلوبة غير متوفرة.',
                    severity = 'critical',
                    designStyle = 'error',
                    durationMs = 6000,
                    category = 'general'
                },
                ERR_PLAYER_NO_IDENTIFIER = {
                    title = 'لا يوجد معرف',
                    body = 'لا يمتلك اللاعب أي معرف صالح.',
                    severity = 'warning',
                    designStyle = 'warning',
                    durationMs = 5000,
                    category = 'player'
                },
                ERR_PLAYER_BLOCKED = {
                    title = 'لاعب محظور',
                    body = 'هذا اللاعب محظور من السيرفر.',
                    severity = 'warning',
                    designStyle = 'warning',
                    durationMs = 5000,
                    category = 'player'
                },
                ERR_COMMAND_NOT_FOUND = {
                    title = 'أمر غير موجود',
                    body = 'الأمر المطلوب غير موجود.',
                    severity = 'warning',
                    designStyle = 'warning',
                    durationMs = 5000,
                    category = 'general'
                },
                ERR_KEYWORD_NOT_FOUND = {
                    title = 'كلمة مفتاحية غير موجودة',
                    body = 'لم يتم العثور على الكلمة المفتاحية المطلوبة.',
                    severity = 'warning',
                    designStyle = 'warning',
                    durationMs = 5000,
                    category = 'general'
                },
                ERR_QUEUE_FULL = {
                    title = 'قائمة الانتظار ممتلئة',
                    body = 'قائمة الانتظار ممتلئة حاليًا. حاول لاحقًا.',
                    severity = 'warning',
                    designStyle = 'warning',
                    durationMs = 5000,
                    category = 'general'
                },
                ERR_MIGRATION_FAILED = {
                    title = 'فشل الترحيل',
                    body = 'حدث خطأ أثناء ترحيل قاعدة البيانات.',
                    severity = 'critical',
                    designStyle = 'error',
                    durationMs = 8000,
                    category = 'database'
                },
                ERR_ALREADY_LOADING = {
                    title = 'جارٍ التحميل',
                    body = 'يتم تحميل البيانات بالفعل. يرجى الانتظار.',
                    severity = 'info',
                    designStyle = 'info',
                    durationMs = 3000,
                    category = 'general'
                }
            },
            allowedCategories = {
                'general', 'database', 'security', 'notification',
                'permission', 'rate_limit', 'system', 'player', 'session'
            }
        }
    }
}
