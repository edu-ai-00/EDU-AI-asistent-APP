# Prohlášení o přístupnosti

*Účinnost od: 20. 5. 2026 · Verze: 1.0 (předběžné znění)*

> **Pozn.:** Definitivní finální znění tohoto prohlášení dodá Poskytovatel po dokončení formálního auditu přístupnosti. Níže uvedený obsah vychází z požadavků WCAG 2.1 úrovně AA, směrnice (EU) 2019/882 (European Accessibility Act, „EAA"), zákona č. 424/2023 Sb. o přístupnosti výrobků a služeb, zákona č. 99/2019 Sb. o přístupnosti webových stránek a mobilních aplikací (přiměřeně) a interní politiky Poskytovatele.

## 1. Závazek k přístupnosti

1.1 **EDU-AI o.p.s.** (dále „Poskytovatel") se zavazuje zajistit, aby aplikace EDU AI asistent („Aplikace"), její mobilní verze (iOS, Android), webová verze i veřejné stránky byly přístupné co nejširšímu okruhu uživatelů, včetně osob se zdravotním postižením a osob s funkčními omezeními.

1.2 Toto prohlášení se vztahuje na:

- Webovou verzi Aplikace dostupnou na [app.edu-ai.eu](https://app.edu-ai.eu)
- Mobilní aplikaci EDU AI asistent pro iOS (App Store) a Android (Google Play)
- Veřejné právní stránky (terms, privacy, cookies, about, accessibility, AI)

## 2. Stav souladu

2.1 Aplikace je **částečně v souladu** s WCAG 2.1 úrovně AA. Některé funkce, zejména některé komplexní interaktivní vzdělávací prvky, mohou zatím vykazovat dílčí nedostatky, na jejichž odstranění průběžně pracujeme.

2.2 Při hodnocení souladu jsme vycházeli z:

- standardu **WCAG 2.1 úrovně AA** (Web Content Accessibility Guidelines),
- standardu **EN 301 549 V3.2.1** (Accessibility requirements for ICT products and services),
- směrnice **(EU) 2019/882** (European Accessibility Act, EAA), platné od 28. 6. 2025,
- zákona **č. 424/2023 Sb.** o přístupnosti výrobků a služeb (transpozice EAA do české právní úpravy).

## 3. Implementované funkce přístupnosti

3.1 Aplikace je navržena a vyvíjena tak, aby v rámci možností daných její povahou umožňovala zejména:

- **Ovládání klávesnicí** – navigace bez nutnosti polohovacího zařízení; viditelný fokus na interaktivních prvcích.
- **Asistivní technologie** – kompatibilita s běžnými čtečkami obrazovky (VoiceOver na iOS, TalkBack na Androidu, NVDA / JAWS / VoiceOver na webu).
- **Hlasové ovládání** – podpora hlasových asistentů operačního systému.
- **Barevný kontrast** – minimální poměr 4.5:1 pro normální text a 3:1 pro velký text v souladu s WCAG 1.4.3.
- **Zvětšení textu** – respektování nastavení velikosti písma operačního systému; zachování čitelnosti při zvětšení až 200 %.
- **Textové alternativy** – alt texty u obrázků, popisky u ikon, transkripty u audio/video obsahu (postupně doplňováno).
- **Sémantická struktura** – nadpisy, seznamy, landmarky a ARIA atributy v souladu s WAI-ARIA.
- **Adaptivní tempo** – uživatel může upravit tempo interakcí v kvízech a cvičeních; časové limity lze prodloužit nebo vypnout v nastavení.
- **Přizpůsobení obtížnosti** – AI funkce a FSRS opakování přizpůsobují obtížnost individuálním schopnostem uživatele.
- **Redukce pohybu** – respektování preference `prefers-reduced-motion` v operačním systému / prohlížeči.
- **Tmavý režim** – respektování systémového nastavení barevného schématu.

## 4. AI funkce a přístupnost

4.1 Poskytovatel dbá na to, aby AI výstupy byly formulovány srozumitelným jazykem a aby je bylo možné prezentovat ve formátech kompatibilních s asistivními technologiemi.

4.2 AI funkce nesmí být využívány způsobem, který by znevýhodňoval uživatele se zdravotním postižením nebo se specifickými vzdělávacími potřebami. AI asistent je trénován k poskytování výkladů s alternativními příklady, postupným vysvětlením a možností volby formy odpovědi.

## 5. Známé nedostatky a výjimky

5.1 Aktuálně známé oblasti, na jejichž zlepšení pracujeme:

- Některé starší obrázky ve vzdělávacím obsahu nemají kompletní textové alternativy.
- Některé komplexní interaktivní vzdělávací prvky (drag-and-drop kvízy) mají omezenou podporu ovládání pouze klávesnicí — pro tyto úlohy je k dispozici alternativní forma.
- Matematické výrazy generované AI v některých případech nemusí být plně srozumitelné pro čtečky obrazovky bez podpory MathML.
- Některá videa zatím postrádají skryté titulky (CC); titulky jsou doplňovány průběžně.

5.2 Nepřiměřená zátěž (čl. 7 EAA): v současné době neuplatňujeme výjimku „nepřiměřená zátěž" pro žádnou část Aplikace.

## 6. Příprava prohlášení

6.1 Toto prohlášení bylo vypracováno dne 20. 5. 2026 na základě:

- vlastního ověření přístupnosti vývojovým týmem Poskytovatele,
- interních testů s asistivními technologiemi (VoiceOver, TalkBack, NVDA),
- automatizovaných nástrojů (axe-core, Lighthouse, WAVE).

6.2 Plánovaný externí audit přístupnosti: 2026 (přesný termín bude doplněn).

6.3 Prohlášení bude aktualizováno minimálně jednou ročně a vždy po významné změně Aplikace ovlivňující její přístupnost.

## 7. Zpětná vazba a kontakt

7.1 Pokud narazíte na bariéru v přístupnosti naší Aplikace nebo potřebujete informace ve formátu, který Aplikace momentálně nepodporuje, prosíme, kontaktujte nás:

- **E-mail:** [app@edu-ai.eu](mailto:app@edu-ai.eu?subject=Přístupnost) (předmět: „Přístupnost")
- **Telefon:** [(+420) 226 257 206](tel:+420226257206)
- **Adresa:** EDU-AI o.p.s., Husinecká 903/10, 130 00 Praha 3
- **Datová schránka:** ejezs6q

7.2 Na podnět se zavazujeme reagovat **bez zbytečného odkladu, nejpozději do 30 dnů**. Nabídneme přiměřené řešení nebo alternativní způsob přístupu k požadované funkci či obsahu.

## 8. Postup pro vymáhání práva

8.1 Není-li uživatel spokojen s tím, jak Poskytovatel jeho podnět k přístupnosti vyřídil, může se obrátit na příslušný dozorový orgán:

- **Česká obchodní inspekce** – pro výrobky a služby spadající pod EAA / zákon 424/2023 Sb. Adresa: Štěpánská 567/15, 120 00 Praha 2. Web: [www.coi.cz](https://www.coi.cz)
- **Digitální a informační agentura** – pro digitální přístupnost veřejných služeb (přiměřeně). Web: [www.dia.gov.cz](https://www.dia.gov.cz)

## 9. Použité standardy a předpisy

- WCAG 2.1 (Web Content Accessibility Guidelines) – úroveň AA
- EN 301 549 V3.2.1 – evropský harmonizovaný standard přístupnosti ICT
- Směrnice (EU) 2019/882 ze dne 17. 4. 2019 (European Accessibility Act)
- Zákon č. 424/2023 Sb., o přístupnosti výrobků a služeb
- Zákon č. 99/2019 Sb., o přístupnosti internetových stránek a mobilních aplikací (přiměřeně)
- WAI-ARIA 1.2 (Accessible Rich Internet Applications)
