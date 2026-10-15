# MySQL may interpolate literals into SQL before the standard log subscriber
# sees them. Parameter filtering alone does not protect recovery codes there.
module PrivateRecoverySqlLogging
  def sql(event)
    unless event.payload[:sql].to_s.match?(/\bpassword_recoveries\b/i)
      return super
    end

    payload = event.payload.merge(
      sql: '[FILTERED password recovery query]', binds: [], type_casted_binds: []
    )
    safe_event = ActiveSupport::Notifications::Event.new(
      event.name, event.time, event.end, event.transaction_id, payload
    )
    # Preserve duration/name/runtime accounting without changing the SQL sent
    # to MySQL or the event other non-logging subscribers receive.
    super(safe_event)
  end
end

ActiveRecord::LogSubscriber.prepend(PrivateRecoverySqlLogging)
