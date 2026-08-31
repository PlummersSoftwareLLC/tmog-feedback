#!/usr/bin/env bash
# Build and install the Task Manager TMOG Flatpak into the user installation.
set -euo pipefail
cd "$(dirname "$0")"

# flatpak-builder runs `appstreamcli compose` from PATH. A Homebrew appstreamcli
# ships without the compose addon and makes the build fail at the very last step,
# so make sure the distro one in /usr/bin wins.
if [ -x /usr/libexec/appstreamcli-compose ]; then
    export PATH="/usr/bin:$PATH"
fi

# The `flathub` remote exists in both system and user scope on some machines,
# so every flatpak command here is explicitly --user.
flatpak install --user --noninteractive --or-update flathub \
    org.kde.Platform//6.10 org.kde.Sdk//6.10

flatpak-builder --user --force-clean --repo=repo --install \
    build-dir com.tmog.taskmanager.yml

echo
echo "Installed. Run with:  flatpak run com.tmog.taskmanager"
