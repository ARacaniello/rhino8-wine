# rhino8-wine

Patches and instructions to run **Rhinoceros 8** on Linux under Wine 11.9.

Tested on **Ubuntu 24.04.4 LTS (Noble Numbat)**, kernel 6.17, with Rhino **8.31.26126.13431**.

Rhino 8 uses .NET 8 via Microsoft's CLR, which has requirements that Wine doesn't meet out of the box. Six distinct problems had to be solved to get it working:

1. **.NET 8 requires ~512MB of reserved stack space** — Wine defaults to 1MB. Patched `ntdll` to force 512MB stacks on all threads.
2. **.NET calibrates recursion depth from `VirtualQuery`** — with a 512MB stack it would try to use all of it and overflow. Patched `ntdll` to clamp the reported stack size to 1MB so .NET calibrates correctly.
3. **Stack overflow exception frames couldn't be delivered** — with large stacks the guard page was too close to the stack bottom to fit an exception frame. Moved the guard page to +64KB.
4. **Dark mode detection caused 254,955-deep mutual recursion** — `rhcommon_c.dll`'s `RHC_RhOSInDarkMode` and the managed `get_DarkMode()` called each other indefinitely on Wine. Fixed with a binary patch to make it always return light mode.
5. **Wine can't verify Microsoft Authenticode signatures** — missing CA root store causes installer verification to fail. Patched `wintrust` to return success while still populating certificate state.
6. **OAuth licensing callback (port 1717) never bound** — stale `http.sys` state from a previous run blocked the port. Fixed by killing the wineserver before launch.

See [WINE_PORTING_NOTES.md](WINE_PORTING_NOTES.md) for a detailed writeup of each problem.

---

## Setup

### Ubuntu 24.04 LTS

#### 1. Install build dependencies

```bash
sudo apt update
sudo apt install -y \
  build-essential git autoconf bison flex python3 pkg-config \
  gcc-mingw-w64 \
  libx11-dev libxext-dev libxrandr-dev libxcomposite-dev libxcursor-dev \
  libxi-dev libxinerama-dev libxrender-dev libxxf86vm-dev \
  libxfixes-dev libxdamage-dev \
  libfreetype-dev libfontconfig-dev \
  libgnutls28-dev \
  libgl-dev \
  libvulkan-dev vulkan-headers \
  libwayland-dev \
  libpulse-dev \
  libcups2-dev libpcap-dev libsdl2-dev libv4l-dev \
  ocl-icd-opencl-dev libpcsclite-dev unixodbc-dev \
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
  libssl-dev
```

#### 2. Build and install the patched Wine

Ubuntu doesn't have `makepkg` so build manually:

```bash
git clone https://github.com/ItHasLegs/rhino8-wine
cd rhino8-wine

# Clone Wine at the tested commit
git clone https://github.com/wine-mirror/wine.git wine-src
cd wine-src
git checkout 11c0254541e169e80495f4f48f7231af36ff8a0c
cd ..

# Apply the patch
cd wine-src
git apply ../rhino8-wine.patch
cd ..

# Configure and build
mkdir wine-build && cd wine-build
../wine-src/configure \
  --prefix=/opt/wine-rhino8 \
  --enable-archs=i386,x86_64 \
  --with-x \
  --with-wayland \
  --with-vulkan \
  --with-openssl
make -j$(nproc)
sudo make install
```

---

### Arch Linux (untested)

#### 1. Install build dependencies

```bash
sudo pacman -S --needed \
  base-devel git \
  mingw-w64-gcc \
  autoconf bison flex perl python \
  lib32-glibc lib32-gcc-libs \
  vulkan-headers \
  fontconfig freetype2 gnutls libxcomposite libxcursor libxdamage \
  libxext libxfixes libxi libxinerama libxrandr libxrender libxxf86vm \
  mesa opencl-icd-loader openssl pcsclite sdl2 v4l-utils \
  vulkan-icd-loader wayland gst-plugins-base-libs libcups libpcap libpulse
```

#### 2. Build and install the patched Wine

```bash
git clone https://github.com/ItHasLegs/rhino8-wine
cd rhino8-wine
makepkg -si
```

Clones Wine at the tested commit, applies the patches, builds (~20–40 min), and installs to `/opt/wine-rhino8`. Your system Wine is untouched.

---

### 3. Install Rhino

```bash
export WINEPREFIX=~/.local/share/wineprefixes/rhino8
export WINE=/opt/wine-rhino8/bin/wine

# Create the prefix
WINEPREFIX=$WINEPREFIX WINEDEBUG=-all $WINE wineboot

# Run the Rhino installer — it bundles and auto-installs all prerequisites
# (VC2013, VC2015, WebView2, .NET 8 Desktop Runtime, ASP.NET Core Runtime)
WINEPREFIX=$WINEPREFIX WINEDEBUG=-all $WINE RhinoInstaller.exe
```

The `wintrust` patch (included in `rhino8-wine.patch`) is required for the installer to complete — Wine lacks the Microsoft CA root store needed to verify the installer's Authenticode signatures, and without the patch it fails during package verification.

### 4. Apply the rhcommon_c.dll binary patch

Rhino ships `rhcommon_c.dll` — you already have it from the installer. Patch your local copy:

```bash
DLL="$HOME/.local/share/wineprefixes/rhino8/drive_c/Program Files/Rhino 8/System/rhcommon_c.dll"
cp "$DLL" "$DLL.bak"
printf '\x31\xc0\xc3\x90\x90\x90\x90' | \
    dd of="$DLL" bs=1 seek=$((16#dff50)) conv=notrunc
```

This replaces the `RHC_RhOSInDarkMode` JMP thunk with `xor eax,eax; ret` (always returns light mode), preventing the mutual recursion crash.

### 5. Run Rhino

```bash
./run-rhino.sh
```

If the licensing OAuth flow fails (Firefox redirects to `http://127.0.0.1:1717/` and gets "can't connect"), run:

```bash
./run-rhino.sh --fresh
```

This kills and restarts the wineserver, resetting the internal HTTP server state that handles the OAuth callback.

![Rhino 8 running on Linux](desktop_screenshot.jpeg)
