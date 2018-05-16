#!/bin/bash

set -e
PEER=$1
VERSION=$2

selinux_level="$(getenforce)"
if [ $selinux_level == "Enforcing" ]
then
  setenforce Permissive
fi

my_ip="$(hostname -I | cut -f1 -d' ')"
if [ $my_ip == $PEER ]
then
  peer_flag=""
else
  peer_flag="--peer $PEER"
fi
echo $peer_flag

curl https://raw.githubusercontent.com/habitat-sh/habitat/master/components/hab/install.sh > /tmp/install.sh
hab_version="$(hab -V || true)"
if [[ $hab_version = *"$VERSION"* ]]
then
  echo "hab version $VERSION already installed"
else
  bash /tmp/install.sh -v $VERSION
fi

habitat_service="$(systemctl list-units --all | grep habitat-supervisor.service || true)"
tmp_unit_file="/tmp/habitat-supervisor.service"
if [ -z "$habitat_service" ]
then
  echo "Adding the habitat systemd service"
  cat > $tmp_unit_file <<- EOM
[Unit]
Description=The Habitat Supervisor

[Service]
ExecStart=/bin/hab sup run $peer_flag --permanent-peer
Restart=on-failure

[Install]
WantedBy=default.target
EOM
  mv $tmp_unit_file /usr/lib/systemd/system/
  systemctl enable habitat-supervisor
  systemctl start habitat-supervisor
fi
