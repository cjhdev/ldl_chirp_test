require 'chirpstack_api'

class AppServer < ChirpStackAPI::AS::ApplicationServerService::Service

  def initialize(**opts)
    @dev_eui = opts[:dev_eui]
    @join_eui = opts[:join_eui]
    @dev_key = opts[:dev_key]
    @join_key = opts[:join_key]
  end

  def handle_uplink_data(arg, _unused_call)
    puts __method__
    puts arg
    Google::Protobuf::Empty.new
  end

  def handle_proprietary_uplink(arg, _unused_call)
    puts __method__
    Google::Protobuf::Empty.new
  end

  def handle_error(arg, _unused_call)
    puts __method__
    puts arg
    Google::Protobuf::Empty.new
  end

  def handle_downlink_ack(arg, _unused_call)
    puts __method__
    Google::Protobuf::Empty.new
  end

  def handle_gateway_stats(arg, _unused_call)
    puts __method__
    Google::Protobuf::Empty.new
  end

  def handle_tx_ack(arg, _unused_call)
    puts __method__
    Google::Protobuf::Empty.new
  end

  def handle_device_status(arg, _unused_call)
    puts __method__
    Google::Protobuf::Empty.new
  end

  def set_device_location(arg, _unused_call)
    puts __method__
    Google::Protobuf::Empty.new
  end

end
