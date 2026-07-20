# Informační list AI systému

*Účinnost od: 20. 5. 2026 · Verze: 1.0 (předběžné znění)*

> **Pozn.:** Konečné znění tohoto informačního listu dodá Poskytovatel. Níže uvedený obsah vychází z požadavků nařízení Evropského parlamentu a Rady **(EU) 2024/1689** („AI Act"), zejména čl. 13 (transparentnost), čl. 14 (lidský dohled), čl. 50 (povinnosti transparentnosti při interakci s AI) a čl. 52 (povinnosti poskytovatelů modelů GPAI), a z interní AI policy Poskytovatele.

## 1. Účel a klasifikace AI systému

1.1 Aplikace EDU AI asistent integruje funkce založené na umělé inteligenci s cílem poskytnout uživateli vzdělávací podporu (vysvětlení, doporučení, odpovědi na dotazy, adaptivní obtížnost cvičení, kontextová nápověda).

1.2 **Klasifikace dle AI Act:** AI funkce Aplikace jsou navrženy a provozovány jako systém umělé inteligence ve smyslu čl. 3 odst. 1 AI Actu. Vzhledem k tomu, že:

- cílovou skupinou jsou žáci a studenti,
- někteří uživatelé jsou děti (zranitelná skupina dle čl. 5 odst. 1 písm. b AI Actu),
- AI je využívána ve **vzdělávacím kontextu**,

Poskytovatel zachovává **nejvyšší úroveň péče**, transparentnosti a lidského dohledu. Aplikace **nepoužívá** AI funkce uvedené v příloze III AI Actu (vysoce rizikové AI systémy ve vzdělávání), zejména:

- nepoužívá AI k **závaznému hodnocení** studijních výsledků nebo k rozhodování o přijetí, postupu či ukončení studia,
- nepoužívá AI k **monitoringu chování** nebo detekci podvádění při zkouškách,
- nepoužívá AI k **biometrické identifikaci** ani k **emoční detekci**.

## 2. Použité AI modely

2.1 Aplikace využívá komerční jazykové modely (LLM) provozované renomovanými poskytovateli v rámci Evropské unie:

| Poskytovatel | Modely | Účel v Aplikaci | Sídlo zpracování |
|---|---|---|---|
| OpenAI Ireland Ltd. | GPT-4o, GPT-4o mini, GPT-4.1 (a nástupci) | AI chat asistent, vysvětlení lekcí, generování zpětné vazby ke kvízům | EU (Irsko); USA via EU–U.S. DPF |
| Anthropic Ireland Ltd. | Claude Sonnet, Claude Haiku (a nástupci) | AI chat asistent, hloubková vysvětlení, alternativní vysvětlení | EU (Irsko); USA via EU–U.S. DPF |
| OpenRouter, Inc. | Routovací proxy na výše uvedené modely (volitelně) | Routování dotazů a load balancing mezi modely | USA; standardní smluvní doložky (SCC) |

2.2 **Vstupy nejsou používány k trénování modelů** – všechny smlouvy s poskytovateli AI obsahují klauzuli zakazující využití dat z Aplikace pro trénování jejich modelů (Zero Data Retention, resp. opt-out z trénování).

2.3 Modely od OpenAI a Anthropic spadají do kategorie **obecných AI modelů (GPAI)** ve smyslu čl. 51 a násl. AI Actu. Tito poskytovatelé jsou povinni publikovat technickou dokumentaci, shrnutí trénovacích dat a zajistit soulad s autorskoprávními předpisy.

## 3. AI funkce v Aplikaci

### 3.1 AI mentor (Chat)

Konverzační AI asistent dostupný v sekci Chat. Odpovídá na vzdělávací dotazy, vysvětluje pojmy, navrhuje studijní postupy. Zřetelně označen jako AI v souladu s čl. 50 AI Actu.

### 3.2 Vysvětlení odpovědí v kvízech

Po dokončení kvízu může AI vygenerovat hloubkové vysvětlení správné odpovědi, alternativní postup nebo příklad. AI výstupy jsou označeny ikonou a popiskem.

### 3.3 Adaptivní obtížnost (FSRS)

Algoritmus rozloženého opakování (Free Spaced Repetition Scheduler, FSRS) adaptivně upravuje frekvenci opakování kartiček podle individuální paměťové křivky uživatele. Nejedná se o generativní AI, ale o statistický model.

### 3.4 Doporučení dalšího obsahu

Na základě dokončených lekcí a kvízů Aplikace doporučuje další lekce. Doporučení je generováno deterministickou logikou (pravidlově), nikoliv neuronovou sítí.

## 4. Vstupy, výstupy a zpracování dat

4.1 **Vstupy** do AI funkcí:

- uživatelský prompt (text otázky či zadání) – v případě chatu,
- kontext lekce/kvízu (otázka, správná odpověď, odpověď uživatele) – v případě vysvětlení,
- systémový prompt Poskytovatele (instrukce, bezpečnostní filtry, persona AI mentora).

4.2 **Výstupy** jsou textové (vysvětlení, odpověď, doporučení) případně strukturované (JSON pro doporučení).

4.3 **Zpracování:**

- Vstupy jsou předány AI poskytovateli přes šifrované spojení (TLS 1.3).
- Vstupy a výstupy jsou v naší infrastruktuře uchovávány po dobu **maximálně 90 dnů** pro účely bezpečnosti, ladění a kontroly kvality, poté jsou anonymizovány nebo smazány.
- Uživatel je opakovaně upozorňován, aby do AI funkcí nevkládal citlivé osobní údaje (Podmínky čl. 7.6).

## 5. Lidský dohled (čl. 14 AI Act)

5.1 Poskytovatel zajišťuje **lidský dohled** nad AI funkcemi následujícími způsoby:

- Vývojový tým průběžně reviduje vzorky AI výstupů a opravuje systémové prompty.
- Uživatelé mohou nahlásit nevhodný AI výstup pomocí tlačítka „Nahlásit" u každé odpovědi AI.
- Pedagogický tým Poskytovatele vyhodnocuje statistiky chybnosti AI odpovědí a iteruje obsah.
- Uživatel má právo požádat o **lidský přezkum** jakéhokoliv AI vyhodnocení, které se ho významně dotýká, na [app@edu-ai.eu](mailto:app@edu-ai.eu). Vyřízení do 30 dnů.

5.2 **AI nenahrazuje učitele.** Pedagogické rozhodnutí o uživateli vždy přijímá učitel nebo vzdělávací instituce.

## 6. Omezení a rizika

6.1 AI funkce mohou generovat **nepřesné, neúplné, zastaralé nebo nevhodné odpovědi** („halucinace"). Toto je vlastní povaze velkých jazykových modelů a Poskytovatel toto riziko nemůže zcela eliminovat.

6.2 Konkrétní omezení:

- **Faktická přesnost:** AI může uvádět nesprávná fakta zejména u úzce specializovaných nebo aktuálních témat. Datum trénovacího cut-offu se u jednotlivých modelů liší.
- **Matematika a logika:** u složitějších matematických úloh může AI udělat chybu v mezikroku.
- **Jazyk:** AI primárně optimalizována pro češtinu a angličtinu; v jiných jazycích může být kvalita nižší.
- **Pedagogická vhodnost:** AI se snaží přizpůsobit věku uživatele, ale v ojedinělých případech může poskytnout obsah, který není pro daný věk vhodný.
- **Bias:** AI modely mohou v důsledku trénovacích dat vykazovat předsudky. Poskytovatel průběžně vyhodnocuje a mitiguje známé biasy.

6.3 **Uživatel je povinen AI výstupy vždy přiměřeně ověřit**, zejména pokud mají být použity při studiu, odevzdání školní práce, hodnocení nebo v jiné významné situaci (Podmínky čl. 7.5).

## 7. Opatření pro ochranu dětí a zranitelných uživatelů

7.1 V souladu s čl. 5 odst. 1 písm. b AI Actu (zákaz zneužití zranitelnosti dětí) a čl. 5 odst. 1 písm. a (zákaz manipulativních technik) Poskytovatel zajišťuje:

- AI mentor používá **věkově přiměřený jazyk** a tón, přizpůsobený vzdělávací úrovni uživatele.
- AI **nepoužívá manipulativní techniky** ani persuasive design ke zvýšení času stráveného v Aplikaci.
- AI je instruována **odmítnout odpovědi** na témata nevhodná pro dětský věk (násilí, sebepoškozování, sexuálně explicitní obsah, návody na nelegální činnost) a doporučit kontakt s dospělou osobou nebo odbornou pomocí.
- AI je instruována **doporučit krizovou linku** (např. [Linka bezpečí 116 111](https://www.linkabezpeci.cz)) v případě indikací duševní tísně.
- Ve školním režimu má vzdělávací instituce možnost AI funkce **úplně deaktivovat**.
- Plný přístup k AI je k dispozici pouze uživatelům starším **15 let** (Podmínky čl. 4).

## 8. Práva uživatele ve vztahu k AI

8.1 **Právo na transparentnost** (čl. 50 AI Act): AI výstupy jsou v Aplikaci jasně označeny jako vytvořené umělou inteligencí.

8.2 **Právo vypnout AI**: AI funkce lze kdykoli vypnout v Nastavení Aplikace. Aplikaci je možné plně používat bez AI asistence.

8.3 **Právo na lidský přezkum** (čl. 14 AI Act): při AI vyhodnocení, které se uživatele významně dotýká, lze požádat o přezkum člověkem na [app@edu-ai.eu](mailto:app@edu-ai.eu).

8.4 **Právo nahlásit nevhodný výstup**: pomocí tlačítka „Nahlásit" u každé AI odpovědi nebo na [app@edu-ai.eu](mailto:app@edu-ai.eu).

8.5 **Právo na vymazání vstupů**: viz [Zásady zpracování osobních údajů](/privacy).

## 9. Změny tohoto informačního listu

9.1 Tento informační list můžeme aktualizovat zejména při změně použitých AI modelů, AI funkcí nebo regulace. Aktuální znění bude vždy dostupné na [app.edu-ai.eu/ai](https://app.edu-ai.eu/ai).

9.2 O podstatných změnách informujeme uživatele v Aplikaci nejméně 30 dní předem.

## 10. Kontakt

Dotazy k AI funkcím a tomuto informačnímu listu: [app@edu-ai.eu](mailto:app@edu-ai.eu).
Žádosti o lidský přezkum AI vyhodnocení: [app@edu-ai.eu](mailto:app@edu-ai.eu) (předmět „Lidský přezkum AI").
Otázky ke zpracování osobních údajů AI funkcemi: [gdpr@edu-ai.eu](mailto:gdpr@edu-ai.eu).
