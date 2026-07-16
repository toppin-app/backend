module BlackCoffeeConcertCoverSearch
  ProviderResult = Struct.new(
    :status,
    :identities,
    :candidates,
    :identifiers,
    :evidence,
    :error_type,
    :error_message,
    :requests_count,
    keyword_init: true
  ) do
    def self.ok(identities: [], candidates: [], identifiers: {}, evidence: {}, requests_count: 0)
      new(
        status: 'ok',
        identities: identities,
        candidates: candidates,
        identifiers: identifiers,
        evidence: evidence,
        requests_count: requests_count
      )
    end

    def self.failure(status:, error_type:, error_message:, evidence: {}, requests_count: 0)
      new(
        status: status.to_s,
        identities: [],
        candidates: [],
        identifiers: {},
        evidence: evidence,
        error_type: error_type,
        error_message: error_message,
        requests_count: requests_count
      )
    end
  end
end
