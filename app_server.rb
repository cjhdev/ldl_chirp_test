require 'chirpstack_api'

class AppServer < ChirpStackAPI::AS::ApplicationServerService::Service

  def initialize(&block)
    @block = block
  end

  def handle_uplink_data(arg, _unused_call)
    @block.call(__method__, arg)
    Google::Protobuf::Empty.new
  end

  def handle_downlink_ack
    @block.call(__method__, arg)
    Google::Protobuf::Empty.new
  end

  def handle_proprietary_uplink(arg, _unused_call)
    @block.call(__method__, arg)
    Google::Protobuf::Empty.new
  end

  def handle_error(arg, _unused_call)
    @block.call(__method__, arg)
    Google::Protobuf::Empty.new
  end

  def handle_downlink_ack(arg, _unused_call)
    @block.call(__method__, arg)
    Google::Protobuf::Empty.new
  end

  def handle_gateway_stats(arg, _unused_call)
    @block.call(__method__, arg)
    Google::Protobuf::Empty.new
  end

  def handle_tx_ack(arg, _unused_call)
    @block.call(__method__, arg)
    Google::Protobuf::Empty.new
  end

  def handle_device_status(arg, _unused_call)
    @block.call(__method__, arg)
    Google::Protobuf::Empty.new
  end

  def set_device_location(arg, _unused_call)
    @block.call(__method__, arg)
    Google::Protobuf::Empty.new
  end

end
