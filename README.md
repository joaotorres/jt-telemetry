# jt_telemetry

Sentry and PostHog for my Rails apps, configured once.

- **Sentry**: backend errors and performance, via `sentry-ruby` and
  `sentry-rails`. No Sentry JS on the frontend
- **PostHog**: analytics, session replay and frontend exceptions, via
  `posthog-js` loaded through the `t.joaotorr.es` reverse proxy

## Install

```ruby
gem "jt_telemetry", github: "joaotorres/jt_telemetry", branch: "main"
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
| `APP_NAME`                  | none                      | Required when telemetry is on, boot fails without it. PostHog `app` super property and Sentry `app` tag |
| `SENTRY_DSN`                | none                      | Sentry is not initialized without it |
| `SENTRY_TRACES_SAMPLE_RATE` | `0.1`                     | `/up` is never traced |
| `POSTHOG_KEY`               | the shared project key    | Public key |
| `POSTHOG_HOST`              | `https://t.joaotorr.es`   | Reverse proxy |
| `POSTHOG_UI_HOST`           | `https://eu.posthog.com`  | |
| `TELEMETRY_ENABLED`         | `true` in production only | `true`/`1`/`yes` or anything else for off |

Sentry also gets `environment` from `Rails.env`, `release` from
`KAMAL_VERSION` (Kamal sets it in the container) and `send_default_pii = false`.

## What the helper renders

One inline `<script>`:

- `window.jtTrack(name, props)`, always, so app code can call it in every
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
Rails.public_path.join("index.html").read.sub("</head>", "#{JtTelemetry.tags}</head>")
```

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

## Adding a new app

1. Add the gem to the `Gemfile` (line above) and `bundle install`
2. Set the ENV in `config/deploy.yml`. The DSN only allows sending events, it
   does not need to be a secret:

   ```yaml
   env:
     clear:
       APP_NAME: myapp
       SENTRY_DSN: https://...@....ingest.de.sentry.io/...
   ```

3. Call `<%= jt_telemetry_tags %>` in the layout's `<head>`
4. If the app has a CSP, allow the hosts above
5. Create the Sentry project and copy its DSN
6. Add `https://myapp.joaotorr.es` to PostHog authorized URLs (Settings > Web
   analytics). No wildcards allowed
7. Add an uptime monitor on `https://myapp.joaotorr.es/up`

## Development

```sh
bundle install
bundle exec rspec
```
