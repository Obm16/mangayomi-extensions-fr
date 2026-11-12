# Extensions MangaYomi — Animes FR

5 sources anime françaises (ou multilingues avec FR) pour [MangaYomi](https://github.com/kodjodevf/mangayomi), au format **Dart** (`MProvider`), compatibles avec le dépôt anime (`anime_index.json`).

## Sources

| Source | URL (à jour) | Statut |
|---|---|---|
| **AnimeSama** | https://anime-sama.to | Portée depuis `m2k3a/mangayomi-extensions` (Apache-2.0) — VOSTFR/VF/multi-voix, complète |
| **AnimesUltra** | https://animesultra.org | Portée depuis `m2k3a/mangayomi-extensions` (Apache-2.0) |
| **KissKH FR** | https://kisskh.do | Variante FR de la source KissKH (API JSON, sous-titres FR intégrés) |
| **Voiranime** | https://voir-anime.to | **Nouvelle** — thème Madara, hébergeurs VOE/Filemoon/Streamtape/myTV |
| **TenshiTV** | https://tenshitv.com | **Nouvelle** — ⚠️ Cloudflare actif, sélecteurs à valider dans l'app |

Les domaines de ces sites changent régulièrement (blocages ARCOM/FAI). Adresses vérifiées le 12/11/2026 via `recherche-stream.xyz`. Chaque source a une préférence « Changer l'url de base » pour suivre les changements de domaine sans mise à jour du code.

## Structure

```
anime_index.json                                  # catalogue (5 entrées)
dart/anime/src/fr/animesama/animesama.dart
dart/anime/src/fr/animesultra/animesultra.dart
dart/anime/src/fr/kisskhfr/kisskhfr.dart
dart/anime/src/fr/voiranime/voiranime.dart
dart/anime/src/fr/tenshitv/tenshitv.dart
```

## Installer dans l'app (sans compiler)

1. MangaYomi → onglet **Extensions** → **+**
2. Pour chaque source : nom, URL de base (voir tableau), langue `fr`, isManga = **false**
3. Ouvrir les réglages de la source → **Edit code** → coller le `.dart` correspondant
4. Tester avec **Fetch result** (getPopular, getDetail, getVideoList)

## Publier sur ton propre dépôt d'extensions

1. Créer un repo GitHub (fork de `m2k3a/mangayomi-extensions` ou repo vierge)
2. Pousser ces fichiers, remplacer `TON-COMPTE/TON-REPO` dans `anime_index.json`
3. Héberger le catalogue : GitHub Pages → l'URL `https://<compte>.github.io/<repo>/anime_index.json` s'ajoute dans MangaYomi (More → Settings → Browse → Add repository)
4. Ajouter une icône `icon.png` (24×24) par source et compléter `iconUrl`
5. Pour une PR vers `m2k3a/mangayomi-extensions` : importer les nouvelles sources dans `dart/anime/anime_source_list.dart`

## Notes techniques

- **Voiranime** : liste des épisodes directement dans la page anime (`li.wp-manga-chapter`) ; chaque hôte est une variante de l'URL d'épisode (`?host=LECTEUR VOE`…) avec un iframe à extraire.
- **AnimeSama** : épisodes exposés via `episodes.js` par saison ; multi-voix (VOSTFR/VF/VF1/VF2/VQ…) avec épisodes fusionnés par numéro.
- **KissKH** : API JSON pure (`/api/DramaList/...`), sous-titres chiffrés AES déchiffrés via `cryptoHandler`.
- **TenshiTV** : Cloudflare bloque toute inspection hors app ; le flag `hasCloudflare: true` active le contournement webview de MangaYomi. Si des sélecteurs ne matchent pas, ajuster dans l'éditeur de code de l'app (les logs/fetch result montrent le HTML réel).
