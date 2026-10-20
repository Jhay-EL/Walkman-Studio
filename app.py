#!/usr/bin/env python3
"""
Sony Walkman Studio - Unified macOS Desktop Launcher.
Spins up the FastAPI backend and launches a native macOS WKWebView desktop window
using pywebview (with automatic browser fallback).
"""

import os
import sys
import time
import socket
import threading
import urllib.request
import webbrowser
from pathlib import Path

import uvicorn

DEFAULT_PORT = 8455
HOST = "127.0.0.1"


def is_port_in_use(port: int, host: str = "127.0.0.1") -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        return s.connect_ex((host, port)) == 0


def is_walkman_studio_alive(port: int, host: str = "127.0.0.1") -> bool:
    """Verifies that the process on the port is indeed Walkman Studio API."""
    try:
        url = f"http://{host}:{port}/api/drives"
        req = urllib.request.Request(url, headers={"User-Agent": "WalkmanStudio"})
        with urllib.request.urlopen(req, timeout=1.0) as resp:
            if resp.status == 200:
                body = resp.read()
                return b"drives" in body
    except Exception:
        pass
    return False


def find_free_port(start_port: int = DEFAULT_PORT, host: str = "127.0.0.1") -> int:
    port = start_port
    while port < start_port + 50:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            if s.connect_ex((host, port)) != 0:
                return port
        port += 1
    return start_port


def start_backend(port: int):
    """Runs Uvicorn serving FastAPI backend."""
    root_dir = Path(__file__).resolve().parent
    if str(root_dir) not in sys.path:
        sys.path.insert(0, str(root_dir))

    from backend.main import app
    config = uvicorn.Config(
        app=app,
        host=HOST,
        port=port,
        log_level="warning",
        access_log=False,
    )
    server = uvicorn.Server(config)
    server.run()


def wait_for_server(port: int, timeout: float = 10.0) -> bool:
    start_time = time.time()
    while time.time() - start_time < timeout:
        if is_walkman_studio_alive(port):
            return True
        time.sleep(0.15)
    return False


def main():
    print("=" * 60)
    print("  Sony Walkman Studio (macOS Apple Silicon)")
    print("  Target: Sony Walkman NW-A55L & Walkman One CFW")
    print("=" * 60)

    # 1. Determine active port
    port = DEFAULT_PORT
    if is_walkman_studio_alive(port):
        print(f"[+] Walkman Studio engine already running on http://{HOST}:{port}")
    else:
        if is_port_in_use(port):
            print(f"[!] Warning: Port {port} is occupied by another application.")
            port = find_free_port(DEFAULT_PORT + 1)
            print(f"[*] Re-routing to available port: {port}")

        print(f"[*] Starting Walkman Studio FastAPI engine on http://{HOST}:{port} ...")
        t = threading.Thread(target=start_backend, args=(port,), daemon=True)
        t.start()

        if not wait_for_server(port, timeout=10.0):
            print("[-] Error: Backend server timed out on startup.")
            sys.exit(1)
        print(f"[+] Engine online on port {port}.")

    app_url = f"http://{HOST}:{port}/"

    # 2. Check if pywebview is available and can launch GUI
    use_gui = True
    if os.environ.get("HEADLESS") == "1" or (not os.environ.get("DISPLAY") and sys.platform.startswith("linux")):
        use_gui = False

    if use_gui:
        try:
            import webview

            print("[*] Launching native macOS desktop window (pywebview WKWebView)...")
            window = webview.create_window(
                title="Sony Walkman Studio",
                url=app_url,
                width=1240,
                height=820,
                min_size=(1024, 700),
                background_color="#0A0A0C",
            )
            webview.start(debug=True)
            print("[*] Walkman Studio window closed. Goodbye.")
            return
        except Exception as e:
            print(f"[!] Native desktop window error: {e}")
            print("[*] Falling back to system default web browser...")

    # 3. Fallback: Open in default browser
    print(f"[+] Opening Walkman Studio in default browser: {app_url}")
    webbrowser.open(app_url)
    print("[*] Press Ctrl+C to stop the server.")
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\n[*] Exiting Walkman Studio.")


if __name__ == "__main__":
    main()
