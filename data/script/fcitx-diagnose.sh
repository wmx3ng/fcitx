#!/usr/bin/env bash

shopt -s extglob nullglob globstar
export TEXTDOMAIN=fcitx

__test_bash_unicode() {
    local magic_str='${1}'$'\xe4'$'\xb8'$'\x80'
    local magic_replace=${magic_str//\$\{/$'\n'$\{}
    ! [ "${magic_str}" = "${magic_replace}" ]
}

if type gettext &> /dev/null && __test_bash_unicode; then
    _() {
        gettext "$@"
    }
else
    _() {
        echo "$@"
    }
fi

#############################
# utility
#############################

array_push() {
    eval "${1}"'=("${'"${1}"'[@]}" "${@:2}")'
}

_find_file() {
    local "${1}"
    eval "${2}"'=()'
    while IFS= read -r -d '' "${1}"; do
        array_push "${2}" "${!1}"
    done < <(find "${@:3}" -print0)
}

find_file() {
    if [[ ${1} = __find_file_line ]]; then
        _find_file __find_file_line2 "$@"
    else
        _find_file __find_file_line "$@"
    fi
}

str_match_glob() {
    local pattern=$1
    local str=$2
    case "$2" in
        $pattern)
            return 0
            ;;
    esac
    return 1
}

str_match_regex() {
    local pattern=$1
    local str=$2
    [[ $str =~ $pattern ]]
}

add_and_check_file() {
    local prefix="$1"
    local file="$2"
    local inode
    inode="$(stat -L --printf='%i' "${file}" 2> /dev/null)" || return 0
    local varname="___add_and_check_file_${prefix}_${inode}"
    [ ! -z "${!varname}" ] && return 1
    eval "${varname}=1"
    return 0
}

unique_file_array() {
    for f in "${@:3}"; do
        add_and_check_file "${1}" "${f}" && {
            array_push "${2}" "${f}"
        }
    done
}

print_array() {
    for ele in "$@"; do
        echo "${ele}"
    done
}

repeat_str() {
    local i
    local n="$1"
    local str="$2"
    local res=""
    for ((i = 0;i < n;i++)); do
        res="${res}${str}"
    done
    echo "${res}"
}

# require `shopt -s nullglob` and the argument needs to be a glob
find_in_path() {
    local w="$1"
    local IFS=':'
    local p
    local f
    local fs
    for p in ${PATH}; do
        eval 'fs=("${p}/"'"${w}"')'
        for f in "${fs[@]}"; do
            echo "$f"
        done
    done
}

run_grep_fcitx() {
    "$@" | grep fcitx
}

get_config_dir() {
    local conf_option="$1"
    local default_name="$2"
    for path in "$(fcitx4-config "--${conf_option}" 2> /dev/null)" \
        "/usr/share/fcitx/${default_name}" \
        "/usr/local/share/fcitx/${default_name}"; do
        [ ! -z "${path}" ] && [ -d "${path}" ] && {
            echo "${path}"
            return 0
        }
    done
    return 1
}

get_from_config_file() {
    local file="$1"
    local key="$2"
    local value
    value=$(sed -ne "s=^${key}\=\(.*\)=\1=gp" "$file" 2> /dev/null)
    [ -z "$value" ] && return 1
    echo "${value}"
    return 0
}

get_locale() {
    local name=$1
    str_match_glob 'LC_*' "$name" || str_match_glob 'LANG' "$name" || {
        name="LC_$name"
    }
    [ -z "${LC_ALL}" ] || {
        echo "${LC_ALL}"
        return
    }
    [ -z "${!name}" ] || {
        echo "${!name}"
        return
    }
    [ -z "${LANG}" ] || {
        echo "${LANG}"
        return
    }
    echo "POSIX"
}

if type dbus-send &> /dev/null; then
    dbus_get_name_owner() {
        local address
        address=$(dbus-send --print-reply=literal --dest=org.freedesktop.DBus \
            /org/freedesktop/DBus org.freedesktop.DBus.GetNameOwner \
            "string:$1" 2> /dev/null) || return 1
        echo -n "${address##* }"
    }
    dbus_get_pid() {
        local pid
        pid=$(dbus-send --print-reply=literal --dest=org.freedesktop.DBus \
            /org/freedesktop/DBus org.freedesktop.DBus.GetConnectionUnixProcessID \
            "string:$1" 2> /dev/null) || return 1
        echo -n "${pid##* }"
    }
elif qdbus_exe=$(which qdbus 2> /dev/null) || \
    qdbus_exe=$(which qdbus-qt4 2> /dev/null); then
    dbus_get_name_owner() {
        local address
        "${qdbus_exe}" org.freedesktop.DBus /org/freedesktop/DBus \
            org.freedesktop.DBus.GetNameOwner "$1" 2> /dev/null
    }
    dbus_get_pid() {
        "${qdbus_exe}" org.freedesktop.DBus /org/freedesktop/DBus \
            org.freedesktop.DBus.GetConnectionUnixProcessID "$1" 2> /dev/null
    }
else
    dbus_get_name_owner() {
        return 1
    }
    dbus_get_pid() {
        return 1
    }
fi

print_process_info() {
    ps -o pid=,args= --pid "$1" 2> /dev/null && return
    cmdline=''
    [[ -d /proc/$1 ]] && {
        cmdline=$(cat /proc/$1/cmdline) || cmdline=$(cat /proc/$1/comm) || \
            cmdline=$(readlink /proc/$1/exe)
    } 2> /dev/null
    echo "$1 ${cmdline}"
}

_detectDE_XDG_CURRENT() {
    case "${XDG_CURRENT_DESKTOP}" in
        GNOME)
            DE=gnome
            ;;
        KDE)
            DE=kde
            ;;
        LXDE)
            DE=lxde
            ;;
        XFCE)
            DE=xfce
            ;;
        *)
            return 1
            ;;
    esac
}

_detectDE_classic() {
    if [ x"$KDE_FULL_SESSION" = x"true" ]; then
        DE=kde
    elif xprop -root KDE_FULL_SESSION 2> /dev/null | \
        grep ' = \"true\"$' > /dev/null 2>&1; then
        DE=kde
    elif [ x"$GNOME_DESKTOP_SESSION_ID" != x"" ]; then
        DE=gnome
    elif [ x"$MATE_DESKTOP_SESSION_ID" != x"" ]; then
        DE=mate
    elif dbus_get_name_owner org.gnome.SessionManager > /dev/null; then
        DE=gnome
    elif xprop -root _DT_SAVE_MODE 2> /dev/null | \
        grep ' = \"xfce4\"$' >/dev/null 2>&1; then
        DE=xfce
    elif xprop -root 2> /dev/null | \
        grep -i '^xfce_desktop_window' >/dev/null 2>&1; then
        DE=xfce
    else
        return 1
    fi
}

_detectDE_SESSION() {
    case "$DESKTOP_SESSION" in
        gnome)
            DE=gnome
            ;;
        LXDE|Lubuntu)
            DE=lxde
            ;;
        xfce|xfce4|'Xfce Session')
            DE=xfce
            ;;
        *)
            return 1
            ;;
    esac
}

_detectDE_uname() {
    case "$(uname 2>/dev/null)" in
        Darwin)
            DE=darwin
            ;;
        *)
            return 1
            ;;
    esac
}

detectDE() {
    # see https://bugs.freedesktop.org/show_bug.cgi?id=34164
    unset GREP_OPTIONS

    _detectDE_XDG_CURRENT || _detectDE_classic || \
        _detectDE_SESSION || _detectDE_uname || {
        DE=generic
    }
    if [ x"$DE" = x"gnome" ]; then
        # gnome-default-applications-properties is only available in GNOME 2.x
        # but not in GNOME 3.x
        which gnome-default-applications-properties > /dev/null 2>&1 || \
            DE="gnome3"
        which gnome-shell &> /dev/null && DE="gnome3"
    fi
}

maybe_gnome3() {
    [[ $DE = gnome3 ]] && return 0
    [[ $DE = generic ]] && which gnome-shell &> /dev/null && return 0
    return 1
}

detectDE

#############################
# print
#############################

# tty and color
__istty=0

check_istty() {
    [ -t 1 ] && {
        __istty=1
    } || {
        __istty=0
    }
}

print_tty_ctrl() {
    ((__istty)) || return
    echo -ne '\e['"${1}"'m'
}

replace_reset() {
    local line
    local IFS=$'\n'
    if [ ! -z "$1" ]; then
        while read line; do
            echo "${line//$'\e'[0m/$'\e'[${1}m}"
        done
        [ -z "${line}" ] || {
            echo -n "${line//$'\e'[0m/$'\e'[${1}m}"
        }
    else
        cat
    fi
}

__replace_line() {
    local IFS=$'\n'
    local __line=${1//\$\{/$'\n'$\{}
    shift
    local __varname
    echo "${__line}" | while read __line; do
        if [[ ${__line} =~ ^\$\{([_a-zA-Z0-9]+)\} ]]; then
            __varname="${BASH_REMATCH[1]}"
            echo -n "${__line/\$\{${__varname}\}/${!__varname}}"
        else
            echo -n "${__line}"
        fi
    done
    echo
}

__replace_vars() {
    local IFS=$'\n'
    local __line
    while read __line; do
        __replace_line "${__line}" "$@"
    done
    [ -z "${__line}" ] || {
        echo -n "$(__replace_line "${__line}" "$@")"
    }
}

print_eval() {
    echo "$1" | __replace_vars "${@:2}"
}

# print inline
code_inline() {
    print_tty_ctrl '01;36'
    echo -n '`'"$1"'`' | replace_reset '01;36'
    print_tty_ctrl '0'
}

print_link() {
    local text="$1"
    local url="$2"
    print_tty_ctrl '01;33'
    echo -n "[$text]($url)" | replace_reset '01;33'
    print_tty_ctrl '0'
}

print_not_found() {
    print_eval "$(_ '${1} not found.')" "$(code_inline $1)"
}

# indent levels and list index counters
__current_level=0
__list_indexes=(0)

set_cur_level() {
    local level="$1"
    local indexes=()
    local i
    if ((level >= 0)); then
        ((__current_level = level))
        for ((i = 0;i <= __current_level;i++)); do
            ((indexes[i] = __list_indexes[i]))
        done
        __list_indexes=("${indexes[@]}")
    else
        ((__current_level = 0))
        __list_indexes=()
    fi
}

increase_cur_level() {
    local level="$1"
    ((level = __current_level + level))
    set_cur_level "$level"
}

# print blocks
__need_blank_line=0

write_paragraph() {
    local str="$1"
    local p1="$2"
    local p2="$3"
    local code="$4"
    local prefix="$(repeat_str "${__current_level}" "    ")"
    local line
    local i=0
    local whole_prefix
    local IFS=$'\n'
    ((__need_blank_line)) && echo
    [ -z "${code}" ] || print_tty_ctrl "${code}"
    {
        while read line; do
            ((i == 0)) && {
                whole_prefix="${prefix}${p1}"
            } || {
                whole_prefix="${prefix}${p2}"
            }
            ((i++))
            [ -z "${line}" ] && {
                echo
            } || {
                echo "${whole_prefix}${line}"
            }
        done | replace_reset "${code}"
    } <<< "${str}"
    [ -z "${code}" ] || print_tty_ctrl "0"
    __need_blank_line=1
}

write_eval() {
    write_paragraph "$(print_eval "$@")"
}

write_error() {
    write_paragraph "**${1}**" "${2}" "${3}" '01;31'
}

write_error_eval() {
    write_error "$(print_eval "$@")"
}

write_quote_str() {
    local str="$1"
    increase_cur_level 1
    __need_blank_line=0
    echo
    write_paragraph "${str}" '' '' '01;35'
    echo
    __need_blank_line=0
    increase_cur_level -1
}

write_quote_cmd() {
    local cmd_output_str cmd_ret_val
    cmd_output_str="$("$@" 2>&1)"
    cmd_ret_val=$?
    write_quote_str "${cmd_output_str}"
    return $cmd_ret_val
}

write_title() {
    local level="$1"
    local title="$2"
    local prefix='######'
    prefix="${prefix::$level}"
    ((__need_blank_line)) && echo
    print_tty_ctrl '01;34'
    echo "${prefix} ${title}" | replace_reset '01;34'
    print_tty_ctrl '0'
    __need_blank_line=0
    set_cur_level -1
}

write_order_list() {
    local str="$1"
    local index
    increase_cur_level -1
    increase_cur_level 1
    ((index = ++__list_indexes[__current_level - 1]))
    ((${#index} > 2)) && index="${index: -2}"
    index="${index}.   "
    increase_cur_level -1
    write_paragraph "${str}" "${index::4}" '    ' '01;32'
    increase_cur_level 1
}

write_order_list_eval() {
    write_order_list "$(print_eval "$@")"
}

# write_list() {
#     local str="$1"
#     increase_cur_level -1
#     write_paragraph "${str}" '*   ' '    ' '01;32'
#     increase_cur_level 1
# }


#############################
# print tips and links
#############################

wiki_url="http://fcitx-im.org/wiki"

beginner_guide_link() {
    print_link "$(_ "Beginner's Guide")" \
        "${wiki_url}$(_ /Beginner%27s_Guide)"
}

set_env_link() {
    local env_name="$1"
    local value="$2"
    local fmt
    fmt=$(_ 'Please set environment variable ${env_name} to "${value}" using the tool your distribution provides or add ${1} to your ${2}. See ${link}.')
    local link
    link=$(print_link \
        "$(_ "Input Method Related Environment Variables: ")${env_name}" \
        "${wiki_url}$(_ "/Input_method_related_environment_variables")#${env_name}")
    write_error_eval "${fmt}" "$(code_inline "export ${env_name}=${value}")" \
        "$(code_inline '~/.xprofile')"
}

gnome_36_check_gsettings() {
    gsettings get org.gnome.settings-daemon.plugins.keyboard \
        active 2> /dev/null || return 1
}

gnome_36_link() {
    # Do nothing if the DE is not gnome3
    maybe_gnome3 || return 1
    local link ibus_activated fmt
    link=$(print_link \
        "$(_ "Note for GNOME Later than 3.6")" \
        "${wiki_url}$(_ "/Note_for_GNOME_Later_than_3.6")")

    # Check if the gsettings key exists
    if ibus_activated=$(gnome_36_check_gsettings); then
        [[ $ibus_activated = 'false' ]] && return 1
        g36_disable_ibus=$(code_inline 'gsettings set org.gnome.settings-daemon.plugins.keyboard active false')
        fmt=$(_ 'If you are using ${1}, you may want to uninstall ${2}, remove ${3} or use the command ${g36_disable_ibus} to disable IBus integration in order to use any input method other than ${2}. See ${link} for more detail.')
    else
        fmt=$(_ 'If you are using ${1}, you may want to uninstall ${2} or remove ${3} in order to use any input method other than ${2}. See ${link} for more detail as well as alternative solutions.')
    fi
    write_error_eval "${fmt}" "$(code_inline 'gnome>=3.6')" \
        "$(code_inline 'ibus')" "$(code_inline 'ibus-daemon')"
}

no_xim_link() {
    local fmt
    fmt=$(_ 'To see some application specific problems you may have when using xim, check ${link1}. For other more general problems of using XIM including application freezing, see ${link2}.')
    local link1
    link1=$(print_link \
        "$(_ "Hall of Shame for Linux IME Support")" \
        "${wiki_url}$(_ "/Hall_of_Shame_for_Linux_IME_Support")")
    local link2
    link2=$(print_link \
        "$(_ "here")" \
        "${wiki_url}$(_ "/XIM")")
    write_error_eval "${fmt}"
}


#############################
# system info
#############################

ldpaths=()
init_ld_paths() {
    local IFS=$'\n'
    ldpaths=()
    unique_file_array ldpath ldpaths $(ldconfig -p 2> /dev/null | grep '=>' | \
        sed -e 's:.* => \(.*\)/[^/]*$:\1:g' | sort -u) \
        {/usr,,/usr/local}/lib*
}
init_ld_paths

check_system() {
    write_title 1 "$(_ "System Info:")"
    write_order_list "$(code_inline 'uname -a'):"
    if type uname &> /dev/null; then
        write_quote_cmd uname -a
    else
        write_error "$(print_not_found 'uname')"
    fi
    if type lsb_release &> /dev/null; then
        write_order_list "$(code_inline 'lsb_release -a'):"
        write_quote_cmd lsb_release -a
        write_order_list "$(code_inline 'lsb_release -d'):"
        write_quote_cmd lsb_release -d
    else
        write_order_list "$(code_inline lsb_release):"
        write_paragraph "$(print_not_found 'lsb_release')"
    fi
    write_order_list "$(code_inline /etc/lsb-release):"
    if [ -f /etc/lsb-release ]; then
        write_quote_cmd cat /etc/lsb-release
    else
        write_paragraph "$(print_not_found '/etc/lsb-release')"
    fi
    write_order_list "$(code_inline /etc/os-release):"
    if [ -f /etc/os-release ]; then
        write_quote_cmd cat /etc/os-release
    else
        write_paragraph "$(print_not_found '/etc/os-release')"
    fi
    write_order_list "$(_ "Desktop Environment:")"
    if [ -z "$DE" ]; then
        write_eval "$(_ 'Cannot determine desktop environment.')"
    else
        write_eval "$(_ 'Desktop environment is ${1}.')" \
            "$(code_inline "${DE}")"
    fi
}

check_env() {
    write_title 1 "$(_ "Environment:")"
    write_order_list "DISPLAY:"
    write_quote_str "DISPLAY='${DISPLAY}'"
    write_order_list "$(_ "Keyboard Layout:")"
    increase_cur_level 1
    write_order_list "$(code_inline setxkbmap):"
    if type setxkbmap &> /dev/null; then
        write_quote_cmd setxkbmap -print
    else
        write_paragraph "$(print_not_found 'setxkbmap')"
    fi
    write_order_list "$(code_inline xprop):"
    if type xprop &> /dev/null; then
        write_quote_cmd xprop -root _XKB_RULES_NAMES
    else
        write_paragraph "$(print_not_found 'xprop')"
    fi
    increase_cur_level -1
    write_order_list "$(_ "Locale:")"
    if type locale &> /dev/null; then
        increase_cur_level 1
        write_order_list "$(_ "All locale:")"
        write_quote_str "$(locale -a 2> /dev/null)"
        write_order_list "$(_ "Current locale:")"
        write_quote_str "$(locale 2> /dev/null)"
        locale_error="$(locale 2>&1 > /dev/null)"
        if [[ -n $locale_error ]]; then
            write_error_eval "$(_ 'Error occurs when running ${1}. Please check your locale settings.')" \
            "$(code_inline "locale")"
            write_quote_str "${locale_error}"
        fi
        increase_cur_level -1
    else
        write_paragraph "$(print_not_found 'locale')"
    fi
}

check_fcitx() {
    local IFS=$'\n'
    write_title 1 "$(_ "Fcitx State:")"
    write_order_list "$(_ 'executable:')"
    if ! fcitx_exe="$(which fcitx 2> /dev/null)"; then
        write_error "$(_ "Cannot find fcitx executable!")"
        __need_blank_line=0
        write_error_eval "$(_ 'Please check ${1} for how to install fcitx.')" \
            "$(beginner_guide_link)"
        exit 1
    else
        write_eval "$(_ 'Found fcitx at ${1}.')" "$(code_inline "${fcitx_exe}")"
    fi
    write_order_list "$(_ 'version:')"
    version=$(fcitx -v 2> /dev/null | \
        sed -e 's/.*fcitx version: \([0-9.]*\).*/\1/g')
    write_eval "$(_ 'Fcitx version: ${version}')"
    write_order_list "$(_ 'process:')"
    psoutput=$(ps -Ao pid,comm)
    process=()
    while read line; do
        if [[ $line =~ ^([0-9]*)\ .*fcitx.* ]]; then
            [ "${BASH_REMATCH[1]}" = "$$" ] && continue
            array_push process "${line}"
        fi
    done <<< "${psoutput}"
    if ! ((${#process[@]})); then
        write_error "$(_ "Fcitx is not running.")"
        __need_blank_line=0
        write_error_eval "$(_ 'Please check the Configure link of your distribution in ${1} for how to setup fcitx autostart.')" "$(beginner_guide_link)"
        return 1
    fi
    local pcount="${#process[@]}"
    if ((pcount > 1)); then
        write_eval "$(_ 'Found ${1} fcitx processes:')" "${#process[@]}"
    else
        write_eval "$(_ 'Found ${1} fcitx process:')" "${#process[@]}"
    fi
    write_quote_cmd print_array "${process[@]}"
    write_order_list "$(code_inline 'fcitx-remote'):"
    if type fcitx-remote &> /dev/null; then
        if ! fcitx-remote &> /dev/null; then
            write_error "$(_ "Cannot connect to fcitx correctly.")"
        else
            write_eval "$(_ '${1} works properly.')" \
                "$(code_inline 'fcitx-remote')"
        fi
    else
        write_error "$(print_not_found "fcitx-remote")"
    fi
}

_find_config_gtk() {
    [ -n "${_config_tool_gtk_exe}" ] && {
        echo "${_config_tool_gtk_exe}"
        return 0
    }
    local config_gtk
    config_gtk="$(which "fcitx-config-gtk" 2> /dev/null)" || return 1
    echo "${config_gtk}"
    _config_tool_gtk_exe="${config_gtk}"
}

_check_config_gtk_version() {
    local version=$1
    local config_gtk
    [ -z "${_config_tool_gtk_version}" ] && {
        config_gtk="$(_find_config_gtk)" || return 1
        ld_info="$(ldd "$config_gtk" 2> /dev/null)" ||
        ld_info="$(objdump -p "$config_gtk" 2> /dev/null)" || return 1
        if [[ $ld_info =~ libgtk[-._a-zA-Z0-9]*3[-._a-zA-Z0-9]*\.so ]]; then
            _config_tool_gtk_version=3
        elif [[ $ld_info =~ libgtk[-._a-zA-Z0-9]*2[-._a-zA-Z0-9]*\.so ]]; then
            _config_tool_gtk_version=2
        else
            return 1
        fi
    }
    [ "${_config_tool_gtk_version}" = "$version" ]
}

_check_config_gtk() {
    local version=$1
    local config_gtk config_gtk_name
    write_order_list_eval "$(_ 'Config GUI for gtk${1}:')" "${version}"
    if ! config_gtk="$(which "fcitx-config-gtk${version}" 2> /dev/null)"; then
        if ! _check_config_gtk_version "${version}"; then
            write_error_eval \
                "$(_ "Config GUI for gtk${1} not found.")" "${version}"
            return 1
        else
            config_gtk=$(_find_config_gtk)
            config_gtk_name="fcitx-config-gtk"
        fi
    else
        config_gtk_name="fcitx-config-gtk${version}"
    fi
    write_eval "$(_ 'Found ${1} at ${2}.')" \
        "$(code_inline "${config_gtk_name}")" \
        "$(code_inline "${config_gtk}")"
}

_check_config_kcm() {
    local kcm_shell config_kcm
    write_order_list "$(_ 'Config GUI for kde:')"
    if ! kcm_shell="$(which "kcmshell4" 2> /dev/null)"; then
        write_error "$(print_not_found 'kcmshell4')"
        return 1
    fi
    config_kcm="$(kcmshell4 --list 2> /dev/null | grep -i fcitx)" && {
        write_paragraph "$(_ 'Found fcitx kcm module.')"
        write_quote_str "${config_kcm}"
        return 0
    }
    return 1
}

check_config_ui() {
    local IFS=$'\n'
    write_title 1 "$(_ "Fcitx Configure UI:")"
    write_order_list "$(_ 'Config Tool Wrapper:')"
    if ! fcitx_configtool="$(which fcitx-configtool 2> /dev/null)"; then
        write_error "$(_ "Cannot find fcitx-configtool executable!")"
    else
        write_eval "$(_ 'Found fcitx-configtool at ${1}.')" \
            "$(code_inline "${fcitx_configtool}")"
    fi
    local config_backend_found=0
    _check_config_gtk 2 && config_backend_found=1
    _check_config_gtk 3 && config_backend_found=1
    _check_config_kcm && config_backend_found=1
    if ((!config_backend_found)) && [[ -n "$DISPLAY$WAYLAND_DISPLAY" ]]; then
        write_error_eval "$(_ 'Cannot find a GUI config tool, please install one of ${1}, ${2}, or ${3}.')" \
            "$(code_inline kcm-fcitx)" "$(code_inline fcitx-config-gtk2)" \
            "$(code_inline fcitx-config-gtk3)"
    fi
}


#############################
# front end
#############################

_env_correct() {
    write_eval \
        "$(_ 'Environment variable ${1} is set to "${2}" correctly.')" \
        "$1" "$2"
}

_env_incorrect() {
    write_error_eval \
        "$(_ 'Environment variable ${1} is "${2}" instead of "${3}". Please check if you have exported it incorrectly in any of your init files.')" \
        "$1" "$3" "$2"
}

check_xim() {
    write_title 2 "Xim:"
    xim_name=fcitx
    write_order_list "$(code_inline '${XMODIFIERS}'):"
    if [ -z "${XMODIFIERS}" ]; then
        set_env_link XMODIFIERS '@im=fcitx'
        __need_blank_line=0
    elif [ "${XMODIFIERS}" = '@im=fcitx' ]; then
        _env_correct 'XMODIFIERS' '@im=fcitx'
        __need_blank_line=0
    else
        _env_incorrect 'XMODIFIERS' '@im=fcitx' "${XMODIFIERS}"
        if [[ ${XMODIFIERS} =~ @im=([-_0-9a-zA-Z]+) ]]; then
            xim_name="${BASH_REMATCH[1]}"
        else
            __need_blank_line=0
            write_error_eval "$(_ 'Cannot interpret XMODIFIERS: ${1}.')" \
                "${XMODIFIERS}"
        fi
        if [ "${xim_name}" = "ibus" ]; then
            __need_blank_line=0
            gnome_36_link || __need_blank_line=1
        fi
    fi
    write_eval "$(_ 'Xim Server Name from Environment variable is ${1}.')" \
        "${xim_name}"
    write_order_list "$(_ 'XIM_SERVERS on root window:')"
    local atom_name=XIM_SERVERS
    if ! type xprop &> /dev/null; then
        write_error "$(print_not_found 'xprop')"
    else
        xprop=$(xprop -root -notype -f "${atom_name}" \
            '32a' ' $0\n' "${atom_name}" 2> /dev/null)
        if [[ ${xprop} =~ ^${atom_name}\ @server=(.*)$ ]]; then
            xim_server_name="${BASH_REMATCH[1]}"
            if [ "${xim_server_name}" = "${xim_name}" ]; then
                write_paragraph "$(_ "Xim server name is the same with that set in the environment variable.")"
            else
                write_error_eval "$(_ 'Xim server name: "${1}" is different from that set in the environment variable: "${2}".')" \
                    "${xim_server_name}" "${xim_name}"
            fi
        else
            write_error "$(_ "Cannot find xim_server on root window.")"
        fi
    fi
    local _LC_CTYPE=$(get_locale CTYPE)
    if type emacs &> /dev/null &&
        ! str_match_regex '^(zh|ja|ko)([._].*|)$' "${_LC_CTYPE}"; then
        write_order_list "$(_ "XIM for Emacs:")"
        write_error_eval \
            "$(_ 'Your LC_CTYPE is set to ${1} instead of one of zh, ja, ko. You may not be able to use input method in emacs because of an really old emacs bug that upstream refuse to fix for years.')" "${_LC_CTYPE}"
    fi
    if ! str_match_regex '.[Uu][Tt][Ff]-?8$' "${_LC_CTYPE}"; then
        write_order_list "$(_ "XIM encoding:")"
        write_error_eval \
            "$(_ 'Your LC_CTYPE is set to ${1} whose encoding is not UTF-8. You may have trouble committing strings using XIM.')" "${_LC_CTYPE}"
    fi
}

_check_toolkit_env() {
    local env_name="$1"
    local name="$2"
    write_order_list "$(code_inline '${'"${env_name}"'}'):"
    if [ -z "${!env_name}" ]; then
        set_env_link "${env_name}" 'fcitx'
    elif [ "${!env_name}" = 'fcitx' ]; then
        _env_correct "${env_name}" 'fcitx'
    else
        _env_incorrect "${env_name}" 'fcitx' "${!env_name}"
        __need_blank_line=0
        if [ "${!env_name}" = 'xim' ]; then
            write_error_eval "$(_ 'You are using xim in ${1} programs.')" \
                "${name}"
            no_xim_link
        else
            write_error_eval \
                "$(_ 'You may have trouble using fcitx in ${1} programs.')" \
                "${name}"
            if [ "${!env_name}" = "ibus" ] && [ "${name}" = 'qt' ]; then
                __need_blank_line=0
                gnome_36_link || __need_blank_line=1
            fi
        fi
        set_env_link "${env_name}" 'fcitx'
    fi
}

find_qt_modules() {
    local qt_dirs _qt_modules
    find_file qt_dirs -H "${ldpaths[@]}" -type d -name '*qt*'
    find_file _qt_modules -H "${qt_dirs[@]}" -type f -iname '*fcitx*.so'
    qt_modules=()
    unique_file_array qt_modules qt_modules "${_qt_modules[@]}"
}

check_qt() {
    write_title 2 "Qt:"
    _check_toolkit_env QT_IM_MODULE qt
    find_qt_modules
    qt4_module_found=''
    qt5_module_found=''
    write_order_list "$(_ 'Qt IM module files:')"
    for file in "${qt_modules[@]}"; do
        basename=$(basename "${file}")
        __need_blank_line=0
        if [[ ${basename} =~ im-fcitx ]] &&
            [[ ${file} =~ plugins/inputmethods ]]; then
            write_eval "$(_ 'Found fcitx im module for Qt4: ${1}.')" \
                "$(code_inline "${file}")"
            qt4_module_found=1
        elif [[ ${basename} =~ fcitxplatforminputcontextplugin ]] &&
            [[ ${file} =~ plugins/platforminputcontexts ]]; then
            write_eval "$(_ 'Found fcitx im module for Qt5: ${1}.')" \
                "$(code_inline "${file}")"
            qt5_module_found=1
        elif [[ ${file} =~ /fcitx/qt/ ]]; then
            write_eval "$(_ 'Found fcitx qt module: ${1}.')" \
                "$(code_inline "${file}")"
        else
            write_eval "$(_ 'Found unknown fcitx qt module: ${1}.')" \
                "$(code_inline "${file}")"
        fi
    done
    if [ -z "${qt4_module_found}" ]; then
        __need_blank_line=0
        write_error "$(_ "Cannot find fcitx input method module for Qt4.")"
    fi
    if [ -z "${qt5_module_found}" ]; then
        __need_blank_line=0
        write_error "$(_ "Cannot find fcitx input method module for Qt5.")"
    fi
}

init_gtk_dirs() {
    local gtk_dirs_name="__gtk${version}_dirs"
    eval '((${#'"${gtk_dirs_name}"'[@]}))' || {
        find_file "${gtk_dirs_name}" -H "${ldpaths[@]}" -type d \
            '(' -name "gtk-${version}*" -o -name 'gtk' ')'
    }
    eval 'gtk_dirs=("${'"${gtk_dirs_name}"'[@]}")'
}

find_gtk_query_immodules() {
    local version="$1"
    init_gtk_dirs "${version}"
    local IFS=$'\n'
    local query_im_lib
    find_file query_im_lib -H "${gtk_dirs[@]}" -type f \
        -name "gtk-query-immodules-${version}*"
    gtk_query_immodules=()
    unique_file_array "gtk_query_immodules_${version}" gtk_query_immodules \
        $(find_in_path "gtk-query-immodules-${version}*") \
        "${query_im_lib[@]}"
}

reg_gtk_query_output() {
    local version="$1"
    while read line; do
        regex='"(/[^"]*\.so)"'
        [[ $line =~ $regex ]] || continue
        file=${BASH_REMATCH[1]}
        add_and_check_file "__gtk_immodule_files_${version}" "${file}" && {
            array_push "gtk_immodule_files_${version}" "${file}"
        }
    done <<< "$2"
}

check_gtk_immodule_file() {
    local version=$1
    local gtk_immodule_files
    local all_exists=1
    write_order_list "gtk ${version}:"
    eval 'gtk_immodule_files=("${gtk_immodule_files_'"${version}"'[@]}")'
    for file in "${gtk_immodule_files[@]}"; do
        [[ -f "${file}" ]] || {
            all_exists=0
            write_error_eval \
                "$(_ 'Gtk ${1} immodule file ${2} does not exist.')" \
                "${version}" \
                "${file}"
        }
    done
    ((all_exists)) && \
        write_eval "$(_ 'All found Gtk ${1} immodule files exist.')" \
        "${version}"
}

check_gtk_query_immodule() {
    local version="$1"
    local IFS=$'\n'
    find_gtk_query_immodules "${version}"
    local module_found=0
    local query_found=0
    write_order_list "gtk ${version}:"

    for query_immodule in "${gtk_query_immodules[@]}"; do
        query_output=$("${query_immodule}")
        real_version=''
        version_line=''
        while read line; do
            regex='[Cc]reated.*gtk-query-immodules.*gtk\+-*([0-9][^ ]+)$'
            [[ $line =~ $regex ]] && {
                real_version="${BASH_REMATCH[1]}"
                version_line="${line}"
                break
            }
        done <<< "${query_output}"
        if [[ -n $version_line ]]; then
            regex="^${version}\."
            if [[ $real_version =~ $regex ]]; then
                query_found=1
                write_command=write_eval
            else
                write_command=write_error_eval
            fi
            "$write_command" \
                "$(_ 'Found ${3} for gtk ${1} at ${2}.')" \
                "$(code_inline "${real_version}")" \
                "$(code_inline "${query_immodule}")" \
                "$(code_inline gtk-query-immodules)"
            __need_blank_line=0
            write_eval "$(_ 'Version Line:')"
            write_quote_str "${version_line}"
        else
            write_eval "$(_ 'Found ${2} for unknow gtk version at ${1}.')" \
                "$(code_inline "${query_immodule}")" \
                "$(code_inline gtk-query-immodules)"
            real_version=${version}
        fi
        if fcitx_gtk=$(grep fcitx <<< "${query_output}"); then
            module_found=1
            __need_blank_line=0
            write_eval "$(_ 'Found fcitx im modules for gtk ${1}.')" \
                "$(code_inline ${real_version})"
            write_quote_str "${fcitx_gtk}"
            reg_gtk_query_output "${version}" "${fcitx_gtk}"
        else
            write_error_eval \
                "$(_ 'Failed to find fcitx in the output of ${1}')" \
                "$(code_inline "${query_immodule}")"
        fi
    done
    ((query_found)) || {
        write_error_eval \
            "$(_ 'Cannot ${2} for gtk ${1}')" \
            "${version}" \
            "$(code_inline gtk-query-immodules)"
    }
    ((module_found)) || {
        write_error_eval \
            "$(_ 'Cannot find fcitx im module for gtk ${1}.')" \
            "${version}"
    }
}

find_gtk_immodules_cache() {
    local version="$1"
    init_gtk_dirs "${version}"
    local IFS=$'\n'
    local __gtk_immodule_cache
    find_file __gtk_immodule_cache -H \
        "${gtk_dirs[@]}" /etc/gtk-${version}* -type f \
        '(' -name '*gtk.immodules*' -o -name '*immodules.cache*' ')'
    unique_file_array "gtk_immodules_cache_${version}" "$2" \
        "${__gtk_immodule_cache[@]}"
}

check_gtk_immodule_cache() {
    local version="$1"
    local IFS=$'\n'
    local cache_found=0
    local module_found=0
    local version_correct=0
    write_order_list "gtk ${version}:"
    local gtk_immodules_cache
    find_gtk_immodules_cache "${version}" gtk_immodules_cache

    for cache in "${gtk_immodules_cache[@]}"; do
        cache_content=$(cat "${cache}")
        real_version=''
        version_line=''
        version_correct=0
        while read line; do
            regex='[Cc]reated.*gtk-query-immodules.*gtk\+-*([0-9][^ ]+)$'
            [[ $line =~ $regex ]] && {
                real_version="${BASH_REMATCH[1]}"
                version_line="${line}"
                break
            }
        done <<< "${cache_content}"
        if [[ -n $version_line ]]; then
            regex="^${version}\."
            if [[ $real_version =~ $regex ]]; then
                cache_found=1
                version_correct=1
                write_command=write_eval
            else
                write_command=write_error_eval
            fi
            "$write_command" \
                "$(_ 'Found immodules cache for gtk ${1} at ${2}.')" \
                "$(code_inline ${real_version})" \
                "$(code_inline "${cache}")"
            __need_blank_line=0
            write_eval "$(_ 'Version Line:')"
            write_quote_str "${version_line}"
        else
            write_eval \
                "$(_ 'Found immodule cache for unknow gtk version at ${1}.')" \
                "$(code_inline "${cache}")"
            real_version=${version}
        fi
        if fcitx_gtk=$(grep fcitx <<< "${cache_content}"); then
            ((version_correct)) && module_found=1
            __need_blank_line=0
            write_eval "$(_ 'Found fcitx im modules for gtk ${1}.')" \
                "$(code_inline ${real_version})"
            write_quote_str "${fcitx_gtk}"
            reg_gtk_query_output "${version}" "${fcitx_gtk}"
        else
            write_error_eval \
                "$(_ 'Failed to find fcitx in immodule cache at ${1}')" \
                "$(code_inline "${cache}")"
        fi
    done
    ((cache_found)) || {
        write_error_eval \
            "$(_ 'Cannot find immodules cache for gtk ${1}')" \
            "${version}"
    }
    ((module_found)) || {
        write_error_eval \
            "$(_ 'Cannot find fcitx im module for gtk ${1} in cache.')" \
            "${version}"
    }
}

check_gtk() {
    write_title 2 "Gtk:"
    _check_toolkit_env GTK_IM_MODULE gtk
    write_order_list "$(code_inline gtk-query-immodules):"
    increase_cur_level 1
    check_gtk_query_immodule 2
    check_gtk_query_immodule 3
    increase_cur_level -1
    write_order_list "$(_ 'Gtk IM module cache:')"
    increase_cur_level 1
    check_gtk_immodule_cache 2
    check_gtk_immodule_cache 3
    increase_cur_level -1
    write_order_list "$(_ 'Gtk IM module files:')"
    increase_cur_level 1
    check_gtk_immodule_file 2
    check_gtk_immodule_file 3
    increase_cur_level -1
}


#############################
# fcitx modules
#############################

check_modules() {
    local addon_conf_dir
    write_title 2 "$(_ "Fcitx Addons:")"
    write_order_list "$(_ 'Addon Config Dir:')"
    addon_conf_dir="$(get_config_dir addonconfigdir addon)" || {
        write_error "$(_ "Cannot find fcitx addon config directory.")"
        return
    }
    local enabled_addon=()
    local disabled_addon=()
    local enabled_ui=()
    local name
    local enable
    write_eval "$(_ 'Found fcitx addon config directory: ${1}.')" \
        "$(code_inline "${addon_conf_dir}")"
    write_order_list "$(_ 'Addon List:')"
    for file in "${addon_conf_dir}"/*.conf; do
        if ! name=$(get_from_config_file "${file}" Name); then
            write_error_eval \
                "$(_ 'Invalid addon config file ${1}.')" \
                "$(code_inline "${file}")"
            continue
        fi
        enable=$(get_from_config_file "${file}" Enabled)
        if [ -f ~/.config/fcitx/addon/${name}.conf ]; then
            _enable=$(get_from_config_file \
                ~/.config/fcitx/addon/${name}.conf Enabled)
            [ -z "${_enable}" ] || enable="${_enable}"
        fi
        if [ $(echo "${enable}" | sed -e 's/.*/\L&/g') = false ]; then
            array_push disabled_addon "${name}"
        else
            array_push enabled_addon "${name}"
            if [[ $(get_from_config_file "${file}" Category) = UI ]]; then
                array_push enabled_ui "${name}"
            fi
        fi
    done
    increase_cur_level 1
    write_order_list_eval "$(_ 'Found ${1} enabled addons:')" \
        "${#enabled_addon[@]}"
    [ "${#enabled_addon[@]}" = 0 ] || {
        write_quote_cmd print_array "${enabled_addon[@]}"
    }
    write_order_list_eval "$(_ 'Found ${1} disabled addons:')" \
        "${#disabled_addon[@]}"
    [ "${#disabled_addon[@]}" = 0 ] || {
        write_quote_cmd print_array "${disabled_addon[@]}"
    }
    write_order_list_eval "$(_ 'User Interface:')"
    if ! ((${#enabled_ui[@]})); then
        write_error_eval "$(_ 'Cannot find enabled fcitx user interface!')"
    else
        write_eval "$(_ 'Found ${1} enabled user interface addons:')" \
            "${#enabled_ui[@]}"
        write_quote_cmd print_array "${enabled_ui[@]}"
        has_non_kimpanel=0
        has_kimpanel_dbus=0
        for ui in "${enabled_ui[@]}"; do
            if [[ $ui =~ kimpanel ]]; then
                pid=$(dbus_get_pid org.kde.impanel) || continue
                has_kimpanel_dbus=1
                write_eval "$(_ "Kimpanel process:")"
                write_quote_cmd print_process_info "${pid}"
            else
                has_non_kimpanel=1
            fi
        done
        ((has_non_kimpanel)) || ((has_kimpanel_dbus)) || \
            write_error_eval \
            "$(_ 'Cannot find kimpanel dbus interface or enabled non-kimpanel user interface.')"
    fi
    increase_cur_level -1
}

check_input_methods() {
    write_title 2 "$(_ "Input Methods:")"
    local IFS=','
    local imlist=($(get_from_config_file \
        ~/.config/fcitx/profile EnabledIMList)) || {
        write_error "$(_ "Cannot read im list from fcitx profile.")"
        return 0
    }
    local enabled_im=()
    local disabled_im=()
    local im
    local name
    local enable
    for im in "${imlist[@]}"; do
        [[ $im =~ ^([^:]+):(True|False)$ ]] || {
            write_error_eval "$(_ 'Invalid item ${1} in im list.')" \
                "${im}"
            continue
        }
        name="${BASH_REMATCH[1]}"
        if [ "${BASH_REMATCH[2]}" = True ]; then
            enabled_im=("${enabled_im[@]}" "${name}")
        else
            disabled_im=("${disabled_im[@]}" "${name}")
        fi
    done
    write_order_list_eval "$(_ 'Found ${1} enabled input methods:')" \
        "${#enabled_im[@]}"
    [ "${#enabled_im[@]}" = 0 ] || {
        write_quote_cmd print_array "${enabled_im[@]}"
    }
    write_order_list "$(_ 'Default input methods:')"
    case "${#enabled_im[@]}" in
        0)
            write_error "$(_ "You don't have any input methods enabled.")"
            ;;
        1)
            write_error "$(_ "You only have one input method enabled, please add a keyboard input method as the first one and your main input method as the second one.")"
            ;;
        *)
            if [[ ${enabled_im[0]} =~ ^fcitx-keyboard- ]]; then
                write_eval \
                    "$(_ 'You have a keyboard input method "${1}" correctly added as your default input method.')" \
                    "${enabled_im[0]}"
            else
                write_error_eval \
                    "$(_ 'Your first (default) input method is ${1} instead of a keyboard input method. You may have trouble deactivate fcitx.')" \
                    "${enabled_im[0]}"
            fi
            ;;
    esac
}


#############################
# log
#############################

check_log() {
    write_order_list "$(code_inline 'date'):"
    if type date &> /dev/null; then
        write_quote_cmd date
    else
        write_error "$(print_not_found 'date')"
    fi
    write_order_list "$(code_inline '~/.config/fcitx/log/'):"
    [ -d ~/.config/fcitx/log/ ] || {
        write_paragraph "$(print_not_found '~/.config/fcitx/log/')"
        return
    }
    write_quote_cmd ls -AlF ~/.config/fcitx/log/
    write_order_list "$(code_inline '~/.config/fcitx/log/crash.log'):"
    if [ -f ~/.config/fcitx/log/crash.log ]; then
        write_quote_cmd cat ~/.config/fcitx/log/crash.log
    else
        write_paragraph "$(print_not_found '~/.config/fcitx/log/crash.log')"
    fi
}


#############################
# cmd line
#############################

_check_frontend=1
_check_modules=1
_check_log=1
[ -z "$1" ] || exec > "$1"


#############################
# init output
#############################

check_istty


#############################
# run
#############################

check_system
check_env
check_fcitx
check_config_ui

((_check_frontend)) && {
    write_title 1 "$(_ "Frontends setup:")"
    check_xim
    check_qt
    check_gtk
}

((_check_modules)) && {
    write_title 1 "$(_ "Configuration:")"
    check_modules
    check_input_methods
}

((_check_log)) && {
    write_title 1 "$(_ "Log:")"
    check_log
}
