module JtTelemetry
  module Helper
    # Call once in the layout's <head>, before javascript_importmap_tags.
    def jt_telemetry_tags
      nonce = content_security_policy_nonce if respond_to?(:content_security_policy_nonce)
      JtTelemetry.tags(nonce:).html_safe
    end
  end
end
