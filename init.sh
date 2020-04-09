#!/bin/bash

set -e

echo "初始化CentOS-7 系统"
SELINUX_STATUS=`getenforce`
if [ $SELINUX_STATUS != "Disabled" ];
then
    sed -i 's/^SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
fi

yum install -y wget
mkdir -p /etc/yum.repos.d/bak
mv /etc/yum.repos.d/*.repo /etc/yum.repos.d/bak
wget -O /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-7.repo
yum install epel-release -y
wget -O /etc/yum.repos.d/epel.repo http://mirrors.aliyun.com/repo/epel-7.repo

yum install python-devel gcc zlib zlib-devel openssl-devel tcpdump net-tools lsof telnet ntp vim-* -y
yum install epel-release -y
yum install python-pip -y
pip install --upgrade pip

echo "关闭防火墙/NetworkManager服务"
systemctl stop firewalld.service
systemctl disable firewalld.service
iptables -F
systemctl stop NetworkManager.service
systemctl disable NetworkManager.service
echo "关闭swap"
swapoff -a
sed -i 's/.*swap.*/#&/' /etc/fstab
echo "设置文件描述符"
cat >>/etc/rc.local<<EOF
#open files
ulimit -SHn 65535
#stack size
ulimit -s 65535
EOF
echo "优化sshd服务"
cp /etc/ssh/sshd_config{,.bak}
cat >/etc/ssh/sshd_config<<EOF
HostKey                         /etc/ssh/ssh_host_rsa_key
HostKey                         /etc/ssh/ssh_host_ecdsa_key
HostKey                         /etc/ssh/ssh_host_ed25519_key
SyslogFacility                  AUTHPRIV
AuthorizedKeysFile              .ssh/authorized_keys
PasswordAuthentication          yes
ChallengeResponseAuthentication no
GSSAPIAuthentication            no
GSSAPICleanupCredentials        no
UsePAM                          yes
X11Forwarding                   yes
AcceptEnv                       LANG LC_CTYPE LC_NUMERIC LC_TIME LC_COLLATE LC_MONETARY LC_MESSAGES
AcceptEnv                       LC_PAPER LC_NAME LC_ADDRESS LC_TELEPHONE LC_MEASUREMENT
AcceptEnv                       LC_IDENTIFICATION LC_ALL LANGUAGE
AcceptEnv                       XMODIFIERS
Subsystem                       sftp    /usr/libexec/openssh/sftp-server
UseDNS=no
IgnoreRhosts                    yes
EOF
echo "内核参数和ip_vs"
yum install ipvsadm ipset sysstat conntrack libseccomp -y
cat > /etc/sysconfig/modules/ipvs.modules <<EOF
#!/bin/bash
modprobe -- ip_vs
modprobe -- ip_vs_rr
modprobe -- ip_vs_wrr
modprobe -- ip_vs_sh
modprobe -- nf_conntrack
modprobe -- br_netfilter
EOF
chmod 755 /etc/sysconfig/modules/ipvs.modules
bash /etc/sysconfig/modules/ipvs.modules
lsmod | grep -e ip_vs -e nf_conntrack_ipv4
cat > /etc/sysctl.d/k8s.conf<<EOF 
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 10
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
net.ipv4.neigh.default.gc_stale_time = 120
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0
net.ipv4.conf.default.arp_announce = 2
net.ipv4.conf.lo.arp_announce = 2
net.ipv4.conf.all.arp_announce = 2
net.ipv4.ip_forward = 1
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 1024
net.ipv4.tcp_synack_retries = 2
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.netfilter.nf_conntrack_max = 2310720
fs.inotify.max_user_watches=89100
fs.may_detach_mounts = 1
fs.file-max = 52706963
fs.nr_open = 52706963
net.bridge.bridge-nf-call-arptables = 1
vm.swappiness = 0
vm.overcommit_memory=1
vm.panic_on_oom=0
vm.max_map_count = 655360
EOF
sysctl --system
echo "时间同步"
yum install -y chrony
cp /etc/chrony.conf{,.bak}
cat >/etc/chrony.conf<<EOF
server ntp1.aliyun.com          iburst
server ntp2.aliyun.com
server time1.cloud.tencent.com  iburst
server time2.cloud.tencent.com  iburst
server 0.cn.pool.ntp.org        iburst
server 0.centos.pool.ntp.org    iburst
server 1.centos.pool.ntp.org    iburst
server 2.centos.pool.ntp.org    iburst
server 3.centos.pool.ntp.org    iburst
stratumweight 0
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
allow 0.0.0.0/0
bindcmdaddress 127.0.0.1
local stratum 10
keyfile /etc/chrony.keys
logdir /var/log/chrony
noclientlog
logchange 1
EOF
timedatectl set-timezone Asia/Shanghai
timedatectl set-local-rtc 1
hwclock --systohc --utc

cat >>/etc/vimrc<<EOF
set expandtab
set tabstop=4
set softtabstop=4
set shiftwidth=4
autocmd FileType html setlocal shiftwidth=4 tabstop=4 softtabstop=4
autocmd FileType golang setlocal shiftwidth=4 tabstop=4 softtabstop=4
autocmd FileType go setlocal shiftwidth=4 tabstop=4 softtabstop=4
autocmd FileType yml setlocal shiftwidth=2 tabstop=2 softtabstop=2
autocmd FileType yaml setlocal shiftwidth=2 tabstop=2 softtabstop=2
autocmd FileType htmldjango setlocal shiftwidth=4 tabstop=4 softtabstop=4
autocmd FileType javascript setlocal shiftwidth=4 tabstop=4 softtabstop=4
set ls=2
set incsearch
set hlsearch
syntax on
set ruler
EOF

rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
rpm -Uvh http://www.elrepo.org/elrepo-release-7.0-3.el7.elrepo.noarch.rpm
yum --disablerepo=\* --enablerepo=elrepo-kernel repolist
# 查看可用的rpm包
yum --disablerepo=\* --enablerepo=elrepo-kernel list kernel*
# 安装长期支持版本的kernel
yum --disablerepo=\* --enablerepo=elrepo-kernel install -y kernel-lt.x86_64
# 删除旧版本工具包
yum remove kernel-tools-libs.x86_64 kernel-tools.x86_64 -y
# 安装新版本工具包
yum --disablerepo=\* --enablerepo=elrepo-kernel install -y kernel-lt-tools.x86_64
#查看默认启动顺序
awk -F\' '$1=="menuentry " {print $2}' /etc/grub2.cfg  
#默认启动的顺序是从0开始，新内核是从头插入（目前位置在0，而4.4.4的是在1），所以需要选择0。
grub2-set-default 0  
#重启并检查
reboot
