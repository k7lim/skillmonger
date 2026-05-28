import json
import os
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


SKILL_DIR = Path(__file__).resolve().parents[1]
CLI = SKILL_DIR / "scripts" / "sm-video"
PREREQS = SKILL_DIR / "scripts" / "check-prereqs.sh"
RAW_FIXTURES = SKILL_DIR / "fixtures" / "raw"


def run_cli(*args, env=None):
    command_env = os.environ.copy()
    if env:
        command_env.update(env)
    return subprocess.run([str(CLI), *args], text=True, capture_output=True, env=command_env)


def run_cli_with_fake_ytdlp(*args, fixture="youtube_comments.info.json", stdout=None, stderr="", returncode=0, extra_env=None):
    with tempfile.TemporaryDirectory() as tempdir:
        fake = Path(tempdir) / "yt-dlp"
        fake.write_text(textwrap.dedent(
            """\
            #!/usr/bin/env python3
            import os
            import sys
            from pathlib import Path

            args = sys.argv[1:]
            required = [
                "--ignore-config",
                "--no-cache-dir",
                "--skip-download",
                "--dump-single-json",
                "--write-comments",
                "--extractor-args",
                "--no-playlist",
            ]
            missing = [item for item in required if item not in args]
            expected_sort = os.environ.get("SM_VIDEO_EXPECT_SORT")
            expected_max = os.environ.get("SM_VIDEO_EXPECT_MAX_COMMENTS")
            extractor_args = args[args.index("--extractor-args") + 1] if "--extractor-args" in args else ""
            if missing or (expected_sort and f"comment_sort={expected_sort}" not in extractor_args) or (expected_max and f"max_comments={expected_max}" not in extractor_args):
                sys.stderr.write(f"unexpected args: {args}\\n")
                sys.exit(9)

            if int(os.environ.get("SM_VIDEO_FAKE_RETURNCODE", "0")):
                sys.stderr.write(os.environ.get("SM_VIDEO_FAKE_STDERR", "fake yt-dlp failure"))
                sys.exit(int(os.environ["SM_VIDEO_FAKE_RETURNCODE"]))

            if "SM_VIDEO_FAKE_STDOUT" in os.environ:
                sys.stdout.write(os.environ["SM_VIDEO_FAKE_STDOUT"])
            else:
                sys.stdout.write(Path(os.environ["SM_VIDEO_FAKE_FIXTURE"]).read_text(encoding="utf-8"))
            """
        ), encoding="utf-8")
        fake.chmod(0o755)
        env = {
            "PATH": f"{tempdir}{os.pathsep}{os.environ.get('PATH', '')}",
            "SM_VIDEO_FAKE_FIXTURE": str(RAW_FIXTURES / fixture),
            "SM_VIDEO_FAKE_RETURNCODE": str(returncode),
            "SM_VIDEO_FAKE_STDERR": stderr,
        }
        if stdout is not None:
            env["SM_VIDEO_FAKE_STDOUT"] = stdout
        if extra_env:
            env.update(extra_env)
        return run_cli(*args, env=env)


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

    def test_comments_describe_returns_sensor_metadata(self):
        result = run_cli("comments", "--describe")
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)

        self.assertEqual(payload["name"], "comments")
        self.assertEqual(payload["kind"], "sensor")
        self.assertFalse(payload["side_effecting"])
        options = {item["name"]: item for item in payload["options"]}
        self.assertEqual(options["sort"]["choices"], ["top", "new"])
        fields = {item["name"] for item in payload["output_fields"]}
        self.assertEqual(fields, {"id", "parent", "author", "author_id", "text", "timestamp", "like_count", "is_pinned", "author_is_uploader", "url"})

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

    def test_comments_normalizes_youtube_fixture_with_limit_offset_and_top_sort(self):
        result = run_cli_with_fake_ytdlp(
            "comments",
            "--url", "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            "--limit", "2",
            "--offset", "1",
            "--sort", "top",
            extra_env={"SM_VIDEO_EXPECT_SORT": "top", "SM_VIDEO_EXPECT_MAX_COMMENTS": "3"},
        )
        payload = json.loads(result.stdout)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_envelope(payload)
        self.assertTrue(payload["success"])
        self.assertEqual(payload["meta"]["provider"], "youtube")
        self.assertEqual(payload["meta"]["source"], "yt-dlp")
        self.assertEqual(payload["meta"]["sort"], "top")
        self.assertEqual([item["id"] for item in payload["data"]], ["youtube-comment-2", "youtube-comment-3"])
        self.assertNotIn("provider", payload["data"][0])
        self.assertEqual(set(payload["data"][0]), {"id", "parent", "author", "author_id", "text", "timestamp", "like_count", "is_pinned", "author_is_uploader", "url"})
        self.assertIsNone(payload["data"][0]["url"])

    def test_comments_new_sort_and_query_are_applied_after_normalization(self):
        result = run_cli_with_fake_ytdlp(
            "comments",
            "--url", "https://youtu.be/dQw4w9WgXcQ",
            "--limit", "1",
            "--sort", "new",
            "--query", "COMMENT 4",
            extra_env={"SM_VIDEO_EXPECT_SORT": "new", "SM_VIDEO_EXPECT_MAX_COMMENTS": "500"},
        )
        payload = json.loads(result.stdout)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(payload["success"])
        self.assertEqual(payload["meta"]["query"], "COMMENT 4")
        self.assertEqual([item["id"] for item in payload["data"]], ["youtube-comment-4"])

    def test_comments_fields_filter_comment_objects_only(self):
        result = run_cli_with_fake_ytdlp(
            "comments",
            "--url", "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            "--limit", "1",
            "--fields", "id,text,like_count",
        )
        payload = json.loads(result.stdout)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(payload["data"], [{"id": "youtube-comment-1", "text": "redacted youtube comment 1", "like_count": 246000}])
        self.assertEqual(payload["meta"]["provider"], "youtube")

    def test_comments_rejects_non_youtube_provider_and_generic_url(self):
        provider = run_cli("comments", "--provider", "bilibili", "--url", "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
        provider_payload = json.loads(provider.stdout)
        self.assertEqual(provider.returncode, 2)
        self.assertEqual(provider_payload["meta"]["error"]["code"], "unsupported_provider")

        generic = run_cli("comments", "--url", "https://example.com/video")
        generic_payload = json.loads(generic.stdout)
        self.assertEqual(generic.returncode, 2)
        self.assertEqual(generic_payload["meta"]["error"]["code"], "unsupported_url")

    def test_comments_rejects_malformed_url_and_invalid_field(self):
        malformed = run_cli("comments", "--url", "not-a-url")
        malformed_payload = json.loads(malformed.stdout)
        self.assertEqual(malformed.returncode, 2)
        self.assertEqual(malformed_payload["meta"]["error"]["code"], "malformed_url")

        missing_video = run_cli("comments", "--url", "https://www.youtube.com/")
        missing_video_payload = json.loads(missing_video.stdout)
        self.assertEqual(missing_video.returncode, 2)
        self.assertEqual(missing_video_payload["meta"]["error"]["code"], "malformed_url")

        invalid_field = run_cli("comments", "--url", "https://www.youtube.com/watch?v=dQw4w9WgXcQ", "--fields", "id,provider")
        invalid_field_payload = json.loads(invalid_field.stdout)
        self.assertEqual(invalid_field.returncode, 2)
        self.assertEqual(invalid_field_payload["meta"]["error"]["code"], "invalid_field")

    def test_comments_surfaces_yt_dlp_and_malformed_source_failures(self):
        failed = run_cli_with_fake_ytdlp(
            "comments",
            "--url", "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            returncode=17,
            stderr="ERROR: youtube said no",
        )
        failed_payload = json.loads(failed.stdout)
        self.assertEqual(failed.returncode, 2)
        self.assertEqual(failed_payload["meta"]["error"]["code"], "yt_dlp_failed")
        self.assertIn("youtube said no", failed_payload["meta"]["error"]["message"])

        malformed = run_cli_with_fake_ytdlp(
            "comments",
            "--url", "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            stdout='{"comments": {}}',
        )
        malformed_payload = json.loads(malformed.stdout)
        self.assertEqual(malformed.returncode, 2)
        self.assertEqual(malformed_payload["meta"]["error"]["code"], "malformed_source_data")

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
