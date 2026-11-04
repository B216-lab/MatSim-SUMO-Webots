import queue
import threading
from pathlib import Path

from django.conf import settings

from pipeline.mocks import Mocks
from pipeline.storage import Storage

_pipeline = None
_pipeline_lock = threading.Lock()


class Pipeline:
    def __init__(self, root: Path, mocks: Mocks | None = None):
        self.storage = Storage(root)
        self.mocks = mocks or Mocks()
        self.matsim_queue: queue.PriorityQueue = queue.PriorityQueue()
        self.sumo_queue: queue.PriorityQueue = queue.PriorityQueue()
        self.webots_queue: queue.PriorityQueue = queue.PriorityQueue()
        self.zip_queue: queue.PriorityQueue = queue.PriorityQueue()
        self.matsim_current_request_timestamp = None
        self.matsim_current_team_dir = None
        self.sumo_current_request_timestamp = None
        self.sumo_current_team_dir = None
        self.webots_current_request_timestamp = None
        self.webots_current_team_dir = None
        self._stop = threading.Event()
        self._threads: list[threading.Thread] = []

    def start(self) -> None:
        if self._threads:
            return
        targets = (
            ("matsim", self._run_matsim),
            ("sumo", self._run_sumo),
            ("webots", self._run_webots),
            ("zip", self._run_zip),
        )
        for name, target in targets:
            thread = threading.Thread(target=target, name=f"pipeline-{name}", daemon=True)
            thread.start()
            self._threads.append(thread)

    def stop(self) -> None:
        self._stop.set()
        for thread in self._threads:
            thread.join(timeout=2)
        self._threads.clear()

    def enqueue_matsim(self, request_timestamp: str, team_dir: str) -> None:
        self.matsim_queue.put((request_timestamp, team_dir))

    def _take(self, jobs: queue.PriorityQueue):
        try:
            return jobs.get(timeout=0.05)
        except queue.Empty:
            return None

    def _run_matsim(self) -> None:
        while not self._stop.is_set():
            item = self._take(self.matsim_queue)
            if item is None:
                continue
            request_timestamp, team_dir = item
            self.matsim_current_request_timestamp = request_timestamp
            self.matsim_current_team_dir = team_dir
            try:
                run_dir = self.storage.run_dir(team_dir, request_timestamp)
                try:
                    self.mocks.matsim(run_dir, team_dir)
                except Exception:
                    self.zip_queue.put((request_timestamp, team_dir))
                else:
                    self.sumo_queue.put((request_timestamp, team_dir))
            finally:
                self.matsim_current_request_timestamp = None
                self.matsim_current_team_dir = None
                self.matsim_queue.task_done()

    def _run_sumo(self) -> None:
        while not self._stop.is_set():
            item = self._take(self.sumo_queue)
            if item is None:
                continue
            request_timestamp, team_dir = item
            self.sumo_current_request_timestamp = request_timestamp
            self.sumo_current_team_dir = team_dir
            try:
                run_dir = self.storage.run_dir(team_dir, request_timestamp)
                try:
                    self.mocks.sumo(run_dir, team_dir)
                except Exception:
                    self.zip_queue.put((request_timestamp, team_dir))
                else:
                    self.webots_queue.put((request_timestamp, team_dir))
            finally:
                self.sumo_current_request_timestamp = None
                self.sumo_current_team_dir = None
                self.sumo_queue.task_done()

    def _run_webots(self) -> None:
        while not self._stop.is_set():
            item = self._take(self.webots_queue)
            if item is None:
                continue
            request_timestamp, team_dir = item
            self.webots_current_request_timestamp = request_timestamp
            self.webots_current_team_dir = team_dir
            try:
                run_dir = self.storage.run_dir(team_dir, request_timestamp)
                try:
                    self.mocks.webots(run_dir, team_dir)
                except Exception:
                    pass
                self.zip_queue.put((request_timestamp, team_dir))
            finally:
                self.webots_current_request_timestamp = None
                self.webots_current_team_dir = None
                self.webots_queue.task_done()

    def _run_zip(self) -> None:
        while not self._stop.is_set():
            item = self._take(self.zip_queue)
            if item is None:
                continue
            request_timestamp, team_dir = item
            try:
                self.storage.make_result_zip(team_dir, request_timestamp)
            finally:
                self.zip_queue.task_done()


def get_pipeline() -> Pipeline:
    global _pipeline
    if _pipeline is None:
        with _pipeline_lock:
            if _pipeline is None:
                pipeline = Pipeline(settings.DATA_ROOT)
                pipeline.start()
                _pipeline = pipeline
    return _pipeline


def set_pipeline(pipeline: Pipeline | None) -> None:
    global _pipeline
    _pipeline = pipeline
