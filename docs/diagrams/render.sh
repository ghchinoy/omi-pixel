#!/usr/bin/env bash
set -euo pipefail

# Render Graphviz .dot diagrams directly to .webp images
# Intermediate PNGs (if any) are written to /tmp and never committed to git.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v dot >/dev/null 2>&1; then
  echo "Error: 'dot' (Graphviz) is required to render diagrams."
  exit 1
fi

render_diagram() {
  local dot_file="$1"
  local base_name
  base_name="$(basename "${dot_file}" .dot)"
  local webp_out="${SCRIPT_DIR}/${base_name}.webp"

  echo "==> Rendering ${dot_file} to ${webp_out}..."

  # Try direct webp output from Graphviz
  if dot -Twebp "${dot_file}" -o "${webp_out}" 2>/dev/null; then
    echo "    Created ${webp_out} via native Graphviz webp generator."
  elif command -v cwebp >/dev/null 2>&1; then
    local tmp_png="/tmp/${base_name}_$$.png"
    dot -Tpng "${dot_file}" -o "${tmp_png}"
    cwebp -q 90 "${tmp_png}" -o "${webp_out}" >/dev/null 2>&1
    rm -f "${tmp_png}"
    echo "    Created ${webp_out} via cwebp conversion."
  else
    echo "Error: Neither Graphviz webp plugin nor cwebp found."
    exit 1
  fi
}

for f in "${SCRIPT_DIR}"/*.dot; do
  if [[ -f "$f" ]]; then
    render_diagram "$f"
  fi
done

echo "==> All diagrams successfully rendered to WebP!"
