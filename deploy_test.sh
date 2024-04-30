#!/bin/bash  

#定义变量
deploy_dir="$1"
job_name="$2"
version_tag="$3"
host_value="$4"

# 检查参数个数
if [ "$#" -eq 3 -o "$#" -eq 4 ]; then
        echo "单个部署模式......"
elif [ $# -eq 2 ]; then
        echo "批量部署模式......"
else
        echo "单个部署模式用法: $0 <项目目录> <Job名称> <镜像TAG> <域名>"
        echo "批量部署模式用法：$0 <项目目录> <批量部署配置文件>"
        echo "说明：批量部署配置文件每行格式：JOB名称 镜像TAG"
       exit 1
fi
 
# 部署应用的函数  
deploy_app() {  
    local deploy_dir=$1  
    local job_name=$2  
    local version_tag=$3  
    local pro_dir="$deploy_dir/$job_name"  
  
    echo "************开始部署************"
#    kubectl apply -f $pro_dir/.
     ls  $pro_dir/.
    echo "************部署完成************"
}  

# 脚本名称和目录  
SCRIPT_NAME=$(basename "$0")  
SCRIPT_DIR=$(dirname "$(realpath "$0")")  

# 从配置文件中读取JOB名称和镜像TAG，并调用deploy_app函数  
if [ "$#" -eq 2 ]; then  
    deploy_dir="$1"
    config_file="$2"  
    
    # 检查配置文件是否存在  
    if [[ ! -f "$config_file" ]]; then  
        echo "错误: 配置文件不存在: $config_file"  
        exit 1
    fi  

    # 初始化计数变量
    count=0

    while IFS= read -r line; do
      job_name=$(echo "$line" | awk '{print $1}')
      version_tag=$(echo "$line" | awk '{print $2}')
      host_value=$(echo "$line" | awk '{print $3}')
      pro_dir="$deploy_dir/$job_name"

      count=$((count + 1))

      # 检查目录是否存在
      if [[ ! -d "$pro_dir" ]]; then
        echo "错误: 目录不存在 $pro_dir"
        exit 1
      fi

      echo "$count.部署应用名:$job_name 镜像TAG:$version_tag Yaml路径:$pro_dir"
      #find "$pro_dir" -type f -exec sed -i -r "s|(image: .+:).+|\1$version_tag|" {} +
      #修改tag
      find "$pro_dir" -type f \( -name "*.yaml" -o -name "*.yml" \) -exec sed -i -r "s|(image: .+:).+|\1$version_tag|" {} +
      #修改host
      if [ -n "$host_value" ]; then
          find "$pro_dir" \( -name "ingress.yaml" -o -name "ingress.yml" \) -exec sed -i -r "s|(\s*host:\s*).*|\\1$host_value|" {} +
      fi
      deploy_app "$deploy_dir" "$job_name" "$version_tag"
    done < "$config_file"  
else  
    # 如果没有提供配置文件，则直接使用命令行参数调用deploy_app函数  
    pro_dir="$deploy_dir/$job_name"
      
    # 检查目录是否存在
    if [[ ! -d "$pro_dir" ]]; then
        echo "错误: 目录不存在 $pro_dir"
        exit 1
    fi

    echo "1.部署应用名:$job_name 镜像TAG:$version_tag Yaml路径:$pro_dir"
    find "$pro_dir" -type f \( -name "*.yaml" -o -name "*.yml" \) -exec sed -i -r "s|(image: .+:).+|\1$version_tag|" {} +
    if [ "$#" -eq 4 ]; then
        find "$pro_dir" \( -name "ingress.yaml" -o -name "ingress.yml" \) -exec sed -i -r "s|(\s*host:\s*).*|\\1$host_value|" {} +
    fi
    deploy_app "$deploy_dir" "$job_name" "$version_tag"
fi
