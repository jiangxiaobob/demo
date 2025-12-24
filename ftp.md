## Vsftpd 配置指南

### 1. 安装Vsftpd
```shell
#检查是否已安装
vsftpd -v
#Ubuntu
sudo apt update
sudo apt install -y vsftpd
#CentOS
yum install -y vsftpd
#设置开机自启动
systemctl enable vsftpd
```

### 2. 创建FTP用的目录

```shell
mkdir /app/www/nginx/upload #要求: upload前面全部至少有x权限(755)归属随意，但其中upload目录归属需为ftpuser
chown ftpuser:ftpuser /app/www/nginx/upload
chmod -R 777 /app/www/nginx/upload # upload目录下的权限要x，想不加权限就改归属为ftpuser
```

### 3. 创建FTP用户配置chroot白名单

```bash
# 创建用户并设置密码
useradd -d /app/www/nginx/upload -s /bin/false ftpuser && echo "ftpuser:jht1688" | chpasswd
# 将用户加入chroot白名单
echo "ftpuser" | sudo tee -a /etc/vsftpd.chroot_list > /dev/null
# 添加合法shell（避免登录错误）
echo "/bin/false" | sudo tee -a /etc/shells
# 验证用户配置
getent passwd ftpuser #预期输出：ftpuser:x:1002:1002::/app/www/nginx/upload:/bin/false
```

### 4. 配置Vsftpd

```bash
# 备份原配置文件
sudo cp /etc/vsftpd/vsftpd.conf /etc/vsftpd/vsftpd.conf.bak
# 编辑配置文件
grep -Ev '^(#|$)' /etc/vsftpd.conf 其中包含以下内容(没就取消注释补上)
local_enable=YES # 启用本地用户
write_enable=YES # 允许写（上传、删除等）
local_umask=011 # 控制用户上传文件和目录时的默认权限掩码,011=文件655 目录766；022=文件644，目录755 (x=1 w=2 r=4)
chroot_local_user=NO # 把用户限制在其 home 目录
# 启用 chroot 白名单（当 chroot_local_user=NO 时,去读取chroot_list_file里的进行chroot）
chroot_list_enable=YES
chroot_list_file=/etc/vsftpd.chroot_list
# 允许可写子目录
allow_writeable_chroot=YES
#anonymous_enable=NO # 禁止匿名登录（安全考虑,可不要）

#允许root登录
cat /etc/ftpusers #若存在则 注释或删除掉里面的 root
cat /etc/vsftpd/user_list #若存在则 注释或删除掉里面的 root
systemctl restart vsftpd
```

> ⚠️ 若依旧不行则检查：
>
> - \#存在 ftpuser 单独设置根目录，因前面配置了 chroot_list_file, 所以多余冲突了，存在下面这操作就删掉
> - #mkdir /etc/vsftpd_user_conf && echo "local_root=/app/www/nginx/upload" > /etc/vsftpd_user_conf/ftpuser

### 5. 防火墙配置（如需要）

```bash
# 开放FTP端口（默认21）
sudo firewall-cmd --permanent --add-service=ftp
sudo firewall-cmd --reload

cat /etc/ftpusers
```