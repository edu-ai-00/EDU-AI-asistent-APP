"""Read and rewrite the leaf strings of a Laravel lang file.

Only the array literal matters, so the file is scanned rather than executed:
`parse()` returns {dotted.key: (text, span)} and `apply()` replaces single
values in place, leaving comments, order and formatting untouched.
"""

from __future__ import annotations

import re

from dart_strings import literal_at


def _unescape(raw: str) -> str:
    body = raw[1:-1]
    if raw[0] == "'":                      # single quotes: only \' and \\
        return body.replace("\\'", "'").replace('\\\\', '\\')
    return re.sub(r'\\(.)', lambda m: {'n': '\n', 't': '\t'}.get(m.group(1), m.group(1)), body)


def _escape(text: str) -> str:
    return "'" + text.replace('\\', '\\\\').replace("'", "\\'") + "'"


def parse(src: str) -> dict:
    out, stack, pending, i = {}, [], None, 0
    while i < len(src):
        if src.startswith('//', i) or src.startswith('#', i):
            nl = src.find('\n', i)
            i = len(src) if nl < 0 else nl
            continue
        if src.startswith('/*', i):
            end = src.find('*/', i)
            i = len(src) if end < 0 else end + 2
            continue
        ch = src[i]
        if ch in '\'"':
            raw, span = literal_at(src, i)
            text = _unescape(raw)
            after = src[span[1]:span[1] + 40].lstrip()
            if after.startswith('=>'):
                pending = text
            elif pending is not None:
                out['.'.join(stack + [pending])] = (text, span)
                pending = None
            else:
                out['.'.join(stack + [text])] = (text, span)
            i = span[1]
            continue
        if ch == '[':
            if pending is not None:
                stack.append(pending)
                pending = None
            i += 1
            continue
        if ch == ']':
            if stack:
                stack.pop()
            i += 1
            continue
        i += 1
    return out


def apply(src: str, edits: dict) -> tuple[str, list]:
    """edits: {dotted.key: new_text}."""
    entries = parse(src)
    patches, log = [], []
    for key, new in edits.items():
        if key not in entries:
            raise KeyError(f'klíč {key} v souboru není')
        old, span = entries[key]
        if new == old:
            continue
        patches.append((span, _escape(new)))
        log.append((key, old, new))
    for (start, end), text in sorted(patches, key=lambda p: -p[0][0]):
        src = src[:start] + text + src[end:]
    return src, log
