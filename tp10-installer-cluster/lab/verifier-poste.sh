#!/usr/bin/env bash
# Avant « vagrant up » : ce poste peut-il porter le lab du TP10 ?
# Vagrant, le fournisseur (libvirt ou VirtualBox), les ressources libres, les
# réseaux du lab. Ne modifie rien. Lancez-le depuis le dossier du lab :
#   ./verifier-poste.sh
# Autonome (pas de scripts/lib.sh) : il doit marcher dans une copie du lab, hors du dépôt.
set -uo pipefail

CPU_MIN=4          # 2 (cp-1) + 1 + 1, voir le Vagrantfile
MEMOIRE_MIN_GO=7   # 3 + 1,5 + 1,5 Go pour les VM, plus de la marge pour le poste
DISQUE_MIN_GO=10   # la box, puis trois disques qui grossissent avec les paquets

if [ -t 1 ]; then
  GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; NC='\033[0m'
else
  GREEN=''; RED=''; YELLOW=''; BLUE=''; NC=''
fi
FAIL=0
step() { printf "${BLUE}▶ %s${NC}\n" "$*"; }
ok()   { printf "  ${GREEN}✓${NC} %s\n" "$*"; }
ko()   { printf "  ${RED}✗ %s${NC}\n" "$1"; [ -n "${2:-}" ] && printf "    → %s\n" "$2"; FAIL=$((FAIL+1)); }
warn() { printf "  ${YELLOW}⚠ %s${NC}\n" "$*"; }

WSL=0
grep -qi microsoft /proc/version 2>/dev/null && WSL=1

step "Vagrant"
if command -v vagrant >/dev/null; then
  ok "$(vagrant --version)"
else
  ko "vagrant introuvable" "https://developer.hashicorp.com/vagrant/install"
  exit 1
fi
if [ -f Vagrantfile ]; then
  ok "lancé depuis le dossier du lab"
else
  ko "pas de Vagrantfile ici" "lancez ce script depuis le dossier lab/ (ou sa copie)"
fi
if [ "$WSL" = 1 ]; then
  case "$PWD" in
    /mnt/*) ko "WSL : le lab est sous /mnt/… (disque Windows), Vagrant refusera d'y travailler" \
               "cp -r lab ~/tp10-lab && cd ~/tp10-lab (ou clonez le dépôt dans votre home Linux)" ;;
    *) ok "WSL : le lab est dans le système de fichiers Linux" ;;
  esac
fi

step "Fournisseur"
FOURNISSEUR="${VAGRANT_DEFAULT_PROVIDER:-}"
if [ -z "$FOURNISSEUR" ]; then
  if [ "$WSL" = 1 ]; then
    ko "VAGRANT_DEFAULT_PROVIDER n'est pas défini : sous WSL, Vagrant tente VirtualBox et s'arrête (« unable to use the VirtualBox provider from the Windows Subsystem for Linux »)" \
       "export VAGRANT_DEFAULT_PROVIDER=libvirt   (dans chaque nouveau terminal)"
    FOURNISSEUR=libvirt   # la suite vérifie libvirt, le seul possible sous WSL
  elif vagrant plugin list 2>/dev/null | grep -q '^vagrant-libvirt'; then
    FOURNISSEUR=libvirt   # le premier fournisseur du Vagrantfile qui est utilisable
  else
    FOURNISSEUR=virtualbox
  fi
fi
[ -n "${VAGRANT_DEFAULT_PROVIDER:-}" ] || [ "$WSL" = 0 ] && ok "fournisseur retenu : $FOURNISSEUR"

case "$FOURNISSEUR" in
  libvirt)
    if vagrant plugin list 2>/dev/null | grep -q '^vagrant-libvirt'; then
      ok "plugin $(vagrant plugin list | grep '^vagrant-libvirt')"
    else
      ko "plugin vagrant-libvirt absent" "vagrant plugin install vagrant-libvirt"
    fi
    if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
      ok "/dev/kvm accessible : virtualisation matérielle disponible"
    elif [ -e /dev/kvm ]; then
      ko "/dev/kvm existe mais vous n'y avez pas accès" "sudo usermod -aG kvm,libvirt \$USER, puis rouvrez la session (sous WSL : wsl --shutdown)"
    else
      ko "/dev/kvm absent : pas de virtualisation matérielle" "activez la virtualisation dans le BIOS ; sous WSL, la virtualisation imbriquée (nestedVirtualization=true dans .wslconfig)"
    fi
    if command -v virsh >/dev/null && virsh -c qemu:///system list >/dev/null 2>&1; then
      ok "libvirt répond (qemu:///system)"
    else
      ko "libvirt ne répond pas sur qemu:///system" "sudo systemctl enable --now libvirtd, et soyez dans le groupe libvirt (id -nG)"
    fi
    ;;
  virtualbox)
    if [ "$WSL" = 1 ]; then
      ko "VirtualBox depuis WSL n'est pas pris en charge par ce lab" "utilisez libvirt : export VAGRANT_DEFAULT_PROVIDER=libvirt"
    elif command -v VBoxManage >/dev/null; then
      ok "VirtualBox $(VBoxManage --version)"
    else
      ko "VirtualBox introuvable (VBoxManage)" "installez VirtualBox, ou le plugin vagrant-libvirt sous Linux"
    fi
    ;;
  *) ko "fournisseur « $FOURNISSEUR » : ce lab ne connaît que libvirt et virtualbox" ;;
esac

step "Ressources libres"
if vagrant status --machine-readable 2>/dev/null | grep -q ',state,running$'; then
  warn "des VM du lab tournent déjà : leurs ressources sont déjà prises, le contrôle est sauté (vagrant status)"
else
  cpus="$(nproc)"
  if [ "$cpus" -ge "$CPU_MIN" ]; then ok "$cpus processeurs (il en faut $CPU_MIN)"
  else ko "$cpus processeurs, il en faut $CPU_MIN" "les VM se partageraient trop peu de CPU : kubeadm exige 2 processeurs pour cp-1"; fi

  mem_ko="$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)"
  mem_go=$((mem_ko / 1024 / 1024))
  if [ "$mem_go" -ge "$MEMOIRE_MIN_GO" ]; then ok "$mem_go Go de mémoire disponibles (il en faut $MEMOIRE_MIN_GO)"
  else
    conseil="fermez des applications, ou arrêtez minikube (minikube stop)"
    [ "$WSL" = 1 ] && conseil="$conseil ; sous WSL, la mémoire se règle dans .wslconfig (memory=…)"
    ko "$mem_go Go de mémoire disponibles, il en faut $MEMOIRE_MIN_GO" "$conseil"
  fi

  stockage="$HOME"
  [ "$FOURNISSEUR" = libvirt ] && [ -d /var/lib/libvirt/images ] && stockage=/var/lib/libvirt/images
  libre_go="$(df -P -BG "$stockage" | awk 'NR==2{gsub("G","",$4); print $4}')"
  if [ "$libre_go" -ge "$DISQUE_MIN_GO" ]; then ok "$libre_go Go libres sur le disque des VM ($stockage)"
  else ko "$libre_go Go libres sur le disque des VM ($stockage), il en faut $DISQUE_MIN_GO"; fi
fi

step "Réseaux du lab (10.30.0.0/24 pour le cluster, 10.20.0.0/24 pour Vagrant)"
for reseau in 10.30.0 10.20.0; do
  dev="$(ip -4 route show 2>/dev/null | awk -v r="$reseau." 'index($1, r) == 1 {print $3; exit}')"
  case "$dev" in
    "")              ok "$reseau.0/24 libre" ;;
    virbr*|vboxnet*) ok "$reseau.0/24 déjà pris par un réseau de VM ($dev) : normal si le lab existe déjà" ;;
    *)               ko "$reseau.0/24 est déjà utilisé par $dev sur ce poste" "les VM ne seraient pas joignables : changez les adresses du Vagrantfile (et celles du TP)" ;;
  esac
done

step "Téléchargements"
if vagrant box list 2>/dev/null | grep -q "^almalinux/10 .*$FOURNISSEUR"; then
  ok "box almalinux/10 déjà téléchargée"
else
  warn "box almalinux/10 absente : « vagrant up » la téléchargera (environ 500 Mo)"
fi
for url in https://pkgs.k8s.io https://download.docker.com; do
  if curl -s -o /dev/null --max-time 10 "$url"; then ok "$url joignable"
  else ko "$url injoignable" "les nœuds y prendront leurs paquets : vérifiez l'accès Internet ou le proxy"; fi
done

echo
if [ "$FAIL" -eq 0 ]; then
  printf "${GREEN}Poste prêt : vagrant up${NC}\n"
else
  printf "${RED}%d point(s) à corriger avant vagrant up${NC}\n" "$FAIL"
  exit 1
fi
