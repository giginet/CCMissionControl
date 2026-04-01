---
name: release
description: Create a versioned release with notarization and GitHub release
disable-model-invocation: true
allowed-tools: Bash
argument-hint: <version>
---

# Release CCMissionControl

Create a release for version `$ARGUMENTS`.

Current tags:
!`git tag -l | tail -5`

## Steps

1. **Validate**: Confirm `$ARGUMENTS` is a valid version (e.g. `0.1.0`). Ensure working directory is clean.
2. **Update version**: Set `MARKETING_VERSION` in the Xcode project to `$ARGUMENTS` using sed on `project.pbxproj`.
3. **Commit**: `git commit -am "Release $ARGUMENTS"`
4. **Tag**: `git tag $ARGUMENTS`
5. **Push**: `git push && git push origin $ARGUMENTS`
6. **Notarize**: Run `./scripts/notarize.sh`
7. **GitHub Release**: Create a release with the notarized zip attached:
   ```
   gh release create $ARGUMENTS CCMissionControl.zip --title "v$ARGUMENTS" --generate-notes
   ```
8. Report the release URL to the user.
