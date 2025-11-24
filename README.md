# AntiHub 自部署说明

### 声明

> 本项目设计之初的目标就是多人账号共享平台, 因此并不适合个人本地使用. 如果您的需求仅仅只是将您的账号进行2api使用, 那么我们建议您直接登录我们的公共平台 [AntiHub](https://antihub.mortis.edu.kg/dashboard) 创建您自己的专属账号即可, 专属账号只有您本人创建的 API Key 能访问, 使用效果和自部署一致. 只有您不信任我们的公共平台, 或您有修改本项目源代码实现您自己的需求时, 我们才建议您继续操作. 

> 下面所有操作都是在服务器上完成的, 请不要使用国内服务器, 否则会无法访问. 一键脚本默认单机部署, 如果要进行多机分开部署, 请自行完成相关部分. 

### 快速开始

请找一台全新安装的服务器, 登录后克隆仓库: 

请至少使用4核心以上的服务器进行部署, 否则编译前端代码可能会导致服务器宕机. 

```bash
git clone https://github.com/AntiHub-Project/scripts.git && cd scripts
```

### Linux.do 登录配置

> 请务必提前完成反向代理及及SSL配置，并将下面的 `http://$SERVER_IP:$PORT` 都替换为 `https://你的域名`.

- 登录 [Linux.do Connect](https://connect.linux.do/dash/sso), 点击 `申请新接入` , 填入应用名, 应用主页 (http://$SERVER_IP:3000), 应用描述及回调地址 ( http://$SERVER_IP:3000/api/auth/callback), 点击保存. 

- 得到一个 `Client Id` 和 `Client Secret` , 将这两个值填入 `config.yaml` 中的此处：
```yaml
# Linux.do OAuth
oauth_client_id: your-oauth-client-id 
oauth_client_secret: your-oauth-client-secret
```

### Github 登录配置

- 登录 [Github](https://github.com/settings/applications/new), 填入`Application name`, `Homepage URL`( http://$SERVER_IP:3000 ), `Authorization callback URL`(  http://$SERVER_IP:3000/api/auth/github/callback ), 点击`Register application`.

- 你会在新的页面看到一个 `Client ID` , 复制它下面的值; 然后点击 `Generate a new client secret` , 复制得到的 `Client Secret` , 将得到的这两个值填入 `config.yaml` 中的此处:

```yaml
# GitHub OAuth
github_client_id: your-github-client-id
github_client_secret: your-github-client-secret
```

### 部署
```bash
chmod +x deploy.sh && ./deploy.sh
```

部署完成如果你无法访问面板, 请转到云厂商处将对应端口打开. 本说明文档已经足够详细, 如果仍有问题, 请善用AI. 

后续如果修改前端代码或配置, 均需要重新编译, 然后到pm2重启服务; 后端和插件亦是如此, 但只需重启服务即可. 