#!/bin/bash

# --- AUTOMATIC CLEANUP FUNCTION ---
cleanup() {
    if [ "$CLEANUP_DONE" = true ]; then exit 0; fi
    CLEANUP_DONE=true

    # Custom ANSI formatting variables
    # 36m is cyan/blue, 32m is green, 1m is bold (0 for normal ex: BLUE ="\033[0;36m"), 0m resets formatting
    local BLUE="\033[1;36m"
    local GREEN="\033[1;32m"
    local RESET="\033[0m"
    
    echo -e "\n${BLUE}========== INITIATING PURGE LOGS ==========${RESET}"
    
    # Step 1: Stopping Container
    echo -ne "${BLUE}[internal] stopping active test containers...${RESET}"
    docker rm -f movie-site-test >/dev/null 2>&1
    sleep 0.4
    echo -e "\r${GREEN}✓ [internal] stopping active test containers... DONE${RESET}"

    # Step 2: Extracting and removing history logs
    echo -ne "${BLUE}[internal] removing build log records...${RESET}"
    local target_log_id
    target_log_id=$(docker buildx history ls --format '{{.Ref}}' 2>/dev/null | head -n 1)
    if [ ! -z "$target_log_id" ]; then
        docker buildx history rm "$target_log_id" >/dev/null 2>&1
    fi
    sleep 0.4
    echo -e "\r${GREEN}✓ [internal] removing build log records... DONE${RESET}"

    # Step 3: Purging image layers
    echo -ne "${BLUE}[internal] purging image layers from disk...${RESET}"
    docker rmi -f "$IMAGE_ID" >/dev/null 2>&1
    docker rmi -f movie-site-tmp >/dev/null 2>&1
    sleep 0.4
    echo -e "\r${GREEN}✓ [internal] purging image layers from disk... DONE${RESET}"

    # Step 4: Pruning BuildKit
    echo -ne "${BLUE}[internal] clearing remaining buildkit step records...${RESET}"
    docker builder prune --all --force >/dev/null 2>&1
    sleep 0.4
    echo -e "\r${GREEN}✓ [internal] clearing remaining buildkit step records... DONE${RESET}"

    echo -e "\n${GREEN}✨ System remains completely spotless.${RESET}"
    exit 0
}

# Create a temporary file to store the Image ID
IID_FILE=$(mktemp)

# 31m is red, 32m is green, 36m is cyan/blue, 1m is bold (0 for normal), 0m resets formatting
RED="\033[1;31m"
GREEN="\033[1;32m"
BLUE="\033[1;36m"
RESET="\033[0m"

echo -e "${BLUE}Building the temporary image... ${RESET}"
docker build -t movie-site-tmp --iidfile "$IID_FILE" --progress=auto .
echo -e "${GREEN}✓ Building the temporary image... DONE${RESET}"


# Capture the exact structural data Image ID (sha256)
IMAGE_ID=$(cat "$IID_FILE")
rm -f "$IID_FILE"

if [ -z "$IMAGE_ID" ]; then
    echo -e "${RED} Error: Failed to capture Image ID. ${RESET}"
    exit 1
fi

echo -e "${BLUE}Captured Image ID${RESET}: ${GREEN}$IMAGE_ID${RESET}"

# Bind ONLY to SIGINT (Ctrl+C). Natural exits fall through to the manual call at the bottom.
trap cleanup SIGINT

# Run the temporary container (Blocks terminal)
echo -e "${BLUE}Starting container on http://localhost:6969...${RESET}"
docker run --rm -p 6969:6969 --name movie-site-test movie-site-tmp

# Call cleanup manually if the container stops naturally 
cleanup
