<div align="center">

[English](README.md) | **Français**

# NicoFy

**Une application de streaming musical faite avec Flutter**

[![GitHub release](https://img.shields.io/github/v/release/nicotontige/NicoFy?color=D3BEAB)](https://github.com/nicotontige/NicoFy/releases)
[![License](https://img.shields.io/github/license/nicotontige/NicoFy?color=D3BEAB)](LICENSE)

<a href="https://buymeacoffee.com/nicotontige" target="_blank" title="Buy me a coffee">
  <img src="https://img.shields.io/badge/Buy%20me%20a%20coffee-nicotontige-FFDD00?logo=buymeacoffee&logoColor=black" alt="Buy me a coffee">
</a>

</div>

NicoFy est un fork de [Musify](https://github.com/gokadzev/Musify), de Valeri
Gokadze. Il est parti de Musify 10.6.0 et suit désormais son propre chemin,
avec ses propres versions, mises à jour et fonctionnalités.

---

## Fonctionnalités

### Écoute
- Recherche en ligne avec suggestions, résultats rangés par catégories
- Écoute hors ligne, avec les titres téléchargés signalés dans la recherche
- Lecture fiable : les titres sont lus depuis un fichier tampon et ne se coupent pas
- File d'attente conservée entre deux lancements, reprise au moment exact
- La file d'attente n'affiche que le titre en cours et la suite ; « précédent » fonctionne toujours
- Radio à partir du titre en cours : jusqu'à 25 titres proches remplacent la suite
- Choix automatique du titre suivant quand la file est vide : chansons, mixes ou les deux
- « Précédent » relance le titre quand on est au milieu
- Navigation par chapitres dans les longues compilations
- Paroles synchronisées
- Égaliseur avec préréglages, minuterie de mise en veille, SponsorBlock
- Stations de radio

### Bibliothèque
- Playlists personnelles, y compris depuis un lien YouTube, et dossiers de playlists
- Import de playlists Spotify
- Actions sur plusieurs titres à la fois, tri des playlists et des artistes par nom
- Récapitulatifs d'écoute
- Scrobbling vers Last.fm et ListenBrainz
- Import et export de vos données

### Android TV
- Pensée pour la télécommande : un écran « En lecture » qui s'ouvre sur Lecture/Pause, les flèches pour précédent/suivant et ±10 s
- Après une minute sans toucher la télécommande, le titre en cours s'affiche en plein écran
- L'élément sélectionné est clairement mis en évidence
- Un appui long sur OK sur un titre de la file ouvre son menu
- Commande vocale avec le bouton Assistant

### Android Auto
- Accès à la file d'attente, aux titres aimés, aux playlists, aux téléchargements et aux écoutes récentes
- Aimer un titre, lire une playlist en aléatoire et lancer une radio depuis la voiture

### Entre vos appareils
- Piloter la TV depuis le téléphone : voir ce qu'elle joue, mettre en pause, changer de titre, avancer, modifier sa file ; une fois connecté, tout ce que vous lancez sur le téléphone se joue sur la TV
- Synchronisation facultative de la bibliothèque sur le réseau local
- Les appareils s'appairent une seule fois avec un code PIN

### Et aussi
- Mises à jour dans l'application : téléchargées et installées depuis l'app, avec les notes de toutes les versions sautées
- Sans publicité, sans abonnement
- Material You : couleurs d'accent et couleurs dynamiques (Android 12+)
- 21 langues

---

## Captures d'écran

| ![Capture 1](https://raw.githubusercontent.com/nicotontige/NicoFy/master/fastlane/metadata/android/en-US/images/phoneScreenshots/01.jpg) | ![Capture 2](https://raw.githubusercontent.com/nicotontige/NicoFy/master/fastlane/metadata/android/en-US/images/phoneScreenshots/02.jpg) | ![Capture 3](https://raw.githubusercontent.com/nicotontige/NicoFy/master/fastlane/metadata/android/en-US/images/phoneScreenshots/03.jpg) | ![Capture 4](https://raw.githubusercontent.com/nicotontige/NicoFy/master/fastlane/metadata/android/en-US/images/phoneScreenshots/04.jpg) |
|----------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------|

---

## Plateformes

| Plateforme | État | Dépendances |
|----------|--------|--------------|
| Android (téléphone, Android TV, Android Auto) | ✅ Pris en charge | — |
| Linux    | ✅ Pris en charge (bêta) | libmpv |
| Windows    | ✅ Pris en charge (bêta) | — |
| iOS    | ❌ Non pris en charge | — |

---

## Téléchargement

[<img src="https://github.com/nicotontige/NicoFy/raw/master/.github/assets/get-it-on-github.png" alt="Disponible sur GitHub" height="80">](https://github.com/nicotontige/NicoFy/releases/latest)

---

## Contribuer

Les contributions sont les bienvenues. Merci de lire le [guide de contribution](CONTRIBUTING.md) (en anglais) avant de commencer.

---

## Remerciements

- [Musify](https://github.com/gokadzev/Musify) de Valeri Gokadze et ses
  contributeurs : NicoFy est construit sur son code, sous la même licence.
- [Musify](https://github.com/Harsh-23/Musify) de Harsh-23 : l'inspiration
  d'origine du concept et du nom de Musify.

---

## Licence

```
Copyright © 2026 Valeri Gokadze (Musify)
Copyright © 2026 Nicolas Manceau (modifications NicoFy)

NicoFy est un logiciel libre sous licence GPL v3.0, comme Musify, dont il est
une version modifiée. Vous pouvez l'utiliser, le modifier et le distribuer
librement, à condition de garder le code source ouvert et public, de conserver
toutes les mentions de copyright, d'indiquer les modifications apportées et
d'utiliser la même licence GPL v3.0.
```

Le texte complet est dans la [GNU General Public License](LICENSE) (en anglais).

---

## Avertissement

```
NicoFy et ses contributeurs n'hébergent, ne possèdent ni ne distribuent aucun contenu audio protégé par le droit d'auteur.
L'application donne accès à des contenus via des modules et des sources externes. Les marques, chansons, fichiers audio et contenus associés restent la propriété de leurs détenteurs respectifs et sont protégés par le droit d'auteur applicable.
Les modules inclus sont fournis à des fins d'interopérabilité et d'apprentissage uniquement. Chaque utilisateur est seul responsable du respect des lois locales, du droit d'auteur et des conditions d'utilisation des fournisseurs de contenu.
Les développeurs de NicoFy n'encouragent ni ne cautionnent la violation du droit d'auteur et déclinent toute responsabilité en cas d'usage abusif du logiciel ou de modules tiers.
```
---
