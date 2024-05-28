#!/bin/bash
#目的：本地挂载了nfs共享目录，将所需文件备份到nfs挂载目录且删除源文件，并只保留最近7~8天的，再写入计划任务每天执行
#gitlab每天自动备份一个压缩包到 $source_code_dir 目录，将其同步到 $nfs_dir 目录并删除原来在 $source_code_dir 目录的压缩包。在 $nfs_dir 目录删除创建了7~8天前的压缩包
DATE=$(date +"%Y%m%d")
source_code_dir="/data/gitlab/gitlab-data/backups"
nfs_dir="/mnt/windows_share_data/gitlab"
backup_dir=$nfs_dir/$DATE

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

rsync -av --no-perms --no-owner --no-g --remove-source-files $source_code_dir/*.tar $backup_dir/
#mv $source_code_dir/* $backup_dir/

find $nfs_dir -maxdepth 1 -type d ! -name gitlab -mtime +7 -exec rm -rf {} \;
echo "执行结束"

