module JtTelemetry
  # Renders the <head> script: window.jtTrack always, PostHog only when enabled.
  class Tags
    # Loader from https://posthog.com/docs/libraries/js, verbatim.
    POSTHOG_SNIPPET = <<~'JS'.strip
      !function(t,e){var o,n,p,r;e.__SV||(window.posthog=e,e._i=[],e.init=function(i,s,a){function g(t,e){var o=e.split(".");2==o.length&&(t=t[o[0]],e=o[1]),t[e]=function(){t.push([e].concat(Array.prototype.slice.call(arguments,0)))}}(p=t.createElement("script")).type="text/javascript",p.crossOrigin="anonymous",p.async=!0,p.src=s.api_host.replace(".i.posthog.com","-assets.i.posthog.com")+"/static/array.js",(r=t.getElementsByTagName("script")[0]).parentNode.insertBefore(p,r);var u=e;for(void 0!==a?u=e[a]=[]:a="posthog",u.people=u.people||[],Object.defineProperty(u,"toString",{configurable:!0,enumerable:!0,writable:!0,value:function(t){var e="posthog";return"posthog"!==a&&(e+="."+a),t||(e+=" (stub)"),e}}),Object.defineProperty(u.people,"toString",{configurable:!0,enumerable:!0,writable:!0,value:function(){return u.toString(1)+".people (stub)"}}),o="init capture register register_once register_for_session unregister unregister_for_session getFeatureFlag getFeatureFlagResult isFeatureEnabled reloadFeatureFlags updateEarlyAccessFeatureEnrollment getEarlyAccessFeatures on onFeatureFlags onSessionId getSurveys getActiveMatchingSurveys renderSurvey canRenderSurvey getNextSurveyStep identify setPersonProperties group resetGroups setPersonPropertiesForFlags resetPersonPropertiesForFlags setGroupPropertiesForFlags resetGroupPropertiesForFlags reset get_distinct_id getGroups get_session_id get_session_replay_url alias set_config startSessionRecording stopSessionRecording sessionRecordingStarted captureException loadToolbar get_property getSessionProperty createPersonProfile opt_in_capturing opt_out_capturing has_opted_in_capturing has_opted_out_capturing clear_opt_in_out_capturing debug".split(" "),n=0;n<o.length;n++)g(u,o[n]);e._i.push([i,s,a])},e.__SV=1)}(document,window.posthog||[]);
    JS

    # Turbo Drive can evaluate the head script again; the jtTrack check stops a
    # second init. Warns on names that are not snake_case object_action.
    # { beacon: true } skips the batch queue and sends with sendBeacon, for an
    # event fired right before the page navigates away.
    TRACK = <<~'JS'.strip
      if (window.jtTrack) return;
      window.jtTrack = function (name, props, options) {
        if (!/^[a-z][a-z0-9]*(_[a-z0-9]+)+$/.test(name)) {
          console.warn("jtTrack: event names are snake_case object_action, e.g. game_created. Got: " + name);
        }
        var capture = options && options.beacon ? { transport: "sendBeacon", send_instantly: true } : undefined;
        if (window.posthog) window.posthog.capture(name, props, capture);
      };
    JS

    # The declared paths' :segments replaced by their names in every string of
    # an event's properties, $set and $set_once ($current_url, $pathname,
    # $referrer, $initial_current_url and replay's $snapshot_data among them),
    # and in the URLs replay records: the page's and each network request's
    # (https://posthog.com/docs/session-replay/privacy). Only plain objects and
    # arrays are walked, so compressed replay data is left as it is.
    REDACT = <<~'JS'.strip
      function (sources) {
        var patterns = sources.map(function (s) { return [new RegExp(s[0], "g"), s[1]]; });
        function redact(value) {
          if (typeof value === "string") return patterns.reduce(function (v, p) { return v.replace(p[0], function () { return p[1]; }); }, value);
          if (Array.isArray(value)) return value.map(redact);
          if (Object.prototype.toString.call(value) !== "[object Object]") return value;
          var copy = {};
          for (var key in value) if (Object.prototype.hasOwnProperty.call(value, key)) copy[key] = redact(value[key]);
          return copy;
        }
        return {
          before_send: function (event) {
            if (event) ["properties", "$set", "$set_once"].forEach(function (key) { if (event[key]) event[key] = redact(event[key]); });
            return event;
          },
          session_recording: {
            maskCapturedNetworkRequestFn: function (request) {
              if (request.name) request.name = redact(request.name);
              return request;
            }
          }
        };
      }
    JS

    def initialize(config, redact_paths: [])
      @config = config
      @redactor = Redactor.new(redact_paths)
    end

    def render(nonce: nil)
      body = [TRACK]
      body.push(POSTHOG_SNIPPET, "posthog.init(#{json(@config.posthog_key)}, #{init_options});", "posthog.register(#{json(app: @config.app_name)});") if @config.enabled?
      nonce_attribute = %( nonce="#{ERB::Util.html_escape(nonce)}") if nonce
      %(<script#{nonce_attribute}>(function () {\n#{body.join("\n")}\n})();</script>)
    end

    def posthog_options
      {
        api_host: @config.posthog_host,
        ui_host: @config.posthog_ui_host,
        defaults: "2026-05-30",
        persistence: "memory",
        person_profiles: "identified_only",
        capture_pageview: "history_change",
        capture_exceptions: true
      }
    end

    private

    def init_options
      sources = @redactor.sources
      return json(posthog_options) if sources.empty?

      "Object.assign(#{json(posthog_options)}, (#{REDACT})(#{json(sources)}))"
    end

    def json(value)
      JSON.generate(value).gsub("<", "\\u003c")
    end
  end
end
