# Rails Refactoring Patterns Reference

## Service Object Pattern

### Basic Service (Initialize + Call)

```ruby
# app/services/order_creation_service.rb
class OrderCreationService
  def initialize(user:, params:)
    @user = user
    @params = params
  end

  def call
    order = @user.orders.build(@params)
    order.calculate_total
    order.save!
    OrderConfirmationJob.perform_later(order.id)
    order
  end
end

# Controller usage:
def create
  order = OrderCreationService.new(user: current_user, params: order_params).call
  render json: order, status: :created
rescue ActiveRecord::RecordInvalid => e
  render json: { errors: e.record.errors }, status: :unprocessable_entity
end
```

### Service with Result Object

```ruby
# app/services/payment_service.rb
class PaymentService
  Result = Data.define(:success?, :order, :error)

  def initialize(order:, payment_method:)
    @order = order
    @payment_method = payment_method
  end

  def call
    charge = gateway.charge(@order.total, @payment_method)
    @order.update!(payment_reference: charge.id, status: :paid)
    Result.new(success?: true, order: @order, error: nil)
  rescue Gateway::PaymentError => e
    Result.new(success?: false, order: @order, error: e.message)
  end

  private

  def gateway
    @gateway ||= StripeGateway.new
  end
end

# Controller usage:
def create
  result = PaymentService.new(order: @order, payment_method: params[:method]).call
  if result.success?
    render json: result.order, status: :created
  else
    render json: { error: result.error }, status: :unprocessable_entity
  end
end
```

### Service with Memoization

```ruby
# app/services/availability_service.rb
class AvailabilityService
  def initialize(date_range:, location:)
    @date_range = date_range
    @location = location
  end

  def available_slots
    @available_slots ||= all_slots - booked_slots
  end

  def utilization_rate
    @utilization_rate ||= booked_slots.size.to_f / all_slots.size
  end

  private

  def all_slots
    @all_slots ||= Slot.where(location: @location, date: @date_range)
  end

  def booked_slots
    @booked_slots ||= all_slots.where.not(booking_id: nil)
  end
end
```

### Service with SemanticLogger

```ruby
# app/services/import_service.rb
class ImportService
  include SemanticLogger::Loggable

  def initialize(file_path:)
    @file_path = file_path
  end

  def call
    logger.info("Starting import", file: @file_path)
    rows = parse_csv
    rows.each_with_index do |row, index|
      process_row(row)
    rescue StandardError => e
      logger.error("Failed to process row", row: index, error: e.message)
    end
    logger.info("Import complete", total: rows.size)
  end

  private

  def parse_csv
    CSV.read(@file_path, headers: true)
  end

  def process_row(row)
    # ...
  end
end
```

## Fat Controller → Service Extraction

### Before

```ruby
# app/controllers/api/orders_controller.rb
class Api::OrdersController < ApiController
  def create
    order = current_user.orders.build(order_params)
    order.reference = generate_reference
    order.tax_amount = order.subtotal * tax_rate

    if order.coupon_code.present?
      coupon = Coupon.find_by!(code: order.coupon_code)
      raise "Coupon expired" if coupon.expired?
      order.discount = coupon.calculate_discount(order.subtotal)
      coupon.increment!(:usage_count)
    end

    order.total = order.subtotal + order.tax_amount - (order.discount || 0)
    order.save!

    OrderMailer.confirmation(order).deliver_later
    InventoryUpdateJob.perform_later(order.id)

    render json: order, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Invalid coupon code" }, status: :unprocessable_entity
  end

  private

  def generate_reference
    "ORD-#{SecureRandom.hex(4).upcase}"
  end

  def tax_rate
    0.22
  end
end
```

### After

```ruby
# app/services/order_creation_service.rb
class OrderCreationService
  TAX_RATE = 0.22

  def initialize(user:, params:)
    @user = user
    @params = params
  end

  def call
    order = build_order
    apply_coupon(order) if order.coupon_code.present?
    calculate_total(order)
    order.save!
    enqueue_side_effects(order)
    order
  end

  private

  def build_order
    order = @user.orders.build(@params)
    order.reference = "ORD-#{SecureRandom.hex(4).upcase}"
    order.tax_amount = order.subtotal * TAX_RATE
    order
  end

  def apply_coupon(order)
    coupon = Coupon.find_by!(code: order.coupon_code)
    raise ActiveRecord::RecordInvalid.new(order) if coupon.expired?
    order.discount = coupon.calculate_discount(order.subtotal)
    coupon.increment!(:usage_count)
  end

  def calculate_total(order)
    order.total = order.subtotal + order.tax_amount - (order.discount || 0)
  end

  def enqueue_side_effects(order)
    OrderMailer.confirmation(order).deliver_later
    InventoryUpdateJob.perform_later(order.id)
  end
end

# app/controllers/api/orders_controller.rb (after)
class Api::OrdersController < ApiController
  def create
    order = OrderCreationService.new(user: current_user, params: order_params).call
    render json: order, status: :created
  end
end
```

## Concern Extraction

### Before (Fat Model)

```ruby
# app/models/route.rb (300+ lines)
class Route < ApplicationRecord
  include AASM

  # State machine (50 lines)
  aasm column: :status do
    state :draft, initial: true
    state :confirmed, :in_progress, :completed, :cancelled
    event :confirm { transitions from: :draft, to: :confirmed }
    event :start { transitions from: :confirmed, to: :in_progress }
    event :complete { transitions from: :in_progress, to: :completed }
    event :cancel { transitions from: [:draft, :confirmed], to: :cancelled }
  end

  # Geocoding (40 lines)
  geocoded_by :full_address
  after_validation :geocode, if: :address_changed?

  def full_address
    [address_street, address_city, address_zip, address_country].compact.join(", ")
  end

  def address_changed?
    address_street_changed? || address_city_changed? || address_zip_changed?
  end

  # ... 200 more lines of mixed concerns
end
```

### After

```ruby
# app/models/concerns/route_state_machine.rb
module RouteStateMachine
  extend ActiveSupport::Concern

  included do
    include AASM

    aasm column: :status do
      state :draft, initial: true
      state :confirmed, :in_progress, :completed, :cancelled

      event :confirm do
        transitions from: :draft, to: :confirmed
      end

      event :start do
        transitions from: :confirmed, to: :in_progress
      end

      event :complete do
        transitions from: :in_progress, to: :completed
      end

      event :cancel do
        transitions from: [:draft, :confirmed], to: :cancelled
      end
    end
  end
end

# app/models/concerns/route_geocoding.rb
module RouteGeocoding
  extend ActiveSupport::Concern

  included do
    geocoded_by :full_address
    after_validation :geocode, if: :address_changed?
  end

  def full_address
    [address_street, address_city, address_zip, address_country].compact.join(", ")
  end

  def address_changed?
    address_street_changed? || address_city_changed? || address_zip_changed?
  end
end

# app/models/route.rb (after — clean and focused)
class Route < ApplicationRecord
  include RouteStateMachine
  include RouteGeocoding

  belongs_to :driver
  has_many :journeys, dependent: :destroy

  validates :name, presence: true
  validates :scheduled_date, presence: true

  scope :upcoming, -> { where("scheduled_date >= ?", Date.current) }
end
```

## Query Object Pattern

### Before (Inline Query Chains)

```ruby
# Used in multiple controllers/services
orders = Order.where(status: :pending)
              .where("created_at > ?", 30.days.ago)
              .where(region: current_region)
              .includes(:user, :line_items)
              .order(created_at: :desc)
```

### After

```ruby
# app/queries/orders_query.rb
class OrdersQuery
  def initialize(relation = Order.all)
    @relation = relation
  end

  def pending
    @relation = @relation.where(status: :pending)
    self
  end

  def recent(days: 30)
    @relation = @relation.where("created_at > ?", days.days.ago)
    self
  end

  def in_region(region)
    @relation = @relation.where(region: region) if region.present?
    self
  end

  def with_associations
    @relation = @relation.includes(:user, :line_items)
    self
  end

  def newest_first
    @relation = @relation.order(created_at: :desc)
    self
  end

  def call
    @relation
  end

  # Shortcut for common combinations
  def self.pending_for_region(region)
    new.pending.recent.in_region(region).with_associations.newest_first.call
  end
end

# Usage
orders = OrdersQuery.pending_for_region(current_region)
# Or chainable:
orders = OrdersQuery.new.pending.recent(days: 7).newest_first.call
```

## DelegateClass Wrapper Pattern

### Before (Display Logic in Model)

```ruby
# app/models/journey.rb
class Journey < ApplicationRecord
  def display_duration
    return "N/A" unless completed_at && started_at
    minutes = ((completed_at - started_at) / 60).round
    "#{minutes / 60}h #{minutes % 60}m"
  end

  def display_status
    status.humanize.upcase
  end

  def full_route_label
    "#{origin_city} → #{destination_city}"
  end
end
```

### After

```ruby
# app/decorators/journey_presenter.rb
class JourneyPresenter < DelegateClass(Journey)
  def display_duration
    return "N/A" unless completed_at && started_at
    minutes = ((completed_at - started_at) / 60).round
    "#{minutes / 60}h #{minutes % 60}m"
  end

  def display_status
    status.humanize.upcase
  end

  def full_route_label
    "#{origin_city} → #{destination_city}"
  end
end

# Usage in controller/view
presenter = JourneyPresenter.new(journey)
presenter.display_duration  # => "2h 15m"
presenter.id                # delegates to journey.id
presenter.save!             # delegates to journey.save! (still works but avoid)
```

## Form Object Pattern

### Before (Multi-Model Form in Controller)

```ruby
# Complex registration handling company + user + address
def create
  company = Company.new(company_params)
  user = company.users.build(user_params)
  address = company.build_address(address_params)

  ActiveRecord::Base.transaction do
    company.save!
    user.save!
    address.save!
  end
rescue ActiveRecord::RecordInvalid
  # gather errors from all three models...
end
```

### After

```ruby
# app/forms/registration_form.rb
class RegistrationForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :company_name, :string
  attribute :email, :string
  attribute :password, :string
  attribute :street, :string
  attribute :city, :string
  attribute :zip, :string

  validates :company_name, :email, :password, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 8 }

  def save
    return false unless valid?

    ActiveRecord::Base.transaction do
      company = Company.create!(name: company_name)
      company.users.create!(email: email, password: password)
      company.create_address!(street: street, city: city, zip: zip)
    end

    true
  rescue ActiveRecord::RecordInvalid => e
    errors.add(:base, e.message)
    false
  end
end

# Controller
def create
  @form = RegistrationForm.new(registration_params)
  if @form.save
    render json: { status: :created }
  else
    render json: { errors: @form.errors }, status: :unprocessable_entity
  end
end
```

## Callback Chain → Service Extraction

### Before (Side Effects in Callbacks)

```ruby
class Order < ApplicationRecord
  after_create :send_confirmation_email
  after_create :update_inventory
  after_create :notify_warehouse
  after_create :log_analytics_event
  after_update :sync_to_erp, if: :status_changed?

  private

  def send_confirmation_email
    OrderMailer.confirmation(self).deliver_later
  end

  def update_inventory
    line_items.each { |item| item.product.decrement!(:stock, item.quantity) }
  end

  # ... more callbacks
end
```

### After

```ruby
# app/models/order.rb (clean)
class Order < ApplicationRecord
  belongs_to :user
  has_many :line_items

  validates :total, numericality: { greater_than: 0 }
end

# app/services/order_creation_service.rb
class OrderCreationService
  def initialize(user:, params:)
    @user = user
    @params = params
  end

  def call
    order = @user.orders.create!(@params)
    after_creation(order)
    order
  end

  private

  def after_creation(order)
    OrderMailer.confirmation(order).deliver_later
    InventoryUpdateJob.perform_later(order.id)
    WarehouseNotificationJob.perform_later(order.id)
    AnalyticsService.track("order.created", order_id: order.id)
  end
end
```

This moves side effects out of the model (which should only handle data integrity) and into explicit service calls that are easier to test, skip, and reason about.
