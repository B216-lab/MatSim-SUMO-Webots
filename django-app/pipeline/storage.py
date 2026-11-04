import re
import zipfile
from datetime import datetime, timezone
from pathlib import Path

_TEAM_RE = re.compile(r"^[A-Za-z0-9_-]+$")


def team_dir_from_filename(filename: str) -> str:
    base = Path(filename).name
    if not base.lower().endswith(".osm"):
        raise ValueError("expected a .osm file")
    team = base[: -len(".osm")]
    if not _TEAM_RE.fullmatch(team):
        raise ValueError("invalid team name")
    return team


def validate_team_dir(team: str) -> str:
    if not _TEAM_RE.fullmatch(team or ""):
        raise ValueError("invalid team_dir")
    return team


def new_request_timestamp() -> str:
    now = datetime.now(timezone.utc)
    return now.strftime("%Y%m%d-%H%M%S-") + f"{now.microsecond:06d}"


class Storage:
    def __init__(self, root: Path):
        self.root = Path(root)
        self.root.mkdir(parents=True, exist_ok=True)

    def run_dir(self, team: str, request_timestamp: str) -> Path:
        return self.root / team / request_timestamp

    def team_path(self, team: str) -> Path:
        return self.root / team

    def save_osm(self, team: str, request_timestamp: str, filename: str, content: bytes) -> Path:
        folder = self.run_dir(team, request_timestamp)
        folder.mkdir(parents=True, exist_ok=True)
        dest = folder / Path(filename).name
        dest.write_bytes(content)
        return dest

    def make_result_zip(self, team: str, request_timestamp: str) -> Path:
        folder = self.team_path(team)
        folder.mkdir(parents=True, exist_ok=True)
        run = self.run_dir(team, request_timestamp)
        n = sum(1 for path in folder.glob("*.zip") if path.is_file())
        target = folder / f"result{n}.zip"
        with zipfile.ZipFile(target, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for path in sorted(item for item in run.iterdir() if item.is_file()):
                archive.write(path, arcname=path.name)
        return target

    def latest_zip(self, team: str) -> Path | None:
        folder = self.team_path(team)
        if not folder.is_dir():
            return None
        names = sorted(path.name for path in folder.glob("*.zip") if path.is_file())
        if not names:
            return None
        return folder / names[-1]
