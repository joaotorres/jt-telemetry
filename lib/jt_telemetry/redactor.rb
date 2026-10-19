module JtTelemetry
  # Sentry's before_send and before_send_transaction. send_default_pii = false
  # still sends the request URL and the path in span data, so a secret in a
  # path, such as the token in /phone/:token, reaches Sentry. Each declared
  # path's :segments are replaced by their names wherever a URL can appear.
  # The same patterns go to the PostHog snippet (Tags).
  class Redactor
    SEGMENT = /(:\w+)/
    # A segment ends at the next slash, query, fragment, whitespace or quote.
    VALUE = %([^/?#\\s"']+).freeze

    def initialize(paths)
      @patterns = paths.map { |path| [pattern(path), path] }
    end

    def call(event, _hint = nil)
      return event if @patterns.empty?

      event.transaction = redact(event.transaction)
      event.message = redact(event.message)
      event.contexts = redact(event.contexts)
      event.tags = redact(event.tags)
      event.extra = redact(event.extra)
      redact_request(event.request)
      event.breadcrumbs&.each do |crumb|
        crumb.message = redact(crumb.message)
        crumb.data = redact(crumb.data)
      end
      event.exception&.values&.each { |exception| exception.value = redact(exception.value) } if event.respond_to?(:exception)
      event.spans = redact(event.spans) if event.respond_to?(:spans=)
      event
    end

    # [pattern source, replacement] pairs for the PostHog snippet. The sources
    # use only escapes that mean the same in a JavaScript RegExp.
    def sources
      @patterns.map { |pattern, path| [pattern.source, path] }
    end

    def redact(value)
      case value
      when String then @patterns.reduce(value) { |string, (pattern, path)| string.gsub(pattern) { path } }
      when Hash then value.transform_values { redact(_1) }
      when Array then value.map { redact(_1) }
      else value
      end
    end

    private

    def pattern(path)
      Regexp.new(path.split(SEGMENT).map { |part| part.match?(SEGMENT) ? VALUE : Regexp.escape(part) }.join)
    end

    def redact_request(request)
      return unless request

      %i[url query_string headers env data].each do |field|
        request.public_send(:"#{field}=", redact(request.public_send(field)))
      end
    end
  end
end
