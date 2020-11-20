#!/bin/bash
set -euo pipefail

# Colorful output.
function greenprint {
  echo -e "\033[1;32m${1}\033[0m"
}

# Get OS and architecture details.
source /etc/os-release
ARCH=$(uname -m)

# Mock is only available in EPEL for RHEL.
if [[ $ID == rhel ]] && ! rpm -q epel-release; then
    greenprint "📦 Setting up EPEL repository"
    curl -Ls --retry 5 --output /tmp/epel.rpm \
        https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
    sudo rpm -Uvh /tmp/epel.rpm
fi

# Register RHEL if we are provided with a registration script.
if [[ -n "${RHN_REGISTRATION_SCRIPT:-}" ]] && ! sudo subscription-manager status; then
    greenprint "🪙 Registering RHEL instance"
    sudo chmod +x $RHN_REGISTRATION_SCRIPT
    sudo $RHN_REGISTRATION_SCRIPT
fi

# Install requirements for building RPMs in mock.
greenprint "📦 Installing mock requirements"
sudo dnf -y install createrepo_c meson mock ninja-build python3-pip rpm-build

# Install s3cmd if it is not present.
if ! s3cmd --version > /dev/null 2>&1; then
    greenprint "📦 Installing s3cmd"
    sudo pip3 -q install s3cmd
fi

# Jenkins sets a workspace variable as the root of its working directory.
WORKSPACE=${WORKSPACE:-$(pwd)}

# Mock configuration file to use for building RPMs.
MOCK_CONFIG="${ID}-${VERSION_ID%.*}-$(uname -m)"

# The commit we are testing
GIT_SHA=$(git rev-parse --short HEAD)

# Bucket in S3 where our artifacts are uploaded
REPO_BUCKET=osbuild-composer-repos

# Public URL for the S3 bucket with our artifacts.
MOCK_REPO_BASE_URL="http://${REPO_BUCKET}.s3-website.us-east-2.amazonaws.com"

# Directory to hold the RPMs temporarily before we upload them.
REPO_DIR=koji-osbuild/${GIT_SHA}/${ID}${VERSION_ID//./}_${ARCH}

# Full URL to the RPM repository after they are uploaded.
REPO_URL=${MOCK_REPO_BASE_URL}/${REPO_DIR}

# Print some data.
greenprint "🧬 Using mock config: ${MOCK_CONFIG}"
greenprint "📦 Git SHA: ${GIT_SHA}"
greenprint "📤 RPMS will be uploaded to: ${REPO_URL}"

# Build source RPMs.
greenprint "🔧 Building source RPMs."
meson build
ninja -C build srpms

# Compile RPMs in a mock chroot
greenprint "🎁 Building RPMs with mock"
sudo mock -v -r $MOCK_CONFIG --resultdir repo/$REPO_DIR --with=tests \
    build/rpmbuild/SRPMS/*.src.rpm

# Change the ownership of all of our repo files from root to our CI user.
sudo chown -R $USER repo/${REPO_DIR%%/*}

greenprint "  Remove logs from mock build"
rm repo/${REPO_DIR}/*.log

# Create a repo of the built RPMs.
greenprint "⛓️ Creating dnf repository"
createrepo_c repo/${REPO_DIR}

# Upload repository to S3.
greenprint "☁ Uploading RPMs to S3"
pushd repo
    s3cmd --acl-public sync . s3://${REPO_BUCKET}/
popd

# Create a repository file.
greenprint "📜 Generating dnf repository file"
tee mock.repo << EOF
[schutzbot-mock]
name=schutzbot mock ${GIT_SHA} ${ID}${VERSION_ID//./}
baseurl=${REPO_URL}
enabled=1
gpgcheck=0
# Default dnf repo priority is 99. Lower number means higher priority.
priority=5
EOF
