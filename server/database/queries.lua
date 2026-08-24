-- =============================================================
-- ox_lib_secure
-- File: server/database/queries.lua
-- Description:
--   استعلامات قاعدة البيانات لنظام ox_lib_secure.
--
-- Notes:
--   - جميع الاستعلامات تستخدم بادئة الجداول من الإعدادات.
--   - يتم تنظيم الاستعلامات حسب الوحدة.
--   - متوافق بالكامل مع schema.sql المعتمد.
--   - معرفات اللاعبين تُخزن في جدول منفصل وليس في جدول اللاعبين.
-- =============================================================

Config = Config or {}
OxSecure = OxSecure or {}
OxSecure.Queries = OxSecure.Queries or {}

local Queries = OxSecure.Queries

local TABLE_PREFIX = Config.Database and Config.Database.TablePrefix or 'oxsecure_'

-- =============================================================
-- أداة مساعدة للحصول على اسم الجدول
-- =============================================================
local function T(tableName)
    return TABLE_PREFIX .. tableName
end

-- =============================================================
-- استعلامات اللوجات
-- متوافق مع جدول: oxsecure_logs
-- =============================================================
Queries.Logs = {
    Insert = ('INSERT INTO %s (level, category, event_code, message, message_hash, source_system_id, player_id, session_id, is_public, meta_json, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'):format(T('logs')),

    SelectAll = ('SELECT * FROM %s ORDER BY created_at DESC LIMIT ? OFFSET ?'):format(T('logs')),

    SelectByLevel = ('SELECT * FROM %s WHERE level = ? ORDER BY created_at DESC LIMIT ? OFFSET ?'):format(T('logs')),

    SelectByCategory = ('SELECT * FROM %s WHERE category = ? ORDER BY created_at DESC LIMIT ? OFFSET ?'):format(T('logs')),

    SelectByPlayer = ('SELECT * FROM %s WHERE player_id = ? ORDER BY created_at DESC LIMIT ? OFFSET ?'):format(T('logs')),

    SelectBySession = ('SELECT * FROM %s WHERE session_id = ? ORDER BY created_at DESC'):format(T('logs')),

    SelectPublic = ('SELECT * FROM %s WHERE is_public = 1 ORDER BY created_at DESC LIMIT ? OFFSET ?'):format(T('logs')),

    CountAll = ('SELECT COUNT(*) as total FROM %s'):format(T('logs')),

    CountByLevel = ('SELECT COUNT(*) as total FROM %s WHERE level = ?'):format(T('logs')),

    DeleteOld = ('DELETE FROM %s WHERE created_at < ?'):format(T('logs')),

    Search = ('SELECT * FROM %s WHERE message LIKE ? ORDER BY created_at DESC LIMIT ? OFFSET ?'):format(T('logs'))
}

-- =============================================================
-- استعلامات الإشعارات
-- متوافق مع جدول: oxsecure_notifications
--
-- ملاحظة: تم إزالة duration_ms لأنه غير موجود في المخطط.
-- يمكن تمرير المدة عبر meta_json إذا لزم الأمر.
-- =============================================================
Queries.Notifications = {
    Insert = ('INSERT INTO %s (notification_type, title_ar, body_ar, position, design_style, meta_json, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)'):format(T('notifications')),

    SelectAll = ('SELECT * FROM %s ORDER BY created_at DESC LIMIT ? OFFSET ?'):format(T('notifications')),

    SelectByType = ('SELECT * FROM %s WHERE notification_type = ? ORDER BY created_at DESC LIMIT ? OFFSET ?'):format(T('notifications')),

    CountAll = ('SELECT COUNT(*) as total FROM %s'):format(T('notifications')),

    DeleteOld = ('DELETE FROM %s WHERE created_at < ?'):format(T('notifications'))
}

-- =============================================================
-- استعلامات الأخطاء
-- متوافق مع جدول: oxsecure_errors
-- =============================================================
Queries.Errors = {
    Insert = ('INSERT INTO %s (error_code, title_ar, body_ar, severity, design_style, source_system_id, player_id, meta_json, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)'):format(T('errors')),

    SelectAll = ('SELECT * FROM %s ORDER BY created_at DESC LIMIT ? OFFSET ?'):format(T('errors')),

    SelectByCode = ('SELECT * FROM %s WHERE error_code = ? ORDER BY created_at DESC LIMIT ? OFFSET ?'):format(T('errors')),

    SelectBySeverity = ('SELECT * FROM %s WHERE severity = ? ORDER BY created_at DESC LIMIT ? OFFSET ?'):format(T('errors')),

    SelectByPlayer = ('SELECT * FROM %s WHERE player_id = ? ORDER BY created_at DESC LIMIT ? OFFSET ?'):format(T('errors')),

    CountAll = ('SELECT COUNT(*) as total FROM %s'):format(T('errors')),

    CountByCode = ('SELECT COUNT(*) as total FROM %s WHERE error_code = ?'):format(T('errors')),

    DeleteOld = ('DELETE FROM %s WHERE created_at < ?'):format(T('errors'))
}

-- =============================================================
-- استعلامات اللاعبين
-- متوافق مع جدول: oxsecure_players
--
-- ملاحظة: المعرفات (بما فيها discord) تُخزن في جدول
-- منفصل (oxsecure_player_identifiers) وليس هنا.
-- =============================================================
Queries.Players = {
    Insert = ('INSERT INTO %s (display_name, primary_identifier_type, primary_identifier_value, first_seen, last_seen) VALUES (?, ?, ?, ?, ?)'):format(T('players')),

    SelectById = ('SELECT * FROM %s WHERE id = ?'):format(T('players')),

    SelectByPrimaryIdentifier = ('SELECT * FROM %s WHERE primary_identifier_type = ? AND primary_identifier_value = ?'):format(T('players')),

    UpdateLastSeen = ('UPDATE %s SET last_seen = ? WHERE id = ?'):format(T('players')),

    UpdateDisplayName = ('UPDATE %s SET display_name = ? WHERE id = ?'):format(T('players')),

    SelectAll = ('SELECT * FROM %s ORDER BY last_seen DESC LIMIT ? OFFSET ?'):format(T('players')),

    CountAll = ('SELECT COUNT(*) as total FROM %s'):format(T('players')),

    Search = ('SELECT * FROM %s WHERE display_name LIKE ? ORDER BY last_seen DESC LIMIT ? OFFSET ?'):format(T('players'))
}

-- =============================================================
-- استعلامات معرفات اللاعبين
-- متوافق مع جدول: oxsecure_player_identifiers
--
-- هذا الجدول يخزن جميع المعرفات بما فيها discord.
-- =============================================================
Queries.PlayerIdentifiers = {
    Insert = ('INSERT INTO %s (player_id, identifier_type, identifier_value, first_seen) VALUES (?, ?, ?, ?)'):format(T('player_identifiers')),

    SelectByPlayer = ('SELECT * FROM %s WHERE player_id = ?'):format(T('player_identifiers')),

    SelectByTypeAndValue = ('SELECT * FROM %s WHERE identifier_type = ? AND identifier_value = ?'):format(T('player_identifiers')),

    SelectDiscordByPlayer = ('SELECT * FROM %s WHERE player_id = ? AND identifier_type = ?'):format(T('player_identifiers')),

    DeleteByPlayer = ('DELETE FROM %s WHERE player_id = ?'):format(T('player_identifiers'))
}

-- =============================================================
-- استعلامات جلسات اللاعبين
-- متوافق مع جدول: oxsecure_player_sessions
-- =============================================================
Queries.PlayerSessions = {
    Insert = ('INSERT INTO %s (session_id, player_id, server_player_id, connected_at) VALUES (?, ?, ?, ?)'):format(T('player_sessions')),

    SelectBySessionId = ('SELECT * FROM %s WHERE session_id = ?'):format(T('player_sessions')),

    SelectByPlayer = ('SELECT * FROM %s WHERE player_id = ? ORDER BY connected_at DESC LIMIT ? OFFSET ?'):format(T('player_sessions')),

    UpdateDisconnected = ('UPDATE %s SET disconnected_at = ? WHERE session_id = ?'):format(T('player_sessions')),

    SelectActive = ('SELECT * FROM %s WHERE disconnected_at IS NULL'):format(T('player_sessions')),

    CountActive = ('SELECT COUNT(*) as total FROM %s WHERE disconnected_at IS NULL'):format(T('player_sessions')),

    DeleteOld = ('DELETE FROM %s WHERE connected_at < ? AND disconnected_at IS NOT NULL'):format(T('player_sessions'))
}

-- =============================================================
-- استعلامات الأنظمة المربوطة
-- متوافق مع جدول: oxsecure_systems
--
-- ملاحظة: secret_hash وsigning_key_hash إلزاميان (NOT NULL).
-- =============================================================
Queries.Systems = {
    Insert = ('INSERT INTO %s (system_code, display_name, notes, secret_hash, signing_key_hash, is_active, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)'):format(T('systems')),

    SelectById = ('SELECT * FROM %s WHERE id = ?'):format(T('systems')),

    SelectBySystemCode = ('SELECT * FROM %s WHERE system_code = ?'):format(T('systems')),

    SelectActive = ('SELECT * FROM %s WHERE is_active = 1'):format(T('systems')),

    SelectAll = ('SELECT * FROM %s ORDER BY created_at DESC LIMIT ? OFFSET ?'):format(T('systems')),

    UpdateActive = ('UPDATE %s SET is_active = ? WHERE id = ?'):format(T('systems')),

    UpdateLastUsed = ('UPDATE %s SET last_used_at = ? WHERE id = ?'):format(T('systems')),

    UpdateSecretHash = ('UPDATE %s SET secret_hash = ? WHERE id = ?'):format(T('systems')),

    UpdateSigningKeyHash = ('UPDATE %s SET signing_key_hash = ? WHERE id = ?'):format(T('systems')),

    CountAll = ('SELECT COUNT(*) as total FROM %s'):format(T('systems'))
}

-- =============================================================
-- استعلامات توكنات الأنظمة
-- متوافق مع جدول: oxsecure_system_tokens
-- =============================================================
Queries.SystemTokens = {
    Insert = ('INSERT INTO %s (system_id, token_hash, token_hint, expires_at, created_at) VALUES (?, ?, ?, ?, ?)'):format(T('system_tokens')),

    SelectByTokenHash = ('SELECT * FROM %s WHERE token_hash = ? AND revoked_at IS NULL AND (expires_at IS NULL OR expires_at > NOW())'):format(T('system_tokens')),

    SelectBySystem = ('SELECT * FROM %s WHERE system_id = ? AND revoked_at IS NULL AND (expires_at IS NULL OR expires_at > NOW())'):format(T('system_tokens')),

    Revoke = ('UPDATE %s SET revoked_at = NOW() WHERE token_hash = ?'):format(T('system_tokens')),

    UpdateLastUsed = ('UPDATE %s SET last_used_at = NOW() WHERE token_hash = ?'):format(T('system_tokens')),

    DeleteExpired = ('DELETE FROM %s WHERE expires_at IS NOT NULL AND expires_at < NOW()'):format(T('system_tokens'))
}

-- =============================================================
-- استعلامات صلاحيات الأنظمة
-- متوافق مع جدول: oxsecure_system_scopes
-- =============================================================
Queries.SystemScopes = {
    Insert = ('INSERT INTO %s (system_id, scope_code) VALUES (?, ?)'):format(T('system_scopes')),

    SelectBySystem = ('SELECT * FROM %s WHERE system_id = ?'):format(T('system_scopes')),

    DeleteBySystem = ('DELETE FROM %s WHERE system_id = ?'):format(T('system_scopes')),

    CheckScope = ('SELECT COUNT(*) as total FROM %s WHERE system_id = ? AND scope_code = ?'):format(T('system_scopes'))
}

-- =============================================================
-- استعلامات المشرفين
-- متوافق مع جدول: oxsecure_admins
-- =============================================================
Queries.Admins = {
    Insert = ('INSERT INTO %s (discord_id, label, is_active, created_at) VALUES (?, ?, ?, ?)'):format(T('admins')),

    SelectByDiscordId = ('SELECT * FROM %s WHERE discord_id = ?'):format(T('admins')),

    SelectActive = ('SELECT * FROM %s WHERE is_active = 1'):format(T('admins')),

    SelectAll = ('SELECT * FROM %s ORDER BY created_at DESC LIMIT ? OFFSET ?'):format(T('admins')),

    UpdateActive = ('UPDATE %s SET is_active = ? WHERE id = ?'):format(T('admins')),

    UpdateLabel = ('UPDATE %s SET label = ? WHERE id = ?'):format(T('admins')),

    CountAll = ('SELECT COUNT(*) as total FROM %s'):format(T('admins'))
}

-- =============================================================
-- استعلامات أدوار المشرفين
-- متوافق مع جدول: oxsecure_admin_roles
-- =============================================================
Queries.AdminRoles = {
    Insert = ('INSERT INTO %s (admin_id, role_code) VALUES (?, ?)'):format(T('admin_roles')),

    SelectByAdmin = ('SELECT * FROM %s WHERE admin_id = ?'):format(T('admin_roles')),

    DeleteByAdmin = ('DELETE FROM %s WHERE admin_id = ?'):format(T('admin_roles')),

    DeleteByAdminAndRole = ('DELETE FROM %s WHERE admin_id = ? AND role_code = ?'):format(T('admin_roles')),

    CheckRole = ('SELECT COUNT(*) as total FROM %s WHERE admin_id = ? AND role_code = ?'):format(T('admin_roles'))
}

-- =============================================================
-- استعلامات الكلمات المفتاحية
-- متوافق مع جدول: oxsecure_keywords
-- =============================================================
Queries.Keywords = {
    Insert = ('INSERT INTO %s (keyword, match_type, is_active, created_at) VALUES (?, ?, ?, ?)'):format(T('keywords')),

    SelectActive = ('SELECT * FROM %s WHERE is_active = 1'):format(T('keywords')),

    SelectAll = ('SELECT * FROM %s ORDER BY created_at DESC LIMIT ? OFFSET ?'):format(T('keywords')),

    UpdateActive = ('UPDATE %s SET is_active = ? WHERE id = ?'):format(T('keywords')),

    Delete = ('DELETE FROM %s WHERE id = ?'):format(T('keywords')),

    CountAll = ('SELECT COUNT(*) as total FROM %s'):format(T('keywords'))
}

-- =============================================================
-- استعلامات قائمة الانتظار
-- متوافق مع جدول: oxsecure_message_queue
-- =============================================================
Queries.MessageQueue = {
    Insert = ('INSERT INTO %s (status, priority, attempts, max_attempts, payload_json, last_error, scheduled_at, expires_at, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)'):format(T('message_queue')),

    SelectPending = ('SELECT * FROM %s WHERE status = ? ORDER BY priority DESC, scheduled_at ASC LIMIT ?'):format(T('message_queue')),

    SelectById = ('SELECT * FROM %s WHERE id = ?'):format(T('message_queue')),

    UpdateStatus = ('UPDATE %s SET status = ?, attempts = attempts + 1 WHERE id = ?'):format(T('message_queue')),

    UpdatePayload = ('UPDATE %s SET payload_json = ? WHERE id = ?'):format(T('message_queue')),

    UpdateLastError = ('UPDATE %s SET last_error = ? WHERE id = ?'):format(T('message_queue')),

    DeleteCompleted = ('DELETE FROM %s WHERE status = ? AND created_at < ?'):format(T('message_queue')),

    DeleteFailed = ('DELETE FROM %s WHERE status = ? AND attempts >= max_attempts'):format(T('message_queue')),

    DeleteExpired = ('DELETE FROM %s WHERE expires_at IS NOT NULL AND expires_at < NOW()'):format(T('message_queue')),

    CountPending = ('SELECT COUNT(*) as total FROM %s WHERE status = ?'):format(T('message_queue'))
}

-- =============================================================
-- استعلامات التدقيق
-- متوافق مع جدول: oxsecure_audit_actions
-- =============================================================
Queries.AuditActions = {
    Insert = ('INSERT INTO %s (action_code, actor_admin_id, actor_discord_id, actor_player_id, target_type, target_id, details, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)'):format(T('audit_actions')),

    SelectAll = ('SELECT * FROM %s ORDER BY created_at DESC LIMIT ? OFFSET ?'):format(T('audit_actions')),

    SelectByActionCode = ('SELECT * FROM %s WHERE action_code = ? ORDER BY created_at DESC LIMIT ? OFFSET ?'):format(T('audit_actions')),

    SelectByActorAdmin = ('SELECT * FROM %s WHERE actor_admin_id = ? ORDER BY created_at DESC LIMIT ? OFFSET ?'):format(T('audit_actions')),

    SelectByTargetType = ('SELECT * FROM %s WHERE target_type = ? ORDER BY created_at DESC LIMIT ? OFFSET ?'):format(T('audit_actions')),

    CountAll = ('SELECT COUNT(*) as total FROM %s'):format(T('audit_actions')),

    DeleteOld = ('DELETE FROM %s WHERE created_at < ?'):format(T('audit_actions'))
}

-- =============================================================
-- استعلامات المحاولات الفاشلة
-- متوافق مع جدول: oxsecure_failed_attempts
-- =============================================================
Queries.FailedAttempts = {
    Insert = ('INSERT INTO %s (player_id, server_player_id, discord_id, reason_code, ip_hash, created_at) VALUES (?, ?, ?, ?, ?, ?)'):format(T('failed_attempts')),

    SelectByPlayer = ('SELECT * FROM %s WHERE player_id = ? ORDER BY created_at DESC LIMIT ? OFFSET ?'):format(T('failed_attempts')),

    SelectByDiscordId = ('SELECT * FROM %s WHERE discord_id = ? ORDER BY created_at DESC LIMIT ? OFFSET ?'):format(T('failed_attempts')),

    SelectRecent = ('SELECT * FROM %s WHERE created_at > ? ORDER BY created_at DESC LIMIT ?'):format(T('failed_attempts')),

    CountByPlayer = ('SELECT COUNT(*) as total FROM %s WHERE player_id = ? AND created_at > ?'):format(T('failed_attempts')),

    CountByDiscordId = ('SELECT COUNT(*) as total FROM %s WHERE discord_id = ? AND created_at > ?'):format(T('failed_attempts')),

    DeleteOld = ('DELETE FROM %s WHERE created_at < ?'):format(T('failed_attempts'))
}

-- =============================================================
-- استعلامات معدل الاستخدام
-- متوافق مع جدول: oxsecure_rate_limits
--
-- ملاحظة: window_start يجب أن يُمرر كقيمة Timestamp.
-- =============================================================
Queries.RateLimits = {
    InsertOrUpdate = ('INSERT INTO %s (bucket_key, window_start, hits, updated_at) VALUES (?, ?, ?, NOW()) ON DUPLICATE KEY UPDATE hits = hits + 1, updated_at = NOW()'):format(T('rate_limits')),

    SelectByBucketKey = ('SELECT * FROM %s WHERE bucket_key = ? AND window_start > ?'):format(T('rate_limits')),

    DeleteExpired = ('DELETE FROM %s WHERE window_start < ?'):format(T('rate_limits')),

    CountAll = ('SELECT COUNT(*) as total FROM %s'):format(T('rate_limits'))
}

-- =============================================================
-- استعلامات سجل الأوامر
-- متوافق مع جدول: oxsecure_command_history
-- =============================================================
Queries.CommandHistory = {
    Insert = ('INSERT INTO %s (command_name, server_player_id, player_id, args_json, created_at) VALUES (?, ?, ?, ?, ?)'):format(T('command_history')),

    SelectAll = ('SELECT * FROM %s ORDER BY created_at DESC LIMIT ? OFFSET ?'):format(T('command_history')),

    SelectByPlayer = ('SELECT * FROM %s WHERE player_id = ? ORDER BY created_at DESC LIMIT ? OFFSET ?'):format(T('command_history')),

    SelectByCommand = ('SELECT * FROM %s WHERE command_name = ? ORDER BY created_at DESC LIMIT ? OFFSET ?'):format(T('command_history')),

    CountAll = ('SELECT COUNT(*) as total FROM %s'):format(T('command_history')),

    DeleteOld = ('DELETE FROM %s WHERE created_at < ?'):format(T('command_history'))
}

-- =============================================================
-- استعلامات الإعدادات
-- متوافق مع جدول: oxsecure_settings
-- =============================================================
Queries.Settings = {
    SelectByKey = ('SELECT * FROM %s WHERE setting_key = ?'):format(T('settings')),

    InsertOrUpdate = ('INSERT INTO %s (setting_key, setting_value, is_encrypted, description, updated_at) VALUES (?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value), updated_at = VALUES(updated_at)'):format(T('settings')),

    SelectAll = ('SELECT * FROM %s'):format(T('settings')),

    DeleteByKey = ('DELETE FROM %s WHERE setting_key = ?'):format(T('settings'))
}

-- =============================================================
-- رسالة تحميل ناجحة
-- =============================================================
if OxSecure.Console and type(OxSecure.Console.debug) == 'function' then
    OxSecure.Console.debug('server/database/queries.lua loaded')
end
