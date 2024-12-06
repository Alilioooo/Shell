#!/bin/bash

echo -e "\033[91;1m当前系统资源使用情况:\033[0m"
echo "=============================="
echo ""

echo -e "\033[91;1mCPU核心:\033[0m"
echo "------------------------------"
echo "$(lscpu | grep 'CPU(s):' | head -n1 | column -t)"
echo ""

echo -e "\033[91;1m内存容量:\033[0m"
echo "------------------------------"
echo "Mem:     $(free -h |grep -Ew "Mem|内存" | awk '{print $2}')"
echo ""

echo -e "\033[91;1m系统盘:\033[0m"
echo "------------------------------"
# 获取根文件系统的设备名称
root_device=$(lsblk -P | grep 'MOUNTPOINTS="/"')
if [[ $root_device =~ NAME=\"([^\"]+)\" ]]; then
  root_device_name="${BASH_REMATCH[1]}"
  if [[ $root_device_name =~ nvme ]]; then
    new_device_name="$(echo $root_device_name | sed 's/[a-z][0-9]*$//')"
    device_name="/dev/$new_device_name"
  else
    new_device_name="$(echo $root_device_name | sed 's/[0-9]*$//')"
    device_name="/dev/$new_device_name"
  fi
  echo "$device_name"
else
  echo "无法找到根目录所在设备的名称"
fi
echo ""

echo -e "\033[91;1m系统分区:\033[0m"
echo "------------------------------"
lsblk_output=$(lsblk -o NAME,SIZE,FSTYPE,TYPE,MOUNTPOINT $device_name | column -t)
echo "$lsblk_output"
echo ""

echo -e "\033[91;1m检查分区:\033[0m"
echo "------------------------------"
# 正则表达式，匹配类似 "/data/proclog" 的拼写
pro=$(lsblk -o NAME,MOUNTPOINT $device_name | awk '{print $2}' | grep -Ei '/d[ae]{1}t[ae]/p[aroclog]*')
# 检查匹配结果
if [ -n "$pro" ]; then
  if [[ "$pro" =~ /data/proclog ]]; then
    echo -e "\033[92;1m$pro 默认名称正确，无需更改 ! ! !\033[0m"
  else
    echo -e "\033[93;1m值与 /data/proclog 不一致: $pro\033[0m"
#    umount $pro
#    mkdir -p /data/proclog
#    sed -i "s|$pro|/data/proclog|g" /etc/fstab
#    mount -a
  fi
else
  echo -e "\033[91;1m无法找到 /data/proclog 目录 ? ? ?\033[0m"
fi
echo ""

echo -e "\033[91;1m硬盘类型:\033[0m"
echo "------------------------------"
# 获取系统盘的数量和总大小
disk_System=$(lsscsi -s | grep "$device_name" | awk '$NF ~ /[0-9]/  {size[$NF]++} END {for (s in size) printf "系统盘 %s：%d块\n", s,size[s]}' | column )
# 输出系统盘信息
if [[ -n "$disk_System" ]]; then
  echo "$disk_System"
else
  echo "系统盘：0块 0TB"
fi

# 获取Nvme盘的数量和总大小
disk_Nvme=$(lsscsi -s | grep -v "$device_name" | grep nvme | awk '$NF ~ /[0-9]/ {size[$NF]++} END {for (s in size) printf "Nvme %s：%d块\n", s, size[s]}' | column -t )
# 输出 NVMe 硬盘信息
if [[ -n "$disk_Nvme" ]]; then
  echo "$disk_Nvme"
else
  echo "Nvme 硬盘：0块 0TB"
fi

# 获取机械硬盘的数量和总大小
disk_Scsi=$(lsscsi -s | grep -Ev "nvme|$device_name" |awk '$NF ~ /[0-9]/ {size[$NF]++} END {for (s in size) printf "机械 %s：%d块\n", s, size[s]}' | column  -t )
# 输出机械硬盘信息
if [[ -n "$disk_Scsi" ]]; then
  echo "$disk_Scsi"
else
  echo "机械盘：0块 0TB"
fi
echo ""

echo -e "\033[91;1m网卡接口信息:\033[0m"
echo "------------------------------"
# 获取所有接口信息，并排除掉lo接口以及没有配置IP地址的接口
interfaces=$(ip a | grep -E '^[0-9]+:' | grep -v 'lo' | awk -F ': ' '{print $2}' | awk -F '@' '{print $1}' | while read -r intf; do ip a show dev $intf | grep -q 'inet ' && echo "$intf"; done)
# 循环遍历每个接口
for interface in $interfaces; do
  echo "接口: $interface"
# 获取公网IPv4接口的（如果有的话）
  ipv4_address=$(ip a show dev $interface | grep -E 'inet [0-9.]+' | awk '{print $2}')
  if [ -n "$ipv4_address" ]; then
    echo -e "\033[35;1m  IPv4 地址: $ipv4_address\033[0m"
  else
    echo "  IPv4地址: 无"
  fi

# 获取公网IPv6接口的（如果有的话），排除Link-Local地址
  ipv6_addresses=$(ip a show dev $interface | grep -E 'inet6 [0-9a-fA-F:]+' | awk '{print $2}')
    ipv6_found=false
    for ipv6_address in $ipv6_addresses; do
      if [[ ! $ipv6_address == fe80* ]]; then
        echo -e "\033[35;1m  IPv6 地址: $ipv6_address\033[0m"
        ipv6_found=true
      fi
    done
    if [ "$ipv6_found" = false ]; then
      echo "  IPv6地址: 无"
    fi
    echo ""
done
echo ""

# 判断IP地址是否为公网IP地址的函数
is_public_ip() {
  local ip=$1
  if [[ $ip =~ ^10\. ]] || [[ $ip =~ ^172\.1[6-9]\. ]] || [[ $ip =~ ^172\.2[0-9]\. ]] || [[ $ip =~ ^172\.3[0-1]\. ]] || [[ $ip =~ ^192\.168\. ]] || [[ $ip =~ ^127\. ]]; then
    return 1
  else
    return 0
  fi
}

# 打印IP连通性标题
echo -e "\033[91;1mIP连通性:\033[0m"
echo "------------------------------"

# 目标IP地址
ipv4_ping_target="223.5.5.5"
ipv6_ping_target="2400:3200::1"

# 遍历所有接口，获取其IPv4和IPv6地址
for interface in $interfaces; do
  echo -e "\033[45;1m网卡:\033[0m $interface"
  # 获取IPv4地址
  ipv4=$(ip a show dev $interface | grep -E 'inet [0-9.]+' | awk '{print $2}' | awk -F'/' '{print $1}')
  if [ -n "$ipv4" ]; then
    echo "  IPv4地址: $ipv4"
    if is_public_ip "$ipv4"; then
      echo "  Ping $ipv4_ping_target..."
      ping -fc 100 -I $interface $ipv4_ping_target
    else
      # 提取网段
      subnet=$(ip a show dev $interface | grep -E 'inet [0-9.]+' | awk '{print $2}')
      subnet_prefix=$( echo $subnet | cut -d'/' -f1 | sed 's/\.[0-9]*$/.0\/24/')
      network=$(echo $subnet | cut -d'/' -f1 | sed 's/\.[0-9]*$/./')
      echo "  内网网段: $subnet_prefix"
      echo "  扫描内网存活IP..."
      alive_ips=$(timeout 5s fping -a -g ${network}0/24 2>/dev/null)
      echo "  Ping内网存活IP..."
      echo " "
      for ip in $alive_ips; do
        echo -e "  \033[91;1mPing $ip...\033[0m"
        ping -fc 100 -I $ipv4 $ip
      done
    fi
  else
    echo "  IPv4地址: 无"
  fi

# 获取IPv6地址
  ipv6=$(ip a show dev $interface | grep -v fe80 | grep -E 'inet6 [0-9a-fA-F:]+' | awk '{print $2}' | awk -F'/' '{print $1}')
  if [ -n "$ipv6" ]; then
    echo -e "  \033[91;1mIPv6地址: $ipv6\033[0m"
    echo -e "  \033[91;1mPing    : $ipv6_ping_target... \033[0m"
    ping6 -fc 100 -I $ipv6 $ipv6_ping_target
  else
    echo ""
    echo -e "  \033[55;1mIPv6地址: 无\033[0m"
  fi
  echo "------------------------------"
done
echo ""
