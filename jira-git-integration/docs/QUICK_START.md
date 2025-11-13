# Quick Start Guide

Get up and running with Jira Git Integration in 5 minutes!

## Prerequisites

- Python 3.7+ installed
- Git repository
- Jira Cloud account
- API token from Jira

## Step 1: Install

```bash
cd your-project
./jira-git-integration/install.sh
```

The installer will:
- Check requirements
- Prompt for Jira credentials
- Install Git hooks
- Create helper scripts

## Step 2: Configure

Edit `.env` file in your repository root:

```bash
JIRA_SITE=yourcompany.atlassian.net
JIRA_EMAIL=your.email@company.com
JIRA_API_TOKEN=your_token_here
```

**Get API Token**: https://id.atlassian.com/manage-profile/security/api-tokens

## Step 3: Test

```bash
# Test Jira connection
python3 jira-git-integration/lib/jira_client.py

# Create test branch
git checkout -b "TEST-123-test-integration"

# Make test commit
git commit --allow-empty -m "[TEST-123] test: testing integration #comment Testing setup"
```

Check Jira - you should see:
- New comment on TEST-123
- Commit linked to issue

## Step 4: Use Smart Commits

```bash
# Log time
git commit -m "[PROJ-456] feat: add feature #time 2h"

# Add comment
git commit -m "[PROJ-456] fix: bug fix #comment Fixed the issue"

# Transition issue
git commit -m "[PROJ-456] feat: complete #done"

# Multiple commands
git commit -m "[PROJ-456] feat: feature #time 2h 30m #comment Ready #in-review"
```

## Common Commands

```bash
# Generate release notes
./bin/generate-release-notes --version v2.0.0

# Generate metrics
./bin/generate-metrics --days 30 --project PROJ

# Start webhook server
./bin/start-webhook-server

# Temporarily disable hooks
JIRA_HOOK_DISABLED=1 git commit -m "message"
```

## Troubleshooting

### Hooks not running?

```bash
# Check permissions
ls -la .git/hooks/
chmod +x .git/hooks/*
```

### Jira not updating?

```bash
# Validate config
python3 jira-git-integration/config/config_manager.py --validate

# Check credentials in .env
```

### Need help?

```bash
# View full documentation
cat jira-git-integration/README.md

# Check configuration
python3 jira-git-integration/config/config_manager.py --show
```

## Next Steps

1. Read the [README](../README.md) for detailed documentation
2. Customize configuration in `.env`
3. Set up webhook server for PR automation
4. Configure auto-reviewer assignment
5. Create custom Jira dashboards

**Happy coding! 🚀**
