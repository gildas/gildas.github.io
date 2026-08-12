#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/apt"
workspace="$(mktemp -d)"
download_dir="$workspace/downloads"
trap 'rm -rf "$workspace"' EXIT

required_commands=(curl jq gpg reprepro dpkg-deb gh)
for command in "${required_commands[@]}"; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Missing required command: $command" >&2
    exit 1
  fi
done

echo "Building APT repository from releases" 
REPOSITORIES=(
  $(echo '{"name":"Logviewer","slug":"gildas/lv","package":"bunyan-logviewer"}' | jq -r --compact-output '. | @base64')
  $(echo '{"name":"Bitbucket CLI","slug":"gildas/bitbucket-cli","package":"bitbucket-cli"}' | jq -r --compact-output '. | @base64')
)

echo "Repositories to process: ${#REPOSITORIES[@]}"
ARCHITECTURES=(
  "amd64"
  "arm64"
)

mkdir -p "$workspace/repository/conf" "$download_dir"

cat >"$workspace/repository/conf/distributions" <<EOF
Origin: gildas
Label: gildas
Suite: stable
Codename: stable
Architectures: ${ARCHITECTURES[*]}
Components: main
Description: gildas APT repository
SignWith: $GPG_KEY_ID
EOF

touch "$workspace/repository/conf/options"

function get_field() {
	local object="$1"
	local field="$2"
	local decoded=$(echo "$object" | base64 --decode | jq -r "$field")
	printf "%s" "$decoded"
}

# In Github Actions, the GITHUB_TOKEN environment variable is automatically created
# and contains a token that can be used to authenticate on behalf of GitHub Actions.
# This token is scoped to the repository that contains the workflow file.

imported=0
for repository in ${REPOSITORIES[@]}; do
  repository_name=$(get_field $repository .name)
  echo "Processing repository: $repository_name"
  repository_slug=$(get_field $repository .slug)
  package_name=$(get_field "$repository" '.package')
  echo "  Package name: $package_name"
  echo "    Importing package URLs for $repository_name"
  gh api -H "Accept: application/vnd.github+json" "/repos/$repository_slug/releases/latest" | \
    jq -r '.assets[] | select(.name | endswith(".deb")) | .browser_download_url' | \
    while read -r url; do
      repository_path="$repo_root/pool/main/b/${package_name}/$(basename $url)"
      asset_path="$download_dir/$(basename $url)"
      if [[ -f $repository_path ]]; then
        echo "    Package is alredy up-to-date in the repository"
        cp "$repository_path" "$asset_path"
      else
        echo "    Downloading $url"
        curl -sSL "$url" -o "$asset_path"
      fi
      #reprepro --basedir "$workspace/repository" --gnupghome "$GNUPGHOME" includedeb stable "$asset_path"
      reprepro --basedir "$workspace/repository" includedeb stable "$asset_path"
      imported=$((imported + 1))
    done
done

if (( imported == 0 )); then
  echo "No package was newly imported"
  exit 0
fi

gpg --batch --yes --no-tty --pinentry-mode loopback --output "$workspace/repository/gildas-archive-keyring.gpg" --export "$GPG_KEY_ID"

rm -rf "$repo_root/dists" "$repo_root/pool"
cp -a "$workspace/repository/dists" "$repo_root/dists"
cp -a "$workspace/repository/pool" "$repo_root/pool"
cp "$workspace/repository/gildas-archive-keyring.gpg" "$repo_root/gildas-archive-keyring.gpg"
