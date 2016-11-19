module Middleman
  module Sitemap
    class Resource
      def redirect?
        false
      end
    end

    module Extensions
      class RedirectResource
        def target_url
          @target_url ||= ::Middleman::Util.url_for(@store.app, @request_path, relative: false, find_resource: true)
        end

        def redirect?
          true
        end
      end
    end
  end
end
