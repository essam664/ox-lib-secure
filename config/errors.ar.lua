-- =============================================================
-- ox_lib_secure
-- File: config/errors.ar.lua
-- Description:
--   كتالوج الأخطاء العربية لنظام ox_lib_secure.
--   هذا الملف يُحمّل من جهة السيرفر فقط.
--
-- Notes:
--   - المفاتيح تبقى بالإنجليزية حتى يسهل استخدامها في الكود.
--   - القيم كلها عربية بالكامل.
--   - أي خطأ غير معروف سيتم تحويله إلى fallback.
--   - يجب أن تكون قيم designStyle متوافقة مع:
--     Config.UI.AllowedDesignStyles
--   - يجب أن تكون قيم category متوافقة مع:
--     allowedCategories في نفس الملف.
-- =============================================================

Config = Config or {}
Config.Localization = Config.Localization or {}
Config.Localization.ar = Config.Localization.ar or {}

Config.Localization.ar.errors = {
    -- =============================================================
    -- إعدادات تنسيق الرسائل
    -- =============================================================
    formatting = {
        -- النمط المستخدم لاكتشاف المتغيرات داخل النصوص.
        placeholderPattern = '{([%w_]+)}',

        -- إذا لم يتم استبدال المتغير، يتم حذفه من النص النهائي.
        removeUnresolvedPlaceholders = true,

        -- إذا كان الخطأ يحتوي على templateBody ولم تتوفر القيم،
        -- يتم استخدام body العام الآمن بدلًا منه.
        useGenericBodyWhenUnresolved = true,

        -- القيمة البديلة إذا أردت ترك نص بديل بدل الحذف.
        fallbackReplacement = ''
    },

    -- =============================================================
    -- التصنيفات المسموحة
    -- =============================================================
    allowedCategories = {
        'general',
        'permission',
        'security',
        'validation',
        'rate_limit',
        'database',
        'ui',
        'session',
        'systems',
        'queue',
        'players',
        'keywords'
    },

    -- =============================================================
    -- الخطأ البديل الآمن
    -- =============================================================
    fallback = {
        code = 'ERR_UNKNOWN',
        title = 'خطأ غير معروف',
        body = 'حدث خطأ غير متوقع في النظام. تم تسجيل المشكلة.',
        severity = 'error',
        designStyle = 'error',
        durationMs = 6000,
        category = 'general'
    },

    -- =============================================================
    -- كتالوج الأخطاء
    -- =============================================================
    catalog = {
        ERR_UNKNOWN = {
            title = 'خطأ غير معروف',
            body = 'حدث خطأ غير متوقع في النظام. تم تسجيل المشكلة.',
            severity = 'error',
            designStyle = 'error',
            durationMs = 6000,
            category = 'general'
        },

        ERR_PERMISSION_DENIED = {
            title = 'رفض الصلاحية',
            body = 'لا تملك صلاحية كافية لتنفيذ هذا الإجراء.',
            severity = 'critical',
            designStyle = 'critical',
            durationMs = 7000,
            category = 'permission'
        },

        ERR_UNAUTHORIZED_SYSTEM = {
            title = 'نظام غير مصرح به',
            body = 'النظام المرسل غير مصرح له باستخدام هذا النظام.',
            severity = 'critical',
            designStyle = 'critical',
            durationMs = 7000,
            category = 'security'
        },

        ERR_INVALID_PAYLOAD = {
            title = 'بيانات غير صالحة',
            body = 'البيانات المرسلة إلى النظام غير صالحة أو ناقصة.',
            severity = 'error',
            designStyle = 'error',
            durationMs = 6000,
            category = 'validation'
        },

        ERR_VALIDATION_FAILED = {
            title = 'فشل التحقق',
            body = 'فشل التحقق من البيانات المرسلة.',
            severity = 'error',
            designStyle = 'error',
            durationMs = 6000,
            category = 'validation'
        },

        ERR_RATE_LIMIT = {
            title = 'تجاوز الحد المسموح',
            body = 'تم تجاوز الحد المسموح من الطلبات. حاول لاحقًا.',
            severity = 'warning',
            designStyle = 'warning',
            durationMs = 6000,
            category = 'rate_limit'
        },

        ERR_DB_FAILURE = {
            title = 'خطأ في قاعدة البيانات',
            body = 'حدث خطأ أثناء التعامل مع قاعدة البيانات.',
            severity = 'critical',
            designStyle = 'critical',
            durationMs = 8000,
            category = 'database'
        },

        ERR_TOKEN_INVALID = {
            title = 'توكن غير صالح',
            body = 'رمز الوصول غير صالح أو تم رفضه.',
            severity = 'critical',
            designStyle = 'critical',
            durationMs = 7000,
            category = 'security'
        },

        ERR_TOKEN_EXPIRED = {
            title = 'انتهاء صلاحية التوكن',
            body = 'انتهت صلاحية رمز الوصول المستخدم.',
            severity = 'error',
            designStyle = 'error',
            durationMs = 6000,
            category = 'security'
        },

        ERR_UI_FAILED = {
            title = 'خطأ في الواجهة',
            body = 'تعذر عرض الواجهة بشكل صحيح.',
            severity = 'error',
            designStyle = 'error',
            durationMs = 6000,
            category = 'ui'
        },

        ERR_SPAM_BLOCKED = {
            title = 'تم حظر الإرسال المتكرر',
            body = 'تم إيقاف الإرسال بسبب تكرار الرسائل بشكل غير طبيعي.',
            severity = 'critical',
            designStyle = 'critical',
            durationMs = 8000,
            category = 'rate_limit'
        },

        ERR_INVALID_SESSION = {
            title = 'جلسة غير صالحة',
            body = 'الجلسة المستخدمة غير صالحة.',
            severity = 'error',
            designStyle = 'error',
            durationMs = 6000,
            category = 'session'
        },

        ERR_SESSION_EXPIRED = {
            title = 'انتهاء الجلسة',
            body = 'انتهت صلاحية الجلسة الحالية.',
            severity = 'warning',
            designStyle = 'warning',
            durationMs = 6000,
            category = 'session'
        },

        ERR_REPLAY_REJECTED = {
            title = 'طلب مكرر',
            body = 'تم رفض الطلب لأنه يبدو مكررًا أو معادًا.',
            severity = 'critical',
            designStyle = 'critical',
            durationMs = 7000,
            category = 'security'
        },

        ERR_SIGNATURE_MISSING = {
            title = 'التوقيع مفقود',
            body = 'الطلب لا يحتوي على توقيع أمني.',
            severity = 'critical',
            designStyle = 'critical',
            durationMs = 7000,
            category = 'security'
        },

        ERR_SIGNATURE_INVALID = {
            title = 'التوقيع غير صالح',
            body = 'تعذر التحقق من صحة توقيع الطلب.',
            severity = 'critical',
            designStyle = 'critical',
            durationMs = 7000,
            category = 'security'
        },

        ERR_MISSING_FIELD = {
            title = 'حقل مفقود',
            body = 'حقل مطلوب مفقود في البيانات المرسلة.',
            templateBody = 'حقل مطلوب مفقود: {field}.',
            placeholders = {
                'field'
            },
            severity = 'error',
            designStyle = 'error',
            durationMs = 6000,
            category = 'validation'
        },

        ERR_FIELD_TOO_LONG = {
            title = 'حقل طويل جدًا',
            body = 'أحد الحقول أطول من الحد المسموح به.',
            templateBody = 'الحقل {field} أطول من الحد المسموح به.',
            placeholders = {
                'field'
            },
            severity = 'error',
            designStyle = 'error',
            durationMs = 6000,
            category = 'validation'
        },

        ERR_INVALID_TYPE = {
            title = 'نوع غير صالح',
            body = 'نوع الرسالة أو الطلب غير صالح.',
            severity = 'error',
            designStyle = 'error',
            durationMs = 6000,
            category = 'validation'
        },

        ERR_INVALID_POSITION = {
            title = 'مكان غير صالح',
            body = 'مكان عرض الرسالة غير صالح.',
            severity = 'error',
            designStyle = 'error',
            durationMs = 6000,
            category = 'validation'
        },

        ERR_INVALID_STYLE = {
            title = 'نمط تصميم غير صالح',
            body = 'نمط التصميم المطلوب غير صالح.',
            severity = 'error',
            designStyle = 'error',
            durationMs = 6000,
            category = 'validation'
        },

        ERR_INVALID_LEVEL = {
            title = 'مستوى لوج غير صالح',
            body = 'مستوى اللوج المرسل غير صالح.',
            severity = 'error',
            designStyle = 'error',
            durationMs = 6000,
            category = 'validation'
        },

        ERR_INVALID_SEVERITY = {
            title = 'درجة خطأ غير صالحة',
            body = 'درجة الخطأ المرسلة غير صالحة.',
            severity = 'error',
            designStyle = 'error',
            durationMs = 6000,
            category = 'validation'
        },

        ERR_INVALID_META = {
            title = 'بيانات إضافية غير صالحة',
            body = 'البيانات الإضافية المرسلة غير صالحة.',
            severity = 'error',
            designStyle = 'error',
            durationMs = 6000,
            category = 'validation'
        },

        ERR_EMPTY_MESSAGE = {
            title = 'رسالة فارغة',
            body = 'لا يمكن إرسال رسالة فارغة.',
            severity = 'error',
            designStyle = 'error',
            durationMs = 6000,
            category = 'validation'
        },

        ERR_SCOPE_MISSING = {
            title = 'صلاحية نظام مفقودة',
            body = 'النظام لا يملك صلاحية مطلوبة.',
            templateBody = 'النظام لا يملك الصلاحية المطلوبة: {scope}.',
            placeholders = {
                'scope'
            },
            severity = 'critical',
            designStyle = 'critical',
            durationMs = 7000,
            category = 'security'
        },

        ERR_SYSTEM_NOT_FOUND = {
            title = 'نظام غير موجود',
            body = 'لم يتم العثور على النظام المطلوب.',
            severity = 'error',
            designStyle = 'error',
            durationMs = 6000,
            category = 'systems'
        },

        ERR_SYSTEM_INACTIVE = {
            title = 'نظام غير نشط',
            body = 'النظام المطلوب غير نشط حاليًا.',
            severity = 'warning',
            designStyle = 'warning',
            durationMs = 6000,
            category = 'systems'
        },

        ERR_QUEUE_FAILED = {
            title = 'فشل الإرسال',
            body = 'تعذر إرسال الرسالة عبر قائمة الانتظار.',
            severity = 'error',
            designStyle = 'error',
            durationMs = 6000,
            category = 'queue'
        },

        ERR_NUI_ACTION_DENIED = {
            title = 'إجراء واجهة مرفوض',
            body = 'تم رفض الإجراء المطلوب داخل الواجهة.',
            severity = 'critical',
            designStyle = 'critical',
            durationMs = 7000,
            category = 'security'
        },

        ERR_NUI_UNKNOWN_ACTION = {
            title = 'إجراء واجهة غير معروف',
            body = 'تم استقبال إجراء غير معروف داخل الواجهة.',
            severity = 'error',
            designStyle = 'error',
            durationMs = 6000,
            category = 'ui'
        },

        ERR_COMMAND_NOT_ALLOWED = {
            title = 'أمر غير مسموح',
            body = 'لا تملك صلاحية استخدام هذا الأمر.',
            severity = 'critical',
            designStyle = 'critical',
            durationMs = 7000,
            category = 'permission'
        },

        ERR_PLAYER_NOT_FOUND = {
            title = 'لاعب غير موجود',
            body = 'لم يتم العثور على اللاعب المطلوب.',
            severity = 'error',
            designStyle = 'error',
            durationMs = 6000,
            category = 'players'
        },

        ERR_PLAYER_BLOCKED = {
            title = 'لاعب محظور',
            body = 'اللاعب المطلوب محظور حاليًا.',
            severity = 'warning',
            designStyle = 'warning',
            durationMs = 6000,
            category = 'players'
        },

        ERR_PLAYER_NOT_BLOCKED = {
            title = 'لاعب غير محظور',
            body = 'اللاعب المطلوب غير محظور.',
            severity = 'warning',
            designStyle = 'warning',
            durationMs = 6000,
            category = 'players'
        },

        ERR_KEYWORD_LIMIT = {
            title = 'تجاوز حد الكلمات المفتاحية',
            body = 'تم تجاوز الحد الأقصى للكلمات المفتاحية.',
            severity = 'warning',
            designStyle = 'warning',
            durationMs = 6000,
            category = 'keywords'
        }
    }
}
