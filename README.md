# Plex AMD VAAPI Docker Mod

A [linuxserver.io Docker Mod](https://github.com/linuxserver/docker-mods) to enable **hardware transcoding (VAAPI)** for AMD GPUs in [linuxserver/plex](https://docs.linuxserver.io/images/docker-plex).

> **Note:** This is a rebuilt fork of [`jefflessard/plex-vaapi-amdgpu-mod`](https://github.com/jefflessard/docker-mods). The original Docker Hub image was last updated ~2022 and doesn't support newer AMD GPUs (like gfx1151 / Radeon 8060S). This fork auto-rebuilds weekly from Alpine edge to stay current with Mesa updates.

## Why This Mod?

The linuxserver/plex image is musl-based and ships its own ffmpeg/libva. Mixing glibc VA drivers from the host is unsafe. This mod provides a **musl-compatible VAAPI stack** from Alpine edge that supports modern AMD GPUs including new iGPUs like the Radeon 8060S (gfx1151).

Libraries are installed to `/vaapi-amdgpu/lib` (outside the Plex path) so Plex can auto-update without replacing the provided libraries.

## Building

### Automatic (GitHub Actions)

This repo includes a GitHub Actions workflow that automatically:

- Builds and pushes to **GitHub Container Registry** (ghcr.io)
- Triggers on every push to `main`/`master`
- Rebuilds weekly to pick up Alpine edge Mesa updates
- Tags images as `latest` and `mesa-edge-YYYY-MM-DD`

**No setup required!** Just push to main and the image is built and pushed automatically using the built-in `GITHUB_TOKEN`.

Your image will be available at:

```
ghcr.io/justinappler/plex-vaapi-amdgpu-mod:latest
```

### Manual Build

Build the mod image for x86_64:

```bash
docker build --platform linux/amd64 -t ghcr.io/justinappler/plex-vaapi-amdgpu-mod:latest .
```

Push to GHCR (after `docker login ghcr.io`):

```bash
docker push ghcr.io/justinappler/plex-vaapi-amdgpu-mod:latest
```

## Usage

Set the `DOCKER_MODS` environment variable to point to your GHCR image:

```bash
docker run -d \
    --device /dev/dri/ \
    -e DOCKER_MODS=ghcr.io/justinappler/plex-vaapi-amdgpu-mod:latest \
    -e VERSION=latest \
    ...
    --name plex \
    linuxserver/plex
```

Or in docker-compose:

```yaml
services:
  plex:
    image: linuxserver/plex
    devices:
      - /dev/dri:/dev/dri
    environment:
      - DOCKER_MODS=ghcr.io/justinappler/plex-vaapi-amdgpu-mod:latest
      - VERSION=latest
```

**Note:** You do NOT need to set `LD_LIBRARY_PATH` or `LIBVA_DRIVERS_PATH` manually. The mod's run script exports these automatically:

- `LD_LIBRARY_PATH=/vaapi-amdgpu/lib`
- `LIBVA_DRIVERS_PATH=/vaapi-amdgpu/lib/dri`
- `LIBVA_DRIVER_NAME=radeonsi`

## Verification

### Check VAAPI inside the container

```bash
docker exec -it plex bash -c "
  export LIBVA_DRIVERS_PATH=/vaapi-amdgpu/lib/dri
  export LD_LIBRARY_PATH=/vaapi-amdgpu/lib
  export LIBVA_DRIVER_NAME=radeonsi
  vainfo --display drm --device /dev/dri/renderD128
"
```

### Check Plex Transcoder

```bash
docker exec -it plex \
  env LIBVA_DRIVERS_PATH=/vaapi-amdgpu/lib/dri \
      LD_LIBRARY_PATH=/vaapi-amdgpu/lib \
      LIBVA_DRIVER_NAME=radeonsi \
  /usr/lib/plexmediaserver/Plex\ Transcoder \
    -hide_banner -loglevel debug -vaapi_device /dev/dri/renderD128
```

### What to look for in Plex logs

When hardware transcoding is working, you should see:

- References to `/vaapi-amdgpu/lib/dri/radeonsi_drv_video.so`
- Transcoding showing **(hw)** indicator
- No "Failed to initialise VAAPI connection" errors

## Included Components

This mod bundles from Alpine edge:

- `radeonsi_drv_video.so` - AMD VA driver (Mesa 25.x)
- `libLLVM.so` - LLVM runtime (required by Mesa)
- `libdrm.so`, `libdrm_amdgpu.so` - DRM libraries
- `amdgpu.ids` - GPU identification database
- All transitive dependencies (libelf, libexpat, libstdc++, etc.)
- musl libc runtime

## Troubleshooting

### Driver init failed

If you see:

```
libva: /vaapi-amdgpu/lib/dri/radeonsi_drv_video.so init failed
```

This usually means the Mesa version is too old to recognize your GPU. Rebuild the mod to pull the latest Alpine edge packages.

### Permission denied on /dev/dri

Ensure the container has access to DRI devices:

```yaml
devices:
  - /dev/dri:/dev/dri
```

And that the Plex user (abc) has permission to access the render device. You may need to add the `render` or `video` group.
