import json
import os
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

APP_DIR = Path(__file__).resolve().parents[2]


def test_health_over_real_http(tmp_path: Path) -> None:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]

    env = os.environ.copy()
    env["DATABASE_URL"] = f"sqlite+aiosqlite:///{tmp_path / 'e2e.db'}"
    url = f"http://127.0.0.1:{port}/health"
    process = subprocess.Popen(
        [
            sys.executable,
            "-m",
            "uvicorn",
            "app.main:app",
            "--host",
            "127.0.0.1",
            "--port",
            str(port),
        ],
        cwd=APP_DIR,
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        body = None
        for _ in range(100):
            if process.poll() is not None:
                raise AssertionError("uvicorn exited before accepting requests")
            try:
                with urllib.request.urlopen(url, timeout=0.2) as response:
                    body = json.loads(response.read())
                break
            except (urllib.error.URLError, TimeoutError):
                time.sleep(0.1)
        assert body is not None, "server did not become ready"
        assert body["status"] == "ok"
        assert body["database"] == "ok"
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
