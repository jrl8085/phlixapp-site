#!/bin/sh
# Phlix Camera Upload: one-command installer.
#
#   curl -fsSL https://raw.githubusercontent.com/jrl8085/phlix-camera-upload/main/install.sh | sh
#
# You can also download this file and run:  sh install.sh
#
# What it does, in this order:
#   1. It checks that Docker and Docker Compose are installed and answer.
#   2. It asks which folder should receive the photos. It makes the folder
#      if you agree.
#   3. It writes docker-compose.yml into the install folder.
#   4. It downloads the image and starts the helper.
#   5. It waits until the helper is healthy, and runs the helper's own check.
#   6. It tells you what to do next in Plex and in the Phlix app.
#
# Run it again at any time to update the helper.
#
# It never uses sudo. It never changes Plex. It never deletes a photo.
#
# Options:      sh install.sh --help
# Setup guide:  https://phlixapp.com/camera-upload/

set -u

IMAGE_DEFAULT=ghcr.io/jrl8085/phlix-camera-upload:1
CONTAINER=phlix-camera-upload
INSTALLER_URL=https://raw.githubusercontent.com/jrl8085/phlix-camera-upload/main/install.sh
NETWORKING_URL=https://github.com/jrl8085/phlix-camera-upload/blob/main/NETWORKING.md

usage() {
    cat <<'USAGE'
Phlix Camera Upload installer

Usage:
  sh install.sh [options]
  curl -fsSL https://raw.githubusercontent.com/jrl8085/phlix-camera-upload/main/install.sh | sh
  curl -fsSL https://raw.githubusercontent.com/jrl8085/phlix-camera-upload/main/install.sh | sh -s -- [options]

Options:
  --photos PATH    The upload folder on this server: where the photos go.
                   It must be inside a folder that one of your Plex photo
                   libraries includes. Without this option the installer
                   asks for it.
  --dir PATH       The install folder: where docker-compose.yml and the
                   helper's own data go.
                   Default: phlix-camera-upload in your home folder.
  --port N         The port on this server. Default: 7459. The Phlix app
                   looks for port 7459 by itself. With another port you type
                   the helper's address into the app.
  --plex-url URL   Where Plex Media Server is, for example
                   http://192.168.1.10:32400
                   Default: the helper finds Plex by itself.
  --puid N         Write files as this user id.
  --pgid N         Write files as this group id.
                   Default for both: the owner of the upload folder.
  --yes            Ask no questions. A first install then needs --photos.
  --dry-run        Say what would be done. Change nothing.
  --help           Show this text.

Run the installer again to update the helper. An update keeps your
docker-compose.yml as it is.

The installer never uses sudo, never changes Plex and never deletes a photo.
USAGE
}

say() {
    printf '%s\n' "$*"
}

warn() {
    printf 'Note: %s\n' "$*" >&2
}

die() {
    printf '\nThe installer stopped: %s\n' "$1" >&2
    shift
    for line in "$@"; do
        printf '  %s\n' "$line" >&2
    done
    exit 1
}

die_usage() {
    printf 'install.sh: %s\n' "$1" >&2
    printf 'Run "sh install.sh --help" to see the options.\n' >&2
    exit 2
}

# stop WHAT [MORE LINES]
# Something a real run cannot go past. A dry run notes it and goes on, so
# that it can show the whole plan.
stop() {
    if [ "$DRY_RUN" = 1 ]; then
        BLOCKERS=$((BLOCKERS + 1))
        printf '  A real run stops here: %s\n' "$1"
        shift
        for line in "$@"; do
            printf '    %s\n' "$line"
        done
        return 0
    fi
    die "$@"
}

is_number() {
    case $1 in
        '' | *[!0-9]*) return 1 ;;
    esac
    [ "${#1}" -le 10 ]
}

# Docker and Compose, always with nothing on standard input. When this file
# arrives through "curl | sh", standard input is the script itself.
docker_quiet() {
    docker "$@" </dev/null
}

compose() {
    if [ "$COMPOSE_KIND" = plugin ]; then
        docker compose "$@" </dev/null
    else
        docker-compose "$@" </dev/null
    fi
}

compose_words() {
    if [ "$COMPOSE_KIND" = plugin ]; then
        printf 'docker compose'
    else
        printf 'docker-compose'
    fi
}

# Questions are asked on the terminal itself, not on standard input.
have_terminal() {
    (: </dev/tty) 2>/dev/null
}

# ask QUESTION: leaves the answer in ANSWER.
ask() {
    printf '%s ' "$1" >/dev/tty
    ANSWER=
    IFS= read -r ANSWER </dev/tty || true
}

# confirm QUESTION DEFAULT(y or n): true for yes. With --yes, always yes.
# Without --yes and without a terminal the question cannot be asked, and the
# run stops: a silent "no" could hide that nothing was done.
confirm() {
    if [ "$ASSUME_YES" = 1 ]; then
        return 0
    fi
    if ! have_terminal; then
        die "The installer has to ask a question, and there is no terminal to ask on." \
            "The question: $1" \
            "Run the installer again with --yes to answer yes."
    fi
    if [ "$2" = y ]; then
        ask "$1 [Y/n]"
    else
        ask "$1 [y/N]"
    fi
    case $ANSWER in
        [Yy] | [Yy][Ee][Ss]) return 0 ;;
        [Nn] | [Nn][Oo]) return 1 ;;
        '') [ "$2" = y ] ;;
        *) return 1 ;;
    esac
}

# A path as the installer uses it: "~" opened up, no slash at the end.
tidy_path() {
    tidy=$1
    case $tidy in
        '~') tidy=${HOME:-} ;;
        '~/'*) tidy=${HOME:-}/${tidy#'~/'} ;;
    esac
    while [ "$tidy" != / ] && [ "${tidy%/}" != "$tidy" ]; do
        tidy=${tidy%/}
    done
    printf '%s' "$tidy"
}

# What a person types or pastes at the question: quotes around the path and
# backslashes in front of spaces are taken away.
tidy_answer() {
    typed=$1
    case $typed in
        \"*\") typed=${typed#\"}; typed=${typed%\"} ;;
        \'*\') typed=${typed#\'}; typed=${typed%\'} ;;
        *) typed=$(printf '%s' "$typed" | sed 's/\\\(.\)/\1/g') ;;
    esac
    tidy_path "$typed"
}

# "uid:gid" of a file or folder, as numbers.
owner_of() {
    ls -ldn "$1" 2>/dev/null | awk 'NR == 1 { print $3 ":" $4 }'
}

# The home folder of a user.
home_of() {
    case $1 in
        '' | *[!A-Za-z0-9._-]*) return 1 ;;
    esac
    if command -v getent >/dev/null 2>&1; then
        getent passwd "$1" | cut -d: -f6
    else
        eval "printf '%s' ~$1"
    fi
}

# This machine's address on the home network. Best effort.
server_address() {
    address=
    if command -v ip >/dev/null 2>&1; then
        address=$(ip -4 route get 192.0.2.1 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p' | head -n 1)
    fi
    if [ -z "$address" ] && command -v route >/dev/null 2>&1 && command -v ipconfig >/dev/null 2>&1; then
        interface=$(route -n get default 2>/dev/null | sed -n 's/^ *interface: *//p' | head -n 1)
        if [ -n "$interface" ]; then
            address=$(ipconfig getifaddr "$interface" 2>/dev/null)
        fi
    fi
    if [ -z "$address" ] && command -v hostname >/dev/null 2>&1; then
        address=$(hostname -I 2>/dev/null | awk '{ print $1 }')
    fi
    printf '%s' "${address:-YOUR-SERVER-ADDRESS}"
}

# A path as one YAML value: in single quotes, with a quote written twice.
# A "$" is written twice too, because Docker Compose reads "$" as the start
# of a variable.
yaml_value() {
    printf "'%s'" "$(printf '%s' "$1" | sed -e "s/'/''/g" -e 's/\$/$$/g')"
}

# docker-compose.yml, exactly as it is in the repository. Do not edit it
# here. After a change to docker-compose.yml, copy it in again with:
#   python3 scripts/check-docs.py --sync
compose_template() {
    cat <<'PHLIX_COMPOSE_FILE'
# Phlix Camera Upload
#
# This file starts the helper that receives the photos and videos the Phlix
# app uploads from your iPhone or iPad, and writes them into a folder of your
# Plex photo library.
#
# How to use this file:
#   1. Change the one line marked CHANGE THE NEXT LINE below.
#   2. In the folder that holds this file, run:  docker compose up -d
#   3. Open https://YOUR-SERVER:7459 in a browser to check that it runs.
#      The browser warns about the certificate. That is expected.
#
# If something does not work, ask the helper what is wrong:
#   docker exec phlix-camera-upload python -m phlix_upload doctor
#
# Setup guide: https://phlixapp.com/camera-upload/
# If the app cannot find the helper:
#   https://github.com/jrl8085/phlix-camera-upload/blob/main/NETWORKING.md

services:
  phlix-camera-upload:
    image: ghcr.io/jrl8085/phlix-camera-upload:1
    container_name: phlix-camera-upload

    # Start again by itself when the server or Docker restarts.
    restart: unless-stopped

    # The Phlix app looks for the helper on port 7459 of your server.
    ports:
      - "7459:7459"

    volumes:
      # Your upload folder: the folder on this server where the photos go.
      #
      # It must be inside a folder that one of your Plex photo libraries
      # includes. If it is not, Plex never shows the photos.
      #
      # Make the folder before you start the helper. Docker refuses to start
      # the helper if the folder is missing. The helper writes files as the
      # user who owns the folder.
      #
      # Write the path as it is on the server itself. If Plex runs in Docker,
      # do not use the path from inside the Plex container.
      #
      # Examples:
      #   Linux      /mnt/media/Photos/Camera Uploads
      #   Synology   /volume1/photo/Camera Uploads
      #   TrueNAS    /mnt/tank/media/Photos/Camera Uploads
      #   Mac        /Users/you/Pictures/Camera Uploads
      #   Windows    C:\Users\you\Pictures\Camera Uploads
      #
      # Spaces in the path are fine. If the path has a "#" after a space, or
      # a ":" before a space, put the whole path in 'single quotes'.
      - type: bind
        # CHANGE THE NEXT LINE. Keep "source: " and write your folder after it.
        source: /CHANGE/THIS/Photos/Camera Uploads
        target: /photos
        bind:
          create_host_path: false

      # The helper's own data: the list of paired phones, the list of files
      # it has received, and its certificate. No photos are kept here.
      # Docker makes a folder named "config" next to this file. Keep it: if
      # it is lost, every phone has to pair again.
      # If your tool has no "next to this file" (TrueNAS, Portainer), write a
      # full path in place of ./config, for example:
      #   /mnt/tank/apps/phlix-camera-upload:/config
      - ./config:/config

    # Lets the helper find Plex Media Server on this machine.
    extra_hosts:
      - "host.docker.internal:host-gateway"

    # The helper can never gain more rights than it was started with.
    security_opt:
      - "no-new-privileges:true"

    # Optional settings. The helper works without any of them.
    #
    # To use one, remove the "# " in front of "environment:" and in front of
    # the setting you want. Leave the other spaces as they are. Then run
    # "docker compose up -d" again.
    #
    # environment:
    #   # Where Plex Media Server is. Set this if the helper's status page
    #   # says "Plex Media Server: Not found", or to make sure that the helper
    #   # asks your own server and no other.
    #   PLEX_URL: "http://192.168.1.10:32400"
    #
    #   # Write files as this user and group. Without these, the helper uses
    #   # the owner of the upload folder.
    #   PUID: "1000"
    #   PGID: "1000"
    #
    #   # Permissions for new files and folders. With 022, other users may
    #   # read them. With 002, the group may also change them.
    #   UMASK: "022"
    #
    #   # The name that the app and the status page show for this helper.
    #   NAME: "Phlix Camera Upload"
    #
    #   # Who may pair. auto: the owner of the Plex server pairs without a
    #   # code and everyone else types the pairing code. code: everyone types
    #   # the code. plex: only the owner of the Plex server may pair.
    #   PAIRING: "auto"
    #
    #   # Your own pairing code, in place of the one the helper makes. Write
    #   # at least 6 letters or digits between the quotes.
    #   PAIRING_CODE: ""
    #
    #   # The folders the helper makes inside the upload folder. You can use
    #   # {device}, {year}, {month} and {day}.
    #   PATH_TEMPLATE: "{device}/{year}/{year}-{month}"
    #
    #   # Refuse uploads that would leave less than this many GB free. Uploads
    #   # that are still arriving count too.
    #   MIN_FREE_GB: "2"
    #
    #   # The largest single file the helper accepts, in GB.
    #   MAX_UPLOAD_GB: "50"
    #
    #   # More file types to accept, besides the usual photo and video types.
    #   # Separate them with commas.
    #   EXTRA_EXTENSIONS: "insp,lrv"
    #
    #   # How much the log says: debug, info, warning or error.
    #   LOG_LEVEL: "info"
    #
    #   # Write "off" only if your own reverse proxy adds HTTPS in front of
    #   # the helper. Phlix talks HTTPS only: with "off" and no such proxy,
    #   # the app cannot use the helper.
    #   TLS: "on"
    #
    #   # Your own certificate and its key, as paths inside the container.
    #   # Set both. A file you put in the config folder is at /config/...
    #   TLS_CERT: "/config/my-cert.pem"
    #   TLS_KEY: "/config/my-key.pem"
    #
    # PORT, BIND, UPLOAD_DIR and CONFIG_DIR exist too. With Docker you do not
    # need them. To use another port on your server, change only the first
    # number in the "ports" line above, for example "8443:7459". The app
    # looks for port 7459 by itself, so with another port you type the
    # helper's address into the app.
PHLIX_COMPOSE_FILE
}

# write_compose FILE: the template, with this install's values filled in.
write_compose() {
    compose_template | while IFS= read -r line; do
        case $line in
            '    image: ghcr.io/jrl8085/phlix-camera-upload:1')
                printf '    image: %s\n' "$IMAGE"
                ;;
            '      - "7459:7459"')
                printf '      - "%s:7459"\n' "$PORT"
                ;;
            '        source: /CHANGE/THIS/Photos/Camera Uploads')
                printf '        source: %s\n' "$(yaml_value "$PHOTOS")"
                ;;
            '    # environment:')
                if [ "$NEED_SETTINGS" = 1 ]; then
                    printf '    environment:\n'
                else
                    printf '%s\n' "$line"
                fi
                ;;
            '    #   PLEX_URL: "http://192.168.1.10:32400"')
                if [ -n "$PLEX_URL" ]; then
                    printf '      PLEX_URL: "%s"\n' "$PLEX_URL"
                else
                    printf '%s\n' "$line"
                fi
                ;;
            '    #   PUID: "1000"')
                if [ -n "$PUID" ]; then
                    printf '      PUID: "%s"\n' "$PUID"
                else
                    printf '%s\n' "$line"
                fi
                ;;
            '    #   PGID: "1000"')
                if [ -n "$PGID" ]; then
                    printf '      PGID: "%s"\n' "$PGID"
                else
                    printf '%s\n' "$line"
                fi
                ;;
            *)
                printf '%s\n' "$line"
                ;;
        esac
    done >"$1"

    # The file must hold this install's folder and port, and no placeholder.
    grep -q "^        source: '" "$1" || return 1
    grep -q "^      - \"$PORT:7459\"\$" "$1" || return 1
    if grep -v '^ *#' "$1" | grep -q '/CHANGE/THIS'; then
        return 1
    fi
    if [ "$NEED_SETTINGS" = 1 ]; then
        grep -q '^    environment:$' "$1" || return 1
    fi
    return 0
}

# The upload folder that an existing docker-compose.yml names. Prints nothing
# when the line cannot be read with certainty.
photos_in_file() {
    written=$(sed -n 's/^ *source: //p' "$1" | head -n 1)
    case $written in
        \'*\')
            written=${written#\'}
            written=${written%\'}
            printf '%s' "$written" | sed -e "s/''/'/g" -e 's/\$\$/$/g'
            ;;
        '' | \"* | *' #'*)
            ;;
        *)
            printf '%s' "$written" | sed -e 's/\$\$/$/g'
            ;;
    esac
}

# The port on this server that an existing docker-compose.yml publishes.
port_in_file() {
    sed -n 's/^ *- *"\{0,1\}\([0-9.]*:\)\{0,1\}\([0-9][0-9]*\):7459"\{0,1\} *$/\2/p' "$1" | head -n 1
}

# setting_in_file FILE NAME: the value of a setting that is switched on in
# an existing docker-compose.yml, such as:   PUID: "1000"
setting_in_file() {
    sed -n "s/^ *$2: \"\\(.*\\)\" *\$/\\1/p" "$1" | head -n 1
}

# The same rule as the helper has for PLEX_URL: http or https, an address,
# and nothing after the port.
valid_plex_url() {
    case $1 in
        http://* | https://*) address_part=${1#*://} ;;
        *) return 1 ;;
    esac
    case $address_part in
        '' | *[!]A-Za-z0-9.:_[-]*) return 1 ;;
    esac
    return 0
}

# Files the installer makes for a moment. They never outlive the run.
TEMP_COMPOSE=
TEMP_OUTPUT=

cleanup() {
    if [ -n "$TEMP_COMPOSE" ]; then
        rm -f "$TEMP_COMPOSE"
    fi
    if [ -n "$TEMP_OUTPUT" ]; then
        rm -f "$TEMP_OUTPUT"
    fi
}

# check_photos: is PHOTOS a folder the helper can use? Sets PHOTOS_STATE to
# "exists" or "missing", or leaves a reason in PHOTOS_PROBLEM.
check_photos() {
    PHOTOS_PROBLEM=
    PHOTOS_STATE=
    case $PHOTOS in
        '')
            PHOTOS_PROBLEM="The folder cannot be empty."
            return 1
            ;;
        /)
            PHOTOS_PROBLEM="The folder cannot be the whole disk (/). Choose a folder inside your Plex photo library."
            return 1
            ;;
        /*) ;;
        *)
            PHOTOS_PROBLEM="Write the full path of the folder. It starts with a slash (/)."
            return 1
            ;;
    esac
    case $PHOTOS in
        "$DIR" | "$DIR"/* )
            PHOTOS_PROBLEM="The upload folder cannot be inside the install folder ($DIR)."
            return 1
            ;;
    esac
    case $DIR in
        "$PHOTOS"/*)
            PHOTOS_PROBLEM="The install folder ($DIR) cannot be inside the upload folder. Choose another one with --dir."
            return 1
            ;;
    esac
    if [ -d "$PHOTOS" ]; then
        PHOTOS_STATE=exists
        return 0
    fi
    if [ -e "$PHOTOS" ]; then
        PHOTOS_PROBLEM="$PHOTOS is a file, not a folder."
        return 1
    fi
    PHOTOS_PARENT=${PHOTOS%/*}
    [ -n "$PHOTOS_PARENT" ] || PHOTOS_PARENT=/
    if [ ! -d "$PHOTOS_PARENT" ]; then
        PHOTOS_PROBLEM="$PHOTOS does not exist, and neither does the folder above it. Check the spelling of the path."
        return 1
    fi
    PHOTOS_STATE=missing
    return 0
}

main() {
    PHOTOS=
    PHOTOS_GIVEN=0
    DIR=
    PORT=7459
    PLEX_URL=
    PUID=
    PGID=
    ASSUME_YES=0
    DRY_RUN=0
    BLOCKERS=0
    COMPOSE_KIND=plugin
    IMAGE=${PHLIX_CAMERA_UPLOAD_IMAGE:-$IMAGE_DEFAULT}
    SETTINGS_GIVEN=0
    PORT_GIVEN=0

    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    while [ "$#" -gt 0 ]; do
        case $1 in
            --photos | --dir | --port | --plex-url | --puid | --pgid)
                [ "$#" -ge 2 ] || die_usage "$1 needs a value."
                option=$1
                value=$2
                shift 2
                ;;
            --photos=* | --dir=* | --port=* | --plex-url=* | --puid=* | --pgid=*)
                option=${1%%=*}
                value=${1#*=}
                shift
                ;;
            --yes | -y)
                ASSUME_YES=1
                shift
                continue
                ;;
            --dry-run)
                DRY_RUN=1
                shift
                continue
                ;;
            --help | -h)
                usage
                exit 0
                ;;
            *)
                die_usage "Unknown option: $1"
                ;;
        esac
        case $option in
            --photos)
                PHOTOS=$(tidy_path "$value")
                PHOTOS_GIVEN=1
                SETTINGS_GIVEN=1
                ;;
            --dir)
                DIR=$(tidy_path "$value")
                ;;
            --port)
                is_number "$value" || die_usage "--port must be a number from 1 to 65535, not \"$value\"."
                while [ "${#value}" -gt 1 ] && [ "${value#0}" != "$value" ]; do
                    value=${value#0}
                done
                [ "${#value}" -le 5 ] && [ "$value" -ge 1 ] && [ "$value" -le 65535 ] ||
                    die_usage "--port must be a number from 1 to 65535, not \"$value\"."
                PORT=$value
                PORT_GIVEN=1
                SETTINGS_GIVEN=1
                ;;
            --plex-url)
                while [ "${value%/}" != "$value" ]; do
                    value=${value%/}
                done
                valid_plex_url "$value" ||
                    die_usage "--plex-url must look like http://192.168.1.10:32400, not \"$value\"."
                PLEX_URL=$value
                SETTINGS_GIVEN=1
                ;;
            --puid)
                is_number "$value" || die_usage "--puid must be a number, not \"$value\"."
                PUID=$value
                SETTINGS_GIVEN=1
                ;;
            --pgid)
                is_number "$value" || die_usage "--pgid must be a number, not \"$value\"."
                PGID=$value
                SETTINGS_GIVEN=1
                ;;
        esac
    done

    IS_ROOT=0
    if [ "$(id -u 2>/dev/null)" = 0 ]; then
        IS_ROOT=1
    fi
    # The words to put in front of "docker" in the commands shown at the end.
    SUDO_WORD=
    if [ "$IS_ROOT" = 1 ] && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then
        SUDO_WORD='sudo '
    fi

    if [ -z "$DIR" ]; then
        home=${HOME:-}
        if [ -n "$SUDO_WORD" ]; then
            # Started with sudo: use the home folder of the person, not of root.
            sudo_home=$(home_of "$SUDO_USER" 2>/dev/null) || sudo_home=
            if [ -n "$sudo_home" ] && [ -d "$sudo_home" ]; then
                home=$sudo_home
            fi
        fi
        [ -n "$home" ] || die_usage "There is no home folder to install into. Give one with --dir PATH."
        DIR=$(tidy_path "$home")/phlix-camera-upload
    fi
    case $DIR in
        /*) ;;
        *) DIR=$(pwd)/$DIR ;;
    esac
    COMPOSE_FILE=$DIR/docker-compose.yml

    if [ "$DRY_RUN" = 1 ]; then
        say "Phlix Camera Upload installer (dry run: nothing is changed)"
    else
        say "Phlix Camera Upload installer"
    fi
    say

    # -- 1. Docker ----------------------------------------------------------

    DOCKER_READY=0
    if ! command -v docker >/dev/null 2>&1; then
        say "Docker:          not found"
        stop "Docker is not installed." \
            "Install Docker first: https://docs.docker.com/engine/install/" \
            "Then run this installer again."
    else
        docker_answer=$(docker_quiet version --format '{{.Server.Version}}' 2>&1)
        docker_status=$?
        if [ "$docker_status" -ne 0 ]; then
            case $docker_answer in
                *[Pp]ermission\ denied*)
                    say "Docker:          installed, but this user may not use it"
                    stop "Docker needs more rights than this user has." \
                        "This installer never uses sudo by itself. Do one of these two things:" \
                        "  1. Run the installer again with sudo in front of sh:" \
                        "       curl -fsSL $INSTALLER_URL | sudo sh" \
                        "  2. Or let your user use Docker, then sign out and in again:" \
                        "       sudo usermod -aG docker \"\$USER\""
                    ;;
                *)
                    say "Docker:          installed, but it does not answer"
                    stop "Docker is installed but not running." \
                        "Start Docker, then run this installer again." \
                        "Docker said: $(printf '%s' "$docker_answer" | head -n 1)"
                    ;;
            esac
        else
            docker_version=$(printf '%s' "$docker_answer" | head -n 1)
            say "Docker:          version $docker_version"
            DOCKER_READY=1
            docker_major=${docker_version%%.*}
            docker_rest=${docker_version#*.}
            docker_minor=${docker_rest%%.*}
            if is_number "$docker_major" && is_number "$docker_minor"; then
                if [ "$docker_major" -lt 20 ] || { [ "$docker_major" -eq 20 ] && [ "$docker_minor" -lt 10 ]; }; then
                    stop "Docker $docker_version is too old. The helper needs Docker 20.10 or later." \
                        "Update Docker, then run this installer again."
                fi
            fi
        fi
    fi

    if [ "$DOCKER_READY" = 1 ]; then
        compose_version=$(docker compose version --short 2>/dev/null </dev/null) || compose_version=
        if [ -n "$compose_version" ]; then
            COMPOSE_KIND=plugin
        elif command -v docker-compose >/dev/null 2>&1; then
            compose_version=$(docker-compose version --short 2>/dev/null </dev/null) || compose_version=
            COMPOSE_KIND=standalone
        fi
        compose_version=${compose_version#v}
        compose_major=${compose_version%%.*}
        if [ -z "$compose_version" ]; then
            say "Docker Compose:  not found"
            if [ -f /etc/unraid-version ]; then
                stop "Unraid has no Docker Compose." \
                    "On Unraid, install the helper with its template instead:" \
                    "https://github.com/jrl8085/phlix-camera-upload#unraid"
            else
                stop "Docker Compose is not installed." \
                    "Install the Docker Compose plugin: https://docs.docker.com/compose/install/" \
                    "Then run this installer again."
            fi
        elif is_number "$compose_major" && [ "$compose_major" -lt 2 ]; then
            say "Docker Compose:  version $compose_version ($(compose_words))"
            stop "Docker Compose $compose_version is too old. The helper needs version 2 or later." \
                "Install the Docker Compose plugin: https://docs.docker.com/compose/install/"
        else
            say "Docker Compose:  version $compose_version ($(compose_words))"
        fi
    fi

    # -- 2. A first install, or an update -----------------------------------

    MODE=install
    if [ -f "$COMPOSE_FILE" ]; then
        if ! grep -q "container_name: $CONTAINER" "$COMPOSE_FILE"; then
            die "$COMPOSE_FILE belongs to something else." \
                "Choose another install folder with --dir PATH."
        fi
        MODE=update
        if [ "$SETTINGS_GIVEN" = 1 ]; then
            MODE=change
            # An option changes an install that exists. What the options do
            # not name stays as the existing file has it.
            if [ "$PORT_GIVEN" = 0 ]; then
                kept=$(port_in_file "$COMPOSE_FILE")
                if is_number "$kept"; then
                    PORT=$kept
                fi
            fi
            if [ -z "$PLEX_URL" ]; then
                kept=$(setting_in_file "$COMPOSE_FILE" PLEX_URL)
                if valid_plex_url "$kept"; then
                    PLEX_URL=$kept
                fi
            fi
            if [ -z "$PUID" ]; then
                kept=$(setting_in_file "$COMPOSE_FILE" PUID)
                if is_number "$kept"; then
                    PUID=$kept
                fi
            fi
            if [ -z "$PGID" ]; then
                kept=$(setting_in_file "$COMPOSE_FILE" PGID)
                if is_number "$kept"; then
                    PGID=$kept
                fi
            fi
        fi
    fi
    NEED_SETTINGS=0
    if [ -n "$PLEX_URL$PUID$PGID" ]; then
        NEED_SETTINGS=1
    fi
    say "Install folder:  $DIR"

    if [ "$MODE" = install ] && [ "$DOCKER_READY" = 1 ]; then
        existing=$(docker_quiet ps -a --filter "name=^/$CONTAINER\$" --format '{{.Names}}' 2>/dev/null) || existing=
        if [ -n "$existing" ]; then
            origin=$(docker_quiet inspect --format '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}' "$CONTAINER" 2>/dev/null) || origin=
            case $origin in
                /*)
                    stop "The helper is already installed, from the folder $origin." \
                        "To update it, run the installer with:  --dir \"$origin\""
                    ;;
                *)
                    stop "A container named $CONTAINER exists already. This installer did not make it." \
                        "To replace it, remove it first:  ${SUDO_WORD}docker rm -f $CONTAINER" \
                        "That does not touch your photos. Then run this installer again."
                    ;;
            esac
        fi
    fi

    # -- 3. The upload folder -------------------------------------------------

    if [ "$MODE" = update ]; then
        say "Upload folder:   as it is in $COMPOSE_FILE"
        say
        say "The helper is installed here already. This run updates it."
    else
        if [ "$PHOTOS_GIVEN" = 0 ] && [ "$MODE" = change ]; then
            # An option changes an install that exists: keep its upload folder.
            PHOTOS=$(photos_in_file "$COMPOSE_FILE")
            if [ -z "$PHOTOS" ]; then
                die_usage "To change this install, give the upload folder again with --photos PATH."
            fi
            PHOTOS_GIVEN=1
        fi
        if [ "$PHOTOS_GIVEN" = 0 ]; then
            if [ "$ASSUME_YES" = 1 ]; then
                die_usage "--yes needs --photos PATH for a first install."
            fi
            if ! have_terminal; then
                if [ "$DRY_RUN" = 1 ]; then
                    say "Upload folder:   not given"
                    stop "The installer has to ask for the upload folder, and there is no terminal to ask on." \
                        "Give the folder with --photos PATH."
                else
                    die_usage "There is no terminal to ask questions on. Give the upload folder with --photos PATH."
                fi
            else
                say
                say "Which folder should receive the photos?"
                say "It must be inside a folder that one of your Plex photo libraries includes,"
                say "for example /mnt/media/Photos/Camera Uploads. If it is not, Plex never shows them."
                tries=0
                while :; do
                    ask "Upload folder:"
                    PHOTOS=$(tidy_answer "$ANSWER")
                    if check_photos; then
                        break
                    fi
                    say "  $PHOTOS_PROBLEM"
                    tries=$((tries + 1))
                    if [ "$tries" -ge 5 ]; then
                        die "No usable upload folder was given."
                    fi
                done
                PHOTOS_GIVEN=1
            fi
        fi
        if [ "$PHOTOS_GIVEN" = 1 ]; then
            if ! check_photos; then
                die_usage "--photos: $PHOTOS_PROBLEM"
            fi
            if [ "$PHOTOS_STATE" = exists ]; then
                say "Upload folder:   $PHOTOS"
            else
                say "Upload folder:   $PHOTOS (it does not exist yet)"
            fi
        fi
    fi

    # -- 4. The plan, for a dry run -----------------------------------------

    if [ "$DRY_RUN" = 1 ]; then
        say
        say "A real run would do this:"
        step=1
        if [ "$MODE" != update ] && [ "${PHOTOS_STATE:-}" = missing ]; then
            say "  $step. Ask whether to make the folder $PHOTOS, and make it."
            step=$((step + 1))
        fi
        if [ ! -d "$DIR" ]; then
            say "  $step. Make the folder $DIR."
            step=$((step + 1))
        fi
        case $MODE in
            install)
                say "  $step. Write $COMPOSE_FILE"
                say "       with the upload folder ${PHOTOS:-(the one you give)}, port $PORT and image $IMAGE."
                ;;
            change)
                say "  $step. Ask whether to replace $COMPOSE_FILE, if the new one differs."
                say "       The old file is kept next to it."
                ;;
            update)
                say "  $step. Keep $COMPOSE_FILE as it is."
                ;;
        esac
        step=$((step + 1))
        say "  $step. Run: $(compose_words) pull"
        step=$((step + 1))
        say "  $step. Run: $(compose_words) up -d"
        step=$((step + 1))
        say "  $step. Wait up to 60 seconds for the helper to be healthy."
        step=$((step + 1))
        say "  $step. Run: docker exec $CONTAINER python -m phlix_upload doctor"
        step=$((step + 1))
        say "  $step. Show the address of the status page and the steps for the Phlix app."
        say
        if [ "$BLOCKERS" -gt 0 ]; then
            say "Nothing was changed. A real run would stop at the point marked above."
            exit 1
        fi
        say "Nothing was changed."
        exit 0
    fi

    # -- 5. Make the folders and write the Compose file ---------------------

    if [ "$MODE" != update ] && [ "$PHOTOS_STATE" = missing ]; then
        say
        if ! confirm "The folder $PHOTOS does not exist. Make it?" y; then
            die "The upload folder does not exist." \
                "Make it yourself, as the user who owns your photos, then run this installer again."
        fi
        if ! mkdir "$PHOTOS" 2>/dev/null; then
            die "This user may not make $PHOTOS." \
                "Make the folder yourself, as the user who owns your photos:" \
                "  mkdir \"$PHOTOS\"" \
                "Then run this installer again."
        fi
        if [ "$IS_ROOT" = 1 ]; then
            # Made by root: hand it to the owner of the folder above it, so
            # that the helper writes files as that user and not as root.
            parent_owner=$(owner_of "$PHOTOS_PARENT")
            case $parent_owner in
                [0-9]*:[0-9]*) chown "$parent_owner" "$PHOTOS" 2>/dev/null || true ;;
            esac
        fi
        say "Made the folder $PHOTOS"
    fi

    if [ "$MODE" != update ]; then
        photos_owner=$(owner_of "$PHOTOS")
        case $photos_owner in
            0:*)
                if [ -z "$PUID" ]; then
                    warn "The upload folder belongs to root, so uploaded files will belong to root."
                    warn "To change that, run the installer again with --puid and --pgid."
                fi
                ;;
            [0-9]*:[0-9]*)
                if [ -z "$PUID" ]; then
                    say "Files will be written as user ${photos_owner%%:*}, group ${photos_owner##*:}: the owner of the upload folder."
                fi
                ;;
        esac
    fi

    if [ ! -d "$DIR" ]; then
        mkdir -p "$DIR" 2>/dev/null || die "This user may not make the install folder $DIR." \
            "Choose another one with --dir PATH."
    fi

    if [ "$MODE" != update ]; then
        new_file=$COMPOSE_FILE.new
        TEMP_COMPOSE=$new_file
        if ! write_compose "$new_file"; then
            die "The Compose file could not be written to $DIR."
        fi
        if ! compose -f "$new_file" config --quiet; then
            die "Docker Compose does not accept the file the installer wrote." \
                "Please report this: https://phlixapp.com/support/"
        fi
        if [ "$MODE" = change ] && cmp -s "$new_file" "$COMPOSE_FILE"; then
            rm -f "$new_file"
            say "The Compose file is already as asked. Kept it."
        elif [ "$MODE" = change ]; then
            say
            say "$COMPOSE_FILE exists, and the new one differs from it."
            say "The new file keeps the upload folder, the port, PLEX_URL, PUID and PGID."
            say "Other changes that you made by hand are not carried over."
            say "The old file is kept next to the new one."
            if confirm "Replace $COMPOSE_FILE?" n; then
                backup=$COMPOSE_FILE.before-$(date +%Y%m%d-%H%M%S)
                cp -p "$COMPOSE_FILE" "$backup" || die "The old Compose file could not be copied to $backup."
                mv -f "$new_file" "$COMPOSE_FILE"
                say "Wrote $COMPOSE_FILE. The old one is kept as $backup"
            else
                rm -f "$new_file"
                say "Kept your $COMPOSE_FILE as it is."
                MODE=update
            fi
        else
            mv -f "$new_file" "$COMPOSE_FILE"
            say "Wrote $COMPOSE_FILE"
        fi
        if [ -n "$SUDO_WORD" ] && [ -n "${SUDO_UID:-}" ] && [ -n "${SUDO_GID:-}" ]; then
            # Started with sudo: the person keeps their own folder and file.
            chown "$SUDO_UID:$SUDO_GID" "$DIR" "$COMPOSE_FILE" 2>/dev/null || true
        fi
    fi

    # -- 6. Download and start ----------------------------------------------

    cd "$DIR" || die "The install folder $DIR cannot be opened."
    image_in_file=$(sed -n 's/^ *image: *//p' "$COMPOSE_FILE" | head -n 1)
    [ -n "$image_in_file" ] || image_in_file=$IMAGE

    say
    say "Downloading the image ..."
    if ! compose pull; then
        if docker_quiet image inspect "$image_in_file" >/dev/null 2>&1; then
            warn "The newest image could not be downloaded. Using the image that is already here."
        else
            die "The image could not be downloaded." \
                "Check that this server can reach the internet, then run this installer again."
        fi
    fi

    say
    say "Starting the helper ..."
    TEMP_OUTPUT=$DIR/.install-output
    if compose up -d >"$TEMP_OUTPUT" 2>&1; then
        cat "$TEMP_OUTPUT"
    else
        cat "$TEMP_OUTPUT" >&2
        reason=$(cat "$TEMP_OUTPUT")
        case $reason in
            *"port is already allocated"* | *"address already in use"*)
                die "Port $PORT is already in use on this server." \
                    "Run the installer again with another port, for example:  --port 7460" \
                    "With another port, you type the helper's address into the Phlix app."
                ;;
            *"is already in use by container"*)
                die "Another container named $CONTAINER exists already." \
                    "Remove it first:  ${SUDO_WORD}docker rm -f $CONTAINER" \
                    "That does not touch your photos. Then run this installer again."
                ;;
            *"bind source path does not exist"*)
                die "The upload folder in $COMPOSE_FILE does not exist." \
                    "Make the folder, or correct the line that starts with \"source:\", then run this installer again."
                ;;
            *"invalid IP address in add-host"*)
                die "This Docker is too old. The helper needs Docker 20.10 or later."
                ;;
            *)
                die "Docker could not start the helper. Its message is above."
                ;;
        esac
    fi

    # -- 7. Wait until it is healthy ----------------------------------------

    say
    printf 'Waiting for the helper to be healthy '
    waited=0
    health=starting
    while [ "$waited" -lt 60 ]; do
        state=$(docker_quiet inspect --format '{{.State.Status}} {{.RestartCount}} {{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$CONTAINER" 2>/dev/null) || state='missing 0 none'
        set -- $state
        status=${1:-missing}
        restarts=${2:-0}
        health=${3:-none}
        if [ "$status" = running ] && [ "$health" = healthy ]; then
            break
        fi
        case $status in
            exited | dead | missing)
                health=stopped
                break
                ;;
        esac
        if is_number "$restarts" && [ "$restarts" -gt 0 ]; then
            health=stopped
            break
        fi
        printf '.'
        sleep 2
        waited=$((waited + 2))
    done
    say

    if [ "$health" = stopped ]; then
        say
        say "The last lines of the helper's log:"
        docker_quiet logs --tail 30 "$CONTAINER" 2>&1 | grep -v 'Pairing code' | sed 's/^/  /'
        die "The helper started and stopped again. Its log, above, says why." \
            "The whole log:  ${SUDO_WORD}docker logs $CONTAINER"
    fi
    if [ "$health" != healthy ]; then
        warn "Docker has not reported the helper healthy after 60 seconds. Its own check follows."
    fi

    # -- 8. The helper's own check ------------------------------------------

    say
    say "The helper's own check:"
    doctor_status=0
    docker_quiet exec "$CONTAINER" python -m phlix_upload doctor 2>&1 | sed 's/^/  /' >"$TEMP_OUTPUT"
    cat "$TEMP_OUTPUT"
    if grep -q '^  Nothing needs fixing\.$' "$TEMP_OUTPUT"; then
        doctor_status=0
    else
        doctor_status=1
    fi

    # -- 9. What to do next ---------------------------------------------------

    address=$(server_address)
    shown_port=$(port_in_file "$COMPOSE_FILE")
    [ -n "$shown_port" ] || shown_port=$PORT

    say
    if [ "$doctor_status" -eq 0 ]; then
        say "Phlix Camera Upload is running."
    else
        say "Phlix Camera Upload is installed, but its own check found something to fix."
        say "Read the PROBLEM lines above. Each one has a line that starts with Fix."
    fi
    say
    say "  Status page:     https://$address:$shown_port"
    say "                   Your browser warns about the certificate. That is expected:"
    say "                   the helper makes its own certificate."
    if [ "$MODE" != update ]; then
        say "  Upload folder:   $PHOTOS"
    fi
    say "  Install folder:  $DIR"
    say
    say "One thing to do in Plex:"
    say "  Switch on Settings > Library > Scan my library automatically."
    say "  Plex shows new photos only after it scans."
    say
    say "Three steps in the Phlix app, version 1.0.21 or later:"
    say "  1. Connect the iPhone or iPad to your home Wi-Fi."
    say "  2. Open Phlix and go to Settings > Camera Upload."
    say "  3. Tap Check for the Helper and follow the steps on screen. Phlix shows Connected when it has paired."
    if [ "$shown_port" != 7459 ]; then
        say
        say "Phlix looks for port 7459 by itself. This helper is on port $shown_port,"
        say "so type this address into the app:  https://$address:$shown_port"
    fi
    say
    say "The pairing code:"
    say "  The owner of the Plex server pairs without a code."
    say "  Everyone else types the pairing code. To see it, run:"
    say "    ${SUDO_WORD}docker exec $CONTAINER python -m phlix_upload code"
    say "  It is also in the helper's log:  ${SUDO_WORD}docker logs $CONTAINER"
    say
    say "To update the helper later, run this installer again."
    say "If the app cannot find the helper, read: $NETWORKING_URL"

    if [ "$doctor_status" -ne 0 ]; then
        exit 1
    fi
    exit 0
}

# The whole file is read before anything runs, so a download that stops
# half way does nothing.
main "$@"
