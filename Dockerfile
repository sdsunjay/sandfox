# For supply chain integrity, consider pinning to a specific digest:
#   docker pull ubuntu:22.04 && docker inspect --format='{{index .RepoDigests 0}}' ubuntu:22.04
# Then use: FROM ubuntu:22.04@sha256:<digest>
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install real Firefox from Mozilla PPA (Ubuntu 22.04 ships a snap stub)
# Pinned to latest stable (149.0). Update via:
#   https://launchpad.net/~mozillateam/+archive/ubuntu/ppa/+packages?field.name_filter=firefox
# Note: dbus-x11 intentionally omitted — no dbus daemon in container, reduces attack surface.
# Note: ffmpeg kept — Firefox uses system libavcodec for H.264/AAC (required for YouTube).
RUN apt-get update && apt-get install -y --no-install-recommends \
    software-properties-common gpg-agent \
    && add-apt-repository -y ppa:mozillateam/ppa \
    && printf 'Package: *\nPin: release o=LP-PPA-mozillateam\nPin-Priority: 1001\n' \
       > /etc/apt/preferences.d/mozilla-firefox \
    && apt-get update && apt-get install -y --no-install-recommends \
    firefox=149.0+build1-0ubuntu0.22.04.1~mt1 \
    pulseaudio \
    libcanberra-pulse \
    libpci3 \
    fonts-liberation \
    fonts-noto-color-emoji \
    ca-certificates \
    curl \
    ffmpeg \
    && apt-get purge -y software-properties-common gpg-agent \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

# Install uBlock Origin extension
# The SHA256 is logged at build time — pin it for reproducible builds:
#   1. Build once, note the hash from build output
#   2. Uncomment the sha256sum check below and paste in the hash
RUN curl -L -o /tmp/ublock.xpi \
    "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/addon-latest.xpi" \
    && echo "uBlock Origin SHA256: $(sha256sum /tmp/ublock.xpi)" \
    && mkdir -p /usr/lib/firefox/distribution/extensions \
    && cp /tmp/ublock.xpi /usr/lib/firefox/distribution/extensions/uBlock0@raymondhill.net.xpi \
    && rm /tmp/ublock.xpi
    # To pin: && echo "<hash>  /tmp/ublock.xpi" | sha256sum -c -

# Firefox enterprise policies: pre-configure uBlock Origin with blocklists
RUN mkdir -p /usr/lib/firefox/distribution
COPY policies.json /usr/lib/firefox/distribution/policies.json

# Create non-root user
RUN groupadd -r firefox && useradd -r -g firefox -G audio,video -d /home/firefox -s /bin/bash -m firefox

# Create Firefox hardened profile
RUN mkdir -p /home/firefox/.mozilla/firefox/hardened.default && \
    echo '[Profile0]' > /home/firefox/.mozilla/firefox/profiles.ini && \
    echo 'Name=default' >> /home/firefox/.mozilla/firefox/profiles.ini && \
    echo 'IsRelative=1' >> /home/firefox/.mozilla/firefox/profiles.ini && \
    echo 'Path=hardened.default' >> /home/firefox/.mozilla/firefox/profiles.ini && \
    echo 'Default=1' >> /home/firefox/.mozilla/firefox/profiles.ini && \
    echo '' >> /home/firefox/.mozilla/firefox/profiles.ini && \
    echo '[General]' >> /home/firefox/.mozilla/firefox/profiles.ini && \
    echo 'StartWithLastProfile=1' >> /home/firefox/.mozilla/firefox/profiles.ini && \
    echo 'Version=2' >> /home/firefox/.mozilla/firefox/profiles.ini

COPY user.js /home/firefox/.mozilla/firefox/hardened.default/user.js

# Backup profile to /opt so entrypoint can copy it into writable tmpfs
RUN cp -a /home/firefox/.mozilla /opt/firefox-profile

# Remove curl after use, strip apt metadata to prevent package reinstallation
# (rootfs is read-only, but this adds defense-in-depth)
RUN apt-get purge -y curl && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/* /var/lib/dpkg/info/*.md5sums \
    && rm -rf /etc/apt/sources.list.d/*

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

RUN chown -R firefox:firefox /home/firefox /opt/firefox-profile

USER firefox
WORKDIR /home/firefox

ENV PULSE_SERVER=tcp:host.docker.internal:4713
ENV DISPLAY=host.docker.internal:0

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
