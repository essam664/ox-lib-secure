-- =============================================================
-- ox_lib_secure
-- File: server/database/migrations.lua
-- Description:
--   نظام الترحيلات لقاعدة بيانات ox_lib_secure.
--   يدير إنشاء وتحديث الجداول بشكل تدريجي.
--
-- Notes:
--   - كل ترحيلة لها رقم إصدار فريد.
--   - يتم تنفيذ الترحيلات بالترتيب.
--   - يتم تسجيل الترحيلات المنفذة في جدول الترحيلات.
--   - إصلاح: مواءمة الجداول مع بقية الوحدات.
-- =============================================================

Config = Config or {}
OxSecure = OxSecure or {}
OxSecure.Migrations = OxSecure.Migrations or {}

local Migrations = OxSecure.Migrations
local Database = OxSecure.Database or {}
local Logger = OxSecure.Logger or {}

-- =============================================================
-- أدوات مساعدة داخلية
-- =============================================================
local function T(table)
    return Database.GetTableName(table)
end

local function logMigrationEvent(message)
    if Logger.Info then
        Logger.Info(message, {
            category = 'migration',
            eventCode = 'migration_event'
        })
    end
end

local function logMigrationError(message)
    if Logger.Error then
        Logger.Error(message, {
            category = 'migration',
            eventCode = 'migration_error'
        })
    end
end

-- =============================================================
-- إصلاح 5: تنفيذ استعلام مع دعم فعلي للمعاملات
-- =============================================================
local function executeInTransaction(query, params, callback)
    Database.Execute('START TRANSACTION', {}, function(_, startErr)
        if startErr then
            -- إذا فشل بدء المعاملة، ننفذ الاستعلام مباشرة
            Database.Execute(query, params, function(result, err)
                if err then
                    callback(false, err)
                else
                    callback(true, result)
                end
            end)
            return
        end

        Database.Execute(query, params, function(result, err)
            if err then
                Database.Execute('ROLLBACK', {}, function()
                    callback(false, err)
                end)
            else
                Database.Execute('COMMIT', {}, function(_, commitErr)
                    if commitErr then
                        callback(false, commitErr)
                    else
                        callback(true, result)
                    end
                end)
            end
        end)
    end)
end

-- =============================================================
-- قائمة الترحيلات
-- =============================================================
local migrationList = {
    -- =========================================================
    -- 001: جدول اللاعبين
    -- =========================================================
    {
        name = '001_create_players',
        version = 1,
        up = function(callback)
            local query = ([[
                CREATE TABLE IF NOT EXISTS %s (
                    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                    display_name VARCHAR(120) NOT NULL DEFAULT 'Unknown',
                    primary_identifier_type VARCHAR(32) NOT NULL,
                    primary_identifier_value VARCHAR(255) NOT NULL,
                    first_seen DATETIME(6) DEFAULT CURRENT_TIMESTAMP(6),
                    last_seen DATETIME(6) DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
                    is_blocked TINYINT(1) NOT NULL DEFAULT 0,
                    block_reason TEXT NULL,
                    block_until DATETIME(6) NULL DEFAULT NULL,
                    UNIQUE KEY unique_primary_identifier (primary_identifier_type, primary_identifier_value),
                    INDEX idx_is_blocked (is_blocked),
                    INDEX idx_last_seen (last_seen)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ]]):format(T('players'))

            executeInTransaction(query, {}, callback)
        end
    },

    -- =========================================================
    -- 002: جدول معرفات اللاعبين
    -- =========================================================
    {
        name = '002_create_player_identifiers',
        version = 2,
        up = function(callback)
            local query = ([[
                CREATE TABLE IF NOT EXISTS %s (
                    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                    player_id BIGINT UNSIGNED NOT NULL,
                    identifier_type VARCHAR(32) NOT NULL,
                    identifier_value VARCHAR(255) NOT NULL,
                    first_seen DATETIME(6) DEFAULT CURRENT_TIMESTAMP(6),
                    last_seen DATETIME(6) DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
                    UNIQUE KEY unique_identifier (identifier_type, identifier_value),
                    INDEX idx_player_id (player_id),
                    CONSTRAINT fk_player_identifiers_player FOREIGN KEY (player_id) REFERENCES %s(id) ON DELETE CASCADE
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ]]):format(T('player_identifiers'), T('players'))

            executeInTransaction(query, {}, callback)
        end
    },

    -- =========================================================
    -- 003: جدول المشرفين
    -- =========================================================
    {
        name = '003_create_admins',
        version = 3,
        up = function(callback)
            local query = ([[
                CREATE TABLE IF NOT EXISTS %s (
                    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                    player_id BIGINT UNSIGNED NULL,
                    discord_id VARCHAR(64) NULL,
                    display_name VARCHAR(120) NOT NULL DEFAULT 'Admin',
                    is_active TINYINT(1) NOT NULL DEFAULT 1,
                    created_at DATETIME(6) DEFAULT CURRENT_TIMESTAMP(6),
                    updated_at DATETIME(6) DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
                    INDEX idx_player_id (player_id),
                    INDEX idx_discord_id (discord_id),
                    INDEX idx_is_active (is_active)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ]]):format(T('admins'))

            executeInTransaction(query, {}, callback)
        end
    },

    -- =========================================================
    -- 004: جدول أدوار المشرفين (RBAC)
    -- إصلاح 1: إضافة جدول admin_roles المطلوب في
    -- permissions.lua
    -- =========================================================
    {
        name = '004_create_admin_roles',
        version = 4,
        up = function(callback)
            local query = ([[
                CREATE TABLE IF NOT EXISTS %s (
                    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                    admin_id BIGINT UNSIGNED NOT NULL,
                    role_code VARCHAR(120) NOT NULL,
                    created_at DATETIME(6) DEFAULT CURRENT_TIMESTAMP(6),
                    UNIQUE KEY unique_admin_role (admin_id, role_code),
                    INDEX idx_admin_id (admin_id),
                    CONSTRAINT fk_admin_roles_admin FOREIGN KEY (admin_id) REFERENCES %s(id) ON DELETE CASCADE
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ]]):format(T('admin_roles'), T('admins'))

            executeInTransaction(query, {}, callback)
        end
    },

    -- =========================================================
    -- 005: جدول صلاحيات الأدوار (RBAC)
    -- إصلاح 1: إضافة جدول role_permissions المطلوب في
    -- permissions.lua
    -- =========================================================
    {
        name = '005_create_role_permissions',
        version = 5,
        up = function(callback)
            local query = ([[
                CREATE TABLE IF NOT EXISTS %s (
                    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                    role_code VARCHAR(120) NOT NULL,
                    permission_code VARCHAR(120) NOT NULL,
                    created_at DATETIME(6) DEFAULT CURRENT_TIMESTAMP(6),
                    UNIQUE KEY unique_role_permission (role_code, permission_code),
                    INDEX idx_role_code (role_code)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ]]):format(T('role_permissions'))

            executeInTransaction(query, {}, callback)
        end
    },

    -- =========================================================
    -- 006: جدول صلاحيات المشرفين المباشرة
    -- =========================================================
    {
        name = '006_create_admin_permissions',
        version = 6,
        up = function(callback)
            local query = ([[
                CREATE TABLE IF NOT EXISTS %s (
                    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                    admin_id BIGINT UNSIGNED NOT NULL,
                    permission_code VARCHAR(120) NOT NULL,
                    created_at DATETIME(6) DEFAULT CURRENT_TIMESTAMP(6),
                    UNIQUE KEY unique_admin_permission (admin_id, permission_code),
                    INDEX idx_admin_id (admin_id),
                    CONSTRAINT fk_admin_permissions_admin FOREIGN KEY (admin_id) REFERENCES %s(id) ON DELETE CASCADE
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ]]):format(T('admin_permissions'), T('admins'))

            executeInTransaction(query, {}, callback)
        end
    },

    -- =========================================================
    -- 007: جدول الأنظمة المربوطة
    -- =========================================================
    {
        name = '007_create_systems',
        version = 7,
        up = function(callback)
            local query = ([[
                CREATE TABLE IF NOT EXISTS %s (
                    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                    system_code VARCHAR(64) NOT NULL,
                    display_name VARCHAR(120) NOT NULL,
                    notes TEXT NULL,
                    secret_hash VARCHAR(255) NOT NULL,
                    signing_key_hash VARCHAR(255) NULL,
                    is_active TINYINT(1) NOT NULL DEFAULT 1,
                    last_used_at DATETIME(6) NULL DEFAULT NULL,
                    created_at DATETIME(6) DEFAULT CURRENT_TIMESTAMP(6),
                    UNIQUE KEY unique_system_code (system_code),
                    INDEX idx_is_active (is_active)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ]]):format(T('systems'))

            executeInTransaction(query, {}, callback)
        end
    },

    -- =========================================================
    -- 008: جدول توكنات الأنظمة
    -- =========================================================
    {
        name = '008_create_system_tokens',
        version = 8,
        up = function(callback)
            local query = ([[
                CREATE TABLE IF NOT EXISTS %s (
                    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                    system_id BIGINT UNSIGNED NOT NULL,
                    token_hash VARCHAR(255) NOT NULL,
                    token_hint VARCHAR(16) NULL,
                    expires_at DATETIME(6) NULL DEFAULT NULL,
                    last_used_at DATETIME(6) NULL DEFAULT NULL,
                    revoked_at DATETIME(6) NULL DEFAULT NULL,
                    created_at DATETIME(6) DEFAULT CURRENT_TIMESTAMP(6),
                    UNIQUE KEY unique_token_hash (token_hash),
                    INDEX idx_system_id (system_id),
                    INDEX idx_expires_at (expires_at),
                    CONSTRAINT fk_system_tokens_system FOREIGN KEY (system_id) REFERENCES %s(id) ON DELETE CASCADE
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ]]):format(T('system_tokens'), T('systems'))

            executeInTransaction(query, {}, callback)
        end
    },

    -- =========================================================
    -- 009: جدول نطاقات الأنظمة
    -- =========================================================
    {
        name = '009_create_system_scopes',
        version = 9,
        up = function(callback)
            local query = ([[
                CREATE TABLE IF NOT EXISTS %s (
                    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                    system_id BIGINT UNSIGNED NOT NULL,
                    scope_code VARCHAR(120) NOT NULL,
                    created_at DATETIME(6) DEFAULT CURRENT_TIMESTAMP(6),
                    UNIQUE KEY unique_system_scope (system_id, scope_code),
                    INDEX idx_system_id (system_id),
                    CONSTRAINT fk_system_scopes_system FOREIGN KEY (system_id) REFERENCES %s(id) ON DELETE CASCADE
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ]]):format(T('system_scopes'), T('systems'))

            executeInTransaction(query, {}, callback)
        end
    },

    -- =========================================================
    -- 010: جدول اللوجات
    -- إصلاح 2: تغيير session_id إلى VARCHAR(64) لأنه
    -- يُمرر كنص من logs.lua
    -- =========================================================
    {
        name = '010_create_logs',
        version = 10,
        up = function(callback)
            local query = ([[
                CREATE TABLE IF NOT EXISTS %s (
                    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                    level VARCHAR(16) NOT NULL DEFAULT 'info',
                    category VARCHAR(64) NOT NULL DEFAULT 'general',
                    event_code VARCHAR(120) NOT NULL DEFAULT 'log',
                    message TEXT NOT NULL,
                    message_hash VARCHAR(128) NULL,
                    source_system_id BIGINT UNSIGNED NULL,
                    player_id BIGINT UNSIGNED NULL,
                    session_id VARCHAR(64) NULL,
                    is_public TINYINT(1) NOT NULL DEFAULT 0,
                    meta_json JSON NULL,
                    created_at DATETIME(6) DEFAULT CURRENT_TIMESTAMP(6),
                    INDEX idx_level (level),
                    INDEX idx_category (category),
                    INDEX idx_created_at (created_at),
                    INDEX idx_player_id (player_id),
                    INDEX idx_session_id (session_id)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ]]):format(T('logs'))

            executeInTransaction(query, {}, callback)
        end
    },

    -- =========================================================
    -- 011: جدول الإشعارات
    -- =========================================================
    {
        name = '011_create_notifications',
        version = 11,
        up = function(callback)
            local query = ([[
                CREATE TABLE IF NOT EXISTS %s (
                    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                    notification_type VARCHAR(32) NOT NULL DEFAULT 'info',
                    title_ar VARCHAR(255) NOT NULL DEFAULT '',
                    body_ar TEXT NOT NULL,
                    position VARCHAR(32) NOT NULL DEFAULT 'left',
                    design_style VARCHAR(64) NOT NULL DEFAULT 'default',
                    player_id BIGINT UNSIGNED NULL,
                    server_player_id INT NULL,
                    discord_id VARCHAR(64) NULL,
                    source_system_id BIGINT UNSIGNED NULL,
                    keyword_id BIGINT UNSIGNED NULL,
                    log_id BIGINT UNSIGNED NULL,
                    status VARCHAR(32) NOT NULL DEFAULT 'queued',
                    failure_reason TEXT NULL,
                    delivered_at DATETIME(6) NULL DEFAULT NULL,
                    expires_at DATETIME(6) NULL DEFAULT NULL,
                    meta_json JSON NULL,
                    created_at DATETIME(6) DEFAULT CURRENT_TIMESTAMP(6),
                    INDEX idx_notification_type (notification_type),
                    INDEX idx_status (status),
                    INDEX idx_created_at (created_at),
                    INDEX idx_player_id (player_id)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ]]):format(T('notifications'))

            executeInTransaction(query, {}, callback)
        end
    },

    -- =========================================================
    -- 012: جدول الأخطاء
    -- =========================================================
    {
        name = '012_create_errors',
        version = 12,
        up = function(callback)
            local query = ([[
                CREATE TABLE IF NOT EXISTS %s (
                    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                    error_code VARCHAR(120) NOT NULL DEFAULT 'ERR_UNKNOWN',
                    title_ar VARCHAR(255) NOT NULL DEFAULT '',
                    body_ar TEXT NOT NULL,
                    severity VARCHAR(16) NOT NULL DEFAULT 'error',
                    design_style VARCHAR(64) NOT NULL DEFAULT 'error',
                    source_system_id BIGINT UNSIGNED NULL,
                    player_id BIGINT UNSIGNED NULL,
                    server_player_id INT NULL,
                    discord_id VARCHAR(64) NULL,
                    log_id BIGINT UNSIGNED NULL,
                    stack_ref TEXT NULL,
                    is_handled TINYINT(1) NOT NULL DEFAULT 0,
                    meta_json JSON NULL,
                    created_at DATETIME(6) DEFAULT CURRENT_TIMESTAMP(6),
                    INDEX idx_error_code (error_code),
                    INDEX idx_severity (severity),
                    INDEX idx_created_at (created_at),
                    INDEX idx_player_id (player_id)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ]]):format(T('errors'))

            executeInTransaction(query, {}, callback)
        end
    },

    -- =========================================================
    -- 013: جدول الكلمات المفتاحية
    -- =========================================================
    {
        name = '013_create_keywords',
        version = 13,
        up = function(callback)
            local query = ([[
                CREATE TABLE IF NOT EXISTS %s (
                    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                    keyword VARCHAR(255) NOT NULL,
                    match_type VARCHAR(32) NOT NULL DEFAULT 'contains',
                    design_style VARCHAR(64) NULL DEFAULT NULL,
                    title_ar VARCHAR(255) NULL DEFAULT NULL,
                    body_ar TEXT NULL,
                    sound_name VARCHAR(64) NULL DEFAULT NULL,
                    duration_ms INT NULL DEFAULT NULL,
                    priority INT NOT NULL DEFAULT 0,
                    is_active TINYINT(1) NOT NULL DEFAULT 1,
                    created_at DATETIME(6) DEFAULT CURRENT_TIMESTAMP(6),
                    UNIQUE KEY unique_keyword (keyword),
                    INDEX idx_is_active (is_active),
                    INDEX idx_priority (priority)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ]]):format(T('keywords'))

            executeInTransaction(query, {}, callback)
        end
    },

    -- =========================================================
    -- 014: جدول جلسات اللاعبين
    -- =========================================================
    {
        name = '014_create_player_sessions',
        version = 14,
        up = function(callback)
            local query = ([[
                CREATE TABLE IF NOT EXISTS %s (
                    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                    session_id VARCHAR(64) NOT NULL,
                    player_id BIGINT UNSIGNED NOT NULL,
                    server_player_id INT NULL,
                    connected_at DATETIME(6) DEFAULT CURRENT_TIMESTAMP(6),
                    disconnected_at DATETIME(6) NULL DEFAULT NULL,
                    UNIQUE KEY unique_session_id (session_id),
                    INDEX idx_player_id (player_id),
                    INDEX idx_disconnected_at (disconnected_at),
                    CONSTRAINT fk_sessions_player FOREIGN KEY (player_id) REFERENCES %s(id) ON DELETE CASCADE
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ]]):format(T('player_sessions'), T('players'))

            executeInTransaction(query, {}, callback)
        end
    },

    -- =========================================================
    -- 015: جدول قائمة الانتظار
    -- =========================================================
    {
        name = '015_create_message_queue',
        version = 15,
        up = function(callback)
            local query = ([[
                CREATE TABLE IF NOT EXISTS %s (
                    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                    status VARCHAR(32) NOT NULL DEFAULT 'pending',
                    priority TINYINT UNSIGNED NOT NULL DEFAULT 0,
                    attempts INT UNSIGNED NOT NULL DEFAULT 0,
                    max_attempts INT UNSIGNED NOT NULL DEFAULT 3,
                    payload_json JSON NOT NULL,
                    last_error TEXT NULL,
                    scheduled_at DATETIME(6) NULL DEFAULT NULL,
                    processed_at DATETIME(6) NULL DEFAULT NULL,
                    expires_at DATETIME(6) NULL DEFAULT NULL,
                    created_at DATETIME(6) DEFAULT CURRENT_TIMESTAMP(6),
                    INDEX idx_status (status),
                    INDEX idx_priority (priority),
                    INDEX idx_scheduled_at (scheduled_at),
                    INDEX idx_expires_at (expires_at)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ]]):format(T('message_queue'))

            executeInTransaction(query, {}, callback)
        end
    },

    -- =========================================================
    -- 016: جدول إجراءات التدقيق
    -- =========================================================
    {
        name = '016_create_audit_actions',
        version = 16,
        up = function(callback)
            local query = ([[
                CREATE TABLE IF NOT EXISTS %s (
                    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                    action_code VARCHAR(120) NOT NULL,
                    actor_admin_id BIGINT UNSIGNED NULL,
                    actor_discord_id VARCHAR(64) NULL,
                    actor_player_id BIGINT UNSIGNED NULL,
                    target_type VARCHAR(64) NULL,
                    target_id VARCHAR(255) NULL,
                    details JSON NULL,
                    created_at DATETIME(6) DEFAULT CURRENT_TIMESTAMP(6),
                    INDEX idx_action_code (action_code),
                    INDEX idx_actor_discord_id (actor_discord_id),
                    INDEX idx_actor_player_id (actor_player_id),
                    INDEX idx_created_at (created_at)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ]]):format(T('audit_actions'))

            executeInTransaction(query, {}, callback)
        end
    },

    -- =========================================================
    -- 017: جدول المحاولات الفاشلة
    -- إصلاح 3: مواءمة الأعمدة مع Database.SaveFailedAttempt
    -- =========================================================
    {
        name = '017_create_failed_attempts',
        version = 17,
        up = function(callback)
            local query = ([[
                CREATE TABLE IF NOT EXISTS %s (
                    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                    player_id BIGINT UNSIGNED NULL,
                    server_player_id INT NULL,
                    discord_id VARCHAR(64) NULL,
                    reason_code VARCHAR(120) NOT NULL DEFAULT 'unknown',
                    ip_hash VARCHAR(128) NULL,
                    meta_json JSON NULL,
                    created_at DATETIME(6) DEFAULT CURRENT_TIMESTAMP(6),
                    INDEX idx_player_id (player_id),
                    INDEX idx_discord_id (discord_id),
                    INDEX idx_reason_code (reason_code),
                    INDEX idx_created_at (created_at)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ]]):format(T('failed_attempts'))

            executeInTransaction(query, {}, callback)
        end
    },

    -- =========================================================
    -- 018: جدول تدقيق معدل الاستخدام
    -- =========================================================
    {
        name = '018_create_rate_limit_audit',
        version = 18,
        up = function(callback)
            local query = ([[
                CREATE TABLE IF NOT EXISTS %s (
                    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                    source_type VARCHAR(32) NOT NULL DEFAULT 'player',
                    source_id VARCHAR(255) NOT NULL,
                    bucket_name VARCHAR(64) NOT NULL DEFAULT 'default',
                    window_count INT UNSIGNED NOT NULL DEFAULT 1,
                    meta_json JSON NULL,
                    created_at DATETIME(6) DEFAULT CURRENT_TIMESTAMP(6),
                    INDEX idx_source (source_type, source_id),
                    INDEX idx_bucket_name (bucket_name),
                    INDEX idx_created_at (created_at)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ]]):format(T('rate_limit_audit'))

            executeInTransaction(query, {}, callback)
        end
    },

    -- =========================================================
    -- 019: إضافة فهرس على players.block_until
    -- =========================================================
    {
        name = '019_index_players_block_until',
        version = 19,
        up = function(callback)
            local query = ('ALTER TABLE %s ADD INDEX idx_block_until (block_until)'):format(T('players'))

            executeInTransaction(query, {}, function(ok, err)
                if err and err:find('Duplicate key name') then
                    callback(true, nil)
                else
                    callback(ok, err)
                end
            end)
        end
    },

    -- =========================================================
    -- 020: إضافة فهرس على notifications.keyword_id
    -- =========================================================
    {
        name = '020_index_notifications_keyword_id',
        version = 20,
        up = function(callback)
            local query = ('ALTER TABLE %s ADD INDEX idx_keyword_id (keyword_id)'):format(T('notifications'))

            executeInTransaction(query, {}, function(ok, err)
                if err and err:find('Duplicate key name') then
                    callback(true, nil)
                else
                    callback(ok, err)
                end
            end)
        end
    },

    -- =========================================================
    -- 021: إضافة فهرس على logs.event_code
    -- =========================================================
    {
        name = '021_index_logs_event_code',
        version = 21,
        up = function(callback)
            local query = ('ALTER TABLE %s ADD INDEX idx_event_code (event_code)'):format(T('logs'))

            executeInTransaction(query, {}, function(ok, err)
                if err and err:find('Duplicate key name') then
                    callback(true, nil)
                else
                    callback(ok, err)
                end
            end)
        end
    },

    -- =========================================================
    -- 022: إضافة فهرس على systems.is_active + created_at
    -- =========================================================
    {
        name = '022_index_systems_active_created',
        version = 22,
        up = function(callback)
            local query = ('ALTER TABLE %s ADD INDEX idx_is_active_created (is_active, created_at)'):format(T('systems'))

            executeInTransaction(query, {}, function(ok, err)
                if err and err:find('Duplicate key name') then
                    callback(true, nil)
                else
                    callback(ok, err)
                end
            end)
        end
    },

    -- =========================================================
    -- 023: إضافة فهرس على message_queue.status + priority
    -- =========================================================
    {
        name = '023_index_queue_status_priority',
        version = 23,
        up = function(callback)
            local query = ('ALTER TABLE %s ADD INDEX idx_status_priority (status, priority)'):format(T('message_queue'))

            executeInTransaction(query, {}, function(ok, err)
                if err and err:find('Duplicate key name') then
                    callback(true, nil)
                else
                    callback(ok, err)
                end
            end)
        end
    },

    -- =========================================================
    -- 024: إضافة فهرس على audit_actions.target_type
    -- =========================================================
    {
        name = '024_index_audit_target_type',
        version = 24,
        up = function(callback)
            local query = ('ALTER TABLE %s ADD INDEX idx_target_type (target_type)'):format(T('audit_actions'))

            executeInTransaction(query, {}, function(ok, err)
                if err and err:find('Duplicate key name') then
                    callback(true, nil)
                else
                    callback(ok, err)
                end
            end)
        end
    },

    -- =========================================================
    -- 025: إضافة فهرس على errors.severity + created_at
    -- =========================================================
    {
        name = '025_index_errors_severity_created',
        version = 25,
        up = function(callback)
            local query = ('ALTER TABLE %s ADD INDEX idx_severity_created (severity, created_at)'):format(T('errors'))

            executeInTransaction(query, {}, function(ok, err)
                if err and err:find('Duplicate key name') then
                    callback(true, nil)
                else
                    callback(ok, err)
                end
            end)
        end
    },

    -- =========================================================
    -- 026: جدول التخزين العام (Key-Value Storage)
    -- =========================================================
    {
        name = '026_create_storage',
        version = 26,
        up = function(callback)
            local query = ([[
                CREATE TABLE IF NOT EXISTS %s (
                    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                    storage_key VARCHAR(255) NOT NULL,
                    value_json LONGTEXT NOT NULL,
                    expires_at DATETIME(6) NULL DEFAULT NULL,
                    created_at DATETIME(6) DEFAULT CURRENT_TIMESTAMP(6),
                    updated_at DATETIME(6) DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
                    UNIQUE KEY unique_storage_key (storage_key),
                    INDEX idx_expires_at (expires_at)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ]]):format(T('storage'))

            executeInTransaction(query, {}, callback)
        end
    }
}

-- =============================================================
-- إنشاء جدول الترحيلات نفسه
-- =============================================================
local function createMigrationsTable(callback)
    local query = ([[
        CREATE TABLE IF NOT EXISTS %s (
            id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
            migration_name VARCHAR(255) NOT NULL,
            version INT UNSIGNED NOT NULL,
            executed_at DATETIME(6) DEFAULT CURRENT_TIMESTAMP(6),
            UNIQUE KEY unique_version (version)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]]):format(T('migrations'))

    Database.Execute(query, {}, function(_, err)
        if err then
            logMigrationError(('Failed to create migrations table: %s'):format(tostring(err)))
            callback(false, err)
            return
        end

        callback(true, nil)
    end)
end

-- =============================================================
-- جلب آخر إصدار ترحيلة منفذة
-- =============================================================
local function getLastExecutedVersion(callback)
    local query = ('SELECT MAX(version) as last_version FROM %s'):format(T('migrations'))

    Database.Single(query, {}, function(result, err)
        if err then
            callback(0, err)
            return
        end

        local lastVersion = result and result.last_version or 0
        callback(lastVersion, nil)
    end)
end

-- =============================================================
-- تسجيل ترحيلة منفذة
-- =============================================================
local function recordMigration(name, version, callback)
    local query = ('INSERT INTO %s (migration_name, version) VALUES (?, ?)'):format(T('migrations'))

    Database.Execute(query, { name, version }, function(_, err)
        if err then
            logMigrationError(('Failed to record migration %s: %s'):format(name, tostring(err)))
        end

        if callback then callback(not err, err) end
    end)
end

-- =============================================================
-- تنفيذ جميع الترحيلات المعلقة
-- =============================================================
function Migrations.Run(callback)
    createMigrationsTable(function(ok, err)
        if not ok then
            if callback then callback(false, err) end
            return
        end

        getLastExecutedVersion(function(lastVersion, getErr)
            if getErr then
                if callback then callback(false, getErr) end
                return
            end

            -- ترتيب الترحيلات حسب الإصدار
            table.sort(migrationList, function(a, b)
                return a.version < b.version
            end)

            local pendingMigrations = {}

            for _, migration in ipairs(migrationList) do
                if migration.version > lastVersion then
                    pendingMigrations[#pendingMigrations + 1] = migration
                end
            end

            if #pendingMigrations == 0 then
                logMigrationEvent('No pending migrations.')
                if callback then callback(true, 0) end
                return
            end

            logMigrationEvent(('%d pending migration(s) found. Starting from version %d.'):format(#pendingMigrations, lastVersion + 1))

            local currentIndex = 1
            local executedCount = 0

            local function runNext()
                if currentIndex > #pendingMigrations then
                    logMigrationEvent(('All migrations completed. %d migration(s) executed.'):format(executedCount))
                    if callback then callback(true, executedCount) end
                    return
                end

                local migration = pendingMigrations[currentIndex]

                logMigrationEvent(('Running migration: %s (version %d)'):format(migration.name, migration.version))

                local ok2, err2 = pcall(function()
                    migration.up(function(migrationOk, migrationErr)
                        if migrationOk then
                            recordMigration(migration.name, migration.version, function()
                                executedCount = executedCount + 1
                                currentIndex = currentIndex + 1
                                runNext()
                            end)
                        else
                            logMigrationError(('Migration %s failed: %s'):format(migration.name, tostring(migrationErr)))
                            if callback then callback(false, migrationErr) end
                        end
                    end)
                end)

                if not ok2 then
                    logMigrationError(('Migration %s threw an error: %s'):format(migration.name, tostring(err2)))
                    if callback then callback(false, err2) end
                end
            end

            runNext()
        end)
    end)
end

-- =============================================================
-- الحصول على حالة الترحيلات
-- =============================================================
function Migrations.GetStatus(callback)
    getLastExecutedVersion(function(lastVersion, err)
        if err then
            if callback then callback({}, err) end
            return
        end

        local totalMigrations = #migrationList
        local pendingCount = 0

        for _, migration in ipairs(migrationList) do
            if migration.version > lastVersion then
                pendingCount = pendingCount + 1
            end
        end

        if callback then
            callback({
                lastVersion = lastVersion,
                totalMigrations = totalMigrations,
                pendingCount = pendingCount,
                executedCount = totalMigrations - pendingCount
            }, nil)
        end
    end)
end

-- =============================================================
-- رسالة تحميل ناجحة
-- =============================================================
if Logger.Debug then
    Logger.Debug('server/database/migrations.lua loaded')
elseif OxSecure.Console and type(OxSecure.Console.debug) == 'function' then
    OxSecure.Console.debug('server/database/migrations.lua loaded')
end
