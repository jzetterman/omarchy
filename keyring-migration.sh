# ----------------------
# Helper functions
# ----------------------
check_process() {
    pgrep -u "$USER" "$1" > /dev/null 2>&1
    return $?
}

check_package() {
    yay -Qs "$1" > /dev/null 2>&1
    return $?
}

check_directory() {
    [ -d "$1" ] && [ "$(ls -A "$1")" ]
    return $?
}

check_keepassxc_secrets() {
    # Check if KeePassXC is running and providing org.freedesktop.secrets via DBus
    if check_process "keepassxc" && dbus-send --session --dest=org.freedesktop.DBus --type=method_call --print-reply /org/freedesktop/DBus org.freedesktop.DBus.ListNames | grep -q "org.freedesktop.secrets"; then
        return 0
    fi
    # Check configuration for Secret Service integration
    if [ -f "$HOME/.config/keepassxc/keepassxc.ini" ]; then
        grep -q "SecretServiceIntegration=true" "$HOME/.config/keepassxc/keepassxc.ini" 2>/dev/null
        return $?
    fi
    return 1
}

# ----------------------
# Initialize flags
# ----------------------
gnome_keyring_in_use=0
kwallet_in_use=0
keepassxc_secrets_in_use=0

# Step 1: Check for GNOME Keyring
echo -n "Checking for GNOME Keyring... "
if check_process "gnome-keyring" || check_package "gnome-keyring" || check_directory "$HOME/.local/share/keyrings"; then
    echo "GNOME Keyring is in use."
    gnome_keyring_in_use=1
else
    echo "GNOME Keyring not detected."
fi

# Step 2: Check for KWallet
echo -n "Checking for KWallet... "
if check_process "kwalletd" || check_package "kwallet" || check_directory "$HOME/.local/share/kwallet5"; then
    echo "KWallet is in use."
    kwallet_in_use=1
else
    echo "KWallet not detected."
fi

# Step 3: Check for KeePassXC (Secret Service only)
echo -n "Checking for KeePassXC as secrets backend... "
if check_keepassxc_secrets; then
    echo "KeePassXC is in use as a secrets backend (Secret Service integration detected)."
    keepassxc_secrets_in_use=1
else
    echo "KeePassXC not detected as a secrets backend."
fi

# Step 4: Summary and decision for pass
echo -e "\nSummary:"
if [ $gnome_keyring_in_use -eq 1 ] || [ $kwallet_in_use -eq 1 ] || [ $keepassxc_secrets_in_use -eq 1 ]; then
    echo "Existing secrets backend(s) detected."
    echo " - GNOME Keyring: $HOME/.local/share/keyrings"
    echo " - KWallet: $HOME/.local/share/kwallet5"
    echo " - KeePassXC (secrets): $HOME/.config/keepassxc"
    echo "WARNING: Setting up pass may conflict with existing secrets backends."
    echo "Please back up your keyring data before proceeding."

    # Prompt user with gum
    choice=$(gum choose --header "Existing keyrings have been detected. Do you want to replace the existing keyring with pass?" "No" "Yes")
    if [ "$choice" = "Yes" ]; then
        echo "Proceeding with pass installation and setup..."
        # Install pass if not already installed
        if ! check_package "pass"; then
            echo "Installing pass..."
            sudo yay -S pass
        else
            echo "pass is already installed."
        fi

        if [ -z "$(git config user.name)" ] || [ -z "$(git config user.email)" ]; then
            GPG_OUTPUT=$(cat <<EOF | gpg --batch --generate-key 2>&1
%no-protection
Key-Type: RSA
Key-Length: 4096
Name-Real: Omarchy
Name-Email: omarchy@keyring.local
Expire-Date: 0
EOF
        )
        else
            GPG_OUTPUT=$(cat <<EOF | gpg --batch --generate-key 2>&1
%no-protection
Key-Type: RSA
Key-Length: 4096
Name-Real: $(git config user.name)
Name-Email: $(git config user.email)
Expire-Date: 0
EOF
        )
        fi

        # Initialize pass (assuming GPG key is already set up)
        if [ ! -d "$HOME/.password-store" ]; then
            echo "Initializing pass..."
            pass init <your-gpg-id>  # Replace with your GPG key ID or email
        else
            echo "pass is already initialized."
        fi
        echo "pass has been set up. You may need to manually migrate secrets from existing keyrings."
    else
        echo "Declined to set up pass. Exiting."
        exit 0
    fi
else
    echo "No existing secrets backends detected. Safe to install and activate pass."
    # Install pass if not already installed
    if ! check_package "pass"; then
        echo "Installing pass..."
        yay -S --noconfirm --needed pass pass-secret-service-bin
    else
        echo "pass is already installed."
    fi
    # Initialize pass (assuming GPG key is already set up)
    if [ ! -d "$HOME/.password-store" ]; then
        echo "Initializing pass..."
        pass init <your-gpg-id>  # Replace with your GPG key ID or email
    else
        echo "pass is already initialized."
    fi
fi
