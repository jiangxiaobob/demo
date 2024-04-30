#!/bin/bash
# 设置变量
RED='\033[0;31m'
NC='\033[0m'
DATE=$(date +"%Y%m%d")
####DB_USER="root"
####DB_PASS="123456"
####DB_PORT="13306"

source_code_dir="/data/zentao/data/zentao/"
nfs_dir="/mnt/windows_share_data/zentao"
backup_dir=$nfs_dir/$DATE
backup_code_name="$backup_dir/code.tar.gz"
#####backup_data_name="$backup_dir/db.sql"

# 检查NFS共享目录和NFS数据目录是否存在，如果不存在，则停止脚本退出
if [ ! -d "$nfs_dir" ]; then
    if [ ! -d "$nfs_dir" ]; then
        echo -e "${RED}Error: NFS数据目录 $nfs_data_dir 不存在${NC}"
    fi
    exit 1
fi

# 检查并创建NFS备份目录
if [ ! -d "$backup_dir" ] ; then
    echo "备份目录 $backup_dir 不存在，开始创建"
    mkdir $nfs_dir/$DATE
    if [ -d "$backup_dir" ]; then
        echo "备份目录 $backup_dir 创建成功"
    else
        echo -e "${RED}备份目录 $backup_dir 创建失败${NC}"
        exit 1
    fi
fi

# 备份数据库
####mysqldump -h 127.0.0.1 -P $DB_PORT -u $DB_USER -p$DB_PASS --all-databases --single-transaction --routines --triggers --events > "$backup_data_name"
###if [ $? -ne 0 ]; then
###    echo -e "${RED}MySQL数据库备份失败${NC}"
###else 
###    echo "MySQL数据库备份成功"
###fi

# 备份目录文件
tar -czvf "$backup_code_name" --exclude=tmp/backup -C "$source_code_dir" . 
if [ $? -eq 0 ]; then
   echo "目录文件备份打包成功"
else
   echo -e "${RED}备份打包失败${NC}"
fi

# 删除超过7天的备份文件
find $nfs_dir -type d -mtime +7 -exec rm -rf {} \;

echo "执行结束"
