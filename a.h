#内网客户端安装
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

systemctl restart 
systemctl reload-or-restart

cat <<EOF > /root/frp_0.58.0_linux_amd64/frpc.toml 
serverAddr = "服务端IP"
serverPort = 7000

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

systemctl start frpc
systemctl status frpc
ss -untlp|grep 7000

#公网服务端安装
wget https://github.com/fatedier/frp/releases/download/v0.58.0/frp_0.58.0_linux_amd64.tar.gz
tar -xf frp_0.58.0_linux_amd64.tar.gz
cd frp_0.58.0_linux_amd64/
cat <<EOF > frps.toml
bindPort = 7000
vhostHTTPPort = 8080
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

systemctl restart 
systemctl reload-or-restart
cat <<EOF > frps.toml 
bindPort = 7000
vhostHTTPPort = 8080
EOF

systemctl start frps
systemctl status frps
ss -nutlp|grep 7000
ss -nutlp|grep 6000

#测试
ssh -p port user@服务端IP
客户端passwd
