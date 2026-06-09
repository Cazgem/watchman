# Watchman v1.0.1
  __        __    ,_       _                           
  \ \      / /_ _ | |_ ___| |__  _ __ ___   __ _ _ __  
   \ \ /\ / / _` /  __/ __| '_ \| '_ ` _ \ / _` | '_ \ 
    \ V  V / (_| \\ || (__| | | | | | | | | (_| | | | |
     \_/\_/ \__,\_/\__\___|_| |_|_| |_| |_|\__,_|_| |_|
#              Watchman — Automated Git Steward

Automated Git Maintenance, Commit, Rebase, and Tagging System  
https://github.com/Cazgem/watchman

Watchman is a lightweight automation tool designed to keep your Git repositories clean, current, and production‑safe. It performs nightly maintenance across multiple repositories, ensuring:

- Automatic commits to `dev`
- Automatic rebasing of `dev` onto `main` (or `master`)
- Automatic tagging when `dev` is merged into the primary branch
- Automatic creation of missing `dev` branches
- Automatic creation of `main` if neither `main` nor `master` exists
- Clean, timestamped logging
- Stale rebase cleanup
- Hard‑coded repo support
- Optional per‑repo execution (`watchman -r /path/to/repo`)
- Health checks (`watchman doctor`)
- Status reporting (`watchman status`)

Watchman is designed for environments where:
- `main` is the live/production branch  
- `dev` is the working branch  
- You want automation without risking production stability  

---

## 🚀 Features

### 🔧 Automatic Maintenance
- Commits untracked/modified files to `dev`
- Rebases `dev` onto the primary branch
- Pushes changes safely (`--force-with-lease`)

### 🏷 Automatic Tagging
When you manually merge `dev` → `main`, Watchman detects it and creates a timestamped release tag.

### 🌿 Branch Management
- Creates `dev` if missing
- Detects `main` → falls back to `master`
- Creates `main` if neither exists

### 🩺 Health Tools
- `watchman status` — shows repo state
- `watchman doctor` — checks for common Git issues

### 🎯 Per‑Repo Execution
Run Watchman on a single repo:
watchman -r /path/to/repo
---

## 📦 Installation
Clone the repo:
git clone https://github.com/Cazgem/watchman
cd watchman

Install the script:
sudo cp watchman.sh /usr/local/bin/watchman
sudo chmod +x /usr/local/bin/watchman

Install the systemd service + timer:
sudo cp watchman.service /etc/systemd/system/
sudo cp watchman.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now watchman.timer

---

## 🕒 Systemd Timer

Watchman runs nightly at 2:00 AM by default.  
See `watchman.timer` for configuration.
---

## 🧪 Commands

### Run full scan:
watchman

### Run on a single repo:
watchman -r /srv/www/example/html

### Show status:
watchman status

### Run health checks:
watchman doctor
---

## 📄 Logging

Logs are stored at:
/var/log/nightly-commit-YYYY-MM-DD.log


---

## 🛡 Safety

Watchman **never touches `main` automatically**.  
You merge manually. Watchman only tags after detecting your merge.

---

## 📝 License

MIT License.
