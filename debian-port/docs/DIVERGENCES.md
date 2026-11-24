# Portage Ryoku pour Debian / Parrot / Kali (`debian/port`)

Ce document recense les divergences entre le projet **Ryoku** original (conçu pour Arch Linux / CachyOS) et le portage **Ryoku-for-debian** (testé sur Parrot Security 7.4 / Debian 13 Trixie et Kali Linux).  
Il est mis à jour au fil des correctifs avant la publication des prochaines releases `.deb`.

---

## 1. Divergences majeures avec le Ryoku original

### 1.1 Gestionnaire de paquets et `ryoku-cli`
- **Arch (`pacman` / AUR) → Debian (`apt` / `dpkg`)** :
  - Adaptation de `ryoku` et `ryoku-host` pour interroger l'état des paquets via `dpkg`/`apt` au lieu de `pacman` (commits `7042a3d2e`, `dc73ad65e`, `44171ef98`).
  - `ryoku doctor` ignore les vérifications propres à Arch/Btrfs/Limine (`pacman`, `mkinitcpio`, `snapper`).

### 1.2 Packaging Debian (`.deb` et dépôt APT)
- Construction de **7 paquets `.deb`** (`v1.1.0-1`, commits `313b5cc61`, `bfb642437`, `107a630a6`) :
  - `ryoku-archive-keyring`
  - `ryoku-blobs`
  - `ryoku-cli`
  - `ryoku-desktop`
  - `ryoku-desktop-hyprland`
  - `ryoku-palette-bridge`
  - `ryoku-shell`
- Génération d'un dépôt APT local via `debian/packages/repo/build-deb-repo.sh`.

### 1.3 Compatibilité Qt / Quickshell (`0.3.0`, Qt < 6.11)
Sur Debian/Parrot, la version de Qt6 est antérieure à Qt 6.11 :
- **Imports QML** : suppression du suffixe de version `6.11` (`import QtQuick 6.11` → `import QtQuick`) dans **112 fichiers QML** sous `quickshell/`.
- **Stubs QML de repli** ajoutés dans `debian/packages/stubs/` :
  - `QtQuick/Effects/RectangularShadow.qml`
  - `Ryoku/Blobs/CavaSpectrumPainter.qml`
- **Correctifs QML spécifiques** :
  - `shell/modules/sidebar/ControlsBoard.qml` (suppression de la propriété `acceptedButtons` non supportée).
  - `shell/modules/stage/StageBackdrop.qml`
  - `inir/modules/common/widgets/ContextMenu.qml`
  - `inir/modules/ii/overlay/OverlayWidgetDelegateChooser.qml`

> **État transitoire (`.deb v1.1.0-1`) :** Les paquets `.deb` v1.1.0-1 actuels déploient encore la version non patchée dans `/usr/share/ryoku/config/quickshell/`. Tant que les nouveaux `.deb` ne sont pas recompilés, les fichiers QML corrigés doivent être placés dans `~/.config/ryoku/user_edits/quickshell/` pour ne pas être écrasés lors d'un `ryoku materialize`.

---

## 2. Éléments manquants dans les `.deb v1.1.0-1` et contournements actuels

| Élément | Symptôme sans correctif | Solution appliquée actuellement | À faire pour la v1.2 / Release |
|---|---|---|---|
| **`ryogami`** (`/usr/bin/ryogami`) | `ryogami.service` échoue 5 fois (`status=203/EXEC`), fond transparent, `reload-cover` bloque **45s** puis affiche `DESKTOP FAILED TO LOAD`. | Binaire copié dans `~/.local/bin/ryogami` (ou `/usr/bin/ryogami`) + fork de `systemd/user/ryogami.service` dans `user_edits`. | Inclure `/usr/bin/ryogami` dans `ryoku-shell` ou `ryoku-desktop`. |
| **`ryoku-hub`** (`/usr/bin/ryoku-hub`) | Erreur `Unable to locate executable '/usr/bin/ryoku-hub'` sur `ExecStartPost` de `ryoku-shell.service`. | Binaire présent dans `~/.local/bin/ryoku-hub` + fork de `systemd/user/ryoku-shell.service` dans `user_edits`. | Inclure `/usr/bin/ryoku-hub` dans les `.deb`. |
| **Police `Material Symbols Rounded`** | Toutes les icônes du shell s'affichent sous forme de texte brut (ligatures : `wifi`, `bluetooth`, `work`, etc.). | Installation de `MaterialSymbolsRounded.ttf` dans `~/.local/share/fonts/MaterialSymbols/` + `fc-cache`. | Embarquer la police dans un paquet `.deb` ou post-install. |
| **Curseur `Bibata-Modern-Ice`** | Curseur bitmap par défaut dans Hyprland. | Archive extraite dans `~/.local/share/icons/Bibata-Modern-Ice/`. | Embarquer ou déclarer en dépendance. |
| **`ryoku-bluetooth-reset.service`** | Échec `Interactive authentication required` sur `systemctl restart bluetooth.service` au login. | Service masqué côté utilisateur (`systemctl --user mask ryoku-bluetooth-reset.service`). | Adapter le script ou une règle polkit. |
| **Fond par défaut Hyprland** | Splash/logo Hyprland visible si le fond est transparent. | `misc = { force_default_wallpaper = -1 }` ajouté dans `~/.config/hypr/user.lua`. | Intégrer par défaut dans `hypr/modules/misc.lua`. |

---

## 3. Dépendances logicielles externes

### 3.1 Paquets disponibles via `apt` (Debian / Parrot / Kali)
Ces outils sont requis pour les captures d'écran, presse-papiers, OCR, contrôle média, visualiseur audio, pipette, filtre lumière bleue et mise en veille :
```bash
sudo apt install -y \
  grim slurp wl-clipboard tesseract-ocr \
  playerctl cava hyprpicker hyprsunset hypridle
```

### 3.2 Outils installés hors `apt`
- **`matugen` (`v4.2.0`)** : installé dans `~/.local/bin/matugen` (binaire x86_64 depuis les releases GitHub `InioX/matugen`) pour l'extraction dynamique des couleurs du fond d'écran.
- **Optionnels non installés** : `tailscale`, `prowl`, `voxtype`.

---

## 4. Chemins suivis sur le système

- **Code source du portage** : `~/ryoku-debian-port` (sur cette machine : `/home/junior/.gemini/antigravity/scratch/ryoku-debian-port`, branche `debian/port`)
- **Configuration système shippée par les `.deb`** : `/usr/share/ryoku/config/`
- **Configuration matérialisée utilisateur** : `~/.config/` (générée par `ryoku materialize`)
- **Surcharges utilisateur protégées** : `~/.config/ryoku/user_edits/`
- **Configuration Hyprland utilisateur** : `~/.config/hypr/user.lua`
- **Preset d'animation actif** : `~/.config/ryoku/anim-preset` (presets disponibles dans `~/.config/hypr/modules/animations/`)
- **Fonds d'écran** : `~/Pictures/Wallpapers/` (images) et `~/Pictures/livewalls/` (vidéos `.mp4`/`.webm`)
- **Enregistrements vidéo** : `~/Videos/Recordings/`

---

## 5. Feuille de route (prochaines étapes)

- [ ] Recompiler les `.deb` en incluant `ryogami`, `ryoku-hub` et les correctifs QML (`QtQuick` sans `6.11`, `ControlsBoard.qml`, etc.) directement dans `/usr/share/ryoku/config/`.
- [ ] Ajouter les dépendances `apt` (`grim`, `slurp`, `wl-clipboard`, `tesseract-ocr`, `playerctl`, `cava`, `hyprpicker`, `hyprsunset`, `hypridle`) dans `debian/control`.
- [ ] Embarquer `MaterialSymbolsRounded.ttf`, `Bibata-Modern-Ice` et `matugen` dans le packaging ou le script d'installation unifié.
- [ ] Publier les paquets `.deb` et l'archive APT sur les **GitHub Releases** de `bigmum0a-wq/Ryoku-for-debian`.
