#!/usr/bin/env bash
# Runs the assert-based checks for logic that has no SPM test target yet.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build
swiftc -O Sources/FuseOS/LoopGuard.swift Checks/main.swift -o .build/checks
.build/checks
