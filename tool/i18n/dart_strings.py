"""Parse and rewrite the user-facing strings in lib/core/strings/app_strings.dart.

The file holds three kinds of translatable text, each addressed by a stable ID
so an edited spreadsheet can be imported back:

  ui.<key>              an entry of the _cz / _sk / _en maps
  dyn.<fn>[#n]          a `_pick(cz:, sk:, en:)` call; #n only when one
                        function holds several calls
  plural.<fn>.<form>    one branch of a `switch (LocaleManager.current)`
                        plural helper; form is one|few|other

Every entry records the exact character span of each locale's literal (or run
of adjacent concatenated literals), which is what lets `apply()` rewrite one
value without touching anything else.

Strings whose value is assembled in code — adjacent literals around a
condition, or a `${cond ? 'a' : 'b'}` interpolation — are marked `locked`:
they are exported for reference but refused on import, because there is no
single literal to put the edited text into.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

LOCALES = ('cz', 'sk', 'en')
MAP_HEADER = "static const Map<String, String> _%s = {"

# Plural helpers return several literals per locale, in source order: Czech
# and Slovak branch three ways (1, 2-4, 5+), English two (1, other).
PLURAL_FORMS = {'cz': ('one', 'few', 'other'), 'sk': ('one', 'few', 'other'), 'en': ('one', 'other')}


@dataclass
class Entry:
    id: str
    kind: str                                     # 'ui' | 'dyn' | 'plural'
    name: str                                     # map key or function name
    values: dict = field(default_factory=dict)    # locale -> text
    spans: dict = field(default_factory=dict)     # locale -> (start, end)
    locked: dict = field(default_factory=dict)    # locale -> reason


def scan_literal(src: str, i: int):
    """End index of the Dart string literal starting at src[i].

    Interpolation-aware: `'a ${x == 1 ? 'b' : 'c'} d'` is one literal, not
    three. Raw strings (r'…') and triple quotes are not used in this file.
    """
    quote = src[i]
    i += 1
    while i < len(src):
        ch = src[i]
        if ch == '\\':
            i += 2
            continue
        if ch == quote:
            return i + 1
        if ch == '$' and i + 1 < len(src) and src[i + 1] == '{':
            depth, i = 0, i + 1
            while i < len(src):
                c = src[i]
                if c in '\'"':
                    i = scan_literal(src, i)
                    continue
                if c == '{':
                    depth += 1
                elif c == '}':
                    depth -= 1
                    if depth == 0:
                        i += 1
                        break
                i += 1
            continue
        i += 1
    raise ValueError(f'unterminated string literal at offset {i}')


def literal_at(src: str, i: int):
    end = scan_literal(src, i)
    return src[i:end], (i, end)


def _unescape(lit: str) -> str:
    body = lit[1:-1]
    return re.sub(r"\\(.)", lambda m: {'n': '\n', 't': '\t'}.get(m.group(1), m.group(1)), body)


def _escape(text: str) -> str:
    return "'" + text.replace('\\', '\\\\').replace("'", "\\'").replace('\n', '\\n') + "'"


def _nested_cond(lit: str) -> bool:
    return bool(re.search(r"\$\{[^}]*['\"]", lit))


def _literals(src: str, start: int, end: int):
    """Adjacent string literals in src[start:end] as (raw, span) pairs."""
    out, i = [], start
    while i < end:
        ch = src[i]
        if ch in '\'"':
            raw, span = literal_at(src, i)
            out.append((raw, span))
            i = span[1]
            continue
        if src.startswith('//', i):
            nl = src.find('\n', i)
            i = end if nl < 0 else nl
            continue
        i += 1
    return out


def _skip_to_close(src: str, open_idx: int, opener: str, closer: str) -> int:
    depth, i = 0, open_idx
    while i < len(src):
        ch = src[i]
        if ch in '\'"':
            i = scan_literal(src, i)
            continue
        if src.startswith('//', i):
            nl = src.find('\n', i)
            i = len(src) if nl < 0 else nl
            continue
        if ch == opener:
            depth += 1
        elif ch == closer:
            depth -= 1
            if depth == 0:
                return i
        i += 1
    raise ValueError('unbalanced delimiters')


def _store(src: str, entry: Entry, locale: str, lits):
    """Record one locale's text, and lock it when code — not concatenation —
    decides the wording.

    Several adjacent literals are normally just a long sentence wrapped to fit
    the line limit; those are joined and stay editable. But when the gap
    between two literals holds anything other than whitespace or a comment
    (a `?` / `:` of a ternary), the final text depends on a condition and no
    single literal can hold an edited value — same for a `${cond ? 'a' : 'b'}`
    inside one literal.
    """
    texts = [_unescape(raw) for raw, _ in lits]
    glue = [src[a[1][1]:b[1][0]] for a, b in zip(lits, lits[1:])]
    conditional = any(re.sub(r'//[^\n]*', '', g).strip() for g in glue)
    entry.values[locale] = (' | ' if conditional else '').join(texts)
    entry.spans[locale] = (lits[0][1][0], lits[-1][1][1])
    if conditional:
        entry.locked[locale] = 'text se v kódu skládá podle podmínky'
    elif _nested_cond(lits[0][0]) or any(_nested_cond(raw) for raw, _ in lits):
        entry.locked[locale] = 'text obsahuje podmínku uvnitř ${…}'


def _parse_maps(src: str, entries: dict):
    for locale in LOCALES:
        head = src.index(MAP_HEADER % locale)
        start = src.index('{', head)
        end = _skip_to_close(src, start, '{', '}')
        i, key, vals, state = start + 1, None, [], 'key'
        while i < end:
            ch = src[i]
            if src.startswith('//', i):
                nl = src.find('\n', i)
                i = end if nl < 0 else nl
                continue
            if ch in '\'"':
                raw, span = literal_at(src, i)
                if state in ('key', 'colon'):
                    key, state = _unescape(raw), 'colon'
                else:
                    vals.append((raw, span))
                i = span[1]
                continue
            if ch == ':' and state == 'colon':
                state, vals = 'value', []
            elif ch == ',' and state == 'value':
                if key and vals:
                    eid = f'ui.{key}'
                    e = entries.setdefault(eid, Entry(eid, 'ui', key))
                    _store(src, e, locale, vals)
                key, vals, state = None, [], 'key'
            i += 1


def _enclosing_member(src: str, pos: int) -> str:
    head = src.rfind('static String', 0, pos)
    m = re.match(r'static String (?:get )?(\w+)', src[head:])
    return m.group(1) if m else '?'


def _parse_picks(src: str, entries: dict, limit: int):
    found, counts = [], {}
    for m in re.finditer(r'_pick\(', src[:limit]):
        op = m.end() - 1
        close = _skip_to_close(src, op, '(', ')')
        body = src[op + 1:close]
        if 'required String' in body:          # the helper's own declaration
            continue
        labels = [(lm.group(1), op + 1 + lm.end()) for lm in re.finditer(r'\b(cz|sk|en):', body)]
        if len(labels) < 3:
            continue
        name = _enclosing_member(src, m.start())
        counts[name] = counts.get(name, 0) + 1
        e = Entry('', 'dyn', name)
        for idx, (loc, after) in enumerate(labels):
            seg_end = labels[idx + 1][1] - len(labels[idx + 1][0]) - 1 if idx + 1 < len(labels) else close
            lits = _literals(src, after, seg_end)
            if lits:
                _store(src, e, loc, lits)
        if len(e.values) == 3:
            found.append((name, counts[name], e))
    totals = {}
    for name, _, _ in found:
        totals[name] = totals.get(name, 0) + 1
    for name, nth, e in found:
        e.id = f'dyn.{name}' if totals[name] == 1 else f'dyn.{name}#{nth}'
        entries[e.id] = e


def _parse_plurals(src: str, entries: dict, limit: int):
    pat = re.compile(r'static String (\w+)\(([^)]*)\) \{\s*switch \(LocaleManager\.current\) \{')
    for m in pat.finditer(src[:limit]):
        name = m.group(1)
        if name == '_pick':
            continue
        brace = src.index('{', m.end() - 1)
        body_end = _skip_to_close(src, brace, '{', '}')
        cases = [(cm.group(1), cm.end()) for cm in re.finditer(r'case AppLocale\.(cs|sk|en):', src[brace:body_end])]
        for idx, (loc, after) in enumerate(cases):
            start = brace + after
            end = brace + cases[idx + 1][1] - len(f'case AppLocale.{cases[idx + 1][0]}:') if idx + 1 < len(cases) else body_end
            lits = _literals(src, start, end)
            locale = 'cz' if loc == 'cs' else loc
            forms = PLURAL_FORMS[locale]
            if len(lits) == len(forms):
                pairs = list(zip(forms, lits))
            else:
                # An unexpected branch shape (e.g. English folding its two
                # forms into one interpolated literal) is exported as the
                # 'other' form and locked rather than guessed apart.
                pairs = [('other', lits[-1])] if lits else []
            for form, lit in pairs:
                eid = f'plural.{name}.{form}'
                e = entries.setdefault(eid, Entry(eid, 'plural', name))
                _store(src, e, locale, [lit])


def parse(src: str) -> dict:
    limit = src.index(MAP_HEADER % 'cz')
    entries: dict = {}
    _parse_picks(src, entries, limit)
    _parse_plurals(src, entries, limit)
    _parse_maps(src, entries)
    return entries


def apply(src: str, entries: dict, edits: dict):
    """edits: {id: {locale: new_text}} -> (new_src, changelog, skipped)."""
    patches, log, skipped = [], [], []
    for eid, per_locale in edits.items():
        entry = entries.get(eid)
        if entry is None:
            raise KeyError(f'neznámé ID: {eid}')
        for locale, new in per_locale.items():
            if locale not in entry.spans:
                raise KeyError(f'{eid}: locale {locale} není ve zdroji')
            old = entry.values[locale]
            if new == old:
                continue
            if locale in entry.locked:
                skipped.append((eid, locale, old, new, entry.locked[locale]))
                continue
            patches.append((entry.spans[locale], _escape(new)))
            log.append((eid, locale, old, new))
    for (start, end), text in sorted(patches, key=lambda p: -p[0][0]):
        src = src[:start] + text + src[end:]
    return src, log, skipped
