#!/usr/bin/env python3
"""Export every user-facing string of the app into one editable workbook.

    python3 eduai-app/tool/i18n/export_strings.py [-o out.xlsx]

Sheets:
  Pokyny          how to edit the file and what not to touch
  Texty aplikace  the app UI (AppStrings) — the sheet import_strings.py reads
  E-maily         the API's mail/consent translations (lang/{cs,sk,en})
  Notifikace      the notification catalogue, Czech only, for reference

Round trip: export -> edit the three language columns -> import_strings.py.
Only the language columns may change; ID is the address of the string.
"""

from __future__ import annotations

import argparse
import csv
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dart_strings  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..'))
STRINGS = os.path.join(REPO, 'eduai-app', 'lib', 'core', 'strings', 'app_strings.dart')
LANG = os.path.join(REPO, 'eduai-api', 'lang')
SEEDER = os.path.join(REPO, 'eduai-api', 'database', 'seeders', 'NotificationCatalogSeeder.php')
SHEET = 'Texty aplikace'

# Key prefix -> the screen a translator would recognise. First match wins, so
# the list is ordered from the most specific prefix to the most general.
GROUPS = [
    (('nav', 'shell', 'sideNav', 'tab'), 'Navigace'),
    (('welcome', 'guide', 'onboarding', 'profileSetup'), 'Úvod a nastavení profilu'),
    (('practice',), 'Opakování (dřív Procvičování)'),
    (('kurzy', 'library'), 'Záložka Kurzy a knihovna'),
    (('course',), 'Kurz a jeho detail'),
    (('lesson', 'step', 'block', 'open', 'hint'), 'Lekce a bloky'),
    (('quiz', 'elo'), 'Kvíz'),
    (('skill',), 'Dovednosti a úrovně'),
    (('chat', 'mentor'), 'Chat a mentor'),
    (('auth', 'login', 'consent', 'ageGate', 'guest', 'code'), 'Přihlášení, souhlas rodiče'),
    (('notif', 'novinky'), 'Notifikace a Novinky'),
    (('shop', 'doplnky', 'avatar', 'theme', 'edux', 'coin'), 'Shop a doplňky'),
    (('game', 'miniGames'), 'Hry'),
    (('achievement', 'stat', 'progress', 'streak', 'trophy'), 'Statistiky a odznaky'),
    (('classroom', 'school', 'teacher', 'class'), 'Třída a škola'),
    (('terms', 'privacy', 'legal', 'accessibility'), 'Právní dokumenty'),
    (('profile',), 'Profil'),
    (('about',), 'O aplikaci'),
    (('shared', 'device'), 'Sdílené zařízení'),
    (('persona', 'goal', 'subject', 'jpz'), 'Osobnost, cíle, předměty'),
    (('exercise', 'engine', 'trueFalse', 'confidence', 'level'), 'Cvičení a vyhodnocení'),
    (('email', 'push', 'install', 'promo', 'banner'), 'E-maily, push a bannery'),
    (('global', 'challenge', 'dash', 'recent', 'continue', 'bookmarks'), 'Přehled a výzvy'),
    (('dialog', 'drawer', 'section', 'filter', 'action', 'edit', 'new', 'default', 'time', 'duration'),
     'Obecné prvky rozhraní'),
    (('error', 'generic', 'offline', 'sync', 'retry', 'common', 'app'), 'Systémové hlášky'),
]
RENAME = re.compile('procvič|precvič|practi[cs]', re.I)
PLACEHOLDER = re.compile(r'\$\{?\w+\}?|\{\w+\}')
FORM_LABEL = {'one': '1 (jeden)', 'few': '2–4', 'other': '5 a více'}


def group_of(name: str) -> str:
    for prefixes, label in GROUPS:
        if any(name.startswith(p) for p in prefixes):
            return label
    return 'Ostatní'


def app_rows():
    src = open(STRINGS, encoding='utf-8').read()
    rows = []
    for entry in dart_strings.parse(src).values():
        note = []
        if entry.kind == 'plural':
            note.append(f'množné číslo, tvar {FORM_LABEL.get(entry.id.rsplit(".", 1)[1], "?")}')
        if entry.locked:
            note.append('needitovatelné – text se skládá v kódu, předej vývojáři')
        placeholders = sorted(set(PLACEHOLDER.findall(entry.values.get('cz', ''))))
        if placeholders:
            note.append('zachovej ' + ', '.join(placeholders))
        if RENAME.search(entry.values.get('cz', '')):
            note.insert(0, '⚠ k přejmenování')
        rows.append([
            entry.id,
            group_of(entry.name),
            entry.values.get('cz', ''),
            entry.values.get('sk', ''),
            entry.values.get('en', ''),
            '; '.join(note),
            bool(entry.locked),
        ])
    rows.sort(key=lambda r: (r[1], r[0]))
    return rows


def _php_strings(path: str) -> dict:
    """Flatten a Laravel lang file without running PHP."""
    src = open(path, encoding='utf-8').read()
    out, stack, i = {}, [], 0
    pending = None
    while i < len(src):
        ch = src[i]
        if src.startswith('//', i) or src.startswith('/*', i):
            end = src.find('\n', i) if src[i + 1] == '/' else src.find('*/', i) + 2
            i = len(src) if end <= 0 else end
            continue
        if ch in '\'"':
            raw, (_, end) = dart_strings.literal_at(src, i)
            text = raw[1:-1].replace("\\'", "'").replace('\\"', '"')
            nxt = src[end:end + 60].lstrip()
            if nxt.startswith('=>'):
                pending = text
            elif pending is not None:
                out['.'.join(stack + [pending])] = text
                pending = None
            i = end
            continue
        if ch == '[':
            stack.append(pending) if pending else None
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


def mail_rows():
    rows = []
    for group in ('mail', 'consent'):
        cs_path = os.path.join(LANG, 'cs', f'{group}.php')
        if not os.path.exists(cs_path):
            continue
        cs = _php_strings(cs_path)
        per = {}
        for loc in ('sk', 'en'):
            path = os.path.join(LANG, loc, f'{group}.php')
            per[loc] = _php_strings(path) if os.path.exists(path) else {}
        for key, value in cs.items():
            missing = [loc for loc in ('sk', 'en') if not per[loc].get(key)]
            rows.append([f'{group}.{key}', value, per['sk'].get(key, ''), per['en'].get(key, ''),
                         'chybí: ' + ', '.join(missing) if missing else ''])
    return rows


def notification_rows():
    src = open(SEEDER, encoding='utf-8').read()
    body = src[src.index('public static function types()'):]
    rows = []
    for block in re.split(r'\n            \[\n', body)[1:]:
        def field(key):
            m = re.search(r"'" + key + r"' => '((?:[^'\\]|\\.)*)'", block)
            return m.group(1).replace("\\'", "'") if m else ''
        key = field('key')
        if not key:
            continue
        for slot in ('push_title', 'push_body', 'feed_title', 'feed_body'):
            text = field(slot)
            if text:
                rows.append([key, field('name'), slot, text])
    return rows


def build(out_path: str):
    from openpyxl import Workbook
    from openpyxl.styles import Alignment, Font, PatternFill, Protection
    from openpyxl.utils import get_column_letter
    from openpyxl.worksheet.protection import SheetProtection

    head_font = Font(bold=True, color='FFFFFF')
    head_fill = PatternFill('solid', start_color='1F3864')
    locked_fill = PatternFill('solid', start_color='E7E6E6')
    rename_fill = PatternFill('solid', start_color='FFF2CC')
    missing_fill = PatternFill('solid', start_color='F8CBAD')
    top = Alignment(wrap_text=True, vertical='top')

    wb = Workbook()
    guide = wb.active
    guide.title = 'Pokyny'
    guide.column_dimensions['A'].width = 110
    lines = [
        ('EDU AI — texty aplikace', 16, True),
        ('', 11, False),
        ('Jak soubor upravit', 13, True),
        ('1. Upravuj POUZE sloupce Čeština, Slovenština a Angličtina na listu „Texty aplikace“.', 11, False),
        ('2. Sloupec ID je adresa textu v aplikaci. Needituj ho, nemaž řádky, nepřeřazuj je.', 11, False),
        ('3. Texty s $jmeno nebo {count} jsou místa, kam aplikace vloží číslo nebo jméno.', 11, False),
        ('   Zástupný znak musí zůstat ve tvaru, v jakém je (viz sloupec Poznámka).', 11, False),
        ('4. Šedé řádky needituj — ten text si aplikace skládá v kódu, upraví ho vývojář.', 11, False),
        ('5. Žlutě je označené to, co se týká přejmenování „Procvičování“ → „Opakování“.', 11, False),
        ('6. Prázdná buňka znamená, že daný jazyk text nemá (třeba množné číslo 2–4 v angličtině).', 11, False),
        ('   Prázdnou buňku nechej prázdnou, pokud tam text nepatří.', 11, False),
        ('', 11, False),
        ('Listy', 13, True),
        ('Texty aplikace — vše, co uživatel vidí v appce. Tento list naimportujeme zpět do kódu.', 11, False),
        ('E-maily — texty e-mailů z API (ověřovací kód, souhlas rodiče). Importujeme také.', 11, False),
        ('Notifikace — texty push a Novinek. Jsou v databázi, přepíšeme je po dohodě ručně.', 11, False),
        ('', 11, False),
        ('Zpátky pošli tento soubor (klidně i jako CSV listu „Texty aplikace“).', 11, False),
    ]
    for text, size, bold in lines:
        guide.append([text])
        guide.cell(guide.max_row, 1).font = Font(size=size, bold=bold)

    ws = wb.create_sheet(SHEET)
    ws.append(['ID', 'Kde to je', 'Čeština', 'Slovenština', 'Angličtina', 'Poznámka'])
    for width, col in zip((40, 30, 52, 52, 52, 40), 'ABCDEF'):
        ws.column_dimensions[col].width = width
    rows = app_rows()
    for row in rows:
        ws.append(row[:6])
        r = ws.max_row
        if row[6]:
            for col in range(1, 7):
                ws.cell(r, col).fill = locked_fill
        elif row[5].startswith('⚠'):
            for col in (3, 4, 5):
                ws.cell(r, col).fill = rename_fill
    for cell in ws[1]:
        cell.font, cell.fill = head_font, head_fill
    for row in ws.iter_rows(min_row=2):
        for cell in row:
            cell.alignment = top
        editable = row[0].fill != locked_fill
        for cell in (row[0], row[1], row[5]):
            cell.protection = Protection(locked=True)
        for cell in row[2:5]:
            cell.protection = Protection(locked=not editable)
    ws.protection = SheetProtection(sheet=True, formatCells=False, formatColumns=False)
    ws.freeze_panes = 'C2'
    ws.auto_filter.ref = f'A1:F{ws.max_row}'

    mails = wb.create_sheet('E-maily')
    mails.append(['ID', 'Čeština', 'Slovenština', 'Angličtina', 'Poznámka'])
    for width, col in zip((34, 58, 58, 58, 24), 'ABCDE'):
        mails.column_dimensions[col].width = width
    for row in mail_rows():
        mails.append(row)
        if row[4]:
            mails.cell(mails.max_row, 5).fill = missing_fill
    for cell in mails[1]:
        cell.font, cell.fill = head_font, head_fill
    for row in mails.iter_rows(min_row=2):
        for cell in row:
            cell.alignment = top
    mails.freeze_panes = 'B2'

    notif = wb.create_sheet('Notifikace')
    notif.append(['typ', 'název typu', 'místo', 'Čeština', 'Slovenština', 'Angličtina'])
    for width, col in zip((30, 34, 14, 50, 50, 50), 'ABCDEF'):
        notif.column_dimensions[col].width = width
    for row in notification_rows():
        notif.append(row)
    for cell in notif[1]:
        cell.font, cell.fill = head_font, head_fill
    for row in notif.iter_rows(min_row=2):
        for cell in row:
            cell.alignment = top
    notif.freeze_panes = 'D2'

    wb.save(out_path)

    csv_path = os.path.splitext(out_path)[0] + '.csv'
    with open(csv_path, 'w', newline='', encoding='utf-8-sig') as fh:
        writer = csv.writer(fh)
        writer.writerow(['ID', 'Kde to je', 'Čeština', 'Slovenština', 'Angličtina', 'Poznámka'])
        writer.writerows(row[:6] for row in rows)
    return out_path, csv_path, len(rows)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('-o', '--out', help='cílový .xlsx (vedle se uloží i .csv)')
    args = ap.parse_args()
    out = args.out or os.path.join(os.getcwd(), 'EDUAI-texty.xlsx')
    xlsx, csv_path, count = build(out)
    print(f'{count} textů aplikace\n{xlsx}\n{csv_path}')


if __name__ == '__main__':
    main()
