#!/bin/bash

set -euo pipefail

tmp2sys() {
	local path="$1"
	shift

	if [ -d "$path" ]; then
		rsync "$@" -a "$path/" "/$path/"
	else
		rsync "$@" -a "$path" "/$path"
	fi
}

# Source: https://stackoverflow.com/a/29613573
escape_sed_replacement() {
	sed 's/[&/\]/\\&/g' <<< "$1"
}

replace_template() {
	local template="$1"
	local replacement="$2"
	local file="$3"
	local replacement_escaped

	replacement_escaped=$(escape_sed_replacement "$replacement")

	sed -i "s/{{ $template }}/$replacement_escaped/g" "$file"
}

secret_value() {
	podman secret inspect --showsecret "$1" -f '{{ .SecretData }}'
}

cleanup_systemd() {
	find /etc/systemd/system -mindepth 1 -maxdepth 1 -print0 |
	while IFS= read -rd '' path_etc; do
		path_usr="/usr$path_etc"

		if [ -L "$path_usr" ] || [ -e "$path_usr" ]; then
			continue
		fi
		if [ -d "$path_etc" ] && [[ "$path_etc" != *service.d ]]; then
			continue
		fi

		echo "WARNING: delete $path_etc"
		rm -r "$path_etc"
	done
}

install() {
	cd "$HOME/tmp_config"

	replace_template wan_username "$(secret_value wan_username)" \
		etc/NetworkManager/system-connections/wan.nmconnection
	replace_template wan_password "$(secret_value wan_password)" \
		etc/NetworkManager/system-connections/wan.nmconnection

	chmod -R go= etc/NetworkManager/system-connections/*

	tmp2sys etc/hostname
	tmp2sys etc/sysctl.d/30-router.conf
	tmp2sys etc/subuid
	tmp2sys etc/subgid
	tmp2sys etc/NetworkManager/system-connections --delete
	tmp2sys etc/containers/systemd --delete
	tmp2sys etc/systemd/system
	tmp2sys usr/local/bin --delete
	tmp2sys usr/local/share --delete

	tmp2sys etc/sqm/ppp0.iface.conf

	systemctl daemon-reload
	nmcli connection reload
	systemctl enable --now \
		container-image-builder.timer \
		podman-auto-update.timer \
		nftables.service \
		sqm@ppp0.service

	systemctl reload nftables.service
}

rsync \
	--recursive \
	--times \
	--links \
	--devices \
	--specials \
	--executability \
	~/config-provisioned/ \
	~/tmp_config/

cleanup_systemd
install
