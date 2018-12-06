#!/bin/bash
###############################################################################
# Copyright (c) 2018 Advanced Micro Devices, Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
###############################################################################
BASE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
set -e
trap 'lastcmd=$curcmd; curcmd=$BASH_COMMAND' DEBUG
trap 'errno=$?; print_cmd=$lastcmd; if [ $errno -ne 0 ]; then echo "\"${print_cmd}\" command failed with exit code $errno."; fi' EXIT
source "$BASE_DIR/common/common_options.sh"
parse_args "$@"

echo "Preparing to set up ROCm requirements. You must be root/sudo for this."
sudo yum install -y epel-release
sudo yum install -y dkms kernel-headers-`uname -r` kernel-devel-`uname -r` wget bzip2

# 1.9.1 is an old release, so the deb packages have moved over to an archive
# tarball. Let's set up a local repo to allow us to do the install here.
# Store the repo in the source directory or a temp directory.
if [ $ROCM_SAVE_SOURCE = true ]; then
    SOURCE_DIR=${ROCM_SOURCE_DIR}
    if [ ${ROCM_FORCE_GET_CODE} = true ] && [ -d ${SOURCE_DIR}/rocm_1.9.1 ]; then
        rm -rf ${SOURCE_DIR}/rocm_1.9.1
    fi
    mkdir -p ${SOURCE_DIR}
else
    SOURCE_DIR=`mktemp -d`
fi
cd ${SOURCE_DIR}
if [ ! -f ${SOURCE_DIR}/yum_1.9.1.tar.bz2 ]; then
    wget http://repo.radeon.com/rocm/archive/yum_1.9.1.tar.bz2
fi
if [ ! -d yum_1.9.1.211 ]; then
    tar -xf yum_1.9.1.tar.bz2
fi
cd yum_1.9.1.211
REAL_SOURCE_DIR=`realpath ${SOURCE_DIR}`
sudo sh -c "echo [ROCm] > /etc/yum.repos.d/rocm.repo"
sudo sh -c "echo name=ROCm >> /etc/yum.repos.d/rocm.repo"
sudo sh -c "echo baseurl=file://${REAL_SOURCE_DIR}/yum_1.9.1.211/ >> /etc/yum.repos.d/rocm.repo"
sudo sh -c "echo enabled=1 >> /etc/yum.repos.d/rocm.repo"
sudo sh -c "echo gpgcheck=0 >> /etc/yum.repos.d/rocm.repo"

OS_VERSION_NUM=`cat /etc/redhat-release | sed -rn 's/[^0-9]*([0-9]+\.*[0-9]*).*/\1/p'`
OS_VERSION_MAJOR=`echo ${OS_VERSION_NUM} | awk -F"." '{print $1}'`
OS_VERSION_MINOR=`echo ${OS_VERSION_NUM} | awk -F"." '{print $2}'`
if [ ${OS_VERSION_MAJOR} -ne 7 ]; then
    echo "Attempting to run on an unsupported OS version: ${OS_VERSION_MAJOR}"
    exit 1
fi
if [ ${OS_VERSION_MINOR} -eq 4 ] || [ ${OS_VERSION_MINOR} -eq 5 ]; then
    # On older versions of CentOS/RHEL 7, we should install the DKMS kernel module
    # as well as all of the user-level utilities
    sudo yum install -y rocm-dkms rocm-cmake atmi rocm_bandwidth_test
elif [ ${OS_VERSION_MINOR} -eq 6 ]; then
    # On CentOS/RHEL 7.6, we can skip the kernel module because the proper KFD
    # version was backported so our user-land tools can work cleanly.
    # In addition, the ROCm 1.9.1 DKMS module fails to build against the
    # backported changes, so we must skip the driver.
    sudo yum install -y rocm-dev rocm-cmake atmi rocm_bandwidth_test
    sudo mkdir -p /opt/rocm/.info/
    echo '1.9.307' | sudo tee /opt/rocm/.info/version
    echo 'SUBSYSTEM=="kfd", KERNEL=="kfd", TAG+="uaccess", GROUP="video"' | sudo tee /etc/udev/rules.d/70-kfd.rules
else
    echo "Attempting to run on an unsupported OS version: ${OS_VERSION_NUM}"
    sudo rm -f /etc/yum.repos.d/rocm.repo
    exit 1
fi
sudo rm -f /etc/yum.repos.d/rocm.repo

sudo usermod -a -G video `logname`

if [ ${ROCM_FORCE_YES} = true ]; then
    ROCM_RUN_NEXT_SCRIPT=true
elif [ ${ROCM_FORCE_NO} = true ]; then
    ROCM_RUN_NEXT_SCRIPT=false
else
    echo ""
    echo "The next script will set up users on the system to have GPU access."
    read -p "Do you want to automatically run the next script now? (y/n)? " answer
    case ${answer:0:1} in
        y|Y )
            ROCM_RUN_NEXT_SCRIPT=true
            echo 'User chose "yes". Running next setup script.'
        ;;
        * )
            echo 'User chose "no". Not running the next script.'
        ;;
    esac
fi

if [ ${ROCM_RUN_NEXT_SCRIPT} = true ]; then
    ${BASE_DIR}/02_setup_rocm_users.sh "$@"
fi
