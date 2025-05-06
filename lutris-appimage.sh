#!/usr/bin/env bash
set -e

# An example of lutris packaging in a RunImage container

if [ ! -x 'runimage' ]; then
	echo '== download base RunImage'
	curl -o runimage -L "https://github.com/VHSgunzo/runimage/releases/download/continuous/runimage-$(uname -m)"
	chmod +x runimage
fi

run_install() {
	set -e

	INSTALL_PKGS=(
		lutris egl-wayland vulkan-radeon lib32-vulkan-radeon vulkan-tools
		vulkan-intel lib32-vulkan-intel vulkan-nouveau lib32-vulkan-nouveau
		lib32-libpipewire libpipewire pipewire lib32-libpipewire libpulse
		lib32-libpulse vkd3d lib32-vkd3d wget xdg-utils vulkan-mesa-layers
		lib32-vulkan-mesa-layers freetype2 lib32-freetype2 fuse2 mangohud
		lib32-mangohud gamescope gamemode lib32-gamemode wine lib32-libglvnd
		lib32-gnutls xterm python-protobuf xdg-desktop-portal-gtk pipewire-pulse zenity-gtk3
	)

	echo '== checking for updates'
	rim-update

	echo '== install packages'
	pac --needed --noconfirm -S "${INSTALL_PKGS[@]}"

	echo '== install glibc with patches for Easy Anti-Cheat (optionally)'
	yes|pac -S glibc-eac lib32-glibc-eac

	echo '== install debloated llvm for space saving (optionally)'
	LLVM="https://github.com/pkgforge-dev/llvm-libs-debloated/releases/download/continuous/llvm-libs-mini-x86_64.pkg.tar.zst"
	wget --retry-connrefused --tries=30 "$LLVM" -O ./llvm-libs.pkg.tar.zst
	pac -U --noconfirm ./llvm-libs.pkg.tar.zst
	rm -f ./llvm-libs.pkg.tar.zst

	echo '== shrink (optionally)'
	pac -Rsndd --noconfirm wget gocryptfs jq gnupg
	rim-shrink --all
	pac -Rsndd --noconfirm binutils svt-av1

	pac -Qi | awk -F': ' '/Name/ {name=$2}
		/Installed Size/ {size=$2}
		name && size {print name, size; name=size=""}' \
			| column -t | grep MiB | sort -nk 2

	VERSION=$(pacman -Q lutris | awk 'NR==1 {print $2; exit}')
	echo "$VERSION" > ~/version
	cp /usr/share/icons/hicolor/scalable/apps/net.lutris.Lutris.svg ~/
	cp /usr/share/applications/net.lutris.Lutris.desktop ~/

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

	echo '== Build new DwarFS runimage with zstd 22 lvl and 24 block size'
	rim-build -s lutris.RunImage
}
export -f run_install

##########################

# enable OverlayFS mode, disable Nvidia driver check and run install steps
RIM_OVERFS_MODE=1 RIM_NO_NVIDIA_CHECK=1 ./runimage bash -c run_install
./lutris.RunImage --runtime-extract
rm -f ./lutris.RunImage

mv ./RunDir ./AppDir
mv ./AppDir/Run ./AppDir/AppRun

mv ~/net.lutris.Lutris.desktop  ./AppDir
mv ~/net.lutris.Lutris.svg      ./AppDir
ln -s net.lutris.Lutris.svg     ./AppDir/.DirIcon

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
VERSION="$(cat ~/version)"
export ARCH="$(uname -m)"
UPINFO="gh-releases-zsync|$(echo "$GITHUB_REPOSITORY" | tr '/' '|')|latest|*-$ARCH.AppImage.zsync"
URUNTIME="https://github.com/VHSgunzo/uruntime/releases/latest/download/uruntime-appimage-dwarfs-$ARCH"

wget --retry-connrefused --tries=30 "$URUNTIME" -O ./uruntime
chmod +x ./uruntime

# Add udpate info to runtime
echo "Adding update information \"$UPINFO\" to runtime..."
./uruntime --appimage-addupdinfo "$UPINFO"

echo "Generating AppImage..."
./uruntime --appimage-mkdwarfs -f \
	--set-owner 0 --set-group 0 \
	--no-history --no-create-timestamp \
	--categorize=hotness --hotness-list=lutris.dwfsprof \
	--compression zstd:level=22 -S26 -B32 \
	--header uruntime \
	-i ./AppDir -o Lutris+wine-"$VERSION"-anylinux-"$ARCH".AppImage

zsyncmake *.AppImage -u *.AppImage
echo "All Done!"
