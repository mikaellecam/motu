#!/usr/bin/env bash
# Rebuilds what git leaves out (ADR-007): the content packs' datasets from their recipes, the app's
# bundled packs, the stock logos, and the price history the asset screenshots render. Run it after cloning
# and after a content change.
#
#   scripts/fetch-data.sh              real data, from TWELVEDATA_API_KEY in backend/.env (about 17
#                                      provider credits and 22 logos the first time, a few minutes)
#   scripts/fetch-data.sh --synthetic  made-up prices, no key: CI and a first look, never a release
set -euo pipefail
cd "$(dirname "$0")/../backend"

if [ "${1:-}" = --synthetic ]; then
  go run ./cmd/freeze -recipes ../content -synthetic
  go run ./cmd/freeze -recipes ../app/screenshots/fixtures -synthetic
else
  if [ -f .env ]; then
    set -a
    . ./.env
    set +a
  fi
  go run ./cmd/freeze -recipes ../content
  go run ./cmd/freeze -recipes ../app/screenshots/fixtures
fi
go run ./cmd/contentcheck -bundle ../app/assets/packs -write ../content
# Last: the app shows initials without them. Like freeze, logos waits out the provider's per-minute limit.
if [ "${1:-}" != --synthetic ]; then
  go run ./cmd/logos
fi
