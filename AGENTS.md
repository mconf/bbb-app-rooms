# AGENTS.md

Rooms: the BigBlueButton app launched through the LTI broker. Rooms, scheduled meetings, recordings and the Moodle, Brightspace, Eduplay and FileSender integrations.

Placeholder: this repo does not follow the Mconf repository baseline yet (no Makefile, no pre-commit hook). Standards: https://github.com/mconf/mpedia/tree/main/development

## Checks

The same commands CI runs (`.github/workflows/ci.yml`):

```bash
bundle exec rubocop
bundle exec rspec
bundle exec brakeman -q
```

## Logs never carry credentials

The launch brings the consumer's credentials in `custom_params` (BBB secret, Moodle token, Brightspace client secret), and integrations add their own tokens (OAuth, Eduplay, FileSender). Logs end up in shared storage, so a credential in a log line is a leaked credential.

- Never interpolate a secret or a token into a log line in full. Log ids when they are enough (`MoodleToken id=12`).
- A hash that may hold one (launch params, `custom_params`, a config, an `OmniAuth::AuthHash`) goes through `filter_for_log` (`ApplicationController`); a lone value, through `Mconf::LogFilter.mask`. Both keep only a 7-char prefix, enough to tell which credential was used.
- Personal data (names, e-mails) only when needed, e.g. support correlates launches by e-mail. Once logged, the log retention policy takes care of it.
