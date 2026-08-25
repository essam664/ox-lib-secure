"""Configuration for the Discord admin bot.

All secrets are read from environment variables so the bot token is never stored in
source control.  Colours are integers accepted by ``discord.Embed``.
"""

from __future__ import annotations

import os
from dataclasses import dataclass


def _env_bool(name: str, default: bool = False) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on", "enable", "enabled"}


def _env_int(name: str, default: int = 0) -> int:
    value = os.getenv(name)
    if not value:
        return default
    return int(value)


@dataclass(frozen=True, slots=True)
class BotConfig:
    token: str
    version: str = "5.0.0"
    owner_id: int = 0
    database_path: str = "bot.db"
    command_prefix: str = "!"
    sync_commands: bool = True
    auto_restart_hours: int = 0
    spam_window_seconds: int = 8
    spam_duplicate_limit: int = 3
    spam_message_limit: int = 6
    ticket_cooldown_seconds: int = 300
    ticket_idle_hours: int = 24
    log_retention_days: int = 30

    @classmethod
    def from_env(cls) -> "BotConfig":
        return cls(
            token=os.getenv("BOT_TOKEN", ""),
            version=os.getenv("BOT_VERSION", "5.0.0"),
            owner_id=_env_int("BOT_OWNER_ID", 0),
            database_path=os.getenv("DATABASE_PATH", "bot.db"),
            command_prefix=os.getenv("BOT_PREFIX", "!"),
            sync_commands=_env_bool("SYNC_COMMANDS", True),
            auto_restart_hours=_env_int("AUTO_RESTART_HOURS", 0),
            spam_window_seconds=_env_int("SPAM_WINDOW_SECONDS", 8),
            spam_duplicate_limit=_env_int("SPAM_DUPLICATE_LIMIT", 3),
            spam_message_limit=_env_int("SPAM_MESSAGE_LIMIT", 6),
            ticket_cooldown_seconds=_env_int("TICKET_COOLDOWN_SECONDS", 300),
            ticket_idle_hours=_env_int("TICKET_IDLE_HOURS", 24),
            log_retention_days=_env_int("LOG_RETENTION_DAYS", 30),
        )


CONFIG = BotConfig.from_env()

BOT_TOKEN = CONFIG.token
BOT_VERSION = CONFIG.version
BOT_OWNER_ID = CONFIG.owner_id
DB_PATH = CONFIG.database_path
WELCOME_IMAGE_URL = os.getenv(
    "WELCOME_IMAGE_URL",
    "https://images.unsplash.com/photo-1519389950473-47ba0277781c?w=1200",
)

EMBED_COLOR = 0x2B2D31
SUCCESS_COLOR = 0x57F287
ERROR_COLOR = 0xED4245
WARNING_COLOR = 0xFEE75C
INFO_COLOR = 0x5865F2
GOLD_COLOR = 0xF1C40F

LOG_COLORS = {
    "join": 0x57F287,
    "leave": 0xED4245,
    "message_delete": 0xED4245,
    "message_edit": 0xFEE75C,
    "nickname": 0x5865F2,
    "role_add": 0x57F287,
    "role_remove": 0xED4245,
    "channel_create": 0x57F287,
    "channel_delete": 0xED4245,
    "role_create": 0x57F287,
    "role_delete": 0xED4245,
    "voice_join": 0x57F287,
    "voice_leave": 0xED4245,
    "voice_move": 0x5865F2,
    "kick": 0xFEE75C,
    "ban": 0xED4245,
    "unban": 0x57F287,
    "mute": 0xFEE75C,
    "unmute": 0x57F287,
    "warn": 0xFEE75C,
}
