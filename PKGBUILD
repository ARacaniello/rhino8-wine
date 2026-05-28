# Maintainer: your name here
# Wine patched for Rhino 8 on Linux.
# Installs to /opt/wine-rhino8 — does NOT conflict with system wine.
#
# Patches applied:
#   1. ntdll: force 512 MB thread stacks + clamp StackLimit to 1 MB for .NET 8 CLR
#   2. ntdll: move guard page to +64 KB on large stacks so overflow frames can be delivered
#   3. wintrust: override Authenticode result to S_OK (Wine lacks MS CA store)

pkgname=wine-rhino8
pkgver=11.9
_commit=11c0254541e169e80495f4f48f7231af36ff8a0c
pkgrel=1
pkgdesc="Wine patched for Rhino 8 .NET 8 compatibility — installs to /opt/wine-rhino8"
url="https://www.winehq.org"
arch=(x86_64)
license=(LGPL)

depends=(
  fontconfig
  freetype2
  gcc-libs
  gettext
  gnutls
  gst-plugins-base-libs
  libcups
  libpcap
  libpulse
  libxcomposite
  libxcursor
  libxdamage
  libxext
  libxfixes
  libxi
  libxinerama
  libxrandr
  libxrender
  libxxf86vm
  mesa
  opencl-icd-loader
  openssl
  pcsclite
  sdl2
  unixodbc
  v4l-utils
  vulkan-icd-loader
  wayland
)

makedepends=(
  autoconf
  bison
  flex
  mingw-w64-gcc
  perl
  python
  vulkan-headers
  lib32-glibc
  lib32-gcc-libs
)

optdepends=(
  'alsa-lib: ALSA audio support'
  'lib32-mesa: 32-bit OpenGL'
  'wine: system Wine for other applications (installs independently)'
)

source=(
  "wine-src::git+https://github.com/wine-mirror/wine.git#commit=${_commit}"
  "rhino8-wine.patch"
)

sha256sums=(
  SKIP
  SKIP
)

prepare() {
  cd wine-src
  patch -Np1 -i "${srcdir}/rhino8-wine.patch"
}

build() {
  mkdir -p build
  cd build

  "../wine-src/configure" \
    --prefix=/opt/wine-rhino8 \
    --enable-archs=i386,x86_64 \
    --with-x \
    --with-wayland \
    --with-vulkan \
    --with-openssl

  make -j$(nproc)
}

package() {
  cd build
  make DESTDIR="${pkgdir}" install
}
