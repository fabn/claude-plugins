# Rails Testing Patterns Reference

## Model Spec Pattern

```ruby
# spec/models/order_spec.rb
RSpec.describe Order do
  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to have_many(:line_items).dependent(:destroy) }
    it { is_expected.to have_one(:invoice) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_numericality_of(:total).is_greater_than(0) }
    it { is_expected.to validate_uniqueness_of(:reference_number) }
  end

  describe "scopes" do
    describe ".recent" do
      it "returns orders from the last 30 days" do
        old_order = create(:order, created_at: 2.months.ago)
        recent_order = create(:order, created_at: 1.week.ago)

        expect(described_class.recent).to include(recent_order)
        expect(described_class.recent).not_to include(old_order)
      end
    end
  end

  describe "#total_with_tax" do
    it "calculates total including tax" do
      order = build(:order, total: 100.0, tax_rate: 0.22)
      expect(order.total_with_tax).to eq(122.0)
    end
  end

  describe "state machine" do
    describe "#confirm!" do
      context "when pending" do
        it "transitions to confirmed" do
          order = create(:order, :pending)
          order.confirm!
          expect(order).to be_confirmed
        end
      end

      context "when already shipped" do
        it "raises an error" do
          order = create(:order, :shipped)
          expect { order.confirm! }.to raise_error(AASM::InvalidTransition)
        end
      end
    end
  end

  describe "callbacks" do
    it "generates reference number before creation" do
      order = create(:order)
      expect(order.reference_number).to be_present
    end
  end
end
```

## Service Spec Pattern

```ruby
# spec/services/payment_service_spec.rb
RSpec.describe PaymentService do
  subject(:service) { described_class.new(order: order, payment_method: method) }

  let(:order) { create(:order, total: 100.0) }
  let(:method) { create(:payment_method, :credit_card) }

  describe "#call" do
    context "when payment succeeds" do
      before do
        allow(StripeGateway).to receive(:charge).and_return(
          OpenStruct.new(success?: true, transaction_id: "txn_123")
        )
      end

      it "marks the order as paid" do
        service.call
        expect(order.reload).to be_paid
      end

      it "records the transaction" do
        result = service.call
        expect(result.transaction_id).to eq("txn_123")
      end

      it "enqueues a confirmation email" do
        expect { service.call }.to have_enqueued_job(OrderConfirmationJob)
      end
    end

    context "when payment fails" do
      before do
        allow(StripeGateway).to receive(:charge).and_raise(
          Stripe::CardError.new("declined", nil, code: "card_declined")
        )
      end

      it "does not change order status" do
        expect { service.call rescue nil }.not_to change { order.reload.status }
      end

      it "raises a payment error" do
        expect { service.call }.to raise_error(PaymentService::PaymentError)
      end
    end
  end
end
```

## Request Spec Pattern

```ruby
# spec/requests/api/orders_spec.rb
RSpec.describe "Orders API" do
  let(:user) { create(:user) }
  let(:headers) { auth_headers(user) }

  describe "GET /api/orders" do
    it "returns a list of user orders" do
      create_list(:order, 3, user: user)

      get "/api/orders", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response.size).to eq(3)
    end

    context "when not authenticated" do
      it "returns unauthorized" do
        get "/api/orders"
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "POST /api/orders" do
    let(:valid_params) { { order: { product_id: create(:product).id, quantity: 2 } } }

    it "creates an order" do
      expect {
        post "/api/orders", params: valid_params, headers: headers
      }.to change(Order, :count).by(1)

      expect(response).to have_http_status(:created)
    end

    context "with invalid params" do
      it "returns validation errors" do
        post "/api/orders", params: { order: { quantity: -1 } }, headers: headers

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json_response["errors"]).to be_present
      end
    end
  end
end
```

## Job Spec Pattern

```ruby
# spec/jobs/order_confirmation_job_spec.rb
RSpec.describe OrderConfirmationJob do
  describe "#perform" do
    let(:order) { create(:order, :confirmed) }

    it "sends a confirmation email" do
      expect {
        described_class.new.perform(order.id)
      }.to change { ActionMailer::Base.deliveries.count }.by(1)
    end

    context "when order not found" do
      it "does not raise" do
        expect { described_class.new.perform(0) }.not_to raise_error
      end
    end

    context "when already notified" do
      before { order.update!(notified_at: Time.current) }

      it "skips sending" do
        expect {
          described_class.new.perform(order.id)
        }.not_to change { ActionMailer::Base.deliveries.count }
      end
    end
  end
end
```

## Policy Spec Pattern

```ruby
# spec/policies/order_policy_spec.rb
RSpec.describe OrderPolicy do
  subject { described_class.new(user, order) }

  let(:order) { create(:order, user: owner) }
  let(:owner) { create(:user) }

  context "when user is the owner" do
    let(:user) { owner }

    it { is_expected.to permit_action(:show) }
    it { is_expected.to permit_action(:update) }
    it { is_expected.to forbid_action(:destroy) }
  end

  context "when user is an admin" do
    let(:user) { create(:user, :admin) }

    it { is_expected.to permit_actions([:show, :update, :destroy]) }
  end

  context "when user is a different user" do
    let(:user) { create(:user) }

    it { is_expected.to forbid_actions([:show, :update, :destroy]) }
  end
end
```

## FactoryBot Patterns

### Basic Factory

```ruby
# spec/factories/orders.rb
FactoryBot.define do
  factory :order do
    association :user
    sequence(:reference_number) { |n| "ORD-#{n.to_s.rjust(6, '0')}" }
    status { :pending }
    total { 99.99 }
    currency { "EUR" }

    trait :confirmed do
      status { :confirmed }
      confirmed_at { Time.current }
    end

    trait :shipped do
      confirmed
      status { :shipped }
      shipped_at { Time.current }
    end

    trait :with_items do
      transient do
        items_count { 3 }
      end

      after(:create) do |order, evaluator|
        create_list(:line_item, evaluator.items_count, order: order)
      end
    end
  end
end
```

### Factory Best Practices

```ruby
# Use build when you don't need persistence
user = build(:user)           # No DB hit
user = build_stubbed(:user)   # No DB hit, has fake ID

# Use create when you need persistence
user = create(:user)          # Saved to DB

# Use traits for variations
create(:order, :confirmed)
create(:order, :shipped, :with_items)

# Use transient attributes for customization
create(:order, :with_items, items_count: 5)

# Sequences for unique values
sequence(:email) { |n| "user#{n}@example.com" }

# Avoid build/create chains that are too deep
# BAD: creates user -> company -> plan -> features chain
create(:user, :with_company)

# GOOD: create only what's needed
user = create(:user)
# associate company only when the test needs it
```

## VCR Configuration

```ruby
# spec/support/vcr.rb
VCR.configure do |config|
  config.cassette_library_dir = "spec/cassettes"
  config.hook_into :webmock
  config.configure_rspec_metadata!
  config.default_cassette_options = {
    record: :once,
    match_requests_on: [:method, :uri, :body]
  }

  # Filter sensitive data
  config.filter_sensitive_data("<STRIPE_KEY>") { ENV["STRIPE_SECRET_KEY"] }
  config.filter_sensitive_data("<API_TOKEN>") { ENV["API_TOKEN"] }

  # Ignore local services
  config.ignore_localhost = true
end
```

### VCR Usage

```ruby
# Automatic cassette from metadata
it "fetches user data", :vcr do
  result = ExternalApi.fetch_user(123)
  expect(result.name).to eq("John")
end

# Explicit cassette
it "fetches user data" do
  VCR.use_cassette("external_api/fetch_user") do
    result = ExternalApi.fetch_user(123)
    expect(result.name).to eq("John")
  end
end

# Re-record cassette
# VCR_RECORD=all bundle exec rspec spec/services/external_api_spec.rb
```

## Webmock Stubs (Without VCR)

```ruby
# Stub a GET request
stub_request(:get, "https://api.example.com/users/1")
  .to_return(
    status: 200,
    body: { id: 1, name: "John" }.to_json,
    headers: { "Content-Type" => "application/json" }
  )

# Stub with regex
stub_request(:post, /api\.stripe\.com/)
  .to_return(status: 200, body: { status: "ok" }.to_json)

# Stub to raise timeout
stub_request(:get, "https://api.example.com/slow")
  .to_timeout

# Verify request was made
expect(WebMock).to have_requested(:post, "https://api.example.com/orders")
  .with(body: hash_including(amount: 100))
  .once
```

## Time-Dependent Tests

```ruby
# Freeze time for consistent assertions
it "sets expiry to 30 days from now" do
  travel_to Time.zone.parse("2024-06-15 10:00:00") do
    token = create(:token)
    expect(token.expires_at).to eq(Time.zone.parse("2024-07-15 10:00:00"))
  end
end

# Alternative: freeze_time
it "records current timestamp" do
  freeze_time do
    order = create(:order)
    expect(order.placed_at).to eq(Time.current)
  end
end
```

## Shared Examples

```ruby
# spec/support/shared_examples/authorizable.rb
RSpec.shared_examples "authorizable" do
  context "when not authenticated" do
    it "returns 401" do
      make_request(headers: {})
      expect(response).to have_http_status(:unauthorized)
    end
  end
end

# Usage
describe "GET /api/orders" do
  it_behaves_like "authorizable" do
    let(:make_request) { get "/api/orders", headers: headers }
  end
end
```

## Test Helpers

```ruby
# spec/support/json_helpers.rb
module JsonHelpers
  def json_response
    JSON.parse(response.body)
  end
end

RSpec.configure do |config|
  config.include JsonHelpers, type: :request
end

# spec/support/auth_helpers.rb
module AuthHelpers
  def auth_headers(user)
    # Devise token auth
    user.create_new_auth_token
    # Or simple token
    { "Authorization" => "Bearer #{user.auth_token}" }
  end
end

RSpec.configure do |config|
  config.include AuthHelpers, type: :request
end
```
