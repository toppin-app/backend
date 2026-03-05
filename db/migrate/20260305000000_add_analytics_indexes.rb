# frozen_string_literal: true

# Migration to add performance indexes for Analytics Dashboard
# Run this migration to optimize analytics queries
#
# Usage: rails generate migration AddAnalyticsIndexes
# Then copy this content and run: rails db:migrate

class AddAnalyticsIndexes < ActiveRecord::Migration[6.0]
  def up
    # Users table indexes for analytics queries
    if table_exists?(:users)
      add_index :users, :created_at, name: 'idx_users_created_at' unless index_exists?(:users, :created_at, name: 'idx_users_created_at')
      add_index :users, :last_sign_in_at, name: 'idx_users_last_sign_in' unless index_exists?(:users, :last_sign_in_at, name: 'idx_users_last_sign_in')
      add_index :users, [:deleted_account, :fake_user], name: 'idx_users_deleted_fake' unless index_exists?(:users, [:deleted_account, :fake_user], name: 'idx_users_deleted_fake')
      add_index :users, :location_country, name: 'idx_users_country' unless index_exists?(:users, :location_country, name: 'idx_users_country')
      add_index :users, :location_city, name: 'idx_users_city' unless index_exists?(:users, :location_city, name: 'idx_users_city')
      add_index :users, :device_platform, name: 'idx_users_platform' unless index_exists?(:users, :device_platform, name: 'idx_users_platform')
      add_index :users, :current_subscription_name, name: 'idx_users_subscription' unless index_exists?(:users, :current_subscription_name, name: 'idx_users_subscription')
      add_index :users, :verified, name: 'idx_users_verified' unless index_exists?(:users, :verified, name: 'idx_users_verified')
      add_index :users, :gender, name: 'idx_users_gender' unless index_exists?(:users, :gender, name: 'idx_users_gender')
      
      # Composite indexes for common query patterns
      add_index :users, [:deleted_account, :fake_user, :created_at], name: 'idx_users_analytics_growth' unless index_exists?(:users, [:deleted_account, :fake_user, :created_at], name: 'idx_users_analytics_growth')
      add_index :users, [:deleted_account, :fake_user, :last_sign_in_at], name: 'idx_users_analytics_engagement' unless index_exists?(:users, [:deleted_account, :fake_user, :last_sign_in_at], name: 'idx_users_analytics_engagement')
      
      puts "✅ Users indexes created successfully"
    else
      puts "⚠️  Table 'users' not found, skipping users indexes"
    end
    
    # User match requests indexes
    if table_exists?(:user_match_requests)
      add_index :user_match_requests, :created_at, name: 'idx_match_requests_created' unless index_exists?(:user_match_requests, :created_at, name: 'idx_match_requests_created')
      add_index :user_match_requests, [:is_match, :match_date], name: 'idx_match_requests_match' unless index_exists?(:user_match_requests, [:is_match, :match_date], name: 'idx_match_requests_match')
      add_index :user_match_requests, :is_superlike, name: 'idx_match_requests_superlike' unless index_exists?(:user_match_requests, :is_superlike, name: 'idx_match_requests_superlike')
      
      puts "✅ User match requests indexes created successfully"
    else
    if table_exists?(:users)
      remove_index :users, name: 'idx_users_analytics_engagement' if index_exists?(:users, name: 'idx_users_analytics_engagement')
      remove_index :users, name: 'idx_users_analytics_growth' if index_exists?(:users, name: 'idx_users_analytics_growth')
      remove_index :users, name: 'idx_users_gender' if index_exists?(:users, name: 'idx_users_gender')
      remove_index :users, name: 'idx_users_verified' if index_exists?(:users, name: 'idx_users_verified')
      remove_index :users, name: 'idx_users_subscription' if index_exists?(:users, name: 'idx_users_subscription')
      remove_index :users, name: 'idx_users_platform' if index_exists?(:users, name: 'idx_users_platform')
      remove_index :users, name: 'idx_users_city' if index_exists?(:users, name: 'idx_users_city')
      remove_index :users, name: 'idx_users_country' if index_exists?(:users, name: 'idx_users_country')
      remove_index :users, name: 'idx_users_deleted_fake' if index_exists?(:users, name: 'idx_users_deleted_fake')
      remove_index :users, name: 'idx_users_last_sign_in' if index_exists?(:users, name: 'idx_users_last_sign_in')
      remove_index :users, name: 'idx_users_created_at' if index_exists?(:users, name: 'idx_users_created_at')
    end
    
    if table_exists?(:purchases)
      remove_index :purchases, name: 'idx_purchases_user' if index_exists?(:purchases, name: 'idx_purchases_user')
      remove_index :purchases, name: 'idx_purchases_created' if index_exists?(:purchases, name: 'idx_purchases_created')
    end
    
    if table_exists?(:user_match_requests)
      remove_index :user_match_requests, name: 'idx_match_requests_superlike' if index_exists?(:user_match_requests, name: 'idx_match_requests_superlike')
      remove_index :user_match_requests, name: 'idx_match_requests_match' if index_exists?(:user_match_requests, name: 'idx_match_requests_match')
      remove_index :user_match_requests, name: 'idx_match_requests_created' if index_exists?(:user_match_requests, name: 'idx_match_requests_created')
    endalytics_engagement')
    remove_index :users, name: 'idx_users_analytics_growth' if index_exists?(:users, name: 'idx_users_analytics_growth')
    
    remove_index :purchases, name: 'idx_purchases_user' if index_exists?(:purchases, name: 'idx_purchases_user')
    remove_index :purchases, name: 'idx_purchases_created' if index_exists?(:purchases, name: 'idx_purchases_created')
    
    remove_index :user_match_requests, name: 'idx_match_requests_superlike' if index_exists?(:user_match_requests, name: 'idx_match_requests_superlike')
    remove_index :user_match_requests, name: 'idx_match_requests_match' if index_exists?(:user_match_requests, name: 'idx_match_requests_match')
    remove_index :user_match_requests, name: 'idx_match_requests_created' if index_exists?(:user_match_requests, name: 'idx_match_requests_created')
    
    remove_index :users, name: 'idx_users_gender' if index_exists?(:users, name: 'idx_users_gender')
    remove_index :users, name: 'idx_users_verified' if index_exists?(:users, name: 'idx_users_verified')
    remove_index :users, name: 'idx_users_subscription' if index_exists?(:users, name: 'idx_users_subscription')
    remove_index :users, name: 'idx_users_platform' if index_exists?(:users, name: 'idx_users_platform')
    remove_index :users, name: 'idx_users_city' if index_exists?(:users, name: 'idx_users_city')
    remove_index :users, name: 'idx_users_country' if index_exists?(:users, name: 'idx_users_country')
    remove_index :users, name: 'idx_users_deleted_fake' if index_exists?(:users, name: 'idx_users_deleted_fake')
    remove_index :users, name: 'idx_users_last_sign_in' if index_exists?(:users, name: 'idx_users_last_sign_in')
    remove_index :users, name: 'idx_users_created_at' if index_exists?(:users, name: 'idx_users_created_at')
    
    puts "✅ Analytics indexes removed"
  end
end
