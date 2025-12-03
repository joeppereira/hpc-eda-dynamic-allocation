#!/bin/bash
# Push to GitLab using Midway HTTPS credentials

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}=== Push to GitLab (Midway Authentication) ===${NC}"

GITLAB_URL="https://gitlab.aws.dev/spereirj/dynamic_allocation.git"

echo -e "${YELLOW}Target: ${GITLAB_URL}${NC}"
echo -e "${YELLOW}Note: Use Midway credentials when prompted${NC}"
echo ""

# Check current branch
CURRENT_BRANCH=$(git branch --show-current)
echo -e "${BLUE}Current branch: ${CURRENT_BRANCH}${NC}"

# Show last commit
echo -e "${BLUE}Last commit:${NC}"
git log -1 --oneline
echo ""

# Check if gitlab remote exists and update it to HTTPS
if git remote | grep -q "gitlab"; then
    echo -e "${YELLOW}Updating gitlab remote to use HTTPS...${NC}"
    git remote remove gitlab
fi

# Add GitLab remote with HTTPS
echo -e "${BLUE}Adding GitLab remote (HTTPS)...${NC}"
git remote add gitlab "$GITLAB_URL"

# Show remotes
echo -e "${BLUE}Current remotes:${NC}"
git remote -v
echo ""

# Check for uncommitted changes
echo -e "${BLUE}Checking for uncommitted changes...${NC}"
if ! git diff-index --quiet HEAD --; then
    echo -e "${YELLOW}Found uncommitted changes, committing...${NC}"
    git add .
    git commit -m "Update: elastic jobs implementation - $(date +%Y-%m-%d)"
else
    echo -e "${GREEN}No uncommitted changes${NC}"
fi
echo ""

# Push to GitLab
echo -e "${BLUE}Pushing to GitLab...${NC}"
echo -e "${YELLOW}⚠️  Use your Midway credentials when prompted${NC}"
echo ""

if git push -u gitlab "$CURRENT_BRANCH"; then
    echo ""
    echo -e "${GREEN}✓ Successfully pushed to GitLab${NC}"
    echo ""
    echo -e "${BLUE}Repository: https://gitlab.aws.dev/spereirj/dynamic_allocation${NC}"
    echo ""
    echo -e "${GREEN}New elastic jobs implementation includes:${NC}"
    echo "  ✓ elastic_jobs/README.md - Complete documentation"
    echo "  ✓ elastic_jobs/scripts/submit_elastic.py - Submit elastic jobs"
    echo "  ✓ elastic_jobs/scripts/unified_submit.py - Unified submission"
    echo "  ✓ elastic_jobs/scripts/monitor_elastic.py - Monitor scaling"
    echo "  ✓ elastic_jobs/aws/enable_elastic.sh - Enable on cluster"
    echo "  ✓ elastic_jobs/aws/install_mpi.sh - Install PMIx MPI"
    echo "  ✓ docs/ARCHITECTURE_COMPARISON.md - Architecture docs"
    echo ""
    echo -e "${BLUE}View at: https://gitlab.aws.dev/spereirj/dynamic_allocation${NC}"
else
    echo ""
    echo -e "${YELLOW}Normal push failed, trying force push...${NC}"
    if git push --force gitlab "$CURRENT_BRANCH"; then
        echo -e "${GREEN}✓ Force push successful${NC}"
        echo -e "${BLUE}View at: https://gitlab.aws.dev/spereirj/dynamic_allocation${NC}"
    else
        echo ""
        echo -e "${YELLOW}⚠️  Push failed. Try manually:${NC}"
        echo "  git push gitlab $CURRENT_BRANCH"
        echo ""
        echo -e "${YELLOW}Or check if repository exists:${NC}"
        echo "  https://gitlab.aws.dev/spereirj/dynamic_allocation"
    fi
fi

echo ""
echo -e "${GREEN}=== Done ===${NC}"
