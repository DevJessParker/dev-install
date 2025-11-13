#!/usr/bin/env python3
"""
Smart Commit Parser
Parses Git commit messages for Jira smart commit commands
"""

import re
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass


@dataclass
class SmartCommit:
    """Represents a parsed smart commit"""
    issue_keys: List[str]
    message: str
    time_spent: Optional[str] = None
    comment: Optional[str] = None
    transition: Optional[str] = None
    raw_message: str = ""


class SmartCommitParser:
    """Parser for Jira smart commit syntax"""

    # Regex patterns
    ISSUE_KEY_PATTERN = r'\b([A-Z][A-Z0-9_]+-\d+)\b'
    TIME_PATTERN = r'#time\s+(\d+[wdhm](?:\s+\d+[wdhm])*)'
    COMMENT_PATTERN = r'#comment\s+([^\#]+?)(?=\s*#|\s*$)'
    TRANSITION_PATTERN = r'#([\w-]+)(?:\s|$)'

    # Common transition keywords
    TRANSITIONS = {
        'in-progress': 'In Progress',
        'inprogress': 'In Progress',
        'progress': 'In Progress',
        'in-review': 'In Review',
        'inreview': 'In Review',
        'review': 'In Review',
        'code-review': 'Code Review',
        'codereview': 'Code Review',
        'done': 'Done',
        'complete': 'Done',
        'completed': 'Done',
        'resolved': 'Resolved',
        'resolve': 'Resolved',
        'qa-ready': 'QA Ready',
        'qaready': 'QA Ready',
        'qa': 'QA Ready',
        'testing': 'Testing',
        'test': 'Testing',
        'deployed': 'Deployed',
        'deploy': 'Deployed',
        'blocked': 'Blocked',
        'blocked-review': 'Blocked',
        'reopened': 'Reopened',
        'reopen': 'Reopened',
        'closed': 'Closed',
        'close': 'Closed',
        'start': 'In Progress',
        'started': 'In Progress',
    }

    def __init__(self):
        """Initialize parser"""
        pass

    def parse(self, commit_message: str) -> SmartCommit:
        """
        Parse commit message for smart commit commands

        Args:
            commit_message: Git commit message

        Returns:
            SmartCommit object with parsed data
        """
        # Extract issue keys
        issue_keys = self.extract_issue_keys(commit_message)

        # Extract time spent
        time_spent = self.extract_time(commit_message)

        # Extract comment
        comment = self.extract_comment(commit_message)

        # Extract transition
        transition = self.extract_transition(commit_message)

        # Clean message (remove smart commit commands)
        clean_message = self.clean_message(commit_message)

        return SmartCommit(
            issue_keys=issue_keys,
            message=clean_message,
            time_spent=time_spent,
            comment=comment,
            transition=transition,
            raw_message=commit_message
        )

    def extract_issue_keys(self, text: str) -> List[str]:
        """
        Extract Jira issue keys from text

        Args:
            text: Text to search

        Returns:
            List of unique issue keys
        """
        matches = re.findall(self.ISSUE_KEY_PATTERN, text, re.IGNORECASE)
        # Return unique keys, preserve order
        seen = set()
        result = []
        for key in matches:
            key_upper = key.upper()
            if key_upper not in seen:
                seen.add(key_upper)
                result.append(key_upper)
        return result

    def extract_time(self, text: str) -> Optional[str]:
        """
        Extract time spent from #time command

        Args:
            text: Text to search

        Returns:
            Time string (e.g., '2h 30m') or None
        """
        match = re.search(self.TIME_PATTERN, text, re.IGNORECASE)
        if match:
            return match.group(1).strip()
        return None

    def extract_comment(self, text: str) -> Optional[str]:
        """
        Extract comment from #comment command

        Args:
            text: Text to search

        Returns:
            Comment text or None
        """
        match = re.search(self.COMMENT_PATTERN, text, re.IGNORECASE)
        if match:
            return match.group(1).strip()
        return None

    def extract_transition(self, text: str) -> Optional[str]:
        """
        Extract workflow transition from # commands

        Args:
            text: Text to search

        Returns:
            Transition name or None
        """
        # Find all # commands
        matches = re.finditer(self.TRANSITION_PATTERN, text, re.IGNORECASE)

        for match in matches:
            keyword = match.group(1).lower()

            # Skip known non-transition commands
            if keyword in ['time', 'comment']:
                continue

            # Check if it's a known transition
            if keyword in self.TRANSITIONS:
                return self.TRANSITIONS[keyword]

        return None

    def clean_message(self, text: str) -> str:
        """
        Remove smart commit commands from message

        Args:
            text: Original message

        Returns:
            Cleaned message
        """
        # Remove #time commands
        text = re.sub(self.TIME_PATTERN, '', text, flags=re.IGNORECASE)

        # Remove #comment commands
        text = re.sub(self.COMMENT_PATTERN, '', text, flags=re.IGNORECASE)

        # Remove transition commands (but keep issue keys)
        for keyword in self.TRANSITIONS.keys():
            text = re.sub(rf'#{keyword}\b', '', text, flags=re.IGNORECASE)

        # Clean up extra whitespace
        text = re.sub(r'\s+', ' ', text)
        text = text.strip()

        return text

    def is_smart_commit(self, commit_message: str) -> bool:
        """
        Check if message contains smart commit commands

        Args:
            commit_message: Commit message to check

        Returns:
            True if contains smart commands
        """
        has_time = bool(re.search(self.TIME_PATTERN, commit_message, re.IGNORECASE))
        has_comment = bool(re.search(self.COMMENT_PATTERN, commit_message, re.IGNORECASE))
        has_transition = self.extract_transition(commit_message) is not None

        return has_time or has_comment or has_transition

    def extract_from_branch(self, branch_name: str) -> List[str]:
        """
        Extract issue keys from branch name

        Args:
            branch_name: Git branch name

        Returns:
            List of issue keys
        """
        return self.extract_issue_keys(branch_name)

    def validate_time_format(self, time_str: str) -> bool:
        """
        Validate time format is Jira-compatible

        Args:
            time_str: Time string to validate

        Returns:
            True if valid
        """
        # Jira accepts: w (weeks), d (days), h (hours), m (minutes)
        pattern = r'^\d+[wdhm](\s+\d+[wdhm])*$'
        return bool(re.match(pattern, time_str, re.IGNORECASE))

    def parse_time_to_minutes(self, time_str: str) -> int:
        """
        Convert time string to minutes

        Args:
            time_str: Time string (e.g., '2h 30m')

        Returns:
            Total minutes
        """
        if not time_str:
            return 0

        total_minutes = 0

        # Extract all time components
        pattern = r'(\d+)([wdhm])'
        matches = re.findall(pattern, time_str, re.IGNORECASE)

        for amount, unit in matches:
            amount = int(amount)
            unit = unit.lower()

            if unit == 'w':
                total_minutes += amount * 40 * 60  # 40 hour work week
            elif unit == 'd':
                total_minutes += amount * 8 * 60  # 8 hour work day
            elif unit == 'h':
                total_minutes += amount * 60
            elif unit == 'm':
                total_minutes += amount

        return total_minutes

    def format_commit_info(self, commit_hash: str, author: str, date: str,
                          message: str, files_changed: int = 0,
                          insertions: int = 0, deletions: int = 0) -> str:
        """
        Format commit information for Jira comment

        Args:
            commit_hash: Git commit hash
            author: Commit author
            date: Commit date
            message: Commit message
            files_changed: Number of files changed
            insertions: Lines inserted
            deletions: Lines deleted

        Returns:
            Formatted commit info string
        """
        info = f"**Commit:** `{commit_hash[:7]}`\n"
        info += f"**Author:** {author}\n"
        info += f"**Date:** {date}\n"
        info += f"**Message:** {message}\n"

        if files_changed > 0:
            info += f"**Changes:** {files_changed} files changed"
            if insertions > 0 or deletions > 0:
                info += f" (+{insertions}/-{deletions})"
            info += "\n"

        return info


# Convenience functions
def parse_commit(commit_message: str) -> SmartCommit:
    """Parse a commit message"""
    parser = SmartCommitParser()
    return parser.parse(commit_message)


def extract_issue_keys(text: str) -> List[str]:
    """Extract issue keys from text"""
    parser = SmartCommitParser()
    return parser.extract_issue_keys(text)


if __name__ == '__main__':
    # Example usage
    parser = SmartCommitParser()

    # Test cases
    test_messages = [
        "[PHARM-456] feat: add filtering #time 2h 30m #comment Feature complete #in-review",
        "PROJ-123 Fix bug in login #time 1h #done",
        "[PHARM-456] [PHARM-457] Multiple tickets #time 3h",
        "Regular commit without smart commands",
        "PHARM-789 #comment Added tests #time 45m #qa-ready",
    ]

    print("Smart Commit Parser Examples\n")
    print("=" * 60)

    for msg in test_messages:
        print(f"\nOriginal: {msg}")
        result = parser.parse(msg)
        print(f"Issue Keys: {result.issue_keys}")
        print(f"Clean Message: {result.message}")
        if result.time_spent:
            minutes = parser.parse_time_to_minutes(result.time_spent)
            print(f"Time: {result.time_spent} ({minutes} minutes)")
        if result.comment:
            print(f"Comment: {result.comment}")
        if result.transition:
            print(f"Transition: {result.transition}")
        print(f"Is Smart Commit: {parser.is_smart_commit(msg)}")
