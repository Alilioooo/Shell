#!/bin/bash

set -u

BACKUP_TAG=$(date +%F_%H%M%S)

echo "============== Start processing the naming of a single dual-port 10 Gigabit optical network card =============="

# 获取系统类型
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID="${ID:-unknown}"
else
    echo "Operating system not recognized, exiting."
    exit 1
fi

declare -A fibre_groups
declare -A iface_pci_full

# 获取所有物理接口
interfaces=$(ls /sys/class/net | grep -v '^lo$' | grep -v '\.[0-9]\+$')

for iface in $interfaces; do
    [ -e "/sys/class/net/$iface/device" ] || continue

    ethinfo=$(ethtool "$iface" 2>/dev/null)
    [ -n "$ethinfo" ] || continue

    # 只识别光口
    echo "$ethinfo" | grep -q 'Supported ports:.*FIBRE' || continue

    pci_full=$(basename "$(readlink -f /sys/class/net/$iface/device)")
    pci_group="${pci_full%.*}"

    iface_pci_full["$iface"]="$pci_full"
    fibre_groups["$pci_group"]="${fibre_groups[$pci_group]:-} $iface"

    echo "Discover optical interface: $iface PCI: $pci_full Group: $pci_group"
done

# 找唯一一组双口光卡
matched_groups=()
for group in "${!fibre_groups[@]}"; do
    group_ifaces=$(echo "${fibre_groups[$group]:-}" | xargs)
    count=$(echo "$group_ifaces" | wc -w)

    if [ "$count" -eq 2 ]; then
        matched_groups+=("$group")
    fi
done

# 安全控制
if [ "${#matched_groups[@]}" -eq 0 ]; then
    echo "Target network card not found, exit."
    exit 1
fi

if [ "${#matched_groups[@]}" -gt 1 ]; then
    echo "Multiple dual-port optical cards detected, skipping."
    exit 0
fi

target_group="${matched_groups[0]}"
target_ifaces=$(echo "${fibre_groups[$target_group]}" | xargs)

echo
echo "Target dual-port optical card grouping:$target_group"
echo "Internal group interface: $target_ifaces"

# 排序（.0 → Wan, .1 → Lan）
sorted_ifaces=$(for iface in $target_ifaces; do
    echo "${iface_pci_full[$iface]} $iface"
done | sort | awk '{print $2}')

wan_if=$(echo "$sorted_ifaces" | sed -n '1p')
lan_if=$(echo "$sorted_ifaces" | sed -n '2p')

if [ -z "$wan_if" ] || [ -z "$lan_if" ]; then
    echo "Network card recognition failed, exit."
    exit 1
fi

wan_mac=$(cat "/sys/class/net/$wan_if/address")
lan_mac=$(cat "/sys/class/net/$lan_if/address")

echo
echo "============== Recognition results =============="
echo "First  light   port -> Wan : $wan_if MAC: $wan_mac"
echo "Second optical port -> LAN : $lan_if MAC: $lan_mac"

########################################
# CentOS / RHEL 处理
########################################

write_rhel_rules() {
    local rule_file="/etc/udev/rules.d/70-persistent-net.rules"

    [ -f "$rule_file" ] && cp -a "$rule_file" "${rule_file}.bak.${BACKUP_TAG}"

    cat >> "$rule_file" <<EOF
SUBSYSTEM=="net", ACTION=="add", DRIVERS=="?*", ATTR{address}=="$wan_mac", ATTR{type}=="1", NAME="Wan"
SUBSYSTEM=="net", ACTION=="add", DRIVERS=="?*", ATTR{address}=="$lan_mac", ATTR{type}=="1", NAME="Lan"
EOF

    echo "Already written into udev rules: $rule_file"
}

rename_ifcfg_rhel() {
    local old_name="$1"
    local new_name="$2"
    local cfg_dir="/etc/sysconfig/network-scripts"
    local old_cfg="$cfg_dir/ifcfg-$old_name"
    local new_cfg="$cfg_dir/ifcfg-$new_name"

    [ -f "$old_cfg" ] && mv -f "$old_cfg" "$new_cfg"

    if [ ! -f "$new_cfg" ]; then
        cat > "$new_cfg" <<EOF
DEVICE=$new_name
ONBOOT=yes
EOF
    else
        if grep -q '^DEVICE=' "$new_cfg"; then
            sed -i "s/^DEVICE=.*/DEVICE=$new_name/" "$new_cfg"
        else
            echo "DEVICE=$new_name" >> "$new_cfg"
        fi

        if grep -q '^ONBOOT=' "$new_cfg"; then
            sed -i 's/^ONBOOT=.*/ONBOOT=yes/' "$new_cfg"
        else
            echo "ONBOOT=yes" >> "$new_cfg"
        fi
    fi

    echo "Configuration file ready: $new_cfg"
}

########################################
# Debian 处理（仅改名，不动IP）
########################################

write_debian_rules() {
    local rule_file="/usr/lib/udev/rules.d/73-special-net-names.rules"

    [ -f "$rule_file" ] && cp -a "$rule_file" "${rule_file}.bak.${BACKUP_TAG}"

    cat >> "$rule_file" <<EOF
SUBSYSTEM=="net", ACTION=="add", DRIVERS=="?*", ATTR{address}=="$wan_mac", ATTR{type}=="1", NAME="Wan"
SUBSYSTEM=="net", ACTION=="add", DRIVERS=="?*", ATTR{address}=="$lan_mac", ATTR{type}=="1", NAME="Lan"
EOF
    echo "Already written into Debian udev rules: $rule_file"
}

########################################
# 分支执行
########################################

case "$OS_ID" in
    centos|rhel|rocky|almalinux)
        write_rhel_rules
        rename_ifcfg_rhel "$wan_if" "Wan"
        rename_ifcfg_rhel "$lan_if" "Lan"
        udevadm control --reload-rules
        ;;
    debian|ubuntu)
        write_debian_rules
        udevadm control --reload-rules
        ;;
    *)
        echo "Unsupported system types: $OS_ID"
        exit 1
        ;;
esac

########################################

echo
echo "============== Processing complete =============="
echo "Wan: $wan_if -> Wan"
echo "Lan: $lan_if -> Lan"
echo
echo "Please restart your system for the changes to take effect ! ! !"
