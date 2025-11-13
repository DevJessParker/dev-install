#!/usr/bin/env python3
"""
Automatic Reviewer Assignment
Assigns reviewers based on files changed in pull request
"""

import sys
import json
import subprocess
from pathlib import Path
from typing import Dict, List, Set

# Add lib directory to path
lib_path = Path(__file__).parent.parent / 'lib'
sys.path.insert(0, str(lib_path))


class ReviewerAssigner:
    """Automatically assigns reviewers based on code ownership"""

    def __init__(self, config_file: str = None):
        """
        Initialize reviewer assigner

        Args:
            config_file: Path to reviewer configuration file
        """
        self.config_file = config_file or 'reviewer_config.json'
        self.rules = self.load_config()

    def load_config(self) -> Dict:
        """Load reviewer assignment rules"""
        default_config = {
            "rules": [
                {
                    "name": "Backend changes",
                    "patterns": ["**/*.cs", "**/*.java", "**/*.py", "**/api/**"],
                    "reviewers": ["backend-lead"],
                    "required": 1
                },
                {
                    "name": "Frontend changes",
                    "patterns": ["**/*.ts", "**/*.tsx", "**/*.jsx", "**/*.vue"],
                    "reviewers": ["frontend-lead"],
                    "required": 1
                },
                {
                    "name": "Database migrations",
                    "patterns": ["**/migrations/**", "**/*.sql"],
                    "reviewers": ["database-admin", "backend-lead"],
                    "required": 2
                },
                {
                    "name": "Infrastructure changes",
                    "patterns": ["**/Dockerfile", "**/*.yml", "**/*.yaml", "**/terraform/**"],
                    "reviewers": ["devops-lead"],
                    "required": 1
                },
                {
                    "name": "Security sensitive",
                    "patterns": ["**/auth/**", "**/security/**", "**/credentials/**"],
                    "reviewers": ["security-lead", "tech-lead"],
                    "required": 2
                },
                {
                    "name": "Documentation",
                    "patterns": ["**/*.md", "**/docs/**"],
                    "reviewers": ["tech-writer"],
                    "required": 1
                }
            ],
            "default_reviewers": ["team-lead"],
            "max_reviewers": 3
        }

        try:
            if Path(self.config_file).exists():
                with open(self.config_file, 'r') as f:
                    return json.load(f)
        except Exception as e:
            print(f"Warning: Could not load config: {e}")

        return default_config

    def get_changed_files(self, base_branch: str = 'main') -> List[str]:
        """
        Get list of files changed in current branch

        Args:
            base_branch: Base branch to compare against

        Returns:
            List of changed file paths
        """
        try:
            # Get diff from base branch
            output = subprocess.check_output(
                ['git', 'diff', '--name-only', f'{base_branch}...HEAD'],
                stderr=subprocess.STDOUT
            ).decode().strip()

            return output.split('\n') if output else []

        except subprocess.CalledProcessError as e:
            print(f"Error getting changed files: {e}")
            return []

    def match_pattern(self, file_path: str, pattern: str) -> bool:
        """
        Check if file matches pattern (glob-style)

        Args:
            file_path: File path to check
            pattern: Glob pattern

        Returns:
            True if matches
        """
        from fnmatch import fnmatch
        return fnmatch(file_path, pattern)

    def assign_reviewers(self, files: List[str] = None, base_branch: str = 'main') -> Dict:
        """
        Assign reviewers based on changed files

        Args:
            files: List of changed files (if None, auto-detect)
            base_branch: Base branch for comparison

        Returns:
            Dictionary with reviewer assignments
        """
        if files is None:
            files = self.get_changed_files(base_branch)

        if not files:
            return {
                'reviewers': self.rules.get('default_reviewers', []),
                'rules_matched': [],
                'files_analyzed': 0
            }

        reviewers: Set[str] = set()
        rules_matched: List[Dict] = []

        # Check each rule
        for rule in self.rules.get('rules', []):
            matched_files = []

            for file_path in files:
                for pattern in rule.get('patterns', []):
                    if self.match_pattern(file_path, pattern):
                        matched_files.append(file_path)
                        break

            if matched_files:
                rule_reviewers = rule.get('reviewers', [])
                required = rule.get('required', 1)

                # Add reviewers up to required amount
                added = 0
                for reviewer in rule_reviewers:
                    if reviewer not in reviewers:
                        reviewers.add(reviewer)
                        added += 1
                        if added >= required:
                            break

                rules_matched.append({
                    'name': rule.get('name'),
                    'matched_files': matched_files,
                    'reviewers_added': list(rule_reviewers[:required])
                })

        # If no rules matched, use default reviewers
        if not reviewers:
            reviewers.update(self.rules.get('default_reviewers', []))

        # Limit to max reviewers
        max_reviewers = self.rules.get('max_reviewers', 3)
        final_reviewers = list(reviewers)[:max_reviewers]

        return {
            'reviewers': final_reviewers,
            'rules_matched': rules_matched,
            'files_analyzed': len(files)
        }

    def generate_config_template(self, output_file: str = 'reviewer_config.json'):
        """Generate a configuration template"""
        template = {
            "_description": "Reviewer assignment configuration",
            "_instructions": "Patterns use glob syntax. ** matches directories, * matches files.",
            "rules": [
                {
                    "name": "Backend API changes",
                    "patterns": ["**/api/**/*.cs", "**/controllers/**"],
                    "reviewers": ["backend-dev-1", "backend-dev-2"],
                    "required": 1
                }
            ],
            "default_reviewers": ["team-lead"],
            "max_reviewers": 3
        }

        with open(output_file, 'w') as f:
            json.dump(template, f, indent=2)

        print(f"✓ Generated config template: {output_file}")


def main():
    """Main execution"""
    import argparse

    parser = argparse.ArgumentParser(description='Automatic reviewer assignment')
    parser.add_argument('--config', help='Path to reviewer config file')
    parser.add_argument('--base-branch', default='main', help='Base branch for comparison')
    parser.add_argument('--generate-config', action='store_true', help='Generate config template')
    parser.add_argument('--json', action='store_true', help='Output as JSON')

    args = parser.parse_args()

    assigner = ReviewerAssigner(args.config)

    if args.generate_config:
        assigner.generate_config_template()
        return

    # Assign reviewers
    result = assigner.assign_reviewers(base_branch=args.base_branch)

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        print("\n📋 Reviewer Assignment\n")
        print(f"Files analyzed: {result['files_analyzed']}")
        print(f"\nRecommended reviewers: {', '.join(result['reviewers'])}")

        if result['rules_matched']:
            print("\nRules matched:")
            for rule in result['rules_matched']:
                print(f"  • {rule['name']}")
                print(f"    Files: {len(rule['matched_files'])}")
                print(f"    Reviewers: {', '.join(rule['reviewers_added'])}")


if __name__ == '__main__':
    main()
