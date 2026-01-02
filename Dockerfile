FROM --platform=linux/amd64 alpine:edge AS source

RUN apk add --no-cache mesa-va-gallium pax-utils libdrm

# Create target directory structure
RUN mkdir -p /source/vaapi-amdgpu/lib/dri \
             /source/usr/share/libdrm \
             /source/etc/s6-overlay/s6-rc.d/svc-plex

# Copy the radeonsi VA driver
RUN cp /usr/lib/dri/radeonsi_drv_video.so /source/vaapi-amdgpu/lib/dri/

# Copy all shared library dependencies (flattened into lib dir)
# ldd output format: "libfoo.so => /path/to/libfoo.so (addr)" or "/lib/ld-musl..."
# We extract the absolute paths and copy each library
RUN ldd /usr/lib/dri/radeonsi_drv_video.so | \
    awk '{for(i=1;i<=NF;i++) if($i ~ /^\//) print $i}' | \
    grep -v '(0x' | \
    sort -u | \
    while read -r lib; do \
        [ -f "$lib" ] && cp -n "$lib" /source/vaapi-amdgpu/lib/ 2>/dev/null || true; \
    done

# Ensure musl dynamic loader and libc are definitely present (they may be symlinks)
RUN for f in /lib/ld-musl-*.so.1 /lib/libc.musl-*.so.1; do \
        [ -f "$f" ] && cp -nL "$f" /source/vaapi-amdgpu/lib/ 2>/dev/null || true; \
    done

# Copy amdgpu.ids (GPU identification database) if present
RUN [ -f /usr/share/libdrm/amdgpu.ids ] && \
    cp /usr/share/libdrm/amdgpu.ids /source/usr/share/libdrm/ || true

# Copy the run script for s6-overlay
COPY run /source/etc/s6-overlay/s6-rc.d/svc-plex/

FROM scratch

COPY --from=source "/source/" "/"
