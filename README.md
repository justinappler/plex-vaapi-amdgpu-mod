# Plex AMD VAAPI Docker Mod

A [linuxserver.io Docker Mod](https://github.com/linuxserver/docker-mods) to enable **hardware transcoding (VAAPI)** for AMD GPUs in [linuxserver/plex](https://docs.linuxserver.io/images/docker-plex).

## Quick Start

Add this to your Plex container:

```yaml
services:
  plex:
    image: linuxserver/plex
    devices:
      - /dev/dri:/dev/dri
    environment:
      - DOCKER_MODS=ghcr.io/justinappler/plex-vaapi-amdgpu-mod:latest
```

That's it! Restart your container and hardware transcoding should work.

---

## Why This Mod Exists

### The Problem

You have a **new AMD GPU** (like Radeon 8060S / gfx1151 / RDNA4) and VAAPI works perfectly on your host:

```bash
$ vainfo
libva info: VA-API version 1.22.0
Trying display: drm
vainfo: Supported profile and target: VAProfileH264Main : VAEntrypointVLD/VAEntrypointEncSlice
...
```

But inside Plex Docker, hardware transcoding fails with:
```
libva: radeonsi_drv_video.so init failed
Failed to initialise VAAPI connection: -1 (unknown libva error)
```

### The Root Causes

1. **Plex bundles old libraries**: Plex ships musl-compiled binaries with libdrm 2.4.120 which doesn't recognize new GPUs
2. **Hardcoded paths**: Plex's bundled libdrm has a hardcoded path to `amdgpu.ids` from their build environment that doesn't exist
3. **No libva bundled**: Plex expects libva from the system, but linuxserver/plex doesn't include it
4. **The original mod is stale**: [`jefflessard/plex-vaapi-amdgpu-mod`](https://github.com/jefflessard/docker-mods) hasn't been rebuilt since ~2022

### What This Mod Does

1. **Bundles modern Mesa/libva** from Alpine edge (Mesa 25.x with gfx1151 support)
2. **Wraps Plex binaries** to inject `LD_LIBRARY_PATH` so our libraries are used
3. **Creates Plex's hardcoded paths** so libdrm can find `amdgpu.ids`
4. **Auto-rebuilds weekly** to stay current with Mesa updates

---

## Supported GPUs

This mod is specifically designed for **new AMD GPUs** that aren't recognized by Plex's bundled libraries:

| GPU | Architecture | Status |
|-----|--------------|--------|
| Radeon 8060S | gfx1151 / RDNA4 | ✅ Tested, working |
| Radeon 8050S | gfx1151 / RDNA4 | Should work |
| Other RDNA4 | gfx115x | Should work |
| Older AMD GPUs | RDNA3, RDNA2, etc. | Should work |

If your GPU works on the host with `vainfo` but not in Plex Docker, this mod should help.

---

## Installation

### Option 1: Use the pre-built image (recommended)

```yaml
services:
  plex:
    image: linuxserver/plex
    devices:
      - /dev/dri:/dev/dri
    environment:
      - DOCKER_MODS=ghcr.io/justinappler/plex-vaapi-amdgpu-mod:latest
      - PUID=1000
      - PGID=1000
```

### Option 2: Pin to a specific date

For reproducibility, you can pin to a dated tag:

```yaml
environment:
  - DOCKER_MODS=ghcr.io/justinappler/plex-vaapi-amdgpu-mod:mesa-edge-2026-01-02
```

### Option 3: Fork and build your own

1. Fork this repo
2. Push to trigger GitHub Actions build
3. Use your own image: `ghcr.io/YOUR_USERNAME/plex-vaapi-amdgpu-mod:latest`

---

## Verification

### Check container startup logs

You should see:
```
**** Setting up AMD VAAPI drivers ****
Creating Plex's hardcoded amdgpu.ids path...
Linked amdgpu.ids to Plex's expected path
Creating Plex Transcoder wrapper...
Transcoder wrapper created
Creating Plex Media Server wrapper...
Plex Media Server wrapper created
Linked driver: radeonsi_drv_video.so
**** AMD VAAPI setup complete ****
```

### Check Plex transcoding logs

When transcoding, look for:
```
TPU: hardware transcoding: final decoder: vaapi, final encoder: vaapi
```

This confirms VAAPI is being used for both decode and encode.

### Check Plex dashboard

Active transcodes should show **(hw)** indicator:
- `Video: HEVC → H264 (hw)`

### Harmless warnings you can ignore

```
amdgpu: os_same_file_description couldn't determine if two DRM fds reference the same file description.
```
This is a Mesa warning and doesn't affect functionality.

```
Critical: libusb_init failed
```
Plex tells you to ignore this - it's unrelated to transcoding.

---

## Troubleshooting

### "init failed" or "resource allocation failed"

If the mod is installed but transcoding still fails:

1. **Clear the mod cache and recreate container**:
   ```bash
   docker compose down plex
   rm -rf /path/to/plex/config/.modcache
   docker compose up -d plex
   ```

2. **Check that wrappers were created**:
   ```bash
   docker exec plex head -5 "/usr/lib/plexmediaserver/Plex Transcoder"
   ```
   Should show a bash script, not ELF binary header.

3. **Verify libraries are present**:
   ```bash
   docker exec plex ls /vaapi-amdgpu/lib/
   ```

### Permission denied on /dev/dri

Ensure your container has device access and correct group permissions:

```yaml
devices:
  - /dev/dri:/dev/dri
group_add:
  - video
  - render  # if this group exists on your system
```

### GPU not recognized (Unknown AMD)

The "Unknown AMD (XXXX)" message is normal - it just means Plex doesn't have a marketing name for your GPU. As long as transcoding works, ignore it.

---

## Technical Details

### How it works

1. **At container init** (via s6-overlay oneshot):
   - Creates Plex's hardcoded `amdgpu.ids` path and symlinks our file there
   - Wraps `Plex Media Server` binary with a script that sets `LD_LIBRARY_PATH`
   - Wraps `Plex Transcoder` binary similarly
   - Symlinks our VA driver to Plex's driver cache

2. **At runtime**:
   - Plex binaries load our modern Mesa/libva instead of their bundled old versions
   - Our `amdgpu.ids` (from Alpine libdrm 2.4.131) recognizes new GPUs
   - VA driver initializes successfully

### Bundled components (from Alpine edge)

| Component | Purpose |
|-----------|---------|
| `radeonsi_drv_video.so` | AMD VA driver (Mesa 25.x) |
| `libva*.so` | VA-API library |
| `libdrm*.so` | DRM library with new GPU support |
| `libLLVM*.so` | LLVM runtime for Mesa |
| `amdgpu.ids` | GPU identification database |
| `ld-musl-x86_64.so.1` | musl dynamic linker |
| + all transitive dependencies | |

### Why musl?

Plex Media Server is compiled with musl libc (not glibc). You can verify this:
```bash
docker exec plex ls /usr/lib/plexmediaserver/lib/ | grep musl
# ld-musl-x86_64.so.1
```

This is why we use Alpine (musl-based) rather than Ubuntu packages.

---

## Building from source

```bash
# Clone
git clone https://github.com/justinappler/plex-vaapi-amdgpu-mod.git
cd plex-vaapi-amdgpu-mod

# Build
docker build --platform linux/amd64 -t my-plex-mod .

# Test locally
# Add to your compose: DOCKER_MODS=my-plex-mod
```

---

## Credits

- Original mod by [@jefflessard](https://github.com/jefflessard/docker-mods)
- This fork maintained by [@justinappler](https://github.com/justinappler)
- Built on [linuxserver/docker-mods](https://github.com/linuxserver/docker-mods) framework

## License

MIT
