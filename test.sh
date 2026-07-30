#!/bin/bash
# Self-checks for the parsing and geometry logic (no UI needed).
set -euo pipefail
cd "$(dirname "$0")"

OUT="$(mktemp -d)/selftest"
swiftc -o "$OUT" Sources/Hurakai/Data.swift Tests/main.swift
"$OUT"
