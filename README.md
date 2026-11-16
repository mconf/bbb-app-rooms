# bbb-app-rooms

The LTI rooms tool of Elos and ConferênciaWeb: what teachers and students see when they
open the conference tool from their LMS (e.g. Moodle, Brightspace). Each course
becomes a room where users schedule meetings, join them and access recordings, reports
and AI artifacts.

The app does not receive LTI launches directly: they arrive through
[bbb-lti-broker](https://github.com/mconf/bbb-lti-broker), which authenticates the LMS
and hands the user over via OAuth2. It started as a fork of the BigBlueButton project
but has diverged; upstream docs don't apply here.

For architecture, conventions and pitfalls, see [AGENTS.md](AGENTS.md).

## Requirements

- Docker and Docker Compose
- A running [bbb-lti-broker](https://github.com/mconf/bbb-lti-broker) (needed to launch
  the app; the specs run without it)
- A BigBlueButton server to create meetings on

## Running locally

1. Create `.env.development.local` (git-ignored) with the values specific to your
   environment:

   ```bash
   URL_HOST=                     # host where the app is reached
   OMNIAUTH_BBBLTIBROKER_SITE=   # URL of your broker
   BIGBLUEBUTTON_ENDPOINT=       # https://<server>/bigbluebutton/api
   BIGBLUEBUTTON_SECRET=
   ```

   The committed `.env` and `.env.development` hold the shared defaults (database,
   Redis, broker key/secret). Optional integrations (Data API, Eduplay, Filesender,
   SMTP…) are documented in `.env.example`.

2. Build the images and install the JavaScript packages, then start the app
   (Postgres and Redis come up with it; `scripts/start.sh` creates or migrates the
   database on boot):

   ```bash
   make install
   make run
   ```

   Run `make install` again whenever the `Gemfile` changes.

   The app listens on port 3001 under `/rooms` (or `/<RELATIVE_URL_ROOT>/rooms`).

3. Register the app in the broker, using the key and secret set in
   `OMNIAUTH_BBBLTIBROKER_KEY` / `OMNIAUTH_BBBLTIBROKER_SECRET` (see the broker's
   README). The second argument is the OAuth2 callback URL, which the broker also
   uses to derive where it sends the launches:

   ```bash
   # run in the broker
   rake "db:apps:add[rooms,https://<host>/rooms/auth/bbbltibroker/callback,<key>,<secret>]"
   ```

Background jobs (attendance, recording uploads, recurring meetings) need the Resque
worker and scheduler: `docker compose up rooms_worker rooms_scheduler`.

The theme is chosen by `APP_THEME` (`elos` or `rnp`, set in `.env`).

## Tests and lint

The same checks the CI runs (`.github/workflows/ci.yml`):

```bash
make lint      # RuboCop + Brakeman
make format    # RuboCop safe auto-corrections
make test      # prepares the test database and runs the specs
```

All targets run inside Docker Compose (`make help` lists them). To run on the host,
empty the wrapper: `make lint RUN=`, `make test RUN_TEST=`. On the host, set
`DATABASE_URL` to a test database first (the CI `test` job shows the values it uses):
with the one from `.env`, the specs would use and wipe the development database.

Write new tests in `spec/`; `test/` is legacy and not run by CI.

## Build

```bash
make build               # elos image, tagged bbb-app-rooms:local
make build THEME=rnp     # ConferênciaWeb image
```

Releases and deployment: see [AGENTS.md](AGENTS.md#deployment).

## License

See [LICENSE](LICENSE).
