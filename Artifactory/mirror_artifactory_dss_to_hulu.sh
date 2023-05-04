#!/bin/bash
URL_PREFIX=""
# PACKAGE=
export TEAM=$1
export PACKAGE=$2

echo "Ensure the URL prefix is set properly, remove the / after URLPREFIX in the URL if URLPREFIX is empty"
read

frogger repo create-remote --smart --url https://artifactory.us-east-1.bamgrid.net/artifactory/${URL_PREFIX}/${TEAM}-local \
    --package-type ${PACKAGE} --target-urls https://artifactory.ava.prod.hulu.com ${TEAM}-local
 
frogger repo create-virtual --package-type ${PACKAGE} --add-repos ${TEAM}-local  \
    --target-urls https://artifactory.ava.prod.hulu.com ${TEAM}
 
frogger repo create-remote --smart --url https://artifactory.ava.prod.hulu.com/artifactory/${URL_PREFIX}/${TEAM}-local --package-type ${PACKAGE} \
    --target-urls https://artifactory.aor.prod.hulu.com ${TEAM}-local
 
frogger repo create-virtual --package-type ${PACKAGE} --add-repos ${TEAM}-local  \
    --target-urls https://artifactory.aor.prod.hulu.com ${TEAM}
