#!/bin/bash
# === CONFIGURATION ===
ROM_DIR=/home/joker/sos
PATCH_REPO=https://github.com/Joker-V2/android_tools.git
PATCH_DIR=~/android_tools

# === TELEGRAM CONFIG ===
TELEGRAM_BOT_TOKEN="your_bot_token_here"
TELEGRAM_CHAT_ID="your_chat_id_here"
send_telegram_message() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d chat_id="${TELEGRAM_CHAT_ID}" \
        -d parse_mode="Markdown" \
        -d text="$message" > /dev/null
}

# === COLOR SETUP ===
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
NC="\e[0m"

# === SYNC SOURCE ===
echo -e "${GREEN}==> Syncing SuperiorOS source to $ROM_DIR...${NC}"
send_telegram_message "🚀 *Starting SuperiorOS source sync...*"
mkdir -p "$ROM_DIR"
cd "$ROM_DIR" || exit 1

# Ask user which branch to sync
read -rp "Which branch do you want to sync? [dev/stable]: " BRANCH_TYPE
BRANCH_TYPE=$(echo "$BRANCH_TYPE" | tr '[:upper:]' '[:lower:]')
if [[ "$BRANCH_TYPE" = "stable" ]]; then
    INIT_CMD="repo init -u https://github.com/SuperiorOS/manifest.git -b fifteen-los -m stable/latest.xml --git-lfs"
    BRANCH_LABEL="Stable Branch"
else
    INIT_CMD="repo init -u https://github.com/SuperiorOS/manifest.git -b fifteen-los --git-lfs"
    BRANCH_LABEL="Development Branch"
fi
send_telegram_message "🔀 *Selected branch:* $BRANCH_LABEL"

if [[ -d ".repo" ]]; then
    echo -e "${YELLOW}ROM source already exists at $ROM_DIR${NC}"
    read -rp "Do you want to force sync it? [y/N]: " SYNC_CHOICE
    SYNC_CHOICE=$(echo "$SYNC_CHOICE" | tr '[:upper:]' '[:lower:]')
    if [[ "$SYNC_CHOICE" = "y" || "$SYNC_CHOICE" = "yes" ]]; then
        echo -e "${YELLOW}→ Resetting manifest and force syncing...${NC}"
        rm -rf .repo/manifest*
        send_telegram_message "♻️ *ROM source already exists.* Resetting manifests and re-syncing."
    else
        echo -e "${YELLOW}⏩ Skipping source sync as requested.${NC}"
        send_telegram_message "⏭ *ROM source sync skipped by user.*"
        SKIP_SYNC=true
    fi
fi

if [[ "$SKIP_SYNC" != "true" ]]; then
    if ! eval "$INIT_CMD"; then
        send_telegram_message "❌ *repo init failed!* Could not initialize $BRANCH_LABEL."
        exit 1
    fi
    if ! repo sync --force-sync; then
        send_telegram_message "❌ *repo sync failed!* Check your connection or manifest."
        exit 1
    fi
    echo -e "${GREEN}✔ Source synced successfully.${NC}"
    send_telegram_message "✅ *SuperiorOS source sync completed successfully.* ($BRANCH_LABEL)"
fi

# === CLONE PATCH REPO ===
echo -e "${GREEN}\n==> Cloning patch repo...${NC}"
cd ~
if [[ -d "$PATCH_DIR/.git" ]]; then
    echo -e "${YELLOW}Patch repo already exists. Pulling latest...${NC}"
    cd "$PATCH_DIR" && git pull
else
    git clone "$PATCH_REPO" "$PATCH_DIR" || {
        send_telegram_message "❌ *Failed to clone patch repo!*"
        exit 1
    }
fi
echo -e "${GREEN}✔ Patch repo ready.${NC}"
send_telegram_message "📥 *Patch repo is ready.* Cloned or updated from GitHub."

# === APPLY PATCHES ===
echo -e "\n${YELLOW}==> Scanning for patches...${NC}"
find "$PATCH_DIR" -type f -name '*.patch' | sort -u > /tmp/patch_list.txt
PATCH_COUNT=$(wc -l < /tmp/patch_list.txt)
echo -e "${YELLOW}Found $PATCH_COUNT patch(es).${NC}"
read -rp "Apply all patches now? (y/N): " confirm
confirm=${confirm,,}

if [[ "$confirm" != "y" && "$confirm" != "yes" ]]; then
    echo -e "${YELLOW}⏩ Patch application aborted by user.${NC}"
    send_telegram_message "⚠️ *Patch application aborted by user.*"
else
    APPLIED_COUNT=0
    SKIPPED_COUNT=0
    while IFS= read -r patch_file; do
        PATCH_NAME=$(basename "$patch_file")
        project_rel=${patch_file#$PATCH_DIR/}
        target_dir="$ROM_DIR/$(dirname "$project_rel")"

        echo -e "\n${YELLOW}Processing patch:${NC} $PATCH_NAME"
        echo -e "${YELLOW}Target directory:${NC} $target_dir"

        if [[ ! -d "$target_dir" ]]; then
            echo -e "${RED}✖ Directory not found: $target_dir — skipping.${NC}"
            ((SKIPPED_COUNT++))
            continue
        fi

        pushd "$target_dir" > /dev/null || continue
        if git log --oneline | grep -qF "$PATCH_NAME"; then
            echo -e "${YELLOW}⚠ Already applied: $PATCH_NAME — skipping.${NC}"
            ((SKIPPED_COUNT++))
        elif git apply --check "$patch_file" &>/dev/null; then
            git apply "$patch_file"
            git add -A
            git commit -m "Applied patch: $PATCH_NAME"
            echo -e "${GREEN}✔ Applied: $PATCH_NAME${NC}"
            ((APPLIED_COUNT++))
        else
            echo -e "${YELLOW}⚠ Conflict or bad patch: $PATCH_NAME — skipped.${NC}"
            ((SKIPPED_COUNT++))
        fi
        popd > /dev/null
    done < /tmp/patch_list.txt

    echo -e "\n${GREEN}✅ Patch processing complete.${NC}"
    send_telegram_message "✅ *Patch application completed.*\n📦 Total patches: $PATCH_COUNT\n✅ Applied: $APPLIED_COUNT\n⚠ Skipped: $SKIPPED_COUNT"
fi

rm /tmp/patch_list.txt
