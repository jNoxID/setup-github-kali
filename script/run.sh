#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# Configuration SSH GitHub sur Kali, sans stocker de token GitHub.
# Usage : bash setup-github-kali.sh

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; RESET='\033[0m'
info() { printf '%b\n' "${BLUE}[INFO]${RESET} $*"; }
ok()   { printf '%b\n' "${GREEN}[OK]${RESET} $*"; }
fail() { printf '%b\n' "${RED}[ERREUR]${RESET} $*" >&2; exit 1; }

[[ ${EUID} -ne 0 ]] || fail 'Lance ce script avec ton utilisateur Kali habituel, sans sudo.'
[[ -n ${HOME:-} && -d $HOME ]] || fail 'Répertoire HOME introuvable.'
command -v apt-get >/dev/null || fail 'Ce script nécessite Debian/Kali (apt-get).'

info 'Vérification des dépendances (git et client OpenSSH)…'
missing=()
command -v git >/dev/null || missing+=(git)
for cmd in ssh ssh-keygen ssh-keyscan; do
  if ! command -v "$cmd" >/dev/null; then missing+=(openssh-client); break; fi
done
if (( ${#missing[@]} )); then
  info "Installation : ${missing[*]}"
  if command -v sudo >/dev/null; then
    sudo apt-get update
    sudo apt-get install -y "${missing[@]}"
  else
    fail 'sudo indisponible. Installe git et openssh-client en administrateur, puis relance.'
  fi
fi

printf '\nMode d’accès GitHub :\n  1) Clé de compte (accès selon les droits du compte, pull et push)\n  2) Deploy key (un seul dépôt, lecture seule par défaut)\n'
read -r -p 'Choix [1/2, défaut 2] : ' mode
mode=${mode:-2}
[[ $mode == 1 || $mode == 2 ]] || fail 'Choix invalide.'

owner=''; repo=''
if [[ $mode == 2 ]]; then
  read -r -p 'Dépôt GitHub (OWNER/REPO) : ' repo_path
  [[ $repo_path =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || fail 'Format attendu : OWNER/REPO'
  owner=${repo_path%/*}; repo=${repo_path#*/}; repo=${repo%.git}
fi

ssh_dir="$HOME/.ssh"
mkdir -p "$ssh_dir"
chmod 700 "$ssh_dir"
if [[ $mode == 1 ]]; then
  alias_name='github-kali'
  key="$ssh_dir/id_ed25519_github_kali"
else
  alias_name="github-kali-${owner}-${repo}"
  key="$ssh_dir/id_ed25519_${alias_name}"
fi
config="$ssh_dir/config"
hosts="$ssh_dir/known_hosts_github_kali"

if [[ -e $key && ! -f $key ]]; then fail 'Le chemin de la clé existe mais ne désigne pas un fichier.'; fi
if [[ ! -f $key ]]; then
  info 'Création d’une clé ED25519 dédiée. Choisis une passphrase solide (ne la laisse pas vide).'
  ssh-keygen -t ed25519 -a 100 -f "$key" -C "${alias_name}@kali"
else
  info "Clé existante conservée : $key"
fi
[[ -f ${key}.pub ]] || fail "Clé publique absente : ${key}.pub"
chmod 600 "$key"; chmod 644 "${key}.pub"

# Vérification explicite de l’empreinte ED25519 GitHub publiée sur docs.github.com.
# Ne jamais accepter aveuglément ssh-keyscan sans vérification.
expected='SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU'
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
info 'Récupération de la clé hôte ED25519 de github.com…'
ssh-keyscan -T 10 -t ed25519 github.com 2>/dev/null | awk '$1 == "github.com" && $2 == "ssh-ed25519" {print}' > "$tmp"
[[ -s $tmp ]] || fail 'Impossible de récupérer la clé hôte GitHub (port 22 bloqué ou réseau indisponible).'
actual=$(ssh-keygen -lf "$tmp" -E sha256 | awk 'NR==1 {print $2}')
[[ $actual == "$expected" ]] || fail "Empreinte hôte non conforme ! Reçue : $actual / attendue : $expected. Arrêt de sécurité."
ok 'Empreinte officielle GitHub vérifiée.'
# Fichier dédié : ne modifie pas le known_hosts existant.
if [[ -f $hosts ]]; then
  if ! ssh-keygen -F github.com -f "$hosts" >/dev/null 2>&1; then cat "$tmp" >> "$hosts"; fi
else
  install -m 600 "$tmp" "$hosts"
fi
chmod 600 "$hosts"

# L’alias évite d’affecter les autres connexions SSH à github.com.
touch "$config"; chmod 600 "$config"
if grep -Eq "^[[:space:]]*Host[[:space:]]+${alias_name}([[:space:]]|$)" "$config"; then
  info "L’alias '$alias_name' existe déjà : vérifie sa configuration dans $config."
else
  cat >> "$config" <<CONFIG

# Clé GitHub dédiée créée par setup-github-kali.sh
Host $alias_name
    HostName github.com
    User git
    IdentityFile $key
    IdentitiesOnly yes
    StrictHostKeyChecking yes
    UserKnownHostsFile $hosts
    HostKeyAlgorithms ssh-ed25519
    AddKeysToAgent yes
CONFIG
  ok "Alias SSH '$alias_name' ajouté dans $config"
fi

printf '\n================ CLÉ PUBLIQUE ================\n'
cat "${key}.pub"
printf '=============================================\n\n'
if [[ $mode == 1 ]]; then
  printf 'ACTION MANUELLE : ajoute la clé publique dans :\nhttps://github.com/settings/ssh/new\n(Authentification / Authentication key)\n'
else
  printf 'ACTION MANUELLE : ajoute la clé publique dans :\nhttps://github.com/%s/%s/settings/keys\nDécoche « Allow write access » pour rester en lecture seule.\n' "$owner" "$repo"
fi
printf '\nLa clé privée reste sur Kali : %s\n' "$key"
read -r -p 'Une fois la clé ajoutée sur GitHub, appuie sur Entrée pour tester (ou Ctrl+C pour quitter)… ' _

info 'Test de connexion SSH (GitHub retourne normalement un code 1 même en cas de succès).'
set +e
output=$(ssh -o BatchMode=no -o ConnectTimeout=12 -T "git@${alias_name}" 2>&1)
status=$?
set -e
printf '%s\n' "$output"
if [[ $output == *'successfully authenticated'* ]]; then
  ok 'Authentification GitHub validée.'
else
  info "Authentification non confirmée (code $status). Ajoute la clé et réessaie : ssh -T git@${alias_name}"
fi

if [[ $mode == 1 ]]; then
  read -r -p 'Dépôt à cloner (OWNER/REPO, vide pour ignorer) : ' repo_path
  if [[ -n $repo_path ]]; then
    [[ $repo_path =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(\.git)?$ ]] || fail 'Format attendu : OWNER/REPO'
    owner=${repo_path%/*}; repo=${repo_path#*/}; repo=${repo%.git}
  fi
else
  read -r -p "Cloner $owner/$repo maintenant ? [o/N] : " clone_choice
  [[ $clone_choice =~ ^[oOyY]$ ]] || repo=''
fi

if [[ -n $repo ]]; then
  destination="$HOME/projets-github"
  mkdir -p "$destination"
  chmod 700 "$destination"
  if [[ -e "$destination/$repo" ]]; then
    info "Dossier déjà présent : $destination/$repo. Aucun écrasement."
  else
    git -C "$destination" clone "git@${alias_name}:${owner}/${repo}.git"
    ok "Dépôt cloné dans $destination/$repo"
  fi
fi

printf '\nTerminé. Alias SSH : %s\nTest : ssh -T git@%s\n' "$alias_name" "$alias_name"
printf 'Note : ne lance pas de scripts inconnus depuis un dépôt sans les examiner.\n'
