emulate -L zsh
setopt errexit nounset pipefail

config_file=$1
test_root=$(mktemp -d "${TMPDIR:-/tmp}/srdzsh-cryptex-paths.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

mount_root=$test_root/mnt
current_mount=$mount_root/com.research.zsh.Current
alpha_mount=$mount_root/com.research.alpha.First
spaced_mount=$mount_root/com.research.tools\ With\ Spaces.Second

mkdir -p \
	$current_mount/usr/local/bin \
	$current_mount/usr/bin \
	$current_mount/usr/share/zsh/5.9.2/functions \
	$current_mount/usr/share/zsh/site-functions \
	$current_mount/usr/share/terminfo \
	$alpha_mount/usr/bin \
	$alpha_mount/usr/sbin \
	$spaced_mount/bin

probe=$alpha_mount/usr/bin/srd-cryptex-path-probe
print -r -- '#!/bin/sh' 'exit 0' > $probe
chmod 0755 $probe

export SRD_CRYPTEX_MOUNT_ROOT=$mount_root
export CRYPTEX_MOUNT_PATH=$current_mount
export PATH="$current_mount/usr/bin:/inherited/bin:/usr/bin:/bin"
fpath=(/inherited/functions)

source $config_file

expected_path=(
	$current_mount/usr/local/bin
	$current_mount/usr/bin
	/inherited/bin
	/usr/bin
	/bin
	$alpha_mount/usr/bin
	$alpha_mount/usr/sbin
	$spaced_mount/bin
)

[[ "${(j.:.)path}" == "${(j.:.)expected_path}" ]] || {
	print -u2 "unexpected cryptex PATH:"
	print -l -u2 -- $path
	exit 1
}

(( ${path[(I)$current_mount/usr/bin]} == 2 )) || {
	print -u2 "current cryptex path was not deduplicated"
	exit 1
}

[[ $fpath[1] == $current_mount/usr/share/zsh/5.9.2/functions ]] || {
	print -u2 "current cryptex function path is not first"
	exit 1
}

[[ $TERMINFO == $current_mount/usr/share/terminfo ]] || {
	print -u2 "current cryptex terminfo path was not selected"
	exit 1
}

[[ $(whence -p srd-cryptex-path-probe) == $probe ]] || {
	print -u2 "tool in another cryptex was not discoverable"
	exit 1
}

(
	unset CRYPTEX_MOUNT_PATH
	export SRD_CRYPTEX_MOUNT_ROOT=$test_root/not-mounted
	export PATH=/inherited/bin:/usr/bin:/bin
	fpath=(/inherited/functions)

	source $config_file

	[[ $PATH == /inherited/bin:/usr/bin:/bin ]] || {
		print -u2 "PATH changed when no cryptexes were mounted"
		exit 1
	}
)
