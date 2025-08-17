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

# ----------------------
# Initialize flags
# ----------------------
gnome_keyring_in_use=0

# Step 1: Check for GNOME Keyring
echo -n "Checking for GNOME Keyring... "
if check_process "gnome-keyring" || check_package "gnome-keyring" || check_directory "$HOME/.local/share/keyrings"; then
    echo "GNOME Keyring is in use."
    gnome_keyring_in_use=1
else
    echo "GNOME Keyring not detected."
fi

# Step 4: Create the GPG meta data
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

# Step 5: Summary and decision for pass
echo -e "\nSummary:"
if [ $gnome_keyring_in_use -eq 1 ] || [ $kwallet_in_use -eq 1 ] || [ $keepassxc_secrets_in_use -eq 1 ]; then
    echo "Existing secrets backend(s) detected."
    echo " - GNOME Keyring: $HOME/.local/share/keyrings"
    echo "WARNING: Setting up pass may conflict with existing secrets backends."
    echo "Gnome-keyring will be uninstalled, but your keyrings won't be modified."

    # Get user confirmation to proceed
    choice=$(gum choose --header "Existing keyrings have been detected. Do you want to replace the existing keyring with pass?" "No" "Yes")
    if [ "$choice" = "Yes" ]; then
        echo "Proceeding with pass installation and setup..."

        # Remove existing keyring solutions
        if [ $gnome_keyring_in_use -eq 1 ]; then
            echo "Removing GNOME Keyring..."
            yay -Rns gnome-keyring
        fi

        # Install pass if not already installed
        echo "Installing pass..."
        yay -S --noconfirm --needed pass pass-secret-service-bin

        # Initialize pass
        if [ ! -d "$HOME/.password-store" ]; then
            echo "Initializing pass..."
            pass init $GPG_OUTPUT
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
    echo "Installing pass..."
    yay -S --noconfirm --needed pass pass-secret-service-bin
    # Initialize pass
    if [ ! -d "$HOME/.password-store" ]; then
        echo "Initializing pass..."
        pass init $GPG_OUTPUT
    else
        echo "pass is already initialized."
    fi
fi
