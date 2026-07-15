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

ActiveRecord::Schema.define(version: 2026_07_15_120000) do

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

  create_table "banner_users", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "banner_id", null: false
    t.bigint "user_id", null: false
    t.boolean "viewed", default: false, null: false
    t.datetime "viewed_at"
    t.datetime "opened_at"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.string "locality"
    t.string "country"
    t.string "lat"
    t.string "lng"
    t.index ["banner_id"], name: "index_banner_users_on_banner_id"
    t.index ["opened_at"], name: "index_banner_users_on_opened_at"
    t.index ["user_id", "banner_id"], name: "index_banner_users_on_user_id_and_banner_id"
    t.index ["user_id"], name: "index_banner_users_on_user_id"
    t.index ["viewed_at"], name: "index_banner_users_on_viewed_at"
  end

  create_table "banners", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "title", null: false
    t.text "description"
    t.string "image", null: false
    t.string "url"
    t.boolean "active", default: true
    t.datetime "start_date"
    t.datetime "end_date"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["active", "start_date", "end_date"], name: "index_banners_on_active_and_start_date_and_end_date"
    t.index ["active"], name: "index_banners_on_active"
  end

  create_table "black_coffee_bulk_import_steps", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "black_coffee_bulk_import_id", null: false
    t.bigint "black_coffee_import_run_id"
    t.string "category", null: false
    t.string "status", default: "pending", null: false
    t.integer "depth", default: 0, null: false
    t.decimal "south_latitude", precision: 10, scale: 7, null: false
    t.decimal "south_longitude", precision: 10, scale: 7, null: false
    t.decimal "north_latitude", precision: 10, scale: 7, null: false
    t.decimal "north_longitude", precision: 10, scale: 7, null: false
    t.integer "found_count", default: 0, null: false
    t.integer "saved_count", default: 0, null: false
    t.integer "duplicate_count", default: 0, null: false
    t.integer "request_count", default: 0, null: false
    t.boolean "saturated", default: false, null: false
    t.datetime "processed_at"
    t.text "error_message"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.integer "existing_skipped_count", default: 0, null: false
    t.integer "outside_region_skipped_count", default: 0, null: false
    t.integer "invalid_category_skipped_count", default: 0, null: false
    t.integer "photo_requests_count", default: 0, null: false
    t.integer "photo_references_saved_count", default: 0, null: false
    t.integer "photo_urls_resolved_count", default: 0, null: false
    t.integer "no_photo_skipped_count", default: 0, null: false
    t.index ["black_coffee_bulk_import_id", "category", "status"], name: "idx_bc_bulk_steps_import_category_status"
    t.index ["black_coffee_bulk_import_id"], name: "idx_bc_bulk_steps_import"
    t.index ["black_coffee_import_run_id"], name: "idx_bc_bulk_steps_run"
    t.index ["status"], name: "idx_bc_bulk_steps_status"
  end

  create_table "black_coffee_bulk_imports", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "black_coffee_import_region_id", null: false
    t.string "status", default: "pending", null: false
    t.string "geometry_strategy"
    t.json "categories_payload"
    t.json "bounds_payload"
    t.integer "max_depth", default: 8, null: false
    t.integer "min_cell_size_meters", default: 1500, null: false
    t.integer "step_limit", default: 60, null: false
    t.integer "total_steps", default: 0, null: false
    t.integer "pending_steps_count", default: 0, null: false
    t.integer "running_steps_count", default: 0, null: false
    t.integer "completed_steps_count", default: 0, null: false
    t.integer "split_steps_count", default: 0, null: false
    t.integer "failed_steps_count", default: 0, null: false
    t.integer "saturated_steps_count", default: 0, null: false
    t.integer "completed_categories_count", default: 0, null: false
    t.integer "requests_count", default: 0, null: false
    t.integer "found_count", default: 0, null: false
    t.integer "saved_candidates_count", default: 0, null: false
    t.integer "duplicate_candidates_count", default: 0, null: false
    t.integer "error_count", default: 0, null: false
    t.string "current_category"
    t.string "current_cell_label"
    t.datetime "started_at"
    t.datetime "last_advanced_at"
    t.datetime "finished_at"
    t.text "error_message"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.integer "existing_skipped_count", default: 0, null: false
    t.integer "outside_region_skipped_count", default: 0, null: false
    t.integer "invalid_category_skipped_count", default: 0, null: false
    t.integer "google_photo_requests_count", default: 0, null: false
    t.integer "photo_references_saved_count", default: 0, null: false
    t.integer "photo_urls_resolved_count", default: 0, null: false
    t.json "import_options"
    t.integer "no_photo_skipped_count", default: 0, null: false
    t.index ["black_coffee_import_region_id", "status"], name: "idx_bc_bulk_imports_region_status"
    t.index ["black_coffee_import_region_id"], name: "idx_bc_bulk_imports_region"
    t.index ["status"], name: "idx_bc_bulk_imports_status"
  end

  create_table "black_coffee_concert_cover_repair_batches", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci", force: :cascade do |t|
    t.string "status", default: "pending", null: false
    t.string "review_status_filter", default: "approved", null: false
    t.boolean "external_search_enabled", default: false, null: false
    t.integer "total_venues", default: 0, null: false
    t.integer "processed_venues", default: 0, null: false
    t.integer "source_recovered_count", default: 0, null: false
    t.integer "search_recovered_count", default: 0, null: false
    t.integer "rejected_count", default: 0, null: false
    t.integer "failed_count", default: 0, null: false
    t.integer "skipped_count", default: 0, null: false
    t.integer "source_requests_count", default: 0, null: false
    t.integer "search_requests_count", default: 0, null: false
    t.integer "image_requests_count", default: 0, null: false
    t.bigint "created_by_id"
    t.string "worker_token"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "last_worker_heartbeat_at"
    t.text "error_message"
    t.json "report_payload"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["created_at"], name: "idx_bc_concert_cover_batches_created"
    t.index ["created_by_id"], name: "idx_bc_concert_cover_batches_user"
    t.index ["status"], name: "idx_bc_concert_cover_batches_status"
  end

  create_table "black_coffee_concert_cover_repair_items", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "black_coffee_concert_cover_repair_batch_id", null: false
    t.string "venue_id"
    t.string "venue_name"
    t.string "status", default: "pending", null: false
    t.string "original_review_status"
    t.string "resolution_source"
    t.text "source_page_url"
    t.text "selected_image_url"
    t.text "result_page_url"
    t.decimal "confidence", precision: 5, scale: 2
    t.json "evidence"
    t.string "error_type"
    t.text "error_message"
    t.datetime "processed_at"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["black_coffee_concert_cover_repair_batch_id", "venue_id"], name: "idx_bc_concert_cover_items_batch_venue", unique: true
    t.index ["black_coffee_concert_cover_repair_batch_id"], name: "idx_bc_concert_cover_items_batch"
    t.index ["status"], name: "idx_bc_concert_cover_items_status"
    t.index ["venue_id"], name: "idx_bc_concert_cover_items_venue"
  end

  create_table "black_coffee_concert_import_items", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "black_coffee_concert_import_run_id", null: false
    t.string "venue_id"
    t.string "status", default: "pending", null: false
    t.string "source", default: "songkick", null: false
    t.text "source_url"
    t.string "source_path"
    t.string "source_event_id"
    t.string "fingerprint"
    t.string "name"
    t.string "venue_name"
    t.string "city"
    t.string "state"
    t.string "country"
    t.string "country_code"
    t.date "start_date"
    t.date "end_date"
    t.text "image_url"
    t.decimal "latitude", precision: 10, scale: 6
    t.decimal "longitude", precision: 10, scale: 6
    t.string "coordinates_source"
    t.string "coordinates_confidence"
    t.text "source_description"
    t.string "source_description_language"
    t.string "source_description_status"
    t.text "official_url"
    t.text "ticket_url"
    t.text "warning_message"
    t.text "error_message"
    t.json "raw_payload"
    t.json "normalized_payload"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.datetime "start_at"
    t.datetime "end_at"
    t.string "event_dedupe_key"
    t.string "image_resolution_source"
    t.decimal "image_resolution_confidence", precision: 5, scale: 2
    t.json "image_resolution_evidence"
    t.index ["black_coffee_concert_import_run_id"], name: "idx_bc_concert_items_run"
    t.index ["country_code"], name: "idx_bc_concert_items_country"
    t.index ["event_dedupe_key"], name: "idx_bc_concert_items_event_dedupe"
    t.index ["fingerprint"], name: "idx_bc_concert_items_fingerprint"
    t.index ["source_event_id"], name: "idx_bc_concert_items_source_event"
    t.index ["status"], name: "idx_bc_concert_items_status"
    t.index ["venue_id"], name: "idx_bc_concert_items_venue"
  end

  create_table "black_coffee_concert_import_runs", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci", force: :cascade do |t|
    t.string "source", default: "songkick", null: false
    t.string "status", default: "pending", null: false
    t.string "mode", default: "dry_run", null: false
    t.text "source_url"
    t.text "source_paths"
    t.integer "max_pages_per_source", default: 1, null: false
    t.integer "max_events", default: 500, null: false
    t.decimal "request_delay_seconds", precision: 6, scale: 2, default: "10.0", null: false
    t.string "strict_country_code", default: "ES", null: false
    t.boolean "include_festivals", default: false, null: false
    t.boolean "download_images", default: true, null: false
    t.boolean "only_future", default: true, null: false
    t.boolean "auto_publish", default: false, null: false
    t.boolean "preserve_manual_edits", default: true, null: false
    t.bigint "created_by_id"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.integer "robots_requests_count", default: 0, null: false
    t.integer "listing_requests_count", default: 0, null: false
    t.integer "detail_requests_count", default: 0, null: false
    t.integer "candidates_found_count", default: 0, null: false
    t.integer "outside_country_skipped_count", default: 0, null: false
    t.integer "festival_skipped_count", default: 0, null: false
    t.integer "duplicate_skipped_count", default: 0, null: false
    t.integer "invalid_skipped_count", default: 0, null: false
    t.integer "past_skipped_count", default: 0, null: false
    t.integer "images_downloaded_count", default: 0, null: false
    t.integer "items_created_count", default: 0, null: false
    t.integer "venues_created_count", default: 0, null: false
    t.integer "needs_review_count", default: 0, null: false
    t.integer "failed_count", default: 0, null: false
    t.json "summary_payload"
    t.text "error_message"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.string "import_origin", default: "dashboard", null: false
    t.integer "non_concert_skipped_count", default: 0, null: false
    t.integer "occurred_marked_count", default: 0, null: false
    t.integer "source_cover_recovered_count", default: 0, null: false
    t.integer "search_cover_recovered_count", default: 0, null: false
    t.integer "no_cover_skipped_count", default: 0, null: false
    t.integer "image_search_requests_count", default: 0, null: false
    t.integer "image_download_requests_count", default: 0, null: false
    t.index ["created_at"], name: "idx_bc_concert_runs_created_at"
    t.index ["created_by_id"], name: "idx_bc_concert_runs_created_by"
    t.index ["source"], name: "idx_bc_concert_runs_source"
    t.index ["status"], name: "idx_bc_concert_runs_status"
  end

  create_table "black_coffee_fake_favorite_batches", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci", force: :cascade do |t|
    t.string "status", default: "pending", null: false
    t.json "user_ids_payload"
    t.json "pending_user_ids_payload"
    t.json "failed_user_ids_payload"
    t.json "states_payload"
    t.json "categories_payload"
    t.json "combination_entries_payload"
    t.json "empty_combinations_payload"
    t.integer "total_users_count", default: 0, null: false
    t.integer "pending_users_count", default: 0, null: false
    t.integer "processed_users_count", default: 0, null: false
    t.integer "failed_users_count", default: 0, null: false
    t.integer "deleted_favorites_count", default: 0, null: false
    t.integer "created_favorites_count", default: 0, null: false
    t.integer "combinations_count", default: 0, null: false
    t.integer "combinations_without_venues_count", default: 0, null: false
    t.bigint "current_user_id"
    t.string "current_user_name"
    t.bigint "last_processed_user_id"
    t.string "last_processed_user_name"
    t.datetime "favorites_reset_at"
    t.datetime "started_at"
    t.datetime "last_advanced_at"
    t.datetime "finished_at"
    t.text "error_message"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["status"], name: "idx_bc_fake_favorite_batches_status"
  end

  create_table "black_coffee_festival_import_items", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "black_coffee_festival_import_run_id", null: false
    t.string "venue_id"
    t.string "status", default: "pending", null: false
    t.string "source", default: "fanmusicfest", null: false
    t.text "source_url"
    t.string "source_event_id"
    t.string "fingerprint"
    t.string "name"
    t.string "city"
    t.string "state"
    t.string "country"
    t.string "country_code"
    t.date "start_date"
    t.date "end_date"
    t.text "image_url"
    t.text "error_message"
    t.json "raw_payload"
    t.json "normalized_payload"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.decimal "latitude", precision: 10, scale: 6
    t.decimal "longitude", precision: 10, scale: 6
    t.string "coordinates_source"
    t.string "coordinates_confidence"
    t.text "source_description"
    t.string "source_description_language"
    t.string "source_description_status"
    t.text "official_url"
    t.text "ticket_url"
    t.string "festival_venue_name"
    t.text "warning_message"
    t.index ["black_coffee_festival_import_run_id"], name: "idx_bc_festival_items_run"
    t.index ["country_code"], name: "idx_bc_festival_items_country"
    t.index ["fingerprint"], name: "idx_bc_festival_items_fingerprint"
    t.index ["source_event_id"], name: "idx_bc_festival_items_source_event"
    t.index ["status"], name: "idx_bc_festival_items_status"
    t.index ["venue_id"], name: "idx_bc_festival_items_venue"
  end

  create_table "black_coffee_festival_import_runs", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci", force: :cascade do |t|
    t.string "source", default: "fanmusicfest", null: false
    t.string "status", default: "pending", null: false
    t.string "mode", default: "dry_run", null: false
    t.text "source_url"
    t.integer "max_pages", default: 1, null: false
    t.integer "max_details", default: 0, null: false
    t.decimal "request_delay_seconds", precision: 6, scale: 2, default: "10.0", null: false
    t.string "strict_country_code", default: "ES", null: false
    t.boolean "import_details", default: false, null: false
    t.boolean "auto_publish", default: false, null: false
    t.bigint "created_by_id"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.integer "robots_requests_count", default: 0, null: false
    t.integer "listing_requests_count", default: 0, null: false
    t.integer "detail_requests_count", default: 0, null: false
    t.integer "candidates_found_count", default: 0, null: false
    t.integer "outside_country_skipped_count", default: 0, null: false
    t.integer "duplicate_skipped_count", default: 0, null: false
    t.integer "invalid_skipped_count", default: 0, null: false
    t.integer "items_created_count", default: 0, null: false
    t.integer "venues_created_count", default: 0, null: false
    t.integer "venues_updated_count", default: 0, null: false
    t.integer "needs_review_count", default: 0, null: false
    t.integer "failed_count", default: 0, null: false
    t.json "summary_payload"
    t.text "error_message"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.string "operation", default: "import", null: false
    t.boolean "preserve_manual_edits", default: true, null: false
    t.boolean "download_images", default: true, null: false
    t.boolean "only_future", default: true, null: false
    t.integer "images_downloaded_count", default: 0, null: false
    t.integer "past_skipped_count", default: 0, null: false
    t.index ["created_at"], name: "idx_bc_festival_runs_created_at"
    t.index ["created_by_id"], name: "idx_bc_festival_runs_created_by"
    t.index ["operation"], name: "idx_bc_festival_runs_operation"
    t.index ["source"], name: "idx_bc_festival_runs_source"
    t.index ["status"], name: "idx_bc_festival_runs_status"
  end

  create_table "black_coffee_google_import_filters", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci", force: :cascade do |t|
    t.string "category", null: false
    t.json "excluded_primary_types"
    t.json "excluded_types"
    t.json "excluded_keywords"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["category"], name: "idx_bc_google_import_filters_category", unique: true
  end

  create_table "black_coffee_image_audit_batches", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci", force: :cascade do |t|
    t.string "status", default: "pending", null: false
    t.integer "total_venues", default: 0, null: false
    t.integer "processed_venues", default: 0, null: false
    t.integer "total_images", default: 0, null: false
    t.integer "checked_images", default: 0, null: false
    t.integer "failed_venues_count", default: 0, null: false
    t.integer "failed_images_count", default: 0, null: false
    t.integer "rejected_venues_count", default: 0, null: false
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "rejected_at"
    t.bigint "rejected_by_id"
    t.text "error_message"
    t.json "report_payload"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.string "review_status_filter", default: "pending", null: false
    t.string "processing_mode", default: "manual", null: false
    t.datetime "background_started_at"
    t.datetime "last_worker_heartbeat_at"
    t.integer "background_requested_limit"
    t.string "worker_token"
    t.index ["created_at"], name: "idx_bc_image_audit_batches_created_at"
    t.index ["processing_mode"], name: "idx_bc_image_audit_batches_mode"
    t.index ["rejected_by_id"], name: "idx_bc_image_audit_batches_rejected_by"
    t.index ["review_status_filter"], name: "idx_bc_image_audit_batches_review_filter"
    t.index ["status"], name: "idx_bc_image_audit_batches_status"
  end

  create_table "black_coffee_image_audit_items", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "black_coffee_image_audit_batch_id", null: false
    t.string "venue_id", null: false
    t.bigint "venue_image_id"
    t.string "venue_name"
    t.text "image_url"
    t.string "status", default: "pending", null: false
    t.string "error_type"
    t.integer "http_status"
    t.text "error_message"
    t.datetime "checked_at"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["black_coffee_image_audit_batch_id"], name: "idx_bc_image_audit_items_batch"
    t.index ["error_type"], name: "idx_bc_image_audit_items_error_type"
    t.index ["status"], name: "idx_bc_image_audit_items_status"
    t.index ["venue_id"], name: "idx_bc_image_audit_items_venue"
  end

  create_table "black_coffee_image_internalization_batches", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci", force: :cascade do |t|
    t.string "status", default: "pending", null: false
    t.integer "total_venues", default: 0, null: false
    t.integer "processed_venues", default: 0, null: false
    t.integer "total_images", default: 0, null: false
    t.integer "processed_images", default: 0, null: false
    t.integer "converted_images_count", default: 0, null: false
    t.integer "converted_venues_count", default: 0, null: false
    t.integer "failed_images_count", default: 0, null: false
    t.integer "failed_venues_count", default: 0, null: false
    t.integer "skipped_images_count", default: 0, null: false
    t.bigint "created_by_id"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.text "error_message"
    t.json "report_payload"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.string "processing_mode", default: "manual", null: false
    t.datetime "background_started_at"
    t.datetime "last_worker_heartbeat_at"
    t.integer "background_requested_limit"
    t.string "worker_token"
    t.index ["created_at"], name: "idx_bc_image_internalization_batches_created_at"
    t.index ["created_by_id"], name: "idx_bc_image_internalization_batches_created_by"
    t.index ["processing_mode"], name: "idx_bc_image_internalization_batches_mode"
    t.index ["status"], name: "idx_bc_image_internalization_batches_status"
  end

  create_table "black_coffee_image_internalization_items", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "black_coffee_image_internalization_batch_id", null: false
    t.string "venue_id", null: false
    t.bigint "venue_image_id"
    t.string "venue_name"
    t.text "source_url"
    t.string "status", default: "pending", null: false
    t.string "content_type"
    t.bigint "file_size"
    t.integer "http_status"
    t.string "error_type"
    t.text "error_message"
    t.datetime "processed_at"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["black_coffee_image_internalization_batch_id"], name: "idx_bc_image_internalization_items_batch"
    t.index ["error_type"], name: "idx_bc_image_internalization_items_error_type"
    t.index ["status"], name: "idx_bc_image_internalization_items_status"
    t.index ["venue_id"], name: "idx_bc_image_internalization_items_venue"
    t.index ["venue_image_id"], name: "idx_bc_image_internalization_items_image"
  end

  create_table "black_coffee_import_approval_batches", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "black_coffee_import_run_id", null: false
    t.string "status", default: "pending", null: false
    t.string "selection_mode", default: "selected_ids", null: false
    t.json "candidate_ids_payload"
    t.json "pending_candidate_ids_payload"
    t.json "failed_candidate_ids_payload"
    t.integer "total_candidates_count", default: 0, null: false
    t.integer "pending_candidates_count", default: 0, null: false
    t.integer "processed_candidates_count", default: 0, null: false
    t.integer "approved_candidates_count", default: 0, null: false
    t.integer "duplicate_candidates_count", default: 0, null: false
    t.integer "skipped_candidates_count", default: 0, null: false
    t.integer "failed_candidates_count", default: 0, null: false
    t.bigint "last_processed_candidate_id"
    t.bigint "current_candidate_id"
    t.string "current_candidate_name"
    t.datetime "started_at"
    t.datetime "last_advanced_at"
    t.datetime "finished_at"
    t.text "error_message"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["black_coffee_import_run_id", "status"], name: "idx_bc_import_approval_batches_run_status"
    t.index ["black_coffee_import_run_id"], name: "idx_bc_import_approval_batches_run"
    t.index ["status"], name: "idx_bc_import_approval_batches_status"
  end

  create_table "black_coffee_import_candidates", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "black_coffee_import_run_id", null: false
    t.bigint "black_coffee_import_region_id", null: false
    t.bigint "black_coffee_import_region_category_id"
    t.string "status", default: "pending", null: false
    t.string "google_place_id"
    t.string "name", null: false
    t.string "address"
    t.string "city"
    t.string "category", null: false
    t.string "subcategory"
    t.decimal "latitude", precision: 10, scale: 7
    t.decimal "longitude", precision: 10, scale: 7
    t.decimal "rating", precision: 3, scale: 2
    t.integer "user_ratings_total"
    t.text "website"
    t.string "phone"
    t.text "google_maps_uri"
    t.json "image_urls"
    t.json "google_photo_references"
    t.json "author_attributions"
    t.json "raw_payload"
    t.string "duplicate_venue_id"
    t.string "approved_venue_id"
    t.datetime "reviewed_at"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.string "postal_code"
    t.string "state"
    t.string "country"
    t.string "country_code"
    t.text "google_description"
    t.string "google_description_language_code"
    t.index ["approved_venue_id"], name: "idx_bc_candidates_approved_venue"
    t.index ["black_coffee_import_region_category_id"], name: "idx_bc_candidates_region_category"
    t.index ["black_coffee_import_region_id"], name: "idx_bc_candidates_region"
    t.index ["black_coffee_import_run_id", "status", "id"], name: "idx_bc_candidates_run_status_id"
    t.index ["black_coffee_import_run_id"], name: "idx_bc_candidates_run"
    t.index ["duplicate_venue_id"], name: "idx_bc_candidates_duplicate_venue"
    t.index ["google_place_id"], name: "idx_bc_candidates_google_place"
    t.index ["status"], name: "idx_bc_candidates_status"
  end

  create_table "black_coffee_import_photo_refresh_batches", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "black_coffee_import_run_id", null: false
    t.string "status", default: "pending", null: false
    t.json "candidate_ids_payload"
    t.json "pending_candidate_ids_payload"
    t.json "refreshed_candidate_ids_payload"
    t.json "skipped_candidate_ids_payload"
    t.json "failed_candidate_ids_payload"
    t.integer "total_candidates_count", default: 0, null: false
    t.integer "pending_candidates_count", default: 0, null: false
    t.integer "processed_candidates_count", default: 0, null: false
    t.integer "refreshed_candidates_count", default: 0, null: false
    t.integer "skipped_candidates_count", default: 0, null: false
    t.integer "failed_candidates_count", default: 0, null: false
    t.integer "requests_count", default: 0, null: false
    t.bigint "current_candidate_id"
    t.string "current_candidate_name"
    t.datetime "started_at"
    t.datetime "last_advanced_at"
    t.datetime "finished_at"
    t.text "error_message"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["black_coffee_import_run_id"], name: "idx_bc_photo_refresh_batches_run"
    t.index ["status"], name: "idx_bc_photo_refresh_batches_status"
  end

  create_table "black_coffee_import_region_categories", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "black_coffee_import_region_id", null: false
    t.string "category", null: false
    t.string "status", default: "pending", null: false
    t.integer "total_candidates", default: 0, null: false
    t.integer "pending_count", default: 0, null: false
    t.integer "approved_count", default: 0, null: false
    t.integer "rejected_count", default: 0, null: false
    t.integer "duplicate_count", default: 0, null: false
    t.datetime "last_imported_at"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.integer "google_total_count"
    t.datetime "google_total_counted_at"
    t.text "google_total_count_error"
    t.text "google_total_count_error_details"
    t.index ["black_coffee_import_region_id", "category"], name: "idx_bc_region_categories_unique", unique: true
    t.index ["black_coffee_import_region_id"], name: "idx_bc_region_categories_region"
  end

  create_table "black_coffee_import_regions", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.string "country_code", default: "ES", null: false
    t.string "status", default: "pending", null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.string "google_region_place_id"
    t.datetime "google_region_place_id_resolved_at"
    t.string "google_count_location_strategy", default: "region", null: false
    t.text "google_count_location_note"
    t.index ["google_region_place_id"], name: "idx_bc_regions_google_place"
    t.index ["slug"], name: "idx_bc_import_regions_slug", unique: true
  end

  create_table "black_coffee_import_runs", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "black_coffee_import_region_id", null: false
    t.bigint "black_coffee_import_region_category_id"
    t.string "category", null: false
    t.string "query"
    t.json "google_types"
    t.integer "limit", default: 10, null: false
    t.string "status", default: "pending", null: false
    t.integer "found_count", default: 0, null: false
    t.integer "candidate_count", default: 0, null: false
    t.integer "duplicate_count", default: 0, null: false
    t.integer "approved_count", default: 0, null: false
    t.integer "rejected_count", default: 0, null: false
    t.text "error_message"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.bigint "black_coffee_bulk_import_id"
    t.integer "raw_candidates_count", default: 0, null: false
    t.integer "existing_skipped_count", default: 0, null: false
    t.integer "outside_region_skipped_count", default: 0, null: false
    t.integer "invalid_category_skipped_count", default: 0, null: false
    t.integer "google_search_requests_count", default: 0, null: false
    t.integer "google_details_requests_count", default: 0, null: false
    t.integer "google_photo_requests_count", default: 0, null: false
    t.integer "photo_references_saved_count", default: 0, null: false
    t.integer "photo_urls_resolved_count", default: 0, null: false
    t.json "import_options"
    t.integer "no_photo_skipped_count", default: 0, null: false
    t.index ["black_coffee_bulk_import_id"], name: "idx_bc_import_runs_bulk_import"
    t.index ["black_coffee_import_region_category_id"], name: "idx_bc_import_runs_region_category"
    t.index ["black_coffee_import_region_id"], name: "idx_bc_import_runs_region"
    t.index ["category"], name: "idx_bc_import_runs_category"
    t.index ["status"], name: "idx_bc_import_runs_status"
  end

  create_table "black_coffee_review_batch_items", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "black_coffee_review_batch_id", null: false
    t.string "venue_id", null: false
    t.string "review_status", default: "pending", null: false
    t.string "review_rejection_reason"
    t.text "review_rejection_note"
    t.datetime "reviewed_at"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.string "category_correction_from"
    t.string "category_correction_to"
    t.bigint "venue_subcategory_correction_from_id"
    t.index ["black_coffee_review_batch_id", "venue_id"], name: "idx_bc_review_items_batch_venue", unique: true
    t.index ["black_coffee_review_batch_id"], name: "idx_bc_review_items_batch"
    t.index ["review_rejection_reason"], name: "idx_bc_review_items_reason"
    t.index ["review_status"], name: "idx_bc_review_items_status"
    t.index ["venue_id"], name: "idx_bc_review_items_venue"
  end

  create_table "black_coffee_review_batches", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci", force: :cascade do |t|
    t.string "status", default: "open", null: false
    t.json "filters_payload"
    t.integer "batch_size", default: 100, null: false
    t.integer "total_places", default: 0, null: false
    t.integer "approved_count", default: 0, null: false
    t.integer "rejected_count", default: 0, null: false
    t.datetime "reviewed_at"
    t.bigint "reviewed_by_id"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["reviewed_at"], name: "idx_bc_review_batches_reviewed_at"
    t.index ["reviewed_by_id"], name: "idx_bc_review_batches_reviewer"
    t.index ["status"], name: "idx_bc_review_batches_status"
  end

  create_table "black_coffee_venue_google_sync_batches", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci", force: :cascade do |t|
    t.string "status", default: "pending", null: false
    t.string "selection_mode", default: "selected_ids", null: false
    t.json "venue_ids_payload"
    t.json "pending_venue_ids_payload"
    t.json "failed_venue_ids_payload"
    t.integer "total_venues_count", default: 0, null: false
    t.integer "pending_venues_count", default: 0, null: false
    t.integer "processed_venues_count", default: 0, null: false
    t.integer "synced_venues_count", default: 0, null: false
    t.integer "skipped_venues_count", default: 0, null: false
    t.integer "failed_venues_count", default: 0, null: false
    t.integer "requests_count", default: 0, null: false
    t.string "current_venue_id"
    t.string "current_venue_name"
    t.string "last_processed_venue_id"
    t.datetime "started_at"
    t.datetime "last_advanced_at"
    t.datetime "finished_at"
    t.text "error_message"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["created_at"], name: "idx_bc_venue_google_sync_batches_created_at"
    t.index ["selection_mode"], name: "idx_bc_venue_google_sync_batches_mode"
    t.index ["status"], name: "idx_bc_venue_google_sync_batches_status"
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
    t.index ["created_at"], name: "idx_purchases_created"
    t.index ["user_id"], name: "idx_purchases_user"
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

  create_table "user_favorites", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "venue_id", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["user_id", "venue_id"], name: "index_user_favorites_on_user_id_and_venue_id", unique: true
    t.index ["user_id"], name: "index_user_favorites_on_user_id"
    t.index ["venue_id"], name: "index_user_favorites_on_venue_id"
  end

  create_table "user_filter_preferences", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.integer "gender_preferences"
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
    t.index ["created_at"], name: "idx_match_requests_created"
    t.index ["is_match", "match_date"], name: "idx_match_requests_match"
    t.index ["is_superlike"], name: "idx_match_requests_superlike"
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
    t.boolean "deleted_account", default: false, null: false
    t.boolean "fake_user", default: false, null: false
    t.index ["created_at"], name: "idx_users_created_at"
    t.index ["current_subscription_name"], name: "idx_users_subscription"
    t.index ["deleted_account", "fake_user", "created_at"], name: "idx_users_analytics_growth"
    t.index ["deleted_account", "fake_user", "last_sign_in_at"], name: "idx_users_analytics_engagement"
    t.index ["deleted_account", "fake_user"], name: "idx_users_deleted_fake"
    t.index ["device_platform"], name: "idx_users_platform"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["gender"], name: "idx_users_gender"
    t.index ["jti"], name: "index_users_on_jti", unique: true
    t.index ["last_sign_in_at"], name: "idx_users_last_sign_in"
    t.index ["location_city"], name: "idx_users_city"
    t.index ["location_country"], name: "idx_users_country"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["verified"], name: "idx_users_verified"
  end

  create_table "venue_images", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci", force: :cascade do |t|
    t.string "venue_id", null: false
    t.string "url"
    t.integer "position", default: 0, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.string "image"
    t.string "source"
    t.json "author_attributions"
    t.index ["venue_id", "position"], name: "index_venue_images_on_venue_id_and_position", unique: true
    t.index ["venue_id"], name: "index_venue_images_on_venue_id"
  end

  create_table "venue_schedules", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci", force: :cascade do |t|
    t.string "venue_id", null: false
    t.string "day", limit: 1, null: false
    t.boolean "closed", default: false, null: false
    t.time "slot_open"
    t.time "slot_close"
    t.integer "slot_index", default: 0, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["venue_id", "day", "slot_index"], name: "index_venue_schedules_on_venue_id_and_day_and_slot_index", unique: true
    t.index ["venue_id"], name: "index_venue_schedules_on_venue_id"
  end

  create_table "venue_subcategories", id: :string, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci", force: :cascade do |t|
    t.string "name", null: false
    t.string "category", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["category", "name"], name: "index_venue_subcategories_on_category_and_name", unique: true
  end

  create_table "venues", id: :string, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci", force: :cascade do |t|
    t.string "name", null: false
    t.string "category", null: false
    t.string "venue_subcategory_id"
    t.text "description"
    t.string "address", null: false
    t.string "city", null: false
    t.decimal "latitude", precision: 10, scale: 7, null: false
    t.decimal "longitude", precision: 10, scale: 7, null: false
    t.boolean "featured", default: false, null: false
    t.json "tags"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.string "google_place_id"
    t.boolean "internal_test", default: false, null: false
    t.boolean "payment_current", default: true, null: false
    t.boolean "visible", default: true, null: false
    t.string "postal_code"
    t.string "state"
    t.string "country"
    t.string "country_code"
    t.string "google_primary_type"
    t.json "google_secondary_types"
    t.string "review_status", default: "pending", null: false
    t.string "review_rejection_reason"
    t.text "review_rejection_note"
    t.datetime "reviewed_at"
    t.bigint "reviewed_by_id"
    t.string "external_source"
    t.text "external_source_url"
    t.string "external_source_id"
    t.string "source_fingerprint"
    t.date "festival_start_date"
    t.date "festival_end_date"
    t.json "festival_metadata"
    t.string "coordinates_source"
    t.string "coordinates_confidence"
    t.text "source_description"
    t.string "source_description_language"
    t.string "source_description_status"
    t.text "official_url"
    t.text "ticket_url"
    t.string "festival_venue_name"
    t.text "festival_raw_location_text"
    t.datetime "event_start_at"
    t.datetime "event_end_at"
    t.string "event_status", default: "upcoming", null: false
    t.string "event_import_origin"
    t.string "event_dedupe_key"
    t.index ["category", "event_dedupe_key"], name: "idx_venues_category_event_dedupe_unique", unique: true
    t.index ["category", "event_status", "event_start_at"], name: "idx_venues_category_event_status_start"
    t.index ["category"], name: "index_venues_on_category"
    t.index ["country_code"], name: "idx_venues_country_code"
    t.index ["event_import_origin"], name: "idx_venues_event_import_origin"
    t.index ["external_source", "external_source_id"], name: "idx_venues_external_source_id"
    t.index ["featured"], name: "index_venues_on_featured"
    t.index ["festival_start_date", "festival_end_date"], name: "idx_venues_festival_dates"
    t.index ["google_place_id"], name: "idx_venues_google_place_id", unique: true
    t.index ["google_primary_type"], name: "idx_venues_google_primary_type"
    t.index ["latitude", "longitude"], name: "index_venues_on_latitude_and_longitude"
    t.index ["review_rejection_reason"], name: "idx_venues_review_reason"
    t.index ["review_status"], name: "idx_venues_review_status"
    t.index ["reviewed_at"], name: "idx_venues_reviewed_at"
    t.index ["reviewed_by_id"], name: "idx_venues_reviewed_by"
    t.index ["source_description_status"], name: "idx_venues_source_description_status"
    t.index ["source_fingerprint"], name: "idx_venues_source_fingerprint"
    t.index ["venue_subcategory_id"], name: "index_venues_on_venue_subcategory_id"
    t.index ["visible"], name: "idx_venues_visible"
  end

  add_foreign_key "banner_users", "banners"
  add_foreign_key "banner_users", "users"
  add_foreign_key "black_coffee_bulk_import_steps", "black_coffee_bulk_imports"
  add_foreign_key "black_coffee_bulk_import_steps", "black_coffee_import_runs"
  add_foreign_key "black_coffee_bulk_imports", "black_coffee_import_regions"
  add_foreign_key "black_coffee_concert_cover_repair_batches", "users", column: "created_by_id", name: "fk_bc_concert_cover_batches_user", on_delete: :nullify
  add_foreign_key "black_coffee_concert_cover_repair_items", "black_coffee_concert_cover_repair_batches"
  add_foreign_key "black_coffee_concert_cover_repair_items", "venues", name: "fk_bc_concert_cover_items_venue", on_delete: :nullify
  add_foreign_key "black_coffee_concert_import_items", "black_coffee_concert_import_runs"
  add_foreign_key "black_coffee_concert_import_items", "venues", name: "fk_bc_concert_items_venue", on_delete: :nullify
  add_foreign_key "black_coffee_concert_import_runs", "users", column: "created_by_id", name: "fk_bc_concert_runs_created_by", on_delete: :nullify
  add_foreign_key "black_coffee_festival_import_items", "black_coffee_festival_import_runs"
  add_foreign_key "black_coffee_festival_import_items", "venues", name: "fk_bc_festival_items_venue", on_delete: :nullify
  add_foreign_key "black_coffee_festival_import_runs", "users", column: "created_by_id", name: "fk_bc_festival_runs_created_by", on_delete: :nullify
  add_foreign_key "black_coffee_image_audit_batches", "users", column: "rejected_by_id", name: "fk_bc_image_audit_batches_rejected_by", on_delete: :nullify
  add_foreign_key "black_coffee_image_audit_items", "black_coffee_image_audit_batches", name: "fk_bc_image_audit_items_batch", on_delete: :cascade
  add_foreign_key "black_coffee_image_audit_items", "venues", name: "fk_bc_image_audit_items_venue", on_delete: :cascade
  add_foreign_key "black_coffee_image_internalization_batches", "users", column: "created_by_id", name: "fk_bc_image_internalization_batches_created_by", on_delete: :nullify
  add_foreign_key "black_coffee_image_internalization_items", "black_coffee_image_internalization_batches", name: "fk_bc_image_internalization_items_batch", on_delete: :cascade
  add_foreign_key "black_coffee_image_internalization_items", "venue_images", name: "fk_bc_image_internalization_items_image", on_delete: :nullify
  add_foreign_key "black_coffee_image_internalization_items", "venues", name: "fk_bc_image_internalization_items_venue", on_delete: :cascade
  add_foreign_key "black_coffee_import_approval_batches", "black_coffee_import_runs"
  add_foreign_key "black_coffee_import_candidates", "black_coffee_import_region_categories"
  add_foreign_key "black_coffee_import_candidates", "black_coffee_import_regions"
  add_foreign_key "black_coffee_import_candidates", "black_coffee_import_runs"
  add_foreign_key "black_coffee_import_photo_refresh_batches", "black_coffee_import_runs"
  add_foreign_key "black_coffee_import_region_categories", "black_coffee_import_regions"
  add_foreign_key "black_coffee_import_runs", "black_coffee_bulk_imports"
  add_foreign_key "black_coffee_import_runs", "black_coffee_import_region_categories"
  add_foreign_key "black_coffee_import_runs", "black_coffee_import_regions"
  add_foreign_key "black_coffee_review_batch_items", "black_coffee_review_batches", name: "fk_bc_review_items_batch", on_delete: :cascade
  add_foreign_key "black_coffee_review_batch_items", "venues", name: "fk_bc_review_items_venue", on_delete: :cascade
  add_foreign_key "black_coffee_review_batches", "users", column: "reviewed_by_id", name: "fk_bc_review_batches_reviewer", on_delete: :nullify
  add_foreign_key "complaints", "users"
  add_foreign_key "devices", "users"
  add_foreign_key "info_item_values", "info_item_categories"
  add_foreign_key "interests", "interest_categories"
  add_foreign_key "purchases", "users"
  add_foreign_key "spotify_user_data", "users", name: "fk_spotify_user_data_user_id"
  add_foreign_key "user_favorites", "users"
  add_foreign_key "user_favorites", "venues"
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
  add_foreign_key "venue_images", "venues"
  add_foreign_key "venue_schedules", "venues"
  add_foreign_key "venues", "users", column: "reviewed_by_id", name: "fk_venues_reviewed_by", on_delete: :nullify
  add_foreign_key "venues", "venue_subcategories", on_delete: :nullify
end
