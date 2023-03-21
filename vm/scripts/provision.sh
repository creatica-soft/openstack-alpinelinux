set -ux

. /etc/os-release
VERSION=`echo ${VERSION_ID}|cut -f1-2 -d"."`

sed -i -e "/\/v${VERSION}\/community$/s/^#//" /etc/apk/repositories

# Upgrade All Packages in OneShot
apk upgrade --update-cache --available

# Install sudo
apk add sudo cloud-init acpi

# Add cloud-init to startup
rc-update add cloud-init

# Create Initial User
adduser -D alpine -G wheel

# Unlock alpine user
sed -i -e '/^alpine/s/!/*/' /etc/shadow

# Add alpine user to sudoers
sed -i -e '/^root ALL=(ALL) ALL/a\\alpine ALL=(ALL) ALL' /etc/sudoers

# Update MOTD

cat << EOF > /etc/motd
Welcome to $PRETTY_NAME ($VERSION_ID)!
Home URL: $HOME_URL
EOF

# Poweroff
poweroff
