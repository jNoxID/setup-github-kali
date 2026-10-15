# GitHub Secure Setup — Kali Linux

Script Bash interactif pour configurer un accès SSH à GitHub depuis Kali Linux (ou une distribution Debian compatible), **sans token GitHub** et sans écraser les clés SSH existantes.

Fichier : [`setup-github-kali.sh`](setup-github-kali.sh)

## Fonctionnalités

- Vérifie la présence de Git et du client OpenSSH ; installe les paquets manquants avec `sudo apt-get`.
- Propose deux modes : **clé SSH de compte** ou **Deploy Key dédiée à un dépôt**.
- Crée une clé **ED25519** (ou conserve celle déjà présente), avec invitation à définir une passphrase.
- Vérifie l'empreinte de la clé hôte ED25519 de GitHub avant de l'enregistrer dans un fichier `known_hosts` dédié.
- Ajoute un alias dans `~/.ssh/config` sans remplacer les autres entrées.
- Affiche la clé publique et l'URL GitHub où l'enregistrer **manuellement**.
- Teste l'authentification et propose le clonage dans `~/projets-github/`.

## Prérequis

- Kali Linux / Debian avec `apt-get`, accès réseau à `github.com` (SSH, port 22).
- Compte GitHub et accès au dépôt concerné.
- Utilisateur Linux ordinaire, **sans lancer le script avec `sudo`** ; `sudo` peut être demandé pour installer des dépendances.
- Pour créer une Deploy Key : droits d'administration sur les paramètres du dépôt GitHub.

## Installation et exécution

Place les deux fichiers dans le même dossier, puis :

```bash
bash -n setup-github-kali.sh
chmod +x setup-github-kali.sh
./setup-github-kali.sh
```

`bash -n` vérifie uniquement la syntaxe : il ne garantit pas la sécurité du script. Lire le script avant de l'exécuter.

Tu peux aussi utiliser directement `bash setup-github-kali.sh` sans `chmod +x`.

## Choisir son mode

| Mode                        | Clé et alias SSH                                                      | Où ajouter la clé publique                                                         | Usage                                                |
| --------------------------- | --------------------------------------------------------------------- | ---------------------------------------------------------------------------------- | ---------------------------------------------------- |
| **1 — Compte**              | `~/.ssh/id_ed25519_github_kali` ; `github-kali`                       | [GitHub → SSH keys](https://github.com/settings/keys), type **Authentication Key** | Accès selon les droits de ton compte GitHub          |
| **2 — Deploy Key** (défaut) | `~/.ssh/id_ed25519_github-kali-OWNER-REPO` ; `github-kali-OWNER-REPO` | `https://github.com/OWNER/REPO/settings/keys`                                      | Accès à **un seul dépôt** ; lecture seule par défaut |

Le script demande `OWNER/REPO` en mode 2, par exemple `USER_ID/REPO_NAME` (sans URL complète). En mode 1, le dépôt à cloner est demandé plus tard et peut être omis.

**Sécurité :** laisse **Allow write access** désactivé pour une Deploy Key si tu n'as besoin que de `clone`, `fetch` et `pull`. Active-le seulement si des `push` sont nécessaires. Une clé de compte peut avoir un périmètre beaucoup plus large : évite de la conserver sur une VM utilisée pour des tests risqués si elle n'est pas indispensable.

## Procédure GitHub

1. Lance le script et choisis le mode `1` ou `2`.
2. Lors de la génération de la clé, choisis une **passphrase solide**.
3. Copie **uniquement** la clé publique affichée (fichier `.pub`).
4. Dans GitHub, ajoute-la comme **Authentication Key** pour le mode 1, ou dans les **Deploy keys** du dépôt pour le mode 2.
5. Reviens au terminal et appuie sur Entrée pour tester l'accès.
6. Accepte le clonage proposé si tu le souhaites.

Le script **ne peut pas ajouter automatiquement la clé à GitHub** : cette étape requiert ton autorisation dans l'interface GitHub.

## Exemples de tests et de clonage

### Mode 1 — Clé de compte

```bash
ssh -T git@github-kali
git clone git@github-kali:OWNER/REPO.git
```

### Mode 2 — Deploy Key dédiée

Exemple pour `USER_ID/REPO_NAME` :

```bash
ssh -T git@github-kali-USER_ID-REPO_NAME
git clone git@github-kali-USER_ID-REPO_NAME:USER_ID/REPO_NAME.git
```

**Important :** `github-kali` et `github-kali-OWNER-REPO` sont des alias distincts. Un alias inexistant produit `Could not resolve hostname` ; utiliser `github.com` directement peut sélectionner une autre clé.

GitHub affiche normalement `Hi ...! You've successfully authenticated, but GitHub does not provide shell access.` en cas de succès. La commande `ssh -T` peut néanmoins renvoyer le code de sortie `1` : ce n'est pas forcément un échec.

## Emplacement des fichiers

| Chemin                                     | Rôle                           |
| ------------------------------------------ | ------------------------------ |
| `~/.ssh/config`                            | Déclarations des alias SSH     |
| `~/.ssh/id_ed25519_github_kali`            | Clé privée du mode 1           |
| `~/.ssh/id_ed25519_github-kali-OWNER-REPO` | Clé privée du mode 2           |
| `~/.ssh/*.pub`                             | Clés publiques correspondantes |
| `~/.ssh/known_hosts_github_kali`           | Clé hôte GitHub vérifiée       |
| `~/projets-github/`                        | Répertoire de clonage proposé  |

Le script définit `700` sur `~/.ssh` et `~/projets-github`, `600` sur les clés privées et le fichier SSH config, et `644` sur les clés publiques.

## Dépannage

**`Permission denied (publickey)`**

- Vérifie que **la clé publique correspondant à l'alias utilisé** a été ajoutée au bon endroit sur GitHub.
- Vérifie l'alias et la clé sélectionnée :

```bash
cat ~/.ssh/config
ssh -G github-kali-USER_ID-REPO_NAME | grep -E '^(hostname|identityfile) '
ssh -vT git@github-kali-USER_ID-REPO_NAME
```

**`Could not resolve hostname github-kali`**

Tu as probablement choisi le mode 2. Utilise l'alias complet `github-kali-OWNER-REPO` indiqué par le script et présent dans `~/.ssh/config`.

**`Repository not found` ou accès refusé pendant `git clone`**

Vérifie l'orthographe de `OWNER/REPO`, que le dépôt existe, et que la clé utilisée a bien accès à **ce** dépôt. Une authentification SSH réussie ne garantit pas l'autorisation sur tous les dépôts.

**`git push` refusé**

Une Deploy Key est en lecture seule par défaut. Vérifie **Allow write access** et les éventuelles règles de protection des branches.

**Le script affiche un échec d'authentification mais poursuit**

Dans cette version, un échec au test SSH affiche un avertissement **sans interrompre le script** ; un clonage peut donc échouer ensuite. Corrige l'enregistrement de la clé, puis teste l'alias manuellement avant de cloner.

**Connexion SSH bloquée**

Le script nécessite l'accès au port SSH 22 de GitHub pour `ssh-keyscan` et les connexions. Il ne configure pas de solution de repli sur le port 443.

## Bonnes pratiques

- **Ne publie jamais une clé privée** et ne l'ajoute pas à un dépôt Git.
- Utilise une passphrase, des clés différentes par machine et par dépôt sensible, et révoque celles qui ne servent plus.
- Ne lance pas de scripts inconnus clonés depuis GitHub sans les examiner.
- Sur une VM Kali dédiée au pentest, privilégie les Deploy Keys en lecture seule.
- Sauvegarde ta configuration SSH avant de la modifier manuellement.

## Limites

Le script ne configure pas les permissions des branches, n'active pas la MFA de ton compte, ne gère pas les clés sur GitHub et ne synchronise pas automatiquement les dépôts. Une exécution répétée conserve les fichiers de clé existants et ne remplace pas une entrée SSH dont l'alias existe déjà : inspecte `~/.ssh/config` si tu as modifié la configuration entre-temps.

## 📜 Licence

Ce projet est distribué sous licence **GNU General Public License v3.0 (GPL-3.0-only)**.

Vous êtes libre d'utiliser, d'étudier, de modifier et de redistribuer ce logiciel, dans le respect des conditions de la licence GNU GPL v3.0.

Ce logiciel est fourni **sans aucune garantie**, dans les limites autorisées par la loi applicable.

Pour consulter les conditions complètes, reportez-vous au fichier [LICENSE](LICENSE) ou au [texte officiel de la GNU GPL v3.0](https://www.gnu.org/licenses/gpl-3.0.html).
