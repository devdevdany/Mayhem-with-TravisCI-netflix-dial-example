#!/usr/bin/env bash

#   Copyright (C) 2020 ForAllSecure, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

######################################################################
# run-mayhem.sh
#
# SYNOPSIS: Remove all resources
#
######################################################################

# Bash safeties: exit on error, no unset variables, pipelines can't hide errors
set -o errexit
set -o nounset
set -o pipefail
set -x

# Locate the mayhem directory and make sure we are running in that folder
ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "${ROOT}"

######################################################################
# Environment pre-conditions
######################################################################

# MAYHEM_TOKEN is used to authenticate with the Mayhem API.
if [[ -z "${MAYHEM_TOKEN}" ]]; then
    echo "[ERROR] MAYHEM_TOKEN missing." 1>&2
    exit 1
fi

# MAYHEM_URL is the URL of the Mayhem deploy with which you are working.
if [[ -z "${MAYHEM_URL}" ]]; then
    echo "[ERROR] MAYHEM_URL missing." 1>&2
    exit 1
fi

# DOCKER_REGISTRY is the docker URI to the Mayhem docker registry
if [[ -z "${DOCKER_REGISTRY}" ]]; then
    echo "[ERROR] DOCKER_REGISTRY missing." 1>&2
    exit 1
fi

# IMAGE_TAG is defined in the travis build config. It contains the binary that
 # will be fuzzed by Mayhem.
if [[ -z "${IMAGE_TAG}" ]]; then
    echo "[ERROR] IMAGE_TAG missing." 1>&2
    exit 1
fi

# TRAVIS_BRANCH is provided by Travis-CI. It is the name of the branch being built.
if [[ -z "${TRAVIS_BRANCH}" ]]; then
    echo "[ERROR] TRAVIS_BRANCH missing." 1>&2
    exit 1
fi

# The organization of your Mayhem project. This must match the string on the
# left-hand-side of the 'project' property in your Mayhemfile. For example:
#
# + Mayhemfile +
#
#   project: mayhem/netflix
#
# In the above example, the organization is "mayhem" and the project
# name is "netflix". The organization needs to be created before it
# can be referenced.
#
# If an organization is not defined, then this will be the name of the user whose
# API token is used to authenticate with Mayhem.
MAYHEM_ORGANIZATION="mayhem"

# The primary branch will be continuously fuzzed. In git, for example, this
# is typically the "master" branch. Other branches will use the test cases
# generated against this branch to run regression tests.
PRIMARY_BRANCH="master"

# The Mayhem target takes the form
# $HARNESS-$BRANCH
MAYHEM_TARGET="dial-reference-${TRAVIS_BRANCH}"
MAYHEM_PRIMARY_TARGET="dial-reference-${PRIMARY_BRANCH}"

######################################################################
# Fetch the Mayhem CLI
######################################################################
CLI_NAME=mayhem
CLI_URL="${MAYHEM_URL}/cli/Linux/${CLI_NAME}"
CLI="${ROOT}/${CLI_NAME}"
wget --no-check-certificate -O "${CLI}" "${CLI_URL}"
chmod a+x "${CLI}"
${CLI} --version

######################################################################
# Authenticate with Mayhem and Mayhem Docker Registry
######################################################################
# Authenticate with Mayhem API
${CLI} login "${MAYHEM_URL}" "${MAYHEM_TOKEN}"

# Authenticate with Mayhem Docker Registry. The 'mayhem' username can be used
# when using an API token to authenticate.
docker login -u mayhem -p "${MAYHEM_TOKEN}" "${DOCKER_REGISTRY}"

######################################################################
# Upload test harness
######################################################################

# Upload the harness to the Mayhem Docker Registry
docker push "${IMAGE_TAG}"

######################################################################
# Update Mayhemfile
#
# Update the Mayhemfile with target and the name of the image that
# was just pushed to the registry
######################################################################

sed -i "s|target:.*|target: $MAYHEM_TARGET|g" Mayhemfile
sed -i "s|baseimage:.*|baseimage: $IMAGE_TAG|g" Mayhemfile

######################################################################
# Clear pending runs
#
######################################################################
${CLI} stop -n ${MAYHEM_ORGANIZATION} "netflix/${MAYHEM_TARGET}" || true

######################################################################
# Start a new run
#
# The primary branch will be triggered with whatever duration is set
# in the Mayhemfile. If a duration was not set, this will be an infinite
# run which will be stopped on the next commit to the primary branch.
#
# Other branches will fetch regression tests from the primary branch
# and run those to see if crashes have been fixed/introduced compared
# with the primary branch.
######################################################################
if [[ "${TRAVIS_BRANCH}" = "${PRIMARY_BRANCH}" ]]; then
    # Start a new continuous run
    ${CLI} run .
else
    # Find the latest run on the primary branch to determine the project/target
    # from which to download test cases.
    LATEST_PRIMARY_TARGET=$(${CLI} show -n ${MAYHEM_ORGANIZATION} --format csv "netflix/${MAYHEM_PRIMARY_TARGET}" | tail -n +2 | head -1 | cut -d"," -f1 | cut -d"/" -f"1,2"|| true)
    if [[ -n "${LATEST_PRIMARY_TARGET}" ]]; then

        # Create a folder to download primary test suite into. This is to avoid
        # overwriting the existing Mayhemfile and corpus directory.
        mkdir branch
        cd branch
        ${CLI} download -n ${MAYHEM_ORGANIZATION} -o . "${LATEST_PRIMARY_TARGET}"

        # Replace the downloaded Mayhemfile with the one that was created for
        # the current branch
        cp ../Mayhemfile .

        # Run a new regression test using the tests downloaded from the primary
        # branch target on a target for this branch and wait for it to complete
        ${CLI} wait -n ${MAYHEM_ORGANIZATION} --junit "${ROOT}/junit-results.xml" "$(${CLI} run --regression .)"

        # Unlike some CI tools, Travis CI does not have ingest junit xml files
        # natively. Use xmllint to parse for errors/failures in the output.

        # First check for failures
        if [[ $(xmllint --xpath 'string(/testsuites/@failures)' "${ROOT}/junit-results.xml") -ne 0 ]]; then
          echo "There were regression test failures..."
          cat junit-results.xml
          exit 1
        fi

        # Then check for errors
        if [[ $(xmllint --xpath 'string(/testsuites/@errors)' "${ROOT}/junit-results.xml") -ne 0 ]]; then
          echo "There were regression test errors..."
          cat junit-results.xml
          exit 1
        fi
    fi
fi

