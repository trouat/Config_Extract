#!/bin/bash
#set -x

##############################################################
# Testé sur 
#     - Valide pour | Fedora 22, Archlinux 1.4/4.9.11-1-ARCH
#                   | Debian 3.0 r6
#     - Voir le dépôt gitlab pour plus d’informations
##############################################################

# CONFIGURATION
TMPDIR="/tmp/extract_linux/"
OUTFILE="/tmp/`hostname`.config.$$.tar.xz"
LG="/var/log"
NETTOYAGE=1
HOSTNAME=`hostname`
VERIFIE=1

OUT_FILE_LST="find.txt find_log.txt netstat.txt pkg_list.txt ps.txt mount.txt uname.txt kernel_config.txt config.gz passwd.txt group.txt network.txt routes.txt iptables.txt kernel_modules.txt lspci.txt cpuinfo.txt sysctl.txt"


VAR_LOG="$LG/dpkg.log $LG/aptitude $LG/alternatives.log $LG/apt/history.log $LG/pacman.log $LG/lxc/lxc-monitord.log $LG/yum.log $LG/dnf.log*"

erreur() {
    echo "[!] $1" > /dev/stderr
    exit 42
}

nettoyage() {
    if [ ${NETTOYAGE} -eq 1 ]; then
	echo "[!] nettoyage répertoire de sortie (${OUTDIR})" > /dev/stderr
	rm -rf ${TMPDIR}
    fi
}

verification () {
    __mypwd=`pwd`; cd "${OUTDIR}" || exit 1;

    for __file in ${OUT_FILE_LST}; do
        if [ ! -f "${__file}" ]; then
            echo "[!] ATTENTION : le fichier ${__file} manque.";
        elif which md5sum > /dev/null 2>&1; then
            md5sum "${__file}" >> "${OUTDIR}"/check.txt;
        fi
    done
    
    cd "${__mypwd}" || ( echo "Impossible de retourner dans l’arborescence initiale." && exit 1 );
}

# Got from http://fr.w3support.net/index.php?db=sf&id=3331
get_distribution_type()
{
    # Assume unknown
    __dtype="unknown"

    # First test against Fedora / RHEL / CentOS / generic Redhat derivative
    if [ -r /etc/rc.d/init.d/functions ]; then
        . /etc/rc.d/init.d/functions
        [ zz`type -t passed 2>/dev/null` == "zzfunction" ] && __dtype="redhat"

    # Then test against SUSE (must be after Redhat,
    # I've seen rc.status on Ubuntu I think? TODO: Recheck that)
    elif [ -r /etc/rc.status ]; then
        . /etc/rc.status
        [ zz`type -t rc_reset 2>/dev/null` == "zzfunction" ] && __dtype="suse"

    # Then test against Debian, Ubuntu and friends
    elif [ -r /lib/lsb/init-functions ]; then
        . /lib/lsb/init-functions
        [ zz`type -t log_begin_msg 2>/dev/null` == "zzfunction" ] && __dtype="debian"
    # Then test against old Debian style
    elif [ -f /etc/debian_version ] && ( which dpkg > /dev/null ) && ( which apt-get > /dev/null ); then
        __dtype="debian";
    # Then test against Gentoo
    elif [ -r /etc/init.d/functions.sh ]; then
        . /etc/init.d/functions.sh
        [ zz`type -t ebegin 2>/dev/null` == "zzfunction" ] && __dtype="gentoo"

    # For Slackware we currently just test if /etc/slackware-version exists
    # and isn't empty (TODO: Find a better way :)
    elif [ -s /etc/slackware-version ]; then
        __dtype="slackware"
    fi

    DISTRO=${__dtype}
}

get_pkg () {
    if [ "${DISTRO}" == "debian" ]; then
        dpkg -l > "${OUTDIR}"/pkg_list.txt;
    elif [ "${DISTRO}" == "redhat" ]; then
        rpm -qa --last > "${OUTDIR}"/pkg_list.txt;
    else
        echo "[!] attention, distribution non reconnue";
    fi
}

get_eth () {
    for __inet in /sys/class/net/*; do 
        ethtool "`basename "${__inet}"`";
    done;
}

which_compress () {
    (which xz || which bzip2 || which gzip || which compress) | tail -n1;
}

get_lxc_conf () {
    echo "[-] LXC conf…"
    lxc-checkconfig > "${OUTDIR}"/lxc-check.txt;

    ( for cfg in `lxc-config -l`; do
        echo "[+] ${cfg}";
        lxc-config ${cfg};
    done; ) > "${OUTDIR}"/lxc-config.txt;

    lxc-ls > "${OUTDIR}"/lxc-ls.txt;
}

get_selinux_conf () {
    echo "[-] SELinux conf…"
    getenforce > "${OUTDIR}"/selinux-enforce.txt;
    sestatus > "${OUTDIR}"/selinux-status.txt;
    Z="Z";
    lsZ='-exec ls -Z {} ;';
    getsebool -a > "${OUTDIR}"/selinux-bool.txt;
    semanage login -l > "${OUTDIR}"/se-login.txt;
    id -Z >  "${OUTDIR}"/se-id.txt;
}

get_crypt_conf () {
    echo "[-] cryptsetup conf…"
    dmsetup ls --target crypt > "${OUTDIR}"/crypt_target.txt;
    
    for item in $(cat "${OUTDIR}"/crypt_target.txt | awk '{print $1}');
        do cryptsetup status ${item} >> "${OUTDIR}"/encrypted.txt;
    done;
}

get_file_attrib () {
    echo "[-] attributs étendus des fichiers"
    mkfifo "${OUTDIR}"/fifo_ls "${OUTDIR}"/fifo_attr "${OUTDIR}"/fifo_cap;
    
    cat "${OUTDIR}"/fifo_attr | xargs -0 lsattr      > "${OUTDIR}"/attr_all.txt 2> "${OUTDIR}"/attr_log.txt&
    __ps_attr=$!;
    cat "${OUTDIR}"/fifo_cap  | xargs -0 getcap      > "${OUTDIR}"/cap.txt  2> "${OUTDIR}"/cap_log.txt&
    __ps_cap=$!;
    cat "${OUTDIR}"/fifo_ls   | xargs -0 ls -ltd${Z} > "${OUTDIR}"/find.txt 2> "${OUTDIR}"/find_log.txt&
    __ps_ls=$!;
    
    find / -print0 | tee "${OUTDIR}"/fifo_ls "${OUTDIR}"/fifo_attr "${OUTDIR}"/fifo_cap > /dev/null&
    __ps_find=$!;
    
    wait ${__ps_find}; 
    grep "^[cdrwx-]\{10\}+" "${OUTDIR}"/find.txt | awk '{print $NF}' | xargs getfacl > "${OUTDIR}"/acl.txt
    
    wait ${__ps_attr}; 
    grep -v "^-------------------- " "${OUTDIR}"/attr_all.txt > "${OUTDIR}"/attr.txt;
    
    wait ${__ps_cap}; wait ${__ps_ls};
    rm "${OUTDIR}"/fifo_ls "${OUTDIR}"/fifo_attr "${OUTDIR}"/fifo_cap;
}

echo "[+] validation compression"
_compress=`which_compress`
if [ -f "${_compress}" ]; then
    _tar="tar --"`basename "${_compress}"`" -cf";
else
    echo "Pas de compression de l’archive";
    _tar="tar -cf";
fi

echo "[+] vérification des droits"
if [ ! "`id -u`" -eq 0 ]; then
    erreur "Le script doit être exécuté avec les droits « root »"
fi

echo "[+] création du répertoire de destination"
MKTEMP_BIN=`which mktemp`
if [ -n "${MKTEMP_BIN}" ] && [ -x "${MKTEMP_BIN}" ]; then
    TMPDIR="`mktemp -d`"
    OUTDIR="${TMPDIR}/${HOSTNAME}"
    mkdir -p  "${OUTDIR}"
elif [ ! -d "${OUTDIR}" ]; then
    mkdir -p "${OUTDIR}"
else
    erreur "Impossible de créer le répertoire de sortie"
fi
echo "[-] répertoire de sortie : « ${OUTDIR} »"

echo "[+] détection de la distribution"
get_distribution_type
echo "[-] distribution détectée : ${DISTRO}"

# Nettoyage uniquement après la création du répertoire de sortie
trap "nettoyage" 0

echo "[+] présence de LXC ?"
( which lxc-ls > /dev/null 2>&1; ) && ( which lxc-checkconfig > /dev/null 2>&1; ) && get_lxc_conf&

echo "[+] présence de SELinux ?"
( id -Z > /dev/null 2>&1; ) && get_selinux_conf&

echo "[+] présence de dm_crypt ?"
( lsmod | grep dm_crypt > /dev/null 2>&1; ) && get_crypt_conf&

wait;

echo "[+] liste des fichiers et des droits associés"
( which lsattr > /dev/null  ) && get_file_attrib || find / -print0 | xargs -0 ls -ltd${Z} > "${OUTDIR}"/find.txt 2> "${OUTDIR}"/find_log.txt;


### Liste des fichiers avec exclusion de répertoire (Linux)
#find / -type d \( -wholename "/directoryA" -o -wholename "/DirectoryB" \) -prune -o -ls ${lsZ} > "${OUTDIR}"/find.txt

echo "[+] liste des processus en écoute"
( ( which ss > /dev/null ) && ss -a -n -p || netstat -a -n -p ) > "${OUTDIR}"/netstat.txt&

echo "[+] liste des sockets en écoute"
( ( which ss > /dev/null ) && ss -ltp ) > "${OUTDIR}"/ss-listen.txt&

echo "[+] liste de connexions établies"
( ( which ss > /dev/null ) && ss -ptn ) > "${OUTDIR}"/ss-established.txt&

echo "[+] liste des processus actifs"
ps faux${Z} > "${OUTDIR}"/ps.txt&

echo "[+] liste formatées des processus"
ps -axeo pid,ppid,user,args > "${OUTDIR}"/ps-format.txt&

wait;

echo "[+] liste des paquets installés"
get_pkg&

echo "[+] contenu du répertoire /etc/"
${_tar} "${OUTDIR}"/etc.tar.xz -p --atime-preserve --dereference /etc&
### Ignore certains fichiers sensibles (linux)
#${tar} "${OUTDIR}"/etc.tar.xz -p --atime-preserve --dereference --wildcards --exclude "/etc/passwd*" --exclude "/etc/shadow*" --exclude "/etc/group*" --exclude "/etc/krb5.conf" --exclude "/etc/sudoers*" --exclude "/etc/publickeys*" --exclude "/etc/pki*" /etc

echo "[+] liste des points de montage"
mount > "${OUTDIR}"/mount.txt&

echo "[+] version du noyau en cours de fonctionnement"
uname -a > "${OUTDIR}"/uname.txt&

echo "[+] configuration du noyau"
[ -f /boot/"config-`uname -r`" ] && cp /boot/"config-`uname -r`" "${OUTDIR}"/kernel_config.txt&
[ -f /proc/config.gz ] && cp /proc/config.gz "${OUTDIR}"/config.gz&

echo "[+] liste des utilisateurs et des groupes"
getent passwd > "${OUTDIR}"/passwd.txt&
getent group > "${OUTDIR}"/group.txt&

echo "[+] configuration réseau"
( ( which ip > /dev/null ) && ip a || ifconfig -a ) > "${OUTDIR}"/network.txt&
( ( which ethtool > /dev/null ) && get_eth ) > "${OUTDIR}"/net_phys.txt&

echo "[+] table de routage"
( ( which ip > /dev/null ) && ip route show || route -n -e ) > "${OUTDIR}"/routes.txt&

echo "[+] règles du pare-feu"
iptables-save > "${OUTDIR}"/iptables.txt&

echo "[+] liste des modules noyau"
lsmod > "${OUTDIR}"/kernel_modules.txt&

echo "[+] configuration matérielle"
lspci -vvv > "${OUTDIR}"/lspci.txt&
cat /proc/cpuinfo > "${OUTDIR}"/cpuinfo.txt&

echo "[+] options système"
sysctl -a > "${OUTDIR}"/sysctl.txt&

echo "[+] liste des tâches plannifiées des utilisateurs, répertoire"
[ -d /var/spool/cron ] && ${_tar} "${OUTDIR}"/var_spool_cron.tar.xz -p --atime-preserve /var/spool/cron&
[ -d /var/spool/anacron ] && ${_tar} "${OUTDIR}"/var_spool_anacron.tar.xz  -p --atime-preserve /var/spool/anacron&
echo "[+] journaux d’installation"
[ -d /var/log ] && ${_tar} "${OUTDIR}"/var_log.tar.xz -p --atime-preserve --ignore-failed-read "${VAR_LOG}" 2> "${OUTDIR}"/var_log.txt&

wait;

echo "[+] timestamp"
date +%s > "${OUTDIR}"/timestamp.txt;

echo "[+] vérification de la présence des fichiers"
[ "${VERIFIE}" -eq 1 ] && verification;

echo "[+] création de l'archive finale"
cd "${TMPDIR}" || ( echo "Erreur d’accès à « ${TMPDIR} »." && exit 1 );
${_tar} "${OUTFILE}" "${HOSTNAME}"

echo "[+] Ok ! Fichier de sortie : « ${OUTFILE} »"
