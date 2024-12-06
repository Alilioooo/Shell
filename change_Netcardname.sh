#!/bin/bash

#获取所有网络接口及其速度的列表
interfaces=$(ls /sys/class/net | grep -v lo)

# 更新ifcfg- 文件以反映新的接口名称
for interface_name in $interfaces; do
  ifcfg_file="/etc/sysconfig/network-scripts/ifcfg-$interface_name"
  if [[ ! -e $ifcfg_file ]]; then
    touch "$ifcfg_file"
  fi
done

# 查找10Gbps接口的索引
# shellcheck disable=SC2207
ten_gig_interfaces=($(for interface in $interfaces; do
  speed=$(ethtool $interface | grep 'Supported link modes:' | sed 's/.* \([0-9]\{4,\}\)baseT\/.*/\1/')
  if [[ $speed == 10000 ]]; then
    echo $interface
  fi
done))

# 重命名10Gbps网络接口
for interface_name in "${ten_gig_interfaces[@]}"; do
  if [[ $interface_name =~ ^p.*p.*1$ || $interface_name =~ ^ens.*0$ ]]; then
    new_name="Wan"
  elif [[ $interface_name =~ ^p.*p.*2$ || $interface_name =~ ^ens.*1$ ]]; then
    new_name="Lan"
  else
    echo "Unknown network interface naming convention. Skipping $interface_name."
    continue
  fi
  ip link set $interface_name down
  ip link set $interface_name name $new_name
  ip link set $new_name up

  # 更新udev规则，使新接口名称在重新启动后保持不变
  mac_address=$(ip link show $new_name | awk '/ether/ {print $2}')
  sed -i '1s/^/#/g' /usr/lib/udev/rules.d/60-net.rules
  echo "ACTION==\"add\", SUBSYSTEM==\"net\", DRIVERS==\"?*\", ATTR{type}==\"1\", ATTR{address}==\"$mac_address\", NAME=\"$new_name\"" >> /usr/lib/udev/rules.d/60-net.rules

  # 更新ifcfg文件以反映新的接口名称
  ifcfg_file="/etc/sysconfig/network-scripts/ifcfg-$interface_name"
  if [[ -f $ifcfg_file ]]; then
    mv $ifcfg_file "/etc/sysconfig/network-scripts/ifcfg-$new_name"
    sed -i "s/$interface_name/$new_name/" "/etc/sysconfig/network-scripts/ifcfg-$new_name"
    echo "DEVICE=$new_name" > "/etc/sysconfig/network-scripts/ifcfg-$new_name"
    echo "ONBOOT=yes"  >> "/etc/sysconfig/network-scripts/ifcfg-$new_name"
    echo "Updated $ifcfg_file -> /etc/sysconfig/network-scripts/ifcfg-$new_name"
  else
    echo "ifcfg file $ifcfg_file not found. Skipping."
  fi

done
