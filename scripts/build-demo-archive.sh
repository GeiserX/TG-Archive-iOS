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

archive = {
    "auth_check": {"authenticated": True, "auth_required": False, "role": None, "username": None, "no_download": False},
    "stats": load("stats"),
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
print(f"demo archive: {len(everything)} chats, {total} messages, {bundled} of {len(photos)} photos bundled")
PY
