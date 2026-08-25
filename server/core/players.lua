-- =============================================================
-- ox_lib_secure
-- File: server/core/players.lua
-- Description:
--   طبقة إدارة اللاعبين لنظام ox_lib_secure.
--
-- Notes:
--   - يتم إنشاء سجل لاعب جديد عند أول ظهور.
--   - يتم تخزين جميع المعرفات في جدول منفصل.
--   - يتم تحديث آخر ظهور تلقائيًا.
--   - يدعم الحظر والفك مع سبب وتاريخ انتهاء.
--   - يتكامل مع أحداث FiveM لدخول وخروج اللاعبين.
--   - يتم تحويل block_until من نص إلى طابع زمني بشكل صحيح.
--   - العداد لا يتضاعف عند الاستدعاء المتكرر.
-- =============================================================

Config = Config or {}
OxSecure = OxSecure or {}
OxSecure.Players = OxSecure.Players or {}

local Players = OxSecure.Players
local Database = OxSecure.Database or {}
local Validator = OxSecure.Validator or {}
local Logger = OxSecure.Logger or {}
local Utils = OxSecure.Utils or {}
local StateManager = OxSecure.StateManager or {}
local Permissions = OxSecure.Permissions or {}

local playersConfig = Config.Players or {}
local TRACK_LAST_SEEN = playersConfig.TrackLastSeen ~= false

-- =============================================================
-- أدوات مساعدة داخلية
-- =============================================================
local function getPlayersCache()
    local state = StateManager.Get and StateManager.Get() or nil
    return state and state.players or nil
end

local function logPlayerEvent(message, options)
    if Logger.Info then
        Logger.Info(message, options or {
            category = 'player',
            eventCode = 'player_event'
        })
    end
end

local function logPlayerError(message, options)
    if Logger.Error then
        Logger.Error(message, options or {
            category = 'player',
            eventCode = 'player_error'
        })
    end
end

-- =============================================================
-- تحويل قيمة DATETIME من قاعدة البيانات إلى طابع زمني
-- =============================================================
local function datetimeToTimestamp(value)
    if value == nil then
        return nil
    end

    if type(value) == 'number' then
        return value
    end

    if type(value) ~= 'string' then
        return nil
    end

    local year, month, day, hour, min, sec = value:match('(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)')

    if year then
        return os.time({
            year = tonumber(year),
            month = tonumber(month),
            day = tonumber(day),
            hour = tonumber(hour),
            min = tonumber(min),
            sec = tonumber(sec)
        })
    end

    year, month, day = value:match('(%d+)-(%d+)-(%d+)')

    if year then
        return os.time({
            year = tonumber(year),
            month = tonumber(month),
            day = tonumber(day),
            hour = 0,
            min = 0,
            sec = 0
        })
    end

    return nil
end

-- =============================================================
-- إضافة لاعب إلى الكاش مع تحديث العداد بشكل آمن
--
-- إصلاح: زيادة العداد فقط إذا لم يكن اللاعب موجودًا بالفعل
-- =============================================================
local function addToCache(playerId, serverId, playerData)
    local cache = getPlayersCache()

    if not cache then
        return
    end

    if not cache.byDbId then
        cache.byDbId = {}
    end

    if not cache.byServerId then
        cache.byServerId = {}
    end

    -- إصلاح: التحقق من عدم وجود اللاعب بالفعل في الكاش
    local isAlreadyCached = cache.byServerId[serverId] ~= nil

    cache.byDbId[playerId] = playerData
    cache.byServerId[serverId] = playerId

    -- زيادة العداد فقط إذا كان اللاعب جديدًا في الكاش
    if not isAlreadyCached then
        cache.count = (cache.count or 0) + 1
    end
end

-- =============================================================
-- إنشاء أو جلب لاعب من قاعدة البيانات
-- =============================================================
function Players.EnsurePlayer(source, callback)
    local okPlayer, player = Validator.ValidatePlayerSource(source, {
        requireOnline = true,
        requireIdentifiers = true
    })

    if not okPlayer then
        if callback then callback(false, player) end
        return
    end

    local primaryType = player.primaryIdentifierType
    local primaryValue = player.primaryIdentifierValue

    if not primaryType or not primaryValue then
        if callback then callback(false, { code = 'ERR_PLAYER_NO_IDENTIFIER' }) end
        return
    end

    local selectQuery = ('SELECT * FROM %s WHERE primary_identifier_type = ? AND primary_identifier_value = ?'):format(Database.GetTableName('players'))

    Database.Single(selectQuery, { primaryType, primaryValue }, function(existingPlayer, err)
        if err then
            logPlayerError(('Failed to fetch player: %s'):format(tostring(err)))
            if callback then callback(false, { code = 'ERR_DB_QUERY_FAILED', details = err }) end
            return
        end

        local playerId = nil
        local isNewPlayer = false

        if existingPlayer then
            playerId = existingPlayer.id

            -- تحديث آخر ظهور
            if TRACK_LAST_SEEN then
                local updateQuery = ('UPDATE %s SET last_seen = NOW(), display_name = ? WHERE id = ?'):format(Database.GetTableName('players'))
                Database.Execute(updateQuery, { player.name or existingPlayer.display_name, playerId }, function(_, updateErr)
                    if updateErr then
                        logPlayerError(('Failed to update last seen: %s'):format(tostring(updateErr)))
                    end
                end)
            end

            -- حفظ في الكاش
            addToCache(playerId, player.serverId, {
                id = playerId,
                serverId = player.serverId,
                name = player.name or (existingPlayer and existingPlayer.display_name),
                primaryIdentifierType = primaryType,
                primaryIdentifierValue = primaryValue,
                identifiers = player.identifiers,
                isAdmin = false,
                isBlocked = existingPlayer and existingPlayer.is_blocked == 1 or false,
                joinedAt = os.time()
            })

            if Permissions.LoadPlayerPermissions then
                Permissions.LoadPlayerPermissions(player.serverId)
            end

            if callback then
                callback(true, {
                    id = playerId,
                    serverId = player.serverId,
                    name = player.name or (existingPlayer and existingPlayer.display_name),
                    primaryIdentifierType = primaryType,
                    primaryIdentifierValue = primaryValue,
                    isNew = isNewPlayer
                })
            end
        else
            -- إنشاء لاعب جديد
            isNewPlayer = true

            local insertQuery = ('INSERT INTO %s (display_name, primary_identifier_type, primary_identifier_value, first_seen, last_seen) VALUES (?, ?, ?, NOW(), NOW())'):format(Database.GetTableName('players'))

            Database.Insert(insertQuery, {
                player.name or 'Unknown',
                primaryType,
                primaryValue
            }, function(insertId, insertErr)
                if insertErr then
                    logPlayerError(('Failed to create player: %s'):format(tostring(insertErr)))
                    if callback then callback(false, { code = 'ERR_DB_INSERT_FAILED', details = insertErr }) end
                    return
                end

                playerId = insertId

                Players.SavePlayerIdentifiers(playerId, player.identifiers, function()
                    -- حفظ في الكاش
                    addToCache(playerId, player.serverId, {
                        id = playerId,
                        serverId = player.serverId,
                        name = player.name,
                        primaryIdentifierType = primaryType,
                        primaryIdentifierValue = primaryValue,
                        identifiers = player.identifiers,
                        isAdmin = false,
                        isBlocked = false,
                        joinedAt = os.time()
                    })

                    logPlayerEvent(('New player created: %s (ID: %d)'):format(player.name or 'Unknown', playerId))

                    if Permissions.LoadPlayerPermissions then
                        Permissions.LoadPlayerPermissions(player.serverId)
                    end

                    if callback then
                        callback(true, {
                            id = playerId,
                            serverId = player.serverId,
                            name = player.name,
                            primaryIdentifierType = primaryType,
                            primaryIdentifierValue = primaryValue,
                            isNew = isNewPlayer
                        })
                    end
                end)
            end)
        end
    end)
end

-- =============================================================
-- حفظ معرفات اللاعب
-- =============================================================
function Players.SavePlayerIdentifiers(playerId, identifiers, callback)
    if not playerId or type(identifiers) ~= 'table' then
        if callback then callback(false) end
        return
    end

    local pendingInserts = #identifiers

    if pendingInserts == 0 then
        if callback then callback(true) end
        return
    end

    local insertQuery = ('INSERT INTO %s (player_id, identifier_type, identifier_value, first_seen) VALUES (?, ?, ?, NOW()) ON DUPLICATE KEY UPDATE last_seen = NOW()'):format(Database.GetTableName('player_identifiers'))

    for _, identifier in ipairs(identifiers) do
        Database.Execute(insertQuery, {
            playerId,
            identifier.type,
            identifier.value
        }, function(_, err)
            if err then
                logPlayerError(('Failed to save identifier %s: %s'):format(identifier.type, tostring(err)))
            end

            pendingInserts = pendingInserts - 1

            if pendingInserts <= 0 and callback then
                callback(true)
            end
        end)
    end
end

-- =============================================================
-- جلب بيانات لاعب من الكاش
-- =============================================================
function Players.GetPlayer(source)
    local serverId = tonumber(source)

    if not serverId or serverId <= 0 then
        return nil
    end

    local cache = getPlayersCache()

    if not cache then
        return nil
    end

    local playerId = cache.byServerId and cache.byServerId[serverId]

    if not playerId then
        return nil
    end

    return cache.byDbId and cache.byDbId[playerId]
end

-- =============================================================
-- جلب بيانات لاعب من قاعدة البيانات
-- =============================================================
function Players.GetPlayerFromDb(source, callback)
    local serverId = tonumber(source)

    if not serverId or serverId <= 0 then
        if callback then callback(nil, 'Invalid source') end
        return
    end

    local cachedPlayer = Players.GetPlayer(serverId)

    if cachedPlayer then
        if callback then callback(cachedPlayer, nil) end
        return
    end

    local okPlayer, player = Validator.ValidatePlayerSource(serverId, {
        requireOnline = true,
        requireIdentifiers = true
    })

    if not okPlayer then
        if callback then callback(nil, player) end
        return
    end

    local selectQuery = ('SELECT * FROM %s WHERE primary_identifier_type = ? AND primary_identifier_value = ?'):format(Database.GetTableName('players'))

    Database.Single(selectQuery, { player.primaryIdentifierType, player.primaryIdentifierValue }, function(result, err)
        if err then
            if callback then callback(nil, err) end
            return
        end

        if callback then callback(result, nil) end
    end)
end

-- =============================================================
-- تحديث آخر ظهور
-- =============================================================
function Players.UpdateLastSeen(source, callback)
    if not TRACK_LAST_SEEN then
        if callback then callback(true) end
        return
    end

    local playerData = Players.GetPlayer(source)

    if not playerData or not playerData.id then
        if callback then callback(false) end
        return
    end

    local updateQuery = ('UPDATE %s SET last_seen = NOW() WHERE id = ?'):format(Database.GetTableName('players'))

    Database.Execute(updateQuery, { playerData.id }, function(_, err)
        if err then
            logPlayerError(('Failed to update last seen for player %d: %s'):format(playerData.id, tostring(err)))
            if callback then callback(false) end
            return
        end

        if callback then callback(true) end
    end)
end

-- =============================================================
-- حظر لاعب
-- =============================================================
function Players.BlockPlayer(discordId, reason, untilTimestamp, callback)
    if type(discordId) ~= 'string' or discordId == '' then
        if callback then callback(false, 'Invalid discord ID') end
        return
    end

    local selectQuery = ('SELECT player_id FROM %s WHERE identifier_type = ? AND identifier_value = ?'):format(Database.GetTableName('player_identifiers'))

    Database.Single(selectQuery, { 'discord', discordId }, function(result, err)
        if err then
            if callback then callback(false, err) end
            return
        end

        if not result or not result.player_id then
            if callback then callback(false, 'Player not found') end
            return
        end

        local updateQuery = ('UPDATE %s SET is_blocked = 1, block_reason = ?, block_until = ? WHERE id = ?'):format(Database.GetTableName('players'))

        Database.Execute(updateQuery, {
            reason or 'Blocked by admin',
            untilTimestamp,
            result.player_id
        }, function(_, updateErr)
            if updateErr then
                if callback then callback(false, updateErr) end
                return
            end

            logPlayerEvent(('Player blocked: discord=%s reason=%s'):format(discordId, reason or 'N/A'))

            if callback then callback(true, nil) end
        end)
    end)
end

-- =============================================================
-- فك حظر لاعب
-- =============================================================
function Players.UnblockPlayer(discordId, callback)
    if type(discordId) ~= 'string' or discordId == '' then
        if callback then callback(false, 'Invalid discord ID') end
        return
    end

    local selectQuery = ('SELECT player_id FROM %s WHERE identifier_type = ? AND identifier_value = ?'):format(Database.GetTableName('player_identifiers'))

    Database.Single(selectQuery, { 'discord', discordId }, function(result, err)
        if err then
            if callback then callback(false, err) end
            return
        end

        if not result or not result.player_id then
            if callback then callback(false, 'Player not found') end
            return
        end

        local updateQuery = ('UPDATE %s SET is_blocked = 0, block_reason = NULL, block_until = NULL WHERE id = ?'):format(Database.GetTableName('players'))

        Database.Execute(updateQuery, { result.player_id }, function(_, updateErr)
            if updateErr then
                if callback then callback(false, updateErr) end
                return
            end

            logPlayerEvent(('Player unblocked: discord=%s'):format(discordId))

            if callback then callback(true, nil) end
        end)
    end)
end

-- =============================================================
-- التحقق مما إذا كان اللاعب محظورًا
-- =============================================================
function Players.IsBlocked(source, callback)
    local serverId = tonumber(source)

    if not serverId or serverId <= 0 then
        if callback then callback(false) end
        return
    end

    local okPlayer, player = Validator.ValidatePlayerSource(serverId, {
        requireOnline = true,
        requireIdentifiers = true
    })

    if not okPlayer then
        if callback then callback(false) end
        return
    end

    local selectQuery = ('SELECT is_blocked, block_reason, block_until FROM %s WHERE primary_identifier_type = ? AND primary_identifier_value = ?'):format(Database.GetTableName('players'))

    Database.Single(selectQuery, { player.primaryIdentifierType, player.primaryIdentifierValue }, function(result, err)
        if err or not result then
            if callback then callback(false) end
            return
        end

        if result.is_blocked ~= 1 then
            if callback then callback(false) end
            return
        end

        local blockUntil = datetimeToTimestamp(result.block_until)

        if blockUntil and os.time() > blockUntil then
            -- الحظر انتهى، نفك الحظر تلقائيًا
            local updateQuery = ('UPDATE %s SET is_blocked = 0, block_reason = NULL, block_until = NULL WHERE primary_identifier_type = ? AND primary_identifier_value = ?'):format(Database.GetTableName('players'))

            Database.Execute(updateQuery, { player.primaryIdentifierType, player.primaryIdentifierValue }, function(_, updateErr)
                if updateErr then
                    logPlayerError(('Failed to auto-unblock player: %s'):format(tostring(updateErr)))
                else
                    logPlayerEvent(('Player auto-unblocked: identifier=%s'):format(player.primaryIdentifierValue))
                end

                if callback then callback(false) end
            end)
            return
        end

        if callback then
            callback(true, {
                reason = result.block_reason,
                until = result.block_until
            })
        end
    end)
end

-- =============================================================
-- إزالة لاعب من الكاش عند الخروج
-- =============================================================
function Players.RemoveFromCache(source)
    local serverId = tonumber(source)

    if not serverId or serverId <= 0 then
        return
    end

    local cache = getPlayersCache()

    if not cache then
        return
    end

    local playerId = cache.byServerId and cache.byServerId[serverId]

    if playerId and cache.byDbId then
        cache.byDbId[playerId] = nil

        if cache.count and cache.count > 0 then
            cache.count = cache.count - 1
        end
    end

    if cache.byServerId then
        cache.byServerId[serverId] = nil
    end
end

-- =============================================================
-- الحصول على عدد اللاعبين المتصلين
-- =============================================================
function Players.GetOnlineCount()
    local cache = getPlayersCache()

    if not cache then
        return 0
    end

    return cache.count or 0
end

-- =============================================================
-- أحداث دخول وخروج اللاعبين
-- =============================================================
AddEventHandler('playerJoin', function()
    local src = source

    Players.EnsurePlayer(src, function(ok, result)
        if not ok then
            logPlayerError(('Failed to ensure player on join: %s'):format(tostring(result and result.code or 'unknown')))
            return
        end

        -- التحقق من الحظر
        Players.IsBlocked(src, function(blocked, blockInfo)
            if blocked then
                local reason = blockInfo and blockInfo.reason or 'محظور'
                DropPlayer(src, ('تم حظرك من السيرفر: %s'):format(reason))
            end
        end)
    end)
end)

AddEventHandler('playerDropped', function()
    local src = source

    Players.UpdateLastSeen(src)
    Players.RemoveFromCache(src)
end)

-- =============================================================
-- رسالة تحميل ناجحة
-- =============================================================
if Logger.Debug then
    Logger.Debug('server/core/players.lua loaded')
elseif OxSecure.Console and type(OxSecure.Console.debug) == 'function' then
    OxSecure.Console.debug('server/core/players.lua loaded')
end
