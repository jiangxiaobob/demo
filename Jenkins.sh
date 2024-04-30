# shellcheck disable=SC2148
# 配置网卡
nmcli connection modify ens33 ipv4.method manual ipv4.addresses 192.168.50.40/24 ipv4.gateway 192.168.50.1 ipv4.dns 8.8.8.8 connection.autoconnect yes
nmcli connection up ens33
nmcli connection reload
nmcli connection up ens33
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
#安装tab补全
yum install -y bash-completion 
source /usr/share/bash-completion/bash_completion
#安装docer
yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
sudo yum -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl start docker
docker version
mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json <<-'EOF'
{
  "registry-mirrors": ["https://1mvmtgbg.mirror.aliyuncs.com"]
}
EOF
sudo systemctl daemon-reload
sudo systemctl restart docker
#安装nginx反代
yum install -y nginx nginx-mod-stream
cat <<EOF >/etc/nginx/nginx.conf
# 加载stream模块
load_module /usr/lib64/nginx/modules/ngx_stream_module.so;

user nginx;
worker_processes auto;
pid /var/run/nginx.pid;
worker_rlimit_nofile 5120;
events {
  use epoll;
  worker_connections 5120;
  multi_accept on;
}

stream {
  upstream k8s {
    least_conn;
    server 192.168.50.40:6443;
  }

  server {
      listen 127.0.0.1:7443;
      access_log off;
      proxy_connect_timeout 3s;
      proxy_timeout 120s;
      proxy_pass k8s;
  }
  
}
EOF
systemctl start nginx
systemctl enable nginx
netstat -utnlp|grep 7443
#创建MySQL
systemctl restart docker
docker run -d -p 3306:3306 --privileged=true -v /mnt/mysql/log:/var/log/mysql -v /mnt/mysql/data:/var/lib/mysql  -v /mnt/mysql/conf:/etc/mysql/conf.d -e MYSQL_ROOT_PASSWORD=root --name mysql mysql:5.7
cat <<EOF > /mnt/mysql/conf/my.conf
[client]
default_character_set=utf8
[mysqld]
collation_server=utf8_general_ci
character_set_server=utf8
EOF

docker restart mysql
docker exec -it mysql /bin/bash
mysql -uroot -proot
show variables like 'character%';
#创建redis
docker run -p 6379:6379 --privileged=true \
-v /app/redis/redis.conf:/etc/redis/redis.conf \
-v /app/redis/data:/data  --name redis \
-d redis:6.2 redis-server /etc/redis/redis.conf

#创建Jenkins
docker run -d  --name jenkins -p 8080:8080 -p 50000:50000 -u root -v /opt/jenkins_home:/var/jenkins_home --restart=always jenkins/jenkins:2.400
docker ps 
docker logs jenkins


#=======================================================================================================================================================================================================================================================
#k8s-master安装rancher
helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
helm repo update
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.11.0/cert-manager.crds.yaml
#准备仓库
helm repo add jetstack https://charts.jetstack.io
helm repo update
kubectl create namespace cattle-system
helm install cert-manager jetstack/cert-manager \
--namespace cert-manager \
--create-namespace \
--version v1.11.0
#超时报错的话就删除重新安装
#helm uninstall cert-manager --namespace cert-manager
#helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --version v1.11.0

kubectl get pods -n cert-manager
kubectl get all -n cert-manager
helm repo list
#hostname自定义，ingress.extraAnnotations.kubernetes.io/ingress.class指定代理访问
helm install rancher rancher-stable/rancher \
--namespace cattle-system \
--set hostname=www.kuberancherx.cn \
--set bootstrapPassword=admin \
--set ingress.tls.source=rancher \
--set ingress.extraAnnotations.'kubernetes\.io/ingress\.class'=nginx


#检查
kubectl get nodes
kubectl get pods -n ingress-nginx
kubectl get pods -n cert-manager
kubectl get services -n ingress-nginx
kubectl get services -n cert-manager
kubectl get pods -n cattle-system
helm list -n cattle-system
kubectl get ingress -n cattle-system
kubectl describe ingress rancher -n cattle-system
kubectl exec -it ingress-nginx-controller-x9kbb  -n ingress-nginx  -- /bin/bash