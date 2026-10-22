<p align="center">
  <img src="App/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png" width="128" alt="Icône de Revive">
</p>

<h1 align="center">Revive</h1>

<p align="center">
  Un nettoyeur, optimiseur et antimalware pour Mac, gratuit et open source, développé nativement en SwiftUI.<br>
  <a href="README.md">English version</a>
</p>

---

Revive garde votre Mac propre, sûr et rapide, avec une interface soignée et sans abonnement. Ce genre d'outil est utile à tout le monde : il devrait être gratuit pour tout le monde.

> **État : préversion (0.4).** Tous les modules fonctionnent, mais ils n'ont pas encore été testés à grande échelle. Laissez le **mode simulation** activé (Réglages) tant que vous n'avez pas confiance, et signalez tout comportement étrange.

## Fonctionnalités

| Module | Ce qu'il fait |
|---|---|
| **Checkup** | En un clic : fichiers inutiles, protections intégrées (SIP, Gatekeeper, FileVault, pare-feu), recherche rapide de malwares, mémoire et mises à jour d'apps, avec un score de santé |
| **Nettoyage** | Fichiers système inutiles, encombrement IA, pièces jointes Mail, corbeilles |
| **Security** | Malwares détectés avec **les signatures XProtect d'Apple** (YARA), éléments de démarrage suspects, historique et cookies, extensions, réseaux Wi-Fi, autorisations des apps |
| **Optimisation** | Tâches de maintenance, éléments d'ouverture, agents et daemons, gros consommateurs de CPU et de mémoire |
| **Apps** | Désinstallation complète avec revue des restes, réinitialisation, restes d'apps supprimées, installeurs, mises à jour (Sparkle, App Store, Homebrew) |
| **Désencombrer** | Doublons (SHA-256), photos similaires (Vision d'Apple), gros fichiers anciens, captures d'écran |
| **Storage Map** | Carte en bulles navigable d'un dossier ou du disque |
| **Stockage cloud** | iCloud Drive, Google Drive, OneDrive, Dropbox : libérer les copies locales sans rien supprimer du cloud |
| **Raccourcis / Historique / barre des menus / analyses automatiques** | Outils épinglés, historique, moniteur en direct, alertes quand les fichiers inutiles s'accumulent |

## La sécurité d'abord

- **Rien n'est supprimé sans vérification**, et tout passe par la Corbeille.
- **Un garde de sécurité** contrôle chaque élément juste avant d'y toucher : emplacements système, documents (nettoyages automatiques), trousseaux, iCloud, bases Mail et Messages, apps et données d'Apple, caches que macOS ne sait pas recréer.
- **Les apps ouvertes** gardent leurs caches ; elles sont quittées avant d'être désinstallées.
- **Mode simulation** et **exclusions** dans les Réglages.
- **Vos données restent sur votre Mac.** Seules les vérifications de mises à jour contactent Internet.

## Installer

Téléchargez le DMG dans [Releases](https://github.com/mbielle/revive/releases), puis glissez Revive dans Applications. Donnez ensuite à Revive l'**accès complet au disque** quand il le demande.

## Compiler

```bash
brew install xcodegen
git clone https://github.com/mbielle/revive.git
cd revive
xcodegen generate
open Revive.xcodeproj
```

Pour tester sans toucher à vos fichiers : `swift scripts/make-demo-home.swift /tmp/ReviveDemo`, puis lancez l'app de debug avec `--args -home /tmp/ReviveDemo -dryRun YES`.

## Licence

Logiciel libre sous [licence GPL-3.0](LICENSE). Projet indépendant, sans lien avec MacPaw ni CleanMyMac.
