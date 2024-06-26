HOSTNAME=master
hostnamectl set-hostname $HOSTNAME

MASTER=192.168.50.40
NODE1=192.168.50.41
NODE2=192.168.50.42

CONTAINERD_VERSION=1.7.13
RUNC_VERSION=1.1.12
CNI_PLUGINS_VERSION=1.4.0
K8S_VERSION=1.28.2
CALICOCTL_VERSION=3.27.2
HELM_VERSION=3.14.0
INGRESS_NGINX_HELM_CHART_VERSION=4.9.1
INGRESS_NGINX_VERSION=1.9.6
POD_NETWORK=10.168.0.0/16
SVC_NETWORK=10.96.0.0/12

yum update -y
yum install -y epel-release
yum makecache
yum erase -y firewalld
yum install -y wget yum-utils net-tools bridge-utils telnet vim jq iftop screen lrzsz lsof rsync \
    bind-utils chrony ipset ipvsadm dos2unix iptables-services
systemctl disable iptables && systemctl stop iptables


# 取消vim自动添加注释
touch ~/.vimrc
echo "set paste"|sudo tee ~/.vimrc
# 关闭selinux
setenforce 0
sed -i "s/SELINUX=enforcing/SELINUX=disabled/g" /etc/selinux/config
# 关闭交换分区
swapoff -a
sed -i 's/.*swap.*/# remove swap/' /etc/fstab

#配置时间同步
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

# 使能NFS
yum install -y nfs-utils rpcbind
systemctl start nfs-server
systemctl start rpcbind
systemctl enable nfs-server
systemctl enable rpcbind

# 限制NetworkManager管理calico生成的网卡
cat <<EOF >/etc/NetworkManager/conf.d/calico.conf
[keyfile]
unmanaged-devices=interface-name:cali*;interface-name:tunl*;interface-name:vxlan.calico
EOF

cat >> /etc/hosts <<EOF
127.0.0.1 api.k8s.com
${MASTER} master
${NODE1} node1
${NODE2} node2
EOF
more /etc/hosts

cat > /etc/modules-load.d/k8s.conf << EOF
overlay
br_netfilter
EOF

#添加网桥过滤及内核转发配置文件
cat > /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
vm.swappiness = 0
EOF

#加载br_netfilter模块
modprobe overlay
modprobe br_netfilter

#查看是否加载        
lsmod | grep    br_netfilter    

#加载网桥过滤及内核转发配置文件
sysctl -p /etc/sysctl.d/k8s.conf

dnf install -y ipset ipvsadm
cat > /etc/sysconfig/modules/ipvs.modules <<EOF
#!/bin/bash
modprobe -- ip_vs
modprobe -- ip_vs_rr
modprobe -- ip_vs_wrr
modprobe -- ip_vs_sh
modprobe -- nf_conntrack
EOF
chmod 755 /etc/sysconfig/modules/ipvs.modules && bash /etc/sysconfig/modules/ipvs.modules && lsmod | grep -e ip_vs -e nf_conntrack

# 配置containerd
wget https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/containerd-${CONTAINERD_VERSION}-linux-amd64.tar.gz
tar xzvf containerd-${CONTAINERD_VERSION}-linux-amd64.tar.gz -C /usr/local
wget -O /usr/lib/systemd/system/containerd.service https://raw.githubusercontent.com/containerd/containerd/main/containerd.service
systemctl daemon-reload
systemctl enable --now containerd
systemctl status containerd

# 配置runc
wget https://github.com/opencontainers/runc/releases/download/v${RUNC_VERSION}/runc.amd64
install -m 755 runc.amd64 /usr/local/sbin/runc

# 配置CNI plugins
wget https://github.com/containernetworking/plugins/releases/download/v${CNI_PLUGINS_VERSION}/cni-plugins-linux-amd64-v${CNI_PLUGINS_VERSION}.tgz
mkdir -p /opt/cni/bin
tar xzvf cni-plugins-linux-amd64-v${CNI_PLUGINS_VERSION}.tgz -C /opt/cni/bin

# 配置cgroup
mkdir /etc/containerd
/usr/local/bin/containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
sed -i 's/sandbox_image = "registry.k8s.io\/pause:3.8"/sandbox_image = "registry.aliyuncs.com\/google_containers\/pause:3.9"/g' /etc/containerd/config.toml
systemctl restart containerd

# 安装calico管理客户端
curl -o /usr/local/bin/calicoctl -O -L  "https://github.com/projectcalico/calico/releases/download/v${CALICOCTL_VERSION}/calicoctl-linux-amd64" 
chmod +x /usr/local/bin/calicoctl

# 配置k8s yum源
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
EOF

yum makecache -y

# 查看所有的可用版本
yum list kubelet --showduplicates | sort -r |grep 1.28
dnf install -y kubectl-${K8S_VERSION} kubelet-${K8S_VERSION} kubeadm-${K8S_VERSION}
sed -i 's/KUBELET_EXTRA_ARGS=/KUBELET_EXTRA_ARGS="--cgroup-driver=systemd"/g' /etc/sysconfig/kubelet
systemctl enable kubelet
crictl config --set runtime-endpoint=unix:///run/containerd/containerd.sock
crictl images ls

# 准备镜像
kubeadm config images pull #这个不太行
# 如果拉不动，使用阿里源
crictl pull registry.aliyuncs.com/google_containers/kube-apiserver:v1.28.7
crictl pull registry.aliyuncs.com/google_containers/kube-controller-manager:v1.28.7
crictl pull registry.aliyuncs.com/google_containers/kube-scheduler:v1.28.7
crictl pull registry.aliyuncs.com/google_containers/kube-proxy:v1.28.7
crictl pull registry.aliyuncs.com/google_containers/pause:3.9
crictl pull registry.aliyuncs.com/google_containers/etcd:3.5.9-0
crictl pull registry.aliyuncs.com/google_containers/coredns/coredns:v1.10.1
#上面最后这个不行就用这个crictl pull registry.aliyuncs.com/google_containers/coredns:v1.10.1

# 安装k8s api LB
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
    server ${MASTER}:6443;
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

# 在master使用kubeadm init命令初始化
kubeadm init --kubernetes-version=v${K8S_VERSION} \
    --pod-network-cidr=${POD_NETWORK} \
    --service-cidr=${SVC_NETWORK} \
    --apiserver-advertise-address=master \
    --apiserver-advertise-address=${MASTER} \
    --control-plane-endpoint=api.k8s.com:7443 \
    --image-repository registry.aliyuncs.com/google_containers \
    --dry-run
# 删除dry-run参数正式开始初始化，一切正常后显示以下内容
#Your Kubernetes control-plane has initialized successfully!
#
#To start using your cluster, you need to run the following as a regular user:
#
#  mkdir -p $HOME/.kube
#  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
#  sudo chown $(id -u):$(id -g) $HOME/.kube/config
#
#Alternatively, if you are the root user, you can run:
#
#  export KUBECONFIG=/etc/kubernetes/admin.conf
#
#You should now deploy a pod network to the cluster.
#Run "kubectl apply -f [podnetwork].yaml" with one of the options listed at:
#  https://kubernetes.io/docs/concepts/cluster-administration/addons/
#
#You can now join any number of control-plane nodes by copying certificate authorities
#and service account keys on each node and then running the following as root:
#
#  kubeadm join api.k8s.com:7443 --token pe9nyt.8gzolcvpnwmygoke \
#	--discovery-token-ca-cert-hash sha256:20204a06b30b937665e4689ca864dfd9c46ccf80896b411c77d26bae298c26f6 \
#	--control-plane 
#
#Then you can join any number of worker nodes by running the following on each as root:
#
#kubeadm join api.k8s.com:7443 --token pe9nyt.8gzolcvpnwmygoke \
#	--discovery-token-ca-cert-hash sha256:20204a06b30b937665e4689ca864dfd9c46ccf80896b411c77d26bae298c26f6 

# 打上work节点标记，可选
kubectl label node node1 node-role.kubernetes.io/worker=worker
kubectl label node node2 node-role.kubernetes.io/worker=worker

# 安装calico网络插件
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v${CALICOCTL_VERSION}/manifests/tigera-operator.yaml
mkdir calicodir
cd calicodir
wget https://raw.githubusercontent.com/projectcalico/calico/v${CALICOCTL_VERSION}/manifests/custom-resources.yaml
sed -i 's|192.168.0.0\/16|'"${POD_NETWORK}"'|' custom-resources.yaml
kubectl create -f custom-resources.yaml
# 确认所有pod运行正常，等待每个pod状态为running
kubectl get pods -n calico-system

# 设置kubectl命令补全(执行节点：安装了kubectl工具的主机，通常为master主机)
yum install -y bash-completion 
source /usr/share/bash-completion/bash_completion
source <(kubectl completion bash)
echo "source <(kubectl completion bash)" >> ~/.bashrc

# 调整模式为ipvs
kubectl -n kube-system edit cm kube-proxy
#将metricsBindAddress: ""下面的
#mode: "" 修改为 mode: "ipvs"
#然后删除原来所有的kube-proxy的pod使生效
#kubectl -n kube-system get pod
#kubectl -n kube-system delete pod kube-proxy-bpht4 
#kubectl -n kube-system delete pod kube-proxy-fpv6m
# 验证ipvs规则
ipvsadm -Ln

# 删除控制平面上的污点，没有污点则忽略
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
kubectl taint nodes --all node-role.kubernetes.io/master-

# 验证集群可用性
kubectl get node
kubectl get pods -n kube-system
calicoctl get nodes --allow-version-mismatch
kubectl get pods -n calico-system

# 部署metrics-server
wget https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.7.1/components.yaml
#vim components.yaml
#spec:
#      containers:
#      - args:
#        - --cert-dir=/tmp
#        - --secure-port=10250
#        - --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname
#        - --kubelet-use-node-status-port
#        - --metric-resolution=15s
#        - --kubelet-insecure-tls    #添加
#        image: k8s.mirror.nju.edu.cn/metrics-server/metrics-server:v0.7.1  #修改
kubectl apply -f components.yaml
kubectl top node
kubectl get pod -n kube-system | grep metrics-server

# 安装helm
curl -o /opt/helm-v${HELM_VERSION}-linux-amd64.tar.gz https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz
cd /opt
tar zxf helm-v${HELM_VERSION}-linux-amd64.tar.gz
cp /opt/linux-amd64/helm /usr/bin
helm version

# 安装Ingress-Nginx，采用DaemonSet+hostnetwork模式
wget https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v${INGRESS_NGINX_VERSION}/deploy/static/provider/cloud/deploy.yaml -O ingress_nginx.yaml
# 修改为DaemonSet
#将 kind: Deployment 修改为 kind: DaemonSet
#在DaemonSet.spec.template.spec下增加：hostNetwork: true
#删除在DaemonSet.strategy整个结构
#将ingress-nginx-controller的Service.spec.type 由ClusterIP修改为NodePort
#将image后面的镜像地址 @sha256删除，一共三处
#registry.cn-hangzhou.aliyuncs.com/google_containers/nginx-ingress-controller:v1.6.3
#registry.cn-hangzhou.aliyuncs.com/google_containers/kube-webhook-certgen:v20220916-gd32f8c343

kubectl apply -f ingress_nginx.yaml
watch kubectl get pods -n ingress-nginx -o wide


#=============================================================================rancher======================================================================================
#k8s-master安装rancher
helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
#helm repo remove  rancher-stable
helm repo update
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.5/cert-manager.crds.yaml
#kubectl delete -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.5/cert-manager.crds.yaml

#准备仓库
helm repo add jetstack https://charts.jetstack.io
#helm repo remove jetstack
helm repo update
kubectl create namespace cattle-system
#kubectl delete namespace cattle-system
#如果已创建过 cattle-system 可能没有被完全清理，会出现 Rancher 的验证网关错误，清理后重新创建即可
#kubectl get ValidatingWebhookConfiguration
#kubectl delete ValidatingWebhookConfiguration rancher.cattle.io
#kubectl delete ValidatingWebhookConfiguration validating-webhook-configuration
#kubectl get MutatingWebhookConfiguration
#kubectl delete MutatingWebhookConfiguration rancher.cattle.io
#kubectl create namespace cattle-system
helm install cert-manager jetstack/cert-manager \
--namespace cert-manager \
--create-namespace \
--version v1.14.5
#超时报错的话就删除重新安装
#helm uninstall cert-manager --namespace cert-manager
#helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --version v1.14.5

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
#helm uninstall rancher -n cattle-system

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
