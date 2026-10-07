#!/usr/bin/env bash
# Captures the JSON fixtures the unit tests decode, from a running demo server (scripts/demo-server.sh).
#   scripts/capture-fixtures.sh [base-url]      default http://127.0.0.1:${PORT:-8000}
# Env: DEMO_USERNAME, DEMO_PASSWORD (master login, demo defaults), DEMO_SHARE_TOKEN (the generator's token).
#
# The demo archive is synthetic, so every response is kept whole. It signs in three times in all (the
# master, one wrong password, the share link), well under the server's 15 attempts per 5 minutes, logs
# both sessions out at the end, and fails unless the messages it saved hold every kind of message the
# generator makes. It replaces every *.json under TGArchiveTests/Fixtures.
set -euo pipefail

cd "$(dirname "$0")/.."
BASE_URL=${1:-http://127.0.0.1:${PORT:-8000}}
STAGE=$(mktemp -d)
trap 'rm -rf "${STAGE:?}"' EXIT

BASE_URL="$BASE_URL" STAGE="$STAGE" \
DEMO_USERNAME="${DEMO_USERNAME:-admin}" DEMO_PASSWORD="${DEMO_PASSWORD:-demo-admin-not-a-secret}" \
DEMO_SHARE_TOKEN="${DEMO_SHARE_TOKEN:-demo-share-link-not-a-secret}" \
python3 -I - <<'PY'
import http.cookiejar, json, os, re, sys, urllib.error, urllib.parse, urllib.request
from collections import Counter

base, stage = os.environ["BASE_URL"].rstrip("/"), os.environ["STAGE"]
saved = {}


def opener():
    return urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))


def call(session, path, *, body=None, method=None, expect=200, save=None):
    data = json.dumps(body).encode() if body is not None else None
    method = method or ("POST" if data else "GET")
    request = urllib.request.Request(base + path, data=data, method=method)
    if data is not None:
        request.add_header("Content-Type", "application/json")
    try:
        with session.open(request, timeout=30) as response:
            status, raw = response.status, response.read()
    except urllib.error.HTTPError as error:
        status, raw = error.code, error.read()
    if status != expect:
        sys.exit(f"{method} {path}: expected {expect}, got {status}: {raw[:300]!r}")
    value = json.loads(raw)
    if save:
        if save in saved:
            sys.exit(f"two captures want the name {save}.json")
        saved[save] = value
        with open(os.path.join(stage, save + ".json"), "w", encoding="utf-8") as f:
            json.dump(value, f, ensure_ascii=False, indent=2)
            f.write("\n")
    return value


def q(**params):
    return "?" + urllib.parse.urlencode(params)


def display_name(chat):
    name = chat.get("title") or " ".join(p for p in (chat.get("first_name"), chat.get("last_name")) if p)
    return name or chat.get("username") or "deleted-account"


def slug(text):
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


anonymous = opener()
call(anonymous, "/api/health", save="health")
call(anonymous, "/api/auth/check", save="auth-check-signed-out")
call(anonymous, "/api/chats", expect=401, save="error-401")
call(anonymous, "/api/login", body={"username": os.environ["DEMO_USERNAME"], "password": "not-the-password"},
     expect=401, save="login-401")

master = opener()
call(master, "/api/login", body={"username": os.environ["DEMO_USERNAME"], "password": os.environ["DEMO_PASSWORD"]},
     save="login")
if not call(master, "/api/auth/check", save="auth-check").get("authenticated"):
    sys.exit("the master login did not give an authenticated session")

call(master, "/api/stats", save="stats")
call(master, "/api/folders", save="folders")
call(master, "/api/archived/count", save="archived-count")
chats = call(master, "/api/chats" + q(limit=50, offset=0, archived="false"), save="chats")["chats"]
archived = call(master, "/api/chats" + q(limit=50, offset=0, archived="true"), save="chats-archived")["chats"]
everything = chats + archived

# One name per chat: its display name, plus the account when two chats share a name (the private chat
# between the archive's two accounts is kept once per account).
names = Counter(slug(display_name(c)) for c in everything)
chat_slug = {}
for c in everything:
    s = slug(display_name(c))
    chat_slug[c["ref"]] = s if names[s] == 1 else f"{s}-account{c['accounts'][0]}"

messages = {}  # ref -> {id: message} for every message captured from that chat
for c in everything:
    ref, s = c["ref"], chat_slug[c["ref"]]
    page = call(master, f"/api/chats/{ref}/messages" + q(limit=50), save=f"messages-{s}")
    if len(page) == 50:
        last = page[-1]
        page = page + call(master, f"/api/chats/{ref}/messages" + q(limit=50, before_date=last["date"], before_id=last["id"]),
                           save=f"messages-{s}-older")
    messages[ref] = {m["id"]: m for m in page}

largest = max(everything, key=lambda c: len(messages[c["ref"]]))
call(master, f"/api/chats/{largest['ref']}", save="chat")
call(master, f"/api/chats/{largest['ref']}/stats", save="chat-stats")

forum = next(c for c in everything if c.get("is_forum"))
topics = call(master, f"/api/chats/{forum['ref']}/topics", save="topics")["topics"]
call(master, f"/api/chats/{forum['ref']}/messages" + q(limit=50, topic_id=topics[0]["id"]),
     save=f"messages-{chat_slug[forum['ref']]}-topic")

pinned_chat = next(c for c in everything if any(m.get("is_pinned") for m in messages[c["ref"]].values()))
call(master, f"/api/chats/{pinned_chat['ref']}/pinned", save="pinned")

# Earlier versions: the message whose edit replaced its photo, and the text edit with the most versions.
edited = [(ref, m["id"]) for ref in messages for m in messages[ref].values() if m.get("version_count")]
versions = {key: call(master, f"/api/chats/{key[0]}/messages/{key[1]}/versions") for key in edited}
with_media = next(key for key, v in versions.items() if any("media" in x for x in v))
most = max((key for key in versions if key != with_media), key=lambda key: len(versions[key]))
for name, (ref, mid) in (("versions-media", with_media), ("versions", most)):
    call(master, f"/api/chats/{ref}/messages/{mid}/versions", save=name)

search = call(master, "/api/search/messages" + q(q="the", limit=20, offset=0), save="search")
call(master, "/api/search/messages" + q(q="solder", limit=20, offset=0), save="search-topics")

# A chat opened at a search hit: the hit and older, then the newer messages.
hit_ref = search["results"][0]["chat"]["ref"]
anchor = min(r["id"] for r in search["results"] if r["chat"]["ref"] == hit_ref)
call(master, f"/api/chats/{hit_ref}/messages" + q(limit=50, before_id=anchor + 1), save="messages-anchored-before")
call(master, f"/api/chats/{hit_ref}/messages" + q(limit=50, after_id=anchor), save="messages-anchored-after")

every = [m for ms in messages.values() for m in ms.values()]
ids = sorted({r["emoji"][len("custom_"):] for m in every for r in m.get("reactions") or []
              if str(r["emoji"]).startswith("custom_")}
             | {e["document_id"] for m in every for e in (m.get("raw_data") or {}).get("entities") or []
                if e.get("type") == "custom_emoji"})
call(master, "/api/custom-emoji" + q(ids=",".join(ids)), save="custom-emoji")
call(master, "/api/chats/not-a-chat/messages", expect=404, save="error-404")

# The share link: one chat, downloads off.
share = opener()
call(share, "/auth/token", body={"token": os.environ["DEMO_SHARE_TOKEN"]}, save="token-login")
if not call(share, "/api/auth/check", save="auth-check-token").get("no_download"):
    sys.exit("the demo share link is expected to have downloads off")
token_ref = call(share, "/api/chats" + q(limit=50, offset=0, archived="false"), save="token-chats")["chats"][0]["ref"]
call(share, f"/api/chats/{token_ref}/messages" + q(limit=50), save="token-messages")
photo = next(m["media"]["id"] for m in messages[token_ref].values() if (m.get("media") or {}).get("type") == "photo")
call(share, f"/media/thumb/400/{token_ref}/{photo}", expect=403, save="error-403")

call(share, "/api/logout", method="POST", save="logout")
call(master, "/api/logout", method="POST")
call(master, "/api/auth/check", save="auth-check-after-logout")

# Every kind of message the generator's docstring names must be in the master's saved message pages.
pages = [m for name, v in saved.items() if name.startswith("messages-") or name == "pinned" for m in v]


def media(m):
    return m.get("media") or {}


def raw(m):
    return m.get("raw_data") or {}


def transcripts(m):
    return media(m).get("transcripts") or []


def entity(m, kind):
    return any(e.get("type") == kind for e in raw(m).get("entities") or [])


albums = Counter(raw(m)["grouped_id"] for m in pages if raw(m).get("grouped_id"))
required = {
    "photo": lambda m: media(m).get("type") == "photo",
    "album": lambda m: albums.get(raw(m).get("grouped_id"), 0) > 1,
    "picture sticker": lambda m: media(m).get("type") == "sticker" and media(m).get("mime_type") == "image/webp",
    "animated sticker": lambda m: media(m).get("type") == "sticker" and media(m).get("mime_type") == "application/x-tgsticker",
    "video sticker": lambda m: media(m).get("type") == "sticker" and media(m).get("mime_type") == "video/webm",
    "voice note with a transcript": lambda m: media(m).get("type") == "voice" and any(t["status"] == "done" and t.get("text") for t in transcripts(m)),
    "transcript that failed": lambda m: any(t["status"] == "failed" for t in transcripts(m)),
    "transcript with no speech": lambda m: any(t["status"] == "done" and t.get("text") == "" for t in transcripts(m)),
    "two transcripts": lambda m: len(transcripts(m)) > 1,
    "round video": lambda m: media(m).get("type") == "video_note",
    "video": lambda m: media(m).get("type") == "video",
    "document": lambda m: media(m).get("type") == "document",
    "location": lambda m: "lat" in (raw(m).get("geo") or {}),
    "location without a point": lambda m: media(m).get("type") == "geo" and "geo" not in raw(m),
    "venue": lambda m: "venue" in raw(m),
    "live location": lambda m: "geo_live" in raw(m),
    "contact": lambda m: "contact" in raw(m),
    "poll": lambda m: "poll" in raw(m),
    "poll with a later state": lambda m: "poll" in (m.get("snapshots") or {}),
    "link card with a later state": lambda m: "preview" in (m.get("snapshots") or {}),
    "reply": lambda m: m.get("reply_to_msg_id"),
    "forward": lambda m: raw(m).get("forward_from_name"),
    "reactions": lambda m: m.get("reactions"),
    "reactions taken back": lambda m: m.get("removed_reactions"),
    "custom emoji reaction": lambda m: any(str(r["emoji"]).startswith("custom_") for r in m.get("reactions") or []),
    "custom emoji in text": lambda m: entity(m, "custom_emoji"),
    "formatted text": lambda m: entity(m, "bold"),
    "edit with earlier versions": lambda m: m.get("version_count"),
    "edit Telegram hides": lambda m: m.get("edit_date") and m.get("edit_hide") == 1,
    "deleted in Telegram, kept": lambda m: m.get("is_deleted"),
    "pinned": lambda m: m.get("is_pinned"),
    "outgoing": lambda m: m.get("is_outgoing"),
    "service row": lambda m: raw(m).get("action_type"),
    "forum topic message": lambda m: m.get("reply_to_top_id"),
    "not downloaded (too large)": lambda m: media(m).get("skip_reason") == "oversize",
    "not downloaded (filtered)": lambda m: media(m).get("skip_reason") == "filtered",
    "not downloaded yet": lambda m: bool(media(m)) and media(m).get("downloaded") is False and not media(m).get("skip_reason"),
}
missing = [kind for kind, test in required.items() if not any(test(m) for m in pages)]
# Under the share link, downloads are off: media rows keep their key but lose the url.
if not any(media(m).get("type") == "photo" and media(m).get("url") is None for m in saved["token-messages"]):
    missing.append("a photo with downloads off")
if missing:
    sys.exit("the captured messages lack: " + ", ".join(missing))
print(f"captured {len(saved)} fixtures from {base}: {len(pages)} messages covering all {len(required)} kinds")
PY

rm -f TGArchiveTests/Fixtures/*.json
cp "${STAGE:?}"/*.json TGArchiveTests/Fixtures/
