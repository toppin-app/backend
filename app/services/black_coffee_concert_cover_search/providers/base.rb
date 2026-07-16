module BlackCoffeeConcertCoverSearch
  module Providers
    class Base
      def key
        self.class::KEY
      end

      def requests_count
        0
      end

      def search(_context)
        raise NotImplementedError, "#{self.class.name} debe implementar #search"
      end

      private

      def artist_from(context)
        context.fetch(:artist)
      end

      def identities_from(context)
        Array(context[:identities])
      end

      def provider_failure(response, requests_count:)
        ProviderResult.failure(
          status: response.status,
          error_type: response.error_type,
          error_message: response.error_message,
          evidence: {
            http_status: response.http_status,
            retry_after: response.retry_after
          }.compact,
          requests_count: requests_count
        )
      end
    end
  end
end
