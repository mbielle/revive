<p align="center">
  <img src="App/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png" width="128" alt="Icône de Lucent">
</p>

<h1 align="center">Lucent</h1>

<p align="center">
  Un nettoyeur et outil d'entretien pour Mac, gratuit et open source, développé nativement en SwiftUI.<br>
  <a href="README.md">English version</a>
</p>

---

Lucent garde votre Mac propre, sûr et rapide, avec une interface soignée et sans abonnement. Ce genre d'outil est utile à tout le monde : il devrait être gratuit pour tout le monde.

> **État : préversion (0.1).** Smart Care, Nettoyage, Space Lens et Mon activité fonctionnent déjà. Les autres modules sont développés en open source, voir la [feuille de route](#feuille-de-route).

## Fonctionnalités

| Module | Ce qu'il fait | État |
|---|---|---|
| **Smart Care** | Bilan en un clic : fichiers inutiles, protections intégrées du Mac (SIP, Gatekeeper, FileVault, pare-feu), espace libre et score de santé | ✅ 0.1 |
| **Nettoyage** | Fichiers système inutiles (caches, journaux, Xcode, navigateurs, gestionnaires de paquets), encombrement IA, pièces jointes Mail, corbeilles | ✅ 0.1 |
| **Space Lens** | Carte en bulles navigable d'un dossier ou du disque entier | ✅ 0.1 |
| **Mon activité** | Historique de tout ce qui a été nettoyé | ✅ 0.1 |
| **Applications** | Désinstallation complète, restes d'apps, mises à jour (Sparkle, App Store, Homebrew) | 🛠 0.2 |
| **Performances** | Tâches de maintenance, ouverture à la connexion, éléments en arrière-plan | 🛠 0.2 |
| **Protection** | Recherche de malwares avec les règles YARA XProtect d'Apple, persistance, confidentialité, autorisations | 🛠 0.3 |
| **Encombrement** | Doublons, photos similaires, gros fichiers anciens | 🛠 0.3 |
| **Barre des menus** | CPU, mémoire, disque, réseau et batterie en direct | 🛠 0.3 |
| **Nettoyage cloud** | Gros fichiers et copies locales d'iCloud Drive, Google Drive, OneDrive | 🛠 0.4 |

## La sécurité d'abord

- **Rien n'est supprimé sans vérification** : chaque analyse se termine sur un récapitulatif détaillé.
- **Tout passe par la Corbeille**, sauf ce qui y est déjà quand vous choisissez de la vider.
- **Un garde de sécurité** contrôle chaque élément juste avant d'y toucher : emplacements système, documents (pour les nettoyages automatiques), trousseaux, iCloud, bases Mail et Messages, et caches que macOS ne sait pas recréer sont refusés. Les liens symboliques sont résolus avant.
- **Les apps ouvertes** gardent leurs caches : ces éléments restent décochés.
- **Mode simulation** (Réglages) : tout fonctionne, rien n'est supprimé.
- **Exclusions** : indiquez les dossiers que Lucent ne doit jamais toucher.
- **Aucun réseau, aucune télémétrie.**

## Compiler

```bash
brew install xcodegen
git clone https://github.com/mbielle/lucent.git
cd lucent
xcodegen generate
open Lucent.xcodeproj
```

Pour de meilleurs résultats, donnez à Lucent l'**accès complet au disque** (Réglages Système › Confidentialité et sécurité). L'app vous guide.

## Feuille de route

- **0.2** : outil d'aide privilégié, Applications, Performances
- **0.3** : Protection, Encombrement, barre des menus, Mes outils
- **0.4** : Nettoyage cloud, analyses planifiées, DMG signé et notarisé, cask Homebrew

## Licence

Logiciel libre sous [licence GPL-3.0](LICENSE). Projet indépendant, sans lien avec MacPaw ni CleanMyMac.
