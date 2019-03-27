#!/bin/bash

##############################################################
# Testé sur Solaris 9u8, 10 et 11.1
#     - Valide pour Solaris 10 et 11
#     - Solaris 9 et antérieur : ne fonctionne pas
##############################################################

##############################################################
# Suivi des modifications :
#     - Création à partir du script linux (trt - 15/05/2013)
#     - Adaptation pour Solaris 10 (trt - 24/05/2013)
#     - Sortie en erreur pour Solaris 9 (trt - 28/05/2013)
#     - Gestion zone non globale Solaris 10 (trt - 28/05/2013)
##############################################################

# CONFIGURATION
TMPDIR="/tmp/extract_solaris/"
OUTFILE="/tmp/`hostname`.config.$$.tar"
NETTOYAGE=1
HOSTNAME=`hostname`

#Versions testés (regexp)
VERSIONS="^(11\.1|10)$"

lsof_dir="/usr/local/bin/lsof";

erreur() {
    echo "[!] $1" > /dev/stderr
    exit 42
}

nettoyage() {
    if [ $NETTOYAGE -eq 1 ]; then
	echo "[!] nettoyage répertoire de sortie ($OUTDIR)" > /dev/stderr
        cd /tmp;
	rm -rf $TMPDIR
    fi
}

get_version()
{
    local dtype
    # Inconnu
    version="unknown"

    # Pour Solaris, trouver "Solaris" dans /etc/release
    if [ -s /etc/release ]; then
        cat /etc/release | grep -i "Solaris";
        if [ $? -eq 0 ]; then
            version=$(head -n1 /etc/release | awk '{print $3}');
        fi
    else
       erreur "Système non supporté : ce n'est pas un OS Solaris";
    fi
    
    RELEASE=$version
}

#Détection de la version avant de faire quoi que ce soit d'autre
echo "[+] détection de la version"

get_version

echo "[-] version détectée : $RELEASE"
if echo $RELEASE | grep "9/"; then
   erreur "version obsolète. Abandon."
fi

if [[ ! $RELEASE =~ $VERSIONS ]]; then
    rep="nop";
    while [[ ! "$rep" =~ ^[oOnN]{1}$ ]]
    do
        echo "    Cette version n'as pas été testée.";
        echo "    Versions testés : $VERSIONS."
        echo "    Ce script est écrit pour les versions :"
        echo "         → 10 et 11."
        echo "    Continuer quand même ? [o/N]"
        read rep;
    done

    if [[ "$rep" =~ [nN] ]]; then
        erreur "Abandon, version non testée ($RELEASE)"
    fi
fi

get_pfiles_listen_ps()
{
    echo "[-] $1";
    rep="nop"
    while [[ ! "$rep" =~ ^[oOnN]{1}$ ]]
    do
        echo "[!] Attention ! La méthode de listage utilise pfiles"
        echo "    sur tout les PID découverts dans /proc."
        echo "    Cette méthode peut parfois surcharger le système."
        echo ""
        echo "    Continuer ? [o/N]"
        read rep;
    done
    if [[ "$rep" =~ [oO] ]]; then
        for i in $(ls /proc/ | sed 's+/++g')
        do
            echo "++++ Process $i ++++" >> $OUTDIR/netstat.txt
            pfiles $i | grep AF_INET >> $OUTDIR/netstat.txt
        done;
    else
        echo "[!] Abandon, pas de liste des processus en écoute"
    fi
}

get_lsof_listen_ps()
{
# Beware if you are on Solaris 10 and using ZONES(more on zones in solaris 10 coming soon)
# On Solaris 10, using “lsof -i” to show mapping of processes to TCP ports incorrectly shows all processes that have socket open as using port 65535
echo "[-] lsof=$lsof_dir";
    if pkgcond is_global_zone; then
        $lsof_dir -i > $OUTDIR/netstat.txt;
    else
        if [[ $RELEASE =~ ^10(\..*)?$ ]]; then
            get_pfiles_listen_ps "Zone non globale sous Solaris 10.x";
        else
            $lsof_dir -z > $OUTDIR/netstat.txt;
        fi
    fi
}

echo "[+] vérification des droits"
#Solaris 10 : pas d'option '-u' pour id
if [ ! "`id | sed 's/uid=\([0-9]*\)(.*/\1/'`" -eq 0 ]; then
    erreur "Le script doit être exécuté avec les droits « root »"
fi

echo "[+] création du repertoire de destination"
MKTEMP_BIN=`which mktemp`
if [ -n $MKTEMP_BIN -a -x $MKTEMP_BIN ]; then
    TMPDIR="`mktemp -d`"
    OUTDIR="$TMPDIR/$HOSTNAME"
    mkdir $OUTDIR
elif [ ! -d $OUTDIR ]; then
    mkdir $OUTDIR
else
    erreur "Impossible de créer le répertoire de sortie"
fi
echo "[-] répertoire de sortie : $OUTDIR"
  
# Nettoyage uniquement après la création du répertoire de sortie
trap "nettoyage" 0

echo "[+] liste des fichiers et des droits associés"
### Liste des fichiers avec exclusion de répertoire (Solaris 11)
#find / -exec test "{}" == "/mounted_filesystemA" -o "{}" == "/mounted_filesystemB" \; -prune -o -ls > $OUTDIR/find.txt

find / -ls > $OUTDIR/find.txt

echo "[+] liste des processus en écoute"
if [ ! -s $lsof_dir ]; then
    #Solaris 10 : which renvoie toujours 0
    #             message d'erreur de wich sur stdout
    lsof_dir=$(which lsof);
    if [ ! -s "$lsof_dir" ]; then
        get_pfiles_listen_ps "pas de binaire lsof détecté";
    else
        get_lsof_listen_ps;
    fi
else
    get_lsof_listen_ps;
fi

echo "[+] liste des paquets installés"
    pkginfo > $OUTDIR/pkg_list.txt

echo "[+] contenu du répertoire /etc/"
if [[ "$RELEASE" =~ ^11(\..*){0,1}$ ]]; then
    tar cjf $OUTDIR/etc.tar.bz2 /etc;
elif [[ "$RELEASE" =~ ^10(\..*){0,1}$ ]]; then
    tar cf $OUTDIR/etc.tar /etc;
    bzip2 -z $OUTDIR/etc.tar;
fi

### Ignore certains fichiers sensibles (Solaris 11)
#echo -e "/etc/krb5/krb5.conf\n/etc/passwd\n/etc/group\n/etc/krb5.conf\n/etc/sudoers\n/etc/publickeys\n/etc/pki" > $OUTDIR/exclude.txt
#tar cjfX $OUTDIR/etc.tar.bz2 $OUTDIR/exclude.txt  /etc

echo "[+] liste des processus actifs"
#[[ "$RELEASE" =~ ^11(\..*){0,1}$ ]] && ps -ejH > $OUTDIR/ps.txt;
#[[ "$RELEASE" =~ ^10(\..*){0,1}$ ]] && 
ps -ejf > $OUTDIR/ps.txt;

echo "[+] liste des points de montage"
    mount > $OUTDIR/mount.txt;

echo "[+] version du noyau en cours de fonctionnement"
uname -a > $OUTDIR/uname.txt;

echo "[+] configuration du noyau"

echo "[+] liste des utilisateurs et des groupes"
getent passwd > $OUTDIR/passwd.txt;
getent group > $OUTDIR/group.txt;

echo "[+] configuration réseau"
ifconfig -a > $OUTDIR/network.txt

echo "[+] table de routage"
   netstat -nrv > $OUTDIR/routes.txt;

echo "[+] règles du pare-feu"
   ipfstat -io >  $OUTDIR/iptables.txt 2>&1;

echo "[+] liste des modules noyau"
   modinfo > $OUTDIR/kernel_modules.txt;

echo "[+] configuration matérielle"
if [[ $(which scanpci > /dev/null 2>&1) != "" ]]; then
    scanpci -v > $OUTDIR/lspci.txt;
elif [ -s /usr/X11/bin/scanpci ]; then
    /usr/X11/bin/scanpci -v > $OUTDIR/lspci.txt;
else
    echo "[!] ne trouve pas scanpci";
fi
    prtconf > $OUTDIR/prtconf.txt
    prtdiag > $OUTDIR/prtdiag.txt
    psrinfo -v > $OUTDIR/psrinfo.txt

echo "[+] liste des tâches plannifiées des utilisateurs, répertoire"
if [[ "$RELEASE" =~ ^11(\..*){0,1}$ ]]; then
    tar cjf $OUTDIR/var_spool_cron.tar.bz2 /var/spool/cron;
elif [[ "$RELEASE" =~ ^10(\..*){0,1}$ ]]; then
    tar cf $OUTDIR/var_spool_cron.tar /var/spool/cron;
    bzip2 -z $OUTDIR/var_spool_cron.tar;
fi

echo "[+] création de l'archive finale"
cd $TMPDIR
if [[ "$RELEASE" =~ ^11(\..*){0,1}$ ]]; then
    tar cjf $OUTFILE.bz2 $HOSTNAME;
elif [[ "$RELEASE" =~ ^10(\..*){0,1}$ ]]; then
    tar cf $OUTFILE $HOSTNAME;
    bzip2 -z $OUTFILE;
fi

echo "[+] Ok ! Fichier de sortie : $OUTFILE.bz2"
