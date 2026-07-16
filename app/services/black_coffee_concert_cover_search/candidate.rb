module BlackCoffeeConcertCoverSearch
  Candidate = Struct.new(
    :image_url,
    :page_url,
    :provider,
    :width,
    :height,
    :identifiers,
    :evidence,
    keyword_init: true
  )
end
