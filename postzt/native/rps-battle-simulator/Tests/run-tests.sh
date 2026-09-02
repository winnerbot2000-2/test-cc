#!/bin/bash
# Runs the RPSBattleSimulator automated test suite.
# Compiles the core (non-UI) sources plus the test runner, then executes it.
set -euo pipefail

cd "$(dirname "$0")/.."
SRC="RPSBattleSimulator/RPSBattleSimulator"
OUT=".build/tests/RPSBattleTests"

mkdir -p .build/tests

echo "Compiling test suite..."
swiftc -O -o "$OUT" \
  "$SRC/SimulationTypes.swift" \
  "$SRC/SeededRNG.swift" \
  "$SRC/SimulationSettings.swift" \
  "$SRC/SimulationEngine.swift" \
  "$SRC/ThemeManager.swift" \
  "$SRC/VideoFrameRenderer.swift" \
  "$SRC/VideoExporter.swift" \
  "$SRC/AudioGenerator.swift" \
  "$SRC/BatchExporter.swift" \
  "$SRC/BattlePreset.swift" \
  "$SRC/SocialPlatform.swift" \
  "$SRC/KeychainStore.swift" \
  "$SRC/SocialAuthManager.swift" \
  "$SRC/SocialUploader.swift" \
  Tests/TestSuite/main.swift

echo "Running tests..."
"$OUT"
