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

@test "trusted.overlay.opaque" {

	mkdir /mnt/scratch/test
	chown 165536:165536 /mnt/scratch/test

	# deploy a sys container
	local syscont=$(docker_run --rm -v /mnt/scratch/test:/mnt ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

	# the attr package brings the setfattr and getfattr utils
	docker exec "$syscont" sh -c "apk add attr"
	[ "$status" -eq 0 ]

	# setup the overlayfs lower, upper, work, and merged dirs (but don't mount yet).
	docker exec "$syscont" sh -c "mkdir /mnt/lower && mkdir /mnt/upper && mkdir /mnt/work && mkdir /mnt/merged"
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c "mkdir /mnt/lower/ld1 && touch /mnt/lower/ld1/l1"
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c "mkdir /mnt/upper/ld1"
	[ "$status" -eq 0 ]

	# adding trusted.overlay.opaque to /mnt/upper/ld1 hides the contents of the lower ld1
	docker exec "$syscont" sh -c 'setfattr -n trusted.overlay.opaque -v "y" /mnt/upper/ld1'
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c 'getfattr -m "trusted.overlay.opaque" /mnt/upper/ld1'
	[ "$status" -eq 0 ]
	[[ "${lines[1]}" == 'trusted.overlay.opaque="y"' ]]

	# create the overlayfs mount and verify the opaque attribute took effect (/mnt/merged/ld1/l1 should be hidden).
	docker exec "$syscont" sh -c "mount -t overlay overlay -olowerdir=/mnt/lower,upperdir=/mnt/upper,workdir=/mnt/work /mnt/merged"
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c "ls /mnt/merged/ld1"
	[ "$status" -eq 0 ]
	[[ "$output" == "" ]]

	# umount overlayfs
	docker exec "$syscont" sh -c "umount /mnt/merged"
	[ "$status" -eq 0 ]

	# remove the trusted.overlay.opaque attribute
	docker exec "$syscont" sh -c 'setfattr -x trusted.overlay.opaque /mnt/upper/ld1'
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c 'getfattr -m "^trusted.overlay.opaque" /mnt/upper/ld1'
	[ "$status" -eq 0 ]
	[[ "${lines[1]}" == "" ]]

	# re-create the overlayfs mount
	docker exec "$syscont" sh -c "mount -t overlay overlay -olowerdir=/mnt/lower,upperdir=/mnt/upper,workdir=/mnt/work /mnt/merged"
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c "ls /mnt/merged/ld1"
	[ "$status" -eq 0 ]
	[[ "$output" == "" ]]

	# umount overlayfs
	docker exec "$syscont" sh -c "umount /mnt/merged"
	[ "$status" -eq 0 ]

	docker_stop "$syscont"

	rm -rf /mnt/scratch/test
}

# TODO:
# - Test listxattr; use "getfattr -d /mnt/upper/ld1"
# - Test getfattr on a non-existing attribute; syscall should return "-1 ENODATA"
