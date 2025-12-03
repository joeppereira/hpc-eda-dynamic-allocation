#!/bin/bash
# Push elastic jobs implementation to GitLab

set -e

echo "=========================================="
echo "Push Elastic Jobs to GitLab"
echo "=========================================="
echo ""

# Check if we're in a git repo
if [ ! -d .git ]; then
    echo "Error: Not in a git repository"
    exit 1
fi

echo "Current commit:"
git log -1 --oneline
echo ""

echo "Files to be pushed:"
git diff --stat HEAD~1 HEAD | head -20
echo ""

echo "Remote configuration:"
git remote -v
echo ""

echo "Attempting to push to GitLab..."
echo ""

# Try to push
if git push -u gitlab main; then
    echo ""
    echo "=========================================="
    echo "✓ Successfully pushed to GitLab!"
    echo "=========================================="
    echo ""
    echo "Repository: https://gitlab.aws.dev/spereirj/dynamic_allocation"
    echo ""
    echo "New files added:"
    echo "  - elastic_jobs/README.md"
    echo "  - elastic_jobs/scripts/submit_elastic.py"
    echo "  - elastic_jobs/scripts/unified_submit.py"
    echo "  - elastic_jobs/scripts/monitor_elastic.py"
    echo "  - elastic_jobs/aws/enable_elastic.sh"
    echo "  - elastic_jobs/aws/install_mpi.sh"
    echo "  - docs/ARCHITECTURE_COMPARISON.md"
    echo "  - And more..."
    echo ""
else
    echo ""
    echo "=========================================="
    echo "✗ Push failed"
    echo "=========================================="
    echo ""
    echo "This may be due to SSH key configuration."
    echo ""
    echo "To fix:"
    echo "1. Ensure your SSH key is configured for GitLab"
    echo "2. Visit: https://gitlab.pages.aws.dev/docs/Platform/ssh.html"
    echo "3. Test SSH: ssh -T git@gitlab.aws.dev"
    echo ""
    echo "Alternative: Use GitLab web interface"
    echo "1. Create a new repository at: https://gitlab.aws.dev/spereirj/dynamic_allocation"
    echo "2. Upload files manually or use GitLab's push instructions"
    echo ""
    exit 1
fi
