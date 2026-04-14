#!/bin/bash
#
# blitzbot — Whisper-Setup
# Installiert whisper.cpp via Homebrew und lädt Modell nach ~/.blitzbot/models/
# (Modell liegt außerhalb des Projekt-Ordners, damit Repo klein bleibt.)
#

set -euo pipefail

MODEL_DIR="$HOME/.blitzbot/models"
MODEL_NAME="ggml-large-v3-turbo.bin"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin"

echo "blitzbot — Whisper Setup"
echo "------------------------"

if ! command -v brew >/dev/null 2>&1; then
  echo "Fehler: Homebrew nicht gefunden. Installiere es von https://brew.sh"
  exit 1
fi

if ! command -v whisper-cli >/dev/null 2>&1; then
  echo "-> Installiere whisper-cpp via brew..."
  brew install whisper-cpp
else
  echo "-> whisper-cli bereits installiert: $(which whisper-cli)"
fi

mkdir -p "$MODEL_DIR"

if [ ! -f "$MODEL_DIR/$MODEL_NAME" ]; then
  echo "-> Lade Modell nach $MODEL_DIR/$MODEL_NAME (~1.5 GB)..."
  curl -L --progress-bar -o "$MODEL_DIR/$MODEL_NAME" "$MODEL_URL"
else
  echo "-> Modell bereits vorhanden: $MODEL_DIR/$MODEL_NAME"
fi

echo ""
echo "Fertig."
echo "  Modell:      $MODEL_DIR/$MODEL_NAME"
echo "  whisper-cli: $(which whisper-cli)"
