#!/usr/bin/env sh

# This script performs basic setup for Fedora and Podman on the Windows Subsystem for Linux (WSL).
# Fedora must be installed in WSL. A compatible Fedora image may be downloaded at https://github.com/fedora-cloud/docker-brew-fedora.
# To find the correct image, you must follow the link and switch to the branch for the version you want.
# Once you arrive at the correct branch, you must choose the directory for your CPU architecture (usually x86_64), and download the .tar file.

# Create user account
dnf install cracklib-dicts -y
read -p "Enter new username (all lower-case): " USERNAME
adduser -G wheel "$USERNAME"
echo -e "[user]\ndefault=$USERNAME" >> /etc/wsl.conf
passwd $USERNAME

# Set up Podman
dnf reinstall shadow-utils -y # Version of shadow-utils installed with container base appears to be broken, so gets reinstalled
dnf install podman slirp4netns -y
sed -i 's/events_logger = "journald"/events_logger = "file"/' /usr/share/containers/containers.conf
sed -i 's/log_driver = "journald"/log_driver = "k8s-file"/' /usr/share/containers/containers.conf
echo -e "[boot]\ncommand = mount --make-rshared / && rm -rf /tmp/*\n" | tee -a /etc/wsl.conf

# Install Nvidia GPU support
echo "Do you want to use an Nvidia GPU with Podman?"
select yn in "Yes" "No"; do
    case $yn in
        Yes ) curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo | tee /etc/yum.repos.d/nvidia-container-toolkit.repo \
            && dnf install nvidia-container-toolkit -y \
            && nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml;
            break;;
        No ) break;;
    esac
done

# Install Nvidia GPU support
echo "Do you want to make Nano the default text editor?"
select yn in "Yes" "No"; do
    case $yn in
        Yes ) dnf install nano-default-editor --allowerasing;
            break;;
        No ) break;;
    esac
done
