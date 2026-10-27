#!/bin/sh
# The backend image's start (docs/deploy.md). The image's lessons replace the volume's, the datasets frozen on
# an earlier start are kept, the missing ones are frozen from their recipes (TWELVEDATA_API_KEY), and those no
# recipe lists any more are removed. Then the server starts. Lessons whose datasets could not be frozen wait
# for the next start; market data is served either way.
set -eu
live=/app/data/content
next=/app/data/content.next

rm -rf "$next"
cp -R /app/content "$next"
# Keep the frozen datasets of every pack version the image still has.
if [ -d "$live/packs" ]; then
  for datasets in "$live"/packs/*/*/datasets; do
    [ -d "$datasets" ] || continue
    version=${datasets%/datasets}
    version=${version#"$live"/}
    if [ -d "$next/$version" ]; then
      mv "$datasets" "$next/$version/datasets"
    fi
  done
fi
rm -rf "$live"
mv "$next" "$live"

freeze -recipes "$live" -prune || echo "motu: datasets are missing; their lessons wait for the next start" >&2
exec server
