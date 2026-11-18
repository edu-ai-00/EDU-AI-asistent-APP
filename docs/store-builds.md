# Store builds

iOS builds run on **Xcode Cloud** under the client's Apple team (EDU-AI, o.p.s., `24ZTV92G3K`). Android builds run on **GitHub Actions**. Both start from the **App store build** workflow (`.github/workflows/app-store.yml`).

## Releasing to the stores

**Push to `release/app`.** Every push is a release, so put on that branch only what may reach store users: merge `staging` into it, or cherry-pick single commits. The run then does this:

1. **Tag** checks that the production API (git `main`) has every route the app calls (`check_api.sh`). If any is missing, the run goes on and warns in its summary: the release goes to review first, and the API to `main` after approval. Release and deploy the API before releasing the app to users.
2. It tags `app-vX.Y.Z`, and Xcode Cloud's **App Store** workflow builds that commit. Android goes to Play **production as a draft**.
3. **App Review (iOS)** waits until App Store Connect has processed the build. Then it submits the build for review, set to a manual release, with "What's New" from `whats_new.txt`. If an older release is still waiting for review, it is taken back and replaced by this one.
4. Once Apple approves, release by hand: App Store Connect → the version → **Release This Version**. On Play: Production → the draft release → Review → Start rollout.

Step 3 needs the App Store Connect API key (see One-time setup). Until it is set, submit by hand: App Store Connect → version X.Y.Z (create it with the + if it isn't there) → pick the build → What's New → Manually release this version → Submit for Review.

## Test builds

GitHub → Actions → **App store build** → Run workflow. Pick `channel` and `branch` (default `staging`).

| channel | Tag pushed | iOS (Xcode Cloud workflow) | Android | API | Meant for |
|---|---|---|---|---|---|
| `internal` | `app-internal-X.Y.Z-<versionCode>` | **Internal** → TestFlight internal testers | Play **internal testing** | dev | any time |
| `beta` | `app-beta-X.Y.Z-<versionCode>` | **Beta** → TestFlight internal + public testers | Play **open testing** | staging | ~2× a week |

A release (push to `release/app`) talks to the production API.

TestFlight testers see the latest eduai-app commits as "What to Test".

## How it works

The tag is what starts Xcode Cloud, so iOS and Android always build the same commit.

The **iOS (Xcode Cloud)** job builds nothing itself. It waits for Xcode Cloud's checks on the tagged commit, links the build in the run summary, and ends with Xcode Cloud's result. If Xcode Cloud starts no build within 15 minutes, the job fails; usually the workflow for that tag prefix is missing or broken.

Things to know:
- **The channel picks the API.** `dart_defines.sh` maps it: `internal` → dev (`api-dev-8b6a.up.railway.app`), `beta` → staging (`app-api-stage.edu-ai.eu`), `release` → production (`app-api.edu-ai.eu`). Xcode Cloud reads the channel off the tag, the Android job gets it from the run. A store build without a channel fails rather than fall back to production, so Xcode Cloud builds only from these tags. The app's About page shows the API it uses.
- **Every channel is the same app** (`com.eduai.eduaiapp`). A tester who moves to a build on another API is signed out once: the old API's token gets a 401 there, and the 401 logout wipes the local data. Nothing crosses between the environments.
- **Versions come from the tags, not from `pubspec.yaml`.** A release is the last `app-vX.Y.Z` plus a patch. Test builds carry the version the next release will get, because Apple closes a version once it approves it. The tag names the version, and `ci_post_clone.sh` and the Android build pass it to Flutter.
- **For a minor or major release, raise `version` in `pubspec.yaml`.** It is the floor: the next version is never lower.
- **Skipped versions are fine.** A push while a release waits for review makes the next version, which replaces the waiting one.
- **The first public beta of each version waits for Apple's beta review** (usually under a day). Later betas of the same version usually go out without waiting. Play reviews open-testing releases too.
- **Build numbers never come from `pubspec.yaml`.** iOS uses the Xcode Cloud counter. Android uses `ANDROID_VERSION_CODE_BASE` (100) + the run number.
- **The `app-vX.Y.Z` tag marks the commit in the stores.**
- **For another build, start a new run.** Re-running only the failed jobs is fine. Re-running the whole run reuses its run number, so the tag already exists and the push fails.
- **Flutter is pinned to the same version in two places:** `FLUTTER_VERSION` in the workflow and in `ci_post_clone.sh`.
- **The dart-define list lives in one place:** `dart_defines.sh`, shared by the local `build_*.sh` scripts and Xcode Cloud.
- **Xcode Cloud includes 25 compute hours a month.** A build takes roughly 20–30 min, because every run installs Flutter and pods. That is about 50 builds a month across all three channels.

## One-time setup

### Xcode Cloud

You need the Admin or App Manager role in the EDU-AI team.

1. Open `eduai-app/ios/Runner.xcworkspace` in Xcode → Integrate → Create Workflow, product **Edu**. The first setup only works from Xcode.
2. **Grant Access** → GitHub. An **owner of the `nobig-deals` org** must install Apple's GitHub app, and only for `nobig-deals/eduai`.
3. Three workflows, the same except for the start tag and the post-actions:

   | Workflow | Start condition: Tag Changes, tags beginning with | Post-actions |
   |---|---|---|
   | Internal | `app-internal-` | TestFlight Internal Testing |
   | Beta | `app-beta-` | TestFlight Internal Testing + TestFlight External Testing (the public group) |
   | App Store | `app-v` | TestFlight Internal Testing |

   Shared settings:
   - Delete the default *Branch Changes* condition; *Manual Start* may stay (it never fires on its own).
   - **Environment:** latest release Xcode.
   - **Environment variables:** `MICROSOFT_CLIENT_ID`, `GOOGLE_WEB_CLIENT_ID`, `MICROSOFT_TENANT_ID`, `FIREBASE_*`. Copy the values from Railway → EDU AI → `eduai-app` → production variables. They are compile-time dart-defines; a missing `MICROSOFT_CLIENT_ID` fails the build on purpose.
   - **Actions:** Archive – iOS, scheme `Runner`, deployment preparation **TestFlight and App Store**. Set the actions up in Xcode (Integrate → Manage Workflows); the App Store Connect web lists no schemes. Once one workflow is complete, the others can be duplicated from it on the web.
4. App Store Connect → Xcode Cloud → Settings → Build Number → **Next Build Number** above the last uploaded build (36+).

### App Store Connect API key (automatic App Review)

1. Only the **Account Holder** can do this step, and only once: App Store Connect → Users and Access → Integrations → App Store Connect API → **Request Access**.
2. An Admin then generates a **Team key** with the **App Manager** role and downloads its `.p8` file. Apple offers the download only once.
3. Put the key into GitHub. The **App Review (iOS)** job runs only when `ASC_KEY_ID` is set.

   ```bash
   gh variable set ASC_KEY_ID -R nobig-deals/eduai      # Key ID column
   gh variable set ASC_ISSUER_ID -R nobig-deals/eduai   # Issuer ID above the key list
   gh secret set ASC_KEY_P8 -R nobig-deals/eduai < AuthKey_XXXXXXXXXX.p8
   ```

The job runs `ios/fastlane/Fastfile` (lane `submit_review`).

### Google Play

1. Google Cloud project `edu-ai-asistent`:
   - Enable the *Google Play Android Developer API*.
   - Create a service account and download a JSON key.
2. Play Console → Users and permissions → invite the service-account e-mail for `com.eduai.eduaiapp` with these permissions:
   - release to production
   - release to testing tracks
   - manage testing tracks
3. GitHub secret `PLAY_SERVICE_ACCOUNT_JSON` = the JSON key.

### GitHub (`nobig-deals/eduai`)

The **Run workflow** button only shows once `.github/workflows/app-store.yml` is on the default branch (`main`), and it runs `main`'s copy of the workflow. A push to `release/app` runs that branch's copy.

The `release/app` branch is made once from `staging` (`git push origin origin/staging:refs/heads/release/app`). That push is already the first release.

Secrets (upload keystore = `~/eduai-upload-key.jks`, values from the gitignored `eduai-app/android/key.properties`):

```bash
base64 -i ~/eduai-upload-key.jks | gh secret set ANDROID_UPLOAD_KEYSTORE_BASE64 -R nobig-deals/eduai
gh secret set ANDROID_KEY_ALIAS -R nobig-deals/eduai
gh secret set ANDROID_KEY_PASSWORD -R nobig-deals/eduai
gh secret set ANDROID_STORE_PASSWORD -R nobig-deals/eduai
gh secret set PLAY_SERVICE_ACCOUNT_JSON -R nobig-deals/eduai < service-account.json
```

Variables (not secret — they ship inside the app binary). Use the same values as in Xcode Cloud:

```bash
gh variable set GOOGLE_WEB_CLIENT_ID -R nobig-deals/eduai
gh variable set MICROSOFT_CLIENT_ID -R nobig-deals/eduai
gh variable set MICROSOFT_TENANT_ID -R nobig-deals/eduai
# FIREBASE_API_KEY, FIREBASE_PROJECT_ID, FIREBASE_MESSAGING_SENDER_ID,
# FIREBASE_ANDROID_APP_ID, FIREBASE_IOS_APP_ID, FIREBASE_IOS_BUNDLE_ID once push is set up
```

### Sentry (readable crash reports)

The app reports to Sentry (`no-big-deals` / `eduai-app`) without any setup; its DSN is built in. What needs a token is uploading the files that turn minified or native frames back into source lines. Each upload is skipped without one and never fails a build.

Create an **organization auth token** in Sentry (Settings → Auth Tokens, `https://no-big-deals.sentry.io/settings/auth-tokens/`; it carries the EU region, so nothing else is configured) and set it as `SENTRY_AUTH_TOKEN` in three places:

- GitHub secret (`gh secret set SENTRY_AUTH_TOKEN -R nobig-deals/eduai`): the Android job uploads the native debug files and the R8 mapping.
- Xcode Cloud, every workflow → Environment variables, marked **Secret**: `ios/ci_scripts/ci_post_xcodebuild.sh` uploads the archive's dSYMs.
- Railway → EDU AI → `eduai-app`, production and staging variables: the web build uploads its source maps and deletes them before serving.
