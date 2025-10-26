#!/bin/bash

set -euo pipefail

applynow=true

if [ "${APPLYNOW:-1}" = "0" ]; then
	applynow=false
fi

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
	# Remove our old service files
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

	# Remove our old `enable` symlinks
	find /etc/systemd/system/*.wants -mindepth 1 -maxdepth 1 -print0 -type l |
	while IFS= read -rd '' path_etc; do
		path_usr="/usr$path_etc"

		if [ -L "$path_usr" ]; then
			continue
		fi

		echo "WARNING: delete $path_etc"
		rm "$path_etc"
	done
}

install() {
	cd "$HOME/tmp_config"

	replace_template wan_username "$(secret_value wan_username)" \
		usr/local/share/ppp/peers/modem
	replace_template wan_password "$(secret_value wan_password)" \
		usr/local/share/ppp/peers/modem

	tmp2sys etc/hostname
	tmp2sys etc/sysctl.d/30-router.conf
	tmp2sys etc/subuid
	tmp2sys etc/subgid
	tmp2sys etc/containers/networks --delete
	tmp2sys etc/containers/systemd --delete
	tmp2sys etc/containers/containers.conf
	tmp2sys etc/udev/rules.d --delete
	tmp2sys etc/systemd/resolved.conf.d --delete
	tmp2sys etc/wireguard --delete
	tmp2sys etc/pki/ca-trust/source/anchors --delete
	tmp2sys etc/systemd/system
	tmp2sys usr/local/bin --delete
	tmp2sys usr/local/lib --delete
	tmp2sys usr/local/share --delete
	tmp2sys etc/sqm/ppp0.iface.conf

	chcon -u system_u -r object_r -t bin_t /usr/local/share/jool/pre

	systemctl daemon-reload

	# We use our own. Don't apply it now, but at the next boot.
	systemctl disable NetworkManager.service NetworkManager-wait-online.service
	systemctl mask NetworkManager.service NetworkManager-wait-online.service
	systemctl enable \
		lan-inet.service \
		lan-void.service \
		lan-mgmt.service \
		lan-inet_vpn0.service \
		netif@jool_internet.service \
		netif@jool_parents.service \
		netif@lan.service \
		netif@modem.service

	if [ "$applynow" = true ] ; then
		systemctl enable --now nftables.service
		systemctl reload nftables.service

		systemctl enable --now \
			container-image-builder.timer \
			podman-auto-update.timer \
			prometheus-node-exporter.service \
			sqm@ppp0.service \
			wg-quick@wg0.service \
			wg-quick@wg1.service
	fi
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
