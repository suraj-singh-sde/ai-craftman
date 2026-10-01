import unittest

from shortener import Shortener


class ShortenerTest(unittest.TestCase):
    def test_round_trip(self):
        s = Shortener()
        self.assertEqual(s.resolve(s.shorten("https://example.com")), "https://example.com")

    def test_rejects_non_http(self):
        with self.assertRaises(ValueError):
            Shortener().shorten("ftp://example.com")

    def test_unknown_code(self):
        with self.assertRaises(KeyError):
            Shortener().resolve("nope")


if __name__ == "__main__":
    unittest.main()
