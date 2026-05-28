import json
import subprocess
import unittest
from pathlib import Path


SKILL_DIR = Path(__file__).resolve().parents[1]
CLI = SKILL_DIR / "scripts" / "sm-video"
PREREQS = SKILL_DIR / "scripts" / "check-prereqs.sh"


def run_cli(*args):
    return subprocess.run([str(CLI), *args], text=True, capture_output=True)


class SmVideoContractTests(unittest.TestCase):
    def assert_envelope(self, payload):
        self.assertIn("success", payload)
        self.assertIn("data", payload)
        self.assertIn("meta", payload)
        self.assertIn("schema_version", payload["meta"])

    def test_describe_lists_sensors_and_actuators(self):
        result = run_cli("--describe")
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual({item["name"] for item in payload["sensors"]}, {"search", "probe", "transcript", "comments", "sites"})
        self.assertEqual({item["name"] for item in payload["actuators"]}, {"download", "clip", "explore"})
        for item in payload["actuators"]:
            self.assertTrue(item["side_effecting"])
            self.assertTrue(item["requires_dry_run_before_execution"])

    def test_valid_command_returns_not_implemented_envelope(self):
        result = run_cli("search", "--provider", "youtube", "--query", "dune", "--limit", "3")
        payload = json.loads(result.stdout)
        self.assertEqual(result.returncode, 1)
        self.assert_envelope(payload)
        self.assertFalse(payload["success"])
        self.assertEqual(payload["meta"]["error"]["code"], "not_implemented")
        self.assertEqual(payload["meta"]["provider"], "youtube")

    def test_unknown_fields_fail_invalid_field(self):
        result = run_cli("probe", "--url", "https://example.com/video", "--fields", "id,nope")
        payload = json.loads(result.stdout)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(payload["meta"]["error"]["code"], "invalid_field")

    def test_invalid_provider_fails_boundary_validation(self):
        result = run_cli("search", "--provider", "vimeo", "--query", "topic")
        payload = json.loads(result.stdout)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(payload["meta"]["error"]["code"], "invalid_provider")

    def test_control_characters_are_rejected(self):
        result = run_cli("search", "--query", "bad\nquery")
        payload = json.loads(result.stdout)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(payload["meta"]["error"]["code"], "invalid_input")

    def test_command_specific_enums_are_rejected(self):
        transcript = run_cli("transcript", "--url", "https://example.com/video", "--prefer", "machine")
        transcript_payload = json.loads(transcript.stdout)
        self.assertEqual(transcript.returncode, 2)
        self.assertEqual(transcript_payload["meta"]["error"]["code"], "invalid_argument")

        comments = run_cli("comments", "--url", "https://example.com/video", "--sort", "loudest")
        comments_payload = json.loads(comments.stdout)
        self.assertEqual(comments.returncode, 2)
        self.assertEqual(comments_payload["meta"]["error"]["code"], "invalid_argument")

    def test_actuator_requires_dry_run_and_sandboxed_paths(self):
        missing_dry_run = run_cli("download", "--url", "https://example.com/video", "--output-dir", "downloads")
        missing_payload = json.loads(missing_dry_run.stdout)
        self.assertEqual(missing_payload["meta"]["error"]["code"], "dry_run_required")

        absolute = run_cli("download", "--url", "https://example.com/video", "--output-dir", "/tmp/out", "--dry-run")
        absolute_payload = json.loads(absolute.stdout)
        self.assertEqual(absolute_payload["meta"]["error"]["code"], "invalid_output_path")

        traversal = run_cli("explore", "--url", "https://example.com/video", "--output", "../explore.html", "--dry-run")
        traversal_payload = json.loads(traversal.stdout)
        self.assertEqual(traversal_payload["meta"]["error"]["code"], "invalid_output_path")

    def test_check_prereqs_uses_skill_script_interface_not_envelope(self):
        result = subprocess.run([str(PREREQS)], text=True, capture_output=True)
        self.assertEqual(result.returncode, 0)
        payload = json.loads(result.stdout)
        self.assertIn("ready", payload)
        self.assertIn("checks", payload)
        self.assertIn("context", payload)
        self.assertNotIn("success", payload)
        checks = {item["name"]: item for item in payload["checks"]}
        self.assertTrue(checks["yt-dlp"]["required"])
        self.assertFalse(checks["ffmpeg"]["required"])
        self.assertIn("clip", checks["ffmpeg"]["required_for"])


if __name__ == "__main__":
    unittest.main()
