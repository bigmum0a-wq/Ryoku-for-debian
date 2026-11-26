# Ryoku for Debian — Guide de réinstallation & dépendances

Ce guide explique comment réinstaller **Ryoku Desktop** proprement sur une nouvelle installation de **Debian 13 (Trixie)** ou d'un système compatible basé sur Debian (`amd64`).

---

## Méthode 1 — Installation complète en ligne (via le dépôt APT)

### Option rapide (script automatique)
```bash
git clone https://github.com/bigmum0a-wq/Ryoku-for-debian.git
cd Ryoku-for-debian
bash debian-port/install-deps.sh
```

### Option manuelle (3 commandes sans cloner le dépôt)
```bash
curl -fsSL https://bigmum0a-wq.github.io/Ryoku-for-debian/ryoku-debian-release.pub.asc \
  | sudo gpg --yes --dearmor -o /usr/share/keyrings/ryoku-archive-keyring.gpg
sudo chmod 644 /usr/share/keyrings/ryoku-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/ryoku-archive-keyring.gpg] https://bigmum0a-wq.github.io/Ryoku-for-debian/apt trixie main" \
  | sudo tee /etc/apt/sources.list.d/ryoku.list >/dev/null
sudo chmod 644 /etc/apt/sources.list.d/ryoku.list

sudo apt-get update && sudo apt-get install -y ryoku-desktop
ryoku materialize
```

> Une fois `ryoku-archive-keyring` installé, `/etc/apt/sources.list.d/ryoku.sources` est configuré automatiquement ; tu peux supprimer `/etc/apt/sources.list.d/ryoku.list` pour éviter les doublons dans `apt update`.

---

## Méthode 2 — Réinstallation hors ligne (clé USB / archive `.tar.gz`)

1. Télécharge `ryoku-deb-repo-<version>.tar.gz` depuis [GitHub Releases](https://github.com/bigmum0a-wq/Ryoku-for-debian/releases).
2. Installe les dépendances système (si tu as internet uniquement pour APT Debian, ou depuis ton miroir local) :
   ```bash
   bash debian-port/install-deps.sh --deps-only
   ```
3. Extrais et installe les 7 paquets `.deb` :
   ```bash
   tar -xzf ryoku-deb-repo-*.tar.gz
   sudo dpkg -i out/pool/main/r/ryoku/ryoku-archive-keyring_*.deb
   sudo apt-get update || true
   sudo apt-get install -y out/pool/main/r/ryoku/*.deb
   ryoku materialize
   ```

---

## Méthode 3 — Recompiler les paquets `.deb` depuis les sources

1. Installe les dépendances de compilation :
   ```bash
   bash debian-port/install-deps.sh --build
   ```
   *(Assure-toi d'avoir **Go 1.26+** installé dans ton `PATH` pour compiler `ryoku-shell` et `ryoku-hub`.)*
2. Compile le dépôt APT complet :
   ```bash
   umask 0022
   bash debian/packages/repo/build-deb-repo.sh
   ```
   Les paquets générés se trouvent dans `debian/packages/repo/out/`.

---

## Liste des dépendances système

- **Compositeur & Shell :** `hyprland`, `quickshell`, `qml6-module-qtquick3d`
- **Portails & Session D-Bus :** `xdg-desktop-portal`, `xdg-desktop-portal-gtk`, `xdg-desktop-portal-hyprland`, `dbus-user-session`, `gnome-keyring`, `libsecret-1-0`
- **Audio, Vidéo & Capture :** `pipewire`, `wireplumber`, `playerctl`, `cava`, `ffmpeg`, `mpv`, `grim`, `slurp`, `wl-clipboard`, `tesseract-ocr`
- **Outils Hyprland & Thèmes :** `hyprpicker`, `hyprsunset`, `hypridle`, `qt6ct`, `papirus-icon-theme`
- **Utilitaires scripts Ryoku :** `python3`, `jq`, `socat`, `x11-xserver-utils` (`xhost`), `libglib2.0-bin` (`gsettings`)

---

## Après l'installation

1. Déconnecte-toi et choisis la session **Hyprland** sur ton écran de connexion (SDDM/GDM/LightDM).
2. Raccourcis utiles :
   - **`Super + ,`** : ouvrir les paramètres (**Ryoku Hub**)
   - **`Super + H`** : ranger la fenêtre active dans la pile en coin (`winstash`)
   - **`Super + Shift + H`** (ou clic sur la pile) : déployer les fenêtres rangées en arcs concentriques
   - **Clic prolongé** sur la pile : déplacer la pile n'importe où sur l'écran
