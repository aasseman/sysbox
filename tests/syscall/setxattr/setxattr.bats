#!/usr/bin/env bats

#
# Verify trapping & emulation on "setxattr"
#

load ../../helpers/run
load ../../helpers/syscall
load ../../helpers/docker
load ../../helpers/environment
load ../../helpers/mounts
load ../../helpers/sysbox-health

function teardown() {
  sysbox_log_check
}

@test "setxattr trusted.overlay.opaque" {

	# deploy a sys container
	local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

	# the attr package brings the setfattr and getfattr utils
	docker exec "$syscont" sh -c "apk add attr"
	[ "$status" -eq 0 ]

	# setup the overlayfs lower, upper, work, and merged dirs (but don't mount yet).
	docker exec "$syscont" sh -c "mkdir /root/lower && mkdir /root/upper && mkdir /root/work && mkdir /root/merged"
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c "mkdir /root/lower/ld1 && touch /root/lower/ld1/l1"
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c "mkdir /root/upper/ld1"
	[ "$status" -eq 0 ]

	# adding trusted.overlay.opaque to /root/upper/ld1 hides the contents of the lower ld1
	docker exec "$syscont" sh -c 'setfattr -n trusted.overlay.opaque -v "y" /root/upper/ld1'
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c 'getfattr -m "^trusted\." -d /root/upper/ld1'
	[ "$status" -eq 0 ]
	[[ "${lines[1]}" == 'trusted.overlay.opaque="y"' ]]

	# create the overlayfs mount and verify the opaque attribute took effect (/root/merged/ld1/l1 should be hidden).
	docker exec "$syscont" sh -c "mount -t overlay overlay -olowerdir=/root/lower,upperdir=/root/upper,workdir=/root/work /root/merged"
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c "ls /root/merged/ld1"
	[ "$status" -eq 0 ]
	[[ "$output" == "" ]]

	# umount overlayfs
	docker exec "$syscont" sh -c "umount /root/merged"
	[ "$status" -eq 0 ]

	# remove the trusted.overlay.opaque attribute
	docker exec "$syscont" sh -c 'setfattr -x trusted.overlay.opaque /root/upper/ld1'
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c 'getfattr -m "^trusted\." -d /root/upper/ld1'
	[ "$status" -eq 0 ]
	[[ "${lines[1]}" == "" ]]

	# re-create the overlayfs mount
	docker exec "$syscont" sh -c "mount -t overlay overlay -olowerdir=/root/lower,upperdir=/root/upper,workdir=/root/work /root/merged"
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c "ls /root/merged/ld1"
	[ "$status" -eq 0 ]
	[[ "$output" == "" ]]

	# umount overlayfs
	docker exec "$syscont" sh -c "umount /root/merged"
	[ "$status" -eq 0 ]

	docker_stop "$syscont"
}
