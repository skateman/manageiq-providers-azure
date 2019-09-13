class ManageIQ::Providers::Azure::CloudManager::EventCatcher::Stream
  #
  # Creates an event monitor
  #
  def initialize(ems)
    @ems = ems
    @collecting_events = false
    @since = nil
  end

  # Start capturing events
  def start
    @collecting_events = true
  end

  # Stop capturing events
  def stop
    @collecting_events = false
  end

  def each_batch
    while @collecting_events
      yield get_events.collect { |e| JSON.parse(e) }
    end
  end

  private

  def get_events
    # Grab only events for the last minute if this is the first poll
    filter = @since ? "eventTimestamp ge #{@since}" : "eventTimestamp ge #{startup_interval}"
    fields = 'authorization,description,eventDataId,eventName,eventTimestamp,resourceGroupName,resourceProviderName,resourceId,resourceType'
    events = connection.list(:filter => filter, :select => fields, :all => true).sort_by(&:event_timestamp)

    # HACK: the Azure Insights API does not support the 'gt' (greater than relational operator)
    # therefore we have to poll from 1 millisecond past the timestamp of the last event to avoid
    # gathering the same event more than once.
    @since = one_ms_from_last_timestamp(events) unless events.empty?
    events
  end

  # When the appliance first starts, or is restarted, start looking for events
  # from a fixed, recent point in the past.
  #
  def startup_interval
    format_timestamp(2.minutes.ago)
  end

  def one_ms_from_last_timestamp(events)
    time = Time.at(one_ms_from_last_timestamp_as_f(events)).utc
    format_timestamp(time)
  end

  def one_ms_from_last_timestamp_as_f(events)
    Time.zone.parse(events.last.event_timestamp).to_f + 0.001
  end

  # Given a Time object, return a string suitable for the Azure REST API query.
  #
  def format_timestamp(time)
    time.strftime('%Y-%m-%dT%H:%M:%S.%L')
  end

  # A cached connection to the event service, which is used to query for events.
  #
  def connection
    @connection ||= create_event_service
  end

  # Create an event service object using the provider connection credentials.
  # This will be used by the +connection+ method to query for events.
  #
  def create_event_service
    @ems.with_provider_connection do |conf|
      Azure::Armrest::Insights::EventService.new(conf)
    end
  end
end
