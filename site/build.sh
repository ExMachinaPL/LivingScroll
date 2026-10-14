#!/usr/bin/env bash
# Builds the project website (livingscroll.net) into a static directory that
# GitHub Pages serves as-is. Used by .github/workflows/pages.yml and for a
# local preview. Requires only pandoc.
#
# Usage:
#   site/build.sh [out-dir]          # build only (default out-dir: _site)
#   site/build.sh --serve [out-dir]  # build, then preview at http://localhost:8000
#                                    # (a plain file:// view can't resolve the
#                                    # clean /privacy/ URLs to index.html)
#
# The privacy policy is rendered from site/legal/privacy-policy.<lang>.md —
# the SAME files the app bundles as assets (pubspec.yaml), so the website and
# the app always show identical text. English lives at /privacy/, other
# languages at /<lang>/privacy/ (lib/widgets/privacy_policy_dialog.dart
# PrivacyPolicy.urlFor must match).
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

serve=false
if [[ ${1:-} == --serve ]]; then
  serve=true
  shift
fi
out_dir=${1:-_site}
template=site/templates/legal.html

rm -rf "$out_dir"
mkdir -p "$out_dir/assets"

# The download buttons link straight to the LATEST release's files. Their
# names carry the version (release.yml), so a fixed /releases/latest/download/
# URL can't work — resolve the latest release tag at build time instead
# (release.yml re-runs pages.yml after publishing, so the links follow every
# release). GH_TOKEN, when set (CI), only lifts the API rate limit. With no
# release reachable (offline preview) the buttons fall back to the releases page.
releases=https://github.com/ExMachinaPL/LivingScroll/releases
api_auth=()
if [[ -n ${GH_TOKEN:-} ]]; then
  api_auth=(-H "Authorization: Bearer $GH_TOKEN")
fi
tag=$(curl -fsSL "${api_auth[@]}" \
        https://api.github.com/repos/ExMachinaPL/LivingScroll/releases/latest \
      | sed -nE 's/^ *"tag_name": *"([^"]+)".*/\1/p') || tag=""
if [[ -n $tag ]]; then
  version=${tag#v}
  dl="$releases/download/$tag"
  windows_url="$dl/LivingScroll-$version-windows-x64-setup.exe"
  linux_url="$dl/LivingScroll-$version-x86_64.AppImage"
  android_url="$dl/LivingScroll-$version.apk"
  echo "Download links -> $tag"
else
  windows_url="$releases/latest"
  linux_url="$releases/latest"
  android_url="$releases/latest"
  echo "WARNING: latest release not found — download links point to $releases/latest" >&2
fi
sed -e "s#@DOWNLOAD_WINDOWS@#$windows_url#" \
    -e "s#@DOWNLOAD_LINUX@#$linux_url#" \
    -e "s#@DOWNLOAD_ANDROID@#$android_url#" \
    site/index.html > "$out_dir/index.html"

cp site/style.css "$out_dir/"
cp site/assets/* "$out_dir/assets/"
cp Assets/icon-hires.svg "$out_dir/assets/icon.svg"
# Serve files verbatim (no Jekyll processing on GitHub Pages).
touch "$out_dir/.nojekyll"

# render_policy <lang> <page-title> <dest-dir> <path-to-site-root>
#               <other-lang-label> <other-lang-path>
render_policy() {
  local lang=$1 title=$2 dest=$3 root=$4 other_label=$5 other_path=$6
  mkdir -p "$out_dir/$dest"
  pandoc "site/legal/privacy-policy.$lang.md" \
    --from gfm --to html5 --standalone \
    --template "$template" \
    --metadata lang="$lang" \
    --metadata pagetitle="$title" \
    --variable root="$root" \
    --variable other-lang-label="$other_label" \
    --variable other-lang-path="$other_path" \
    --output "$out_dir/$dest/index.html"
}

render_policy en "Privacy Policy — Living Scroll" privacy ../ \
  "Polski" ../pl/privacy/
render_policy pl "Polityka prywatności — Living Scroll" pl/privacy ../../ \
  "English" ../../privacy/

echo "Built site into $out_dir"

if $serve; then
  echo "Preview: http://localhost:8000/  (Ctrl+C to stop)"
  exec python3 -m http.server 8000 --directory "$out_dir"
fi
