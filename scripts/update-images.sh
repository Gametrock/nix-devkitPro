if [[ ${1-} == --help ]]; then
  echo 'Usage: nix run .#update-images -- [devkitarm|devkitppc|devkita64|all] [image-tag]'
  exit 0
fi

selection=${1:-all}
tag=${2:-latest}
if [[ $# -gt 2 || ! "$tag" =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.-]{0,127}$ ]]; then
  echo 'Invalid image tag or too many arguments; use --help' >&2
  exit 2
fi

case "$selection" in
  all)
    images=(devkitarm devkitppc devkita64)
    ;;
  devkitarm|devkitppc|devkita64)
    images=("$selection")
    ;;
  *)
    echo "Unknown image: $selection" >&2
    exit 2
    ;;
esac

if [[ ! -f flake.nix || ! -d nix/images ]]; then
  echo 'Run this command from the devkitpro repository root.' >&2
  exit 2
fi

# Use a temporary workspace
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
export TMPDIR="$staging"

# Keep registry settings isolated; use REGISTRY_AUTH_FILE if set.
export HOME="$staging/home"
mkdir -p "$HOME/.config/containers"
printf 'unqualified-search-registries = ["docker.io"]\n' \
  > "$HOME/.config/containers/registries.conf"

common=(
  --insecure-policy
  --tmpdir "$TMPDIR"
  --override-os linux
  --override-arch amd64
)

for image in "${images[@]}"; do
  name="devkitpro/$image"
  digest=$(skopeo "${common[@]}" inspect "docker://docker.io/$name:$tag" | jq -er '.Digest')
  archive="$staging/docker-image-devkitpro-$image-$tag.tar"

  skopeo "${common[@]}" copy \
    "docker://docker.io/$name@$digest" \
    "docker-archive:$archive:$name:$tag"
  hash=$(nix hash file --type sha256 --sri "$archive")
  nix-store --add-fixed sha256 "$archive" > /dev/null

  jq -n \
    --arg name "$name" \
    --arg digest "$digest" \
    --arg hash "$hash" \
    --arg tag "$tag" \
    '{imageName: $name, imageDigest: $digest, hash: $hash, finalImageName: $name, finalImageTag: $tag}' \
    > "$staging/$image.json"
done

# Don't replace any pins unless every requested prefetch succeeded.
for image in "${images[@]}"; do
  cp "$staging/$image.json" "nix/images/$image.json"
done

echo 'Image pins updated. Make sure to review the diff and run nix flake check before committing.'
