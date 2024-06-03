#=======================================================内网客户端安装frpc=======================================================
cd ~
wget https://github.com/fatedier/frp/releases/download/v0.58.0/frp_0.58.0_linux_amd64.tar.gz
tar -xf frp_0.58.0_linux_amd64.tar.gz
cd frp_0.58.0_linux_amd64/
cat <<EOF > /etc/systemd/system/frpc.service
[Unit]
# 服务名称，可自定义
Description = frp client
After = network.target syslog.target
Wants = network.target

[Service]
Type = simple
# 启动frpc的命令，需修改为您的frpc的安装路径
ExecStart =  /root/frp_0.58.0_linux_amd64/frpc -c /root/frp_0.58.0_linux_amd64/frpc.toml

[Install]
WantedBy = multi-user.target
EOF
systemctl daemon-reload

cat <<EOF > /root/frp_0.58.0_linux_amd64/frpc.toml 
serverAddr = "服务端IP"
serverPort = 7000

auth.method = "token"  #使用token认证，不是必须
auth.token = "1234f2ea-b98b-467f-80e0-852b123a3123"  #设置token，不是必须

[[proxies]]
name = "ssh"
type = "tcp"
localIP = "127.0.0.1"
localPort = 22
remotePort = 6000

[[proxies]]
name = "web"
type = "http"
localPort = 80
customDomains = ["www.yourdoadmin.com"]

[[proxies]]
name = "web2"
type = "http"
localPort = 8080
customDomains = ["www.yourdomain2.com"]
EOF

systemctl enable frpc --now
systemctl status frpc

#=======================================================公网服务端安装frps=======================================================
wget https://github.com/fatedier/frp/releases/download/v0.58.0/frp_0.58.0_linux_amd64.tar.gz
tar -xf frp_0.58.0_linux_amd64.tar.gz
cd frp_0.58.0_linux_amd64/
cat <<EOF > frps.toml 
bindPort = 7000  
vhostHTTPPort = 8080
auth.token = "1234f2ea-b98b-467f-80e0-852b123a3123" #服务端 客户端 都必须配置相同的token ,或在配置其system时启动命令修改为 frps -p 6000 -t 1234f2ea-b98b-467f-80e0-852b123a3123
EOF

cat <<EOF > /etc/systemd/system/frps.service
[Unit]
# 服务名称，可自定义
Description = frp server
After = network.target syslog.target
Wants = network.target

[Service]
Type = simple
# 启动frps的命令，需修改为您的frps的安装路径
ExecStart = /root/frp_0.58.0_linux_amd64/frps -c /root/frp_0.58.0_linux_amd64/frps.toml

[Install]
WantedBy = multi-user.target
EOF
systemctl daemon-reload

systemctl enable frps --now
systemctl status frps
ss -nutlp|grep 7000  #frps服务端口
ss -nutlp|grep 6000  #代理端口

#服务端配置密钥登录测试
ssh-keygen -t rsa #生成密钥对
ssh-copy-id -p 6000 -i ~/.ssh/id_rsa.pub root@本机IP #将公钥复制到远程服务器
ssh -p 6000 user@服务端IP

#或者不配置密钥，直接登录
ssh -p 6000 user@服务端IP
客户端passwd

#=======================================================docker安装frps=======================================================
cat << EOF > /etc/frps.toml 
bindPort = 7000
auth.token = "1234f2ea-b98b-467f-80e0-852b123a3123"
EOF

cat << EOF >docker-compose.yml 
services:
  frps:
    image: stilleshan/frps 
    container_name: frps
    restart: unless-stopped
    #network_mode: host
    volumes:
      - /etc/frps.toml:/frp/frps.toml
EOF

docker-compose up -d #启动
docker-compose down #关闭
docker-compose restart frps #重启
docker restart frps #重庆
docker ps | grep frps #检查
#=======================================================docker安装frpc=======================================================
cat << EOF > /etc/frpc.toml 
serverAddr = "服务端IP"
serverPort = "7000"

auth.method = "token"
auth.token = "1234f2ea-b98b-467f-80e0-852b123a3123"

[[proxies]]
name = "ssh2" #名称自定义，在所有客户端中不可有重复相同的
type = "tcp"
localIP = "192.168.50.40" #不可写回环地址，因为是容器环境，写本机内网IP即可
localPort = 22
remotePort = 6001 #映射端口也不可有重复相同的
EOF

#编写docker-compose文件，需先在本地自行配置/etc/frpc.toml文件再使用，如上个步骤
cat << EOF > docker-compose.yml
services:
  frpc:
    image: stilleshan/frpc  #https://github.com/stilleshan 他写的详细可参考，但是没有用到docker-compose
    container_name: frpc
    restart: always
    #network_mode: host
    volumes:
      - /etc/frpc.toml:/frp/frpc.toml
EOF

docker-compose up -d #启动
docker-compose down #关闭
docker-compose restart frpc #重启
docker restart frpc #重庆
docker ps | grep frpc #检查

#服务端配置密钥登录测试
ssh-keygen -t rsa #生成密钥对
ssh-copy-id -p 6001 -i ~/.ssh/id_rsa.pub root@本机IP #将公钥复制到远程服务器
ssh -p 6001 user@服务端IP

#或者不配置密钥，直接登录
ssh -p 6001 user@服务端IP
客户端passwd










