"""Async SQLite storage layer for the Discord admin bot."""

from __future__ import annotations

import json
from datetime import datetime, timezone
from typing import Any, Iterable

import aiosqlite

from config import DB_PATH


SCHEMA = """
PRAGMA journal_mode=WAL;
PRAGMA foreign_keys=ON;

CREATE TABLE IF NOT EXISTS guild_settings (
    guild_id INTEGER NOT NULL,
    key TEXT NOT NULL,
    value TEXT,
    PRIMARY KEY (guild_id, key)
);

CREATE TABLE IF NOT EXISTS warnings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    guild_id INTEGER NOT NULL,
    user_id INTEGER NOT NULL,
    moderator_id INTEGER NOT NULL,
    reason TEXT NOT NULL,
    timestamp TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    guild_id INTEGER NOT NULL,
    action_type TEXT NOT NULL,
    user_id INTEGER,
    moderator_id INTEGER,
    reason TEXT,
    extra TEXT,
    timestamp TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS tempbans (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    guild_id INTEGER NOT NULL,
    moderator_id INTEGER NOT NULL,
    reason TEXT,
    expires_at TEXT NOT NULL,
    active INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS tempmutes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    guild_id INTEGER NOT NULL,
    moderator_id INTEGER NOT NULL,
    reason TEXT,
    expires_at TEXT NOT NULL,
    active INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS tickets (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    guild_id INTEGER NOT NULL,
    channel_id INTEGER NOT NULL UNIQUE,
    user_id INTEGER NOT NULL,
    reason TEXT NOT NULL,
    type TEXT NOT NULL DEFAULT 'support',
    status TEXT NOT NULL DEFAULT 'open',
    created_at TEXT NOT NULL,
    closed_at TEXT,
    transcript TEXT
);

CREATE TABLE IF NOT EXISTS giveaways (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    guild_id INTEGER NOT NULL,
    channel_id INTEGER NOT NULL,
    message_id INTEGER NOT NULL,
    title TEXT NOT NULL,
    description TEXT,
    image TEXT,
    winners INTEGER NOT NULL,
    ends_at TEXT NOT NULL,
    host_id INTEGER NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    winner_ids TEXT,
    created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS command_permissions (
    guild_id INTEGER NOT NULL,
    target_id INTEGER NOT NULL,
    target_type TEXT NOT NULL CHECK(target_type IN ('user','role')),
    command TEXT NOT NULL DEFAULT '*',
    PRIMARY KEY (guild_id, target_id, target_type, command)
);

CREATE TABLE IF NOT EXISTS automod_excluded_channels (
    guild_id INTEGER NOT NULL,
    channel_id INTEGER NOT NULL,
    PRIMARY KEY (guild_id, channel_id)
);

CREATE TABLE IF NOT EXISTS xp (
    guild_id INTEGER NOT NULL,
    user_id INTEGER NOT NULL,
    xp INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (guild_id, user_id)
);
"""

INTEGER_SETTINGS = {
    "welcome_channel", "goodbye_channel", "log_channel", "auto_role",
    "ticket_category", "ticket_role", "automod_antilink", "automod_antispam",
    "automod_enabled",
}


def utcnow() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def _row_to_dict(row: aiosqlite.Row | None) -> dict[str, Any] | None:
    return dict(row) if row is not None else None


class Database:
    def __init__(self, db_path: str = DB_PATH) -> None:
        self.db_path = db_path

    async def initialize(self) -> None:
        async with aiosqlite.connect(self.db_path) as conn:
            await conn.executescript(SCHEMA)
            await conn.commit()

    async def _execute(self, query: str, params: Iterable[Any] = ()) -> None:
        async with aiosqlite.connect(self.db_path) as conn:
            await conn.execute(query, tuple(params))
            await conn.commit()

    async def _fetchone(self, query: str, params: Iterable[Any] = ()) -> dict[str, Any] | None:
        async with aiosqlite.connect(self.db_path) as conn:
            conn.row_factory = aiosqlite.Row
            cursor = await conn.execute(query, tuple(params))
            return _row_to_dict(await cursor.fetchone())

    async def _fetchall(self, query: str, params: Iterable[Any] = ()) -> list[dict[str, Any]]:
        async with aiosqlite.connect(self.db_path) as conn:
            conn.row_factory = aiosqlite.Row
            cursor = await conn.execute(query, tuple(params))
            return [dict(row) for row in await cursor.fetchall()]

    async def set_guild_setting(self, guild_id: int, key: str, value: Any) -> None:
        stored = json.dumps(value, ensure_ascii=False)
        await self._execute(
            "INSERT INTO guild_settings(guild_id, key, value) VALUES(?,?,?) "
            "ON CONFLICT(guild_id, key) DO UPDATE SET value=excluded.value",
            (guild_id, key, stored),
        )

    async def get_guild_settings(self, guild_id: int) -> dict[str, Any]:
        rows = await self._fetchall("SELECT key, value FROM guild_settings WHERE guild_id=?", (guild_id,))
        settings: dict[str, Any] = {}
        for row in rows:
            try:
                value = json.loads(row["value"])
            except (TypeError, json.JSONDecodeError):
                value = row["value"]
            if row["key"] in INTEGER_SETTINGS and value is not None:
                value = int(value)
            settings[row["key"]] = value
        return settings

    async def add_warning(self, user_id: int, guild_id: int, moderator_id: int, reason: str) -> None:
        await self._execute(
            "INSERT INTO warnings(guild_id,user_id,moderator_id,reason,timestamp) VALUES(?,?,?,?,?)",
            (guild_id, user_id, moderator_id, reason, utcnow()),
        )

    async def get_warnings(self, user_id: int, guild_id: int) -> list[dict[str, Any]]:
        return await self._fetchall(
            "SELECT * FROM warnings WHERE guild_id=? AND user_id=? ORDER BY id DESC",
            (guild_id, user_id),
        )

    async def clear_warnings(self, user_id: int, guild_id: int) -> None:
        await self._execute("DELETE FROM warnings WHERE guild_id=? AND user_id=?", (guild_id, user_id))

    async def remove_warning(self, warn_id: int) -> None:
        await self._execute("DELETE FROM warnings WHERE id=?", (warn_id,))

    async def add_log(self, guild_id: int, action_type: str, user_id: int | None, moderator_id: int | None, reason: str = "", extra: str = "") -> None:
        await self._execute(
            "INSERT INTO logs(guild_id,action_type,user_id,moderator_id,reason,extra,timestamp) VALUES(?,?,?,?,?,?,?)",
            (guild_id, action_type, user_id, moderator_id, reason, extra, utcnow()),
        )

    async def get_logs(self, guild_id: int, user_id: int | None = None, limit: int = 20) -> list[dict[str, Any]]:
        if user_id is None:
            return await self._fetchall("SELECT * FROM logs WHERE guild_id=? ORDER BY id DESC LIMIT ?", (guild_id, limit))
        return await self._fetchall(
            "SELECT * FROM logs WHERE guild_id=? AND user_id=? ORDER BY id DESC LIMIT ?",
            (guild_id, user_id, limit),
        )

    async def add_tempban(self, user_id: int, guild_id: int, moderator_id: int, reason: str, expires_at: str) -> None:
        await self._execute(
            "INSERT INTO tempbans(user_id,guild_id,moderator_id,reason,expires_at) VALUES(?,?,?,?,?)",
            (user_id, guild_id, moderator_id, reason, expires_at),
        )

    async def add_tempmute(self, user_id: int, guild_id: int, moderator_id: int, reason: str, expires_at: str) -> None:
        await self._execute(
            "INSERT INTO tempmutes(user_id,guild_id,moderator_id,reason,expires_at) VALUES(?,?,?,?,?)",
            (user_id, guild_id, moderator_id, reason, expires_at),
        )

    async def create_ticket(self, guild_id: int, channel_id: int, user_id: int, reason: str, ticket_type: str) -> None:
        await self._execute(
            "INSERT INTO tickets(guild_id,channel_id,user_id,reason,type,created_at) VALUES(?,?,?,?,?,?)",
            (guild_id, channel_id, user_id, reason, ticket_type, utcnow()),
        )

    async def get_ticket_by_channel_id(self, channel_id: int | str) -> dict[str, Any] | None:
        return await self._fetchone("SELECT * FROM tickets WHERE channel_id=? OR id=?", (int(channel_id), int(channel_id)))

    async def close_ticket(self, channel_id: int, transcript: str | None = None) -> None:
        await self._execute(
            "UPDATE tickets SET status='closed', closed_at=?, transcript=COALESCE(?, transcript) WHERE channel_id=?",
            (utcnow(), transcript, channel_id),
        )

    async def save_ticket_transcript(self, channel_id: int, transcript: str) -> None:
        await self._execute("UPDATE tickets SET transcript=? WHERE channel_id=?", (transcript, channel_id))

    async def create_giveaway(self, guild_id: int, channel_id: int, message_id: int, title: str, description: str,
                              image: str | None, winners: int, ends_at: str, host_id: int) -> None:
        await self._execute(
            "INSERT INTO giveaways(guild_id,channel_id,message_id,title,description,image,winners,ends_at,host_id,created_at) "
            "VALUES(?,?,?,?,?,?,?,?,?,?)",
            (guild_id, channel_id, message_id, title, description, image, winners, ends_at, host_id, utcnow()),
        )

    async def get_giveaway(self, giveaway_id: int) -> dict[str, Any] | None:
        return await self._fetchone("SELECT * FROM giveaways WHERE id=?", (giveaway_id,))

    async def get_active_giveaways(self, guild_id: int | None = None) -> list[dict[str, Any]]:
        if guild_id is None:
            return await self._fetchall("SELECT * FROM giveaways WHERE status='active' ORDER BY ends_at")
        return await self._fetchall("SELECT * FROM giveaways WHERE guild_id=? AND status='active' ORDER BY ends_at", (guild_id,))

    async def end_giveaway(self, giveaway_id: int, winner_ids: str) -> None:
        await self._execute(
            "UPDATE giveaways SET status='ended', winner_ids=? WHERE id=?",
            (winner_ids, giveaway_id),
        )

    async def add_permission(self, guild_id: int, target_id: int, target_type: str, command: str | None) -> None:
        await self._execute(
            "INSERT OR IGNORE INTO command_permissions(guild_id,target_id,target_type,command) VALUES(?,?,?,?)",
            (guild_id, target_id, target_type, command or "*"),
        )

    async def remove_permission(self, guild_id: int, target_id: int, target_type: str, command: str | None) -> None:
        await self._execute(
            "DELETE FROM command_permissions WHERE guild_id=? AND target_id=? AND target_type=? AND command=?",
            (guild_id, target_id, target_type, command or "*"),
        )

    async def check_command_permission(self, guild_id: int, member: Any, command: str | None) -> bool:
        checks = [(member.id, "user", command or "*"), (member.id, "user", "*")]
        checks.extend((role.id, "role", command or "*") for role in getattr(member, "roles", []))
        checks.extend((role.id, "role", "*") for role in getattr(member, "roles", []))
        placeholders = ",".join("(?,?,?)" for _ in checks)
        params: list[Any] = []
        for item in checks:
            params.extend(item)
        row = await self._fetchone(
            f"SELECT 1 FROM command_permissions WHERE guild_id=? AND (target_id,target_type,command) IN ({placeholders}) LIMIT 1",
            (guild_id, *params),
        )
        return row is not None

    async def add_automod_excluded_channel(self, guild_id: int, channel_id: int) -> None:
        await self._execute("INSERT OR IGNORE INTO automod_excluded_channels(guild_id,channel_id) VALUES(?,?)", (guild_id, channel_id))

    async def remove_automod_excluded_channel(self, guild_id: int, channel_id: int) -> None:
        await self._execute("DELETE FROM automod_excluded_channels WHERE guild_id=? AND channel_id=?", (guild_id, channel_id))

    async def get_automod_excluded_channels(self, guild_id: int) -> list[int]:
        rows = await self._fetchall("SELECT channel_id FROM automod_excluded_channels WHERE guild_id=?", (guild_id,))
        return [int(row["channel_id"]) for row in rows]

    async def add_xp(self, user_id: int, guild_id: int, amount: int) -> None:
        await self._execute(
            "INSERT INTO xp(guild_id,user_id,xp) VALUES(?,?,?) ON CONFLICT(guild_id,user_id) DO UPDATE SET xp=xp+excluded.xp",
            (guild_id, user_id, amount),
        )


db = Database()
