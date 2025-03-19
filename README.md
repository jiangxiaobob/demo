### 编排ELK容器

1. 安装docker compose 

   ```shell
   #wget https://github.com/docker/compose/releases/download/v2.33.0/docker-compose-linux-x86_64 -O /usr/local/bin/docker-compose
   #chmod +x /usr/local/bin/docker-compose
   #docker-compose version
   ```

2. 创建工作目录，编写compose并启动

   ```shell
   #mkdir elk-single-node && cd elk-single-node
   #mkdir -p es/{config,data,logs,plugins}
   #mkdir -p kibana/{config,data,logs}
   #mkdir -p logstash/{config,pipeline,data,logs}
   #vim docker-compose.yml
   services:
     elasticsearch:
       image: docker.elastic.co/elasticsearch/elasticsearch:8.17.3
       container_name: elasticsearch
       restart: no
       environment:
         - discovery.type=single-node
         - ES_JAVA_OPTS=-Xms4096m -Xmx4096m
         #- xpack.security.enabled=true
         - xpack.security.enrollment.enabled=true
         - ELASTIC_PASSWORD=passwd
       volumes:
         - ./es/data:/usr/share/elasticsearch/data:rw
         - ./es/logs:/usr/share/elasticsearch/logs:rw
         - ./es/config:/usr/share/elasticsearch/config:rw
         - ./es/plugins:/usr/share/elasticsearch/plugins:rw
         - /etc/localtime:/etc/localtime:ro
       ports:
         - 9200:9200
         - 9400:9300
       networks:
         - elk
   
     logstash:
       image: docker.elastic.co/logstash/logstash:8.17.3
       container_name: logstash
       restart: no
       volumes:
         - ./logstash/pipeline:/usr/share/logstash/pipeline:rw
         - ./logstash/config:/usr/share/logstash/config:rw
         - ./logstash/logs:/usr/share/logstash/logs:rw
         - ./logstash/data:/usr/share/logstash/data:rw
         - /etc/localtime:/etc/localtime:ro
       ports:
         - 5044:5044
       environment:
         - LS_JAVA_OPTS=-Xms4096m -Xmx4096m
       depends_on:
         - elasticsearch
       networks:
         - elk
   
     kibana:
       image: docker.elastic.co/kibana/kibana:8.17.3
       container_name: kibana
       restart: no
       ports:
         - 5601:5601
       environment:
         #- ELASTICSEARCH_HOSTS=http://192.168.0.116:9200
         - discovery.type=single-node
       volumes:
         - ./kibana/config:/usr/share/kibana/config:rw
         - ./kibana/data:/usr/share/kibana/data:rw
         - ./kibana/logs:/usr/share/kibana/logs:rw
         - /etc/localtime:/etc/localtime:ro
       depends_on:
         - elasticsearch
       networks:
         - elk
   
   networks:
     elk:
       name: elk
       driver: bridge
   ```

   ```shell
   #docker compose up -d  #启动前暂时注释所有volumes，用于拷贝默认文件
   #docker cp elasticsearch:/usr/share/elasticsearch/config  es/
   #docker cp kibana:/usr/share/kibana/config  kibana/
   #docker cp logstash:/usr/share/logstash/config logstash/
   #docker cp logstash:/usr/share/logstash/pipeline logstash/
   #chmod 777 -R es/*
   #chmod 777 -R kibana/*
   #chmod 777 -R logstash/*
   #docker compose -f docker-compose.yml  stop #停止前 取消之前的vloumes注释再执行此命令
   #docker compose -f docker-compose.yml  rm 
   #docker compose -f docker-compose.yml up -d
   
   ```

### 配置ES和kibana并开启SSL

1. 进入es容器生成CA和证书：elastic-stack-ca.p12和elastic-certificates.p12

   ```shell
   #docker exec -it elasticsearch bash 
   #./bin/elasticsearch-certutil ca  #2次回车可不设密码
   #./bin/elasticsearch-certutil cert --ca elastic-stack-ca.p12 #3次回车可不设密码
   ```

2. 移动证书文件

   ```shell
   #mv elastic-certificates.p12 config/certs/
   #mv elastic-stack-ca.p12 ./config/
   #chmod 777 config/certs/elastic-certificates.p12
   #exit
   #chown linux当前登录用户名或elasticsearch(没有就创建) es/config/elasticsearch.keystore
   #docker exec -it elasticsearch bash 
   #./bin/elasticsearch-keystore add xpack.security.transport.ssl.keystore.secure_password #输入设置的密码
   #./bin/elasticsearch-keystore add xpack.security.transport.ssl.truststore.secure_password #输入设置的密码
   
   ```

3. 配置elasticsearch.yml 

   ```shell
   network.host: 0.0.0.0
   xpack:
     ml.enabled: false
     #monitoring.enabled: false
     security:
       enabled: true
       transport.ssl:
         enabled: true
         verification_mode: certificate
         keystore.path: /usr/share/elasticsearch/config/certs/elastic-certificates.p12   
         truststore.path: /usr/share/elasticsearch/config/certs/elastic-certificates.p12 
     watcher.enabled: false
   ```

4. 为证书文件设置权限并重启ES容器

   ```shell
   #chmod 777 config/certs/elastic-certificates.p12  
   #exit 
   #docker restart elasticsearch
   ```

5. 进入es容器生成生成HTTP证书并解压：elasticsearch-ssl-http.zip

   ```shell
   #docker exec -it elasticsearch bash 
   #./bin/elasticsearch-certutil http 
   #生成CSR：n  #是否使用存在的ca：y 
   #输入ca文件的地址：/usr/share/elasticsearch/config/elastic-stack-ca.p12
   #输入文件设置的密码:? #设置过期时间：5y #是否为每一个节点生成证书：n
   #设置为节点的hostname： elasticsearch #是否配置正确：y #节点的ip:? #配置是否正确：y
   #是否更改：n #输入生成文件的密码:? #再次输入:? #生成压缩文件的地址和名称：回车
   #mv elasticsearch-ssl-http.zip ./config/
   #unzip config/elasticsearch-ssl-http.zip
   #mv elasticsearch/http.p12 ./config/certs/
   #./bin/elasticsearch-keystore add xpack.security.http.ssl.keystore.secure_password
   ```

6. 为HTTP证书设置权限并重启ES容器：

   ```shell
   #chmod 777 config/certs/http.p12 
   #exit 
   #docker restart elasticsearch
   ```

7. 进入es容器设置elastic用户密码

   ```shell
   #docker exec -it elasticsearch bash
   #./bin/elasticsearch-reset-password -u elastic -i
   #执行后可能会报错:ERROR: Failed to determine the health of the cluster.等待一分钟再尝试
   ```

8. 验证https访问es：浏览器访问验证，提示用户密码即是上一步操作的elastic、passwd

9. 复制CA证书到Kibana配置目录：
   第5步生成的压缩包内kibana文件夹下elasticsearch-ca.pem到kibana的配置文件夹内

   ```shell
   #docker cp elasticsearch:/usr/share/elasticsearch/kibana/elasticsearch-ca.pem /tmp
   #docker cp /tmp/elasticsearch-ca.pem kibana:/usr/share/kibana/config/
   ```

10. 进入es容器配置kibana_system用户的密码

    ```shell
    #docker exec -it elasticsearch bash  
    #./bin/elasticsearch-reset-password -u kibana_system -i
    ```

11. 生成Kibana的SSL证书：kibana用https访问的公钥和私钥

    ```shell
    #./bin/elasticsearch-certutil csr -name kibana-server
    # unzip csr-bundle.zip #会解压出kibana-server目录以及它的csr、key
    ```

12. 将kibana-server.csr和kibana-server.key两个文件拷贝到kibana配置文件夹内

    ```shell
    #docker cp elasticsearch:/usr/share/elasticsearch/kibana-server/kibana-server.csr /tmp
    #docker cp elasticsearch:/usr/share/elasticsearch/kibana-server/kibana-server.key /tmp
    #docker cp /tmp/kibana-server.csr kibana:/usr/share/kibana/config/
    #docker cp /tmp/kibana-server.key kibana:/usr/share/kibana/config/
    ```

13. 执行下列命令，生成Kibana的CRT文件

    ```shell
    #docker exec -it kibana bash
    #openssl  x509 -req -days 3650 -in config/kibana-server.csr -signkey config/kibana-server.key -out config/kibana-server.crt
    ```

14. 配置kibana.yml文件

    ```shell
    server.host: "0.0.0.0"
    server.shutdownTimeout: "5s"
    elasticsearch.hosts: ["https://elasticsearch:9200"]
    monitoring.ui.container.elasticsearch.enabled: true
    elasticsearch.ssl.certificateAuthorities: ["/usr/share/kibana/config/elasticsearch-ca.pem"]
    #elasticsearch.ssl.verificationMode: "certificate"  
    elasticsearch.username: "kibana_system"
    elasticsearch.password: "passwd"
    
    server.ssl.enabled: true
    server.ssl.certificate: "/usr/share/kibana/config/kibana-server.crt"
    server.ssl.key: "/usr/share/kibana/config/kibana-server.key"
    
    i18n.locale: "zh-CN"
    ```

15. 设置文件权限并重启Kibana容器

    ```shell
    #docker exec -u root -it kibana bash
    #chmod 777 config/elasticsearch-ca.pem 
    #chmod 777 config/kibana-server.csr
    #chmod 777 config/kibana-server.key 
    #chmod 777 config/kibana-server.crt
    #exit
    #docker restart kibana
    ```

16. 浏览器访问kibana控制台验证，帐号为elastic 密码为刚设置的密码

17. 配置Kibana的Encrypted Saved Objects插件的加密密钥

    ```shell
    #docker exec -it kibana bash
    #./bin/kibana-encryption-keys generate 执行后最后一部分信息输出，将其复制到yml文件
    Settings:
    xpack.encryptedSavedObjects.encryptionKey: 4265914dafab37660135cfe0e6a0964b
    xpack.reporting.encryptionKey: 0d5634b32c5bee96c695f85f6dc1f5db
    xpack.security.encryptionKey: 6e0e100186d617c2bf5423bc2a585b8a
    #exit
    #vim /elk-single-node/kibana/config/kibana.yml #追加到底部
    xpack.encryptedSavedObjects.encryptionKey: "4265914dafab37660135cfe0e6a0964b"
    xpack.reporting.encryptionKey: "0d5634b32c5bee96c695f85f6dc1f5db"
    xpack.security.encryptionKey: "6e0e100186d617c2bf5423bc2a585b8a"
    #docker restart kibana 
    ```


### 配置logstash

1. 进入es容器 配置elasticsearch内置用户logstash_system密码

   ```shell
   #docker exec -it elasticsearch bash  
   #./bin/elasticsearch-reset-password -u logstash_system -i
   ```

2. 生成Logstash的SSL证书:  logstash和elasticsearch之间的安全认证文件

   ```shell
   #docker exec -it elasticsearch bash 
   #openssl pkcs12 -in config/certs/elastic-certificates.p12 -cacerts -nokeys -chain  -out config/logstash.pem
   ```

3. 复制证书文件到Logstash配置目录并赋予权限

   ```shell
   #docker cp elasticsearch:/usr/share/elasticsearch/config/logstash.pem /tmp
   #docker cp /tmp/logstash.pem logstash:/usr/share/logstash/config/
   #docker exec -u root -it logstash bash 
   #chmod 777 config/logstash.pem
   #exit
   ```

4. 配置logstash.yml文件

   ```shell
   http.host: "0.0.0.0"
   
   xpack.monitoring.enabled: true
   xpack.monitoring.elasticsearch.username: logstash_system
   xpack.monitoring.elasticsearch.password: passwd
   
   #这里必须用 https 
   xpack.monitoring.elasticsearch.hosts: [ "https://elasticsearch:9200" ]
   #你的ca.pem 的所在路径
   xpack.monitoring.elasticsearch.ssl.certificate_authority: "/usr/share/logstash/config/logstash.pem"
   xpack.monitoring.elasticsearch.ssl.verification_mode: certificate
   
   探嗅 es节点，设置为 false
   
   xpack.monitoring.elasticsearch.sniffing: false
   ```

5. 使用kabina配置一个新的elasticsearch用户给logstash使用

6. 配置logstash.conf文件并重启logstash容器

   ```shell
   input {
       beats {
           port => 5044
           codec => json {
               charset => "UTF-8"
           }
       }
   
   }
   
   filter {
       #过滤器配置
   
   }
   
   output {
       elasticsearch {
         hosts => ["https://elasticsearch:9200"]
         index => "demo-%{+YYYY.MM.dd}"
         user => "elastic"
         password => "passwd"
         ssl_enabled => true
         ssl_certificate_authorities => ["/usr/share/logstash/config/logstash.pem"]
     }
     stdout {
       codec => rubydebug
     }
   }
   ```

   ```
   #docker restart logstash
   ```

7. 检测elk连通性

   ```shell
   #docker exec -it logstash curl --cacert /usr/share/logstash/config/logstash.pem -u elastic:passwd https://172.20.0.2:9200
   #docker exec -it kibana curl --cacert /usr/share/kibana/config/elasticsearch-ca.pem -u elastic:passwd https://172.20.0.2:9200
   ```

### 配置filebeat

1. 创建工作目录

   ```shell
   #mkdir -p filebeat/{config,data,logs} && cd filebeat
   #cat <<EOF >compose.yml
   services:
     filebeat:
       image: docker.elastic.co/beats/filebeat:8.17.3
       container_name: filebeat
       restart: no
       volumes:
         - ./filebeat.yml:/usr/share/filebeat/filebeat.yml:ro
         - ./config:/usr/share/filebeat/config
         - ./data:/usr/share/filebeat/data:rw
         - ./logs:/usr/share/filebeat/logs
         - /var/lib/docker/containers:/var/lib/docker/containers:ro
         - /var/run/docker.sock:/var/run/docker.sock:ro
         - /app/logs:/app/logs
   
       networks:
         - elk
   
   networks:
       elk:
         external: true
   EOF
   
   ```

2. 配置编辑 yml文件

   ```
   filebeat.inputs:
   - type: container
     enabled: true
     paths: "/var/lib/docker/containers/123xxxx123xxx-json.log"      #docker容器日志的路径，可写可不写
     ids:
       - "*"    #收集所有容器日志，单个就写单个id
     fields:
       source_type: "docker_container"
   
   - type: log
     enabled: true
     paths:
       - /app/logs/*/*.log 
     fields:
       source_type: "app_log"
       project: ms
       app: appx
   
   setup.ilm.enabled: false
   setup.template:
     name: "ms-appx"
     pattern: "ms-appx-*"  # 通配符匹配动态索引
   
   output.elasticsearch:
     hosts: ["https://172.20.0.2:9200"]
     index: "ms-appx-%{+yyyy.MM.dd}"
     username: "elastic"
     password: "passwd"
     ssl:
       certificate_authorities: ["/usr/share/filebeat/config/elasticsearch-ca.pem"]
       verification_mode: "none"
   max_procs: 1 #限制filebeat只使用一个 CPU 核心来处理事件或日志
   ```

3. 配置ca证书连接

   ```shell
   #docker cp elasticsearch:/usr/share/elasticsearch/kibana/elasticsearch-ca.pem /tmp
   #docker cp /tmp/elasticsearch-ca.pem filebeat:/usr/share/filebeat/config
   #docker-compose up -d
   ```

4. 检测filebeat与es连通性

   ```shell
   #docker exec -it filebeat curl --cacert /usr/share/filebeat/config/elasticsearch-ca.pem -u elastic:passwd https://172.20.0.2:9200
   ```

   
