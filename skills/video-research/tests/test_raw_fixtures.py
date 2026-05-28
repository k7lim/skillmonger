import json
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path


FIXTURE_DIR = Path(__file__).resolve().parents[1] / "fixtures" / "raw"


def load_json(name):
    with (FIXTURE_DIR / name).open(encoding="utf-8") as handle:
        return json.load(handle)


class RawFixtureTests(unittest.TestCase):
    def test_manifest_covers_expected_characterization_fixtures(self):
        manifest = load_json("manifest.json")
        entries = manifest["entries"]
        purposes = {(entry["provider"], entry["purpose"]) for entry in entries}

        self.assertEqual(manifest["yt_dlp_version"], "2026.03.17")
        self.assertIn(("youtube", "metadata"), purposes)
        self.assertIn(("youtube", "comments"), purposes)
        self.assertIn(("bilibili", "metadata"), purposes)
        self.assertIn(("bilibili", "timed-text-danmaku"), purposes)

        for entry in entries:
            path = FIXTURE_DIR / entry["file"]
            self.assertTrue(path.exists(), entry["file"])
            self.assertLess(path.stat().st_size, 50_000, entry["file"])
            self.assertIn("yt-dlp ", entry["collection_command"])
            self.assertNotIn("python3 -m yt_dlp", entry["collection_command"])
            self.assertTrue(entry["public_source_url"].startswith("https://"))
            self.assertEqual(entry["collection_date"], manifest["collection_date"])
            self.assertIn("known_missing_fields", entry)
            self.assertIn("volatility_notes", entry)

    def test_youtube_metadata_fixture_has_video_result_inputs(self):
        data = load_json("youtube_metadata.info.json")

        self.assertEqual(data["extractor"], "youtube")
        self.assertEqual(data["extractor_key"], "Youtube")
        self.assertEqual(data["id"], "dQw4w9WgXcQ")
        self.assertEqual(data["webpage_url"], "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
        for field in ("title", "uploader", "uploader_id", "thumbnail", "upload_date"):
            self.assertIsInstance(data[field], str)
            self.assertTrue(data[field])
        for field in ("duration", "view_count", "like_count", "comment_count"):
            self.assertIsInstance(data[field], int)
            self.assertGreater(data[field], 0)

        self.assertIn("en", data["subtitles"])
        self.assertTrue(any(item["ext"] == "vtt" for item in data["subtitles"]["en"]))
        self.assertNotIn("formats", data)
        self.assertFalse(any("url" in item for item in data["subtitles"]["en"]))

    def test_youtube_comments_fixture_has_comment_inputs_and_known_url_gap(self):
        data = load_json("youtube_comments.info.json")
        comments = data["comments"]

        self.assertEqual(data["extractor"], "youtube")
        self.assertGreaterEqual(len(comments), 3)
        first = comments[0]
        for field in ("id", "parent", "author", "author_id", "text", "timestamp", "like_count"):
            self.assertIn(field, first)
        self.assertEqual(first["parent"], "root")
        self.assertIsInstance(first["is_pinned"], bool)
        self.assertIsInstance(first["author_is_uploader"], bool)
        self.assertTrue(first["text"].startswith("redacted youtube comment "))
        self.assertNotIn("author_thumbnail", first)
        self.assertNotIn("url", first)

        manifest = load_json("manifest.json")
        entry = next(item for item in manifest["entries"] if item["file"] == "youtube_comments.info.json")
        self.assertIn("comments[].url", entry["known_missing_fields"])

    def test_bilibili_metadata_fixture_has_video_result_inputs_and_subtitle_limitation(self):
        data = load_json("bilibili_metadata.info.json")

        self.assertEqual(data["extractor"], "BiliBili")
        self.assertEqual(data["extractor_key"], "BiliBili")
        self.assertEqual(data["webpage_url"], "https://www.bilibili.com/video/BV1np4y1e7oN/")
        for field in ("id", "display_id", "title", "uploader", "uploader_id", "thumbnail", "upload_date"):
            self.assertIsInstance(data[field], str)
            self.assertTrue(data[field])
        for field in ("duration", "view_count", "like_count", "comment_count"):
            self.assertIsInstance(data[field], (int, float))
            self.assertGreater(data[field], 0)

        self.assertEqual(data["subtitles"], {})
        manifest = load_json("manifest.json")
        entry = next(item for item in manifest["entries"] if item["file"] == "bilibili_metadata.info.json")
        self.assertIn("subtitles regular caption entries", entry["known_missing_fields"])

    def test_bilibili_danmaku_fixture_has_timed_text_inputs(self):
        root = ET.parse(FIXTURE_DIR / "bilibili_danmaku.xml").getroot()
        entries = root.findall("d")

        self.assertEqual(root.tag, "i")
        self.assertEqual(root.findtext("chatid"), "233166672")
        self.assertGreaterEqual(len(entries), 3)
        for item in entries:
            parts = item.attrib["p"].split(",")
            self.assertGreaterEqual(len(parts), 8)
            self.assertGreaterEqual(float(parts[0]), 0)
            self.assertTrue(item.text.startswith("redacted danmaku "))

        manifest = load_json("manifest.json")
        entry = next(item for item in manifest["entries"] if item["file"] == "bilibili_danmaku.xml")
        self.assertIn("language", entry["known_missing_fields"])


if __name__ == "__main__":
    unittest.main()
