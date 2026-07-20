# Veřejné právní stránky — deployment

Aplikace má veřejně dostupné právní stránky řešené přes Flutter routing (`go_router`):

| URL | Routa v appce | Obsah (markdown asset) |
|---|---|---|
| `/terms` | `LegalPage(slug:'terms', locale:'cs')` | `assets/legal/cs/terms.md` |
| `/terms/en` | `LegalPage(slug:'terms', locale:'en')` | `assets/legal/en/terms.md` |
| `/privacy` | `LegalPage(slug:'privacy', locale:'cs')` | `assets/legal/cs/privacy.md` |
| `/privacy/en` | `LegalPage(slug:'privacy', locale:'en')` | `assets/legal/en/privacy.md` |
| `/about` | `LegalPage(slug:'about', locale:'cs')` | `assets/legal/cs/about.md` |
| `/about/en` | `LegalPage(slug:'about', locale:'en')` | `assets/legal/en/about.md` |
| `/cookies` | `LegalPage(slug:'cookies', locale:'cs')` | `assets/legal/cs/cookies.md` |
| `/cookies/en` | `LegalPage(slug:'cookies', locale:'en')` | `assets/legal/en/cookies.md` |
| `/accessibility` | `LegalPage(slug:'accessibility', locale:'cs')` | `assets/legal/cs/accessibility.md` |
| `/accessibility/en` | `LegalPage(slug:'accessibility', locale:'en')` | `assets/legal/en/accessibility.md` |
| `/ai` | `LegalPage(slug:'ai', locale:'cs')` | `assets/legal/cs/ai.md` |
| `/ai/en` | `LegalPage(slug:'ai', locale:'en')` | `assets/legal/en/ai.md` |

Routing definovaný v `lib/routing/app_router.dart`. URL strategie: `usePathUrlStrategy()` (clean URLs bez hashe).

## Jak to funguje

1. Uživatel jde na `https://app.edu-ai.eu/terms`.
2. Hosting (Cloudflare Pages / Netlify / Firebase / nginx) **musí mít SPA fallback**: pokud `/terms` není fyzický soubor, vrátit `/index.html`.
3. `index.html` bootstrapne Flutter app.
4. GoRouter přečte URL `/terms` a otevře `LegalPage(slug:'terms', locale:'cs')`.
5. `LegalPage` načte `assets/legal/cs/terms.md` z rootBundle a vykreslí přes `flutter_markdown` s brand stylingem.

## Hosting konfigurace

### Cloudflare Pages / Netlify

Soubor `web/_redirects` (už hotov) — Flutter build ho zkopíruje do `build/web/_redirects`:

```
/*    /index.html   200
```

### Firebase Hosting

`firebase.json`:

```json
{
  "hosting": {
    "public": "build/web",
    "ignore": ["firebase.json", "**/.*", "**/node_modules/**"],
    "rewrites": [
      { "source": "**", "destination": "/index.html" }
    ]
  }
}
```

### Nginx

```nginx
location / {
  try_files $uri $uri/ /index.html;
}
```

### Apache (.htaccess)

```apache
<IfModule mod_rewrite.c>
  RewriteEngine On
  RewriteCond %{REQUEST_FILENAME} !-f
  RewriteCond %{REQUEST_FILENAME} !-d
  RewriteRule . /index.html [L]
</IfModule>
```

## Aktualizace obsahu

Pro úpravu textu právní stránky:

1. Editovat příslušný markdown soubor v `assets/legal/{cs,en}/{slug}.md`.
2. Aktualizovat verzi a datum účinnosti v hlavičce dokumentu.
3. Synchronizovat CZ + EN verzi.
4. Pro podstatnou změnu Podmínek nebo Privacy: informovat uživatele v Aplikaci a e-mailem **30 dní před účinností** (Terms 16.2, Privacy 14.2).
5. `flutter build web` → nasadit. (Markdown soubory jsou bundlované, takže žádný server-side reload.)

## V Aplikaci (in-app)

Existující obrazovky `lib/pages/terms_page.dart` a `lib/pages/privacy_page.dart` jsou nyní tenké wrappery nad `LegalPage(inAppMode: true)`. Otevírají se z Profile menu beze změny chování.

`about_page.dart` má ve své in-app verzi navíc akce (Send Debug Report, Factory Reset, …) — zůstává nedotčen. Veřejná `/about` URL zobrazuje pouze legal description (bez akcí).

## Store readiness checklist

- [ ] Otestovat `https://app.edu-ai.eu/privacy` po deploy (200 OK, vrací HTML s privacy textem)
- [ ] Otestovat `/terms`, `/cookies`, `/accessibility`, `/ai`, `/about` (CZ + EN)
- [ ] App Store Connect → App Privacy → Privacy Policy URL = `https://app.edu-ai.eu/privacy`
- [ ] Google Play Console → App content → Privacy Policy = `https://app.edu-ai.eu/privacy`
- [ ] Apple Sign-In / Google Sign-In / Microsoft Sign-In OAuth consent screen → Privacy URL + Terms URL
- [ ] App Privacy Details v App Store Connect vyplněny v souladu s `/privacy`
- [ ] Data Safety formulář v Google Play Console vyplněn v souladu s `/privacy`
- [ ] In-app Profil → odkazy na všechny právní stránky funkční
