# frozen_string_literal: true

# Test Helper for Source License System
# Sets up test environment, database, and common utilities

ENV['APP_ENV'] = 'test'
ENV['RACK_ENV'] = 'test'

# Set test environment variables BEFORE loading the application
# This prevents the .env file from overriding our test settings
ENV['APP_SECRET'] =
  'test_secret_key_for_testing_only_this_is_a_very_long_secret_key_that_meets_minimum_requirements_64_chars'
ENV['DATABASE_ADAPTER'] = 'sqlite'
ENV['ADMIN_EMAIL'] = 'admin@test.com'
ENV['ADMIN_PASSWORD'] = 'test_password'
ENV['STRIPE_SECRET_KEY'] = 'sk_test_fake_key_for_testing'
ENV['STRIPE_PUBLISHABLE_KEY'] = 'pk_test_fake_key_for_testing'

require 'simplecov'
require 'simplecov-console'

# Configure SimpleCov for coverage reporting
SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter.new([
  SimpleCov::Formatter::HTMLFormatter,
  SimpleCov::Formatter::Console,
])

SimpleCov.start do
  add_filter '/test/'
  add_filter '/vendor/'
  add_group 'Models', 'lib/models'
  add_group 'Helpers', 'lib/helpers'
  add_group 'Controllers', 'app.rb'
  add_group 'Libraries', 'lib'

  minimum_coverage 80
  minimum_coverage_by_file 70
end

require 'minitest/autorun'
require 'minitest/reporters'
require 'rack/test'
require 'sequel'
require 'database_cleaner/sequel'
require 'factory_bot'
require 'faker'
require 'webmock/minitest'
require 'vcr'

# Configure Minitest reporters
Minitest::Reporters.use! [
  Minitest::Reporters::SpecReporter.new,
  Minitest::Reporters::HtmlReporter.new,
]

# Test Database Configuration - Set up BEFORE loading app
DB_TEST = Sequel.connect('sqlite://test.db')

# Set the main database connection for tests
Object.const_set(:DB, DB_TEST) unless defined?(DB)

# Create test tables BEFORE loading models to prevent schema introspection errors
def create_all_test_tables
  # Create admin table
  DB.create_table?(:admins) do
    primary_key :id
    String :email, null: false, unique: true
    String :password_hash, null: false
    String :status, default: 'active'
    String :roles, default: 'admin'
    Integer :login_count, default: 0
    DateTime :last_login_at
    String :last_login_ip
    String :last_login_user_agent, text: true
    String :two_factor_secret
    TrueClass :two_factor_enabled, default: false
    DateTime :two_factor_enabled_at
    DateTime :two_factor_disabled_at
    String :password_reset_token
    DateTime :password_reset_sent_at
    TrueClass :must_change_password, default: false
    DateTime :password_changed_at
    DateTime :activated_at
    DateTime :deactivated_at
    DateTime :locked_at
    DateTime :unlocked_at
    DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
    DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
  end

  # Create products table
  DB.create_table?(:products) do
    primary_key :id
    String :name, null: false
    String :description, text: true
    Decimal :price, size: [10, 2], null: false
    String :currency, default: 'USD'
    String :license_type, default: 'one_time'
    Integer :max_activations, default: 1
    Integer :license_duration_days
    String :version
    String :download_file
    String :features, text: true
    TrueClass :active, default: true
    DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
    DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
  end

  # Create orders table
  DB.create_table?(:orders) do
    primary_key :id
    String :email, null: false
    Decimal :amount, size: [10, 2], null: false
    String :currency, default: 'USD'
    String :status, default: 'pending'
    String :payment_method
    String :payment_intent_id
    String :payment_details, text: true
    DateTime :completed_at
    DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
    DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
  end

  # Create order_items table
  DB.create_table?(:order_items) do
    primary_key :id
    foreign_key :order_id, :orders, on_delete: :cascade
    foreign_key :product_id, :products, on_delete: :cascade
    Integer :quantity, default: 1
    Decimal :price, size: [10, 2], null: false
    DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
  end

  # Create licenses table
  DB.create_table?(:licenses) do
    primary_key :id
    String :license_key, null: false, unique: true
    foreign_key :product_id, :products, on_delete: :cascade
    foreign_key :order_id, :orders, on_delete: :cascade, null: true
    String :customer_email, null: false
    String :status, default: 'active'
    Integer :max_activations, default: 1
    Integer :activation_count, default: 0
    Integer :download_count, default: 0
    DateTime :expires_at
    DateTime :last_activated_at
    DateTime :last_downloaded_at
    DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
    DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
  end

  # Create subscriptions table
  DB.create_table?(:subscriptions) do
    primary_key :id
    foreign_key :license_id, :licenses, on_delete: :cascade
    String :stripe_subscription_id
    String :paypal_subscription_id
    String :status, default: 'active'
    DateTime :current_period_start
    DateTime :current_period_end
    TrueClass :auto_renew, default: true
    DateTime :canceled_at
    DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
    DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
  end

  # Create license_activations table
  DB.create_table?(:license_activations) do
    primary_key :id
    foreign_key :license_id, :licenses, on_delete: :cascade
    String :machine_fingerprint, null: false
    String :machine_name
    String :os_info
    String :ip_address
    String :user_agent, text: true
    String :system_info, text: true
    TrueClass :active, default: true
    DateTime :activated_at, default: Sequel::CURRENT_TIMESTAMP
    DateTime :last_seen_at, default: Sequel::CURRENT_TIMESTAMP
    DateTime :deactivated_at
  end
end

# Create tables before loading models
create_all_test_tables

# Prevent Database.setup from being called in test environment
class Database
  def self.setup
    # Skip database setup in test environment - already configured above
  end
end

# Load the application AFTER database is configured and tables exist
require_relative '../app'

# Configure WebMock
WebMock.disable_net_connect!(allow_localhost: true)

# Configure VCR for HTTP recording
VCR.configure do |config|
  config.cassette_library_dir = 'test/vcr_cassettes'
  config.hook_into :webmock
  config.default_cassette_options = {
    record: :once,
    match_requests_on: %i[method uri body],
  }
  config.filter_sensitive_data('<STRIPE_SECRET_KEY>') { ENV.fetch('STRIPE_SECRET_KEY', nil) }
  config.filter_sensitive_data('<PAYPAL_CLIENT_ID>') { ENV.fetch('PAYPAL_CLIENT_ID', nil) }
  config.filter_sensitive_data('<PAYPAL_CLIENT_SECRET>') { ENV.fetch('PAYPAL_CLIENT_SECRET', nil) }
end

# Configure Database Cleaner
DatabaseCleaner[:sequel].strategy = :truncation

# Factory Bot configuration
FactoryBot.find_definitions

class Minitest::Test
  include Rack::Test::Methods
  include FactoryBot::Syntax::Methods

  def app
    SourceLicenseApp
  end

  def setup
    DatabaseCleaner[:sequel].start

    # Create test tables
    create_test_tables

    # Set test environment variables
    setup_test_env

    # Clear any session data
    clear_session
  end

  def teardown
    DatabaseCleaner[:sequel].clean
  end

  private

  def create_test_tables
    create_admin_table
    create_product_table
    create_order_tables
    create_license_tables
  end

  def create_admin_table
    DB.create_table?(:admins) do
      primary_key :id
      String :email, null: false, unique: true
      String :password_hash, null: false
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
    end
  end

  def create_product_table
    DB.create_table?(:products) do
      primary_key :id
      String :name, null: false
      String :description, text: true
      Decimal :price, size: [10, 2], null: false
      String :currency, default: 'USD'
      String :license_type, default: 'one_time'
      Integer :max_activations, default: 1
      Integer :license_duration_days
      String :version
      String :download_file
      String :features, text: true
      TrueClass :active, default: true
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
    end
  end

  def create_order_tables
    DB.create_table?(:orders) do
      primary_key :id
      String :email, null: false
      Decimal :amount, size: [10, 2], null: false
      String :currency, default: 'USD'
      String :status, default: 'pending'
      String :payment_method
      String :payment_intent_id
      DateTime :completed_at
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
    end

    DB.create_table?(:order_items) do
      primary_key :id
      foreign_key :order_id, :orders, on_delete: :cascade
      foreign_key :product_id, :products, on_delete: :cascade
      Integer :quantity, default: 1
      Decimal :price, size: [10, 2], null: false
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
    end
  end

  def create_license_tables
    create_licenses_table
    create_subscriptions_table
    create_license_activations_table
  end

  def create_licenses_table
    DB.create_table?(:licenses) do
      primary_key :id
      String :license_key, null: false, unique: true
      foreign_key :product_id, :products, on_delete: :cascade
      foreign_key :order_id, :orders, on_delete: :cascade, null: true
      String :customer_email, null: false
      String :status, default: 'active'
      Integer :max_activations, default: 1
      Integer :activation_count, default: 0
      Integer :download_count, default: 0
      DateTime :expires_at
      DateTime :last_activated_at
      DateTime :last_downloaded_at
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
    end
  end

  def create_subscriptions_table
    DB.create_table?(:subscriptions) do
      primary_key :id
      foreign_key :license_id, :licenses, on_delete: :cascade
      String :stripe_subscription_id
      String :paypal_subscription_id
      String :status, default: 'active'
      DateTime :next_billing_date
      DateTime :cancelled_at
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
    end
  end

  def create_license_activations_table
    DB.create_table?(:license_activations) do
      primary_key :id
      foreign_key :license_id, :licenses, on_delete: :cascade
      String :machine_fingerprint, null: false
      String :machine_name
      String :os_info
      DateTime :activated_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :last_seen_at, default: Sequel::CURRENT_TIMESTAMP
    end
  end

  def setup_test_env
    ENV['APP_SECRET'] =
      'test_secret_key_for_testing_only_this_is_a_very_long_secret_key_that_meets_minimum_requirements_64_chars'
    ENV['DATABASE_ADAPTER'] = 'sqlite'
    ENV['ADMIN_EMAIL'] = 'admin@test.com'
    ENV['ADMIN_PASSWORD'] = 'test_password'
    ENV['STRIPE_SECRET_KEY'] = 'sk_test_fake_key_for_testing'
    ENV['STRIPE_PUBLISHABLE_KEY'] = 'pk_test_fake_key_for_testing'
  end

  def clear_session
    # Skip clearing session to avoid triggering middleware in test environment
    # The session will be automatically cleared by DatabaseCleaner between tests
  end
end

# Custom assertions for license management
module LicenseAssertions
  def assert_valid_license_key(key)
    assert_match(/\A[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}\z/, key,
                 'License key should match the expected format')
  end

  def assert_license_active(license)
    assert_equal 'active', license.status, 'License should be active'
    assert_predicate license, :valid?, 'License should be valid'
  end

  def assert_successful_response
    assert_predicate last_response, :ok?, "Expected successful response, got #{last_response.status}"
  end

  def assert_json_response
    assert_equal 'application/json', last_response.content_type.split(';').first
    JSON.parse(last_response.body)
  end

  def assert_redirect_to(path)
    assert_predicate last_response, :redirect?, 'Expected redirect response'
    assert_equal path, URI.parse(last_response.location).path
  end

  def assert_admin_required
    assert_equal 401, last_response.status, 'Should require admin authentication'
  end
end

# Include custom assertions in test cases
Minitest::Test.include(LicenseAssertions)

# Test helpers
module TestHelpers
  def login_as_admin(email: 'admin@test.com', password: 'test_password')
    post '/admin/login', { email: email, password: password }
  end

  def create_test_admin(email: 'admin@test.com', password: 'test_password')
    Admin.create(
      email: email,
      password_hash: BCrypt::Password.create(password)
    )
  end

  def json_response
    JSON.parse(last_response.body)
  end

  def with_customizations(customizations = {})
    original_file = TemplateCustomizer::CUSTOMIZATIONS_FILE

    # Create temporary customizations
    FileUtils.mkdir_p(File.dirname(original_file))
    File.write(original_file, customizations.to_yaml)

    yield
  ensure
    # Clean up
    FileUtils.rm_f(original_file)
  end
end

Minitest::Test.include(TestHelpers)

puts 'Test environment setup complete!'
puts "Database: #{DB.opts[:database] || 'SQLite in-memory'}"
puts "Tables created: #{DB.tables.join(', ')}"
