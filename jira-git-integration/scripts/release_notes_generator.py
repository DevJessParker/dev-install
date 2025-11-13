#!/usr/bin/env python3
"""
Release Notes Generator
Generates release notes from Git commits and Jira tickets
"""

import sys
import subprocess
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional
from collections import defaultdict

# Add lib directory to path
lib_path = Path(__file__).parent.parent / 'lib'
sys.path.insert(0, str(lib_path))

from jira_client import JiraClient
from smart_commit_parser import SmartCommitParser


class ReleaseNotesGenerator:
    """Generate release notes from Git and Jira"""

    def __init__(self):
        """Initialize generator"""
        self.parser = SmartCommitParser()
        self.jira_client = None

        try:
            self.jira_client = JiraClient()
        except ValueError:
            print("⚠️  Warning: Jira credentials not configured")
            print("   Release notes will be generated from Git commits only")

    def get_commits_since(self, since: str, until: str = 'HEAD') -> List[Dict]:
        """
        Get commits between two references

        Args:
            since: Starting reference (tag, commit, date)
            until: Ending reference

        Returns:
            List of commit information
        """
        try:
            # Format: hash|author|date|subject
            log_format = '%H|%an|%ad|%s'

            cmd = ['git', 'log', f'{since}..{until}', f'--pretty=format:{log_format}', '--date=short']

            output = subprocess.check_output(cmd, stderr=subprocess.STDOUT).decode().strip()

            commits = []
            for line in output.split('\n'):
                if not line:
                    continue

                parts = line.split('|', 3)
                if len(parts) == 4:
                    commits.append({
                        'hash': parts[0],
                        'author': parts[1],
                        'date': parts[2],
                        'message': parts[3]
                    })

            return commits

        except subprocess.CalledProcessError as e:
            print(f"Error getting commits: {e}")
            return []

    def get_tags(self) -> List[Dict]:
        """Get all Git tags with dates"""
        try:
            # Get tags with dates
            output = subprocess.check_output(
                ['git', 'tag', '-l', '--sort=-creatordate', '--format=%(refname:short)|%(creatordate:short)'],
                stderr=subprocess.STDOUT
            ).decode().strip()

            tags = []
            for line in output.split('\n'):
                if not line:
                    continue

                parts = line.split('|', 1)
                if len(parts) == 2:
                    tags.append({
                        'name': parts[0],
                        'date': parts[1]
                    })

            return tags

        except subprocess.CalledProcessError:
            return []

    def get_latest_tag(self) -> Optional[str]:
        """Get the most recent tag"""
        tags = self.get_tags()
        return tags[0]['name'] if tags else None

    def categorize_commits(self, commits: List[Dict]) -> Dict:
        """
        Categorize commits by type

        Args:
            commits: List of commits

        Returns:
            Categorized commits
        """
        categories = defaultdict(list)

        for commit in commits:
            # Parse commit message
            smart_commit = self.parser.parse(commit['message'])

            # Determine category from conventional commit format
            message = smart_commit.message
            category = 'Other'

            if ':' in message:
                prefix = message.split(':', 1)[0].strip().lower()

                if prefix.startswith('feat'):
                    category = 'Features'
                elif prefix.startswith('fix'):
                    category = 'Bug Fixes'
                elif prefix.startswith('docs'):
                    category = 'Documentation'
                elif prefix.startswith('perf'):
                    category = 'Performance'
                elif prefix.startswith('refactor'):
                    category = 'Refactoring'
                elif prefix.startswith('test'):
                    category = 'Testing'
                elif prefix.startswith('chore'):
                    category = 'Maintenance'
                elif prefix.startswith('ci') or prefix.startswith('build'):
                    category = 'CI/CD'

            categories[category].append({
                **commit,
                'parsed': smart_commit
            })

        return dict(categories)

    def enrich_with_jira(self, commits: List[Dict]) -> List[Dict]:
        """
        Enrich commits with Jira ticket information

        Args:
            commits: List of commits

        Returns:
            Enriched commits
        """
        if not self.jira_client:
            return commits

        enriched = []

        for commit in commits:
            parsed = commit.get('parsed')
            if not parsed or not parsed.issue_keys:
                enriched.append(commit)
                continue

            # Get Jira ticket details
            issue_key = parsed.issue_keys[0]  # Use first issue key
            try:
                issue = self.jira_client.get_issue(issue_key)
                if issue:
                    commit['jira'] = {
                        'key': issue_key,
                        'summary': issue['fields']['summary'],
                        'type': issue['fields']['issuetype']['name'],
                        'status': issue['fields']['status']['name'],
                        'priority': issue['fields'].get('priority', {}).get('name', 'None')
                    }
            except Exception as e:
                print(f"Warning: Could not fetch {issue_key}: {e}")

            enriched.append(commit)

        return enriched

    def generate_markdown(self, version: str, commits: List[Dict],
                         include_authors: bool = False,
                         include_commits: bool = False) -> str:
        """
        Generate markdown release notes

        Args:
            version: Version string
            commits: List of commits
            include_authors: Include commit authors
            include_commits: Include commit hashes

        Returns:
            Markdown string
        """
        # Categorize commits
        categorized = self.categorize_commits(commits)

        # Enrich with Jira
        for category in categorized:
            categorized[category] = self.enrich_with_jira(categorized[category])

        # Generate markdown
        md = f"# Release Notes - {version}\n\n"
        md += f"**Release Date:** {datetime.now().strftime('%Y-%m-%d')}\n\n"
        md += f"**Total Changes:** {len(commits)} commits\n\n"

        # Summary of changes by category
        md += "## Summary\n\n"
        for category, items in categorized.items():
            md += f"- {category}: {len(items)}\n"
        md += "\n---\n\n"

        # Detailed changes by category
        category_order = ['Features', 'Bug Fixes', 'Performance', 'Documentation',
                         'Refactoring', 'Testing', 'CI/CD', 'Maintenance', 'Other']

        for category in category_order:
            if category not in categorized:
                continue

            items = categorized[category]
            md += f"## {category}\n\n"

            for item in items:
                parsed = item.get('parsed')

                # Build entry
                entry = "- "

                # Add Jira reference if available
                if 'jira' in item:
                    jira = item['jira']
                    entry += f"**[{jira['key']}]** {jira['summary']}"

                    # Add type emoji
                    type_emoji = {
                        'Bug': '🐛',
                        'Story': '✨',
                        'Task': '📋',
                        'Epic': '🎯',
                        'Improvement': '⚡'
                    }
                    if jira['type'] in type_emoji:
                        entry = entry.replace('- ', f"- {type_emoji[jira['type']]} ")
                else:
                    # Use commit message
                    message = parsed.message if parsed else item['message']
                    # Remove conventional commit prefix
                    if ':' in message:
                        message = message.split(':', 1)[1].strip()
                    entry += message

                # Add commit hash if requested
                if include_commits:
                    entry += f" (`{item['hash'][:7]}`)"

                # Add author if requested
                if include_authors:
                    entry += f" - _{item['author']}_"

                md += entry + "\n"

            md += "\n"

        # Contributors section
        authors = set(commit['author'] for commit in commits)
        md += "## Contributors\n\n"
        md += f"Thank you to all {len(authors)} contributors:\n\n"
        for author in sorted(authors):
            md += f"- {author}\n"
        md += "\n"

        return md

    def generate_jira_release_notes(self, version: str, project: str,
                                   fix_version: str = None) -> str:
        """
        Generate release notes directly from Jira

        Args:
            version: Version string
            project: Jira project key
            fix_version: Jira fix version name

        Returns:
            Markdown string
        """
        if not self.jira_client:
            return "Error: Jira not configured"

        fix_version = fix_version or version

        # Query Jira for issues in this version
        jql = f'project = {project} AND fixVersion = "{fix_version}" ORDER BY type DESC, priority DESC'

        try:
            result = self.jira_client.search_issues(jql, max_results=200)
            if not result or not result.get('issues'):
                return f"No issues found for version {fix_version}"

            issues = result['issues']

            # Categorize by type
            by_type = defaultdict(list)
            for issue in issues:
                issue_type = issue['fields']['issuetype']['name']
                by_type[issue_type].append(issue)

            # Generate markdown
            md = f"# Release Notes - {version}\n\n"
            md += f"**Release Date:** {datetime.now().strftime('%Y-%m-%d')}\n\n"
            md += f"**Project:** {project}\n\n"
            md += f"**Total Issues:** {len(issues)}\n\n"

            # Summary
            md += "## Summary\n\n"
            for issue_type, items in by_type.items():
                md += f"- {issue_type}: {len(items)}\n"
            md += "\n---\n\n"

            # Details by type
            type_order = ['Epic', 'Story', 'Feature', 'Improvement', 'Bug', 'Task', 'Sub-task']

            for issue_type in type_order:
                if issue_type not in by_type:
                    continue

                items = by_type[issue_type]
                md += f"## {issue_type}s\n\n"

                for issue in items:
                    key = issue['key']
                    summary = issue['fields']['summary']
                    priority = issue['fields'].get('priority', {}).get('name', 'None')

                    # Priority emoji
                    priority_emoji = {
                        'Highest': '🔴',
                        'High': '🟠',
                        'Medium': '🟡',
                        'Low': '🟢',
                        'Lowest': '⚪'
                    }

                    emoji = priority_emoji.get(priority, '')

                    md += f"- {emoji} **[{key}]** {summary}\n"

                md += "\n"

            return md

        except Exception as e:
            return f"Error generating Jira release notes: {e}"


def main():
    """Main execution"""
    import argparse

    parser = argparse.ArgumentParser(description='Generate release notes')
    parser.add_argument('--version', required=True, help='Version string (e.g., v2.4.0)')
    parser.add_argument('--since', help='Starting reference (tag, commit, or date)')
    parser.add_argument('--until', default='HEAD', help='Ending reference')
    parser.add_argument('--output', help='Output file (default: stdout)')
    parser.add_argument('--authors', action='store_true', help='Include commit authors')
    parser.add_argument('--commits', action='store_true', help='Include commit hashes')
    parser.add_argument('--jira-only', action='store_true', help='Generate from Jira only')
    parser.add_argument('--project', help='Jira project key (required for --jira-only)')
    parser.add_argument('--fix-version', help='Jira fix version (defaults to --version)')

    args = parser.parse_args()

    generator = ReleaseNotesGenerator()

    # Generate release notes
    if args.jira_only:
        if not args.project:
            print("Error: --project required with --jira-only")
            sys.exit(1)

        markdown = generator.generate_jira_release_notes(
            args.version,
            args.project,
            args.fix_version
        )
    else:
        # Determine starting point
        since = args.since
        if not since:
            # Use latest tag
            since = generator.get_latest_tag()
            if not since:
                print("Error: No previous tag found. Use --since to specify starting point")
                sys.exit(1)
            print(f"📌 Using latest tag as starting point: {since}")

        # Get commits
        print(f"📝 Generating release notes: {since}..{args.until}")
        commits = generator.get_commits_since(since, args.until)

        if not commits:
            print("No commits found in range")
            sys.exit(0)

        print(f"   Found {len(commits)} commits")

        markdown = generator.generate_markdown(
            args.version,
            commits,
            args.authors,
            args.commits
        )

    # Output
    if args.output:
        with open(args.output, 'w') as f:
            f.write(markdown)
        print(f"✓ Release notes saved to: {args.output}")
    else:
        print("\n" + "=" * 60)
        print(markdown)
        print("=" * 60)


if __name__ == '__main__':
    main()
