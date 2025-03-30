#!/bin/bash
# ec2-setup/user-data.sh
# This script initializes the EC2 instance for the Neo4j Enterprise application.
# It performs system updates, installs essential utilities, synchronizes code from S3,
# and starts containerized services (Portainer and Neo4j) along with supporting utilities.
#
# All output is logged to /var/log/user-data.log and forwarded to the system console.
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

# ------------------------------
# Utility Functions
# ------------------------------

# Check if a command exists.
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# ------------------------------
# System Update
# ------------------------------
update_dnf() {
    echo "Updating system packages using dnf..."
    sudo dnf -q update -y
}

# ------------------------------
# Docker Installation
# ------------------------------
install_docker() {
    if command_exists docker; then
        echo "Docker is already installed."
    else
        echo "Installing Docker..."
        sudo dnf install -y docker
        sudo systemctl start docker
        sudo systemctl enable docker
        sudo usermod -aG docker ec2-user
        sudo chown root:docker /var/run/docker.sock
        sudo systemctl restart docker
        docker --version
    fi
}

# ------------------------------
# Docker Compose Installation
# ------------------------------
install_docker_compose() {
    if command_exists docker-compose; then
        echo "Docker Compose is already installed."
    else
        echo "Installing Docker Compose..."
        curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
        docker-compose --version
    fi
}

# ------------------------------
# Start Docker Containers (Create Shared Network)
# ------------------------------
start_containers() {
    # Create shared network if it doesn't exist.
    if ! docker network ls | grep -q "shared_network"; then
        echo "Creating docker network: shared_network"
        docker network create shared_network
    else
        echo "Docker network 'shared_network' already exists."
    fi
}

# ------------------------------
# Docker Command Execution Helper
# ------------------------------
docker_command() {
    local cmd="$1"
    local max_attempts=3
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if timeout 300 $cmd; then
            return 0
        fi
        echo "Docker command failed. Attempt $attempt of $max_attempts. Retrying in 10 seconds..."
        sleep 10
        ((attempt++))
    done

    echo "Docker command failed after $max_attempts attempts."
    return 1
}

# ------------------------------
# Code Synchronization from S3
# ------------------------------
get_code_from_s3() {
    # Create the ~/code directory if it doesn't exist
    CODE_DIR=/home/ec2-user/code
    mkdir -p $CODE_DIR

    # Download all files from S3 bucket to ~/code
    aws s3 sync s3://${DATA_BUCKET_NAME}/code $CODE_DIR

    # Check if the download was successful
    if [ $? -eq 0 ]; then
        echo "Files downloaded successfully from S3."
    else
        echo "Error downloading files from S3. Exiting."
        exit 1
    fi

    # Unzip all files in ~/code
    for zip_file in $CODE_DIR/*.zip; do
        if [ -f "$zip_file" ]; then
            # Extract the filename without extension
            folder_name=$(basename "$zip_file" .zip)

            # Create the directory if it doesn't exist
            mkdir -p "$CODE_DIR/$folder_name"

            unzip -o "$zip_file" -d "$CODE_DIR/$folder_name"
            if [ $? -eq 0 ]; then
                echo "Unzipped: $zip_file"
                # Optionally, remove the zip file after extraction
                # rm "$zip_file"
            else
                echo "Error unzipping: $zip_file"
            fi
        fi
    done

    sudo chown -R ec2-user:ec2-user $CODE_DIR
    cp -a /home/ec2-user/code/docker /home/ec2-user/
    cp -a /home/ec2-user/code/scripts /home/ec2-user/
    # cp -a /home/ec2-user/code/ansible /home/ec2-user/
    # cp -a /home/ec2-user/code/web-apps /home/ec2-user/
    # cp -a /home/ec2-user/code/code-server-extensions /home/ec2-user/

    echo "Download and unzip process completed."
}

# ------------------------------
# Caddy Installation & Configuration
# ------------------------------
install_caddy() {
    if command_exists caddy; then
        echo "Caddy is already installed."
    else
        echo "Installing Caddy..."
        cd /tmp
        wget -q https://github.com/caddyserver/caddy/releases/download/v2.9.1/caddy_2.9.1_linux_amd64.tar.gz
        tar xzf caddy_2.9.1_linux_amd64.tar.gz
        sudo mv caddy /usr/local/bin/
        sudo chmod +x /usr/local/bin/caddy
        caddy version
        sudo mkdir -p /etc/caddy/certs


        CERT_DIR="/etc/caddy/certs"
        DOMAIN="localhost"  # Using localhost as the default domain
        DAYS_VALID=365
        IP_ADDRESS=$(curl -s https://api.ipify.org)

        sudo mkdir -p $CERT_DIR

        sudo openssl genrsa -out $CERT_DIR/server.key 2048

        cat << EOF > $CERT_DIR/server.cnf
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
x509_extensions = v3_req

[dn]
C = US
ST = State
L = City
O = Organization
OU = OrganizationalUnit
CN = $DOMAIN

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = $DOMAIN
IP.1 = $IP_ADDRESS
EOF

        sudo openssl req -x509 -nodes -days $DAYS_VALID \
            -keyout "$CERT_DIR/server.key" \
            -out "$CERT_DIR/server.crt" \
            -config "$CERT_DIR/server.cnf"
        sudo chown caddy:caddy "$CERT_DIR/server.key" "$CERT_DIR/server.crt"
        sudo chmod 600 "$CERT_DIR/server.key"
        sudo chmod 644 "$CERT_DIR/server.crt"
        sudo rm "$CERT_DIR/server.cnf"

        echo "Self-signed certificate created for $DOMAIN and IP $IP_ADDRESS"
        echo "Certificate location: $CERT_DIR/server.crt"
        echo "Private key location: $CERT_DIR/server.key"

        # Copy Caddy files from code repository if available.
        echo "Copying caddy files from /home/ec2-user/code/caddy to /etc/caddy"
        sudo cp -R /home/ec2-user/code/caddy /etc

        # Create systemd service for Caddy.
        cat << EOF | sudo tee /etc/systemd/system/caddy.service
[Unit]
Description=Caddy Web Server
After=network.target

[Service]
ExecStart=/usr/local/bin/caddy run --config /etc/caddy/Caddyfile
ExecReload=/usr/local/bin/caddy reload --config /etc/caddy/Caddyfile
TimeoutStopSec=5
LimitNOFILE=1048576
LimitNPROC=512
PrivateTmp=true
ProtectSystem=full
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF
        sudo systemctl daemon-reload
        sudo systemctl start caddy
        sudo systemctl enable caddy
    fi
}

# ------------------------------
# Install Portainer
# ------------------------------
install_portainer() {
    echo "Installing portainer in docker"
    export PORTAINER_DIR=/home/ec2-user/docker/portainer
    # mkdir -p $PORTAINER_DIR
    # echo "$PORTAINER_COMPOSE_CONTENT" > "$PORTAINER_DIR/docker-compose.yml"
    cd $PORTAINER_DIR
    docker-compose up -d --quiet-pull
    sudo chown -R ec2-user:ec2-user $PORTAINER_DIR
    echo "Portainer installed"
}

# ------------------------------
# Install Neo4j
# ------------------------------
install_neo4j() {
    echo "Installing Neo4j container..."
    export NEO4J_DIR=/home/ec2-user/docker/neo4j
    if [ -d "$NEO4J_DIR" ]; then
        cd "$NEO4J_DIR" || exit
        docker-compose up -d --quiet-pull
        sudo chown -R ec2-user:ec2-user "$NEO4J_DIR"
        echo "Neo4j container installed."
    else
        echo "Neo4j directory ($NEO4J_DIR) not found."
    fi
}

# ------------------------------
# Create Utility Scripts & Install Tools
# ------------------------------
create_utils() {
    echo "Installing git..."
    sudo yum install -y git

    echo "Installing nodejs..."
    sudo dnf install -y nodejs

    echo "Installing vsce..."
    sudo npm install -g vsce

    mkdir -p /home/ec2-user/.local/bin

    cat << 'EOF' > /home/ec2-user/.local/bin/tail_setup_log
#!/bin/bash
sudo tail -f /var/log/user-data.log  
EOF

    cat << 'EOF' > /home/ec2-user/.local/bin/less_setup_log
#!/bin/bash
sudo less +G /var/log/user-data.log
EOF

#     cat << EOF > /home/ec2-user/.local/bin/show_passwords
# #!/bin/bash
# echo "=== LiteLLM Key ==="
# echo "To change this key, edit file: /home/ec2-user/docker/open-webui/docker-compose.yml" 
# grep -E 'LITELLM_API_KEY=' /home/ec2-user/docker/open-webui/docker-compose.yml | sed 's/^[[:space:]]*//'
# echo
# echo "=== Controller Lambda auth key ==="
# echo "To change this key, update the parameter store value \"/\$PROJECT_ID/info\", key \"controller_auth_key\""
# aws ssm get-parameter --name "/$PROJECT_ID/info" --with-decryption | jq -r '.Parameter.Value' | jq -r '.controller_auth_key'
# EOF

    chmod 755 /home/ec2-user/.local/bin/tail_setup_log
    chmod 755 /home/ec2-user/.local/bin/less_setup_log
    chmod 755 /home/ec2-user/.local/bin/show_passwords
    chown -R ec2-user:ec2-user /home/ec2-user/.local
}

# ------------------------------
# Generate Apps JSON
# ------------------------------
create_apps_json() {
    SCRIPTS_DIR=/home/ec2-user/scripts
    mkdir -p "$SCRIPTS_DIR"
    cd "$SCRIPTS_DIR" || exit

    # If generate-app-urls.py is available in code, use it.
    if [ -f /home/ec2-user/code/generate-app-urls.py ]; then
        cp /home/ec2-user/code/generate-app-urls.py "$SCRIPTS_DIR"
    fi

    chown -R ec2-user:ec2-user "$SCRIPTS_DIR"
    su - ec2-user -c "cd /home/ec2-user/scripts && python generate-app-urls.py"
    echo "apps.json has been generated."
}

# ------------------------------
# Registration Functions (Optional)
# ------------------------------
register_start() {
    if [ -n "$PROJECT_ID" ] && [ -n "$DATA_BUCKET_NAME" ]; then
        current_datetime=$(date "+%Y-%m-%d %H:%M:%S")
        echo "$current_datetime" > "${PROJECT_ID}-ec2-setup-started"
        echo "Copying ${PROJECT_ID}-ec2-setup-started to s3://$DATA_BUCKET_NAME"
        aws s3 cp "${PROJECT_ID}-ec2-setup-started" "s3://${DATA_BUCKET_NAME}/"
        rm "${PROJECT_ID}-ec2-setup-started"
        aws s3 rm "s3://${DATA_BUCKET_NAME}/${PROJECT_ID}-ec2-setup-ended" --quiet
    else
        echo "PROJECT_ID or DATA_BUCKET_NAME not set. Skipping registration start."
    fi
}

register_end() {
    if [ -n "$PROJECT_ID" ] && [ -n "$DATA_BUCKET_NAME" ]; then
        current_datetime=$(date "+%Y-%m-%d %H:%M:%S")
        echo "$current_datetime" > "${PROJECT_ID}-ec2-setup-ended"
        echo "Copying ${PROJECT_ID}-ec2-setup-ended to s3://$DATA_BUCKET_NAME"
        aws s3 cp "${PROJECT_ID}-ec2-setup-ended" "s3://${DATA_BUCKET_NAME}/"
        rm "${PROJECT_ID}-ec2-setup-ended"
    else
        echo "PROJECT_ID or DATA_BUCKET_NAME not set. Skipping registration end."
    fi
}

# ------------------------------
# Environment Variables Setup
# ------------------------------
add_vars_to_bashrc() {
    # Array of variable names to add to .bashrc
    variables=(
        "PROJECT_ID"
        "AWS_REGION"
        "DATA_BUCKET_NAME"
    )

    # Path to .bashrc file
    bashrc_file="/home/ec2-user/.bashrc"

    # Helper function to add a single variable to .bashrc if it's set and not already present.
    add_variable_to_bashrc() {
        local var_name=$1
        local var_value=${!var_name}
        
        if [ -n "$var_value" ]; then
            if ! grep -q "export $var_name=" "$bashrc_file"; then
                echo "export $var_name=\"$var_value\"" >> "$bashrc_file"
                echo "Added $var_name to .bashrc"
            else
                echo "$var_name already exists in .bashrc, skipping"
            fi
        else
            echo "$var_name is not set, skipping"
        fi
    }

    # Process each variable in the array using the helper function.
    for var in "${variables[@]}"; do
        add_variable_to_bashrc "$var"
    done

    echo "Finished updating .bashrc"
}

# ------------------------------
# Main Execution
# ------------------------------
register_start
update_dnf
add_vars_to_bashrc
get_code_from_s3
create_utils
install_docker
install_docker_compose
start_containers
install_portainer
install_caddy
install_neo4j
create_apps_json
register_end

echo "All installations completed."
