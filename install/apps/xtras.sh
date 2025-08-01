#!/bin/bash

if [ -z "$OMARCHY_BARE" ]; then
  yay -S --noconfirm --needed \
    gnome-calculator gnome-keyring signal-desktop \
    obsidian-bin libreoffice obs-studio kdenlive \
    xournalpp localsend-bin

  # Packages known to be flaky or having key signing issues are run one-by-one
  for pkg in pinta typora spotify zoom; do
    yay -S --noconfirm --needed "$pkg" ||
      echo -e "\e[31mFailed to install $pkg. Continuing without!\e[0m"
  done

  yay -S --noconfirm --needed 1password-beta 1password-cli ||
    echo -e "\e[31mFailed to install 1password. Continuing without!\e[0m"
fi

# Copy over Omarchy applications
source ~/.local/share/omarchy/bin/omarchy-refresh-applications || true

# If no existing keyrings, set up login.keyring with no password as the default keyring.
# This allows, for example, 1Password to store MFA tokens automatically.
if [ -z "$(find ~/.local/share/keyrings/ -maxdepth 1 -type f)" ]; then
    echo "Creating default keyring..." | tee -a ~/omarchy-install.log
    pkill gnome-keyring-d || true
    eval "$(gnome-keyring-daemon --start --components=pkcs11,secrets,ssh)"
    echo '' | gnome-keyring-daemon --unlock
fi
