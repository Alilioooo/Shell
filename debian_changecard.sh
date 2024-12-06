#!/bin/bash

# 获取所有网络接口，过滤掉 lo 接口及Vlan接口
interfaces=$(ls /sys/class/net | grep -v lo | grep -v '\.[0-9]\+')

# 查找10Gbps接口
ten_gig_interfaces=()
for interface in $interfaces; do
  speed=$(ethtool $interface 2>/dev/null | grep 'Supported link modes:' | sed 's/.* \([0-9]\{4,\}\)baseT\/.*/\1/')
  if [[ $speed == 10000 ]]; then
    ten_gig_interfaces+=("$interface")
  fi
done

# 如果没有找到10Gbps接口，则退出
if [ ${#ten_gig_interfaces[@]} -eq 0 ]; then
  echo "没有找到10Gbps接口"
  exit 1
fi

# 对接口名称进行排序
IFS=$'\n' sorted_interfaces=($(sort <<<"${ten_gig_interfaces[*]}"))
unset IFS

# 为排序后的接口设置 udev 规则，并更新网络脚本配置文件
for i in "${!sorted_interfaces[@]}"; do
  interface=${sorted_interfaces[$i]}
  mac_address=$(ip link show "$interface" | awk '/ether/ {print $2}')
  if [[ $i -eq 0 ]]; then
    name="Wan"
  else
    name="Lan"
  fi

  # 更新 udev 规则
  echo "SUBSYSTEM==\"net\", ACTION==\"add\", DRIVERS==\"?*\", ATTR{address}==\"$mac_address\", ATTR{type}==\"1\", NAME=\"$name\"" >> /usr/lib/udev/rules.d/73-special-net-names.rules

done

#重新加载 udev 规则
udevadm control --reload-rules

echo "网卡配置已更新，请重启系统以应用更改。"
