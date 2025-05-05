json.extract! user_filter_reference, :id, :user_id, :gender, :distance_range, :age_from, :age_till, :created_at, :updated_at
json.url user_filter_reference_url(user_filter_reference, format: :json)
