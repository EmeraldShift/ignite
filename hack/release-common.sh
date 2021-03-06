#!/bin/bash

DOCKER_TTY="${DOCKER_TTY:+"-t"}"

if [[ ! -f bin/gren_token ]]; then
    echo "File bin/gren_token is needed; should contain a Github token with repo access"
    exit 1
fi

run_gren() {
    docker run -i ${DOCKER_TTY} \
        -v $(pwd):/data \
        -w /data \
        -u $(id -u):$(id -g) \
        -e GREN_GITHUB_TOKEN=$(cat bin/gren_token) \
        ignite-relnotes \
        /bin/bash -c "gren $@"
}

make_tidy_autogen() {
    make autogen tidy-in-docker graph
    if [[ $(git status --short) != "" ]]; then
        git add -A
        git commit -m "Ran 'make autogen tidy graph'"
    fi
}

gen_changelog_md() {
    file="CHANGELOG.md"
    echo '<!-- Note: This file is autogenerated based on files in docs/releases. Run hack/release.sh to update -->' > ${file}
    echo "" >> ${file}
    echo "# Changelog" >> ${file}
    echo "" >> ${file}
    
    # Generate docs/releases/next.md based of GH release notes
    run_gren "changelog"
    # Add the new release and existing ones to the changelog
    cat "docs/releases/${FULL_VERSION}.md" docs/releases/next.md >> ${file}
    # Remove the temporary file
    rm docs/releases/next.md
}

write_changelog() {
    # Generate the changelog draft
    if [[ ! -f "docs/releases/${FULL_VERSION}.md" ]]; then
        # Build the gren image
        docker build -t ignite-relnotes hack/relnotes

        # Push a temporary changlog-tag (we'll delete this)
        CHANGELOG_TAG="changelog-tmp-${FULL_VERSION}"

        echo "Tagging the current commit ${CHANGELOG_TAG} temporarily in order to run gren..."
        git tag -f "${CHANGELOG_TAG}"
        git push upstream --tags -f

        echo "Creating a changelog for PRs between tags ${CHANGELOG_TAG}..${PREVIOUS_TAG}"
        run_gren "changelog --generate --tags=${CHANGELOG_TAG}..${PREVIOUS_TAG}"

        git push --delete upstream "${CHANGELOG_TAG}"
        git tag --delete "${CHANGELOG_TAG}"

        mv docs/releases/next.md "docs/releases/${FULL_VERSION}.md"
        # Add an extra newline in the end of the changelog
        echo "" >> "docs/releases/${FULL_VERSION}.md"
    fi

    read -p "Please manually fixup the changelog file now. Continue? [y/N] " confirm
    if [[ ! ${confirm} =~ ^[Yy]$ ]]; then
        exit 1
    fi

    # Generate the CHANGELOG.md file
    gen_changelog_md

    # Proceed with making the commit
    read -p "Are you sure you want to do a commit for the changelog? [y/N] " confirm
    if [[ ! ${confirm} =~ ^[Yy]$ ]]; then
        exit 1
    fi

    git add "docs/releases/${FULL_VERSION}.md" "CHANGELOG.md"
    git commit -m "Document ${FULL_VERSION} change log"
}

build_push_release_artifacts() {
    make release
    # Do this at a later stage
    #make -C images push-all
}
