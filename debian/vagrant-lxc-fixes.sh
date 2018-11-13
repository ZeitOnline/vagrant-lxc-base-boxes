#!/bin/bash
set -e

source common/ui.sh
source common/utils.sh

# Fixes some networking issues
# See https://github.com/fgrehm/vagrant-lxc/issues/91 for more info
if ! $(grep -q 'ip6-allhosts' ${ROOTFS}/etc/hosts); then
  log "Adding ipv6 allhosts entry to container's /etc/hosts"
  echo 'ff02::3 ip6-allhosts' >> ${ROOTFS}/etc/hosts
fi

utils.lxc.start

if [ ${DISTRIBUTION} = 'debian' ]; then
  # Ensure locales are properly set, based on http://askubuntu.com/a/238063
  LANG=${LANG:-en_US.UTF-8}
  sed -i "s/^# ${LANG}/${LANG}/" ${ROOTFS}/etc/locale.gen

  # Fixes some networking issues
  # See https://github.com/fgrehm/vagrant-lxc/issues/91 for more info
  sed -i -e "s/\(127.0.0.1\s\+localhost\)/\1\n127.0.1.1\t${CONTAINER}\n/g" ${ROOTFS}/etc/hosts

  # Ensures that `/tmp` does not get cleared on halt
  # See https://github.com/fgrehm/vagrant-lxc/issues/68 for more info
  utils.lxc.attach /usr/sbin/update-rc.d -f checkroot-bootclean.sh remove
  utils.lxc.attach /usr/sbin/update-rc.d -f mountall-bootclean.sh remove
  utils.lxc.attach /usr/sbin/update-rc.d -f mountnfs-bootclean.sh remove

  # Fixes for jessie, following the guide from
  # https://wiki.debian.org/LXC#Incompatibility_with_systemd
  if [ "$RELEASE" = 'jessie' ] || [ "$RELEASE" = 'stretch' ]; then
	  # Reconfigure the LXC
	  utils.lxc.attach /bin/cp \
		  /lib/systemd/system/getty@.service \
		  /etc/systemd/system/getty@.service
	  # Comment out ConditionPathExists
	  sed -i -e 's/\(ConditionPathExists=\)/# \n# \1/' \
		  "${ROOTFS}/etc/systemd/system/getty@.service"

	  # Mask udev.service and systemd-udevd.service:
	  utils.lxc.attach /bin/systemctl mask udev.service systemd-udevd.service
  fi
fi

# Disable automatic apt runs, otherwise they might lock apt/dpkg directly after
# boot, when e.g. test runs will want to use it.
# See https://github.com/chef/bento/issues/609 for more info.
echo 'APT::Periodic::Enable "0";' > ${ROOTFS}/etc/apt/apt.conf.d/10disable-periodic

# Disable system-resolved, since it breaks resolving DNS names of other
# lxc containers, see https://github.com/systemd/systemd/issues/10298
rm -f ${ROOTFS}/etc/resolv.conf
ln -s ../run/systemd/resolve/resolv.conf ${ROOTFS}/etc/resolv.conf

utils.lxc.attach /usr/sbin/locale-gen ${LANG}
utils.lxc.attach update-locale LANG=${LANG}

# Fix to allow bindfs
utils.lxc.attach ln -sf /bin/true /sbin/modprobe
utils.lxc.attach mknod -m 666 /dev/fuse c 10 229
