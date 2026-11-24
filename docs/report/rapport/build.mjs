// Builds docs/report/rapport.docx, the school report, in French.
// Needs node, the packages in package.json (npm install) and ImageMagick (`magick`).
//   cd docs/report/rapport && npm install && npm run diagrams && npm run build
import { writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  AlignmentType, Document, Footer, LevelFormat, Packer, PageNumber, Paragraph,
  TableOfContents, TextRun,
} from 'docx';
import {
  C, FONT, H1, H2, H3, P, bullets, code, fr, note, screens, spacer, table, wideFigure,
} from './lib.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const shots = join(here, '../../screenshots');
const diag = (f) => join(here, 'diagrams', f);
const shot = (f) => join(shots, f);

// Cover ---------------------------------------------------------------------

const cover = [
  new Paragraph({ children: [], spacing: { before: 1600 } }),
  new Paragraph({ children: [new TextRun({ text: 'Motu', font: FONT, size: 96, bold: true, color: C.ink })], alignment: AlignmentType.CENTER }),
  new Paragraph({
    children: [new TextRun({ text: fr('Apprendre à investir sur des données réelles, sans argent réel'), size: 30, color: C.primary })],
    alignment: AlignmentType.CENTER, spacing: { after: 480 },
  }),
  ...wideFigure(shot('m13-2-district-12.png'), '', { maxCm: 9, numbered: false }),
  new Paragraph({ children: [new TextRun({ text: fr("Actions & ETF, l'île des leçons sur la bourse, une fois ses douze leçons faites"), size: 16, color: C.muted, italics: true })], alignment: AlignmentType.CENTER }),
  new Paragraph({ children: [], spacing: { before: 600 } }),
  new Paragraph({ children: [new TextRun({ text: 'Rapport de projet', size: 32, bold: true, color: C.ink })], alignment: AlignmentType.CENTER }),
  new Paragraph({ children: [new TextRun({ text: fr('Module de développement mobile · INSA'), size: 24, color: C.muted })], alignment: AlignmentType.CENTER, spacing: { after: 120 } }),
  new Paragraph({ children: [new TextRun({ text: 'Novembre 2026', size: 24, color: C.muted })], alignment: AlignmentType.CENTER, spacing: { after: 120 } }),
  new Paragraph({ children: [new TextRun({ text: fr('Auteur : à compléter'), size: 24, color: C.muted, highlight: 'yellow' })], alignment: AlignmentType.CENTER }),
];

const contents = [
  new Paragraph({ children: [new TextRun({ text: 'Sommaire', size: 32, bold: true, color: C.ink })], spacing: { after: 240 } }),
  new TableOfContents('Sommaire', { hyperlink: true, headingStyleRange: '1-2' }),
  P("Le sommaire se remplit à l'ouverture dans Word (accepter la mise à jour des champs), ou par clic droit, « Mettre à jour les champs ».", { run: { size: 16, color: C.muted, italics: true } }),
];

// 1. Le projet ----------------------------------------------------------------

const projet = [
  H1('1. Le projet'),
  H2('1.1 Le problème et la personne visée'),
  P("Motu s'adresse aux débutants français de 18 à 30 ans dont l'épargne dort sur un Livret A ou un compte courant et qui n'ont jamais investi. Pour eux, investir paraît risqué et opaque ; les cours théoriques ennuient ; les applications de courtage intimident. Beaucoup prennent le Livret A pour un placement. L'objectif est de leur faire **apprendre en manipulant des données réelles, sans argent réel**."),
  P("Deux principes tiennent toute l'application : aucun argent réel ni aucune connexion à un courtier ou à une banque, jamais ; et rien de ce qu'elle affiche n'est un conseil ou une prévision. Les textes décrivent ce qui s'est passé, jamais ce qui va se passer."),
  H2('1.2 Le concept : deux moitiés qui ne se bloquent jamais'),
  table(['Moitié', 'Ce que c’est', 'Données', 'Verrouillée ?'], [
    ['**Les îles** (les leçons)', 'Un archipel, une île par domaine. Chaque île est un parcours de courts exercices interactifs (« nœuds ») et de missions, chaque leçon construisant un bâtiment de l’île.', 'Des données historiques réelles, figées dans des packs de contenu. Déterministe.', 'Les leçons s’ouvrent dans l’ordre, à l’intérieur d’une île.'],
    ['**Le bac à sable**', 'Des portefeuilles fictifs : un portefeuille **live** aux prix du jour, et autant de **voyages dans le temps** qu’on veut, qui partent d’une date passée et avancent dans l’histoire réelle. Un simulateur de DCA.', 'Les cours réels du marché, servis par notre backend et gardés en cache sur le téléphone.', 'Jamais.'],
  ], [1.2, 3, 2.2, 1.6]),
  spacer(),
  P("Des ponts relient les deux moitiés. Une leçon peut se terminer par « Rejoue-le toi-même », qui ouvre l'assistant de voyage déjà rempli : après « Mars 2020 : vendre ou tenir ? », un voyage qui part le 18 février 2020. Inversement, certaines leçons sont des **missions** qui se valident toutes seules quand le portefeuille live les remplit (posséder un ETF, couvrir trois zones géographiques, mettre en place un DCA)."),
  H2('1.3 Les objectifs'),
  ...bullets([
    "**Pédagogiques** : faire comprendre la diversification, la volatilité, les frais, le risque de change, l'inflation, les intérêts composés, l'investissement programmé, sur des épisodes réels (2008, mars 2020, 2022) plutôt que sur des exemples inventés.",
    "**Techniques** : couvrir toutes les exigences du sujet (section 2.2) avec une architecture qui se justifie : des couches séparées, des calculs exacts sur l'argent, un cache qui fait marcher l'application hors ligne, et des tests sur toute la logique métier.",
    "**De confiance** : aucune donnée « du futur » ne peut atteindre un voyage dans le temps (pas d'anticipation), et chaque chiffre affiché vient de cours réels, datés et sourcés.",
  ]),
  H2('1.4 Hors périmètre de la V1'),
  P("Le vrai courtage, les comptes et la connexion, la synchronisation entre appareils, tout aspect social ou compétitif (pas de classement), les cryptomonnaies, l'immobilier, une île de trading, les notifications, et le classement des actifs. Un score explicable par actif est en revanche présent (« Stabilité passée », section 11), mais l'application ne trie ni ne classe jamais les actifs avec."),
];

// 2. Fonctionnalités --------------------------------------------------------------

const fonctionnalites = [
  H1('2. Les fonctionnalités'),
  H2('2.1 Prévues et réalisées'),
  P("Le plan d'origine (`docs/ROADMAP.md`) découpait la V1 en dix jalons, M0 à M9. Le projet en a compté quatorze : M10 à M13 sont venus ensuite (la publication, le « monde » sur chaque onglet, l'île Les bases, les îles en gros plan). **158 tickets**, tous terminés, chacun sur sa branche et sa pull request."),
  table(['Fonctionnalité', 'Prévue', 'État'], [
    ['Questionnaire d’accueil : quatre questions qui choisissent le point de départ et le niveau d’interface', 'M6', 'Réalisé ; une cinquième question retirée en M13'],
    ['Île **Actions & ETF** : 12 leçons (prédire puis révéler, jouets, décisions, classements, puzzles, missions, point d’étape)', 'M6', 'Réalisé'],
    ['Île **Les bases** : 9 leçons (matelas de sécurité, inflation, crédit, arnaques), qui ouvre Actions & ETF', 'Non prévue', 'Ajoutée en M12'],
    ['Les îles dessinées en code, une leçon = un bâtiment ; la carte marine pour naviguer', 'M7 (une carte)', 'Réalisé, refait en M13 : chaque île en gros plan'],
    ['Leçons en cartes : un exemple chiffré, une comparaison, une vérification rapide', 'Non prévue', 'Ajoutée en M13'],
    ['Portefeuille live : 50 000 € fictifs, positions, graphique, répartition, comparaison à l’ETF Monde', 'M4', 'Réalisé'],
    ['Ordres au marché, à cours limité, stop ; frais ; validation', 'M4', 'Réalisé'],
    ['Voyages dans le temps : assistant en trois étapes, avancée par jour, semaine, mois, arrêts automatiques, bilan, journal', 'M5', 'Réalisé ; un voyage qui atteint aujourd’hui continue au rythme réel (M9)'],
    ['Simulateur de DCA, et plans DCA dans un portefeuille', 'M8', 'Réalisé ; les plans ajoutés en M9'],
    ['Livret A simulé, avec ses taux et plafonds historiques et ses intérêts par quinzaine', 'M8', 'Réalisé'],
    ['Compagnon : des « moments » qui expliquent ce qui arrive au portefeuille', 'M8', 'Réalisé'],
    ['Glossaire : 30 notions, exemples sur données réelles, mini-quiz', 'M6', 'Réalisé'],
    ['Explorer : catalogue de 29 actifs, recherche, filtres, favoris ; page d’un actif', 'M4', 'Réalisé ; « Stabilité passée » ajoutée en M9'],
    ['Mode hors ligne partiel, bandeau de données anciennes', 'M3, M9', 'Réalisé ; pause du backend injoignable en M13'],
    ['Français et anglais ; accessibilité (texte à 130 %, cibles de 44 px, libellés)', 'M9', 'Réalisé'],
    ['Backend Go : historique des cours, cotations, calendrier, taux du Livret, packs de contenu ; image Docker', 'M2', 'Réalisé ; image publiée en M10'],
    ['Îles Trading, Immobilier, Crypto', 'Visibles, « Bientôt »', 'Non écrites (après la V1) ; leurs conditions d’ouverture sont déjà fixées'],
  ], [5, 1.4, 2.6]),
  spacer(),
  H2('2.2 Les exigences du sujet'),
  P('Chaque exigence du sujet, et où elle se trouve dans l’application :'),
  table(['Exigence', 'Dans Motu'], [
    ['Au moins 3 écrans et une navigation', 'Quatre onglets (Archipel, Portefeuille, Explorer, Glossaire) et des parcours : page d’un actif, ordre, assistant de voyage, lecteur de leçon, carte marine, réglages ; `go_router`, liens profonds'],
    ['Un formulaire avec validation', 'Ordre (montant, liquidités, quantité entière…), assistant de voyage (date, nom, paramètres), questionnaire, simulateur de DCA, versement sur le Livret'],
    ['Une liste dynamique', 'Catalogue de l’Explorer, positions, glossaire, liste des portefeuilles'],
    ['Au moins une API REST, JSON vers objets Dart', 'Notre backend (`/v1/…`) et Frankfurter, appelé directement ; DTO générés par `json_serializable`'],
    ['Persistance des données métier', 'drift (SQLite) : portefeuilles, ordres, exécutions, journal, profil, progression, favoris, simulations'],
    ['Cache local des données d’API', 'Historique incrémental, cotations, taux de change, calendrier, catalogue, packs (section 7)'],
    ['Mode hors ligne partiel', 'Tout se lit hors ligne ; bandeau avec la date des derniers cours'],
    ['États chargement / données / erreur explicites', '`AsyncValue` partout, avec des widgets partagés : squelette, erreur avec « Réessayer », bandeau'],
    ['Au moins un graphique utile', 'Cours d’un actif, valeur d’un portefeuille, courbes des leçons, répartition, volatilité jour par jour'],
    ['Au moins 2 calculs métier', 'Quinze, en section 9 : valorisation, plus-values, rendement pondéré dans le temps, volatilité, pire baisse, décomposition d’un mouvement, DCA, intérêts du Livret…'],
    ['Au moins 3 animations, dont 2 codées à la main', 'Section 10 : trois codées à la main pour l’exigence, d’autres encore sur les îles, et celles de fl_chart'],
    ['Tests unitaires de la logique métier', '1 353 tests dans l’application, dont 465 sur le domaine pur ; 131 tests côté backend (section 12)'],
    ['Un rapport qui justifie l’architecture, l’état, la persistance et le cache', 'Ce document, sections 4 à 7, et les ADR en annexe'],
  ], [2.2, 5]),
  H2('2.3 Le déroulement'),
  table(['Jalon', 'Contenu', 'Tickets'], [
    ['M0', 'Fondations : projet, jetons du thème, localisation, premières ADR', '4'],
    ['M1', 'Le domaine en Dart pur, écrit test d’abord : argent, horloges, positions, analyses, ordres, moteur de voyage', '12'],
    ['M2', 'Le backend : fournisseur de données, stockage, API, synchronisation, contenu', '7'],
    ['M3', 'La couche données de l’application : base drift, clients HTTP, dépôts, cache', '6'],
    ['M4', 'Le bac à sable live : portefeuille, Explorer, page d’un actif, ordres, liste des portefeuilles', '7'],
    ['M5', 'Les voyages dans le temps', '5'],
    ['M6', 'Le moteur de leçons, le glossaire, le questionnaire', '9'],
    ['M7', 'La carte et les animations', '4'],
    ['M8', 'Livret A, simulateur de DCA, compagnon', '3'],
    ['M9', 'Finitions : hors ligne, anglais, accessibilité, la direction artistique écran par écran', '45'],
    ['M10', 'Le nom Motu, l’icône, la publication du dépôt, les données hors de git', '11'],
    ['M11', 'Le « monde » sur chaque onglet : contrôles en blocs, îles des portefeuilles', '6'],
    ['M12', 'L’île Les bases, le quiz, les missions automatiques', '14'],
    ['M13', 'Les îles en gros plan, la carte marine, les leçons en cartes', '25'],
  ], [0.8, 6, 1]),
  spacer(),
  P("Chaque ticket suit le même chemin : une branche, le code du domaine écrit test d'abord, une pull request, l'intégration continue (analyse statique, tests de l'application et du backend, contrôle des packs de contenu) qui doit passer avant la fusion. Chaque choix d'architecture est consigné dans une ADR (Architecture Decision Record : contexte, options, décision, conséquences), et chaque décision produit datée dans le cahier des charges (`docs/BRIEF.md`)."),
];

// 3. Écrans ---------------------------------------------------------------------

const ecrans = [
  H1('3. Les écrans'),
  P("Toutes les captures sont rendues par des tests à partir des vrais widgets de l'application, sur des données fixes (`flutter test screenshots`), à la taille d'un téléphone. Elles sont donc toujours à jour : un écran qui change fait échouer son test tant que la capture n'est pas refaite. Les écrans qui défilent sont coupés à la hauteur d'un téléphone."),
  H2('3.1 Premier lancement et îles'),
  screens(shots, [
    ['m6-7-onboarding-question', 'Le questionnaire : un formulaire dont chaque question est obligatoire'],
    ['m6-7-onboarding-result', 'Le point de départ choisi, et pourquoi'],
    ['m13-9-lesson-card', "L'onglet Archipel : le port de Les bases ; toucher un repère montre sa leçon"],
    ['m6-9-island-path', 'Actions & ETF en gros plan : un repère par leçon sur son bâtiment'],
    ['m13-5-sea-chart', 'La carte marine, dessinée en code : naviguer entre le port et les îles'],
    ['m6-5-mission', 'Une mission, validée en la faisant dans le bac à sable'],
  ]),
  ...wideFigure(shot('m13-3-port-9.png'), 'Les bases, le port du continent, une fois ses neuf leçons faites : la digue, l’écluse, la grue, le phare allumé', { maxCm: 9 }),
  H2('3.2 Les leçons'),
  screens(shots, [
    ['m6-3-predict-reveal', 'Prédire, puis révéler : Apple ou l’ETF Monde en 2022, sur des cours réels'],
    ['m7-4-reveal-drawing', 'Les courbes de la révélation se dessinent (animation codée)'],
    ['m6-4-decision', '« Mars 2020 : vendre ou tenir ? » : une décision sur une crise passée'],
    ['m6-3-toy', 'Le jouet des frais : l’écart après 30 ans (calcul)'],
    ['m6-4-build-puzzle', 'Construire un portefeuille calme : volatilité sous 8 % (calcul)'],
    ['m12-5-cash-inflation', '10 000 € sous le matelas, et ce qu’ils achètent aux prix de l’INSEE'],
    ['m12-3-loan-toy', 'Le vrai prix d’un crédit : mensualités et intérêts au centime'],
    ['m13-13-card-example', 'Après l’exercice, la leçon continue en cartes : un exemple chiffré'],
    ['m13-13-card-check', 'Une vérification rapide, juste ou fausse, avec son pourquoi'],
  ]),
  H2('3.3 Le portefeuille'),
  screens(shots, [
    ['m4-7-wallets', 'Les portefeuilles : le live, les voyages, le simulateur de DCA'],
    ['m4-2-wallet', 'Le portefeuille live : son île, sa valeur, son graphique, sa répartition'],
    ['m4-6-wallet-pending', 'Un ordre en attente : son bâtiment en chantier (animation codée)'],
    ['m8-1-livret', 'Le Livret A à côté des placements : intérêts par quinzaine'],
    ['m8-3-wallet-companion', 'Un moment du compagnon : une ligne pèse lourd', { top: 1050 }],
    ['m9-41-wallet-plans', 'Les versements programmés (DCA) d’un portefeuille'],
  ]),
  H2("3.4 L'Explorer, la page d'un actif, les ordres"),
  screens(shots, [
    ['m4-3-explorer', 'Le catalogue : une liste dynamique, filtres et favoris'],
    ['m4-4-asset', 'Un actif : cours, graphique, et pourquoi il a bougé'],
    ['m9-36-asset-score', '« Stabilité passée » : un score sur 100, ses quatre parts détaillées'],
    ['m4-5-order-sheet', "La feuille d'ordre : frais et total avant d'envoyer"],
    ['m9-17-order-error', 'Une erreur de validation, dite en mots'],
    ['m9-34-order-done-pending', 'Un achat programmé : son immeuble en chantier'],
  ]),
  H2('3.5 Les voyages dans le temps'),
  screens(shots, [
    ['m5-1-trip-wizard-dates', 'Quand partir : moments historiques ou date précise'],
    ['m5-2-trip-wizard-difficulty', 'La difficulté : capital, versements, frais'],
    ['m5-2-trip-wizard-recap', 'Le récapitulatif et les arrêts automatiques'],
    ['m5-3-trip-wallet', 'Un voyage en 2008, qui avance d’un jour, d’une semaine, d’un mois'],
    ['m5-4-stop', 'Un arrêt automatique : ce qui s’est passé, et trois choix'],
    ['m5-5-trip-summary', "Le bilan d'un voyage, face à « ne rien toucher »"],
  ]),
  H2('3.6 Simulateur, glossaire, réglages'),
  screens(shots, [
    ['m8-2-dca-form', 'Le simulateur de DCA : un formulaire validé'],
    ['m8-2-dca-result', 'Son résultat, face à un placement unique et au Livret A'],
    ['m6-6-glossary', 'Le glossaire : une liste avec recherche et filtres'],
    ['m6-6-term-sheet', 'Une notion, avec son exemple sur données réelles'],
    ['m9-1-settings', 'Les réglages : langue, niveau, données et cache'],
    ['m0-2-gallery', 'Le système de design : les deux familles de composants'],
  ]),
  H2('3.7 Hors ligne, accessibilité, anglais'),
  screens(shots, [
    ['m9-5-wallet-offline', 'Relancée hors ligne : les derniers cours, datés'],
    ['m9-4-order-offline', 'Un ordre passé hors ligne attend la prochaine ouverture', { top: 450 }],
    ['m9-3-asset-130', 'Texte à 130 % : chaque écran se réorganise'],
  ]),
];

// 4. Architecture ------------------------------------------------------------------

const architecture = [
  H1("4. L'architecture"),
  H2("4.1 Vue d'ensemble"),
  P("Deux programmes. **L'application Flutter** porte tout ce que fait l'utilisateur et fonctionne hors ligne une fois son cache rempli. **Un petit backend Go** se place entre elle et le fournisseur de données de marché, pour trois raisons : la clé du fournisseur ne peut pas être livrée dans une application ; il garde tout l'historique des cours, une fois pour tous ; et il répartit les crédits du plan gratuit (8 par minute, 800 par jour) entre tous les utilisateurs. L'application appelle aussi **Frankfurter** directement pour les taux de change (BCE, sans clé)."),
  ...wideFigure(diag('systeme.png'), "Les deux programmes et les deux sources de données", { diagram: true, maxCm: 8 }),
  H2("4.2 L'application : quatre couches"),
  P("`présentation → application → domaine ← données`. Chaque couche ne connaît que celle d'en dessous ; le domaine ne connaît personne. La couche **domaine** est du Dart pur : pas de Flutter, pas d'entrée-sortie, pas de Riverpod, et pas de `DateTime.now()` : le temps lui est toujours passé en argument. La couche **données** est la seule à faire du réseau ou du disque. La couche **application** relie les deux avec des providers Riverpod. La **présentation** n'a aucune logique métier : les widgets affichent un état et transmettent des intentions."),
  ...wideFigure(diag('couches.png'), "Les quatre couches de l'application et leurs classes principales", { diagram: true, maxCm: 19 }),
  P("Ces règles sont vérifiées, pas seulement écrites : `test/architecture_test.dart` fait échouer l'intégration continue quand un fichier du domaine importe Flutter, Riverpod ou `dart:io` ou appelle `DateTime.now()`, quand un fichier hors de `data/` importe dio, et quand une couleur est écrite ailleurs que dans les jetons du thème."),
  table(['Dossier', 'Contient', 'Exemples'], [
    ['`lib/core/`', 'Ce que toutes les couches partagent', '`SimulationClock`, `Money`, `Failure`, `CacheStatus`, jetons du thème, formats'],
    ['`lib/domain/`', 'Règles et calculs métier : des fonctions pures sur des valeurs immuables', '`trip_engine.dart`, `valuation.dart`, `order_matcher.dart`, `analytics/`, `dca.dart`'],
    ['`lib/data/`', 'Tables et DAO drift, clients HTTP et DTO, dépôts', '`market_repository.dart`, `wallet_repository.dart`, `tables.dart`'],
    ['`lib/application/`', 'Un provider ou un notifier par besoin d’un écran', '`wallet_providers.dart`, `order_ticket.dart`, `trip_runner.dart`'],
    ['`lib/presentation/`', 'Écrans et widgets, par fonctionnalité', '`features/wallet/`, `features/island/`, `routing/router.dart`'],
  ], [1.4, 2.6, 3.4]),
  spacer(),
  H3("L'horloge, clé des voyages dans le temps"),
  P("Le temps vient d'une `SimulationClock` : `LiveClock` pour le portefeuille live, `HistoricalClock(date)` pour un voyage. Toute lecture de données de marché passe par un dépôt qui prend une date `asOf` et coupe sa réponse à cette date : aucun cours, taux, point de graphique ou actif daté après `clock.now()` ne peut atteindre le domaine ou l'écran. C'est ce qui permet à **un seul code** de servir le portefeuille d'aujourd'hui et un voyage en 2008, sans qu'un voyage puisse « voir » l'avenir."),
  H2('4.3 Le backend'),
  P("Go, routage `net/http` de la bibliothèque standard, SQLite (`modernc.org/sqlite`, sans cgo), journaux structurés (`log/slog`), configuration par variables d'environnement, image Docker multi-architecture publiée à chaque version. Il ne garde **aucune donnée utilisateur** et n'a pas de comptes : il sert les mêmes données publiques et les mêmes leçons à tout le monde."),
  ...wideFigure(diag('backend.png'), 'Les commandes et les paquets du backend', { diagram: true, maxCm: 8 }),
  ...bullets([
    "`cmd/server` : le serveur HTTP et le planificateur. `jobs` télécharge l'historique de chaque actif une fois, puis ajoute chaque séance après la clôture américaine, une fenêtre de dates et un crédit à la fois, en sauvegardant sa progression ; les cotations sont rafraîchies toutes les 30 minutes pendant la séance. Un budget de crédits étale le tout.",
    "`cmd/freeze` : fabrique les jeux de données figés des leçons, depuis le même fournisseur, et écrit leur recette (section 8).",
    "`cmd/contentcheck` : valide chaque pack de leçons (schéma, deux langues, liens vers le glossaire, jeux de données) ; il tourne dans l'intégration continue.",
    "`cmd/logos` : télécharge les logos des entreprises, livrés avec l'application.",
  ]),
  H2("4.4 Les questions d'architecture du sujet"),
  H3("Où est l'état de l'application, et pourquoi ?"),
  P("La source de vérité est la base drift : portefeuilles, ordres, exécutions, progression, réglages. Les providers Riverpod (`lib/application/`) tiennent ce qui en est déduit pour les écrans (la valorisation d'un portefeuille, les chiffres d'un actif, l'état d'une leçon) et se recalculent quand ce qu'ils observent change. Les widgets ne gardent que ce qui appartient à l'écran lui-même : le contrôleur d'un champ de texte, celui d'une animation. Un seul endroit où persister, beaucoup de vues bon marché, et chaque vue testable sans widget."),
  H3("Qui décide entre l'API et le cache ?"),
  P("Les dépôts, et eux seuls : `MarketRepository`, `FxService`, `ContentRepository`. Un provider demande « l'historique d'Apple à telle date » ; le dépôt répond depuis drift et décide seul si une requête est due (section 7). L'interface ne sait jamais d'où viennent les données, sauf par `CacheStatus`."),
  H3('Où sont les calculs métier ?'),
  P("Dans `lib/domain/`, en fonctions pures sur des valeurs immuables, sans Flutter, sans entrée-sortie et sans horloge : valorisation, exécution des ordres, moteur de voyage, rendements, pire baisse, volatilité, décomposition, DCA, intérêts du Livret. Le temps est un argument (`asOf`), donc une fonction donne la même réponse pour le portefeuille live et pour un voyage en 2008. Elles portent l'essentiel des tests."),
  H3('Qui est responsable de la persistance ?'),
  P("La couche données : `AppDatabase` (drift) et ses DAO, utilisés seulement à travers les dépôts (`WalletRepository`, `ProfileRepository`…). Un achat est une seule transaction : l'ordre, son exécution et ses écritures de liquidités (le montant et les frais) sont écrits ensemble ou pas du tout."),
  H3("Comment les erreurs et le chargement arrivent-ils à l'écran ?"),
  P("Chaque échec est typé là où il se produit : les erreurs dio deviennent `NetworkFailure`, `RateLimitedFailure`, `NotFoundFailure` ou `ServerFailure` ; les erreurs de base de données, `StorageFailure` ; un voyage au-delà des données en cache lève `DataUnavailableFailure`. Les providers sont asynchrones, donc Riverpod donne à l'écran un `AsyncValue` : chargement, données ou erreur. Les écrans aiguillent dessus avec trois widgets partagés : `AsyncSkeleton` pendant le chargement, `ErrorView` (l'échec en mots, et un « Réessayer » qui invalide le provider), et le contenu. Un rafraîchissement garde les données précédentes à l'écran. L'ancienneté des données n'est pas une erreur : elle circule à part, dans le flux `CacheStatus` derrière `CacheStatusBanner`."),
  H3('Que se passe-t-il quand un widget est reconstruit ?'),
  P("Rien de coûteux. `build` ne fait qu'observer des providers et disposer ce qu'ils contiennent ; rien n'est chargé dans `build`. Un provider garde sa valeur d'une reconstruction à l'autre et ne recalcule que si ce qu'il observe change ou s'il est invalidé. Ce qui doit survivre à une image vit dans un objet `State` (un contrôleur d'animation appartient au `State` de son widget, qui le libère) ou dans un provider. Un provider que plus personne n'observe est libéré."),
];

// 5. État ----------------------------------------------------------------------

const etat = [
  H1("5. La gestion de l'état"),
  P("**Choix : Riverpod, avec génération de code** (ADR-001). Trois besoins étaient durs : un modèle d'état asynchrone (chargement, données, erreur, rafraîchissement) sur chaque écran ; un état propre à chaque portefeuille (le live, et chaque voyage avec sa propre horloge) ; et des tests de la logique d'écran sans construire d'écran."),
  table(['Option', 'Pour', 'Contre'], [
    ['`setState` et `InheritedWidget`', 'Aucune dépendance', 'L’état vit dans les widgets : partager un portefeuille entre deux écrans oblige à le remonter et à le faire redescendre ; chargement et erreur réécrits sur chaque écran ; tester un calcul oblige à construire l’écran'],
    ['Provider', 'Injection de dépendances simple', 'Recherche dans l’arbre de widgets : une lecture au mauvais endroit échoue à l’exécution ; état paramétré (« le portefeuille de tel id ») à placer à la main dans l’arbre ; son auteur recommande Riverpod comme successeur'],
    ['Bloc / Cubit', 'États explicites, très testable', 'Beaucoup de cérémonie (une classe d’état, souvent scellée, par fonctionnalité) ; chargement et erreur modélisés à la main ; portée liée à la navigation'],
    ['**Riverpod**', '`AsyncValue` donne chargement / données / erreur en gardant la valeur précédente ; `family` paramètre un provider par portefeuille ; tout provider se remplace dans un test', 'Une étape de génération de code ; des notions à apprendre (`ref.watch` contre `ref.read`, libération automatique)'],
  ], [1.4, 2.6, 3.6]),
  spacer(),
  P("Riverpod est la seule option où les trois besoins sont fournis plutôt que réécrits pour chaque écran. Voici, raccourci, le provider de la page d'un actif : il est paramétré par l'actif et par le portefeuille, et prend l'horloge de ce portefeuille."),
  ...code([
    '@riverpod',
    'Future<AssetOverview> assetOverview(Ref ref, String assetId, String? walletId) async {',
    '  final market = ref.watch(marketRepositoryProvider);',
    '  final wallets = ref.watch(walletRepositoryProvider);',
    '  final now = ref.watch(liveClockProvider).now();',
    '  final wallet = await wallets.load(walletId ?? WalletRepository.liveWalletId);',
    '  final asOf = wallet.kind == WalletKind.live',
    '      ? now : HistoricalClock(wallet.simDate!).now();   // un voyage voit son jour',
    '  final bars = await market.history(assetId, from: from, to: asOf, asOf: asOf);',
    '  …',
    '  return buildAssetOverview(asset: asset, wallet: wallet, asOf: asOf, bars: bars, …);',
    '}',
  ]),
  P("L'écran aiguille sur l'état ; l'erreur garde son type jusqu'à l'écran, et « Réessayer » invalide le provider :"),
  ...code([
    'final state = ref.watch(assetOverviewProvider(assetId, walletId));',
    'body: switch (state.value) {',
    '  final o? => AssetPage(o),                // données, gardées pendant un rafraîchissement',
    '  null when state.hasError => ErrorView(',
    '      failure: state.error as Failure,',
    '      onRetry: () => ref.invalidate(assetOverviewProvider(assetId, walletId))),',
    '  null => const AsyncSkeleton(lines: 6),   // chargement',
    '},',
  ]),
  P("Les échecs forment une classe scellée (`sealed class Failure`) : `NetworkFailure`, `RateLimitedFailure(retryAfter)`, `NotFoundFailure`, `ServerFailure`, `DataUnavailableFailure(asOf)`, `ValidationFailure(code, params)`, `StorageFailure`. `ErrorView` les traduit en phrases. Jamais une chaîne brute ne remonte jusqu'à l'écran.", { align: AlignmentType.LEFT }),
  P("Dans les tests, un `ProviderContainer` remplace les dépôts par des faux, et un notifier se teste seul : chargement puis données, erreur puis nouvel essai, rafraîchissement qui garde les données."),
];

// 6. Persistance -----------------------------------------------------------------

const persistance = [
  H1('6. La persistance et le modèle de données'),
  H2('6.1 Le choix : drift (SQLite typé)'),
  P("Les données sont relationnelles et lues par plages : les cours d'un actif entre deux dates, les exécutions d'un portefeuille avec leurs ordres. Et chaque évolution du schéma doit être testée (ADR-002)."),
  table(['Option', 'Pourquoi pas'], [
    ['`shared_preferences`', 'Clé-valeur : ni requêtes, ni transactions, ni schéma. Impossible pour un grand livre ou 200 000 cours'],
    ['Hive / Isar', 'Pas de requêtes de plage ou de jointure, pas d’intégrité relationnelle, migrations à la main ; les deux projets ont perdu leurs mainteneurs d’origine'],
    ['`sqflite`', 'Le bon moteur, mais requêtes en chaînes et lignes en `Map` : erreurs de type à l’exécution, migrations écrites et testées à la main'],
    ['**drift**', 'Retenu : SQLite avec des tables déclarées en Dart, des requêtes vérifiées à la compilation, des flux observables (l’écran se met à jour quand une exécution est écrite), des transactions, et des migrations versionnées avec un outil qui les teste'],
  ], [1.4, 6]),
  H2('6.2 Deux familles de tables'),
  P("Les tables de **cache** gardent ce qui vient du réseau : les réglages peuvent les vider, et elles se remplissent à nouveau. Les tables **utilisateur** gardent ce que seul l'utilisateur a créé ; elles ne pointent jamais vers une table de cache, donc vider le cache ne peut pas casser un portefeuille. Les **positions ne sont jamais stockées** : elles se déduisent des exécutions (méthode du coût moyen), si bien que le grand livre des liquidités, les exécutions et les valeurs quotidiennes sont toute la vérité."),
  ...wideFigure(diag('modele-portefeuille.png'), 'Les tables utilisateur autour d’un portefeuille', { diagram: true, maxCm: 12.5 }),
  table(['Table utilisateur', 'Colonnes principales'], [
    ['`wallets`', 'id, kind (live ou trip), name, startDate, simDate (le jour d’un voyage), difficulty, params (règles, versements, arrêts, en JSON), status, reachedToday'],
    ['`cash_ledger`', 'walletId, date, amountCents, kind (départ, versement, achat, vente, frais, Livret), refId : les liquidités sont la somme des écritures'],
    ['`orders`', 'id, walletId, assetId, side, type (marché, limite, stop), amountCents ou quantityMicros, limitPrice, stopPrice, status, cancelReason, planId'],
    ['`fills`', 'orderId (unique), walletId, assetId, side, date, price, quantityMicros, fxRate, feesCents'],
    ['`wallet_values`', 'walletId, date, valueCents, flowCents : la série quotidienne des graphiques et du rendement pondéré'],
    ['`dca_plans` · `journal_entries` · `companion_log`', 'les plans d’investissement programmé ; les décisions d’un voyage ; les moments du compagnon déjà montrés'],
    ['`profiles` · `node_progress` · `glossary_state` · `favorites` · `dca_simulations`', 'sans lien avec un portefeuille : les réponses au questionnaire et l’île d’ouverture (une seule ligne) ; la progression des leçons ; les notions découvertes ; les favoris ; les simulations enregistrées'],
  ], [2.4, 5.2]),
  ...wideFigure(diag('modele-cache.png'), 'Les tables de cache (plus `fx_rates`, `livret_rates`, `livret_ceilings` et `content_packs`, sans relation)', { diagram: true, maxCm: 10 }),
  H2("6.3 L'argent n'est jamais un double"),
  P("En virgule flottante binaire, `0.1 + 0.2 != 0.3` : sur des milliers d'écritures et de jours de voyage, les erreurs s'accumulent. Chaque grandeur a donc la représentation qui correspond à son comportement (ADR-003) :"),
  table(['Type', 'Représentation', 'Sert à'], [
    ['`Money`', 'entier en centimes, avec sa devise', 'liquidités, écritures, frais, montants comptabilisés, valeurs quotidiennes'],
    ['`Quantity`', 'entier en millionièmes de part', 'parts détenues et échangées (fractionnées à 6 décimales)'],
    ['`Price`', '`Decimal`, avec sa devise', 'cotations et cours'],
    ['Taux de change', '`Decimal`, daté', 'conversion, uniquement par `FxService`'],
  ], [1.2, 2.4, 3.6]),
  spacer(),
  P("Un montant est arrondi au demi pair une seule fois : quand il est comptabilisé (une exécution, des frais, des intérêts) ou affiché. Les rapports intermédiaires restent exacts en `Decimal`. Ajouter des euros à des dollars lève une erreur typée. Dans la base, les prix et les taux sont stockés en chaînes décimales exactes, et dans le JSON de l'API aussi, jamais en nombres."),
  H2('6.4 Les migrations'),
  P("Le schéma en est à sa **version 7**. Chaque version arrive avec sa migration et un test qui met à jour une base de chaque version plus ancienne, avec des schémas générés par drift (`app/test/drift/`)."),
  table(['Version', 'Changement', 'Pourquoi'], [
    ['2', 'Les raisons d’arrêt d’un voyage', 'Garder l’arrêt automatique jusqu’à ce que l’utilisateur décide'],
    ['3', 'Le capital de départ du portefeuille live', 'Le choisir dans les réglages pour la prochaine remise à zéro'],
    ['4', 'Les fermetures anticipées de la bourse', 'Une séance qui finit à 13 h la veille de Noël ; chaque année en cache est revérifiée une fois'],
    ['5', 'Un voyage qui a rejoint aujourd’hui', 'Il continue au rythme des vrais jours'],
    ['6', 'L’île où l’application s’ouvre', 'Rouvrir là où l’on était'],
    ['7', 'La question du temps par semaine retirée', 'SQLite supprime une colonne en reconstruisant la table'],
  ], [0.8, 3, 3.6]),
];

// 7. Cache -------------------------------------------------------------------------

const cache = [
  H1('7. Le cache : persistance, invalidation, rafraîchissement'),
  H2('7.1 Deux niveaux, une raison chacun'),
  ...wideFigure(diag('cache.png'), 'Les deux niveaux de cache', { diagram: true, maxCm: 5 }),
  P("**Le backend** est le seul client du fournisseur, parce que la clé ne peut pas être livrée dans une application et que le plan gratuit ne pourrait pas servir chaque téléphone. Il télécharge l'historique de chaque actif une fois, depuis le 3 janvier 2000, puis ajoute chaque séance. Ses réponses portent un `ETag`, les corps de plus de 1 Ko sont compressés en gzip, et chaque client est limité à 120 requêtes par minute."),
  P("**L'application** garde ce dont l'utilisateur a eu besoin, pour répondre tout de suite (un écran lit sa base locale, puis le réseau seulement si quelque chose est dû) et pour continuer à marcher sans connexion."),
  H2('7.2 Ce que garde l’application, et quand elle redemande'),
  table(['Donnée', 'Téléchargée', 'Gardée', 'Pourquoi'], [
    ['Historique des cours', 'Au premier besoin, tout l’historique (environ 775 Ko de JSON, 195 Ko compressés). Ensuite seulement les jours après le dernier en cache, au plus toutes les 15 min', 'Toujours', 'Un jour clos ne change jamais ; demander les seuls jours manquants réduit un rafraîchissement à quelques centaines d’octets. Le délai de 15 min évite que des écrans ouverts l’un après l’autre redemandent'],
    ['Historique réajusté', 'Quand le `adjustedAt` du backend diffère de celui en cache', 'Remplacé', 'Les cours sont ajustés des dividendes et des divisions d’actions : une division réécrit le passé, donc l’historique de l’actif est remplacé en entier, dans une transaction'],
    ['Cotations (live)', '15 min après leur téléchargement si la bourse est ouverte ; sinon à sa prochaine ouverture, jours fériés compris', 'Jusqu’au remplacement', 'Le backend les rafraîchit toutes les 30 min ; le prix d’un marché fermé ne peut pas changer, donc nuits et week-ends ne coûtent rien'],
    ['Catalogue', 'Une fois par jour, et pour un actif inconnu', 'Jusqu’au remplacement', 'Il change rarement ; un identifiant inconnu est le seul signe qu’il a changé plus tôt'],
    ['Calendrier de la bourse', 'Les années passées une fois ; l’année en cours et les suivantes une fois par jour', 'Toujours', 'Un jour férié passé est fixé ; une fermeture exceptionnelle peut encore être annoncée'],
    ['Taux de change', 'Au premier besoin d’une paire, tout son historique depuis 2000 (une requête) ; ensuite les nouveaux jours, au plus toutes les 15 min', 'Toujours', 'Un taux de référence BCE publié ne change plus ; un week-end prend le taux du vendredi'],
    ['Taux du Livret A', 'Une fois par jour', 'Jusqu’au remplacement', 'Ils changent quelques fois par an'],
    ['Packs de leçons', 'Livrés avec l’application ; le manifeste au plus une fois par jour ; une version plus récente est gardée seulement si elle se lit', 'Jusqu’à une plus récente', 'Les leçons marchent hors ligne dès le premier lancement ; un téléchargement abîmé ne peut pas les casser'],
  ], [1.3, 2.8, 1.1, 3]),
  H2('7.3 Les règles de toute lecture'),
  ...bullets([
    "**Coupée à la date demandée** (`asOf`). L'historique s'arrête ce jour-là, une cotation observée après est retenue, un actif coté après est caché. Un voyage en 2008 et le portefeuille live utilisent le même code, et aucun prix de l'avenir ne peut atteindre un voyage.",
    "**L'horloge de l'appareil date le cache.** Les durées de vie utilisent l'heure réelle ; `asOf` ne fait que couper ce qui est lu.",
    "**Le cache remplace le réseau.** Une requête qui échoue retombe sur ce qui est en cache. Un échec typé n'atteint l'écran que si rien n'est en cache.",
    "**Les données utilisateur ne dépendent jamais du cache.** Vider le cache ne peut pas casser un portefeuille.",
  ]),
  H2('7.4 Ce qui invalide quoi'),
  table(['Événement', 'Effet'], [
    ['Le temps passe', 'La lecture suivante après une durée de vie redemande'],
    ['Une séance se clôture', 'La lecture d’historique suivante, 15 min après la dernière vérification, demande le nouveau jour'],
    ['Le backend réajuste un actif', 'Son historique en cache est supprimé et retéléchargé en entier'],
    ['Une nouvelle version d’une leçon est publiée', 'Téléchargée dans la journée, gardée si elle se lit'],
    ['Une mise à jour de l’application livre un pack plus récent', 'Le pack livré remplace un pack en cache plus ancien'],
    ['« Actualiser maintenant » (réglages)', 'Tous les cours deviennent dus ; jusque-là, et hors ligne, les cours en cache restent'],
    ['« Vider le cache » (réglages)', 'Cours, cotations et taux supprimés ; portefeuilles, leçons, catalogue et calendriers restent'],
  ], [2.6, 5]),
  H2('7.5 Hors ligne : un mode dégradé, dit à l’écran'),
  P("`MarketRepository.status()` émet un `CacheStatus` : `Offline(lastUpdated)` quand l'appareil n'a pas de connexion (`connectivity_plus`), `Stale(lastUpdated)` quand il en a une mais que le dernier téléchargement de cours a échoué et que le cache a pris le relais, `Fresh` sinon. `CacheStatusBanner` affiche les deux premiers au-dessus des prix : « Hors connexion. Tu vois les cours du 7 octobre 2026, 22 h 05. », avec « Réessayer »."),
  P("Quand le backend lui-même est injoignable (pas de connexion, délai dépassé, erreur 502 à 504), `BackendApi` arrête de l'appeler pendant 30 secondes : chaque appel échoue aussitôt, et chaque dépôt répond depuis son cache sans attendre. Avant cette pause, la première ouverture de l'Explorer sans backend envoyait environ 70 requêtes l'une après l'autre, chacune échouant en 0,5 à 1 s : 15 à 25 secondes de squelette."),
  P("Ce qui marche hors ligne : les îles et la carte marine, toutes les leçons (livrées), les portefeuilles, les positions et les graphiques, le glossaire, les simulations enregistrées, les pages des actifs et l'Explorer, un voyage qui avance dans son historique en cache. Un ordre au marché passé hors ligne attend l'ouverture de la séance suivante, pour ne jamais s'exécuter à un prix vieux de plusieurs heures."),
  ...wideFigure(diag('lecture.png'), "Ouvrir la page d'un actif, de bout en bout : où chaque décision est prise", { diagram: true, maxCm: 15 }),
  H2('7.6 Mesuré, et vérifié'),
  ...bullets([
    "La première vue d'un actif télécharge environ 775 Ko de JSON, envoyés compressés en environ 195 Ko ; chaque rafraîchissement suivant n'apporte que les nouveaux jours.",
    'Un voyage qui avance dans un historique en cache ne fait aucune requête.',
    "Après une séance d'utilisation sur un téléphone, les réglages indiquaient « 29 historiques, 167 390 cours, 21,1 Mo sur l'appareil » : tout le catalogue depuis 2000.",
    "`app/test/offline_test.dart` remplit le cache en ligne, tue l'application, la relance sans réseau et ouvre chaque onglet et chaque écran, dans l'intégration continue. Le même parcours a été fait à la main sur un téléphone en mode avion : il a trouvé trois bugs, corrigés depuis.",
  ]),
];

// 8. APIs et données ------------------------------------------------------------------

const donnees = [
  H1('8. Les API et les données'),
  H2('8.1 Le fournisseur de données de marché : Twelve Data'),
  P("Le plan gratuit de Twelve Data (8 crédits par minute, 800 par jour) ne couvre que les bourses américaines ; les cotations européennes demandent un plan payant à 79 $ par mois. Trois options ont été pesées (ADR-004) : le plan gratuit avec des cotations américaines, le plan payant, ou un second fournisseur gratuit pour l'Europe (deux fournisseurs à maintenir, et des conditions de redistribution floues). **Choix : le plan gratuit, cotations américaines.** Les mêmes entreprises et les mêmes expositions sont là, par des ETF cotés aux États-Unis et des ADR (certificats américains) pour les actions européennes."),
  ...bullets([
    '**29 instruments** : 7 ETF (Monde, S&P 500, Nasdaq 100, Europe, pays émergents, obligations internationales, obligations agrégées), 12 actions européennes (LVMH, TotalEnergies, Airbus, ASML, SAP…), 10 américaines (Apple, Microsoft, Nvidia…).',
    "**Depuis le 3 janvier 2000** (`dataFloor`), avant le premier voyage proposé (la bulle internet, 10 mars 2000). Un actif n'apparaît dans un voyage qu'à partir de son premier cours.",
    "**Cours ajustés des dividendes et des divisions** : l'application ne comptabilise pas les dividendes, donc des cours ajustés des seules divisions effaceraient en silence 1 à 2 % de rendement par an d'un ETF. La ligne de provenance le dit.",
    "**L'ETF Monde de référence est ACWI** (depuis 2008), pas URTH (depuis 2012) : il sert de comparaison, de « marché » dans la décomposition et de scénario « ne rien toucher », et couvre le voyage de 2008.",
  ]),
  P("Conséquence assumée : chaque actif est coté en dollars, donc chaque actif porte un risque de change. L'application en a fait une leçon (« Le piège du dollar ») et un élément de la décomposition des mouvements."),
  H2('8.2 Les autres sources'),
  table(['Source', 'Données', 'Accès'], [
    ['**Frankfurter**', 'Taux de référence de la BCE, depuis 1999', 'Appelé directement par l’application (dio), et par le backend ; sans clé'],
    ['**INSEE**', 'Indice des prix à la consommation, mensuel, depuis 1996 (ADR-008)', 'Par `cmd/freeze` seulement : les leçons de Les bases montrent ce que des billets ou un Livret achètent aux prix de chaque mois'],
    ['**Livret A**', 'Taux depuis 2000 (révisés le 1er février et le 1er août) et plafonds datés', 'Encodés dans le backend (`catalogue/livret.go`), jamais dans l’application ; servis par `/v1/livret/rates`'],
    ['**Calendrier NYSE**', 'Jours fériés et fermetures anticipées', 'Calculés par le backend (`calendar`), servis par `/v1/calendar/{exchange}`'],
  ], [1.3, 2.8, 3.4]),
  H2('8.3 Notre API REST'),
  table(['Méthode et chemin', 'Renvoie'], [
    ['`GET /v1/assets`', 'Le catalogue : date de cotation, devise, région, type'],
    ['`GET /v1/assets/{id}/history?from=&to=`', 'Cours quotidiens ajustés, croissants ; `adjustedAt` = dernier téléchargement complet après un dividende ou une division'],
    ['`GET /v1/quotes?ids=a,b,c`', 'Le dernier prix de chaque actif, avec `asOf` et l’état du marché'],
    ['`GET /v1/fx?base=USD&quote=EUR&from=&to=`', 'Taux quotidiens'],
    ['`GET /v1/livret/rates`', 'Historique daté des taux et des plafonds du Livret A'],
    ['`GET /v1/calendar/{exchange}?year=`', 'Jours fériés et fermetures anticipées (heure de New York)'],
    ['`GET /v1/content/manifest` · `/v1/content/packs/{island}/{version}`', 'Distribution des leçons'],
    ['`GET /healthz`', 'Vivacité'],
  ], [3.4, 4]),
  spacer(),
  P("Les erreurs ont une forme unique, `{\"error\": {\"code\": \"…\", \"message\": \"…\"}}`, avec le bon code HTTP ; une réponse 429 porte `Retry-After`. Chaque point d'accès répond aux requêtes conditionnelles. **Les prix et les taux sont des chaînes décimales, jamais des nombres JSON**, pour qu'aucune précision ne se perde. Côté application, dio fait les appels et `json_serializable` génère des DTO, convertis en types du domaine (`Price`, `Money`) dans la couche données."),
  H2('8.4 Les leçons et leurs données figées'),
  P("Une leçon ne lit jamais les cours du jour : elle s'appuie sur des **jeux de données figés**, produits par `cmd/freeze` depuis le même fournisseur, jamais tapés à la main, avec leur provenance affichée (« Cours réels, clôtures hebdo, 2022, en dollars »). Une leçon donne donc toujours le même résultat, et chacun de ses chiffres est vrai. Un test (`actions_etf_copy_test.dart`) vérifie chaque chiffre cité par les leçons d'Actions & ETF contre les vrais cours."),
  P("Un pack de leçons est **un seul document par version** : `{island, nodes, datasets, glossary}` (ADR-006). L'application en livre un par île, pour marcher hors ligne dès le premier lancement, et télécharge une version plus récente au plus une fois par jour, gardée seulement si elle se lit entièrement. `contentcheck` refuse un pack dont un texte manque dans une langue, dont un lien vers le glossaire est inconnu ou dont un jeu de données manque."),
  P("Les données du fournisseur ne sont pas dans git (ADR-007) : git garde la **recette** de chaque jeu de données, et `scripts/fetch-data.sh` reconstruit les jeux, le pack livré avec l'application et les logos à partir d'une clé (environ 17 crédits). L'intégration continue tourne sur des prix inventés, qu'une version publiée refuse."),
];

// 9. Calculs ---------------------------------------------------------------------

const calculs = [
  H1('9. Les traitements et les calculs'),
  P("Tous les calculs sont des fonctions pures du domaine, testées unitairement. L'argent est en centimes entiers, les prix en `Decimal`, les rapports intermédiaires en `Decimal` à 10 chiffres ; l'arrondi au demi pair n'a lieu que lorsqu'un montant est comptabilisé ou affiché."),
  table(['Calcul', 'Formule et règles'], [
    ['Position (coût moyen)', 'Un achat ajoute la quantité et le coût (prix × quantité × change + frais, en €) ; une vente réduit la quantité, plus-value réalisée = produit − coût moyen × quantité ; le coût moyen ne bouge pas à la vente'],
    ['Valeur de marché (€)', 'quantité × prix(asOf) × change(devise → EUR, asOf) ; sans prix ce jour-là, le dernier prix avant, signalé comme ancien'],
    ['Valeur d’un portefeuille', 'liquidités + Σ valeurs de marché + solde du Livret (intérêts courus montés à part)'],
    ['Plus-value latente', 'valeur de marché − prix de revient (montant et %) ; % indéfini pour un prix de revient nul'],
    ['Répartition', 'poids = valeur / valeur du portefeuille ; les poids somment à 1'],
    ['Rendement pondéré dans le temps (TWR)', 'r_t = (V_t − F_t) / V_{t−1} − 1, où F_t est le versement du jour ; TWR = Π(1 + r_t) − 1 ; les jours où V_{t−1} = 0 sont sautés. Toute « performance » d’un portefeuille qui reçoit des versements l’utilise'],
    ['Volatilité annualisée', 'écart type des rendements logarithmiques quotidiens × √252 ; moins de 20 rendements : pas de chiffre (« pas assez de données »)'],
    ['Niveau de risque 1 à 5', 'volatilité sur un an : < 8 % → 1, < 15 % → 2, < 25 % → 3, < 40 % → 4, sinon 5'],
    ['Décomposition d’un mouvement', 'pour un actif en devise L : total en € = (1 + r_local)(1 + r_change) − 1 ; marché = rendement de l’ETF Monde ; devise = r_change ; propre à l’actif = le reste (termes croisés compris, approximation documentée)'],
    ['Pire baisse (max drawdown)', 'sommet courant ; dd_t = P_t / sommet_t − 1 ; le minimum, avec ses dates de sommet et de creux'],
    ['Concentration', 'poids maximal hors liquidités ; nombre effectif de positions = 1 / Σ w_i²'],
    ['DCA', 'dates mensuelles (ou hebdomadaires), jour sans séance → séance suivante ; quantité += (montant − frais) / clôture ; comparé à un placement unique au départ et au Livret A'],
    ['Intérêts du Livret A', 'par quinzaine : intérêts += solde éligible × taux annuel / 24 ; un versement rapporte à partir de la quinzaine suivante, un retrait cesse de rapporter dès le début de la sienne ; versés le 31 décembre ; plafonds datés respectés'],
    ['Exécution d’un ordre', 'section 9.1'],
    ['Règles du profil, missions, compagnon, score', 'sections 11 et 4'],
  ], [2, 5.6]),
  H2("9.1 Le moteur de voyage et l'exécution des ordres"),
  P("Le moteur de voyage (`TripEngine`) avance un portefeuille jour de bourse par jour de bourse. Chaque jour, dans cet ordre : il verse le versement mensuel (le premier jour du mois), passe les ordres des plans DCA dus, exécute les ordres en attente sur le cours du jour, fait courir le Livret, valorise le portefeuille, puis évalue les moments du compagnon et les arrêts automatiques. Le même moteur rattrape le portefeuille live au lancement, jusqu'à la dernière séance close."),
  ...bullets([
    "Le jour simulé est « après la clôture » du jour J : un ordre au marché s'exécute à l'ouverture du jour de bourse suivant.",
    "Achat à cours limité : le premier jour où le plus bas ≤ limite s'exécute à min(ouverture, limite). Vente à cours limité : plus haut ≥ limite → max(ouverture, limite).",
    "Vente stop : le premier jour où le plus bas ≤ stop s'exécute à min(ouverture, stop). Le glissement sur un trou de cotation est réel, et il est enseigné.",
    "Un ordre déclenché qui ne peut pas s'exécuter comme demandé est annulé avec sa raison, jamais exécuté en partie : liquidités insuffisantes après un trou, parts plus détenues, montant inférieur à une part, frais supérieurs au produit d'une vente.",
    "Les heures de bourse utilisent les fuseaux des places, jamais un décalage codé en dur : les semaines où l'Europe et les États-Unis ne changent pas d'heure le même jour sont testées, ainsi que les fermetures anticipées.",
  ]),
  P("La validation d'un ordre (`validateOrder`) renvoie des erreurs typées : montant positif, quantité entière dans un portefeuille sans fractions, coût total frais compris ≤ liquidités disponibles (« Tu as 1 200,00 € de liquidités. Baisse le montant, ou vends d'abord une position. »), quantité vendue ≤ position, actif disponible à la date. Les ordres en attente réservent ce dont ils ont besoin."),
];

// 10. Animations -------------------------------------------------------------------

const animations = [
  H1('10. Les animations'),
  P("Trois animations codées à la main répondent à l'exigence du sujet ; d'autres sont venues avec les îles. Toutes s'exécutent sans mouvement quand l'utilisateur a désactivé les animations dans son système."),
  table(['Animation', 'Technique', 'Où'], [
    ['**1. Les bâtiments d’un portefeuille** grandissent et rétrécissent avec ses positions', '`CustomPainter` en projection isométrique, piloté par un `AnimationController` ; les hauteurs suivent les cinq plus grosses positions', 'Écran d’un portefeuille'],
    ['**2. Un ordre en attente** est un bâtiment en chantier, qui se termine à l’exécution', 'Un contrôleur de 1,4 s, trois intervalles : hauteurs 0 à 0,6, la partie construite qui monte dans son fantôme 0,3 à 0,9, le fantôme qui s’efface 0,85 à 1', 'Portefeuille, écran après un achat'],
    ['**3. Les courbes d’une révélation** se dessinent', '`Tween<double>` sur la longueur du chemin (`PathMetric`), 1,6 s, accélération et freinage, un point à la pointe de chaque courbe ; les valeurs finales comptent en même temps', 'Leçons « prédire puis révéler » et « décision »'],
    ['Un bâtiment de leçon monte dans son fantôme', '`AnimationController`, 1,4 s, puis la vue glisse en 0,9 s vers le repère suivant', 'Île en gros plan'],
    ['Le repère de la leçon à faire pulse ; le bateau traverse la carte marine', '`AnimationController` (1,8 s pour la traversée)', 'Île, carte marine'],
    ['Pastille d’un contrôle segmenté qui glisse ; recherche qui se déplie', 'Animations implicites', 'Glossaire, Explorer, réglages'],
    ['Transitions des graphiques', 'Fournies par fl_chart', 'Tous les graphiques'],
  ], [2.6, 3.6, 1.6]),
  spacer(),
  screens(shots, [
    ['m9-34-order-done-pending', 'Animation 2 : un achat en attente, son immeuble en chantier dans son fantôme'],
    ['m7-4-reveal-drawing', 'Animation 3 : les courbes se dessinent, les valeurs comptent'],
    ['m13-17-district-rising', 'Une leçon terminée : son bâtiment monte dans son fantôme', { top: 820, height: 900 }],
  ]),
];

// 11. Score et recommandations -------------------------------------------------------

const score = [
  H1('11. Le score et les recommandations'),
  P("Motu ne recommande **aucun actif**. Le profil de l'utilisateur ne choisit jamais d'actif ; il façonne seulement le parcours, le niveau d'interface, des seuils et des formulations. Ce qui ressemble à un score ou à une recommandation est expliqué, et dit ce qu'il ne dit pas."),
  H2('11.1 « Stabilité passée », un score explicable'),
  P("Sur la page d'un actif, un score sur 100 de combien peu le prix a bougé dans le passé. Plus haut veut dire qu'il a moins bougé, pas qu'il est « meilleur » : ce n'est pas un classement, et l'Explorer ne l'affiche, ne le trie ni ne le classe jamais. Il se calcule sur les cours jusqu'au jour de l'horloge (`pastStability`), donc un voyage le voit à sa date. Quatre parts, chacune avec ses points et le fait qui les justifie :"),
  table(['Part', 'Points', 'Calcul'], [
    ['Mouvements', '40', 'volatilité annualisée sur un an : 40 moins un point par point de volatilité, 0 à partir de 40 %'],
    ['Pire baisse', '30', 'pire baisse sur cinq ans, avec ses mois (« −34 % entre février et mars 2020 ») : 30 moins un point par 2 % de baisse, 0 à partir de −60 %'],
    ['Une entreprise ou un panier', '15', 'un ETF répartit le risque (15), une action non (0)'],
    ['Durée de l’historique', '15', '1,5 point par année complète de cotation, 15 à partir de dix ans : un long historique rend les autres chiffres plus fiables'],
  ], [2, 0.8, 5]),
  spacer(),
  P("Chaque part est arrondie au point, et le score est leur somme, donc les lignes s'additionnent. Moins d'un an de cours : pas de score. Sous les parts : « Ce score décrit les cinq dernières années. Il ne dit rien de l'avenir et ce n'est pas un conseil. » Couleurs neutres : ce n'est ni un gain ni une perte."),
  H2('11.2 Le point de départ, choisi par le questionnaire'),
  table(['Question', 'Ce qu’elle change'], [
    ['Pourquoi veux-tu investir ?', 'L’horizon par défaut des projections et du DCA, la formulation du compagnon'],
    ['Ton portefeuille perd 20 % en un mois. Tu fais quoi ?', 'Le seuil de concentration du compagnon et de l’aide avant un ordre'],
    ['Tu sais déjà…', 'La leçon de départ et le niveau d’interface ; « Ce qu’est un ETF » et « J’investis déjà » passent Les bases'],
    ['Où est ton épargne aujourd’hui ?', 'Une épargne sur Livret met « Livret ou ETF ? » en premier'],
  ], [3, 4.6]),
  spacer(),
  P("Après le questionnaire, une phrase explique le choix (« On commence par “Ton matelas de sécurité” parce que tu as répondu “Pas d'épargne”. »). Refaire le questionnaire recalcule tout, sans jamais effacer la progression."),
  H2('11.3 Le compagnon'),
  P("Un moteur de règles pur sur les événements du portefeuille. Chaque « moment » décrit ce qui arrive, renvoie vers les notions du glossaire et vers la leçon qui l'explique, et n'impose rien."),
  table(['Règle', 'Déclencheur', 'Délai avant de revenir'], [
    ['Première perte', 'Une position passe sous −5 % pour la première fois', 'une fois'],
    ['Chute d’une position', '−15 % depuis son sommet après l’achat', '30 jours par position'],
    ['Baisse du portefeuille', '−10 % depuis son sommet, versements exclus', '30 jours'],
    ['Concentration', 'Une position pèse plus de 30 % (prudent) ou 40 % (autres)', '14 jours'],
    ['Liquidités qui dorment', 'Plus de 25 % de liquidités pendant plus de 30 jours', '30 jours'],
    ['Vente sous le coup de la panique', 'Une vente dans les 10 jours de bourse après une chute de −15 % ; revue 3 mois plus tard', 'par événement'],
    ['Mouvement du dollar', 'EUR/USD bouge de plus de 3 % en un mois avec plus de 20 % d’exposition au dollar', '30 jours'],
  ], [2.2, 4, 1.6]),
];

// 12. Tests -----------------------------------------------------------------------

const tests = [
  H1('12. Les tests'),
  P("Tous les tests passent, et l'intégration continue les lance à chaque pull request, après `flutter analyze` et `go vet`. La liste complète, test par test, est générée depuis les rapports des outils de test (`docs/report/tests.md`)."),
  table(['Zone', 'Fichiers', 'Tests'], [
    ['Domaine : logique métier pure, sans Flutter ni entrée-sortie', '24', '465'],
    ['Application : providers et notifiers, sur des faux', '29', '237'],
    ['Données : dépôts, DAO, décodage, sur une base en mémoire et de faux serveurs', '17', '219'],
    ['Données : migrations du schéma, chaque version vers la suivante', '1', '15'],
    ['Présentation : widgets, écrans, accessibilité', '39', '306'],
    ['Core : argent, formats, localisation, thème', '6', '105'],
    ['Application entière : démarrage, règles des couches, parcours hors ligne', '4', '6'],
    ['**Total de l’application**', '**120**', '**1 353**'],
    ['Backend (Go) : handlers, stockage, synchronisation, adaptateur, contrôle du contenu', '12 paquets', '131'],
  ], [5.4, 1, 1]),
  spacer(),
  P("En plus : 97 tests de captures d'écran (section 3), l'adaptateur du fournisseur contre la vraie API (`go test -tags live`), le contrôle de chaque pack de leçons, et le parcours hors ligne à la main (`docs/qa/offline.md`)."),
  H2('12.1 La stratégie, couche par couche'),
  ...bullets([
    "**Domaine** : des tests exhaustifs, pilotés par des tables, avec des horloges fixes. Le domaine a été écrit test d'abord.",
    "**Données** : des tests de dépôts avec un faux serveur et une base drift en mémoire, dont la politique de cache (téléchargement incrémental, durées de vie, repli hors ligne, coupure à `asOf`).",
    "**Application** : des notifiers testés avec des faux (mocktail) : chargement puis données, erreur puis nouvel essai, rafraîchissement qui garde les données.",
    "**Widgets** : les parcours clés (validation d'un ordre, de l'assistant de voyage, du questionnaire).",
    "**Accessibilité** : chaque écran est rendu une fois avec un texte à 130 % (un débordement fait échouer le test) et vérifié contre les règles de Flutter : cibles d'au moins 44 × 44, un libellé sur chaque élément touchable, un contraste de texte lisible.",
    "**Architecture** : un test fait respecter les règles des couches (section 4.2).",
  ]),
  H2('12.2 Les cas limites'),
  P("Le cahier des charges impose un minimum de cas limites pour chaque fonction du domaine. Quelques-uns, avec le nombre de tests dont le nom les cite :"),
  table(['Cas', 'Tests', 'Exemple'], [
    ['Historique vide ou sans données', '80', '« maxDrawdown empty or single point: 0 with no dates »'],
    ['Un seul point de données', '15', '« timeWeightedReturn empty or single day: 0 »'],
    ['Montant nul ou négatif', '32', '« simpleReturn undefined from zero »'],
    ['Prix manquant pour une date', '16', '« investFlows a flow on a day without a bar buys at the next bar »'],
  ], [2.4, 0.7, 4.6]),
  spacer(),
  P("S'y ajoutent, entre autres : un montant inférieur aux frais, la vente de plus que détenu, une limite jamais atteinte, un trou à travers un stop, les week-ends et jours fériés, les semaines de changement d'heure, un taux de change manquant, un actif pas encore coté, un versement le 15 ou le 16 du mois sur le Livret, un retrait en milieu de quinzaine, un plafond atteint, un rendement pondéré avec un jour à valeur nulle, une pire baisse sur une série monotone."),
];

// 13. Difficultés --------------------------------------------------------------------

const limites = [
  H1('13. Difficultés, limites, améliorations'),
  H2('13.1 Les difficultés rencontrées'),
  ...bullets([
    "**Les données.** Aucun fournisseur gratuit ne donnait les cotations européennes : il a fallu repenser le catalogue en cotations américaines, avec un risque de change sur chaque actif, et en faire un sujet de leçon plutôt qu'un défaut caché (section 8.1).",
    "**Un seul code pour aujourd'hui et pour 2008.** Garantir qu'aucune donnée de l'avenir n'atteigne un voyage a imposé l'horloge injectée, la coupure à `asOf` dans chaque dépôt, et le même moteur pour rattraper le portefeuille live.",
    "**Le calendrier de la bourse.** Jours fériés, fermetures anticipées (à 13 h la veille de Noël), décalages entre heures d'été européenne et américaine : chaque cas a donné un test et parfois une migration (version 4 du schéma).",
    "**Le hors ligne réel.** Le parcours à la main en mode avion a trouvé trois bugs que les tests automatiques ne voyaient pas. Plus tard, un backend éteint rendait l'Explorer lent de 15 à 25 secondes : d'où la pause de 30 secondes (section 7.5).",
    "**La direction artistique.** Chaque écran a été repris d'après une maquette validée (M9), puis le « monde » a gagné chaque onglet (M11), puis la carte de l'archipel a laissé place aux îles en gros plan, un bâtiment par leçon, et à une carte marine (M13). Ces allers-retours entre maquettes et code sont restés sûrs grâce aux tests de captures d'écran, qui montrent chaque écran changé.",
    "**La justesse du contenu.** Un texte de leçon qui cite un chiffre peut devenir faux si les données changent : un test vérifie chaque chiffre cité par Actions & ETF contre les vrais cours.",
  ]),
  H2('13.2 Les limites'),
  ...bullets([
    "Seules deux îles sur cinq sont écrites ; Trading, Immobilier et Crypto sont visibles mais fermées.",
    "Le catalogue est fait de cotations américaines en dollars : pas d'ETF coté en euros comme ceux qu'achèterait un débutant français.",
    "Le backend répond aux requêtes conditionnelles (`ETag`, `Last-Modified`), mais l'application ne les envoie pas encore ; ses durées de vie et ses téléchargements incrémentaux évitent déjà de retélécharger ce qu'elle a.",
    "Les valeurs quotidiennes enregistrées d'un portefeuille gardent les prix avec lesquels elles ont été calculées ; après un réajustement, elles ne sont pas recalculées.",
    "« Actualiser maintenant » n'est retenu qu'en mémoire : après une relance, les durées de vie habituelles s'appliquent.",
    "Le cache n'a pas d'éviction automatique : il est borné par le catalogue (29 actifs depuis 2000, environ 21 Mo), et « Vider le cache » le vide.",
    "Pas de compte, donc pas de synchronisation : changer de téléphone, c'est repartir de zéro.",
  ]),
  H2('13.3 Les améliorations possibles'),
  ...bullets([
    "Écrire les îles suivantes, dont les conditions d'ouverture sont déjà fixées (Immobilier après « Le vrai prix d'un crédit », Trading et Crypto après « Repère l'arnaque »).",
    "Une simulation de vie qui rassemble tout : un scénario fixe un salaire et des dépenses, puis l'on décide combien épargner et où placer.",
    "Des cotations européennes en euros, avec un plan payant du fournisseur.",
    "Envoyer les requêtes conditionnelles depuis l'application, et recalculer les valeurs d'un portefeuille après un réajustement.",
  ]),
];

// Annexe ------------------------------------------------------------------------------

const annexe = [
  H1('Annexe : les décisions d’architecture'),
  P("Chaque choix d'architecture est une ADR dans `docs/decisions/` : le contexte, les options pesées, la décision, ses conséquences."),
  table(['ADR', 'Décision', 'En bref'], [
    ['001', 'Riverpod pour l’état', '`AsyncValue` pour chaque état asynchrone, `family` pour un provider par portefeuille, remplacements pour tester sans widget'],
    ['002', 'drift (SQLite) pour la persistance', 'Données relationnelles lues par plages ; requêtes typées et migrations testées ; tables de cache et utilisateur séparées'],
    ['003', 'L’argent en centimes entiers, les quantités en virgule fixe, les prix en `Decimal`', 'Pas de `double` pour l’argent ; un arrondi au demi pair, une seule fois'],
    ['004', 'Twelve Data, plan gratuit, cotations américaines', '29 instruments depuis 2000, ajustés des dividendes et des divisions ; ACWI comme ETF Monde ; Frankfurter pour le change'],
    ['005', 'La politique de cache des données de marché', 'Tout l’historique une fois puis les nouveaux jours ; cotations 15 min en séance ; lectures coupées à `asOf` ; le cache remplace le réseau'],
    ['006', 'Les packs de contenu : un document par version, livré et téléchargé', 'Leçons hors ligne dès le premier lancement ; une version abîmée ne casse rien ; `contentcheck` dans l’intégration continue'],
    ['007', 'Les données du fournisseur hors de git', 'Git garde les recettes ; un script reconstruit les données à partir d’une clé ; l’intégration continue tourne sur des prix inventés'],
    ['008', 'L’inflation par l’indice des prix de l’INSEE', 'Ce qu’achètent des billets ou un Livret, aux prix de chaque mois, depuis 1996'],
  ], [0.6, 2.8, 4.4]),
];

// Document -------------------------------------------------------------------------------

const heading = (size, color, before, after) => ({
  run: { font: FONT, size, bold: true, color },
  paragraph: { spacing: { before, after }, keepNext: true, keepLines: true },
});

const doc = new Document({
  creator: 'Motu',
  title: 'Motu, rapport de projet',
  description: 'Rapport du projet de développement mobile',
  features: { updateFields: true },
  styles: {
    default: {
      document: { run: { font: FONT, size: 21, color: C.ink } },
      heading1: heading(34, C.ink, 0, 240),
      heading2: heading(26, C.primary, 280, 120),
      heading3: heading(22, C.ink, 200, 80),
    },
  },
  numbering: {
    config: [{
      reference: 'bullets',
      levels: [{ level: 0, format: LevelFormat.BULLET, text: '•', alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: 400, hanging: 260 } } } }],
    }],
  },
  sections: [
    { properties: { page: { margin: { top: 1134, bottom: 1134, left: 1134, right: 1134 } } }, children: [...cover] },
    {
      properties: { page: { margin: { top: 1134, bottom: 1134, left: 1134, right: 1134 } } },
      footers: {
        default: new Footer({
          children: [new Paragraph({
            alignment: AlignmentType.CENTER,
            children: [
              new TextRun({ text: fr('Motu · Rapport de projet · '), size: 16, color: C.muted }),
              new TextRun({ children: [PageNumber.CURRENT], size: 16, color: C.muted }),
            ],
          })],
        }),
      },
      children: [
        ...contents, ...projet, ...fonctionnalites, ...ecrans, ...architecture, ...etat,
        ...persistance, ...cache, ...donnees, ...calculs, ...animations, ...score, ...tests,
        ...limites, ...annexe,
      ],
    },
  ],
});

const out = join(here, '..', 'rapport.docx');
writeFileSync(out, await Packer.toBuffer(doc));
console.log(`wrote ${out}`);
