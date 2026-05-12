"""
Discord Admin Bot Ultimate v5.0

نسخة منظمة وقوية مقسمة إلى ثلاثة ملفات:
- main.py: تشغيل البوت والأوامر والأحداث.
- database.py: طبقة التخزين SQLite async.
- config.py: الإعدادات الآمنة من متغيرات البيئة.
"""

from __future__ import annotations

import asyncio
import io
import json
import random
import re
import sys
from collections import defaultdict, deque
from datetime import datetime, timedelta, timezone
from typing import Any

import aiosqlite
import discord
from discord import app_commands, ui
from discord.ext import commands, tasks

from config import (
    BOT_OWNER_ID,
    BOT_TOKEN,
    BOT_VERSION,
    CONFIG,
    EMBED_COLOR,
    ERROR_COLOR,
    GOLD_COLOR,
    INFO_COLOR,
    LOG_COLORS,
    SUCCESS_COLOR,
    WARNING_COLOR,
    WELCOME_IMAGE_URL,
)
from database import db

URL_RE = re.compile(r"(?:https?://|www\.)\S+", re.IGNORECASE)
TIME_RE = re.compile(r"^(\d+)([dhms])$", re.IGNORECASE)


def now_utc() -> datetime:
    return datetime.now(timezone.utc).replace(microsecond=0)


def create_embed(
    title: str,
    description: str = "",
    color: int = EMBED_COLOR,
    thumbnail: str | None = None,
    image: str | None = None,
) -> discord.Embed:
    embed = discord.Embed(title=title, description=description, color=color, timestamp=now_utc())
    if thumbnail:
        embed.set_thumbnail(url=thumbnail)
    if image:
        embed.set_image(url=image)
    if bot.user:
        embed.set_footer(text=f"{bot.user.name} v{BOT_VERSION}")
    return embed


def parse_time(time_str: str) -> int | None:
    match = TIME_RE.match(time_str.strip())
    if not match:
        return None
    value, unit = int(match.group(1)), match.group(2).lower()
    seconds = value * {"d": 86400, "h": 3600, "m": 60, "s": 1}[unit]
    return seconds if seconds > 0 else None


def safe_channel_name(value: str, limit: int = 28) -> str:
    clean = re.sub(r"[^a-zA-Z0-9\-_\u0600-\u06FF]", "-", value).strip("-").lower()
    return (clean or "user")[:limit]


def guild_icon_url(guild: discord.Guild | None) -> str | None:
    return guild.icon.url if guild and guild.icon else None


def branded_embed(
    interaction: discord.Interaction,
    title: str,
    description: str = "",
    color: int = EMBED_COLOR,
    thumbnail: str | None = None,
    image: str | None = None,
) -> discord.Embed:
    embed = create_embed(title, description, color, thumbnail or guild_icon_url(interaction.guild), image)
    if interaction.guild:
        embed.set_author(name=interaction.guild.name, icon_url=guild_icon_url(interaction.guild))
    return embed


def has_higher_role(actor: discord.Member, target: discord.Member) -> bool:
    if actor.guild.owner_id == actor.id:
        return True
    return actor.top_role > target.top_role


def bot_can_manage_member(guild: discord.Guild, target: discord.Member) -> bool:
    return guild.me is not None and guild.me.top_role > target.top_role and target != guild.owner


def bot_can_manage_role(guild: discord.Guild, role: discord.Role) -> bool:
    return guild.me is not None and role < guild.me.top_role and not role.managed and not role.is_default()


async def check_permissions(interaction: discord.Interaction, command_name: str | None = None) -> bool:
    if not interaction.guild or not isinstance(interaction.user, discord.Member):
        return True
    if interaction.user.id == BOT_OWNER_ID:
        return True
    if interaction.user.guild_permissions.administrator:
        return True
    allowed = await db.check_command_permission(interaction.guild_id, interaction.user, command_name)
    if not allowed:
        if interaction.response.is_done():
            await interaction.followup.send("❌ ليس لديك صلاحية لاستخدام هذا الأمر!", ephemeral=True)
        else:
            await interaction.response.send_message("❌ ليس لديك صلاحية لاستخدام هذا الأمر!", ephemeral=True)
        return False
    return True


class TicketSystem(ui.View):
    def __init__(self) -> None:
        super().__init__(timeout=None)

    @ui.button(label="🎫 دعم فني", style=discord.ButtonStyle.green, custom_id="persistent_ticket:support")
    async def support_ticket(self, interaction: discord.Interaction, _: ui.Button) -> None:
        await interaction.response.send_modal(TicketModal("دعم فني", "support"))

    @ui.button(label="🛒 شراء", style=discord.ButtonStyle.blurple, custom_id="persistent_ticket:purchase")
    async def purchase_ticket(self, interaction: discord.Interaction, _: ui.Button) -> None:
        await interaction.response.send_modal(TicketModal("طلب شراء", "purchase"))


class TicketModal(ui.Modal):
    def __init__(self, ticket_type: str, type_key: str) -> None:
        super().__init__(title=f"فتح تذكرة {ticket_type}")
        self.ticket_type = type_key
        self.reason = ui.TextInput(label="السبب", placeholder="اكتب سبب فتح التذكرة...", required=True, max_length=200)
        self.add_item(self.reason)

    async def on_submit(self, interaction: discord.Interaction) -> None:
        await create_ticket(interaction, str(self.reason.value), self.ticket_type)


class TicketControls(ui.View):
    def __init__(self) -> None:
        super().__init__(timeout=None)

    @ui.button(label="🔒 إغلاق", style=discord.ButtonStyle.red, custom_id="ticket:close")
    async def close_ticket(self, interaction: discord.Interaction, _: ui.Button) -> None:
        if not await bot.user_can_manage_ticket(interaction):
            await interaction.response.send_message("❌ ليس لديك صلاحية!", ephemeral=True)
            return
        await interaction.response.send_message("🔒 سيتم إغلاق التذكرة بعد 3 ثوانٍ...")
        transcript = await build_transcript(interaction.channel)
        await db.close_ticket(interaction.channel_id, transcript)
        await asyncio.sleep(3)
        await interaction.channel.delete(reason=f"Ticket closed by {interaction.user}")

    @ui.button(label="📝 حفظ", style=discord.ButtonStyle.blurple, custom_id="ticket:save")
    async def save_ticket(self, interaction: discord.Interaction, _: ui.Button) -> None:
        if not await bot.user_can_manage_ticket(interaction):
            await interaction.response.send_message("❌ ليس لديك صلاحية!", ephemeral=True)
            return
        transcript = await build_transcript(interaction.channel)
        await db.save_ticket_transcript(interaction.channel_id, transcript)
        file = discord.File(io.BytesIO(transcript.encode("utf-8")), filename=f"{interaction.channel.name}.txt")
        await interaction.response.send_message("📄 تم حفظ المحادثة:", file=file, ephemeral=True)


async def build_transcript(channel: discord.abc.Messageable) -> str:
    lines: list[str] = []
    async for msg in channel.history(limit=1000, oldest_first=True):
        attachments = " ".join(a.url for a in msg.attachments)
        content = msg.content or attachments or "[embed/attachment]"
        lines.append(f"[{msg.created_at.isoformat()}] {msg.author} ({msg.author.id}): {content}")
    return "\n".join(lines) or "No messages."


class AdminBot(commands.Bot):
    def __init__(self) -> None:
        intents = discord.Intents.default()
        intents.members = True
        intents.message_content = True
        intents.guilds = True
        intents.guild_messages = True
        intents.reactions = True
        intents.voice_states = True
        super().__init__(command_prefix=CONFIG.command_prefix, intents=intents, help_command=None)
        self.start_time = now_utc()
        self.ticket_cooldown: dict[int, float] = {}
        self.spam_cache: dict[tuple[int, int], deque[tuple[float, str]]] = defaultdict(deque)

    async def setup_hook(self) -> None:
        await db.initialize()
        self.add_view(TicketSystem())
        self.add_view(TicketControls())
        if CONFIG.sync_commands:
            await self.tree.sync()
        self.check_mutes.start()
        self.check_tempbans.start()
        self.update_status.start()
        self.log_cleanup.start()
        self.auto_close_tickets.start()
        self.giveaway_check.start()
        self.cleanup_cache.start()
        if CONFIG.auto_restart_hours > 0:
            self.auto_restart.change_interval(hours=CONFIG.auto_restart_hours)
            self.auto_restart.start()
        print(f"✅ Bot setup complete | Commands: {len(self.tree.get_commands())}")

    async def on_ready(self) -> None:
        print(f"🤖 {self.user} Online | Guilds: {len(self.guilds)}")

    async def on_message(self, message: discord.Message) -> None:
        if message.author.bot:
            return
        if isinstance(message.channel, discord.DMChannel):
            await message.reply(embed=create_embed("❌ رسائل خاصة معطلة", "البوت يعمل داخل السيرفرات فقط.", ERROR_COLOR))
            return
        await self.automod_check(message)
        await self.process_commands(message)

    async def automod_check(self, message: discord.Message) -> None:
        if not message.guild or not isinstance(message.author, discord.Member):
            return
        settings = await db.get_guild_settings(message.guild.id)
        if not settings.get("automod_enabled", 1):
            return
        if settings.get("automod_antilink"):
            excluded = await db.get_automod_excluded_channels(message.guild.id)
            if message.channel.id not in excluded and URL_RE.search(message.content):
                await message.delete()
                await message.channel.send(f"{message.author.mention} ❌ الروابط غير مسموحة هنا.", delete_after=5)
                return
        if settings.get("automod_antispam"):
            key = (message.guild.id, message.author.id)
            queue = self.spam_cache[key]
            ts = now_utc().timestamp()
            queue.append((ts, message.content.lower().strip()))
            while queue and ts - queue[0][0] > CONFIG.spam_window_seconds:
                queue.popleft()
            duplicates = sum(1 for _, text in queue if text == message.content.lower().strip())
            if len(queue) >= CONFIG.spam_message_limit or duplicates >= CONFIG.spam_duplicate_limit:
                await message.delete()
                await message.author.timeout(timedelta(minutes=10), reason="AutoMod anti-spam")
                await message.channel.send(f"{message.author.mention} ⏱️ تم كتمك 10 دقائق بسبب السبام.", delete_after=8)
                queue.clear()
                return
        await db.add_xp(message.author.id, message.guild.id, random.randint(5, 10))

    async def send_log(self, guild_id: int, log_type: str, member: discord.abc.User | None = None,
                       color: int = INFO_COLOR, description: str = "", fields: list[tuple[str, str, bool]] | None = None) -> None:
        settings = await db.get_guild_settings(guild_id)
        channel_id = settings.get("log_channel")
        channel = self.get_channel(channel_id) if channel_id else None
        if not isinstance(channel, discord.TextChannel):
            return
        embed = create_embed(f"📋 {log_type.upper()}", description, color)
        if member:
            embed.set_thumbnail(url=member.display_avatar.url)
            embed.set_footer(text=f"User ID: {member.id}")
        for name, value, inline in fields or []:
            embed.add_field(name=name, value=value[:1024], inline=inline)
        await channel.send(embed=embed)

    async def user_can_manage_ticket(self, interaction: discord.Interaction) -> bool:
        if not interaction.guild or not isinstance(interaction.user, discord.Member):
            return False
        settings = await db.get_guild_settings(interaction.guild.id)
        support_role = interaction.guild.get_role(settings.get("ticket_role", 0))
        return interaction.user.guild_permissions.administrator or (support_role in interaction.user.roles if support_role else False)

    async def on_member_join(self, member: discord.Member) -> None:
        settings = await db.get_guild_settings(member.guild.id)
        if settings.get("auto_role"):
            role = member.guild.get_role(settings["auto_role"])
            if role:
                await member.add_roles(role, reason="Auto role")
        channel = member.guild.get_channel(settings.get("welcome_channel", 0))
        if isinstance(channel, discord.TextChannel):
            embed = create_embed(
                f"👋 أهلاً {member.display_name}!",
                f"مرحباً في {member.guild.name} 🎉\n👥 الأعضاء: {member.guild.member_count}",
                SUCCESS_COLOR,
                thumbnail=member.display_avatar.url,
                image=WELCOME_IMAGE_URL,
            )
            await channel.send(content=member.mention, embed=embed)
        await self.send_log(member.guild.id, "join", member, LOG_COLORS["join"], f"📥 دخل {member.mention}\n🆔 `{member.id}`")

    async def on_member_remove(self, member: discord.Member) -> None:
        settings = await db.get_guild_settings(member.guild.id)
        channel = member.guild.get_channel(settings.get("goodbye_channel", 0))
        if isinstance(channel, discord.TextChannel):
            await channel.send(embed=create_embed(f"👋 وداعاً {member.display_name}", f"غادر {member.guild.name}", ERROR_COLOR, member.display_avatar.url))
        await self.send_log(member.guild.id, "leave", member, LOG_COLORS["leave"], f"📤 غادر {member.mention}\n🆔 `{member.id}`")

    async def on_message_delete(self, message: discord.Message) -> None:
        if not message.guild or message.author.bot:
            return
        await self.send_log(message.guild.id, "message_delete", message.author, LOG_COLORS["message_delete"],
                            f"🗑️ حذف رسالة\n👤 {message.author.mention}\n📌 {message.channel.mention}\n📝 {(message.content or 'مرفق')[:900]}")

    async def on_message_edit(self, before: discord.Message, after: discord.Message) -> None:
        if not before.guild or before.author.bot or before.content == after.content:
            return
        await self.send_log(
            before.guild.id,
            "message_edit",
            before.author,
            LOG_COLORS["message_edit"],
            f"✏️ تعديل رسالة\n👤 {before.author.mention}\n📌 {before.channel.mention}",
            [("قبل", (before.content or "فارغ")[:500], False), ("بعد", (after.content or "فارغ")[:500], False)],
        )

    async def on_member_update(self, before: discord.Member, after: discord.Member) -> None:
        if before.nick != after.nick:
            await self.send_log(
                after.guild.id,
                "nickname",
                after,
                LOG_COLORS["nickname"],
                f"✏️ تغيير لقب\n👤 {after.mention}",
                [("القديم", before.nick or "لا يوجد", True), ("الجديد", after.nick or "لا يوجد", True)],
            )
        added = [role for role in after.roles if role not in before.roles]
        removed = [role for role in before.roles if role not in after.roles]
        for role in added:
            await self.send_log(after.guild.id, "role_add", after, LOG_COLORS["role_add"], f"🎭 إضافة رتبة\n👤 {after.mention}\n📛 {role.mention}")
        for role in removed:
            await self.send_log(after.guild.id, "role_remove", after, LOG_COLORS["role_remove"], f"🎭 إزالة رتبة\n👤 {after.mention}\n📛 {role.mention}")

    async def on_guild_channel_create(self, channel: discord.abc.GuildChannel) -> None:
        mention = channel.mention if hasattr(channel, "mention") else f"`{channel.name}`"
        await self.send_log(channel.guild.id, "channel_create", None, LOG_COLORS["channel_create"], f"➕ إنشاء قناة\n📌 {mention}")

    async def on_guild_channel_delete(self, channel: discord.abc.GuildChannel) -> None:
        await self.send_log(channel.guild.id, "channel_delete", None, LOG_COLORS["channel_delete"], f"🗑️ حذف قناة\n📌 `{channel.name}`")

    async def on_guild_role_create(self, role: discord.Role) -> None:
        await self.send_log(role.guild.id, "role_create", None, LOG_COLORS["role_create"], f"➕ إنشاء رتبة\n📛 {role.mention}")

    async def on_guild_role_delete(self, role: discord.Role) -> None:
        await self.send_log(role.guild.id, "role_delete", None, LOG_COLORS["role_delete"], f"🗑️ حذف رتبة\n📛 `{role.name}`")

    async def on_voice_state_update(self, member: discord.Member, before: discord.VoiceState, after: discord.VoiceState) -> None:
        if before.channel == after.channel:
            return
        if before.channel and after.channel:
            await self.send_log(member.guild.id, "voice_move", member, LOG_COLORS["voice_move"], f"🔊 نقل\n👤 {member.mention}\n📤 {before.channel.mention}\n📥 {after.channel.mention}")
        elif after.channel:
            await self.send_log(member.guild.id, "voice_join", member, LOG_COLORS["voice_join"], f"🔊 دخول صوتي\n👤 {member.mention}\n📥 {after.channel.mention}")
        elif before.channel:
            await self.send_log(member.guild.id, "voice_leave", member, LOG_COLORS["voice_leave"], f"🔊 خروج صوتي\n👤 {member.mention}\n📤 {before.channel.mention}")

    @tasks.loop(minutes=1)
    async def check_mutes(self) -> None:
        async with aiosqlite.connect(db.db_path) as conn:
            cursor = await conn.execute("SELECT user_id, guild_id FROM tempmutes WHERE expires_at <= ? AND active=1", (now_utc().isoformat(),))
            rows = await cursor.fetchall()
            for user_id, guild_id in rows:
                guild = self.get_guild(guild_id)
                member = guild.get_member(user_id) if guild else None
                role = discord.utils.get(guild.roles, name="Muted") if guild else None
                if member and role and role in member.roles:
                    await member.remove_roles(role, reason="Tempmute expired")
                await conn.execute("UPDATE tempmutes SET active=0 WHERE user_id=? AND guild_id=?", (user_id, guild_id))
            await conn.commit()

    @tasks.loop(minutes=5)
    async def check_tempbans(self) -> None:
        async with aiosqlite.connect(db.db_path) as conn:
            cursor = await conn.execute("SELECT user_id, guild_id FROM tempbans WHERE expires_at <= ? AND active=1", (now_utc().isoformat(),))
            rows = await cursor.fetchall()
            for user_id, guild_id in rows:
                guild = self.get_guild(guild_id)
                if guild:
                    user = await self.fetch_user(user_id)
                    await guild.unban(user, reason="Tempban expired")
                await conn.execute("UPDATE tempbans SET active=0 WHERE user_id=? AND guild_id=?", (user_id, guild_id))
            await conn.commit()

    @tasks.loop(minutes=5)
    async def update_status(self) -> None:
        await self.wait_until_ready()
        await self.change_presence(activity=discord.Activity(type=discord.ActivityType.watching, name=f"/help | {len(self.guilds)} Servers"))

    @tasks.loop(hours=24)
    async def log_cleanup(self) -> None:
        cutoff = (now_utc() - timedelta(days=CONFIG.log_retention_days)).isoformat()
        async with aiosqlite.connect(db.db_path) as conn:
            await conn.execute("DELETE FROM logs WHERE timestamp < ?", (cutoff,))
            await conn.commit()

    @tasks.loop(minutes=15)
    async def auto_close_tickets(self) -> None:
        cutoff = (now_utc() - timedelta(hours=CONFIG.ticket_idle_hours)).isoformat()
        async with aiosqlite.connect(db.db_path) as conn:
            cursor = await conn.execute("SELECT channel_id, guild_id FROM tickets WHERE status='open' AND created_at < ?", (cutoff,))
            rows = await cursor.fetchall()
            for channel_id, guild_id in rows:
                guild = self.get_guild(guild_id)
                channel = guild.get_channel(channel_id) if guild else None
                if isinstance(channel, discord.TextChannel):
                    await channel.send("⏳ تم إغلاق التذكرة لعدم النشاط.")
                    await channel.delete(reason="Ticket idle timeout")
                await conn.execute("UPDATE tickets SET status='closed', closed_at=? WHERE channel_id=?", (now_utc().isoformat(), channel_id))
            await conn.commit()

    @tasks.loop(seconds=30)
    async def giveaway_check(self) -> None:
        for item in await db.get_active_giveaways():
            if item["ends_at"] <= now_utc().isoformat():
                await self.finish_giveaway(item["id"], item["guild_id"], item["channel_id"], item["message_id"], item["winners"])

    async def finish_giveaway(self, gid: int, guild_id: int, channel_id: int, message_id: int, winners_count: int) -> None:
        guild = self.get_guild(guild_id)
        channel = guild.get_channel(channel_id) if guild else None
        if not isinstance(channel, discord.TextChannel):
            return
        msg = await channel.fetch_message(message_id)
        reaction = discord.utils.get(msg.reactions, emoji="🎉")
        users = [user async for user in reaction.users() if not user.bot] if reaction else []
        if not users:
            await msg.reply("❌ لا يوجد مشاركين.")
            await db.end_giveaway(gid, "none")
            return
        winners = random.sample(users, min(winners_count, len(users)))
        await msg.reply(embed=create_embed("🎉 السحب انتهى!", ", ".join(w.mention for w in winners), GOLD_COLOR))
        await db.end_giveaway(gid, ",".join(str(w.id) for w in winners))

    @tasks.loop(hours=3)
    async def auto_restart(self) -> None:
        await self.wait_until_ready()
        print("🔄 Scheduled restart")
        await self.close()
        sys.exit(0)

    @tasks.loop(hours=1)
    async def cleanup_cache(self) -> None:
        self.spam_cache.clear()
        self.ticket_cooldown.clear()


bot = AdminBot()


async def create_ticket(interaction: discord.Interaction, reason: str, ticket_type: str = "support") -> None:
    if not interaction.guild or not isinstance(interaction.user, discord.Member):
        await interaction.response.send_message("❌ التذاكر تعمل داخل السيرفر فقط.", ephemeral=True)
        return
    expires = bot.ticket_cooldown.get(interaction.user.id, 0)
    if expires > now_utc().timestamp():
        await interaction.response.send_message(f"⏳ انتظر <t:{int(expires)}:R> قبل فتح تذكرة جديدة.", ephemeral=True)
        return
    settings = await db.get_guild_settings(interaction.guild.id)
    category = interaction.guild.get_channel(settings.get("ticket_category", 0))
    support_role = interaction.guild.get_role(settings.get("ticket_role", 0))
    overwrites: dict[Any, discord.PermissionOverwrite] = {
        interaction.guild.default_role: discord.PermissionOverwrite(view_channel=False),
        interaction.user: discord.PermissionOverwrite(view_channel=True, send_messages=True, read_message_history=True),
        interaction.guild.me: discord.PermissionOverwrite(view_channel=True, send_messages=True, manage_channels=True),
    }
    if support_role:
        overwrites[support_role] = discord.PermissionOverwrite(view_channel=True, send_messages=True, read_message_history=True)
    prefix = "support" if ticket_type == "support" else "buy"
    channel = await interaction.guild.create_text_channel(
        name=f"{prefix}-{safe_channel_name(interaction.user.name)}-{random.randint(1000, 9999)}",
        category=category if isinstance(category, discord.CategoryChannel) else None,
        overwrites=overwrites,
        topic=f"{ticket_type}: {reason[:80]}",
        reason=f"Ticket by {interaction.user}",
    )
    await db.create_ticket(interaction.guild.id, channel.id, interaction.user.id, reason, ticket_type)
    bot.ticket_cooldown[interaction.user.id] = now_utc().timestamp() + CONFIG.ticket_cooldown_seconds
    mention_support = support_role.mention if support_role else ""
    ticket_embed = branded_embed(
        interaction,
        f"🎫 تذكرة {channel.name}",
        f"**أهلاً {interaction.user.mention}**\n\n📝 **السبب:** {reason}\n👤 **صاحب التذكرة:** `{interaction.user.id}`\n⏰ **تم الفتح:** <t:{int(now_utc().timestamp())}:R>",
        SUCCESS_COLOR,
        thumbnail=guild_icon_url(interaction.guild) or interaction.user.display_avatar.url,
    )
    ticket_embed.set_footer(text="استخدم الأزرار للحفظ أو الإغلاق • Ticket System")
    await channel.send(
        content=f"{interaction.user.mention} {mention_support}",
        embed=ticket_embed,
        view=TicketControls(),
        allowed_mentions=discord.AllowedMentions(users=True, roles=True, everyone=False),
    )
    await interaction.response.send_message(f"✅ تم فتح تذكرتك: {channel.mention}", ephemeral=True)


@bot.tree.command(name="help", description="📚 عرض جميع الأوامر")
async def help_cmd(interaction: discord.Interaction) -> None:
    embed = branded_embed(interaction, "📚 أوامر البوت", color=INFO_COLOR)
    groups = {
        "🛡️ الإدارة": "kick, ban, unban, mute, unmute, warn, warnings, clearwarns, removewarn, purge, tempban, tempmute, nuke",
        "🔒 الحماية والقنوات": "lock, unlock, hide, show, slowmode, automod, antilink, antispam, backup",
        "⚙️ الإعدادات": "settings, setwelcome, setgoodbye, setlogs, autorole",
        "🎭 الرتب": "role, removerole, createrole, deleterole, giverole, removeroleall",
        "🎫 التذاكر": "ticketsetup, setticketrole, ticketinfo",
        "🔊 الصوت": "voicekick, voicemove, moveall, voicemute, voiceunmute, voicedeafen, voiceundeafen",
        "📢 التفاعل": "announce, dmall, poll, remind, addemoji",
        "🎉 السحوبات": "giveaway, glist, greroll, gend",
        "📊 المعلومات": "ping, botinfo, userinfo, serverinfo, avatar, banner, permissions, modlogs",
        "🔐 الصلاحيات": "permit, unpermit",
    }
    for name, value in groups.items():
        embed.add_field(name=name, value=f"`{value}`", inline=False)
    await interaction.response.send_message(embed=embed, ephemeral=True)


@bot.tree.command(name="ping", description="🏓 سرعة الاستجابة")
async def ping(interaction: discord.Interaction) -> None:
    latency = round(bot.latency * 1000)
    color = SUCCESS_COLOR if latency < 150 else WARNING_COLOR if latency < 300 else ERROR_COLOR
    await interaction.response.send_message(embed=create_embed("🏓 Pong!", f"`{latency}ms`", color))


@bot.tree.command(name="botinfo", description="📊 معلومات البوت")
async def botinfo(interaction: discord.Interaction) -> None:
    uptime = now_utc() - bot.start_time
    embed = create_embed(
        f"🤖 {bot.user.name if bot.user else 'Bot'}",
        f"**الإصدار:** {BOT_VERSION}\n**التشغيل:** {str(uptime).split('.')[0]}\n**السيرفرات:** {len(bot.guilds)}\n**الأوامر:** {len(bot.tree.get_commands())}",
        INFO_COLOR,
    )
    await interaction.response.send_message(embed=embed)


@bot.tree.command(name="kick", description="👢 طرد عضو")
@app_commands.checks.has_permissions(kick_members=True)
async def kick(interaction: discord.Interaction, member: discord.Member, reason: str = "غير محدد") -> None:
    if not await check_permissions(interaction, "kick"):
        return
    if member.top_role >= interaction.user.top_role:
        await interaction.response.send_message("❌ لا يمكنك طرد هذا العضو!", ephemeral=True)
        return
    await member.kick(reason=f"By {interaction.user}: {reason}")
    await db.add_log(interaction.guild_id, "kick", member.id, interaction.user.id, reason)
    await bot.send_log(interaction.guild_id, "kick", member, LOG_COLORS["kick"], f"👢 طرد\n👤 {member.mention}\n👮 {interaction.user.mention}\n📝 {reason}")
    await interaction.response.send_message(embed=create_embed("👢 تم الطرد", f"{member.mention}\nالسبب: {reason}", SUCCESS_COLOR))


@bot.tree.command(name="ban", description="🔨 حظر عضو")
@app_commands.checks.has_permissions(ban_members=True)
async def ban(interaction: discord.Interaction, member: discord.Member, reason: str = "غير محدد", delete_messages: app_commands.Range[int, 0, 7] = 0) -> None:
    if not await check_permissions(interaction, "ban"):
        return
    if member.top_role >= interaction.user.top_role:
        await interaction.response.send_message("❌ لا يمكنك حظر هذا العضو!", ephemeral=True)
        return
    await member.ban(reason=f"By {interaction.user}: {reason}", delete_message_days=delete_messages)
    await db.add_log(interaction.guild_id, "ban", member.id, interaction.user.id, reason)
    await bot.send_log(interaction.guild_id, "ban", member, LOG_COLORS["ban"], f"🔨 حظر\n👤 {member.mention}\n👮 {interaction.user.mention}\n📝 {reason}")
    await interaction.response.send_message(embed=create_embed("🔨 تم الحظر", f"{member.mention}\nالسبب: {reason}", SUCCESS_COLOR))


@bot.tree.command(name="unban", description="🔓 فك حظر")
@app_commands.checks.has_permissions(ban_members=True)
async def unban(interaction: discord.Interaction, user_id: str, reason: str = "غير محدد") -> None:
    if not await check_permissions(interaction, "unban"):
        return
    user = await bot.fetch_user(int(user_id))
    await interaction.guild.unban(user, reason=f"By {interaction.user}: {reason}")
    await db.add_log(interaction.guild_id, "unban", user.id, interaction.user.id, reason)
    await interaction.response.send_message(embed=create_embed("🔓 تم فك الحظر", user.mention, SUCCESS_COLOR))


@bot.tree.command(name="mute", description="🔇 كتم Timeout")
@app_commands.checks.has_permissions(moderate_members=True)
async def mute(interaction: discord.Interaction, member: discord.Member, duration: str, reason: str = "غير محدد") -> None:
    if not await check_permissions(interaction, "mute"):
        return
    seconds = parse_time(duration)
    if not seconds or seconds > 2419200:
        await interaction.response.send_message("❌ استخدم مدة صحيحة حتى 28 يوم مثل 1h أو 30m.", ephemeral=True)
        return
    await member.timeout(timedelta(seconds=seconds), reason=reason)
    await db.add_log(interaction.guild_id, "mute", member.id, interaction.user.id, reason, duration)
    await interaction.response.send_message(embed=create_embed("🔇 تم الكتم", f"{member.mention}\nالمدة: {duration}", SUCCESS_COLOR))


@bot.tree.command(name="unmute", description="🔊 فك الكتم")
@app_commands.checks.has_permissions(moderate_members=True)
async def unmute(interaction: discord.Interaction, member: discord.Member) -> None:
    if not await check_permissions(interaction, "unmute"):
        return
    await member.timeout(None, reason=f"Unmuted by {interaction.user}")
    await interaction.response.send_message(embed=create_embed("🔊 تم فك الكتم", member.mention, SUCCESS_COLOR))


@bot.tree.command(name="tempban", description="⏱️ حظر مؤقت")
@app_commands.checks.has_permissions(ban_members=True)
async def tempban(interaction: discord.Interaction, member: discord.Member, duration: str, reason: str = "غير محدد") -> None:
    if not await check_permissions(interaction, "tempban"):
        return
    seconds = parse_time(duration)
    if not seconds:
        await interaction.response.send_message("❌ صيغة خاطئة: 1d, 12h, 30m", ephemeral=True)
        return
    expires = now_utc() + timedelta(seconds=seconds)
    await db.add_tempban(member.id, interaction.guild_id, interaction.user.id, reason, expires.isoformat())
    await member.ban(reason=f"Tempban by {interaction.user}: {reason}")
    await interaction.response.send_message(embed=create_embed("⏱️ حظر مؤقت", f"{member.mention}\nينتهي <t:{int(expires.timestamp())}:R>", SUCCESS_COLOR))


@bot.tree.command(name="tempmute", description="⏱️ كتم مؤقت برتبة Muted")
@app_commands.checks.has_permissions(manage_roles=True)
async def tempmute(interaction: discord.Interaction, member: discord.Member, duration: str, reason: str = "غير محدد") -> None:
    if not await check_permissions(interaction, "tempmute"):
        return
    seconds = parse_time(duration)
    if not seconds:
        await interaction.response.send_message("❌ صيغة خاطئة.", ephemeral=True)
        return
    mute_role = discord.utils.get(interaction.guild.roles, name="Muted")
    if not mute_role:
        mute_role = await interaction.guild.create_role(name="Muted", reason="Mute role created")
    await member.add_roles(mute_role, reason=reason)
    expires = now_utc() + timedelta(seconds=seconds)
    await db.add_tempmute(member.id, interaction.guild_id, interaction.user.id, reason, expires.isoformat())
    await interaction.response.send_message(embed=create_embed("⏱️ كتم مؤقت", f"{member.mention}\nينتهي <t:{int(expires.timestamp())}:R>", SUCCESS_COLOR))


@bot.tree.command(name="warn", description="⚠️ إنذار")
@app_commands.checks.has_permissions(manage_messages=True)
async def warn(interaction: discord.Interaction, member: discord.Member, reason: str) -> None:
    if not await check_permissions(interaction, "warn"):
        return
    await db.add_warning(member.id, interaction.guild_id, interaction.user.id, reason)
    warnings = await db.get_warnings(member.id, interaction.guild_id)
    await interaction.response.send_message(embed=create_embed("⚠️ إنذار", f"{member.mention}\nالسبب: {reason}\nالعدد: {len(warnings)}/3", WARNING_COLOR))
    if len(warnings) >= 3:
        await member.kick(reason="3 warnings")


@bot.tree.command(name="warnings", description="📋 عرض الإنذارات")
async def warnings(interaction: discord.Interaction, member: discord.Member | None = None) -> None:
    member = member or interaction.user
    rows = await db.get_warnings(member.id, interaction.guild_id)
    if not rows:
        await interaction.response.send_message(f"✅ {member.mention} ليس لديه إنذارات!", ephemeral=True)
        return
    embed = create_embed(f"⚠️ إنذارات {member.display_name}", color=WARNING_COLOR, thumbnail=member.display_avatar.url)
    for row in rows[:10]:
        embed.add_field(name=f"#{row['id']}", value=f"{row['reason']}\n{row['timestamp']}", inline=False)
    await interaction.response.send_message(embed=embed, ephemeral=True)


@bot.tree.command(name="clearwarns", description="🗑️ مسح الإنذارات")
@app_commands.checks.has_permissions(administrator=True)
async def clearwarns(interaction: discord.Interaction, member: discord.Member) -> None:
    if not await check_permissions(interaction, "clearwarns"):
        return
    await db.clear_warnings(member.id, interaction.guild_id)
    await interaction.response.send_message(embed=create_embed("🗑️ تم المسح", member.mention, SUCCESS_COLOR))


@bot.tree.command(name="purge", description="🧹 حذف رسائل")
@app_commands.checks.has_permissions(manage_messages=True)
async def purge(interaction: discord.Interaction, amount: app_commands.Range[int, 1, 1000], member: discord.Member | None = None) -> None:
    if not await check_permissions(interaction, "purge"):
        return
    await interaction.response.defer(ephemeral=True)
    deleted = await interaction.channel.purge(limit=amount, check=(lambda m: m.author == member) if member else None)
    await interaction.followup.send(embed=create_embed("🧹 تم الحذف", f"حذف **{len(deleted)}** رسالة.", SUCCESS_COLOR), ephemeral=True)


@bot.tree.command(name="settings", description="⚙️ إعدادات السيرفر")
@app_commands.checks.has_permissions(administrator=True)
async def settings(interaction: discord.Interaction) -> None:
    data = await db.get_guild_settings(interaction.guild_id)
    embed = create_embed("⚙️ إعدادات السيرفر", color=INFO_COLOR)
    for label, key in [("الترحيب", "welcome_channel"), ("الوداع", "goodbye_channel"), ("اللوق", "log_channel"), ("الرتبة التلقائية", "auto_role"), ("كاتيغوري التذاكر", "ticket_category"), ("رتبة الدعم", "ticket_role")]:
        value = data.get(key)
        mention = f"<#{value}>" if "channel" in key or "category" in key else f"<@&{value}>"
        embed.add_field(name=label, value=mention if value else "❌ معطل", inline=True)
    embed.add_field(name="Anti-Link", value="✅" if data.get("automod_antilink") else "❌", inline=True)
    embed.add_field(name="Anti-Spam", value="✅" if data.get("automod_antispam") else "❌", inline=True)
    await interaction.response.send_message(embed=embed, ephemeral=True)


async def set_channel_setting(interaction: discord.Interaction, key: str, channel: discord.TextChannel, label: str) -> None:
    await db.set_guild_setting(interaction.guild_id, key, channel.id)
    await interaction.response.send_message(embed=create_embed("✅ تم الحفظ", f"{label}: {channel.mention}", SUCCESS_COLOR))


@bot.tree.command(name="setwelcome", description="🎉 تعيين قناة الترحيب")
@app_commands.checks.has_permissions(administrator=True)
async def setwelcome(interaction: discord.Interaction, channel: discord.TextChannel) -> None:
    await set_channel_setting(interaction, "welcome_channel", channel, "قناة الترحيب")


@bot.tree.command(name="setgoodbye", description="👋 تعيين قناة الوداع")
@app_commands.checks.has_permissions(administrator=True)
async def setgoodbye(interaction: discord.Interaction, channel: discord.TextChannel) -> None:
    await set_channel_setting(interaction, "goodbye_channel", channel, "قناة الوداع")


@bot.tree.command(name="setlogs", description="📋 قناة السجلات")
@app_commands.checks.has_permissions(administrator=True)
async def setlogs(interaction: discord.Interaction, channel: discord.TextChannel) -> None:
    await set_channel_setting(interaction, "log_channel", channel, "قناة اللوق")


@bot.tree.command(name="autorole", description="🎭 الرتبة التلقائية")
@app_commands.checks.has_permissions(administrator=True)
async def autorole(interaction: discord.Interaction, role: discord.Role) -> None:
    await db.set_guild_setting(interaction.guild_id, "auto_role", role.id)
    await interaction.response.send_message(embed=create_embed("✅ تم الحفظ", f"الرتبة: {role.mention}", SUCCESS_COLOR))


@bot.tree.command(name="automod", description="🤖 تفعيل/تعطيل الحماية")
@app_commands.checks.has_permissions(administrator=True)
async def automod(interaction: discord.Interaction, enabled: bool) -> None:
    await db.set_guild_setting(interaction.guild_id, "automod_enabled", int(enabled))
    await interaction.response.send_message(embed=create_embed("🤖 AutoMod", "مفعل" if enabled else "معطل", SUCCESS_COLOR if enabled else ERROR_COLOR))


@bot.tree.command(name="antilink", description="🔗 تفعيل/تعطيل منع الروابط")
@app_commands.checks.has_permissions(administrator=True)
async def antilink(interaction: discord.Interaction, enabled: bool, excluded_channel: discord.TextChannel | None = None) -> None:
    await db.set_guild_setting(interaction.guild_id, "automod_antilink", int(enabled))
    if excluded_channel and enabled:
        await db.add_automod_excluded_channel(interaction.guild_id, excluded_channel.id)
    await interaction.response.send_message(embed=create_embed("🔗 Anti-Link", "مفعل" if enabled else "معطل", SUCCESS_COLOR if enabled else ERROR_COLOR))


@bot.tree.command(name="antispam", description="🛡️ تفعيل/تعطيل منع السبام")
@app_commands.checks.has_permissions(administrator=True)
async def antispam(interaction: discord.Interaction, enabled: bool) -> None:
    await db.set_guild_setting(interaction.guild_id, "automod_antispam", int(enabled))
    await interaction.response.send_message(embed=create_embed("🛡️ Anti-Spam", "مفعل" if enabled else "معطل", SUCCESS_COLOR if enabled else ERROR_COLOR))


@bot.tree.command(name="ticketsetup", description="🎫 إعداد التذاكر")
@app_commands.checks.has_permissions(administrator=True)
async def ticketsetup(interaction: discord.Interaction, channel: discord.TextChannel, category: discord.CategoryChannel) -> None:
    await db.set_guild_setting(interaction.guild_id, "ticket_category", category.id)
    embed = branded_embed(
        interaction,
        "🎫 مركز التذاكر",
        "**اختر نوع التذكرة من الأزرار بالأسفل**\n\n🟢 دعم فني: للمشاكل والاستفسارات.\n🔵 شراء: للطلبات والمدفوعات.\n\n> سيتم إنشاء روم خاص بينك وبين فريق الدعم.",
        INFO_COLOR,
        thumbnail=guild_icon_url(interaction.guild),
    )
    embed.set_footer(text="Ticket Center • اضغط مرة واحدة فقط")
    await channel.send(embed=embed, view=TicketSystem())
    await interaction.response.send_message(f"✅ تم إعداد واجهة التذاكر في {channel.mention} مع لوجو السيرفر.", ephemeral=True)


@bot.tree.command(name="setticketrole", description="🎫 تحديد رتبة الدعم")
@app_commands.checks.has_permissions(administrator=True)
async def setticketrole(interaction: discord.Interaction, role: discord.Role) -> None:
    await db.set_guild_setting(interaction.guild_id, "ticket_role", role.id)
    await interaction.response.send_message(embed=create_embed("✅ تم", f"رتبة الدعم: {role.mention}", SUCCESS_COLOR))


@bot.tree.command(name="ticketinfo", description="🔍 معلومات تذكرة")
async def ticketinfo(interaction: discord.Interaction, ticket_id: str) -> None:
    ticket = await db.get_ticket_by_channel_id(ticket_id)
    if not ticket:
        await interaction.response.send_message("❌ لم يتم العثور على التذكرة!", ephemeral=True)
        return
    await interaction.response.send_message(embed=create_embed(f"🎫 تذكرة #{ticket['id']}", f"القناة: <#{ticket['channel_id']}>\nالحالة: {ticket['status']}\nالسبب: {ticket['reason']}", INFO_COLOR), ephemeral=True)


@bot.tree.command(name="giveaway", description="🎉 بدء سحب جديد")
@app_commands.checks.has_permissions(administrator=True)
async def giveaway(interaction: discord.Interaction, title: str, description: str, winners: app_commands.Range[int, 1, 20], duration: str, channel: discord.TextChannel | None = None, image: str | None = None) -> None:
    seconds = parse_time(duration)
    if not seconds:
        await interaction.response.send_message("❌ صيغة المدة خاطئة.", ephemeral=True)
        return
    target = channel or interaction.channel
    ends = now_utc() + timedelta(seconds=seconds)
    embed = create_embed(f"🎉 {title}", description, GOLD_COLOR, image=image)
    embed.add_field(name="الفائزون", value=str(winners))
    embed.add_field(name="ينتهي", value=f"<t:{int(ends.timestamp())}:R>")
    embed.set_footer(text="تفاعل بـ 🎉 للدخول")
    msg = await target.send(embed=embed)
    await msg.add_reaction("🎉")
    await db.create_giveaway(interaction.guild_id, target.id, msg.id, title, description, image, winners, ends.isoformat(), interaction.user.id)
    await interaction.response.send_message("✅ تم إنشاء السحب!", ephemeral=True)


@bot.tree.command(name="glist", description="📋 قائمة السحوبات")
@app_commands.checks.has_permissions(administrator=True)
async def glist(interaction: discord.Interaction) -> None:
    rows = await db.get_active_giveaways(interaction.guild_id)
    embed = create_embed("🎉 السحوبات النشطة", color=GOLD_COLOR)
    for row in rows[:10]:
        embed.add_field(name=f"#{row['id']} - {row['title']}", value=f"ينتهي: {row['ends_at']}\nالفائزون: {row['winners']}", inline=False)
    await interaction.response.send_message(embed=embed if rows else create_embed("🎉 السحوبات", "لا توجد سحوبات نشطة.", WARNING_COLOR), ephemeral=True)


@bot.tree.command(name="gend", description="⏹️ إنهاء سحب")
@app_commands.checks.has_permissions(administrator=True)
async def gend(interaction: discord.Interaction, giveaway_id: int) -> None:
    item = await db.get_giveaway(giveaway_id)
    if not item:
        await interaction.response.send_message("❌ لم يتم العثور على السحب.", ephemeral=True)
        return
    await bot.finish_giveaway(item["id"], item["guild_id"], item["channel_id"], item["message_id"], item["winners"])
    await interaction.response.send_message("✅ تم إنهاء السحب.", ephemeral=True)


@bot.tree.command(name="userinfo", description="👤 معلومات المستخدم")
async def userinfo(interaction: discord.Interaction, member: discord.Member | None = None) -> None:
    member = member or interaction.user
    roles = [role.mention for role in member.roles if role != interaction.guild.default_role]
    embed = create_embed(f"👤 {member.display_name}", color=INFO_COLOR, thumbnail=member.display_avatar.url)
    embed.add_field(name="ID", value=str(member.id), inline=True)
    embed.add_field(name="أعلى رتبة", value=member.top_role.mention, inline=True)
    embed.add_field(name="انضم", value=f"<t:{int(member.joined_at.timestamp())}:R>" if member.joined_at else "?", inline=True)
    embed.add_field(name=f"الرتب ({len(roles)})", value=", ".join(roles[:15]) or "لا يوجد", inline=False)
    await interaction.response.send_message(embed=embed)


@bot.tree.command(name="serverinfo", description="🏠 معلومات السيرفر")
async def serverinfo(interaction: discord.Interaction) -> None:
    guild = interaction.guild
    embed = create_embed(f"🏠 {guild.name}", color=INFO_COLOR, thumbnail=guild.icon.url if guild.icon else None)
    embed.add_field(name="المالك", value=guild.owner.mention if guild.owner else "?", inline=True)
    embed.add_field(name="الأعضاء", value=str(guild.member_count), inline=True)
    embed.add_field(name="القنوات", value=str(len(guild.channels)), inline=True)
    embed.add_field(name="الرتب", value=str(len(guild.roles)), inline=True)
    await interaction.response.send_message(embed=embed)


@bot.tree.command(name="avatar", description="🖼️ عرض الصورة")
async def avatar(interaction: discord.Interaction, member: discord.Member | None = None) -> None:
    member = member or interaction.user
    embed = create_embed(f"🖼️ {member.display_name}", color=INFO_COLOR)
    embed.set_image(url=member.display_avatar.url)
    await interaction.response.send_message(embed=embed)


@bot.tree.command(name="permissions", description="🔐 صلاحيات العضو")
async def permissions_cmd(interaction: discord.Interaction, member: discord.Member | None = None) -> None:
    member = member or interaction.user
    perms = [name.replace("_", " ").title() for name, enabled in member.guild_permissions if enabled]
    await interaction.response.send_message(embed=create_embed(f"🔐 صلاحيات {member.display_name}", "\n".join(perms[:25]) or "لا يوجد", INFO_COLOR), ephemeral=True)


@bot.tree.command(name="modlogs", description="📋 سجل الأحداث")
@app_commands.checks.has_permissions(view_audit_log=True)
async def modlogs(interaction: discord.Interaction, member: discord.Member | None = None) -> None:
    rows = await db.get_logs(interaction.guild_id, member.id if member else None, 20)
    embed = create_embed("📋 سجل الأحداث", color=INFO_COLOR)
    for row in rows:
        embed.add_field(name=f"{row['action_type']} • {row['timestamp']}", value=f"المستخدم: <@{row['user_id']}> | المسؤول: <@{row['moderator_id']}>\n{row['reason'] or ''}", inline=False)
    await interaction.response.send_message(embed=embed if rows else create_embed("📋 سجل الأحداث", "لا توجد سجلات.", WARNING_COLOR), ephemeral=True)


@bot.tree.command(name="permit", description="🔐 إعطاء صلاحية أمر")
@app_commands.checks.has_permissions(administrator=True)
async def permit(interaction: discord.Interaction, target: str, command: str | None = None) -> None:
    target_id = int(re.sub(r"[<@&>]", "", target))
    target_type = "role" if "&" in target else "user"
    await db.add_permission(interaction.guild_id, target_id, target_type, command)
    await interaction.response.send_message(embed=create_embed("✅ تم", f"صلاحية `{command or 'الكل'}` محفوظة.", SUCCESS_COLOR))


@bot.tree.command(name="unpermit", description="🔓 سحب صلاحية أمر")
@app_commands.checks.has_permissions(administrator=True)
async def unpermit(interaction: discord.Interaction, target: str, command: str | None = None) -> None:
    target_id = int(re.sub(r"[<@&>]", "", target))
    target_type = "role" if "&" in target else "user"
    await db.remove_permission(interaction.guild_id, target_id, target_type, command)
    await interaction.response.send_message(embed=create_embed("✅ تم", f"تم سحب صلاحية `{command or 'الكل'}`.", SUCCESS_COLOR))


@bot.tree.command(name="removewarn", description="❌ حذف إنذار محدد")
@app_commands.checks.has_permissions(manage_messages=True)
async def removewarn(interaction: discord.Interaction, warn_id: int) -> None:
    if not await check_permissions(interaction, "removewarn"):
        return
    await db.remove_warning(warn_id)
    await interaction.response.send_message(embed=branded_embed(interaction, "❌ تم حذف الإنذار", f"تم حذف الإنذار رقم `#{warn_id}`.", SUCCESS_COLOR), ephemeral=True)


@bot.tree.command(name="lock", description="🔒 قفل قناة")
@app_commands.checks.has_permissions(manage_channels=True)
async def lock(interaction: discord.Interaction, channel: discord.TextChannel | None = None) -> None:
    if not await check_permissions(interaction, "lock"):
        return
    target = channel or interaction.channel
    await target.set_permissions(interaction.guild.default_role, send_messages=False, reason=f"Locked by {interaction.user}")
    await bot.send_log(interaction.guild_id, "channel_lock", None, WARNING_COLOR, f"🔒 قفل قناة\n📌 {target.mention}\n👮 {interaction.user.mention}")
    await interaction.response.send_message(embed=branded_embed(interaction, "🔒 تم القفل", f"تم قفل {target.mention}", SUCCESS_COLOR))


@bot.tree.command(name="unlock", description="🔓 فتح قناة")
@app_commands.checks.has_permissions(manage_channels=True)
async def unlock(interaction: discord.Interaction, channel: discord.TextChannel | None = None) -> None:
    if not await check_permissions(interaction, "unlock"):
        return
    target = channel or interaction.channel
    await target.set_permissions(interaction.guild.default_role, send_messages=True, reason=f"Unlocked by {interaction.user}")
    await bot.send_log(interaction.guild_id, "channel_unlock", None, SUCCESS_COLOR, f"🔓 فتح قناة\n📌 {target.mention}\n👮 {interaction.user.mention}")
    await interaction.response.send_message(embed=branded_embed(interaction, "🔓 تم الفتح", f"تم فتح {target.mention}", SUCCESS_COLOR))


@bot.tree.command(name="hide", description="👻 إخفاء قناة")
@app_commands.checks.has_permissions(manage_channels=True)
async def hide(interaction: discord.Interaction, channel: discord.TextChannel | None = None) -> None:
    if not await check_permissions(interaction, "hide"):
        return
    target = channel or interaction.channel
    await target.set_permissions(interaction.guild.default_role, view_channel=False, reason=f"Hidden by {interaction.user}")
    await interaction.response.send_message(embed=branded_embed(interaction, "👻 تم الإخفاء", f"تم إخفاء {target.mention}", SUCCESS_COLOR), ephemeral=True)


@bot.tree.command(name="show", description="👁️ إظهار قناة")
@app_commands.checks.has_permissions(manage_channels=True)
async def show(interaction: discord.Interaction, channel: discord.TextChannel | None = None) -> None:
    if not await check_permissions(interaction, "show"):
        return
    target = channel or interaction.channel
    await target.set_permissions(interaction.guild.default_role, view_channel=True, reason=f"Shown by {interaction.user}")
    await interaction.response.send_message(embed=branded_embed(interaction, "👁️ تم الإظهار", f"تم إظهار {target.mention}", SUCCESS_COLOR), ephemeral=True)


@bot.tree.command(name="slowmode", description="🐌 تحديد وضع البطيء")
@app_commands.checks.has_permissions(manage_channels=True)
async def slowmode(interaction: discord.Interaction, seconds: app_commands.Range[int, 0, 21600], channel: discord.TextChannel | None = None) -> None:
    if not await check_permissions(interaction, "slowmode"):
        return
    target = channel or interaction.channel
    await target.edit(slowmode_delay=seconds, reason=f"Slowmode by {interaction.user}")
    text = f"تم تعيين البطيء إلى **{seconds}** ثانية في {target.mention}." if seconds else f"تم إلغاء البطيء في {target.mention}."
    await interaction.response.send_message(embed=branded_embed(interaction, "🐌 Slowmode", text, SUCCESS_COLOR))


@bot.tree.command(name="nuke", description="💥 إعادة إنشاء القناة بنفس الإعدادات")
@app_commands.checks.has_permissions(administrator=True)
async def nuke(interaction: discord.Interaction, reason: str = "تنظيف القناة") -> None:
    if not await check_permissions(interaction, "nuke"):
        return
    old_channel = interaction.channel
    new_channel = await old_channel.clone(reason=f"Nuked by {interaction.user}: {reason}")
    await new_channel.edit(position=old_channel.position)
    await old_channel.delete(reason=f"Nuked by {interaction.user}: {reason}")
    embed = branded_embed(interaction, "💥 تم تجديد القناة", f"تمت إعادة إنشاء القناة بواسطة {interaction.user.mention}\n📝 السبب: {reason}", SUCCESS_COLOR)
    await new_channel.send(embed=embed)


@bot.tree.command(name="backup", description="💾 تصدير نسخة JSON لإعدادات السيرفر")
@app_commands.checks.has_permissions(administrator=True)
async def backup(interaction: discord.Interaction) -> None:
    if not await check_permissions(interaction, "backup"):
        return
    await interaction.response.defer(ephemeral=True)
    guild = interaction.guild
    payload = {
        "id": guild.id,
        "name": guild.name,
        "created_at": guild.created_at.isoformat(),
        "roles": [
            {"id": role.id, "name": role.name, "color": role.color.value, "permissions": role.permissions.value, "position": role.position}
            for role in guild.roles if not role.is_default()
        ],
        "channels": [
            {"id": channel.id, "name": channel.name, "type": str(channel.type), "position": channel.position, "category": channel.category.name if getattr(channel, "category", None) else None}
            for channel in guild.channels
        ],
        "exported_at": now_utc().isoformat(),
    }
    data = json.dumps(payload, ensure_ascii=False, indent=2).encode("utf-8")
    file = discord.File(io.BytesIO(data), filename=f"backup_{guild.id}_{int(now_utc().timestamp())}.json")
    await interaction.followup.send(embed=branded_embed(interaction, "💾 تم تجهيز النسخة", "تم تصدير الرتب والقنوات في ملف JSON.", SUCCESS_COLOR), file=file, ephemeral=True)


@bot.tree.command(name="role", description="🎭 إعطاء رتبة لعضو")
@app_commands.checks.has_permissions(manage_roles=True)
async def role(interaction: discord.Interaction, member: discord.Member, role: discord.Role) -> None:
    if not await check_permissions(interaction, "role"):
        return
    if not bot_can_manage_role(interaction.guild, role):
        await interaction.response.send_message("❌ البوت لا يستطيع إدارة هذه الرتبة.", ephemeral=True)
        return
    if not has_higher_role(interaction.user, member):
        await interaction.response.send_message("❌ لا تستطيع تعديل عضو رتبته أعلى أو مساوية لك.", ephemeral=True)
        return
    await member.add_roles(role, reason=f"Role by {interaction.user}")
    await bot.send_log(interaction.guild_id, "role_add", member, LOG_COLORS["role_add"], f"🎭 إعطاء رتبة\n👤 {member.mention}\n📛 {role.mention}\n👮 {interaction.user.mention}")
    await interaction.response.send_message(embed=branded_embed(interaction, "🎭 تم إعطاء الرتبة", f"{role.mention} → {member.mention}", SUCCESS_COLOR))


@bot.tree.command(name="removerole", description="❌ إزالة رتبة من عضو")
@app_commands.checks.has_permissions(manage_roles=True)
async def removerole(interaction: discord.Interaction, member: discord.Member, role: discord.Role) -> None:
    if not await check_permissions(interaction, "removerole"):
        return
    if not bot_can_manage_role(interaction.guild, role):
        await interaction.response.send_message("❌ البوت لا يستطيع إدارة هذه الرتبة.", ephemeral=True)
        return
    await member.remove_roles(role, reason=f"Remove role by {interaction.user}")
    await bot.send_log(interaction.guild_id, "role_remove", member, LOG_COLORS["role_remove"], f"❌ إزالة رتبة\n👤 {member.mention}\n📛 {role.mention}\n👮 {interaction.user.mention}")
    await interaction.response.send_message(embed=branded_embed(interaction, "❌ تم إزالة الرتبة", f"{role.mention} ✕ {member.mention}", SUCCESS_COLOR))


@bot.tree.command(name="createrole", description="➕ إنشاء رتبة")
@app_commands.checks.has_permissions(manage_roles=True)
async def createrole(interaction: discord.Interaction, name: str, color: str = "FFFFFF", permissions: str = "member") -> None:
    if not await check_permissions(interaction, "createrole"):
        return
    color_value = int(color.replace("#", ""), 16) if re.fullmatch(r"#?[0-9a-fA-F]{6}", color) else 0xFFFFFF
    perms = discord.Permissions.none()
    if permissions.lower() == "admin":
        perms = discord.Permissions(administrator=True)
    elif permissions.lower() == "moderator":
        perms = discord.Permissions(manage_messages=True, kick_members=True, ban_members=True, moderate_members=True, manage_nicknames=True)
    role_obj = await interaction.guild.create_role(name=name[:100], color=discord.Color(color_value), permissions=perms, reason=f"Created by {interaction.user}")
    await interaction.response.send_message(embed=branded_embed(interaction, "➕ تم إنشاء الرتبة", role_obj.mention, SUCCESS_COLOR))


@bot.tree.command(name="deleterole", description="🗑️ حذف رتبة")
@app_commands.checks.has_permissions(manage_roles=True)
async def deleterole(interaction: discord.Interaction, role: discord.Role, reason: str = "غير محدد") -> None:
    if not await check_permissions(interaction, "deleterole"):
        return
    if not bot_can_manage_role(interaction.guild, role):
        await interaction.response.send_message("❌ البوت لا يستطيع حذف هذه الرتبة.", ephemeral=True)
        return
    role_name = role.name
    await role.delete(reason=f"By {interaction.user}: {reason}")
    await interaction.response.send_message(embed=branded_embed(interaction, "🗑️ تم حذف الرتبة", f"`{role_name}`\nالسبب: {reason}", SUCCESS_COLOR))


@bot.tree.command(name="giverole", description="📤 إعطاء رتبة لكل الأعضاء")
@app_commands.checks.has_permissions(administrator=True)
async def giverole(interaction: discord.Interaction, role: discord.Role) -> None:
    if not await check_permissions(interaction, "giverole"):
        return
    if not bot_can_manage_role(interaction.guild, role):
        await interaction.response.send_message("❌ البوت لا يستطيع إدارة هذه الرتبة.", ephemeral=True)
        return
    await interaction.response.defer(ephemeral=True)
    count = 0
    for member in interaction.guild.members:
        if not member.bot and role not in member.roles:
            await member.add_roles(role, reason=f"Mass role by {interaction.user}")
            count += 1
            await asyncio.sleep(0.4)
    await interaction.followup.send(embed=branded_embed(interaction, "📤 تم التوزيع", f"تم إعطاء {role.mention} إلى **{count}** عضو.", SUCCESS_COLOR), ephemeral=True)


@bot.tree.command(name="removeroleall", description="📥 إزالة رتبة من كل الأعضاء")
@app_commands.checks.has_permissions(administrator=True)
async def removeroleall(interaction: discord.Interaction, role: discord.Role) -> None:
    if not await check_permissions(interaction, "removeroleall"):
        return
    if not bot_can_manage_role(interaction.guild, role):
        await interaction.response.send_message("❌ البوت لا يستطيع إدارة هذه الرتبة.", ephemeral=True)
        return
    await interaction.response.defer(ephemeral=True)
    count = 0
    for member in interaction.guild.members:
        if role in member.roles:
            await member.remove_roles(role, reason=f"Mass remove role by {interaction.user}")
            count += 1
            await asyncio.sleep(0.4)
    await interaction.followup.send(embed=branded_embed(interaction, "📥 تم السحب", f"تمت إزالة `{role.name}` من **{count}** عضو.", SUCCESS_COLOR), ephemeral=True)


@bot.tree.command(name="nickname", description="✏️ تغيير لقب عضو")
@app_commands.checks.has_permissions(manage_nicknames=True)
async def nickname(interaction: discord.Interaction, member: discord.Member, nickname: str | None = None) -> None:
    if not await check_permissions(interaction, "nickname"):
        return
    if not bot_can_manage_member(interaction.guild, member):
        await interaction.response.send_message("❌ البوت لا يستطيع تعديل هذا العضو.", ephemeral=True)
        return
    old = member.nick or member.name
    await member.edit(nick=nickname, reason=f"Nickname by {interaction.user}")
    await interaction.response.send_message(embed=branded_embed(interaction, "✏️ تم تغيير اللقب", f"قبل: `{old}`\nبعد: `{nickname or member.name}`", SUCCESS_COLOR))


@bot.tree.command(name="banner", description="🖼️ عرض بانر العضو")
async def banner(interaction: discord.Interaction, member: discord.Member | None = None) -> None:
    member = member or interaction.user
    user = await bot.fetch_user(member.id)
    if not user.banner:
        await interaction.response.send_message("❌ هذا المستخدم لا يملك بانر ظاهر.", ephemeral=True)
        return
    embed = branded_embed(interaction, f"🖼️ بانر {member.display_name}", color=INFO_COLOR)
    embed.set_image(url=user.banner.url)
    await interaction.response.send_message(embed=embed)


@bot.tree.command(name="voicekick", description="🔊 طرد عضو من الصوت")
@app_commands.checks.has_permissions(move_members=True)
async def voicekick(interaction: discord.Interaction, member: discord.Member) -> None:
    if not await check_permissions(interaction, "voicekick"):
        return
    if not member.voice:
        await interaction.response.send_message("❌ العضو ليس داخل روم صوتي.", ephemeral=True)
        return
    await member.move_to(None, reason=f"Voice kick by {interaction.user}")
    await interaction.response.send_message(embed=branded_embed(interaction, "🔊 تم الطرد الصوتي", member.mention, SUCCESS_COLOR))


@bot.tree.command(name="voicemove", description="🔊 نقل عضو لروم صوتي")
@app_commands.checks.has_permissions(move_members=True)
async def voicemove(interaction: discord.Interaction, member: discord.Member, channel: discord.VoiceChannel) -> None:
    if not await check_permissions(interaction, "voicemove"):
        return
    if not member.voice:
        await interaction.response.send_message("❌ العضو ليس داخل روم صوتي.", ephemeral=True)
        return
    await member.move_to(channel, reason=f"Voice move by {interaction.user}")
    await interaction.response.send_message(embed=branded_embed(interaction, "🔊 تم النقل", f"{member.mention} → {channel.mention}", SUCCESS_COLOR))


@bot.tree.command(name="moveall", description="🔊 نقل كل أعضاء روم صوتي")
@app_commands.checks.has_permissions(move_members=True)
async def moveall(interaction: discord.Interaction, from_channel: discord.VoiceChannel, to_channel: discord.VoiceChannel) -> None:
    if not await check_permissions(interaction, "moveall"):
        return
    count = 0
    for member in list(from_channel.members):
        await member.move_to(to_channel, reason=f"Move all by {interaction.user}")
        count += 1
    await interaction.response.send_message(embed=branded_embed(interaction, "🔊 تم نقل الجميع", f"تم نقل **{count}** عضو إلى {to_channel.mention}", SUCCESS_COLOR))


@bot.tree.command(name="voicemute", description="🔇 كتم عضو صوتياً")
@app_commands.checks.has_permissions(mute_members=True)
async def voicemute(interaction: discord.Interaction, member: discord.Member) -> None:
    if not await check_permissions(interaction, "voicemute"):
        return
    await member.edit(mute=True, reason=f"Voice mute by {interaction.user}")
    await interaction.response.send_message(embed=branded_embed(interaction, "🔇 تم الكتم الصوتي", member.mention, SUCCESS_COLOR))


@bot.tree.command(name="voiceunmute", description="🔊 فك الكتم الصوتي")
@app_commands.checks.has_permissions(mute_members=True)
async def voiceunmute(interaction: discord.Interaction, member: discord.Member) -> None:
    if not await check_permissions(interaction, "voiceunmute"):
        return
    await member.edit(mute=False, reason=f"Voice unmute by {interaction.user}")
    await interaction.response.send_message(embed=branded_embed(interaction, "🔊 تم فك الكتم الصوتي", member.mention, SUCCESS_COLOR))


@bot.tree.command(name="voicedeafen", description="🔇 تصميم عضو صوتياً")
@app_commands.checks.has_permissions(deafen_members=True)
async def voicedeafen(interaction: discord.Interaction, member: discord.Member) -> None:
    if not await check_permissions(interaction, "voicedeafen"):
        return
    await member.edit(deafen=True, reason=f"Voice deafen by {interaction.user}")
    await interaction.response.send_message(embed=branded_embed(interaction, "🔇 تم التصميم", member.mention, SUCCESS_COLOR))


@bot.tree.command(name="voiceundeafen", description="🔊 فك التصميم الصوتي")
@app_commands.checks.has_permissions(deafen_members=True)
async def voiceundeafen(interaction: discord.Interaction, member: discord.Member) -> None:
    if not await check_permissions(interaction, "voiceundeafen"):
        return
    await member.edit(deafen=False, reason=f"Voice undeafen by {interaction.user}")
    await interaction.response.send_message(embed=branded_embed(interaction, "🔊 تم فك التصميم", member.mention, SUCCESS_COLOR))


@bot.tree.command(name="announce", description="📢 إرسال إعلان Embed")
@app_commands.checks.has_permissions(mention_everyone=True)
async def announce(interaction: discord.Interaction, channel: discord.TextChannel, title: str, message: str, mention_everyone: bool = False) -> None:
    if not await check_permissions(interaction, "announce"):
        return
    embed = branded_embed(interaction, f"📢 {title}", message[:4000], INFO_COLOR)
    content = "@everyone" if mention_everyone else None
    await channel.send(content=content, embed=embed, allowed_mentions=discord.AllowedMentions(everyone=mention_everyone))
    await interaction.response.send_message(f"✅ تم إرسال الإعلان إلى {channel.mention}", ephemeral=True)


@bot.tree.command(name="dmall", description="📩 إرسال رسالة خاصة لكل الأعضاء")
@app_commands.checks.has_permissions(administrator=True)
async def dmall(interaction: discord.Interaction, message: str) -> None:
    if not await check_permissions(interaction, "dmall"):
        return
    await interaction.response.defer(ephemeral=True)
    sent = 0
    failed = 0
    embed = branded_embed(interaction, f"📩 رسالة من {interaction.guild.name}", message[:4000], INFO_COLOR)
    for member in interaction.guild.members:
        if member.bot:
            continue
        try:
            await member.send(embed=embed)
            sent += 1
            await asyncio.sleep(0.8)
        except discord.DiscordException:
            failed += 1
    await interaction.followup.send(embed=branded_embed(interaction, "📩 انتهى الإرسال", f"✅ وصل: **{sent}**\n❌ فشل: **{failed}**", SUCCESS_COLOR), ephemeral=True)


@bot.tree.command(name="poll", description="📊 إنشاء تصويت")
async def poll(interaction: discord.Interaction, question: str, opt1: str, opt2: str, opt3: str | None = None, opt4: str | None = None) -> None:
    if not await check_permissions(interaction, "poll"):
        return
    options = [option for option in (opt1, opt2, opt3, opt4) if option]
    emojis = ["1️⃣", "2️⃣", "3️⃣", "4️⃣"]
    embed = branded_embed(interaction, f"📊 {question}", "\n".join(f"{emojis[i]} {option}" for i, option in enumerate(options)), INFO_COLOR)
    await interaction.response.send_message(embed=embed)
    msg = await interaction.original_response()
    for emoji in emojis[:len(options)]:
        await msg.add_reaction(emoji)


@bot.tree.command(name="remind", description="⏰ تذكير خاص")
async def remind(interaction: discord.Interaction, time: str, message: str) -> None:
    if not await check_permissions(interaction, "remind"):
        return
    seconds = parse_time(time)
    if not seconds or seconds > 604800:
        await interaction.response.send_message("❌ المدة غير صحيحة، الحد الأقصى 7 أيام.", ephemeral=True)
        return
    await interaction.response.send_message(embed=branded_embed(interaction, "⏰ تم ضبط التذكير", f"سأذكرك بعد `{time}`.", SUCCESS_COLOR), ephemeral=True)
    await asyncio.sleep(seconds)
    try:
        await interaction.user.send(embed=create_embed("⏰ تذكير", message[:4000], INFO_COLOR))
    except discord.DiscordException:
        await interaction.channel.send(interaction.user.mention, embed=create_embed("⏰ تذكير", message[:4000], INFO_COLOR), allowed_mentions=discord.AllowedMentions(users=True))


@bot.tree.command(name="addemoji", description="😀 إضافة إيموجي للسيرفر")
@app_commands.checks.has_permissions(manage_emojis_and_stickers=True)
async def addemoji(interaction: discord.Interaction, name: str, image: discord.Attachment) -> None:
    if not await check_permissions(interaction, "addemoji"):
        return
    if image.size > 256000:
        await interaction.response.send_message("❌ حجم الصورة أكبر من 256KB.", ephemeral=True)
        return
    data = await image.read()
    emoji = await interaction.guild.create_custom_emoji(name=name[:32], image=data, reason=f"Emoji by {interaction.user}")
    await interaction.response.send_message(embed=branded_embed(interaction, "😀 تم إضافة الإيموجي", str(emoji), SUCCESS_COLOR))


@bot.tree.command(name="greroll", description="🎲 إعادة اختيار فائز للسحب")
@app_commands.checks.has_permissions(administrator=True)
async def greroll(interaction: discord.Interaction, giveaway_id: int) -> None:
    if not await check_permissions(interaction, "greroll"):
        return
    item = await db.get_giveaway(giveaway_id)
    if not item:
        await interaction.response.send_message("❌ لم يتم العثور على السحب.", ephemeral=True)
        return
    channel = interaction.guild.get_channel(item["channel_id"])
    if not isinstance(channel, discord.TextChannel):
        await interaction.response.send_message("❌ قناة السحب غير موجودة.", ephemeral=True)
        return
    msg = await channel.fetch_message(item["message_id"])
    reaction = discord.utils.get(msg.reactions, emoji="🎉")
    users = [user async for user in reaction.users() if not user.bot] if reaction else []
    if not users:
        await interaction.response.send_message("❌ لا يوجد مشاركين.", ephemeral=True)
        return
    winner = random.choice(users)
    await msg.reply(embed=branded_embed(interaction, "🎲 فائز جديد", winner.mention, GOLD_COLOR))
    await interaction.response.send_message(f"✅ الفائز الجديد: {winner.mention}", ephemeral=True)


@bot.tree.error
async def on_app_command_error(interaction: discord.Interaction, error: app_commands.AppCommandError) -> None:
    message = "❌ حدث خطأ أثناء تنفيذ الأمر."
    if isinstance(error, app_commands.MissingPermissions):
        message = "❌ لا تملك صلاحيات Discord المطلوبة."
    elif isinstance(error, app_commands.BotMissingPermissions):
        message = "❌ البوت لا يملك الصلاحيات المطلوبة."
    elif isinstance(error, app_commands.CommandOnCooldown):
        message = f"⏳ انتظر {error.retry_after:.1f} ثانية."
    if interaction.response.is_done():
        await interaction.followup.send(message, ephemeral=True)
    else:
        await interaction.response.send_message(message, ephemeral=True)
    print(f"[Command Error] {error!r}")


if __name__ == "__main__":
    if not BOT_TOKEN:
        raise RuntimeError("BOT_TOKEN environment variable is required")
    bot.run(BOT_TOKEN)
