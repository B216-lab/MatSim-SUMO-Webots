import tempfile
import time
import zipfile
from pathlib import Path

from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import SimpleTestCase

from pipeline.queues import Pipeline, set_pipeline


class PipelineHttpTests(SimpleTestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.pipeline = Pipeline(self.root)
        self.pipeline.start()
        set_pipeline(self.pipeline)

    def tearDown(self):
        self.pipeline.mocks.matsim_gate.set()
        self.pipeline.stop()
        set_pipeline(None)
        self.tmp.cleanup()

    def post_osm(self, name: str, content: bytes = b"<osm/>"):
        upload = SimpleUploadedFile(name, content, content_type="application/xml")
        return self.client.post("/", {"file": upload})

    def wait_zip(self, team: str, timeout: float = 5) -> Path:
        deadline = time.time() + timeout
        folder = self.root / team
        while time.time() < deadline:
            if folder.is_dir():
                zips = sorted(path for path in folder.glob("*.zip") if path.is_file())
                if zips:
                    return zips[-1]
            time.sleep(0.02)
        raise AssertionError(f"no zip for {team}")

    def zip_names(self, team: str, archive: Path) -> set[str]:
        with zipfile.ZipFile(archive) as handle:
            return set(handle.namelist())

    def test_all_steps_pass_and_get_returns_zip(self):
        response = self.post_osm("team1.osm", b"<osm>full</osm>")
        self.assertEqual(response.status_code, 200)
        archive = self.wait_zip("team1")
        self.assertEqual(archive.name, "result0.zip")
        names = self.zip_names("team1", archive)
        self.assertEqual(
            names,
            {"team1.osm", "matsim.mp4", "plans.xml", "sumo.mp4", "objects.xml", "webots.mp4"},
        )
        fetched = self.client.get("/", {"team_dir": "team1"})
        self.assertEqual(fetched.status_code, 200)
        self.assertIn("result0.zip", fetched["Content-Disposition"])

    def test_matsim_failure_skips_sumo_and_webots(self):
        self.pipeline.mocks.fail_step["broken"] = "matsim"
        response = self.post_osm("broken.osm")
        self.assertEqual(response.status_code, 200)
        archive = self.wait_zip("broken")
        names = self.zip_names("broken", archive)
        self.assertEqual(names, {"broken.osm"})
        self.assertEqual(self.pipeline.mocks.sumo_seen, [])
        self.assertEqual(self.pipeline.mocks.webots_seen, [])
        self.assertTrue(self.pipeline.sumo_queue.empty())
        self.assertTrue(self.pipeline.webots_queue.empty())

    def test_sumo_failure_keeps_matsim_output(self):
        self.pipeline.mocks.fail_step["sumofail"] = "sumo"
        self.post_osm("sumofail.osm")
        archive = self.wait_zip("sumofail")
        names = self.zip_names("sumofail", archive)
        self.assertEqual(names, {"sumofail.osm", "matsim.mp4", "plans.xml"})
        self.assertEqual(self.pipeline.mocks.webots_seen, [])
        self.assertTrue(self.pipeline.webots_queue.empty())

    def test_webots_failure_still_zips(self):
        self.pipeline.mocks.fail_step["webfail"] = "webots"
        self.post_osm("webfail.osm")
        archive = self.wait_zip("webfail")
        names = self.zip_names("webfail", archive)
        self.assertEqual(
            names,
            {"webfail.osm", "matsim.mp4", "plans.xml", "sumo.mp4", "objects.xml"},
        )
        self.assertNotIn("webots.mp4", names)

    def test_second_run_returns_latest_sorted_zip(self):
        self.post_osm("repeat.osm", b"<osm>1</osm>")
        self.wait_zip("repeat")
        self.post_osm("repeat.osm", b"<osm>2</osm>")
        deadline = time.time() + 5
        latest = None
        while time.time() < deadline:
            zips = sorted(path.name for path in (self.root / "repeat").glob("*.zip"))
            if zips and zips[-1] == "result1.zip":
                latest = zips[-1]
                break
            time.sleep(0.02)
        self.assertEqual(latest, "result1.zip")
        fetched = self.client.get("/", {"team_dir": "repeat"})
        self.assertEqual(fetched.status_code, 200)
        self.assertIn("result1.zip", fetched["Content-Disposition"])

    def test_get_without_zip_is_404(self):
        response = self.client.get("/", {"team_dir": "nobody"})
        self.assertEqual(response.status_code, 404)

    def test_post_returns_before_matsim_finishes(self):
        self.pipeline.mocks.matsim_gate.clear()
        self.pipeline.mocks.matsim_started.clear()
        response = self.post_osm("held.osm")
        self.assertEqual(response.status_code, 200)
        self.assertTrue(self.pipeline.mocks.matsim_started.wait(2))
        self.assertEqual(self.pipeline.matsim_current_team_dir, "held")
        self.assertFalse(list((self.root / "held").glob("*.zip")))
        self.pipeline.mocks.matsim_gate.set()
        self.wait_zip("held")

    def test_earlier_timestamp_enters_matsim_first(self):
        self.pipeline.stop()
        self.pipeline = Pipeline(self.root)
        set_pipeline(self.pipeline)
        self.pipeline.mocks.matsim_gate.clear()
        self.pipeline.storage.save_osm("later", "20000101-000000-000002", "later.osm", b"<osm/>")
        self.pipeline.storage.save_osm("earlier", "20000101-000000-000001", "earlier.osm", b"<osm/>")
        self.pipeline.enqueue_matsim("20000101-000000-000002", "later")
        self.pipeline.enqueue_matsim("20000101-000000-000001", "earlier")
        self.pipeline.start()
        self.assertTrue(self.pipeline.mocks.matsim_started.wait(2))
        time.sleep(0.15)
        self.assertEqual(self.pipeline.mocks.matsim_seen, ["earlier"])
        self.assertEqual(self.pipeline.matsim_current_team_dir, "earlier")
        self.pipeline.mocks.matsim_gate.set()
        self.wait_zip("earlier")
        self.wait_zip("later")
        self.assertEqual(self.pipeline.mocks.matsim_seen, ["earlier", "later"])

    def test_rejects_non_osm_upload(self):
        upload = SimpleUploadedFile("notes.txt", b"nope", content_type="text/plain")
        response = self.client.post("/", {"file": upload})
        self.assertEqual(response.status_code, 400)
