#!/usr/bin/sh
set -ux

KOJI_SERVER=${KOJI_SERVER:-http://localhost:8080/kojihub}

KOJI="koji --server=${KOJI_SERVER} --user=kojiadmin --password=kojipass --authtype=password"

$KOJI add-tag f33
$KOJI add-tag --parent f33 f33-candidate
$KOJI add-tag --parent f33 --arches=x86_64 f33-build
$KOJI add-target f33-candidate f33-build f33-candidate

$KOJI add-pkg --owner kojiadmin f33-candidate Fedora-Cloud
$KOJI add-pkg --owner kojiadmin f33-candidate RHEL-Cloud

$KOJI add-pkg --owner kojiadmin f33-candidate Fedora-IoT

$KOJI regen-repo f33-build
