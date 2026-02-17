# Rails Performance Patterns Reference

## N+1 Query Detection Patterns

### Pattern 1: Collection Iteration with Association Access

```ruby
# N+1: Each order triggers a separate query for user
orders.each { |o| puts o.user.name }

# Fix: Preload the association
orders.includes(:user).each { |o| puts o.user.name }
```

### Pattern 2: Nested Association Chain

```ruby
# N+1: orders -> line_items -> product (3 levels)
orders.each do |order|
  order.line_items.each do |item|
    puts item.product.name
  end
end

# Fix: Nested includes
orders.includes(line_items: :product).each do |order|
  order.line_items.each { |item| puts item.product.name }
end
```

### Pattern 3: Conditional Association Access

```ruby
# Hidden N+1: only triggers for some records
orders.each do |order|
  puts order.coupon.code if order.coupon_id.present?
end

# Fix: Still needs includes even if conditional
orders.includes(:coupon).each do |order|
  puts order.coupon.code if order.coupon_id.present?
end
```

### Pattern 4: Counter Queries

```ruby
# N+1: .size/.count on has_many triggers COUNT query per record
users.each { |u| puts u.orders.size }

# Fix option 1: Counter cache
belongs_to :user, counter_cache: true

# Fix option 2: Preload with size
users.includes(:orders).each { |u| puts u.orders.size }

# Fix option 3: Manual count (most efficient for display only)
counts = Order.where(user_id: users.ids).group(:user_id).count
users.each { |u| puts counts[u.id] || 0 }
```

### Pattern 5: Scope Inside Loop

```ruby
# N+1: scope re-queries each iteration
users.each { |u| puts u.orders.recent.count }

# Fix: Cannot use includes for scoped queries
# Use a single grouped query instead
recent_counts = Order.where(user_id: users.ids)
                     .where('created_at > ?', 1.week.ago)
                     .group(:user_id).count
```

### Pattern 6: Serializer/View N+1

```ruby
# In a serializer or jbuilder template
class OrderSerializer
  def customer_name
    object.user.name  # N+1 if orders not loaded with includes(:user)
  end
end

# Fix: Ensure the controller preloads
@orders = Order.includes(:user).where(...)
```

## Eager Loading Strategy Guide

| Strategy | SQL | Best For | Caveat |
|----------|-----|----------|--------|
| `includes` | Rails decides | General use | May switch to JOIN unexpectedly |
| `preload` | Separate queries | has_many associations | Cannot filter by association in WHERE |
| `eager_load` | LEFT OUTER JOIN | Filtering by association columns | Single large query, duplicates parent rows |

### When to Use Each

```ruby
# preload: Best for has_many (separate IN query, no row duplication)
Order.preload(:line_items).where(status: :pending)

# eager_load: When you need to filter/sort BY the association
Order.eager_load(:user).where(users: { role: :admin })

# includes: General case (Rails picks preload unless it detects a need for JOIN)
Order.includes(:user, :line_items)

# Strict loading: Catch N+1 in development
Order.strict_loading.find(id)
# Or globally in model:
self.strict_loading_by_default = true
```

## Memory Optimization Patterns

### Batch Processing

```ruby
# BAD: Loads all records into memory
User.all.each { |u| process(u) }

# GOOD: Loads in batches of 1000
User.find_each(batch_size: 1000) { |u| process(u) }

# GOOD: Batched updates without instantiation
User.in_batches(of: 1000).update_all(processed: true)
```

### Pluck vs Select

```ruby
# Instantiates AR objects (heavy)
User.select(:id, :email).map { |u| [u.id, u.email] }

# Returns raw arrays (light)
User.pluck(:id, :email)
# => [[1, "a@b.com"], [2, "c@d.com"]]
```

### Streaming Large Responses

```ruby
# For CSV exports — stream instead of building in memory
def index
  headers["Content-Disposition"] = "attachment; filename=export.csv"
  headers["Content-Type"] = "text/csv"

  response.status = 200
  self.response_body = Enumerator.new do |yielder|
    yielder << CSV.generate_line(%w[id name email])
    User.find_each do |user|
      yielder << CSV.generate_line([user.id, user.name, user.email])
    end
  end
end
```

### Avoid Loading Unnecessary Data

```ruby
# BAD: Loads all columns
order_ids = Order.where(status: :pending).map(&:id)

# GOOD: Only loads ids
order_ids = Order.where(status: :pending).ids

# BAD: Loads records to check existence
if Order.where(user: user).count > 0

# GOOD: Uses EXISTS subquery
if Order.where(user: user).exists?
```

## Index Analysis Guide

### Common Missing Index Scenarios

```ruby
# Foreign keys — ALWAYS need indexes
add_reference :orders, :user, index: true  # Rails adds index automatically
# But manual foreign key columns may lack indexes:
add_column :orders, :coupon_id, :integer
add_index :orders, :coupon_id  # Don't forget this!

# Polymorphic associations — need composite index
add_index :comments, [:commentable_type, :commentable_id]

# Status/state columns queried frequently
add_index :orders, :status

# Unique constraints — add both index and model validation
add_index :users, :email, unique: true
# Model: validates :email, uniqueness: true
```

### Composite Index Rules

```ruby
# Composite index covers queries on LEADING columns
add_index :orders, [:user_id, :status, :created_at]

# This index covers:
# ✅ WHERE user_id = ?
# ✅ WHERE user_id = ? AND status = ?
# ✅ WHERE user_id = ? AND status = ? AND created_at > ?
# ❌ WHERE status = ?  (not a leading column)
# ❌ WHERE created_at > ?  (not a leading column)

# So DON'T add a redundant single-column index:
# ❌ add_index :orders, :user_id  (already covered by composite)
```

### Checking Query Plans

```ruby
# In rails console
Order.where(user_id: 1, status: :pending).explain
# Look for "Seq Scan" (PostgreSQL) or "Full Table Scan" (MySQL) = missing index
# "Index Scan" or "Index Cond" = index being used
```

## Bullet Configuration

```ruby
# config/environments/development.rb
config.after_initialize do
  Bullet.enable = true
  Bullet.alert = false           # Don't show JS alerts
  Bullet.bullet_logger = true    # Log to log/bullet.log
  Bullet.console = true          # Browser console warnings
  Bullet.rails_logger = true     # Rails log warnings
  Bullet.add_footer = true       # Show in page footer

  # Whitelist known acceptable N+1s
  Bullet.add_safelist type: :n_plus_one_query,
                       class_name: "User",
                       association: :profile
end
```

## rack-mini-profiler Usage

```ruby
# Gemfile (development only)
gem 'rack-mini-profiler', require: false
gem 'stackprof'         # For flamegraphs
gem 'memory_profiler'   # For memory analysis

# Query parameters for profiling:
# ?pp=flamegraph          — CPU flamegraph
# ?pp=profile-gc          — GC profiling
# ?pp=analyze-memory      — Memory allocation analysis
# ?pp=help                — List all options

# Disable for API-only apps:
# config/initializers/mini_profiler.rb
Rack::MiniProfiler.config.pre_authorize_cb = lambda { |env|
  !Rails.env.test? && env['PATH_INFO'] !~ /\A\/api/
}
```

## Quick Benchmarking

```ruby
# Compare implementations
require 'benchmark/ips'

Benchmark.ips do |x|
  x.report("includes") { Order.includes(:user).limit(100).to_a }
  x.report("preload")  { Order.preload(:user).limit(100).to_a }
  x.report("eager")    { Order.eager_load(:user).limit(100).to_a }
  x.compare!
end

# Memory profiling a block
require 'memory_profiler'
report = MemoryProfiler.report { Order.includes(:items).limit(100).to_a }
report.pretty_print(to_file: 'memory_report.txt')
```

## GraphQL-Specific Performance

### DataLoader / BatchLoader Pattern

```ruby
# app/graphql/loaders/association_loader.rb
class Loaders::AssociationLoader < GraphQL::Batch::Loader
  def initialize(model, association_name)
    super()
    @model = model
    @association_name = association_name
  end

  def perform(records)
    preloader = ActiveRecord::Associations::Preloader.new(
      records: records,
      associations: @association_name
    )
    preloader.call
    records.each { |record| fulfill(record, record.public_send(@association_name)) }
  end
end

# Usage in type:
def orders
  Loaders::AssociationLoader.for(User, :orders).load(object)
end
```

### Avoiding N+1 in Resolvers

```ruby
# BAD: Each resolver triggers separate query
def author
  object.author  # N+1 when resolving list of posts
end

# GOOD: Use dataloader
def author
  dataloader.with(Sources::ActiveRecordObject, User).load(object.author_id)
end
```
