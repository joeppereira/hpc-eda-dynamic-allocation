#!/bin/bash

# Push Workshop Content to GitLab
# Source: /Users/spereirj/workshopstudio/intelligent-traffic-workshop-3
# Target: https://gitlab.aws.dev/spereirj/intelligent-traffic-workshop-studio

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}=== Push Workshop to GitLab ===${NC}"

SOURCE_DIR="/Users/spereirj/workshopstudio/intelligent-traffic-workshop-3"
GITLAB_URL="https://gitlab.aws.dev/spereirj/intelligent-traffic-workshop-studio.git"

echo -e "${YELLOW}Source: ${SOURCE_DIR}${NC}"
echo -e "${YELLOW}Target: ${GITLAB_URL}${NC}"
echo -e "${YELLOW}Note: Use Midway credentials when prompted${NC}"

# Navigate to source directory
cd "$SOURCE_DIR"

# Check if gitlab remote exists
if git remote | grep -q "gitlab"; then
    echo -e "${YELLOW}Removing existing gitlab remote...${NC}"
    git remote remove gitlab
fi

# Add GitLab remote
echo -e "${BLUE}Adding GitLab remote...${NC}"
git remote add gitlab "$GITLAB_URL"

# Show remotes
echo -e "${BLUE}Current remotes:${NC}"
git remote -v

# Check current branch
CURRENT_BRANCH=$(git branch --show-current)
echo -e "${BLUE}Current branch: ${CURRENT_BRANCH}${NC}"

# Add and commit any changes
echo -e "${BLUE}Checking for uncommitted changes...${NC}"
if ! git diff-index --quiet HEAD --; then
    echo -e "${YELLOW}Found uncommitted changes, committing...${NC}"
    git add .
    git commit -m "Update workshop content - $(date +%Y-%m-%d)"
else
    echo -e "${GREEN}No uncommitted changes${NC}"
fi

# Push to GitLab
echo -e "${BLUE}Pushing to GitLab...${NC}"
echo -e "${YELLOW}⚠️  Use your Midway credentials when prompted${NC}"

if git push gitlab "$CURRENT_BRANCH"; then
    echo -e "${GREEN}✓ Successfully pushed to GitLab${NC}"
else
    echo -e "${YELLOW}Normal push failed, trying force push...${NC}"
    if git push --force gitlab "$CURRENT_BRANCH"; then
        echo -e "${GREEN}✓ Force push successful${NC}"
    else
        echo -e "${YELLOW}⚠️  Push failed. Try manually:${NC}"
        echo -e "  cd $SOURCE_DIR"
        echo -e "  git push gitlab $CURRENT_BRANCH"
    fi
fi

echo -e "\n${GREEN}=== Done ===${NC}"
echo -e "${BLUE}GitLab URL: ${GITLAB_URL}${NC}"
echo -e "${BLUE}View at: https://gitlab.aws.dev/spereirj/intelligent-traffic-workshop-studio${NC}"
