#!/bin/bash

set -e
export PATH="$HOME/.local/bin:$PATH"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

error_exit() {
    echo -e "${RED}错误: $1${NC}" >&2
    exit 1
}

log() {
    echo -e "${GREEN}▸${NC} $1"
}

[ ! -f config.yaml ] && error_exit "找不到配置文件"

if ! command -v yq &> /dev/null; then
    if command -v wget &> /dev/null; then
        wget -qO /tmp/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 2>&1 | grep -v "^$" || true
    else
        curl -sL https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /tmp/yq 2>&1 | grep -v "^$" || true
    fi
    chmod +x /tmp/yq
    sudo mv /tmp/yq /usr/local/bin/yq || mv /tmp/yq ~/.local/bin/yq
fi

SERVER_IP=$(curl -s ip.sb)
[ -z "$SERVER_IP" ] && SERVER_IP=$(hostname -I | awk '{print $1}')
[ -z "$SERVER_IP" ] && SERVER_IP="localhost"

DB_HOST="localhost"
DB_PORT="5432"
DB_NAME="antihub_db"
DB_USER="antihub_db"
DB_PASSWORD=$(openssl rand -hex 16)

PLUGIN_DB_HOST="localhost"
PLUGIN_DB_PORT="5432"
PLUGIN_DB_NAME="antigv_plugin_db"
PLUGIN_DB_USER="antigv_plugin_db"
PLUGIN_DB_PASSWORD=$(openssl rand -hex 16)

BACKEND_PORT=$(yq eval '.backend.port' config.yaml)
JWT_SECRET=$(yq eval '.backend.jwt_secret' config.yaml)
OAUTH_CLIENT_ID=$(yq eval '.backend.oauth_client_id' config.yaml)
OAUTH_CLIENT_SECRET=$(yq eval '.backend.oauth_client_secret' config.yaml)
OAUTH_REDIRECT_URI=$(yq eval '.backend.oauth_redirect_uri' config.yaml | sed "s/localhost/$SERVER_IP/g")
GITHUB_CLIENT_ID=$(yq eval '.backend.github_client_id' config.yaml)
GITHUB_CLIENT_SECRET=$(yq eval '.backend.github_client_secret' config.yaml)
GITHUB_REDIRECT_URI=$(yq eval '.backend.github_redirect_uri' config.yaml | sed "s/localhost/$SERVER_IP/g")

PLUGIN_PORT=$(yq eval '.plugin.port' config.yaml)
PLUGIN_HOST=$(yq eval '.plugin.host' config.yaml)
PLUGIN_ADMIN_KEY=$(yq eval '.plugin.admin_api_key' config.yaml)
PLUGIN_ENCRYPTION_KEY=$(yq eval '.plugin.encryption_key' config.yaml)

FRONTEND_PORT=$(yq eval '.frontend.port' config.yaml)
FRONTEND_API_URL=$(yq eval '.frontend.api_url' config.yaml | sed "s/localhost/$SERVER_IP/g")
FRONTEND_URL=$(yq eval '.frontend.frontend_url' config.yaml | sed "s/localhost/$SERVER_IP/g")

REDIS_URL=$(yq eval '.redis.url' config.yaml)

[[ "$OSTYPE" != "linux-gnu"* ]] && error_exit "不支持的系统类型: $OSTYPE"

if command -v apt-get &> /dev/null; then
    PKG_MGR="apt"
elif command -v yum &> /dev/null; then
    PKG_MGR="yum"
elif command -v dnf &> /dev/null; then
    PKG_MGR="dnf"
elif command -v pacman &> /dev/null; then
    PKG_MGR="pacman"
else
    error_exit "不支持的包管理器"
fi

PACKAGES=()
! command -v curl &> /dev/null && ! command -v wget &> /dev/null && PACKAGES+=("curl")
! command -v git &> /dev/null && PACKAGES+=("git")
! command -v psql &> /dev/null && PACKAGES+=("postgresql")
! command -v redis-server &> /dev/null && PACKAGES+=("redis")

if [ ${#PACKAGES[@]} -gt 0 ]; then
    case $PKG_MGR in
        apt)
            sudo apt-get update -qq
            sudo apt-get install -y ${PACKAGES[@]} postgresql-contrib
            ;;
        yum)
            sudo yum install -y ${PACKAGES[@]} postgresql-server postgresql-contrib
            [ ! -f /var/lib/pgsql/data/PG_VERSION ] && sudo postgresql-setup --initdb
            ;;
        dnf)
            sudo dnf install -y ${PACKAGES[@]} postgresql-server postgresql-contrib
            [ ! -f /var/lib/pgsql/data/PG_VERSION ] && sudo postgresql-setup --initdb
            ;;
        pacman)
            sudo pacman -S --noconfirm ${PACKAGES[@]}
            [ ! -d /var/lib/postgres/data/base ] && sudo -u postgres initdb -D /var/lib/postgres/data
            ;;
    esac
fi

if command -v psql &> /dev/null; then
    sudo systemctl is-active --quiet postgresql || sudo systemctl start postgresql
    sudo systemctl is-enabled --quiet postgresql || sudo systemctl enable postgresql 2>/dev/null || true
fi

if command -v redis-server &> /dev/null; then
    sudo systemctl is-active --quiet redis-server || sudo systemctl start redis-server
    sudo systemctl is-enabled --quiet redis-server || sudo systemctl enable redis-server 2>/dev/null || true
fi

if ! command -v node &> /dev/null; then
    case $PKG_MGR in
        apt)
            curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
            sudo apt-get install -y nodejs
            ;;
        yum|dnf)
            curl -fsSL https://rpm.nodesource.com/setup_lts.x | sudo bash -
            sudo $PKG_MGR install -y nodejs
            ;;
        pacman)
            sudo pacman -S --noconfirm nodejs npm
            ;;
    esac
fi

NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
[ "$NODE_VERSION" -lt 18 ] && error_exit "需要 Node.js >= 18.0.0"

if ! command -v uv &> /dev/null; then
    (command -v curl &> /dev/null && curl -LsSf https://astral.sh/uv/install.sh || wget -qO- https://astral.sh/uv/install.sh) | sh
    export PATH="$HOME/.local/bin:$PATH"
fi

NPM_PACKAGES=()
! command -v pnpm &> /dev/null && NPM_PACKAGES+=("pnpm")
! command -v pm2 &> /dev/null && NPM_PACKAGES+=("pm2")
[ ${#NPM_PACKAGES[@]} -gt 0 ] && log "安装Package: ${NPM_PACKAGES[*]}" && npm install -g ${NPM_PACKAGES[@]}

[ ! -d "AntiHub" ] && git clone -q https://github.com/AntiHub-Project/AntiHub.git
[ ! -d "Backend" ] && git clone -q https://github.com/AntiHub-Project/Backend.git
[ ! -d "Antigv-plugin" ] && git clone -q https://github.com/AntiHub-Project/Antigv-plugin.git

sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname = '$DB_NAME'" | grep -q 1 || \
    sudo -u postgres psql -c "CREATE DATABASE $DB_NAME;"

sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname = '$DB_USER'" | grep -q 1 || \
    sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';"

sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;"

sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname = '$PLUGIN_DB_NAME'" | grep -q 1 || \
    sudo -u postgres psql -c "CREATE DATABASE $PLUGIN_DB_NAME;"

sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname = '$PLUGIN_DB_USER'" | grep -q 1 || \
    sudo -u postgres psql -c "CREATE USER $PLUGIN_DB_USER WITH PASSWORD '$PLUGIN_DB_PASSWORD';"

sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $PLUGIN_DB_NAME TO $PLUGIN_DB_USER;"

PG_HBA=$(sudo -u postgres psql -t -c "SHOW hba_file;" | xargs)
if [ -f "$PG_HBA" ]; then
    grep -q "host.*$DB_NAME.*$DB_USER.*md5" "$PG_HBA" || \
        echo "host    $DB_NAME    $DB_USER    127.0.0.1/32    md5" | sudo tee -a "$PG_HBA"
    grep -q "host.*$PLUGIN_DB_NAME.*$PLUGIN_DB_USER.*md5" "$PG_HBA" || \
        echo "host    $PLUGIN_DB_NAME    $PLUGIN_DB_USER    127.0.0.1/32    md5" | sudo tee -a "$PG_HBA"
    sudo systemctl reload postgresql
fi

cd Antigv-plugin

[ "$PLUGIN_ADMIN_KEY" == "auto_generate" ] || [ -z "$PLUGIN_ADMIN_KEY" ] && PLUGIN_ADMIN_KEY="sk-admin-$(openssl rand -hex 32)"
cat > config.json <<EOF
{
  "server": {
    "port": $PLUGIN_PORT,
    "host": "$PLUGIN_HOST"
  },
  "oauth": {
    "callbackUrl": "http://localhost:42532/oauth-callback"
  },
  "database": {
    "host": "$PLUGIN_DB_HOST",
    "port": $PLUGIN_DB_PORT,
    "database": "$PLUGIN_DB_NAME",
    "user": "$PLUGIN_DB_USER",
    "password": "$PLUGIN_DB_PASSWORD",
    "max": 20,
    "idleTimeoutMillis": 30000,
    "connectionTimeoutMillis": 2000
  },
  "api": {
    "url": "https://daily-cloudcode-pa.sandbox.googleapis.com/v1internal:streamGenerateContent?alt=sse",
    "modelsUrl": "https://daily-cloudcode-pa.sandbox.googleapis.com/v1internal:fetchAvailableModels",
    "host": "daily-cloudcode-pa.sandbox.googleapis.com",
    "userAgent": "antigravity/1.11.3 windows/amd64"
  },
  "defaults": {
    "temperature": 1,
    "top_p": 0.85,
    "top_k": 50,
    "max_tokens": 8096
  },
  "security": {
    "maxRequestSize": "50mb",
    "adminApiKey": "$PLUGIN_ADMIN_KEY"
  },
  "systemInstruction": ""
}
EOF

npm install

[ -f schema.sql ] && PGPASSWORD=$PLUGIN_DB_PASSWORD psql -h $PLUGIN_DB_HOST -p $PLUGIN_DB_PORT -U $PLUGIN_DB_USER -d $PLUGIN_DB_NAME -f schema.sql || true

pm2 delete antigv-plugin || true
pm2 start src/server/index.js --name antigv-plugin
pm2 save

cd ../Backend

[ "$JWT_SECRET" == "auto_generate" ] || [ -z "$JWT_SECRET" ] && JWT_SECRET=$(openssl rand -hex 32)

if [ "$PLUGIN_ENCRYPTION_KEY" == "auto_generate" ] || [ -z "$PLUGIN_ENCRYPTION_KEY" ]; then
    uv sync
    PLUGIN_ENCRYPTION_KEY=$(uv run python generate_encryption_key.py | grep -v "^$" | grep -v "请将以下" | tail -n 1)
fi
cat > .env <<EOF
# Application Configuration
APP_ENV=production
LOG_LEVEL=INFO

# Database Configuration
DATABASE_URL=postgresql+asyncpg://$DB_USER:$DB_PASSWORD@$DB_HOST:$DB_PORT/$DB_NAME

# Redis Configuration
REDIS_URL=$REDIS_URL

# JWT Configuration
JWT_SECRET_KEY=$JWT_SECRET
JWT_ALGORITHM=HS256
JWT_EXPIRE_HOURS=24

# Linux.do OAuth Configuration
OAUTH_CLIENT_ID=$OAUTH_CLIENT_ID
OAUTH_CLIENT_SECRET=$OAUTH_CLIENT_SECRET
OAUTH_REDIRECT_URI=$OAUTH_REDIRECT_URI
OAUTH_AUTHORIZATION_ENDPOINT=https://connect.linux.do/oauth2/authorize
OAUTH_TOKEN_ENDPOINT=https://connect.linux.do/oauth2/token
OAUTH_USER_INFO_ENDPOINT=https://connect.linux.do/api/user

# GitHub OAuth Configuration
GITHUB_CLIENT_ID=$GITHUB_CLIENT_ID
GITHUB_CLIENT_SECRET=$GITHUB_CLIENT_SECRET
GITHUB_REDIRECT_URI=$GITHUB_REDIRECT_URI

# Plug-in API Configuration
PLUGIN_API_BASE_URL=http://$PLUGIN_HOST:$PLUGIN_PORT
PLUGIN_API_ADMIN_KEY=$PLUGIN_ADMIN_KEY
PLUGIN_API_ENCRYPTION_KEY=$PLUGIN_ENCRYPTION_KEY
EOF

uv sync

uv run alembic upgrade head || error_exit "数据库迁移失败"

pm2 delete antihub-backend || true
pm2 start "uv run uvicorn app.main:app --host 0.0.0.0 --port $BACKEND_PORT" --name antihub-backend
pm2 save

cd ../AntiHub

cat > .env <<EOF
NEXT_PUBLIC_API_URL=$FRONTEND_API_URL
NEXT_PUBLIC_FRONTEND_URL=$FRONTEND_URL
EOF

pnpm install

pnpm run build || error_exit "前端构建失败"

cat > ecosystem.config.js <<EOF
module.exports = {
  apps: [{
    name: 'antihub-frontend',
    script: 'node_modules/.bin/next',
    args: 'start',
    cwd: '$(pwd)',
    instances: 1,
    autorestart: true,
    watch: false,
    max_memory_restart: '1G',
    env: {
      NODE_ENV: 'production',
      PORT: $FRONTEND_PORT
    },
    error_file: 'logs/pm2-error.log',
    out_file: 'logs/pm2-out.log',
    log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
    merge_logs: true
  }]
};
EOF

mkdir -p logs

pm2 delete antihub-frontend || true
pm2 start ecosystem.config.js
pm2 save

cd ..

command -v systemctl &>/dev/null && pm2 startup systemd -u $(whoami) --hp $(eval echo ~$(whoami)) || true

echo ""
log "部署完成"
echo ""
echo "后端: http://$SERVER_IP:$BACKEND_PORT"
echo "前端: http://$SERVER_IP:$FRONTEND_PORT"
echo ""
pm2 status
echo ""