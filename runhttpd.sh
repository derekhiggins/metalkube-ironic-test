#!/usr/bin/bash

PROVISIONING_INTERFACE=${PROVISIONING_INTERFACE:-"provisioning"}
HTTP_PORT=${HTTP_PORT:-"80"}
HTTP_IP=$(ip -4 address show dev "$PROVISIONING_INTERFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1)
until [ ! -z "${HTTP_IP}" ]; do
  echo "Waiting for ${PROVISIONING_INTERFACE} interface to be configured"
  sleep 1
  HTTP_IP=$(ip -4 address show dev "$PROVISIONING_INTERFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1)
done

mkdir -p /shared/html
chmod 0777 /shared/html

# Copy files to shared mount
cp /tmp/inspector.ipxe /shared/html/inspector.ipxe
cp /tmp/dualboot.ipxe /shared/html/dualboot.ipxe

# Use configured values
sed -i -e s/IRONIC_IP/${HTTP_IP}/g -e s/HTTP_PORT/${HTTP_PORT}/g /shared/html/inspector.ipxe

sed -i 's/^Listen .*$/Listen '"$HTTP_PORT"'/' /etc/httpd/conf/httpd.conf
sed -i -e 's|\(^[[:space:]]*\)\(DocumentRoot\)\(.*\)|\1\2 "/shared/html"|' \
    -e 's|<Directory "/var/www/html">|<Directory "/shared/html">|' \
    -e 's|<Directory "/var/www">|<Directory "/shared">|' /etc/httpd/conf/httpd.conf

# Log to std out/err
sed -i -e 's%^ \+CustomLog.*%    CustomLog /dev/stderr combined%g' /etc/httpd/conf/httpd.conf
sed -i -e 's%^ErrorLog.*%ErrorLog /dev/stderr%g' /etc/httpd/conf/httpd.conf

# Allow external access
if ! iptables -C INPUT -i "$PROVISIONING_INTERFACE" -p tcp --dport "$HTTP_PORT" -j ACCEPT 2>/dev/null ; then
    iptables -I INPUT -i "$PROVISIONING_INTERFACE" -p tcp --dport "$HTTP_PORT" -j ACCEPT
fi

/bin/runhealthcheck "httpd" "$HTTP_PORT" &>/dev/null &
exec /usr/sbin/httpd -DFOREGROUND
