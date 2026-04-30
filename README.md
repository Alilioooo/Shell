# 项目名称
描述脚本集合的用途，例如：用于系统检查和网卡配置的实用脚本。

---

## 脚本说明

### 1. `changeCard.sh`
- **作用**: Centos7通用的网卡配置脚本，设备上线后，挂载执行此脚本，根据网卡检索顺序，将万兆网卡按排序更改为Wan和Lan。
- **适用系统**: Centos7/Debian

### 2. `Centos_checksystem.sh`
- **作用**: 检查 CentOS 系统的信息，包括硬件、网络和操作系统等。
- **适用系统**: CentOS 系列。
  
### 3. `debian_checksystem.sh`
- **作用**: 检查 Debian 系统的信息，包括硬件、网络和操作系统等。
- **适用系统**: Debian 系列。

---

## 使用方法
1. 下载脚本到本地：
   ```bash
   git clone https://github.com/Alilioooo/shell.git
   cd  shell
