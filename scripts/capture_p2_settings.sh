export XDG_DATA_HOME=/tmp/duel8-data XDG_CACHE_HOME=/tmp/duel8-cache XDG_CONFIG_HOME=/tmp/duel8-config
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
godot --path . --script tests/impact_movie_capture.gd -- --settings-stills=exports/qa-p2/final > exports/qa-p2/final/settings-native.log 2>&1
