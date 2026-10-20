"""
Integration tests for FastAPI endpoints in backend/main.py.
"""

import tempfile
from pathlib import Path
from fastapi.testclient import TestClient
from backend.main import app

client = TestClient(app)


def test_api_drives():
    res = client.get("/api/drives?allow_virtual=true")
    assert res.status_code == 200
    data = res.json()
    assert "drives" in data
    assert len(data["drives"]) >= 1


def test_api_library_and_playlists():
    with tempfile.TemporaryDirectory() as tmp_dir:
        mount = Path(tmp_dir)
        music_dir = mount / "MUSIC"
        music_dir.mkdir()

        # 1. Test get library on empty drive
        res = client.get(f"/api/library?mount_point={mount}")
        assert res.status_code == 200
        lib = res.json()
        assert lib["total_tracks"] == 0

        # 2. Test create playlist
        pl_data = {
            "mount_point": str(mount),
            "playlist_name": "My Heavy Rotation",
            "relative_tracks": ["Artist/Album/01 - Song.flac", "Artist/Album/02 - Song2.flac"],
        }
        res_pl = client.post("/api/playlists", json=pl_data)
        assert res_pl.status_code == 200
        assert res_pl.json()["tracks"] == 2

        # 3. Test list playlists
        res_list = client.get(f"/api/playlists?mount_point={mount}")
        assert res_list.status_code == 200
        pls = res_list.json()["playlists"]
        assert len(pls) == 1
        assert pls[0]["filename"] == "My Heavy Rotation.m3u8"
        assert len(pls[0]["tracks"]) == 2

        # 4. Test clean-eject endpoint
        res_clean = client.post("/api/clean-eject", json={"mount_point": str(mount)})
        assert res_clean.status_code == 200
        assert res_clean.json()["status"] == "ok"
