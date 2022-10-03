#!/usr/bin/env bash
# coding=utf-8

# WARNING: DO NOT EDIT!
#
# This file was generated by plugin_template, and is managed by it. Please use
# './plugin-template --github galaxy_ng' to update this file.
#
# For more info visit https://github.com/pulp/plugin_template

# make sure this script runs at the repo root
cd "$(dirname "$(realpath -e "$0")")"/../../..
REPO_ROOT="$PWD"

set -mveuo pipefail

shopt -s expand_aliases
source .github/workflows/scripts/utils.sh

export POST_SCRIPT=$PWD/.github/workflows/scripts/post_script.sh
export POST_DOCS_TEST=$PWD/.github/workflows/scripts/post_docs_test.sh
export FUNC_TEST_SCRIPT=$PWD/.github/workflows/scripts/func_test_script.sh

# Needed for both starting the service and building the docs.
# Gets set in .github/settings.yml, but doesn't seem to inherited by
# this script.
export DJANGO_SETTINGS_MODULE=pulpcore.app.settings
export PULP_SETTINGS=$PWD/.ci/ansible/settings/settings.py

export PULP_URL="https://pulp"

if [[ "$TEST" = "docs" ]]; then
  if [[ "$GITHUB_WORKFLOW" == "Galaxy CI" ]]; then
    pip install towncrier==19.9.0
    towncrier --yes --version 4.0.0.ci
  fi
  cd docs
  make PULP_URL="$PULP_URL" diagrams html
  tar -cvf docs.tar ./_build
  cd ..

  if [ -f $POST_DOCS_TEST ]; then
    source $POST_DOCS_TEST
  fi
  exit
fi

if [[ "${RELEASE_WORKFLOW:-false}" == "true" ]]; then
  STATUS_ENDPOINT="${PULP_URL}${PULP_API_ROOT}api/v3/status/"
  echo $STATUS_ENDPOINT
  REPORTED_VERSION=$(http $STATUS_ENDPOINT | jq --arg plugin galaxy --arg legacy_plugin galaxy_ng -r '.versions[] | select(.component == $plugin or .component == $legacy_plugin) | .version')
  response=$(curl --write-out %{http_code} --silent --output /dev/null https://pypi.org/project/galaxy-ng/$REPORTED_VERSION/)
  if [ "$response" == "200" ];
  then
    echo "galaxy_ng $REPORTED_VERSION has already been released. Skipping running tests."
    exit
  fi
fi

if [[ "$TEST" == "plugin-from-pypi" ]]; then
  COMPONENT_VERSION=$(http https://pypi.org/pypi/galaxy-ng/json | jq -r '.info.version')
  git checkout ${COMPONENT_VERSION} -- galaxy_ng/tests/
fi

echo "machine pulp
login admin
password password
" | cmd_stdin_prefix bash -c "cat > ~pulp/.netrc"
cmd_stdin_prefix bash -c "chmod og-rw ~pulp/.netrc"

cat unittest_requirements.txt | cmd_stdin_prefix bash -c "cat > /tmp/unittest_requirements.txt"
cat functest_requirements.txt | cmd_stdin_prefix bash -c "cat > /tmp/functest_requirements.txt"
cmd_prefix pip3 install -r /tmp/unittest_requirements.txt
cmd_prefix pip3 install -r /tmp/functest_requirements.txt
cmd_prefix pip3 install --upgrade ../pulp-smash

cd ../pulp-openapi-generator
./generate.sh galaxy_ng python
cmd_prefix pip3 install /root/pulp-openapi-generator/galaxy_ng-client
sudo rm -rf ./galaxy_ng-client
./generate.sh pulpcore python
cmd_prefix pip3 install /root/pulp-openapi-generator/pulpcore-client
sudo rm -rf ./pulpcore-client
./generate.sh pulp_ansible python
cmd_prefix pip3 install /root/pulp-openapi-generator/pulp_ansible-client
sudo rm -rf ./pulp_ansible-client
./generate.sh pulp_container python
cmd_prefix pip3 install /root/pulp-openapi-generator/pulp_container-client
sudo rm -rf ./pulp_container-client
cd $REPO_ROOT

CERTIFI=$(cmd_prefix python3 -c 'import certifi; print(certifi.where())')
cmd_prefix bash -c "cat /etc/pulp/certs/pulp_webserver.crt  | tee -a "$CERTIFI" > /dev/null"

# check for any uncommitted migrations
echo "Checking for uncommitted migrations..."
cmd_user_prefix bash -c "django-admin makemigrations --check --dry-run"

# Run unit tests.
cmd_user_prefix bash -c "PULP_DATABASES__default__USER=postgres pytest -v -r sx --color=yes -p no:pulpcore --pyargs galaxy_ng.tests.unit"

# Run functional tests
if [[ "$TEST" == "performance" ]]; then
  if [[ -z ${PERFORMANCE_TEST+x} ]]; then
    cmd_user_prefix bash -c "pytest -vv -r sx --color=yes --pyargs --capture=no --durations=0 galaxy_ng.tests.performance"
  else
    cmd_user_prefix bash -c "pytest -vv -r sx --color=yes --pyargs --capture=no --durations=0 galaxy_ng.tests.performance.test_$PERFORMANCE_TEST"
  fi
  exit
fi

if [ -f $FUNC_TEST_SCRIPT ]; then
  source $FUNC_TEST_SCRIPT
else

    if [[ "$GITHUB_WORKFLOW" == "Galaxy Nightly CI/CD" ]] || [[ "${RELEASE_WORKFLOW:-false}" == "true" ]]; then
        cmd_user_prefix bash -c "pytest -v -r sx --color=yes --suppress-no-test-exit-code --pyargs galaxy_ng.tests.functional -m parallel -n 8 --nightly"
        cmd_user_prefix bash -c "pytest -v -r sx --color=yes --pyargs galaxy_ng.tests.functional -m 'not parallel' --nightly"

    
    else
        cmd_user_prefix bash -c "pytest -v -r sx --color=yes --suppress-no-test-exit-code --pyargs galaxy_ng.tests.functional -m parallel -n 8"
        cmd_user_prefix bash -c "pytest -v -r sx --color=yes --pyargs galaxy_ng.tests.functional -m 'not parallel'"

    
    fi

fi

if [ -f $POST_SCRIPT ]; then
  source $POST_SCRIPT
fi
