#!/bin/bash

get_largest_nvme_namespace() {
    # this function doesn't exist if the version is old enough, so we redefine it
    local largest size tmp_size dev
    size=0
    dev=$(basename "$1")

    for nvme in /sys/block/"${dev%n*}"*; do
        tmp_size=$(cat "${nvme}"/size)
        if [ "${tmp_size}" -gt "${size}" ]; then
            largest="${nvme##*/}"
            size="${tmp_size}"
        fi
    done
    echo "${largest}"
}

traps() {
    set +e
    trap 'last_command=$current_command; current_command=$BASH_COMMAND' DEBUG
    trap 'echo \"${last_command}\" command failed with exit code $?' EXIT
    trap '' INT
}

mush_info() {
    cat <<-EOF
Welcome to mush, the fakemurk developer shell.

If you got here by mistake, don't panic! Just close this tab and carry on.

This shell contains a list of utilities for performing various actions on a fakemurked chromebook.

This installation of fakemurk has been patched by murkmod. Don't report any bugs you encounter with it to the fakemurk developers.
EOF
}
doas() {
    ssh -t -p 1337 -i /rootkey -oStrictHostKeyChecking=no root@127.0.0.1 "$@"
}

runjob() {
    trap 'kill -2 $! >/dev/null 2>&1' INT
    (
        # shellcheck disable=SC2068
        $@
    )
    trap '' INT
}

swallow_stdin() {
    while read -t 0 notused; do
        read input
    done
}

edit() {
    if which nano 2>/dev/null; then
        doas nano "$@"
    else
        doas vi "$@"
    fi
}

main() {
    traps
    mush_info
    while true; do
        cat <<-EOF
(1) Root Shell
(2) Chronos Shell
(3) Plugins
(4) Crosh
(5) Powerwash
(6) Soft Disable Extensions
(7) Hard Disable Extensions
(8) Hard Enable Extensions
(9) Emergency Revert & Re-Enroll
(10) Edit Pollen
(11) Install plugins
(12) Uninstall plugins
(13) Run neofetch
(14) Check for updates
EOF
        if ! test -f /mnt/stateful_partition/crouton; then
            echo "(15) Install Crouton"
            echo "(16) Start Crouton (only run after running above)"
        fi

        
        swallow_stdin
        read -r -p "> (1-16): " choice
        case "$choice" in
        1) runjob doas bash ;;
        2) runjob bash ;;
        3) runjob show_plugins ;;
        4) runjob /usr/bin/crosh.old ;;
        5) runjob powerwash ;;
        6) runjob softdisableext ;;
        7) runjob harddisableext ;;
        8) runjob hardenableext ;;
        9) runjob revert ;;
        10) runjob edit /etc/opt/chrome/policies/managed/policy.json ;;
        11) runjob install_plugins ;;
        12) runjob uninstall_plugins ;;
        13) runjob do_neofetch ;;
        14) runjob do_updates ;;
        15) runjob install_crouton ;;
        16) runjob run_crouton ;;

        *) echo "----- Invalid option ------" ;;
        esac
    done
}

do_updates() {
    doas "bash <(curl -SLk https://raw.githubusercontent.com/rainestorme/murkmod/main/murkmod.sh)"
}

do_neofetch() {
    curl https://raw.githubusercontent.com/dylanaraps/neofetch/master/neofetch | bash
}

show_plugins() {
    clear
    
    plugins_dir="/mnt/stateful_partition/murkmod/plugins"
    plugin_files=()

    while IFS= read -r -d '' file; do
        plugin_files+=("$file")
    done < <(find "$plugins_dir" -type f -name "*.sh" -print0)

    plugin_info=()
    for file in "${plugin_files[@]}"; do
        plugin_script=$file
        PLUGIN_NAME=$(grep -o 'PLUGIN_NAME=".*"' "$plugin_script" | cut -d= -f2-)
        PLUGIN_FUNCTION=$(grep -o 'PLUGIN_FUNCTION=".*"' "$plugin_script" | cut -d= -f2-)
        PLUGIN_DESCRIPTION=$(grep -o 'PLUGIN_DESCRIPTION=".*"' "$plugin_script" | cut -d= -f2-)
        PLUGIN_AUTHOR=$(grep -o 'PLUGIN_AUTHOR=".*"' "$plugin_script" | cut -d= -f2-)
        PLUGIN_VERSION=$(grep -o 'PLUGIN_VERSION=".*"' "$plugin_script" | cut -d= -f2-)
        plugin_info+=("$PLUGIN_FUNCTION (provided by $PLUGIN_NAME)")
    done

    # Print menu options
    for i in "${!plugin_info[@]}"; do
        printf "%s. %s\n" "$((i+1))" "${plugin_info[$i]}"
    done

    # Prompt user for selection
    read -p "> Select a plugin (or q to quit): " selection

    if [ "$selection" = "q" ]; then
        return 0
    fi

    # Validate user's selection
    if ! [[ "$selection" =~ ^[1-9][0-9]*$ ]]; then
        echo "Invalid selection. Please enter a number between 0 and ${#plugin_info[@]}"
        return 1
    fi

    if ((selection < 1 || selection > ${#plugin_info[@]})); then
        echo "Invalid selection. Please enter a number between 0 and ${#plugin_info[@]}"
        return 1
    fi

    # Get plugin function name and corresponding file
    selected_plugin=${plugin_info[$((selection-1))]}
    selected_file=${plugin_files[$((selection-1))]}

    # Execute the plugin
    bash <(cat $selected_file) # weird syntax due to noexec mount
    return 0
}


install_plugins() {
  local raw_url="https://raw.githubusercontent.com/rainestorme/murkmod/main/plugins/"

  echo "Find a plugin you want to install here: "
  echo "  https://github.com/rainestorme/murkmod/tree/main/plugins"
  echo "Enter the name of a plugin (including the .sh) to install it (or q to quit):"
  read -r plugin_name

  while [[ $plugin_name != "q" ]]; do
    local plugin_url="$plugins_url/$plugin_name"
    local plugin_info=$(curl -s $plugin_url)

    if [[ $plugin_info == *"Not Found"* ]]; then
      echo "Plugin not found"
    else      
      doas "pushd /mnt/stateful_partition/murkmod/plugins && curl https://raw.githubusercontent.com/rainestorme/murkmod/main/plugins/$plugin_name -O $plugin_name && popd"
      echo "Installed $plugin_name"
    fi

    echo "Enter the name of a plugin (including the .sh) to install (or q to quit):"
    read -r plugin_name
  done
}


uninstall_plugins() {
    clear
    
    plugins_dir="/mnt/stateful_partition/murkmod/plugins"
    plugin_files=()

    while IFS= read -r -d '' file; do
        plugin_files+=("$file")
    done < <(find "$plugins_dir" -type f -name "*.sh" -print0)

    plugin_info=()
    for file in "${plugin_files[@]}"; do
        plugin_script=$file
        PLUGIN_NAME=$(grep -o 'PLUGIN_NAME=.*' "$plugin_script" | cut -d= -f2-)
        PLUGIN_FUNCTION=$(grep -o 'PLUGIN_FUNCTION=.*' "$plugin_script" | cut -d= -f2-)
        PLUGIN_DESCRIPTION=$(grep -o 'PLUGIN_DESCRIPTION=.*' "$plugin_script" | cut -d= -f2-)
        PLUGIN_AUTHOR=$(grep -o 'PLUGIN_AUTHOR=.*' "$plugin_script" | cut -d= -f2-)
        PLUGIN_VERSION=$(grep -o 'PLUGIN_VERSION=.*' "$plugin_script" | cut -d= -f2-)
        plugin_info+=("$PLUGIN_NAME (version $PLUGIN_VERSION by $PLUGIN_AUTHOR)")
    done

    if [ ${#plugin_info[@]} -eq 0 ]; then
        echo "No plugins installed. Select "
        return
    fi

    while true; do
        echo "Installed plugins:"
        for i in "${!plugin_info[@]}"; do
            echo "$(($i+1)). ${plugin_info[$i]}"
        done
        echo "0. Exit back to mush"
        read -r -p "Enter a number to uninstall a plugin, or 0 to exit: " choice

        if [ "$choice" -eq 0 ]; then
            clear
            return
        fi

        index=$(($choice-1))

        if [ "$index" -lt 0 ] || [ "$index" -ge ${#plugin_info[@]} ]; then
            echo "Invalid choice."
            continue
        fi

        plugin_file="${plugin_files[$index]}"
        PLUGIN_NAME=$(grep -o 'PLUGIN_NAME=".*"' "$plugin_file" | cut -d= -f2-)
        PLUGIN_FUNCTION=$(grep -o 'PLUGIN_FUNCTION=".*"' "$plugin_file" | cut -d= -f2-)
        PLUGIN_DESCRIPTION=$(grep -o 'PLUGIN_DESCRIPTION=".*"' "$plugin_file" | cut -d= -f2-)
        PLUGIN_AUTHOR=$(grep -o 'PLUGIN_AUTHOR=".*"' "$plugin_file" | cut -d= -f2-)
        PLUGIN_VERSION=$(grep -o 'PLUGIN_VERSION=".*"' "$plugin_file" | cut -d= -f2-)

        plugin_name="$PLUGIN_NAME (version $PLUGIN_VERSION by $PLUGIN_AUTHOR)"

        read -r -p "Are you sure you want to uninstall $plugin_name? [y/n] " confirm
        if [ "$confirm" == "y" ]; then
            doas rm "$plugin_file"
            echo "$plugin_name uninstalled."
            unset plugin_info[$index]
            plugin_info=("${plugin_info[@]}")
        fi
    done
}

powerwash() {
    echo "Are you sure you wanna powerwash? This will remove all user accounts and data, but won't remove fakemurk."
    sleep 2
    echo "(Press enter to continue, ctrl-c to cancel)"
    swallow_stdin
    read -r
    doas echo "fast safe" >/mnt/stateful_partition/factory_install_reset
    doas reboot
    exit
}

revert() {
    echo "This option will re-enroll your chromebook restore to before fakemurk was run. This is useful if you need to quickly go back to normal"
    echo "This is *permanent*. You will not be able to fakemurk again unless you re-run everything from the beginning."
    echo "Are you sure - 100% sure - that you want to continue? (press enter to continue, ctrl-c to cancel)"
    swallow_stdin
    read -r
    sleep 4
    echo "Setting kernel priority"

    DST=/dev/$(get_largest_nvme_namespace)

    if doas "(($(cgpt show -n "$DST" -i 2 -P) > $(cgpt show -n "$DST" -i 4 -P)))"; then
        doas cgpt add "$DST" -i 2 -P 0
        doas cgpt add "$DST" -i 4 -P 1
    else
        doas cgpt add "$DST" -i 4 -P 0
        doas cgpt add "$DST" -i 2 -P 1
    fi
    echo "Setting vpd"
    doas vpd.old -i RW_VPD -s check_enrollment=1
    doas vpd.old -i RW_VPD -s block_devmode=1
    doas crossystem.old block_devmode=1

    echo "Done. Press enter to reboot"
    swallow_stdin
    read -r
    echo "Bye!"
    sleep 2
    doas reboot
    sleep 1000
    echo "Your chromebook should have rebooted by now. If your chromebook doesn't reboot in the next couple of seconds, press Esc+Refresh to do it manually."
}
harddisableext() { # calling it "hard disable" because it only reenables when you press
    read -r -p "Enter extension ID > " extid
    chmod 000 "/home/chronos/user/Extensions/$extid"
    kill -9 $(pgrep -f "\-\-extension\-process")
}

hardenableext() {
    read -r -p "Enter extension ID > " extid
    chmod 777 "/home/chronos/user/Extensions/$extid"
    kill -9 $(pgrep -f "\-\-extension\-process")
}

softdisableext() {
    echo "Extensions will stay disabled until you press Ctrl+c or close this tab"
    while true; do
        kill -9 $(pgrep -f "\-\-extension\-process") 2>/dev/null
        sleep 0.5
    done
}
install_crouton() {
    echo "Installing Crouton on /mnt/stateful_partition"
    doas "bash <(curl -SLk https://goo.gl/fd3zc) -t xfce -r bullseye" && touch /mnt/stateful_partition/crouton
}
run_crouton() {
    echo "Use Crtl+Shift+Alt+Forward and Ctrl+Shift+Alt+Back to toggle between desktops"
    doas "startxfce4"
}

wrapper() {
  while true; do
    # call the main function
    main
    # if the main function exits, then something went wrong
    echo "Something went wrong. A root shell should be presented to you, and hopefully you can fix the issue."
    doas bash
  done
}

if [ "$0" = "$BASH_SOURCE" ]; then
    stty sane
    wrapper
fi
