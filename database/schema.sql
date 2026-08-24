-- =============================================================
-- ox_lib_secure
-- File: database/schema.sql
-- Description:
--   قاعدة البيانات الكاملة لنظام ox_lib_secure
--   تدعم اللوجات، الرسائل، الأخطاء، اللاعبين، الجلسات،
--   الأنظمة المربوطة، الصلاحيات، الكلمات المفتاحية،
--   منع السبام، الإعدادات، سجل الأوامر، قائمة الانتظار، والترجمة.
--
-- Architecture Notes:
--   - player_id هو المعرف الدائم للاعب.
--   - server_player_id هو معرف جلسة مؤقت فقط.
--   - runtime rate limiting يجب أن يكون داخل Lua memory أولًا.
--   - مفاتيح التشفير الرئيسية يجب أن تكون خارج قاعدة البيانات.
--   - الصلاحيات تعتمد على RBAC وليس على نص مفتوح.
--   - صلاحيات الأنظمة تعتمد على scopes وليس على نص مفصول بفواصل.
--   - يجب أن تضمن طبقة التطبيق أن جلسة اللاعب تنتمي فعلاً إلى اللاعب.
--
-- Database:
--   MySQL 8+ - InnoDB - utf8mb4
-- =============================================================

SET NAMES utf8mb4;

-- =============================================================
-- جدول إصدارات قاعدة البيانات
-- =============================================================
CREATE TABLE IF NOT EXISTS `oxsecure_schema_migrations` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `version` VARCHAR(32) NOT NULL,
  `description` VARCHAR(190) NOT NULL,
  `applied_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_oxsecure_schema_migrations_version` (`version`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================
-- جدول أنماط التصميم المرجعي
-- يجب إدخال بياناته قبل أي جدول يعتمد عليه
-- =============================================================
CREATE TABLE IF NOT EXISTS `oxsecure_design_styles` (
  `style_code` VARCHAR(20) NOT NULL,
  `label_ar` VARCHAR(100) NOT NULL,
  `description` VARCHAR(255) NULL,
  `is_active` TINYINT(1) NOT NULL DEFAULT 1,
  `sort_order` INT UNSIGNED NOT NULL DEFAULT 100,
  `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  `updated_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  PRIMARY KEY (`style_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================
-- جدول الإعدادات العامة
-- =============================================================
CREATE TABLE IF NOT EXISTS `oxsecure_settings` (
  `setting_key` VARCHAR(100) NOT NULL,
  `setting_value` LONGTEXT NULL,
  `is_encrypted` TINYINT(1) NOT NULL DEFAULT 0,
  `description` VARCHAR(255) NULL,
  `updated_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  PRIMARY KEY (`setting_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================
-- جدول مفاتيح التشفير
-- Master Key يجب أن يكون خارج قاعدة البيانات، مثل ENV أو KMS
-- =============================================================
CREATE TABLE IF NOT EXISTS `oxsecure_crypto_keys` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `key_name` VARCHAR(100) NOT NULL,
  `algorithm` VARCHAR(50) NOT NULL DEFAULT 'AES-256-GCM',
  `purpose` VARCHAR(50) NOT NULL DEFAULT 'app',
  `external_key_ref` VARCHAR(100) NULL COMMENT 'Reference to external master key, e.g. ENV name or KMS key id',
  `public_data` LONGTEXT NULL,
  `encrypted_private_data` LONGTEXT NULL COMMENT 'Must be encrypted by external master key. Do not store master key in DB.',
  `nonce` VARCHAR(64) NULL,
  `auth_tag` VARCHAR(64) NULL,
  `is_active` TINYINT(1) NOT NULL DEFAULT 1,
  `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  `rotated_at` DATETIME(6) NULL DEFAULT NULL,
  `revoked_at` DATETIME(6) NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_oxsecure_crypto_keys_key_name` (`key_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================
-- جدول الصلاحيات
-- =============================================================
CREATE TABLE IF NOT EXISTS `oxsecure_permissions` (
  `permission_code` VARCHAR(100) NOT NULL,
  `label_ar` VARCHAR(190) NOT NULL,
  `description` VARCHAR(255) NULL,
  `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  PRIMARY KEY (`permission_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================
-- جدول الأدوار
-- =============================================================
CREATE TABLE IF NOT EXISTS `oxsecure_roles` (
  `role_code` VARCHAR(50) NOT NULL,
  `label_ar` VARCHAR(100) NOT NULL,
  `description` VARCHAR(255) NULL,
  `is_active` TINYINT(1) NOT NULL DEFAULT 1,
  `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  `updated_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  PRIMARY KEY (`role_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================
-- جدول المشرفين
-- لا يوجد عمود صلاحية مفتوح؛ الصلاحيات تأتي من الأدوار
-- =============================================================
CREATE TABLE IF NOT EXISTS `oxsecure_admins` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `discord_id` VARCHAR(32) NOT NULL,
  `label` VARCHAR(100) NULL,
  `is_active` TINYINT(1) NOT NULL DEFAULT 1,
  `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  `updated_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_oxsecure_admins_discord_id` (`discord_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================
-- جدول ربط المشرفين بالأدوار
-- =============================================================
CREATE TABLE IF NOT EXISTS `oxsecure_admin_roles` (
  `admin_id` INT UNSIGNED NOT NULL,
  `role_code` VARCHAR(50) NOT NULL,
  `assigned_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  PRIMARY KEY (`admin_id`, `role_code`),
  KEY `idx_oxsecure_admin_roles_role_code` (`role_code`),
  CONSTRAINT `fk_oxsecure_admin_roles_admin`
    FOREIGN KEY (`admin_id`)
    REFERENCES `oxsecure_admins` (`id`)
    ON DELETE CASCADE,
  CONSTRAINT `fk_oxsecure_admin_roles_role`
    FOREIGN KEY (`role_code`)
    REFERENCES `oxsecure_roles` (`role_code`)
    ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================
-- جدول ربط الأدوار بالصلاحيات
-- =============================================================
CREATE TABLE IF NOT EXISTS `oxsecure_role_permissions` (
  `role_code` VARCHAR(50) NOT NULL,
  `permission_code` VARCHAR(100) NOT NULL,
  `assigned_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  PRIMARY KEY (`role_code`, `permission_code`),
  KEY `idx_oxsecure_role_permissions_permission_code` (`permission_code`),
  CONSTRAINT `fk_oxsecure_role_permissions_role`
    FOREIGN KEY (`role_code`)
    REFERENCES `oxsecure_roles` (`role_code`)
    ON DELETE CASCADE,
  CONSTRAINT `fk_oxsecure_role_permissions_permission`
    FOREIGN KEY (`permission_code`)
    REFERENCES `oxsecure_permissions` (`permission_code`)
    ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================
-- جدول صلاحيات الأنظمة المربوطة
-- =============================================================
CREATE TABLE IF NOT EXISTS `oxsecure_scopes` (
  `scope_code` VARCHAR(100) NOT NULL,
  `label_ar` VARCHAR(190) NOT NULL,
  `description` VARCHAR(255) NULL,
  `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  PRIMARY KEY (`scope_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================
-- جدول الأنظمة المربوطة
-- =============================================================
CREATE TABLE IF NOT EXISTS `oxsecure_systems` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `system_code` VARCHAR(64) NOT NULL,
  `display_name` VARCHAR(120) NOT NULL,
  `secret_hash` CHAR(64) NOT NULL,
  `signing_key_hash` CHAR(64) NULL,
  `max_per_window` INT UNSIGNED NOT NULL DEFAULT 30,
  `window_seconds` INT UNSIGNED NOT NULL DEFAULT 10,
  `is_active` TINYINT(1) NOT NULL DEFAULT 1,
  `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  `last_used_at` DATETIME(6) NULL DEFAULT NULL,
  `notes` VARCHAR(255) NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_oxsecure_systems_system_code` (`system_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================
-- جدول ربط الأنظمة بالصلاحيات
-- =============================================================
CREATE TABLE IF NOT EXISTS `oxsecure_system_scopes` (
  `system_id` INT UNSIGNED NOT NULL,
  `scope_code` VARCHAR(100) NOT NULL,
  `granted_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  PRIMARY KEY (`system_id`, `scope_code`),
  KEY `idx_oxsecure_system_scopes_scope_code` (`scope_code`),
  CONSTRAINT `fk_oxsecure_system_scopes_system`
    FOREIGN KEY (`system_id`)
    REFERENCES `oxsecure_systems` (`id`)
    ON DELETE CASCADE,
  CONSTRAINT `fk_oxsecure_system_scopes_scope`
    FOREIGN KEY (`scope_code`)
    REFERENCES `oxsecure_scopes` (`scope_code`)
    ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================
-- جدول توكنات الأنظمة المربوطة
-- =============================================================
CREATE TABLE IF NOT EXISTS `oxsecure_system_tokens` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `system_id` INT UNSIGNED NOT NULL,
  `token_hash` CHAR(64) NOT NULL,
  `token_hint` VARCHAR(12) NOT NULL,
  `expires_at` DATETIME(6) NULL DEFAULT NULL,
  `revoked_at` DATETIME(6) NULL DEFAULT NULL,
  `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  `last_used_at` DATETIME(6) NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_oxsecure_system_tokens_token_hash` (`token_hash`),
  KEY `idx_oxsecure_system_tokens_system_id` (`system_id`),
  CONSTRAINT `fk_oxsecure_system_tokens_system`
    FOREIGN KEY (`system_id`)
    REFERENCES `oxsecure_systems` (`id`)
    ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================
-- جدول اللاعبين
-- يحتوي على المعرف الأساسي الثابت للاعب.
-- لا يتم الاعتماد على server_player_id كمعرّف دائم.
-- =============================================================
CREATE TABLE IF NOT EXISTS `oxsecure_players` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `display_name` VARCHAR(100) NULL,
  `primary_identifier_type` ENUM('license', 'license2', 'discord', 'fivem', 'xbl', 'steam', 'live') NOT NULL DEFAULT 'license',
  `primary_identifier_value` VARCHAR(255) NOT NULL,
  `first_seen` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  `last_seen` DATETIME(6) NULL DEFAULT NULL,
  `is_blocked` TINYINT(1) NOT NULL DEFAULT 0,
  `block_reason` VARCHAR(190) NULL,
  `block_until` DATETIME(6) NULL DEFAULT NULL,
  `notes` VARCHAR(255) NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_oxsecure_players_primary_identifier` (`primary_identifier_type`, `primary_identifier_value`),
  KEY `idx_oxsecure_players_is_blocked` (`is_blocked`),
  KEY `idx_oxsecure_players_last_seen` (`last_seen`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================
-- جدول معرفات اللاعبين
-- يخزن المعرفات الثابتة المرتبطة باللاعب.
-- لا يُستخدم لتخزين معرفات الجلسة المؤقتة.
-- =============================================================
CREATE TABLE IF NOT EXISTS `oxsecure_player_identifiers` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `player_id` BIGINT UNSIGNED NOT NULL,
  `identifier_type` ENUM('license', 'license2', 'discord', 'fivem', 'xbl', 'steam', 'live') NOT NULL,
  `identifier_value` VARCHAR(255) NOT NULL,
  `first_seen` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  `last_seen` DATETIME(6) NULL DEFAULT NULL,
  `updated_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_oxsecure_player_identifiers_identifier` (`identifier_type`, `identifier_value`),
  KEY `idx_oxsecure_player_identifiers_player_id` (`player_id`),
  CONSTRAINT `fk_oxsecure_player_identifiers_player`
    FOREIGN KEY (`player_id`)
    REFERENCES `oxsecure_players` (`id`)
    ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================
-- جدول جلسات اللاعبين
-- يحفظ تاريخ الجلسات ويربطها باللاعب الدائم.
-- لا يجب استخدام 0 كقيمة server_player_id.
-- =============================================================
CREATE TABLE IF NOT EXISTS `oxsecure_player_sessions` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `session_id` VARCHAR(64) NOT NULL,
  `player_id` BIGINT UNSIGNED NOT NULL,
  `server_player_id` INT UNSIGNED NOT NULL COMMENT 'Session/runtime identifier only - not persistent',
  `connected_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  `disconnected_at` DATETIME(6) NULL DEFAULT NULL,
  `endpoint_hash` CHAR(64) NULL,
  `connect_reason` VARCHAR(100) NULL,
  `disconnect_reason` VARCHAR(100) NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_oxsecure_player_sessions_session_id` (`session_id`),
  KEY `idx_oxsecure_player_sessions_player_id` (`player_id`),
  KEY `idx_oxsecure_player_sessions_server_player_id` (`server_player_id`),
  KEY `idx_oxsecure_player_sessions_connected_at` (`connected_at`),
  CONSTRAINT `fk_oxsecure_player_sessions_player`
    FOREIGN KEY (`player_id`)
    REFERENCES `oxsecure_players` (`id`)
    ON DELETE CASCADE,
  CONSTRAINT `chk_oxsecure_player_sessions_server_player_id`
    CHECK (`server_player_id` > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================
-- جدول الترجمة
-- =============================================================
CREATE TABLE IF NOT EXISTS `oxsecure_locale_strings` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `locale` VARCHAR(5) NOT NULL DEFAULT 'ar',
  `string_key` VARCHAR(190) NOT NULL,
  `string_value` LONGTEXT NOT NULL,
  `updated_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_oxsecure_locale_strings_locale_key` (`locale`, `string_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================
-- كتالوج الأخطاء المعربة
-- =============================================================
CREATE TABLE IF NOT EXISTS `oxsecure_error_catalog` (
  `error_code` VARCHAR(100) NOT NULL,
  `severity` ENUM('info', 'warning', 'error', 'critical') NOT NULL DEFAULT 'error',
  `title_ar` VARCHAR(190) NOT NULL,
  `body_ar` TEXT NOT NULL,
  `design_style` VARCHAR(20) NOT NULL DEFAULT 'error',
  `duration_ms` INT UNSIGNED NOT NULL DEFAULT 6000,
  `is_active` TINYINT(1) NOT NULL DEFAULT 1,
  `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  `updated_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  PRIMARY KEY (`error_code`),
  KEY `idx_oxsecure_error_catalog_design_style` (`design_style`),
  CONSTRAINT `fk_oxsecure_error_catalog_design_style`
    FOREIGN KEY (`design_style`)
    REFERENCES `oxsecure_design_styles` (`style_code`)
    ON UPDATE CASCADE
    ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================
-- جدول الكلمات المفتاحية
-- إذا وصلت رسالة تحتوي كلمة معينة، يمكن تغيير تصميمها
-- =============================================================
CREATE TABLE IF NOT EXISTS `oxsecure_keywords` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `keyword` VARCHAR(190) NOT NULL,
  `match_type` ENUM('contains', 'exact', 'starts_with', 'ends_with') NOT NULL DEFAULT 'contains',
  `design_style` VARCHAR(20) NOT NULL DEFAULT 'critical',
  `title_ar` VARCHAR(190) NULL,
  `body_ar` TEXT NULL,
  `sound_name` VARCHAR(50) NULL,
  `duration_ms` INT UNSIGNED NOT NULL DEFAULT 6000,
  `priority` INT UNSIGNED NOT NULL DEFAULT 100,
  `is_active` TINYINT(1) NOT NULL DEFAULT 1,
  `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_oxsecure_keywords_keyword_match` (`keyword`, `match_type`),
  KEY `idx_oxsecure_keywords_active_priority` (`is_active`, `priority`),
  KEY `idx_oxsecure_keywords_design_style` (`design_style`),
  CONSTRAINT `fk_oxsecure_keywords_design_style`
    FOREIGN KEY (`design_style`)
    REFERENCES `oxsecure_design_styles` (`style_code`)
    ON UPDATE CASCADE
    ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================
-- جدول اللوجات الرئيسي
-- server_player_id معرف جلسة مؤقت فقط.
-- يمكن ربط اللوج بجلسة عن طريق session_id عندما تتوفر.
-- قيد CHECK يمنع وجود جلسة بدون لاعب، لكن يجب على طبقة التطبيق
-- التأكد أن الجلسة تنتمي فعلاً إلى نفس اللاعب.
-- =============================================================
CREATE TABLE IF NOT EXISTS `oxsecure_logs` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  `level` ENUM('debug', 'info', 'warn', 'error', 'critical') NOT NULL DEFAULT 'info',
  `category` VARCHAR(50) NOT NULL DEFAULT 'general',
  `event_code` VARCHAR(100) NOT NULL,
  `message` TEXT NOT NULL,
  `message_hash` CHAR(64) NULL,
  `source_system_id` INT UNSIGNED NULL,
  `player_id` BIGINT UNSIGNED NULL,
  `session_id` VARCHAR(64) NULL,
  `server_player_id` INT UNSIGNED NULL COMMENT 'Session/runtime identifier only - not persistent',
  `player_name` VARCHAR(100) NULL,
  `discord_id` VARCHAR(32) NULL,
  `route_name` VARCHAR(100) NULL,
  `ip_hash` CHAR(64) NULL,
  `meta_json` JSON NULL,
  `is_public` TINYINT(1) NOT NULL DEFAULT 0,
  `is_resolved` TINYINT(1) NOT NULL DEFAULT 0,
  `resolved_at` DATETIME(6) NULL DEFAULT NULL,
  `resolved_by_admin_id` INT UNSIGNED NULL,
  PRIMARY KEY (`id`),
  KEY `idx_oxsecure_logs_created_at` (`created_at`),
  KEY `idx_oxsecure_logs_level` (`level`),
  KEY `idx_oxsecure_logs_category` (`category`),
  KEY `idx_oxsecure_logs_event_code` (`event_code`),
  KEY `idx_oxsecure_logs_player_id` (`player_id`),
  KEY `idx_oxsecure_logs_session_id` (`session_id`),
  KEY `idx_oxsecure_logs_source_system_id` (`source_system_id`),
  KEY `idx_oxsecure_logs_discord_id` (`discord_id`),
  KEY `idx_oxsecure_logs_message_hash` (`message_hash`),
  KEY `idx_oxsecure_logs_is_public` (`is_public`),
  CONSTRAINT `fk_oxsecure_logs_system`
    FOREIGN KEY (`source_system_id`)
    REFERENCES `oxsecure_systems` (`id`)
    ON DELETE SET NULL,
  CONSTRAINT `fk_oxsecure_logs_player`
    FOREIGN KEY (`player_id`)
    REFERENCES `oxsecure_players` (`id`)
    ON DELETE SET NULL,
  CONSTRAINT `fk_oxsecure_logs_session`
    FOREIGN KEY (`session_id`)
    REFERENCES `oxsecure_player_sessions` (`session_id`)
    ON DELETE SET NULL,
  CONSTRAINT `fk_oxsecure_logs_resolver_admin`
    FOREIGN KEY (`resolved_by_admin_id`)
    REFERENCES `oxsecure_admins` (`id`)
    ON DELETE SET NULL,
  CONSTRAINT `chk_oxsecure_logs_session_requires_player`
    CHECK ((`session_id` IS NULL) OR (`player_id` IS NOT NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================
-- جدول الإشعارات المرسلة
-- =============================================================
CREATE TABLE IF NOT EXISTS `oxsecure_notifications` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  `player_id` BIGINT UNSIGNED NULL,
  `server_player_id` INT UNSIGNED NULL COMMENT 'Session/runtime identifier only - not persistent',
  `discord_id` VARCHAR(32) NULL,
  `source_system_id` INT UNSIGNED NULL,
  `notification_type` ENUM('info', 'success', 'warning', 'error', 'critical', 'system') NOT NULL DEFAULT 'info',
  `design_style` VARCHAR(20) NOT NULL DEFAULT 'glass',
  `position` ENUM('left', 'right', 'top', 'bottom', 'center') NOT NULL DEFAULT 'left',
  `title_ar` VARCHAR(190) NOT NULL,
  `body_ar` TEXT NOT NULL,
  `keyword_id` INT UNSIGNED NULL,
  `log_id` BIGINT UNSIGNED NULL,
  `status` ENUM('queued', 'delivered', 'failed', 'expired') NOT NULL DEFAULT 'queued',
  `failure_reason` VARCHAR(190) NULL,
  `delivered_at` DATETIME(6) NULL DEFAULT NULL,
  `expires_at` DATETIME(6) NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_oxsecure_notifications_player_id` (`player_id`),
  KEY `idx_oxsecure_notifications_status` (`status`),
  KEY `idx_oxsecure_notifications_created_at` (`created_at`),
  KEY `idx_oxsecure_notifications_design_style` (`design_style`),
  CONSTRAINT `fk_oxsecure_notifications_player`
    FOREIGN KEY (`player_id`)
    REFERENCES `oxsecure_players` (`id`)
    ON DELETE SET NULL,
  CONSTRAINT `fk_oxsecure_notifications_system`
    FOREIGN KEY (`source_system_id`)
    REFERENCES `oxsecure_systems` (`id`)
    ON DELETE SET NULL,
  CONSTRAINT `fk_oxsecure_notifications_keyword`
    FOREIGN KEY (`keyword_id`)
    REFERENCES `oxsecure_keywords` (`id`)
    ON DELETE SET NULL,
  CONSTRAINT `fk_oxsecure_notifications_log`
    FOREIGN KEY (`log_id`)
    REFERENCES `oxsecure_logs` (`id`)
    ON DELETE SET NULL,
  CONSTRAINT `fk_oxsecure_notifications_design_style`
    FOREIGN KEY (`design_style`)
    REFERENCES `oxsecure_design_styles` (`style_code`)
    ON UPDATE CASCADE
    ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================
-- جدول الأخطاء
-- =============================================================
CREATE TABLE IF NOT EXISTS `oxsecure_errors` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  `error_code` VARCHAR(100) NOT NULL,
  `severity` ENUM('info', 'warning', 'error', 'critical') NOT NULL DEFAULT 'error',
  `title_ar` VARCHAR(190) NOT NULL,
  `body_ar` TEXT NOT NULL,
  `player_id` BIGINT UNSIGNED NULL,
  `server_player_id` INT UNSIGNED NULL COMMENT 'Session/runtime identifier only - not persistent',
  `discord_id` VARCHAR(32) NULL,
  `source_system_id` INT UNSIGNED NULL,
  `log_id` BIGINT UNSIGNED NULL,
  `stack_ref` VARCHAR(190) NULL,
  `meta_json` JSON NULL,
  `is_handled` TINYINT(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (`id`),
  KEY `idx_oxsecure_errors_error_code` (`error_code`),
  KEY `idx_oxsecure_errors_severity` (`severity`),
  KEY `idx_oxsecure_errors_player_id` (`player_id`),
  KEY `idx_oxsecure_errors_created_at` (`created_at`),
  CONSTRAINT `fk_oxsecure_errors_player`
    FOREIGN KEY (`player_id`)
    REFERENCES `oxsecure_players` (`id`)
    ON DELETE SET NULL,
  CONSTRAINT `fk_oxsecure_errors_system`
    FOREIGN KEY (`source_system_id`)
    REFERENCES `oxsecure_systems` (`id`)
    ON DELETE SET NULL,
  CONSTRAINT `fk_oxsecure_errors_log`
    FOREIGN KEY (`log_id`)
    REFERENCES `oxsecure_logs` (`id`)
    ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================
-- جدول منع السبام / معدل الاستخدام
-- مهم:
--   لا يجب الاعتماد على قاعدة البيانات لكل طلب.
--   الأفضل أن يكون هناك Lua Memory Rate Limiter أولًا،
--   ثم تُسجل النتيجة هنا عند الحاجة فقط.
-- =============================================================
CREATE TABLE IF NOT EXISTS `oxsecure_rate_limits` (
  `bucket_key` CHAR(64) NOT NULL,
  `window_start` DATETIME(6) NOT NULL,
  `hits` INT UNSIGNED NOT NULL DEFAULT 1,
  `updated_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  PRIMARY KEY (`bucket_key`, `window_start`),
  KEY `idx_oxsecure_rate_limits_bucket_key` (`bucket_key`),
  KEY `idx_oxsecure_rate_limits_window_start` (`window_start`),
  KEY `idx_oxsecure_rate_limits_updated_at` (`updated_at`),
  CONSTRAINT `chk_oxsecure_rate_limits_hits`
    CHECK (`hits` > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================
-- جدول المحاولات الفاشلة
-- =============================================================
CREATE TABLE IF NOT EXISTS `oxsecure_failed_attempts` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  `player_id` BIGINT UNSIGNED NULL,
  `server_player_id` INT UNSIGNED NULL COMMENT 'Session/runtime identifier only - not persistent',
  `discord_id` VARCHAR(32) NULL,
  `reason_code` VARCHAR(100) NOT NULL,
  `details` JSON NULL,
  `ip_hash` CHAR(64) NULL,
  PRIMARY KEY (`id`),
  KEY `idx_oxsecure_failed_attempts_player_id` (`player_id`),
  KEY `idx_oxsecure_failed_attempts_reason_code` (`reason_code`),
  KEY `idx_oxsecure_failed_attempts_created_at` (`created_at`),
  CONSTRAINT `fk_oxsecure_failed_attempts_player`
    FOREIGN KEY (`player_id`)
    REFERENCES `oxsecure_players` (`id`)
    ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================
-- جدول سجل العمليات الإدارية
-- =============================================================
CREATE TABLE IF NOT EXISTS `oxsecure_audit_actions` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  `actor_admin_id` INT UNSIGNED NULL,
  `actor_discord_id` VARCHAR(32) NULL,
  `actor_player_id` BIGINT UNSIGNED NULL,
  `action_code` VARCHAR(100) NOT NULL,
  `target_type` VARCHAR(50) NULL,
  `target_id` VARCHAR(100) NULL,
  `details` JSON NULL,
  PRIMARY KEY (`id`),
  KEY `idx_oxsecure_audit_actions_action_code` (`action_code`),
  KEY `idx_oxsecure_audit_actions_actor_discord_id` (`actor_discord_id`),
  KEY `idx_oxsecure_audit_actions_created_at` (`created_at`),
  CONSTRAINT `fk_oxsecure_audit_actions_admin`
    FOREIGN KEY (`actor_admin_id`)
    REFERENCES `oxsecure_admins` (`id`)
    ON DELETE SET NULL,
  CONSTRAINT `fk_oxsecure_audit_actions_player`
    FOREIGN KEY (`actor_player_id`)
    REFERENCES `oxsecure_players` (`id`)
    ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================
-- جدول سجل الأوامر
-- =============================================================
CREATE TABLE IF NOT EXISTS `oxsecure_command_history` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  `command_name` VARCHAR(100) NOT NULL,
  `player_id` BIGINT UNSIGNED NULL,
  `server_player_id` INT UNSIGNED NULL COMMENT 'Session/runtime identifier only - not persistent',
  `discord_id` VARCHAR(32) NULL,
  `is_allowed` TINYINT(1) NOT NULL DEFAULT 0,
  `args_json` JSON NULL,
  PRIMARY KEY (`id`),
  KEY `idx_oxsecure_command_history_command_name` (`command_name`),
  KEY `idx_oxsecure_command_history_player_id` (`player_id`),
  KEY `idx_oxsecure_command_history_created_at` (`created_at`),
  CONSTRAINT `fk_oxsecure_command_history_player`
    FOREIGN KEY (`player_id`)
    REFERENCES `oxsecure_players` (`id`)
    ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================
-- جدول جلسات الواجهة
-- =============================================================
CREATE TABLE IF NOT EXISTS `oxsecure_ui_sessions` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `opened_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  `closed_at` DATETIME(6) NULL DEFAULT NULL,
  `player_id` BIGINT UNSIGNED NULL,
  `server_player_id` INT UNSIGNED NULL COMMENT 'Session/runtime identifier only - not persistent',
  `discord_id` VARCHAR(32) NULL,
  `ui_name` VARCHAR(50) NOT NULL DEFAULT 'logs_panel',
  `allowed` TINYINT(1) NOT NULL DEFAULT 0,
  `reason_code` VARCHAR(100) NULL,
  PRIMARY KEY (`id`),
  KEY `idx_oxsecure_ui_sessions_player_id` (`player_id`),
  KEY `idx_oxsecure_ui_sessions_opened_at` (`opened_at`),
  CONSTRAINT `fk_oxsecure_ui_sessions_player`
    FOREIGN KEY (`player_id`)
    REFERENCES `oxsecure_players` (`id`)
    ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================
-- جدول قائمة انتظار الرسائل
-- يساعد على الأداء ومنع الضغط عند كثرة الرسائل.
-- تتم المعالجة بواسطة عامل خارجي أو عامل مجدول وليس بالضرورة
-- داخل نفس العملية الحالية.
-- =============================================================
CREATE TABLE IF NOT EXISTS `oxsecure_message_queue` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  `scheduled_at` DATETIME(6) NULL DEFAULT NULL,
  `status` ENUM('pending', 'processing', 'completed', 'failed', 'cancelled', 'expired') NOT NULL DEFAULT 'pending',
  `priority` INT UNSIGNED NOT NULL DEFAULT 100,
  `attempts` INT UNSIGNED NOT NULL DEFAULT 0,
  `max_attempts` INT UNSIGNED NOT NULL DEFAULT 3,
  `payload_json` JSON NOT NULL,
  `last_error` JSON NULL,
  `processed_at` DATETIME(6) NULL DEFAULT NULL,
  `expires_at` DATETIME(6) NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_oxsecure_message_queue_status_priority` (`status`, `priority`, `scheduled_at`),
  KEY `idx_oxsecure_message_queue_expires_at` (`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================
-- إدخال إصدار قاعدة البيانات
-- =============================================================
INSERT IGNORE INTO `oxsecure_schema_migrations` (`version`, `description`)
VALUES ('1.0.0', 'Initial ox_lib_secure schema');

-- =============================================================
-- إدخال أنماط التصميم المعتمدة
-- يجب أن تكون قبل أي بيانات تعتمد عليها
-- =============================================================
INSERT IGNORE INTO `oxsecure_design_styles` (`style_code`, `label_ar`, `description`, `is_active`, `sort_order`) VALUES
('default', 'افتراضي', 'التصميم الافتراضي للنظام', 1, 1),
('purple_glass', 'بنفسجي زجاجي', 'الثيم الرئيسي للنظام: زجاجي بنفسجي', 1, 2),
('glass', 'زجاجي', 'رسالة زجاجية شفافة', 1, 3),
('critical', 'حرج', 'رسالة حمراء قوية للتنبيهات الحرجة', 1, 4),
('purple', 'بنفسجي', 'رسالة بنفسجية مميزة', 1, 5),
('gold', 'ذهبي', 'رسالة ذهبية فاخرة', 1, 6),
('info', 'معلومات', 'رسالة معلومات', 1, 7),
('warning', 'تحذير', 'رسالة تحذير', 1, 8),
('success', 'نجاح', 'رسالة نجاح', 1, 9),
('error', 'خطأ', 'رسالة خطأ', 1, 10);

-- =============================================================
-- إدخال الصلاحيات
-- =============================================================
INSERT IGNORE INTO `oxsecure_permissions` (`permission_code`, `label_ar`, `description`) VALUES
('ui.open', 'فتح لوحة النظام', 'يسمح بفتح لوحة الإدارة'),
('logs.read', 'قراءة اللوجات', 'يسمح بعرض اللوجات'),
('logs.delete', 'حذف اللوجات', 'يسمح بحذف اللوجات'),
('logs.export', 'تصدير اللوجات', 'يسمح بتصدير اللوجات'),
('players.block', 'حظر اللاعبين', 'يسمح بحظر اللاعبين'),
('players.unblock', 'فك حظر اللاعبين', 'يسمح بفك حظر اللاعبين'),
('systems.manage', 'إدارة الأنظمة', 'يسمح بإدارة الأنظمة المربوطة'),
('tokens.manage', 'إدارة التوكنات', 'يسمح بإدارة توكنات الأنظمة'),
('settings.manage', 'إدارة الإعدادات', 'يسمح بتعديل إعدادات النظام');

-- =============================================================
-- إدخال الأدوار
-- =============================================================
INSERT IGNORE INTO `oxsecure_roles` (`role_code`, `label_ar`, `description`, `is_active`) VALUES
('owner', 'المالك', 'صلاحية كاملة على النظام', 1),
('admin', 'مشرف', 'صلاحيات إدارية قابلة للتخصيص', 1),
('moderator', 'مراقب', 'صلاحيات مراقبة قابلة للتخصيص', 1);

-- =============================================================
-- إدخال المشرف الأساسي
-- =============================================================
INSERT IGNORE INTO `oxsecure_admins` (`discord_id`, `label`, `is_active`)
VALUES ('1249662830568013825', 'Owner', 1);

-- =============================================================
-- ربط المشرف الأساسي بدور المالك
-- =============================================================
INSERT IGNORE INTO `oxsecure_admin_roles` (`admin_id`, `role_code`)
SELECT `id`, 'owner'
FROM `oxsecure_admins`
WHERE `discord_id` = '1249662830568013825';

-- =============================================================
-- إعطاء دور المالك جميع الصلاحيات الحالية
-- =============================================================
INSERT IGNORE INTO `oxsecure_role_permissions` (`role_code`, `permission_code`)
SELECT 'owner', `permission_code`
FROM `oxsecure_permissions`;

-- =============================================================
-- إدخال صلاحيات الأنظمة المربوطة
-- =============================================================
INSERT IGNORE INTO `oxsecure_scopes` (`scope_code`, `label_ar`, `description`) VALUES
('notify.send', 'إرسال إشعارات', 'يسمح للنظام بإرسال إشعارات إلى اللاعبين'),
('errors.report', 'الإبلاغ عن الأخطاء', 'يسمح للنظام بإرسال أخطاء إلى النظام المركزي'),
('logs.write', 'كتابة اللوجات', 'يسمح للنظام بكتابة لوجات داخل النظام المركزي');

-- =============================================================
-- الإعدادات الافتراضية
-- =============================================================
INSERT IGNORE INTO `oxsecure_settings` (`setting_key`, `setting_value`, `is_encrypted`, `description`) VALUES
('core.version', '1.0.0', 0, 'إصدار النظام'),
('core.language', 'ar', 0, 'اللغة الافتراضية'),
('ui.theme', 'purple_glass', 0, 'الثيم الأساسي'),
('ui.position', 'left', 0, 'مكان الإشعارات'),
('ui.rtl', '1', 0, 'تفعيل الاتجاه العربي'),
('security.rate_limit.window_seconds', '10', 0, 'نافذة معدل الاستخدام بالثواني'),
('security.rate_limit.max_per_window', '20', 0, 'أقصى عمليات داخل النافذة'),
('security.rate_limit.use_memory_limiter', '1', 0, 'استخدام محدد معدل في الذاكرة قبل قاعدة البيانات'),
('security.failed_attempts.max', '10', 0, 'أقصى محاولات فاشلة قبل الإجراء'),
('security.failed_attempts.ban_minutes', '30', 0, 'مدة الحجز بعد تجاوز المحاولات'),
('security.master_key.env_name', 'OXSECURE_MASTER_KEY', 0, 'اسم متغير البيئة لمفتاح التشفير الرئيسي'),
('logs.save_to_database', '1', 0, 'حفظ اللوجات في قاعدة البيانات'),
('logs.save_to_console', '1', 0, 'عرض اللوجات في الكونسول'),
('keywords.enabled', '1', 0, 'تفعيل قواعد الكلمات المفتاحية'),
('players.track_last_seen', '1', 0, 'تتبع آخر ظهور للاعبين'),
('queue.enabled', '1', 0, 'تفعيل قائمة الإرسال');

-- =============================================================
-- كتالوج الأخطاء المعربة الافتراضي
-- تم إدخاله بعد oxsecure_design_styles لاحترام العلاقة الخارجية
-- =============================================================
INSERT IGNORE INTO `oxsecure_error_catalog` (`error_code`, `severity`, `title_ar`, `body_ar`, `design_style`, `duration_ms`, `is_active`) VALUES
('ERR_UNKNOWN', 'error', 'خطأ غير معروف', 'حدث خطأ غير متوقع في النظام. تم تسجيل المشكلة.', 'error', 6000, 1),
('ERR_PERMISSION_DENIED', 'critical', 'رفض الصلاحية', 'لا تملك صلاحية كافية لتنفيذ هذا الإجراء.', 'critical', 7000, 1),
('ERR_UNAUTHORIZED_SYSTEM', 'critical', 'نظام غير مصرح به', 'النظام المرسل غير مصرح له باستخدام هذا النظام.', 'critical', 7000, 1),
('ERR_INVALID_PAYLOAD', 'error', 'بيانات غير صالحة', 'البيانات المرسلة إلى النظام غير صالحة أو ناقصة.', 'error', 6000, 1),
('ERR_VALIDATION_FAILED', 'error', 'فشل التحقق', 'فشل التحقق من البيانات المرسلة.', 'error', 6000, 1),
('ERR_RATE_LIMIT', 'warning', 'تجاوز الحد المسموح', 'تم تجاوز الحد المسموح من الطلبات. حاول لاحقًا.', 'warning', 6000, 1),
('ERR_DB_FAILURE', 'critical', 'خطأ في قاعدة البيانات', 'حدث خطأ أثناء التعامل مع قاعدة البيانات.', 'critical', 8000, 1),
('ERR_TOKEN_INVALID', 'critical', 'توكن غير صالح', 'رمز الوصول غير صالح أو تم رفضه.', 'critical', 7000, 1),
('ERR_TOKEN_EXPIRED', 'error', 'انتهاء صلاحية التوكن', 'انتهت صلاحية رمز الوصول المستخدم.', 'error', 6000, 1),
('ERR_UI_FAILED', 'error', 'خطأ في الواجهة', 'تعذر عرض الواجهة بشكل صحيح.', 'error', 6000, 1),
('ERR_SPAM_BLOCKED', 'critical', 'تم حظر الإرسال المتكرر', 'تم إيقاف الإرسال بسبب تكرار الرسائل بشكل غير طبيعي.', 'critical', 8000, 1);

-- =============================================================
-- لا يتم إدخال كلمات مفتاحية افتراضية.
-- يمكن إضافتها لاحقًا حسب الحاجة فقط.
-- =============================================================

-- =============================================================
-- نصوص واجهة عربية افتراضية
-- =============================================================
INSERT IGNORE INTO `oxsecure_locale_strings` (`locale`, `string_key`, `string_value`) VALUES
('ar', 'system.ready', 'النظام جاهز'),
('ar', 'ui.logs.empty', 'لا توجد لوجات لعرضها'),
('ar', 'ui.logs.loading', 'جاري تحميل اللوجات'),
('ar', 'ui.permission_denied', 'لا تملك صلاحية الوصول'),
('ar', 'ui.close', 'إغلاق'),
('ar', 'ui.search', 'بحث'),
('ar', 'ui.refresh', 'تحديث'),
('ar', 'ui.time', 'الوقت'),
('ar', 'ui.message', 'الرسالة'),
('ar', 'ui.player', 'اللاعب'),
('ar', 'ui.system', 'النظام'),
('ar', 'ui.level', 'المستوى');

-- End of database/schema.sql
