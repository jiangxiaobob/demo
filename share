#==================================配置SMB共享==================================
#Ubuntu服务端
apt install samba
mkdir /mysmb
addgroup nobody 
chown -R nobody:nobody /mysmb
#vim  /etc/samba/smb.conf 添加在Global Settings下面
#[shared]
#comment = Shared folder
#path = /mysmb #共享目录
#public = yes  #允许所有人访问
#read only = no #禁止只读
#browsable = yes #允许客户机在网络上浏览当前共享
#create mask = 0644 #用于新文件的权限
#directory mask = 0777 #用于新目录的权限
##guest ok = yes  #访问服务共享文件时不需要用户密码，但是前面设置了public，所以就不用这个
systemctl restart smbd

#Windows客户端连接
打开 控制面板/所有控制面板项/程序和功能 --> 启用或关闭Windows功能, 找到 SMB 1.0/CIFS文件共享支持打上勾
win+R输入 gpedit.msc 来到本地组策略编辑器-->本地计算机策略-->计算机配置-->管理模板-->网络-->Lanman工作站-->启用不安全的来宾登录, 点击已启用再点确定。重启Windows
win+R输入 \\服务端IP\mysmb   连接到共享目录


#==================================配置NFS共享==================================
#Linux服务端
apt-get install nfs-kernel-server || yum install nfs-utils -y
mkdir /var/mynfs
addgroup nobody 
chown nobody:nobody /var/mynfs
echo "/var/mynfs    *(insecure,fsid=0,rw,sync,no_root_squash,no_all_squash)" >> /etc/exports
exportfs -a
systemctl start nfs-kernel-server || systemctl start nfs
systemctl enable nfs-kernel-server  || systemctl enable nfs

#Windows server NFS共享 在服务器管理器->文件和存储服务->任务中新建
#创建好后，其中 （共享  本地路径  协议  可用性类型）的‘共享’显示的名称 为客户端所需挂载的目录名称，并非按照本地路径挂载

#客户端
apt-get install nfs-common || yum install nfs-utils -y
mkdir -p /mnt/mountnfs
mount -t nfs 服务端IP:/var/mynfs /mnt/mountnfs
echo "服务端IP:/var/mynfs    /mnt/mountnfs    nfs defaults 0 0" >> /etc/fstab
mount -a
mount | grep  mountnfs
