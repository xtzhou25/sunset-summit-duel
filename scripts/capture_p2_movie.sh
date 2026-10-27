export XDG_DATA_HOME=/tmp/duel8-data XDG_CACHE_HOME=/tmp/duel8-cache XDG_CONFIG_HOME=/tmp/duel8-config
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
godot --path . --script tests/impact_movie_capture.gd --write-movie exports/qa-p2/impact-native.avi --fixed-fps 60 --disable-vsync -- --telemetry=res://exports/qa-p2/final/impact-native-telemetry.json > /tmp/p2-native-movie.log 2>&1
