#!/usr/bin/env python3
"""
cloak2nlm_bridge.py
CloakBrowser (CDP) → notebooklm-py (storage_state.json) Cookie 桥接

功能:
  从运行中的 CloakBrowser 通过 CDP 提取 Google 域 Cookie
  转换为 Playwright storage_state.json 格式
  写入 notebooklm-py 的认证目录

用法:
  python3 cloak2nlm_bridge.py                    # 手动执行
  # 或作为 NOTEBOOKLM_REFRESH_CMD 自动触发
  # 或由 cron 每15分钟调用
"""

import json
import sys
import os
import asyncio
import logging
from pathlib import Path

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [bridge] %(message)s",
    datefmt="%H:%M:%S"
)
log = logging.getLogger("bridge")

# ─── 配置 ─────────────────────────────────────────────
CDP_HOST = os.getenv("CLOAK_CDP_HOST", "127.0.0.1")
CDP_PORT = int(os.getenv("CLOAK_CDP_PORT", "9222"))
NBLM_HOME = Path(os.getenv("NOTEBOOKLM_HOME", os.path.expanduser("~/.notebooklm")))
NBLM_PROFILE = os.getenv("NOTEBOOKLM_PROFILE", "default")
STORAGE_PATH = NBLM_HOME / "profiles" / NBLM_PROFILE / "storage_state.json"

GOOGLE_DOMAINS = [
    ".google.com",
    ".google.co.jp",
    ".google.co.uk",
    "notebooklm.google.com",
    "accounts.google.com",
    "myaccount.google.com",
    ".youtube.com",
]

CRITICAL_COOKIES = [
    "__Secure-1PSID",
    "__Secure-3PSID",
    "__Secure-1PSIDTS",
    "SID",
    "HSID",
    "SSID",
    "APISID",
    "SAPISID",
]


async def extract_cookies_from_cloak() -> list[dict]:
    """通过 CDP WebSocket 从 CloakBrowser 提取 Google cookies"""
    try:
        import httpx
    except ImportError:
        log.error("缺少 httpx，请运行: pip install httpx")
        sys.exit(1)

    # 获取页面列表
    async with httpx.AsyncClient() as http:
        try:
            resp = await http.get(
                f"http://{CDP_HOST}:{CDP_PORT}/json",
                timeout=5
            )
            targets = resp.json()
        except Exception as e:
            log.error(f"无法连接 CloakBrowser CDP ({CDP_HOST}:{CDP_PORT}): {e}")
            log.error("请确认 CloakBrowser 正在运行: cloak_launch()")
            sys.exit(1)

    # 找到 WebSocket URL
    ws_url = None
    for t in targets:
        if t.get("type") == "page":
            ws_url = t.get("webSocketDebuggerUrl")
            break

    if not ws_url:
        # 回退到 browser 级别
        async with httpx.AsyncClient() as http:
            resp = await http.get(
                f"http://{CDP_HOST}:{CDP_PORT}/json/version",
                timeout=5
            )
            ws_url = resp.json().get("webSocketDebuggerUrl")

    if not ws_url:
        log.error("无法获取 CloakBrowser WebSocket URL")
        sys.exit(1)

    # 通过 WebSocket 获取 cookies
    try:
        import websockets
    except ImportError:
        log.error("缺少 websockets，请运行: pip install websockets")
        sys.exit(1)

    async with websockets.connect(ws_url, max_size=10 * 1024 * 1024) as ws:
        await ws.send(json.dumps({
            "id": 1,
            "method": "Network.getCookies",
            "params": {
                "urls": [
                    "https://www.google.com",
                    "https://accounts.google.com",
                    "https://notebooklm.google.com",
                    "https://myaccount.google.com",
                    "https://docs.google.com",
                    "https://drive.google.com",
                ]
            },
        }))
        resp = json.loads(await ws.recv())
        cookies = resp.get("result", {}).get("cookies", [])
        log.info(f"从 CloakBrowser 提取到 {len(cookies)} 个 cookies")
        return cookies


def cdp_to_playwright(cdp_cookies: list[dict]) -> dict:
    """CDP cookie 格式 → Playwright storage_state.json 格式"""
    pw_cookies = []
    for c in cdp_cookies:
        domain = c.get("domain", "")
        # 只保留 Google 相关域名
        if not any(domain.endswith(d.lstrip(".")) for d in GOOGLE_DOMAINS):
            continue

        ss = c.get("sameSite", "Lax")
        if ss not in ("Strict", "Lax", "None"):
            ss = "Lax"

        pw_cookies.append({
            "name": c["name"],
            "value": c["value"],
            "domain": domain,
            "path": c.get("path", "/"),
            "expires": c.get("expires", -1),
            "httpOnly": c.get("httpOnly", False),
            "secure": c.get("secure", False),
            "sameSite": ss,
        })

    return {
        "cookies": pw_cookies,
        "origins": [
            {
                "origin": "https://notebooklm.google.com",
                "localStorage": [],
            }
        ],
    }


async def bridge() -> int:
    """主流程: CloakBrowser CDP → storage_state.json"""
    # 提取 cookies
    cookies = await extract_cookies_from_cloak()
    if not cookies:
        log.error("CloakBrowser 中没有 cookies。请先登录 Google。")
        return 1

    # 转换格式
    storage = cdp_to_playwright(cookies)
    if not storage["cookies"]:
        log.error("没有找到 Google 相关 cookies。请确认已登录 Google。")
        return 1

    # 写入文件
    STORAGE_PATH.parent.mkdir(parents=True, exist_ok=True)
    STORAGE_PATH.write_text(json.dumps(storage, indent=2))
    os.chmod(STORAGE_PATH, 0o600)

    # 统计关键 cookies
    names = {c["name"] for c in storage["cookies"]}
    present = [n for n in CRITICAL_COOKIES if n in names]
    missing = [n for n in CRITICAL_COOKIES if n not in names]

    log.info(f"已写入: {STORAGE_PATH}")
    log.info(f"  Google cookies: {len(storage['cookies'])} 个")
    log.info(f"  关键 cookies: {present}")
    if missing:
        log.warning(f"  缺失: {missing} (可能需要重新登录)")

    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(bridge()))
