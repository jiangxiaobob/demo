#!/bin/bash
# 设置变量
RED='\033[0;31m'
NC='\033[0m'
DATE=$(date +"%Y-%m-%d")
DB_USER="root"
DB_PASS=$(grep '^\s*- MYSQL_ROOT_PASSWORD=' /data/xinhuoa/docker-compose.yaml | cut -d'=' -f2)
DB_PORT=$(grep '^\s*ports:' /data/xinhuoa/docker-compose.yaml -A 4 | grep '^\s*- 3306:' | cut -d':' -f1 | awk '{print $2}')

source_file_dir="/data/xinhuoa/xinhu"
#source_data_dir="/data/xinhuoa/mysql/data"
nfs_file_dir="/mnt/windows_share_file/xinhu"
nfs_data_dir="/mnt/windows_share_data/xinhu"

backup_file_name="oa_file_backup_$DATE.tar.gz"
#backup_data_name="oa_data_backup_$DATE.tar.gz"
backup_sql="$nfs_data_dir/oa_data_backup_$DATE.sql"

# 检查NFS共享目录和NFS数据目录是否存在，如果不存在，则停止脚本退出
if [ ! -d "$nfs_file_dir" ] || [ ! -d "$nfs_data_dir" ]; then
    if [ ! -d "$nfs_file_dir" ]; then
        echo -e "${RED}Error: NFS共享目录 $nfs_file_dir 不存在${NC}"
    fi
    if [ ! -d "$nfs_data_dir" ]; then
        echo -e "${RED}Error: NFS数据目录 $nfs_data_dir 不存在${NC}"
    fi
    exit 1
fi

# 备份数据库
mysqldump -h 127.0.0.1 -P $DB_PORT -u $DB_USER -p$DB_PASS --all-databases --single-transaction --routines --triggers --events > "$backup_sql"
if [ $? -ne 0 ]; then
    echo -e "${RED}MySQL数据库备份失败${NC}"
else 
    echo "MySQL数据库备份成功"
fi

# 备份目录文件
tar -czvf "$nfs_file_dir/$backup_file_name" -C "$source_file_dir" . 
#tar -czvf "$nfs_data_dir/$backup_data_name" -C "$source_data_dir" .
if [ $? -eq 0 ]; then
   echo "目录文件备份打包成功"
else
   echo -e "${RED}备份打包失败${NC}"
fi


# 删除超过7天的备份文件
find $nfs_file_dir -name "oa_file_backup*" -mtime +7 -exec rm -rf {} \;
find $nfs_data_dir -name "oa_data_backup*" -mtime +7 -exec rm -rf {} \;

echo "执行结束"
