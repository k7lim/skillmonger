---
name: gh-json-fields
description: JSON field names for gh CLI subcommands — names differ across subcommands
tags: gh, json, fields, gotcha
---

# gh CLI JSON Field Names

Field names are NOT consistent across subcommands. This is the primary source of runtime errors.

## Field Name Conflicts

| Concept | `gh search repos` | `gh repo view` / `gh repo list` | `gh api` (REST) |
|---|---|---|---|
| Stars | `stargazersCount` | `stargazerCount` | `stargazers_count` |
| Forks | `forksCount` | `forkCount` | `forks_count` |
| Open issues | `openIssuesCount` | *(use `issues`)* | `open_issues_count` |
| Repo name | `name` / `fullName` | `name` / `nameWithOwner` | `name` / `full_name` |
| License | `license` | `licenseInfo` | `license` |
| Default branch | `defaultBranch` | `defaultBranchRef` | `default_branch` |
| Watchers | `watchersCount` | `watchers` | `watchers_count` |

Pattern: `gh search repos` uses camelCase with plural+Count. `gh repo view` uses camelCase with singular+Count (or object). `gh api` uses snake_case.

## Complete Field Lists

### gh search repos --json

createdAt, defaultBranch, description, forksCount, fullName, hasDownloads, hasIssues,
hasPages, hasProjects, hasWiki, homepage, id, isArchived, isDisabled, isFork, isPrivate,
language, license, name, openIssuesCount, owner, pushedAt, size, stargazersCount,
updatedAt, url, visibility, watchersCount

### gh repo view --json / gh repo list --json

archivedAt, assignableUsers, codeOfConduct, contactLinks, createdAt, defaultBranchRef,
deleteBranchOnMerge, description, diskUsage, forkCount, fundingLinks,
hasDiscussionsEnabled, hasIssuesEnabled, hasProjectsEnabled, hasWikiEnabled, homepageUrl,
id, isArchived, isBlankIssuesEnabled, isEmpty, isFork, isInOrganization, isMirror,
isPrivate, isSecurityPolicyEnabled, isTemplate, isUserConfigurationRepository,
issueTemplates, issues, labels, languages, latestRelease, licenseInfo, mentionableUsers,
mergeCommitAllowed, milestones, mirrorUrl, name, nameWithOwner, openGraphImageUrl, owner,
parent, primaryLanguage, projects, projectsV2, pullRequestTemplates, pullRequests,
pushedAt, rebaseMergeAllowed, repositoryTopics, securityPolicyUrl, squashMergeAllowed,
sshUrl, stargazerCount, templateRepository, updatedAt, url, usesCustomOpenGraphImage,
viewerCanAdminister, viewerDefaultCommitEmail, viewerDefaultMergeMethod, viewerHasStarred,
viewerPermission, viewerPossibleCommitEmails, viewerSubscription, visibility, watchers

### gh pr list --json

additions, assignees, author, autoMergeRequest, baseRefName, baseRefOid, body,
changedFiles, closed, closedAt, closingIssuesReferences, comments, commits, createdAt,
deletions, files, fullDatabaseId, headRefName, headRefOid, headRepository,
headRepositoryOwner, id, isCrossRepository, isDraft, labels, latestReviews,
maintainerCanModify, mergeCommit, mergeStateStatus, mergeable, mergedAt, mergedBy,
milestone, number, potentialMergeCommit, projectCards, projectItems, reactionGroups,
reviewDecision, reviewRequests, reviews, state, statusCheckRollup, title, updatedAt, url

### gh issue list --json

assignees, author, body, closed, closedAt, closedByPullRequestsReferences, comments,
createdAt, id, isPinned, labels, milestone, number, projectCards, projectItems,
reactionGroups, state, stateReason, title, updatedAt, url
