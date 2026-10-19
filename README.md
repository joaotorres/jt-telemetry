# jt_telemetry

Sentry and PostHog for my Rails apps, configured once.

- **Sentry**: backend errors and performance, via `sentry-ruby` and
  `sentry-rails`. No Sentry JS on the frontend
- **PostHog**: analytics, session replay and frontend exceptions, via
  `posthog-js` loaded through the `t.joaotorr.es` reverse proxy

## Install

```ruby
gem "jt_telemetry", github: "joaotorres/jt-telemetry", branch: "main"
```

Then call the helper once in the `<head>` of the layout, before
`javascript_importmap_tags`:

```erb
<%= csp_meta_tag %>
<%= jt_telemetry_tags %>
<%= javascript_importmap_tags %>
```

Sentry starts on its own through the Railtie. There is no initializer to write.

## Configuration

All from ENV.

| Variable                    | Default                   | Notes |
| --------------------------- | ------------------------- | ----- |
| `APP_NAME`                  | none                      | Without it telemetry is off and the boot logs a warning. PostHog `app` super property and Sentry `app` tag |
| `SENTRY_DSN`                | none                      | Sentry is not initialized without it |
| `SENTRY_TRACES_SAMPLE_RATE` | `0.1`                     | `/up` is never traced |
| `POSTHOG_KEY`               | the shared project key    | Public key |
| `POSTHOG_HOST`              | `https://t.joaotorr.es`   | Reverse proxy |
| `POSTHOG_UI_HOST`           | `https://eu.posthog.com`  | |
| `TELEMETRY_ENABLED`         | `true` in production only | `true`/`1`/`yes` or anything else for off |

The gem never stops a boot. Telemetry is always off when `SECRET_KEY_BASE_DUMMY`
is set, so `assets:precompile` in a Docker build needs none of this ENV.

Sentry also gets `environment` from `Rails.env`, `release` from
`KAMAL_VERSION` (Kamal sets it in the container) and `send_default_pii = false`.

## Secrets in paths

A path that holds a secret, such as a token, reaches both services as it is.
In Sentry, `send_default_pii = false` does not keep it out: the request URL,
the path in span data and, before a controller runs, the transaction name all
carry it. In PostHog, every event carries the page URL in several properties
and session replay records it along with each network request. An app
declares those paths in `config/application.rb`:

```ruby
config.jt_telemetry.redact_paths = ["/phone/:token"]
```

`before_send` and `before_send_transaction` then replace each `:segment` with
its name, so `/phone/x0Rx...9nWS/bundle.pkpasses` reaches Sentry as
`/phone/:token/bundle.pkpasses`. This covers the request URL, query string and
headers (a `Referer` from such a page), the transaction name, span
descriptions and data, breadcrumbs, exception messages, contexts, tags and
extra. A segment ends at the next `/`, `?`, `#`, whitespace or quote.

The tag passes the same patterns to PostHog, where they run in the browser,
so the token never leaves the device:

- `before_send` replaces them in every string of an event's `properties`,
  `$set` and `$set_once`: `$current_url`, `$pathname`, `$referrer`,
  `$initial_current_url`, `$session_entry_url`, `$prev_pageview_pathname`,
  the web vitals' `navigationURL` and the like, and the replay data in
  `$snapshot`. Compressed replay data is not walked
- `session_recording.maskCapturedNetworkRequestFn` replaces them in the URLs
  replay records: the page's and each captured network request's
  (https://posthog.com/docs/session-replay/privacy)

A path that is not in the URL, such as an API call's, still belongs in the
list when the page calls it: replay records the request. Text on the page is
not covered, so a page that shows a token marks that element `ph-no-capture`.

Checked against a mock PostHog backend that recorded what posthog-js 1.438
sent from a page at `/invite/<token>` with production's replay settings:
without the paths the token was in 40 places across `$pageview`,
`$pageleave`, `$autocapture`, `$$heatmap`, `$web_vitals`, `$set` and
`$snapshot`, with them in none.

## What the helper renders

One inline `<script>`:

- `window.jtTrack(name, props, options)`, always, so app code can call it in every
  environment. It forwards to `posthog.capture` and does nothing when PostHog
  is not loaded
- the PostHog loader and `posthog.init`, only when telemetry is on, followed by
  `posthog.register({ app: APP_NAME })`

PostHog settings:

- `persistence: "memory"`: no cookies or localStorage, so no consent banner.
  The cost is that a full page reload starts a new anonymous user and session.
  Turbo Drive navigations do not reload, so they keep both.
  `cookieless_mode` is deliberately not used: it strips the IP, which loses
  GeoIP and bot detection
- `person_profiles: "identified_only"`
- `capture_exceptions: true`
- `capture_pageview: "history_change"`: Turbo Drive and client routers change
  the URL through the History API, so each navigation is a pageview
- The script returns early if `window.jtTrack` already exists, so PostHog never
  initializes twice, even if Turbo evaluates the head script again

Session replay is switched on in the PostHog project settings, not here.

## Content Security Policy

The script tag carries the request's CSP nonce when the app sets one. Allow
the proxy host for the scripts PostHog loads at runtime (`array.js`, the replay
recorder, exception autocapture) and for its API calls:

```ruby
# config/initializers/content_security_policy.rb
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.script_src  :self, "https://t.joaotorr.es"
    policy.connect_src :self, "https://t.joaotorr.es"
    policy.worker_src  :self, :blob
  end

  config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
  config.content_security_policy_nonce_directives = %w[script-src]
end
```

`worker-src blob:` is in PostHog's own CSP examples. The PostHog toolbar needs
more (`img-src`, `style-src`, `font-src`), see
https://posthog.com/docs/advanced/content-security-policy.

## Apps without a layout

An API-only app that serves a built SPA (Done) has no layout to call the
helper from. Insert the same tag into the HTML it serves:

```ruby
Rails.public_path.join("index.html").read.sub("</head>") { "#{JtTelemetry.tags}</head>" }
```

Use the block form. As a replacement string, `sub` reads `\\` as an escape and
halves every backslash in the tag, which breaks the redaction patterns.

Pass `nonce:` if the app has a CSP. The tag is missing whenever the HTML does
not come from Rails, such as the Vite dev server or an `index.html` the service
worker precached, so frontend code calls `window.jtTrack?.(...)`.

## Event naming

`object_action`, snake_case, action in the past tense:

- `game_created`
- `pass_exported`
- `invite_accepted`

Property names are snake_case too. `jtTrack` warns in the console when a name
does not match, and still sends it. Pageviews are automatic, do not track
them by hand.

```js
window.jtTrack("game_created", { players: 4 })
```

### Events right before the page navigates away

PostHog batches events and sends them every few seconds, so an event fired
just before a navigation (a redirect to another site, `location.assign`) is
lost with the page. Pass `{ beacon: true }` for those:

```js
window.jtTrack("pass_exported", { wallet: "google" }, { beacon: true })
window.location.assign(saveUrl)
```

It calls `posthog.capture` with `{ transport: "sendBeacon", send_instantly:
true }`, as https://posthog.com/docs/libraries/js/usage recommends: the event
skips the queue and goes out through `navigator.sendBeacon`, which the browser
finishes after the page is gone. In headless Chrome, firing then navigating at
once sent the event with the option and sent nothing without it.

It works through the proxy as is. A beacon is a `POST /e/` with an
`application/x-www-form-urlencoded` body, a CORS simple request, so there is
no preflight, and the browser does not need to read the response. Delivery is
still up to the browser, so keep it for the events that need it.

## Adding a new app

1. Add the gem to the `Gemfile` (line above) and `bundle install`
2. Create the Sentry project and store its DSN in the Keychain as
   `myapp-sentry-dsn`:

   ```sh
   security add-generic-password -a "$USER" -s myapp-sentry-dsn -w
   ```

3. Set the ENV in `config/deploy.yml`. `SENTRY_DSN` is a secret, never in
   `clear`:

   ```yaml
   env:
     clear:
       APP_NAME: myapp
     secret:
       - SENTRY_DSN
   ```

   and read it from the Keychain in `.kamal/secrets`:

   ```sh
   SENTRY_DSN=$(security find-generic-password -w -s myapp-sentry-dsn)
   ```

4. Call `<%= jt_telemetry_tags %>` in the layout's `<head>`
5. If the app has a CSP, allow the hosts above
6. If any path holds a secret, declare it (Secrets in paths above)
7. Add `https://myapp.joaotorr.es` to PostHog authorized URLs (Settings > Web
   analytics). No wildcards allowed
8. Add an uptime monitor on `https://myapp.joaotorr.es/up`

## Development

```sh
bundle install
bundle exec rspec
```
