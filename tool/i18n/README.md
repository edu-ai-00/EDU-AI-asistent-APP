# Export a import textů

Nástroj na kolečko „pošli klientovi texty → klient je upraví → naimportuj je zpět“.
Všechny texty aplikace žijí v `lib/core/strings/app_strings.dart` (mapy `_cz`, `_sk`,
`_en` + funkce `_pick`), texty e-mailů v `eduai-api/lang/{cs,sk,en}`.

## Export

```bash
python3 eduai-app/tool/i18n/export_strings.py -o ~/Desktop/EDUAI-texty.xlsx
```

Vznikne `.xlsx` se čtyřmi listy (`Pokyny`, `Texty aplikace`, `E-maily`, `Notifikace`)
a vedle něj `.csv` s listem `Texty aplikace` pro případ, že klient pracuje v Google
Sheets. Jazykové sloupce jsou editovatelné, ostatní zamčené (bez hesla).

## Import

```bash
python3 eduai-app/tool/i18n/import_strings.py ~/Desktop/EDUAI-texty.xlsx --dry-run
python3 eduai-app/tool/i18n/import_strings.py ~/Desktop/EDUAI-texty.xlsx --mails
flutter test test/core/strings/app_strings_test.dart
```

Odeslaný export si schovej a při importu ho předej jako `--base`:

```bash
python3 eduai-app/tool/i18n/import_strings.py upraveno.xlsx --base odeslano.xlsx --mails --dry-run
```

Kód se mezitím mění dál. Bez `--base` by buňka, na kterou klient nesáhl, vrátila
text, který se od exportu v kódu opravil. S `--base` se importují jen buňky, které
klient opravdu změnil. Kdo odeslaný soubor nemá, vygeneruje ho exportem z commitu,
ze kterého odešel.

Import je adresovaný sloupcem `ID`, takže klient může řádky filtrovat i přeřadit.
Když cokoli nesedí (neznámé ID, zmizelý `$count`, vyprázdněná buňka), nezapíše se
**nic** a vypíše se seznam problémů.

## Co se importovat nedá

Pár textů si appka skládá v kódu podle podmínky — `'den'` vs `'dní'`,
`${count == 1 ? … : …}`, nebo věta slepená ze dvou částí kolem ternárního operátoru.
Export je ukáže šedě a import je odmítne; musí je přepsat vývojář ručně.

Jazyky jsou `cz` / `sk` / `en` (mapa `_cz` se historicky jmenuje `cz`, ne `cs`,
zatímco `AppLocale.cs` a `Accept-Language` používají `cs` — převod řeší nástroj sám).

## Notifikace

List `Notifikace` je jen pro čtení. Texty push a Novinek nejsou v kódu, ale v tabulce
`notification_types` (seed: `eduai-api/database/seeders/NotificationCatalogSeeder.php`,
edituje je admin v panelu) a dnes existují **jen česky** — jazykové sloupce v listu
jsou proto prázdné a čekají na rozhodnutí, jestli se do tabulky doplní locale varianty.
