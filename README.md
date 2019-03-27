# Script d'extraction de la configuration de système GNU/Linux et Solaris

Le fichier d’extraction de configuration de ce dépôt vient initialement du proje pyCAF. C’est un *framework* d'audit de sécurité de configuration. Il a vocation à accompagner l'auditeur en lui facilitant la manipulation des données pertinentes sur lesquelles il va pouvoir baser son expertise.

## Introduction

Ce projet contient quatre scripts :
* `extract_linux.sh`, permet de réaliser les extractions de configurations sur un système GNU/Linux, à exécuter avec les droits « root » par l’administrateur ;
* ` extract_solaris.sh`, permet de réaliser les extractions de configurations sur un système Solaris 10 et 11, à exécuter avec les droits « root » par l’administrateur ;
*  `make_ISO-8859-1`, permet de convertir l’encodage des scripts pour un affichage sur une plateforme limitée (pas d’UTF-8) ;
* `verify_extract.sh`, permet de valider rapidement que tous les fichiers attendus sont présents sur un ensemble d’archives issu du script d’extraction GNU/Linux.

Ces deux derniers scripts sont à exécuter éventuellement sur la machine de l’auditeur. Il est _**fortement recommandé**_ d’exécuter le script `verify_extract.sh` sur les archives avant de rentrer au bureau.

## Philosophie

L’objectif de ces scripts est d’être facilement compréhensible par un administrateur afin qu’il puisse s’assurer de son innocuité avant de l’utiliser. Le second objectif est d’être compatible avec le plus de système possible. C’est pourquoi nous nous sommes imposés une notation POSIX strict qui peut paraître un peu lourde au premier regard, mais qui a l’avantage d’être aussi bien exécuté sur des systèmes GNU/Linux actuels que d’autres qui ont plus de 10 ans (comme la Debian Woody par exemple).

Vous remarquerez en utilisant le script GNU/Linux que des messages qui peuvent sembler être des erreurs apparaissent lors de l’exécution de la commande `find`. Rien d’inquiétant, c’est un choix de conception. Les erreurs affichées sont simplement dues à la disparition du fichier entre le moment où le fichier est listé et le moment où on veut accéder à ses propriétés.

```
[+] liste des fichiers et des droits associés
find: ‘/run/user/1000/gvfs’: Permission non accordée
find: /proc/2/task/2/exe: Aucun fichier ou dossier de ce type
find: /proc/2/exe: Aucun fichier ou dossier de ce type
find: /proc/3/task/3/exe: Aucun fichier ou dossier de ce type
find: /proc/3/exe: Aucun fichier ou dossier de ce type
find: /proc/5/task/5/exe: Aucun fichier ou dossier de ce type
find: /proc/5/exe: Aucun fichier ou dossier de ce type
find: /proc/7/task/7/exe: Aucun fichier ou dossier de ce type
find: /proc/7/exe: Aucun fichier ou dossier de ce type
find: /proc/8/task/8/exe: Aucun fichier ou dossier de ce type
find: /proc/8/exe: Aucun fichier ou dossier de ce type
find: /proc/9/task/9/exe: Aucun fichier ou dossier de ce type
find: /proc/9/exe: Aucun fichier ou dossier de ce type
find: /proc/10/task/10/exe: Aucun fichier ou dossier de ce type
find: /proc/10/exe: Aucun fichier ou dossier de ce type
find: /proc/11/task/11/exe: Aucun fichier ou dossier de ce type
[…]
```
Pourquoi lister /proc ? Parce tous les systèmes ne sont pas standard, loin de là. En audit, on peut être confronté à la présence de périphérique spéciaux ou de fichiers malveillant dissimulés dans cet endroit.

## En cas de problème…

Si vous rencontrez un problème en audit avec l’un des deux scripts d’extraction, merci de récupérer le maximum d’information directement chez le client. Ces informations sont souvent rapides à récupérer et sont essentielles pour faire évoluer nos outils dans le bon sens.

À votre retour sur place, ouvrez une note de bug sur la page « Issues » du projet. Décrivez le problème et joignez-y les données techniques.

### Information d’exécution sur le script GNU/Linux

Il est généralement possible réaliser une trace d’exécution du script. Cette trace ne contient pas d’informations sensible sur le système cible, si ce n’est son nom d’hôte. Elle permet de connaître tous les détails liés à l’exécution du script et nous sera donc très utile pour analyser un dysfonctionnement. Voici comment la générer (très simple) :

Éditer le script pour décommenter la seconde ligne afin que la première commande exécutée soit `set -x`.  Avec l’utilisateur « root » :
```
mkfifo fifo;
bash extract_linux.sh > fifo 2>&1;
```
Dans une autre console :
```
cat fifo >> my_out;
```

Ou avec une seule console :
```
mkfifo fifo; (bash extract_linux.sh > fifo 2>&1)&
cat fifo >> my_out; rm fifo;
```

Attendre la fin de l’exécution du script et ramener le fichier *my_out*.

### Échappement des répertoires réseaux partagés volumineux

Avant d’exécuter un script sur le système d’un client, _**il est important de s’entretenir avec les administrateurs**_. Cet entretien permettra de démystifier le script et d’identifier les contraintes de production. Il est nécessaire de déterminer si des répertoires réseaux volumineux sont montés. Comme le script liste les droits sur tout les répertoires depuis le rootfs, il est possible que la machine soit surchargée, voir que le répertoire temporaire soit remplis si des répertoires réseaux volumineux sont montés.
La commande `mount` permet d’identifier les points de montages sur la machine, que ce soit avec un système GNU/Linux ou Solaris. L’auditeur doit ensuite modifier **MANUELLEMENT** le script.

La ligne suivante doit être commentée dans le script GNU/Linux :
```
find / -ls ${lsZ} > "${OUTDIR}"/find.txt
```

La ligne suivante (juste au dessus) doit être dé-commentée et adaptée. Ici, les répertoires « directoryA » et « DirectoryB » sont ignorés :
```
find / -type d \( -wholename "/directoryA" -o -wholename "/DirectoryB" \) -prune -o -ls ${lsZ} > "${OUTDIR}"/find.txt
```

Le script Solaris contient des directives similaires. La même manipulation permet d’échapper les répertoires réseaux volumineux.

→ _Pourquoi le script n’échape pas automatiquement les répertoires réseaux montés ?_

Nous avions fait initialement le choix d’un script simple et linéaire. Mais nous nous sommes également aperçu que cela dépend du contexte client. Dans la majorité des cas, le script sera utilisé tel quel.

## Méthode de travail pour la modification du code

Deux branches sont disponibles : 
* _**master**_, code stable et éprouvé ;
* _**unstable**_, code réscement modifié qui n’as pas encore été suffisamment testé pour être directement utilisé sur la machine d’un client.

Le code doit être éprouvé sur des machines récentes et ancienne et sur des architectures différentes avant d’être poussé sur la branche « master ». Une trace d’exécution doit être réalisé pour chaque architecture testée. Cette trace permet de valider le fonctionnement et d’identifier des anomalies par `diff` entre un fonctionnement anormal chez un client et la trace du fonctionnement nominal.

Actuellement, le code est joint à la branche master après les tests suivants :
1. analyse de la trace d’exécution sur une machine Fedora 22, ARM, SELinux activé, `ss`, `ip`, `xz` ;
2. analyse de la trace d’exécution sur une machine Debian 3.0r6, x86, `ifconfig`, `netstat`, `gzip` ;
3. analyse de la trace d’exécution sur une machine ArchLinux avec un noyau 4.9.11-1, x86_64, iptables, lxc (présent mais non configuré), `ss`, `ip`, `ifconfig`, `netstat`, `xz` ;
4. validation des extractions sur les trois machines ;
5. analyse qualité du code produit avec l’outil `shellcheck`.

## Licence
Ce code est publié sous licence GPLv3.
