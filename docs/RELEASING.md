# Releasing to CurseForge

Releases are built and uploaded by GitHub Actions (`.github/workflows/release.yml`) using the
[BigWigs packager](https://github.com/BigWigsMods/packager). Pushing a version tag builds the
addon zip, uploads it to CurseForge and creates a GitHub release. `docs/`, `.github/` and
`README.md` aren't included in the zip (see `.pkgmeta`).

## One-time setup

1. **Create the CurseForge project.** On [authors.curseforge.com](https://authors.curseforge.com),
   choose *Create Project*, game *World of Warcraft*, and fill in:
   - name: `PixlLootCouncil`
   - a summary
   - a category, e.g. *Raid Frames* or *Bags & Inventory*
   - license *GNU General Public License version 3 (GPLv3)*
   - a description (you can paste from `README.md`)

   New projects are reviewed by CurseForge before they go public; files can be uploaded meanwhile.
2. **Add the project ID to the .toc.** Copy the *Project ID* from the project's sidebar, add this line
   below `## X-Website` in `PixlLootCouncil.toc`, and commit:

       ## X-Curse-Project-ID: 123456

3. **Create an API token.** In CurseForge, go to *My Profile → API Tokens* and generate a token.
4. **Store it on GitHub.** In the repository, go to *Settings → Secrets and variables → Actions →
   New repository secret*, name it `CF_API_KEY`, and paste the token.

## Making a release

1. Add a section for the new version at the top of `CHANGELOG.md` and commit.
2. Tag the commit and push the branch and the tag:

       git push origin main
       git tag v0.1.0-beta
       git push origin v0.1.0-beta

   - A tag containing `alpha` or `beta` is uploaded as an *alpha* or *beta* file.
   - A plain tag such as `v1.0.0` is uploaded as a *release*.
   - The tag becomes the version shown in game (`## Version: @project-version@` in the .toc).
3. Follow the run under the repository's *Actions* tab. When it's green, the file is on CurseForge.
   Most addon managers only offer beta files to users who opted into betas.

## Building a zip locally (no upload)

To test the packaged result without uploading anything:

    curl -sO https://raw.githubusercontent.com/BigWigsMods/packager/master/release.sh
    bash release.sh -d -z    # -d: don't upload, -z: skip the zip and keep the folder in .release/

The packaged addon ends up in `.release/PixlLootCouncil/`. Drop `-z` to also get the zip.
