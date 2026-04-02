FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install real Firefox from Mozilla PPA (Ubuntu 22.04 ships a snap stub)
RUN apt-get update && apt-get install -y --no-install-recommends \
    software-properties-common gpg-agent \
    && add-apt-repository -y ppa:mozillateam/ppa \
    && printf 'Package: *\nPin: release o=LP-PPA-mozillateam\nPin-Priority: 1001\n' \
       > /etc/apt/preferences.d/mozilla-firefox \
    && apt-get update && apt-get install -y --no-install-recommends \
    firefox \
    pulseaudio \
    libcanberra-pulse \
    libpci3 \
    dbus-x11 \
    fonts-liberation \
    fonts-noto-color-emoji \
    ca-certificates \
    curl \
    ffmpeg \
    && apt-get purge -y software-properties-common gpg-agent \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

# Install uBlock Origin extension
RUN curl -L -o /tmp/ublock.xpi \
    "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/addon-latest.xpi" \
    && mkdir -p /usr/lib/firefox/distribution/extensions \
    && cp /tmp/ublock.xpi /usr/lib/firefox/distribution/extensions/uBlock0@raymondhill.net.xpi \
    && rm /tmp/ublock.xpi

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

# Remove curl after use, clean up
RUN apt-get purge -y curl && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

RUN chown -R firefox:firefox /home/firefox /opt/firefox-profile

USER firefox
WORKDIR /home/firefox

ENV PULSE_SERVER=tcp:host.docker.internal:4713
ENV DISPLAY=host.docker.internal:0

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
