"""Tiny in-memory URL shortener used as the AI-Craftman demo/eval target."""
import hashlib


class Shortener:
    def __init__(self):
        self._links = {}

    def shorten(self, url: str) -> str:
        if not url.startswith(("http://", "https://")):
            raise ValueError("url must start with http:// or https://")
        code = hashlib.sha256(url.encode()).hexdigest()[:7]
        self._links[code] = url
        return code

    def resolve(self, code: str) -> str:
        if code not in self._links:
            raise KeyError(code)
        return self._links[code]
