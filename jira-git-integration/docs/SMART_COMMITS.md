# Smart Commits Guide

Complete guide to using smart commits with Jira Git Integration.

## What are Smart Commits?

Smart commits allow you to perform Jira actions directly from your Git commit messages. When you commit code, Jira is automatically updated with:

- Work time logging
- Comments
- Status transitions
- Issue linking

## Basic Syntax

```
[ISSUE-KEY] type: description #command1 #command2
```

## Commands

### 1. Time Logging (`#time`)

Log work time to the issue.

**Syntax:**
```
#time <duration>
```

**Time Units:**
- `m` - minutes
- `h` - hours
- `d` - days (8 hour workday)
- `w` - weeks (40 hour workweek)

**Examples:**
```bash
git commit -m "[PROJ-456] feat: add filtering #time 2h"
git commit -m "[PROJ-456] fix: bug fix #time 30m"
git commit -m "[PROJ-456] feat: feature #time 1d 4h"
git commit -m "[PROJ-456] refactor: cleanup #time 2h 30m"
```

### 2. Comments (`#comment`)

Add a comment to the Jira issue.

**Syntax:**
```
#comment <your comment text>
```

**Examples:**
```bash
git commit -m "[PROJ-456] fix: null pointer #comment Fixed the NPE in user service"

git commit -m "[PROJ-456] feat: add API #comment Implemented REST API with docs"

git commit -m "[PROJ-456] test: add tests #comment Added unit tests, coverage 95%"
```

**Note:** Comment text extends until the next `#` command or end of message.

### 3. Workflow Transitions

Move issues through your workflow states.

#### In Progress
```bash
#in-progress
#progress
#start
#started
```

**Examples:**
```bash
git commit -m "[PROJ-456] feat: start work #in-progress"
git commit -m "[PROJ-456] fix: working on bug #start"
```

#### Code Review
```bash
#in-review
#review
#code-review
```

**Examples:**
```bash
git commit -m "[PROJ-456] feat: ready for review #in-review"
git commit -m "[PROJ-456] refactor: needs review #code-review"
```

#### QA/Testing
```bash
#qa-ready
#qa
#testing
#test
```

**Examples:**
```bash
git commit -m "[PROJ-456] feat: ready for QA #qa-ready"
git commit -m "[PROJ-456] fix: needs testing #qa"
```

#### Done/Resolved
```bash
#done
#complete
#completed
#resolved
#resolve
```

**Examples:**
```bash
git commit -m "[PROJ-456] feat: feature complete #done"
git commit -m "[PROJ-456] fix: bug fixed #resolved"
```

#### Other States
```bash
#deployed        # Deployed to production
#blocked         # Blocked/On Hold
#reopened        # Reopen issue
#closed          # Close issue
```

### 4. Multiple Commands

Combine multiple commands in one commit:

```bash
# Time + Comment
git commit -m "[PROJ-456] feat: add filtering #time 2h #comment Feature complete"

# Time + Transition
git commit -m "[PROJ-456] feat: add API #time 3h #done"

# All three
git commit -m "[PROJ-456] feat: add feature #time 2h 30m #comment Ready for review #in-review"

# Multiple issues
git commit -m "[PROJ-456] [PROJ-789] fix: shared fix #time 1h #done"
```

## Conventional Commit Format

We recommend using conventional commit format with smart commits:

```
[ISSUE-KEY] type: description #commands

Types:
- feat:      New feature
- fix:       Bug fix
- docs:      Documentation
- style:     Code style changes
- refactor:  Code refactoring
- test:      Adding tests
- chore:     Maintenance tasks
- perf:      Performance improvements
```

**Examples:**
```bash
git commit -m "[PROJ-456] feat: add user authentication #time 4h #in-review"
git commit -m "[PROJ-456] fix: resolve login timeout #time 1h #comment Fixed session handling #done"
git commit -m "[PROJ-456] docs: update API documentation #time 30m"
git commit -m "[PROJ-456] test: add integration tests #time 2h #comment Coverage 90%"
```

## Branch Naming

Include issue key in branch name for automatic linking:

```bash
# Recommended format
ISSUE-KEY-description

# Examples
git checkout -b "PROJ-456-add-filtering"
git checkout -b "PROJ-789-fix-login-bug"
git checkout -b "PROJ-123-update-docs"

# Also works
git checkout -b "feature/PROJ-456-filtering"
git checkout -b "bugfix/PROJ-789-login"
git checkout -b "hotfix/PROJ-999-critical"
```

**Benefits:**
- Commits automatically tagged with issue key
- Checkout triggers Jira update (if configured)
- Easy to track work in progress

## Complete Examples

### Example 1: Feature Development

```bash
# Start work
git checkout -b "PROJ-456-add-package-filtering"

# Initial commit
git commit -m "[PROJ-456] feat: add filter menu component #time 1h #in-progress"

# More work
git commit -m "[PROJ-456] feat: implement filter logic #time 2h #comment Added multi-select support"

# Testing
git commit -m "[PROJ-456] test: add filter tests #time 1h #comment Unit tests pass"

# Complete
git commit -m "[PROJ-456] feat: filtering complete #time 30m #comment Ready for review #in-review"
```

**Total time logged:** 4h 30m
**Final status:** In Review
**Comments:** 3 added

### Example 2: Bug Fix

```bash
# Start work
git checkout -b "PROJ-789-fix-null-pointer"

# Investigate
git commit -m "[PROJ-789] fix: investigate NPE #time 30m #in-progress"

# Fix
git commit -m "[PROJ-789] fix: add null check in user service #time 1h #comment Fixed NPE when user not found"

# Test
git commit -m "[PROJ-789] test: add null safety tests #time 30m"

# Complete
git commit -m "[PROJ-789] fix: bug resolved #time 15m #comment Tested, all pass #done"
```

**Total time logged:** 2h 15m
**Final status:** Done

### Example 3: Refactoring

```bash
git checkout -b "PROJ-321-refactor-auth"

git commit -m "[PROJ-321] refactor: extract auth service #time 2h #comment Improved code organization"

git commit -m "[PROJ-321] refactor: add interfaces #time 1h #comment Better abstraction"

git commit -m "[PROJ-321] test: update tests #time 1h 30m #comment All tests pass"

git commit -m "[PROJ-321] refactor: complete #time 30m #done"
```

### Example 4: Multiple Issues

```bash
# Shared fix for multiple tickets
git commit -m "[PROJ-123] [PROJ-456] fix: shared database fix #time 2h #comment Fixed schema issue affecting both #done"

# Feature spanning multiple tickets
git commit -m "[PROJ-100] [PROJ-101] feat: API integration #time 4h #in-review"
```

## What Gets Logged in Jira?

For each commit with smart commands, Jira receives:

1. **Commit Comment:**
   - Commit hash
   - Author
   - Date
   - Message
   - Files changed
   - Lines added/removed
   - Link to commit

2. **Remote Link:**
   - Direct link to commit in Bitbucket/GitHub
   - Visible in "Development" panel

3. **Work Log (if #time):**
   - Time spent
   - When logged
   - Work description

4. **Comment (if #comment):**
   - Your custom comment

5. **Status Change (if transition):**
   - Issue moved to new status
   - Comment added about transition

## Best Practices

### ✅ DO:

```bash
# Be specific in messages
git commit -m "[PROJ-456] feat: add package type filtering to picklist table #time 2h #in-review"

# Log time regularly
git commit -m "[PROJ-456] feat: work in progress #time 1h 30m"

# Add context in comments
git commit -m "[PROJ-456] fix: bug fix #comment Fixed by adding null check in line 234"

# Use multiple commands
git commit -m "[PROJ-456] feat: complete #time 3h #comment All tests pass #done"
```

### ❌ DON'T:

```bash
# Vague messages
git commit -m "[PROJ-456] stuff #time 1h"

# No issue key
git commit -m "feat: add filtering #time 2h"
# ^ Won't update Jira!

# Invalid time format
git commit -m "[PROJ-456] feat: work #time 2 hours"
# ^ Use: #time 2h

# Typos in commands
git commit -m "[PROJ-456] feat: work #tiem 2h"
# ^ Typo: #tiem instead of #time
```

## Time Tracking Tips

### Accurate Logging

```bash
# After focused work session
git add .
git commit -m "[PROJ-456] feat: implement feature #time 2h 15m"

# Multiple small commits? Consolidate time
git commit -m "[PROJ-456] feat: part 1 #time 1h"
git commit -m "[PROJ-456] feat: part 2 #time 1h 30m"
git commit -m "[PROJ-456] feat: final touches #time 30m"
# Total: 3h logged
```

### Time Estimates

```
30m  = Quick fix or small change
1h   = Small feature or bug
2-4h = Medium feature
1d   = Large feature (8h)
2-3d = Very large feature
1w   = Epic-level work (40h)
```

## Disabling Smart Commits

### Temporarily (one commit)

```bash
JIRA_HOOK_DISABLED=1 git commit -m "message without Jira"
```

### Permanently

```bash
# Add to .env
echo "JIRA_HOOK_DISABLED=1" >> .env

# Or in your shell profile
export JIRA_HOOK_DISABLED=1
```

### Re-enable

```bash
# Remove from .env or set to 0
JIRA_HOOK_DISABLED=0
```

## Testing Smart Commits

Create a test issue in Jira, then:

```bash
# Test time logging
git commit --allow-empty -m "[TEST-123] test: time log #time 15m"

# Test comment
git commit --allow-empty -m "[TEST-123] test: comment #comment This is a test comment"

# Test transition
git commit --allow-empty -m "[TEST-123] test: transition #in-progress"

# Test all commands
git commit --allow-empty -m "[TEST-123] test: all commands #time 5m #comment Testing everything #done"
```

Check Jira to verify each command worked!

## Troubleshooting

### Commands not working?

1. **Check format:**
   ```bash
   # Correct
   #time 2h

   # Wrong (space before #)
   # time 2h

   # Wrong (no space after #time)
   #time2h
   ```

2. **Check transition names:**
   ```bash
   # Check available transitions in Jira
   # Must match your workflow
   ```

3. **Verify hooks are running:**
   ```bash
   # Enable debug
   git commit -m "[PROJ-456] test" 2>&1 | tee commit.log
   ```

### Time not logged?

- Format must be: `2h`, `30m`, `1d 4h`, `2h 30m`
- Invalid: `2 hours`, `2hrs`, `30 minutes`

### Issue not transitioning?

- Transition must exist in your Jira workflow
- Issue must be in valid state for transition
- Check workflow permissions

## Advanced: Custom Transitions

Add custom transitions in `.env`:

```bash
JIRA_CUSTOM_TRANSITIONS=review:Code Review,qa:QA Testing,prod:Production
```

Then use:
```bash
git commit -m "[PROJ-456] feat: done #review"
git commit -m "[PROJ-456] feat: tested #qa"
git commit -m "[PROJ-456] feat: deployed #prod"
```

---

**Happy committing! 🚀**

For more information, see the [main README](../README.md).
