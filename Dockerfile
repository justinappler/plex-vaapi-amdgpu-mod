FROM --platform=linux/amd64 alpine:edge AS source

# Install mesa VA driver AND libva (we need both from the same source for ABI compatibility)
RUN apk add --no-cache mesa-va-gallium libva pax-utils libdrm

# Create target directory structure
RUN mkdir -p /source/vaapi-amdgpu/lib/dri \
             /source/usr/share/libdrm

# Copy the radeonsi VA driver
RUN cp /usr/lib/dri/radeonsi_drv_video.so /source/vaapi-amdgpu/lib/dri/

# Copy libva libraries (these must match the driver version)
RUN cp -a /usr/lib/libva*.so* /source/vaapi-amdgpu/lib/

# Copy all shared library dependencies (flattened into lib dir)
RUN ldd /usr/lib/dri/radeonsi_drv_video.so | \
    awk '{for(i=1;i<=NF;i++) if($i ~ /^\//) print $i}' | \
    grep -v '(0x' | \
    sort -u | \
    while read -r lib; do \
        [ -f "$lib" ] && cp -n "$lib" /source/vaapi-amdgpu/lib/ 2>/dev/null || true; \
    done

# Also get libva dependencies
RUN ldd /usr/lib/libva.so.2 | \
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

# Copy the s6-overlay init scripts (correct structure for v3)
COPY root/ /source/

# Make init scripts executable
RUN chmod +x /source/etc/s6-overlay/s6-rc.d/*/run 2>/dev/null || true

FROM scratch

COPY --from=source "/source/" "/"
