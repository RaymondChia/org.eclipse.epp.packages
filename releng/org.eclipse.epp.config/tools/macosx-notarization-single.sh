#!/bin/bash
#*******************************************************************************
# Copyright (c) 2019, 2020 IBM Corporation and others.
#
# This program and the accompanying materials
# are made available under the terms of the Eclipse Public License 2.0
# which accompanies this distribution, and is available at
# https://www.eclipse.org/legal/epl-2.0/
#
# SPDX-License-Identifier: EPL-2.0
#
# Contributors:
#     Sravan Kumar Lakkimsetti - initial API and implementation
#     Jonah Graham - adapted for the EPP project (used https://git.eclipse.org/c/platform/eclipse.platform.releng.aggregator.git/tree/cje-production/scripts/common-functions.shsource?id=8866cc6db76d777751acb56456b248708dd80eda#n47 as source)
#*
set -x # echo all commands used for debugging purposes


##
# Notatize a single file passed as an argument. Uses current directory as a temporary directory

DMG_FILE="$1"
DMG="$(basename "${DMG_FILE}")"
cp "${DMG_FILE}" "${DMG}"

PRIMARY_BUNDLE_ID="$(echo ${DMG} | sed  's/-macosx.cocoa.x86_64.dmg//g' | sed -E 's/^[0-9\-]*_(.*)/\1/g')"

# Because this script is run in parallel, randomly delay each script so they don't start in the same second
# (this should probably be moved to the caller that does parallel)
sleep $((RANDOM%120))s

retryCount=3
while [ ${retryCount} -gt 0 ]; do

  RESPONSE=$(curl -s -X POST -F file=@${DMG} -F 'options={"primaryBundleId": "'${PRIMARY_BUNDLE_ID}'", "staple": true};type=application/json' http://172.30.206.146:8383/macos-notarization-service/notarize)
  UUID="$(echo "${RESPONSE}" | jq -r '.uuid')"
  STATUS="$(echo "${RESPONSE}" | jq -r '.notarizationStatus.status')"

  while [[ ${STATUS} == 'IN_PROGRESS' ]]; do
    sleep 1m
    RESPONSE=$(curl -s http://172.30.206.146:8383/macos-notarization-service/${UUID}/status)
    STATUS=$(echo ${RESPONSE} | jq -r '.notarizationStatus.status')
  done

  if [[ ${STATUS} != 'COMPLETE' ]]; then
    echo "Notarization failed: ${RESPONSE}"
    retryCount=$(expr $retryCount - 1)
    if [ $retryCount -eq 0 ]; then
      echo "Notarization failed 3 times. Exiting"
      exit 1
    else
      echo "Retrying..."
    fi
  else
    break
  fi

done

rm "${DMG}"
curl -JO http://172.30.206.146:8383/macos-notarization-service/${UUID}/download
cp -vf "${DMG}" "${DMG_FILE}"
