pipeline{
    agent any
    //全局变量，会在所有stage中生效
    environment{
        GIT_REPO = 'https://gitlab.ycsoftwares.com/saas/platform/api/admin.git'
        DOCKER_CREDS = credentials('docker')
        NAMESPACE = 'saas'
        GROUP = 'platform'
        PROJECT_TYPE = 'api'
        PROJECT_NAME = 'admin'
        IMAGE_NAME = "$DOCKER_REGISTRY/$NAMESPACE/$GROUP/$PROJECT_NAME-$PROJECT_TYPE"
        TAG = params.TAG.replaceAll(/.*\//, '')
        BUILD_IMAGE = "${env.IMAGE_NAME}:${env.TAG}"
        BUILD_TIME = new Date().format('yyyy-MM-dd HH:mm:ss')

        MYSQL_HOST = '192.168.50.12'
        MYSQL_PORT = '3306'
        MYSQL_USER = 'root'
        MYSQL_PASS = '123456'
        MYSQL_DB = 'saas'

        REDIS_HOST = '192.168.50.12'
        REDIS_PORT = '6379'
        REDIS_PASS = '123456'

    }
    parameters {
        gitParameter(name: 'TAG', defaultValue: 'origin/dev', type: 'PT_BRANCH_TAG', sortMode: 'DESCENDING_SMART', description: '分支或tag')
    }
    stages{
        stage("CheckOut") {
            steps{
                checkout scmGit(
                    branches: [[name: params.TAG]],
                    extensions: [cleanBeforeCheckout()],
                    userRemoteConfigs: [[credentialsId: 'gitlab', url: env.GIT_REPO]]
                )
            } 
        }
        stage("Build"){
            agent {
                docker {
                    image 'golang:1.20'
                    args '-v $JENKINS_HOME/caches/$JOB_NAME:$WORKSPACE/.cache'
                    reuseNode true
                }
                }
            steps{
                sh '''
                GOPATH=${WORKSPACE}/.cache
                go env -w GOPROXY=https://goproxy.cn,direct
                go mod tidy
                CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -a -ldflags '-s -w -extldflags "-static"' -o "${PROJECT_NAME}"
                '''
                println("构建成功")                
            }           
        }
        stage("Package"){
            steps{
                echo '======Package Begin======'
                script {
                    sh """
                    sed -e "s!\\\${PROJECT_NAME}!${PROJECT_NAME}!g" -i Dockerfile
                    docker images | grep -E ${IMAGE_NAME} | awk '{print \$3}' | uniq | xargs -I {} docker rmi --force {}
                    docker build -t ${env.BUILD_IMAGE} .
                    docker login $DOCKER_REGISTRY -u $DOCKER_CREDS_USR -p $DOCKER_CREDS_PSW
                    docker push ${env.BUILD_IMAGE}
                    """
                    if (!params.TAG.contains('origin/')) {
                        withCredentials([usernamePassword(credentialsId:'docker-release', usernameVariable: 'USERNAME', passwordVariable: 'PASSWORD')]) {
                            env.BUILD_IMAGE_RELEASE = env.BUILD_IMAGE.replace("${DOCKER_REGISTRY}", "${DOCKER_REGISTRY_RELEASE}")
                            sh """
                            docker images | grep -E ${IMAGE_NAME} | awk '{print \$3}' | uniq | xargs -I {} docker rmi --force {}
                            docker build -t ${env.BUILD_IMAGE_RELEASE} .
                            docker login $DOCKER_REGISTRY_RELEASE -u $USERNAME -p $PASSWORD
                            docker push ${env.BUILD_IMAGE_RELEASE}
                            """   
                        }
                    }
                }
                echo '======Package End======'
            }
        }
        stage("Deploy"){
            steps{
                echo '======Deploy Begin======'
                //预文件处理
                sh """
                cd devops/k8s
                for file in *.yaml; do
                    sed -e "s!\\\${NAMESPACE}!${NAMESPACE}!g" \
                        -e "s!\\\${GROUP}!${GROUP}!g" \
                        -e "s!\\\${BUILD_IMAGE}!${BUILD_IMAGE}!g" \
                        -e "s!\\\${BUILD_TIME}!${BUILD_TIME}!g" \
                        -e "s!\\\${PROJECT_NAME}!${PROJECT_NAME}!g" \
                        -e "s!\\\${PROJECT_TYPE}!${PROJECT_TYPE}!g" \
                        -e "s!\\\${MYSQL_HOST}!${MYSQL_HOST}!g" \
                        -e "s!\\\${MYSQL_PORT}!${MYSQL_PORT}!g" \
                        -e "s!\\\${MYSQL_USER}!${MYSQL_USER}!g" \
                        -e "s!\\\${MYSQL_PASS}!${MYSQL_PASS}!g" \
                        -e "s!\\\${MYSQL_DB}!${MYSQL_DB}!g" \
                        -e "s!\\\${REDIS_HOST}!${REDIS_HOST}!g" \
                        -e "s!\\\${REDIS_PORT}!${REDIS_PORT}!g" \
                        -e "s!\\\${REDIS_PASS}!${REDIS_PASS}!g" \
                        -i \$file
                    done
                """
                script {
                    // 打包至服务器
                    def depoyPath = "/data/deploy/${JOB_NAME}"
                    sshagent (credentials: ['k8s-agent']) {
                        sh """
                        cd devops
                        cp -rf k8s ${BUILD_NUMBER}
                        tar -czvf ${BUILD_NUMBER}.tar.gz ${BUILD_NUMBER}
                        rm -rf ${BUILD_NUMBER}
                        ssh -o StrictHostKeyChecking=no ${K8S_HOST} mkdir -p ${depoyPath}
                        scp ${BUILD_NUMBER}.tar.gz ${K8S_HOST}:${depoyPath}
                        ssh ${K8S_HOST} "cd ${depoyPath}; tar -xzvf ${BUILD_NUMBER}.tar.gz; cd ${BUILD_NUMBER}; kubectl apply -f ."
                        """
                        }
                    }
                echo '======Deploy End======'              
                }          
            }
        }
    }