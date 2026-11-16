# AGENTS.md

AI development guidelines for bbb-app-rooms.

## Project Overview

The LTI rooms tool of Elos: what teachers and students see when they open Elos from
their LMS. Each course becomes a `Room` (identified by a `handler`), where users schedule
meetings (`ScheduledMeeting`, identified by a `hash_id`) and join the conference.

- Launches arrive through [bbb-lti-broker](https://github.com/mconf/bbb-lti-broker);
  meetings are created and joined through the BigBlueButton API.
- Recordings, usage reports, engagement data and AI artifacts come from the Mconf Data
  API (`lib/mconf/data_api.rb`), not from buckets.
- Optional integrations: Moodle, Brightspace, Eduplay, Filesender, Elos Analytics.

This started as a fork of the upstream BigBlueButton project but has diverged. Do not
assume upstream docs, issues or PRs apply here.

Non-obvious parts of the tree:

```text
themes/elos|rnp/     # Per-theme views, helpers, assets and locales (see Themes)
test/                # Legacy Minitest files, not run by CI; write tests in spec/
config/deploy/k8s/   # Local minikube setup only, not production (see Deployment)
scripts/start.sh     # Image default command (docker compose only)
```

## Development Setup

```bash
bundle install
yarn install               # node_modules is on the Sprockets load path; layouts need it
bin/rails db:prepare
bin/rails s                # or: docker compose up app (plus postgres, rooms_redis)
```

Shared defaults are in the committed `.env` and `.env.development`; per-machine values
(`URL_HOST`, `OMNIAUTH_BBBLTIBROKER_SITE`, `BIGBLUEBUTTON_ENDPOINT`/`SECRET`) go in
`.env.development.local` (not committed). `.env.example` documents the optional
integrations. Workers: `bin/rake resque:work` and
`bin/rake resque:scheduler`. There is no Makefile yet.

## Verifying Changes

Run the same checks CI runs (`.github/workflows/ci.yml`):

```bash
bundle exec rubocop -l --config .rubocop.yml     # CI runs lint cops only (-l)
bundle exec brakeman -q
APP_THEME=elos bin/rails db:test:prepare
APP_THEME=elos bundle exec rspec
```

- Tests need PostgreSQL and Redis reachable (see the `env` of the CI `test` job).
- `APP_THEME=elos` is required: some locale keys (e.g. `time.formats.short_custom`)
  only exist under `themes/`.
- WebMock blocks real HTTP in specs. Stub every external call (BBB API, Data API,
  Moodle, Brightspace, Eduplay, Filesender).

## Themes

`APP_THEME` (`elos` or `rnp`) is read at boot (`config/application.rb`,
`config/initializers/assets.rb`). Theme views, helpers, locales and assets take
precedence over the base ones in `app/` and `config/locales/`.

- Before editing a view, helper or asset, check if `themes/<theme>/` overrides it; a
  change in `app/` may not show up in a theme that overrides the file.
- A UI change usually has to be made in both `themes/elos` and `themes/rnp`.
- The theme is baked in at `assets:precompile`, so each theme ships as its own Docker
  image (`<tag>` for elos, `<tag>-rnp` for rnp).

## Code Style

- Follow `.rubocop.yml` (e.g. `Style/MethodCallWithArgsParentheses` is enabled).
- Configuration: read each env var once in `config/application.rb` with
  `Mconf::Env.fetch` / `fetch_boolean` / `fetch_int` into a `config.<name>`, use it in the
  code as `Rails.configuration.<name>`, and document the variable in `.env.example`.
  Don't read `ENV[]` in app code.
- New user-facing strings go in the locale files for `en`, `es` and `pt`. JavaScript
  reads the same files through i18n-js (`I18n.t(...)`).
- Commit messages follow Conventional Commits (`feat:`, `fix:`, `test:`, `chore:` …).

## Architecture

### Launch flow

1. The broker sends the user to `GET /launch?launch_nonce=…` (`RoomsController#launch`).
2. `authenticate_with_oauth!` redirects to the OmniAuth `bbbltibroker` strategy;
   `SessionsController#create` stores the auth in the session and redirects back to the
   launch with `session_set=true`.
3. `set_launch_room` fetches the launch from the broker
   (`/api/v1/sessions/:nonce`), checks it is valid and belongs to the session user,
   invalidates it, and saves it as an `AppLaunch` (the LTI params plus the room
   `handler`, from `AppLaunch#resource_handler`).
4. `setup_consumer_configs` copies the launch custom params into `ConsumerConfig` and
   related models, then the user lands on the room (or on a scheduled meeting, if
   `custom_scheduled_meeting` was sent).

### Session, user and authorization

- There are no user accounts. `User` (`lib/user.rb`) is a plain object built from the
  `AppLaunch` on each request.
- The session cookie keeps one entry per room handler (at most
  `COOKIE_ROOMS_MAX_KEYS` rooms) pointing to the launch nonce. Contexts without the
  cookie (e.g. a new tab to join a meeting) use a single-use `session_token`.
- Every permission check goes through `Abilities.can?` (`app/models/abilities.rb`). Add
  new permissions as actions there, not as ad hoc checks in controllers or views.

### Per-client configuration

- `ConsumerConfig` (keyed by the LTI consumer key) holds the per-tool flags
  (`allow_ai_artifacts`, `allow_student_scheduling`, `allow_elos_analytics`…). Related
  models hang off it: `ConsumerConfigServer` (dedicated BBB server, used by
  `BbbApi#bbb` instead of the default one), `MoodleToken`,
  `ConsumerConfigBrightspaceOauth`.
- These records are **rewritten from the custom params on every launch**
  (`setup_consumer_configs`). The source of truth is the tool config in the broker;
  edits made only here (e.g. in RailsAdmin at `/dash`) are overwritten on the next
  launch.
- A new per-client flag needs: a migration on `consumer_configs`, the mapping in
  `setup_consumer_configs` defaulting to `false` when absent (older brokers don't send
  new flags), the check (usually in `Abilities` or the view), and a spec like the ones
  in `spec/controllers/rooms_controller_spec.rb`.

### Meetings and recordings

- A `ScheduledMeeting` is only a schedule. The BBB meeting is created on the first
  `join` (`ScheduledMeetingsController#join`, options from
  `ScheduledMeeting#create_options`).
- The BBB `meetingID` is `<room.handler>-<room.id>-<scheduled_meeting.id>`, plus
  `-<moodle_group_id>` when Moodle groups are on. Recordings and past meetings are
  looked up by the room prefix (`meetingIDWildcard`), and
  `MeetingsController#meeting_belongs_to_room?` relies on the same prefix.
- Every meeting is created with `meta_bbb-*` metadata (`origin: LTI`, `room-handler`,
  `meeting-db-id`, context and consumer data). Downstream data and reports filter on
  it (e.g. `bbb-origin = 'LTI'`).

### Cache, jobs and admin

- `Rails.cache` holds short-lived state: session tokens, the user's current Moodle
  group, AI artifact request status. In production it is Redis when `REDIS_URL` is
  set, otherwise a per-process `memory_store`, which breaks those flows with more than
  one pod. In tests it is `:null_store`, so specs that depend on it stub `Rails.cache`.
- Resque jobs run in a separate process, so they only see what is passed as
  arguments, never the session.
- The same image serves the app and the admin, toggled by `SERVE_APPLICATION` and
  `SERVE_RAILS_ADMIN` (RailsAdmin at `/dash`).

## Common Pitfalls

- Routes are scoped under `RELATIVE_URL_ROOT` and the app is mounted at
  `/<RELATIVE_URL_ROOT>/rooms`. Use route helpers, never hardcoded paths.
- Room `handler` is derived from the LTI launch in `AppLaunch#resource_handler`
  (consumer key + `context_id`, plus `resource_link_id` when
  `custom_enable_groups_scoping` is on). Changing that logic moves users to different
  rooms.
- Per-tool flags come from the broker on each launch and only take effect on the next
  launch.
- Don't change the `meetingID` format or the `meta_bbb-*` keys without checking who
  consumes them: old recordings stop matching the room and data queries break.
- The app runs inside the LMS iframe. The session cookie is `SameSite=None`, `Secure`
  and partitioned (`config/initializers/session_store.rb`); browsers that block
  third-party cookies end up on the retry page (`sessions#retry`).
- The session cookie name includes `VERSION` (unless `SESSION_COOKIE_KEY` is set), so
  a version bump invalidates every open session.
- In Kubernetes, migrations do not run on boot: the deployment overrides the command
  with `rails s`, and `db:migrate` runs as a separate Job (`jobs/migrate.yml` in the
  infra repos). The old pods keep serving while it runs, so keep migrations backward
  compatible (add first, remove in a later release) and leave heavy data changes out
  of them (see `development/database-migrations.md` in mpedia).
- Never commit credentials or real `.env` values.

## Deployment

- The version lives in `config/application.rb` (`VERSION`); releases are commits named
  `Version X.Y.Z` plus a `vX.Y.Z` tag.
- Pushing a `v*.*.*` tag builds and pushes both theme images to Harbor
  (`.github/workflows/build.yml`).
- Deployment is not done from this repo: the Kubernetes manifests (web, workers,
  scheduler, migrate and rollback jobs, all from the same image) live in the infra
  repositories, one per environment.

## Resources

- Catalog entry (what the app does, what it calls, data it touches):
  <https://github.com/mconf/mpedia/blob/main/architecture/components/portal-bbb-app-rooms.yaml>
- Mconf development standards: <https://github.com/mconf/mpedia/tree/main/development>
  (loaded automatically by the `mpedia-dev` agent skill — no per-project setup needed)
