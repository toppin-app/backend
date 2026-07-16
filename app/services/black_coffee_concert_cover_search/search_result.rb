module BlackCoffeeConcertCoverSearch
  SearchResult = Struct.new(
    :status,
    :candidate,
    :confidence,
    :identifiers,
    :provider_attempts,
    :evidence,
    :error_type,
    :error_message,
    keyword_init: true
  ) do
    def found?
      status == 'found' && candidate.present?
    end

    def ambiguous?
      status == 'ambiguous'
    end

    def retryable?
      status == 'retryable_error'
    end
  end
end
