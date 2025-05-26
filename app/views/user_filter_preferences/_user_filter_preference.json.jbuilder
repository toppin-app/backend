json.extract! user_filter_preference, :id, :user_id, :distance_range, :age_from, :age_till, :only_verified_users, :interests, :categories
json.gender_preferences user_filter_preference.gender_preferences_array
