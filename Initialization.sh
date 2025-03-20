#===============================================CentOS初始化================================================
# 配置网卡
nmcli connection modify ens33 ipv4.method manual ipv4.addresses 192.168.50.43/24 ipv4.gateway 192.168.50.1 ipv4.dns 8.8.8.8 connection.autoconnect yes
nmcli connection up ens33 && nmcli connection reload && nmcli connection up ens33
#或者用nimatui或者直接修改配置文件
tee /etc/sysconfig/network-scripts/ifcfg-ens33  <<'EOF'
TYPE=Ethernet
PROXY_METHOD=none
BROWSER_ONLY=no
DEFROUTE=yes
IPV4_FAILURE_FATAL=no
IPV6INIT=yes
IPV6_AUTOCONF=yes
IPV6_DEFROUTE=yes
IPV6_FAILURE_FATAL=no
IPV6_ADDR_GEN_MODE=eui64
NAME=ens33
UUID=37ee78f5-f959-478e-b7cf-bff140a2e7d1
DEVICE=ens160
ONBOOT=yes
PREFIX=24
BOOTPROTO=static #或者直接删除
IPADDR=192.168.177.111
GATEWAY=192.168.177.2
DNS1=114.114.114.114
EOF
#检查
nmcli connection reload && nmcli connection up ens33
more /etc/resolv.conf
route -n
ping -c 4 www.baidu.com
#安装组件
yum install -y wget yum-utils net-tools bridge-utils telnet vim jq iftop screen lrzsz lsof rsync bind-utils chrony ipset ipvsadm dos2unix iptables-services
systemctl disable iptables && systemctl stop iptables
# 取消vim自动添加注释
touch ~/.vimrc
echo "set paste"|sudo tee ~/.vimrc
# 关闭交换分区
swapoff -a
sed -i 's/.*swap.*/# remove swap/' /etc/fstab
# 安装NFS
yum install -y nfs-utils rpcbind
systemctl start nfs-server
systemctl start rpcbind
systemctl enable nfs-server
systemctl enable rpcbind
#关闭selinux
setenforce 0
sed -i "s/SELINUX=enforcing/SELINUX=disabled/g" /etc/selinux/config

#时间同步
yum install chrony
systemctl start chronyd
systemctl enable chronyd
#vim /etc/chrony.conf
#server ntp1.aliyun.com iburst
#server time1.aliyun.com iburst
systemctl restart chronyd
cp -r /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
chronyc tracking
date

#CentOS安装tab补全
yum install -y bash-completion 
source /usr/share/bash-completion/bash_completion

#配置代理
echo "export http_proxy=http://代理ip:端口/" >> ~/.bashrc
echo "export https_proxy=https://代理ip:端口/" >> ~/.bashrc
source ~/.bashrc

#================================================Ubuntu初始化=================================================
#切换到root用户
sudo su #回车后输入普通用户密码
cd && pwd

# 网络配置
sudo tee /etc/netplan/01-netcfg.yaml <<'EOF'
network:
  version: 2
  renderer: networkd
  ethernets:
    ens33:
      dhcp4: false #或者 no
      addresses: [192.168.32.128/24]
      routes:
        - to: default
          via: 192.168.32.2
      nameservers:
        addresses: [8.8.8.8]
EOF
sudo netplan apply
#网络配置验证
ip a | grep 192
ip route
ping -c 4 baidu.com 

#root默认没密码，设置root密码
echo 'root:passwd' | sudo chpasswd
#允许root登录ssh 
sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
systemctl restart ssh

#配置软件仓库
bash <(curl -sSL https://gitee.com/SuperManito/LinuxMirrors/raw/main/ChangeMirrors.sh)
#安装基础组件
sudo apt update && sudo apt upgrade -y
sudo apt install -y wget curl net-tools chrony telnet lrzsz lsof \
screen bridge-utils iftop jq rsync dnsutils ipset ipvsadm dos2unix \
nfs-common nfs-kernel-server bash-completion

# 禁用防火墙
sudo ufw disable

# 关闭交换分区
sudo swapoff -a
sudo sed -i '/swap/s/^/#/' /etc/fstab  # 永久禁用

# 配置 Vim 避免自动注释
echo "set paste" | sudo tee -a ~/.vimrc

# 禁用AppArmor
sudo systemctl stop apparmor
sudo systemctl disable apparmor

# 时间同步配置
sudo sed -i 's/^pool.*/server ntp.aliyun.com iburst/' /etc/chrony/chrony.conf
sudo systemctl restart chrony
sudo timedatectl set-timezone Asia/Shanghai
#时间同步状态
chronyc tracking
# 强制24小时制时间格式，执行后重启或登录新窗口再验证
echo 'LC_TIME=en_DK.UTF-8' | sudo tee -a /etc/environment
date

# 启用bash自动补全
#echo 'source /usr/share/bash-completion/bash_completion' >> ~/.bashrc
source /usr/share/bash-completion/bash_completion
 
# 代理配置
echo 'export http_proxy="http://代理ip:端口/"' | sudo tee -a /etc/environment
echo 'export https_proxy="https://代理ip:端口/"' | sudo tee -a /etc/environment
source /etc/environment
