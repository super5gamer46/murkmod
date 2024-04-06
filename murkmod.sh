#!/bin/bash

CURRENT_MAJOR=6
CURRENT_MINOR=0
CURRENT_VERSION=0

if [[ -z "${MURKMOD_BRANCH}" ]]; then
  BRANCH="main"
else
  BRANCH="${MURKMOD_BRANCH}"
fi

get_asset() {
    curl -s -f "https://api.github.com/repos/super5gamer46/murkmod/contents/$1?ref=$BRANCH" | jq -r ".content" | base64 -d
}

get_asset_fakemurk() {
    curl -s -f "https://api.github.com/repos/MercuryWorkshop/fakemurk/contents/$1" | jq -r ".content" | base64 -d
}

get_built_asset_fakemurk() {
    curl -SLk "https://github.com/MercuryWorkshop/fakemurk/releases/latest/download/1"
}

install() {
    TMP=$(mktemp)
    get_asset "$1" >"$TMP"
    if [ "$?" == "1" ] || ! grep -q '[^[:space:]]' "$TMP"; then
        echo "Failed to install $1 to $2"
        rm -f "$TMP"
        exit
    fi
    # Don't mv, that would break permissions
    cat "$TMP" >"$2"
    rm -f "$TMP"
}

install_fakemurk() {
    TMP=$(mktemp)
    get_asset_fakemurk "$1" >"$TMP"
    if [ "$?" == "1" ] || ! grep -q '[^[:space:]]' "$TMP"; then
        echo "Failed to install $1 to $2"
        rm -f "$TMP"
        exit
    fi
    # Don't mv, that would break permissions
    cat "$TMP" >"$2"
    rm -f "$TMP"
}

install_built_fakemurk() {
    TMP=$(mktemp)
    get_built_asset_fakemurk "$1" >"$TMP"
    if [ "$?" == "1" ] || ! grep -q '[^[:space:]]' "$TMP"; then
        echo "failed to install $1 to $2"
        rm -f "$TMP"
        return 1
    fi
    cat "$TMP" >"$2"
    rm -f "$TMP"
}

if [ "$BRANCH" != "main" ]; then
    echo "Using branch $BRANCH - Keep in mind any alternate branches can be unstable and are not reccomended!"
    if [ "$0" != "/usr/local/tmp/murkmod.sh" ]; then
        echo "Fetching installer on alternate branch..."
        mkdir -p /usr/local/tmp
        install "murkmod.sh" /usr/local/tmp/murkmod.sh
        chmod 755 /usr/local/tmp/murkmod.sh
        clear
        echo "Handing over to alternate branch..."
        MURKMOD_BRANCH=$BRANCH /usr/local/tmp/murkmod.sh
        exit 0
    else
        echo "Running installer from branch $BRANCH!"
    fi
fi

show_logo() {
    echo -e "                      __                      .___\n  _____  __ _________|  | __ _____   ____   __| _/\n /     \|  |  \_  __ \  |/ //     \ /  _ \ / __ | \n|  Y Y  \  |  /|  | \/    <|  Y Y  (  <_> ) /_/ | \n|__|_|  /____/ |__|  |__|_ \__|_|  /\____/\____ | \n      \/                  \/     \/            \/\n"
    echo "        The fakemurk plugin manager - v$CURRENT_MAJOR.$CURRENT_MINOR.$CURRENT_VERSION"
}

lsbval() {
  local key="$1"
  local lsbfile="${2:-/etc/lsb-release}"

  if ! echo "${key}" | grep -Eq '^[a-zA-Z0-9_]+$'; then
    return 1
  fi

  sed -E -n -e \
    "/^[[:space:]]*${key}[[:space:]]*=/{
      s:^[^=]+=[[:space:]]*::
      s:[[:space:]]+$::
      p
    }" "${lsbfile}"
}

install_patched_files() {
    install "daemon.sh" /sbin/murkmod-daemon.sh
    local milestone=$(lsbval CHROMEOS_RELEASE_CHROME_MILESTONE $ROOT/etc/lsb-release)
    if [ "$milestone" -gt "116" ]; then
        echo "Detected v116 or higher, using new chromeos_startup"
        install "chromeos_startup.sh" /sbin/chromeos_startup
        touch /new-startup
    else
        install "chromeos_startup.sh" /sbin/chromeos_startup.sh
    fi
    install "mush.sh" /usr/bin/crosh
    install "pre-startup.conf" /etc/init/pre-startup.conf
    install "cr50-update.conf" /etc/init/cr50-update.conf
    install "ssd_util.sh" /usr/share/vboot/bin/ssd_util.sh
    install "image_patcher.sh" /sbin/image_patcher.sh
    chmod 777 /sbin/murkmod-daemon.sh /sbin/chromeos_startup.sh /sbin/chromeos_startup /usr/bin/crosh /usr/share/vboot/bin/ssd_util.sh /sbin/image_patcher.sh
}

create_stateful_files() {
    # This is only here for backwards compatibility
    touch /mnt/stateful_partition/murkmod_version
    echo "$CURRENT_MAJOR $CURRENT_MINOR $CURRENT_VERSION" > /mnt/stateful_partition/murkmod_version
    
    mkdir -p /mnt/stateful_partition/murkmod/plugins
    touch /mnt/stateful_partition/murkmod/settings
    if [ ! -f /mnt/stateful_partition/murkmod/settings ]; then
        echo "# ----- murkmod settings -----" > /mnt/stateful_partition/murkmod/settings
        echo "" >> /mnt/stateful_partition/murkmod/settings
        echo "# this file is unused for now, but this might change" >> /mnt/stateful_partition/murkmod/settings
    fi
}

check_for_emergencyshell() {
    if test -d "/home/chronos/user/Downloads/fix-mush"; then
        echo "Running from emergency shell, reverting..."
        rm -Rf /home/chronos/user/Downloads/fix-mush
    fi
}

do_policy_patch() {
    url1="https://raw.githubusercontent.com/rainestorme/murkmod/main/pollen.json"
    url2="https://raw.githubusercontent.com/MercuryWorkshop/fakemurk/main/pollen.json"
    response1=$(curl -s "$url1")
    response2=$(curl -s "$url2")

    if [ "$response1" = "$response2" ]; then
        install "pollen.json" /etc/opt/chrome/policies/managed/policy.json
    else
        read -r -p "Use murkmod reccomended pollen config? [Y/n] " choice
        case "$choice" in
            n | N) install_fakemurk "pollen.json" /etc/opt/chrome/policies/managed/policy.json ;;
            *) install "pollen.json" /etc/opt/chrome/policies/managed/policy.json ;;
        esac
    fi
}

set_chronos_password() {
    echo -en "murkmod\nmurkmod\n" | passwd chronos > /dev/null
}

set_sudo_perms() {
    if ! cat /etc/sudoers | grep chronos; then
        echo "Sudo permissions are not already set, setting..."
        echo "chronos ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers 
    else
        echo "Looks like sudo permissions are already set correctly."
    fi
}

collect_analytics() {
    hwid=$(crossystem.old hwid)
    
    if [ ! -f /mnt/stateful_partition/murkmod/method_collected ]; then
        read -r -p "Did you use sh1mmer to unenroll this device? Reply with N if you used a different method. [y/N] " choice
        case "$choice" in
            y | Y) used_sh1mmer="yes" && touch /mnt/stateful_partition/murkmod/method_collected ;;
            *) used_sh1mmer="no" && touch /mnt/stateful_partition/murkmod/method_collected ;;
        esac
        curl -X POST \
             -H "Content-Type: application/json" \
             -d "{\"hwid\":\"${hwid}\",\"method\":\"${used_sh1mmer}\"}" \
             https://murkmod-analytics.besthaxer.repl.co/addmethod > /dev/null
    fi
    if [ ! -f /mnt/stateful_partition/murkmod/guide_collected ]; then
        read -r -p "Did you use the Chromebook Exploit Guide (chromebook-guide.github.io) to fakemurk your device? [y/N] " choice
        case "$choice" in
            y | Y) used_guide="yes" && touch /mnt/stateful_partition/murkmod/guide_collected ;;
            *) used_guide="no" && touch /mnt/stateful_partition/murkmod/guide_collected ;;
        esac
        curl -X POST \
             -H "Content-Type: application/json" \
             -d "{\"hwid\":\"${hwid}\",\"guide\":\"${used_guide}\"}" \
             https://murkmod-analytics.besthaxer.repl.co/addguide > /dev/null
    fi

    fakemurk_version=$(cat /mnt/stateful_partition/fakemurk_version | base64 -w 0 || echo "")
    murkmod_version=$(cat /mnt/stateful_partition/murkmod_version | base64 -w 0)
    release_board=$(lsbval CHROMEOS_RELEASE_BOARD)
    devicetype=$(lsbval DEVICETYPE)
    auserver=$(lsbval CHROMEOS_AUSERVER)
    chromeos_version=$(lsbval CHROMEOS_RELEASE_DESCRIPTION)
    build_type=$(lsbval CHROMEOS_RELEASE_BUILD_TYPE)
    chrome_milestone=$(lsbval CHROMEOS_RELEASE_CHROME_MILESTONE)
    release_track=$(lsbval CHROMEOS_RELEASE_TRACK)
    curl -X POST \
         -H "Content-Type: application/json" \
         -d "{\"murkmod_version\":\"${murkmod_version}\",\"fakemurk_version\":\"${fakemurk_version}\",\"hwid\":\"${hwid}\",\"release_board\":\"${release_board}\",\"devicetype\":\"${devicetype}\",\"auserver\":\"${auserver}\",\"cros_version\":\"${chromeos_version}\",\"build_type\":\"${build_type}\",\"chrome_milestone\":\"${chrome_milestone}\",\"release_track\":\"${release_track}\"}" \
         https://murkmod-analytics.besthaxer.repl.co/analytics > /dev/null
    echo "Analytics collected."
}

get_analytics_permission() {
    echo "Analytics are completely anonymous - based on HWID only. It only collects basic information about your device and requires only minimal information on your part."
    echo "Although I would greatly appreciate it if you opt in, this is completely optional and you can opt out at any time by deleting /mnt/stateful_partition/murkmod/analytics_opted_in."
    read -r -p "Opt-in to analytics? [y/N] " choice
    case "$choice" in
        y | Y) collect_analytics && touch /mnt/stateful_partition/murkmod/analytics_opted_in ;;
        *) echo "Opting out of analytics." && touch /mnt/stateful_partition/murkmod/analytics_opted_out ;;
    esac
}

set_cros_debug() {
    sed -i "s/\(cros_debug=\).*/\11/" /usr/bin/crossystem
}

check_legacy_daemon() {
    if [ -f /sbin/fakemurk-daemon.sh ]; then
        echo "Found legacy fakemurk daemon, removing..."
        kill $(pgrep fakemurk)
        rm -f /sbin/fakemurk-daemon.sh
        mkdir -p /var/murkmod
        echo "Restarting daemon..."
        /sbin/murkmod-daemon.sh >/var/murkmod/daemon-log 2>&1 &
    fi
}

murkmod() {
    show_logo
    if [ "$1" != "--dryrun" ]; then
        if [ ! -f /sbin/fakemurk-daemon.sh ]; then
            if [ ! -f /sbin/murkmod-daemon.sh ]; then
                echo "Either your system has a broken fakemurk/murkmod installation or your system doesn't have a fakemurk or murkmod installation at all. (Re)install fakemurk/murkmod, then re-run this script."
                exit
            fi
        fi
        echo "Checking for emergency shell..."
        check_for_emergencyshell
        echo "Installing patched files..."
        install_patched_files
        echo "Checking for legacy fakemurk daemon..."
        check_legacy_daemon
        echo "Creating stateful partition files..."
        create_stateful_files
        echo "Patching policy..."
        do_policy_patch
        echo "Setting chronos user password..."
        set_chronos_password
        echo "Checking sudo perms..."
        set_sudo_perms
        echo "Setting crossystem cros_debug..."
        set_cros_debug
        if [ ! -f /mnt/stateful_partition/murkmod/analytics_opted_in ]; then
            if [ ! -f /mnt/stateful_partition/murkmod/analytics_opted_out ]; then
                get_analytics_permission
            fi
        else
            collect_analytics
        fi
    fi
    read -n 1 -s -r -p "Done. If cros_debug was enabled for the first time, a reboot may be required. Press any key to exit."
    exit
}

if [ "$0" = "$BASH_SOURCE" ]; then
    if [ "$EUID" -ne 0 ]; then
        echo "Please run this as root from mush. Use option 1 (root shell) instead of any other method of getting to a shell."
        exit
    fi
    murkmod
fi
