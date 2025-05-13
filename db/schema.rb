# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `rails
# db:schema:load`. When creating a new database, `rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 2024_06_25_093800) do

  create_table "app_versions", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "android_last_version"
    t.string "android_last_version_required"
    t.string "ios_last_version"
    t.string "ios_last_version_required"
    t.string "android_store_link"
    t.string "ios_store_link"
  end

  create_table "apple_tokens", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "token"
    t.string "email"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
  end

  create_table "complaints", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.integer "to_user_id"
    t.string "reason"
    t.text "text"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["user_id"], name: "index_complaints_on_user_id"
  end

  create_table "devices", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "token"
    t.string "so"
    t.string "device_uid"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["user_id"], name: "index_devices_on_user_id"
  end

  create_table "info_item_categories", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.string "description"
  end

  create_table "info_item_values", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "value"
    t.bigint "info_item_category_id", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["info_item_category_id"], name: "index_info_item_values_on_info_item_category_id"
  end

  create_table "interest_categories", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
  end

  create_table "interests", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "interest_category_id", null: false
    t.string "name"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["interest_category_id"], name: "index_interests_on_interest_category_id"
  end

  create_table "personal_questions", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
  end

  create_table "publis", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "title"
    t.datetime "start_date"
    t.datetime "end_date"
    t.string "weekdays"
    t.time "start_time"
    t.time "end_time"
    t.string "image"
    t.string "video"
    t.string "link"
    t.boolean "cancellable", default: true
    t.integer "repeat_swipes", default: 30
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
  end

  create_table "purchases", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "product_id"
    t.text "receipt"
    t.boolean "validated", default: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["user_id"], name: "index_purchases_on_user_id"
  end

  create_table "rpush_apps", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name", null: false
    t.string "environment"
    t.text "certificate"
    t.string "password"
    t.integer "connections", default: 1, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.string "type", null: false
    t.string "auth_key"
    t.string "client_id"
    t.string "client_secret"
    t.string "access_token"
    t.datetime "access_token_expiration"
    t.text "apn_key"
    t.string "apn_key_id"
    t.string "team_id"
    t.string "bundle_id"
    t.boolean "feedback_enabled", default: true
  end

  create_table "rpush_feedback", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "device_token"
    t.timestamp "failed_at", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.integer "app_id"
    t.index ["device_token"], name: "index_rpush_feedback_on_device_token"
  end

  create_table "rpush_notifications", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.integer "badge"
    t.string "device_token"
    t.string "sound"
    t.text "alert"
    t.text "data"
    t.integer "expiry", default: 86400
    t.boolean "delivered", default: false, null: false
    t.timestamp "delivered_at"
    t.boolean "failed", default: false, null: false
    t.timestamp "failed_at"
    t.integer "error_code"
    t.text "error_description"
    t.timestamp "deliver_after"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.boolean "alert_is_json", default: false, null: false
    t.string "type", null: false
    t.string "collapse_key"
    t.boolean "delay_while_idle", default: false, null: false
    t.text "registration_ids", size: :medium
    t.integer "app_id", null: false
    t.integer "retries", default: 0
    t.string "uri"
    t.timestamp "fail_after"
    t.boolean "processing", default: false, null: false
    t.integer "priority"
    t.text "url_args"
    t.string "category"
    t.boolean "content_available", default: false, null: false
    t.text "notification"
    t.boolean "mutable_content", default: false, null: false
    t.string "external_device_id"
    t.string "thread_id"
    t.boolean "dry_run", default: false, null: false
    t.boolean "sound_is_json", default: false
    t.index ["delivered", "failed", "processing", "deliver_after", "created_at"], name: "index_rpush_notifications_multi"
  end

  create_table "spotify_user_data", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "artist_name"
    t.string "image"
    t.string "preview_url"
    t.string "track_name"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["user_id"], name: "index_spotify_user_data_on_user_id"
  end

  create_table "user_filter_preferences", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.integer "gender"
    t.integer "distance_range"
    t.integer "age_from"
    t.integer "age_till"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.boolean "only_verified_users"
    t.string "interests"
    t.string "categories"
    t.index ["user_id"], name: "index_user_filter_preferences_on_user_id"
  end

  create_table "user_filter_references", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.integer "gender"
    t.integer "distance_range"
    t.integer "age_from"
    t.integer "age_till"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["user_id"], name: "index_user_filter_references_on_user_id"
  end

  create_table "user_info_item_values", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "info_item_value_id", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.string "category_name"
    t.string "item_name"
    t.index ["info_item_value_id"], name: "index_user_info_item_values_on_info_item_value_id"
    t.index ["user_id"], name: "index_user_info_item_values_on_user_id"
  end

  create_table "user_interests", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "interest_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.string "interest_name"
    t.index ["interest_id"], name: "index_user_interests_on_interest_id"
    t.index ["user_id"], name: "index_user_interests_on_user_id"
  end

  create_table "user_main_interests", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "interest_id"
    t.integer "percentage"
    t.string "name"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
  end

  create_table "user_match_requests", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.integer "target_user"
    t.boolean "is_match", default: false
    t.boolean "is_paid", default: false
    t.boolean "is_rejected", default: false
    t.integer "affinity_index"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.boolean "is_like"
    t.boolean "is_superlike"
    t.integer "user_ranking"
    t.integer "target_user_ranking"
    t.string "twilio_conversation_sid"
    t.datetime "match_date"
    t.boolean "target_is_like", default: false
    t.boolean "is_sugar_sweet", default: false
    t.index ["user_id"], name: "index_user_match_requests_on_user_id"
  end

  create_table "user_media", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "file"
    t.integer "position"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["user_id"], name: "index_user_media_on_user_id"
  end

  create_table "user_personal_questions", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "personal_question_id", null: false
    t.text "answer"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["personal_question_id"], name: "index_user_personal_questions_on_personal_question_id"
    t.index ["user_id"], name: "index_user_personal_questions_on_user_id"
  end

  create_table "user_vip_unlocks", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.integer "target_id"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["user_id"], name: "index_user_vip_unlocks_on_user_id"
  end

  create_table "users", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.string "jti"
    t.string "name"
    t.string "lastname"
    t.string "role"
    t.string "department"
    t.string "position"
    t.string "signature"
    t.string "image"
    t.string "user_name"
    t.boolean "blocked", default: false
    t.boolean "phone_validated", default: false
    t.boolean "verified", default: false
    t.string "verification_file"
    t.string "push_token"
    t.string "device_id"
    t.integer "device_platform"
    t.text "description"
    t.integer "gender"
    t.boolean "high_visibility", default: false
    t.datetime "high_visibility_expire"
    t.boolean "hidden_by_user", default: false
    t.boolean "is_connected", default: true
    t.datetime "last_connection"
    t.datetime "last_match"
    t.boolean "is_new", default: true
    t.integer "activity_level"
    t.date "birthday"
    t.string "born_in"
    t.string "living_in"
    t.string "locality"
    t.string "country"
    t.string "lat"
    t.string "lng"
    t.string "occupation"
    t.string "studies"
    t.integer "popularity"
    t.integer "ranking", default: 50
    t.boolean "user_gen", default: false
    t.integer "matches_number", default: 0
    t.integer "incoming_match_request_number", default: 0
    t.string "twilio_sid"
    t.boolean "admin", default: false
    t.integer "boost_available", default: 0
    t.integer "superlike_available", default: 1
    t.string "current_subscription_name"
    t.datetime "current_subscription_expires"
    t.datetime "last_superlike_given"
    t.integer "likes_left", default: 50
    t.datetime "last_like_given"
    t.integer "sign_in_count", default: 0
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.string "verification_image"
    t.boolean "bundled", default: false
    t.string "social"
    t.integer "profile_completed", default: 10
    t.text "social_login_token"
    t.integer "next_sugar_play", default: 30
    t.integer "spin_roulette_available", default: 1
    t.datetime "last_roulette_played"
    t.string "current_subscription_id"
    t.string "spoty1"
    t.string "spoty2"
    t.string "spoty3"
    t.string "spoty4"
    t.boolean "push_general", default: true
    t.boolean "push_match", default: true
    t.boolean "push_chat", default: true
    t.boolean "push_likes", default: true
    t.boolean "push_sound", default: true
    t.boolean "push_vibration", default: true
    t.string "apple_token"
    t.string "spoty_title1"
    t.string "spoty_title2"
    t.string "spoty_title3"
    t.string "spoty_title4"
    t.string "location_city"
    t.string "location_country"
    t.string "spoty5"
    t.string "spoty_title5"
    t.string "spoty6"
    t.string "spoty_title6"
    t.boolean "show_publi", default: true
    t.string "current_conversation"
    t.string "instagram"
    t.integer "incoming_likes_number", default: 0
    t.float "ratio_likes", default: 0.0
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["jti"], name: "index_users_on_jti", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "complaints", "users"
  add_foreign_key "devices", "users"
  add_foreign_key "info_item_values", "info_item_categories"
  add_foreign_key "interests", "interest_categories"
  add_foreign_key "purchases", "users"
  add_foreign_key "spotify_user_data", "users", name: "fk_spotify_user_data_user_id"
  add_foreign_key "user_filter_preferences", "users"
  add_foreign_key "user_filter_references", "users"
  add_foreign_key "user_info_item_values", "info_item_values"
  add_foreign_key "user_info_item_values", "users"
  add_foreign_key "user_interests", "interests"
  add_foreign_key "user_interests", "users"
  add_foreign_key "user_match_requests", "users"
  add_foreign_key "user_media", "users"
  add_foreign_key "user_personal_questions", "personal_questions"
  add_foreign_key "user_personal_questions", "users"
  add_foreign_key "user_vip_unlocks", "users"
end
