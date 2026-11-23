#!/usr/bin/env bash
# Builds the demo archive bundled in the app ("Try the demo" on the connect screen) from the committed
# unit-test fixtures, which hold the demo server's invented archive.
#   scripts/build-demo-archive.sh [media-dir]
# media-dir is a demo server's `backups/media` folder (scripts/demo-server.sh, under DATA_DIR). When given,
# the photos the bundled messages show are copied in too, scaled to 960 px on the long side; without it the
# photos already in the bundle stay. Rerun after scripts/capture-fixtures.sh.
#
# Writes TGArchive/Resources/DemoArchive/DemoArchive.json: every chat with its messages, the folders (the
# fixtures do not say which chat is in which, so private chats go in Friends and groups in Hobbies), the
# forum topics and the archive figures.
set -euo pipefail

cd "$(dirname "$0")/.."
OUT=TGArchive/Resources/DemoArchive
MEDIA_DIR=${1:-}
mkdir -p "$OUT"

OUT="$OUT" MEDIA_DIR="$MEDIA_DIR" python3 -I - <<'PY'
import glob, json, os, re, subprocess
from collections import Counter

fixtures, out, media_dir = "TGArchiveTests/Fixtures", os.environ["OUT"], os.environ["MEDIA_DIR"]


def load(name):
    with open(os.path.join(fixtures, name + ".json"), encoding="utf-8") as f:
        return json.load(f)


# The same names capture-fixtures.sh gives each chat's message files.
def display_name(chat):
    name = chat.get("title") or " ".join(p for p in (chat.get("first_name"), chat.get("last_name")) if p)
    return name or chat.get("username") or "deleted-account"


def slug(text):
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


chats, archived = load("chats")["chats"], load("chats-archived")["chats"]
everything = chats + archived
names = Counter(slug(display_name(c)) for c in everything)
by_ref = {}
for c in everything:
    s = slug(display_name(c))
    by_ref[c["ref"]] = s if names[s] == 1 else f"{s}-account{c['accounts'][0]}"
refs_by_chat_id = Counter(c["id"] for c in everything)
ref_of_chat_id = {c["id"]: c["ref"] for c in everything if refs_by_chat_id[c["id"]] == 1}

messages = {ref: {} for ref in by_ref}
for ref, s in by_ref.items():
    for name in (f"messages-{s}", f"messages-{s}-older", f"messages-{s}-topic"):
        if os.path.exists(os.path.join(fixtures, name + ".json")):
            for m in load(name):
                messages[ref][m["id"]] = m
# Pages captured from other routes add what the first pages did not reach, where the chat is unambiguous.
for name in ("pinned", "messages-anchored-before", "messages-anchored-after"):
    for m in load(name):
        ref = ref_of_chat_id.get(m["chat_id"])
        if ref:
            messages[ref].setdefault(m["id"], m)

forum = next(c["ref"] for c in everything if c.get("is_forum"))
folders = load("folders")["folders"]
private = [c["ref"] for c in chats if c["type"] == "private"]
groups = [c["ref"] for c in chats if c["type"] != "private" and c["type"] != "channel"]
members = {folders[0]["id"]: private[: folders[0]["chat_count"]], folders[1]["id"]: groups[: folders[1]["chat_count"]]}

# A contact who deleted their Telegram account, which the server's demo generator does not make: a private
# chat with Wren, who is also in two groups, with the time the archive saw the account deleted on the chat
# (account_deleted_at) and on Wren's messages everywhere (sender_account_deleted_at). The names are kept.
WREN, WREN_REF, WREN_GONE = 7100009, "Wr3nOakh0llowGoneDem0A", "2026-09-24T09:30:00"
wren_lines = [
    (90, "2026-09-22T18:40:00", False, "Finished the lantern build. The hinge finally sits flush."),
    (91, "2026-09-22T18:47:00", True, "Bring it on Thursday, Dax will want to see that hinge."),
    (92, "2026-09-24T09:12:00", False, "I'm leaving Telegram for a while. You'll find me at the book club."),
    (93, "2026-09-24T09:20:00", True, "Understood. I'll save you a seat by the window."),
]
owner = {"sender_id": 7000001, "first_name": "Robin", "last_name": "Ashgrove", "sender_name": "Robin Ashgrove",
         "username": "robin_ashgrove", "sender_account_id": 1, "sender_avatar_url": None}
wren = {"sender_id": WREN, "first_name": "Wren", "last_name": "Oakhollow", "sender_name": "Wren Oakhollow",
        "username": "wren_oak", "sender_account_id": None, "sender_avatar_url": None}
messages[WREN_REF] = {}
for mid, date, outgoing, text in wren_lines:
    who = owner if outgoing else wren
    messages[WREN_REF][mid] = {
        "chat_id": WREN, "id": mid, "date": date, "created_at": date, "text": text, "is_outgoing": int(outgoing),
        "is_deleted": 0, "deleted_at": None, "is_pinned": 0, "edit_date": None, "edit_hide": None,
        "version_count": 0, "forward_from_id": None, "media": None, "raw_data": {}, "reactions": [],
        "removed_reactions": [], "reaction_history": [], "reaction_history_omitted": 0, "reply_to_msg_id": None,
        "reply_to_text": None, "reply_to_top_id": None, "snapshots": {}, **who,
    }
for ms in messages.values():
    for m in ms.values():
        if m.get("sender_id") == WREN:
            m["sender_account_deleted_at"] = WREN_GONE
last_id, last_date, last_outgoing, last_text = wren_lines[-1]
wren_chat = {
    "ref": WREN_REF, "id": WREN, "type": "private", "title": None, "first_name": "Wren", "last_name": "Oakhollow",
    "username": "wren_oak", "phone": None, "description": None, "participants_count": None, "is_forum": 0,
    "is_archived": 0, "account_id": 1, "accounts": [1], "avatar_photo_id": None, "avatar_url": None,
    "last_message_date": last_date, "last_synced_message_id": 0, "created_at": wren_lines[0][1],
    "updated_at": WREN_GONE, "account_deleted_at": WREN_GONE,
    "preview": {"message_id": last_id, "date": last_date, "text": last_text, "sender": "You" if last_outgoing else None,
                "kind": "text", "outgoing": last_outgoing, "action": None, "action_title": None},
}
chats.insert(next(i for i, c in enumerate(chats) if c["last_message_date"] < last_date), wren_chat)
stats = load("stats")
stats["chats"] += 1
stats["messages"] += len(wren_lines)

archive = {
    "auth_check": {"authenticated": True, "auth_required": False, "role": None, "username": None, "no_download": False},
    "stats": stats,
    "folders": folders,
    "folder_members": {str(k): v for k, v in members.items()},
    "chats": chats,
    "archived": archived,
    "topics": {forum: load("topics")["topics"]},
    "messages": {ref: sorted(ms.values(), key=lambda m: (m["date"], m["id"]), reverse=True) for ref, ms in messages.items()},
}

photos = {}
for ref, ms in archive["messages"].items():
    for m in ms:
        media = m.get("media") or {}
        if media.get("type") == "photo" and media.get("downloaded") and media.get("file_path"):
            photos[f"demo-{ref}-{media['id']}.jpg"] = media["file_path"]

if media_dir:
    for old in glob.glob(os.path.join(out, "demo-*.jpg")):
        os.remove(old)
    for name, path in sorted(photos.items()):
        source = os.path.join(media_dir, path)
        if os.path.exists(source):
            subprocess.run(["sips", "-Z", "960", "-s", "format", "jpeg", "-s", "formatOptions", "70",
                            source, "--out", os.path.join(out, name)], check=True, capture_output=True)

with open(os.path.join(out, "DemoArchive.json"), "w", encoding="utf-8") as f:
    json.dump(archive, f, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
    f.write("\n")

total = sum(len(ms) for ms in archive["messages"].values())
bundled = len(glob.glob(os.path.join(out, "demo-*.jpg")))
print(f"demo archive: {len(chats) + len(archived)} chats, {total} messages, {bundled} of {len(photos)} photos bundled")
PY
