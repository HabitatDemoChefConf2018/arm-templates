#!/bin/bash

set -e
PEERS=$1
VERSION=$2
BUILDER_URL=$3
HAB_PACKAGE=$4
HAB_SVC_CONFIG=$5


selinux_level="$(getenforce)"
if [ $selinux_level == "Enforcing" ]
then
  setenforce Permissive
fi

my_ip="$(hostname -I | cut -f1 -d' ')"
peer_flag=""
IFS=',' read -ra ADDR <<< "$PEERS"
for i in "${ADDR[@]}"; do
  if [ $my_ip != $i ]
  then
    peer_flag="$peer_flag --peer $i"
  fi
done

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
ExecStart=/bin/hab sup run --url $BUILDER_URL $peer_flag
Restart=on-failure

[Install]
WantedBy=default.target
EOM
  mv $tmp_unit_file /usr/lib/systemd/system/
  systemctl enable habitat-supervisor
  systemctl start habitat-supervisor
fi

if [ -n $HAB_PACKAGE ]
then
  if [ -z $(hab sup status | grep $HAB_PACKAGE || true) ]
  then
    hab sup load --url $BUILDER_URL $HAB_PACKAGE $HAB_SVC_CONFIG
  fi
fi
