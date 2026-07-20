# Prohlášení o cookies a obdobných technologiích

*Účinnost od: 20. 5. 2026*

> Toto Prohlášení doplňuje [Zásady zpracování osobních údajů](/privacy) a popisuje, jaké technologie pro ukládání informací používáme v aplikaci EDU AI asistent („Aplikace") a na souvisejících webových stránkách.

## 1. Co jsou cookies a obdobné technologie

1.1 **Cookies** jsou malé textové soubory ukládané prohlížečem na vašem zařízení. Aplikace EDU AI asistent jako Single Page Application v prohlížeči standardní HTTP cookies nepoužívá. Pro plnění funkcí v prohlížeči využíváme tzv. obdobné technologie:

- **Local Storage** a **Session Storage** – úložiště pro uchování drobných hodnot na úrovni domény (např. zvolený jazyk).
- **IndexedDB** – strukturovaná databáze v prohlížeči pro offline pokrok, lekce, kvízy a uživatelská data.
- **Cache Storage / Service Worker** – ukládání statických souborů Aplikace (HTML, JS, CSS, fontů) pro rychlejší načítání a offline použití.
- **Session tokeny** – krátkodobé identifikátory přihlášení uložené v zabezpečeném úložišti prohlížeče.

1.2 V mobilních aplikacích (iOS, Android) se ekvivalentně využívají:

- **SQLite databáze** (Drift) – pro uložení uživatelského pokroku, záložek, kurzů, statistik.
- **Šifrované úložiště klíčů** (Keychain na iOS, Keystore na Androidu prostřednictvím `flutter_secure_storage`) – pro autentizační token.
- **SharedPreferences / NSUserDefaults** – pro uživatelská nastavení (jazyk, motiv, drobné konfigurace).

## 2. Náš přístup

2.1 Aplikace **nepoužívá**:

- sledovací cookies (tracking),
- reklamní cookies,
- cookies třetích stran k profilování,
- technologie pro behaviorální cílení,
- analytické nástroje, které předávají data marketingovým sítím,
- cross-site tracking nebo fingerprinting.

2.2 Aplikace používá **pouze technicky nezbytné** technologie, které jsou nezbytné k poskytnutí služby vyžádané uživatelem.

## 3. Právní základ

3.1 Pro technicky nezbytné cookies a obdobné technologie není podle § 89 odst. 3 zákona č. 127/2005 Sb., o elektronických komunikacích, ve znění platném po novele z roku 2021 (transpozice směrnice ePrivacy 2002/58/ES), vyžadován souhlas uživatele.

3.2 Pokud bychom v budoucnu zavedli analytické či marketingové technologie vyžadující souhlas, požádali bychom o něj prostřednictvím transparentní souhlasné lišty v souladu s platnými předpisy.

## 4. Přehled používaných technologií

### 4.1 Webová verze Aplikace (prohlížeč)

| Název / klíč | Typ úložiště | Účel | Doba uložení |
|---|---|---|---|
| locale | Local Storage | Zapamatovaný jazyk uživatelského rozhraní | Trvale (do smazání uživatelem) |
| theme | Local Storage | Zapamatované barevné téma rozhraní | Trvale |
| session_meta | Local Storage | Metadata o aktivní session (poslední aktivita, sdílené zařízení) | Po dobu session, max. dle nastavené inaktivity |
| auth_token | Local Storage (web) / Secure storage (mobil) | Autentizační token (Bearer) pro REST API | Do odhlášení nebo expirace tokenu |
| eduai_db | IndexedDB | Lokální databáze (Drift): kurzy, lekce, pokrok, záložky, kvízy, statistiky, FSRS karty | Trvale (do smazání uživatelem nebo odinstalování) |
| flutter-cache | Cache Storage | Statické soubory Aplikace (HTML, JS, CSS, fonty, ikony) pro offline použití | Aktualizováno při novém nasazení |
| cf-* (Cloudflare) | Cookies třetí strany (technická) | Ochrana před útoky (DDoS, bot management) — pouze pro stránky chráněné Cloudflare | 30 minut – 1 rok dle typu |

### 4.2 Mobilní verze (iOS, Android)

| Název | Typ úložiště | Účel | Doba uložení |
|---|---|---|---|
| app_database.sqlite | SQLite (Drift) | Uživatelská data: kurzy, lekce, pokrok, záložky, statistiky, FSRS karty, chat sessions | Trvale (do odinstalování / smazání dat) |
| auth_token | Keychain (iOS) / Keystore (Android) | Autentizační token (Bearer) | Do odhlášení nebo expirace |
| SharedPreferences / NSUserDefaults | OS nastavení | Jazyk, motiv, drobné konfigurace, příznaky | Trvale (do odinstalování / smazání dat) |
| FCM token | Firebase storage | Push notifikace (pokud uživatel povolil) | Do odhlášení nebo zákazu notifikací |

### 4.3 Veřejné stránky (terms, privacy, about, …)

Tyto stránky **nepoužívají žádné cookies** ani neukládají žádné informace na vaše zařízení nad rámec běžné cache prohlížeče (HTTP cache, kterou plně kontrolujete sami).

## 5. Doba uložení

5.1 Technicky nezbytné technologie jsou ukládány po dobu nezbytnou pro jejich účel — typicky po dobu trvání session nebo po dobu existence vašeho účtu, pokud to nestanoví jinak konkrétní záznam v tabulce výše.

5.2 Lokální data můžete kdykoli odstranit:

- v Aplikaci: *Profil → Nastavení → Odhlásit / Smazat účet*,
- v prohlížeči: smazáním dat webu (Site Data / IndexedDB / Local Storage),
- v mobilním OS: smazáním dat aplikace v nastavení systému nebo odinstalováním.

## 6. Jak technologie spravovat nebo odmítnout

6.1 Většinu prohlížečů můžete nastavit tak, aby cookies a obdobné technologie blokovala. Odmítnutí technicky nezbytných technologií však může způsobit, že Aplikace nebude fungovat správně (např. nepůjde se přihlásit nebo se vyresetuje váš pokrok).

6.2 Nastavení prohlížečů:

- [Google Chrome](https://support.google.com/chrome/answer/95647)
- [Mozilla Firefox](https://support.mozilla.org/cs/kb/povoleni-zakazani-cookies)
- [Apple Safari](https://support.apple.com/cs-cz/guide/safari/sfri11471/mac)
- [Microsoft Edge](https://support.microsoft.com/cs-cz/microsoft-edge)

6.3 Push notifikace v mobilní Aplikaci kdykoliv vypnete v nastavení operačního systému.

## 7. Třetí strany

7.1 Aplikace komunikuje s následujícími službami třetích stran, které mohou v rámci svého technického fungování krátkodobě zpracovávat údaje (např. IP adresu pro doručení obsahu). Tyto služby jsou popsány v [Zásadách zpracování osobních údajů](/privacy):

- Cloudflare — distribuce obsahu a ochrana před útoky
- Amazon Web Services (AWS) — hosting
- Firebase (Google) — push notifikace, autentizace přes Google Sign-In
- Apple / Microsoft — pouze v případě přihlášení přes Apple Sign-In nebo Microsoft Sign-In

7.2 Žádný z těchto poskytovatelů neukládá do Aplikace marketingové ani analytické cookies.

## 8. Změny Prohlášení

8.1 Toto Prohlášení můžeme přiměřeně měnit, zejména při změně technické architektury Aplikace nebo při zavedení nových technologií. Aktuální znění bude vždy dostupné na adrese [app.edu-ai.eu/cookies](https://app.edu-ai.eu/cookies).

8.2 V případě podstatné změny vás informujeme v Aplikaci nebo e-mailem nejméně 30 dní před účinností.

## 9. Kontakt

Dotazy k tomuto Prohlášení směřujte na [gdpr@edu-ai.eu](mailto:gdpr@edu-ai.eu) nebo na další kontakty uvedené v [Zásadách zpracování osobních údajů](/privacy).
