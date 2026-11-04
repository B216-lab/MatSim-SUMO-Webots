import threading
from pathlib import Path


class SimulatorError(RuntimeError):
    pass


class Mocks:
    """Stand-ins for the single MatSim, SUMO and Webots containers."""

    def __init__(self):
        self.fail_step: dict[str, str] = {}
        self.matsim_seen: list[str] = []
        self.sumo_seen: list[str] = []
        self.webots_seen: list[str] = []
        self.matsim_started = threading.Event()
        self.matsim_gate = threading.Event()
        self.matsim_gate.set()

    def matsim(self, run_dir: Path, team_dir: str) -> None:
        osm = _read_named(run_dir, ".osm")
        self.matsim_seen.append(team_dir)
        self.matsim_started.set()
        if not self.matsim_gate.wait(timeout=5):
            raise SimulatorError("matsim gate timed out")
        _fail_if_requested(self, team_dir, "matsim")
        (run_dir / "matsim.mp4").write_bytes(b"matsim-mp4\n" + osm)
        (run_dir / "plans.xml").write_text("<plans/>", encoding="utf-8")

    def sumo(self, run_dir: Path, team_dir: str) -> None:
        _read_named(run_dir, ".osm")
        (run_dir / "plans.xml").read_bytes()
        self.sumo_seen.append(team_dir)
        _fail_if_requested(self, team_dir, "sumo")
        (run_dir / "sumo.mp4").write_bytes(b"sumo-mp4\n")
        (run_dir / "objects.xml").write_text("<objects/>", encoding="utf-8")

    def webots(self, run_dir: Path, team_dir: str) -> None:
        _read_named(run_dir, ".osm")
        (run_dir / "objects.xml").read_bytes()
        self.webots_seen.append(team_dir)
        _fail_if_requested(self, team_dir, "webots")
        (run_dir / "webots.mp4").write_bytes(b"webots-mp4\n")


def _fail_if_requested(mocks: Mocks, team_dir: str, step: str) -> None:
    if mocks.fail_step.get(team_dir) == step:
        raise SimulatorError(f"{step} failed")


def _read_named(run_dir: Path, suffix: str) -> bytes:
    matches = [path for path in run_dir.iterdir() if path.is_file() and path.name.endswith(suffix)]
    if not matches:
        raise SimulatorError(f"missing {suffix}")
    return matches[0].read_bytes()
