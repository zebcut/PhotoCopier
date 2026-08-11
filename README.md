# PhotoCopier

Application macOS native (SwiftUI) qui copie les fichiers d'une carte mémoire vers un disque en
les classant automatiquement dans une arborescence `AAAA/MM/JJ` selon leur date de création.

## Fonctionnalités

- Classement dans `AAAA/MM/JJ` d'après la date de création du fichier (équivalent `st_birthtime`),
  avec repli sur la date de modification
- Création automatique des dossiers manquants
- Après sélection de la source, scan et liste des extensions présentes sous forme de cases à
  cocher — seuls les types cochés sont copiés
- Détection des doublons par checksum SHA-256 : fichier identique déjà présent → ignoré ;
  fichier différent portant le même nom → copié avec un suffixe numérique (`_1`, `_2`…)
- Fichier dont la date ne peut pas être déterminée → copié dans `dateUnknown/` à la racine de
  la destination
- Annulation possible en cours de traitement

## Prérequis

- macOS 14 (Sonoma) ou supérieur
- Swift 5.9+ (les Command Line Tools suffisent, Xcode complet non requis)

## Lancer en développement

```bash
git clone https://github.com/zebcut/PhotoCopier.git
cd PhotoCopier
swift run
```

## Empaqueter en application `.app`

```bash
./Scripts/build_app.sh
```

Compile en mode release et génère `PhotoCopier.app` à la racine du projet, signé en ad-hoc
(signature locale, pas de compte développeur Apple requis). Au tout premier lancement depuis le
Finder, l'app n'étant pas notariée par Apple, macOS peut demander une confirmation : clic droit →
**Ouvrir**.

## Structure du projet

```
Package.swift                          # Swift Package Manager (pas de .xcodeproj)
Sources/PhotoCopier/
├── PhotoCopierApp.swift                # point d'entrée @main
├── ContentView.swift                   # interface SwiftUI
├── OrganizerViewModel.swift            # état de l'UI, orchestration (@MainActor)
└── Organizer.swift                     # logique de classement/copie, testable hors UI
Scripts/build_app.sh                   # empaquetage en bundle .app
```

## Licence

GPL-3.0 — voir [LICENSE](LICENSE).
