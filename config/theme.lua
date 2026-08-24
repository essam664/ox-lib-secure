-- =============================================================
-- ox_lib_secure
-- File: config/theme.lua
-- Description:
--   إعدادات الثيم الخاصة بنظام ox_lib_secure.
--   هذا الملف يُحمّل من جهة السيرفر، ثم يتم إرسال القيم
--   الآمنة منه إلى واجهة NUI عند الحاجة.
--
-- Theme:
--   Purple Glass UI - Arabic RTL - Left Notifications
-- =============================================================

Config = Config or {}

-- =============================================================
-- قيم مشتركة لتقليل التكرار
-- =============================================================
local Shared = {
    Blur = {
        normal = '18px',
        strong = '20px'
    },

    Radius = {
        small = '10px',
        medium = '16px',
        large = '20px',
        xlarge = '22px'
    },

    Shadow = {
        normal = '0 10px 35px rgba(0, 0, 0, 0.35)',
        strong = '0 18px 50px rgba(0, 0, 0, 0.42)',
        modal = '0 24px 70px rgba(0, 0, 0, 0.55)',
        critical = '0 0 32px rgba(239, 68, 68, 0.35)'
    },

    Border = {
        glass = '1px solid rgba(167, 139, 250, 0.25)',
        glassStrong = '1px solid rgba(167, 139, 250, 0.30)',
        critical = '1px solid rgba(239, 68, 68, 0.55)',
        errorModal = '1px solid rgba(239, 68, 68, 0.35)'
    },

    Background = {
        glass = 'rgba(16, 8, 32, 0.55)',
        glassStrong = 'rgba(16, 8, 32, 0.58)',
        dark = 'rgba(10, 4, 22, 0.72)',
        critical = 'rgba(40, 5, 10, 0.62)'
    },

    Highlight = 'inset 0 1px 0 rgba(255, 255, 255, 0.08)'
}

Config.Theme = {
    Name = 'purple_glass',
    LabelAr = 'بنفسجي زجاجي',
    Version = '1.0.0',

    -- اتجاه الواجهة
    Direction = 'rtl',

    -- الخط العربي الافتراضي
    -- تم الاعتماد على خطوط عربية أولاً، ثم نهاية عامة بدون خط غير عربي.
    FontFamily = "'Cairo', 'Tajawal', 'Noto Kufi Arabic', sans-serif",

    -- =============================================================
    -- الألوان الأساسية
    -- =============================================================
    Colors = {
        primary = '#7C3AED',
        primarySoft = '#A78BFA',
        primaryDark = '#4C1D95',
        primaryUltraDark = '#2E1065',

        background = 'rgba(16, 8, 32, 0.55)',
        backgroundStrong = 'rgba(10, 4, 22, 0.72)',
        glassBorder = 'rgba(167, 139, 250, 0.25)',
        glassHighlight = 'rgba(255, 255, 255, 0.08)',

        text = '#F5F3FF',
        textMuted = '#C4B5FD',
        textFaint = '#9F86C0',

        success = '#22C55E',
        info = '#38BDF8',
        warning = '#F59E0B',
        error = '#EF4444',
        critical = '#DC2626',

        overlay = 'rgba(0, 0, 0, 0.35)',
        focusRing = 'rgba(167, 139, 250, 0.85)'
    },

    -- =============================================================
    -- إعدادات الزجاج
    -- =============================================================
    Glass = {
        blur = Shared.Blur.normal,
        saturation = '140%',
        radius = Shared.Radius.medium,
        border = Shared.Border.glass,
        shadow = Shared.Shadow.normal,
        innerHighlight = Shared.Highlight
    },

    -- =============================================================
    -- التخطيط العام
    -- =============================================================
    Layout = {
        safeArea = '12px',
        notificationSide = 'left',
        panelWidth = '860px',
        panelMaxWidth = '94vw',
        panelMinHeight = '520px',
        contentPadding = '18px',
        borderRadiusLarge = Shared.Radius.large,
        borderRadiusMedium = Shared.Radius.medium,
        borderRadiusSmall = Shared.Radius.small
    },

    -- =============================================================
    -- الحركات
    -- =============================================================
    Animations = {
        durationMs = 220,
        criticalDurationMs = 320,
        easing = 'cubic-bezier(0.2, 0.9, 0.2, 1)',

        notificationEnter = 'slide-in-left',
        notificationExit = 'slide-out-left',

        glassEnter = 'fade-scale-in',
        glassExit = 'fade-scale-out',

        criticalEnter = 'critical-pop',
        criticalExit = 'critical-fade',

        reduceMotion = false
    },

    -- =============================================================
    -- الإشعارات
    -- =============================================================
    Notifications = {
        width = '360px',
        mobileWidth = '92vw',
        maxWidth = '420px',
        minHeight = '64px',
        gap = '12px',
        padding = '14px 16px',
        iconSize = '22px',
        titleFontWeight = 700,
        bodyFontWeight = 400,
        titleSize = '14px',
        bodySize = '13px',
        background = Shared.Background.glass,
        border = Shared.Border.glass,
        shadow = Shared.Shadow.normal,
        blur = Shared.Blur.normal,
        radius = Shared.Radius.medium,
        progressHeight = '3px',
        progressOpacity = 0.65
    },

    -- =============================================================
    -- الرسالة الزجاجية
    -- =============================================================
    GlassMessage = {
        width = '520px',
        maxWidth = '92vw',
        minHeight = '90px',
        padding = '20px',
        radius = Shared.Radius.large,
        background = Shared.Background.glassStrong,
        border = Shared.Border.glassStrong,
        shadow = Shared.Shadow.strong,
        blur = Shared.Blur.strong,
        titleSize = '16px',
        bodySize = '14px',
        titleColor = '#F5F3FF',
        bodyColor = '#E9D5FF'
    },

    -- =============================================================
    -- الرسالة الحمراء الحرجة
    -- =============================================================
    CriticalMessage = {
        width = '560px',
        maxWidth = '92vw',
        minHeight = '100px',
        padding = '22px',
        radius = Shared.Radius.large,
        background = Shared.Background.critical,
        border = Shared.Border.critical,
        shadow = Shared.Shadow.critical,
        blur = Shared.Blur.strong,
        titleColor = '#FEE2E2',
        bodyColor = '#FECACA',
        iconColor = '#F87171',
        glow = '0 0 22px rgba(220, 38, 38, 0.35)',
        pulse = true,
        shake = true,
        shakeIntensity = 'small'
    },

    -- =============================================================
    -- نافذة الخطأ الكاملة
    -- =============================================================
    ErrorModal = {
        width = '620px',
        maxWidth = '94vw',
        minHeight = '180px',
        padding = '24px',
        radius = Shared.Radius.xlarge,
        background = Shared.Background.dark,
        border = Shared.Border.errorModal,
        shadow = Shared.Shadow.modal,
        blur = Shared.Blur.strong,
        titleSize = '18px',
        bodySize = '14px',
        codeBadgeBackground = 'rgba(239, 68, 68, 0.14)',
        codeBadgeColor = '#FCA5A5',
        codeBadgeBorder = '1px solid rgba(239, 68, 68, 0.35)'
    },

    -- =============================================================
    -- لوحة اللوجات
    -- =============================================================
    LogsPanel = {
        headerBackground = 'rgba(30, 15, 50, 0.65)',
        tableBackground = Shared.Background.glass,
        rowBorder = '1px solid rgba(167, 139, 250, 0.12)',
        rowHover = 'rgba(124, 58, 237, 0.14)',
        rowPadding = '12px 14px',
        titleSize = '18px',
        textMuted = '#C4B5FD',
        radius = Shared.Radius.large,

        -- أي badge جديد يجب أن يكون متطابقًا مع مستويات اللوجات
        -- ومع القيم المعتمدة في النظام.
        badges = {
            debug = {
                background = 'rgba(148, 163, 184, 0.14)',
                color = '#CBD5E1',
                border = '1px solid rgba(148, 163, 184, 0.35)'
            },

            info = {
                background = 'rgba(56, 189, 248, 0.14)',
                color = '#7DD3FC',
                border = '1px solid rgba(56, 189, 248, 0.35)'
            },

            warn = {
                background = 'rgba(245, 158, 11, 0.14)',
                color = '#FCD34D',
                border = '1px solid rgba(245, 158, 11, 0.35)'
            },

            error = {
                background = 'rgba(239, 68, 68, 0.14)',
                color = '#FCA5A5',
                border = '1px solid rgba(239, 68, 68, 0.35)'
            },

            critical = {
                background = 'rgba(220, 38, 38, 0.20)',
                color = '#FEE2E2',
                border = '1px solid rgba(220, 38, 38, 0.55)'
            }
        }
    },

    -- =============================================================
    -- الأزرار
    -- =============================================================
    Buttons = {
        radius = Shared.Radius.small,
        padding = '10px 16px',
        fontWeight = 600,
        fontSize = '13px',

        primary = {
            background = 'linear-gradient(135deg, #7C3AED, #6D28D9)',
            color = '#FFFFFF',
            border = '1px solid rgba(255, 255, 255, 0.12)',
            hover = 'linear-gradient(135deg, #8B5CF6, #7C3AED)',
            shadow = '0 8px 24px rgba(124, 58, 237, 0.35)'
        },

        danger = {
            background = 'linear-gradient(135deg, #DC2626, #B91C1C)',
            color = '#FFFFFF',
            border = '1px solid rgba(255, 255, 255, 0.12)',
            hover = 'linear-gradient(135deg, #EF4444, #DC2626)',
            shadow = '0 8px 24px rgba(220, 38, 38, 0.35)'
        },

        ghost = {
            background = 'rgba(167, 139, 250, 0.08)',
            color = '#E9D5FF',
            border = '1px solid rgba(167, 139, 250, 0.25)',
            hover = 'rgba(167, 139, 250, 0.16)',
            shadow = 'none'
        }
    },

    -- =============================================================
    -- المدخلات
    -- =============================================================
    Inputs = {
        background = 'rgba(10, 4, 22, 0.45)',
        border = '1px solid rgba(167, 139, 250, 0.22)',
        focusBorder = '1px solid rgba(167, 139, 250, 0.65)',
        radius = Shared.Radius.small,
        padding = '10px 12px',
        color = '#F5F3FF',
        placeholder = '#9F86C0'
    },

    -- =============================================================
    -- شريط التمرير
    -- =============================================================
    Scrollbar = {
        width = '8px',
        height = '8px',
        track = 'transparent',
        thumb = 'rgba(167, 139, 250, 0.45)',
        thumbHover = 'rgba(167, 139, 250, 0.70)',
        radius = '999px'
    },

    -- =============================================================
    -- طبقات العرض
    -- =============================================================
    ZIndex = {
        notificationStack = 9100,
        glassMessage = 9200,
        errorModal = 9300,
        logsPanel = 9400,
        permissionDenied = 9500,
        loadingScreen = 9800,
        debugOverlay = 9900
    },

    -- =============================================================
    -- أنماط أنواع الرسائل
    --
    -- ملاحظة مهمة:
    -- عند إضافة نوع جديد، يجب أن تكون قيمة designStyle
    -- مطابقة لإحدى القيم الموجودة في:
    -- Config.UI.AllowedDesignStyles داخل config/main.lua
    -- =============================================================
    TypeStyles = {
        info = {
            icon = 'info',
            sound = 'notify',
            accent = '#38BDF8',
            designStyle = 'info'
        },

        success = {
            icon = 'success',
            sound = 'success',
            accent = '#22C55E',
            designStyle = 'success'
        },

        warning = {
            icon = 'warning',
            sound = 'warning',
            accent = '#F59E0B',
            designStyle = 'warning'
        },

        error = {
            icon = 'error',
            sound = 'error',
            accent = '#EF4444',
            designStyle = 'error'
        },

        critical = {
            icon = 'critical',
            sound = 'critical',
            accent = '#DC2626',
            designStyle = 'critical'
        },

        system = {
            icon = 'system',
            sound = 'notify',
            accent = '#A78BFA',
            designStyle = 'purple_glass'
        }
    },

    -- =============================================================
    -- أنماط مستويات اللوجات
    --
    -- ملاحظة مهمة:
    -- عند إضافة مستوى جديد، يجب أن تكون قيمة badge
    -- مطابقة لأحد المفاتيح الموجودة في:
    -- Config.Theme.LogsPanel.badges
    -- =============================================================
    LogLevelStyles = {
        debug = {
            color = '#CBD5E1',
            badge = 'debug'
        },

        info = {
            color = '#7DD3FC',
            badge = 'info'
        },

        warn = {
            color = '#FCD34D',
            badge = 'warn'
        },

        error = {
            color = '#FCA5A5',
            badge = 'error'
        },

        critical = {
            color = '#FEE2E2',
            badge = 'critical'
        }
    },

    -- =============================================================
    -- استجابة الشاشات
    -- =============================================================
    Responsive = {
        smallScreenWidth = 768,
        mediumScreenWidth = 1280,
        compactPadding = '10px',
        stackNotificationsOnMobile = true
    },

    -- =============================================================
    -- إمكانية الوصول
    -- =============================================================
    Accessibility = {
        focusOutline = '2px solid rgba(167, 139, 250, 0.85)',
        focusOffset = '2px',
        highContrast = false,
        respectReducedMotion = true
    }
}
