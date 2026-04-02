#!/bin/bash
# Copy the hardened profile from the image backup into the writable tmpfs
# Use cp without -a since we can't preserve root ownership as non-root user
cp -r /opt/firefox-profile/. /home/firefox/.mozilla/

# Create PulseAudio client config to disable cookie auth (using anonymous TCP)
mkdir -p /home/firefox/.config/pulse
echo "cookie-file = /dev/null" > /home/firefox/.config/pulse/client.conf

exec firefox --no-remote --profile /home/firefox/.mozilla/firefox/hardened.default "$@"
