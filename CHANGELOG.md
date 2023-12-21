# Change Log

## [Unreleased]
[Unreleased]: https://github.com/mconf/bbb-app-rooms/compare/v0.10.0...master-elos

## 0.10.0 - 2023-12-21
### Added
- [LTI-123] | Ipezinho widget.
  - PR: [#82]
- [LTI-116] | EduPlay integration.
  - PR: [#78]
- [LTI-135] | Filesender integration pt. I.
  - PR: [#77]
- [LTI-122] | Filesender integration pt. II.
  - PR: [#80]
- [ELOSP-1021] | Learning dashboard access link through the history page.
  - PR: [#75]

<!-- Cards -->
[LTI-123]:https://www.notion.so/mconf/Adicionar-widget-do-Ipezinho-no-LTI-adec9c744e26486ba31d3f4040f3b3b7?pvs=4
[LTI-116]:https://www.notion.so/mconf/Integra-o-com-o-Eduplay-no-LTI-4186acee2eb64c6f8e034b090747386c?pvs=4
[LTI-122]:https://www.notion.so/mconf/FileSender-no-LTI-Etapa-2-99af304973ef4da6b8024822c1151743?pvs=4
[LTI-135]:https://www.notion.so/mconf/FileSender-no-LTI-Etapa-1-b0dffd5253684528a543f0ff095690b7?pvs=4
[ELOSP-1021]:https://www.notion.so/mconf/Permitir-usu-rio-baixar-acessar-os-dados-do-learning-dashboard-p-s-confer-ncia-a7d47a195c214760b3c44f3da0b47ae1?pvs=4

<!-- PRs -->
[#82]: https://github.com/mconf/bbb-app-rooms/pull/82
[#78]: https://github.com/mconf/bbb-app-rooms/pull/78
[#80]: https://github.com/mconf/bbb-app-rooms/pull/80
[#77]: https://github.com/mconf/bbb-app-rooms/pull/77
[#75]: https://github.com/mconf/bbb-app-rooms/pull/75

## 0.9.1 - 2023-12-20
### Changed
- [LTI-136] | History page:
  - Load meeting data (participants and notes) links only when the dropdown is opened, via XHR,
  to reduce the number of API calls;
  - Make the UI more clear when meeting data links are disabled;
  - Meeting data links can only be opened by logged in users.
  - PRs: [#81]

<!-- Cards -->
[LTI-136]: https://www.notion.so/mconf/Fixes-vers-o-0-9-0-Rooms-62b177893e4b4615b3e56e3495e83e5d?pvs=4

<!-- PRs -->
[#81]: https://github.com/mconf/bbb-app-rooms/pull/81

## 0.9.0 - 2023-04-04
### Added
- [LTI-5] | Added new getting to recordings with paginate. Now get 25 recordings each page,
  the number of recordings per page can be set by `RECORDINGS_PER_PAGE` env var.
  - PRs: [#38]
- [LTI-72] | Added `participants` and `notes` from meetings. New integration made with Bucket.
  - PRs: [#63]
- [LTI-82] | Added Analytics tags.
  - PRs: [#41]
- [LTI-84] | Added metrics exporter by new integration with `prometheus_exporter`. 
  - PRs: [#56]
- [LTI-90] | Created local deploy from `k8s`.
  - PRs: [#43]
- [LTI-107] | Added meeting and recording history page(theme RNP & COC).
  - PRs: [#65]
- [LTI-110] | Added recurrence bullet to history page.
  - PRs: [#64]
- [ELOSP-700] | Added new error pages.
  - PRs: [#46]
### Changed
- [LTI-23] | Changed history page, from recordings list to meetings list.
  if there was any recording in the meeting, it will be added in.
  - PRs: [#50]
- [LTI-46] | Changed logic item(`app_launches`) reduction to background with workers.
  - PRs: [#45]
- [LTI-78] | Now `getRecordings` using `meetingID` with `wildcard` instead of metadata.
  - PRs: [#37]
- [LTI-100] | Updated to `bbb_api_ruby` new version.
  - PRs: [#47]
- [LTI-109] | Updated to `bbb_api_ruby` new version with fixed `get_all_meetings`.
  - PRs: [#73]
- [LTI-116] | Updated `workers` and added loop.
  - PRs: [#68]
### Fixed
- [LTI-36] | Fixed to render error page on wrong url.
  - PRs: [#44]
- [LTI-108] | Fixed `get_all_meeting`.
  - PRs: [#59]
### Removed
- [LTI-101] | Removed secret and endpoint from deploy configs from `k8s`.
  - PRs: [#48]

<!-- Cards -->
[LTI-5]: https://www.notion.so/mconf/Pagina-o-de-grava-es-no-LTI-2af06b03e0bb40d6b1755f4c0f4d4128
[LTI-23]: https://www.notion.so/mconf/P-gina-de-hist-rico-de-reuni-es-e-grava-es-no-LTI-tema-Elos-6bc76c72f9d34f4583211b9f2f2741a8
[LTI-36]: https://www.notion.so/mconf/Erro-ao-tentar-renderizar-p-gina-de-erro-no-LTI-5c6a560bdae04b0e96d65d5214aa27d3
[LTI-46]: https://www.notion.so/mconf/Mudar-a-l-gica-de-remo-o-de-itens-antigos-para-ser-em-background-workers-5b88b9304c0e4c44b93f283e6fcd292e
[LTI-72]: https://www.notion.so/mconf/Relat-rio-para-professores-com-dados-da-atividade-dos-alunos-46b59cb67b4e48a088ba051458be0577
[LTI-78]: https://www.notion.so/getRecordings-usando-meetingID-com-wildcard-no-lugar-de-metadados-649d87fa3907486c8a24a87bf1a08fcc
[LTI-82]: https://www.notion.so/mconf/Incluir-tags-do-Analytics-no-LTI-rooms-1b68a8e92c5348e78c4c9655bf464d1c
[LTI-84]: https://www.notion.so/mconf/Exporter-de-m-tricas-para-o-prometheus-no-LTI-68a2436959804efbb7d14b9705018dbe
[LTI-90]: https://www.notion.so/mconf/Criar-o-deploy-local-do-k8s-9e2c3ac567a44c26856295f4afcf9d36
[LTI-100]: https://www.notion.so/mconf/Atualizar-o-portal-LTI-para-a-nova-vers-o-da-bbb_api_ruby-c993583d12ee41768f952af84ec85a92
[LTI-101]: https://www.notion.so/mconf/Remover-secret-e-endpoint-nos-configs-do-deploy-do-kubernetes-no-LTI-308be992ca5b42f29f6175dbdcb9e5c9
[LTI-107]: https://www.notion.so/mconf/P-gina-de-hist-rico-de-reuni-es-e-grava-es-no-LTI-tema-RNP-e-COC-64bb4995dfa445838cbf7e1cf6da12a6
[LTI-108]: https://www.notion.so/mconf/Corrigir-get_all_meetings-no-LTI-b7ae974e2259409b8c67e125a01152e9
[LTI-109]: https://www.notion.so/mconf/Atualizar-LTI-para-nova-vers-o-da-bbb-api-ruby-get_all_meetings-96faff318527454e8fdb5c444d45ca62
[LTI-110]: https://www.notion.so/mconf/Usar-metadado-de-qual-agendamento-as-confer-ncias-se-originaram-e-montar-o-bullet-de-periodicidade-f226526cde0e487cac28f0a65cd834e2
[LTI-116]: https://www.notion.so/mconf/Melhorias-no-workers-da-v0-9-0-e-v0-5-0-do-LTI-9aa0b6f0d8cb4cc283ebe391ef409bb1
[ELOSP-700]: https://www.notion.so/mconf/Novas-telas-para-as-p-ginas-de-erros-751f2ec7da914dd983517a36ecead24d

<!-- PRs -->
[#38]: https://github.com/mconf/bbb-app-rooms/pull/38
[#50]: https://github.com/mconf/bbb-app-rooms/pull/50
[#44]: https://github.com/mconf/bbb-app-rooms/pull/44
[#45]: https://github.com/mconf/bbb-app-rooms/pull/45
[#63]: https://github.com/mconf/bbb-app-rooms/pull/63
[#37]: https://github.com/mconf/bbb-app-rooms/pull/37
[#41]: https://github.com/mconf/bbb-app-rooms/pull/41
[#56]: https://github.com/mconf/bbb-app-rooms/pull/56
[#43]: https://github.com/mconf/bbb-app-rooms/pull/43
[#47]: https://github.com/mconf/bbb-app-rooms/pull/47
[#48]: https://github.com/mconf/bbb-app-rooms/pull/48
[#65]: https://github.com/mconf/bbb-app-rooms/pull/65
[#59]: https://github.com/mconf/bbb-app-rooms/pull/59
[#73]: https://github.com/mconf/bbb-app-rooms/pull/73
[#64]: https://github.com/mconf/bbb-app-rooms/pull/64
[#68]: https://github.com/mconf/bbb-app-rooms/pull/68
[#46]: https://github.com/mconf/bbb-app-rooms/pull/46

# 0.8.5 - 2023-12-11
### Fixed
- [LTI-140] | Correction on the `recordings` page when there is no `presentation_video`.
  - PRs: [#79]

<!-- Cards -->
[LTI-140]: https://www.notion.so/mconf/Fix-recordings-page-LTI-ConfWeb-016131edc43240f587d804b1ec302aea?pvs=4

<!-- PRs -->
[#79]: https://github.com/mconf/bbb-app-rooms/pull/79


## 0.8.4 - 2023-11-30
### Added
- [LTI-134] | Support for scoping rooms by Moodle activity. Switched on via the custom parameter
  `enable_groups_scoping=true`, configured on the LMS.
  - PRs: [#76]

<!-- Cards -->
[LTI-134]: https://www.notion.so/mconf/Suporte-a-grupos-do-Moodle-no-LTI-0b27302d8b7c49e6a35e87c4f554113b?pvs=4

<!-- PRs -->
[#76]: https://github.com/mconf/bbb-app-rooms/pull/76

## 0.8.3 - 2023-04-04
### Added
- [LTI-125] | Added `Spanish` locale support.
  - PRs: [#74]

<!-- Cards -->
[LTI-125]: https://www.notion.so/mconf/Portal-Gerenciamento-bccb3a3fa75c40f38ead425739d13bb7?p=8216254199cf491e93224e3441f3f9b6&pm=c

<!-- PRs -->
[#74]: https://github.com/mconf/bbb-app-rooms/pull/74

## 0.8.2 - 2022-02-11
### Fixed
- [LTI-104] | Added `post` route` :join`, for external access.
  - PRs: [#58]


## 0.8.1 - 2022-02-09
### Fixed
- [LTI-104] | Add get route to `/join` to open conference in new tab, without exposed method return
  `404` to user.
  - PRs: [#57]


## 0.8.0 - 2022-02-04
### Migration notes
- Migration to add the `external_widget` column from `consumer_configs` table.
### Added
- [LTI-103] | New attribute `external_widget` on `consumer_configs` to add a custom widget.
  Add partial to render customizable widget on `/external` and `/schedules` pages.
  - PRS: [#52]


## 0.7.1 - 2022-01-21
### Fixed
- Recordings page uses version `0.6.4` code.
* [LTI-101] | Portal COC


## 0.7.0 - 2022-01-21
### Added
- `COC` theme.
- Integrations for theme `COC` with the broker.
### Cards
* [LTI-101] | Portal COC


## 0.6.4 - 2021-09-22

* [LTI-89] Added validation to check if there is a `ConsumerConfig` to display the referring message
  to the terms of use, so as not to break in the `/external` if it does not exist.


## 0.6.3 - 2021-09-07

* [LTI-88] Added a new environment variable `APP_LAUNCH_REMOVE_OLD_ON_LAUNCH` to enable/disable
  the removal of AppLaunches on launch. Set to `true` by default.
* [LTI-88] Fix typo in the environment variable `APP_LAUNCH_LIMIT_FOR_DELETE` (was called
  `APP_lAUNCH_LIMIT_FOR_DELETE`, with a lowercase `l`).
* [LTI-88] Removed `.env.development.local` from the repo, it shouldn't be tracked (it's already
  included in `.gitignore`).


## 0.6.2 - 2021-09-01

* [LTI-79] Fixed function name, for if the application is only serving Rails Admin, the root route
  is `/dash`.


## 0.6.1 - 2021-08-31

* [LTI-79] The `/health` routes have been added to application root.
* [LTI-79] Fixed feature to show message reference to terms of use, for `ConsumerConfig` with
  `message_reference_terms_use=true`.
* [LTI-79] Added default lib, to validate and test environment variables: `SERVE_APPLICATION`
  and `SERVE_RAILS_ADMIN`.
* [LTI-79] If the application is only serving Rails Admin, the root route is `/dash`.


## 0.6.0 Elos - 2021-07-28

* [LTI-10] Added theme Conferência Web.
* [LTI-29] Added Rails Admin and environments for configure to application and/or rails admin.
* [LTI-45] Automatically remove old `AppLaunches`. Removes all launches older than `LAUNCH_DAYS_TO_DELETE`
  days. Defaults to 15.
* [LTI-54] Added a new attribute to `ConsumerConfig` called `message_reference_terms_use` so that we can
  display the terms of use reference message for unlogged in  users.
* [LTI-71] Fixed the field `scheduled_meeting_id` in the `BrightspaceCalendar` for `scheduled_meeting_hash_id`
  for delete `ScheduledMeetings`.

Migration notes:

* For use theme RNP, is necessary set `APP_THEME=rnp` in `.env`.
* New environments variables `SERVE_APPLICATION`, `SERVE_RAILS_ADMIN`, `AUTHENTICATION_RAILS_ADMIN`,
  `ADMIN_KEY` and `ADMIN_PASSWORD`, it is necessary to configure as needed for use application and/or rails admin.
* New environments variables `LAUNCH_DAYS_TO_DELETE` and `LAUNCH_LIMIT_FOR_DELETE` to decide how old launches
  have to be to be automatically removed and limit for delete in action. Defaults to `15` and `1000` (will
  remove all launches from 15 or more days ago and not meeting associated).
* New attribute `message_reference_terms_use` on `ConsumerConfig` to turn show/hide the reference message
  for users non logged. It is set to `true` by default in the migration, must be set to false for the
  clients that wish to hide the message.
* New migrate for rename field `scheduled_meeting_id` in the `BrightspaceCalendar` for `scheduled_meeting_hash_id`.


## 0.5.1 Elos - 2021-06-25

* [LTI-69] Fix the page of recordings that was breaking with "undefined method '[]' for nil:NilClass".
* [LTI-69] Improve the text in the `/wait` page now that the polling with redirect the user automatically
  to the conference when it starts.


## 0.5.0 Elos - 2021-06-20

* [LTI-40] Added the logic to authenticate the access to recordings using `getRecordingToken`. Disabled
  by default, can be enabled setting `PLAYBACK_URL_AUTHENTICATION=true`.
* [LTI-48] Allow users to use a custom duration for events other than selecting one of the pre-defined options.
* [LTI-6] Re-enabled the polling in the join conference page to auto join the user when the conference starts.
  Adds a new environment variable `RUNNING_POLLING_DELAY` that defaults to `10000` milliseconds.
* [LTI-53] Changed the URLs of meetings to use random hashes instead of IDs. The old URLs will still work,
  redirecting to the new ones.
* [LTI-52] Added a new attribute to `ConsumerConfig` called `download_presentation_video` so that we can hide
  the links to download recordings to everyone that is not considered a moderator (see
  `BIGBLUEBUTTON_MODERATOR_ROLES`). By default it will still show the links to everyone, must be disabled
  for clients that want the links to be hidden.

Migration notes:

* New environment variable to enable the authentication of recordings `PLAYBACK_URL_AUTHENTICATION`. It
  is disabled by default and can be enabled by setting `PLAYBACK_URL_AUTHENTICATION=true`.
* New environment variable to set the interval for the polling in the join conference page
  `RUNNING_POLLING_DELAY`. Defaults to `10000` (milliseconds).
* New attribute `download_presentation_video` on `ConsumerConfig` to turn on/off the download recording
  link for non moderators. It is set to `true` by default in the migration, must be set to false for the
  clients that wish to hide the links.


## 0.4.6 Elos - 2021-04-13

* [LTI-50] Update Rails to 6.0.3.6 (from 6.0.3.1) to fix an error when building the app:
  mimemagic (0.3.5) doesn't exist anymore.


## 0.4.5 Elos - 2021-04-11

* [LTI-42] Update a recurring meeting when a user access `/external` and the previous occurrence of
  the meeting already ended (the same that is done in `rooms#show`, but only for the target meeting).
* [LTI-37] Allow users that are signed in to access `/external` even when the meeting is configured
  to not allow external users (this is necessary because we are using `/external` as we would use
  a `meetings#show` action in Brigthspace's calendar link).


## 0.4.4 Elos - 2021-03-15

* [LTI-35] Fix errors that happen when a call to the Brightspace's API fails. It now captures the
  exceptions and doesn't throw a 500 to the user.
  Also changed the format of the logs to include the entire stack trace when an exception is
  raised so we have more information about the error.


## 0.4.3 Elos - 2021-01-24

* [LTI-32] Fix error 500 when editing or removing a scheduled meeting that had its event removed
  from Brightspace's calendar. It would show a 500 error and log error messages. Now it recreates
  the event in Brightspace's calendar (when editing the scheduled meeting) and logs messages as
  warning instead of errors.


## 0.4.2 Elos - 2021-01-17

* Fix typo on `AppLaunch#custom_param_true?`, now called `AppLaunch#is_custom_param_true?`.


## 0.4.1 Elos - 2021-01-17

* [LTI-4] When a user tries to edit an event that has no entry in Brightspace's calendar yet, it
  will now create the event in the calendar instead of showing an error.


## 0.4.0 Elos - 2020-12-16

* [ELOSP-578] Include a link to the LTI meeting in the event created in Brigthspace's calendar.
  The link opens a new tab, launches the LTI and directs the user to the meeting's page (for now
  this is the external page, since there's no meetings#show).
* [ELOSP-607] Fix an error that would occur related to the integration with Brigthspace's calendar.
  It happened after a launch with an expired AppLaunch was made and resulted in an ugly error page
  for users. It now shows the proper error page as it did before.
* [ELOSP-577] Fix editing a meeting to be non recurring after it was created being a recurring
  meeting (it was not possible, it would be recurring forever).


## 0.3.1 Elos - 2020-11-16

* [PR#10] Small fixes to try to remove an error in the authentication for some users. The first
  lines of the error look like:
    ```
    \nNoMethodError (undefined method `[]' for nil:NilClass):\n  \nrack (2.2.3) lib/rack/etag.rb:38:in `call'\nrack (2.2.3) lib/rack/conditional_get.rb:27:in `call' \nrack (2.2.3) lib/rack/head.rb:12:in `call'\nactionpack (6.0.3.1)
    ```


## 0.3.0 Elos - 2020-11-15

* [ELOSP-585] Add a new page to list the reports for an LTI room. Reports are stored in
  DigitalOcean's Spaces and might or might not exist for a room. It builds the list dynamically
  and allows the user to download directly from Spaces using authenticated temporary URLs.
* [ELOSP-602] Fix an error when the app couldn't find an AppLaunch when trying to authenticate
  on a Brightspace LMS as part of the integration with their calendar.


## 0.2.0 Elos - 2020-11-07

* [ELOSP-455] Integration with Brightspace's calendar. Includes a refactor of the configurations
  in the database. Use the rake task `db:brightspace:add` to configure a Brightspace for a consumer
  key and enable the integration with its calendar.
* [ELOSP-574] Edit and remove events in Brightspace's calendar when they are edited or removed
  in the application.


## 0.1.3 Elos - 2020-09-24

* [ELOSP-454] New hints for the new configuration options added in 0.1.3.
* Change the text in the "try again" button to "join", "try again" gives a false impression
  that an error happened.


## 0.1.2 Elos - 2020-09-13

* [ELOSP-454] New configuration options in conferences (by default they are all false, so
  that the features are enabled):
  * Disable the external link;
  * Disable private chat;
  * Disable shared notes.


## 0.1.1 Elos - 2020-08-29

* Better rescue for BigBlueButton exceptions so they won't throw a 500 error, instead they will
  show a toast with the error for the user. Also log all 500 errors so we can track them.
* Auto join the user after a few seconds if a `meetingAlreadyBeingCreated` error happens.
* Create the meeting only if it's not already running. Would create the meeting always when a user
  with permission to create would try to join.
* [ELOSP-498] Fix toasts not being closable.
* Notify connected users that a meeting was created only if cable is enabled.


## 0.1.0 Elos - 2020-08-16

* [ELOSP-457] Use `oauth_consumer_key` when generating room handlers. This key is set by the broker
  in the launch, so it's more secured, can't be edited by the LMS. This makes it more certain
  that handlers will be unique for each key used, so different clients won't mess with
  others' rooms.
* Add favicons to `public/rooms/`, so they don't use the fingerprints when served. The links in
  the XML the broker serves use this URL.
* Auto join the user if going to /wait and the meeting is running.
* Set `cache-control` for all assets when serving assets in production.
* Paginate the list of scheduled meetings with kaminari.
* Use the browser's timezone over the default timezone. After a request, a js sets the timezone in
  a cookie so the server can use it. In the first request it won't be there, so it will use the
  default timezone set in the env variable.
* Add env variable `FORCE_DEFAULT_TIMEZONE` to force the default timezone and ignore the one
  in the cookie. Brings back the old behaviour.
* Show the user the time zone being used in the dates right below the tables and in the tooltip
  of the form components that have a date/time.
* Better errors in general, mostly when URLs are not found (weird links). Less false 500 errors.


## 0.0.16 Elos - 2020-08-02

* Add recurring events with the options: weekly and biweekly. The event is reused, it just
  updates its date on rooms/show if it already expired.


## 0.0.15 Elos - 2020-07-22

* Add option to copy the playback link in a recording.
* Add a table `consumer_configs` to store configurations for each customer. Indexed by the key
  the consumer uses to launch the LTI.
* Add a disclaimer in the external access page. Configure for each customer, by default won't
  show anything.
* Set the duration on create. By default won't set the duration, only when the consumer is configured
  to do so. Sets the duration to the duration of the scheduled meeting plus one hour.
* Serve an html in `/healthz.html` to try to speed up the application boot. Kubernetes will check
  it right after the pod starts and it will take a while to respond while Rails loads, so this
  loading time won't affect user requests.
* Add `Room#consumer_key` to optimize db queries. Uses it directly instead of having to list
  all app launches to get the latest one.
* Set `key` as unique in the `bigbluebutton_servers` and `consumer_configs` tables.
* Show meetings for one hour more than their duration to make it a little better for people in
  other timezones until we have a proper solution for multiple timezones.


## 0.0.14 Elos - 2020-07-20

* Fix to use the locale in the launch over the default locale of the browser.
* Fix validation of the room when accessing open routes for scheduled meetings. Accessing
  `:room/scheduled_meetings/:id/external`, for example, was not validating the room, so any meeting
  could be accessed in the scope of any valid room. Now scheduled meetings are only searched
  in the scope of the current room.


## 0.0.13 Elos - 2020-07-19

* Fix the datetime input in mobile by disabling the native integration. Will show
  the selector just as it does in a desktop browser.
* Configure the session cookie with SameSite=None and Secure. Necessary to open the application
  in an iframe, Chrome started blocking cookies otherwise.
* When creating a meeting, initiate it with attributes from its room, that can be configured
  using custom parameters in the launch.
* Add custom parameters to the launch to enable/disable edition of the flags `all_moderators`
  and `wait_moderator`. The parameters are called `allow_all_moderators` and `allow_wait_moderator`.
  If they are not informed, users are allowed to edit the attributes when editing and creating
  scheduled meetings. If they are informed with `true` (has to be this value), users are also
  allowed to edit the attributes. If they are informed with any other value, users will not
  see the attributes in the views, will not be allowed to edit them and they will assume
  their default values when used (`wait_moderator=true` and `all_moderators=false`).
  * New migration to include the attributes `allow_all_moderators` and `allow_wait_moderator`
    on the table `rooms`.


## 0.0.12 Elos - 2020-07-13

<!-- Cards -->
[LTI-104]: https://www.notion.so/mconf/Portal-Gerenciamento-bccb3a3fa75c40f38ead425739d13bb7?p=5ca12a2eb7a7496cb75b4ec58c9a3f0d
[LTI-103]: https://www.notion.so/mconf/e7590828a6524cbeaedbba8b99e258ae?v=835bec4b62b04edeb84d052f7900054a&p=174de60d3c614ff0abf964b265fd21ef
[LTI-101]: https://www.notion.so/mconf/Portal-Gerenciamento-bccb3a3fa75c40f38ead425739d13bb7?p=9ac57ab16aa64130a0ac274241c873ce

<!-- Prs -->
[#58]: https://github.com/mconf/bbb-app-rooms/pull/58
[#57]: https://github.com/mconf/bbb-app-rooms/pull/57
[#52]: https://github.com/mconf/bbb-app-rooms/pull/52

<!-- Compares -->
[0.9.1]: https://github.com/mconf/bbb-app-rooms/compare/v0.9.1...v0.10.0
[0.9.1]: https://github.com/mconf/bbb-app-rooms/compare/v0.9.0...v0.9.1
[0.9.0]: https://github.com/mconf/bbb-app-rooms/compare/v0.8.3...v0.9.0
[0.8.5]: https://github.com/mconf/bbb-app-rooms/compare/v0.8.4...v0.8.5
[0.8.4]: https://github.com/mconf/bbb-app-rooms/compare/v0.8.3...v0.8.4
[0.8.3]: https://github.com/mconf/bbb-app-rooms/compare/v0.8.2...v0.8.3
[0.8.2]: https://github.com/mconf/bbb-app-rooms/compare/v0.8.1...v0.8.2
[0.8.1]: https://github.com/mconf/bbb-app-rooms/compare/v0.8.0...v0.8.1
[0.8.0]: https://github.com/mconf/bbb-app-rooms/compare/v0.7.1...v0.8.0
[0.7.1]: https://github.com/mconf/bbb-app-rooms/compare/v0.6.4...v0.7.1
[0.6.4]: https://github.com/mconf/bbb-app-rooms/compare/release-0.6.x-elos...mconf:feature-coc-on-0.6.4
