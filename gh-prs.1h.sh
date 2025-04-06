#!/bin/bash

# <xbar.title>github pull requests</xbar.title>
# <xbar.version>v0.1</xbar.version>
# <xbar.author>mango-jfg</xbar.author>
# <xbar.author.github>mango-jfg</xbar.author.github>
# <xbar.desc>Show open PRs in all repo of an organization from github</xbar.desc>
# <xbar.dependencies>gh CLI, jq</xbar.dependencies>

# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>
# <swiftbar.hideSwiftBar>true</swiftbar.hideSwiftBar>

MANUAL_REFRESH_TITLE="-> Manual refresh | refresh=true"
SEP="---"
MAX_REPO=200

# check if gh is installed
if ! command -v gh &> /dev/null; then
    echo "( ͡ʘ ͜ʖ ͡ʘ) | color=red"
    echo $SEP
    echo "Please install gh! (brew install gh) | color=Snow"
    echo $MANUAL_REFRESH_TITLE
    exit 0
fi

# check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "( ͡ʘ ͜ʖ ͡ʘ) | color=red"
    echo $SEP
    echo "Please install jq! (brew install jq) | color=Snow"
    echo $MANUAL_REFRESH_TITLE
    exit 0
fi

GITHUB_USER=$(gh api user --jq '.login' 2>/dev/null)
GITHUB_TOKEN=$(gh auth token 2>/dev/null)

CONFIG_FILE=~/.config/swiftbar-gh-prs.conf
FILTER_REQUESTED="draft:false review-requested:$GITHUB_USER" # default
FILTER_ALL="draft:false"

# check if env variables exist
if [ -z "$GITHUB_TOKEN" ]; then
    echo "( ͡ʘ ͜ʖ ͡ʘ) | color=red"
    echo $SEP
    echo "Please set up the GITHUB_TOKEN env variable or authenticate with 'gh auth login'! | color=Snow"
    echo $MANUAL_REFRESH_TITLE
    exit 0
fi

if [ -z "$GITHUB_OWNER" ]; then
    echo "( ͡ʘ ͜ʖ ͡ʘ) | color=red"
    echo $SEP
    echo "Please set up the GITHUB_OWNER env variable! | color=Snow"
    echo $MANUAL_REFRESH_TITLE
    exit 0
fi

# check if the config file exists, if not create it with the default filter
if [ -f $CONFIG_FILE ]; then
    FILTER=$(cat $CONFIG_FILE)
else
    echo $FILTER_REQUESTED > $CONFIG_FILE
    FILTER=$FILTER_REQUESTED
fi

# check if first parameter is "changetoall", if so, put into the config file and change the filter to all PRs
if [ "$1" == "changetoall" ]; then
    echo $FILTER_ALL > $CONFIG_FILE
    FILTER=$FILTER_ALL
fi

# check if $1 is "changetorequested"
if [ "$1" == "changetorequested" ]; then
    echo $FILTER_REQUESTED > $CONFIG_FILE
    FILTER=$FILTER_REQUESTED
fi

# function to format the data of one repo's PRs
format_rows (){
    echo $1 | jq -c '.[]' | while read -r item; do
        # extract the fields from the JSON object
        title=$(echo $item | jq -r '.title')
        url=$(echo $item | jq -r '.url')
        author=$(echo $item | jq -r '.author.login')
        createdAt=$(echo $item | jq -r '.createdAt')
        reviewRequests=$(echo $item | jq -r '.reviewRequests')
        reviewDecision=$(echo $item | jq -r '.reviewDecision')

        # if the title contains a pipe char, replace it with a ¦, because it is used as a separator
        title=${title//|/¦}

        # calculate the number of days since the PR was created
        current_date=$(date -u +"%s")
        days=$(($((current_date - $(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$createdAt" +"%s"))) / 86400))

        # get the login of the users and the slug of the teams that are requested for review
        req=$(echo $reviewRequests | jq -r 'map(select(.["__typename"] == "User") | .login) + map(select(.["__typename"] == "Team") | .slug) | join(", ")')

        # got enough approve? if reviewDecision is APPROVED then add a checkmark
        if [ "$reviewDecision" == "APPROVED" ]; then
            title="$title ☑️"
        fi

        # print the title with the author and the url
        echo "$title (🧑‍💻 $author) | href=$url"

        # print the days and the requested reviewers with a link to the PR, this line is shown when option button is pressed
        echo ":calendar: $days days, 👥 $req| alternate=true href=$url"
    done
}

# retrieve the names of non-archived repositories with open PRs, sorted by date of last push, most recent first
REPOS_W_PR=$(gh repo list $GITHUB_OWNER --no-archived -L $MAX_REPO --json name,pullRequests,pushedAt --jq 'sort_by(.pushedAt) | reverse | .[] | select(.pullRequests.totalCount > 0) | .name')
NUM_OF_PRS=0
OUTPUT=""

# for each repository with open PRs, retrieve the PRs and format them
for REPO in $REPOS_W_PR; do
    NAME="== $REPO ========== | size=15 href=https://github.com/$GITHUB_OWNER/$REPO/pulls"
    # get PRs with the filter and extract the title, url, author, createdAt, reviewRequests and reviewDecision fields
    PRS=$(gh pr list --repo $GITHUB_OWNER/$REPO -S "$FILTER" --json title,url,reviewRequests,author,createdAt,reviewDecision)
    N=$(echo "$PRS" | jq '. | length')
    # if there are PRs, format them and add them to the output
    if [ "$N" -gt 0 ]; then
        NUM_OF_PRS=$(($NUM_OF_PRS + $N))
        # format the PRs and add them to the output
        PRS=$(format_rows "$PRS")
        OUTPUT="$OUTPUT\n$NAME\n$PRS\n$SEP\n"
    fi
done

# if no PRs are found, display a message
if [ -z "$OUTPUT" ]; then
    OUTPUT="No PRs found 👍 | color=SpringGreen\n$SEP"
fi

# display the number of PRs or a relaxed face if there are none
if [ "$NUM_OF_PRS" -eq 0 ]; then
    echo "( ^ ͜ʖ^) ☞ 0| size=15"
else
    echo "( ͡ʘ ͜ʖ ͡ʘ) ☞ $NUM_OF_PRS| size=15"
fi

echo $SEP
echo -e "$OUTPUT"
echo $MANUAL_REFRESH_TITLE

# display the option to change the filter 
# if the current filter is the requested one, display the option to change to all PRs and vice versa
# to change the filter, the script is called with the corresponding parameter
if [ "$FILTER" == "$FILTER_REQUESTED" ]; then
    echo "-> Display all PRs | bash='$0' param1=changetoall terminal=false refresh=true"
else
    echo "-> Display only my requested PRs | bash='$0' param1=changetorequested terminal=false refresh=true"
fi
