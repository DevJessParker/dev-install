#!/bin/bash
###############################################################################
# Jira Git Integration - Installation Script
#
# This script installs Git hooks and sets up the Jira Git Integration system
###############################################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"

###############################################################################
# Helper Functions
###############################################################################

print_header() {
    echo -e "${BLUE}"
    echo "═══════════════════════════════════════════════════════════════"
    echo "  $1"
    echo "═══════════════════════════════════════════════════════════════"
    echo -e "${NC}"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

###############################################################################
# Pre-flight Checks
###############################################################################

check_requirements() {
    print_header "Checking Requirements"

    # Check if in git repository
    if [ -z "$GIT_ROOT" ]; then
        print_error "Not in a Git repository"
        exit 1
    fi
    print_success "Git repository detected: $GIT_ROOT"

    # Check Python
    if ! command -v python3 &> /dev/null; then
        print_error "Python 3 is required but not installed"
        exit 1
    fi
    PYTHON_VERSION=$(python3 --version | awk '{print $2}')
    print_success "Python 3 found: $PYTHON_VERSION"

    # Check required Python packages
    print_info "Checking Python packages..."
    REQUIRED_PACKAGES=("requests" "flask")
    MISSING_PACKAGES=()

    for package in "${REQUIRED_PACKAGES[@]}"; do
        if ! python3 -c "import $package" 2>/dev/null; then
            MISSING_PACKAGES+=("$package")
        fi
    done

    if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
        print_warning "Missing Python packages: ${MISSING_PACKAGES[*]}"
        echo -n "Install missing packages? [y/N] "
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            pip3 install "${MISSING_PACKAGES[@]}"
            print_success "Packages installed"
        else
            print_error "Required packages not installed. Installation aborted."
            exit 1
        fi
    else
        print_success "All required packages installed"
    fi

    echo
}

###############################################################################
# Configuration
###############################################################################

setup_configuration() {
    print_header "Configuration Setup"

    ENV_FILE="$GIT_ROOT/.env"

    if [ -f "$ENV_FILE" ]; then
        print_info "Configuration file already exists: $ENV_FILE"
        echo -n "Do you want to reconfigure? [y/N] "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            print_info "Skipping configuration"
            echo
            return
        fi
    fi

    # Copy example config
    if [ ! -f "$ENV_FILE" ]; then
        cp "$SCRIPT_DIR/config/config.example.env" "$ENV_FILE"
        print_success "Created configuration file: $ENV_FILE"
    fi

    # Prompt for configuration
    echo
    echo "Please provide your Jira credentials:"
    echo "(Press Enter to skip and configure manually later)"
    echo

    # Jira Site
    read -p "Jira Site (e.g., yourcompany.atlassian.net): " jira_site
    if [ -n "$jira_site" ]; then
        # Remove https:// if present
        jira_site=$(echo "$jira_site" | sed 's|https\?://||')
        sed -i.bak "s|^JIRA_SITE=.*|JIRA_SITE=$jira_site|" "$ENV_FILE"
    fi

    # Jira Email
    read -p "Jira Email: " jira_email
    if [ -n "$jira_email" ]; then
        sed -i.bak "s|^JIRA_EMAIL=.*|JIRA_EMAIL=$jira_email|" "$ENV_FILE"
    fi

    # Jira API Token
    echo
    print_info "Generate API token at: https://id.atlassian.com/manage-profile/security/api-tokens"
    read -sp "Jira API Token: " jira_token
    echo
    if [ -n "$jira_token" ]; then
        sed -i.bak "s|^JIRA_API_TOKEN=.*|JIRA_API_TOKEN=$jira_token|" "$ENV_FILE"
    fi

    # Remove backup file
    rm -f "$ENV_FILE.bak"

    # Add .env to .gitignore
    if [ -f "$GIT_ROOT/.gitignore" ]; then
        if ! grep -q "^\.env$" "$GIT_ROOT/.gitignore"; then
            echo ".env" >> "$GIT_ROOT/.gitignore"
            print_success "Added .env to .gitignore"
        fi
    else
        echo ".env" > "$GIT_ROOT/.gitignore"
        print_success "Created .gitignore with .env"
    fi

    echo
    print_success "Configuration saved to: $ENV_FILE"
    print_warning "Keep this file secure - it contains your API token!"
    echo
}

###############################################################################
# Git Hooks Installation
###############################################################################

install_git_hooks() {
    print_header "Installing Git Hooks"

    HOOKS_DIR="$GIT_ROOT/.git/hooks"

    if [ ! -d "$HOOKS_DIR" ]; then
        print_error "Git hooks directory not found: $HOOKS_DIR"
        exit 1
    fi

    # Hooks to install
    HOOKS=("post-commit" "post-checkout" "prepare-commit-msg" "commit-msg")

    for hook in "${HOOKS[@]}"; do
        SOURCE="$SCRIPT_DIR/hooks/$hook"
        TARGET="$HOOKS_DIR/$hook"

        if [ ! -f "$SOURCE" ]; then
            print_warning "Hook not found: $hook"
            continue
        fi

        # Backup existing hook
        if [ -f "$TARGET" ]; then
            if [ ! -f "$TARGET.backup" ]; then
                cp "$TARGET" "$TARGET.backup"
                print_info "Backed up existing $hook to $hook.backup"
            fi
        fi

        # Copy hook
        cp "$SOURCE" "$TARGET"
        chmod +x "$TARGET"
        print_success "Installed: $hook"
    done

    echo
    print_success "Git hooks installed successfully!"
    echo
}

###############################################################################
# Create Helper Scripts
###############################################################################

create_helper_scripts() {
    print_header "Creating Helper Scripts"

    # Create bin directory
    BIN_DIR="$GIT_ROOT/bin"
    mkdir -p "$BIN_DIR"

    # Release notes script
    cat > "$BIN_DIR/generate-release-notes" << 'EOF'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INTEGRATION_DIR="$SCRIPT_DIR/../jira-git-integration"

source "$SCRIPT_DIR/../.env" 2>/dev/null || true

python3 "$INTEGRATION_DIR/scripts/release_notes_generator.py" "$@"
EOF
    chmod +x "$BIN_DIR/generate-release-notes"
    print_success "Created: bin/generate-release-notes"

    # Metrics script
    cat > "$BIN_DIR/generate-metrics" << 'EOF'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INTEGRATION_DIR="$SCRIPT_DIR/../jira-git-integration"

source "$SCRIPT_DIR/../.env" 2>/dev/null || true

python3 "$INTEGRATION_DIR/analytics/metrics_reporter.py" "$@"
EOF
    chmod +x "$BIN_DIR/generate-metrics"
    print_success "Created: bin/generate-metrics"

    # Auto reviewer script
    cat > "$BIN_DIR/assign-reviewers" << 'EOF'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INTEGRATION_DIR="$SCRIPT_DIR/../jira-git-integration"

python3 "$INTEGRATION_DIR/scripts/auto_reviewer_assignment.py" "$@"
EOF
    chmod +x "$BIN_DIR/assign-reviewers"
    print_success "Created: bin/assign-reviewers"

    # Webhook server script
    cat > "$BIN_DIR/start-webhook-server" << 'EOF'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INTEGRATION_DIR="$SCRIPT_DIR/../jira-git-integration"

source "$SCRIPT_DIR/../.env" 2>/dev/null || true

echo "Starting Jira Git Integration Webhook Server..."
python3 "$INTEGRATION_DIR/webhooks/bitbucket_webhook_server.py"
EOF
    chmod +x "$BIN_DIR/start-webhook-server"
    print_success "Created: bin/start-webhook-server"

    # Add bin to gitignore
    if [ -f "$GIT_ROOT/.gitignore" ]; then
        if ! grep -q "^bin/$" "$GIT_ROOT/.gitignore"; then
            echo "bin/" >> "$GIT_ROOT/.gitignore"
        fi
    fi

    echo
}

###############################################################################
# Verify Installation
###############################################################################

verify_installation() {
    print_header "Verifying Installation"

    # Check hooks
    HOOKS_OK=true
    for hook in post-commit post-checkout prepare-commit-msg commit-msg; do
        if [ ! -x "$GIT_ROOT/.git/hooks/$hook" ]; then
            print_error "Hook not executable: $hook"
            HOOKS_OK=false
        fi
    done

    if $HOOKS_OK; then
        print_success "All Git hooks installed and executable"
    fi

    # Check configuration
    if [ -f "$GIT_ROOT/.env" ]; then
        source "$GIT_ROOT/.env"

        if [ -z "$JIRA_SITE" ] || [ -z "$JIRA_EMAIL" ] || [ -z "$JIRA_API_TOKEN" ]; then
            print_warning "Configuration incomplete - please edit .env file"
        else
            print_success "Configuration appears complete"
        fi
    else
        print_warning "No configuration file found"
    fi

    echo
}

###############################################################################
# Print Usage Instructions
###############################################################################

print_usage() {
    print_header "Installation Complete!"

    echo "Jira Git Integration has been installed successfully!"
    echo
    echo "Next Steps:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    echo "1. Configure Jira credentials (if not done already):"
    echo "   Edit: $GIT_ROOT/.env"
    echo
    echo "2. Test your configuration:"
    echo "   cd $GIT_ROOT"
    echo "   python3 jira-git-integration/lib/jira_client.py"
    echo
    echo "3. Start using smart commits:"
    echo "   git commit -m \"[ISSUE-123] feat: new feature #time 2h #in-review\""
    echo
    echo "4. Generate release notes:"
    echo "   ./bin/generate-release-notes --version v2.0.0"
    echo
    echo "5. Generate metrics:"
    echo "   ./bin/generate-metrics --days 30 --project YOUR-PROJECT"
    echo
    echo "6. Start webhook server (optional):"
    echo "   ./bin/start-webhook-server"
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    echo "Documentation: jira-git-integration/docs/"
    echo "Configuration: $GIT_ROOT/.env"
    echo
    print_success "Happy coding! 🚀"
    echo
}

###############################################################################
# Uninstall
###############################################################################

uninstall() {
    print_header "Uninstalling Jira Git Integration"

    echo "This will remove all Git hooks and helper scripts."
    echo -n "Are you sure? [y/N] "
    read -r response

    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        print_info "Uninstall cancelled"
        exit 0
    fi

    # Remove hooks
    HOOKS_DIR="$GIT_ROOT/.git/hooks"
    for hook in post-commit post-checkout prepare-commit-msg commit-msg; do
        if [ -f "$HOOKS_DIR/$hook" ]; then
            rm "$HOOKS_DIR/$hook"
            print_success "Removed: $hook"

            # Restore backup if exists
            if [ -f "$HOOKS_DIR/$hook.backup" ]; then
                mv "$HOOKS_DIR/$hook.backup" "$HOOKS_DIR/$hook"
                print_info "Restored backup: $hook"
            fi
        fi
    done

    # Remove helper scripts
    if [ -d "$GIT_ROOT/bin" ]; then
        rm -rf "$GIT_ROOT/bin"
        print_success "Removed: bin/"
    fi

    print_success "Uninstall complete"
    print_info "Configuration (.env) was preserved"
    echo
}

###############################################################################
# Main Installation Flow
###############################################################################

main() {
    # Parse arguments
    case "${1:-}" in
        --uninstall)
            uninstall
            exit 0
            ;;
        --help)
            echo "Usage: $0 [--uninstall] [--help]"
            echo
            echo "Options:"
            echo "  --uninstall  Remove Git hooks and helper scripts"
            echo "  --help       Show this help message"
            exit 0
            ;;
    esac

    print_header "Jira Git Integration Installer"
    echo

    # Run installation steps
    check_requirements
    setup_configuration
    install_git_hooks
    create_helper_scripts
    verify_installation
    print_usage
}

# Run main function
main "$@"
