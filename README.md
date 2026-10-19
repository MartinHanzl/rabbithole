# Rabbithole

iOS aplikace, která nahrazuje bezduché scrollování krátkými a zajímavými články z české Wikipedie podle zájmů uživatele.

**Fáze 1** (hotovo): onboarding s výběrem témat, personalizovaný feed, čtečka článků, uložené články, nastavení a licence. Bez účtů, všechna data zůstávají v zařízení.

## Požadavky

- Xcode 26.1+
- iOS 17.0+ (iPhone i iPad)
- Žádné externí závislosti

## Spuštění

1. Otevři `rabbithole.xcodeproj` v Xcode, vyber scheme **rabbithole** a simulátor iPhone a spusť ho (⌘R).
2. Před vydáním nastav kontaktní e-mail pro User-Agent v `rabbithole/Config/AppConfig.swift` (`contactEmail`). Wikimedia ho vyžaduje podle [User-Agent policy](https://meta.wikimedia.org/wiki/User-Agent_policy).

Z příkazové řádky:

```sh
# Pokud `xcode-select -p` ukazuje na CommandLineTools:
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

xcodebuild -project rabbithole.xcodeproj -scheme rabbithole \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

xcodebuild -project rabbithole.xcodeproj -scheme rabbithole \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

### Ladicí launch argumenty (jen DEBUG)

| Argument | Efekt |
|---|---|
| `-demoTopics space,history,biology` | přeskočí onboarding s vybranými tématy |
| `-demoArticle "Mars (planeta)"` | otevře rovnou čtečku daného článku |

## Kde upravit mapování témat na kategorie

Všechno je v jednom souboru: **`rabbithole/Config/TopicCatalog.swift`**.

```swift
Topic(
    id: "space",                 // trvalý identifikátor, nepřejmenovávat (ukládá se výběr a váha)
    name: "Vesmír",              // název v UI, automaticky v String Catalogu
    symbol: "sparkles",          // SF Symbol
    categories: ["Vesmír", "Astronomie", "Kosmologie", "Planety", "Kosmonautika"]
)
```

- Kategorie se píšou **bez** prefixu `Kategorie:`, přesně podle názvu na cs.wikipedia.org.
- Podkategorie se procházejí automaticky do hloubky 2 (`ArticlePool.Configuration.maxDepth`), nejvýš 60 kategorií na téma.
- Po změně seznamu kategorií se mezipaměť tématu sama zahodí a vytvoří znovu.
- Nové téma stačí přidat do pole `all`. Jeho název se po buildu v Xcode objeví v `Localizable.xcstrings`.

## Architektura

MVVM s `@Observable` view modely, async/await a SwiftData. Služby jsou za protokoly a předávají se přes `AppServices` v `EnvironmentValues`, takže se v testech dají nahradit.

```
rabbithole/
  App/            RabbitholeApp, RootView (onboarding ↔ taby), AppServices, Theme
  Config/         TopicCatalog (témata → kategorie), AppConfig (User-Agent, limity, klíče nastavení)
  Models/         doménové structy (ArticleSummary, ArticleContent, Topic),
                  SwiftData modely (TopicPreference, SeenArticle, SavedArticle) a repozitáře
  Services/
    Wikipedia/    WikipediaClient (HTTP), WikipediaParser + DTO, ArticleFilter, ArticlePool (procházení kategorií)
    Feed/         FeedLoader (téma → vhodný článek)
    Personalization/ PersonalizationEngine, DailyReadingCounter
  Features/       Onboarding, Feed, ArticleDetail, Saved, Settings, Topics, Shared
  Resources/      Localizable.xcstrings (zdrojový jazyk čeština)
rabbitholeTests/  Swift Testing + JSON fixtures zachycené z reálného API
```

### Tok dat ve feedu

1. `FeedViewModel` si od `PersonalizationEngine` nechá vylosovat téma pro další kartu.
2. `FeedLoader` vezme z `ArticlePool` náhodný ještě neviděný článek daného tématu.
3. Pro tento článek stáhne shrnutí přes REST `page/summary/{title}`.
4. `ArticleFilter` vyřadí rozcestníky, seznamy, články bez úvodu a články s úvodem kratším než 200 znaků. Vyřazené články si pool pamatuje a už je nestahuje.
5. Karty se načítají v dávkách po 5 paralelně. Další dávka se začne načítat, když uživateli zbývají 3 karty do konce.
6. Když se karta zobrazí, uloží se do `SeenArticle`, takže se nikdy nezobrazí znovu. Zároveň se zvýší denní počítadlo.

### Wikipedia API

- **REST API** `https://cs.wikipedia.org/api/rest_v1/page/summary/{title}` dodává obsah karet.
- **Action API** `https://cs.wikipedia.org/w/api.php` se používá na dvě věci:
  - `list=categorymembers` vypisuje členy kategorií (stránky i podkategorie, `cmlimit=200`, s pokračováním);
  - `prop=extracts&explaintext=1` dodává plný text pro nativní čtečku. Sekce jako Reference nebo Externí odkazy se vynechávají.
- Každý požadavek nese User-Agent `Rabbithole/<verze> (iOS; <e-mail>)`.

**Cache:**

- `URLCache` (200 MB na disku) respektuje cache hlavičky REST API.
- Action API cachovat nedovoluje (`max-age=0`). Seznamy článků v kategoriích se proto ukládají jako JSON v `Caches/TopicPools` s platností 7 dní.
- Kategorie se procházejí líně, jen dokud není v zásobě aspoň 15 neviděných článků. První karta je tak k dispozici po 1–2 požadavcích.

### Personalizace

Logika je v `Services/Personalization/PersonalizationEngine.swift`. Je to čistý struct bez I/O s injektovaným generátorem náhody a pokrývají ho unit testy.

| Signál | Změna váhy |
|---|---|
| Uložení článku | +0.3 |
| Čtení v detailu ≥ 30 s (jen čas na popředí) | +0.2 |
| „Nezajímá mě“ | −0.3 |

- Výchozí váha je 1.0 a pohybuje se v rozsahu 0.1–5.0.
- Téma se losuje náhodně, s pravděpodobností úměrnou váze.
- Každá 10. karta je z tématu, které uživatel nemá vybrané. V UI je označená „Mimo tvá témata“.
- Váhy jde v Nastavení vrátit na výchozí hodnotu.

### Pauza

`DailyReadingCounter` počítá karty zobrazené za den a o půlnoci se nuluje. Po každých N kartách (výchozí 20, nastavitelné, 0 = vypnuto) se ve feedu objeví karta s nabídkou pauzy.

### Licence a uvedení zdroje

- Každá karta i detail článku ukazuje „Zdroj: Wikipedie“ (odkaz na článek) a odkaz na CC BY-SA 4.0.
- U obrázků je odkaz „Obrázek: autor a licence“ na stránku `Soubor:…`. Ta přesměruje na Wikimedia Commons, kde je licence uvedená.
- Obrazovka *Nastavení → O aplikaci a licence* shrnuje licence, zdroj dat a soukromí.

### Lokalizace a přístupnost

- Všechny texty jsou v `Localizable.xcstrings` (zdrojový jazyk `cs`), včetně českých plurálů.
- Barvy používají sémantické systémové barvy a `AccentColor` s tmavou variantou.
- Písmo je Dynamic Type. Při velkých velikostech se řádky tlačítek a uvedení zdroje zalomí pod sebe.

## Testy

46 testů (Swift Testing) pokrývá:

- parsování odpovědí API (summary, categorymembers, extracts, názvy souborů obrázků) na fixtures z reálného API;
- `ArticleFilter`;
- `PersonalizationEngine` (váhy, rozsahy, rozložení losování, explorační sloty);
- `ArticlePool` (hloubka procházení, pokračování, TTL, zneplatnění, chyby);
- `FeedLoader` a `DailyReadingCounter`.

## Tajemství

Repozitář neobsahuje žádné klíče. Soubory `Secrets.xcconfig`, `*.xcconfig.local` a `.env` jsou v `.gitignore` a jsou připravené pro Supabase klíče ve Fázi 2.
