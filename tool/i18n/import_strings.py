#!/usr/bin/env python3
"""Import an edited text workbook back into the app and the API.

    python3 eduai-app/tool/i18n/import_strings.py EDUAI-texty.xlsx [--dry-run]
        [--base EDUAI-texty-odeslano.xlsx]

Reads the sheet „Texty aplikace“ (or a CSV with the same columns) and writes
the changed values into eduai-app/lib/core/strings/app_strings.dart; with
--mails it also writes the sheet „E-maily“ into eduai-api/lang/*/.

--base is the workbook as it was sent to the client. The code keeps moving
while the client edits, so a cell the client never touched can hold wording
that has since been changed in code; importing it would silently revert that
change. With --base only the cells that differ from the sent workbook count
as edits.

The ID column is the address of each string, so rows may be reordered or
filtered in the spreadsheet but never renamed. Nothing is written when a
check fails: an unknown ID, a lost `$variable`, or an edit to a row whose
wording is assembled in code (those are listed and left to a developer).
"""

from __future__ import annotations

import argparse
import csv
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dart_strings  # noqa: E402
import php_strings  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..'))
STRINGS = os.path.join(REPO, 'eduai-app', 'lib', 'core', 'strings', 'app_strings.dart')
LANG = os.path.join(REPO, 'eduai-api', 'lang')
APP_SHEET = 'Texty aplikace'
MAIL_SHEET = 'E-maily'
COLUMNS = ('cz', 'sk', 'en')
PLACEHOLDER = re.compile(r'\$\{?\w+\}?|\{\w+\}|\{\{\w+\}\}')


def read_rows(path: str, sheet: str):
    if path.lower().endswith('.csv'):
        with open(path, newline='', encoding='utf-8-sig') as fh:
            rows = list(csv.reader(fh))
        return [r for r in rows[1:] if r and r[0].strip()]
    from openpyxl import load_workbook
    wb = load_workbook(path, data_only=True)
    if sheet not in wb.sheetnames:
        raise SystemExit(f'v souboru chybí list „{sheet}“ (listy: {", ".join(wb.sheetnames)})')
    out = []
    for row in wb[sheet].iter_rows(min_row=2, values_only=True):
        if row and row[0]:
            out.append(['' if c is None else str(c) for c in row])
    return out


def placeholders(text: str):
    return sorted(PLACEHOLDER.findall(text))


def read_base(path: str | None, sheet: str, first: int):
    """ID → language cells of the workbook as sent, or None without --base."""
    if path is None:
        return None
    return {row[0].strip(): (row + ['', '', '', '', ''])[first:first + 3]
            for row in read_rows(path, sheet)}


def untouched(base, key: str, column: int, new: str) -> bool:
    if base is None or key not in base:
        return False
    return new == base[key][column].replace('\r\n', '\n')


def tidy(new: str, old: str) -> str:
    # A stray space typed at the end of a cell is invisible in the sheet but
    # ends up in the UI; keep it only where the code had one (joiners like ' a ').
    if not old.endswith(' '):
        new = new.rstrip(' ')
    if not old.startswith(' '):
        new = new.lstrip(' ')
    return new


def import_app(path: str, dry_run: bool, base_path: str | None = None):
    src = open(STRINGS, encoding='utf-8').read()
    entries = dart_strings.parse(src)
    base = read_base(base_path, APP_SHEET, 2)
    edits, problems, blocked = {}, [], []
    for row in read_rows(path, APP_SHEET):
        eid = row[0].strip()
        entry = entries.get(eid)
        if entry is None:
            problems.append(f'{eid}: takové ID v kódu není')
            continue
        values = (row + ['', '', '', '', ''])[2:5]
        for column, (locale, new) in enumerate(zip(COLUMNS, values)):
            if locale not in entry.values:
                if new.strip():
                    problems.append(f'{eid}/{locale}: text navíc – tento jazyk tu žádný nemá')
                continue
            old = entry.values[locale]
            new = new.replace('\r\n', '\n')
            if untouched(base, eid, column, new):
                continue
            new = tidy(new, old)
            if new == old:
                continue
            if not new.strip():
                problems.append(f'{eid}/{locale}: prázdná buňka, původní text „{old[:40]}“')
                continue
            if locale in entry.locked:
                blocked.append(f'{eid}/{locale}: {entry.locked[locale]}')
                continue
            if placeholders(new) != placeholders(old):
                problems.append(
                    f'{eid}/{locale}: změnily se zástupné znaky '
                    f'{placeholders(old)} → {placeholders(new)}')
                continue
            edits.setdefault(eid, {})[locale] = new
    if problems:
        print('CHYBY — nic se nezapsalo:')
        for p in problems:
            print('  ·', p)
        return None, blocked
    out, log, skipped = dart_strings.apply(src, entries, edits)
    if not dry_run and log:
        open(STRINGS, 'w', encoding='utf-8').write(out)
    return log, blocked + [f'{e}/{loc}: {why}' for e, loc, _, _, why in skipped]


def import_mails(path: str, dry_run: bool, base_path: str | None = None):
    rows = read_rows(path, MAIL_SHEET)
    base = read_base(base_path, MAIL_SHEET, 1)
    per_file, problems, log = {}, [], []
    for row in rows:
        key = row[0].strip()
        if '.' not in key:
            problems.append(f'{key}: ID nemá tvar skupina.klíč')
            continue
        group, rest = key.split('.', 1)
        values = (row + ['', '', ''])[1:4]
        for column, (locale, new) in enumerate(zip(('cs', 'sk', 'en'), values)):
            path_php = os.path.join(LANG, locale, f'{group}.php')
            if not new.strip() or not os.path.exists(path_php):
                continue
            new = new.replace('\r\n', '\n')
            if untouched(base, key, column, new):
                continue
            per_file.setdefault(path_php, {})[rest] = new.strip(' ')
    for php_path, edits in sorted(per_file.items()):
        src = open(php_path, encoding='utf-8').read()
        try:
            out, changes = php_strings.apply(src, edits)
        except KeyError as exc:
            problems.append(f'{os.path.relpath(php_path, REPO)}: {exc}')
            continue
        if changes:
            log += [(os.path.relpath(php_path, REPO), k, o, n) for k, o, n in changes]
            if not dry_run:
                open(php_path, 'w', encoding='utf-8').write(out)
    for p in problems:
        print('  ·', p)
    return log


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('file', help='upravený .xlsx (nebo .csv listu „Texty aplikace“)')
    ap.add_argument('--dry-run', action='store_true', help='jen vypsat, co by se změnilo')
    ap.add_argument('--mails', action='store_true', help='naimportovat i list „E-maily“')
    ap.add_argument('--base', metavar='ODESLANO.xlsx',
                    help='sešit, jak odešel klientovi: importují se jen buňky, které klient změnil')
    args = ap.parse_args()

    log, blocked = import_app(args.file, args.dry_run, args.base)
    if log is None:
        raise SystemExit(1)
    for eid, locale, old, new in log:
        print(f'  {eid} [{locale}] „{old}“ → „{new}“')
    print(f'{len(log)} změn v app_strings.dart' + (' (dry-run)' if args.dry_run else ''))
    if blocked:
        print(f'\n{len(blocked)} textů nelze naimportovat, skládají se v kódu:')
        for b in blocked:
            print('  ·', b)
    if args.mails:
        mail_log = import_mails(args.file, args.dry_run, args.base)
        for rel, key, old, new in mail_log:
            print(f'  {rel} {key} „{old}“ → „{new}“')
        print(f'{len(mail_log)} změn v eduai-api/lang' + (' (dry-run)' if args.dry_run else ''))
    if not args.dry_run and log:
        # The file is not dart-format clean in the repo, so reformatting it
        # here would bury the text change in whitespace noise. The parity
        # test is what actually has to pass.
        print('\nspusť `flutter test test/core/strings/app_strings_test.dart`')


if __name__ == '__main__':
    main()
