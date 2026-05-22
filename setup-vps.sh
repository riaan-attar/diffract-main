#!/bin/bash

# Diffract VPS Setup Script - Production Automated Installation from Local Git Repo
# Designed for clean Ubuntu 24.04 VPS based on nemo setup instructions.

set -e  # Exit on any error

# Make sure we are running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (using sudo)"
  exit 1
fi

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Step 1: Configure Firewall (Ports 80, 443, 22)
print_header "Step 1: Configuring UFW Firewall"

if command -v ufw &> /dev/null; then
    print_warning "Configuring UFW to allow HTTP (80), HTTPS (443), and SSH (22)..."
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw allow 22/tcp
    ufw --force enable
    print_success "UFW firewall rules configured successfully"
else
    print_warning "UFW is not installed. Skipping local firewall configurations."
    print_warning "Please ensure Ports 80 & 443 are allowed in your VPS Hostinger hPanel!"
fi

# Step 2: Install and configure Docker
print_header "Step 2: Installing & Optimizing Docker"

if command -v docker &> /dev/null; then
    print_success "Docker is already installed"
else
    print_warning "Installing Docker Engine..."
    apt-get update
    apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
    print_success "Docker installed successfully"
fi

# Apply Ubuntu 24.04 cgroup v2 configuration patch
print_warning "Applying Docker cgroup v2 gateway patch for Ubuntu 24.04..."
mkdir -p /etc/docker
echo '{"default-cgroupns-mode": "host"}' > /etc/docker/daemon.json
systemctl restart docker
print_success "Docker cgroups patched and restarted successfully"

# Verify docker socket is active
if ! docker ps &> /dev/null; then
    print_error "Docker is not responding after restart. Please check docker status manually."
    exit 1
fi
print_success "Docker daemon is healthy"

# Step 3: Install OpenShell Runtime
print_header "Step 3: Installing OpenShell Gateway Layer"

if command -v openshell &> /dev/null; then
    print_success "OpenShell is already installed"
else
    print_warning "Installing OpenShell gateway binary..."
    curl -LsSf https://raw.githubusercontent.com/NVIDIA/OpenShell/main/install.sh | sh
    print_success "OpenShell runtime deployed successfully"
fi

# Step 4: Install NVM & Node.js LTS
print_header "Step 4: Setting up NVM & Node.js LTS"

export NVM_DIR="$HOME/.nvm"
if [ ! -d "$NVM_DIR" ]; then
    print_warning "Installing NVM (Node Version Manager)..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
fi

# Load NVM into current bash execution session
\. "$NVM_DIR/nvm.sh"

print_warning "Installing and activating Node.js LTS (v20)..."
nvm install 20
nvm use 20
nvm alias default 20
print_success "Node.js $(node -v) and npm $(npm -v) configured"

# Step 5: Build and install NemoClaw CLI globally
print_header "Step 5: Building and Installing NemoClaw CLI"

PROJECT_ROOT=$(pwd)
NEMOCLAW_DIR="$PROJECT_ROOT/NemoClaw"

if [ ! -d "$NEMOCLAW_DIR" ]; then
    print_error "NemoClaw directory not found at $NEMOCLAW_DIR!"
    exit 1
fi

cd "$NEMOCLAW_DIR"
print_warning "Installing NemoClaw CLI dependencies..."
npm install

print_warning "Compiling CLI TypeScript to production JavaScript..."
npm run build:cli

print_warning "Installing CLI globally from local build..."
npm install -g .
print_success "NemoClaw CLI installed globally"

# Step 6: Build Diffract UI Next.js App
print_header "Step 6: Building Diffract UI Next.js Application"

UI_DIR="$PROJECT_ROOT/diffractui"

if [ ! -d "$UI_DIR" ]; then
    print_error "diffractui directory not found at $UI_DIR!"
    exit 1
fi

cd "$UI_DIR"
print_warning "Installing Next.js UI dependencies..."
npm install

print_warning "Building Next.js production build..."
npm run build
print_success "Next.js UI built successfully"

# Step 7: Create and Start systemd Service for Diffract UI
print_header "Step 7: Creating Next.js UI Background Service"

NODE_PATH=$(which node)
NPM_PATH=$(which npm)

# Write native systemd service unit file
cat <<EOF > /etc/systemd/system/diffractui.service
[Unit]
Description=Diffract Next.js Web UI Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$UI_DIR
Environment=PATH=$PATH
Environment=PORT=3000
Environment=NODE_ENV=production
ExecStart=$NPM_PATH run start
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

print_warning "Enabling and booting diffractui service..."
systemctl daemon-reload
systemctl enable diffractui
systemctl restart diffractui

# Wait for process initialization and check status
sleep 3
if systemctl is-active --quiet diffractui; then
    print_success "Diffract UI background service is running on port 3000!"
else
    print_error "Diffract UI service failed to start. Run 'journalctl -u diffractui' for logs."
fi

# Step 8: Install and configure Caddy HTTPS proxy
print_header "Step 8: Configuring Caddy HTTPS Reverse Proxy"

if ! command -v caddy &> /dev/null; then
    print_warning "Installing Caddy Server..."
    apt-get install -y debian-keyring debian-archive-keyring apt-transport-https
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
    apt-get update
    apt-get install caddy -y
    print_success "Caddy server installed"
fi

# Set domain configuration or default to port 80 proxy
DOMAIN=$1
if [ -z "$DOMAIN" ]; then
    print_warning "No domain name argument specified."
    print_warning "Configuring Caddy to proxy on default port 80..."
    CADDY_CONFIG=":80 {
    reverse_proxy 127.0.0.1:3000
}"
else
    print_success "Configuring Caddy reverse proxy for domain: $DOMAIN"
    CADDY_CONFIG="$DOMAIN {
    reverse_proxy 127.0.0.1:3000
}"
fi

echo "$CADDY_CONFIG" > /etc/caddy/Caddyfile
systemctl restart caddy
print_success "Caddy proxy configured and active!"

# Set environment PATH hooks for interactive SSH root sessions
print_header "Adjusting Shell Profile Environment Paths"

if ! grep -q "NVM_DIR" ~/.bashrc; then
    echo 'export NVM_DIR="$HOME/.nvm"' >> ~/.bashrc
    echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> ~/.bashrc
    echo 'export PATH="$PATH:$HOME/.local/bin"' >> ~/.bashrc
    print_success "Updated ~/.bashrc PATH variables"
fi

# Finished!
print_header "Onboarding Infrastructure Setup Complete!"
echo -e "${GREEN}✓ All virtualization dependencies active"
echo -e "✓ NemoClaw CLI globally built and linked"
echo -e "✓ Diffract UI service is active on port 3000"
echo -e "✓ HTTPS/HTTP Caddy Proxy is configured${NC}\n"

if [ -n "$DOMAIN" ]; then
    echo -e "Access your secure web interface at: ${BLUE}https://$DOMAIN${NC}"
else
    echo -e "Access your secure web interface at: ${BLUE}http://<your-vps-ip>${NC}"
fi

echo -e "\nUseful commands:"
echo -e "  To check UI Server status:    ${YELLOW}systemctl status diffractui${NC}"
echo -e "  To restart UI Server:        ${YELLOW}systemctl restart diffractui${NC}"
echo -e "  To watch UI Server logs:      ${YELLOW}journalctl -u diffractui -f -n 50${NC}"
echo -e "  To check Caddy Server status: ${YELLOW}systemctl status caddy${NC}"
echo ""
