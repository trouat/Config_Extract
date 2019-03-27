#!/bin/bash

#
#  Validation des extractions de configuration
#  Multiprocess : très rapide…
#  Test `time` pour 100 archives de 276 Ko :
#  ./verify_extract.sh extract/*  12,47s user 1,72s system 194% cpu 7,306 total
#
#  Test `time` pour 500 archives de 276 Ko :
#  ../verify_extract.sh deb.config*   38,77s user 5,47s system 181% cpu 24,332 total
#
##############################################################
# Testé sur :
#     - Debian Wheezy
#     — ArchLinux 4.9.11-1
##############################################################

##############################################################
# Suivi des modifications :
#     - Création du script (trt - 31/09/2013)
#     - Gestion n fichier (tar.xz | répertoire) (trt - 03/06/2013)
##############################################################

#set -x

BASE_FILE="find.txt netstat.txt pkg_list.txt ps.txt mount.txt uname.txt kernel_config.txt passwd.txt group.txt network.txt routes.txt iptables.txt kernel_modules.txt lspci.txt cpuinfo.txt"

TAR_FILE="var_spool_cron.tar.xz etc.tar.xz"

ETC_FILE="etc/passwd etc/shadow etc/sudoers etc/ssh/sshd_config"

THIS=$(pwd)
DIR=$(cd "$(dirname "$0")" && pwd || exit 1;)
#SEQ=$#

run () {
    cd "$THIS" || exit 1;
    if [ ! -n "$__R" ]; then
        __R=0;
    else
        let __R=$__R+1;
    fi
    LOCKDIR=$(basename "$0").$__R
    shift;
    export __R
    [ ! $# -eq 0 ] && "$DIR"/"$(basename "$0")" $@ > /dev/shm/"$LOCKDIR" &
    F_PID=$!
}

out-all() {
    wait $F_PID && cat /dev/shm/"$(basename "$0")".$__R; rm /dev/shm/"$(basename "$0")".$__R;
    #[[ $__R -eq 0 ]] && rm /dev/shm/"$(basename "$0")".*;
    #[[ $__R -eq 0 ]] && cat /dev/shm/"$(basename "$0")".* && rm /dev/shm/"$(basename "$0")".*;
}

clean() {
#TODO Stopper les fils en cas d'abandon
if [ -d "$TMP" ]; then
    echo "[$__R] nettoyage répertoire de sortie ($OUTDIR)";
    rm -rf "$TMP";
fi
if [ -n "$LOCKDIR" ]; then
    out-all;
fi
}

trap clean 0;
run $@;

erreur() {
    clean;
    echo "[$__R] $1" > /dev/stderr;
    exit 42;
}

usage () {
    echo "Usage :";
    basename "$0";
    echo "               <repertoire_extraction | extraction.tar.xz> […]";
}

ctrl_etc () {
    echo "[$__R] Points de contrôle de l'archive \"etc\"."

    if [ -n "$BZ2" ]; then
        tar -C "$TMP" -xf "$BZ2" --wildcards --no-anchored '*etc*.tar.xz';
    fi
    for ctrl in $ETC_FILE; do
        if tar -tvf etc.tar.xz | grep "$ctrl\$" > /dev/null; then
            echo "   -> $ctrl : OK";
        else
            echo "   -> $ctrl : ÉCHEC";
        fi
    done
}

echo "[$__R] Traitement $(basename "$1")";
#echo "++++ Début $__R" > /dev/stderr

# Vérification des entrées
if [ $# -eq 0 ]; then
    usage;
    erreur "pas d'argument.";
elif [ -d "$1" ]; then
    OUTDIR="$1";
elif [ -f "$1" ] && [[ "$1" =~ .*\.tar\.xz ]]; then
#    TMP="$(mktemp -d)";
    TMP=/dev/shm/$$.tmp
    mkdir $TMP;
    tar -C "$TMP/" -xf "$1" --wildcards --no-anchored '*.txt';
#    tar -C "$TMP" -xf --file $BASE_FILE "$1";
    OUTDIR="$TMP/$(ls $TMP)";
    cd "$(dirname "$1")" || exit 1;
    BZ2=$(pwd)/$(basename "$1");
else
    erreur "Argument invalide : \"$1\"";
fi

if [ ! -d "$OUTDIR" ]; then
    erreur "\"$OUTDIR\" n'est pas un répertoire.";
elif ! cd "$OUTDIR"; then
    erreur "impossible d'accéder à \"$OUTDIR\".";
fi

# Vérification de la présence des fichiers
echo "[$__R] Contrôle de la présence des preuves"
for file in $BASE_FILE; do
    if [ ! -f "$file" ]; then
        echo "[$__R] ATTENTION : le fichier $file manque.";
    fi
done

# Affiche la date
[ -f timestamp.txt ] && echo "[$__R] Date d’extraction : $(date --date @`cat timestamp.txt`)";

# Vérification des sommes de contrôles
echo "[$__R] Contrôle des hachés MD5"
if [ ! -f check.txt ]; then
    echo "[$__R] ATTENTION : impossible de trouver check.txt.";
else
    md5sum -c check.txt;
fi

# Vérification des erreurs find
echo "[$__R] Contrôle des erreurs find"
if [ ! -f find_log.txt ]; then
    echo "[$__R] ATTENTION : impossible de trouver find_log.txt.";
else
    grep -E -v ' .?/proc' find_log.txt;
fi

# Vérification de la présence des archives
echo "[$__R] Contrôle de la présence des archives.";
etc=1;
if [ -n "$BZ2" ]; then
    for tfile in $TAR_FILE; do
        if ! tar -tvf "$BZ2" | grep "$tfile\$" > /dev/null; then
            echo "[$__R] ATTENTION : le fichier $tfile manque.";
            [[ "$tfile" == "etc.tar.xz" ]] && etc=0;
        fi
    done
else
    for tfile in $TAR_FILE; do
        if [ ! -f "$tfile" ]; then
            echo "[$__R] ATTENTION : le fichier $file manque.";
            [[ "$tfile" == "etc.tar.xz" ]] && etc=0;
        fi
    done
fi

# Vérification de la présence de fichers clefs dans les tar.xz
[ $etc -eq 1 ] && ctrl_etc;

