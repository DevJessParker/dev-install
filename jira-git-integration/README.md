# Jira Git Integration

> **Automated Jira integration for Git workflows** - Transform your development process with seamless Git + Jira automation

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Python: 3.7+](https://img.shields.io/badge/Python-3.7+-green.svg)](https://www.python.org/)

Complete development lifecycle tracking system that automatically updates Jira from Git actions, generates release notes, tracks metrics, and provides powerful automation for your development workflow.

---

## ✨ Features

### 🔗 **Smart Commits**
Automatically update Jira with every commit:
- Log work time: `#time 2h 30m`
- Add comments: `#comment Fixed the issue`
- Transition tickets: `#in-review`, `#done`, `#qa-ready`
- Multiple actions in one commit!

### 🎣 **Git Hooks**
Automatic Jira updates on:
- **Post-commit**: Link commits, log time, transition issues
- **Post-checkout**: Update when switching branches
- **Prepare-commit-msg**: Auto-add issue keys
- **Commit-msg**: Validate commit messages

### 🌐 **Webhook Server**
Handle Bitbucket/GitHub webhooks for:
- Pull request creation/updates
- Build status notifications
- Automatic workflow transitions
- Reviewer notifications

### 📊 **Analytics & Reporting**
- **Metrics**: Development velocity, code churn, contributor stats
- **Release Notes**: Auto-generate from commits and Jira
- **Cycle Time**: Track issue lifecycle
- **Team Performance**: Commits, PRs, and code reviews

### 🤖 **Automation**
- **Auto Reviewer Assignment**: Based on files changed
- **Workflow Transitions**: Auto-move tickets through states
- **Subtask Creation**: From commit patterns
- **Slack/Teams Notifications**: Configurable alerts

---

## 🚀 Quick Start

### Prerequisites

- Python 3.7 or higher
- Git repository
- Jira Cloud account with API access

### Installation

1. **Clone or copy** this directory into your project:
   ```bash
   # Option 1: As a submodule
   git submodule add <repo-url> jira-git-integration

   # Option 2: Copy directly
   cp -r jira-git-integration /path/to/your/project/
   ```

2. **Run the installer**:
   ```bash
   cd your-project
   ./jira-git-integration/install.sh
   ```

3. **Configure your credentials**:
   ```bash
   # Edit .env file
   vi .env

   # Or run config tool
   python3 jira-git-integration/config/config_manager.py --show
   ```

4. **Test your setup**:
   ```bash
   # Test Jira connection
   python3 jira-git-integration/lib/jira_client.py

   # Make a test commit
   git commit -m "[PROJ-123] test: testing integration #comment Testing setup"
   ```

---

## 📖 Documentation

### Configuration

Create `.env` file in your repository root:

```bash
# Required: Jira Configuration
JIRA_SITE=yourcompany.atlassian.net
JIRA_EMAIL=your.email@company.com
JIRA_API_TOKEN=your_api_token_here

# Optional: Customize behavior
JIRA_AUTO_TRANSITION_ON_BRANCH=true
JIRA_REQUIRE_ISSUE_KEY=false
WEBHOOK_PORT=5000
```

**Generate API Token**: https://id.atlassian.com/manage-profile/security/api-tokens

### Smart Commit Syntax

```bash
# Basic format
[ISSUE-KEY] type: description

# With time logging
[PROJ-456] feat: add filtering #time 2h 30m

# With comment
[PROJ-456] fix: bug fix #comment Fixed null pointer exception

# With transition
[PROJ-456] feat: complete feature #done

# Combine multiple commands
[PROJ-456] feat: add filtering #time 3h #comment Ready for review #in-review
```

#### Available Transitions

- `#in-progress`, `#progress`, `#start` → In Progress
- `#in-review`, `#review` → Code Review
- `#done`, `#complete`, `#resolved` → Done
- `#qa-ready`, `#qa` → QA/Testing
- `#deployed` → Deployed
- `#blocked` → Blocked

#### Time Format

- `m` - minutes
- `h` - hours
- `d` - days (8 hours)
- `w` - weeks (40 hours)

Examples: `2h 30m`, `1d 4h`, `3w 2d`

### Branch Naming Convention

Include issue key in branch name for automatic linking:

```bash
# Good branch names
git checkout -b "PROJ-456-add-filtering"
git checkout -b "PROJ-789-fix-login-bug"

# Also works
git checkout -b "feature/PROJ-456-filtering"
git checkout -b "bugfix/PROJ-789"
```

When you checkout a branch with an issue key:
- Commit messages automatically get the issue key prepended
- Optional: Auto-transition ticket to "In Progress"

---

## 🛠️ Usage Examples

### Generate Release Notes

```bash
# From latest tag to HEAD
./bin/generate-release-notes --version v2.4.0

# Specific range
./bin/generate-release-notes --version v2.4.0 --since v2.3.0

# From Jira (requires project)
./bin/generate-release-notes --version v2.4.0 --jira-only --project PROJ

# Save to file
./bin/generate-release-notes --version v2.4.0 --output RELEASE_NOTES.md
```

### Generate Metrics Report

```bash
# Last 30 days
./bin/generate-metrics --days 30

# With Jira project data
./bin/generate-metrics --days 30 --project PROJ

# Output as JSON
./bin/generate-metrics --days 30 --json --output metrics.json
```

### Auto Reviewer Assignment

```bash
# Show recommended reviewers for current branch
./bin/assign-reviewers

# Compare against specific branch
./bin/assign-reviewers --base-branch develop

# Generate config template
./bin/assign-reviewers --generate-config
```

### Start Webhook Server

```bash
# Start server (uses config from .env)
./bin/start-webhook-server

# Server will listen on http://0.0.0.0:5000
# Configure webhook in Bitbucket:
#   URL: http://your-server:5000/webhook/bitbucket
#   Events: Push, Pull Request, Build Status
```

---

## 🔧 Advanced Configuration

### Environment Variables

Full list of configuration options:

```bash
# Jira Configuration
JIRA_SITE=                              # Required
JIRA_EMAIL=                             # Required
JIRA_API_TOKEN=                         # Required
JIRA_DEFAULT_PROJECT=                   # Optional

# Hook Behavior
JIRA_HOOK_DISABLED=0                    # Disable all hooks
JIRA_AUTO_TRANSITION_ON_BRANCH=false    # Auto start work on checkout
JIRA_REQUIRE_ISSUE_KEY=false            # Reject commits without key
JIRA_WARN_NO_ISSUE_KEY=true             # Warn about missing key
JIRA_VALIDATE_COMMIT_FORMAT=false       # Enforce conventional commits

# Webhook Server
WEBHOOK_HOST=0.0.0.0
WEBHOOK_PORT=5000
WEBHOOK_DEBUG=false
BITBUCKET_WEBHOOK_SECRET=               # For signature verification
JIRA_AUTO_TRANSITION_PR=true            # Auto-transition on PR creation
```

### Custom Transitions

Map your workflow states:

```bash
JIRA_CUSTOM_TRANSITIONS=review:Code Review,qa:QA Testing,prod:In Production
```

Then use in commits:
```bash
git commit -m "[PROJ-456] feat: done #review"
```

### Reviewer Assignment Rules

Create `reviewer_config.json`:

```json
{
  "rules": [
    {
      "name": "Backend API changes",
      "patterns": ["**/api/**/*.cs", "**/controllers/**"],
      "reviewers": ["backend-lead"],
      "required": 1
    },
    {
      "name": "Frontend changes",
      "patterns": ["**/*.tsx", "**/*.jsx"],
      "reviewers": ["frontend-lead"],
      "required": 1
    },
    {
      "name": "Database migrations",
      "patterns": ["**/migrations/**", "**/*.sql"],
      "reviewers": ["dba", "backend-lead"],
      "required": 2
    }
  ],
  "default_reviewers": ["team-lead"],
  "max_reviewers": 3
}
```

---

## 📂 Project Structure

```
jira-git-integration/
├── lib/                          # Core libraries
│   ├── jira_client.py           # Jira REST API client
│   └── smart_commit_parser.py   # Parse smart commit syntax
├── hooks/                        # Git hooks
│   ├── post-commit              # Update Jira after commit
│   ├── post-checkout            # Update on branch change
│   ├── prepare-commit-msg       # Auto-add issue keys
│   └── commit-msg               # Validate commits
├── webhooks/                     # Webhook handlers
│   └── bitbucket_webhook_server.py
├── scripts/                      # Automation scripts
│   ├── release_notes_generator.py
│   └── auto_reviewer_assignment.py
├── analytics/                    # Metrics and reporting
│   └── metrics_reporter.py
├── config/                       # Configuration
│   ├── config.example.env
│   └── config_manager.py
├── docs/                         # Documentation
├── tests/                        # Unit tests
├── install.sh                    # Installation script
├── requirements.txt              # Python dependencies
└── README.md                     # This file
```

---

## 🤝 Integration with CI/CD

### Bitbucket Pipelines

```yaml
# bitbucket-pipelines.yml
image: python:3.9

pipelines:
  branches:
    main:
      - step:
          name: Build and Deploy
          script:
            - pip install -r requirements.txt
            - npm run build
            - npm test
          after-script:
            # Update Jira with build results
            - source .env
            - python3 jira-git-integration/lib/jira_client.py
```

### GitHub Actions

```yaml
# .github/workflows/build.yml
name: Build

on:
  push:
    branches: [main]
  pull_request:

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.9'

      - name: Install dependencies
        run: pip install -r jira-git-integration/requirements.txt

      - name: Update Jira
        env:
          JIRA_SITE: ${{ secrets.JIRA_SITE }}
          JIRA_EMAIL: ${{ secrets.JIRA_EMAIL }}
          JIRA_API_TOKEN: ${{ secrets.JIRA_API_TOKEN }}
        run: |
          python3 jira-git-integration/webhooks/update_build_status.py
```

---

## 🐛 Troubleshooting

### Hooks not executing

1. Check hook permissions:
   ```bash
   ls -la .git/hooks/
   chmod +x .git/hooks/*
   ```

2. Verify Python path in hooks:
   ```bash
   which python3
   # Update shebang in hooks if needed
   ```

### Jira authentication errors

1. Verify credentials:
   ```bash
   python3 jira-git-integration/config/config_manager.py --validate
   ```

2. Test connection:
   ```bash
   python3 jira-git-integration/lib/jira_client.py
   ```

3. Check API token:
   - Regenerate at: https://id.atlassian.com/manage-profile/security/api-tokens
   - Update `.env` file

### Commits not updating Jira

1. Check commit message format:
   ```bash
   # Issue key must be present
   [PROJ-123] feat: description
   ```

2. Verify hook is running:
   ```bash
   # Enable debug output
   JIRA_HOOK_DEBUG=1 git commit -m "[PROJ-123] test"
   ```

3. Check logs:
   ```bash
   # Hooks write to stderr
   git commit -m "[PROJ-123] test" 2>&1 | tee commit.log
   ```

### Temporarily disable hooks

```bash
# For one commit
JIRA_HOOK_DISABLED=1 git commit -m "message"

# Permanently
echo "JIRA_HOOK_DISABLED=1" >> .env
```

---

## 📊 Metrics & Dashboards

### Available Metrics

**Commit Metrics:**
- Total commits
- Commits per day/author
- Lines added/removed
- Code churn rate
- Average commit size
- Top contributors

**Jira Metrics:**
- Issues created/resolved
- Resolution rate
- Average cycle time
- Time in each status
- Issue type distribution

**Pull Request Metrics:**
- Merged branches
- Commits per branch
- Merge frequency

### Export Metrics

```bash
# Generate JSON for dashboards
./bin/generate-metrics --days 30 --json > metrics.json

# Use in Grafana, Kibana, or custom dashboard
```

---

## 🔒 Security Best Practices

1. **Never commit `.env` file**
   - Already in `.gitignore`
   - Store secrets in environment variables

2. **Use webhook secrets**
   ```bash
   BITBUCKET_WEBHOOK_SECRET=your_secret_here
   ```

3. **Restrict API token permissions**
   - Use Jira API tokens, not passwords
   - Limit token scope if possible

4. **Rotate credentials regularly**
   - Update API tokens quarterly
   - Update webhook secrets

---

## 🚧 Roadmap

- [ ] GitLab support
- [ ] Azure DevOps integration
- [ ] Slack/Teams notifications
- [ ] Custom automation rules engine
- [ ] Web UI for configuration
- [ ] Docker container deployment
- [ ] Multi-project support
- [ ] Advanced analytics dashboard

---

## 🤝 Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

---

## 📄 License

MIT License - see LICENSE file for details

---

## 🙏 Acknowledgments

- Atlassian Jira REST API
- Git hooks documentation
- Flask web framework
- Python requests library

---

## 📞 Support

- **Documentation**: See `docs/` directory
- **Issues**: Open an issue on GitHub
- **Email**: [your-email]

---

## 📝 Changelog

### Version 1.0.0 (2024-11-13)

**Initial Release**
- Git hooks for automatic Jira updates
- Smart commit parser
- Release notes generator
- Metrics and analytics
- Webhook server for Bitbucket/GitHub
- Auto reviewer assignment
- Comprehensive documentation

---

**Made with ❤️ for developers who love automation**
