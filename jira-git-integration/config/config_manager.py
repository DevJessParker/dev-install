#!/usr/bin/env python3
"""
Configuration Manager
Loads and validates configuration from environment and files
"""

import os
from pathlib import Path
from typing import Dict, Optional, List
import json


class ConfigManager:
    """Manage configuration for Jira Git Integration"""

    def __init__(self, env_file: str = None):
        """
        Initialize configuration manager

        Args:
            env_file: Path to .env file (optional)
        """
        self.env_file = env_file
        self.config = {}

        # Load from .env file if specified
        if env_file and Path(env_file).exists():
            self.load_env_file(env_file)

        # Load from environment variables
        self.load_from_env()

    def load_env_file(self, file_path: str):
        """Load configuration from .env file"""
        with open(file_path, 'r') as f:
            for line in f:
                line = line.strip()

                # Skip comments and empty lines
                if not line or line.startswith('#'):
                    continue

                # Parse KEY=VALUE
                if '=' in line:
                    key, value = line.split('=', 1)
                    key = key.strip()
                    value = value.strip()

                    # Remove quotes if present
                    if value.startswith('"') and value.endswith('"'):
                        value = value[1:-1]
                    elif value.startswith("'") and value.endswith("'"):
                        value = value[1:-1]

                    os.environ[key] = value

    def load_from_env(self):
        """Load configuration from environment variables"""
        self.config = {
            # Jira Configuration
            'jira': {
                'site': os.getenv('JIRA_SITE'),
                'email': os.getenv('JIRA_EMAIL'),
                'api_token': os.getenv('JIRA_API_TOKEN'),
                'default_project': os.getenv('JIRA_DEFAULT_PROJECT'),
            },

            # Hook Configuration
            'hooks': {
                'disabled': os.getenv('JIRA_HOOK_DISABLED', '0') == '1',
                'auto_transition_on_branch': os.getenv('JIRA_AUTO_TRANSITION_ON_BRANCH', 'false').lower() == 'true',
                'prepare_commit_disabled': os.getenv('JIRA_PREPARE_COMMIT_DISABLED', '0') == '1',
                'add_commit_template': os.getenv('JIRA_ADD_COMMIT_TEMPLATE', 'true').lower() == 'true',
                'commit_validation_disabled': os.getenv('JIRA_COMMIT_VALIDATION_DISABLED', '0') == '1',
                'require_issue_key': os.getenv('JIRA_REQUIRE_ISSUE_KEY', 'false').lower() == 'true',
                'warn_no_issue_key': os.getenv('JIRA_WARN_NO_ISSUE_KEY', 'true').lower() == 'true',
                'validate_commit_format': os.getenv('JIRA_VALIDATE_COMMIT_FORMAT', 'false').lower() == 'true',
            },

            # Webhook Configuration
            'webhook': {
                'host': os.getenv('WEBHOOK_HOST', '0.0.0.0'),
                'port': int(os.getenv('WEBHOOK_PORT', '5000')),
                'debug': os.getenv('WEBHOOK_DEBUG', 'false').lower() == 'true',
                'secret': os.getenv('BITBUCKET_WEBHOOK_SECRET', ''),
                'auto_transition_pr': os.getenv('JIRA_AUTO_TRANSITION_PR', 'true').lower() == 'true',
            },

            # Advanced Configuration
            'advanced': {
                'custom_transitions': self.parse_custom_transitions(
                    os.getenv('JIRA_CUSTOM_TRANSITIONS', '')
                ),
            }
        }

    def parse_custom_transitions(self, transitions_str: str) -> Dict[str, str]:
        """Parse custom transition mappings"""
        if not transitions_str:
            return {}

        transitions = {}
        for mapping in transitions_str.split(','):
            if ':' in mapping:
                keyword, status = mapping.split(':', 1)
                transitions[keyword.strip().lower()] = status.strip()

        return transitions

    def validate(self) -> List[str]:
        """
        Validate configuration

        Returns:
            List of validation errors (empty if valid)
        """
        errors = []

        # Check required Jira settings
        if not self.config['jira']['site']:
            errors.append("JIRA_SITE is required")

        if not self.config['jira']['email']:
            errors.append("JIRA_EMAIL is required")

        if not self.config['jira']['api_token']:
            errors.append("JIRA_API_TOKEN is required")

        # Validate Jira site format
        if self.config['jira']['site']:
            site = self.config['jira']['site']
            if site.startswith('http://') or site.startswith('https://'):
                errors.append("JIRA_SITE should not include http:// or https://")

        # Validate webhook port
        port = self.config['webhook']['port']
        if not (1 <= port <= 65535):
            errors.append(f"WEBHOOK_PORT must be between 1 and 65535 (got {port})")

        return errors

    def is_configured(self) -> bool:
        """Check if basic configuration is present"""
        return all([
            self.config['jira']['site'],
            self.config['jira']['email'],
            self.config['jira']['api_token']
        ])

    def get(self, key: str, default=None):
        """Get configuration value by dot notation"""
        parts = key.split('.')
        value = self.config

        for part in parts:
            if isinstance(value, dict) and part in value:
                value = value[part]
            else:
                return default

        return value

    def display_config(self, hide_secrets: bool = True) -> str:
        """Display current configuration"""
        output = "Current Configuration:\n"
        output += "=" * 60 + "\n\n"

        # Jira Configuration
        output += "Jira Settings:\n"
        output += f"  Site: {self.config['jira']['site'] or '(not set)'}\n"
        output += f"  Email: {self.config['jira']['email'] or '(not set)'}\n"

        if hide_secrets:
            token = self.config['jira']['api_token']
            if token:
                output += f"  API Token: {token[:4]}...{token[-4:] if len(token) > 8 else ''}\n"
            else:
                output += "  API Token: (not set)\n"
        else:
            output += f"  API Token: {self.config['jira']['api_token'] or '(not set)'}\n"

        if self.config['jira']['default_project']:
            output += f"  Default Project: {self.config['jira']['default_project']}\n"

        output += "\n"

        # Hook Configuration
        output += "Git Hook Settings:\n"
        hooks = self.config['hooks']
        output += f"  Hooks Disabled: {hooks['disabled']}\n"
        output += f"  Auto-transition on Branch: {hooks['auto_transition_on_branch']}\n"
        output += f"  Require Issue Key: {hooks['require_issue_key']}\n"
        output += f"  Warn No Issue Key: {hooks['warn_no_issue_key']}\n"
        output += f"  Validate Commit Format: {hooks['validate_commit_format']}\n"

        output += "\n"

        # Webhook Configuration
        output += "Webhook Server Settings:\n"
        webhook = self.config['webhook']
        output += f"  Host: {webhook['host']}\n"
        output += f"  Port: {webhook['port']}\n"
        output += f"  Debug: {webhook['debug']}\n"
        output += f"  Secret Configured: {bool(webhook['secret'])}\n"
        output += f"  Auto-transition PR: {webhook['auto_transition_pr']}\n"

        output += "\n"
        output += "=" * 60 + "\n"

        return output

    def export_to_file(self, file_path: str):
        """Export configuration to JSON file"""
        with open(file_path, 'w') as f:
            json.dump(self.config, f, indent=2)

    def create_example_env(self, file_path: str = '.env.example'):
        """Create example .env file"""
        example = """# Jira Git Integration Configuration
# Copy this file to .env and fill in your values

# Required: Jira Configuration
JIRA_SITE=yourcompany.atlassian.net
JIRA_EMAIL=your.email@company.com
JIRA_API_TOKEN=your_api_token_here

# Optional: Git Hook Configuration
JIRA_AUTO_TRANSITION_ON_BRANCH=false
JIRA_REQUIRE_ISSUE_KEY=false

# Optional: Webhook Server
WEBHOOK_PORT=5000
BITBUCKET_WEBHOOK_SECRET=

# See config.example.env for full configuration options
"""

        with open(file_path, 'w') as f:
            f.write(example)

        print(f"✓ Created example configuration: {file_path}")


def main():
    """Main execution - configuration tool"""
    import argparse

    parser = argparse.ArgumentParser(description='Configuration management')
    parser.add_argument('--env-file', help='Path to .env file')
    parser.add_argument('--validate', action='store_true', help='Validate configuration')
    parser.add_argument('--show', action='store_true', help='Show current configuration')
    parser.add_argument('--show-secrets', action='store_true', help='Show secrets in output')
    parser.add_argument('--create-example', action='store_true', help='Create example .env file')
    parser.add_argument('--export', help='Export configuration to JSON file')

    args = parser.parse_args()

    if args.create_example:
        manager = ConfigManager()
        manager.create_example_env()
        return

    # Load configuration
    manager = ConfigManager(args.env_file)

    if args.validate:
        errors = manager.validate()
        if errors:
            print("❌ Configuration errors:")
            for error in errors:
                print(f"  - {error}")
        else:
            print("✓ Configuration is valid")

    if args.show:
        print(manager.display_config(hide_secrets=not args.show_secrets))

    if args.export:
        manager.export_to_file(args.export)
        print(f"✓ Configuration exported to: {args.export}")

    if not any([args.validate, args.show, args.export]):
        # Default: show status
        if manager.is_configured():
            print("✓ Jira Git Integration is configured")
        else:
            print("⚠️  Jira Git Integration is not fully configured")
            print("\nMissing required settings:")
            errors = manager.validate()
            for error in errors:
                print(f"  - {error}")


if __name__ == '__main__':
    main()
