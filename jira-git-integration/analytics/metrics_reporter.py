#!/usr/bin/env python3
"""
Metrics Reporter
Generates development metrics from Git and Jira
"""

import sys
import subprocess
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional
from collections import defaultdict, Counter
import json

# Add lib directory to path
lib_path = Path(__file__).parent.parent / 'lib'
sys.path.insert(0, str(lib_path))

from jira_client import JiraClient
from smart_commit_parser import SmartCommitParser


class MetricsReporter:
    """Generate development metrics and analytics"""

    def __init__(self):
        """Initialize reporter"""
        self.parser = SmartCommitParser()
        self.jira_client = None

        try:
            self.jira_client = JiraClient()
        except ValueError:
            pass

    def get_commits_in_range(self, since: str, until: str = 'HEAD') -> List[Dict]:
        """Get commits in date range"""
        try:
            log_format = '%H|%an|%ae|%ad|%s|%ar'

            cmd = ['git', 'log', f'--since={since}', f'--until={until}',
                  f'--pretty=format:{log_format}', '--date=iso']

            output = subprocess.check_output(cmd, stderr=subprocess.STDOUT).decode().strip()

            commits = []
            for line in output.split('\n'):
                if not line:
                    continue

                parts = line.split('|', 5)
                if len(parts) == 6:
                    # Get stats for this commit
                    stats = self.get_commit_stats(parts[0])

                    commits.append({
                        'hash': parts[0],
                        'author': parts[1],
                        'email': parts[2],
                        'date': parts[3],
                        'message': parts[4],
                        'relative_date': parts[5],
                        'files_changed': stats['files'],
                        'insertions': stats['insertions'],
                        'deletions': stats['deletions']
                    })

            return commits

        except subprocess.CalledProcessError as e:
            print(f"Error getting commits: {e}")
            return []

    def get_commit_stats(self, commit_hash: str) -> Dict:
        """Get statistics for a specific commit"""
        try:
            output = subprocess.check_output(
                ['git', 'show', '--stat', '--format=', commit_hash],
                stderr=subprocess.STDOUT
            ).decode().strip()

            files = 0
            insertions = 0
            deletions = 0

            for line in output.split('\n'):
                if '|' in line:
                    files += 1
                    # Parse insertions and deletions
                    if '+' in line or '-' in line:
                        parts = line.split('|')[1].strip()
                        insertions += parts.count('+')
                        deletions += parts.count('-')

            return {
                'files': files,
                'insertions': insertions,
                'deletions': deletions
            }

        except subprocess.CalledProcessError:
            return {'files': 0, 'insertions': 0, 'deletions': 0}

    def generate_commit_metrics(self, days: int = 30) -> Dict:
        """
        Generate commit-based metrics

        Args:
            days: Number of days to analyze

        Returns:
            Metrics dictionary
        """
        since = f"{days} days ago"
        commits = self.get_commits_in_range(since)

        if not commits:
            return {}

        # Calculate metrics
        total_commits = len(commits)
        total_files = sum(c['files_changed'] for c in commits)
        total_insertions = sum(c['insertions'] for c in commits)
        total_deletions = sum(c['deletions'] for c in commits)

        # Author metrics
        commits_by_author = Counter(c['author'] for c in commits)
        lines_by_author = defaultdict(lambda: {'insertions': 0, 'deletions': 0})

        for commit in commits:
            author = commit['author']
            lines_by_author[author]['insertions'] += commit['insertions']
            lines_by_author[author]['deletions'] += commit['deletions']

        # Commit frequency by day
        commits_by_day = defaultdict(int)
        for commit in commits:
            date = commit['date'].split()[0]
            commits_by_day[date] += 1

        # Average commit size
        avg_files = total_files / total_commits if total_commits else 0
        avg_insertions = total_insertions / total_commits if total_commits else 0
        avg_deletions = total_deletions / total_commits if total_commits else 0

        # Churn rate (deletions / total lines)
        total_lines = total_insertions + total_deletions
        churn_rate = (total_deletions / total_lines * 100) if total_lines else 0

        return {
            'period': f'{days} days',
            'total_commits': total_commits,
            'total_files_changed': total_files,
            'total_insertions': total_insertions,
            'total_deletions': total_deletions,
            'net_lines': total_insertions - total_deletions,
            'avg_files_per_commit': round(avg_files, 1),
            'avg_insertions_per_commit': round(avg_insertions, 1),
            'avg_deletions_per_commit': round(avg_deletions, 1),
            'churn_rate': round(churn_rate, 1),
            'unique_authors': len(commits_by_author),
            'commits_per_day': round(total_commits / days, 1),
            'top_contributors': [
                {'author': author, 'commits': count}
                for author, count in commits_by_author.most_common(10)
            ],
            'author_stats': [
                {
                    'author': author,
                    'commits': commits_by_author[author],
                    'insertions': stats['insertions'],
                    'deletions': stats['deletions'],
                    'net_lines': stats['insertions'] - stats['deletions']
                }
                for author, stats in sorted(
                    lines_by_author.items(),
                    key=lambda x: x[1]['insertions'] + x[1]['deletions'],
                    reverse=True
                )
            ][:10]
        }

    def generate_jira_metrics(self, project: str, days: int = 30) -> Dict:
        """
        Generate Jira-based metrics

        Args:
            project: Jira project key
            days: Number of days to analyze

        Returns:
            Metrics dictionary
        """
        if not self.jira_client:
            return {'error': 'Jira not configured'}

        start_date = (datetime.now() - timedelta(days=days)).strftime('%Y-%m-%d')

        # Query for issues
        jql_created = f'project = {project} AND created >= "{start_date}" ORDER BY created DESC'
        jql_resolved = f'project = {project} AND resolved >= "{start_date}" ORDER BY resolved DESC'
        jql_in_progress = f'project = {project} AND status = "In Progress"'

        try:
            created = self.jira_client.search_issues(jql_created, max_results=500)
            resolved = self.jira_client.search_issues(jql_resolved, max_results=500)
            in_progress = self.jira_client.search_issues(jql_in_progress, max_results=100)

            created_issues = created.get('issues', []) if created else []
            resolved_issues = resolved.get('issues', []) if resolved else []
            in_progress_issues = in_progress.get('issues', []) if in_progress else []

            # Issue type distribution
            issue_types = Counter(
                issue['fields']['issuetype']['name']
                for issue in created_issues
            )

            # Priority distribution
            priorities = Counter(
                issue['fields'].get('priority', {}).get('name', 'None')
                for issue in created_issues
            )

            # Calculate cycle times for resolved issues
            cycle_times = []
            for issue in resolved_issues:
                created = issue['fields']['created']
                resolved = issue['fields']['resolved']

                if created and resolved:
                    created_dt = datetime.fromisoformat(created.replace('Z', '+00:00'))
                    resolved_dt = datetime.fromisoformat(resolved.replace('Z', '+00:00'))
                    cycle_time = (resolved_dt - created_dt).total_seconds() / 3600  # hours
                    cycle_times.append(cycle_time)

            avg_cycle_time = sum(cycle_times) / len(cycle_times) if cycle_times else 0

            # Time in status (for resolved issues)
            time_in_status = defaultdict(list)
            for issue in resolved_issues[:50]:  # Limit to avoid API overload
                changelog = self.jira_client.get_issue_changelog(issue['key'])
                if not changelog:
                    continue

                status_times = {}
                last_status = None
                last_time = None

                for history in changelog.get('values', []):
                    for item in history.get('items', []):
                        if item['field'] == 'status':
                            current_time = datetime.fromisoformat(
                                history['created'].replace('Z', '+00:00')
                            )

                            if last_status and last_time:
                                duration = (current_time - last_time).total_seconds() / 3600
                                time_in_status[last_status].append(duration)

                            last_status = item['toString']
                            last_time = current_time

            avg_time_in_status = {
                status: round(sum(times) / len(times), 1)
                for status, times in time_in_status.items()
            }

            return {
                'period': f'{days} days',
                'project': project,
                'issues_created': len(created_issues),
                'issues_resolved': len(resolved_issues),
                'issues_in_progress': len(in_progress_issues),
                'resolution_rate': round(len(resolved_issues) / len(created_issues) * 100, 1)
                    if created_issues else 0,
                'avg_cycle_time_hours': round(avg_cycle_time, 1),
                'avg_cycle_time_days': round(avg_cycle_time / 24, 1),
                'issue_types': dict(issue_types),
                'priorities': dict(priorities),
                'avg_time_in_status': avg_time_in_status
            }

        except Exception as e:
            return {'error': str(e)}

    def generate_pr_metrics(self, days: int = 30) -> Dict:
        """
        Generate pull request metrics (from branch patterns)

        Args:
            days: Number of days to analyze

        Returns:
            Metrics dictionary
        """
        since = f"{days} days ago"

        try:
            # Get all merged branches
            output = subprocess.check_output(
                ['git', 'branch', '-r', '--merged', 'main', '--format=%(refname:short)'],
                stderr=subprocess.STDOUT
            ).decode().strip()

            branches = [b.strip() for b in output.split('\n') if b.strip()]

            # Filter feature branches
            feature_branches = [
                b for b in branches
                if not b.endswith('/main') and not b.endswith('/master')
            ]

            # Get commits per branch
            commits_per_branch = []
            for branch in feature_branches[:50]:  # Limit to recent branches
                try:
                    commit_count = subprocess.check_output(
                        ['git', 'rev-list', '--count', f'{branch}', '--since', since],
                        stderr=subprocess.STDOUT
                    ).decode().strip()

                    if int(commit_count) > 0:
                        commits_per_branch.append(int(commit_count))

                except subprocess.CalledProcessError:
                    continue

            avg_commits_per_branch = (sum(commits_per_branch) / len(commits_per_branch)
                                     if commits_per_branch else 0)

            return {
                'period': f'{days} days',
                'merged_branches': len(feature_branches),
                'avg_commits_per_branch': round(avg_commits_per_branch, 1),
                'merge_frequency': round(len(feature_branches) / days, 1)
            }

        except subprocess.CalledProcessError:
            return {}

    def format_report(self, commit_metrics: Dict, jira_metrics: Dict = None,
                     pr_metrics: Dict = None) -> str:
        """Format metrics as readable report"""
        report = "=" * 60 + "\n"
        report += "DEVELOPMENT METRICS REPORT\n"
        report += "=" * 60 + "\n\n"

        # Git/Commit Metrics
        if commit_metrics:
            report += "📊 COMMIT METRICS\n"
            report += "-" * 60 + "\n"
            report += f"Period: {commit_metrics['period']}\n"
            report += f"Total Commits: {commit_metrics['total_commits']}\n"
            report += f"Commits per Day: {commit_metrics['commits_per_day']}\n"
            report += f"Unique Authors: {commit_metrics['unique_authors']}\n\n"

            report += f"Code Changes:\n"
            report += f"  Files Changed: {commit_metrics['total_files_changed']}\n"
            report += f"  Lines Added: +{commit_metrics['total_insertions']}\n"
            report += f"  Lines Removed: -{commit_metrics['total_deletions']}\n"
            report += f"  Net Lines: {commit_metrics['net_lines']:+d}\n"
            report += f"  Code Churn: {commit_metrics['churn_rate']}%\n\n"

            report += f"Averages per Commit:\n"
            report += f"  Files: {commit_metrics['avg_files_per_commit']}\n"
            report += f"  Insertions: {commit_metrics['avg_insertions_per_commit']}\n"
            report += f"  Deletions: {commit_metrics['avg_deletions_per_commit']}\n\n"

            report += "Top Contributors:\n"
            for contrib in commit_metrics['top_contributors'][:5]:
                report += f"  {contrib['author']}: {contrib['commits']} commits\n"

            report += "\n"

        # Jira Metrics
        if jira_metrics and 'error' not in jira_metrics:
            report += "🎯 JIRA METRICS\n"
            report += "-" * 60 + "\n"
            report += f"Project: {jira_metrics['project']}\n"
            report += f"Period: {jira_metrics['period']}\n\n"

            report += f"Issues:\n"
            report += f"  Created: {jira_metrics['issues_created']}\n"
            report += f"  Resolved: {jira_metrics['issues_resolved']}\n"
            report += f"  In Progress: {jira_metrics['issues_in_progress']}\n"
            report += f"  Resolution Rate: {jira_metrics['resolution_rate']}%\n\n"

            report += f"Cycle Time:\n"
            report += f"  Average: {jira_metrics['avg_cycle_time_days']} days\n"
            report += f"          ({jira_metrics['avg_cycle_time_hours']} hours)\n\n"

            if jira_metrics.get('issue_types'):
                report += "Issue Types:\n"
                for itype, count in jira_metrics['issue_types'].items():
                    report += f"  {itype}: {count}\n"
                report += "\n"

        # PR Metrics
        if pr_metrics:
            report += "🔀 PULL REQUEST METRICS\n"
            report += "-" * 60 + "\n"
            report += f"Period: {pr_metrics['period']}\n"
            report += f"Merged Branches: {pr_metrics['merged_branches']}\n"
            report += f"Avg Commits per Branch: {pr_metrics['avg_commits_per_branch']}\n"
            report += f"Merge Frequency: {pr_metrics['merge_frequency']} per day\n\n"

        report += "=" * 60 + "\n"

        return report


def main():
    """Main execution"""
    import argparse

    parser = argparse.ArgumentParser(description='Generate development metrics')
    parser.add_argument('--days', type=int, default=30, help='Number of days to analyze')
    parser.add_argument('--project', help='Jira project key')
    parser.add_argument('--json', action='store_true', help='Output as JSON')
    parser.add_argument('--output', help='Output file')

    args = parser.parse_args()

    reporter = MetricsReporter()

    print(f"📊 Generating metrics for last {args.days} days...\n")

    # Generate metrics
    commit_metrics = reporter.generate_commit_metrics(args.days)
    pr_metrics = reporter.generate_pr_metrics(args.days)

    jira_metrics = None
    if args.project:
        jira_metrics = reporter.generate_jira_metrics(args.project, args.days)

    # Output
    if args.json:
        output = {
            'commit_metrics': commit_metrics,
            'jira_metrics': jira_metrics,
            'pr_metrics': pr_metrics
        }
        result = json.dumps(output, indent=2)
    else:
        result = reporter.format_report(commit_metrics, jira_metrics, pr_metrics)

    if args.output:
        with open(args.output, 'w') as f:
            f.write(result)
        print(f"✓ Metrics saved to: {args.output}")
    else:
        print(result)


if __name__ == '__main__':
    main()
