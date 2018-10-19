#!/bin/bash

. /etc/sysconfig/heat-params

set -ux

if [ "$(echo "${INSTALL_DISABLED}" | tr '[:upper:]' '[:lower:]')" = "false" ]; then
    _prefix=${CONTAINER_INFRA_PREFIX:-docker.io/openstackmagnum/}
    atomic install \
    --storage ostree \
    --system \
    --system-package no \
    --set REQUESTS_CA_BUNDLE=/etc/pki/tls/certs/ca-bundle.crt \
    --name heat-container-agent \
    ${_prefix}heat-container-agent:rawhide
else
    systemctl enable heat-container-agent
fi

systemctl start heat-container-agent
