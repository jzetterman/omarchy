# ----------------------
# Helper functions
# ----------------------
check_process() {
  pgrep -u "$USER" "$1" >/dev/null 2>&1
  return $?
}

check_package() {
  yay -Qs "$1" >/dev/null 2>&1
  return $?
}

check_directory() {
  [ -d "$1" ] && [ "$(ls -A "$1")" ]
  return $?
}

install_pass() {
  # This is function is only required due to AUR instability. It appears
  # they have implemented rate limiting as a DDoS migtation measure and I
  # have run into this several times while testing which required me to
  # add retry logic to ensure keystore initialization is successful.

  # Install pass if not already installed
  echo "Installing pass..."
  max_retries=5
  retry_count=0
  success=false
  while [ $retry_count -lt $max_retries ] && [ "$success" != "true" ]; do
    ((retry_count++))
    echo "Attempt $retry_count of $max_retries..."

    output=$(yay -S --noconfirm --needed pass pass-secret-service-bin 2>&1 | tee /dev/tty)
    exit_status=$?

    # Handle installation failures due to AUR rate limiting
    if [ $exit_status -eq 0 ]; then
      echo "Package installed successfully."
      success=true
    elif echo "$output" | grep -q "\* status 429: Rate limit reached"; then
      echo "Error occurred while running yay."
      sleep 5
    else
      # Handle other errors
      echo "Other error occurred. Full output:"
      echo "$output"
      break # Exit loop on non-rate-limit errors
    fi
  done

  if [ "$success" != "true" ]; then
    echo "Failed to install package after $max_retries attempts."
    exit 1
  fi
}

# ----------------------
# Initialize flags
# ----------------------
gnome_keyring_in_use=0

# ----------------------
# Migration logic
# ----------------------
# STEP 1: Check for GNOME Keyring
echo -n "Checking for GNOME Keyring... "
if check_process "gnome-keyring" || check_package "gnome-keyring" || check_directory "$HOME/.local/share/keyrings"; then
  echo "GNOME Keyring is in use."
  gnome_keyring_in_use=1
else
  echo "GNOME Keyring not detected."
fi

# STEP 2: Generate GPG key non-interactively and capture output
GPG_OUTPUT=$(
  cat <<EOF | gpg --batch --generate-key 2>&1
%no-protection
Key-Type: RSA
Key-Length: 4096
Name-Real: Omarchy
Name-Email: omarchy@keyring.local
Expire-Date: 0
EOF
)

# STEP 3: Make sure we can get the GPG key ID from the output before we modify existing keyring solution
GPG_ID=$(echo "$GPG_OUTPUT" | grep 'openpgp-revocs.d' | grep -o '[A-F0-9]\{16\}\.rev' | cut -d'.' -f1)
if [ -z "$GPG_ID" ]; then
  echo "Error: Failed to find GPG key ID in output: $GPG_OUTPUT"
  exit 1
fi

# STEP 4: Summary and decision for pass
echo -e "\nSummary:"
if [ $gnome_keyring_in_use -eq 1 ]; then
  echo "WARNING - Gnome Keyring detected."

  # Get user confirmation to proceed
  choice=$(gum choose --header "Omarchy is migrating the OS keystore to pass. You will need to manually \
    migrate secrets from existing keyrings. Do you want to replace gnome-keyring with pass?" "No" "Yes")
  if [ "$choice" = "Yes" ]; then
    # Remove gnome-keyring
    echo "Removing GNOME Keyring..."
    pkill -u $USER gnome-keyring
    yay -Rns --noconfirm gnome-keyring
    mv ~/.local/share/keyrings ~/.local/share/gnome-keyrings-archiv

    # Install pass
    install_pass

    # Initialize pass
    if [ ! -d "$HOME/.password-store" ]; then
      echo "Initializing pass..."
      pass init $GPG_ID
    else
      echo "pass is already initialized."
    fi
    echo "pass has been set up. You will need to manually migrate secrets from existing keyrings."
  else
    echo "Declined to set up pass. Exiting."
    exit 0
  fi
else
  echo "No existing secrets backends detected. Safe to install and activate pass."
  # Install pass if not already installed
  install_pass

  # Initialize pass
  if [ ! -d "$HOME/.password-store" ]; then
    echo "Initializing pass..."
    pass init $GPG_ID
  else
    echo "pass is already initialized."
  fi
fi
