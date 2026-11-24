#!/bin/sh
set -eu

: "${RYOKU_SRC:?RYOKU_SRC is required}"
: "${RYOKU_BUILD_DIR:?RYOKU_BUILD_DIR is required}"

stage_prebuilt() {
	[ -n "${RYOKU_PREBUILT_DIR:-}" ] || return 1
	mkdir -p "$RYOKU_BUILD_DIR"
	cp -a "$RYOKU_PREBUILT_DIR/." "$RYOKU_BUILD_DIR/"
}

case "${1:-}" in
build)
	stage_prebuilt && exit 0
	mkdir -p "$RYOKU_BUILD_DIR"
	RYOKU_BLOBS_BUILD="$RYOKU_BUILD_DIR/build" \
		"$RYOKU_SRC/ryoku/shell/plugin/build.sh" "$RYOKU_BUILD_DIR/qml"
	;;
install)
	destdir=${2:?usage: payload.sh install DESTDIR systemd|runit}
	init=${3:?usage: payload.sh install DESTDIR systemd|runit}
	case "$init" in
	systemd|runit) ;;
	*) printf 'payload.sh: unsupported init system: %s\n' "$init" >&2; exit 2 ;;
	esac
	for module in Blobs Spatial3D; do
		install -dm755 "$destdir/usr/lib/qt6/qml/Ryoku/$module"
		cp -a "$RYOKU_BUILD_DIR/qml/Ryoku/$module/." "$destdir/usr/lib/qt6/qml/Ryoku/$module/"
	done
	# Debian Qt 6.8 compat: install RectangularShadow stub into QtQuick/Effects
	# (RectangularShadow was added in Qt 6.9; this stub uses MultiEffect as fallback)
	install -dm755 "$destdir/usr/lib/x86_64-linux-gnu/qt6/qml/QtQuick/Effects"
	cp "$RYOKU_SRC/debian/packages/stubs/QtQuick/Effects/RectangularShadow.qml" \
		"$destdir/usr/lib/x86_64-linux-gnu/qt6/qml/QtQuick/Effects/RectangularShadow.qml"
	chmod -R u=rwX,go=rX "$destdir/usr/lib/qt6" "$destdir/usr/lib/x86_64-linux-gnu/qt6/qml/QtQuick"
	;;
*)
	printf 'usage: payload.sh build | install DESTDIR systemd|runit\n' >&2
	exit 2
	;;
esac
