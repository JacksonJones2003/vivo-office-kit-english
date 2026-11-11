#!/usr/bin/env python3
"""Local iCloud Photos service for the vivo Office Kit patch.

This runs on 127.0.0.1 and serves the in-app photos panel. It talks to iCloud
with pyicloud: Apple ID + password + the normal two-factor code. The photo grid
is rendered inside the app window; nothing is opened in a separate window.

The service prints one JSON line when ready:
    VOK_ICLOUD_READY {"port": 12345, "token": "..."}
and writes the same information to server.json in VOK_ICLOUD_DIR.
"""
from __future__ import annotations

import json
import mimetypes
import os
import re
import secrets
import shutil
import subprocess
import sys
import threading
import time
import traceback
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

BASE_DIR = os.environ.get("VOK_ICLOUD_DIR") or os.path.dirname(os.path.abspath(__file__))
COOKIE_DIR = os.path.join(BASE_DIR, "cookies")
THUMB_DIR = os.path.join(BASE_DIR, "thumbnails")
ACCOUNT_FILE = os.path.join(BASE_DIR, "account.json")
SERVER_FILE = os.path.join(BASE_DIR, "server.json")
LOG_FILE = os.path.join(BASE_DIR, "service.log")
DOWNLOAD_DIR = os.path.join(os.path.expanduser("~"), "Pictures", "iCloud Photos")
MOCK = os.environ.get("VOK_ICLOUD_MOCK") == "1"
TOKEN = secrets.token_urlsafe(24)

os.makedirs(BASE_DIR, exist_ok=True)
os.makedirs(COOKIE_DIR, exist_ok=True)
os.makedirs(THUMB_DIR, exist_ok=True)
os.makedirs(DOWNLOAD_DIR, exist_ok=True)

try:
    from pyicloud import PyiCloudService
    from pyicloud.exceptions import (
        PyiCloudAcceptTermsException,
        PyiCloudAccountLockedException,
        PyiCloudException,
        PyiCloudFailedLoginException,
        PyiCloud2FARequiredException,
        PyiCloud2SARequiredException,
    )
except Exception as exc:  # pragma: no cover - reported through the UI
    PyiCloudService = None  # type: ignore
    PyiCloudException = Exception  # type: ignore
    PyiCloudFailedLoginException = Exception  # type: ignore
    PyiCloud2FARequiredException = Exception  # type: ignore
    PyiCloud2SARequiredException = Exception  # type: ignore
    PyiCloudAccountLockedException = Exception  # type: ignore
    PyiCloudAcceptTermsException = Exception  # type: ignore
    IMPORT_ERROR = str(exc)
else:
    IMPORT_ERROR = ""

LOCK = threading.RLock()
API = None
ACCOUNT = ""
ALBUM = None
PHOTO_ITER = None
TOTAL = 0
CACHE: list = []
ASSETS: dict[str, object] = {}
EXHAUSTED = False
LAST_ERROR = ""
SELECTED_DEVICE = None
JOBS: dict[str, dict] = {}
STATE = "starting"  # starting | logged_out | needs_2fa | needs_2sa | ready | error


def log(message: str) -> None:
    try:
        with open(LOG_FILE, "a", encoding="utf-8") as fh:
            fh.write(f"{datetime.now().isoformat(timespec='seconds')} {message}\n")
    except Exception:
        pass


def read_account() -> str:
    try:
        with open(ACCOUNT_FILE, "r", encoding="utf-8") as fh:
            return str(json.load(fh).get("apple_id") or "")
    except Exception:
        return ""


def save_account(apple_id: str) -> None:
    try:
        with open(ACCOUNT_FILE, "w", encoding="utf-8") as fh:
            json.dump({"apple_id": apple_id}, fh)
        os.chmod(ACCOUNT_FILE, 0o600)
    except Exception:
        pass


def clear_session_files() -> None:
    try:
        shutil.rmtree(COOKIE_DIR, ignore_errors=True)
        os.makedirs(COOKIE_DIR, exist_ok=True)
        os.remove(ACCOUNT_FILE)
    except Exception:
        pass


def reset_photos() -> None:
    global ALBUM, PHOTO_ITER, TOTAL, CACHE, ASSETS, EXHAUSTED, LAST_ERROR
    with LOCK:
        ALBUM = None
        PHOTO_ITER = None
        TOTAL = 0
        CACHE = []
        ASSETS = {}
        EXHAUSTED = False
        LAST_ERROR = ""


def init_album() -> None:
    global ALBUM, PHOTO_ITER, TOTAL, CACHE, ASSETS, EXHAUSTED, LAST_ERROR, STATE
    with LOCK:
        ALBUM = API.photos.all
        PHOTO_ITER = ALBUM.photos
        TOTAL = len(ALBUM)
        CACHE = []
        ASSETS = {}
        EXHAUSTED = False
        LAST_ERROR = ""
        STATE = "ready"
    log(f"photo library ready: {TOTAL} items")


def ensure_photos(limit: int) -> list:
    global EXHAUSTED, LAST_ERROR
    with LOCK:
        if PHOTO_ITER is None:
            return CACHE[:limit]
        while len(CACHE) < limit and not EXHAUSTED:
            try:
                asset = next(PHOTO_ITER)
            except StopIteration:
                EXHAUSTED = True
                break
            except Exception as exc:
                LAST_ERROR = str(exc)
                EXHAUSTED = True
                log("photo listing failed: " + str(exc))
                break
            CACHE.append(asset)
            ASSETS[asset.id] = asset
        return CACHE[:limit]


def photo_json(asset) -> dict:
    try:
        w, h = asset.dimensions
    except Exception:
        w, h = None, None
    try:
        date = asset.asset_date.isoformat()
    except Exception:
        date = ""
    return {
        "id": asset.id,
        "filename": asset.filename,
        "date": date,
        "type": asset.item_type,
        "width": w,
        "height": h,
        "live": bool(getattr(asset, "is_live_photo", False)),
    }


def get_asset(asset_id: str):
    with LOCK:
        if asset_id in ASSETS:
            return ASSETS[asset_id]
    ensure_photos(len(CACHE) + 100)
    with LOCK:
        return ASSETS.get(asset_id)


def thumb_key(asset) -> str | None:
    versions = getattr(asset, "versions", {}) or {}
    if asset.item_type == "movie":
        for key in ("thumb_video", "thumb_image", "thumb"):
            if key in versions and versions[key].get("url"):
                return key
        return None
    for key in ("thumb", "medium"):
        if key in versions and versions[key].get("url"):
            return key
    return None


def thumb_bytes(asset):
    path = os.path.join(THUMB_DIR, asset.id + ".jpg")
    if os.path.exists(path):
        try:
            with open(path, "rb") as fh:
                return fh.read(), "image/jpeg"
        except Exception:
            pass
    if MOCK:
        data = mock_thumb(asset)
        return data, "image/svg+xml"
    key = thumb_key(asset)
    if not key:
        return None, None
    with LOCK:
        data = asset.download(key)
    if not data:
        return None, None
    try:
        with open(path, "wb") as fh:
            fh.write(data)
    except Exception:
        pass
    ctype = (getattr(asset, "versions", {}).get(key) or {}).get("type") or "image/jpeg"
    return data, ctype


def sanitize_filename(name: str) -> str:
    name = (name or "photo").replace("/", "_").replace("\\", "_").strip()
    return name[:180] or "photo"


def unique_path(directory: str, name: str) -> str:
    base, ext = os.path.splitext(sanitize_filename(name))
    path = os.path.join(directory, base + ext)
    n = 1
    while os.path.exists(path):
        path = os.path.join(directory, f"{base} ({n}){ext}")
        n += 1
    return path


def mock_thumb(asset) -> bytes:
    colors = ["#3a7afe", "#7b61ff", "#e85d75", "#f2a93b", "#2fb380", "#4aa3df", "#d06bd8", "#8b6f47"]
    idx = int("".join(ch for ch in asset.id if ch.isdigit()) or "0") % len(colors)
    label = asset.filename[-18:]
    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" width="480" height="360">
<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
<stop offset="0" stop-color="{colors[idx]}"/><stop offset="1" stop-color="{colors[(idx+3) % len(colors)]}"/>
</linearGradient></defs>
<rect width="480" height="360" fill="url(#g)"/>
<circle cx="360" cy="90" r="42" fill="rgba(255,255,255,.35)"/>
<path d="M0 300 L140 190 L240 270 L330 210 L480 320 L480 360 L0 360 Z" fill="rgba(255,255,255,.18)"/>
<text x="24" y="336" font-family="-apple-system,Helvetica" font-size="18" fill="white">{label}</text>
</svg>"""
    return svg.encode("utf-8")


def mock_assets():
    base = datetime(2026, 11, 1, 12, 0, tzinfo=timezone.utc)
    out = []
    for i in range(30):
        class A:
            id = f"mock{i:03d}"
            filename = f"IMG_{1000+i}.HEIC"
            item_type = "image"
            is_live_photo = i % 7 == 0
            dimensions = (4032, 3024)
            asset_date = base.fromtimestamp(base.timestamp() - i * 86400, tz=timezone.utc)
            versions = {"thumb": {"url": "mock", "type": "image/svg+xml"}}
            def download(self, key="original", **kwargs):
                return mock_thumb(self)
        out.append(A())
    return out


def start_mock():
    global ALBUM, PHOTO_ITER, TOTAL, CACHE, ASSETS, EXHAUSTED, STATE, API
    assets = mock_assets()
    with LOCK:
        ALBUM = None
        CACHE = []
        ASSETS = {}
        for asset in assets:
            CACHE.append(asset)
            ASSETS[asset.id] = asset
        PHOTO_ITER = None
        TOTAL = len(assets)
        EXHAUSTED = True
        STATE = "ready"
    log("mock mode ready")


def restore_session() -> None:
    global API, ACCOUNT, STATE
    if MOCK:
        ACCOUNT = "mock@example.com"
        start_mock()
        return
    if IMPORT_ERROR:
        STATE = "error"
        log("pyicloud import failed: " + IMPORT_ERROR)
        return
    apple_id = read_account()
    if not apple_id:
        STATE = "logged_out"
        return
    try:
        api = PyiCloudService(apple_id, None, cookie_directory=COOKIE_DIR, authenticate=False)
        status = api.get_auth_status()
        if status.get("authenticated"):
            API = api
            ACCOUNT = apple_id
            init_album()
        else:
            STATE = "logged_out"
    except Exception as exc:
        STATE = "logged_out"
        log("session restore failed: " + str(exc))


def login(apple_id: str, password: str) -> dict:
    global API, ACCOUNT, STATE, SELECTED_DEVICE
    if MOCK:
        ACCOUNT = apple_id or "mock@example.com"
        start_mock()
        return {"ok": True, "mock": True}
    if IMPORT_ERROR:
        return {"ok": False, "message": "The iCloud library is not installed: " + IMPORT_ERROR}
    clear_session_files()
    reset_photos()
    try:
        api = PyiCloudService(
            apple_id,
            password,
            cookie_directory=COOKIE_DIR,
            accept_terms=True,
        )
    except PyiCloudAccountLockedException:
        STATE = "logged_out"
        return {"ok": False, "message": "This Apple ID is locked. Unlock it at appleid.apple.com and try again."}
    except PyiCloudAcceptTermsException:
        STATE = "logged_out"
        return {"ok": False, "message": "Apple requires you to accept the updated iCloud terms. Sign in at iCloud.com once, then try again."}
    except PyiCloudFailedLoginException:
        STATE = "logged_out"
        return {"ok": False, "message": "Apple rejected the Apple ID or password."}
    except Exception as exc:
        STATE = "logged_out"
        log("login failed: " + str(exc))
        return {"ok": False, "message": str(exc)}
    API = api
    ACCOUNT = apple_id
    save_account(apple_id)
    if api.requires_2fa:
        STATE = "needs_2fa"
        return {"ok": False, "needs_2fa": True, "message": "Enter the six-digit code shown on your Apple devices."}
    if api.requires_2sa:
        STATE = "needs_2sa"
        try:
            devices = api.trusted_devices
        except Exception:
            devices = []
        return {"ok": False, "needs_2sa": True, "devices": [
            {"index": i, "name": d.get("deviceName") or d.get("name") or "Apple device",
             "model": d.get("model") or "", "phone": d.get("phoneNumber") or ""}
            for i, d in enumerate(devices)
        ]}
    try:
        init_album()
    except Exception as exc:
        STATE = "error"
        log("album init failed: " + str(exc))
        return {"ok": False, "message": "Signed in, but iCloud Photos could not be opened: " + str(exc)}
    return {"ok": True}


def verify_2fa(code: str) -> dict:
    global STATE
    if API is None:
        return {"ok": False, "message": "Sign in again."}
    try:
        ok = API.validate_2fa_code(code)
    except Exception as exc:
        log("2fa error: " + str(exc))
        return {"ok": False, "message": str(exc)}
    if not ok:
        return {"ok": False, "message": "That code was not accepted. Try the newest six-digit code."}
    try:
        API.trust_session()
    except Exception:
        pass
    try:
        init_album()
    except Exception as exc:
        STATE = "error"
        return {"ok": False, "message": "Signed in, but iCloud Photos could not be opened: " + str(exc)}
    return {"ok": True}


def start_2sa(index: int) -> dict:
    global SELECTED_DEVICE
    if API is None:
        return {"ok": False, "message": "Sign in again."}
    try:
        devices = API.trusted_devices
        device = devices[index]
        API.send_verification_code(device)
        SELECTED_DEVICE = device
        return {"ok": True}
    except Exception as exc:
        return {"ok": False, "message": str(exc)}


def verify_2sa(code: str) -> dict:
    if API is None or SELECTED_DEVICE is None:
        return {"ok": False, "message": "Choose a trusted device first."}
    try:
        ok = API.validate_verification_code(SELECTED_DEVICE, code)
    except Exception as exc:
        return {"ok": False, "message": str(exc)}
    if not ok:
        return {"ok": False, "message": "That code was not accepted."}
    try:
        init_album()
    except Exception as exc:
        return {"ok": False, "message": str(exc)}
    return {"ok": True}


def logout() -> dict:
    global API, ACCOUNT, STATE
    try:
        if API is not None and hasattr(API, "logout"):
            API.logout()
    except Exception:
        pass
    API = None
    ACCOUNT = ""
    STATE = "logged_out"
    reset_photos()
    clear_session_files()
    return {"ok": True}


def start_download(ids: list[str]) -> dict:
    job_id = secrets.token_hex(8)
    job = {"id": job_id, "total": len(ids), "done": 0, "errors": [], "files": [], "status": "running"}
    JOBS[job_id] = job

    def work():
        for asset_id in ids:
            asset = get_asset(asset_id)
            if asset is None:
                job["errors"].append(f"{asset_id}: not found")
                continue
            try:
                if MOCK:
                    data = mock_thumb(asset)
                    name = asset.filename.rsplit(".", 1)[0] + ".svg"
                else:
                    key = "original"
                    data = asset.download(key)
                    name = asset.filename
                    if data is None and "original" in asset.versions:
                        data = asset.download("original")
                if not data:
                    job["errors"].append(f"{asset.filename}: no download URL")
                    continue
                dest = unique_path(DOWNLOAD_DIR, name)
                with open(dest, "wb") as fh:
                    fh.write(data)
                job["files"].append(dest)
                job["done"] += 1
            except Exception as exc:
                job["errors"].append(f"{asset.filename}: {exc}")
            finally:
                job["done"] = max(job["done"], len(job["files"]) + len(job["errors"]))
        job["status"] = "done"
        log(f"download job {job_id} finished: {len(job['files'])} files, {len(job['errors'])} errors")

    threading.Thread(target=work, daemon=True).start()
    return {"ok": True, "job": job}


class Handler(BaseHTTPRequestHandler):
    server_version = "VOKiCloud/1.0"

    def log_message(self, fmt, *args):
        message = re.sub(r"token=[^&\s\"]+", "token=…", fmt % args)
        log("%s - %s" % (self.address_string(), message))

    def send_json(self, obj, status=200):
        data = json.dumps(obj).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def send_bytes(self, data, ctype="application/octet-stream", status=200):
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "max-age=86400")
        self.end_headers()
        self.wfile.write(data)

    def token_ok(self, query) -> bool:
        return (query.get("token", [""])[0] or self.headers.get("X-VOK-Token", "")) == TOKEN

    def do_GET(self):
        parsed = urlparse(self.path)
        query = parse_qs(parsed.query)
        path = parsed.path
        if path == "/favicon.ico":
            return self.send_bytes(b"", "image/x-icon", 204)
        if not self.token_ok(query):
            return self.send_json({"ok": False, "message": "Invalid token"}, 403)
        if path == "/":
            try:
                with open(os.path.join(BASE_DIR, "ui.html"), "rb") as fh:
                    return self.send_bytes(fh.read(), "text/html; charset=utf-8")
            except Exception as exc:
                return self.send_json({"ok": False, "message": str(exc)}, 500)
        if path == "/api/status":
            return self.send_json({
                "ok": True,
                "authenticated": STATE == "ready",
                "state": STATE,
                "account": ACCOUNT,
                "total": TOTAL,
                "mock": MOCK,
                "error": LAST_ERROR,
                "import_error": IMPORT_ERROR,
            })
        if path == "/api/photos":
            try:
                offset = max(0, int(query.get("offset", ["0"])[0]))
                limit = min(200, max(1, int(query.get("limit", ["60"])[0])))
            except ValueError:
                return self.send_json({"ok": False, "message": "Bad offset/limit"}, 400)
            photos = ensure_photos(offset + limit)
            items = [photo_json(a) for a in photos[offset:offset + limit]]
            with LOCK:
                has_more = len(CACHE) > offset + limit or (not EXHAUSTED and len(CACHE) < TOTAL)
            return self.send_json({"ok": True, "photos": items, "total": TOTAL, "offset": offset, "has_more": has_more})
        if path == "/api/thumb":
            asset_id = query.get("id", [""])[0]
            asset = get_asset(asset_id)
            if asset is None:
                return self.send_json({"ok": False, "message": "Photo not found"}, 404)
            try:
                data, ctype = thumb_bytes(asset)
            except Exception as exc:
                log("thumbnail failed: " + str(exc))
                data, ctype = None, None
            if not data:
                return self.send_json({"ok": False, "message": "No thumbnail"}, 404)
            return self.send_bytes(data, ctype or "image/jpeg")
        if path == "/api/job":
            job_id = query.get("id", [""])[0]
            job = JOBS.get(job_id)
            if not job:
                return self.send_json({"ok": False, "message": "Job not found"}, 404)
            return self.send_json({"ok": True, "job": job})
        return self.send_json({"ok": False, "message": "Not found"}, 404)

    def do_POST(self):
        parsed = urlparse(self.path)
        query = parse_qs(parsed.query)
        if not self.token_ok(query):
            return self.send_json({"ok": False, "message": "Invalid token"}, 403)
        length = int(self.headers.get("Content-Length", "0") or 0)
        try:
            body = json.loads(self.rfile.read(length) or b"{}")
        except Exception:
            body = {}
        path = parsed.path
        try:
            if path == "/api/login":
                return self.send_json(login(str(body.get("apple_id", "")).strip(), str(body.get("password", ""))))
            if path == "/api/2fa":
                return self.send_json(verify_2fa(str(body.get("code", "")).strip()))
            if path == "/api/2sa/send":
                return self.send_json(start_2sa(int(body.get("index", 0))))
            if path == "/api/2sa/verify":
                return self.send_json(verify_2sa(str(body.get("code", "")).strip()))
            if path == "/api/logout":
                return self.send_json(logout())
            if path == "/api/download":
                ids = body.get("ids") or []
                if not isinstance(ids, list) or not ids:
                    return self.send_json({"ok": False, "message": "No photos selected"}, 400)
                return self.send_json(start_download([str(i) for i in ids]))
            if path == "/api/open-downloads":
                os.makedirs(DOWNLOAD_DIR, exist_ok=True)
                subprocess.Popen(["/usr/bin/open", DOWNLOAD_DIR])
                return self.send_json({"ok": True})
            return self.send_json({"ok": False, "message": "Not found"}, 404)
        except Exception as exc:
            log("request failed: " + str(exc) + "\n" + traceback.format_exc())
            return self.send_json({"ok": False, "message": str(exc)}, 500)


def main() -> None:
    global STATE, ACCOUNT
    if MOCK:
        ACCOUNT = "mock@example.com"
        start_mock()
    else:
        threading.Thread(target=restore_session, daemon=True).start()
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    port = server.server_address[1]
    state = {"port": port, "token": TOKEN, "pid": os.getpid(), "mock": MOCK}
    with open(SERVER_FILE, "w", encoding="utf-8") as fh:
        json.dump(state, fh)
    os.chmod(SERVER_FILE, 0o600)
    print("VOK_ICLOUD_READY " + json.dumps(state), flush=True)
    log(f"listening on 127.0.0.1:{port} mock={MOCK}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
