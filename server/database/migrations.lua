-- =============================================================
-- ox_lib_secure
-- File: server/database/migrations.lua
-- Description:
--   ترحيلات قاعدة البيانات لنظام ox_lib_secure.
--   تنشئ الجداول المطلوبة وتتوافق مع جميع الوحدات.
--
-- Notes:
--   - تستخدم Database.Execute مع callbacks (غير متزامن).
--   - أسماء الجداول والأعمدة متوافقة مع جميع الوحدات.
--   - تشغيل تلقائي أو يدوي حسب الإعدادات.
--   - إصلاح: جدول keywords يتضمن جميع الأعمدة المطلوبة.
--   - إصلاح: MIGRATIONS_TABLE يستخدم بادئة الجداول المخصصة.
-- =============================================================

Config = Config or {}
OxSecure = OxSecure or {}
OxSecure.Migrations = OxSecure.Migrations or {}

local Migrations = OxSecure.Migrations
local Logger = OxSecure.Logger or {}
local Database = OxSecure.Database or {}

-- =============================================================
-- قراءة الإعدادات من الكونفق
-- =============================================================
local migrationsConfig = Config.Migrations or {}
local AUTO_RUN = migrationsConfig.AutoRun ~= false
local STOP_ON_FAILURE = migrationsConfig.StopOnFailure == true

-- =============================================================
-- الحالة الداخلية
-- =============================================================
local isInitialized = false
local isRunning = false
local migrationLog = {}

-- إصلاح 2: سيتم تعيين اسم جدول الترحيلات ديناميكيًا
local MIGRATIONS_TABLE = nil

-- =============================================================
-- أدوات مساعدة داخلية
-- =============================================================
local function logMigration(message, level)
    level = level or 'info'
    if Logger and Logger.Log then
        Logger.Log(level, message, { category = 'migrations' })
    else
        print(('[ox_lib_secure] [MIGRATIONS] %s'):format(message))
    end
end

local function getTableName(name)
    if Database and Database.GetTableName then
        local ok, result = pcall(Database.GetTableName, name)
        if ok and result then
            return result
        end
    end
    return 'oxsecure_' .. name
end

-- =============================================================
-- تنفيذ استعلام باستخدام Database.Execute (غير متزامن)
-- =============================================================
local function executeQuery(sql, params, callback)
    if not Database or not Database.Execute then
        logMigration('Database.Execute not available.', 'error')
        if callback then callback(false, 'Database not available') end
        return
    end

    Database.Execute(sql, params or {}, function(result, error)
        if callback then
            if error then
                callback(false, error)
            else
                callback(true, result)
            end
        end
    end)
end

-- =============================================================
-- تنفيذ استعلام واحد باستخدام Database.Single
-- =============================================================
local function singleQuery(sql, params, callback)
    if not Database or not Database.Single then
        if callback then callback(nil) end
        return
    end

    Database.Single(sql, params or {}, function(result)
        if callback then
            callback(result)
        end
    end)
end

-- =============================================================
-- قائمة الترحيلات
-- =============================================================
local MIGRATIONS = {
    -- =============================================================
    -- 001: إنشاء جدول اللاعبين
    -- =============================================================
    {
        name = '001_create_players',
        description = 'إنشاء جدول اللاعبين الأساسي',
        table = 'players',
        sql = [[
            CREATE TABLE IF NOT EXISTS %s (
                id INT AUTO_INCREMENT PRIMARY KEY,
                display_name VARCHAR(100) DEFAULT NULL,
                primary_identifier_type VARCHAR(20) NOT NULL,
                primary_identifier_value VARCHAR(255) NOT NULL,
                first_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                last_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                is_blocked TINYINT(1) DEFAULT 0,
                block_reason VARCHAR(500) DEFAULT NULL,
                block_until TIMESTAMP NULL DEFAULT NULL,
                UNIQUE KEY unique_primary_identifier (primary_identifier_type, primary_identifier_value),
                INDEX idx_is_blocked (is_blocked),
                INDEX idx_last_seen (last_seen)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        ]]
    },

    -- =============================================================
    -- 002: إنشاء جدول أدوار اللاعبين
    -- =============================================================
    {
        name = '002_create_player_roles',
        description = 'إنشاء جدول أدوار اللاعبين',
        table = 'player_roles',
        sql = [[
            CREATE TABLE IF NOT EXISTS %s (
                id INT AUTO_INCREMENT PRIMARY KEY,
                source INT NOT NULL,
                role VARCHAR(50) NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                UNIQUE KEY unique_source (source),
                INDEX idx_role (role)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        ]]
    },

    -- =============================================================
    -- 003: إنشاء جدول جلسات اللاعبين
    -- =============================================================
    {
        name = '003_create_player_sessions',
        description = 'إنشاء جدول جلسات اللاعبين',
        table = 'player_sessions',
        sql = [[
            CREATE TABLE IF NOT EXISTS %s (
                id BIGINT AUTO_INCREMENT PRIMARY KEY,
                session_id VARCHAR(64) NOT NULL,
                player_id INT DEFAULT NULL,
                server_player_id INT DEFAULT NULL,
                connected_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                disconnected_at TIMESTAMP NULL DEFAULT NULL,
                UNIQUE KEY unique_session_id (session_id),
                INDEX idx_player_id (player_id),
                INDEX idx_server_player_id (server_player_id),
                INDEX idx_connected_at (connected_at)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        ]]
    },

    -- =============================================================
    -- 004: إنشاء جدول الأنظمة المربوطة
    -- =============================================================
    {
        name = '004_create_systems',
        description = 'إنشاء جدول الأنظمة المربوطة',
        table = 'systems',
        sql = [[
            CREATE TABLE IF NOT EXISTS %s (
                id INT AUTO_INCREMENT PRIMARY KEY,
                system_code VARCHAR(100) NOT NULL,
                display_name VARCHAR(200) DEFAULT NULL,
                secret_hash VARCHAR(128) NOT NULL,
                signing_key_hash VARCHAR(128) DEFAULT NULL,
                is_active TINYINT(1) DEFAULT 1,
                last_used_at TIMESTAMP NULL DEFAULT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                UNIQUE KEY unique_system_code (system_code),
                INDEX idx_is_active (is_active)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        ]]
    },

    -- =============================================================
    -- 005: إنشاء جدول توكنات الأنظمة
    -- =============================================================
    {
        name = '005_create_system_tokens',
        description = 'إنشاء جدول توكنات الأنظمة',
        table = 'system_tokens',
        sql = [[
            CREATE TABLE IF NOT EXISTS %s (
                id BIGINT AUTO_INCREMENT PRIMARY KEY,
                system_id INT NOT NULL,
                token_hash VARCHAR(128) NOT NULL,
                token_hint VARCHAR(16) DEFAULT NULL,
                expires_at TIMESTAMP NULL DEFAULT NULL,
                revoked_at TIMESTAMP NULL DEFAULT NULL,
                last_used_at TIMESTAMP NULL DEFAULT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                INDEX idx_system_id (system_id),
                INDEX idx_token_hash (token_hash),
                INDEX idx_expires_at (expires_at),
                INDEX idx_revoked_at (revoked_at)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        ]]
    },

    -- =============================================================
    -- 006: إنشاء جدول نطاقات الأنظمة
    -- =============================================================
    {
        name = '006_create_system_scopes',
        description = 'إنشاء جدول نطاقات الأنظمة',
        table = 'system_scopes',
        sql = [[
            CREATE TABLE IF NOT EXISTS %s (
                id BIGINT AUTO_INCREMENT PRIMARY KEY,
                system_id INT NOT NULL,
                scope_code VARCHAR(100) NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                UNIQUE KEY unique_system_scope (system_id, scope_code),
                INDEX idx_system_id (system_id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        ]]
    },

    -- =============================================================
    -- 007: إنشاء جدول الكلمات المفتاحية
    -- إصلاح 1: إضافة الأعمدة الناقصة (keyword, match_type, is_active)
    -- =============================================================
    {
        name = '007_create_keywords',
        description = 'إنشاء جدول الكلمات المفتاحية',
        table = 'keywords',
        sql = [[
            CREATE TABLE IF NOT EXISTS %s (
                id INT AUTO_INCREMENT PRIMARY KEY,
                keyword VARCHAR(255) NOT NULL,
                match_type VARCHAR(20) DEFAULT 'contains',
                design_style VARCHAR(50) DEFAULT 'default',
                title_ar VARCHAR(200) DEFAULT NULL,
                body_ar TEXT DEFAULT NULL,
                sound_name VARCHAR(50) DEFAULT NULL,
                duration_ms INT DEFAULT 5000,
                priority INT DEFAULT 0,
                is_active TINYINT(1) DEFAULT 1,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                UNIQUE KEY unique_keyword (keyword),
                INDEX idx_match_type (match_type),
                INDEX idx_priority (priority),
                INDEX idx_design_style (design_style),
                INDEX idx_is_active (is_active)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        ]]
    },

    -- =============================================================
    -- 008: إنشاء جدول قائمة الانتظار
    -- =============================================================
    {
        name = '008_create_message_queue',
        description = 'إنشاء جدول قائمة الانتظار',
        table = 'message_queue',
        sql = [[
            CREATE TABLE IF NOT EXISTS %s (
                id BIGINT AUTO_INCREMENT PRIMARY KEY,
                status VARCHAR(20) DEFAULT 'pending',
                priority INT DEFAULT 0,
                attempts INT DEFAULT 0,
                max_attempts INT DEFAULT 3,
                payload_json TEXT NOT NULL,
                last_error TEXT DEFAULT NULL,
                scheduled_at TIMESTAMP NULL DEFAULT NULL,
                expires_at TIMESTAMP NULL DEFAULT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                INDEX idx_status (status),
                INDEX idx_priority (priority),
                INDEX idx_scheduled_at (scheduled_at),
                INDEX idx_expires_at (expires_at)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        ]]
    },

    -- =============================================================
    -- 009: إنشاء جدول الإشعارات
    -- =============================================================
    {
        name = '009_create_notifications',
        description = 'إنشاء جدول الإشعارات',
        table = 'notifications',
        sql = [[
            CREATE TABLE IF NOT EXISTS %s (
                id BIGINT AUTO_INCREMENT PRIMARY KEY,
                notification_type VARCHAR(20) NOT NULL DEFAULT 'info',
                title_ar VARCHAR(200) DEFAULT NULL,
                body_ar TEXT DEFAULT NULL,
                position VARCHAR(20) DEFAULT 'left',
                design_style VARCHAR(30) DEFAULT 'default',
                player_id INT DEFAULT NULL,
                server_player_id INT DEFAULT NULL,
                discord_id VARCHAR(100) DEFAULT NULL,
                source_system_id INT DEFAULT NULL,
                keyword_id INT DEFAULT NULL,
                log_id BIGINT DEFAULT NULL,
                status VARCHAR(20) DEFAULT 'pending',
                failure_reason TEXT DEFAULT NULL,
                delivered_at TIMESTAMP NULL DEFAULT NULL,
                expires_at TIMESTAMP NULL DEFAULT NULL,
                meta_json TEXT DEFAULT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                INDEX idx_notification_type (notification_type),
                INDEX idx_player_id (player_id),
                INDEX idx_server_player_id (server_player_id),
                INDEX idx_discord_id (discord_id),
                INDEX idx_source_system_id (source_system_id),
                INDEX idx_keyword_id (keyword_id),
                INDEX idx_log_id (log_id),
                INDEX idx_status (status),
                INDEX idx_delivered_at (delivered_at),
                INDEX idx_expires_at (expires_at),
                INDEX idx_created_at (created_at)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        ]]
    },

    -- =============================================================
    -- 010: إنشاء جدول الأخطاء
    -- =============================================================
    {
        name = '010_create_errors',
        description = 'إنشاء جدول الأخطاء',
        table = 'errors',
        sql = [[
            CREATE TABLE IF NOT EXISTS %s (
                id BIGINT AUTO_INCREMENT PRIMARY KEY,
                error_code VARCHAR(50) DEFAULT NULL,
                title_ar VARCHAR(200) DEFAULT NULL,
                body_ar TEXT DEFAULT NULL,
                severity VARCHAR(20) NOT NULL DEFAULT 'error',
                design_style VARCHAR(30) DEFAULT 'error',
                source_system_id INT DEFAULT NULL,
                player_id INT DEFAULT NULL,
                server_player_id INT DEFAULT NULL,
                discord_id VARCHAR(100) DEFAULT NULL,
                log_id BIGINT DEFAULT NULL,
                stack_ref VARCHAR(100) DEFAULT NULL,
                is_handled TINYINT(1) DEFAULT 0,
                meta_json TEXT DEFAULT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                INDEX idx_error_code (error_code),
                INDEX idx_severity (severity),
                INDEX idx_source_system_id (source_system_id),
                INDEX idx_player_id (player_id),
                INDEX idx_server_player_id (server_player_id),
                INDEX idx_discord_id (discord_id),
                INDEX idx_log_id (log_id),
                INDEX idx_is_handled (is_handled),
                INDEX idx_created_at (created_at)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        ]]
    },

    -- =============================================================
    -- 011: إنشاء جدول اللوجات
    -- =============================================================
    {
        name = '011_create_logs',
        description = 'إنشاء جدول اللوجات',
        table = 'logs',
        sql = [[
            CREATE TABLE IF NOT EXISTS %s (
                id BIGINT AUTO_INCREMENT PRIMARY KEY,
                level VARCHAR(20) NOT NULL DEFAULT 'info',
                category VARCHAR(50) DEFAULT NULL,
                event_code VARCHAR(50) DEFAULT NULL,
                message TEXT NOT NULL,
                message_hash VARCHAR(64) DEFAULT NULL,
                source_system_id INT DEFAULT NULL,
                player_id INT DEFAULT NULL,
                server_player_id INT DEFAULT NULL,
                player_name VARCHAR(100) DEFAULT NULL,
                discord_id VARCHAR(100) DEFAULT NULL,
                session_id VARCHAR(64) DEFAULT NULL,
                route_name VARCHAR(100) DEFAULT NULL,
                ip_hash VARCHAR(64) DEFAULT NULL,
                is_public TINYINT(1) DEFAULT 0,
                is_resolved TINYINT(1) DEFAULT 0,
                resolved_at TIMESTAMP NULL DEFAULT NULL,
                resolved_by_admin_id INT DEFAULT NULL,
                meta_json TEXT DEFAULT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                INDEX idx_level (level),
                INDEX idx_category (category),
                INDEX idx_event_code (event_code),
                INDEX idx_message_hash (message_hash),
                INDEX idx_source_system_id (source_system_id),
                INDEX idx_player_id (player_id),
                INDEX idx_server_player_id (server_player_id),
                INDEX idx_discord_id (discord_id),
                INDEX idx_session_id (session_id),
                INDEX idx_route_name (route_name),
                INDEX idx_ip_hash (ip_hash),
                INDEX idx_is_public (is_public),
                INDEX idx_is_resolved (is_resolved),
                INDEX idx_resolved_at (resolved_at),
                INDEX idx_resolved_by_admin_id (resolved_by_admin_id),
                INDEX idx_created_at (created_at)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        ]]
    },

    -- =============================================================
    -- 012: إنشاء جدول التدقيق
    -- =============================================================
    {
        name = '012_create_audit_actions',
        description = 'إنشاء جدول التدقيق',
        table = 'audit_actions',
        sql = [[
            CREATE TABLE IF NOT EXISTS %s (
                id BIGINT AUTO_INCREMENT PRIMARY KEY,
                action_code VARCHAR(100) NOT NULL,
                actor_admin_id INT DEFAULT NULL,
                actor_discord_id VARCHAR(100) DEFAULT NULL,
                actor_player_id INT DEFAULT NULL,
                target_type VARCHAR(20) DEFAULT NULL,
                target_id VARCHAR(100) DEFAULT NULL,
                details TEXT DEFAULT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                INDEX idx_action_code (action_code),
                INDEX idx_actor_admin_id (actor_admin_id),
                INDEX idx_actor_discord_id (actor_discord_id),
                INDEX idx_actor_player_id (actor_player_id),
                INDEX idx_target_type (target_type),
                INDEX idx_target_id (target_id),
                INDEX idx_created_at (created_at)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        ]]
    },

    -- =============================================================
    -- 013: إنشاء جدول التخزين العام
    -- =============================================================
    {
        name = '013_create_storage',
        description = 'إنشاء جدول التخزين العام',
        table = 'storage',
        sql = [[
            CREATE TABLE IF NOT EXISTS %s (
                id BIGINT AUTO_INCREMENT PRIMARY KEY,
                storage_key VARCHAR(255) NOT NULL,
                value_json TEXT DEFAULT NULL,
                expires_at TIMESTAMP NULL DEFAULT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                UNIQUE KEY unique_storage_key (storage_key),
                INDEX idx_expires_at (expires_at)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        ]]
    },

    -- =============================================================
    -- 014: إنشاء جدول تدقيق معدل الطلبات
    -- =============================================================
    {
        name = '014_create_rate_limit_audit',
        description = 'إنشاء جدول تدقيق معدل الطلبات',
        table = 'rate_limit_audit',
        sql = [[
            CREATE TABLE IF NOT EXISTS %s (
                id BIGINT AUTO_INCREMENT PRIMARY KEY,
                source_type VARCHAR(20) DEFAULT 'player',
                source_id VARCHAR(100) NOT NULL,
                bucket_name VARCHAR(50) DEFAULT 'default',
                window_count INT DEFAULT 0,
                meta_json TEXT DEFAULT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                INDEX idx_source_type (source_type),
                INDEX idx_source_id (source_id),
                INDEX idx_bucket_name (bucket_name),
                INDEX idx_created_at (created_at)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        ]]
    },

    -- =============================================================
    -- 015: إنشاء جدول المحاولات الفاشلة
    -- =============================================================
    {
        name = '015_create_failed_attempts',
        description = 'إنشاء جدول المحاولات الفاشلة',
        table = 'failed_attempts',
        sql = [[
            CREATE TABLE IF NOT EXISTS %s (
                id BIGINT AUTO_INCREMENT PRIMARY KEY,
                player_id INT DEFAULT NULL,
                server_player_id INT DEFAULT NULL,
                discord_id VARCHAR(100) DEFAULT NULL,
                reason_code VARCHAR(50) DEFAULT NULL,
                ip_hash VARCHAR(64) DEFAULT NULL,
                attempt_count INT DEFAULT 1,
                first_attempt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                last_attempt TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                is_banned TINYINT(1) DEFAULT 0,
                ban_until TIMESTAMP NULL DEFAULT NULL,
                INDEX idx_player_id (player_id),
                INDEX idx_server_player_id (server_player_id),
                INDEX idx_discord_id (discord_id),
                INDEX idx_reason_code (reason_code),
                INDEX idx_ip_hash (ip_hash),
                INDEX idx_is_banned (is_banned),
                INDEX idx_ban_until (ban_until),
                INDEX idx_last_attempt (last_attempt)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        ]]
    }
}

-- =============================================================
-- إنشاء جدول الترحيلات
-- =============================================================
local function createMigrationsTable(callback)
    executeQuery(([[
        CREATE TABLE IF NOT EXISTS %s (
            id INT AUTO_INCREMENT PRIMARY KEY,
            migration_name VARCHAR(100) NOT NULL,
            applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE KEY unique_migration_name (migration_name)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]]):format(MIGRATIONS_TABLE), {}, function(ok, err)
        if callback then callback(ok, err) end
    end)
end

-- =============================================================
-- التحقق من تطبيق ترحيلة
-- =============================================================
local function isMigrationApplied(migrationName, callback)
    singleQuery(
        ('SELECT id FROM %s WHERE migration_name = ? LIMIT 1'):format(MIGRATIONS_TABLE),
        { migrationName },
        function(result)
            if callback then
                callback(result ~= nil)
            end
        end
    )
end

-- =============================================================
-- تسجيل ترحيلة مطبقة
-- =============================================================
local function recordMigration(migrationName, callback)
    executeQuery(
        ('INSERT INTO %s (migration_name) VALUES (?)'):format(MIGRATIONS_TABLE),
        { migrationName },
        function(ok, err)
            if callback then callback(ok, err) end
        end
    )
end

-- =============================================================
-- تشغيل ترحيلة واحدة
-- =============================================================
local function runSingleMigration(index, onComplete)
    if index > #MIGRATIONS then
        if onComplete then onComplete(true) end
        return
    end

    local migration = MIGRATIONS[index]
    local tableName = getTableName(migration.table)
    local sql = migration.sql:format(tableName)

    isMigrationApplied(migration.name, function(alreadyApplied)
        if alreadyApplied then
            runSingleMigration(index + 1, onComplete)
        else
            executeQuery(sql, {}, function(ok, err)
                if ok then
                    recordMigration(migration.name, function()
                        logMigration(('Applied migration: %s -> %s'):format(migration.name, tableName))
                        runSingleMigration(index + 1, onComplete)
                    end)
                else
                    logMigration(('Failed migration: %s - %s'):format(migration.name, tostring(err)), 'error')

                    migrationLog[#migrationLog + 1] = {
                        name = migration.name,
                        status = 'failed',
                        error = tostring(err),
                        timestamp = os.time()
                    }

                    if STOP_ON_FAILURE then
                        if onComplete then onComplete(false) end
                    else
                        runSingleMigration(index + 1, onComplete)
                    end
                end
            end)
        end
    end)
end

-- =============================================================
-- تشغيل جميع الترحيلات
-- =============================================================
function Migrations.Run()
    if isRunning then
        logMigration('Migrations already running.', 'warn')
        return
    end

    if isInitialized then
        logMigration('Migrations already completed.', 'warn')
        return
    end

    isRunning = true
    logMigration('Starting database migrations...')

    if not Database or not Database.Execute then
        logMigration('Database not available. Cannot run migrations.', 'error')
        isRunning = false
        return
    end

    -- إصلاح 2: تعيين اسم جدول الترحيلات ديناميكيًا
    MIGRATIONS_TABLE = getTableName('migrations')

    createMigrationsTable(function(ok, err)
        if not ok then
            logMigration(('Failed to create migrations table: %s'):format(tostring(err)), 'error')
            isRunning = false
            return
        end

        runSingleMigration(1, function(success)
            isRunning = false
            isInitialized = true

            if success == false then
                logMigration('Migrations completed with errors.', 'error')
            else
                logMigration(('Migrations completed successfully. Total: %d migrations.'):format(#MIGRATIONS))
            end
        end)
    end)
end

-- =============================================================
-- إرجاع ترحيلة واحدة
-- =============================================================
function Migrations.Rollback(migrationName, callback)
    if not migrationName then
        if callback then callback(false, 'Migration name required') end
        return
    end

    local migration = nil
    for _, m in ipairs(MIGRATIONS) do
        if m.name == migrationName then
            migration = m
            break
        end
    end

    if not migration then
        if callback then callback(false, 'Migration not found') end
        return
    end

    local tableName = getTableName(migration.table)

    executeQuery(('DROP TABLE IF EXISTS %s'):format(tableName), {}, function(ok, err)
        if ok then
            executeQuery(
                ('DELETE FROM %s WHERE migration_name = ?'):format(MIGRATIONS_TABLE),
                { migrationName },
                function()
                    logMigration(('Rolled back migration: %s (dropped %s)'):format(migrationName, tableName))
                    if callback then callback(true) end
                end
            )
        else
            logMigration(('Failed to drop table %s: %s'):format(tableName, tostring(err)), 'error')
            if callback then callback(false, 'Failed to drop table') end
        end
    end)
end

-- =============================================================
-- الحصول على حالة الترحيلات
-- =============================================================
function Migrations.GetStatus(callback)
    local result = {}
    local index = 1

    local function checkNext()
        if index > #MIGRATIONS then
            if callback then callback(result) end
            return
        end

        local migration = MIGRATIONS[index]

        isMigrationApplied(migration.name, function(applied)
            result[#result + 1] = {
                name = migration.name,
                description = migration.description,
                table = migration.table,
                applied = applied
            }
            index = index + 1
            checkNext()
        end)
    end

    checkNext()
end

-- =============================================================
-- الحصول على إحصائيات
-- =============================================================
function Migrations.GetStats(callback)
    Migrations.GetStatus(function(status)
        local applied = 0
        for _, m in ipairs(status) do
            if m.applied then
                applied = applied + 1
            end
        end

        if callback then
            callback({
                total = #MIGRATIONS,
                applied = applied,
                pending = #MIGRATIONS - applied,
                isInitialized = isInitialized,
                isRunning = isRunning,
                autoRun = AUTO_RUN,
                stopOnFailure = STOP_ON_FAILURE,
                failedMigrations = migrationLog
            })
        end
    end)
end

-- =============================================================
-- تهيئة عند التحميل
-- =============================================================
if AUTO_RUN then
    CreateThread(function()
        Wait(3000)
        Migrations.Run()
    end)
end

-- =============================================================
-- رسالة تحميل ناجحة
-- =============================================================
if Logger and Logger.Debug then
    Logger.Debug('server/database/migrations.lua loaded')
else
    print('[ox_lib_secure] server/database/migrations.lua loaded')
end
