

---

# MySQL 8.0 主从部署与数据迁移

## 1. 部署 MySQL 8.0（主从服务的   端口、my.cnf 不同，其他一样）

### 1.1 创建目录

```shell
mkdir -p /root/mysql
mkdir -p /opt/mysql8.0/{conf,logs,data}
```

### 1.2 编写 `docker-compose.yml`

```shell
cat > /root/mysql/docker-compose.yml << 'EOF'
services:
  mysql:
    image: mysql:8.0
    container_name: mysql8.0
    restart: no
    environment:
      MYSQL_ROOT_PASSWORD: 123456
      TZ: Asia/Shanghai
    ports:
      - "3309:3306"
    volumes:
      - /opt/mysql8.0/data:/var/lib/mysql
      - /opt/mysql8.0/conf/my.cnf:/etc/my.cnf
      - /opt/mysql8.0/logs:/var/log/mysql
EOF
```

### 1.3 编写 MySQL 配置文件

```shell
#主库服务器配置
cat > /opt/mysql8.0/conf/my.cnf << 'EOF'
[mysqld]
skip-host-cache
skip-name-resolve
datadir=/var/lib/mysql
socket=/var/run/mysqld/mysqld.sock
secure-file-priv=/var/lib/mysql-files
user=mysql

pid-file=/var/run/mysqld/mysqld.pid
[client]
socket=/var/run/mysqld/mysqld.sock

server-id=1
log-bin=mysql-bin
# 可选：指定需要同步的数据库，如果不设置则同步所有数据库
binlog-do-db=KanzRecord
binlog-do-db=KanzActivity
binlog-do-db=KanzPay
binlog-do-db=KanzUser
# 可选：指定不需要同步的系统数据库
binlog-ignore-db=mysql
binlog-ignore-db=sys
binlog-ignore-db=information_schema
binlog-ignore-db=performance_schema
# 可选：为未来切换到GTID模式做准备
enforce_gtid_consistency=ON

!includedir /etc/mysql/conf.d/
EOF
#=====================================================================================
#从库服务器配置
cat > /opt/mysql8.0/conf/my.cnf << 'EOF'
[mysqld]
server-id = 2                # 唯一ID
bind-address = 0.0.0.0       # 允许所有服务器访问
skip-host-cache
skip-name-resolve
datadir = /var/lib/mysql
socket = /var/run/mysqld/mysqld.sock
secure-file-priv = /var/lib/mysql-files
user = mysql
pid-file = /var/run/mysqld/mysqld.pid

log-bin = mysql-bin          # 开启二进制日志，主从必备
read-only = 1                # 从库设置只读
# 可选：指定需要同步的数据库（可多次指定）
replicate-do-db = KanzRecord
replicate-do-db = KanzActivity
replicate-do-db = KanzPay
replicate-do-db = KanzUser

!includedir /etc/mysql/conf.d/
[client]
socket = /var/run/mysqld/mysqld.sock
EOF
```

### 1.4 启动 MySQL 容器

```shell
docker compose -f /root/mysql/docker-compose-mysql.yml up -d
```

---

## 2. 数据迁移（使用 Percona Xtrabackup）

### 2.1 安装 Xtrabackup 工具（主从都装）

#### 方法一：直接使用包管理器安装

```shell
apt update && apt install percona-xtrabackup
```

#### 方法二：下载安装包安装

```shell
# 从 https://www.percona.com/downloads 下载对应版本，再安装
dpkg -i percona-xtrabackup-80_8.0.35-35-1.noble_amd64.deb
apt install lz4 #依赖
```

### 2.2 在主库执行物理备份

> **注意：确保主库的 MySQL 数据目录与配置文件路径正确！**

```shell
# 创建符号链接（如需要，因为docker跑的需在宿主机上执行）
ln -s /opt/mysql8.0/data /var/lib/mysql
# 生成备份文件
mkdir /root/db
xtrabackup --defaults-file=/opt/mysql8.0/conf/my.cnf \
            --datadir=/opt/mysql8.0/data \
            --user=root --password=123456 \
            --host=192.168.0.116 \
            --backup --compress \
            --target-dir=/root/db  #生成文件位置
```

### 2.3 传输备份文件到从库

```shell
scp -r /root/db root@192.168.0.113:/root/
```

### 2.4 在从库恢复数据

```bash
cd /root/db && zstd -d *.zst   # 解压（如用zstd压缩）
docker stop mysql8.0
# 准备数据（执行前先确保没数据, /opt/mysql8.0/data 中只有自带MySQL数据 如mysql、sys等）
xtrabackup --prepare --target-dir=/root/db
# 清空数据目录
rm -rf /opt/mysql8.0/data/*
# 恢复数据
xtrabackup --copy-back --target-dir=/root/db --datadir=/opt/mysql8.0/data
# 修改目录权限（MySQL无法启动时 如需要 ）
#chown -R mysql:mysql /opt/mysql8.0/data
docker start mysql8.0
```

---

## 3. 主从同步配置

### 3.1 登录主库MySQL

```sql
-- 创建复制用户
CREATE USER 'replication_user'@'%' IDENTIFIED BY '123456';
-- 授予复制权限
GRANT REPLICATION SLAVE ON *.* TO 'replication_user'@'%';
-- 刷新权限
FLUSH PRIVILEGES;
-- 确保使用 mysql_native_password （兼容性）
ALTER USER 'replication_user'@'%' IDENTIFIED WITH mysql_native_password BY '123456';
FLUSH PRIVILEGES;
-- 查看主库状态（记录File和Position）
SHOW MASTER STATUS; 
-- 查看server-id配置
SHOW VARIABLES LIKE 'server_id';
```

### 3.2 从库配置

```sql
-- 配置主从复制（使用主库show master status获取的值）
CHANGE MASTER TO
  MASTER_HOST='192.168.0.116',
  MASTER_USER='replication_user',
  MASTER_PASSWORD='123456',
  MASTER_LOG_FILE='binlog.000012',   -- 按主库SHOW MASTER STATUS结果填写
  MASTER_LOG_POS=82609;              -- 按主库SHOW MASTER STATUS结果填写

STOP SLAVE;
-- RESET SLAVE; 重置复制
START SLAVE;

-- 查看server-id配置
SHOW VARIABLES LIKE 'server_id';
-- 查看从库状态
SHOW SLAVE STATUS;
-- 在 SHOW SLAVE STATUS\G 输出中关注：[Slave_IO_Running: Yes] [Slave_SQL_Running: Yes] [Seconds_Behind_Master: 0]

-- 查看进程列表
SHOW PROCESSLIST;
-- 查看二进制日志状态
SHOW BINARY LOGS;
```

