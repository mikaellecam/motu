# Offline QA script

The manual check of BRIEF §6.4 (everything readable offline), on a phone or an emulator. Run it before a
release, and whenever a change touches caching, a repository or a screen that shows prices.
`app/test/offline_test.dart` runs the same walk on every CI build, with a fake backend. This script covers
what that test cannot: the real plugin reporting airplane mode, a real process kill, and the screens as a
person sees them.

## Setup (online)

1. Install a build that points at a running backend (`--dart-define=BACKEND_URL=…`).
2. Answer the questionnaire, or open the app on a profile that already has.
3. Open each of these once, so they reach the cache:
   - an island and one of its lessons;
   - **Portefeuille**: the live portfolio, then a time-trip (create one if there is none);
   - **Explorer**: the list, then one asset;
   - **Glossaire**: one term;
   - **Simulateur DCA**: run a simulation and save it.
4. Buy one share of any asset in the live portfolio. Note what the screen shows: cash, position, value.

## Going offline

1. Kill the app: swipe it out of the recent apps, or force-stop it in the system settings.
2. Turn on airplane mode. On an emulator, also turn off Wi-Fi and mobile data in its settings.
3. Launch the app again.

## Checks

Every row must hold. A failed row is a bug: note the step, the screen and what it showed.

The **offline banner** is the line « Hors connexion. Tu vois les cours du {date}, {time}. » (en: "Offline.
You're seeing prices from {date}, {time}."). Its date and time are those of the last successful price fetch,
in local time.

| # | Where | Do | Expected |
|---|---|---|---|
| 1 | Launch | Open the app | It opens on **Carte** with no spinner that never ends and no error. |
| 2 | Carte | Look at the map | The island and its buildings as before going offline; the next-step card; the islands count and level. |
| 3 | Carte → island | Open the Actions & ETF island, then a lesson | The path and the lesson play in full: their data ships with the app. |
| 4 | Portefeuille | Open the tab | The wallets list: the live portfolio and the trips, each with a value. |
| 5 | Live portfolio | Open it | The offline banner. Cash, positions, value and chart as noted in setup step 4 (the value may differ: it uses the last cached prices). |
| 6 | Live portfolio | Pull to refresh | The banner stays; nothing else changes; no error. |
| 7 | Live portfolio → asset → **Acheter** | Place a market order | If the market is open, the sheet says « Pas de cours à jour : ton ordre partira à la prochaine ouverture, le {day} à {time}. »; if it is closed, « … est fermé. Ton ordre partira à l'ouverture… ». After **Acheter**: « Ordre envoyé : il partira à l'ouverture… », and the order shows under « Ordres en attente ». Nothing fills; the cash it holds back is no longer available. |
| 8 | « Voir l'ordre » | Open the order | Sent at the time placed; next step « Ouverture du marché » at the session it waits for. |
| 9 | Trip | Open a trip, then **+1 jour**; then **Avancer jusqu'à…** a date past the last close, e.g. yesterday | The trip moves on while the cached history covers the next day. Past the cached history, the trip stays where it was, with « Pas de données disponibles au {date}. », or « Impossible de joindre le serveur. Vérifie ta connexion. » when the step needs data never fetched (a market calendar year, exchange rates). |
| 10 | Explorer | Open the tab | The offline banner; the list with each asset's figures. An asset never opened online may show its row without figures. |
| 11 | Explorer → asset | Open the asset opened in setup | The offline banner; price, chart and figures. |
| 12 | Glossaire | Open the tab, then a term | Every term reads in full: the glossary ships with the app. |
| 13 | Simulateur DCA | Open it from **Portefeuille** | The form; « Tes simulations » lists the one saved in setup, with its result. |
| 14 | Réglages | Open them from **Carte**, then « Actualiser maintenant » | Every setting shows and changes. « Les cours seront mis à jour à la prochaine lecture. »; the live portfolio still shows its prices, with the offline banner. Leave « Vider le cache » alone: it deletes what offline mode reads. |

## Back online

| # | Do | Expected |
|---|---|---|
| 15 | Turn airplane mode off, then pull to refresh on the live portfolio | The banner goes away once prices are fetched. |
| 16 | Wait until after the session the order of row 7 waited for has closed, then open the app | The order shows « Exécuté » at that session's opening price; the position and the cash reflect it. |

## Record

Add a line to the issue or the PR: date, device (model, OS version), app commit, each row passed or the
row that failed and what it showed.
