#!/bin/bash
# 获取所有网络接口
interfaces=$(ls /sys/class/net | grep -v lo)

# 检测所有 10Gbps 接口
ten_gig_interfaces=()
for interface in $interfaces; do
  speed=$(ethtool $interface 2>/dev/null | grep 'Supported link modes:' | grep -oP '\d{4,}')
  if [[ $speed == 10000 ]]; then
    ten_gig_interfaces+=("$interface")
  fi
done

# 如果没有发现 10Gbps 网卡，直接退出
if [[ ${#ten_gig_interfaces[@]} -eq 0 ]]; then
  echo "No 10Gbps network interfaces found."
  exit 0
fi

# 初始化计数器，用于分配 Wan 和 Lan 名称
count=0

# 更新 ifcfg 文件、重命名接口并更新 udev 规则
udev_rules_file="/usr/lib/udev/rules.d/60-net.rules"
sed -i '1s/^/#/g' "$udev_rules_file" 2>/dev/null || echo "" > "$udev_rules_file"  # 确保文件存在并注释第一行

for interface_name in "${ten_gig_interfaces[@]}"; do
  if [[ $count -eq 0 ]]; then
    new_name="Wan"
  elif [[ $count -eq 1 ]]; then
    new_name="Lan"
  else
    echo "Only two 10Gbps interfaces are supported for renaming. Skipping $interface_name."
    break
  fi

  # 更新 ifcfg 文件（如果不存在则创建）
  ifcfg_file="/etc/sysconfig/network-scripts/ifcfg-$interface_name"
  if [[ ! -e $ifcfg_file ]]; then
    echo -e "DEVICE=$interface_name\nONBOOT=yes" > "$ifcfg_file"
  fi

  # 重命名操作
  ip link set $interface_name down
  ip link set $interface_name name $new_name
  ip link set $new_name up

  # 更新 ifcfg 文件为新名称
  new_ifcfg_file="/etc/sysconfig/network-scripts/ifcfg-$new_name"
  mv "$ifcfg_file" "$new_ifcfg_file"

  # 写入新的网卡配置内容
  cat > "$new_ifcfg_file" <<EOF
DEVICE=$new_name
ONBOOT=yes
EOF

  # 获取 MAC 地址并更新 udev 规则
  mac_address=$(ip link show $new_name | awk '/ether/ {print $2}')
  echo "ACTION==\"add\", SUBSYSTEM==\"net\", DRIVERS==\"?*\", ATTR{type}==\"1\", ATTR{address}==\"$mac_address\", NAME=\"$new_name\"" >> "$udev_rules_file"

  # 增加计数器
  ((count++))

  echo "Interface $interface_name renamed to $new_name, ifcfg file updated, and udev rules added."
done

echo "10Gbps network interfaces renaming and persistence setup complete."

#东八区时钟
timedatectl set-timezone Asia/Shanghai

#关闭防火墙的命令与NetworkManager
systemctl  disable  firewalld
systemctl  stop  firewalld
systemctl disable NetworkManager
systemctl stop NetworkManager

#关闭selinux的命令
sed  -i  '7s/SELINUX=enforcing/SELINUX=disabled/g'  /etc/selinux/config

#更改SSHD端口
sed -i '17a Port 7346' /etc/ssh/sshd_config
sed -i 's/GSSAPIAuthentication yes/#GSSAPIAuthentication no/g' /etc/ssh/sshd_config
sed -i 's/#UseDNS yes/UseDNS no/g' /etc/ssh/sshd_config
systemctl enable sshd
