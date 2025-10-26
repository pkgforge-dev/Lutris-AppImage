#!/usr/bin/env bash
set -e

# An example of lutris packaging in a RunImage container

export ARCH="$(uname -m)"
export DESKTOP=https://raw.githubusercontent.com/lutris/lutris/refs/heads/master/share/applications/net.lutris.Lutris.desktop
export ICON=https://github.com/lutris/lutris/blob/master/share/icons/hicolor/128x128/apps/net.lutris.Lutris.png?raw=true
export UPINFO="gh-releases-zsync|${GITHUB_REPOSITORY%/*}|${GITHUB_REPOSITORY#*/}|latest|*-$ARCH.AppImage.zsync"
export RIM_ALLOW_ROOT=1
URUNTIME="https://raw.githubusercontent.com/pkgforge-dev/Anylinux-AppImages/refs/heads/main/useful-tools/uruntime2appimage.sh"


echo '== download base RunImage'
curl -o runimage -L "https://github.com/VHSgunzo/runimage/releases/download/continuous/runimage-$(uname -m)"
chmod +x runimage

run_install() {
	set -e

	EXTRA_PACKAGES="https://raw.githubusercontent.com/pkgforge-dev/Anylinux-AppImages/refs/heads/main/useful-tools/get-debloated-pkgs.sh"
	INSTALL_PKGS=(
		lutris egl-wayland vulkan-radeon lib32-vulkan-radeon vulkan-tools
		vulkan-intel lib32-vulkan-intel vulkan-nouveau lib32-vulkan-nouveau
		lib32-libpipewire libpipewire pipewire lib32-libpipewire libpulse
		lib32-libpulse vkd3d lib32-vkd3d wget xdg-utils vulkan-mesa-layers
		lib32-vulkan-mesa-layers freetype2 lib32-freetype2 fuse2 mangohud
		lib32-mangohud gamescope gamemode lib32-gamemode wine lib32-libglvnd
		lib32-gnutls xterm python-protobuf xdg-desktop-portal-gtk pipewire-pulse
		zenity-gtk3 libtheora glew glfw
	)

	rim-update
	pac --needed --noconfirm -S "${INSTALL_PKGS[@]}"
	yes|pac -S glibc-eac lib32-glibc-eac

	wget --retry-connrefused --tries=30 "$EXTRA_PACKAGES" -O ./get-debloated-pkgs.sh
	chmod +x ./get-debloated-pkgs.sh
	./get-debloated-pkgs.sh --add-mesa gtk3-mini opus-mini libxml2-mini gdk-pixbuf2-mini librsvg-mini
	
	# remove llvm-libs but don't force it just in case something else depends on it
	pac -Rsn --noconfirm llvm-libs || true
	# same for glycin
	pac -Rsn --noconfirm glycin || true

	echo '== shrink (optionally)'
	pac -Rsndd --noconfirm wget gocryptfs jq gnupg
	rim-shrink --all
	pac -Rsndd --noconfirm binutils

	pac -Qi | awk -F': ' '/Name/ {name=$2}
		/Installed Size/ {size=$2}
		name && size {print name, size; name=size=""}' \
			| column -t | grep MiB | sort -nk 2

	VERSION=$(pacman -Q lutris | awk 'NR==1 {print $2; exit}')
	echo "$VERSION" > ~/version

	echo '== create RunImage config for app (optionally)'
	cat <<- 'EOF' > "$RUNDIR/config/Run.rcfg"
	RIM_CMPRS_LVL="${RIM_CMPRS_LVL:=22}"
	RIM_CMPRS_BSIZE="${RIM_CMPRS_BSIZE:=25}"

	RIM_SYS_NVLIBS="${RIM_SYS_NVLIBS:=1}"

	RIM_NVIDIA_DRIVERS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/runimage_nvidia"
	RIM_SHARE_ICONS="${RIM_SHARE_ICONS:=1}"
	RIM_SHARE_FONTS="${RIM_SHARE_FONTS:=1}"
	RIM_SHARE_THEMES="${RIM_SHARE_THEMES:=1}"
	RIM_HOST_XDG_OPEN="${RIM_HOST_XDG_OPEN:=1}"
	RIM_BIND="/usr/share/locale:/usr/share/locale,/usr/lib/locale:/usr/lib/locale"
	RIM_AUTORUN=lutris
	EOF

	rim-build -s temp.RunImage
}
export -f run_install
RIM_OVERFS_MODE=1 RIM_NO_NVIDIA_CHECK=1 ./runimage bash -c run_install
./temp.RunImage --runtime-extract
rm -f ./temp.RunImage
mv ./RunDir ./AppDir
mv ./AppDir/Run ./AppDir/AppRun

# debloat
rm -rfv ./AppDir/sharun/bin/chisel \
	./AppDir/rootfs/usr/lib*/libgo.so* \
	./AppDir/rootfs/usr/lib*/libgphobos.so* \
	./AppDir/rootfs/usr/lib*/libgfortran.so* \
	./AppDir/rootfs/usr/bin/rav1e \
	./AppDir/rootfs/usr/*/*pacman* \
	./AppDir/rootfs/var/lib/pacman \
	./AppDir/rootfs/etc/pacman* \
	./AppDir/rootfs/usr/share/licenses \
	./AppDir/rootfs/usr/share/terminfo \
	./AppDir/rootfs/usr/lib/udev/hwdb.bin

# Make AppImage with uruntime
export VERSION="$(cat ~/version)"
export OUTNAME=Lutris+wine-"$VERSION"-anylinux-"$ARCH".AppImage
export OPTIMIZE_LAUNCH=1
wget --retry-connrefused --tries=30 "$URUNTIME" -O ./uruntime2appimage
chmod +x ./uruntime2appimage
./uruntime2appimage

# Fetch AppBundle creation tooling
wget -qO ./pelf "https://github.com/xplshn/pelf/releases/latest/download/pelf_$ARCH"
chmod +x ./pelf

echo "Generating [sqfs]AppBundle...(Go runtime)"
./pelf --add-appdir ./AppDir \
	--compression "--categorize=hotness --hotness-list=./AppDir/.dwarfsprofile -C zstd:level=22 -S26 -B6" \
	--appbundle-id="net.lutris.Lutris-$(date +%d_%m_%Y)-contrarybaton60" \
	--appimage-compat \
	--add-updinfo "$UPINFO" \
	--output-to "Lutris+wine-${VERSION}-anylinux-${ARCH}.dwfs.AppBundle"
zsyncmake ./*.AppBundle -u ./*.AppBundle

mkdir -p ./dist
mv -v ./*.AppImage*  ./dist
mv -v ./*.AppBundle* ./dist
mv -v ~/version      ./dist

echo "All Done!"
