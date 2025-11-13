#!/usr/bin/env python3
"""
Bitbucket Webhook Server
Receives webhooks from Bitbucket and updates Jira accordingly
"""

from flask import Flask, request, jsonify
import hmac
import hashlib
import os
import sys
from pathlib import Path

# Add lib directory to path
lib_path = Path(__file__).parent.parent / 'lib'
sys.path.insert(0, str(lib_path))

from jira_client import JiraClient
from smart_commit_parser import SmartCommitParser

app = Flask(__name__)

# Configuration
WEBHOOK_SECRET = os.getenv('BITBUCKET_WEBHOOK_SECRET', '')
JIRA_AUTO_TRANSITION_PR = os.getenv('JIRA_AUTO_TRANSITION_PR', 'true').lower() == 'true'


def verify_signature(payload, signature):
    """Verify webhook signature"""
    if not WEBHOOK_SECRET:
        return True  # Skip verification if no secret configured

    expected = hmac.new(
        WEBHOOK_SECRET.encode(),
        payload,
        hashlib.sha256
    ).hexdigest()

    return hmac.compare_digest(signature, expected)


@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    return jsonify({'status': 'healthy', 'service': 'jira-git-integration'}), 200


@app.route('/webhook/bitbucket', methods=['POST'])
def bitbucket_webhook():
    """Handle Bitbucket webhooks"""
    # Verify signature
    signature = request.headers.get('X-Hub-Signature', '')
    if signature and not verify_signature(request.data, signature.replace('sha256=', '')):
        return jsonify({'error': 'Invalid signature'}), 401

    # Get event type
    event = request.headers.get('X-Event-Key', '')

    try:
        payload = request.json

        # Route to appropriate handler
        if event.startswith('repo:push'):
            return handle_push(payload)
        elif event.startswith('pullrequest:'):
            return handle_pull_request(payload, event)
        elif event.startswith('repo:commit_status_'):
            return handle_build_status(payload, event)
        else:
            return jsonify({'message': f'Event {event} not handled'}), 200

    except Exception as e:
        print(f"Error processing webhook: {e}")
        return jsonify({'error': str(e)}), 500


def handle_push(payload):
    """Handle push events"""
    try:
        client = JiraClient()
        parser = SmartCommitParser()

        changes = payload.get('push', {}).get('changes', [])
        repo_name = payload.get('repository', {}).get('full_name', 'Repository')
        repo_url = payload.get('repository', {}).get('links', {}).get('html', {}).get('href', '')

        issues_updated = set()

        for change in changes:
            commits = change.get('commits', [])

            for commit in commits:
                commit_hash = commit.get('hash', '')[:7]
                message = commit.get('message', '')
                author = commit.get('author', {}).get('raw', 'Unknown')

                # Parse commit for issue keys
                smart_commit = parser.parse(message)

                for issue_key in smart_commit.issue_keys:
                    # Add comment
                    comment = f"**Push to {repo_name}**\n"
                    comment += f"Commit: `{commit_hash}`\n"
                    comment += f"Author: {author}\n"
                    comment += f"Message: {smart_commit.message}\n"

                    if repo_url:
                        commit_url = f"{repo_url}/commits/{commit.get('hash', '')}"
                        comment += f"\n[View Commit]({commit_url})"

                    client.add_comment(issue_key, comment)

                    # Create remote link
                    if repo_url:
                        client.create_remote_link(
                            issue_key,
                            commit_url,
                            f"Commit {commit_hash}",
                            smart_commit.message
                        )

                    issues_updated.add(issue_key)

        return jsonify({
            'message': 'Push processed',
            'issues_updated': list(issues_updated)
        }), 200

    except Exception as e:
        print(f"Error handling push: {e}")
        return jsonify({'error': str(e)}), 500


def handle_pull_request(payload, event):
    """Handle pull request events"""
    try:
        client = JiraClient()
        parser = SmartCommitParser()

        pr = payload.get('pullrequest', {})
        pr_id = pr.get('id', '')
        pr_title = pr.get('title', '')
        pr_state = pr.get('state', '')
        pr_url = pr.get('links', {}).get('html', {}).get('href', '')
        author = pr.get('author', {}).get('display_name', 'Unknown')
        source_branch = pr.get('source', {}).get('branch', {}).get('name', '')
        target_branch = pr.get('destination', {}).get('branch', {}).get('name', '')

        # Extract issue keys from PR title and branch
        issue_keys = parser.extract_issue_keys(pr_title)
        issue_keys.extend(parser.extract_from_branch(source_branch))
        issue_keys = list(set(issue_keys))  # Remove duplicates

        if not issue_keys:
            return jsonify({'message': 'No issue keys found'}), 200

        # Determine action
        action = event.split(':')[-1]

        for issue_key in issue_keys:
            # Create comment based on action
            if action == 'created':
                comment = f"**Pull Request Created**\n"
                comment += f"PR #{pr_id}: {pr_title}\n"
                comment += f"Author: {author}\n"
                comment += f"Branch: `{source_branch}` → `{target_branch}`\n"
                if pr_url:
                    comment += f"\n[View Pull Request]({pr_url})"

                client.add_comment(issue_key, comment)

                # Create remote link
                if pr_url:
                    client.create_remote_link(
                        issue_key,
                        pr_url,
                        f"PR #{pr_id}: {pr_title}",
                        f"Pull request by {author}"
                    )

                # Auto-transition to "In Review" if enabled
                if JIRA_AUTO_TRANSITION_PR:
                    client.transition_issue(issue_key, 'In Review')

            elif action == 'updated':
                comment = f"**Pull Request Updated**\n"
                comment += f"PR #{pr_id}: {pr_title}\n"
                if pr_url:
                    comment += f"\n[View Pull Request]({pr_url})"

                client.add_comment(issue_key, comment)

            elif action == 'approved':
                approver = payload.get('approval', {}).get('user', {}).get('display_name', 'Someone')
                comment = f"**Pull Request Approved**\n"
                comment += f"PR #{pr_id} approved by {approver}\n"
                if pr_url:
                    comment += f"\n[View Pull Request]({pr_url})"

                client.add_comment(issue_key, comment)

            elif action == 'fulfilled':
                comment = f"**Pull Request Merged**\n"
                comment += f"PR #{pr_id}: {pr_title}\n"
                comment += f"Merged `{source_branch}` → `{target_branch}`\n"
                if pr_url:
                    comment += f"\n[View Pull Request]({pr_url})"

                client.add_comment(issue_key, comment)

                # Auto-transition to "Done" if merged to main/master
                if target_branch in ['main', 'master', 'production']:
                    client.transition_issue(issue_key, 'Done')

            elif action == 'declined':
                comment = f"**Pull Request Declined**\n"
                comment += f"PR #{pr_id}: {pr_title}\n"
                if pr_url:
                    comment += f"\n[View Pull Request]({pr_url})"

                client.add_comment(issue_key, comment)

        return jsonify({
            'message': f'Pull request {action} processed',
            'issues_updated': issue_keys
        }), 200

    except Exception as e:
        print(f"Error handling pull request: {e}")
        return jsonify({'error': str(e)}), 500


def handle_build_status(payload, event):
    """Handle build status events"""
    try:
        client = JiraClient()
        parser = SmartCommitParser()

        commit = payload.get('commit', {})
        commit_hash = commit.get('hash', '')[:7]
        message = commit.get('message', '')

        status = payload.get('state', '')
        status_key = payload.get('key', '')
        url = payload.get('url', '')

        # Extract issue keys
        issue_keys = parser.extract_issue_keys(message)

        if not issue_keys:
            return jsonify({'message': 'No issue keys found'}), 200

        # Map status to emoji
        status_emoji = {
            'SUCCESSFUL': '✅',
            'FAILED': '❌',
            'INPROGRESS': '🔄',
            'STOPPED': '⏹️'
        }

        emoji = status_emoji.get(status, '🔔')

        for issue_key in issue_keys:
            comment = f"{emoji} **Build Status: {status}**\n"
            comment += f"Commit: `{commit_hash}`\n"
            comment += f"Build: {status_key}\n"

            if url:
                comment += f"\n[View Build]({url})"

            client.add_comment(issue_key, comment)

            # Create remote link
            if url:
                client.create_remote_link(
                    issue_key,
                    url,
                    f"Build {status_key}",
                    f"Status: {status}"
                )

        return jsonify({
            'message': 'Build status processed',
            'issues_updated': issue_keys
        }), 200

    except Exception as e:
        print(f"Error handling build status: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/webhook/github', methods=['POST'])
def github_webhook():
    """Handle GitHub webhooks (for GitHub users)"""
    # Similar implementation for GitHub
    event = request.headers.get('X-GitHub-Event', '')

    try:
        payload = request.json

        if event == 'push':
            return handle_push(payload)
        elif event == 'pull_request':
            return handle_pull_request(payload, f"pullrequest:{payload.get('action', '')}")
        else:
            return jsonify({'message': f'Event {event} not handled'}), 200

    except Exception as e:
        print(f"Error processing GitHub webhook: {e}")
        return jsonify({'error': str(e)}), 500


if __name__ == '__main__':
    # Get configuration
    host = os.getenv('WEBHOOK_HOST', '0.0.0.0')
    port = int(os.getenv('WEBHOOK_PORT', '5000'))
    debug = os.getenv('WEBHOOK_DEBUG', 'false').lower() == 'true'

    print(f"🚀 Starting Jira Git Integration Webhook Server")
    print(f"   Host: {host}")
    print(f"   Port: {port}")
    print(f"   Endpoints:")
    print(f"     - POST /webhook/bitbucket")
    print(f"     - POST /webhook/github")
    print(f"     - GET  /health")
    print()

    if not WEBHOOK_SECRET:
        print("⚠️  Warning: BITBUCKET_WEBHOOK_SECRET not set - signature verification disabled")

    try:
        JiraClient()
        print("✓ Jira credentials configured")
    except ValueError:
        print("⚠️  Warning: Jira credentials not configured")
        print("   Set JIRA_SITE, JIRA_EMAIL, and JIRA_API_TOKEN")

    print()
    app.run(host=host, port=port, debug=debug)
