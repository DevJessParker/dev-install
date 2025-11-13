#!/usr/bin/env python3
"""
Jira API Client
Handles all interactions with Jira REST API for Git integration
"""

import os
import json
import requests
from typing import Dict, List, Optional, Any
from datetime import datetime
import base64


class JiraClient:
    """Client for interacting with Jira Cloud REST API"""

    def __init__(self, site: str = None, email: str = None, api_token: str = None):
        """
        Initialize Jira client

        Args:
            site: Jira site URL (e.g., 'yourcompany.atlassian.net')
            email: User email for authentication
            api_token: Jira API token
        """
        self.site = site or os.getenv('JIRA_SITE')
        self.email = email or os.getenv('JIRA_EMAIL')
        self.api_token = api_token or os.getenv('JIRA_API_TOKEN')

        if not all([self.site, self.email, self.api_token]):
            raise ValueError("Jira credentials not provided. Set JIRA_SITE, JIRA_EMAIL, and JIRA_API_TOKEN")

        # Remove https:// if present
        self.site = self.site.replace('https://', '').replace('http://', '')

        self.base_url = f"https://{self.site}/rest/api/3"
        self.auth = self._create_auth()
        self.headers = {
            'Content-Type': 'application/json',
            'Accept': 'application/json'
        }

    def _create_auth(self) -> str:
        """Create basic auth header"""
        credentials = f"{self.email}:{self.api_token}"
        encoded = base64.b64encode(credentials.encode()).decode()
        return f"Basic {encoded}"

    def _request(self, method: str, endpoint: str, data: Dict = None) -> Optional[Dict]:
        """
        Make HTTP request to Jira API

        Args:
            method: HTTP method (GET, POST, PUT, DELETE)
            endpoint: API endpoint
            data: Request payload

        Returns:
            Response JSON or None
        """
        url = f"{self.base_url}/{endpoint}"
        headers = {**self.headers, 'Authorization': self.auth}

        try:
            response = requests.request(
                method=method,
                url=url,
                headers=headers,
                json=data,
                timeout=30
            )

            if response.status_code == 204:  # No content
                return {'success': True}

            response.raise_for_status()
            return response.json() if response.text else {'success': True}

        except requests.exceptions.RequestException as e:
            print(f"Error making request to Jira: {e}")
            if hasattr(e, 'response') and e.response is not None:
                print(f"Response: {e.response.text}")
            return None

    def get_issue(self, issue_key: str) -> Optional[Dict]:
        """
        Get issue details

        Args:
            issue_key: Jira issue key (e.g., 'PHARM-456')

        Returns:
            Issue data or None
        """
        return self._request('GET', f"issue/{issue_key}")

    def add_comment(self, issue_key: str, comment: str) -> Optional[Dict]:
        """
        Add comment to issue

        Args:
            issue_key: Jira issue key
            comment: Comment text

        Returns:
            Comment data or None
        """
        data = {
            "body": {
                "type": "doc",
                "version": 1,
                "content": [
                    {
                        "type": "paragraph",
                        "content": [
                            {
                                "type": "text",
                                "text": comment
                            }
                        ]
                    }
                ]
            }
        }
        return self._request('POST', f"issue/{issue_key}/comment", data)

    def log_work(self, issue_key: str, time_spent: str, comment: str = None) -> Optional[Dict]:
        """
        Log work time to issue

        Args:
            issue_key: Jira issue key
            time_spent: Time spent (e.g., '2h 30m', '1d 4h')
            comment: Optional work log comment

        Returns:
            Worklog data or None
        """
        data = {
            "timeSpent": time_spent,
            "started": datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%S.000+0000")
        }

        if comment:
            data["comment"] = {
                "type": "doc",
                "version": 1,
                "content": [
                    {
                        "type": "paragraph",
                        "content": [
                            {
                                "type": "text",
                                "text": comment
                            }
                        ]
                    }
                ]
            }

        return self._request('POST', f"issue/{issue_key}/worklog", data)

    def transition_issue(self, issue_key: str, transition_name: str) -> Optional[Dict]:
        """
        Transition issue to new status

        Args:
            issue_key: Jira issue key
            transition_name: Name of transition (e.g., 'In Progress', 'Done')

        Returns:
            Transition result or None
        """
        # Get available transitions
        transitions = self._request('GET', f"issue/{issue_key}/transitions")
        if not transitions:
            return None

        # Find matching transition
        transition_id = None
        for trans in transitions.get('transitions', []):
            if trans['name'].lower() == transition_name.lower():
                transition_id = trans['id']
                break

        if not transition_id:
            print(f"Transition '{transition_name}' not found for {issue_key}")
            return None

        # Execute transition
        data = {"transition": {"id": transition_id}}
        return self._request('POST', f"issue/{issue_key}/transitions", data)

    def create_remote_link(self, issue_key: str, url: str, title: str, summary: str = None) -> Optional[Dict]:
        """
        Create remote link (e.g., to PR, commit, build)

        Args:
            issue_key: Jira issue key
            url: URL to link
            title: Link title
            summary: Optional summary

        Returns:
            Link data or None
        """
        data = {
            "object": {
                "url": url,
                "title": title
            }
        }

        if summary:
            data["object"]["summary"] = summary

        return self._request('POST', f"issue/{issue_key}/remotelink", data)

    def update_issue(self, issue_key: str, fields: Dict) -> Optional[Dict]:
        """
        Update issue fields

        Args:
            issue_key: Jira issue key
            fields: Fields to update

        Returns:
            Update result or None
        """
        data = {"fields": fields}
        return self._request('PUT', f"issue/{issue_key}", data)

    def search_issues(self, jql: str, fields: List[str] = None, max_results: int = 50) -> Optional[Dict]:
        """
        Search issues with JQL

        Args:
            jql: JQL query string
            fields: List of fields to return
            max_results: Maximum results to return

        Returns:
            Search results or None
        """
        data = {
            "jql": jql,
            "maxResults": max_results
        }

        if fields:
            data["fields"] = fields

        return self._request('POST', 'search', data)

    def get_issue_changelog(self, issue_key: str) -> Optional[Dict]:
        """
        Get issue changelog

        Args:
            issue_key: Jira issue key

        Returns:
            Changelog data or None
        """
        return self._request('GET', f"issue/{issue_key}/changelog")

    def create_subtask(self, parent_key: str, summary: str, description: str = None,
                      assignee: str = None) -> Optional[Dict]:
        """
        Create subtask for an issue

        Args:
            parent_key: Parent issue key
            summary: Subtask summary
            description: Subtask description
            assignee: Assignee account ID

        Returns:
            Subtask data or None
        """
        # Get parent issue to extract project
        parent = self.get_issue(parent_key)
        if not parent:
            return None

        project_key = parent['fields']['project']['key']

        data = {
            "fields": {
                "project": {"key": project_key},
                "parent": {"key": parent_key},
                "summary": summary,
                "issuetype": {"name": "Subtask"}
            }
        }

        if description:
            data["fields"]["description"] = {
                "type": "doc",
                "version": 1,
                "content": [
                    {
                        "type": "paragraph",
                        "content": [
                            {
                                "type": "text",
                                "text": description
                            }
                        ]
                    }
                ]
            }

        if assignee:
            data["fields"]["assignee"] = {"accountId": assignee}

        return self._request('POST', 'issue', data)

    def get_project_versions(self, project_key: str) -> Optional[List[Dict]]:
        """
        Get all versions for a project

        Args:
            project_key: Project key

        Returns:
            List of versions or None
        """
        result = self._request('GET', f"project/{project_key}/versions")
        return result if isinstance(result, list) else None

    def create_version(self, project_key: str, name: str, description: str = None,
                      released: bool = False) -> Optional[Dict]:
        """
        Create new version/release

        Args:
            project_key: Project key
            name: Version name
            description: Version description
            released: Whether version is released

        Returns:
            Version data or None
        """
        data = {
            "name": name,
            "project": project_key,
            "released": released
        }

        if description:
            data["description"] = description

        return self._request('POST', 'version', data)


if __name__ == '__main__':
    # Example usage
    try:
        client = JiraClient()
        issue = client.get_issue('PHARM-456')
        if issue:
            print(f"Issue: {issue['key']} - {issue['fields']['summary']}")
    except Exception as e:
        print(f"Example usage requires JIRA_SITE, JIRA_EMAIL, and JIRA_API_TOKEN environment variables")
