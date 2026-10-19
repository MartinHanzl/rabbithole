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
| `-demoVideo M7lc1UVf-VE` | otevře přehrávač s daným videem (nepotřebuje API klíč) |
| `-demoTab settings` | otevře danou záložku (`feed`, `friends`, `saved`, `settings`) |

## YouTube videa ve feedu

Ve feedu jsou mezi články i krátká naučná videa z YouTube. Výchozí poměr je zhruba každá 4. karta. Poměr jde v Nastavení změnit a videa se dají i úplně vypnout. Videa se přehrávají jen v oficiálním vloženém přehrávači YouTube (IFrame Player API ve WKWebView). Přehrávač se nijak neupravuje a nic se nespouští automaticky.

### Kanály

Kanály se nastavují v souboru **`rabbithole/Config/VideoChannelCatalog.swift`**, který leží vedle `TopicCatalog.swift`. Pro každé téma je tam seznam kanálů:

```swift
"space": [
    .handle("@nazevkanalu"),            // z adresy youtube.com/@nazevkanalu
    .id("UCxxxxxxxxxxxxxxxxxxxxxx"),    // ID kanálu, levnější na kvótu
],
```

- Témata bez kanálů dostanou na místě videa článek.
- Zobrazují se jen veřejná a dokončená videa, která jde vložit do jiných stránek. Vynechávají se živá vysílání, věkově omezená videa a videa mimo `durationRange` (výchozí aspoň 1 minuta, bez horního limitu).

### API klíč (vývoj)

1. V Google Cloud Console otevři *APIs & Services* a povol **YouTube Data API v3**. Pak v *Credentials* vytvoř **API key**.
2. Klíč omez: v *Application restrictions* zvol **iOS apps** s bundle ID `webpulse.rabbithole`, v *API restrictions* povol jen **YouTube Data API v3**. Aplikace posílá hlavičku `X-Ios-Bundle-Identifier`.
3. Klíč zapiš do `Config/Secrets.xcconfig` (je v `.gitignore`) jako `YOUTUBE_API_KEY = …`. Vzor najdeš v `Config/Secrets.example.xcconfig`. Bez klíče se videa nezobrazují.

### Kvóta a podmínky YouTube API

- Aplikace používá jen `channels.list`, `playlistItems.list` (playlist nahraných videí) a `videos.list`. Každý z nich stojí 1 jednotku kvóty. `search.list` za 100 jednotek se nepoužívá.
- Seznam videí jednoho tématu se obnovuje jednou za 24 hodin. Stojí to zhruba 3 jednotky na kanál a uživatele, výchozí kvóta je 10 000 jednotek denně na projekt.
- **Ukládá se jen nezbytné minimum:** ID, název, název kanálu, délka a URL náhledu.
- Údaje starší 30 dní se mažou, i když je zařízení offline (YouTube API Developer Policies). U uložených videí se údaje obnovují po 7 dnech, a když obnovení do 30 dnů neprojde, video se ze seznamu uložených odebere.
- **Ověř si:** 30denní lhůtu pro „API Data“ jsem převzal z Developer Policies. Nejsem si jistý, jestli se smí trvale uchovávat aspoň samotné ID videa. Proto se mažou i ID.
- Obrazovka *O aplikaci a licence* odkazuje na [podmínky YouTube](https://www.youtube.com/t/terms) a [zásady ochrany soukromí Google](https://policies.google.com/privacy).

### Návrh: přesun YouTube API na backend (zatím neimplementováno)

Klíč je teď v aplikaci, takže se dá z binárky vytáhnout a všichni uživatelé čerpají ze stejné kvóty. Návrh:

1. **Edge Function `youtube-videos`** (Supabase): `GET ?topic=space&exclude=<id,…>` vrátí seznam videí ve stejném tvaru jako `YouTubeVideo`. Klíč bude v Supabase Secrets (`YOUTUBE_API_KEY`), omezený na *API restrictions*. Aplikační omezení iOS tam nejde použít, volá se ze serveru.
2. **Sdílená cache** v tabulce `video_cache (topic_id, video_id, title, channel_title, duration, thumbnail_url, fetched_at)`:
   - plní ji `pg_cron` jednou denně pro každé téma;
   - záznamy starší 30 dní maže stejný cron;
   - kvóta pak závisí na počtu kanálů, ne na počtu uživatelů.
3. **Seznam kanálů** se přesune do tabulky `video_channels (topic_id, channel_ref)`, kterou spravuje admin. `VideoChannelCatalog.swift` zůstane jako výchozí seed.
4. **Přístup:**
   - funkce půjde volat publishable klíčem i bez přihlášení, protože feed funguje bez účtu;
   - omezení počtu požadavků na IP adresu nebo zařízení;
   - RLS: `video_cache` čte jen funkce (service role), klient tabulku nevidí.
5. **V aplikaci** se `YouTubeClient` nahradí implementací `YouTubeService`, která volá funkci. `VideoPool` a celý zbytek zůstanou beze změny, protože protokol je stejný.

## Fáze 2: přátelé, sdílení, výzvy

- **Backend** běží na Supabase (free tier). Schéma je v `supabase/migrations/`, testy RLS v pgTAP v `supabase/tests/database/` (`npx supabase test db`).
- **Sdílení a chat:**
  - článek se pošle příteli s volitelnou zprávou;
  - ke každému sdílení patří chat;
  - realtime běží jen pro otevřený chat;
  - seznamy se stránkují po 20 položkách.
- **Výzvy:**
  - otázka k článku se třemi možnostmi nebo otevřená otázka;
  - zapisuje se jen přes RPC `create_challenge` a `answer_challenge`;
  - správná odpověď je v tabulce `challenge_solutions`, kterou příjemce vidí až po své odpovědi;
  - výzvy jde v Nastavení vypnout.
- **Hotové otázky** poskytuje Edge Function `article-questions`: nejdřív šablony z Wikidat, a když nic nevyjde, Gemini z úvodu článku. Výsledek se ukládá do sdílené cache `article_questions`.
  - Tajné proměnné: `npx supabase secrets set GEMINI_API_KEY=…`, volitelně `GEMINI_MODEL` (výchozí `gemini-3.1-flash-lite`).
  - Testy: `docker run --rm -v "$PWD/supabase/functions/article-questions:/app:ro" -w /app denoland/deno:2.1.4 test --no-prompt questions_test.ts`
- **Notifikace bez APNs:** push vyžaduje placený Apple Developer účet. Místo něj iOS občas probudí aplikaci na pozadí (Background App Refresh, `ActivityNotifier`). Aplikace se zeptá na novinky a zobrazí lokální notifikaci.
  - Notifikace může přijít se zpožděním a doručení není zaručené.
  - Zprávy se v notifikacích kvůli soukromí nezobrazují, ukazuje se jen otázka výzvy.
  - Na záložce „Od přátel“ je odznak s počtem novinek.
- **Smazání účtu** řeší Edge Function `delete-account`. Integrační test: `bash supabase/tests/functions/delete-account.sh`.

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
