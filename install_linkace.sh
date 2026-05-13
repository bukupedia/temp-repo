#!/bin/bash

#############################################################################
# LinkAce Docker Installation Script
# Target: Ubuntu 20.04
# Production Environment
# Domain: linkace.arifbudiman.web.id
#############################################################################

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
LINKACE_DOMAIN="linkace.arifbudiman.web.id"
APP_DIR="/opt/linkace"
LINKACE_VERSION="latest"
# Generate secure passwords
DB_PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
REDIS_PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
APP_KEY=$(openssl rand -base64 32)

# Log functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_error "Please run this script as root (use sudo)"
    exit 1
fi

# Pre-flight checks
log_info "Running pre-flight checks..."

# Check Docker
if ! command -v docker &> /dev/null; then
    log_error "Docker is not installed. Please install Docker first."
    exit 1
fi

# Check Docker Compose
if ! command -v docker-compose &> /dev/null; then
    log_warn "Docker Compose not found. Installing..."
    apt-get update
    apt-get install -y docker-compose
fi

# Check if Docker daemon is running
if ! docker ps &> /dev/null; then
    log_warn "Docker daemon is not running. Starting..."
    dockerd > /tmp/docker.log 2>&1 &
    sleep 5
fi

log_info "Pre-flight checks complete."

# Create application directory
log_info "Creating application directory: $APP_DIR"
mkdir -p "$APP_DIR"
cd "$APP_DIR"

# Download LinkAce Docker setup files
log_info "Downloading LinkAce Docker setup package..."

# Try to download from official source, fallback to creating from template
if command -v curl &> /dev/null; then
    DOWNLOAD_CMD="curl -L -o"
elif command -v wget &> /dev/null; then
    DOWNLOAD_CMD="wget -O"
else
    log_error "Neither curl nor wget is installed"
    exit 1
fi

# Download docker-compose.yml from LinkAce repository
$DOWNLOAD_CMD docker-compose.yml \
    "https://raw.githubusercontent.com/linkace/linkace-docker/main/docker-compose.yml" 2>/dev/null || {
    log_warn "Could not download from official repo. Creating from template..."
}

# If download failed, create docker-compose.yml
if [ ! -f docker-compose.yml ]; then
    log_info "Creating docker-compose.yml..."
    cat > docker-compose.yml << 'DOCKEREOF'
version: '3.8'

services:
  app:
    image: linkace/linkace:${LINKACE_VERSION:-latest}
    container_name: linkace_app_1
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy
    environment:
      - APP_ENV=production
      - LOG_CHANNEL=daily
    volumes:
      - ./docker/linkace/.env:/app/.env:ro
      - ./docker/linkace/letsencrypt:/app/letsencrypt
      - linkace-docker:/app/docker
    networks:
      - linkace-network
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.linkace.rule=Host(`${LINKACE_DOMAIN}`)"
      - "traefik.http.routers.linkace.entrypoints=websecure"
      - "traefik.http.routers.linkace.tls.certresolver=letsencrypt"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

  db:
    image: mysql:8.0
    container_name: linkace_db_1
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: ${DB_PASSWORD}
      MYSQL_DATABASE: linkace
      MYSQL_USER: linkace
      MYSQL_PASSWORD: ${DB_PASSWORD}
    volumes:
      - linkace-mysql:/var/lib/mysql
    networks:
      - linkace-network
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-u", "root", "-p${DB_PASSWORD}"]
      interval: 30s
      timeout: 10s
      retries: 3

  redis:
    image: redis:7-alpine
    container_name: linkace_redis_1
    restart: unless-stopped
    command: redis-server --requirepass ${REDIS_PASSWORD} --appendonly yes
    volumes:
      - linkace-redis:/data
    networks:
      - linkace-network
    healthcheck:
      test: ["CMD", "redis-cli", "--no-auth-warning", "-a", "${REDIS_PASSWORD}", "ping"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  linkace-network:
    driver: bridge

volumes:
  linkace-docker:
  linkace-mysql:
  linkace-redis:
DOCKEREOF
fi

# Check if .env file exists, if not create from template or download
log_info "Setting up environment configuration..."

if [ ! -f .env ]; then
    # Try to download .env.example from repository
    $DOWNLOAD_CMD .env.example \
        "https://raw.githubusercontent.com/linkace/linkace-docker/main/.env.example" 2>/dev/null || {
        log_info "Creating .env from template..."
    }
    
    if [ -f .env.example ]; then
        cp .env.example .env
    else
        # Create .env file from scratch
        cat > .env << EOF
# Application
APP_KEY=${APP_KEY}
APP_URL=https://${LINKACE_DOMAIN}
APP_ENV=production

# Database
DB_CONNECTION=mysql
DB_HOST=db
DB_PORT=3306
DB_DATABASE=linkace
DB_USERNAME=linkace
DB_PASSWORD=${DB_PASSWORD}

# Redis
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=${REDIS_PASSWORD}

# Mail Configuration
MAIL_MAILER=smtp
MAIL_HOST=smtp.mailtrap.io
MAIL_PORT=2525
MAIL_USERNAME=null
MAIL_PASSWORD=null
MAIL_ENCRYPTION=tls
MAIL_FROM_ADDRESS=noreply@${LINKACE_DOMAIN}
MAIL_FROM_NAME="${LINKACE_DOMAIN}"

# Session & Cache
SESSION_DRIVER=redis
CACHE_DRIVER=redis

# Log
LOG_CHANNEL=daily
LOG_LEVEL=warning

# Queue
QUEUE_CONNECTION=redis

# Horizon (for queue monitoring in production)
HORIZON_PRODUCTION=true
EOF
    fi
fi

# Make .env writable for setup (will secure it after)
log_info "Making .env writable for setup..."
chmod 666 .env 2>/dev/null || true

# Start the containers
log_info "Starting LinkAce containers..."
docker-compose up -d

# Wait for containers to be ready
log_info "Waiting for containers to initialize..."
sleep 30

# Check if containers are running
log_info "Verifying containers are running..."
docker-compose ps

# Check logs for errors
docker-compose logs --tail=50 | grep -i error || log_warn "No errors found in logs"

# Get container ID for setup
APP_CONTAINER=$(docker-compose ps -q app)

if [ -z "$APP_CONTAINER" ]; then
    log_error "App container is not running. Check logs with: docker-compose logs"
    exit 1
fi

# Run database migrations
log_info "Running database migrations..."
docker exec -it $APP_CONTAINER php artisan migrate --force || {
    log_warn "Migration may have already been run or needs manual intervention"
}

# Complete setup
log_info "Completing setup..."
docker exec -it $APP_CONTAINER php artisan setup:complete || {
    log_warn "Setup may need manual completion"
}

# Generate the application key if not set
log_info "Generating application key if needed..."
docker exec -it $APP_CONTAINER php artisan key:generate --force || true

# Create storage links
log_info "Creating storage links..."
docker exec -it $APP_CONTAINER php artisan storage:link || true

# Clear and cache config
log_info "Caching configuration..."
docker exec -it $APP_CONTAINER php artisan config:cache || true

# Secure .env file after setup
log_info "Securing .env file..."
chmod 644 .env 2>/dev/null || true

# Show status
log_info "LinkAce installation complete!"
log_info "======================================="
log_info "Domain: https://${LINKACE_DOMAIN}"
log_info "App Directory: ${APP_DIR}"
log_info "======================================="
log_info "IMPORTANT: Save these credentials securely:"
log_info "Database Password: ${DB_PASSWORD}"
log_info "Redis Password: ${REDIS_PASSWORD}"
log_info "======================================="
log_info "To manage the application:"
log_info "  cd ${APP_DIR}"
log_info "  docker-compose logs -f    # View logs"
log_info "  docker-compose stop      # Stop"
log_info "  docker-compose start     # Start"
log_info "  docker-compose restart # Restart"
log_info ""
log_info "To create an admin user, run:"
log_info "  docker exec -it linkace_app_1 php artisan registeruser --admin"
log_info ""
log_info "Then access https://${LINKACE_DOMAIN} to complete the setup."

exit 0