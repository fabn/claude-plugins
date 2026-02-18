# Rails Version-Specific Breaking Changes

Quick reference for common breaking changes when upgrading between Rails minor
versions. This is not exhaustive — always check the official Rails upgrade guide
for the full list.

## 7.0 → 7.1

### Key Changes

- **`ActiveRecord::Base.generate_unique_secure_token`** now generates 36-character
  tokens by default (was 24). Existing tokens are unaffected but new ones will be
  longer. Check column length constraints.

- **`Rails.application.config.active_record.default_column_serializer`** defaults
  to `nil` (was `YAML`). All `serialize` calls now require an explicit coder:
  ```ruby
  # Before (implicit YAML)
  serialize :preferences

  # After (explicit)
  serialize :preferences, coder: YAML
  ```

- **`config.active_record.run_commit_callbacks_on_first_saved_instances_in_transaction`**
  changed to `false`. If you rely on commit callbacks running on the first saved
  instance in a transaction (rather than the last), this affects behavior.

- **`config.active_support.cache_format_version`** bumped to `7.1`. Caches written
  with 7.1 format cannot be read by Rails 7.0. If you need zero-downtime deploys,
  defer this default until all instances run 7.1.

- **`ActiveSupport::MessageEncryptor`** and `MessageVerifier` use a new
  serialization format. Set `config.active_support.message_serializer = :json_allow_marshal`
  for a transition period, then switch to `:json` once all old messages expire.

- **`config.action_dispatch.default_headers`** no longer includes
  `X-Download-Options` or `X-Permitted-Cross-Domain-Policies`. If you relied
  on these headers, add them back manually.

- **`Enumerable#sum`** is now loaded eagerly and shadows Ruby's native
  `Enumerable#sum` (which doesn't handle `nil` the same way).

### New Gems / Dependencies

- `drb` must be added to Gemfile if you use DRb (no longer a default gem in Ruby 3.4+)
- `mutex_m`, `bigdecimal`, `base64` may need explicit requires depending on Ruby version

---

## 7.1 → 7.2

### Key Changes

- **`config.active_job.enqueue_after_transaction_commit`** defaults to `:default`.
  Jobs enqueued within transactions are now deferred until after commit. If your
  code relies on jobs being enqueued immediately (e.g., for a transaction-based
  test pattern), set this to `:never`.

- **`config.active_record.automatically_invert_plural_associations`** enabled by
  default. `has_many` associations now automatically detect their inverse when the
  inverse is singular. This can change behavior if you have unusual association names.

- **`config.active_record.validate_migration_timestamps`** enabled by default.
  Migration timestamps are now validated. If you have migrations with non-standard
  timestamps, they will raise an error.

- **`config.active_support.to_time_preserves_timezone`** now defaults to `:zone`.
  `to_time` preserves the timezone instead of converting to the system local timezone.

- **Browser version guard** (`allow_browser`) available in controllers. Not a
  breaking change but a new feature you may want to adopt.

- **`config.yjit`** option added. Rails 7.2 recommends YJIT in production.

- **Deprecation of `to_s(:format)`** — use `to_formatted_s(:format)` or `to_fs(:format)`.

### Removed

- `Rails::Generators::Testing::Behaviour` (use `Behavior` spelling)
- `config.active_record.suppress_multiple_database_warning` removed

---

## 7.2 → 8.0

### Key Changes

- **Requires Ruby 3.2+**. If you're on Ruby 3.1 or below, upgrade Ruby first.

- **`config.active_record.default_column_serializer`** — if you deferred this
  from the 7.1 upgrade, you must resolve it now. Setting it to `nil` is enforced.

- **`config.active_support.message_serializer`** defaults to `:json`. If you
  still have Marshal-serialized messages in caches/cookies, they will fail to
  deserialize. Complete the migration to JSON before upgrading.

- **`config.action_dispatch.cookies_serializer`** defaults to `:json`. Same
  concern as above — users with old Marshal cookies will be logged out.
  Transition period: set to `:hybrid` first, deploy, wait for old cookies to
  expire, then switch to `:json`.

- **`config.log_level`** in production defaults to `:info` (was `:debug` for
  some configurations). Explicitly set it if you need debug logging.

- **`config.active_record.belongs_to_required_by_default`** — already true
  since Rails 5.0 defaults, but 8.0 removes the ability to set it to `false`.
  If you had this as `false`, fix missing associations before upgrading.

- **`ActiveRecord::Base.connection`** deprecated in favor of
  `ActiveRecord::Base.lease_connection` or `with_connection`. The `connection`
  method now shows a deprecation warning.

- **`#to_s` on Active Record** no longer returns `#<ClassName:0x...>`. It
  returns the result of `inspect` by default. Override `to_s` explicitly if
  your code depends on the old format.

### Removed

- `config.active_record.partial_inserts` (was deprecated in 7.0)
- `config.active_record.warn_on_records_fetched_greater_than`
- `Rails.application.config.action_controller.urlsafe_csrf_tokens` (now always true)
- `ActiveRecord::ConnectionAdapters::ConnectionPool#connection` without a block

### New Gems / Dependencies

- `propshaft` is the new default asset pipeline (sprockets still works but is
  not the default for new apps). Existing apps keep their asset pipeline.
- `solid_queue`, `solid_cache`, `solid_cable` are defaults for new apps but
  do not affect upgrades of existing apps.

---

## 8.0 → 8.1

### Key Changes

- **`config.active_record.migration_error`** in development now defaults to
  `:page_load` instead of showing a migration pending page. Pending migrations
  raise immediately on any request.

- **`config.active_job.default_queue_name`** — verify your queue adapter
  handles the default queue name. Some adapters changed behavior.

- **`config.action_mailer.default_url_options`** — 8.1 raises if mailers are
  used without setting this. Add it to all environments if missing.

- **`ActiveRecord::Encryption`** improvements may change encrypted column
  behavior. If you use AR encryption, test thoroughly. New options for
  deterministic encryption are available.

- **`config.active_support.cache_format_version`** may change — check the
  generated `new_framework_defaults` file for the exact value in your target
  version. Same zero-downtime concern as the 7.1 change: caches written with
  the new format cannot be read by older Rails versions.

### Deprecations to Fix Before Upgrading

- `ActiveRecord::Base.connection` → `with_connection` or `lease_connection`
- `config.active_record.legacy_connection_handling` — remove if still present
- Any remaining `to_s(:format)` calls → `to_fs(:format)`

---

## General Upgrade Tips

1. **Always upgrade one minor version at a time.** Rails tests each upgrade
   path individually. Skipping versions may hit unexpected interactions.

2. **Check dependency compatibility before starting.** Use
   [RailsBump](https://www.railsbump.org/) to check gem compatibility with
   your target Rails version.

3. **Read the full release notes.** This reference covers common gotchas but
   the [official upgrade guide](https://guides.rubyonrails.org/upgrading_ruby_on_rails.html)
   is the authoritative source.

4. **Watch for Ruby version requirements.** Rails 7.2 recommends Ruby 3.2+.
   Rails 8.0 requires Ruby 3.2+.

5. **Zero-downtime cache/cookie transitions.** When cache or cookie serializer
   formats change, deploy with the hybrid/transitional serializer first, wait
   for old data to expire, then switch to the new format.

6. **Framework defaults are optional.** You can upgrade Rails without enabling
   new defaults. Enable them incrementally after the upgrade is stable.
