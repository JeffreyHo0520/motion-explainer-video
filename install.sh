#!/usr/bin/env bash
# One-click installer for Motion Explainer Video & Images Suite
# (motion-explainer-video, motion-explainer-images, motion-design, review-loop)
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/JeffreyHo0520/motion-explainer-video/main/install.sh | bash
set -euo pipefail

REPO_URL="https://github.com/JeffreyHo0520/motion-explainer-video.git"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"

IS_REMOTE=0
if [ -z "$SCRIPT_DIR" ] || [ ! -d "$SCRIPT_DIR/skills" ]; then
  IS_REMOTE=1
  TMP_DIR="$(mktemp -d)"
  echo ">>> [motion-explainer-video] Remote execution detected. Cloning repository..."
  git clone --depth 1 "$REPO_URL" "$TMP_DIR"
  SCRIPT_DIR="$TMP_DIR"
fi

cleanup() {
  if [ "$IS_REMOTE" -eq 1 ] && [ -d "${TMP_DIR:-}" ]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

echo "================================================================="
echo " 🎬 Installing Motion Explainer Suite (Video + Images)          "
echo "    - motion-explainer-video   (AI Video + Image + Voice Fix)   "
echo "    - motion-explainer-images  (Licensed Photos & Gen Images)   "
echo "    - motion-design            (Taste & Easing Hard Rules)       "
echo "    - review-loop              (Visual Contact Sheet Audit)     "
echo "================================================================="

TARGET_ROOTS=(
  "$HOME/.gemini/config/skills"
  "$HOME/.claude/skills"
  "$HOME/.codex/skills"
  "$HOME/.agents/skills"
)

SKILLS=(
  "motion-explainer-video"
  "motion-explainer-images"
  "motion-design"
  "review-loop"
)

for root in "${TARGET_ROOTS[@]}"; do
  mkdir -p "$root"
  echo ">>> Target Skills Root: $root"
  for skill in "${SKILLS[@]}"; do
    SRC="$SCRIPT_DIR/skills/$skill"
    DEST="$root/$skill"
    if [ ! -d "$SRC" ]; then
      echo "  [!] Source not found: $SRC"
      continue
    fi
    rm -rf "$DEST"
    cp -R "$SRC" "$DEST"
    find "$DEST" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
    echo "  [+] Installed $skill successfully!"
  done
done

echo ""
echo "-----------------------------------------------------------------"
echo "🔍 Checking environment prerequisites:"
echo "-----------------------------------------------------------------"
command -v node >/dev/null 2>&1 && echo "  [✓] Node.js: $(node --version)" || echo "  [!] Node.js 22+ not found."
command -v python3 >/dev/null 2>&1 && echo "  [✓] Python: $(python3 --version)" || echo "  [!] Python 3 not found."
command -v ffmpeg >/dev/null 2>&1 && echo "  [✓] ffmpeg is installed." || echo "  [!] ffmpeg not found."
command -v hyperframes >/dev/null 2>&1 && echo "  [✓] HyperFrames CLI is installed." || echo "  [!] HyperFrames not found (npm install -g hyperframes)."

echo ""
echo "✨ Installation complete! You can now use /motion-explainer-video or /motion-explainer-images in your AI agent."
